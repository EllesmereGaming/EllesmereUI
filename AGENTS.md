# Agent rules

Read `.github/CONTRIBUTING.md` first. It has the acceptance criteria and code style.

Run the guardrails before you commit. CI runs the same command on every PR and push to main:

```
python3 .tools/guardrails.py --base origin/main
```

It needs a Lua 5.1 `luac` (`luac5.1` on PATH, or set `LUAC=/path/to/luac`).

## Rules and what enforces them

| Rule | Enforced by |
|---|---|
| Every Lua file compiles under Lua 5.1 and stays under 200 locals and 60 upvalues per function. One overflow stops the whole file from loading. | `guardrails.py` `check_compile` |
| Line 1 of every Lua file is `if EUI_CLIENT_BLOCKED then return end`. | `guardrails.py` `check_client_gate` |
| Defer combat-locked work through `EllesmereUI.CombatQueue.Defer(key, fn)` (or the addon's `ns.CombatQueue`). Do not register a raw `PLAYER_REGEN_ENABLED` for it. | `guardrails.py` `check_combat_deferral` |
| Do not call the Blizzard_Deprecated globals (`GetSpecialization`, `GetSpecializationInfo`, `GetItemInfo`, `GetItemInfoInstant`, `GetItemQualityColor`). They are nil on WoW Forever. Use the `C_SpecializationInfo.*` and `C_Item.*` forms. | `guardrails.py` `check_deprecated_globals` |
| Lua is ASCII only outside `EllesmereUILocales/`. Use `--` or a byte escape such as `\226\128\148`. | `guardrails.py` `check_ascii` |
| After you add or change an `L["..."]` key, run `bash .tools/extract-locale-keys.sh` and commit `EllesmereUILocales/_keys.txt`. | `locale-check.yml` (PRs and pushes to main) |
| Do not compare, index, or do arithmetic on secret values (12.x combat aura and unit data). Pass them straight to the widget API that accepts them. | Judgment only. No reliable mechanical check. |
| Do not write to protected Blizzard frames or call protected functions from insecure code, and do not do it in combat. Hook with `hooksecurefunc` and keep the work cosmetic. | Judgment only. No reliable mechanical check. |
| Put role text color pickers on the corresponding Show Role dropdown entries through `item.swatch`, so each picker is visible next to its role. | UI review. |

## Exceptions

Put an exception on the offending line, with an expiry date and the approving human:

```lua
f:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral until 2026-12-31 by Ellesmere: tracks combat state
```

Check keys: `combat-deferral`, `deprecated-global`, `ascii`. An expired exception fails the check.

## Keeping this table

When a reviewer corrects a mistake, fix it and add the rule here. If the rule is already here and nothing enforces it, add a check to `.tools/guardrails.py` in the same change. Remove a rule when its mistake can no longer happen.
