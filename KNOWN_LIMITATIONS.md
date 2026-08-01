# Known Limitations

This document tracks known limitations of the EllesmereUI Midnight-to-WotLK backport.

## Cooldown Manager
* **Aura Instance IDs**: WotLK does not support stable `auraInstanceID`s. Auras are currently matched by `spellID` and unit. This may cause issues with multiple applications of the same aura from different sources.
* **Charges**: Charge support is dependent on `GetSpellCharges`, which may not cover all pseudo-charge mechanics in WotLK.
