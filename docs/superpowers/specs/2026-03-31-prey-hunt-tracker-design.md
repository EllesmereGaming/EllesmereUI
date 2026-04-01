# EllesmereUIPreyHunt — Design Spec

## Overview

A child addon module that tracks Prey Hunt progress in EllesmereUI style. Displays hunt stage progression as a sleek bar, auto-shows only when the player is in active prey content, integrates with unlock mode for positioning, and can be toggled on/off from the EllesmereUI module system.

## Goals

- Track prey hunt stage progression via `C_UIWidgetManager`
- Display progress in three selectable modes: stage segments, smooth bar, compact indicator
- Auto-show when in prey hunt content, auto-hide when not
- Fully movable via EllesmereUI unlock mode
- Toggleable as a module inside EllesmereUI options
- Zero impact on existing EllesmereUI features when disabled

## Architecture

### Module Pattern

- **Addon**: `EllesmereUIPreyHunt/` — independent child addon folder
- **Framework**: `EUILite.NewAddon("EllesmereUIPreyHunt")`
  - `OnInitialize`: fires on ADDON_LOADED, loads DB
  - `OnEnable`: fires on PLAYER_LOGIN, builds frames, starts listening
- **Database**: `EUILite.NewDB("EllesmereUIDB", defaults)` — settings stored at `EllesmereUIDB.profiles[name].addons.EllesmereUIPreyHunt`
- **Module toggle**: Registers with EllesmereUI module system so it appears in the modules list and can be enabled/disabled from options
- **Unlock mode**: Registers via `EllesmereUI:RegisterUnlockElements()` so the bar is draggable/positionable

### Files

| File | Purpose |
|------|---------|
| `EllesmereUIPreyHunt.toc` | TOC with `## Dependencies: EllesmereUI` |
| `EllesmereUIPreyHunt.lua` | Core addon: data layer, frame creation, 3 display modes, auto-show/hide, unlock registration |
| `EUI_PreyHunt_Options.lua` | Options page in EllesmereUI panel: display mode, bar size, opacity |

### No existing files modified

This is a fully additive module. No changes to any core EllesmereUI file or any other child addon.

## Data Layer

### Source: C_UIWidgetManager

The Prey Hunt system exposes progress as **stage transitions** through Blizzard's widget system, not raw percentages.

- **Detection**: Listen to `UPDATE_UI_WIDGET` event, filter for prey hunt widget IDs
- **Stage data**: `C_UIWidgetManager.GetFillUpFramesWidgetVisualizationInfo(widgetID)` returns fill-up frame data with stage/segment info
- **Fallback**: Also check `C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo()` and `C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo()` as Blizzard may expose hunt data through multiple widget types
- **Discovery**: On zone enter, iterate `C_UIWidgetManager.GetAllWidgetsBySetID(C_UIWidgetManager.GetTopCenterWidgetSetID())` to find active prey hunt widgets

### Zone Awareness

- Listen to `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`, `PLAYER_ENTERING_WORLD`
- Query `C_Map.GetBestMapForUnit("player")` to determine if player is in a Midnight prey hunt zone
- Auto-show the bar when: active hunt detected AND in relevant zone
- Auto-hide when: hunt completes, player leaves zone, or no active hunt widget found

### Hunt State

```
state = {
    active      = bool,     -- is a hunt in progress
    stage       = number,   -- current stage (1-based)
    maxStages   = number,   -- total stages in this hunt
    zoneName    = string,   -- zone where hunt is active
    difficulty  = string,   -- "Normal" / "Heroic" / "Nightmare"
    widgetID    = number,   -- tracked widget ID
}
```

## Display Modes

User selects one mode in options. Default: **Smooth Bar**.

### 1. Smooth Bar (default)

- Horizontal bar matching EllesmereUI XP/Rep bar style
- Background: dark (`0.05, 0.07, 0.09, 0.80`)
- Fill: accent color via `EllesmereUI.GetAccentColor()`
- Animated fill transitions (lerp over 0.3s when stage changes)
- Fill percentage: `currentStage / maxStages`
- Stage text right-aligned inside bar: "Stage 3/5"
- Bar dimensions default: 220px wide, 16px tall
- Border: 1px, white, 0.10 alpha (EllesmereUI standard)
- Hunt info label above bar: zone name + difficulty in dim text

