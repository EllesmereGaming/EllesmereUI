# EllesmereUI Plugin Glows API (for addon developers)

Let your addon glow Cooldown Manager icons. You register a named glow source
and tell EUI which spell(s) should glow right now. The player decides, per
icon, whether and how it glows: EUI adds a **Plugin Glows** entry to the icon's
right-click menu with a **Glow Style** and a **Glow Color** for each source you
registered.

```
Plugin Glows
  My Addon: Next Spell
    Glow Style      None / Pixel Glow / ... / Blackout      (Apply to Spell / Bar / Bar (All Specs))
    Glow Color      Default / Class Color / Custom          (Apply to Spell / Bar / Bar (All Specs))
```

Good fits: rotation helpers, "use this now" hints, raid-plan tools, anything that
can answer "which spell should be highlighted?"

## Quick start

1. Load after the EUI Cooldown Manager, so the API exists when you register:

```
## OptionalDeps: EllesmereUI, EllesmereUICooldownManager
```

(Use `## Dependencies: EllesmereUICooldownManager` instead if your addon is
useless without it.)

2. Register once, anywhere in your main file:

```lua
local handle
if EllesmereUI and EllesmereUI.PluginGlows then
    handle = EllesmereUI.PluginGlows.Register("MyAddon-NextSpell", {
        name    = "My Addon: Next Spell",     -- shown in the menu
        onInUse = function(h) handle = h; StartMyTracking() end,
    })
end
```

3. Push the spell(s) that should glow whenever your answer changes:

```lua
handle:SetSpells(12345)             -- one spell
handle:SetSpells({ 12345, 67890 })  -- several (every icon showing any of them glows)
handle:Clear()                      -- nothing glows
```

That is everything. A spell only glows on icons where the player picked a Glow
Style for your source.

## Rules

- **Do no work until `onInUse`.** Registering is free; the Cooldown Manager
  calls `onInUse(handle)` once per session, when the player has chosen a Glow
  Style for your source on at least one icon (including settings saved from an
  earlier session, found at login). Start your events, timers and polling
  there, not before. Players who never use your source then pay nothing.
- **Push changes, not every tick.** `SetSpells` ignores a call that repeats the
  current value, but compute your answer only when it can change.
- **You push spells, EUI draws.** Style, color and opacity are the player's;
  there is no way to force a glow on an icon.
- **Spell IDs may be base or override IDs.** An icon matches when it shows the
  spell, its base spell or its current override (Rising Sun Kick matches
  Rushing Wind Kick when the talent replaces it).
- **Names are plain text.** Color codes, textures and control characters are
  stripped, up to 40 characters. Prefix it with your addon name so players can
  tell sources apart.
- **One addon can register several sources** (for example "Next Spell" and
  "Burst Window"); each gets its own Glow Style and Glow Color, and several can
  glow the same icon at once.
- **Registration is a snapshot.** Editing your spec table afterwards has no
  effect.
- Fields whose names start with `_` and everything on `ns` are internal and can
  change in any update. Only what is documented here is API.

## Reference

`EllesmereUI.PluginGlows.API_VERSION` is `1`. The API only ever grows.

### `EllesmereUI.PluginGlows.Register(id, spec)` -> `handle` or `nil`

`id`: unique and permanent: a letter followed by letters, digits, `_` or `-`,
at most 40 characters. It is part of the saved-setting key, so never change it
once released (a changed id loses the player's settings). Use your addon name
plus the source, e.g. `"MyAddon-NextSpell"`.

`spec` fields:

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | Text shown in the Plugin Glows menu, up to 40 characters. |
| `onInUse(handle)` | no | Called once per session when the player first configures a glow for this source (see Rules). Runs protected. |

Returns a handle, or `nil` after reporting the reason through the error handler
(BugSack/BugGrabber) when the registration is rejected: bad id, duplicate id,
missing name, or more than 50 sources registered. A rejected call changes
nothing.

### Handle methods

Call them with a colon: `handle:SetSpells(...)`.

| Method | Meaning |
|---|---|
| `SetSpells(spells)` | `spells` is a spell ID, a list of spell IDs, or `nil`. Replaces the glowing set. Repeating the current value is ignored. |
| `Clear()` | Same as `SetSpells(nil)`. |
| `IsInUse()` | `true` once the player has configured a glow for this source. |
| `Unregister()` | Removes the source: its glows stop and it leaves the menu. The id can be registered again. |

### `EllesmereUI.PluginGlows.Unregister(id)`

Same as `handle:Unregister()`, by id.

### `EllesmereUI.PluginGlows.IsRegistered(id)` -> `boolean`

## Behaviour notes

- Glows follow the player's other Cooldown Manager glow settings, including
  Show Glows Only in Combat.
- A plugin glow sits on its own overlay, so it never replaces or cancels the
  proc, active-state, max-charges or cooldown-state glows. Blackout is drawn
  under the cooldown swipe and text, like the cooldown-state Blackout.
- Settings are stored per spell and spec like the other glow settings, and
  follow the same Apply to Spell / Bar / Bar (All Specs) scopes. They are not
  removed when your addon is missing; they simply do nothing and are not shown.
- Buff-family bars and custom injected spells do not show the Plugin Glows
  entry.

## Example: glow the next rotation spell

```lua
local handle

local function Tick()
    handle:SetSpells(MyRotation_NextSpellID())   -- nil when there is none
end

local function Start()   -- runs only once the player has chosen a glow style
    C_Timer.NewTicker(0.2, Tick)
end

if EllesmereUI and EllesmereUI.PluginGlows then
    EllesmereUI.PluginGlows.Register("MyRotation-Next", {
        name    = "My Rotation: Next Spell",
        onInUse = function(h) handle = h; Start() end,
    })
end
```

[APLforEUI](https://github.com/zanthor/APLforEUI) uses exactly this pattern.

## Before you release

- [ ] Your `.toc` lists `EllesmereUICooldownManager` in `OptionalDeps` or
      `Dependencies`.
- [ ] Your registration is guarded with `if EllesmereUI and EllesmereUI.PluginGlows`.
- [ ] Nothing runs (events, timers, polling) before `onInUse`.
- [ ] The id is final and your name starts with your addon's name.

## For EUI maintainers

| File | Role |
|---|---|
| `EllesmereUICooldownManager/EUI_CDM_PluginGlows.lua` | The registry, the public API and the whole glow runtime. |
| `EllesmereUICooldownManager/EllesmereUICooldownManager.toc` | Loads the file above. |
| `EllesmereUICooldownManager/EUI_CDM_Icons.lua` | `RefreshCDMIconAppearance` calls `ns.PluginGlowRefreshIcon` (gated on `ns._cdmAnyPluginGlow`). |
| `EllesmereUICooldownManager/EUI_CDM_Rebuild.lua` | `BuildAllCDMBars` calls `ns.RescanPluginGlowFlag` with the other gate scans. |
| `EllesmereUIOptions/CooldownManager_Options/SpellPicker_Options.lua` | `AB.MakePanelRow` (nested flyouts; `MakeSubnavRow` gained `opts.host` / `opts.onApplied`), the Plugin Glows rows, and one line in `AB.FlipSessionGates` that arms the glow when Apply to Bar writes a style. |

Saved keys, per source id: `pluginGlow:<id>:style`, `:alpha` (Blackout opacity),
`:color` (`"class"` / `"custom"`), `:colorR`, `:colorG`, `:colorB`.
