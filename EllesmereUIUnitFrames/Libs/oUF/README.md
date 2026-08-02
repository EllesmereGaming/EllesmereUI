# oUF for World of Warcraft 3.3.5a

This is the Wrath-compatible oUF runtime used by the backported addon. Its
framework-facing API tracks oUF 13.4.5 where the 3.3.5a client can support the
same behavior.

## Compatibility provided

- Current style registration, `GetActiveStyle`, element lifecycle, and header
  visibility APIs.
- Both legacy and current `SpawnHeader` argument forms.
- Modern `oUF.Enum`, `Enum.PowerType`, and color-object methods while retaining
  numeric color-table access.
- Current aura button names and callbacks (`CreateButton`,
  `PostCreateButton`, `FilterAura`, `PostProcessAuraData`, and
  `PostUpdateButton`) backed by Wrath's indexed `UnitAura` API.
- Current tag arguments, `Tags.Vars`, `Tags.RefreshMethods`, extra units, and
  `UpdateTags`.
- `ClassPower` backed by Wrath combo points, plus modern `Totems` backed by
  Wrath's four totem slots. The legacy `ComboPoints` element remains available.
- Modern health-prediction widget names backed by bundled LibHealComm-4.0.

## Wrath-specific behavior retained

The runtime continues to use 3.3.5a events and APIs for auras, casts, power,
runes, pet happiness, group headers, vehicles, and dropdown menus. Retail-only
features such as nameplates, private auras, alternate power, stagger, summon
status, native absorb calculations, empower casts, and frame pings are intentionally
not loaded.

The reported runtime version is `13.4.5-wotlk.1`.
