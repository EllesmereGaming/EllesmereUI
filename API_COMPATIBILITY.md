# API Compatibility Status

This document tracks the compatibility status of Retail APIs used by EllesmereUI and their WotLK equivalents.

## C_CooldownViewer

* **Status**: SHIMMED (Internal Provider)
* **Details**: The `C_CooldownViewer` namespace is used extensively in EllesmereUI's Cooldown Manager to retrieve categorized abilities, check cooldown states, and resolve spell IDs. We have introduced an internal provider interface (`EUICompat.CDM.ProviderBase`) to abstract this away.
* **Retail Implementation**: Wraps `C_CooldownViewer` calls directly.
* **WotLK Implementation**: Uses a static dataset curated per class and resolves known spells and runtime state via `GetSpellCooldown`, `GetSpellCharges`, and aura scanning.
* **Affected Modules**:
  * `EllesmereUICooldownManager`
  * `EllesmereUIResourceBars`

## C_Spell

* **Status**: SHIMMED
* **Details**: Used for getting spell info, textures, etc.
* **WotLK Implementation**: Global wrappers implemented in `EllesmereUI_Compat/Spell.lua`.

## C_UnitAuras

* **Status**: SHIMMED
* **Details**: Retail aura API.
* **WotLK Implementation**: Global wrappers implemented in `EllesmereUI_Compat/Aura.lua`, using `UnitAura` under the hood.
