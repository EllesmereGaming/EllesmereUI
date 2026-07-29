<!-- Thanks for contributing! Please read .github/CONTRIBUTING.md first --
     the checklist below mirrors the acceptance criteria used in review. -->

## What does this PR do?

<!-- User-facing description: what changes for the player? -->

## How was it tested?

<!-- Client build, what you tested in game, etc. -->

## Screenshots

<!-- Required for any visual change: before + after. Delete if not visual. -->

## Checklist

<!-- Check what applies; mark N/A where it genuinely does not. -->

- [ ] New settings default **OFF** (no behavior change without opt-in)
- [ ] Zero cost while disabled: no events registered, no polling, no hooks doing work, no frames built
- [ ] Cheap while enabled: event-driven (no polling, no timer-based logic, no per-frame allocations)
- [ ] No writes onto Blizzard-owned frames (weak-table pattern used); `HookScript`/`hooksecurefunc` only, never `SetScript` on Blizzard frames
- [ ] Tested in-game, works on live retail; no load errors on the 12.1 PTR client
