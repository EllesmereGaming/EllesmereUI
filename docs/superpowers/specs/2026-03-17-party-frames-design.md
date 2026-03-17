# Party Frames Design Spec

## Overview

Add configurable party frames to EllesmereUIUnitFrames, built on oUF's `SpawnHeader` system. Party frames display party1-4 (optionally including the player) with the same component builder pattern used by existing unit frames. The architecture is designed to extend to raid frames in the future without structural changes.

## Requirements

- Configurable for healer or DPS use cases via settings
- Party only (4 members + optional player), raid-ready architecture
- Player inclusion in party group is toggleable
- Every visual component is independently toggleable
- Growth direction: vertical or horizontal
- Sort order: role, group index, or alphabetical
- Uses existing drag-to-position system for the header anchor
- Lives in a new file within the existing `EllesmereUIUnitFrames` addon
- Component builders shared via addon namespace (`ns`)

## Architecture

### Approach: Hybrid Header

Use `oUF:SpawnHeader()` for group lifecycle management (create/destroy/sort/visibility) with a custom `StylePartyFrame` function that reuses existing component builders for appearance.

- Blizzard's `SecureGroupHeaderTemplate` handles combat lockdown, group join/leave, and sorting
- `StylePartyFrame` calls the same `CreateHealthBar`, `CreatePowerBar`, etc. used by other frames
- Layout changes (sort, growth, spacing) require out-of-combat — standard for all group frame addons

### Frame Anatomy

Each party member frame contains (all toggleable):

