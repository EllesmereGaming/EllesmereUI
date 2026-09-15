# Damage meter report checks

Requires Python and `lupa` (with its Lua 5.1 runtime):

```sh
python -m pip install lupa
python .tools/damage-meter-report-tests/run_reports.py
```

The runner compiles the damage meter and its options with Lua 5.1, exercises
the real report module against mocked WoW APIs, and executes the real header
button lifecycle against lightweight frame objects. It never controls WoW or
sends live chat. These files are excluded from addon packages by `.pkgmeta`.

Coverage includes ranked damage/healing reports; current, overall and named
segments; counts and filtered deaths; secret/empty data; UTF-8 message limits;
destination validation; ordered one-click sends; cancellation; opt-in button
creation; dialog event cleanup; and native UI factory, accent and scale contracts.
Native widget rendering and server delivery still require in-game verification.

## Live verification

1. With a fresh profile, confirm no report button appears. Enable **Damage
   Meters > Header > Enable Chat Reports** and check every window's header.
2. Open damage and healing reports for current, overall and boss segments.
   Compare the preview, totals, rates, percentages and ordering with the meter.
3. Choose five entries and click **Send Report** once. Check the header and
   available ranked rows arrive in order in Say, Party, Raid, Instance Chat,
   Guild, an authorized Officer channel, Whisper, and a joined channel.
4. Check one-player reports, a longer preview, scrolling, narrow meter headers,
   alternate accent colors, panel scales, and a non-English locale.
5. Close during a paced send, start combat, leave the destination group, disable
   reports, delete the originating window, and switch profiles. Confirm pending
   lines stop, the dialog closes as applicable, and no Lua errors appear.
6. Attach before/after screenshots of the headers, dialog and resulting chat.

Say and custom-channel sends outside an instance stay on the original click's
call stack. Other destinations use a cancellable 0.3-second interval solely
to pace the requested messages. There is no background collection, polling, or
automatic report. Blizzard chat permissions, rate limits and delivery remain
server-controlled; a successful API call is not a server acknowledgement.
