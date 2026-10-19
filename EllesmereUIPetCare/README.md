# EllesmereUI Pet Care

A separate hunter QoL addon for WoW Forever, integrated into EllesmereUI's QoL Addons list. Requires EllesmereUI and its Unit Frames addon.

Enable **Pet Care → Pet Feeding → Enable Pet Feeding**. The pet happiness icon must also be enabled under **Unit Frames → Pet**. `/epet` opens this module.

- Left-click the pet happiness icon to feed the selected suitable food only while its feeding glow is active. With no glow, both normal and Shift-left-click do nothing.
- While glowing, Shift-left-click selects the next available food without feeding it.
- Hover for the selected food, total carried quantity, pet mood and diet.
- A happiness-icon preview in settings demonstrates the selected glow. The eye icon beside the warning cog/toggle toggles a warning even when the pet is happy; the warning cog adjusts position and font size live. Test warnings stop on combat, module/page changes, closing, or collapsing settings.
- A shared Ellesmere glow highlights feeding opportunities; its style, color and pixel-glow settings use the normal glow picker.
- Optional on-screen text warns when your pet is unhappy or content. Its cog controls the happiness threshold, font size and offsets; it hides while eating or in combat, and defaults off.
- The glow pauses during Feed Pet Effect; a cooldown sweep shows its remaining duration.
- The secure feeding button hides in combat. Secure configuration changes wait through Ellesmere's combat queue.

Food selection supports largest/smallest total quantity or highest food level, ordered preferred IDs, excluded IDs, preferred-only mode, cooked/raw-food filters, and custom diet/level overrides. Exclusions always win. Manual selection persists until that food is unavailable or the selection/settings are reset. Only eligible carried stacks are used, with no bank scanning.

The default pool is staple vendor food. Other cooked food, raw meat and raw fish are opt-in. Cooked food can include valuable buff food: exclude items you want to keep. Quest-tagged and locked stacks are skipped, as are foods more than 30 levels below the pet. The game remains the authority on whether custom food can be eaten.

Both feeding and food-database entries are profile-aware. The feature is off by default and has no active event handlers while off. Food data is loaded only when enabled or when its database page is opened.

## Data and implementation

This is original code. No Feed_Me source or databases are included. Feed_Me is All Rights Reserved.

Food metadata was extracted from the public game data for Forever build **1.60.1.70450**:

- [Item](https://wago.tools/db2/Item?build=1.60.1.70450): `ItemPetFoodID`, item class.
- [ItemSparse](https://wago.tools/db2/ItemSparse?build=1.60.1.70450): item level, quality and display name.
- [ItemPetFood](https://wago.tools/db2/ItemPetFood?build=1.60.1.70450): localized diet categories in eleven locales.

The bundled catalog contains 317 common/poor-quality food records from consumables and trade goods, including 36 staple vendor items. The model combines that metadata with the live pet diet and carried stacks. Custom entries allow new Forever foods to be added without editing Lua.

Secure actions follow Blizzard's `SecureActionButtonTemplate`; pet state is read through `C_PetInfo`, `C_SpellBook` and `C_UnitAuras`.

## Validation

Run from the repository root:

```
lua .tools/tests/test_pet_care.lua
python .tools/guardrails.py --base origin/main
```

Automated tests cover diet localization, filtering, priorities, aggregation, custom food, cycling, the secure macro, feeding-effect suppression, and deferring protected writes in combat. Extended in-game validation remains useful for additional glow styles, profile changes and the custom food editor. The tests do not replace client-side taint checks.

## Reported in-game checks

User tested on WoW Forever beta: feeding works, food cycling works, and combat stops the glow. Screenshots show the settings, the active feeding tooltip, and the happy/not-hungry tooltip. The user also confirmed that the screen-warning preview works after the font initialization fix and supplied an updated screenshot with the centered glow preview and warning eye/cog controls.
