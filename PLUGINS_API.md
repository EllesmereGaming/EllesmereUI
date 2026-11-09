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

`EllesmereUI.PLUGIN_API_VERSION` is `5`. The API only ever grows; existing
functions and fields will not change. Version 2 added
`EllesmereUI.GetCDMIconsForSpell`, version 3 `EllesmereUI.RequestCDMRepopulate`,
version 4 `EllesmereUI.GetCDMRepopulateStatus`, version 5
`EllesmereUI.RegisterQuestTrackerRow` and `EllesmereUI.RefreshQuestTrackerRows`.

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

### `EllesmereUI.GetCDMIconsForSpell(spellID [, out])` -> `table`

The Cooldown Manager icons currently showing `spellID`, on every CDM bar,
including spells the player added that Blizzard's Cooldown Manager doesn't
track. An icon matches when it holds the spell, its base spell or one of its
overrides, the same way the rotation helper highlight finds its icon. Icons
that are not shown are left out. A bar hidden by its visibility settings, or
while the player is in a vehicle, fades its icons out instead of hiding them,
so those icons are still returned.

`out` is optional: pass a table of your own to have it wiped and filled
instead of getting a new one. Each call walks every icon on every CDM bar, so
call it when the spell you track changes, not every frame. The function
exists only while the Cooldown Manager module is loaded, so test for it first:

```lua
local icons = {}
if EllesmereUI.GetCDMIconsForSpell then
    for _, icon in ipairs(EllesmereUI.GetCDMIconsForSpell(spellID, icons)) do
        -- show your own overlay on icon
    end
end
```

Some of these icons are EUI's own frames and some are Blizzard's Cooldown
Manager frames that EUI shows on its bars, so treat every icon as read-only:

- Draw on a frame of your own, created as a child of the icon
  (`CreateFrame("Frame", nil, icon)`) so it moves, fades and hides with it.
  Give it a frame level above the icon's, which carries its own cooldown,
  border and glow layers.
- Keep anything you track per icon in a table of your own, keyed by the
  icon. Never write fields onto an icon: on Blizzard's frames that spreads
  taint into Blizzard's code.
- Don't reparent, hide, move, resize or hook an icon, and don't hand one to
  code that does. Glow libraries usually store their state on the frame they
  are given, so glow your own frame, never the icon.
- Look the icons up again rather than keeping them: bars reuse their icons
  for other spells when they rebuild, so hide your overlay on any icon the
  latest call didn't return.

### `EllesmereUI.RequestCDMRepopulate([specIDs])` -> `boolean`

For profile installers that set up Blizzard's Cooldown Manager layouts. EUI's
Cooldown Manager keeps its own arrangement of Blizzard's spells, so a Blizzard
layout imported or switched to later is not mirrored onto EUI's bars by
itself. This queues the work of the **Repopulate from Blizzard CDM** button:
EUI's bars drop every spell that came from Blizzard's Cooldown Manager (the
spells a player added in EUI, trinkets and presets stay) and are filled again
from the active Blizzard layout.

The character's racial is placed as well. Blood Fury and Berserking go to the
end of the Cooldowns bar; Will of the Forsaken, War Stomp, Will to Survive,
Stoneform, Shadowmeld, Escape Artist, Read Ley Line and Skysight go to the end
of the Utility bar. Any other racial goes where your Blizzard layout puts it,
and if the layout doesn't track it, it stays where the EUI profile had it.

`specIDs` is optional: one spec ID or a list of them, as the game reports them
(`C_SpecializationInfo.GetSpecializationInfo`); leave it out for every spec of
the player's class. The request is kept for the current character only. Each
requested spec is repopulated the next time it is active, once Blizzard's
Cooldown Manager has loaded its saved layouts and finished building its icons
after a login, reload or spec change, and never during combat (it waits for
combat to end). Returns `true` once queued, `false` when nothing valid was
given.

Call it after your installer has written and activated its Blizzard layouts,
right before your own `ReloadUI()`: the bars are filled from whichever Blizzard
layout is active when the repopulate runs. The function exists only while the
Cooldown Manager module is loaded, so test for it first:

```lua
-- after importing and activating the Blizzard Cooldown Manager layouts
if EllesmereUI.RequestCDMRepopulate then
    EllesmereUI.RequestCDMRepopulate()   -- every spec of this class
end
ReloadUI()
```

### `EllesmereUI.GetCDMRepopulateStatus([specID])` -> `status, time, layoutID`

How a repopulate you queued with `EllesmereUI.RequestCDMRepopulate` went, for
the current character. `specID` is optional: a spec ID as the game reports it,
or leave it out for the character's current spec. It returns:

- `"pending"` while the request is still queued: that spec has not been active
  and settled since you asked, or Blizzard has not loaded its saved layouts
  yet, or combat is holding it.
- `"done", time, layoutID` once the queued repopulate has finished. `time` is
  when it ran (`time()`), and `layoutID` is the Blizzard Cooldown Manager
  layout that was active then, the one EUI's bars were filled from (`nil` when
  no saved layout was active). The record stays until your next request for
  that spec.
- `nil` when nothing was requested for that spec, or the run did not finish.

After your reload the repopulate runs a moment after login, once Blizzard has
loaded its layouts and built its icons, so check later than `PLAYER_LOGIN`
(for example when your installer's window opens again):

```lua
if EllesmereUI.GetCDMRepopulateStatus then
    local status, ranAt, layoutID = EllesmereUI.GetCDMRepopulateStatus()
    if status == "done" and layoutID == myLayoutID then
        -- EUI's bars were filled from your layout
    end
end
```

### `EllesmereUI.RegisterQuestTrackerRow(id, fn [, width])` -> `boolean`

WoW Forever only. Adds your own icons or buttons to the quest rows of EUI's
Custom Quest Tracker, the way addons decorate Blizzard's tracker. The custom
tracker draws its own rows, so hooks on Blizzard's tracker never reach it;
register here as well.

- `id`: your addon's folder name. One registration per id.
- `fn(slot, questID, title)`: runs for every quest title row each time the
  tracker redraws.
  - `slot` is a frame of your own at the right end of that row's title
    (titles are left-aligned, so a short one leaves a gap before it),
    `width` wide and as tall as the title. Put your icons and buttons on it
    (create them once, keyed by `slot`). It hides when the row stops showing
    a quest, and is reused for other quests, so set everything from
    `questID` on each call. Never put a secure (protected) frame on it, such
    as a `SecureActionButtonTemplate` button: the tracker moves and hides its
    rows in combat, which a protected child would block.
  - `title` is the row's title FontString, for reading its font, color or
    text width. Read-only: don't change it.
- `width`: pixels kept free right of the title for your slot, 0 to 64,
  default 0. With 0 the slot has no width; anchor to its left edge to draw
  past the title anyway (over anything to its right).

Returns `true` on success, `false` for a bad argument or a taken `id`. An
error in `fn` goes to the error handler and does not stop the tracker. Keep
`fn` cheap: it runs for every row on every redraw.

The tracker redraws on quest log, watch and settings changes. When your own
state changes, call `EllesmereUI.RefreshQuestTrackerRows()` to redraw it.

Both functions exist only on WoW Forever with the Quest Tracker module
loaded, so test for them first. Your addon can load before that module:
register at `PLAYER_LOGIN`, or list `EllesmereUIQuestTracker` in your TOC's
`## OptionalDeps`. Your callback only runs while the user has the Custom
Quest Tracker on; Blizzard's tracker is used otherwise.

```lua
if EllesmereUI and EllesmereUI.RegisterQuestTrackerRow then
    local buttons = {}
    EllesmereUI.RegisterQuestTrackerRow("MyAddon", function(slot, questID, title)
        local b = buttons[slot]
        if not b then
            b = CreateFrame("Button", nil, slot)
            b:SetSize(14, 14)
            b:SetPoint("TOPRIGHT")
            b:SetNormalTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
            b:SetScript("OnClick", function(self) MyAddon:Play(self.questID) end)
            buttons[slot] = b
        end
        b.questID = questID
        b:SetShown(MyAddon:HasAudio(questID))
    end, 16)
end
```

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
