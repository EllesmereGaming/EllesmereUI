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
--  Protected calls in this file, all of them deferred to PLAYER_REGEN_ENABLED
--  when in combat: the override-binding updates, and PushPalette's writes of a
--  palette's contents onto the secure buttons.
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
local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local sin, cos, tan, atan2, sqrt, pi =
    math.sin, math.cos, math.tan, math.atan2, math.sqrt, math.pi
local log = math.log
local tonumber, type, select = tonumber, type, select
local tinsert, tremove, tsort = table.insert, table.remove, table.sort
local GetCursorInfo, ClearCursor = GetCursorInfo, ClearCursor
local GetCursorPosition = GetCursorPosition
local GetBindingKey = GetBindingKey
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
-- Read every frame an open palette holds an entry whose icon can move under it
-- -- see AdvanceLiveIcons.
local IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown =
    IsShiftKeyDown, IsControlKeyDown, IsAltKeyDown

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
-- still aim at rather than to how many fit. Sixteen, which is where a full
-- circle gives each entry 22.5 degrees.
local MAX_SLOTS = 16

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
-- see PerimeterNest, the "Arming gates" section and RunReach below.
--
-- Fourteen is what a lane sharing the block with OTHER claims comes to. Each of
-- those has its own cell taken out of this claim's coverage (see ParentHoles),
-- which splits the side it falls on into at most a slab clear of it and one
-- interval reaching back to the parent -- the pieces past it are dropped, being
-- ground this claim cannot be armed on anyway.
--
-- Derived by running .tools/quickdraw-nest over every block layout at
-- MAX_SLOTS: 330,692 arrangements -- 2 to 16 entries, every arrangement of up
-- to four nesting ones (thinned evenly past 120 per shape), 1 to 16 children
-- each, auto and pinned columns, both nest styles. Fourteen covers all but 239
-- of them; the worst single claim in the sweep comes to eighteen, and spending
-- four more gates and eight more wrapped scripts on every claim to catch that
-- last 0.07 per cent is not the trade. Past the budget the tail is dropped,
-- child-bearing pieces being written first, so a claim that does overflow loses
-- ground between its entries rather than a child.
--
-- Re-run that sweep if MAX_SLOTS, MAX_CHILDREN or any nest geometry moves --
-- this number is an OUTPUT of the shapes below it, not a choice.
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
-- below is what the Keybindings page reads.
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
--  the caption). The options page's "Apply All Settings To" dropdown is the
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

-- The overrides table for a palette, created on demand. Only the options page
-- writes here; everything else reads through the view below.
function ns.PaletteAppearance(palette, create)
    if not palette then return nil end
    if not palette.appearance and create then palette.appearance = {} end
    return palette.appearance
end

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

-- Assigned with the usability filter further down (it needs SpecIndexFor);
-- ChildSlots reads through it so a nested menu contributes only what this
-- character can use, under the nested palette's OWN setting.
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

-------------------------------------------------------------------------------
--  Slot model
--
--  A slot is { kind = <string>, ... }. Everything the secure button needs is
--  derived from the slot at click time by ResolveAction; everything the UI
--  needs is derived by SlotDisplay. Both are pure lookups over the stored
--  ids, so a slot never caches a stale icon or name across a patch.
-------------------------------------------------------------------------------

-- Both marker kinds store the ICON position: 1..8 in the star-to-skull order
-- every marker UI shows, 0 for the entry that clears instead of placing. The
-- engine numbers its WORLD markers differently, so the world kind maps the
-- stored position onto the engine's number before it names one.
--
-- The engine runs blue, green, purple, red, yellow, orange, silver, white --
-- square, triangle, diamond, cross, star, circle, moon, skull. Blizzard's
-- WORLD_RAID_MARKER_ORDER (Blizzard_CompactRaidFrameManager.lua:5-12) is the
-- same eight numbers listed SKULL to STAR, which is the order its dropdown
-- draws them in; read as though it ran star to skull it lands on the marker
-- mirrored about the middle.
local WORLD_MARKER_ENGINE = { 5, 6, 3, 2, 7, 1, 4, 8 }

local MARKER_NAMES = {
    "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull",
}

-------------------------------------------------------------------------------
--  Cycling marker entries
--
--  One entry that walks the eight markers instead of naming one: each press
--  places the next, star to skull and back to the star. It is the whole set in
--  a single slot, for a palette that has no room for nine.
--
--  The position last placed is kept on the slot, so the run continues across a
--  reload rather than restarting at the star. It is NOT what the press reads,
--  though: an insecure SetAttribute is refused in combat, which is exactly when
--  marking matters, so the secure snippet keeps the authoritative copy and
--  advances it itself. CyclePosBack hands the snippet's answer back here after
--  the press, and the push seeds the snippet from it again. Both ends derive
--  "next" from "last" the same way, so the icon can never advertise a marker
--  other than the one the press places.
-------------------------------------------------------------------------------
local CYCLE_N = 8

-- The macro text each step fires, in the order the entry runs through them.
-- Both cycles step through the eight ICON positions; the world one maps each
-- onto the engine's number exactly as a fixed world marker slot does. nil for
-- every kind that does not cycle, which is what marks a slot as one.
local function CycleSteps(kind)
    local out = {}
    if kind == "cycleraidtarget" then
        for i = 1, CYCLE_N do out[i] = "/tm " .. i end
    elseif kind == "cycleworldmarker" then
        for i = 1, CYCLE_N do out[i] = "/wm " .. WORLD_MARKER_ENGINE[i] end
    else
        return nil
    end
    return out
end

-- The icon position the NEXT press places. Derived from the stored one rather
-- than stored itself, so there is only ever one number to keep in step.
local function CycleNext(slot)
    local last = tonumber(slot and slot.cyclePos) or 0
    if last < 1 or last > CYCLE_N then last = 0 end
    return last % CYCLE_N + 1
end

-- The position the snippet advanced to, back onto the slot it belongs to, so
-- the next push and every icon drawn before it agree with what actually fired.
-- Called from the release; a cell that does not cycle answers nothing and
-- leaves the slot alone.
local function CyclePosBack(btn, idx, slot)
    if not btn or not idx or not slot then return end
    local pos = tonumber(btn:GetAttribute("eqdCycPos" .. idx))
    if pos and CycleSteps(slot.kind) then slot.cyclePos = pos end
end

-- "Summon Random Favorite Mount", used only to DRAW the entry -- its icon and
-- its localized name. Firing does not cast it: the spell is neither in the
-- spellbook nor a journal mount, so CastSpellByName resolves it to nothing
-- and the release fires nothing. The roll is made by
-- C_MountJournal.SummonByID(0), which is ordinary API -- the Mount Journal's
-- own button calls it straight from an insecure click handler
-- (Blizzard_MountCollection.lua:998) -- so the kind fires through
-- FireInsecure the way a battle pet does.
local RANDOM_FAVORITE_MOUNT = 150544

local function MarkerIcon(id)
    return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. id
end

-- The CURRENT index of the specialization a slot names, for both kinds that
-- name one. Either way, nil leaves the slot doing nothing.
--
-- A spec slot banks the specID, the same number on every character that has
-- that spec: the index is only a position in one character's list, so a
-- palette carried to an alt would otherwise point at somebody else's spec. A
-- dynamicspec slot banks the position instead, and means it -- the second on a
-- druid and the second on a warrior are both simply "the second one".
local function SpecIndexFor(slot)
    if not slot or not C_SpecializationInfo then return nil end
    local classID = select(3, UnitClass("player"))
    if not classID then return nil end
    local count = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0

    if slot.kind == "dynamicspec" then
        local i = tonumber(slot.index)
        if i and i >= 1 and i <= count then return i end
        return nil
    end

    local want = tonumber(slot.specID)
    if not want then return nil end
    for i = 1, count do
        if C_SpecializationInfo.GetSpecializationInfo(i) == want then return i end
    end
    return nil
end

-- What a dynamicspec entry is CALLED when it is being picked, and on the
-- character that cannot resolve it. Kept here rather than in the options page
-- so the picker row and the placeholder cannot drift apart.
--
-- On ns with no local alias, and called back through ns below: this file's
-- main chunk is at Lua's ceiling of 200 locals (see UsableSlots), and a local
-- here spends the last one.
ns.SpecPositionName = function(index)
    return EllesmereUI.Lf("Specialization %1$d", index or 0)
end

-------------------------------------------------------------------------------
--  Dynamic Profession: a dynamicprofession slot names a POSITION (1/2 = the
--  two primary professions in GetProfessions order, 3/4/5 = Cooking, Fishing,
--  Archaeology), resolved live to that profession's opener spell, or with
--  slot.extra its second non-passive spell. slot.specialization resolves the
--  first known specialization ability for Mining, Herbalism, or Skinning.
--  Unlearned positions and professions with no second ability resolve to nil
--  and go dark under Hide Unusable Entries. Resolvers live on ns (200-local
--  ceiling). SlotUsable, ResolveAction and SlotDisplay share a memo per
--  position and ability kind. PushAllPalettes wipes it beside usableMemo;
--  SPELLS_CHANGED covers the learn/unlearn edge.
-------------------------------------------------------------------------------
do
    local cache = {}

    local function Resolve(slot)
        if not slot or slot.kind ~= "dynamicprofession" then return nil, nil end
        local i = tonumber(slot.index)
        if not i then return nil, nil end
        local key = i * 4 + (slot.extra and 1 or 0)
            + (slot.specialization and 2 or 0)
        local hit = cache[key]
        if hit then return hit.book, hit.spell end

        local prof1, prof2, arch, fish, cook = GetProfessions()
        local book
        if i == 1 then book = prof1
        elseif i == 2 then book = prof2
        elseif i == 3 then book = cook
        elseif i == 4 then book = fish
        elseif i == 5 then book = arch
        end

        -- Gathering specialization abilities live in general spellbook
        -- flyouts, outside the profession's own spellbook block.
        local spell
        if book then
            local _, _, _, _, numSpells, spellOffset, skillLine = GetProfessionInfo(book)
            if slot.specialization then
                -- Blizzard exposes each learned flyout and each profession's
                -- skill line, but no relationship between the two.
                local flyoutID
                if skillLine == 182 then flyoutID = 239       -- Herbalism
                elseif skillLine == 186 then flyoutID = 240   -- Mining
                elseif skillLine == 393 then flyoutID = 238   -- Skinning
                end
                if flyoutID then
                    local numSlots = select(3, GetFlyoutInfo(flyoutID))
                    for n = 1, (numSlots or 0) do
                        local spellID, _, isKnown = GetFlyoutSlotInfo(flyoutID, n)
                        if isKnown then spell = spellID; break end
                    end
                end
            else
                -- Nth non-passive spell in the profession block: 1 = opener,
                -- 2 = the profession's native extra action, when it has one.
                local which = slot.extra and 2 or 1
                local seen = 0
                for n = 1, (numSpells or 0) do
                    local info = C_SpellBook.GetSpellBookItemInfo(
                        n + (spellOffset or 0), Enum.SpellBookSpellBank.Player)
                    if info and info.spellID and not info.isPassive then
                        seen = seen + 1
                        if seen == which then spell = info.spellID; break end
                    end
                end
            end
        end

        cache[key] = { book = book, spell = spell }
        return book, spell
    end

    ns.ProfessionBookIndexFor = function(slot) return (Resolve(slot)) end
    ns.ProfessionSpellFor = function(slot) return (select(2, Resolve(slot))) end
    ns.WipeProfessionCache = function() wipe(cache) end
end

-- Picker / unresolved-placeholder name for a dynamicprofession position (the
-- ns.SpecPositionName counterpart): positions 1-2 by number, 3-5 by the
-- client's own skill name.
ns.ProfessionPositionName = function(index, extra, specialization)
    index = tonumber(index)
    local base
    if index == 3 then base = COOKING or "Cooking"
    elseif index == 4 then base = FISHING or "Fishing"
    elseif index == 5 then base = ARCHAEOLOGY or "Archaeology"
    else base = EllesmereUI.Lf("Profession %1$d", index or 0)
    end
    if specialization then
        return EllesmereUI.Lf("%1$s Specialization Ability", base)
    elseif extra then
        return EllesmereUI.Lf("%1$s Extra Ability", base)
    end
    return base
end