### 2. Stage Segments

- Same bar frame, but divided into `maxStages` equal segments with 1px gaps
- Completed segments: filled with accent color
- Incomplete segments: dark background
- Current segment: partial fill or pulsing accent glow
- No text overlay (clean visual)
- Small stage count below: "3 / 5" in dim text

### 3. Compact Indicator

- Small frame: ~32px icon + text beside it
- Icon: prey hunt themed (use Blizzard's hunt texture or a generic eye/crosshair)
- Text: "3/5" in accent color, spec name in dim text below
- Hover tooltip: full hunt details (zone, difficulty, stage, description)
- Tooltip uses `EllesmereUI.ShowWidgetTooltip()`

## Frame Hierarchy

```
EllesmereUIPreyHuntFrame (main anchor, movable via unlock mode)
  ├── background texture
  ├── fill texture (smooth bar mode)
  ├── segment frames[] (stage segment mode)
  ├── icon texture (compact mode)
  ├── stage label (FontString)
  ├── info label (FontString — zone + difficulty)
  └── border (via MakeBorder)
```

Only the active mode's elements are shown; others are hidden.

## Options Page

Registered as a module page in EllesmereUI options panel.

### Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `enabled` | toggle | true | Module enabled/disabled |
| `displayMode` | dropdown | "bar" | "bar" / "segments" / "compact" |
| `barWidth` | slider | 220 | Bar width in pixels (100-400) |
| `barHeight` | slider | 16 | Bar height in pixels (8-32) |
| `opacity` | slider | 1.0 | Overall frame opacity (0.3-1.0) |
| `showLabel` | toggle | true | Show zone + difficulty label above bar |
| `animateFill` | toggle | true | Animate bar fill transitions |

### Layout

Uses `W:SectionHeader`, `W:DualRow`, `W:Dropdown`, `W:Slider`, `W:Toggle` — standard EllesmereUI widget factory.

## Unlock Mode Integration

Register with unlock mode so the bar is movable:

```lua
EllesmereUI:RegisterUnlockElements({
    {
        key = "PreyHunt",
        label = "Prey Hunt",
        frame = mainFrame,
        savePosition = function() ... end,
        loadPosition = function() ... end,
        clearPosition = function() ... end,
    }
})
```

Position saved to `EllesmereUIDB.unlockAnchors["PreyHunt"]`.

## Auto-Show/Hide Logic

```
on ZONE_CHANGED / PLAYER_ENTERING_WORLD / UPDATE_UI_WIDGET:
    if module disabled → hide, return
    scan widgets for prey hunt data
    if active hunt found:
        update state
        show frame
        refresh display
    else:
        hide frame
```

No polling — purely event-driven.

## Visual Style

- All colors via `EllesmereUI.GetAccentColor()` — matches active theme
- Font: Expressway (via `EllesmereUI.GetFontPath()` or hardcoded path)
- Border: `EllesmereUI.MakeBorder()` at 1px, white, 0.10 alpha
- Tooltips: `EllesmereUI.ShowWidgetTooltip()` / `HideWidgetTooltip()`
- Text labels: `EllesmereUI.MakeFont()`
- Background: dark flat, consistent with action bars / resource bars

## Edge Cases

- **No active hunt**: Frame stays hidden. No errors.
- **Hunt completes**: Widget update fires, state clears, frame hides with fade-out.
- **Zone transition during hunt**: Frame hides on zone leave, re-shows on zone return (hunt is still active server-side).
- **Combat**: Bar is display-only (no protected API calls), safe during combat.
- **Module disabled**: All frames hidden, events unregistered, zero overhead.
- **Widget ID changes between patches**: Discovery loop re-scans on each zone enter rather than hardcoding IDs.

## Branch Strategy

- New branch `prey-hunt` from `keybind-system` (or from `main` if we want it independent)
- Fully isolated — can be deleted/disabled without affecting keybind work
- If successful, can be proposed as a separate PR to the author
