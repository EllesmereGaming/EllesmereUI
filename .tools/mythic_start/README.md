# Mythic+ Start behavior checks

`test_mythic_start.py` loads `EllesmereUIQoL_MythicStart.lua` as a separate Lua
chunk, then runs the existing Auto Insert block and controller initialization
bridge extracted from the main file's `PLAYER_LOGIN` handler. This models the
addon files loading before login while isolating unrelated QoL features. Each
scenario runs in a fresh Lua 5.1 environment. The controller is enabled explicitly
in the general fixtures; dedicated scenarios verify its real default-off behavior.
`mythic_start_mocks.lua` supplies controllable WoW events, frames, group identities,
API responses and cancelable timers. The harness and its dependencies are outside
the addon and are not referenced by its TOC.

Install Lupa in a Python environment, then run from the repository root:

```powershell
python -m pip install lupa==2.8
python -m unittest discover -s .tools/mythic_start -p test_mythic_start.py -v
```

Set `ELLESMERE_TEST_ADDON_ROOT` to test another addon tree; the default is the
repository root. Optional local dependency directories are only import paths;
they are not included in the contribution.

The 56 checks pass on the contribution merged with current upstream
`6dffe7cf03918cfc5c73c4f07f404abf425077e0`. This validates the current
integration in the deterministic harness; future API changes still need
validation.

## Coverage

- The original Auto Insert behavior, including solo, disabled setting and an
  existing slot. Its unchanged listeners may request insertion both on Show and
  the receptacle event before the server confirms the slot.
- The master Ready/Pull Controls setting defaults off: no added frames, events,
  hooks, buttons or timers compared with running Auto Insert alone. Child
  settings cannot activate the disabled master.
- Opt-in while the keystone frame is already open; disabling during ready,
  pending/active pull or pending cancellation stops work, removes controller
  events and hides controls. Retained hooks and stale callbacks stay inert.
- Twenty enable/disable cycles reuse controls and hooks. Buttons are found by
  parent and visible label; no custom button fields are written to Blizzard's
  keystone frame.
- Optional Auto Ready and manual Ready, permissions, duplicate prevention,
  missing answers, timeout, negative answers, preemption and ambiguous initiator.
- The updated user requirement: **Ready never starts a countdown automatically**.
  One PULL button starts 5 seconds with left-click or 10 with right-click.
- Official countdown acknowledgement, complete chat sequences, cancellation,
  stale callbacks, fractional official deadlines and chat channels.
- Either left/right click during an active or pending pull cancels its countdown
  and pending Auto Start, requests official cancellation once and announces
  `Pull cancelado!` to the group. A subsequent click starts a fresh pull.
- Auto Start enabled/disabled, success, failed or restricted API calls, one start
  attempt, settings changed during a pull and disabled official Start button.
- Session close, challenge start, roster changes, leadership loss, slot removal,
  reload/world transition, combat, chat restrictions and direct profile changes.
- Lazy loading, missing APIs, Forever gate, twenty openings with no duplicate
  controls or hooks, READY and one PULL beside the official Start button.
- Instance/raid/party chat broadcasts without local EllesmereUI countdown text;
  solo retains only the official visual countdown.
- Static checks that the new block does not reference Raider.IO, PVEFrame,
  Group Finder, GameTooltip, LibMythicKeystone or LibKeystone.
- The TOC loads the controller once after the main file. Loading the separate
  module creates no frames, hooks, events or timers before login, even when
  enabled; the main login bridge initializes it. The parent client gate leaves
  the module inactive.
- Full Lua 5.1 syntax compilation of all four modified/added addon Lua files.
- The real Reset ALL implementation preserves all three Mythic+ Start settings
  for true, false and absent values, alongside existing QoL settings, friend
  data, UI scale and the graphics/uninstall restore records.

## What these checks do not establish

This is a deterministic mock harness, not a running WoW client. The visual layout,
actual taint/security behavior, server permissions, persistence across a real
`/reload`, and compatibility with enabled Raider.IO/DBM/BigWigs still require
in-game validation. Boss-mod cases here only establish that the code uses one
official countdown request and does not call a separate boss-mod API. API mocks
explicitly emit `START_PLAYER_COUNTDOWN(GUID, timeLeft, totalTime)`.
