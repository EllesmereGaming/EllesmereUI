# EllesmereUI Plugin API (for addon developers)

Give your addon its own settings pages inside the EllesmereUI options panel.
A plugin registers once and gets a new section of its own in the EUI sidebar,
with one or more modules (sidebar rows) under it, each with its own page tabs.

## Quick start

1. Depend on EllesmereUI so it loads before you:

```
## Dependencies: EllesmereUI
```

(Use `## OptionalDeps: EllesmereUI` instead if your addon also runs without
EUI, and keep the `if` guard below.)

2. Register anywhere in your main file:

```lua
if EllesmereUI and EllesmereUI.RegisterPlugin then
    EllesmereUI.RegisterPlugin("MyAddon", {
        label   = "My Addon",          -- sidebar section header
        modules = {
            {
                key         = "General",
                title       = "General",
                description = "Everything MyAddon does, in one place.",
                pages       = { "Display", "Behavior" },
                buildPage   = function(pageName, parent, yOffset)
                    local W = EllesmereUI.Widgets
                    local y = yOffset
                    local _, h
                    _, h = W:SectionHeader(parent, "APPEARANCE", y); y = y - h
                    _, h = W:Toggle(parent, "Show the frame", y,
                        function() return MyAddonDB.shown end,
                        function(v) MyAddonDB.shown = v; MyAddon:Refresh() end); y = y - h
                    return math.abs(y)         -- total content height
                end,
            },
        },
    })
end
```

3. Open it from your own slash command:

```lua
SLASH_MYADDON1 = "/myaddon"
SlashCmdList.MYADDON = function() EllesmereUI.OpenPlugin("MyAddon") end
```

That's everything. Your section appears in the sidebar the next time the panel
is shown, even if you register after the panel was already opened.

## Rules

These are enforced by EUI and cannot be worked around through the API:

- **A plugin only ever creates a new section.** It cannot add a row to one of
  EUI's own sections, add a tab to an EUI module, or replace an EUI page.
- **One section per plugin.** All of your modules live in it, in the order you
  list them. A plugin id can be registered once per session.
- **Your section sits outside EUI's own block.** By default it goes to the
  bottom of the sidebar, below every EUI section; `position = "top"` puts it
  above them instead. Sections that choose the same position keep their
  registration order.
- **Labels are plain text.** Color codes, textures, links and line breaks are
  stripped from `label` and `title`. Labels that imitate EUI's own entries are
  refused: EUI's section names (in any client language), "Global Settings",
  "Profiles", "Patch Notes", and anything starting with "EllesmereUI" or "EUI".
- **Registration is a snapshot.** EUI copies what it needs when you register;
  editing your spec table afterwards has no effect.
- **EUI's own functions and internals are off limits.** Replacing or hooking
  EUI's functions (`EllesmereUI.RegisterModule` in particular) never reaches
  EUI's own pages: EUI puts its own function back before it registers them.
  Fields whose names start with `_` are internal and can change or disappear in
  any update.
- **EUI loads its own settings.** Its options load only when the player first
  opens the panel, so don't load `EllesmereUIOptions` yourself; your
  `buildPage` always runs after it has loaded.

When an addon breaks these rules, EUI keeps its own pages working and leaves
the change out, and once per session the player sees a popup that names the
addon, says it needs an update, and links this page.

