# Chat meters regression tests

From the repository root, with Python 3 and `lupa==2.8` installed:

```sh
python .tools/chat-meters-tests/run.py
```

The runner compiles each affected source file with Lua 5.1, then executes the
complete chat-host controller and the actual production placement, unlock,
visibility, sidebar and Combat Log functions against simulated WoW frames.
The runner extracts those closures because the surrounding modules initialize
the rest of the WoW UI. Their guards are not duplicated in the mock.

Covered behavior:

- No host frames, subscriptions, timers or hooks on a fresh disabled profile.
- Exactly two existing windows adopted; extra windows left standalone.
- Full header controls, transparent backgrounds and sidebar placement.
- All 32 combinations of edit/unlock/settings/resize flags and selected view.
- Native placement/size/mover writes cannot override embedding or saved geometry.
- Live geometry following without additional combat-data fetches.
- Native tab clicks, Combat Log restoration and instance/manual selection.
- Hidden Settings icon, hidden sidebar, unavailable host and chat passthrough.
- Partial/empty window rebuilds, replacements, profile opt-out and restoration.
- Disable removes event subscriptions/callbacks; re-enable reuses allocated frames.

The mocks reject writes to native chat frames/tabs and any controller timer or
method hook. Display-container alpha is exercised separately through the engine.
These tests cannot certify live-client taint, combat restrictions, rendering,
anchor resolution or performance. An in-game pass on Midnight 12.1 is still required.
The directory is excluded from release packages by the existing `.pkgmeta`.
