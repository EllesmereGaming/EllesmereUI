# CDM collision regressions

Run `python tests/run_cdm_collision_tests.py` with Python 3 and Node/npm available.
The runner uses Fengari through `npx`, loads the production spell picker, and
extracts the production routing and repopulation functions into a temporary Lua
module. No WoW installation or SavedVariables are read or changed.

Coverage includes independent cooldown slot placement, migration, ordinary talent
overrides, absent siblings, ghosting and restoration, hosted buffs, and repopulation.
The mocks represent distinct Blizzard cooldownIDs in one base/override family.
They do not establish the live Beacon cooldownIDs, secret-value behavior, visual
ordering, or persistence across actual WoW reloads and talent swaps.

Redundant-override cases use supplied live metadata for native Virtue (29265)
and Light overridden by Virtue (90506). Suppression applies only to explicit
cooldownID claims when a known native replacement also exists in a live viewer
pool. Saved assignments stay intact. Plain spell-ID assignments are outside this
rule. Tests cover missing/invisible replacements, combat metadata caching, talent
changes, and route cache invalidation; actual in-game rendering remains manual.