-------------------------------------------------------------------------------
--  Interface panels: one entry per Blizzard panel, so the whole micro menu
--  fits on a ring and costs one keybind. A panel with a micro button fires as
--  "/click <button>", the click Blizzard's own menu makes: the macro runs
--  untainted from the secure button, where an addon opening the frame from its
--  own Lua taints what it draws (EllesmereUIDataBars_Blocks.lua:4138). The five
--  with no button to click fire from FireInsecure, out of combat only.
-------------------------------------------------------------------------------
do
    -- Scoped, with the accessors on ns: the main chunk is at Lua's ceiling of
    -- 200 locals (see UsableSlots). The ".png" on each name is not optional --
    -- the client only finds a PNG by its full filename.
    local ART = "Interface\\AddOns\\EllesmereUI\\media\\micromenu\\"

    -- button: the micro button to click; a LIST is tried in order, since the
    --   spellbook button was renamed when talents and the spellbook merged.
    -- fire: the toggle for a panel with no button, called from FireInsecure.
    -- label: the client's own caption, by GLOBAL NAME rather than by value so
    --   no English one is baked in; first that answers wins, `default` last.
    -- minor: left out of the preset menu. The panels run two past MAX_SLOTS on
    --   a full client, and the Shop and Customer Support are the two a ring is
    --   worth the least. Both are still in the picker.
    local PANELS = {
        { key = "character",   icon = ART .. "menu-character.png",
          button = "CharacterMicroButton",
          label = "CHARACTER_BUTTON",           default = "Character" },
        { key = "spellbook",   icon = ART .. "menu-spellbook.png",
          button = { "PlayerSpellsMicroButton", "SpellbookMicroButton" },
          label = { "PLAYERSPELLS_BUTTON", "TALENTS_BUTTON" },
          default = "Spellbook and Talents" },
        { key = "professions", icon = ART .. "menu-professions.png",
          button = "ProfessionMicroButton",
          label = "PROFESSIONS_BUTTON",         default = "Professions" },
        { key = "achievements", icon = ART .. "menu-achievements.png",
          button = "AchievementMicroButton",
          label = { "ACHIEVEMENT_BUTTON", "ACHIEVEMENTS" },
          default = "Achievements" },
        { key = "quests",      icon = ART .. "menu-quests.png",
          button = "QuestLogMicroButton",
          label = { "QUESTLOG_BUTTON", "QUEST_LOG" }, default = "Quest Log" },
        { key = "guild",       icon = ART .. "menu-guild.png",
          button = "GuildMicroButton",
          label = { "GUILD_AND_COMMUNITIES", "GUILD" }, default = "Guild" },
        { key = "groupfinder", icon = ART .. "menu-group.png",
          button = "LFDMicroButton",
          label = "DUNGEONS_BUTTON",            default = "Group Finder" },
        -- No micro button of its own since the Group Finder swallowed the tab:
        -- TogglePVPUI is the call the game's own binding makes, and it lives in
        -- a [Bootstrap] file, so it answers from login however late the panel
        -- itself loads.
        { key = "pvp",         icon = ART .. "menu-pvp.png",
          fire = function() if TogglePVPUI then TogglePVPUI() end end,
          exists = function() return TogglePVPUI ~= nil end,
          label = { "PLAYER_V_PLAYER", "PVP" },  default = "Player vs Player" },
        { key = "adventure",   icon = ART .. "menu-adventure.png",
          button = "EJMicroButton",
          label = { "ADVENTURE_JOURNAL", "ENCOUNTER_JOURNAL" },
          default = "Adventure Guide" },
        { key = "collections", icon = ART .. "menu-collections.png",
          button = "CollectionsMicroButton",
          label = "COLLECTIONS",                default = "Collections" },
        { key = "housing",     icon = ART .. "menu-housing.png",
          button = "HousingMicroButton",
          label = "HOUSING_MICRO_BUTTON",       default = "Housing" },
        -- The Quick Join toast, which is what the game binds TOGGLESOCIAL to
        -- now that the social micro button is gone. Same button the micro menu
        -- data bar block clicks for its Friends entry.
        { key = "social",      icon = ART .. "menu-friends.png",
          button = "QuickJoinToastButton",
          label = { "SOCIAL_LABEL", "SOCIAL_BUTTON", "FRIENDS" },
          default = "Social" },
        { key = "map",         icon = ART .. "menu-map.png",
          fire = function() if ToggleWorldMap then ToggleWorldMap() end end,
          exists = function() return ToggleWorldMap ~= nil end,
          label = { "WORLD_MAP", "WORLDMAP_BUTTON" }, default = "Map" },
        { key = "bags",        icon = ART .. "menu-bags.png",
          fire = function() if ToggleAllBags then ToggleAllBags() end end,
          exists = function() return ToggleAllBags ~= nil end,
          label = { "BAGSLOTTEXT", "INVENTORY_TOOLTIP" }, default = "Bags" },
        -- The Great Vault, which the game gives no keybind of its own at all.
        -- Blizzard's entry point only ever SHOWS it, so the toggle half is
        -- ours: a second press on an open vault closes it, which is how every
        -- other entry here answers a second press.
        { key = "greatvault",  icon = ART .. "menu-vault.png",
          fire = function()
              local f = WeeklyRewardsFrame
              if f and f:IsShown() then
                  HideUIPanel(f)
              elseif WeeklyRewards_ShowUI then
                  WeeklyRewards_ShowUI()
              end
          end,
          exists = function() return WeeklyRewards_ShowUI ~= nil end,
          label = "GREAT_VAULT_REWARDS",        default = "Great Vault" },
        -- The one panel with a micro button that cannot be clicked: its OnClick
        -- opens nothing unless the cursor is ON the button
        -- (MainMenuBarMicroButtons.lua:1844), which a macro's click never is.
        { key = "gamemenu",    icon = ART .. "menu-options.png",
          fire = function()
              if GameMenuFrame and GameMenuFrame:IsShown() then
                  HideUIPanel(GameMenuFrame)
              elseif GameMenuFrame_Show then
                  GameMenuFrame_Show()
              end
          end,
          exists = function() return GameMenuFrame_Show ~= nil end,
          label = "MAINMENU_BUTTON",            default = "Game Menu" },
        { key = "shop",        icon = ART .. "menu-shop.png", minor = true,
          button = "StoreMicroButton",
          label = "BLIZZARD_STORE",             default = "Shop" },
        { key = "help",        icon = ART .. "menu-cs.png", minor = true,
          button = "HelpMicroButton",
          label = "HELP_BUTTON",                default = "Customer Support" },
    }

    local byKey = {}
    for _, def in ipairs(PANELS) do byKey[def.key] = def end

    -- The button this panel is clicked by, or nil for the ones with none and
    -- for a client that has not got the button. IsForbidden as well as
    -- existence: /click refuses a frame an addon may not reach
    -- (SlashCommands.lua:738), so an entry pointing at one would fire nothing.
    local function PanelButton(def)
        local names = def and def.button
        if not names then return nil end
        if type(names) == "string" then names = { names } end
        for _, name in ipairs(names) do
            local f = _G[name]
            if f and f.Click and f.IsForbidden and not f:IsForbidden() then
                return name
            end
        end
        return nil
    end

    ns.PanelDef = function(slot)
        return slot and byKey[slot.key]
    end

    ns.PanelName = function(def)
        if not def then return nil end
        local names = def.label
        if type(names) == "string" then names = { names } end
        for _, g in ipairs(names) do
            local s = _G[g]
            if type(s) == "string" and s ~= "" then return s end
        end
        return EllesmereUI.L(def.default)
    end

    -- The macro a panel entry fires, or nil for the ones FireInsecure takes.
    ns.PanelMacro = function(def)
        local name = PanelButton(def)
        return name and ("/click " .. name) or nil
    end

    ns.PanelFire = function(def)
        if def and def.fire and (not def.exists or def.exists()) then def.fire() end
    end

    -- Whether this client has the panel at all: Housing arrived in 12.0, the
    -- Shop is not built into every region's client, and a panel whose addon
    -- never loaded has no toggle to call. An entry that answers no goes dark
    -- under Hide Unusable Entries rather than sitting there firing nothing.
    ns.PanelAvailable = function(def)
        if not def then return false end
        if def.button then return PanelButton(def) ~= nil end
        return (def.fire ~= nil) and (not def.exists or def.exists())
    end

    -- Candidate slots for the picker and the preset, in the order the micro
    -- menu itself runs. keepOrder holds them in it: the panels are a row the
    -- player already reads left to right, and alphabetising them would be the
    -- one place in the interface they are not in that order.
    ns.PanelSlots = function(includeMinor)
        local out = {}
        for _, def in ipairs(PANELS) do
            if (includeMinor or not def.minor) and ns.PanelAvailable(def) then
                out[#out + 1] = { kind = "panel", key = def.key }
            end
        end
        return out
    end
end

-------------------------------------------------------------------------------
--  Dynamic Rez
--
--  One entry that is whichever resurrection spell this character has, so a
--  palette shared between a druid, a priest and a death knight carries the rez
--  once rather than three times over with two of them dead on every character.
--
--  single and group are the out-of-combat casts; battle is the in-combat one.
--  The same kit the raid frames' Dynamic Rez click-cast binding uses
--  (EUI_RaidFrames_ClickCast.lua:90), kept as a copy of the table rather than
--  read across from it: that is a separate addon the user can switch off, and
--  an entry on a palette must not stop working when they do. The two lists have
--  to be changed together when a class gains or loses a rez.
--
--  One table rather than a local per entry point, and everything else scoped to
--  the do-block below. That is not tidiness: this file's main chunk sits within
--  a handful of Lua's ceiling of 200 locals, and neither a field nor a
--  block-local costs one of them.
-------------------------------------------------------------------------------
local Rez = {}
do
local UnitExists, UnitIsFriend, UnitIsDeadOrGhost =
    UnitExists, UnitIsFriend, UnitIsDeadOrGhost

local REZ_BY_CLASS = {
    PRIEST      = { single = 2006,   group = 212036 },
    PALADIN     = { single = 7328,   group = 212056, battle = 391054 },
    SHAMAN      = { single = 2008,   group = 212048 },
    DRUID       = { single = 50769,  group = 212040, battle = 20484 },
    MONK        = { single = 115178, group = 212051 },
    EVOKER      = { single = 361227, group = 361178 },
    DEATHKNIGHT = { battle = 61999 },
    WARLOCK     = { battle = 20707 },
}

-- battle, single, group for this character, any of them nil. Filtered by what
-- is actually in the spellbook, because the macro below picks a branch by
-- CONDITION rather than by knowledge: a /cast line naming a spell the character
-- has not got is a branch that matches and then casts nothing, which would eat
-- the fallback the next branch was there to be.
--
-- Not cached, and deliberately so. What is known moves with talents --
-- Intercession is a holy paladin's -- and it is also simply WRONG for a moment
-- at login, while the spellbook is still cold. A cache would latch that empty
-- answer and hold it until something invalidated it, which is a worse failure
-- than the reads it saves: three spellbook lookups, on a path that runs once
-- per palette open rather than per frame. See AdvanceLiveIcons for the one that
-- does run per frame.
--
-- The macro this feeds is written at push time, and SPELLS_CHANGED already
-- requests a push for the usability filter -- so a talent swap, a spec change,
-- levelling into a rez and the spellbook warming up after login all rebuild it
-- with no registration of its own.
local function RezKit()
    local _, class = UnitClass("player")
    local kit = class and REZ_BY_CLASS[class]
    if not kit then return nil end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local function Known(id)
        if not id then return nil end
        if C_SpellBook.IsSpellInSpellBook and bank
           and not C_SpellBook.IsSpellInSpellBook(id, bank, true) then
            return nil
        end
        return id
    end
    return Known(kit.battle), Known(kit.single), Known(kit.group)
end

-- A corpse worth casting the single-target rez at. UnitIsDeadOrGhost rather
-- than UnitIsDead, to agree with the macro's [dead]: that conditional is true
-- for a player who has released as well, and a released player is exactly who
-- needs resurrecting.
--
-- Identity APIs can answer SECRET booleans in restricted content, and this
-- runs EVERY FRAME from IconState while a menu holding a live-icon entry is
-- open -- truthiness on a secret throws, and a throw here storms the whole
-- OnUpdate. Every read is issecretvalue-guarded FIRST and a secret fails to
-- false: an unknowable corpse keeps the current branch, and the next
-- readable frame corrects the picture.
function Rez.HasDeadTarget()
    local exists = UnitExists("target")
    if issecretvalue(exists) or not exists then return false end
    local friend = UnitIsFriend("player", "target")
    if issecretvalue(friend) or not friend then return false end
    local dead = UnitIsDeadOrGhost("target")
    if issecretvalue(dead) or not dead then return false end
    return true
end

-- Which spell the entry would cast RIGHT NOW, for the icon and the live state
-- beneath it. Display only -- the macro decides again at fire time and the game
-- evaluates its conditionals then -- so this exists to keep the picture honest,
-- and its branch order has to match Rez.MacroText's exactly or the palette shows
-- one spell and casts another.
function Rez.SpellNow()
    local battle, single, group = RezKit()
    -- A class whose only rez is the battle one casts it in every state, which
    -- is what the bare macro line below does for the same case.
    if not (single or group) then return battle end
    if battle and InCombatLockdown() then return battle end
    if single and Rez.HasDeadTarget() then return single end
    return group or single
end

-- The macro a Dynamic Rez entry fires, or nil for a character with no rez at
-- all. One /cast with a fallback chain rather than a line each: the chain
-- attempts exactly ONE cast -- the first branch whose condition holds -- where
-- separate lines would each try in turn and the second would land on "another
-- action is in progress".
function Rez.MacroText()
    local battle, single, group = RezKit()
    local Name = C_Spell.GetSpellName
    if not Name then return nil end

    local parts = {}
    local function Add(cond, id)
        -- By NAME: /cast resolves against the localized one, and a hardcoded
        -- English name would fail silently on every other client.
        local name = id and Name(id)
        if name then parts[#parts + 1] = cond .. name end
    end

    -- [combat] only when there is something after it to be the out-of-combat
    -- answer. A death knight or a warlock, whose only rez IS the battle one,
    -- would otherwise cast nothing out of combat -- where that spell works
    -- perfectly well.
    Add((single or group) and "[combat] " or "", battle)
    -- Not a safety check: a corpse is a rez's only valid target, so there is no
    -- exists/nodead here the way there is on an ordinary cast. This condition is
    -- how the single-target spell is chosen over the group one.
    Add("[@target,help,dead] ", single)
    -- Bare, and last: the group rez takes no target, so it is the honest answer
    -- to "none of the above".
    --
    -- Falling back to the single one when there is no group rez -- a character
    -- still levelling into it -- is what keeps this line in step with
    -- Rez.SpellNow, which ends on the same `group or single`. Without the
    -- fallback the macro has no unconditional branch at all, and the entry
    -- draws the single rez, tints it usable and casts nothing. Attempting it
    -- and being told there is no target is the same answer the spell gives from
    -- an action bar, and it matches the picture.
    Add("", group or single)

    if #parts == 0 then return nil end
    return "/cast " .. table.concat(parts, "; ")
end

-- Does this character's class have a resurrection spell at all? The picker asks
-- so it can leave the entry out for a class that has none -- an entry that
-- could never do anything is worse than no entry. By CLASS rather than by what
-- is currently in the spellbook: a paladin who has not taken Intercession still
-- has Redemption, and a druid at level 10 will have Rebirth soon enough.
function ns.HasRezKit()
    local _, class = UnitClass("player")
    return (class and REZ_BY_CLASS[class]) ~= nil
end
end

-- The filtered answers, one per palette table. Wiped ONLY at the top of
-- PushAllPalettes: the memo is what keeps the drawn menu and the pushed
-- secure attributes reading the SAME list even when the spellbook shifts
-- between the push and the open (a pet swap mid-fight, say) -- usability is
-- allowed to go stale until the next push rather than ever disagreeing with
-- what a cell index fires. Every input that can change an answer lands here
-- through that same wipe: SPELLS_CHANGED and UPDATE_MACROS request a push,
-- every slot edit and the toggle itself request one through Refresh, class
-- and spec-list are fixed for the session, and a profile switch hands out
-- different palette tables (weak keys let the old ones go).
local usableMemo = setmetatable({}, { __mode = "k" })

-- KnownForm, SpellKnownHere and SlotUsable are private to UsableSlots, and
-- are scoped so they cost no main-chunk local: this file's main chunk is at
-- Lua's ceiling of 200 locals, and merging two features into it went over.
-- usableMemo stays outside the block -- PushAllPalettes wipes it.
do
-- Is this one spell id in either of this character's books, player or pet?
local function KnownForm(sid)
    return (sid and sid > 0)
        and (IsPlayerSpell(sid)
             or (C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
                 and C_SpellBook.IsSpellKnownOrInSpellBook(sid)))
        or false
end

-- Whether this character's books hold the spell in ANY of its forms: the
-- stored id, its talent override, and its base form. Generous on purpose --
-- hiding a castable entry is a worse failure than drawing a dead one, so
-- every form is checked before answering no, and a malformed id answers yes
-- and leaves the slot to render as the placeholder it always was.
local function SpellKnownHere(id)
    if type(id) ~= "number" or id <= 0 then return true end
    if KnownForm(id) then return true end
    local ovr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
        and C_SpellBook.FindSpellOverrideByID(id)
    if ovr ~= id and KnownForm(ovr) then return true end
    local base = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(id)
    return base ~= id and KnownForm(base)
end

-- Can this character do anything with the slot? Only the kinds that resolve
-- against one character's own kit are tested -- another class's
-- specialization, a profession position this character does not reach, a
-- spell no book here holds, a macro this character does not have, a
-- resurrection this class has none of. Everything else (items, toys,
-- mounts, pets, markers, nested menus) is account-wide or self-resolving
-- and stays.
local function SlotUsable(slot)
    local k = slot and slot.kind
    if k == "spec" or k == "dynamicspec" then
        return SpecIndexFor(slot) ~= nil
    elseif k == "dynamicprofession" then
        return ns.ProfessionSpellFor(slot) ~= nil
    elseif k == "spell" then
        return SpellKnownHere(tonumber(slot.id))
    elseif k == "macro" then
        return GetMacroInfo(slot.name or slot.id) ~= nil
    elseif k == "panel" then
        -- The one kind whose availability is the CLIENT's rather than the
        -- character's: Housing arrived in 12.0 and the Shop is not in every
        -- region's build. Hidden by the same setting all the same -- an entry
        -- that can never open anything is one to keep off the ring.
        return ns.PanelAvailable(ns.PanelDef(slot))
    elseif k == "dynamicrez" then
        -- By CLASS rather than by what is in the book right now, which is what
        -- ns.HasRezKit answers: a paladin who has not taken Intercession still
        -- has Redemption, and a druid too low for Rebirth will have it. Hiding
        -- the entry on those would take it away from the character it is FOR.
        -- A mage carrying the shared menu is the case this catches, and it is
        -- the one the entry's own note names.
        return ns.HasRezKit()
    end
    return true
end

-- The entries of the palette this character can use ("Hide Unusable
-- Entries"). A view, never a mutation: returns the stored array itself while
-- nothing is filtered or the setting is off, and a fresh dense array
-- otherwise -- the stored slots keep every entry for the characters that CAN
-- use them.
function UsableSlots(palette, p)
    local slots = palette and palette.slots
    if not slots then return slots end
    if p and p.hideUnusable == false then return slots end
    local memo = usableMemo[palette]
    if memo then return memo end
    local out
    for i = 1, #slots do
        if not SlotUsable(slots[i]) then
            if not out then
                out = {}
                for j = 1, i - 1 do out[j] = slots[j] end
            end
        elseif out then
            out[#out + 1] = slots[i]
        end
    end
    usableMemo[palette] = out or slots
    return out or slots
end
end

-- kind -> attribute triple for the secure button, plus an optional 4th value:
-- a sibling attribute key that must be cleared because the same action type
-- would otherwise read it in preference. Returns nil for the kinds with no
-- secure action type at all (battlepet, the two spec kinds, the mounts), which
-- FireInsecure handles instead.
--
-- p is the palette's appearance view, for the one kind whose action depends on
-- a setting rather than only on the slot (worldmarker). It is the view of the
-- palette being PUSHED, which for a nest's cells is the owner's -- the same
-- palette whose appearance draws them.
local function ResolveAction(slot, p)
    if not slot or not slot.kind then return nil end
    local k = slot.kind

    -- A palette opens entries; it never fires one. Returning nothing is what
    -- makes a release on the parent itself a cancel, which is the only sensible
    -- reading of "you stopped on the door rather than going through it".
    if k == "palette" then return nil end

    if k == "spell" then
        if type(slot.id) ~= "number" then return nil end
        return "spell", "spell", slot.id

    elseif k == "dynamicprofession" then
        -- Resolved to the CURRENT position's spell every time the
        -- attributes are written, then fired the same way any other spell
        -- slot is -- see ns.ProfessionSpellFor above for what makes the
        -- position current.
        local spellID = ns.ProfessionSpellFor(slot)
        if not spellID then return nil end
        return "spell", "spell", spellID

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

    elseif k == "raidtarget" then
        -- Fired as the /tm slash command rather than through
        -- SECURE_ACTIONS.raidtarget: that action reads TWO attributes, marker
        -- and action, and the firing end of the snippet pushes exactly one key
        -- per cell. The command reaches SetRaidTarget itself
        -- (SlashCommands.lua:1381-1406), and /tm 0 is its documented clear.
        --
        -- What makes that legal is the secure button running the macro, NOT
        -- anything about SetRaidTarget: it is protected, and refuses any call
        -- an addon makes from its own Lua. See the clearmarkers branch below,
        -- which was written on the opposite assumption and did not work.
        local id = tonumber(slot.id)
        if not id or id < 0 or id > 8 then return nil end
        return "macro", "macrotext", "/tm " .. id, "macro"

    elseif k == "clearmarkers" then
        -- SECURE_ACTIONS.raidtarget's own clear-all branch, which calls
        -- RemoveRaidTargets (SecureTemplates.lua:590-592). SetRaidTarget is
        -- documented AllowedWhenUntainted and is refused outright from an
        -- addon's own Lua -- the sweep this replaces raised
        -- ADDON_ACTION_FORBIDDEN on its first call -- so going through the
        -- secure button, which runs the action untainted, is the only route.
        --
        -- The ACTION rides in the ordinary key/value slot: raidtarget reads
        -- "marker" and "action", and the firing end of the snippet pushes one
        -- key per cell. clear-all is the one branch that never looks at
        -- "marker", so the single key can be spent on "action" instead.
        --
        -- It also clears more than the loop could: RemoveRaidTargets reaches
        -- marks on units the client cannot currently name, which no clear-all
        -- macro can. In a group it needs lead or assist, and quietly does
        -- nothing without them -- the same rule as marking itself.
        return "raidtarget", "action", "clear-all"

    elseif k == "worldmarker" then
        -- Same one-attribute reasoning as /tm above: /wm places a world
        -- marker, /cwm clears. Both take the ENGINE's marker number, so the
        -- stored icon position goes through the map.
        local id = tonumber(slot.id)
        if not id or id < 0 or id > 8 then return nil end
        if id == 0 then
            -- The /cwm handler compares its argument against the client's own
            -- ALL string (SlashCommands.lua:824-830), so that string is what
            -- gets baked -- a hardcoded "all" would fail on a localized client.
            return "macro", "macrotext", "/cwm " .. (ALL or "all"), "macro"
        end
        if p == nil or p.worldMarkerToggle ~= false then
            -- Toggle World Markers. Not a macro: /wm is PlaceRaidMarker with
            -- no test at all (SlashCommands.lua:820), and no macro conditional
            -- reports a world marker as down. SECURE_ACTIONS.worldmarker does
            -- the test itself (SecureTemplates.lua:602-618), and still costs
            -- the ONE attribute a cell may spend -- it reads "marker" and
            -- "action", and "action" falls back to "toggle" when unset, which
            -- the snippet's clear guarantees it is.
            --
            -- Placement is unchanged: neither Blizzard nor /wm passes a unit
            -- token, so the marker still lands under the cursor.
            return "worldmarker", "marker", WORLD_MARKER_ENGINE[id]
        end
        -- Repeating ONE marker fast stalls here, where cycling eight does not:
        -- the game holds each marker on its own cooldown -- about four spammed
        -- presses -- and answers "You can't do that right now". Nothing to do
        -- with this module: a plain /wm macro alone does it.
        --
        -- Clearing before placing, the way retail's own marker button does
        -- (Mainline/Blizzard_CompactRaidFrameManager.lua:1065-1066), does not
        -- buy anything from a macro: the /cwm spends the cooldown and the /wm
        -- behind it lands inside the window, which reads as a toggle. Blizzard
        -- gets away with it by calling both C functions straight from an
        -- OnClick, which is not a route an addon has.
        return "macro", "macrotext", "/wm " .. WORLD_MARKER_ENGINE[id], "macro"

    elseif k == "dynamicrez" then
        -- Fired as macro text, which is what makes it dynamic in the way that
        -- matters: the attributes are written out of combat, and a rez has to
        -- pick its branch DURING the fight. The game evaluates [combat] when
        -- the macro runs, so a menu pushed before the pull still casts the
        -- battle rez in it. A resolved spellID could not do that.
        local text = Rez.MacroText()
        if not text then return nil end
        return "macro", "macrotext", text, "macro"

    elseif k == "panel" then
        -- "/click <micro button>", so the panel opens on Blizzard's own click
        -- rather than on ours: the macro runs untainted from the secure
        -- button, and a panel opened by an addon's Lua carries that addon's
        -- taint into everything it draws. The panels with no micro button
        -- answer nothing here and go to FireInsecure instead.
        local text = ns.PanelMacro(ns.PanelDef(slot))
        if not text then return nil end
        return "macro", "macrotext", text, "macro"

    elseif k == "cycleraidtarget" or k == "cycleworldmarker" then
        -- The step the position on the slot says is up. The snippet overwrites
        -- this with its own answer on every press -- see the eqdCycN branch --
        -- so what is pushed here is only what the entry would fire if the
        -- cycle attributes went missing: the right marker, just not advancing.
        --
        -- Deliberately NOT affected by Toggle World Markers, though the step
        -- machinery would carry a marker number as readily as a macro. A cycle
        -- is a run THROUGH the eight, and a step that picks its marker back up
        -- because that one happened to be down already breaks the run: the
        -- press that should have placed the circle places nothing, and the
        -- position still advances. Placing every time is the only behavior
        -- that keeps a cycle predictable.
        local steps = CycleSteps(k)
        return "macro", "macrotext", steps[CycleNext(slot)], "macro"
    end

    return nil
end
ns.ResolveAction = ResolveAction

-- The kinds with no secure action type at all. None of these calls is
-- protected -- summoning a battle pet or a mount and changing specialization
-- are all ordinary API -- so all are safe straight from PostClick.
--
-- WHICH cell reaches here is the snippet's answer rather than the live view's
-- selection; see OnPostClick.
local function FireInsecure(slot)
    if not slot then return end
    if slot.kind == "battlepet" and slot.guid and C_PetJournal then
        C_PetJournal.SummonPetByGUID(slot.guid)

    elseif slot.kind == "randommount" and C_MountJournal then
        -- The Mount Journal button's own call
        -- (Blizzard_MountCollection.lua:998); 0 means "a random favorite".
        -- Refused by the game itself in combat, where no mount can be
        -- summoned anyway.
        C_MountJournal.SummonByID(0)

    elseif slot.kind == "lastmount" and C_MountJournal then
        -- The same call with the mount the player last rode, tracked rather
        -- than stored on the slot -- the whole point of the entry is that it
        -- changes on its own. Nothing tracked yet (a fresh profile, or a
        -- session where the player has not mounted) falls back to the random
        -- favorite rather than doing nothing: an entry that answers a press
        -- with silence reads as broken.
        local pf = P()
        local id = pf and pf.lastMountID
        C_MountJournal.SummonByID(type(id) == "number" and id or 0)

    elseif slot.kind == "panel" then
        -- Only the panels ResolveAction had no micro button for. Out of combat
        -- only, which is the game's rule rather than ours: an insecure
        -- ShowUIPanel is refused in a fight, and it refuses it quietly.
        ns.PanelFire(ns.PanelDef(slot))

    elseif slot.kind == "spec" or slot.kind == "dynamicspec" then
        local index = SpecIndexFor(slot)
        -- Refused in combat by the game itself, with its own error message.
        -- Nothing to defer to PLAYER_REGEN_ENABLED: a spec change the user
        -- asked for mid-fight and got minutes later is not what they meant.
        if index then C_SpecializationInfo.SetSpecialization(index) end
    end
end

-- The fileID behind the question mark path above. GetMacroInfo answers a fileID
-- rather than a path, so the two cannot be compared without this.
local QUESTION_MARK_ID = GetFileIDFromPath and GetFileIDFromPath(QUESTION_MARK)

-- The icon for what a macro would fire RIGHT NOW, or nil to fall back to the
-- icon the macro was saved with.
--
-- A macro's conditionals are evaluated when it runs, so a [mod] macro fires a
-- different spell depending on what is held at the release -- and the palette
-- has to draw the branch it is going to take, or it shows one picture and casts
-- the other. GetMacroSpell and GetMacroItem answer the current branch.
--
-- ONLY for a macro sitting on the dynamic "?" icon, which is what the caller's
-- question-mark test is for. A macro the player gave a real icon keeps it, the
-- way Blizzard's own action buttons keep it: that icon is a choice, and
-- resolving over the top of it would take the choice away. It also makes this
-- safe whichever of the two things GetMacroInfo does -- return the saved icon,
-- or resolve the dynamic one itself -- because in the resolving case a "?" macro
-- never reaches here with a question mark to begin with.
--
-- By macro NAME resolved to an index, which is the pairing the rest of the suite
-- settled on (EllesmereUICooldownManager.lua:6986-6992): the id a macro action
-- carries is not reliably a macro index, and these two want the index.
local function MacroIcon(nameOrIndex)
    if not nameOrIndex then return nil end
    local index = nameOrIndex
    if type(index) ~= "number" then index = GetMacroIndexByName(index) end
    if not index or index <= 0 then return nil end

    local spellID = GetMacroSpell(index)
    if spellID then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.iconID then return info.iconID end
    end

    -- An item branch answers no spell. The link, not the name: it carries the
    -- itemID, and a name would have to be looked up again to get one.
    --
    -- The existence guard is a statement rather than `GetMacroItem and
    -- GetMacroItem(index)` -- an `and` expression is truncated to ONE value, so
    -- that form would drop the link and leave every item macro on its saved
    -- icon. Same trap SlotDisplay's own note names, one function below.
    if GetMacroItem then
        local _, link = GetMacroItem(index)
        if link then
            local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
            if icon then return icon end
        end
    end

    -- Neither -- a macro that only marks, targets or emotes. The saved icon is
    -- the honest answer for those, and it is the one the caller falls back to.
    return nil
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
        if type(slot.id) ~= "number" then return QUESTION_MARK, slot.name end
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(slot.id)
        local name = C_Item.GetItemInfo(slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "toy" then
        if type(slot.id) ~= "number" then return QUESTION_MARK, slot.name end
        local _, name, icon = C_ToyBox.GetToyInfo(slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "macro" then
        local nameOrIndex = slot.name or slot.id
        local name, icon = GetMacroInfo(nameOrIndex)
        -- A question mark here means the macro carries no icon of its own, so
        -- what it is about to fire is the only thing left to draw. Anything else
        -- is an icon the player picked, and it stands. See MacroIcon.
        if icon == nil or icon == QUESTION_MARK or icon == QUESTION_MARK_ID then
            icon = MacroIcon(nameOrIndex) or icon
        end
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "macrotext" then
        -- slot.icon may be a { atlas = ... } table (the Pings preset stores
        -- one verbatim); SetIconTexture/ApplyIconCrop render both forms.
        return slot.icon or QUESTION_MARK, slot.name or "Macro"

    elseif k == "dynamicrez" then
        -- The spell it would cast, not a fixed emblem: the entry is worth
        -- having because it changes, and one picture over three different casts
        -- would hide the only thing it has to say.
        local id = Rez.SpellNow()
        local info = id and C_Spell.GetSpellInfo(id)
        if info then return info.iconID or QUESTION_MARK, info.name end
        -- A character with no resurrection spell at all -- the mage carrying
        -- the shared palette. Drawn as an occupied slot under its own name, the
        -- same as a spec this character does not have.
        return QUESTION_MARK, "Dynamic Rez"

    elseif k == "mount" then
        if type(slot.id) ~= "number" then return QUESTION_MARK, slot.name end
        local name, _, icon = C_MountJournal.GetMountInfoByID(slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "lastmount" then
        -- Whatever is tracked right now, so the entry shows the mount it would
        -- actually summon. Before anything is tracked it shows what it would
        -- fall back to, which is the random favorite (see FireInsecure), under
        -- a name that says what the entry IS rather than what it is standing
        -- in for.
        local pf = P()
        local id = pf and pf.lastMountID
        if type(id) == "number" then
            local name, _, icon = C_MountJournal.GetMountInfoByID(id)
            if name then return icon or QUESTION_MARK, name end
        end
        local info = C_Spell.GetSpellInfo(RANDOM_FAVORITE_MOUNT)
        return (info and info.iconID) or QUESTION_MARK, "Last Used Mount"

    elseif k == "randommount" then
        local info = C_Spell.GetSpellInfo(RANDOM_FAVORITE_MOUNT)
        -- The client's own caption for the Mount Journal button, so the entry
        -- reads the same on a localized client as the thing it summons.
        return (info and info.iconID) or QUESTION_MARK,
               MOUNT_JOURNAL_SUMMON_RANDOM_FAVORITE_MOUNT
                   or (info and info.name) or "Random Favorite Mount"

    elseif k == "spec" or k == "dynamicspec" then
        local index = SpecIndexFor(slot)
        if index then
            -- Both kinds draw the specialization they would switch to, which
            -- is the whole point of the dynamic one: the icon and the name are
            -- this character's, so a palette carried to another class arrives
            -- showing that class's specs rather than the owner's.
            local _, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(index)
            return icon or QUESTION_MARK, name or slot.name
        end
        if k == "dynamicspec" then
            -- A position this class has not got: four on anything but a
            -- druid, three on a demon hunter. The entry names a seat rather
            -- than an occupant, so with no occupant to draw it says the seat.
            return QUESTION_MARK, ns.SpecPositionName(tonumber(slot.index))
        end
        -- A spec this character's class does not have. Its identity is still
        -- global -- the specID answers by itself -- so the editor and an
        -- unfiltered menu draw the real specialization, not a placeholder.
        local want = tonumber(slot.specID)
        if want and GetSpecializationInfoByID then
            local _, name, _, icon = GetSpecializationInfoByID(want)
            if icon or name then
                return icon or QUESTION_MARK, name or slot.name
            end
        end
        return QUESTION_MARK, slot.name

    elseif k == "dynamicprofession" then
        if slot.extra or slot.specialization then
            -- The ABILITY's own name and icon rather than the profession's:
            -- unlike the opener, these entries are distinct spells.
            local spellID = ns.ProfessionSpellFor(slot)
            if spellID then
                local info = C_Spell.GetSpellInfo(spellID)
                if info then return info.iconID or QUESTION_MARK, info.name or slot.name end
            end
        else
            local bookIndex = ns.ProfessionBookIndexFor(slot)
            if bookIndex then
                -- The profession's own name and icon, not the opener
                -- spell's -- the same skill icon its spellbook entry shows.
                local name, icon = GetProfessionInfo(bookIndex)
                return icon or QUESTION_MARK, name or slot.name
            end
        end
        -- An unavailable position, native extra, or specialization ability.
        -- Name the seat rather than an occupant, like an empty dynamicspec.
        return QUESTION_MARK, ns.ProfessionPositionName(
            tonumber(slot.index), slot.extra, slot.specialization)

    elseif k == "battlepet" then
        if type(slot.guid) ~= "string" then return QUESTION_MARK, slot.name end
        local _, _, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(slot.guid)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "raidtarget" then
        local id = tonumber(slot.id) or 0
        if id < 1 or id > 8 then
            return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Clear Target Marker"
        end
        return MarkerIcon(id), "Target Marker: " .. MARKER_NAMES[id]

    elseif k == "clearmarkers" then
        return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Clear All Target Markers"

    elseif k == "worldmarker" then
        local id = tonumber(slot.id) or 0
        if id < 1 or id > 8 then
            return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Clear World Markers"
        end
        return MarkerIcon(id), "World Marker: " .. MARKER_NAMES[id]

    elseif k == "cycleraidtarget" or k == "cycleworldmarker" then
        -- Drawn as the marker the next press places, not as a fixed emblem: in
        -- a radial the icon is what the entry is picked by, and one that never
        -- changed while the action did would be worse than no entry at all.
        local id = CycleNext(slot)
        local what = (k == "cycleraidtarget") and "Target" or "World"
        return MarkerIcon(id), "Cycle " .. what .. " Marker: " .. MARKER_NAMES[id]

    elseif k == "panel" then
        -- The art is ours rather than the micro button's own: those atlases
        -- are the 32x40 shape of a micro button and would be stretched square
        -- by the icon a menu entry draws at.
        local def = ns.PanelDef(slot)
        if def then return def.icon, ns.PanelName(def) end
        -- A key from a newer version of the module, or one that has been
        -- retired. Drawn as an occupied slot, like every other unresolved kind.
        return QUESTION_MARK, slot.name or "Interface Panel"

    elseif k == "palette" then
        -- ReadPalette, not EnsurePalette: a nested parent is repainted from the
        -- steering path, which must not rewrite the profile's slot array.
        local palette = ReadPalette(ChildIndex(slot))
        -- Two choices before the fallback, narrowest first: this entry's own
        -- override, then the palette's first entry -- so a "Mounts" palette
        -- looks like a mount without anyone having to pick an icon for it.
        -- Only one level down: a first entry that is itself a palette would
        -- send this round its own loop.
        local icon = slot.icon
        local first = palette and palette.slots[1]
        if not icon and first and first.kind ~= "palette" then
            icon = SlotDisplay(first)
        end
        return icon or QUESTION_MARK,
               slot.name or (palette and palette.name) or "Action Menu"
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
-- tainted execution throws. C_Spell.GetSpellCooldownDuration returns an opaque
-- duration object instead: it is AllowedWhenTainted, and it goes straight into
-- the widget C-side, so nothing here ever reads a secret.
--
-- Items keep the plain numeric path -- C_Item.GetItemCooldown carries no secret
-- flag and there is no duration-object equivalent for items.
--
-- The spellID an entry's live state is read from, for the kinds that HAVE one.
-- Dynamic entries answer the spell they resolve to right now, so their
-- cooldown describes the same spell as their icon and secure action.
local function SlotSpellID(slot)
    if not slot then return nil end
    if slot.kind == "spell" then
        return type(slot.id) == "number" and slot.id or nil
    elseif slot.kind == "dynamicrez" then
        return Rez.SpellNow()
    elseif slot.kind == "dynamicprofession" then
        return ns.ProfessionSpellFor(slot)
    end
    return nil
end

-- Display data the client only has once it has been ASKED for: GetSpellInfo
-- answers nothing for a spell whose data has not been loaded this session
-- (SpellDocumentation.lua:800-803), and the toy and item getters answer nothing
-- until their item has. A palette paints once per open, so an entry drawn ahead
-- of its data kept the question mark for the whole of that open, and the second
-- open was right only because the first one's failed lookup had fetched it.
-- Both ns-hosted for the reason ns.SetIconTexture is: this chunk is at Lua
-- 5.1's 200-local cap.
function ns.SlotDataReady(slot)
    if not slot then return true end
    local k = slot.kind

    if k == "spell" or k == "dynamicrez" or k == "dynamicprofession" then
        local id = SlotSpellID(slot)
        return not id or C_Spell.IsSpellDataCached(id)
    end

    -- A toy's id IS its itemID, so the two kinds share the one cache. An item's
    -- icon comes off the client's own table and is right either way; its NAME
    -- is what the load is for, and the hub caption reads that.
    if k == "item" or k == "toy" then
        return type(slot.id) ~= "number" or C_Item.IsItemDataCachedByID(slot.id)
    end

    -- Every other kind reads a client-side table -- the mount journal, the pet
    -- journal, the spec and profession lists -- and answers on the first ask.
    return true
end

-- Ask for it, and say whether the answer is still outstanding. Separate from the
-- test above because AdvancePendingIcons retests every frame and must not send
-- the request again with each one.
function ns.WarmSlot(slot)
    if ns.SlotDataReady(slot) then return false end
    if slot.kind == "item" or slot.kind == "toy" then
        C_Item.RequestLoadItemDataByID(slot.id)
    else
        C_Spell.RequestLoadSpellData(SlotSpellID(slot))
    end
    return true
end

local function SlotCooldown(slot)
    if not slot then return nil end
    local k = slot.kind
    if k == "spell" or k == "mount" or k == "dynamicrez"
       or k == "dynamicprofession" then
        local id
        if k == "mount" then
            -- No falling back to slot.id here: that is a mountID, and looking
            -- a mountID up as a spellID reports some unrelated spell's cooldown.
            id = slot.spellID or select(2, C_MountJournal.GetMountInfoByID(slot.id))
        else
            id = SlotSpellID(slot)
        end
        if id and C_Spell.GetSpellCooldownDuration then
            -- Parenthesised, so only the duration comes back: 12.1 returns a
            -- second value that would land in this function's `start` slot and
            -- hand a boolean to CooldownFrame_Set.
            return (C_Spell.GetSpellCooldownDuration(id))
        end
    elseif k == "item" or k == "toy" then
        if slot.id and C_Item.GetItemCooldown then
            return nil, C_Item.GetItemCooldown(slot.id)
        end
    end
    return nil
end

-- WHETHER an entry writes a number in its corner, and WHAT that number is --
-- deliberately two returns rather than one nilable value. Two things earn a
-- number: a stack of items, and a spell's charges.
--
-- The charge count must never be looked at, not even for truth or for nil.
-- C_Spell.GetSpellCharges is flagged SecretWhenCooldownsRestricted
-- (SpellDocumentation.lua:234), so currentCharges comes back a SECRET number
-- once restrictions are in effect, and touching one from tainted execution
-- throws -- the same wall the spell cooldown hit. So the caller is told
-- separately that there IS a count, and the count itself only ever reaches
-- SetText, which swallows a secret; Blizzard's own action button hands the
-- identical kind of value to the identical call (ActionButton.lua:810).
--
-- What is safe to test is the TABLE the call returns, which is not itself
-- secret: it comes back as nothing for a spell that has no charges at all.
--
-- Neither item call carries a secret flag, so those may be compared -- and
-- have to be, because a count only means something on a stackable item. A
-- Hearthstone writing "1" in its corner is noise.
local function SlotCount(slot)
    if not slot then return false end
    local k = slot.kind

    -- A battle rez is the charge-carrying spell this matters most for: how many
    -- are left is the whole question a raid asks of it.
    if k == "spell" or k == "dynamicrez" then
        local id = SlotSpellID(slot)
        if not id or not C_Spell.GetSpellCharges then return false end
        local charges = C_Spell.GetSpellCharges(id)
        if not charges then return false end
        return true, charges.currentCharges

    elseif k == "item" then
        if type(slot.id) ~= "number" then return false end
        -- Position 8 is the stack size. It is nil until the item's data has
        -- been cached, which costs at most the count on one open -- the
        -- palette repaints from scratch every time it is drawn.
        local stack = select(8, C_Item.GetItemInfo(slot.id))
        if not stack or stack <= 1 then return false end
        return true, C_Item.GetItemCount(slot.id)
    end

    return false
end

-- How an entry that CANNOT be fired right now is tinted, in the three states
-- an action button has always distinguished. The idle and selected tints are
-- multiplied through these, so an unusable entry still reads as selected while
-- saying why it would do nothing.
local USABILITY_TINT = {
    OUTOFRANGE = { 0.90, 0.20, 0.20, false },
    NOPOWER    = { 0.45, 0.45, 1.00, false },
    UNUSABLE   = { 0.45, 0.45, 0.45, true },
}

-- Which of those states an entry is in, or nil for an entry that is fine and
-- for a kind with nothing to say.
--
-- Every call here is secret-SAFE, and that was checked rather than assumed:
-- C_Spell.IsSpellUsable, C_Spell.IsSpellInRange, C_Item.IsUsableItem,
-- C_Item.ItemHasRange and C_Item.IsItemInRange all carry no
-- SecretWhenCooldownsRestricted flag in the generated documentation, unlike
-- the cooldown and charge getters two functions up. So these results may be
-- branched on. Do not add a kind here without checking its getter the same
-- way -- a mount's usability, for one, has to come from the Mount Journal
-- rather than from its summon spell, which is not in the spellbook and
-- answers unusable for every mount.
--
-- Out of range OUTRANKS the other two, matching every action bar: a spell you
-- cannot reach is the thing to say first, and it is the state a step forward
-- fixes.
--
-- Macros, markers and palettes answer nil. A macro's usability is whatever its
-- body resolves to, which is not knowable from here, and tinting one gray on a
-- guess is worse than saying nothing.
--
-- Toys also answer nil. A toy is not a bag item, so C_Item.IsUsableItem says
-- unusable for every toy a player owns, and graying the whole Hearthstones
-- palette is exactly what that produced. The toy box itself draws no
-- usability tint -- Blizzard_ToyBox.lua desaturates only UNCOLLECTED toys --
-- and the cooldown swipe already tells the one thing a toy has to tell.
local function SlotUsability(slot)
    if not slot then return nil end
    local k = slot.kind

    if k == "spell" or k == "dynamicrez" then
        local id = SlotSpellID(slot)
        if not id then return nil end
        if C_Spell.IsSpellInRange(id) == false then return "OUTOFRANGE" end
        local usable, noPower = C_Spell.IsSpellUsable(id)
        if usable then return nil end
        return noPower and "NOPOWER" or "UNUSABLE"

    elseif k == "item" then
        if type(slot.id) ~= "number" then return nil end
        if C_Item.ItemHasRange(slot.id)
           and C_Item.IsItemInRange(slot.id, "target") == false then
            return "OUTOFRANGE"
        end
        local usable, noPower = C_Item.IsUsableItem(slot.id)
        if usable then return nil end
        return noPower and "NOPOWER" or "UNUSABLE"
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
        -- The Toy Box frame hands back cursorType "item", not "toy", so
        -- reclassify here to match what the search picker already stores.
        if PlayerHasToy(itemID) then
            return { kind = "toy", id = itemID }
        end
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
-- One secure button per BOUND palette, indexed the same way. Declared here for
-- the same reason as the three above: PaletteView:ArmedClaim reads a claim's
-- armed state off a palette's own button, and that is defined long before the
-- secure activation section builds any of them.
local secureButtons = {}
local openedAt = 0

-- A held key whose up-event never reaches us (alt-tab, /reload prompt, a
-- taxi takeoff) would otherwise leave the palette on screen forever.
local OPEN_TIMEOUT = 30

-- The same backstop for a LATCHED palette (Toggle Menu Open), which has no key
-- held and is meant to sit there while the player decides. Long enough not to
-- pull the menu out from under that, short enough that one forgotten in a bank
-- does not hold the Select key -- which may well be a mouse button -- for the
-- rest of the session. See the confirm binding in SNIPPET_PRE.
local LATCH_TIMEOUT = 120

-- The mouse-button token the Select key's click arrives under. The palette's own
-- keybind clicks the same button as "LeftButton" (SetOverrideBindingClick's
-- default), so this is the whole of what tells a confirm click apart from a
-- palette-key click inside the snippet, which gets `button` and nothing else.
--
-- A real button name rather than an invented token: RegisterForClicks("AnyDown",
-- "AnyUp") covers it for certain, and the button has EnableMouse(false), so no
-- actual right-click can ever reach it and be mistaken for a confirm.
local CONFIRM_BUTTON = "RightButton"

-- ESCAPE out of a LATCHED menu, under a token of its own on the same button.
--
-- A held palette sends ESCAPE to the shared cancel button, which only raises a
-- flag -- the teardown then rides the key release that is always coming. A
-- latched menu has no such release, so its ESCAPE has to do the closing itself,
-- and doing it from the cancel button's Lua PostClick would leave the bindings
-- and the gates standing for the whole of any fight it happened during: every
-- one of those calls is protected. Routed HERE it is the palette button's own
-- release, so SNIPPET_POST performs the identical teardown it performs for
-- every other close, inside the sandbox, in combat or out.
local CANCEL_BUTTON = "MiddleButton"

-- Selection is drawn with two cues: the icon border takes the selection
-- color, and the entry grows. No additive glow -- at palette scale it bloomed
-- over the neighbouring entries and made the border it was supposed to
-- emphasise harder to read. Border weights are PHYSICAL pixels through the
-- suite's PP border system (PP.CreateBorder on each widget's bhost,
-- PP.UpdateBorder per state in ApplySlotVisual): idle and selected both 2,
-- the armed parent one heavier, drawn INSET over the icon's own edge and
-- crisp at any scale chain -- which a hand-stretched texture ring never was.
local SEL_BORDER = 2
local IDLE_BORDER = 2

-- The entry an ARMED claim hangs off. Selection says where the cursor is; this
-- says which nest is live, and the two part company the moment the cursor moves
-- on into the children -- the entry it came in through has to go on saying so,
-- because it is the only thing on screen that names the nest the release will
-- fire out of.
--
-- Derived from the selection color rather than from a setting of its own: the
-- same hue lifted toward white and drawn a pixel thicker. That reads as "more
-- than selected" at icon size while still sitting next to the selection color,
-- rather than introducing a second color the user would have to learn.
local ARM_BORDER = 3
local ARM_LIFT = 0.55

-- The magnification a selected entry is drawn at: 1, i.e. none -- reverted
-- off with the rest of the selection effects, pending the user's own
-- animation pass. Every call site multiplies by this, so it is the single
-- switch to bring the zoom back (SIZE-based, never scale -- see the note
-- above ApplySlotVisual).
local function SelectedZoom()
    return 1
end

-- Magnification is applied to the entry's SIZE, never its scale. SetPoint
-- offsets are read in the widget's own scaled space, so scaling an entry also
-- multiplies the offset it is anchored at -- and in the arc that offset carries
-- the radius, so selecting an entry threw it outward, out from under the very
-- cursor that had selected it, and the two states then flickered against each
-- other. Growing it in place moves nothing.
--
-- widget.baseSize is the unzoomed size the layout wants, published by whichever
-- geometry pass last placed the entry. Every steered layout rewrites its sizes
-- each frame and applies the zoom itself as it goes; this is what carries the
-- zoom across a selection CHANGE, and it is the whole of the answer on a view
-- that never steers -- the options preview, which draws a static arc.
--
-- armed marks the entry an armed claim hangs off, which may or may not also be
-- the selected one. The zoom stays a selection cue alone: an armed parent the
-- cursor has already left is not what a release would fire.
-- widget.usability is the state PaintCell last read for this cell (see
-- SlotUsability), applied here rather than there because these three branches
-- rewrite the icon's tint on every selection change and would erase it.
local function ApplySlotVisual(widget, selected, armed)
    -- The editor's centred "+" cell is drawn as the suite's picker add
    -- button: dark plate, thin gray border, accent "+" at 0.6 alpha, and on
    -- hover a doubled accent border with the "+" at full alpha -- not as an
    -- entry, which it is not. No zoom either: the add button holds its size
    -- under the cursor.
    if widget.isPlaceholder then
        local ar, ag, ab = 0.047, 0.824, 0.624
        if EllesmereUI.ResolveActiveAccent then ar, ag, ab = EllesmereUI.ResolveActiveAccent() end
        if selected then
            EllesmereUI.PP.UpdateBorder(widget.bhost, 2, ar, ag, ab, 1)
        else
            EllesmereUI.PP.UpdateBorder(widget.bhost, 1, 0.3, 0.3, 0.3, 0.5)
        end
        widget.bg:SetVertexColor(0.08, 0.08, 0.08, 0.6)
        widget.plus:SetTextColor(ar, ag, ab, selected and 1 or 0.6)
        if widget.baseSize then widget:SetSize(widget.baseSize, widget.baseSize) end
        return
    end

    local r, g, b = SelectColor(widget.view:P())
    -- The unusable tint MULTIPLIES whatever the selection state asked for, so
    -- an out-of-range entry the cursor is on still reads as the selected one.
    local tint = USABILITY_TINT[widget.usability or ""]
    local ur, ug, ub = 1, 1, 1
    if tint then ur, ug, ub = tint[1], tint[2], tint[3] end
    widget.icon:SetDesaturated(tint ~= nil and tint[4] or false)
    local t = armed and ARM_BORDER or selected and SEL_BORDER or IDLE_BORDER
    local base = widget.baseSize
    if base then
        local z = selected and SelectedZoom() or 1
        widget:SetSize(base * z, base * z)
    end
    if armed then
        local lr = r + (1 - r) * ARM_LIFT
        local lg = g + (1 - g) * ARM_LIFT
        local lb = b + (1 - b) * ARM_LIFT
        EllesmereUI.PP.UpdateBorder(widget.bhost, t, lr, lg, lb, 1)
        widget.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.9)
        widget.icon:SetVertexColor(ur, ug, ub)
        widget.label:SetTextColor(lr, lg, lb)
    elseif selected then
        EllesmereUI.PP.UpdateBorder(widget.bhost, t, r, g, b, 1)
        widget.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.9)
        widget.icon:SetVertexColor(ur, ug, ub)
        widget.label:SetTextColor(r, g, b)
    else
        EllesmereUI.PP.UpdateBorder(widget.bhost, t, 0, 0, 0, 0.9)
        -- Plate opacity is FIXED -- 0.65 idle, 0.9 selected and armed above
        -- (the Background Opacity setting was removed).
        widget.bg:SetVertexColor(0.05, 0.05, 0.06, 0.65)
        -- Full brightness at idle: the old 0.72 dim was a selection cue, and
        -- selection speaks through the border and the connector line now.
        widget.icon:SetVertexColor(ur, ug, ub)
        widget.label:SetTextColor(0.75, 0.75, 0.75)
    end
end

-- The suite's font, on every string the palette draws.
--
-- The Blizzard font object each string is created from stays the source of its
-- SIZE: the layout is tuned against those sizes, and a re-font is meant to
-- change the typeface and the outline, nothing else. iconText marks the strings
-- that sit ON an icon, which follow the suite's "Outline Icon Text" switch
-- rather than the plain outline mode.
local FONT_KEY = "quickdraw"
local fontStrings = {}

local function ApplyModuleFont(fs)
    local size = fs.eqdFontSize
    if not size or not EllesmereUI.GetFontPath then return end
    -- Snapped to whole physical pixels. A font height is given in the string's
    -- own units and drawn at that height TIMES its effective scale, so a
    -- palette scaled to anything but 1 asks for a fractional pixel height --
    -- and a glyph rasterised between two pixels reads soft and stair-stepped
    -- while the icon art beside it, which is a texture and resamples cleanly,
    -- does not. That is the whole of the pixelated-count report: the icons
    -- were never the problem. PP.perfect is one physical pixel in WoW's
    -- 768-based coordinates, which is what turns a height into pixels and
    -- back. Whole pixels, and never rounded away to nothing.
    local PP = EllesmereUI.PP
    local eff = fs.GetEffectiveScale and fs:GetEffectiveScale()
    if PP and PP.perfect and PP.perfect > 0 and eff and eff > 0 then
        size = max(1, floor(size * eff / PP.perfect + 0.5)) * PP.perfect / eff
    end
    local flags
    if fs.eqdIconText and EllesmereUI.GetIconTextOutlineFlag then
        flags = EllesmereUI.GetIconTextOutlineFlag(FONT_KEY)
    else
        flags = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag(FONT_KEY) or ""
    end
    -- Runtime SetShadowOffset no longer renders on 12.x; the shadow has to be
    -- carried by a FontObject, primed BEFORE the typeface call.
    if EllesmereUI.PrimeFontShadow then
        local useShadow = flags == "" and EllesmereUI.GetFontUseShadow
            and EllesmereUI.GetFontUseShadow()
        EllesmereUI.PrimeFontShadow(fs, useShadow and true or false)
    end
    fs:SetFont(EllesmereUI.GetFontPath(FONT_KEY), size, flags)
end

-- Called once per string, right after it is created from its Blizzard font
-- object, and again for every string whenever the font settings change.
local function AdoptFontString(fs, iconText)
    local _, size = fs:GetFont()
    fs.eqdFontSize = size
    fs.eqdIconText = iconText or nil
    fontStrings[#fontStrings + 1] = fs
    ApplyModuleFont(fs)
end

local function RefreshFonts()
    for i = 1, #fontStrings do ApplyModuleFont(fontStrings[i]) end
end

-- The icon crop, per PAINT rather than per widget: 8% per side (user-tuned
-- past the Action Bars 5.5% default) trims the baked border square action
-- icons carry. The marker textures carry none -- their art runs to the
-- texture's own edge with transparency around it -- so the crop cut into
-- the marker shape itself; they draw at the full rect instead. Keyed off
-- the TEXTURE rather than the slot kind, so a nested menu entry borrowing
-- its first child's marker icon stays whole too. Shared with the options
-- picker's rows, which draw the same icons at list size.
local function ApplyIconCrop(tex, icon)
    -- Atlas-backed icons already have their own UVs and should not be cropped.
    if type(icon) == "table" and icon.atlas then
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end

    if type(icon) == "string"
       and (icon:find("RaidTargetingIcon", 1, true)
            or icon:find("UI-GroupLoot-Pass-Up", 1, true)
            -- The interface panel glyphs, which are drawn to the edge of their
            -- own square the way the marker textures are. The crop is sized
            -- for the border every spell icon carries and would cut into these.
            or icon:find("micromenu", 1, true)) then
        tex:SetTexCoord(0, 1, 0, 1)
    else
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end
ns.ApplyIconCrop = ApplyIconCrop

-- ns-hosted, NOT a file-scope local: this chunk sits at the Lua 5.1 200-local
-- cap and this function was the 200th -- hosting it on ns restores the last
-- slot of headroom. Paint-frequency callers; the ns lookup is free there.
function ns.SetIconTexture(tex, icon)
    if type(icon) == "table" and icon.atlas then
        tex:SetAtlas(icon.atlas, true)
    else
        tex:SetTexture(icon or QUESTION_MARK)
    end
end

local function CreateSlotWidget(view, index)
    local w = CreateFrame("Button", nil, view.frame, "BackdropTemplate")
    w.index = index
    -- Our frame, so the backref is safe to carry. ApplySlotVisual reads the
    -- selection color through it: the color keys are per-menu appearance, and
    -- the widget is the only argument that function gets.
    w.view = view

    w.bg = w:CreateTexture(nil, "BACKGROUND")
    w.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    w.bg:SetAllPoints(w)

    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetAllPoints(w)
    -- The crop is applied per paint -- see ApplyIconCrop.
    w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    w.cd = CreateFrame("Cooldown", nil, w, "CooldownFrameTemplate")
    w.cd:SetAllPoints(w.icon)
    w.cd:SetHideCountdownNumbers(false)
    w.cd:SetDrawEdge(false)

    -- The suite's pixel-perfect border system, INSET: snap-managed strips at
    -- exactly borderSize PHYSICAL pixels whatever the scale chain (the
    -- hand-stretched ring this replaces never rendered crisp), overlaying
    -- the icon's own edge from a host raised above the cooldown swirl.
    -- Per-state weight and color go through PP.UpdateBorder in
    -- ApplySlotVisual; the strips track the widget's rect, so a resized
    -- entry keeps its border without any re-anchor.
    w.bhost = CreateFrame("Frame", nil, w)
    w.bhost:SetAllPoints(w)
    w.bhost:SetFrameLevel(w:GetFrameLevel() + 5)
    EllesmereUI.PP.CreateBorder(w.bhost, 0, 0, 0, 0.9, 2, "OVERLAY", 7)

    -- Stack size or charges, in the corner an action button writes them in.
    -- Its text may be a SECRET value (see SlotCount), so it is SHOWN and
    -- HIDDEN rather than written and cleared: a FontString carrying secret
    -- text refuses text access to tainted callers, and a refused clear would
    -- leave the previous entry's number standing.
    w.count = w:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    w.count:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -1, 2)
    -- Held on BOTH sides, which is the whole width clamp: anchored by one
    -- corner alone a wide count grows until it runs off the icon it belongs
    -- to, and a three-digit stack did. The text cannot be measured to shrink
    -- it instead -- it may be a secret value, and a secret FontString refuses
    -- text access to a tainted caller -- so the width is decided in advance
    -- and the client fits the number into it.
    w.count:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 1, 2)
    w.count:SetJustifyH("RIGHT")
    -- One line whatever it holds: a count wide enough to need the clamp above
    -- would otherwise wrap onto a second line and climb up the icon.
    if w.count.SetWordWrap then w.count:SetWordWrap(false) end
    w.count:Hide()
    AdoptFontString(w.count, true)

    -- "This world marker is on the ground right now", in the corner the count
    -- does not use. Drawn above the border host so a selected entry does not
    -- bury it. Shown only by PaletteView:MarkerPip, which is also what sizes
    -- and colors it; created here unconditionally because a widget is reused
    -- for whatever entry the next open puts in it.
    w.markerPip = w:CreateTexture(nil, "OVERLAY", nil, 7)
    w.markerPip:SetTexture("Interface\\Buttons\\WHITE8X8")
    w.markerPip:SetPoint("TOPLEFT", w, "TOPLEFT", 2, -2)
    w.markerPip:Hide()

    -- "This entry opens a menu", in the corner nothing else uses. Without it a
    -- nested entry is drawn exactly like a plain one until it arms, which is
    -- why the nest used to be previewed faintly instead -- and a preview drawn
    -- over the open nest's own children is what that cost.
    w.nestDots = {}
    for d = 1, 3 do
        local t = w:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:Hide()
        w.nestDots[d] = t
    end

    w.label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    AdoptFontString(w.label)
    w.label:SetPoint("TOP", w, "BOTTOM", 0, -2)
    w.label:SetWidth(96)
    w.label:SetWordWrap(false)

    -- The "+" affordance for an interactive view's trailing placeholder entry.
    -- Created unconditionally; Layout is what decides whether it is ever shown.
    -- Drawn as the suite's picker add button (22pt "+", nudged 1px up) --
    -- ApplySlotVisual's placeholder branch is what colors it as one.
    w.plus = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    AdoptFontString(w.plus)
    w.plus.eqdFontSize = 22
    ApplyModuleFont(w.plus)
    w.plus:SetPoint("CENTER", 0, 1)
    w.plus:SetText("+")
    w.plus:Hide()

    w:EnableMouse(false)
    return w
end

local PaletteView = {}
local PaletteViewMeta = { __index = PaletteView }

-- radius, iconSize, deadZone for this view: the geometry the view was created
-- with when there is one (the options preview fits its own), else the view's
-- own palette -- radius and iconSize are per-menu appearance. The 24 is the
-- dead zone, hardcoded: release inside it cancels, and near the centre the
-- pointer's angle is too unstable to select by.
-- radius, icon size, dead zone. The radius is the ARC's, and it is worked out
-- rather than read: Menu Radius is a MINIMUM, and a ring holding more entries
-- than fit at that distance grows until they no longer touch. That is what
-- lets a menu hold more than the twelve a fixed radius could seat, and it
-- leaves every existing menu exactly where it was -- a count that fits at the
-- setting's own value never reaches the floor.
--
-- shownOverride names the count to measure for, which a caller working out the
-- geometry of a palette this view is not currently drawn as must pass: the
-- view's own shownCount still describes whatever was laid out last. Same
-- reason GridDims takes one.
function PaletteView:Geom(shownOverride)
    if self.opts.geom then return self.opts.geom() end
    local p = self:P()
    if not p then return 100, 40, 24 end
    local radius, iconSize = p.radius or 100, p.iconSize or 40
    if self:LayoutMode() == "ARC" then
        local shown = max(1, shownOverride or self.shownCount or 1)
        if shown > 1 then
            -- The chord between two neighbouring entries is 2R sin(step/2).
            -- Holding that to the separation two entries need and solving for R
            -- gives the smallest ring they do not overlap on. A half-step at or
            -- past a quarter turn is left alone: entries that far apart cannot
            -- crowd, and the sine is on its way back down.
            --
            -- The separation is not one pitch. Entries are SQUARES, and two
            -- axis-aligned squares clear each other only once their centres are
            -- a full icon apart along x or along y -- so a pair whose chord
            -- runs diagonally needs iconSize * root 2 between centres, which is
            -- more than a pitch at the shipped sizes. A ring sized on the pitch
            -- alone therefore still touched at the four diagonals, and only
            -- there, which is exactly what a sixteen-entry ring showed.
            local half = self:ArcGeom(shown) * 0.5
            if half > 0 and half < pi * 0.5 then
                local need = max(iconSize + (p.fanGap or 10), iconSize * 2 ^ 0.5)
                radius = max(radius, need / (2 * sin(half)))
            end
        end
    end
    return radius, iconSize, 24
end

-- The profile as THIS view's palette sees it: its own appearance overrides in
-- front of the profile's values. Every geometry pass reads through here rather
-- than through P(), which is what makes two palettes able to be drawn as two
-- different layouts.
--
-- appIndex is a temporary override for a caller measuring a palette this view
-- is not currently laid out for -- PushPalette does exactly that for every
-- bound palette in turn while the view still holds whatever was last drawn.
function PaletteView:P()
    return PA(self.appIndex or self.paletteIndex)
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
    local p = self:P()
    return self.opts.layout or (p and p.layout) or "ARC"
end

-- Which way a fan runs. Every axis-dependent decision in the file reads this
-- one predicate, so a strip is one layout with an orientation rather than two
-- layouts that happen to share every setting. Meaningless outside a fan, where
-- callers do not ask.
function PaletteView:FanHoriz()
    local p = self:P()
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
    local p = self:P()
    local _, iconSize = self:Geom()
    return iconSize + ((p and p.fanGap) or 10)
end

-------------------------------------------------------------------------------
--  A claim's true ground, as a small set of rects rather than one bounding
--  box -- see the "Arming gates" section further down for what these feed.
--  Shared by both the ARC claims (ChildGeom) and the block-layout ones
--  (CellChildGeom): a nest that breaks out of its parent on one side leaves a
--  bounding box across the two swallowing whatever plain ground of the block
--  sits between them, which is exactly the "dim never backs out" complaint.
--  The true shape is instead the parent's own cell, the nest's own tight box,
--  and a narrow corridor connecting the two -- standing on the block's own
--  ground either side of that corridor is standing outside the nest.
-------------------------------------------------------------------------------

-- Tight bounding box around a set of child boxes, with no parent box folded
-- in -- unlike the old single-rect scheme, this is meant to be paired with a
-- SEPARATE parent box and corridor rather than merged with them.
local function NestBBox(cells)
    local first = cells[1]
    local x0, x1 = first.x - first.hw, first.x + first.hw
    local y0, y1 = first.y - first.hh, first.y + first.hh
    for j = 2, #cells do
        local b = cells[j]
        x0, x1 = min(x0, b.x - b.hw), max(x1, b.x + b.hw)
        y0, y1 = min(y0, b.y - b.hh), max(y1, b.y + b.hh)
    end
    return { x = (x0 + x1) * 0.5, y = (y0 + y1) * 0.5,
             hw = (x1 - x0) * 0.5, hh = (y1 - y0) * 0.5 }
end

-- The rect connecting a claim's parent box to its nest box, that lets
-- crossing the gap between them count as staying on the claim's own ground.
-- axis is the axis the nest's own cells spread ALONG -- every style that
-- hangs its nest off one side of the parent already tags its claim with
-- this, the same convention HaloNest opts out of by setting neither axis nor
-- sign. The corridor runs along the OTHER axis, in the direction sign says
-- the nest lies.
--
-- As WIDE as the wider of the parent cell or the nest box, not one child
-- cell: a natural diagonal reach from the parent toward the nest's own
-- centre drifts outside a one-cell-wide band long before it arrives, and
-- once LeaveSnippet's true-shape test actually runs (see EnsureGates) that
-- reads as having left the claim -- the nest vanishing mid-reach. minWidth
-- is only a floor, for the degenerate case of a single-cell nest whose box
-- is no wider than the corridor itself would otherwise be.
local function CorridorBox(parentBox, nest, axis, sign, minWidth)
    local along, away = "x", "y"
    local hAlong, hAway = "hw", "hh"
    if axis ~= "X" then along, away, hAlong, hAway = "y", "x", "hh", "hw" end

    local pEdge = parentBox[away] + sign * parentBox[hAway]
    local nEdge = nest[away] - sign * nest[hAway]
    local lo, hi = min(pEdge, nEdge), max(pEdge, nEdge)

    local box = {}
    box[along] = parentBox[along]
    box[hAlong] = max(minWidth * 0.5, parentBox[hAlong], nest[hAlong])
    box[away], box[hAway] = (lo + hi) * 0.5, max(0, (hi - lo) * 0.5)
    return box
end

-- One rect covering a nest run AND the ground between it and the parent's own
-- cell: the corridor folded into the run rather than standing beside it. That is
-- what lets a run with cells on more than one side of the block have EVERY side
-- of it reachable -- a reach for a child round the far side of a corner leaves
-- the parent cell diagonally, and a claim with one corridor pointing at one side
-- loses the cursor the moment it aims at another -- without spending a region
-- gate per side on the corridors alone.
--
-- The PARENT'S OWN CELL folded in, rather than a corridor drawn between the two:
-- a rect is convex, so a rect holding both ends of a line holds every point of
-- it, and a reach IS a line -- a hand goes straight at the icon it wants. Any
-- corridor narrower than that leaves some straight reach crossing ground the
-- claim does not hold, however carefully it is aimed: a corridor laid across the
-- gap the two boxes leave in ONE direction is exited by a reach that leaves the
-- parent cell through a different edge.
--
-- What it costs is honest: the sweep from the parent's cell out to a run stands
-- over whatever plain entries lie in it -- for a parent in the middle of a block
-- the ones between it and its lane, which the corridor this replaces covered too
-- (that was as wide as the whole nest), and for a parent on the block's own edge
-- the rest of its own row or column, which the corridor did not. Those entries
-- stay exactly as selectable and as firable as they were; what they no longer do
-- is back the nest out. A run reached by a straight line that breaks halfway is
-- worse than a nest that stays up one entry too long: the break does not cancel
-- anything, it fires whatever the cursor came to rest over instead.
--
-- One kind of entry in that sweep IS allowed to back the nest out: another
-- claim's own entry, which the sweep would otherwise make unreachable while this
-- claim is armed -- its parent gate being dark the whole time. Those cells are
-- taken back out afterwards, one at a time; see ParentHoles.
local function RunReach(parentBox, run)
    return NestBBox({ run, parentBox })
end

-- The overshoot grace, applied to one nest run's own rect. Reaching quickly for
-- a small child icon overruns the run's edge by a few units, and a cursor path
-- sampled once per frame can put a single sample outside it on the way in;
-- either one would otherwise read as having left the claim and vanish the
-- nest mid-reach. A cell's own box is untouched, so this only decides how long the
-- nest STAYS open -- what a release fires still needs the cursor inside a child
-- cell.
--
-- axis and sign are the run's, as ever: the axis its cells spread along and the
-- side of the block it lies on. ALONG the run the grace applies both ways --
-- either end of a run is more run, or empty screen. ACROSS it, only OUTWARD:
-- inward is the block itself, and for a lane hugging it that is a plain entry's
-- own centre less than half an icon away, which a region reaching over would
-- leave unselectable while the nest was up. A nest set a whole band out has the
-- room to spare either way, and nothing wants the inward half of it.
local function GraceBox(box, grace, axis, sign)
    local away, hAway, hAlong = "y", "hh", "hw"
    if axis ~= "X" then away, hAway, hAlong = "x", "hw", "hh" end
    box[hAlong] = box[hAlong] + grace
    box[away] = box[away] + sign * grace * 0.5
    box[hAway] = box[hAway] + grace * 0.5
    return box
end

-- The carve below works in edges; everything else here works in centre and
-- half-extent.
local function BoxEdges(b)
    return b.x - b.hw, b.x + b.hw, b.y - b.hh, b.y + b.hh
end

local function EdgeBox(x0, x1, y0, y1)
    return { x = (x0 + x1) * 0.5, y = (y0 + y1) * 0.5,
             hw = (x1 - x0) * 0.5, hh = (y1 - y0) * 0.5 }
end

local function BoxesMeet(a, b)
    return abs(a.x - b.x) < a.hw + b.hw and abs(a.y - b.y) < a.hh + b.hh
end

local function AnyBoxMeets(b, boxes)
    for j = 1, (boxes and #boxes or 0) do
        if BoxesMeet(b, boxes[j]) then return true end
    end
    return false
end

-- A piece thinner than this holds nothing a cursor could be inside, and would
-- spend one of the REGION_MAX gate slots a piece that matters needs.
local CARVE_MIN = 1

-- One region rect with ONE other claim's parent cell taken out of it, as up to
-- four pieces appended to `out`.
--
-- Why a hole at all: a claim's region sweeps its parent's own row or column (see
-- RunReach), so while claim A is armed its region stands over claim B's parent
-- cell. B's own parent gate is dark for as long as A is armed, and gliding from
-- A's entry straight onto B's leaves no region of A's -- so no OnLeave runs,
-- nothing disarms, and B cannot be reached at all without leaving the row first.
-- Taking B's cell out of A's coverage puts a real boundary there: the glide
-- leaves an rgate at the hole's edge, LeaveSnippet's geometric re-test answers
-- "outside", and its re-arm hands the claim over.
--
-- splitY says which axis the FULL-WIDTH slabs are cut on, and the caller sets it
-- from the run's own axis so the slab that survives whole is the one holding the
-- run: a hole is always a cell INSIDE the block, and the run lies beyond the
-- block along the region's away axis, so cutting that axis first leaves every
-- child in one piece rather than sliced into per-column strips.
local function CarveBox(out, b, hole, splitY)
    local bx0, bx1, by0, by1 = BoxEdges(b)
    local hx0, hx1, hy0, hy1 = BoxEdges(hole)
    if hx1 <= bx0 or hx0 >= bx1 or hy1 <= by0 or hy0 >= by1 then
        out[#out + 1] = b
        return
    end
    hx0, hx1 = max(hx0, bx0), min(hx1, bx1)
    hy0, hy1 = max(hy0, by0), min(hy1, by1)
    if splitY then
        if hy0 - by0 >= CARVE_MIN then out[#out + 1] = EdgeBox(bx0, bx1, by0, hy0) end
        if by1 - hy1 >= CARVE_MIN then out[#out + 1] = EdgeBox(bx0, bx1, hy1, by1) end
        if hx0 - bx0 >= CARVE_MIN then out[#out + 1] = EdgeBox(bx0, hx0, hy0, hy1) end
        if bx1 - hx1 >= CARVE_MIN then out[#out + 1] = EdgeBox(hx1, bx1, hy0, hy1) end
    else
        if hx0 - bx0 >= CARVE_MIN then out[#out + 1] = EdgeBox(bx0, hx0, by0, by1) end
        if bx1 - hx1 >= CARVE_MIN then out[#out + 1] = EdgeBox(hx1, bx1, by0, by1) end
        if hy0 - by0 >= CARVE_MIN then out[#out + 1] = EdgeBox(hx0, hx1, by0, hy0) end
        if by1 - hy1 >= CARVE_MIN then out[#out + 1] = EdgeBox(hx0, hx1, hy1, by1) end
    end
end

-- A hole pulled back off this claim's OWN children, or nil when there is no
-- hole left worth punching. A child cell that stands over a neighbouring
-- claim's cell has to WIN there -- it is drawn there, and a hole under it would
-- make it unselectable -- but a child that merely grazes the cell must not cost
-- the whole hole: a lane hugs the block so closely that its cells reach back
-- over the outer row's own boxes by half a gap, so every hole a lane wants would
-- otherwise be refused on a sliver.
--
-- Each pass gives away the one side a child has got LEAST far in through, which
-- is the smallest concession that answers that child. What must survive it is
-- the neighbour's own CENTRE: that is where a cursor aimed at the neighbour's
-- icon lands, and the hole exists so that landing there is outside this claim.
local function ClipHole(hole, cells)
    local x0, x1, y0, y1 = BoxEdges(hole)
    -- One side given away per pass, so four passes per child is the most that
    -- can be asked of it -- plus the pass that finds nothing left to answer.
    for _ = 1, 4 * (cells and #cells or 0) + 1 do
        local best, bx0, bx1, by0, by1
        for j = 1, (cells and #cells or 0) do
            local qx0, qx1, qy0, qy1 = BoxEdges(cells[j])
            if qx1 > x0 and qx0 < x1 and qy1 > y0 and qy0 < y1 then
                local d = min(qx1 - x0, x1 - qx0, qy1 - y0, y1 - qy0)
                if not best or d < best then
                    best, bx0, bx1, by0, by1 = d, qx1, qx0, qy1, qy0
                end
            end
        end
        if not best then
            local h = EdgeBox(x0, x1, y0, y1)
            -- The centre, with room around it: a hole clipped down to a line
            -- through the neighbour's icon is not somewhere a hand can land.
            if abs(h.x - hole.x) + CARVE_MIN <= h.hw
               and abs(h.y - hole.y) + CARVE_MIN <= h.hh then
                return h
            end
            return nil
        end
        if best == bx0 - x0 then x0 = bx0
        elseif best == x1 - bx1 then x1 = bx1
        elseif best == by0 - y0 then y0 = by0
        else y1 = by1 end
        if x1 - x0 < CARVE_MIN or y1 - y0 < CARVE_MIN then return nil end
    end
    return nil
end

-- Does this hole stand STRAIGHT OUT from the parent, in the direction its own
-- children lie? Then it is the one piece of ground the nest cannot be reached
-- across, and the nest keeps it: a claim whose entry has another claim's entry
-- between it and its own run -- the middle column of a block, all three of them
-- nesting -- would otherwise have every child of its middle nest cut off, the
-- reach handing the claim over before it arrived. The swap in that one direction
-- is what gives way instead, and it is still there the way round the block. A
-- hole to the SIDE of the parent blocks nothing and is carved as normal, which is
-- the case the carve exists for.
--
-- The claim's OWN side only -- groups[1], the nearest one, which PerimeterNest
-- has already sorted to the front -- not every side a long run wrapped onto. The
-- tail of a wrapped run reaches back past the parent's neighbours, and protecting
-- those directions too would leave a block whose neighbouring entries both nest
-- with no hole anywhere and no swap at all. Reaching a wrapped cell out past
-- another claim's entry hands the claim over instead, which is the trade the carve
-- is for; what must not happen is a nest with no way in.
local function BlocksReach(c, hole)
    local pb = c.parentBox
    local side = (c.groups and c.groups[1]) or c
    local axis, sign = side.axis, side.sign
    if not axis then return false end
    local away, halong = "y", "hw"
    if axis ~= "X" then away, halong = "x", "hh" end
    local along = (away == "y") and "x" or "y"
    return abs(hole[along] - pb[along]) < hole[halong] + pb[halong]
           and sign * (hole[away] - pb[away]) > 0
end

-- Every OTHER claim's parent cell, clipped off this claim's own children.
local function ParentHoles(claims, i)
    local c, holes = claims[i], nil
    for j = 1, #claims do
        local h = (j ~= i) and claims[j].parentBox or nil
        if h and BlocksReach(c, h) then h = nil end
        if h then
            if AnyBoxMeets(h, c.cells) then h = ClipHole(h, c.cells) end
            if h then
                holes = holes or {}
                holes[#holes + 1] = h
            end
        end
    end
    return holes
end

-- Is this piece ground the claim already holds? Every side of a run folds the
-- parent's own cell in (see RunReach), so the sides overlap heavily around it and
-- carving each of them splits the same ground into pieces again and again -- and
-- a piece straddling two rects the claim already has is nobody's subset. Answered
-- by subtracting what is already there and asking whether anything survives, so
-- that costs no more code than the carve itself. A gate spent on ground the claim
-- holds anyway is a gate a piece that matters may not get.
local function Covered(b, regions)
    local pieces = { b }
    for r = 1, #regions do
        local kept = {}
        for i = 1, #pieces do CarveBox(kept, pieces[i], regions[r], true) end
        pieces = kept
        if #pieces == 0 then return true end
    end
    return false
end

-- Append one region rect to a claim, carved. The pieces holding one of this
-- claim's own children come first: PushPalette writes only REGION_MAX of them,
-- so an overflow drops the tail, and a dropped piece with a child under it would
-- take that child off the claim's ground entirely.
local AddRegion
do
-- Do these two boxes share a stretch of EDGE, overlapping or merely abutting?
-- BoxesMeet answers the other question -- is one box standing over the other --
-- and a corridor never is: CorridorBox starts it at the parent cell's own outer
-- edge, so the two touch along that whole edge and overlap by nothing at all.
-- Read through BoxesMeet, a corridor therefore looked disconnected from the very
-- cell it leads out of.
--
-- A shared edge and not a shared CORNER: contact at one point is not ground a
-- cursor can cross, and a piece reachable only past a corner is exactly what the
-- filter below is there to drop. So one axis must genuinely overlap while the
-- other is allowed to touch.
--
-- The tolerance is for the touch itself. Two edges that meet by construction
-- still arrive here through different arithmetic -- a centre and a half-extent
-- recovered from a pair of edges -- and a boundary this rests on cannot be left
-- to land on the exact same float twice.
--
-- Inside the block with its only caller, which is what keeps it off the main
-- chunk: this file sits within a couple of Lua's ceiling of 200 locals.
local function BoxesTouch(a, b)
    local dx, dy = abs(a.x - b.x), abs(a.y - b.y)
    local sx, sy = a.hw + b.hw, a.hh + b.hh
    return (dx < sx and dy <= sy + 1e-4)
        or (dy < sy and dx <= sx + 1e-4)
end

function AddRegion(c, box, axis, holes)
    if not holes then
        c.regions[#c.regions + 1] = box
        return
    end
    local pieces = { box }
    for hi = 1, #holes do
        local kept = {}
        for pi = 1, #pieces do
            CarveBox(kept, pieces[pi], holes[hi], axis ~= "Y")
        end
        pieces = kept
    end
    for pass = 1, 2 do
        for pi = 1, #pieces do
            local b = pieces[pi]
            local holds = AnyBoxMeets(b, c.cells)
            -- A piece that holds no child of this claim and does not touch its
            -- parent cell either is on the FAR side of a hole, and the only way
            -- onto it is across that hole -- which hands the claim over before
            -- the cursor arrives. Keeping it would spend a gate on ground this
            -- claim can never be armed on.
            --
            -- Touching is the whole test, so it is asked with BoxesTouch. The
            -- corridor is the piece that turns on this: it abuts the parent cell
            -- along a full edge and overlaps it by nothing, so a strict test
            -- dropped the one rect covering the ground between an entry and its
            -- own nest -- and only ever where a second claim put a hole in play,
            -- which is why one nesting entry behaved and two did not.
            if holds == (pass == 1)
               and (holds or BoxesTouch(b, c.parentBox))
               and not Covered(b, c.regions) then
                c.regions[#c.regions + 1] = b
            end
        end
    end
end
end

-- Nested geometry for one palette. Returns an array of CLAIMS -- one per slot
-- that opens a palette -- or nil when nothing in it nests:
--
--   parent   the slot index the children hang off
--   palette  the palette index they come from
--   slots    the child slots themselves, already capped at what this view's
--            layout can seat (see NestChildCap)
--   n        how many
--   angle    the parent entry's own angle                     } arc only
--   half     the half-angle of the room the rings may spread into } arc only
--   ground   the claim's own ground for the DISARM test, as a beam out of the
--            parent entry and a wedge past the entry ring     } arc only
--   rows     concentric rings of children, hugging the arc's own ring;
--            { radius, step, n, base, start, lo, hi } each -- start is the
--            CENTRE angle of that ring's first child, lo/hi the radial band
--            it answers to, hi nil on the outermost ring    } arc only
--   radius   the outermost ring's radius, for sizing the frame } arc only
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
-- How much of the arc a claim's children may spread along: up to
-- arcChildMaxSpan, whatever its parent's own sector is worth. Child sectors
-- do NOT have to partition the plane against their neighbours: a claim
-- answers a release only while it is armed, and only the cursor's passing
-- through that parent entry arms it, so ground two claims' children both
-- cover is never ambiguous -- at most one of them is live. arcChildOverflow
-- decides whether the widening is allowed onto a neighbouring CLAIM's ground
-- at all:
--
--   NONE      stop at the midpoint to the nearest other claim, so no two
--             nests are ever drawn over one another
--   MIDPOINT  spend the whole span, overlapping other nests if it comes to it
--
-- Both may cross the PLAIN entries in between: those keep answering their own
-- angles whenever nothing is armed, and give them up only for as long as a
-- nest reaching over them is open.
--
-- More children than the span can hold is answered by RINGING them: a claim's
-- children hug the arc's own ring, spaced roughly a child pitch apart, and a
-- ring with no room left spills the rest into a second ring one child pitch
-- further out rather than growing its own radius until the angle buys enough
-- room, which is unbounded.
function PaletteView:ChildGeom(shown, slots)
    local p = self:P()
    if not p or not slots or shown < 1 then return nil end
    -- An editor draws no nests. What a nested entry holds is that palette's own
    -- business -- switch to it and it is the whole preview -- and drawing every
    -- nest at once buries the palette actually being arranged. It would also
    -- make the preview budget space for a reach it is not showing, shrinking the
    -- palette under the cursor to leave room for entries that are not there.
    if self.opts.interactive then return nil end

    -- Claimants in entry order first: how much room each one may take depends
    -- on where the next one sits, so none of them can be sized on its own.
    --
    -- NestChildCap's rule, asked of the view's own predicates rather than of
    -- the stored profile so a preview that pinned its layout seats what the
    -- layout it is showing can seat. Keep the two in step: this is the copy the
    -- LIVE menu uses, and it went on capping the arc at eight for a whole
    -- release after the other one stopped.
    local cap = (self:IsGrid() and p.gridNestStyle == "HALO")
        and MAX_CHILDREN or MAX_SLOTS
    local claims
    for i = 1, shown do
        local kids = ChildSlots(ChildIndex(slots[i]), cap)
        if kids and #kids > 0 then
            claims = claims or {}
            claims[#claims + 1] = { parent = i, n = #kids, slots = kids,
                                    palette = ChildIndex(slots[i]) }
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
    local radius, iconSize = self:Geom(shown)
    -- Scaled by whatever this view scaled its geometry by, recovered from the
    -- icon size Geom handed back -- the same recovery the hub logo makes. The
    -- radius already carries that factor; a band read at its literal profile
    -- size would not, and the options preview would then draw its nests at
    -- full distance around a palette fitted to two-thirds.
    local base = p.iconSize or 40
    local k = (base > 0) and (iconSize / base) or 1
    local band = max(0, p.nestBand or NEST_BAND_DEFAULT) * k
    local gap  = ((p and p.fanGap) or 10) * k
    -- Nested entries are drawn smaller than the palette's own, so a nest reads
    -- as subordinate to the entry it hangs off rather than as a second ring of
    -- equals. It costs nothing in the hit test: the sectors are angular, and an
    -- icon's size has no part in deciding which one the cursor is in.
    local childIcon = iconSize * min(1, max(0.4, p.nestScale or 0.8))
    local childPitch = childIcon + gap
    local capHalf = min(180, max(10, p.arcChildMaxSpan or 90)) * pi / 180 * 0.5
    -- Anything that is not the one opt-in value keeps clear of other claims,
    -- so a saved profile that never set this reads as the cautious side.
    local keepClear = p.arcChildOverflow ~= "MIDPOINT"
    local count = #claims

    -- Angles for all of them before any of them is sized: a claim keeping clear
    -- of its neighbours measures against the claim either side of it, and half
    -- of those sit later in the array.
    for i = 1, count do
        claims[i].angle = arcStart + (claims[i].parent - 1) * step
    end

    -- Both icons' halves plus the gap, so the band the user sets is the space
    -- actually seen between the palette's own ring and the first ring of
    -- children -- the ring every claim's children start hugging from.
    local inner = radius + iconSize * 0.5 + childIcon * 0.5 + band

    for i = 1, count do
        local c = claims[i]
        -- The whole cap by default. NONE stops at the midpoint with the nearest
        -- CLAIMANT either side, so two nests never share ground; a lone
        -- claimant on a full circle has no neighbour to meet, and on an open
        -- arc the ends are free space.
        local half = capHalf
        if keepClear and count > 1 then
            local nxt  = claims[i + 1] and claims[i + 1].angle
                or (full and (claims[1].angle + TWO_PI))
            local prev = claims[i - 1] and claims[i - 1].angle
                or (full and (claims[count].angle - TWO_PI))
            if nxt  then half = min(half, (nxt - c.angle) * 0.5) end
            if prev then half = min(half, (c.angle - prev) * 0.5) end
        end
        -- Never NARROWER than the parent's own sector: a claim always has at
        -- least the room the entry it hangs off already owns.
        half = max(half, step * 0.5)

        c.icon = childIcon
        c.half = half
        -- Halfway across the gap: clear of the parent's own icon, short of the
        -- first ring of children. The parent entry keeps everything inside
        -- this.
        c.band = radius + iconSize * 0.5 + band * 0.5

        -- Ring the children rather than pushing them out: each ring sits one
        -- child pitch further out than the last, its children spaced roughly a
        -- pitch apart along it, and a ring with no room left for the rest
        -- spills them into the next ring instead of growing its own radius.
        -- The room is the whole of c.half, so a claim whose children fit
        -- inside the span cap stays ONE ring however wide that has to be.
        -- MAX_CHILD_ROWS caps how many rings a claim may spill into -- past it
        -- the last ring simply takes everyone still waiting, however crowded
        -- that makes it, which is the same trade the old radius clamp made
        -- except it no longer drifts the children away from the arc to make
        -- it.
        local rows, placed, ri = {}, 0, 0
        while placed < c.n and ri < MAX_CHILD_ROWS do
            local rr = inner + ri * childPitch
            -- The arc length one child pitch buys at this ring's radius, in
            -- radians -- further out, the same angle spans more distance, so
            -- fewer degrees are needed to keep neighbours a pitch apart.
            local angStep = childPitch / rr
            local capacity = (ri == MAX_CHILD_ROWS - 1) and (c.n - placed)
                or max(1, floor((half * 2) / angStep + 1e-6) + 1)
            local m = min(c.n - placed, capacity)
            rows[#rows + 1] = { radius = rr, step = angStep, n = m, base = placed,
                                 start = c.angle - (m - 1) * 0.5 * angStep }
            placed = placed + m
            ri = ri + 1
        end
        -- The boundary between two rings is their midpoint radius: past it,
        -- the further ring's children are the nearer ones underfoot. The
        -- first ring's inner edge is c.band, the parent/child hand-off
        -- already computed above; the last ring has no outer edge at all.
        rows[1].lo = c.band
        for r = 2, #rows do
            local mid = (rows[r - 1].radius + rows[r].radius) * 0.5
            rows[r - 1].hi, rows[r].lo = mid, mid
        end
        c.rows = rows
        -- The outermost ring's radius, so Layout can size the frame to hold
        -- every ring rather than just the first.
        c.radius = rows[#rows].radius

        -- The ground the DISARM test keeps this claim armed on, in two pieces
        -- (LeaveSnippet, ANGULAR branch). Neither is the release's own per-ring
        -- resolution, and both are supersets of it, which is the only property
        -- that has to hold: a claim must never disarm anywhere its own release
        -- would still fire one of its children.
        --
        -- WEDGE, from the entry ring's outer edge outward. Its half-angle is
        -- the widest RING's: a ring answers the angles its children's own
        -- sectors cover, n * step wide, so the widest one covers every angle
        -- the release could resolve to a child here -- and one wedge for the
        -- lot leaves no gap between two rings of unequal width for the cursor
        -- to disarm in on its way out to the further one. Floored at the
        -- parent's own sector, which is the wider of the two on a claim of one
        -- or two children, and at the parent icon's own angular width, so a
        -- palette of one entry on an open arc (step 0) still has a wedge.
        -- Plus a grace of half a child sector, so overshooting the edge child
        -- by a hair leaves the nest open to correct back into rather than
        -- closing it for good; the grace deliberately does NOT widen the
        -- release, which still resolves the rings exactly, so the graced
        -- sliver fires the plain entry behind it while the nest stays live.
        --
        -- BEAM, out of the parent entry itself, for everything nearer than
        -- that. The wedge alone is not enough and the parent's icon box is not
        -- enough either: the reach for a child is a straight line from the
        -- parent, so it passes BESIDE the icon before it gets out past the
        -- entry ring -- a nest spread 44 degrees either side of a 30-degree
        -- entry is crossed at 11 to 25 degrees while still inside the ring's
        -- own radius -- and that ground answers to no ring and no icon box.
        -- The beam is a half-icon wide at the palette's centre and opens at
        -- the parent's own sector angle, which is what keeps it clear of the
        -- NEIGHBOURING entries' icons: the room between the beam's edge and a
        -- neighbour's centre works out to radius * tan(step / 2) - icon / 2,
        -- i.e. the beam misses the neighbour exactly when the two entries'
        -- icons do not overlap in the first place. That clearance is what lets
        -- a neighbouring claim take over -- gliding onto its entry leaves this
        -- ground, which disarms, which puts its parent gate back up.
        local wide, coarsest = 0, 0
        for r = 1, #rows do
            wide = max(wide, rows[r].n * rows[r].step * 0.5)
            coarsest = max(coarsest, rows[r].step)
        end
        c.ground = {
            -- Radial projection onto the parent's own axis, not plain
            -- distance: the beam is measured along and across that axis.
            ax = sin(c.angle), ay = cos(c.angle),
            -- Inward of the icon's inner face is a retreat toward the centre,
            -- and disarming there is what hands the other claims their gates
            -- back.
            lo = radius - iconSize * 0.5,
            -- Where the wedge takes over from the beam. Past the entry ring
            -- rather than past the icons ON it, and that is the whole margin
            -- there is to work with: a nest spread wider than its parent's
            -- sector is reached by a line that crosses its NEIGHBOURS' icons,
            -- so some of that ground has to answer to the armed claim or the
            -- reach breaks -- while a neighbouring entry's own CENTRE sits at
            -- the ring itself and so is always outside the wedge, whatever the
            -- step. That is what a handoff needs: gliding onto another claim's
            -- entry leaves this ground, which disarms, which puts that claim's
            -- parent gate back up.
            edge = radius + iconSize * 0.25,
            beam = iconSize * 0.5,
            -- Clamped short of a quarter turn: tan runs away at one, and a
            -- palette of two entries on a full circle has a half-sector of
            -- exactly that. Past 60 degrees the wedge covers those angles
            -- anyway everywhere it applies.
            slope = tan(min(step * 0.5, pi / 3)),
            half = max(wide + coarsest * 0.5, step * 0.5,
                       (iconSize * 0.5) / max(1, radius)),
        }

        -- The parent's own icon box, for the arming gate (see EnsureGates)
        -- and the disarm test alike -- standing on it always counts as this
        -- claim's ground. ChildRingPos wants c.rows, which is why this waits
        -- until here rather than running alongside the loop above.
        local px, py = radius * sin(c.angle), radius * cos(c.angle)
        c.parentBox = { x = px, y = py, hw = iconSize * 0.5, hh = iconSize * 0.5 }

        -- What the disarm test actually decides an arc claim's ground by is
        -- polar -- c.ground above. The rects
        -- built here are only EVENT surfaces for the real gate frames, which
        -- can only ever be rects: generous rather than tight is fine for
        -- them, because the geometric test that decides whether leaving one
        -- actually disarms never trusts their bounds, only the wedge.
        local ringBoxes = {}
        for j = 1, c.n do
            local r, a = self:ChildRingPos(c, j)
            local cx, cy = r * sin(a), r * cos(a)
            ringBoxes[j] = { x = cx, y = cy, hw = c.icon * 0.5, hh = c.icon * 0.5 }
        end
        local nest = NestBBox(ringBoxes)

        -- The corridor's break-out direction is whichever screen axis the
        -- parent's own radial position leans further along -- an
        -- approximation of "straight out from the centre", which is all a
        -- rect can ever be for a wedge.
        local axis, sign
        if abs(px) >= abs(py) then axis, sign = "Y", (px >= 0) and 1 or -1
        else axis, sign = "X", (py >= 0) and 1 or -1 end
        local corridor = CorridorBox(c.parentBox, nest, axis, sign, childPitch)

        c.regions = { c.parentBox, nest, corridor }
    end

    return claims
end

-- An arc claim's j-th child (1-based across the whole claim, not just one
-- ring) -> the radius and angle it is drawn at. Read by the drawing and by
-- the needle's direction; HitTest walks the rings the other way, from a
-- radius to a ring, but lands on this same row.start/row.step to turn the
-- local index it finds back into the child it belongs to.
function PaletteView:ChildRingPos(c, j)
    local rows = c.rows
    for r = 1, #rows do
        local row = rows[r]
        if j <= row.n then
            return row.radius, row.start + (j - 1) * row.step
        end
        j = j - row.n
    end
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
    local p = self:P()
    local deg  = min(360, max(30, (p and p.arcSpan) or 360))
    local rot  = ((p and p.arcRotation) or 0) * pi / 180

    if deg >= 359.5 then
        return (shown > 0) and (TWO_PI / shown) or 0, rot, true
    end

    local span = deg * pi / 180
    local step = (shown > 1) and (span / (shown - 1)) or 0
    return step, rot - span * 0.5, false
end

-- The pointer-steered fan is RETIRED from the UI: a fan is always
-- wheel-steered, with Select Action with Mouse on top (the Steering setting
-- was removed). The grid-one-deep machinery it routed to stays for the grid
-- itself; a fanInput key left in stored profiles is never read.
function PaletteView:IsHoverFan()
    return false
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
-- The size and alpha falloffs in force: both HARDCODED to 1 -- flat size,
-- full alpha, no proximity effects (the settings were removed pending the
-- user's own animation pass). 1 is a no-op everywhere it lands: decay ^ k
-- stays 1 at every k, the min-scale/alpha floors never engage, and
-- FanOffset's even-spacing branch takes the strip out to full pitch. This
-- pair is the single place to bring the falloffs back.
local function FalloffRatios()
    return 1, 1
end
ns.FalloffRatios = function(paletteIndex) return FalloffRatios(PA(paletteIndex)) end

-- Steps, flattened over the entry's own ground. Raw nearness is measured to an
-- entry's CENTRE, so the entry under the cursor grew and shrank as the cursor
-- crossed it -- it was at its largest only dead in the middle, and the one thing
-- on screen that should hold still while you settle on it was the one thing
-- moving. Everything inside an entry's own ground now reads as zero steps away.
--
-- Ground is half a step each side, which is exactly what the hit tests hand an
-- entry: half a step of arc, half a cell of grid. So the entry drawn at full
-- size and full alpha is precisely the entry a release would fire.
--
-- The identity past one full step is what keeps the settled drawing untouched:
-- an entry a whole step out is still decay ^ 1, two steps decay ^ 2, a grid
-- diagonal decay ^ sqrt 2. Only the half-step band between an entry's edge and
-- its neighbour's centre is redrawn, at twice the rate, and the strip -- whose
-- entries come to rest at whole steps -- never leaves the identity at all.
--
-- Fed ONE AXIS AT A TIME on the grid, then combined: flattening the 2D distance
-- instead would leave the corners of a cell outside the flat disc, still
-- breathing, and would pull the diagonal neighbour in off sqrt 2.
local function FalloffK(k)
    if k <= 0.5 then return 0 end
    if k >= 1 then return k end
    return (k - 0.5) * 2
end

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
--
-- HALF the count, from the full count the caller counted: the strip is cyclic,
-- and ApplyFanGeometry folds every offset into [-shown/2, shown/2], so the
-- entry drawn farthest from the centre is half the palette out and not the
-- whole of it. Measured over the whole count the strip was fitted to about
-- twice its own drawn length -- the preview shrank its icons to half what the
-- panel had room for. The hover reach next door counts the same way.
function ns.FanReach(count, iconSize, gap, decay)
    return FanOffset(count * 0.5, iconSize, gap, decay, FAN_EDIT_MIN_SCALE)
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
    local p = self:P()
    if not p or not self:IsFan() then return end

    local shown = self.shownCount
    if shown < 1 then return end

    local _, iconSize = self:Geom()
    local gap    = p.fanGap or 10
    local decay, aDecay = FalloffRatios(p)
    local minS   = p.fanMinScale or 0.30
    local minA   = p.fanMinAlpha or 0.12
    if self.opts.interactive then
        minS = max(minS, FAN_EDIT_MIN_SCALE)
        minA = max(minA, FAN_EDIT_MIN_ALPHA)
    end
    local horiz  = self:FanHoriz()
    -- The editor windows exactly like play now: it draws the centre plus
    -- fanVisible each side and the wheel scrolls the rest into view, so what
    -- the preview shows is what a hold shows.
    local window = p.fanVisible or 2

    local frame  = self.frame
    local center = self.fanVisual or 1
    local half   = shown / 2
    -- The editor drops a horizontal strip a little to make room for its add
    -- button above the line -- see fanSide in Layout. Zero everywhere else.
    local crossOff = self._fanCrossOff or 0

    -- Half the width the selected entry gains, added to every offset past the
    -- centre so magnifying it cannot close the gaps under its neighbours. A
    -- CONSTANT, applied whichever entry is selected: making it follow the
    -- selection would reflow the whole strip on every step.
    --
    -- Ramped in over the first step rather than switched on the moment k leaves
    -- 0 -- see the offset below. The strip settles onto its entry CONTINUOUSLY,
    -- so a term that appeared the instant k was nonzero held the centre entry a
    -- few pixels out for the whole slide and then dropped it back as k reached
    -- exactly 0: the whole strip came to rest and the middle icon twitched a
    -- moment later, against the direction of travel. At every integer k the
    -- ramp is already at full extra, so nothing about the settled strip moves.
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
        -- The strip FLOWS at its ends instead of popping: an entry keeps
        -- drawing for one slot past the last settled one, its alpha fading
        -- to exactly zero at the first slot a settled strip hides -- alpha
        -- as the mask. A slide therefore carries the incoming icon in from
        -- nothing and the outgoing one out to nothing, while a SETTLED
        -- strip shows precisely the set it always did at full strength, so
        -- the hover and release tests -- untouched -- keep firing exactly
        -- what is drawn solid. floor()ed off the cull's own old bound so a
        -- legacy fractional stored window keeps its drawn set too.
        local edge = floor(window + 0.5) + 1 - k
        if edge <= 0 then
            w:Hide()
        else
            local s   = max(minS, decay ^ k)
            local off = FanOffset(k, iconSize, gap, decay, minS)
            off = off + extra * min(1, k)
            if d < 0 then off = -off end

            w:SetAlpha(min(1, edge) * max(minA, aDecay ^ k))
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
                w:SetPoint("CENTER", frame, "CENTER", off, crossOff)
            else
                w:SetPoint("CENTER", frame, "CENTER", crossOff, -off)
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
--
-- The dim only lands once the nest's gate is actually armed (see ArmedClaim),
-- meaning the cursor has gone through the parent entry itself -- which is
-- worth a clearer break between "the nest you are in" and "the palette
-- behind it".
local NEST_DIM_ALPHA = 0.15
local NEST_DIM_SCALE = 0.7

-- What an UNARMED nest is drawn at while the selection sits on its parent. Its
-- children are placed and visible, so the palette still says that this entry
-- opens a nest and where that nest will appear -- but none of them can be fired
-- until a gate arms the claim, so they are drawn as something that has not
-- happened yet. Drawn at full strength they promised a live nest and then
-- answered nothing, which read as the sub-palette being broken.
--
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
    local p = self:P()
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
-- them is shorter than the path between them by up to a third. An arc of the
-- same radius as the band is deep spends the path length the turn needs, so a
-- run keeps the spacing it asked for as it wraps instead of bunching at the
-- bend. That is all the rounding buys: the icons drawn on those cells can still
-- run into each other across a turn, and PerimeterNest is where they are sized
-- down until they do not.
local function PerimeterSpan(HX, HY, R)
    local sx, sy = HX * 2 - R * 2, HY * 2 - R * 2
    local arc = pi * 0.5 * R
    return sx, sy, arc, 2 * (sx + sy) + 4 * arc
end

-- Also returns the OUTWARD normal, which is how a nest deep enough to need a
-- second row finds where to put it: one row further out along the normal keeps
-- the rows square with each other on a straight edge and fanned around a corner.
local function PerimeterPoint(t, HX, HY, R)
    local sx, sy, arc, L = PerimeterSpan(HX, HY, R)
    t = t % L
    if t < sx then return -HX + R + t, HY, "X", 1, 0, 1 end
    t = t - sx
    if t < arc then
        local a = t / R
        -- Half a turn each: a cell more than halfway round a corner belongs to
        -- the side it is heading onto, so its box lies across the run it is
        -- about to join rather than across the one it has left.
        local ax = (a >= pi * 0.25) and "Y" or "X"
        return HX - R + R * sin(a), HY - R + R * cos(a), ax, 1, sin(a), cos(a)
    end
    t = t - arc
    if t < sy then return HX, HY - R - t, "Y", 1, 1, 0 end
    t = t - sy
    if t < arc then
        local a = t / R
        local ax, sg = "Y", 1
        if a >= pi * 0.25 then ax, sg = "X", -1 end
        return HX - R + R * cos(a), -HY + R - R * sin(a), ax, sg, cos(a), -sin(a)
    end
    t = t - arc
    if t < sx then return HX - R - t, -HY, "X", -1, 0, -1 end
    t = t - sx
    if t < arc then
        local a = t / R
        local ax = (a >= pi * 0.25) and "Y" or "X"
        return -HX + R - R * sin(a), -HY + R - R * cos(a), ax, -1, -sin(a), -cos(a)
    end
    t = t - arc
    if t < sy then return -HX, -HY + R + t, "Y", -1, -1, 0 end
    t = t - sy
    local a = t / R
    local ax, sg = "Y", -1
    if a >= pi * 0.25 then ax, sg = "X", 1 end
    return -HX + R - R * cos(a), HY - R + R * sin(a), ax, sg, -cos(a), sin(a)
end

-- The parameter that advances a run one child pitch of GROUND from ta, not one
-- child pitch of path. The two agree along a straight edge. Around a turn the
-- straight line between two cells is shorter than the path between them, so a
-- run spaced by path alone lands the pair straddling the corner nearer each
-- other than it asked -- near enough, at the radius this band can afford, that
-- their icons collide and the shrink pass at the bottom of PerimeterNest takes
-- the whole run down with them. The step is measured the way overlap is --
-- the wider axis of the two -- so the icons it separates clear at full size
-- however the turn lies between them.
local function PerimeterStep(ta, HX, HY, R, pitch)
    local ax, ay = PerimeterPoint(ta, HX, HY, R)
    local dt = pitch
    -- The point never outruns the parameter, so growing the guess by the
    -- shortfall cannot overshoot, and each round closes most of what is left:
    -- a straight edge is exact on the first try, a turn settles within a
    -- fraction of a pixel well inside the bound.
    for _ = 1, 8 do
        local bx, by = PerimeterPoint(ta + dt, HX, HY, R)
        local sep = max(abs(bx - ax), abs(by - ay))
        if sep >= pitch - 0.5 then break end
        dt = dt + (pitch - sep)
    end
    return dt
end

-- The parameter of the point on that same band NEAREST (px, py): PerimeterPoint
-- read backwards. A lane centres its run here, which is what puts a nest
-- opposite the entry that opens it however that entry sits in the block.
--
-- Worked out per side and per corner arc rather than by walking the path: a
-- scan fine enough to place a run would cost more than the run does, and a
-- coarse one would answer a different parameter to the drawing than to the
-- push.
--
-- positive is the tie-break side (fixed at above/right now), answering
-- wherever the projection genuinely ties, and ties are the ordinary case
-- rather than the awkward one. The band stands
-- the same distance off every edge, so a CORNER cell is exactly as far from
-- both of the edges that meet there: two ADJACENT sides tie, and the answer is
-- the corner between them -- a run centred there wraps its L around it. Two
-- OPPOSITE sides tie for a cell on the block's own middle line, and all four
-- tie for a cell dead centre, where there is no lean to read at all and the
-- run belongs on the middle of the positive edge.
--
-- axisOnly keeps a degenerate one-row or one-column block breaking out ACROSS
-- itself and only across itself: the sides in line with it are left out of the
-- projection altogether rather than merely losing a tie-break.
local function PerimeterNearest(px, py, HX, HY, R, positive, axisOnly)
    local sx, sy, arc, L = PerimeterSpan(HX, HY, R)
    -- Where the corner arcs are centred, and so also the corners of the region
    -- in which some straight side is the nearest part of the path at all.
    local cx, cy = HX - R, HY - R

    -- Diagonally past one of those centres no straight side can answer, and the
    -- nearest point is on that corner's own arc, at the angle the offset points
    -- in. Nothing inside a block ever lands here -- the band stands off further
    -- than it turns -- but an inverse that held only where the caller happens to
    -- ask is a trap for the next caller.
    if not axisOnly and abs(px) > cx and abs(py) > cy then
        local dx = px - ((px > 0) and cx or -cx)
        local dy = py - ((py > 0) and cy or -cy)
        -- Each arc measured from its own start, the way PerimeterPoint runs it,
        -- and the argument order per arc is that arc's own sin/cos pair there.
        if px > 0 and py > 0 then return sx + atan2(dx, dy) * R end
        if px > 0 then return sx + sy + arc + atan2(-dy, dx) * R end
        if py < 0 then return 2 * sx + sy + 2 * arc + atan2(-dx, -dy) * R end
        return 2 * sx + 2 * sy + 3 * arc + atan2(dy, -dx) * R
    end

    -- Distance to each side's straight run in path order -- top, right, bottom,
    -- left -- with the parameter of the projected point alongside, and the
    -- middle of the arc FOLLOWING each side, which is the answer whenever that
    -- side and the next one tie. A side the caller ruled out is never nearest.
    local far = L * 2
    local acrossX = (not axisOnly) or axisOnly == "X"
    local acrossY = (not axisOnly) or axisOnly == "Y"
    local d = { acrossX and (HY - py) or far, acrossY and (HX - px) or far,
                acrossX and (py + HY) or far, acrossY and (px + HX) or far }
    local t = { px + cx,
                sx + arc + (cy - py),
                sx + sy + 2 * arc + (cx - px),
                2 * sx + sy + 3 * arc + (py + cy) }
    local mid = { sx + arc * 0.5,
                  sx + sy + arc * 1.5,
                  2 * sx + sy + 2 * arc + arc * 0.5,
                  2 * sx + 2 * sy + 3 * arc + arc * 0.5 }

    -- Exact wherever it decides anything -- every cell of a row stands the same
    -- distance off the edge it is on -- but compared with a tolerance anyway,
    -- the two distances arriving by different arithmetic.
    local best = min(d[1], d[2], d[3], d[4])
    local tie = {}
    for si = 1, 4 do tie[si] = (d[si] - best) <= 1e-4 end

    if tie[1] and tie[2] and tie[3] and tie[4] then
        -- No lean in any direction: the positive tie-break picks the edge
        -- and the run sits on the middle of it.
        if positive then return sx * 0.5 end
        return sx * 1.5 + sy + 2 * arc
    end
    -- An opposite pair is the tie-break's other question, and answering it here
    -- leaves at most two sides standing, which can then only be adjacent.
    if tie[1] and tie[3] then tie[positive and 3 or 1] = false end
    if tie[2] and tie[4] then tie[positive and 4 or 2] = false end
    for si = 1, 4 do
        if tie[si] and tie[(si % 4) + 1] then return mid[si] end
    end
    for si = 1, 4 do
        if tie[si] then return t[si] end
    end
end

-- Everything the three styles measure from. Sizes are scaled by whatever this
-- view scaled its geometry by, recovered from the icon size Geom handed back --
-- the options preview fits a palette to its panel, and a band read at its
-- literal profile size would draw nests at full distance around a shrunken one.
function PaletteView:NestMetrics(shown)
    local p = self:P()
    local _, iconSize = self:Geom()
    local pitch = self:Pitch()
    local base = p.iconSize or 40
    local k = (base > 0) and (iconSize / base) or 1
    local cols, rows = self:GridDims(shown)

    local m = {
        icon  = iconSize,
        pitch = pitch,
        cols  = cols,
        rows  = rows,
        band  = max(0, p.nestBand or NEST_BAND_DEFAULT) * k,
        gap   = (p.fanGap or 10) * k,
        -- FIXED true -- nests break out above/right wherever the sides tie
        -- (the Nest Side setting was removed); a nestSide key left in stored
        -- profiles is never read.
        positive = true,
        -- Everything that is not a halo is a lane. That includes the retired
        -- POPOUT value a stored profile may still carry: its detached block
        -- came to answer arming exactly the way the lane does, and the lane is
        -- what it folded into.
        style = (p.gridNestStyle == "HALO") and "HALO" or "PERIMETER",
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
    -- The lane works its own out, its children standing off by a gap rather
    -- than by a band -- see PerimeterNest.
    m.depth = m.childIcon + m.band
    -- Whatever Nest Distance was asked for BEYOND the value the profile ships
    -- with. The lane hugs the block at the default and reads the slider as
    -- extra clearance on top of that, so the two answers agree wherever the
    -- user has moved it and the snug read is what an untouched profile gets.
    m.bandExtra = max(0, (p.nestBand or NEST_BAND_DEFAULT) - NEST_BAND_DEFAULT) * k
    -- A strip has no interior to displace and no corner to wrap, so the styles
    -- that rearrange a block have nothing to rearrange: it is always a small
    -- block of its own, centred on the parent and broken out perpendicular to
    -- the strip, whatever gridNestStyle asks for.
    if cols <= 1 or rows <= 1 then m.style = "STRIP" end
    return m
end

-- Box for one cell of a run travelling on `axis`.
local function RunBox(x, y, axis, along, across)
    if axis == "X" then
        return { x = x, y = y, hw = along * 0.5, hh = across * 0.5 }
    end
    return { x = x, y = y, hw = across * 0.5, hh = along * 0.5 }
end

-- (A) A halo hugging the block's own perimeter: one run of children, centred on
-- the point of that perimeter NEAREST the entry they hang off, wrapping the
-- corners when the run is long. A parent on the middle of an edge is served by
-- the stretch of lane just outside it, a parent in the middle of the block by
-- the middle of the positive edge, and a corner parent by the corner itself --
-- the L around it, half the run down each of the two edges that meet there.
--
-- The band is ONE lane: two nests near each other sit side by side along it
-- rather than stacking outward, which is what the eye expects when only one of
-- them is ever drawn. Runs are packed along the perimeter as a single circular
-- coordinate, so a run longer than the edge it started on wraps around the
-- corner instead of shooting off into space.
function PaletteView:PerimeterNest(claims, shown, m)
    -- Snug against the block, which is the whole read of this style: the
    -- children's inner edges stand one gap outside the block's own outer edge,
    -- so the lane looks like a halo ON the grid rather than a second block of
    -- entries floating off it. Nest Distance is honoured as clearance BEYOND
    -- that, so a user who wants the children held further out can still say so.
    local clear = m.gap + m.bandExtra
    local standoff = m.icon * 0.5 + clear + m.childIcon * 0.5
    -- Across the run: from the block's own outer edge to as far past the child
    -- icon as the child icon is from the block. A pointer leaving the parent
    -- enters the nest without crossing dead ground, and one that overruns an
    -- icon on the way out is still inside its box.
    local depth = m.childIcon + clear * 2
    local HX, HY = m.halfX + standoff, m.halfY + standoff
    -- The turn's radius, balanced between the two things it trades off. Too
    -- small and two icons either side of it crowd, the straight line between
    -- them being shorter than the path by up to a third around a square corner
    -- (see PerimeterSpan); too large and the turn itself cuts diagonally in
    -- across the block's own corner entry, which a lane this snug is close
    -- enough in to do. Both are straight lines measured against the same floor
    -- of one child icon, and this is the radius where the two meet. That floor
    -- shapes the turn; it does not clear the icons on it. Two square icons
    -- straddling a corner can sit a whole icon apart in a straight line and
    -- still be short of one on BOTH axes, which is what overlap actually asks,
    -- so the cells are SPACED by that same measure -- see PerimeterStep --
    -- and a turn costs the run extra path rather than ground.
    local turn = (standoff - m.childPitch * 0.5) * sqrt(2)
                 / (2 * sqrt(2) + 1 - sqrt(2) * pi * 0.25)
    local R = min(depth * 0.5, min(HX, HY) * 0.5, max(0, turn))
    local sx, sy, arc, L = PerimeterSpan(HX, HY, R)

    local childPitch, childIcon = m.childPitch, m.childIcon
    -- A strip breaks out ACROSS itself and only across itself: a row of entries
    -- has an edge at both ends, and a nest hung off one of those would run in
    -- line with the palette rather than out of it. NestMetrics sends those
    -- shapes to STRIP before they reach this at all, so this only holds the rule
    -- for a caller that arrives here anyway.
    local axisOnly = (m.rows <= 1 and "X") or (m.cols <= 1 and "Y") or nil

    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        -- c.icon is not set here: what this style may draw a child at depends
        -- on how tightly that run ends up packed, which is not known until its
        -- cells are placed below.
        -- Along the lane, a caption is drawn at CHILD pitch rather than at the
        -- pitch the palette's own entries get, so two neighbouring captions
        -- overlap long before their icons do. Unlabelled, like every other
        -- style's nest.
        c.label = false
        c._bx, c._by = bx, by
        -- The clear distance this style actually held its children out by, which
        -- is what CellChildGeom sizes the arming grace from. Nest Distance is
        -- only part of it here, and at the bottom of that slider's travel none
        -- of it -- a grace read off the slider instead would go on shrinking
        -- after the children had stopped moving.
        c.standoff = clear
        -- The nearest point of the lane, from the parent's own CELL rather than
        -- from anywhere on the screen: the push runs long before the open that
        -- will use it, and the two have to agree.
        c.t0 = PerimeterNearest(bx, by, HX, HY, R, m.positive, axisOnly)
    end

    -- How much of the lane each nest may take: the WHOLE of it. Only one nest is
    -- ever open, and only one is ever armed, so two runs overlapping on the lane
    -- is not an ambiguity -- the cursor can only be inside the armed claim's
    -- cells, and the unarmed one is neither drawn nor answerable. Sharing the
    -- lane out between the claims instead left two nests in neighbouring cells
    -- with three quarters of a pitch each, which collapses cols to one or two
    -- and stacks the run outward into rows: the user asked for a run round the
    -- block and got a cluster hanging off the entry.
    --
    -- L is the bound that remains, and it is a real one: a run longer than the
    -- lane would wrap past its own first cell and put two children on the same
    -- ground.
    for i = 1, #claims do
        local c = claims[i]
        -- A crowded nest EXTENDS along the perimeter first, as far as the lane
        -- goes: wrapping further round the block costs the user nothing, and one
        -- long run is the shape this style is for. Only a nest whose children do
        -- not all fit on the lane spills the rest into a second row further out.
        --
        -- How many fit is WALKED rather than divided out of L: a step spends
        -- more than a pitch of path at a turn, so a row sized by L / pitch
        -- could wrap past its own first cell exactly when the lane is full
        -- enough for it to matter.
        local room, walked = 1, 0
        while room < c.n do
            local step = PerimeterStep(c.t0 + walked, HX, HY, R, childPitch)
            if walked + step > L - childPitch then break end
            walked, room = walked + step, room + 1
        end
        local cols = room
        -- One row of parameters per row of cells, each row centred on t0 the
        -- way the even spacing was: walked once from a guessed start to learn
        -- the path length it really spends, then again from the start that
        -- puts half of that either side of t0.
        local rowTs = {}
        for cr = 0, ceil(c.n / cols) - 1 do
            local inRow = min(cols, c.n - cr * cols)
            local start = c.t0 - (inRow - 1) * 0.5 * childPitch
            local row
            for _ = 1, 2 do
                row = { start }
                for jr = 2, inRow do
                    row[jr] = row[jr - 1]
                              + PerimeterStep(row[jr - 1], HX, HY, R, childPitch)
                end
                start = c.t0 - (row[inRow] - row[1]) * 0.5
            end
            rowTs[cr + 1] = row
        end
        c.cells = {}
        -- The sides the run came down on, in the order it reached them. A run
        -- that wrapped a corner has cells on two of them, and its regions are
        -- one tight box per side rather than one across the L -- see
        -- CellChildGeom, which is where that matters.
        local groups, bySide = {}, {}
        for j = 1, c.n do
            local cr  = floor((j - 1) / cols)
            local cc  = (j - 1) % cols
            local t = rowTs[cr + 1][cc + 1]
            local x, y, axis, sign, nx, ny = PerimeterPoint(t, HX, HY, R)
            -- Rows past the first sit one row further out along the outward
            -- normal, which keeps them square on a straight edge and fanned
            -- around a corner.
            local outw = cr * (childIcon + m.gap)
            local box = RunBox(x + nx * outw, y + ny * outw,
                               axis, childPitch, depth)
            c.cells[j] = box
            -- PerimeterPoint hands a cell more than halfway round a corner to
            -- the side it is heading onto, so these come out as the runs the eye
            -- actually reads rather than as a split at the corner's own edge.
            local key = axis .. sign
            local g = bySide[key]
            if not g then
                g = { axis = axis, sign = sign, cells = {}, order = #groups + 1 }
                bySide[key], groups[#groups + 1] = g, g
            end
            g.cells[#g.cells + 1] = box
        end

        -- The walk above holds every CONSECUTIVE pair a whole pitch apart, but
        -- it says nothing about the pairs it never measured: a run that fills
        -- the lane meets its own first cell across the seam, and a spilled row
        -- crosses back over the one under it wherever the fan folds. So this
        -- run's icons come down to the tightest pair it actually has. The
        -- BOXES keep their pitch -- the run holds its length, its regions and
        -- its gates, and the hit test answers exactly what it did -- and an
        -- ordinary run has no pair nearer than a pitch, so it comes out at
        -- the size it asks for. nestScale is the ceiling either way: this only
        -- ever takes size away.
        local tight = childIcon
        for ja = 1, c.n - 1 do
            for jb = ja + 1, c.n do
                local pa, pb = c.cells[ja], c.cells[jb]
                -- Square icons drawn on the cell centres, so a pair clears as
                -- soon as ONE axis separates them by a whole icon.
                local sep = max(abs(pa.x - pb.x), abs(pa.y - pb.y))
                if sep < tight then tight = sep end
            end
        end
        c.icon = tight

        -- Nearest side first, measured to the nearest cell on it: that is the
        -- side the claim reports as its own axis, and a run long enough to wrap
        -- onto more sides than there are region gates for then loses the
        -- FURTHEST of them rather than the one the reach actually crosses.
        for gi = 1, #groups do
            local near = math.huge
            local cells = groups[gi].cells
            for ci = 1, #cells do
                local dx, dy = cells[ci].x - c._bx, cells[ci].y - c._by
                near = min(near, dx * dx + dy * dy)
            end
            groups[gi].near = near
        end
        tsort(groups, function(g1, g2)
            if g1.near ~= g2.near then return g1.near < g2.near end
            return g1.order < g2.order
        end)
        c.groups = groups
        c.axis, c.sign = groups[1].axis, groups[1].sign
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
    -- unselectable while the halo is up. That caps the ring at two thirds of a
    -- pitch, and the ring is pushed right out to it: the parent icon sits in the
    -- middle at full size and a ring any tighter has its children touching it.
    local hp = m.pitch * 0.62
    -- Small enough that a full-size parent still has clear ground around it,
    -- which is the whole read of this style -- children AROUND an entry, not
    -- crowding it.
    local icon = min(m.childIcon, hp * 0.62)
    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        -- No axis and no side: a halo surrounds its parent rather than coming
        -- out of one edge of the block, so there is no "other side" for the hub
        -- caption to move to and it keeps the placement it would have had.
        c.icon, c.dim = icon, true
        -- The parent draws back to leave the ring somewhere to be. It keeps its
        -- full colour, unlike the rest of the block: it is what the ring is
        -- about, and dimming it would leave nothing saying which entry opened.
        c.parentScale = 0.6
        -- Eight captions around one icon are eight captions on top of each
        -- other. At this size the icon is the whole of what can be read.
        c.label = false
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

-- (C) A single row or column's nest: a small block of its own, centred on the
-- parent's own place along the strip and broken out perpendicular to it. A
-- strip has only the one line every parent already sits on, so there is no
-- interior for PERIMETER's lane to run around -- the crowding that style
-- solves by wrapping corners never arises here, because every claim already
-- owns a stretch of the line to itself the moment it owns a parent cell.
-- The positive side answers the side question -- a line has no lean to read.
function PaletteView:StripCellNest(claims, shown, m)
    -- rows <= 1 means the strip runs along X, so its nests break out along Y;
    -- cols <= 1 is the other way round. NestMetrics only reaches this style
    -- when one of the two is true.
    local axis = (m.rows <= 1) and "X" or "Y"
    local sign = m.positive and 1 or -1
    local out  = m.icon * 0.5 + m.band + m.childIcon * 0.5

    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        c.icon = m.childIcon
        -- Packed at child pitch like every other nest style's captions, a run
        -- of them along a strip collides just as readily as PERIMETER's lane
        -- does, so this style goes unlabelled too.
        c.label = false
        c.axis, c.sign = axis, sign
        c._bx, c._by = bx, by
        -- Position along the strip's own axis, so two claims that are close
        -- together can be told apart from two that are not.
        c.t0 = (axis == "X") and bx or by
    end

    for i = 1, #claims do
        local c = claims[i]
        -- Half the room this claim's block may spread into along the strip:
        -- out to the midpoint with the nearest OTHER nest's own parent. A
        -- strip is a straight line, not PERIMETER's closed loop, so this is a
        -- plain distance rather than a distance around a wrap -- but the
        -- answer it feeds into cols is the same one: a crowded nest gives up
        -- columns and grows another row instead of colliding with its
        -- neighbour.
        local room = math.huge
        for j = 1, #claims do
            if j ~= i then room = min(room, abs(claims[j].t0 - c.t0) * 0.5) end
        end
        local ccols = min(MAX_SLOTS, max(1, ceil(sqrt(c.n))))
        if room < math.huge then
            ccols = min(ccols, max(1, floor(room * 2 / m.childPitch)))
        end

        c.cells = {}
        for j = 1, c.n do
            local cr  = floor((j - 1) / ccols)
            local cc  = (j - 1) % ccols
            local row = min(ccols, c.n - cr * ccols)
            local a = (cc - (row - 1) * 0.5) * m.childPitch
            local d = out + cr * m.childPitch
            local x, y
            if axis == "X" then x, y = c._bx + a, c._by + sign * d
            else x, y = c._bx + sign * d, c._by + a end
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
-- Every nest is built at that same centre; the drawing and the hit tests
-- shift a claim's cells to its parent's own fold offset when the hover
-- channel is on. Nothing is lost by it: only one nest is ever live -- the
-- wheel's entry's under wheel-only steering, the ARMED claim's under the
-- hover channel -- so two nests can no more be reached at once than two
-- entries can.
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
        -- Unlabelled, like the strip's own entries: at strip spacing the
        -- captions of neighbouring icons collide, and a nest is drawn at the
        -- same spacing or tighter.
        c.label = false
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
    if m.style == "STRIP" then
        self:StripCellNest(claims, shown, m)
    elseif m.style == "HALO" then
        self:HaloNest(claims, shown, m)
    else
        self:PerimeterNest(claims, shown, m)
    end

    -- The ground between a parent and its children, so that crossing it keeps
    -- the nest on screen. A nest sitting clear of the block has a gap in front
    -- of it that belongs to no cell of its own, and a nest that vanished halfway
    -- through the reach for it could not be reached at all.
    --
    -- c.regions also doubles as the claim's REGION gates (see EnsureGates):
    -- the rects a secure OnLeave watches, geometrically, to know the cursor
    -- has actually left this nest's ground, parent cell and all. c.parentBox
    -- is the other one, the claim's own cell alone -- the gate whose OnEnter
    -- arms it in the first place. Nothing here decides what a release FIRES,
    -- only what is drawn and what is armable: an entry under either box stays
    -- exactly as selectable as it was.
    --
    -- HALO sets neither axis nor sign -- its ring surrounds the parent on
    -- every side, so there is no one direction to run a corridor in, and the
    -- old single bounding box (parent cell plus every ring position) is
    -- already close enough to the true shape that a second rect buys
    -- nothing: the neighbour centres HaloNest leaves clear of the ring stay
    -- clear of this box too. Every other style hangs its nest off ONE side
    -- of the parent, so a box across the two would swallow whatever plain
    -- ground of the block lies between them -- the dim-never-backs-out
    -- complaint. Those get the true union instead: the parent's own cell,
    -- the nest's own tight box, and a corridor one child cell wide
    -- connecting them, so standing on the block's own ground either side of
    -- that corridor is standing outside the nest. Those also get the
    -- overshoot grace (see GraceBox); the halo's box does NOT, because it
    -- already reaches to just short of its neighbours' centres and a grace on
    -- top of that would swallow one, leaving that entry unselectable while
    -- the ring is up.
    --
    -- A lane brings the same complaint back in a second shape: a run that
    -- wrapped a corner has cells on two edges of the block, and ONE box
    -- around those swallows the block's own corner ground between them. So a
    -- run that carries its sides (c.groups) gets one box per side, each with
    -- its own way back to the parent folded in -- see RunReach.
    -- Every parent cell first: the regions below take the OTHER claims' cells
    -- out of their own coverage (see ParentHoles), so they all have to exist
    -- before the first of them is built.
    for i = 1, #claims do
        local c = claims[i]
        local bx, by = self:GridBase(c.parent, m.cols, m.rows, m.pitch, shown)
        c.parentBox = { x = bx, y = by, hw = m.pitch * 0.5, hh = m.pitch * 0.5 }
    end

    for i = 1, #claims do
        local c = claims[i]
        local holes = ParentHoles(claims, i)

        if c.axis then
            -- How far a claim's ground reaches past its own edges. c.standoff
            -- is a lane saying how far out it actually put its children, which
            -- for that style is not the Nest Distance at all -- it hugs the
            -- block, and the slider only adds to that -- and a grace read off
            -- the slider there would leave the bottom of its travel moving
            -- nothing but invisible slack.
            local grace = max(c.standoff or m.band, 0.75 * m.childPitch)
            local sides = c.groups
            c.regions = { c.parentBox }
            if sides then
                -- Nearest side first, PerimeterNest having ordered them: a run
                -- that reached more sides than there are region gates for then
                -- drops the far ones rather than the one the reach crosses.
                for gi = 1, #sides do
                    local run = RunReach(c.parentBox, NestBBox(sides[gi].cells))
                    AddRegion(c, GraceBox(run, grace, sides[gi].axis, sides[gi].sign),
                              sides[gi].axis, holes)
                end
            else
                local nest = NestBBox(c.cells)
                -- Measured from the TIGHT box, before the grace widens it: the
                -- corridor is as wide as the nest it leads to, and inflating
                -- the nest first would spread the corridor sideways across the
                -- block's own ground as well.
                local corridor = CorridorBox(c.parentBox, nest, c.axis, c.sign,
                                             m.childPitch)
                AddRegion(c, GraceBox(nest, grace, c.axis, c.sign), c.axis, holes)
                AddRegion(c, corridor, c.axis, holes)
            end
        else
            local pb = c.parentBox
            local x0, x1 = pb.x - m.pitch * 0.5, pb.x + m.pitch * 0.5
            local y0, y1 = pb.y - m.pitch * 0.5, pb.y + m.pitch * 0.5
            for j = 1, c.n do
                local b = c.cells[j]
                x0, x1 = min(x0, b.x - b.hw), max(x1, b.x + b.hw)
                y0, y1 = min(y0, b.y - b.hh), max(y1, b.y + b.hh)
            end
            c.regions = {}
            AddRegion(c, EdgeBox(x0, x1, y0, y1), c.axis, holes)
        end
    end
    return claims
end

-- The nested cell whose box holds this offset, WITHIN THE ARMED CLAIM only.
-- Read by the drawing; the snippet carries the same test over the same
-- numbers, gated the same way -- see ArmedClaim and the release branch of
-- SNIPPET_PRE. An unarmed claim answers nothing here at all: the whole point
-- of arming is that a nest's ground is not live until the cursor has actually
-- passed through the entry that opens it.
function PaletteView:NestHit(dx, dy, armed)
    local c = armed and self.claims and self.claims[armed]
    if not c or not c.cells then return end
    for j = 1, c.n do
        local b = c.cells[j]
        if abs(dx - b.x) <= b.hw and abs(dy - b.y) <= b.hh then
            return c.base + j, c
        end
    end
end

-- Lay the grid out and select the entry nearest the pointer. noPointer draws it
-- evenly with nothing selected, which is what Layout and the editor want.
function PaletteView:AdvanceGrid(noPointer)
    local p = self:P()
    local shown = self.shownCount
    if not p or shown < 1 then
        self:SetSelection(nil)
        return
    end

    local _, iconSize = self:Geom()
    local pitch  = iconSize + (p.fanGap or 10)
    local decay, aDecay = FalloffRatios(p)
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
    --
    -- ONLY the armed claim, though: this is the pass-through rule. A nest
    -- earns the right to answer here by having actually had the cursor pass
    -- over its parent entry first -- see ArmedClaim and the gate frames
    -- EnsureGates builds. An unarmed claim's ground answers as though it held
    -- no nest at all, which is exactly what lets two claims share ground
    -- without one springing open behind the other's back.
    local best, bestK
    local armed = self:ArmedClaim()
    if dx then best = self:NestHit(dx, dy, armed) end

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

        -- Falloff is the 2D distance, in cells. A grid has no privileged axis,
        -- so projecting onto one -- as the strip does -- would make the zoom
        -- respond to sideways movement it should ignore.
        --
        -- Each axis is flattened over the cell before they are combined, so the
        -- whole of a cell -- corners included -- reads as zero cells away. See
        -- FalloffK.
        local s, a = max(minS, decay), 1
        if dx then
            local ox = FalloffK(abs(dx - bx) / pitch)
            local oy = FalloffK(abs(dy - by) / pitch)
            local k = (ox * ox + oy * oy) ^ 0.5
            s = max(minS, decay ^ k)
            a = max(minA, aDecay ^ k)
        end
        -- The entry a nest hangs off keeps its colour: it is what the nest is
        -- about, and dimming it would leave nothing on screen saying which entry
        -- was opened. It may still draw back to make room -- the halo needs the
        -- ground its parent would otherwise be standing on.
        if open then
            if i ~= open.parent then
                s, a = s * shrink, a * dim
            elseif open.parentScale then
                s = s * open.parentScale
            end
        end

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
    local p = self:P()
    local _, iconSize = self:Geom()
    -- One window for editor and play alike: the editor draws the same
    -- fanVisible-each-side strip a hold does and scrolls the rest into view.
    local window = (p and p.fanVisible) or 2
    local minS = self.opts.interactive and FAN_EDIT_MIN_SCALE
                                        or ((p and p.fanMinScale) or 0.30)
    -- Plus the room ApplyFanGeometry leaves for the selected entry to grow into,
    -- which every offset past the centre carries. Left out, the frame would be
    -- narrower than the strip drawn in it and the cancel box would sit inside
    -- the last entry rather than beyond it.
    return FanOffset(window, iconSize, (p and p.fanGap) or 10,
                     (FalloffRatios(p)), minS)
           + iconSize + iconSize * (SelectedZoom() - 1) * 0.5
end

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

-- The fold offset `slot` is drawn at on the strip, or nil when the window
-- culls it. One copy of the fold-plus-window arithmetic ApplyFanGeometry
-- draws by, for every reader that has to know where an entry stands: the
-- hover channel's nest tests and the sticky retention both anchor to it,
-- and the snippet's nest walk runs the identical sums.
function PaletteView:FanSlotOffset(slot)
    local shown = self.shownCount
    local target = self:StripTarget()
    if not slot or not target or shown < 1 then return nil end
    local d = (slot - target) % shown
    if d * 2 > shown then d = d - shown end
    local p = self:P()
    if abs(d) > ((p and p.fanVisible) or 2) + 0.5 then return nil end
    return d
end

-- How far the pointer has been carried toward leaving the strip: 0 while it is
-- still on it, 1 at the edge of the cancel box and beyond. Answers 0 for any
-- view with no gate origin -- the options preview, which has no pointer gesture
-- at all -- so only the live palette can be cancelled this way.
function PaletteView:FanCancelProgress()
    if not self._gateX then return 0 end
    local p = self:P()
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
        self.fanTarget = tonumber(scrollCatcher:GetAttribute("eqdFanTarget"))
    end

    -- Published BEFORE the geometry below, which magnifies whichever entry is
    -- selected as it places it. The strip keeps sliding to wherever the wheel
    -- has left it while the pointer is clear of it, so bringing the pointer back
    -- shows the entry that would fire, already settled.
    local target = self:StripTarget()
    local claim  = self:ClaimFor(target)
    local p2 = self:P()
    local mouseSel = (p2 and p2.fanMouseSelect) ~= false
    local sel
    -- Into a nest, if the pointer has gone there. ONLY the ARMED claim's
    -- cells are live ground: hovering a parent's own icon arms its claim
    -- through the strip's lattice gates (see EnsureLatticeGates), hovering
    -- any other entry disarms, and the empty ground beside the strip changes
    -- nothing -- so the reach for the children keeps the nest, while the
    -- space where a CLOSED nest would be answers nothing at all. The snippet
    -- reads the same eqdArmed and runs the identical shifted containment
    -- (drawn == fired). Wheel-only keeps the old rule: the wheel says WHICH
    -- nest, measured from the open point.
    local dx, dy = self:StripOffset()
    if mouseSel and dx then
        local ak = self:ArmedClaim()
        local c = ak and self.claims and self.claims[ak]
        local dp = c and c.base and self:FanSlotOffset(c.parent)
        if dp then
            local fxc, fyc = self.frame:GetCenter()
            if fxc then
                local esc = self.frame:GetEffectiveScale()
                local mxc, myc = GetCursorPosition()
                local ndx, ndy = mxc / esc - fxc, myc / esc - fyc
                local pitch = self:Pitch()
                local sx, sy = 0, 0
                if self:FanHoriz() then sx = dp * pitch else sy = -(dp * pitch) end
                for j = 1, c.n do
                    local b = c.cells[j]
                    if abs(ndx - (b.x + sx)) <= b.hw
                       and abs(ndy - (b.y + sy)) <= b.hh then
                        sel = c.base + j
                        break
                    end
                end
            end
        end
    elseif claim and dx and claim.base then
        for j = 1, claim.n do
            local b = claim.cells[j]
            if abs(dx - b.x) <= b.hw and abs(dy - b.y) <= b.hh then
                sel = claim.base + j
                break
            end
        end
    end
    -- The strip under the pointer ("Select Action with Mouse"): selection is
    -- EXCLUSIVELY hover -- the entry whose drawn box the pointer is inside,
    -- or nothing at all. The wheel still slides the strip, which changes what
    -- sits under a stationary pointer, but it holds no selection of its own:
    -- pointing away from every icon deselects, and a release there cancels
    -- (the snippet runs this identical test, so drawn and fired agree).
    -- Measured against the SETTLED strip -- fanTarget centred on the FRAME,
    -- full pitch -- from the frame's own centre: the gate point in cursor
    -- mode, the pinned point in Fixed Position, so the test is against what
    -- is actually drawn in both.
    if not sel and target and self.fanTarget and mouseSel then
        local fx2, fy2 = self.frame:GetCenter()
        if fx2 then
            local es2 = self.frame:GetEffectiveScale()
            local mx2, my2 = GetCursorPosition()
            local along, across = mx2 / es2 - fx2, my2 / es2 - fy2
            -- NEGATED dy, not raw: a vertical strip runs DOWNWARD --
            -- ApplyFanGeometry draws positive offsets at -off -- so below
            -- the centre is positive d. Raw dy read the strip mirrored.
            -- The snippet's hover test negates identically (drawn == fired).
            if not self:FanHoriz() then along, across = -across, along end
            local _, iconSize = self:Geom()
            local pitch = iconSize + ((p2 and p2.fanGap) or 10)
            local d = floor(along / pitch + 0.5)
            -- One window everywhere now -- the editor draws it too -- and
            -- the same number the snippet was pushed as eqdFanWin, so drawn
            -- and fired agree.
            local window = (p2 and p2.fanVisible) or 2
            -- Inside the icon's own box on BOTH axes -- the gaps between
            -- icons select nothing -- and only a DRAWN entry, bounded by
            -- the draw cull's own test (k <= window + 0.5): d is an
            -- integer, so a whole window reads the same either way, and a
            -- FRACTIONAL stored window draws out to the rounded edge --
            -- the hover has to accept exactly what is on screen. The fold
            -- bound is the drawing's own asymmetric one: entries land in
            -- (-shown/2, shown/2], so on an even fold the +half slot is a
            -- real icon and the -half slot is empty ground.
            if abs(across) <= iconSize * 0.5
               and abs(along - d * pitch) <= iconSize * 0.5
               and abs(d) <= window + 0.5
               and d * 2 <= shown and -d * 2 < shown then
                sel = ((self.fanTarget - 1 + d) % shown) + 1
            end
        end
    end
    -- Sticky nest: the reach for a nest's children crosses ground that
    -- hovers NOTHING, and exclusive hover would drop the parent -- and the
    -- children with it -- mid-reach. The ARMED claim is the sticky itself
    -- now: an empty pointer keeps its parent selected, and only entering
    -- another entry's own position moves it on (the lattice disarms there,
    -- arming the new claim if that entry nests). The parent rather than a
    -- lingering child, so drawn == fired holds: a child is chosen strictly
    -- by containment, a parent is a door, and a release over empty ground
    -- cancels on both sides (nothover).
    if not sel and mouseSel then
        local ak = self:ArmedClaim()
        local c = ak and self.claims and self.claims[ak]
        if c and self:FanSlotOffset(c.parent) then sel = c.parent end
    end
    -- The wheel's entry stands on its own only while the hover channel is
    -- OFF: exclusive hover means an empty pointer selects nothing at all.
    if not sel and target and not mouseSel and not self:FanCancelled() then
        sel = target
    end
    self:SetSelection(sel)

    -- Nested cells. Under the hover channel each claim's children hang off
    -- their parent's DRAWN spot on the strip -- frame-anchored plus the
    -- parent's fold offset, the same anchoring the hit tests measure.
    -- Wheel-only keeps the open-point anchor: the strip's cancel and its
    -- nests are one geometry there.
    local claims = self.claims
    if claims and dx then
        local fx, fy = self.frame:GetCenter()
        local ox, oy = 0, 0
        if not mouseSel and fx then
            ox, oy = self._gateX - fx, self._gateY - fy
        end
        local pitch = self:Pitch()
        local horiz = self:FanHoriz()
        for k = 1, #claims do
            local c = claims[k]
            local sx, sy = 0, 0
            if mouseSel then
                local dp = self:FanSlotOffset(c.parent)
                if dp then
                    if horiz then sx = dp * pitch else sy = -(dp * pitch) end
                end
            end
            for j = 1, c.n do
                local w = c.base and self.widgets[c.base + j]
                if w then
                    w:ClearAllPoints()
                    w:SetPoint("CENTER", self.frame, "CENTER",
                               ox + sx + c.cells[j].x, oy + sy + c.cells[j].y)
                end
            end
        end
    end

    local target = self.fanTarget or 1
    local cur    = self.fanVisual or target
    if cur ~= target then
        -- The settle is FIXED at 0.1s (the Settle Time setting was removed;
        -- a fanAnimTime key left in stored profiles is never read).
        cur = cur + (target - cur) * min(1, (elapsed or 0) / 0.1)
        -- Snap the tail: an asymptote would keep this view dirty forever.
        if abs(target - cur) < 0.001 then cur = target end
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
    -- A vertical nudge the view was created with (the options preview drops
    -- its caption 15px so it clears the fitted palette); the hint is anchored
    -- to the text and follows on its own.
    local dyOff = self.opts.hubTextDY or 0

    hub.text:ClearAllPoints()
    hub.hint:ClearAllPoints()

    if mode == "ARC" then
        hub.text:SetJustifyH("CENTER")
        hub.text:SetPoint("CENTER", hub, "CENTER", 0, dyOff)
        hub.hint:SetPoint("TOP", hub.text, "BOTTOM", 0, -2)
        return
    end

    -- Half the extent the caption has to clear on its own axis. A strip is one
    -- entry deep, but a grid is as deep as it has rows.
    local pad = iconSize * 0.5 + 14
    if mode == "GRID" then
        local p = self:P()
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
            hub.text:SetPoint("BOTTOM", hub, "CENTER", 0, pad + dyOff)
            hub.hint:SetPoint("BOTTOM", hub.text, "TOP", 0, 2)
        else
            hub.text:SetPoint("TOP", hub, "CENTER", 0, -pad + dyOff)
            hub.hint:SetPoint("TOP", hub.text, "BOTTOM", 0, -2)
        end
    else
        -- Right of the middle of the screen -> caption to the LEFT, right
        -- justified so its last character sits against the icon.
        if dx > 0 then
            hub.text:SetJustifyH("RIGHT")
            hub.text:SetPoint("RIGHT", hub, "CENTER", -pad, dyOff)
            hub.hint:SetPoint("TOPRIGHT", hub.text, "BOTTOMRIGHT", 0, -2)
        else
            hub.text:SetJustifyH("LEFT")
            hub.text:SetPoint("LEFT", hub, "CENTER", pad, dyOff)
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

    -- A caller can hand in the frame instead of naming one. The live view does,
    -- because where a frame is created decides which addon its handlers are
    -- billed to -- see the top of this file.
    local frame = view.opts.frame
    if frame then
        frame:SetParent(parent)
    else
        frame = CreateFrame("Frame", view.opts.frameName, parent)
    end
    frame:SetSize(1, 1)
    frame:EnableMouse(false)
    view.frame = frame

    -- Hub: the center disc. Shows the selected action's name, or the palette
    -- name when nothing is selected, which is also the "release now cancels"
    -- signal.
    local hub = CreateFrame("Frame", nil, frame)
    hub:SetSize(2, 2)
    hub:SetPoint("CENTER")
    -- Above the entry widgets (created after it, so otherwise over it): the
    -- fan's caption anchors beside the SELECTED icon now, and where a long
    -- name reaches across neighbouring icons it has to stay readable.
    -- Everything else the hub draws sits on ground of its own anyway.
    hub:SetFrameLevel(frame:GetFrameLevel() + 40)
    view.hub = hub

    -- The hub logo (hardcoded art -- its settings were removed). Default
    -- blend mode: this is real artwork with its own alpha, and ADD would
    -- wash out its dark areas into whatever is behind the palette. ARTWORK
    -- so the hub's OVERLAY strings still read on top of it.
    hub.logo = hub:CreateTexture(nil, "ARTWORK")
    hub.logo:SetTexture((EllesmereUI.MEDIA_PATH or "Interface\\AddOns\\EllesmereUI\\media\\")
                        .. "logo-full-thin.png")
    hub.logo:SetPoint("CENTER")
    hub.logo:Hide()

    -- The connector line to the selected entry (hub.needle) is built lazily
    -- by EnsureNeedle: a fan never draws one, and neither does a palette with
    -- the option off, so nothing is paid until a line is actually shown.

    hub.text = hub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    AdoptFontString(hub.text)
    hub.text:SetPoint("CENTER", hub, "CENTER", 0, 0)
    hub.text:SetWidth(150)
    hub.text:SetWordWrap(false)

    hub.hint = hub:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    AdoptFontString(hub.hint)
    hub.hint:SetPoint("TOP", hub.text, "BOTTOM", 0, -2)

    -- A per-view bump on the hub caption sizes (the options preview asks for
    -- +2). Folded into the strings' own module-font size so RefreshFonts
    -- keeps the delta across every later font change.
    local fontDelta = view.opts.hubFontDelta
    if fontDelta then
        hub.text.eqdFontSize = (hub.text.eqdFontSize or 12) + fontDelta
        hub.hint.eqdFontSize = (hub.hint.eqdFontSize or 10) + fontDelta
        ApplyModuleFont(hub.text)
        ApplyModuleFont(hub.hint)
    end

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
-- IsRaidMarkerActive is unrestricted and answers a plain bool -- it is neither
-- protected nor a secret value, unlike GetRaidTargetIndex beside it in the
-- documentation -- so this reads the same in combat as out of it.
--
-- Every other kind hides the pip rather than leaving it alone: one widget is
-- reused for whatever the next open puts in it, and a stale pip would claim a
-- spell was a marker that is on the ground.
--
-- A method rather than a local function, like MarkerPip's caller and
-- RefreshMarkerPips below: the main chunk is at Lua's ceiling of 200 locals
-- and has no room for another name.
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
    if not id or id < 1 or id > 8
       or not IsRaidMarkerActive(WORLD_MARKER_ENGINE[id]) then
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

-------------------------------------------------------------------------------
--  Selection connector line -- the unlock-mode anchor line's exact look: a
--  soft-textured 3px line from the hub to the chosen entry that grows out
--  over half a second (ease-out, alpha riding the ease), with a warm streak
--  sweeping hub-to-entry on a 2.5s cycle once the grow has landed.
--
--  Region and driver are both lazy. The two Line regions exist only after a
--  line has actually been asked for, and the animation runs off the live
--  view's own open-palette OnUpdate -- a view with no OnUpdate of its own
--  (the options preview) installs one on its frame ONLY while a line is
--  shown and drops it with the line, so an idle page ticks nothing.
--
--  Drawn on the view's own frame at ARTWORK: the entries are child frames,
--  so the line passes under every icon and ends visually at the icon's edge
--  rather than crossing it; the hub's own art covers the line's root.
-------------------------------------------------------------------------------
function PaletteView:EnsureNeedle()
    local hub = self.hub
    if hub.needle then return end
    local line = self.frame:CreateLine(nil, "ARTWORK", nil, 1)
    line:SetThickness(3)
    line:SetSnapToPixelGrid(false)
    line:SetTexelSnappingBias(0)
    line:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\textures\\soft-line")
    line:Hide()
    hub.needle = line

    local pulse = self.frame:CreateLine(nil, "ARTWORK", nil, 2)
    pulse:SetThickness(3)
    pulse:SetSnapToPixelGrid(false)
    pulse:SetTexelSnappingBias(0)
    pulse:SetTexture("Interface\\AnimaChannelingDevice\\AnimaChannelingDeviceLineVerticalMask")
    pulse:Hide()
    hub.pulse = pulse
end

function PaletteView:ShowNeedle(index)
    self:EnsureNeedle()
    -- The line stands off both of its ends: 2/3 of the hub logo's height at
    -- the hub, 1/3 of it at the entry. Measured at this view's own geometry
    -- scale (the same recovery Layout makes for the logo itself), so the
    -- options preview's fitted palette trims proportionally. Stashed here
    -- rather than derived per frame: the geometry cannot move under a shown
    -- line -- any relayout goes through Layout, which hides it, and the
    -- reselect that follows lands back here.
    local p = self:P()
    local _, viewIcon = self:Geom()
    local base = (p and p.iconSize) or 40
    local k = (base > 0) and (viewIcon / base) or 1
    local logo = max(8, 40 * k)  -- the hub logo's hardcoded height
    self._needleTrimS = logo * (2 / 3)
    self._needleTrimE = logo * (1 / 3)
    -- A NEW target grows in from the hub again; the same target keeps its
    -- animation state across repaints.
    if self._needleTarget ~= index then
        self._needleTarget = index
        self._needleT0 = GetTime()
    end
    if not self.opts.live then
        -- One closure per view, made once: the ticker is installed and
        -- removed with the line, never rebuilt per show.
        if not self._needleTicker then
            local view = self
            self._needleTicker = function() view:AdvanceNeedle(GetTime()) end
        end
        self.frame:SetScript("OnUpdate", self._needleTicker)
    end
    self:AdvanceNeedle(GetTime())
end

function PaletteView:HideNeedle()
    self._needleTarget = nil
    local hub = self.hub
    if hub.needle then hub.needle:Hide() end
    if hub.pulse then hub.pulse:Hide() end
    if not self.opts.live and self.frame:GetScript("OnUpdate") == self._needleTicker then
        self.frame:SetScript("OnUpdate", nil)
    end
end

-- One animation step. The live view calls this from its open-palette
-- OnUpdate OUTSIDE the steer skip: the grow-in and the sweep both keep
-- moving under a cursor that is holding still.
function PaletteView:AdvanceNeedle(now)
    local index = self._needleTarget
    local hub = self.hub
    local line = index and hub.needle
    if not line then return end

    local w = self.widgets[index]
    local fx, fy = self.frame:GetCenter()
    local wx, wy
    if w and w:IsShown() then wx, wy = w:GetCenter() end
    if not fx or not wx then
        line:Hide()
        hub.pulse:Hide()
        return
    end
    local dx, dy = wx - fx, wy - fy

    -- Trim both ends by the stand-offs ShowNeedle stashed. A gap too small
    -- to hold both trims draws nothing rather than a backwards sliver.
    local dist = sqrt(dx * dx + dy * dy)
    local trimS = self._needleTrimS or 0
    local trimE = self._needleTrimE or 0
    if dist <= trimS + trimE + 1 then
        line:Hide()
        hub.pulse:Hide()
        return
    end
    local ux, uy = dx / dist, dy / dist
    local sx, sy = ux * trimS, uy * trimS
    local ex, ey = dx - ux * trimE, dy - uy * trimE

    -- 0.25s ease-out grow, the alpha riding the ease. Colored by the
    -- selection color -- lifted toward white for the streak, the same lift
    -- the armed border uses -- so the line and the entry it lands on agree.
    local r, g, b = SelectColor(self:P())
    local t = (now - (self._needleT0 or now)) / 0.25
    if t > 1 then t = 1 end
    local ease = 1 - (1 - t) * (1 - t)
    line:SetStartPoint("CENTER", self.frame, sx, sy)
    line:SetEndPoint("CENTER", self.frame, sx + (ex - sx) * ease, sy + (ey - sy) * ease)
    line:SetVertexColor(r, g, b, 0.75 * ease)
    line:Show()

    local pulse = hub.pulse
    if ease >= 1 then
        -- Streak: a 1.5s cycle, the first 56% of it sweeping (the rest is
        -- pause), smooth ease-in-out motion overshooting to twice the line so
        -- the tail chases the head off the far end.
        local pulseAge = now - self._needleT0 - 0.3
        local cycleT = (pulseAge % 1.5) / 1.5
        if cycleT <= 0.56 then
            local st = cycleT / 0.56
            local smoothT = st * st * (3 - 2 * st)
            local headT = smoothT * 2.0
            local tailT = headT - 1.0
            if tailT < 0 then tailT = 0 end
            local clampHead = (headT < 1) and headT or 1
            local clampTail = (tailT < 1) and tailT or 1
            local fadeA = 1
            if smoothT < 0.1 then
                fadeA = smoothT / 0.1
            elseif smoothT > 0.7 then
                fadeA = (1 - smoothT) / 0.3
            end
            if fadeA < 0 then fadeA = 0 end
            if clampHead <= clampTail then
                pulse:Hide()
            else
                pulse:SetStartPoint("CENTER", self.frame,
                    sx + (ex - sx) * clampTail, sy + (ey - sy) * clampTail)
                pulse:SetEndPoint("CENTER", self.frame,
                    sx + (ex - sx) * clampHead, sy + (ey - sy) * clampHead)
                pulse:SetVertexColor(r + (1 - r) * 0.55, g + (1 - g) * 0.55,
                    b + (1 - b) * 0.55, 0.5 * fadeA)
                pulse:Show()
            end
        else
            pulse:Hide()
        end
    else
        pulse:Hide()
    end
end

-------------------------------------------------------------------------------
--  Slam-open -- the arc's opening animation, live menu only. The entries are
--  visible from the very first frame at 50% alpha, launch from just past the
--  hub, and land on the ring over the (fast) window below, fading to full as
--  they go; the logo pops in over the same window, scaling up from half size
--  with the same fade. Driven from the open palette's own OnUpdate, outside
--  the steer skip; costs one table read per frame once landed. Steering,
--  selection and the connector line all run live throughout -- the line even
--  tracks the moving icons, since it reads their centres per frame.
-------------------------------------------------------------------------------
function PaletteView:AdvanceSlam(now)
    local t0 = self._slamT0
    if not t0 then return end
    local t = (now - t0) / 0.12
    if t >= 1 then
        self._slamT0 = nil
        t = 1
    end
    local ease = 1 - (1 - t) * (1 - t)
    local travel = 0.55 + 0.45 * ease
    local alpha = 0.5 + 0.5 * ease

    local radius = self:Geom()
    local step, arcStart = self:ArcGeom(self.shownCount)
    local frame = self.frame
    for i = 1, self.shownCount do
        local w = self.widgets[i]
        local a = arcStart + (i - 1) * step
        w:ClearAllPoints()
        w:SetPoint("CENTER", frame, "CENTER",
            radius * travel * sin(a), radius * travel * cos(a))
        w:SetAlpha(alpha)
    end

    local hub = self.hub
    local sz = self._slamLogoSize
    if sz and hub.logo:IsShown() then
        local s = sz * (0.5 + 0.5 * ease)
        hub.logo:SetSize(s, s)
        -- SetAlpha, not the vertex slot: it lands on the same unified
        -- channel, and the tint Layout wrote stays put.
        hub.logo:SetAlpha(alpha)
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

-- Where the cursor is in the arc's own terms: the angle clockwise from straight
-- up, and the distance from the centre, both in the frame's units. nil while the
-- movement gate is still armed, or before the frame has been placed.
--
-- One copy, read by the hit test and by the falloff alike, so what the arc DRAWS
-- as nearest and what a release actually FIRES cannot part company.
function PaletteView:PointerPolar()
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
    -- atan2(dx, dy) measures clockwise from straight up, matching the layout
    -- (slot 1 at 12 o'clock, index increasing clockwise).
    local theta = atan2(dx, dy)
    if theta < 0 then theta = theta + TWO_PI end
    return theta, sqrt(dx * dx + dy * dy)
end

-- Cursor -> entry index. nil inside the dead zone, and -- while the movement
-- gate is armed -- until the cursor has actually moved. The gate is what makes
-- "open and release without moving" a cancel in FIXED-POSITION mode, where the
-- cursor starts at some arbitrary point on the palette rather than at the center
-- and would otherwise have a slot pre-selected the instant the palette opens.
--
-- theta/dist may be handed in by a caller that has already read the cursor for
-- the same frame; without them the cursor is read here, so this stays callable
-- on its own.
function PaletteView:HitTest(theta, dist)
    local shown = self.shownCount
    if shown < 1 then return nil end
    local _, _, deadZone = self:Geom()

    if not theta then theta, dist = self:PointerPolar() end
    if not theta then return nil end

    -- The armed claim's rings, and no other's. A child sector reaches past its
    -- parent entry's own, so answering the parent first
    -- would settle the question before the child was ever considered -- but
    -- that only matters for the ONE claim the cursor has actually armed by
    -- passing through its parent entry; every other claim's ground answers as
    -- though it held no nest at all. See ArmedClaim.
    local claims = self.claims
    local armed = self:ArmedClaim()
    local c = armed and claims and claims[armed]
    if c and c.base and dist >= c.band then
        -- Which ring dist falls in -- lo/hi are set so consecutive rings
        -- share a boundary at their midpoint radius, and the last ring's
        -- hi is nil, i.e. everything past the second-to-last ring's
        -- midpoint. A miss here (angularly outside the ring it landed in)
        -- falls out of the claim entirely rather than trying another
        -- ring: the rings partition the RADIUS, not the angle.
        for r = 1, #c.rows do
            local row = c.rows[r]
            if dist >= row.lo and (not row.hi or dist < row.hi) then
                if row.step > 0 then
                    local rel = (theta - row.start + row.step * 0.5) % TWO_PI
                    if rel < row.n * row.step then
                        return c.base + row.base + floor(rel / row.step) + 1
                    end
                end
                break
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

-- Lay the falloff over the ring and select the entry the cursor points at. The
-- arc's answer to AdvanceGrid, and it reads the same two settings: an entry one
-- step off the cursor is drawn at the same fraction of full size and full alpha
-- whichever layout it is standing in.
--
-- Nearness on a ring is an ANGLE, not a distance -- every entry is the same
-- distance out, so a radial measure would say nothing -- and it is counted in
-- STEPS, which is what makes the falloff mean "each entry along from the one
-- under the cursor" here as it does everywhere else.
--
-- Positions are left exactly where Layout put them. Only size and alpha move:
-- an entry that also slid along the ring would drag itself out from under the
-- cursor that had just reached it.
function PaletteView:AdvanceArc()
    local p = self:P()
    local shown = self.shownCount
    if not p or shown < 1 then
        self:SetSelection(nil)
        return
    end

    -- One read of the cursor for the whole pass, handed to the hit test and
    -- used for the falloff below: what the ring DRAWS as nearest and what a
    -- release actually FIRES have to come from the same position.
    local theta, dist = self:PointerPolar()
    local best = self:HitTest(theta, dist)

    local _, iconSize, deadZone = self:Geom()
    local decay, aDecay = FalloffRatios(p)
    local minS   = p.fanMinScale or 0.30
    local minA   = p.fanMinAlpha or 0.12

    local step, arcStart = self:ArcGeom(shown)
    -- Inside the dead zone the cursor is not pointing anywhere yet: an angle
    -- read a pixel from the centre swings wildly on the smallest movement, and
    -- the ring would strobe under a hand that had barely left the middle. The
    -- palette is drawn evenly there, which is also what it opens as.
    local steer = theta and step > 0 and dist >= deadZone

    local zoom = SelectedZoom()
    for i = 1, shown do
        local w = self.widgets[i]
        local s, a = 1, 1
        if steer then
            -- Shortest way round, so an entry just anticlockwise of slot 1 is
            -- one step from it rather than a whole turn away. Flattened over
            -- the entry's own sector -- see FalloffK -- so the entry the cursor
            -- is on holds still while the cursor moves about inside it.
            local d = (theta - (arcStart + (i - 1) * step)) % TWO_PI
            if d > pi then d = TWO_PI - d end
            local k = FalloffK(d / step)
            s = max(minS, decay ^ k)
            a = max(minA, aDecay ^ k)
        end

        -- Magnified here rather than left to the selection paint: these sizes
        -- are rewritten every frame and would erase a zoom applied only where
        -- the selection changed. Same reason the strip and the grid do it.
        local z = (i == best) and zoom or 1
        w:SetAlpha(a)
        w.baseSize = iconSize * s
        w:SetSize(iconSize * s * z, iconSize * s * z)
    end

    self:SetSelection(best)
end

-- Has anything the steering passes read moved since the last frame?
--
-- All three of them are pure functions of the geometry Layout worked out and
-- of four running inputs: where the cursor is, which claim the gates have
-- armed, where the wheel has left the strip, and whether the strip is still
-- sliding toward it. Given the same four they rewrite every entry's point,
-- size and alpha to exactly what is already on screen -- so a frame that
-- brings none of them in new can skip the pass outright. A hold lasts many
-- frames and the hand is still on most of them, which is what makes this
-- worth asking.
--
-- Not the alpha, though: the flick-ahead fade is time-based, so
-- UpdatePaletteAlpha runs on every frame regardless.
--
-- The snapshot is cleared by Layout, the one place the geometry underneath it
-- can change while the palette is open.
function PaletteView:SteerUnchanged()
    local x, y = GetCursorPosition()
    local armed = self:ArmedClaim()
    -- Read the same way AdvanceFan reads it, so a wheel tick the pass has not
    -- picked up yet still counts as a change.
    local wheel = self.opts.live and scrollCatcher
                  and scrollCatcher:GetAttribute("eqdFanTarget") or nil
    -- Mid-settle the strip's geometry moves on its own. Both are nil on the
    -- layouts that have no settle at all, which compares equal -- which is why
    -- ns.Close has to clear the pair rather than just the target.
    local settling = self.fanVisual ~= self.fanTarget

    local same = not settling
             and x == self._steerX and y == self._steerY
             and armed == self._steerArmed and wheel == self._steerWheel
    self._steerX, self._steerY = x, y
    self._steerArmed, self._steerWheel = armed, wheel
    return same
end

-------------------------------------------------------------------------------
--  The live palette
-------------------------------------------------------------------------------
local function CreateLiveView()
    if liveView then return liveView end
    liveView = ns.CreatePaletteView(UIParent, { frame = liveFrame, live = true })
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
        secureHeader = CreateFrame("Frame", "EUIQuickdrawSecureHeader",
            UIParent, "SecureHandlerBaseTemplate")
    end
    return secureHeader
end

-- One wheel tick. This is the ONLY place a LIVE strip's index is advanced: an
-- addon may not write these attributes once the player is in combat. The
-- options preview never comes through here -- its wheel jumps the insecure
-- view with SetFanCenter.
local SNIPPET_WHEEL = [==[
    if not self:GetAttribute("eqdOpen") then
        -- Nothing has this open, so it must stop eating camera zoom. This is the
        -- self-heal for a palette that never saw its key-up -- a zone change or
        -- a taxi swallowing the release -- and it costs one notch of zoom.
        self:Hide()
        return false
    end
    local n = tonumber(self:GetAttribute("eqdShown")) or 0
    if n < 1 then return false end

    local delta = offset
    if self:GetAttribute("eqdInvert") then delta = -delta end
    -- Scrolling up travels toward earlier entries, the direction they are drawn
    -- in for a vertical strip, and the natural reading order for a horizontal
    -- one.
    local step = -1
    if delta <= 0 then step = 1 end

    -- The press seeds this at 1, the entry the strip opens centred on, so every
    -- tick is a plain step from wherever the strip already is. The `or 1` is for
    -- a tick that arrives with no press behind it at all.
    local t = (tonumber(self:GetAttribute("eqdFanTarget")) or 1) + step
    self:SetAttribute("eqdFanTarget", t)

    -- Hover arming has to follow the strip as it slides: a tick puts a
    -- different slot under a stationary pointer, and neither the slide nor a
    -- Show raises any motion event for the lattice gate the pointer is
    -- already inside. So every tick re-derives the armed claim from the
    -- pointer's own lattice cell, exactly the way the gates' OnEnter does --
    -- and like it, leaves the arming alone when the pointer is not on the
    -- strip at all, which is the sticky reach.
    local oi = self:GetAttribute("eqdOwnerIdx")
    local btn = oi and self:GetFrameRef("btn" .. oi)
    if btn and btn:GetAttribute("eqdFanMouse") then
        local ui = self:GetFrameRef("ui")
        local x, y
        if ui then x, y = ui:GetMousePosition() end
        if x then
            local cx, cy = x * ui:GetWidth(), y * ui:GetHeight()
            local s = tonumber(btn:GetAttribute("eqdScale")) or 1
            if s <= 0 then s = 1 end
            local hx, hy
            if btn:GetAttribute("eqdFixed") then
                hx = ui:GetWidth() * 0.5 + (tonumber(btn:GetAttribute("eqdPosX")) or 0)
                hy = ui:GetHeight() * 0.5 + (tonumber(btn:GetAttribute("eqdPosY")) or 0)
            else
                hx = tonumber(btn:GetAttribute("eqdGX"))
                hy = tonumber(btn:GetAttribute("eqdGY"))
            end
            local pitch = tonumber(btn:GetAttribute("eqdPitch")) or 0
            if hx and pitch > 0 then
                local along = (cx - hx) / s
                local across = (cy - hy) / s
                if not btn:GetAttribute("eqdFanHoriz") then
                    along, across = -across, along
                end
                local band = tonumber(btn:GetAttribute("eqdFanBand")) or 0
                local win = tonumber(btn:GetAttribute("eqdFanWin")) or 0
                local d = floor(along / pitch + 0.5)
                if abs(across) <= band and abs(along - d * pitch) <= band
                   and abs(d) <= win + 0.5 and d * 2 <= n and -d * 2 < n then
                    btn:SetAttribute("eqdArmed",
                        tonumber(btn:GetAttribute("eqdClaimAt" .. (((t - 1 + d) % n) + 1))))
                end
            end
        end
    end
    return false
]==]

local function EnsureScrollCatcher()
    if scrollCatcher then return scrollCatcher end
    local f = CreateFrame("Frame", "EUIQuickdrawScrollCatcher", UIParent,
        "SecureHandlerBaseTemplate")
    f:SetAllPoints(UIParent)
    f:SetFrameStrata(LIVE_STRATA)
    f:SetFrameLevel(1)
    f:EnableMouseWheel(true)
    -- The wheel snippet re-derives the hover-armed nest under a stationary
    -- pointer, and reads the cursor the same way every other snippet does.
    SecureHandlerSetFrameRef(f, "ui", UIParent)
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
    -- HARDCODED flick-ahead (the settings were removed): the arc stays
    -- invisible for `delay` seconds after the press, then fades in over
    -- `fade`. Selection is live the whole time -- only the drawing waits.
    -- PARKED AT 0/0: the slam-open (AdvanceSlam) is the arc's reveal now and
    -- has to be visible from the press itself; raise the pair to bring the
    -- flick hold back on top of it.
    if liveView:IsFan() then return 1 end
    local delay, fade = 0, 0
    local t = GetTime() - openedAt
    if t <= delay then return 0 end
    if fade <= 0 or t >= delay + fade then return 1 end
    return (t - delay) / fade
end

-- The last alpha actually applied. Nothing else writes the live frame's alpha,
-- so a repeat is a redraw of the frame and everything under it for a value it
-- already carries -- and past the flick-ahead fade every frame of a hold is a
-- repeat. The strip holds full brightness however far the pointer travels:
-- leaving it speaks through the selection clearing, never through a dim.
local paletteAlpha = nil

local function UpdatePaletteAlpha()
    local a = FlickAlpha()
    if a == paletteAlpha then return end
    paletteAlpha = a
    liveView:GetFrame():SetAlpha(a)
end

local function OnPaletteUpdate(_, elapsed)
    local now = GetTime()
    -- A latched menu has no key held, so the backstop that catches a lost
    -- key-up is not what it needs -- it is meant to sit there while the player
    -- decides. It still gets one, well past the held palette's: a menu left
    -- open holds the Select key, which may be a plain mouse button.
    --
    -- Read off the button rather than off the profile: the latch is the
    -- SNIPPET's answer, and a palette with the switch on but no Select key set
    -- never latched at all. Reading an attribute is unrestricted in combat.
    local btn = secureButtons[liveView:GetPaletteIndex()]
    local latched = btn and btn:GetAttribute("eqdLatched")
    -- ns.Close is INSECURE, and a latched menu's teardown -- the two bindings,
    -- the ownership stamp, the gates -- is every one of the protected calls a
    -- fight refuses. Timing out mid-fight would put the menu off screen and
    -- leave the Select key claimed until PLAYER_REGEN_ENABLED picked the rest
    -- up, so the timer simply does not run there: it takes effect the moment
    -- the fight ends, and this handler is still ticking to notice. A menu the
    -- player latched open and took into a fight is one they asked for.
    --
    -- The held palette's own backstop is unaffected -- its close rides a key
    -- release through the sandbox and was never refused anything.
    if not (latched and InCombatLockdown()) then
        if now - openedAt > (latched and LATCH_TIMEOUT or OPEN_TIMEOUT) then
            ns.Close()
            return
        end
    end
    if not liveView:SteerUnchanged() then
        if liveView:IsPointerLayout() then
            liveView:AdvanceGrid()
        elseif liveView:IsFan() then
            liveView:AdvanceFan(elapsed)
        else
            liveView:AdvanceArc()
        end
    end
    -- Time-based, so it runs even on the frames the steer skip above took.
    UpdatePaletteAlpha()
    -- Outside the steer skip for the same reason: a modifier goes down without
    -- the cursor moving, and that is the whole gesture this answers.
    liveView:AdvanceLiveIcons()
    liveView:AdvancePendingIcons()
    -- Outside the steer skip: the connector line's grow-in and sweep both
    -- keep moving under a cursor that is holding still. Costs two table
    -- reads per frame when no line is up.
    liveView:AdvanceNeedle(now)
    -- After the steering, which repaints alphas flat: the slam's lerp has to
    -- own the frame's final word while it runs.
    liveView:AdvanceSlam(now)
end

-- forceFixed: ignore CURSOR mode and place the palette at its fixed position.
-- Nothing passes it since the full-screen editor was retired; it stays because
-- on-screen drag positioning is being reworked and needs exactly this. Fixed
-- Position mode itself goes through the same branch via p.centerMode.
local function PositionPalette(forceFixed)
    -- The palette that is about to be shown, so a palette pinned to a corner
    -- and one that opens at the cursor can sit side by side in one profile.
    -- Layout has already moved the view onto it.
    local p = liveView:P()
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
        -- opens on costs no ticks at all and the first tick moves by one --
        -- opened unselected, the starting entry would be the one entry that
        -- cannot be chosen without scrolling off it and back. Cancelling is
        -- FanCancelled's job -- throw the pointer clear of the strip.
        liveView:ArmMovementGate()
        liveView.fanTarget = 1
        liveView.fanVisual = 1
        liveView:ApplyFanGeometry()
        -- Guarded: an empty palette has no entry 1 to select, and painting one
        -- would caption the hub with a slot that is not drawn. Under exclusive
        -- hover (Select Action with Mouse) the first paint holds in cursor
        -- mode -- the strip opens centred on the pointer, so entry 1 IS the
        -- hovered one -- but a PINNED strip may open nowhere near the cursor,
        -- and there the first tick's own hover test owns the answer.
        local pOpen = liveView:P()
        local hoverOnly = (pOpen and pOpen.fanMouseSelect) ~= false
        local pinned = pOpen and pOpen.centerMode == "SCREEN"
        local paintFirst = liveView:ShownCount() > 0
            and not (hoverOnly and pinned)
        liveView:SetSelection(paintFirst and 1 or nil)
    else
        -- Through the same pass every later frame goes through, so the ring is
        -- drawn on the first frame exactly as the tick would draw it. With the
        -- gate just armed that is evenly, and nothing selected.
        liveView:ArmMovementGate()
        liveView:AdvanceArc()
        -- Slam-open, from the press itself: the first step runs NOW so the
        -- launch positions are what this frame shows, never a settled ring
        -- for one frame first.
        liveView._slamT0 = openedAt
        liveView:AdvanceSlam(openedAt)
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

-- The rest of what a release puts away -- the scroll catcher, the ownership
-- stamp, and every arming gate the palette had up -- for the closes that never
-- see a key-up. Assigned further down, beside the gate pool it hides, and the
-- index of a close combat refused is left here for PLAYER_REGEN_ENABLED: every
-- frame it touches is protected, so mid-fight there is nothing it may do.
local ReleaseSecureState
local secureCloseDirty

function ns.Close()
    if not liveView then return end
    local palette = liveView:GetFrame()
    if not palette:IsShown() then
        ReleaseEscape()
        return
    end
    palette:SetScript("OnUpdate", nil)
    palette:Hide()
    ReleaseSecureState(liveView:GetPaletteIndex())
    ReleaseEscape()
    -- Both, always together. fanVisual left behind at the strip's last centre
    -- while fanTarget went to nil reads as a settle that can never finish, and
    -- SteerUnchanged takes that to mean the geometry is still moving -- so one
    -- scroll-fan open would cost every later open of ANY layout its per-frame
    -- skip for the rest of the session. Nothing needs it to survive the close:
    -- the strip's own re-seeds it, and both readers default it.
    liveView.fanTarget = nil
    liveView.fanVisual = nil
    liveView:SetSelection(nil)
end

-------------------------------------------------------------------------------
--  Secure activation
-------------------------------------------------------------------------------
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
-- gates" section further down for what arming means. Three hand-kept copies
-- would only have to agree with each other, and the live view reads eqdArmed
-- and nothing else -- so a copy that forgot to hide a neighbour's gate or to
-- show its own regions would draw one claim while the release fired from
-- another.
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

    cancelButton = btn
    return btn
end

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
-- local: this file sits within a couple of Lua's ceiling of 200.
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
-- this file sits within a couple of Lua's ceiling of 200.
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

-- Declared up beside ns.Close, which is the only caller: the closes that never
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
    -- "Arming gates" section above GetSecureButton for what they are for.
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
        -- it: the main chunk is at Lua's ceiling of 200 locals.
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
        -- Inline for the reason the registration above it is: the main chunk is
        -- at Lua's ceiling of 200 locals.
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
    db = EllesmereUI.Lite.NewDB("EllesmereUIQuickdrawDB", DB_DEFAULTS)
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
    -- any of them. All it holds is the one empty frame the main chunk makes.
    if not p.enabled then return end

    for i = 1, PaletteCount() do EnsurePalette(i) end
    ns.UpdateBindings()
    PushAllPalettes()
    SetEventsEnabled(true)
end

