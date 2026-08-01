# Minimum Compatibility Contract

## C_CooldownViewer API
- `C_CooldownViewer.GetCooldownViewerCategorySet(category, includeUnknown)`
- `C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)`

## Global Viewer Pools
- `EssentialCooldownViewer`
- `UtilityCooldownViewer`
- `BuffIconCooldownViewer`
- `BuffBarCooldownViewer`

Each viewer MUST have an `itemFramePool` with an `EnumerateActive()` iterator.

## Adapter Object (Frame mock)
Objects yielded by `EnumerateActive()` MUST have:
- Field: `cooldownID`
- Field: `cooldownInfo`
- Method: `GetSpellID(self)`
- Method: `GetAuraSpellID(self)` (based on EllesmereUI usage)
