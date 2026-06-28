# CDM Spell Layouts — System Briefing & Review Request

You are reviewing a subsystem of the **EllesmereUI** World of Warcraft addon (Lua 5.1,
WoW Midnight 12.0+). You have **no prior context**. Read this briefing, then review the
code as instructed.

## ⚠️ How to review (important)

- **Do NOT trust or read the code comments.** Comments may rationalize a bug or describe
  intent that the code doesn't actually implement. Read **only the executable code** and
  verify its behavior from first principles against the design below.
- Focus **only on the functions listed in the "Code to review" section** — that's the
  recently changed code. Run `git diff` to see uncommitted changes, but note other
  unrelated files may also be modified; stick to the four files/functions named below.
- For each function, ask: *Does this code, line by line, actually enforce the invariants?*
  Look for ordering bugs, both-state bugs, nil/secret-value hazards, stale-cache hazards,
  and behavior changes that would affect users who never touch this feature.
- This is Lua 5.1: no `goto`/labels. The addon uses
  `StoreVariantValue`/`ResolveVariantValue`/`FindVariantIndexInList` (variant-family aware
  spell matching: a spell + its base + override forms are treated as one).

## What the system is

**CDM** = Cooldown Manager. Blizzard has a native "cooldown viewer" that shows tracked
spells in three pools: **Essential** cooldowns, **Utility** cooldowns, and **Tracked
Buffs**. EllesmereUI intercepts those live frames and redistributes them onto its own
custom bars.

**Spell Layouts** are a profile-like system for *which spells sit on which bars*. Key
design points:

1. **Two-part storage, split by ownership:**
   - **Bar definitions** (the bar itself: key, size, position, enabled, barType) live in
     the **EUI profile**: `ECME.db.profile.cdmBars.bars[]` (+ `cdmBarPositions`). Per-profile.
   - **Spell content** (which spells on which bar, per-spell settings) lives in the
     **layout**:
     `EllesmereUIDB.spellAssignments.profiles[<layoutName>].specProfiles[<specID>].barSpells[<barKey>]`
     `= { assignedSpells = {spellID,...}, spellSettings = {...}, ... }`.
   - A bar's spells render only if its **key exists in both** the profile's
     `cdmBars.bars` and the layout's `barSpells`.

2. **Account-wide, detached from profiles.** There is ONE active layout pointer:
   `spellAssignments.activeLayout`. Switching repoints it and rebuilds.
   `ns.GetActiveLayoutName()` reads it (self-heals); `ns.GetActiveSpecProfiles()` returns
   `sa.profiles[activeLayout].specProfiles`; `ns.GetBarSpellData(barKey)` returns the
   active layout's active spec's `barSpells[barKey]`. (Note: there's a LEGACY top-level
   `spellAssignments.specProfiles` that is NOT what renders — the renderer always goes
   through `profiles[activeLayout]`.)

3. **Opt-in profile bindings.** `spellAssignments.profileBindings[<euiProfile>] =
   <layoutName>`. On profile load, `ns.ApplyProfileBinding()` sets `activeLayout` to the
   bound layout *only if the profile is bound* (gated on `ns._lastBindingProfile` changing,
   so a spec/talent change on the same profile never re-applies over a manual swap).
   Unbound profiles never change the active layout. A profile binds to at most one layout.

4. **Bar keys / special bars.** `barKey` is one of: `"cooldowns"`, `"utility"`, `"buffs"`
   (the three default bars), `"__ghost_cd"` (the **ghost bar** — `isGhostBar=true`,
   `barVisibility="never"`; spells routed here are **hidden**), `"focuskick"`, or
   `custom_<...>` (user-created custom bars).

## How rendering works (the route map)

`ns.RebuildSpellRouteMap()` (in `EllesmereUICdmHooks.lua`) builds two maps,
`_divertedSpellsBuff` and `_divertedSpellsCD`, mapping `spellID -> barKey`. It writes with
`StoreVariantValue(map, sid, barKey, preserveExisting=false)` — **`false` means later
writes OVERWRITE earlier ones, so the LAST pass to claim a spell wins.** It runs in passes
over `p.cdmBars.bars`, and pass order = priority (later = higher priority).

At render time (`CollectAndReanchor`), each live Blizzard viewer frame is resolved by
`ResolveCDIDToBar(cdID, viewerDefaultBar)`: it looks up the frame's spellID (and
override/linked variants) in the divert map; if found, routes to that bar; **if not found,
falls back to `viewerDefaultBar`** (the pool it came from — cooldowns/utility/buffs). That
fallback is **"spillover"** — a tracked spell on no bar shows on its default bar. A frame
routed to the ghost bar is excluded (hidden).

**Critical:** `assignedSpells` controls **ordering and ownership**, not whether a spell
renders. Rendering is driven by live viewer frames. A spell in `assignedSpells` with no
live frame (untalented/untracked) is invisible; a live frame in no bar's `assignedSpells`
spills to its default bar.

### Intended priority (verify this is what the passes actually produce)
- For cooldown/utility family: **ghost > custom CD bars > default bars
  (cooldowns/utility)**. Rationale: a spell deliberately placed on a custom bar must beat
  the default bar; a hidden (ghosted) spell must beat everything.
- For buff family: **default buffs bar > custom buff bars** (unchanged historically).

## The "both-state" hazard (root of several bugs)