| Component | Builder | Default |
|---|---|---|
| Health Bar | `CreateHealthBar` (existing) | On |
| Absorb Bar | `CreateAbsorbBar` (existing) | On |
| Power Bar | `CreatePowerBar` (existing) | On, below |
| Portrait | `CreatePortrait` (existing) | Off |
| Castbar | `CreateCastBar` (existing) | Off |
| Name/Health Text | oUF Tag system (existing) | Name left, HP% right |
| Border | `CreateUnifiedBorder` (existing) | On |
| Auras/Debuffs | New party-specific filter (not `CreateTargetAuras` — party needs debuff-priority filtering with dispel highlights, which differs from the target's full aura display) | Debuffs on, buffs off |
| Role Icon | New | On |
| Range Fading | oUF Range element | On |
| Threat Indicator | oUF ThreatIndicator | On |
| Ready Check | oUF ReadyCheckIndicator | Always on |
| Leader/Assist | oUF LeaderIndicator | Always on |

Layout: portrait is optional on the left side. Name and role icon sit on the health bar to the right of the portrait (or at the left edge when portrait is off). Health percentage on the far right of the health bar.

### Header Spawn Pattern

```lua
oUF:RegisterStyle("EllesmereParty", StylePartyFrame)
oUF:SetActiveStyle("EllesmereParty")

partyHeader = oUF:SpawnHeader(
    "EllesmereUIPartyHeader",
    nil,
    "custom [@party1,exists] show;hide",
    "showPlayer",     settings.showPlayer,
    "showParty",      true,
    "showSolo",       false,
    "point",          growthPoint,       -- "TOP" or "LEFT"
    "xOffset",        xOff,
    "yOffset",        yOff,
    "groupBy",        "ASSIGNEDROLE",
    "groupingOrder",  "TANK,HEALER,DAMAGER"
)

ApplyFramePosition(partyHeader, "party")
```

Layout settings map directly to header attributes:

| Setting | Header Attribute |
|---|---|
| `growthDirection` | `point` + `xOffset`/`yOffset` |
| `sortOrder` | `groupBy` + `groupingOrder` |
| `spacing` | `xOffset`/`yOffset` value |
| `showPlayer` | `showPlayer` |
| Position | `ApplyFramePosition` (existing system) |

### Settings Structure

New `party` sub-table in `db.profile`:

```lua
party = {
    -- Frame dimensions
    frameWidth = 160,
    healthHeight = 36,

    -- Power bar
    powerPosition = "below",
    powerHeight = 4,

    -- Text (oUF tags)
    leftTextContent = "name",
    rightTextContent = "perhp",
    centerTextContent = "none",
    textSize = 11,

    -- Bar opacity
    healthBarOpacity = 90,
    powerBarOpacity = 100,

    -- Portrait
    showPortrait = false,

    -- Party-specific components
    showRoleIcon = true,
    showCastbar = false,
    showThreat = true,
    enableRangeFade = true,
    rangeFadeAlpha = 0.4,

    -- Auras
    showDebuffs = true,
    maxDebuffs = 3,
    showBuffs = false,
    maxBuffs = 0,
    highlightDispellable = true,

    -- Layout (header attributes)
    growthDirection = "vertical",
    sortOrder = "role",
    spacing = 1,
    showPlayer = false,
},
```

Shared settings (`borderSize`, `borderColor`, `healthBarTexture`, `darkTheme`, `portraitMode`) are read from top-level `db.profile`, same as boss frames.

`enabledFrames.party` controls the master toggle. `positions.party` stores the header anchor.

### File Structure

```
EllesmereUIUnitFrames/
├── Libs/oUF/oUF.xml
├── EllesmereUIUnitFrames.lua      ← modified (defaults, mappings, ns exports)
├── EllesmereUIPartyFrames.lua     ← NEW (~300-400 lines)
├── EUI_UnitFrames_Options.lua     ← modified (party options panel)
└── EllesmereUIUnitFrames.toc      ← add EllesmereUIPartyFrames.lua
```

### Changes to Existing Files

**`EllesmereUIUnitFrames.lua`:**
- Add `party` defaults to `defaults.profile`
- Add `party = true` to `enabledFrames`
- Add `party` position to `positions`
- Extend `UnitToSettingsKey`: add `if unit:match("^party%d$") then return "party" end` **before** the `db.profile[unit]` fallback probe (line 615), otherwise `party1`–`party4` will return nil since they are not keys in `db.profile`
- Extend `GetSettingsForUnit` map: add `party = db.profile.party` to `unitSettingsMap`. Note: this map is lazily cached — either nil out `unitSettingsMap` after extending it, or add the party entries at the same point where boss entries are built
- Expose component builders via `ns` (complete list):
  - `ns.CreateHealthBar`
  - `ns.CreateAbsorbBar`
  - `ns.CreatePowerBar`
  - `ns.CreatePortrait`
  - `ns.CreateCastBar`
  - `ns.CreateUnifiedBorder`
  - `ns.ReparentBarsToClip` (required — every style function calls this for the overflow clip fix)
  - `ns.UpdateBordersForScale` (called after border creation in every style function)
  - `ns.ApplyFramePosition`
  - `ns.SetFSFont`
  - `ns.ContentToTag`
  - `ns.EstimateUFTextWidth`
  - `ns.GetSettingsForUnit`
  - `ns.SetupUnitMenu`
- Call `SpawnPartyHeader()` from spawn section
- Register party header with `EllesmereUI.RegisterUnlockElements` for Unlock Mode drag support

**`.toc` file:**
- Add `EllesmereUIPartyFrames.lua` after `EllesmereUIUnitFrames.lua`

### New File: `EllesmereUIPartyFrames.lua`

Contents:
- `StylePartyFrame(frame, unit)` — style function using `ns.*` builders
- `SpawnPartyHeader()` — creates oUF header with settings-driven attributes
- `UpdatePartyLayout()` — applies layout changes out of combat
- Role icon creation helper (small texture on health bar)
- Party aura filter with dispellable highlight logic
- Range fade setup via oUF Range element
- CDM registration: `EllesmereUI.PartyFrames[unit] = frame`

### CDM Integration

Party frames register in `EllesmereUI.PartyFrames` lookup table. `FindPlayerPartyFrame()` in `EllesmereUI.lua` must be modified to check this table first before iterating `PARTY_FRAME_SOURCES`.

oUF names header child frames as `EllesmereUIPartyHeaderUnitButton1` through `EllesmereUIPartyHeaderUnitButton5`. Two integration options:

1. **Preferred**: Add a first-check path in `FindPlayerPartyFrame()` that reads `EllesmereUI.PartyFrames` before the `PARTY_FRAME_SOURCES` loop
2. **Alternative**: Add `{ addon = "EllesmereUIUnitFrames", prefix = "EllesmereUIPartyHeaderUnitButton", count = 5 }` to `PARTY_FRAME_SOURCES`

```lua
EllesmereUI.PartyFrames = EllesmereUI.PartyFrames or {}
-- Updated dynamically as header assigns units to child frames
```

**Note:** This requires a code change in `EllesmereUI.lua`, not just the unit frames addon.

## Implementation Phases

### Phase 1: Core Frame
- `StylePartyFrame` with health, power, absorb, name text, role icon, border
- `SpawnHeader` with growth direction, sort order, spacing, showPlayer
- DB defaults and `enabledFrames` toggle
- Position system integration

### Phase 2: Auras & Indicators
- Party-specific debuff display with dispellable highlighting
- Buff tracking (optional)
- Threat indicator
- Range fading
- Ready check / resurrection / leader icons

### Phase 3: CDM Integration
- Register party frames in `EllesmereUI.PartyFrames`
- Update `FindPlayerPartyFrame()` to check native frames first

### Phase 4: Polish
- Castbar (toggleable per-member)
- Portrait support (2D/3D/class art modes)
- Options panel for party settings
- Live-update support (change settings without /reload)

## Behavioral Notes

- **Solo visibility**: Party frames are hidden when solo (`showSolo = false`). Even with `showPlayer = true`, the header only renders when in a group. This is intentional — the standalone player frame handles the solo case.
- **Combat lockdown**: Layout attribute changes (growth direction, sort order, spacing, showPlayer) require out-of-combat. The `UpdatePartyLayout()` function should queue changes and apply them on `PLAYER_REGEN_ENABLED` if called during combat.
- **Unlock Mode**: The party header anchor is registered with `EllesmereUI.RegisterUnlockElements` so it can be dragged in Unlock Mode like all other frames. Individual child frames are not independently draggable — only the header anchor moves.

## Non-Goals

- Raid frames (future, same architecture)
- Arena frames
- Per-member customization (all party members share settings)
- CDM bars on party members (separate feature)
