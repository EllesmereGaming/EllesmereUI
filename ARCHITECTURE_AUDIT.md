# Architecture Audit

## 1. Repository Module Map
* EllesmereUI (Core framework, Locale, Migrations, Profile handling)
* EllesmereUIActionBars (Action bar enhancements)
* EllesmereUIAuraBuffReminders (Aura/Buff tracking)
* EllesmereUIBags (Bag UI adjustments)
* EllesmereUIBasics (Basic UI enhancements)
* EllesmereUIBlizzardSkin (Skinning for default Blizzard frames)
* EllesmereUIChat (Chat improvements)
* EllesmereUICooldownManager (The primary Cooldown tracking system; Heavily uses Retail APIs)
* EllesmereUIDamageMeters (Damage meter enhancements)
* EllesmereUIDataBars (XP/Reputation bars)
* EllesmereUIFriends (Friend list improvements)
* EllesmereUIMinimap (Minimap styling)
* EllesmereUIMythicTimer (M+ Timer - mostly irrelevant in WotLK but might have some features)
* EllesmereUINameplates (Nameplate modifications)
* EllesmereUIQoL (Quality of life features, movement alerts, auto logging)
* EllesmereUIQuestTracker (Quest tracker improvements)
* EllesmereUIRaidFrames (Raid frame enhancements, buff/debuff managers)
* EllesmereUIResourceBars (Resource tracking; uses Retail `C_CooldownViewer` for procs)
* EllesmereUIUnitFrames (Player/Target/Party frames)

## 2. TOC Load Order
The `EllesmereUI.toc` loads in this order:
1. Libraries (LibStub, CallbackHandler, LibSharedMedia, LibDeflate, LibKeystone)
2. Core Polyfills (`Compatibility/*`)
3. EUICompat Layer (`EllesmereUI_Compat/*`)
4. Core Framework (`EllesmereUI_Lite.lua`, `EllesmereUI_Locale.lua`)
5. Locales
6. Dev Tools (`EllesmereUI_LocaleDev.lua`)
7. Migration (`EllesmereUI_Migration.lua`)
8. Startup (`EllesmereUI_Startup.lua`)
9. Shared Code (`EllesmereUI.lua`, `EllesmereUI_Ticker.lua`, widgets, options)
10. Sub-addons are loaded dynamically via the WoW client since they have their own `.toc` files (e.g. `EllesmereUICooldownManager.toc`)

## 3. Retail-only API inventory
* `C_CooldownViewer` (Highly prevalent in CooldownManager)
* `C_Spell.GetSpellDescription`
* `C_PaperDollInfo.GetStaggerPercentage`, `.GetArmor`
* `C_SpecializationInfo.GetSpecializationInfo`
* `C_StringUtil.CreateNumericRuleFormatter`
* `C_CreatureInfo.GetClassInfo`
* `C_CurveUtil.CreateColorCurve`
* `GetAverageItemLevel`
* `UnitSpellHaste`, `GetMasteryEffect`, `GetVersatilityBonus`, `GetLifesteal`, `GetAvoidance`, `GetSpeed`
* `AbbreviateNumbers`, `BreakUpLargeNumbers`

## 4. Retail global-frame inventory
* Retail CDM frames (we've caught this in `EllesmereUICdmSpellPicker.lua` and `EllesmereUICooldownManager.lua`)

## 5. Retail enum inventory
* `CR_MASTERY`, `CR_VERSATILITY_DAMAGE_DONE`, `CR_VERSATILITY_DAMAGE_TAKEN`, `CR_LIFESTEAL`, `CR_AVOIDANCE`, `CR_SPEED`

## 6. Retail mixin and template inventory
* Mostly standard UI templates.

## 7. Lua-version incompatibility inventory
* `lua5.1` is the target runtime.

## 8. Modules that can work unchanged
* Chat, Friends, Minimap, QoL, and DataBars seem mostly independent of massive Retail specific systems, though some minor API tweaks in Core apply to them.

## 9. Modules requiring wrappers
* EllesmereUIResourceBars (Needs `C_CooldownViewer` wrapping for its EM/Proc tracking)

## 10. Modules requiring major replacement
* EllesmereUICooldownManager (Needs a total internal provider shift away from `C_CooldownViewer`)

## 11. Proposed compatibility-layer file structure
```text
EllesmereUI_Compat/
    Init.lua
    Client.lua
    Events.lua
    Enum.lua
    Spell.lua
    Aura.lua
    Talents.lua
    Cooldown.lua
    Frames.lua
    Secure.lua
    CDM/
        Provider.lua
        RetailProvider.lua
        WotLKProvider.lua
        WotLKData.lua
        RuntimeTracker.lua
        Data/
          DeathKnight.lua
          Druid.lua
          Hunter.lua
          Mage.lua
          Paladin.lua
          Priest.lua
          Rogue.lua
          Shaman.lua
          Warlock.lua
          Warrior.lua
          Items.lua
          Racials.lua
```

## 12. Recommended implementation order
1. Setup Compatibility Layer Skeleton.
2. Initialize Provider Base Classes.
3. Replace `C_CooldownViewer` calls with `EUICompat.CDM.ActiveProvider`.
4. Provide WotLK class data one at a time starting with Death Knight.