A spell should live in exactly ONE bar. But two functions append live-rendered icons back
into a bar's `assignedSpells` to keep the options preview in sync with what's on screen:
`EnsureAssignedSpells` (options panel) and `ReseedAssignedSpellsFromLiveIcons` (only via
the manual "Repopulate from Blizzard" button). If a spell spills onto the cooldowns bar
transiently (e.g., during a profile swap before the custom bar's definition is in place),
these can **materialize** it into `cooldowns.assignedSpells`, creating a "both-state": the
spell is now in both its real bar AND cooldowns. The route map then has to arbitrate, and
the wrong bar can win. This must be prevented (don't materialize a spell that's ghosted or
already on another bar) and made harmless (route-map priority).

## Import / Export (sharing layouts)

- **Export** serializes the layout's bars (cooldowns/utility/buffs/custom) and the
  custom-bar definitions, but **must NOT export the ghost bar** — the ghost is "spells the
  sharer hides," specific to the sharer's own Blizzard tracking and meaningless to an
  importer.
- **Import** recreates custom bars (reuse key if present, else recreate with a fresh key),
  copies `barSpells` **except the ghost**, and marks each imported spec with
  `_importGhostMode = true`.
- **First load of each imported spec**: `MigrateSpecToBarFilterModelV6` runs (because
  imported specs lack `_barFilterModelV6`). Starting from an empty ghost, it **ghosts every
  CD/util spell the importer tracks in Blizzard CDM that the layout does NOT place on a
  visible bar** ("ghost all tracked, reveal assigned") — making the layout the single
  source of truth, so a cooldown the importer tracks but the sharer didn't place is hidden,
  not spilled onto cooldowns. Then it stamps `_barFilterModelV6 = true` and clears
  `_importGhostMode`. The same function doubles as a legacy one-time migration for
  non-imported specs; **that legacy path must be byte-identical to before for users who
  never import** (the `_importGhostMode` field is nil for them).

## Invariants the code must uphold
1. A spell renders on exactly one bar; both-states must be prevented and, if they exist,
   arbitrated correctly (ghost > custom > default).
2. Import yields a faithful replica of the sharer's *visible* setup; anything the importer
   tracks beyond that is hidden (one-time at import).
3. **Zero behavior change for users who never import or never bind** — guards keyed on
   `_importGhostMode` must be no-ops when it's nil.
4. Bindings are strictly opt-in; an unbound profile never changes the active layout.
5. No frame leaks (popups cached + repopulated); no writing custom keys onto Blizzard frames.

## Code to review (read the current code of these only; ignore comments)

1. **`EllesmereUICooldownManager/EllesmereUICdmHooks.lua` -> `ns.RebuildSpellRouteMap`** —
   verify the pass order actually yields ghost > custom-CD > default-CD, and that
   buff-family priority is unchanged. Verify `ResolveCDIDToBar` fallback/spillover logic.
2. **`EllesmereUICooldownManager/EllesmereUICdmLayouts.lua` -> `ns.ExportSpellLayout` and
   `ns.ImportSpellLayoutString`** — verify ghost (`__ghost_cd`) is never exported and never
   imported, custom-bar key remap is sound, and every imported spec gets
   `_importGhostMode = true`. (A function `EnforceGhostPrecedence` was removed — confirm
   nothing still calls it.)
3. **`EllesmereUICooldownManager/EllesmereUICdmSpellPicker.lua` ->
   `ns.MigrateSpecToBarFilterModelV6`** — verify "ghost all tracked − assigned" is correct
   from an empty ghost, that the empty-default-bars early-out is bypassed only when
   `_importGhostMode` is set, that it clears `_importGhostMode` and sets
   `_barFilterModelV6`, and that the non-import path is unchanged. Verify the tracked-set
   union (live viewer pools + static category API) and the secret-value guards.
4. **`EllesmereUICooldownManager/EUI_CooldownManager_Options.lua`:**
   - **`EnsureAssignedSpells`** — verify the three guards on the "append live spills" loop:
     (a) skip entirely while `_importGhostMode` pending, (b) never append a ghosted spell,
     (c) never append a spell already on another bar (`claimedElsewhere`, built from the
     active spec's stored bars, variant-aware). Verify these don't suppress legitimate
     appends for normal users.
   - **`ns.ShowProfileBindingPopup`** — verify the cached/repopulated popup (no leak),
     correct checkbox state vs `GetProfileBinding`, the Save logic (`SetProfileBinding`
     add/clear, then a one-shot `ApplyProfileBinding` re-apply via
     `ns._lastBindingProfile = nil` + conditional `FullCDMRebuild` only if the active layout
     actually changed), and the clip/scroll math.
   - **`BuildSpellLayoutsPage` / `MakeLayoutRow`** — verify the "Profiles" button wiring and
     the bound-profiles subtitle, and that 5 controls fit the row.

## What I want from the review
Tell me, from the code alone: (1) any case where a spell still ends up on the wrong bar
(both-state mis-arbitration, spillover that should be dormant, custom-bar key mismatch),
(2) any way the import/first-load ghosting fails to hide a tracked-but-unplaced spell or
wrongly hides a placed one, (3) any non-import or non-binding user whose behavior changes,
(4) correctness/well-formedness issues (nil handling, secret values, frame leaks, stale
caches, Lua 5.1 violations), and (5) anything under-specified or fragile that should be
hardened.
