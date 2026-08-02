# EllesmereUI Skinning API (for addon developers)

Make your addon match the EllesmereUI look with a few one-line calls. You hand
us your frames; EUI paints them in the user's current theme and keeps them in
sync with every future theme tweak, live accent/color changes included. You
never touch EUI textures, fonts, colors, or settings directly.

## Quick start

1. Add EllesmereUI as an optional dependency so it loads before you:

```
## OptionalDeps: EllesmereUI
```

2. Register a skin callback anywhere in your main file:

```lua
if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin("MyAddon", function(S)
        S.Shell(MyAddonFrame)              -- themed window backdrop + border
        S.CloseButton(MyAddonFrame.Close)
        S.EditBox(MyAddonFrame.SearchBox)
        S.Button(MyAddonFrame.SortButton)
        S.ScrollBar(MyAddonFrame.ScrollBar)
        for _, tab in ipairs(MyAddonFrame.Tabs) do
            S.Tab(tab)
        end
    end)
end
```

That's everything. If EllesmereUI isn't installed, the `if` skips it. If the
user turned skinning off, your callback never runs. No other integration code
is needed.

## When your callback runs

- Once per session, at `PLAYER_LOGIN` (or immediately at registration if you
  register later than that, e.g. from a load-on-demand addon).
- Only when the user has EUI's third-party skinning enabled for your addon
  (it is on by default; users can toggle it per addon in EUI's options).
- Your callback is isolated: an error in it is reported through the normal
  error handler and never breaks EUI or other addons' skins.

If you create frames after login (pooled rows, lazy panels), keep the `S`
you were given and call the primitives from your own creation/refresh code.
Every primitive is idempotent: calling it again on an already-skinned frame
is a no-op costing one table lookup, so it is safe in refresh hooks.

```lua
local skin
EllesmereUI.RegisterSkin("MyAddon", function(S) skin = S; SkinStatic(S) end)

-- later, in your row factory:
local function CreateRow(...)
    local row = ...
    if skin then skin.Button(row.actionButton) end
end
```

## Which theme does the user get?

You never choose. EUI resolves it from the user's own window-skin settings:
if most of their Blizzard windows use the Modern flat-color style your addon
gets Modern, otherwise it gets the EllesmereUI style. The two differ only in
the `S.Shell` backdrop; every other primitive looks identical in both. Style
changes the user makes apply to your frames live where possible.

## Reference

`S.apiVersion` is `1`. The API only ever grows; existing functions and their
signatures will not change.

### Containers

| Call | What it does |
|---|---|
| `S.Shell(frame [, opts])` | Full themed window backdrop: fades existing art, paints the theme backdrop and window border. Use on your main window. `opts.noBorder` skips the border, `opts.noTopBar` skips the dark title strip, `opts.bottomBar = true/height` adds a matching footer strip. |
| `S.Panel(frame [, opts])` | Flat dark panel + border for sub-frames and popups. `opts.inset` darker variant, `opts.noBorder`, `opts.noBg`. |
| `S.Inset(inset)` | Strips an `InsetFrameTemplate` (Bg + NineSlice box) so it blends into the shell. |
| `S.FadeRegions(frame)` | Alpha-out every texture region on a frame (art removal only; nothing is Hidden). |
| `S.FadeNineSlice(frame.NineSlice)` | Fades a NineSlice border and keeps it faded through Blizzard re-layouts. |

### Widgets

| Call | What it does |
|---|---|
| `S.Button(button [, keepKeys])` | Flat dark button, subtle white hover, thin border. `keepKeys = {"Icon"}` preserves named regions. Label font/color untouched. |
| `S.WhiteButtonLabel(button)` | Forces a button label white (color only), re-applied on OnEnable. |
| `S.StateButtonLabel(button)` | Label white when enabled, gray when disabled. |
| `S.EditBox(editBox)` | Near-black input box with border, template art removed. |
| `S.Checkbox(checkbox [, opts])` | Dark box + accent-colored check. `opts.stockCheck` keeps Blizzard's check color. |
| `S.Dropdown(dropdown)` | Flat dropdown with the house arrow. |
| `S.ScrollBar(scrollBar)` | Fades arrows/track art, paints the thin white thumb strip. Scroll behavior untouched. |
| `S.Tab(tab)` | House tab: flat plate, accent underline on the active tab. |
| `S.CloseButton(button)` | House close (X) glyph. |
| `S.PageButton(button, "<" or ">")` | House prev/next page arrows. |
| `S.SquareIcon(iconTexture [, parentFrame])` | Squares an icon's baked bevel (texcoord crop). Pass the icon's parent frame to also draw a 1px black border around it. |
| `S.SortHeaderBar(list)` | Flattens a ScrollBox column-header bar (auction-house style lists). |

### Text and bars

| Call | What it does |
|---|---|
| `S.Font(fontString [, r, g, b])` | Re-fonts a FontString to the user's chosen UI font, same size. Optional color. |
| `S.White(fontString [, r, g, b])` | Color-only (default white); font untouched. |
| `S.ApplyBarFill(statusBar)` | The house StatusBar fill (user-configurable color/opacity, kept in sync). |

### State and theme queries

| Call | Returns |
|---|---|
| `S.IsEnabled()` | `true` while skinning for your addon is enabled. |
| `S.GetStyle()` | `"eui"` or `"modern"` -- the resolved theme (informational; primitives already handle it). |
| `S.GetAccentColor()` | `r, g, b` -- the user's live accent color. |
| `S.GetPanelColor()` | `r, g, b, a` -- the house panel fill. |
| `S.GetFont()` | `fontPath, outlineFlag` -- the user's UI font. |
| `S.OnLooksChanged(fn)` | Calls `fn` when accent/theme settings change live. Only needed for custom elements you colored yourself via the getters; skinned frames update on their own. |

## Guidelines

- Skin your own frames only. The primitives are taint-safe (external state,
  alpha-only art removal, no Hide/SetParent), but Blizzard frames inside your
  window are your responsibility to pick sensibly.
- Prefer the primitives over the getters. A frame skinned via primitives
  tracks every future EUI tweak automatically; custom drawing via
  `S.GetAccentColor()` etc. is for the rare element we have no primitive for.
- Do not cache getter results across sessions or long lifetimes; re-read them
  (or use `S.OnLooksChanged`) so live recolors reach your custom elements.
- Registering is free. If skinning is disabled nothing ever runs, so there is
  no need to gate your `RegisterSkin` call behind saved variables.

## FAQ

**Does this cost performance?** No. Skinning is one-time texture setup at
login; no OnUpdate handlers, no events, no per-frame work. Re-calls on
already-skinned frames bail after one lookup.

**Can users turn it off?** Yes -- per addon, in EllesmereUI options under
Blizz UI Enhanced > Blizzard Window Skins > Third-Party Addons. Your callback
simply doesn't run.

**What if two addons register the same name?** First registration wins; use
your addon's folder name to stay unique.

**I need a primitive that isn't listed.** Ask! The API is additive -- ping
Ellesmere on Discord and it can usually ship in the next build.
