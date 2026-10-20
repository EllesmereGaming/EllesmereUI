# Agent rules

Read `.github/CONTRIBUTING.md` first. It has the acceptance criteria and code style.

Run the guardrails before you commit:

```
python3 .tools/guardrails.py
```

(On Windows: `python` or `py -3`.) It checks the Lua files (`.lua` in any case, outside `Libs/` and `.tools/`) that changed since your branch left `origin/main`, uncommitted and untracked ones included. On a fork with an `upstream` remote it compares with whichever of `upstream/main` and `origin/main` the branch left more recently, and warns when that is `origin/main` while `upstream/main` lacks some of its commits: a PR to upstream is judged against `upstream/main`, so fetch `upstream` or pass `--base upstream/main`. `--base <ref>` picks another base. CI runs the same checks on every PR that touches Lua or the guardrails, and on every push to main. It needs a Lua 5.1 `luac` (`luac5.1` on PATH, or set `LUAC=/path/to/luac`). The compile and line-1 checks read every changed file; the others judge only new and changed lines, so older code is reported only once you edit it. An expired exception fails wherever it is (see Exceptions). File names must be valid UTF-8.

If you change `.tools/guardrails.py`, run its tests as well: `python3 .tools/tests/test_guardrails.py`.

## Rules and what enforces them

| Rule | Enforced by |
|---|---|
| Every Lua file compiles under Lua 5.1, with at most 200 locals in scope at once and 60 upvalues per function. One overflow stops the whole file from loading. | `guardrails.py` `check_compile` |
| Line 1 of every Lua file except `EllesmereUI_ClientGate.lua` starts with `if EUI_CLIENT_BLOCKED then return end`. | `guardrails.py` `check_client_gate` |
| Defer combat-locked work through `EllesmereUI.CombatQueue.Defer(key, fn)` (or the addon's `ns.CombatQueue`). Do not register a raw `PLAYER_REGEN_ENABLED` for it, in any form: `f:RegisterEvent`, `f.RegisterEvent(f, ...)`, `pcall`/`xpcall(f.RegisterEvent, ...)`, an event name kept in a local, an event list (or a list of `{ event = ... }` records) or a handler table keyed by event that a loop or call registers, an event appended to a list, an event helper or `EventRegistry`. A frame, list or helper that registers both `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED` tracks combat state, which is not a deferral, and passes, also when one of the two names the frame another way: the first parameter of its script handler (a function literal given to `SetScript`/`HookScript`, or a function of the same file given to them by name), a local copy of a field that holds it, a field that a local holding it is stored in, or `self` in another `:` method of the same object in the same file. A local given a new frame (`f = CreateFrame(...)`) is a new registrant. An event list written inline in an `ipairs`/`pairs` loop header or an unregister call counts only once something registers it; any other event list counts where it is written. The check does not see an event name or handler table that reaches the registration through a field, a function's parameter or return value, or another file, nor a name built at run time; those are still against this rule. | `guardrails.py` `check_combat_deferral` |
| Do not call globals that WoW Forever lacks: the legacy spec functions (`GetSpecialization`, `GetSpecializationInfo`, `GetNumSpecializationsForClassID`, `GetActiveSpecGroup`, `GetSpecializationMasterySpells`, `GetTalentInfo`) and the item, socket, coin, PvP, pet, sound and trade globals that retail keeps only as deprecation fallbacks (`GetItemInfo`, `GetItemInfoInstant`, `GetItemCount`, `GetItemIcon` and the rest of `DEPRECATED` in `guardrails.py`). Use the `C_` form the error names (`C_SpecializationInfo.*`, `C_Item.*`, ...). `GetSpecializationInfoByID` has no `C_` form: guard it and fall through to no spec. `_G.X` counts as `X`, and so do copying `X` into a local, storing it in a table or variable, and `hooksecurefunc("X", ...)`. These pass: a local bound to the `C_` form; a test of the global (`if X then`, `X and X()`, `X ~= nil`, `type(X) == "function"`), including an early exit (`if not X then ... return end`); an `IS_FOREVER` gate (`if not IS_FOREVER then`, `IS_FOREVER ~= true`, `if IS_FOREVER then ... return end`); the `else` of a test of the `C_` form. A guard carried through a variable (`local i = X and X() or 0` ... `if i > 0`) is not seen: use the `C_` form there. Files of an addon whose TOC never loads on Forever are skipped. | `guardrails.py` `check_deprecated_globals` |
| Outside `EllesmereUILocales/`, Lua is ASCII only and saved as UTF-8 without a BOM. Use `--` or a byte escape such as `\226\128\148`. | `guardrails.py` `check_ascii` |
| After you add, change or remove a string literal passed to `EllesmereUI.L("...")` or `EllesmereUI.Lf("...")`, run `bash .tools/extract-locale-keys.sh` and commit `EllesmereUILocales/_keys.txt`. | `locale-check.yml` (PRs and pushes to main) |
| Do not compare, index, or do arithmetic on secret values (12.x combat aura and unit data). Pass them straight to the widget API that accepts them. | Judgment only. No reliable mechanical check. |
| Do not write to protected Blizzard frames or call protected functions from insecure code, and do not do it in combat. Hook with `hooksecurefunc` and keep the work cosmetic. | Judgment only. No reliable mechanical check. |
| Group Finder client-side filters only dim rows with `SetAlpha`; do not hide/reorder results, replace data providers, rebuild Blizzard search rows/lists, or change selection. Skip filtering when required result/member data is nil, secret or unreadable. Combat deferral, `IsProtected` and `hooksecurefunc` do not make feeding data back into Blizzard's list taint-safe. | `guardrails.py` `check_group_finder_presentation` rejects new direct provider/rebuild/sort/selection API calls in `EllesmereUIGroupFinder/`. Indirect mutations and secrecy guards still require review. |

## Exceptions

Put an exception in a comment on the offending statement, naming the human who approved it and why. Any line of the statement counts (for a table, anywhere from its first line to its closing brace) except the inside of a function written in it: a tag there counts only for that function's own statements, so tag a call or table that holds a function on its first line, a key's line or its closing `end)` or `}` line. It does not expire:

```lua
local STOPWORDS = { ... } -- guardrails-allow: ascii by Ellesmere: Russian search stopwords
```

For a stopgap, add an expiry date right after the key. Once the date (UTC) has passed, every guardrails run fails on it wherever it is in the tree, so every later Lua PR fails until the tag is removed or its date moved:

```lua
local name = GetItemInfo(id) -- guardrails-allow: deprecated-global until 2026-12-31 by Ellesmere: retail-only path, C_Item port pending
```

Check keys: `combat-deferral`, `deprecated-global`, `ascii`. A tag is `guardrails-allow:`, colon included, in a comment; one in a string does not count. A tag fails when it has no approver or no reason, an unknown key, a bad date, or a date, the word `until` or another tag in the approver (between `by` and the next colon).

## Keeping this table

When a reviewer corrects a mistake, fix it and add the rule here. If the rule is already here and nothing enforces it, add a check to `.tools/guardrails.py` in the same change. Remove a rule when its mistake can no longer happen.
