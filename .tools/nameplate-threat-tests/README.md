# Nameplate threat positioning checks

Run `python .tools/nameplate-threat-tests/run.py` with Python 3 and `lupa` installed
(the harness explicitly selects its Lua 5.1 runtime).

The harness executes the production percentage painter, positioning, cast layout
and cast show/hide callback. It covers existing inside positions, below-health
placement, live cast start/end and layout changes, Classic drop, varying cast
heights, offsets, large text, pixel snapping, pooled reuse, disable/re-enable,
missing threat data and opaque native values. It also compiles the three changed
Lua files and checks that the Essentials nameplate row exposes the new option
without exposing it on target/focus frames. These are offline checks.

## Pending live checks

On WoW Forever, enable nameplate threat text and choose Below Health Bar from
Enemy Nameplates, then verify the same value on Forever Essentials > Threat.
Check casts, channels, interrupted/finished casts, focus height, each nameplate
art style, larger font/UI scales, X/Y offsets and plate reuse. Switch between all
inside positions and Below while a cast is running. Disable/re-enable, change
profiles, and reload to verify the selected position persists. Confirm target
and focus frame position menus are unchanged. Capture before/after screenshots.

Offline mocks cannot certify rendering, combat taint or live persistence.
