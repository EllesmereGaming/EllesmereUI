Loadout Manager
Version: 2.7.6-lm-120005

NOTE: the addon folder and saved variables keep the InstanceGearSwap name so
your existing assignments carry over. Only the display name and slash changed.

This addon automatically applies assigned Blizzard Equipment Manager gear sets and saved talent loadouts when you enter a new instance context.

Important behavior in this build:
- Automatic swaps only run when you enter a new instance/dungeon/raid/PvP/scenario context.
- It no longer re-checks repeatedly when combat ends, when your spec changes, or when equipment/talent events fire.
- If a swap is attempted while you are already in combat, it queues that one swap and applies it once after combat.
- /reload or initial login inside an instance seeds the current instance key without auto-swapping, to avoid firing during combat.
- Manual Check Now and Equip/Load still work.
- When the addon loads a talent loadout, or when your player specialization changes, a large center-screen warning appears: DONT MOVE - CHANGING SPECS.
- Use /lm warning to test the warning display.

EllesmereUI integration:
- The EllesmereUI house style is built in: flat dark window and panels, EUI-spec
  buttons, checkboxes, inputs and dropdowns, striped assignment rows, and the
  accent-styled spec-change banner all render out of the box with no
  dependencies -- there is no stock Blizzard fallback look anymore.
- With EllesmereUI installed, fonts resolve to its Expressway/UI font and every
  accent color (window highlights, checkbox checks, chat output) follows the
  user's EllesmereUI theme automatically, even if EUI's skinning is disabled.
- When EUI's third-party skinning is active (Blizz UI Enhanced > Blizzard
  Window Skins > Third-Party Addons, on by default), the window is handed to
  EUI's own skin engine, so it tracks live theme/accent changes and the Modern
  vs EllesmereUI window styles exactly.

Open World default:
- The "Open World" row in Type Defaults is applied when you LEAVE an instance,
  so you can revert to a questing/world set automatically. Leave it empty and
  nothing changes on exit - existing setups are unaffected.
- It fires once per exit, not every time you cross a zone border outdoors.

Delves and Timewalking:
- Delves (which the game reports as scenarios) and Timewalking dungeons and
  raids have their own rows, and beat the Scenario / Dungeon / Raid defaults.

Swap verification:
- After a gear swap completes the addon checks the set actually went on, and
  warns if items are missing (commonly still in the bank or void storage)
  rather than letting you find out at the pull.

Mythic+ defaults:
- A dedicated "Mythic+ Keystone" row sits in Type Defaults. Mythic (M0) and
  Keystone-difficulty dungeons resolve it before the general Dungeon / Party
  default, per spec like everything else.
- While a keystone is actively running, gear and talents are locked by the
  game; the addon detects this and skips swaps with a clear message instead
  of failing silently.

Spec-change warning:
- The themed "DONT MOVE - CHANGING SPECS" panel is shown as before.
- Blizzard's orange raid-warning text (the same channel boss mods use) is no
  longer sent; the themed panel covers it. /lm raidwarning on restores it.
- /lm warning on|off toggles the themed panel; /lm testwarning previews
  whichever outputs are enabled.

Performance:
- The window is only rebuilt while it is actually open; events that arrive
  while it is closed mark it for refresh instead of rebuilding it, and the
  refresh happens when you next open it.
- Events that fire together (equipment set changed, swap finished, loadout
  changed) coalesce into a single rebuild rather than one each.
- Swapping logic runs independently of the window, so nothing is lost by
  keeping it closed.

Talent loadout reliability:
- Loadouts are applied and committed (not staged behind the talent window's
  Apply Changes button), and the talent UI's loadout dropdown is updated to
  match what was actually applied - including when the game finishes the
  change asynchronously.
- If the game refuses the change, the addon says so and queues a retry
  instead of reporting a successful load. If the talent window is open when
  this happens, it tells you to close it and run /lm now.

Startup reliability:
- Equipment sets and talent loadouts are not cached by the game client for a
  second or two after login and after zoning into an instance. A swap firing
  in that window used to report "Could not find Equipment Manager set named X"
  for a set that exists, and the swap was dropped. The addon now waits for the
  cache (retrying, and completing immediately when EQUIPMENT_SETS_CHANGED or
  TRAIT_CONFIG_UPDATED arrives) instead of reporting an error.
- /lm verify lists any assignments that point at gear sets which no longer
  exist (renamed or deleted), with the mapping and spec scope for each.

Window and controls:
- Every button, checkbox and row has a tooltip explaining exactly what it does.
- Button names state their scope: Save (Any Diff) vs Save (This Diff), and the
  matching Clear buttons; Save by ID for the manual mapping section.
- Slash command is /lm (also /loadoutmanager; /igs and /ilm still work).
- The window can be opened from the minimap addon compartment.
- /lm scale 0.5-2.0 resizes and saves the window scale.
- Dropdown menus are custom flat house-style menus (with gear set icons)
  instead of the stock Blizzard dropdowns.
- "Copy from..." in the Assign for row copies all assignments from another
  spec (or All Specs) into the current tab; talent entries belonging to other
  specs are skipped and reported.
- Clearing assignments prints exactly what was removed.

Per-specialization defaults:
- The window has "Assign for" tabs: All Specs plus one tab per specialization
  (e.g. Holy / Protection / Retribution). The active tab decides where Assign
  Current / Assign +Diff / Map / type-row clicks save, and which assignments
  the Type Defaults rows and Saved Mappings list show.
- The window opens on your current spec's tab and follows you when you change
  spec while it is open.
- On entering an instance the addon reads your current specialization and
  resolves assignments per specificity level (instance+difficulty, then
  instance, then type default) -- your spec's assignment first, then the
  All Specs layer. All assignments made before this update live in the
  All Specs layer, so existing setups keep working; spec tabs override them
  only where you set something.
- Spec swap (on by default, /lm specswap on|off): changing specialization
  inside an instance re-runs the swap for the new spec, so switching
  Retribution -> Holy mid-run equips and loads your Holy defaults for that
  content.
- Talent loadouts belong to a spec: assigning talents into a different spec's
  tab is skipped with a note (switch to that spec to pick its loadouts), and
  an All Specs talent entry only fires for the spec it was saved from. Gear
  sets have no such restriction.
- Slash assignment commands (/lm set, /lm type, ...) always write to the
  All Specs layer.

Themed window background:
- With EllesmereUI installed, the window uses EllesmereUI's own background
  artwork and follows your active EUI theme: EllesmereUI, Horde, Alliance,
  Faction (Auto), Midnight, and Dark use their dedicated art; Class Colored and
  Custom Color tint the art with your accent, exactly like EUI's own panels.
  Theme changes apply live (and every time the window opens).
- Without EllesmereUI the window keeps its flat dark shell.

Accent colors:
- All highlight colors resolve live from EllesmereUI (its skinning engine when
  active, otherwise the framework's own accent getter), and re-sync every time
  the window opens -- so theme or accent changes in EUI carry over.

Slash commands:
/lm or /ilm - Open UI
/lm now - Manual check now
/lm current - Show current instance ID/type/difficulty
/lm sets - List gear sets
/lm talents - List talent loadouts
/lm warning - Test the spec-change warning
