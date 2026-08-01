# C_CooldownViewer Compatibility Layer

This document outlines the WotLK 3.3.5a compatibility implementation for EllesmereUI's Cooldown Manager.

## Implemented API Contract
- `C_CooldownViewer.RegisterDefinition(def)`
  - Adds a static entry. Uses strict schema validation.
- `C_CooldownViewer.GetCooldownViewerCategorySet(category, includeUnknown)`
  - Returns array of IDs, utilizing deterministic sorting.
- `C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)`
  - Returns a mock `info` block holding `cooldownID`, `spellID`, and `overrideSpellID`.
  - (Note: Includes UI state values that the EllesmereUI renderer expects downstream natively, avoiding an extra object wrapper where possible).

## Implemented Global Pools
The core EllesmereUI renderer accesses these global frames expecting `itemFramePool:EnumerateActive()`:
- `EssentialCooldownViewer`
- `UtilityCooldownViewer`
- `BuffIconCooldownViewer`
- `BuffBarCooldownViewer`

These pools return a persistent mock Adapter carrying:
- `cooldownID`
- `cooldownInfo`
- `GetSpellID()`
- `GetAuraSpellID()`

## Omissions & Approximations
- **Retail Edit Mode**: Not implemented.
- **auraInstanceID**: WotLK does not support unique aura identifiers. The script caches `UNIT_AURA` values using `spellID` keys. Overlapping identical aura applications (e.g. tracking both self-applied and other-applied) may resolve unpredictably.
- **Runtime Callbacks**: We drive evaluation purely off WotLK events (`UNIT_AURA`, `SPELL_UPDATE_COOLDOWN`, `SPELLS_CHANGED`, etc.) rather than Retail callbacks.

*Note: Runtime UI update behaviors require in-client verification.*
