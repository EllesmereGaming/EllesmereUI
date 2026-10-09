# EllesmereUI-APL_Glow

Fork of EllesmereUI that adds an **APL Glow** to the Cooldown Manager, driven by
the APLforEUI addon. Not intended for upstream.

## What it adds

Right-click a CDM icon (CDM Bars preview) and, only when APLforEUI is installed:

- **APL Glow** - glow style (Pixel, Action Button, Auto-Cast, Shape, GCD, Modern, Classic, Blackout). Blackout prompts for an opacity and draws below the cooldown swipe/text, like the CD-state glow. Has the usual Apply to Spell / Bar / Bar (All Specs) strip.
- **APL Glow Color** - Default / Class Color / Custom, same strip.

The glow shows on the icon whose spell APLforEUI reports as next up. APLforEUI only
reports in combat, so the glow is combat-only.

## Where the code is (keep this list small)

| File | Change |
|---|---|
| `EllesmereUICooldownManager/EUI_CDM_APLGlow.lua` | New. Whole runtime (listener, matching, glow overlay). |
| `EllesmereUICooldownManager/EllesmereUICooldownManager.toc` | 1 line: loads the file above. |
| `EllesmereUICooldownManager/EUI_CDM_Icons.lua` | 3 lines in `RefreshCDMIconAppearance`: calls `ns.APLGlowRefreshIcon`. |
| `EllesmereUICooldownManager/EUI_CDM_Rebuild.lua` | 1 line: `ns.RescanAPLGlowFlag()` next to the other gate scans. |
| `EllesmereUIOptions/CooldownManager_Options/SpellPicker_Options.lua` | One `if ns.APLGlow.IsAvailable()` block after the Glow Effect Color row. |

Saved keys (per-spell settings): `aplGlow`, `aplGlowAlpha` (Blackout only), `aplGlowColor`, `aplGlowColorR/G/B`.

## Contract with APLforEUI

APLforEUI exposes `APLforEUI_API`:

- `RegisterListener(fn)` - `fn(spellID|nil, step|nil)` on every change of the next-up spell.
- `GetNextSpell()` - `spellID, step` on demand.

Without that global the menu rows are hidden and nothing in this fork registers or runs.

## Updating from upstream

```
git fetch upstream
git rebase upstream/main     # or merge
```

Conflicts, if any, can only be in the 4 small touch points above. The new file never conflicts.
EUI internals the new file relies on: `ns._hookFrameData`, `ns._ecmeFC`, `ns.ResolveSpellSettings`,
`ns.GetBarSpellData`, `ns.StartNativeGlow` / `ns.StopNativeGlow`, `ns.ForEachSavedSettingsBlock`.