Plugin pages take part in the EUI global search (see [Search](#search)). They
do not take part in EUI profiles, profile sync or spec/conditional overrides:
while the user is editing an override session, plugin rows are locked like
every other module that can't be overridden.

## Reference

`EllesmereUI.PLUGIN_API_VERSION` is `1`. The API only ever grows; existing
functions and fields will not change.

### `EllesmereUI.RegisterPlugin(id, spec)` -> `boolean`

`id`: your plugin's unique id: a letter followed by letters, digits, `_` or
`-`, at most 40 characters. Use your addon's folder name.

`spec` fields:

| Field | Required | Meaning |
|---|---|---|
| `label` | yes | Sidebar section header, up to 32 characters. |
| `position` | no | `"bottom"` (default) or `"top"`. |
| `modules` | yes | List of 1-20 module specs (below), in sidebar order. |

Module spec fields:

| Field | Required | Meaning |
|---|---|---|
| `key` | yes | Module id, unique within your plugin (same format as `id`). |
| `title` | yes | Sidebar row text and panel header title, up to 48 characters. |
| `description` | no | Line under the panel header title (may contain color codes). |
| `pages` | yes | List of 1-20 unique page names (the tabs). Plain text: no `\|` escapes. |
| `buildPage(pageName, parent, yOffset)` | yes | Builds one page into `parent`, starting at `yOffset` (negative, top-down). Return the total content height. The built page is cached, so this normally runs once per page, and again after `RefreshPage(true)` or a cache invalidation. |
| `getHeaderBuilder(pageName)` | no | Return a function `(headerFrame, width) -> height` to draw a fixed header above the page's scroll area (e.g. a live preview), or nil for none. |
| `onPageCacheRestore(pageName)` | no | Called when a cached page is shown again; refresh anything that changed while it was hidden. |
| `onReset()` | no | Enables the footer's Reset button for this module. Reset your settings here. |
| `onModuleLeave()` | no | Called when the user switches away from this module. |
| `searchPrebuild` | no | `false` keeps this module out of the search's hidden pre-build pass (see [Search](#search)). Default `true`. |

Returns `true` on success. On a rejected spec it returns `false` and reports the
reason through the error handler (BugSack/BugGrabber will show it), for example
`EllesmereUI.RegisterPlugin(MyAddon): label "Core Addons" is reserved`. Nothing
is registered from a rejected spec.

### `EllesmereUI.OpenPlugin(id [, moduleKey [, pageName]])` -> `boolean`

Opens the panel on your module (the first one when `moduleKey` is nil),
optionally on a given page. Returns `false` when the plugin, module or page is
unknown. Like the panel itself, it does not open in combat.

### `EllesmereUI.GetPluginModuleKey(id, moduleKey)` -> `string` or `nil`

The full key EUI uses for your module (`"plugin:<id>:<moduleKey>"`). Pass it to
the panel calls that take a module key, e.g.:

```lua
local key = EllesmereUI.GetPluginModuleKey("MyAddon", "General")
if EllesmereUI:GetActiveModule() == key then
    EllesmereUI:RefreshPage(true)           -- rebuild the visible page
end
EllesmereUI:InvalidateModulePageCache(key)  -- drop your cached pages
```

### `EllesmereUI.IsPluginRegistered(id)` -> `boolean`

### `EllesmereUI.IsSearchPrebuild()` -> `boolean`

`true` while the global search's hidden pre-build pass is running one of your
page builders (see [Search](#search)).

## Building pages

`buildPage` runs when the user first opens a page, after the EUI options addon
is loaded, so `EllesmereUI.Widgets` (the same widget factory EUI's own pages
use) is always available there. Widgets such as `W:SectionHeader` and
`W:Toggle` take the parent and the current y offset and return the created
frame plus its height; subtract the height from your running offset as in the
quick-start example.

## Search

The EUI global search (the search box in the sidebar) covers plugin pages the
same way it covers EUI's own. There is nothing to register:

- Every page is a search result on its own ("Page: Display" under
  "My Addon > General").
- Every row you build with `EllesmereUI.Widgets` is indexed with its label,
  tooltip and section, and a result scrolls to that row and highlights it.
- Your section label narrows the search to your plugin: "my addon scale" looks
  for "scale" in your modules only.

Rows are indexed when a page is built. For pages the user has not opened yet,
the first search runs a hidden pre-build pass: it calls your `buildPage` once
per page with a stub widget factory that only records labels and creates no
frames. That makes your options searchable before the user ever visits them,
but it means `buildPage` has to tolerate being run that way:

- Check `EllesmereUI.IsSearchPrebuild()` and skip side effects while it is
  true: registering events, hooking functions, starting timers, building
  previews or touching your addon's live frames.
- Frames you create yourself with `CreateFrame` on `parent` are real; keep
  them cheap or skip them during the pass.
- An error during the pass is swallowed and the page is indexed the first time
  the user opens it instead.

If a page cannot run that way at all (heavy previews, builders that must
always see real widgets), set `searchPrebuild = false` on its module. Its rows
then become searchable once the user has opened the page in the session.

Controls you draw yourself without `EllesmereUI.Widgets` are not indexed; the
page itself still is.

## Errors

Every callback you give EUI runs protected. If `buildPage` or any other
callback throws, the error is reported through the error handler and the panel
keeps working; a failed page simply shows empty.

## FAQ

**Can I add a page to an EUI module, e.g. an extra Unit Frames tab?** No. Put
it in your own section; that is the only place plugins can add pages.

**Do I need to wait for PLAYER_LOGIN?** No. Register from your main chunk or any
later point; the panel picks the section up whenever it is shown.

**My old code called `EllesmereUI:RegisterModule`, wrote into
`EllesmereUI._modules` or edited `EllesmereUI.ADDON_GROUPS`.** It keeps working.
A page your addon registers under a key of its own keeps that key, from any of
your code (a `loadstring` chunk included), and a group of your own that you
inserted into `EllesmereUI.ADDON_GROUPS` shows above or below EUI's groups,
wherever you inserted it, labelled from your entry in
`EllesmereUI._addonInfoByFolder`. A row you placed inside one of EUI's groups
appears in a section of your own instead, as does a page with no row (named
after your addon). Changes aimed at EUI's own pages are ignored (see
[Rules](#rules)). New code should use `RegisterPlugin`: it checks your spec,
guards your callbacks and lets you pick your section's label and position.

**Players see an update popup naming my addon. What should I change?**

| If your addon... | Do this instead |
|---|---|
| Adds a page or tab to an EUI module, for example by wrapping `EllesmereUI.RegisterModule` | Move that page into your own section with `RegisterPlugin` |
| Builds its own rows into EUI's sidebar, or draws its pages over EUI's content area | Register a plugin: EUI builds your rows and hands each page a frame to draw into |
| Inserts rows into one of EUI's sidebar sections | Register your own section; for now those rows are moved into one for you |

## Before you release

- [ ] Your section is registered with `RegisterPlugin`, using your folder name
      as the id.
- [ ] Nothing in your addon replaces or hooks EUI's own functions, pages or
      sidebar, or reads fields starting with `_`.
- [ ] `buildPage` skips side effects while `EllesmereUI.IsSearchPrebuild()` is
      true.
- [ ] After a `/reload`, opening the panel shows your section and no update
      popup naming your addon.
