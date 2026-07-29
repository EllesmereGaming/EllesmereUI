# Contributing to EllesmereUI

Thanks for wanting to contribute! Pull requests are welcome. This document
explains how PRs are reviewed and the hard rules the codebase lives by, so
your change can merge quickly instead of bouncing through review rounds.

Translating the addon? That has its own guide:
[CONTRIBUTING_TRANSLATIONS.md](../CONTRIBUTING_TRANSLATIONS.md).

For a larger feature, please dm me directly on discord @ellesmere and describe
what you want to build. Review here is strict (the rules below are acceptance
criteria, not suggestions), and it is much better to align on the approach before
you write 500 lines of code.

## The five acceptance criteria

Every PR is carefully reviewed against all five. If any are not followed the
PR will either be closed with a comment, asked to be fixed, or merged and I
will make changes to it myself.

1. **Zero cost unless enabled.** If your change adds a setting, users who
   never turn it on must pay nothing: no event registrations, no hooks doing
   work, no frames created, no OnUpdate. Build lazily on first enable and
   register events only while the feature is active.

2. **Zero behavior change without opt-in.** New settings default **OFF**. A
   feature that appears for everyone after an update is a violation, even if
   it is good. Only genuine bug fixes may change behavior without opt-in.

3. **Low cost when enabled.** Opted-in features must still be cheap:
   event-driven, never OnUpdate polling; no wall-clock timers as logic gates;
   no per-frame table allocations in hot paths; small loops.

4. **Zero taint risk.** See the next section. This is the one that gets PRs
   rejected most often, and the one I will not compromise on. Any feature
   that can cause lua errors in any way will be rejected, for this reason
   I also DO NOT ACCEPT ANY PRS FOR THE CHAT MODULE due to its current
   architecture of reskinning Blizzards chat and the dangerous taint risks
   involved in that.

5. **Both clients.** One codebase serves both live servers and the PTR,
   with 12.1-specific paths gated behind `EllesmereUI.IS_121`. Your change
   must work on retail and must not error on the PTR client. If it touches
   aura rendering or anything else that diverges under `IS_121`, say so in
   the PR so the gated path can be handled. Never "improve" code inside a
   12.0-only else-branch: those branches are frozen and deleted at 12.1
   launch.

## Code style

- **Lua 5.1 only.** No `goto`, no `::labels::`.
- **ASCII only** in code, comments, and strings. No em dashes, no curly
  quotes. Multi-byte punctuation corrupts in the packaging pipeline.
- **Match the surrounding code.** Before building any options widget (row,
  slider, swatch, cog popup), find the nearest existing example in the same
  file and copy its shape. The codebase is consistent on purpose.
- **House UI systems, not Blizzard defaults:** plain-text tooltips use
  `EllesmereUI.ShowWidgetTooltip` / `HideWidgetTooltip` (item/spell tooltips
  via `GameTooltip:SetHyperlink` and friends are fine); confirmations use
  `EllesmereUI:ShowConfirmPopup`, never `StaticPopup_Show`.
- Options pages use two-slot rows (`W:DualRow`). Fill slots left to right
  with no gaps; never pass `nil` as the right slot (use
  `{ type = "label", text = "" }`); only the last row of a section may have
  an empty slot.

## PR etiquette

- One focused change per PR; keep the diff minimal.
- Screenshots (before/after) for anything visual.
- Fill in the PR template checklist honestly - "not applicable" is a fine
  answer, silence is not.
