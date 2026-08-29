if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_ManagerPages.lua
--  Single "Player Aura Bars" tab: sidebar lists the two fixed default bars
--  (Buffs, Debuffs -- always present, not deletable) plus any custom bars,
--  with "Add Buff Bar" / "Add Debuff Bar" actions. Selecting any entry shows
--  its settings in the detail pane, split into ASSIGNED (content selection,
--  model-specific) / CORE / DISPLAY sections (RaidFrames layout pattern) --
--  default and custom bars share the same field-building helpers since both
--  are just cfg tables with the same shape (see
--  EllesmereUIUnitFrames_PlayerAuraBars.lua's DefaultBuffsCfg/
--  DefaultDebuffsCfg and the custom-bar CRUD section).
--
-- redesign: default Buffs bar unified onto the same BM2/filters
--  model custom buff bars already used (Filters dropdown + Extra Spells
--  dropdown, ns.PAB_Filters registry) -- classFilters no longer applies to
--  ANY buff-side bar. Debuff bars (default + custom) keep the class-token
--  model, now with a "Show All Debuffs" toggle that bypasses classFilters
--  without discarding it (mirrors RaidFrames' DebuffManager). The Filter
--  Editor modal (ns.PABMP_ShowFilterEditor) is implemented below -- see its
--  doc comment for what was deliberately NOT ported from RaidFrames' BM2
--  (curated preset spell database, own-only tracking).
-------------------------------------------------------------------------------

local ns = EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

local floor, max = math.floor, math.max

local function L(s) return EllesmereUI.L and EllesmereUI.L(s) or s end

local TILE_H = 58

-- Forward-declared: defined below (verbatim port of RaidFrames' editor scroll helper),
-- used by WrapCompensatedBody -- which is itself defined ABOVE that point in the file
-- -- to give the detail pane's body a real scrollbar (fix: the body previously had no
-- scroll mechanism at all, just silent SetClipsChildren cropping; content taller than
-- the visible area was simply unreachable, a pre-existing gap that only became visible
-- once the new preview box pushed settings fields below the fold).
local AttachEditorScroll

-- Selection state: {kind="buff"|"debuff", id=barId|"default"} or nil.
local pabSel = { kind = "buff", id = "default" }
-- Editing-spec bucket: "allspecs" (the legacy bar arrays), a group bucket
-- key, or a concrete "spec<ID>". Session-sticky like pabSel.
local pabSpecSel = "allspecs"
-- Inherited-bar selection ({kind, group, id}); wins over pabSel while set.
local pabInhSel = nil

-- Exported selection setter for What's New deep links (same pattern as
-- EllesmereUI._setUnitFrameUnit / _setMiniUnit): the sidebar selection is a
-- session-sticky file local defaulting to the Buffs bar, so a nav targeting a
-- debuff-side section must pre-select the right pane or the section scan
-- silently misses.
EllesmereUI._setPABSelection = function(kind, id)
    pabSel = { kind = kind, id = id or "default" }
    pabInhSel = nil
end

-- Editing-spec group buckets (labels/icons mirror the RaidFrames roster in
-- EUI_RaidFrames_BuffManager.lua -- different addon namespace, keep the two
-- lists in sync).
local SPEC_GROUP_BUCKETS = {
    { key = "allspecs",  name = "All Specs",
        icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend" },
    { key = "nonhealer", name = "All Non Healers/Aug",
        icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend" },
    { key = "tanks",     name = "All Tanks",
        icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
    { key = "dps",       name = "All DPS (Non-Aug)",
        icon = "Interface\\Icons\\Ability_DualWield" },
    { key = "healers",   name = "All Healers/Aug",
        icon = "Interface\\Icons\\Spell_Holy_Renew" },
}
local SPEC_GROUP_INFO = {}
for i = 1, #SPEC_GROUP_BUCKETS do
    SPEC_GROUP_INFO[SPEC_GROUP_BUCKETS[i].key] = SPEC_GROUP_BUCKETS[i]
end
-- Filter Editor's own selected-filter state (independent of pabSel, since
-- the editor is a modal that can be opened from any buff-side detail pane).
local pabFilterSel
-- Preserves the spell-list scroll position across Rebuild() calls (add/ remove/rename
-- all rebuild the whole editor) -- same reasoning as BM2's fdScrollPos.
local pabFilterScrollPos = 0

-- Standard WoW anchor points -- verified against AK's own usage:
-- style.durationPoint/stackPoint feed SetPoint(point, button, point, ...)
-- directly (EllesmereUI_AuraKit.lua's ApplyStyleToRegions), NOT the old
-- module's lowercase "top"/"bottom" convention.
local AURA_POINT_VALUES = {
    TOP = "Top", BOTTOM = "Bottom", LEFT = "Left", RIGHT = "Right",
    TOPLEFT = "Top Left", TOPRIGHT = "Top Right",
    BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right", CENTER = "Center",
}
local AURA_POINT_ORDER = {
    "TOP", "BOTTOM", "LEFT", "RIGHT",
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER",
}
-- "Default" = the house icon-text rule: forced crisp outline unless the
-- user unchecks Unit Frames in Global Settings' "Outline Icon Text".
local FONT_OUTLINE_VALUES = {
    default = "Default", none = "Drop Shadow",
    outline = "Outline", thick = "Thick Outline",
}
local FONT_OUTLINE_ORDER = { "default", "none", "outline", "thick" }
local GROW_DIR_VALUES = { LEFT = "Left", RIGHT = "Right", CENTER_HORIZONTAL = "Centered Horizontal", CENTER_VERTICAL = "Centered Vertical", UP = "Up", DOWN = "Down" }
local GROW_DIR_ORDER = { "LEFT", "RIGHT", "CENTER_HORIZONTAL", "CENTER_VERTICAL", "UP", "DOWN" }
local ICON_WRAP_VALUES = { LEFT = "Left", RIGHT = "Right", UP = "Up", DOWN = "Down" }
local ICON_WRAP_ORDER = { "LEFT", "RIGHT", "UP", "DOWN" }

-- Same shape vocabulary and media set as Action Bars' Custom Button Shape
-- (EUI_ActionBars_Options.lua), minus "cropped" -- PAB has no equivalent
-- "cropped square" concept.
local SHAPE_VALUES = {
    none = "None", square = "Square", circle = "Circle",
    csquare = "Curved Square", diamond = "Diamond", hexagon = "Hexagon",
    portrait = "Portrait", shield = "Shield",
}
local SHAPE_ORDER = { "none", "square", "circle", "csquare", "diamond", "hexagon", "portrait", "shield" }

-- Levels map 1:1 to Action Bars' ns.BORDER_THICKNESS regular values (thin=1, normal=2,
-- heavy=3, strong=4), so cfg.borderSize stays the same plain 0-4 number used elsewhere
-- (regular border thickness, per-filter Icon Effects override).
local BORDER_SIZE_LEVELS = { "none", "thin", "normal", "heavy", "strong" }
local BORDER_SIZE_VALUES = { none = "None", thin = "Thin", normal = "Normal", heavy = "Heavy", strong = "Strong" }
local BORDER_SIZE_NUM = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
local BORDER_SIZE_KEY = { [0] = "none", [1] = "thin", [2] = "normal", [3] = "heavy", [4] = "strong" }
-- Levels with no distinct shape-border rendering (PabShapeBorderSize collapses them
-- all to "off"); Strong is the only one worth keeping enabled once a shape is active.
local BORDER_SIZE_SHAPE_DISABLED = { thin = true, normal = true, heavy = true }
local BORDER_SIZE_DEFAULT_SHAPE = "strong"

-- Every PAB bar (default Buffs/Debuffs plus any custom ones), for the sync-icon
-- "Apply to: All | Multiple" rows. entry.cfg is the live table, not a copy.
local function PabAllBarEntries()
    local s = ns.db and ns.db.profile and ns.db.profile.playerAuraBars
    if not s then return {} end
    local list = {}
    list[#list + 1] = { key = "buffs", label = "Buffs", isBuff = true, cfg = ns.PAB_DefaultBuffsCfg(s) }
    list[#list + 1] = { key = "debuffs", label = "Debuffs", isBuff = false, cfg = ns.PAB_DefaultDebuffsCfg(s) }
    local buffBars = ns.PAB_CustomBuffBars and ns.PAB_CustomBuffBars()
    if buffBars then
        for i = 1, #buffBars do
            local bar = buffBars[i]
            list[#list + 1] = { key = "custombuff_" .. bar.id, label = bar.name or "Buff Bar", isBuff = true, cfg = bar }
        end
    end
    local debuffBars = ns.PAB_CustomDebuffBars and ns.PAB_CustomDebuffBars()
    if debuffBars then
        for i = 1, #debuffBars do
            local bar = debuffBars[i]
            list[#list + 1] = { key = "customdebuff_" .. bar.id, label = bar.name or "Debuff Bar", isBuff = false, cfg = bar }
        end
    end
    return list
end

-- Which PabAllBarEntries() row a given (cfg, isBuff) pair is.
local function PabBarKeyOf(cfg, isBuff)
    local s = ns.db and ns.db.profile and ns.db.profile.playerAuraBars
    if s then
        if cfg == ns.PAB_DefaultBuffsCfg(s) then return "buffs" end
        if cfg == ns.PAB_DefaultDebuffsCfg(s) then return "debuffs" end
    end
    if cfg.id then return (isBuff and "custombuff_" or "customdebuff_") .. cfg.id end
    return ""
end

-- Restyles one bar live after the caller has written fields onto entry.cfg.
local function PabApplyBarEntry(entry)
    if entry.key == "buffs" or entry.key == "debuffs" then
        if ns.PAB_Restyle then ns.PAB_Restyle() end
        if ns.PAB_ApplyLiveConfig then ns.PAB_ApplyLiveConfig(entry.isBuff) end
    elseif entry.isBuff then
        if ns.PAB_ReloadCustomBuffBar then ns.PAB_ReloadCustomBuffBar(entry.cfg.id) end
    else
        if ns.PAB_ReloadCustomDebuffBar then ns.PAB_ReloadCustomDebuffBar(entry.cfg.id) end
    end
end

-- Native AuraContainerSortMethod/AuraContainerSortDirection enum names
-- (in-game dump: AuraContainerSortMethod = {Default=0,
-- BigDefensive=1, UnitFrameDebuff=2, ImportantOnly=3, Expiration=4,
-- ExpirationOnly=5, Name=6, NameOnly=7, AuraInstanceIDOnly=8},
-- AuraContainerSortDirection = {Normal=0, Reverse=1}). Curated down
-- to the 4 values whose names are unambiguous for an aura bar --
-- BigDefensive/UnitFrameDebuff/ExpirationOnly/NameOnly/ AuraInstanceIDOnly read as
-- narrower, other-UI-specific variants and are deliberately left out of this dropdown
-- (their exact behavior isn't documented anywhere in this repo either way).
--
-- "Important" (native key ImportantOnly) sorts by `C_Spell.IsSpellImportant` (verified
-- against Blizzard's PTR source, AuraUtil.lua's ImportantOnlyAuraCompare) -- a native
-- per-spell flag, not dispel-type- based and not debuff-specific, so it's equally
-- meaningful for buffs. (Originally hidden from the buff-side dropdown under a wrong
-- assumption that it meant "dispellable debuffs first"; corrected, now shared.)
local SORT_METHOD_VALUES = {
    Default = "Default", ImportantOnly = "Important",
    Expiration = "Expiration", Name = "Name",
}
local SORT_METHOD_ORDER = { "Default", "Expiration", "Name", "ImportantOnly" }
local SORT_DIR_VALUES = { Normal = "Normal", Reverse = "Reverse" }
local SORT_DIR_ORDER = { "Normal", "Reverse" }

local DISPEL_COLOR_ROWS = {
    { key = "dispelColorMagic",   label = "Magic",   fallback = { 0.349, 0.475, 1.0 } },
    { key = "dispelColorCurse",   label = "Curse",   fallback = { 0.636, 0.0, 0.64 } },
    { key = "dispelColorDisease", label = "Disease", fallback = { 0.671, 0.384, 0.098 } },
    { key = "dispelColorPoison",  label = "Poison",  fallback = { 0.0, 0.706, 0.286 } },
    { key = "dispelColorBleed",   label = "Bleed",   fallback = { 0.75, 0.15, 0.15 } },
}

-- ns.PAB_AllPresetSpells() intentionally contains resolved `alts` as their own entries
-- (rank/talent-variant spellIDs of the same buff family, see that function's own doc
-- comment) -- correct for PAB_ResolveSpells (any of them tracks the buff), but every UI
-- list drawing from that universe (Extra Spells' Presets group, Filter Editor's Search
-- Spells) showed them as same-named duplicate rows, which read as a bug rather than a
-- feature. Deduped here, display-only, by resolved spell name -- first (lowest) spellID
-- per name wins, matching table.sort's ascending id order. A spell whose name can't be
-- resolved yet (not cached client-side) falls back to its own id as the dedup key so it
-- never collapses into an unrelated entry.
local function DedupedPresetSpellUniverse()
    local universe = (ns.PAB_AllPresetSpells and ns.PAB_AllPresetSpells()) or {}
    local seenNames, out = {}, {}
    for i = 1, #universe do
        local id = universe[i]
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        local dedupKey = name or ("id:" .. id)
        if not seenNames[dedupKey] then
            seenNames[dedupKey] = true
            out[#out + 1] = id
        end
    end
    return out
end

-- Same display-only dedup pass, applied to the "Filters" assignment dropdown (ASSIGNED
-- BUFFS' Filters -- distinct from the Filter Editor's own sidebar list, which manages
-- the real filter objects individually and must NOT be deduped or renaming/deleting the
-- "hidden" duplicate becomes impossible). ns.PAB_Filters() can end up with same-named
-- entries (e.g. two user-created filters both left at the "New Filter" default, or
-- duplicate presets from an earlier import-migration bug) -- first (lowest id, i.e.
-- oldest) entry per name wins. Ordering is Buff Manager PARITY (newer request,
-- supersedes the old always-alphabetical rule): preset filters first in the curated
-- catalogue order (Defensives leads), then user filters in creation (list) order --
-- applied to both the Filters assignment dropdown (via DedupedFilterItems below) and
-- the Filter Editor's own sidebar (ns.PABMP_ShowFilterEditor). Always returns a FRESH
-- copy -- ns.PAB_Filters() hands back the live persisted list
-- (EllesmereUIUnitFrames_PlayerAuraBars.lua's ns.PAB_Filters, `store.list` directly),
-- so sorting in place would silently reorder SavedVariables every time the editor is
-- opened. Rank is matched by NAME, not the preset flag, so filters copied from the
-- Buff Manager order identically on both sides.
local function SortFiltersCanonical(list)
    local rank = {}
    local BP = EllesmereUI.BUFF_PRESETS
    if BP and BP.filters then
        for i = 1, #BP.filters do rank[BP.filters[i].name] = i end
    end
    local out, pos = {}, {}
    for i = 1, #list do
        out[i] = list[i]
        pos[list[i]] = i
    end
    table.sort(out, function(a, b)
        return (rank[a.name] or (1000 + pos[a])) < (rank[b.name] or (1000 + pos[b]))
    end)
    return out
end

local function DedupedFilterItems()
    local filters = (ns.PAB_Filters and ns.PAB_Filters()) or {}
    local seenNames, out = {}, {}
    for i = 1, #filters do
        local f = filters[i]
        if not seenNames[f.name] then
            seenNames[f.name] = true
            out[#out + 1] = f
        end
    end
    return SortFiltersCanonical(out)
end

-- Custom buff bar sidebar tile subtitle -- was a flat "N spells" (the
-- RESOLVED spell count, filters expanded), which didn't tell the user
-- WHICH selection mode a bar was actually in. Now reflects the bar's
-- actual ASSIGNED BUFFS config instead of the resolved count:
--   Show All Buffs on:  "Show All Buffs" (+ " + N spells" if Extra Spells
--     also has entries -- Extra Spells stays active/visible regardless of
--     Show All Buffs, see BuildAssignedBuffsFields' exRow, so it's still
--     meaningful to surface here).
--   Show All Buffs off: first 3 selected filters' names, comma-joined, in
--     ns.PAB_Filters() list order (map iteration via bar.filters alone is
--     unordered -- would make the tile flicker between refreshes). If 3+
--     filters are selected the 3rd shown name is truncated to its first 3
--     characters + "..." as an overflow hint. Falls back to the Extra
--     Spells count when no filters are selected at all (e.g. a bar with
--     only Extra Spells and Show All Buffs off) -- the ASSIGNED count, not
--     the resolved one, which expands curated spell families.
local function TruncateFilterName(name)
    return (name or ""):sub(1, 3) .. "..."
end

-- Both defined in EllesmereUIUnitFrames_PlayerAuraBars.lua next to the cfg they
-- read, so this page and the unlock-mode mover label cannot drift apart. The
-- module returns raw English keys; only the options page translates them.
local function IsWeaponEnchantsOnly(cfg)
    return ns.PAB_IsWeaponEnchantsOnly ~= nil
        and ns.PAB_IsWeaponEnchantsOnly(cfg)
end

local function DefaultBuffBarName(cfg)
    return L(ns.PAB_DefaultBuffsName and ns.PAB_DefaultBuffsName(cfg) or "Buffs")
end

-- Weapon-enchants-only is a fundamentally different shape of bar -- at most
-- three cells (main hand / off hand / ranged, see EUI_UnitFrames_
-- WeaponEnchants.lua's SLOTS, which matches Blizzard's own
-- UpdateTemporaryEnchantmentBuffs) instead of a wrapping buff grid. Resize the
-- grid to fit on the way in and restore it on the way out.
--
-- The user's own iconsPerRow/maxRows/maxTotal are stashed rather than assumed:
-- restoring hardcoded defaults would silently eat a customized grid. Storing
-- nil for an unset key is intentional -- the stash is then empty and restoring
-- puts the keys back to nil, i.e. ComputeGrid's own 11/3/32 buff fallbacks.
--
-- Returns true when it actually crossed the boundary. Callers use that to pick
-- a FORCE page rebuild: crossing rewrites the three grid sliders and the bar's
-- name, and none of those are RegisterWidgetRefresh clients, so the usual
-- lightweight refresh would leave them showing stale numbers.
local function SyncWeaponEnchantsGrid(cfg)
    if not cfg then return false end
    if IsWeaponEnchantsOnly(cfg) then
        if cfg.enchGridSaved then return false end
        cfg.enchGridSaved = { iconsPerRow = cfg.iconsPerRow,
            maxRows = cfg.maxRows, maxTotal = cfg.maxTotal }
        cfg.iconsPerRow, cfg.maxRows, cfg.maxTotal = 3, 1, 3
        return true
    end
    if not cfg.enchGridSaved then return false end
    local saved = cfg.enchGridSaved
    cfg.iconsPerRow, cfg.maxRows, cfg.maxTotal =
        saved.iconsPerRow, saved.maxRows, saved.maxTotal
    cfg.enchGridSaved = nil
    return true
end

local function BuildBuffBarSubtitle(bar)
    local extraCount = bar.spells and #bar.spells or 0
    local nHidden = 0
    if bar.negFilters then for _ in pairs(bar.negFilters) do nHidden = nHidden + 1 end end

    if bar.showAllBuffs ~= false or bar.hasDuration == true then
        local txt = (bar.showAllBuffs ~= false) and L("All Buffs") or L("Has Duration")
        if extraCount > 0 then txt = txt .. " + " .. extraCount .. " " .. L("spells") end
        if nHidden > 0 then txt = txt .. ", " .. nHidden .. " " .. L("hidden") end
        return txt
    end

    local names, totalSelected = {}, 0
    if bar.filters then
        local allFilters = ns.PAB_Filters and ns.PAB_Filters()
        if allFilters then
            for i = 1, #allFilters do
                local f = allFilters[i]
                if bar.filters[f.id] then
                    totalSelected = totalSelected + 1
                    -- L() before the truncate below: preset filters carry raw
                    -- English names (see PAB's BM2_FILTER_SEED), and truncating
                    -- first would leave the tail untranslatable.
                    if #names < 3 then names[#names + 1] = L(f.name) end
                end
            end
        end
    end

    if #names == 0 then
        return tostring(extraCount) .. " " .. L("spells")
    end

    if totalSelected >= 3 then
        names[#names] = TruncateFilterName(names[#names])
    end

    local label = table.concat(names, ", ")
    if extraCount > 0 then
        label = label .. " + " .. extraCount .. " " .. L("spells")
    end
    if nHidden > 0 then
        label = label .. ", " .. nHidden .. " " .. L("hidden")
    end
    return label
end

-- Custom debuff bar sidebar tile subtitle -- same "reflect the actual
-- ASSIGNED DEBUFFS config" fix as BuildBuffBarSubtitle above, just for the
-- debuff shape (bar.showAllDebuffs + bar.classFilters, no filters/extra
-- spells concept on the debuff side -- custom debuff bars are pure
-- class-token selection, see ns.PAB_AddCustomDebuffBar).
local function BuildDebuffBarSubtitle(bar)
    local nc = 0
    if bar.classFilters then for _ in pairs(bar.classFilters) do nc = nc + 1 end end
    local nHidden = 0
    if bar.negClassFilters then for _ in pairs(bar.negClassFilters) do nHidden = nHidden + 1 end end
    if bar.showAllDebuffs ~= false then
        if nHidden > 0 then
            return L("All Debuffs") .. ", " .. nHidden .. " " .. L("hidden")
        end
        return L("All Debuffs")
    end
    local txt = tostring(nc) .. " " .. (nc == 1 and L("class") or L("classes"))
    if nHidden > 0 then
        txt = txt .. ", " .. nHidden .. " " .. L("hidden")
    end
    return txt
end

-------------------------------------------------------------------------------
--  Shared field builders -- used by BOTH the default bars and custom bars.
--  cfg is whatever table the caller wants read/written: DefaultBuffsCfg(s),
--  DefaultDebuffsCfg(s), or a custom bar object itself (custom bar objects
--  carry the same field names directly on themselves, see the CRUD comment
--  in EllesmereUIUnitFrames_PlayerAuraBars.lua). apply() is called after
--  every field edit; callers decide what that means for them (Restyle()+
--  ApplyLiveConfig() for default bars, PAB_ReloadCustomBuffBar/DebuffBar
--  for custom bars).
-------------------------------------------------------------------------------

-- Empty-selection warning for the buff/debuff Filters dropdowns: the shared
-- builder EllesmereUI.AttachEmptyFilterWarn (EllesmereUI_Widgets.lua), also
-- used by the RF Debuff Manager's base Filters dropdown. hasContentFn here
-- is the engine's own content predicate (broad mode / Show lane / Extra
-- Spells / enchants / fx-forced classes), so a bar that still renders
-- anything never warns.

-- "Assigned Buffs": Filters checkbox dropdown (references the shared PAB Filters
-- registry, EllesmereUIUnitFrames_PlayerAuraBars.lua) + Extra Spells checkbox
-- dropdown (direct SpellIDs, cfg.spells). Mirrors ns.BMP_BuildAssignedFilters
-- (EUI_RaidFrames_ManagerPages.lua) 1:1 in widget structure. Deliberately NOT a full
-- port: PAB has no curated preset-spell universe (see PAB_Filters' doc comment), so
-- the Extra Spells dropdown only ever lists the bar's own already-added spells under
-- "Selected" plus the "Custom Spell ID" action -- no "Presets" group, there is
-- nothing to browse. Used by BOTH the default Buffs bar and every custom buff bar
-- (unified onto one model).
local function BuildAssignedBuffsFields(frame, fontPath, sy, cfg, apply, isDefault)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local _, hh = 0, 0

    _, hh = W:SectionHeader(frame, "ASSIGNED BUFFS", sy); sy = sy - hh

    -- "Filters": single unified checkbox dropdown -- pinned pseudo-filter
    -- rows above a divider, then the real (user-editable) PAB_Filters
    -- entries:
    --
    --   Edit Filters      (pinned top action)
    --   [ ] All Buffs     (cfg.showAllBuffs, nil == on)
    --   [ ] Has Duration  (cfg.hasDuration -- a broad-content mode of
    --                      its own, MUTUALLY EXCLUSIVE with All Buffs:
    --                      the catch-all narrowed to duration-carrying
    --                      buffs via candidateFilters.maxDuration)
    --   [ ] Weapon Enchants (cfg.showWeaponEnchants, default-bar only --
    --                      the enchant cells publish from the default
    --                      Buffs bar alone. INDEPENDENT of the two modes
    --                      above and of the real filters: oils/imbues are
    --                      not auras, so they come from their own source
    --                      rather than the catch-all group, and a mode
    --                      flip must not clear it)
    --   ------------------ (isHeader divider)
    --   [ ] <real filters, alphabetical>
    --
    -- Real-filter rows are TWO-LANE (same model as every filter dropdown in the
    -- suite): the left checkbox SHOWS a filter (cfg.filters, add mode only -- while a
    -- broad mode is on everything already shows, so the lane is dimmed), the right red
    -- box HIDES it (cfg.negFilters -- catch-all excludeSpellIDs under a broad mode,
    -- dropped from the spells-group union in add mode; see BuffBarChain /
    -- PAB_ResolveSpells). Lanes are mutually exclusive per filter and PERSIST across
    -- mode flips. The pinned pseudo-filters are never locked and are not
    -- ns.PAB_Filters() entries, so they never appear in the Filter Editor sidebar.
    -- (An Own Only pseudo-filter was tried and removed: the PLAYER token did not
    -- filter reliably on live engine groups, and the filter registry covers the need
    -- better.)
    --
    -- Extra Spells (direct SpellIDs) shares this same row and stays
    -- additive in both modes -- see the RIGHT-region block below.
    local ffRow
    ffRow, hh = W:DualRow(frame, sy,
        {
            type = "dropdown", text = "Filters",
            values = { __placeholder = "..." }, order = { "__placeholder" },
            getValue = function() return "__placeholder" end, setValue = function() end
        },
        {
            type = "dropdown", text = "Extra Spells",
            values = { __placeholder = "..." }, order = { "__placeholder" },
            getValue = function() return "__placeholder" end, setValue = function() end
        }
    ); sy = sy - hh

    local PAB_ALL_BUFFS_KEY, PAB_HAS_DURATION_KEY = "__allBuffs", "__hasDuration"
    local PAB_WEAPON_ENCH_KEY = "__weaponEnchants"

    -- Empty selections are LEGAL (user directive 2026-08-15, reversing the
    -- phase-2 no-empty rule on PAB): any content source can be unchecked,
    -- including the last one. AttachEmptyFilterWarn owns the loud feedback
    -- (red dropdown border + persistent bubble + close-pulse) while the bar
    -- displays nothing.
    local function BuffBarHasContent()
        if not ns.PAB_BuffBarHasContent then return true end
        return ns.PAB_BuffBarHasContent(cfg, isDefault) and true or false
    end

    -- LEFT: Filters checkbox dropdown, "Edit Filters" pinned top action.
    do
        local rgn = ffRow._leftRegion
        if rgn._control then rgn._control:Hide() end
        local function AllBuffsOn() return cfg.showAllBuffs ~= false end
        local function BroadOn() return cfg.showAllBuffs ~= false or cfg.hasDuration == true end
        local function FilterItems()
            local filters = DedupedFilterItems()
            local items = {
                { isTopAction = true, label = "Edit Filters", onClick = function()
                    ns.PABMP_ShowFilterEditor()
                end },
                -- Blacklist editing only matters while broad content is on
                -- (All Buffs / Has Duration); with neither, the bar shows
                -- only explicit picks and unchecking covers the need.
                { isTopAction = true, label = "Edit Blacklist",
                  lockedFn = function()
                      return cfg.showAllBuffs == false and cfg.hasDuration ~= true
                  end,
                  lockedTooltip = function() return EllesmereUI.DisabledTooltip("All Buffs or Has Duration", "enabled") end,
                  onClick = function()
                      EllesmereUI.ShowSpellBlacklistPopup({
                          title = "Buff Blacklist",
                          get = function() return cfg.blacklist end,
                          add = function(id)
                              cfg.blacklist = cfg.blacklist or {}
                              cfg.blacklist[id] = true
                          end,
                          remove = function(id)
                              if cfg.blacklist then
                                  cfg.blacklist[id] = nil
                                  if not next(cfg.blacklist) then cfg.blacklist = nil end
                              end
                          end,
                          onChanged = function() apply() end,
                      })
                  end },
                { key = PAB_ALL_BUFFS_KEY, label = "All Buffs",
                  tooltip = "Show every buff. Use the Hide lane below to remove specific filters." },
                { key = PAB_HAS_DURATION_KEY, label = "Has Duration",
                  tooltip = "Show every buff that has a duration (hides permanent buffs). Use the Hide lane below to remove specific filters." },
            }
            -- Default Buffs bar only: the enchant cells publish from that bar
            -- alone, so the row would be a dead switch on custom buff bars.
            if isDefault then
                items[#items + 1] = { key = PAB_WEAPON_ENCH_KEY, label = "Weapon Enchants",
                  tooltip = "Show weapon oil and imbue icons at the front of this bar. They are weapon enchants rather than auras, so they show independently of the options above -- and the aura grid is shifted inward to make room for them, with every row shifting over by the same amount." }
            end
            items[#items + 1] = { isHeader = true, label = "Show", rightLabel = "Hide" }
            for i = 1, #filters do
                items[#items + 1] = { key = filters[i].id, label = filters[i].name,
                    dual = true, showLockedFn = BroadOn }
            end
            return items
        end
        local warnClosed
        -- Crossing the enchants-only boundary rewrites the grid sliders and the
        -- bar's name, which aren't lightweight-refresh clients -- but a forced
        -- RefreshPage(true) mid-click would also tear down this open dropdown.
        -- So the force is DEFERRED: the setters mark it and onMenuClosed flushes
        -- it once the menu hides (the widget's documented defer pattern). While
        -- the menu stays open the sliders behind it are briefly stale; they
        -- rebuild the moment it closes.
        local pendingForce
        local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 190, rgn:GetFrameLevel() + 2,
            FilterItems,
            function(k, neg)
                if k == PAB_ALL_BUFFS_KEY then return AllBuffsOn() end
                if k == PAB_HAS_DURATION_KEY then return cfg.hasDuration == true end
                if k == PAB_WEAPON_ENCH_KEY then return cfg.showWeaponEnchants == true end
                if neg then
                    local nf = cfg.negFilters
                    return nf and nf[k] == true
                end
                local f = cfg.filters
                return f and f[k] == true
            end,
            function(k, v, neg)
                if k == PAB_ALL_BUFFS_KEY then
                    cfg.showAllBuffs = v
                    -- Mutually exclusive with Has Duration -- both are broad-content
                    -- modes. The show/hide lanes PERSIST across mode flips (the hide
                    -- lane subtracts in both modes; the show lane simply goes dormant
                    -- while broad content is on). Extra Spells stay untouched.
                    cfg.hasDuration = nil
                    if SyncWeaponEnchantsGrid(cfg) then pendingForce = true end
                    apply()
                    -- Non-force, same as every other row: the open menu
                    -- refreshes its own checks/locks in place, so a mode
                    -- flip must not tear the page down under it. Crossing the
                    -- enchants-only boundary defers its rebuild to menu close
                    -- (pendingForce above).
                    EllesmereUI:RefreshPage()
                    return
                end
                if k == PAB_HAS_DURATION_KEY then
                    cfg.hasDuration = v or nil
                    -- Mutually exclusive with All Buffs (a broad-content mode of its
                    -- own); lanes persist, same as All Buffs.
                    if v then cfg.showAllBuffs = false end
                    if SyncWeaponEnchantsGrid(cfg) then pendingForce = true end
                    apply()
                    EllesmereUI:RefreshPage()
                    return
                end
                if k == PAB_WEAPON_ENCH_KEY then
                    -- Its own content source (oils/imbues are not auras), so it
                    -- neither clears nor is cleared by the two modes above and
                    -- never touches the filter lanes.
                    cfg.showWeaponEnchants = v and true or nil
                    if SyncWeaponEnchantsGrid(cfg) then pendingForce = true end
                    apply()
                    -- Non-force so this open dropdown survives the click, same
                    -- as every other row. Entering/leaving enchants-only
                    -- rewrites the grid sliders (Icons per Row / Max Rows /
                    -- Max Total) and the bar's name, none of which are
                    -- RegisterWidgetRefresh clients -- that rebuild is
                    -- deferred to menu close (pendingForce).
                    EllesmereUI:RefreshPage()
                    return
                end
                -- Two-lane real-filter write: checking one lane clears the other;
                -- emptied lane tables drop to nil (saved-variable hygiene).
                if neg then
                    cfg.negFilters = cfg.negFilters or {}
                    cfg.negFilters[k] = v or nil
                    if not next(cfg.negFilters) then cfg.negFilters = nil end
                    if v and cfg.filters then cfg.filters[k] = nil end
                else
                    cfg.filters = cfg.filters or {}
                    cfg.filters[k] = v or nil
                    if v and cfg.negFilters then
                        cfg.negFilters[k] = nil
                        if not next(cfg.negFilters) then cfg.negFilters = nil end
                    end
                end
                if cfg.filters and not next(cfg.filters) then cfg.filters = nil end
                apply()
                -- Non-force: runs only the registered lightweight refresh callbacks
                -- (e.g. the sidebar tile's subtitleFn) in-place, unlike
                -- RefreshPage(true) which would tear down and rebuild the whole page --
                -- and close this open dropdown mid multi-select.
                EllesmereUI:RefreshPage()
            end,
            nil, 12, nil, nil, function()
                if warnClosed then warnClosed() end
                -- Flush the deferred enchants-only rebuild now that closing
                -- can no longer strand an open menu.
                if pendingForce then
                    pendingForce = nil
                    EllesmereUI:RefreshPage(true)
                end
            end)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD; rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbRefresh)
        warnClosed = EllesmereUI.AttachEmptyFilterWarn(rgn, cbDD,
            L("You are displaying NO buffs at all."), BuffBarHasContent)
    end

    -- RIGHT: Extra Spells checkbox dropdown (direct cfg.spells only, see
    -- doc comment above for why there is no "Presets" group here). Shares
    -- ffRow with Filters (redesign) instead of its own row.
    do
        local rgn = ffRow._rightRegion
        if rgn._control then rgn._control:Hide() end
        local function HasDirect(id)
            local sp = cfg.spells
            if not sp then return false end
            for i = 1, #sp do if sp[i] == id then return true end end
            return false
        end
        local function ShowCustomIdPopup()
            EllesmereUI:ShowInputPopup({
                title = L("Add Spell ID"),
                message = L("Enter the spell ID to track."),
                confirmText = L("Add"), cancelText = L("Cancel"),
                onConfirm = function(text)
                    local id = tonumber(text or "")
                    if id and id > 0 and not HasDirect(id) then
                        cfg.spells = cfg.spells or {}
                        cfg.spells[#cfg.spells + 1] = id
                        apply()
                        EllesmereUI:RefreshPage(true)
                    end
                end,
            })
        end
        local function SpellEntry(id)
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            return { key = id, label = (name or ("Spell " .. tostring(id))),
                icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) }
        end
        local function ByLabel(a, b) return a.label < b.label end
        local function ExtraItems()
            -- Spells already provided by ASSIGNED FILTERS' enabled spells
            -- are excluded from Presets (adding them as extras would be
            -- redundant) -- same exclusion BM2 applies.
            local covered = {}
            if cfg.filters then
                for fid in pairs(cfg.filters) do
                    local f = ns.PAB_GetFilter and ns.PAB_GetFilter(fid)
                    if f then
                        for id, on in pairs(f.spells) do
                            if on then covered[id] = true end
                        end
                    end
                end
            end
            local universe = DedupedPresetSpellUniverse()
            local selected, rest = {}, {}
            local seen = {}
            local sp = cfg.spells or {}
            for i = 1, #sp do
                seen[sp[i]] = true
                selected[#selected + 1] = SpellEntry(sp[i])
            end
            for i = 1, #universe do
                local id = universe[i]
                if not seen[id] and not covered[id] then rest[#rest + 1] = SpellEntry(id) end
            end
            table.sort(selected, ByLabel)
            table.sort(rest, ByLabel)
            local items = {
                { isTopAction = true, label = "Custom Spell ID", onClick = ShowCustomIdPopup },
            }
            if #selected > 0 then
                items[#items + 1] = { isHeader = true, label = "Selected" }
                for i = 1, #selected do items[#items + 1] = selected[i] end
            end
            items[#items + 1] = { isHeader = true, label = "Presets" }
            for i = 1, #rest do items[#items + 1] = rest[i] end
            return items
        end
        local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 190, rgn:GetFrameLevel() + 2,
            ExtraItems,
            HasDirect,
            function(k, v)
                cfg.spells = cfg.spells or {}
                if v then
                    if not HasDirect(k) then cfg.spells[#cfg.spells + 1] = k end
                else
                    -- Unchecking drops the whole curated family, not just this id:
                    -- PAB_ResolveSpells expands a family from any member, so a
                    -- differently-named sibling left in the list would keep the buff
                    -- tracked behind an unchecked box. Same family = same table.
                    local fam = ns.PAB_SPELL_FAMILY and ns.PAB_SPELL_FAMILY[k]
                    for i = #cfg.spells, 1, -1 do
                        local id = cfg.spells[i]
                        if id == k or (fam and ns.PAB_SPELL_FAMILY[id] == fam) then
                            table.remove(cfg.spells, i)
                        end
                    end
                end
                apply()
                -- Same reasoning as the Filters dropdown above: lightweight
                -- refresh only, so this checkbox dropdown stays open. The
                -- Filters dropdown's empty warning re-evaluates through the
                -- widget-refresh pass, so emptying a bar from THIS dropdown
                -- lights it up too.
                EllesmereUI:RefreshPage()
            end,
            nil, 10, true)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD; rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbRefresh)
    end

    return sy
end

-- "Assigned Debuffs": unified Filters dropdown (same model as Raid Frames' Debuff
-- Manager base grid): pinned "All Debuffs" row above a Show/Hide caption row, then
-- TWO-LANE class rows -- ONE control, live in both modes. The left checkbox SHOWS a
-- class (cfg.classFilters, add mode; dimmed while All Debuffs is on), the right red
-- box HIDES it (cfg.negClassFilters -- hidden chain links / inverted candidates in
-- both modes, see DebuffSubtractFn/BuildChain). Lanes are mutually exclusive per
-- class and persist across mode flips. Used by BOTH the default Debuffs bar and
-- every custom debuff bar.
local function BuildAssignedDebuffsFields(frame, fontPath, sy, cfg, apply)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local _, hh = 0, 0

    _, hh = W:SectionHeader(frame, "ASSIGNED DEBUFFS", sy); sy = sy - hh

    local safRow
    safRow, hh = W:DualRow(frame, sy,
        {
            type = "dropdown", text = "Filters",
            values = { __placeholder = "..." }, order = { "__placeholder" },
            getValue = function() return "__placeholder" end, setValue = function() end
        },
        { type = "label", text = "" }
    ); sy = sy - hh
    do
        local rgn = safRow._leftRegion
        if rgn._control then rgn._control:Hide() end
        local PAB_ALL_DEBUFFS_KEY = "__allDebuffs"
        local PAB_DEBUFF_HAS_DUR_KEY = "__debuffHasDuration"
        local function AllOn() return cfg.showAllDebuffs ~= false end
        -- Hovering a dimmed Show box explains the dim (the lane is inert
        -- while All Debuffs already shows everything). Has Duration is an
        -- AND-modifier, not a mode: it never locks the lane.
        local lockedTip = L("All Debuffs is selected, so every debuff already shows. Use the red Hide box to exclude these instead.")
        local function FilterItems()
            local items = {
                { key = PAB_ALL_DEBUFFS_KEY, label = "All Debuffs",
                  tooltip = "Show every debuff. Use the Hide lane below to remove specific filters." },
                { key = PAB_DEBUFF_HAS_DUR_KEY, label = "Has Duration",
                  tooltip = "Only show debuffs that have a duration, excluding permanent ones. Combines with the filters below; checked alone it shows every timed debuff." },
                { isHeader = true, label = "Show", rightLabel = "Hide" },
            }
            local classItems = ns.PAB_ClassItems and ns.PAB_ClassItems(false) or {}
            for i = 1, #classItems do
                local ci = classItems[i]
                items[#items + 1] = { key = ci.key, label = ci.label, tooltip = ci.tooltip,
                    dual = true, showLockedFn = AllOn,
                    showLockedTooltip = lockedTip }
            end
            return items
        end
        local warnClosed
        local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 190, rgn:GetFrameLevel() + 2,
            FilterItems,
            function(k, neg)
                if k == PAB_ALL_DEBUFFS_KEY then return AllOn() end
                if k == PAB_DEBUFF_HAS_DUR_KEY then return cfg.hasDuration == true end
                if neg then
                    local nf = cfg.negClassFilters
                    return nf and nf[k] == true
                end
                local f = cfg.classFilters
                return f and f[k] == true
            end,
            function(k, v, neg)
                if k == PAB_ALL_DEBUFFS_KEY then
                    -- Stores the raw boolean directly (nil must mean "on",
                    -- same convention as showAllBuffs). Lanes persist across
                    -- mode flips (the hide lane subtracts in both modes).
                    cfg.showAllDebuffs = v
                    apply()
                    EllesmereUI:RefreshPage()
                    return
                end
                if k == PAB_DEBUFF_HAS_DUR_KEY then
                    -- AND-modifier (native maxDuration on every debuff group;
                    -- permanents excluded): combines with All Debuffs or any
                    -- class-filter selection; alone it acts as the timed
                    -- catch-all (DebuffCatchAllOn).
                    cfg.hasDuration = v or nil
                    apply()
                    EllesmereUI:RefreshPage()
                    return
                end
                -- Two-lane class write: checking one lane clears the other;
                -- emptied lane tables drop to nil (saved-variable hygiene).
                if neg then
                    cfg.negClassFilters = cfg.negClassFilters or {}
                    cfg.negClassFilters[k] = v or nil
                    if not next(cfg.negClassFilters) then cfg.negClassFilters = nil end
                    if v and cfg.classFilters then cfg.classFilters[k] = nil end
                else
                    cfg.classFilters = cfg.classFilters or {}
                    cfg.classFilters[k] = v or nil
                    if v and cfg.negClassFilters then
                        cfg.negClassFilters[k] = nil
                        if not next(cfg.negClassFilters) then cfg.negClassFilters = nil end
                    end
                end
                if cfg.classFilters and not next(cfg.classFilters) then cfg.classFilters = nil end
                apply()
                -- Non-force: runs only the registered lightweight refresh
                -- callbacks (e.g. the sidebar tile's subtitleFn) in place,
                -- without closing this open dropdown.
                EllesmereUI:RefreshPage()
            end,
            nil, 12, nil, nil, function() if warnClosed then warnClosed() end end)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD; rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbRefresh)
        warnClosed = EllesmereUI.AttachEmptyFilterWarn(rgn, cbDD,
            L("You are displaying NO debuffs at all."),
            function()
                if not ns.PAB_DebuffBarHasContent then return true end
                return ns.PAB_DebuffBarHasContent(cfg) and true or false
            end)
    end

    return sy
end

-- "Core": Icon Size (+Icon Zoom cog) | Growth Direction;
--         Sort Method | Sort Direction;
--         Duration [+expand][swatch][toggle] | Stacks [+expand][swatch][toggle].
-- Shared by every bar (default + custom, buff + debuff) -- growDirection is generic
-- (BuildContainerSpec doesn't care about slots vs. groups). isBuff is currently unused
-- here (Sort Method's option set is now shared between buffs/debuffs, see
-- SORT_METHOD_VALUES' doc comment) but kept for callers/future per-polarity fields.
local function BuildCoreFields(frame, fontPath, sy, cfg, apply, isBuff)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local _, hh = 0, 0

    _, hh = W:SectionHeader(frame, "CORE", sy); sy = sy - hh

    local sizeRow
    sizeRow, hh = W:DualRow(frame, sy,
        {
            type = "slider", text = "Icon Size", min = 16, max = 400, step = 1, trackWidth = 120,
            getValue = function() return cfg.iconSize or 32 end,
            setValue = function(v) cfg.iconSize = v; apply() end
        },
        {
            type = "dropdown", text = "Growth Direction",
            values = GROW_DIR_VALUES, order = GROW_DIR_ORDER,
            getValue = function() return cfg.growDirection or "LEFT" end,
            setValue = function(v)
                -- Change the wrap direction to be a valid value from the new growth direction
                if v == "UP" or v == "DOWN" then
                    if cfg.iconWrapDirection ~= "LEFT" and cfg.iconWrapDirection ~= "RIGHT" then
                        cfg.iconWrapDirection = "LEFT"
                    end
                elseif v == "LEFT" or v == "RIGHT" then
                    if cfg.iconWrapDirection ~= "UP" and cfg.iconWrapDirection ~= "DOWN" then
                        cfg.iconWrapDirection = "DOWN"
                    end
                end

                cfg.growDirection = v; apply()
            end
        }
    ); sy = sy - hh

    _, hh = W:DualRow(frame, sy,
        {
            type = "dropdown", text = "Sort Method",
            values = SORT_METHOD_VALUES, order = SORT_METHOD_ORDER,
            getValue = function() return cfg.sortMethod or "Default" end,
            setValue = function(v) cfg.sortMethod = v; apply() end
        },
        {
            type = "dropdown", text = "Sort Direction",
            values = SORT_DIR_VALUES, order = SORT_DIR_ORDER,
            getValue = function() return cfg.sortDirection or "Normal" end,
            setValue = function(v) cfg.sortDirection = v; apply() end
        }
    ); sy = sy - hh
    do
        local rgn = sizeRow._leftRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Icon Size",
            rows = {
                { type = "slider", label = "Icon Zoom", min = 0, max = 0.20, step = 0.01,
                  get = function() return cfg.iconZoom or 0.055 end,
                  set = function(v) cfg.iconZoom = v; apply() end },
            },
        })
        ns._PAMakeCogBtn(rgn, cogShow)
    end
    do
        -- Icon Wrap: only meaningful for vertical growth (Up/Down) and horizontal growth (Left/Right) -- decides which
        -- side additional columns stack toward when Icons Per Row/Column > 1. Cog-only,
        -- no separate dropdown row, and only shown while Growth Direction is Up/Down or Left/Right.
        local rgn = sizeRow._rightRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Growth",
            rows = {
                { type = "dropdown", label = "Icon Wrap",
                  values = ICON_WRAP_VALUES, order = ICON_WRAP_ORDER,
                  get = function() return cfg.iconWrapDirection or "LEFT" end,
                  set = function(v) cfg.iconWrapDirection = v; apply() end,
                  itemDisabled = function(v)
                      if cfg.growDirection == "LEFT" or cfg.growDirection == "RIGHT" then
                        return v == "LEFT" or v == "RIGHT"
                      elseif cfg.growDirection == "UP" or cfg.growDirection == "DOWN" then
                        return v == "UP" or v == "DOWN"
                      end
                      return false
                  end,
                 },
            },
        })
        local cogBtn = ns._PAMakeCogBtn(rgn, cogShow)
        local function UpdateWrapCogVisibility()
            local dir = cfg.growDirection or "LEFT"
            cogBtn:SetShown(dir == "UP" or dir == "DOWN" or dir == "LEFT" or dir == "RIGHT")
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateWrapCogVisibility)
        UpdateWrapCogVisibility()
    end

    local function AttachCog(rgn, title, rows)
        local _, cogShow = EllesmereUI.BuildCogPopup({ title = title, rows = rows })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
    end

    local dsRow
    dsRow, hh = W:DualRow(frame, sy,
        {
            type = "toggle", text = "Duration",
            getValue = function() return cfg.durationShow ~= false end,
            setValue = function(v) cfg.durationShow = v; apply() end
        },
        {
            type = "toggle", text = "Stacks",
            getValue = function() return cfg.stackShow ~= false end,
            setValue = function(v) cfg.stackShow = v; apply() end
        }
    ); sy = sy - hh
    do
        local rgn = dsRow._leftRegion
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, dsRow:GetFrameLevel() + 3,
            function() return (cfg.durationColorR or 1), (cfg.durationColorG or 1), (cfg.durationColorB or 1), 1 end,
            function(r, g, b) cfg.durationColorR, cfg.durationColorG, cfg.durationColorB = r, g, b; apply() end,
            false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(updateSwatch)
        AttachCog(rgn, "Duration Text", {
            { type = "slider", label = "Text Size", min = 6, max = 60, step = 1,
              get = function() return cfg.durationTextSize or 11 end,
              set = function(v) cfg.durationTextSize = v; apply() end },
            { type = "slider", label = "Offset X", min = -50, max = 50, step = 1,
              get = function() return cfg.durationOffsetX or 0 end,
              set = function(v) cfg.durationOffsetX = v; apply() end },
            { type = "slider", label = "Offset Y", min = -50, max = 50, step = 1,
              get = function() return cfg.durationOffsetY or 0 end,
              set = function(v) cfg.durationOffsetY = v; apply() end },
            { type = "dropdown", label = "Position",
              values = AURA_POINT_VALUES, order = AURA_POINT_ORDER,
              get = function() return cfg.durationPosition or "CENTER" end,
              set = function(v) cfg.durationPosition = v; apply() end },
            { type = "toggle", label = "Show S for Seconds",
              get = function() return cfg.durationShowSeconds == true end,
              set = function(v) cfg.durationShowSeconds = v and true or nil; apply() end },
            { type = "slider", label = "Precise Below (minutes, 0 = off)", min = 0, max = 60, step = 1,
              get = function() return cfg.durationPrecisionThreshold and cfg.durationPrecisionThreshold / 60 or 0 end,
              set = function(v) cfg.durationPrecisionThreshold = v > 0 and math.floor(v * 60 + 0.5) or nil; apply() end },
        })
    end
    do
        local rgn = dsRow._rightRegion
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, dsRow:GetFrameLevel() + 3,
            function() return (cfg.stackColorR or 1), (cfg.stackColorG or 1), (cfg.stackColorB or 1), 1 end,
            function(r, g, b) cfg.stackColorR, cfg.stackColorG, cfg.stackColorB = r, g, b; apply() end,
            false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(updateSwatch)
        AttachCog(rgn, "Stacks Text", {
            { type = "slider", label = "Text Size", min = 6, max = 60, step = 1,
              get = function() return cfg.stackTextSize or 11 end,
              set = function(v) cfg.stackTextSize = v; apply() end },
            { type = "slider", label = "Offset X", min = -50, max = 50, step = 1,
              get = function() return cfg.stackOffsetX or 0 end,
              set = function(v) cfg.stackOffsetX = v; apply() end },
            { type = "slider", label = "Offset Y", min = -50, max = 50, step = 1,
              get = function() return cfg.stackOffsetY or 0 end,
              set = function(v) cfg.stackOffsetY = v; apply() end },
            { type = "dropdown", label = "Position",
              values = AURA_POINT_VALUES, order = AURA_POINT_ORDER,
              get = function() return cfg.stackPosition or "BOTTOMRIGHT" end,
              set = function(v) cfg.stackPosition = v; apply() end },
        })
    end

    return sy
end

-- "Display": Border Size [swatch] | Spacing; Icons per Row (+Max Rows/Max
-- Total/Row Spacing cog) | spacer.
local function BuildDisplayFields(frame, fontPath, sy, cfg, apply, isBuff)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local _, hh = 0, 0

    _, hh = W:SectionHeader(frame, "DISPLAY", sy); sy = sy - hh

    local borderRow
    borderRow, hh = W:DualRow(frame, sy,
        {
            type = "dropdown", text = "Border Size",
            values = BORDER_SIZE_VALUES, order = BORDER_SIZE_LEVELS,
            itemDisabled = function(v)
                local shape = cfg.iconShape
                return shape and shape ~= "none" and BORDER_SIZE_SHAPE_DISABLED[v] or false
            end,
            itemDisabledTooltip = function()
                return "This option requires a non-custom shape to be selected"
            end,
            getValue = function() return BORDER_SIZE_KEY[cfg.borderSize or 1] or "thin" end,
            setValue = function(v) cfg.borderSize = BORDER_SIZE_NUM[v] or 1; apply() end
        },
        {
            type = "slider", text = "Spacing", min = -5, max = 20, step = 1, trackWidth = 120,
            getValue = function() return cfg.padding or 5 end,
            setValue = function(v) cfg.padding = v; apply() end
        }
    ); sy = sy - hh
    do
        local rgn = borderRow._leftRegion
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, borderRow:GetFrameLevel() + 3,
            function()
                return (cfg.borderR or 0), (cfg.borderG or 0), (cfg.borderB or 0), (cfg.borderA or 1)
            end,
            function(r, g, b, a)
                cfg.borderR, cfg.borderG, cfg.borderB, cfg.borderA = r, g, b, a
                apply()
            end,
            true, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(updateSwatch)
    end
    do
        local rgn = borderRow._leftRegion
        local keys, labels = {}, {}
        for _, entry in ipairs(PabAllBarEntries()) do
            keys[#keys + 1] = entry.key
            labels[entry.key] = entry.label
        end
        local function CopyBorderTo(entry)
            entry.cfg.borderSize = cfg.borderSize
            -- A SHAPED target can't render Thin/Normal/Heavy (its shape border
            -- has only off/Strong states; the dropdown disables those levels).
            -- Snap to Strong so a sync can't strand a shaped bar on a level it
            -- could never pick, silently losing its border and dispel ring.
            local sz = entry.cfg.borderSize or 1
            if entry.cfg.iconShape and entry.cfg.iconShape ~= "none"
                and sz >= 1 and sz <= 3 then
                entry.cfg.borderSize = BORDER_SIZE_NUM[BORDER_SIZE_DEFAULT_SHAPE]
            end
            entry.cfg.borderR, entry.cfg.borderG, entry.cfg.borderB, entry.cfg.borderA =
                cfg.borderR, cfg.borderG, cfg.borderB, cfg.borderA
            PabApplyBarEntry(entry)
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Border Size and Color to all Bars",
            onClick = function()
                for _, entry in ipairs(PabAllBarEntries()) do
                    if entry.cfg ~= cfg then CopyBorderTo(entry) end
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local size = cfg.borderSize or 1
                local r, g, b, a = cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, cfg.borderA or 1
                for _, entry in ipairs(PabAllBarEntries()) do
                    local c = entry.cfg
                    if (c.borderSize or 1) ~= size or (c.borderR or 0) ~= r or (c.borderG or 0) ~= g
                        or (c.borderB or 0) ~= b or (c.borderA or 1) ~= a then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = keys,
                elementLabels = labels,
                getCurrentKey = function() return PabBarKeyOf(cfg, isBuff) end,
                onApply       = function(checkedKeys)
                    local byKey = {}
                    for _, entry in ipairs(PabAllBarEntries()) do byKey[entry.key] = entry end
                    for _, key in ipairs(checkedKeys) do
                        local entry = byKey[key]
                        if entry then CopyBorderTo(entry) end
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    do
        -- Row Spacing lives here, not in Icons Per Row's cog -- it's spacing between
        -- rows, same family as Spacing (icon-to-icon gap), not a grid-size concern like
        -- Icons Per Row/ Max Rows/Max Total.
        local rgn = borderRow._rightRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Spacing",
            rows = {
                -- nil = 12px default -- deliberately
                -- decoupled from Spacing/padding, no longer mirrors it.
                { type = "slider", label = "Row Spacing", min = -5, max = 20, step = 1,
                  get = function() return cfg.rowSpacing or 12 end,
                  set = function(v) cfg.rowSpacing = v; apply() end },
            },
        })
        ns._PAMakeCogBtn(rgn, cogShow)
    end

    local rowRow
    rowRow, hh = W:DualRow(frame, sy,
        {
            type = "slider", text = "Icons Per Row", min = 1, max = 20, step = 1, trackWidth = 120,
            getValue = function() return cfg.iconsPerRow or (isBuff and 11 or 8) end,
            setValue = function(v) cfg.iconsPerRow = v; apply() end
        },
        {
            type = "dropdown", text = "Font Outline",
            values = FONT_OUTLINE_VALUES, order = FONT_OUTLINE_ORDER,
            getValue = function() return cfg.fontOutline or "default" end,
            setValue = function(v) cfg.fontOutline = v; apply() end
        }
    ); sy = sy - hh
    do
        -- Verified against EUI_RaidFrames_BuffManager.lua's "legacy layout"
        -- branch: perRowCfg paired with a blank spacer, cog on
        -- gridRow._leftRegion -- i.e. directly on Icons Per Row's own
        -- region. Same trackWidth=120 slider + cog combo used there.
        local rgn = rowRow._leftRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Icons Per Row",
            rows = {
                { type = "slider", label = "Max Rows", min = 1, max = 10, step = 1,
                  get = function() return cfg.maxRows or (isBuff and 3 or 2) end,
                  set = function(v) cfg.maxRows = v; apply() end },
                { type = "slider", label = "Max Total", min = 1, max = 40, step = 1,
                  get = function() return cfg.maxTotal or (isBuff and 32 or 16) end,
                  set = function(v) cfg.maxTotal = v; apply() end },
            },
        })
        ns._PAMakeCogBtn(rgn, cogShow)
    end

    -- Icon Shape reuses the base Border Size/Color above -- no separate shape fields.
    local shapeRow
    shapeRow, hh = W:DualRow(frame, sy,
        {
            type = "dropdown", text = "Icon Shape",
            values = SHAPE_VALUES, order = SHAPE_ORDER,
            getValue = function() return cfg.iconShape or "none" end,
            setValue = function(v)
                cfg.iconShape = v
                -- Entering shape mode with a now-disabled Border Size level selected:
                -- snap to the shape default, same as Action Bars' own shape dropdown
                -- resetting border thickness on every shape change.
                local curKey = BORDER_SIZE_KEY[cfg.borderSize or 1] or "thin"
                if v ~= "none" and BORDER_SIZE_SHAPE_DISABLED[curKey] then
                    cfg.borderSize = BORDER_SIZE_NUM[BORDER_SIZE_DEFAULT_SHAPE]
                end
                apply()
            end
        },
        {
            -- cfg.iconZoom stays a raw 0-1 fraction (SetTexCoord's own units); the
            -- slider itself works in percent, like Action Bars' Icon Zoom.
            type = "slider", text = "Icon Zoom", min = 0, max = 15, step = 0.5, trackWidth = 120,
            getValue = function() return (cfg.iconZoom or 0.055) * 100 end,
            setValue = function(v) cfg.iconZoom = v / 100; apply() end
        }
    ); sy = sy - hh
    do
        local rgn = shapeRow._leftRegion
        local keys, labels = {}, {}
        for _, entry in ipairs(PabAllBarEntries()) do
            keys[#keys + 1] = entry.key
            labels[entry.key] = entry.label
        end
        -- Same snap rule as the Icon Shape dropdown's own setValue: a bar
        -- ENTERING shape mode while sitting on Thin/Normal/Heavy would render
        -- no shape border at those levels (and the dropdown disables them), so
        -- the sync snaps it to Strong exactly as a manual shape pick would.
        local function CopyShapeTo(entry)
            local shape = cfg.iconShape
            entry.cfg.iconShape = shape
            local sz = entry.cfg.borderSize or 1
            if shape and shape ~= "none" and sz >= 1 and sz <= 3 then
                entry.cfg.borderSize = BORDER_SIZE_NUM[BORDER_SIZE_DEFAULT_SHAPE]
            end
            PabApplyBarEntry(entry)
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Icon Shape to all Bars",
            onClick = function()
                for _, entry in ipairs(PabAllBarEntries()) do
                    if entry.cfg ~= cfg then CopyShapeTo(entry) end
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local shape = cfg.iconShape or "none"
                for _, entry in ipairs(PabAllBarEntries()) do
                    if (entry.cfg.iconShape or "none") ~= shape then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = keys,
                elementLabels = labels,
                getCurrentKey = function() return PabBarKeyOf(cfg, isBuff) end,
                onApply       = function(checkedKeys)
                    local byKey = {}
                    for _, entry in ipairs(PabAllBarEntries()) do byKey[entry.key] = entry end
                    for _, key in ipairs(checkedKeys) do
                        local entry = byKey[key]
                        if entry then CopyShapeTo(entry) end
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    local swipeRow
    swipeRow, hh = W:DualRow(frame, sy,
        {
            type = "toggle", text = "Show Duration Swipe",
            getValue = function() return cfg.showSwipe ~= false end,
            setValue = function(v) cfg.showSwipe = v; apply() end
        },
        {
            type = "toggle", text = "Show Tooltips",
            tooltip = "Show aura tooltips when hovering this bar's icons.",
            getValue = function() return cfg.showTooltips ~= false end,
            setValue = function(v) cfg.showTooltips = v; apply() end
        }
    ); sy = sy - hh
    do
        local rgn = swipeRow._leftRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Duration Swipe",
            rows = {
                -- Default on = the swipe UNCOVERS the icon as time runs out
                -- (the module's shipped look); off = Blizzard's standard
                -- direction, darkness growing over the icon instead.
                { type = "toggle", label = "Reverse Swipe",
                  get = function() return cfg.reverseSwipe ~= false end,
                  set = function(v) cfg.reverseSwipe = v; apply() end },
            },
        })
        ns._PAMakeCogBtn(rgn, cogShow)
    end

    -- Buff bars only: debuffs are never player-cancelable, so the row would
    -- be a dead switch there. (Weapon enchants used to share this row as a
    -- second toggle; they are a content source rather than a display tweak,
    -- so they now live as the "Weapon Enchants" pinned row in the Filters
    -- dropdown -- see BuildAssignedBuffsFields.)
    if isBuff then
        _, hh = W:DualRow(frame, sy,
            {
                type = "toggle", text = "Right-Click to Cancel",
                tooltip = "Right-clicking a buff icon cancels the buff. Turning this off makes the bar's icons click-through; tooltips still follow the Show Tooltips setting.",
                getValue = function() return cfg.rightClickCancel ~= false end,
                setValue = function(v) cfg.rightClickCancel = v; apply() end
            },
            { type = "label", text = "" }
        ); sy = sy - hh
    end

    return sy
end

-- Debuff-category bars only (default debuffs + custom debuff bars).
local DISPEL_ICON_POS_VALUES = {
    none        = "None",
    topleft     = "Top Left",
    top         = "Top",
    topright    = "Top Right",
    left        = "Left",
    center      = "Center",
    right       = "Right",
    bottomleft  = "Bottom Left",
    bottom      = "Bottom",
    bottomright = "Bottom Right",
}
local DISPEL_ICON_POS_ORDER = { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }

local function BuildDispelColorFields(frame, fontPath, sy, cfg, apply)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local _, hh = 0, 0

    -- Dispel-type indicator icon on each debuff bar (engine-driven, mirrors
    -- Raid Frames' "Type Icon Position"). "none" (default) = feature off.
    _, hh = W:SectionHeader(frame, "DEBUFF TYPE ICON", sy); sy = sy - hh
    do
        local function IconOn() return (cfg.dispelIconPosition or "none") ~= "none" end
        local row
        row, hh = W:DualRow(frame, sy,
            { type = "dropdown", text = "Type Icon Position",
              tooltip = "Shows the debuff's dispel type icon (Magic, Curse, Disease, Poison, Bleed) on the bar.",
              values = DISPEL_ICON_POS_VALUES, order = DISPEL_ICON_POS_ORDER,
              getValue = function() return cfg.dispelIconPosition or "none" end,
              setValue = function(v)
                  cfg.dispelIconPosition = v
                  apply()
                  EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "" }
        ); sy = sy - hh
        local rgn = row._leftRegion
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Type Icon",
            rows = {
                { type = "slider", label = "Icon Size", min = 8, max = 48, step = 1,
                  get = function() return cfg.dispelIconSize or 16 end,
                  set = function(v) cfg.dispelIconSize = v; apply() end },
                { type = "slider", label = "Offset X", min = -50, max = 50, step = 1,
                  get = function() return cfg.dispelIconOffsetX or 0 end,
                  set = function(v) cfg.dispelIconOffsetX = v; apply() end },
                { type = "slider", label = "Offset Y", min = -50, max = 50, step = 1,
                  get = function() return cfg.dispelIconOffsetY or 0 end,
                  set = function(v) cfg.dispelIconOffsetY = v; apply() end },
            },
        })
        local cogBtn = ns._PAMakeCogBtn(rgn, function(self)
            if IconOn() then cogShow(self) end
        end)
        cogBtn:SetAlpha(IconOn() and 0.4 or 0.15)
        cogBtn:SetScript("OnEnter", function(self) if IconOn() then self:SetAlpha(0.7) end end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(IconOn() and 0.4 or 0.15) end)
    end

    _, hh = W:SectionHeader(frame, "DISPEL COLORS", sy); sy = sy - hh

    local function AddDispelSwatch(rgn, entry)
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, rgn:GetFrameLevel() + 3,
            function()
                local c = cfg[entry.key]
                if c then return c.r or 1, c.g or 1, c.b or 1, 1 end
                return entry.fallback[1], entry.fallback[2], entry.fallback[3], 1
            end,
            function(r, g, b)
                cfg[entry.key] = { r = r, g = g, b = b }
                apply()
            end,
            false, 18)
        PP.Point(swatch, "RIGHT", rgn, "RIGHT", -20, 0)
        EllesmereUI.RegisterWidgetRefresh(updateSwatch)
    end
    for i = 1, #DISPEL_COLOR_ROWS, 2 do
        local left, right = DISPEL_COLOR_ROWS[i], DISPEL_COLOR_ROWS[i + 1]
        local row
        row, hh = W:DualRow(frame, sy,
            { type = "label", text = left.label },
            right and { type = "label", text = right.label } or { type = "label", text = "" }
        ); sy = sy - hh
        AddDispelSwatch(row._leftRegion, left)
        if right then AddDispelSwatch(row._rightRegion, right) end
    end

    return sy
end

-------------------------------------------------------------------------------
--  Icon Effects Per-Filter (debuffs only) -- ported from Raid Frames'
--  BuildFxEffects (EUI_RaidFrames_ManagerPages.lua), NOT shared code. Each
--  cfg.fxList entry: a Filters set (ns.PAB_FxClassItems -- PAB's debuff
--  category vocabulary keyed by the lowercase engine group key, plus a
--  synthetic "all" catch-all) + optional Icon Glow + Border override + Size
--  override. The engine side (EllesmereUIUnitFrames_PlayerAuraBars.lua)
--  matches the FIRST active block whose filters include a button's
--  category -- see PAB_ApplyDmFx/PAB_FxBlockFor there.
-------------------------------------------------------------------------------

local function BuildFxEffects(frame, sy, cfg, apply)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    if not (W and PP) then return sy end
    local hh
    local MEDIA_MP = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"

    local list = cfg.fxList or {}

    -- Only offer styles PAB_ApplyDmFx can actually render as selected
    -- live: every driver-ticked style (procedural/buttonGlow/
    -- autocast/shapeGlow) gets unconditionally remapped to a FlipBook-safe
    -- style on real AuraButtons -- confirmed permanent in Blizzard's own
    -- PTR 12.1 source (Blizzard_AuraButton.xml: useForbiddenObjectTable=
    -- "true" + ForbiddenAspects incl. ChangeParent, baked into the base
    -- template, not combat-conditional) -- so picking one here never
    -- actually shows live. Mirrors Glows.RestrictionSafeStyle's own gate
    -- (EllesmereUI_Glows.lua) rather than duplicating the style-name list.
    -- Re-include if Blizzard ever exposes a supported extension point.
    local GLOW_VALUES = { [0] = "None" }
    local GLOW_ORDER = { 0 }
    local Styles = EllesmereUI.Glows and EllesmereUI.Glows.STYLES
    if Styles then
        for i, entry in ipairs(Styles) do
            if not (entry.procedural or entry.buttonGlow or entry.autocast or entry.shapeGlow) then
                GLOW_VALUES[i] = entry.name
                GLOW_ORDER[#GLOW_ORDER + 1] = i
            end
        end
    end

    -- One "ICON EFFECTS" section block per list entry.
    for bi = 1, #list do
        local e = list[bi]
        if not e.filters then e.filters = {} end

        local hdrRgn
        hdrRgn, hh = W:SectionHeader(frame, "ICON EFFECTS", sy); sy = sy - hh
        -- Remove X right after the section title text
        if hdrRgn then
            local del = CreateFrame("Button", nil, hdrRgn)
            del:SetSize(14, 14)
            if hdrRgn._label then
                del:SetPoint("LEFT", hdrRgn._label, "RIGHT", 8, 0)
            else
                del:SetPoint("BOTTOMRIGHT", hdrRgn, "BOTTOMRIGHT", 0, 6)
            end
            del:SetFrameLevel(hdrRgn:GetFrameLevel() + 2)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then dx:SetSnapToPixelGrid(false); dx:SetTexelSnappingBias(0) end
            dx:SetTexture(MEDIA_MP .. "eui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Delete"))
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                EllesmereUI.HideWidgetTooltip()
            end)
            local blockIdx = bi
            del:SetScript("OnClick", function()
                table.remove(list, blockIdx)
                apply()
                EllesmereUI:RefreshPage(true)
            end)
        end

        -- Row 1: Filters | Icon Glow (+ class/custom swatches)
        local row
        row, hh = W:DualRow(frame, sy,
            { type = "dropdown", text = "Filters",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end },
            { type = "dropdown", text = "Icon Glow",
              values = GLOW_VALUES, order = GLOW_ORDER,
              getValue = function() return e.glowType or 0 end,
              setValue = function(v) e.glowType = v; apply(); EllesmereUI:RefreshPage() end }); sy = sy - hh
        do
            local rgn = row._leftRegion
            if rgn._control then rgn._control:Hide() end
            local items = ns.PAB_FxClassItems and ns.PAB_FxClassItems() or {}
            local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 190, rgn:GetFrameLevel() + 2, items,
                function(k) return e.filters[k] == true end,
                function(k, v)
                    e.filters[k] = v or nil
                    apply()
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD; rgn._lastInline = nil
            if cbRefresh then EllesmereUI.RegisterWidgetRefresh(cbRefresh) end
        end
        do
            local rgn = row._rightRegion
            local ctrl = rgn._control

            local classSwatch, updateClassSwatch = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 0.82, 0
                end,
                function() end,
                false, 20)
            PP.Point(classSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            classSwatch:SetScript("OnClick", function()
                e.glowClassColor = true; apply(); EllesmereUI:RefreshPage()
            end)
            classSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Colored")
            end)
            classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function() return e.glowR or 1.0, e.glowG or 0.776, e.glowB or 0.376 end,
                function(r, g, b)
                    e.glowR, e.glowG, e.glowB = r, g, b
                    apply()
                end,
                false, 20)
            PP.Point(glowSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
            glowSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(glowSwatch, "Custom Colored")
            end)
            glowSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Click the dimmed custom swatch to switch back from class color.
            local origGlowClick = glowSwatch:GetScript("OnClick")
            glowSwatch:SetScript("OnClick", function(self, ...)
                if e.glowClassColor then
                    e.glowClassColor = false; apply(); EllesmereUI:RefreshPage()
                    return
                end
                if (e.glowType or 0) == 0 then return end
                if origGlowClick then origGlowClick(self, ...) end
            end)

            local function UpdateFxGlowState()
                local noGlow = (e.glowType or 0) == 0
                local isClassColored = e.glowClassColor
                glowSwatch:SetAlpha((isClassColored or noGlow) and 0.3 or 1)
                classSwatch:SetAlpha((isClassColored and not noGlow) and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateGlowSwatch(); updateClassSwatch(); UpdateFxGlowState() end)
            UpdateFxGlowState()
        end

        -- Row 2: Border (+ swatch) | Size (icon size for the matched
        -- filters; 0 = the bar's own icon size).
        local bRow
        bRow, hh = W:DualRow(frame, sy,
            { type = "dropdown", text = "Border",
              values = BORDER_SIZE_VALUES, order = BORDER_SIZE_LEVELS,
              itemDisabled = function(v)
                  local shape = cfg.iconShape
                  return shape and shape ~= "none" and BORDER_SIZE_SHAPE_DISABLED[v] or false
              end,
              itemDisabledTooltip = function()
                  return "This option requires a non-custom shape to be selected"
              end,
              getValue = function() return BORDER_SIZE_KEY[e.borderSize or 0] or "none" end,
              setValue = function(v) e.borderSize = BORDER_SIZE_NUM[v] or 0; apply() end },
            { type = "slider", text = "Size", min = 0, max = 400, step = 1, trackWidth = 120,
              getValue = function() return e.size or 0 end,
              setValue = function(v)
                  e.size = (v and v > 0) and v or nil
                  apply()
              end }); sy = sy - hh
        do
            local rgn = bRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(rgn, bRow:GetFrameLevel() + 3,
                function()
                    local c = e.borderColor or { r = 0, g = 0, b = 0 }
                    return c.r or 0, c.g or 0, c.b or 0, 1
                end,
                function(r, g, b)
                    e.borderColor = { r = r, g = g, b = b }
                    apply()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
        end
    end

    -- "Add Icon Effects Per-Filter" accent text link (centered)
    do
        local ar, ag, ab = 1, 0.82, 0.30
        if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
        local addBtn = CreateFrame("Button", nil, frame)
        addBtn:SetHeight(22)
        addBtn:SetPoint("TOP", frame, "TOP", 0, sy - 17)
        addBtn:SetFrameLevel(frame:GetFrameLevel() + 2)
        local lbl = addBtn:CreateFontString(nil, "OVERLAY")
        local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
        lbl:SetFont(fp, 16, "")
        lbl:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
        lbl:SetText(EllesmereUI.L("Add Icon Effects Per-Filter"))
        lbl:SetTextColor(ar, ag, ab)
        lbl:SetAlpha(0.9)
        addBtn:SetWidth(lbl:GetStringWidth() + 8)
        addBtn:SetScript("OnEnter", function() lbl:SetAlpha(1) end)
        addBtn:SetScript("OnLeave", function() lbl:SetAlpha(0.9) end)
        addBtn:SetScript("OnClick", function()
            cfg.fxList = cfg.fxList or {}
            cfg.fxList[#cfg.fxList + 1] = { filters = {} }
            EllesmereUI:RefreshPage(true)
        end)
        sy = sy - 17 - 22 - 8
    end
    return sy
end

-------------------------------------------------------------------------------
--  Default bar detail (Buffs / Debuffs -- fixed identity, not deletable)
-------------------------------------------------------------------------------

-- W:DualRow/W:SectionHeader compute their internal label/control proportions assuming
-- a frame padded like a standard single-column options page (EllesmereUI.CONTENT_PAD
-- margins on both sides, typically 45px). PAB's two-pane layout only reserves 20px for
-- its detail pane (PABMP_BuildPage), so DualRow's internal math runs against a
-- narrower frame than it expects and rows overlap -- confirmed by screenshots where
-- the overlap persists regardless of which region (left/right) carries the extra
-- widgets. Verified fix, ported from RaidFrames' ns.DMP_BuildPage (the exact page the
-- reference screenshot came from): oversize the frame actually handed to DualRow by
-- `padDiff` on both sides, shift it left by `padDiff` so its effective left edge still
-- lines up with the visible 20px inset, and clip the overflow on an outer frame
-- (RaidFrames: "DualRow width compensated so rows align with the 20px PAD"). fix:
-- `clip` is now a real ScrollFrame (was a plain Frame with SetClipsChildren --
-- silently cropped any overflow with no way to reach it, a pre-existing gap that only
-- became visible once the new preview box pushed settings fields below the fold).
-- Callers MUST call FinalizeCompensatedBody(body, finalSy) once after building all
-- their fields, so the scroll child's real height (and therefore the scrollbar's
-- thumb/track visibility) reflects actual content instead of a guess. fix:
-- restructured to put the padDiff shift on `scroll` itself (matching RaidFrames'
-- ns.DMP_BuildPage settingsScroll line-for-line) instead of on `body` inside an
-- unshifted scroll. Both are mathematically equivalent for where DualRow/SectionHeader
-- content ends up (verified via /fstack + a full frame-tree dump: both put rows at
-- parentFrame_left + PAD) -- but there is a REAL ~30px visual difference in-game (PAB
-- ~50px, RaidFrames Debuff Manager ~20px) that this math could not explain and
-- multiple manual measurements confirmed. Rather than keep guessing why the two
-- structurally- different-but-equivalent approaches render differently, this mirrors
-- DM's approach exactly since that one is confirmed correct.
local function WrapCompensatedBody(parentFrame, topOffset)
    local contentPad = EllesmereUI.CONTENT_PAD or 45
    local PAD = 20 -- matches PABMP_BuildPage's own detail-pane inset
    local padDiff = contentPad - PAD
    local visibleW = parentFrame:GetWidth()

    local scroll = CreateFrame("ScrollFrame", nil, parentFrame)
    scroll:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", -padDiff, topOffset or 0)
    scroll:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", padDiff, 0)
    scroll:SetFrameLevel(parentFrame:GetFrameLevel() + 1)
    scroll:SetClipsChildren(true)

    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(visibleW + padDiff * 2, 10) -- finalized by FinalizeCompensatedBody
    body._showRowDivider = true
    scroll:SetScrollChild(body)
    body._pabUpdateThumb = AttachEditorScroll(scroll, body, nil, padDiff + 2)

    -- Every WrapCompensatedBody call in this file immediately follows a
    -- PAB_BuildPreviewBox call on the same `parentFrame` (see the four BuildXDetail
    -- functions below) -- registering here, instead of at each call site, keeps the
    -- preview's live-resize wiring in one place. Reanchors this scroll frame's top edge
    -- whenever PAB_MaybeRefreshPreview resizes the preview box above it (Icons Per
    -- Row/Max Rows/Max Total/Icon Size/ Row Spacing change), so the settings area below
    -- never overlaps a grown box or leaves a stale gap under a shrunk one -- and
    -- refreshes the scrollbar thumb/track right after, since MaxScroll()/UpdateThumb
    -- read scroll:GetHeight() live and would otherwise stay stale (wrong thumb size, or
    -- a track that should now show/hide) until the next scroll interaction. Registered
    -- last (after body._pabUpdateThumb exists) so the closure can call it.
    if ns.PAB_SetPreviewResizeHandler then
        ns.PAB_SetPreviewResizeHandler(function(newTopOffset)
            scroll:ClearAllPoints()
            scroll:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", -padDiff, newTopOffset)
            scroll:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", padDiff, 0)
            if body._pabUpdateThumb then body._pabUpdateThumb() end
        end)
    end

    return body
end

-- Sizes the scroll child to its real content height and refreshes the scrollbar's
-- thumb/track visibility. Call once, after all of a detail pane's fields have been
-- built into `body` and the final sy/by accumulator value is known.
local function FinalizeCompensatedBody(body, sy)
    body:SetHeight(max(10, math.abs(sy) + 20))
    if body._pabUpdateThumb then body._pabUpdateThumb() end
end

-- Settings-section header (Raid Frames Buff Manager parity): accent-colored title with
-- the gray parenthesized subtitle inline to its right, rendered INSIDE the compensated
-- settings body directly above the first section (ASSIGNED BUFFS/DEBUFFS, or CORE where
-- no assigned section exists). Bar renames go through EllesmereUI:RefreshPage(true),
-- which rebuilds this pane, so a plain SetText at build time is already live. Takes and
-- returns the body's running y like every section builder.
local function BuildBarTitle(frame, fontPath, name, subtitle, y)
    local pad = EllesmereUI.CONTENT_PAD or 45
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 18, "")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, y - 11)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    local ac = EllesmereUI.ELLESMERE_GREEN
    if ac then title:SetTextColor(ac.r, ac.g, ac.b)
    else title:SetTextColor(0.05, 0.82, 0.62) end
    title:SetText(name)
    local sub = frame:CreateFontString(nil, "OVERLAY")
    sub:SetFont(fontPath, 13, "")
    sub:SetPoint("LEFT", title, "RIGHT", 4, 0)
    sub:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    sub:SetTextColor(0.75, 0.75, 0.75, 0.65)
    sub:SetText("(" .. (subtitle or "") .. ")")
    return y - 11 - 18 - 5
end

local function BuildDefaultBarDetail(frame, fontPath, isBuff)
    local W = EllesmereUI.Widgets
    if not W then return end

    local s = ns.db and ns.db.profile and ns.db.profile.playerAuraBars
    if not s then return end
    -- Defensive: the lane split + enable migration normally run in CreateBars,
    -- but make the page unable to write pre-migration data even if it is ever
    -- reachable without them.
    if ns.PAB_EnsureBarEnable then ns.PAB_EnsureBarEnable(s) end
    local cfg = isBuff and ns.PAB_DefaultBuffsCfg(s) or ns.PAB_DefaultDebuffsCfg(s)

    local function ApplyBar()
        if ns.PAB_Restyle then ns.PAB_Restyle() end
        if ns.PAB_ApplyLiveConfig then ns.PAB_ApplyLiveConfig(isBuff) end
    end

    local scrollTop = 0
    if ns.PAB_BuildPreviewBox then
        scrollTop = ns.PAB_BuildPreviewBox(frame, fontPath, 0, isBuff and "buff" or "debuff", "default", cfg)
    end
    local body = WrapCompensatedBody(frame, scrollTop)
    local sy = 0
    sy = BuildBarTitle(body, fontPath,
        isBuff and DefaultBuffBarName(cfg) or L("Debuffs"),
        L("Built-in bar. Cannot be deleted"), sy)

    if isBuff then
        sy = BuildAssignedBuffsFields(body, fontPath, sy, cfg, ApplyBar, true)
    else
        sy = BuildAssignedDebuffsFields(body, fontPath, sy, cfg, ApplyBar)
    end
    sy = BuildCoreFields(body, fontPath, sy, cfg, ApplyBar, isBuff)
    sy = BuildDisplayFields(body, fontPath, sy, cfg, ApplyBar, isBuff)
    if not isBuff then
        sy = BuildDispelColorFields(body, fontPath, sy, cfg, ApplyBar)
        sy = BuildFxEffects(body, sy, cfg, ApplyBar)
    end
    FinalizeCompensatedBody(body, sy)
end
-------------------------------------------------------------------------------
--  Shared tile widget (verbatim pattern from EUI_RaidFrames_ManagerPages.lua
--  BuildTile, trimmed to the fields this page actually uses)
-------------------------------------------------------------------------------

-- opts.inheritedTooltip marks the INHERITED variant (a group bucket's bar
-- shown on a concrete spec view): blue identity tint on title/subtitle, an
-- always-on blue edge strip, hover tooltip. Callers pass no onDelete/
-- onRename and wire onToggle to the per-spec disable.
local INH_R, INH_G, INH_B = 0.55, 0.72, 1
local function BuildTile(parentFrame, y, opts)
    local fontPath = opts.fontPath
    local tile = CreateFrame("Button", nil, parentFrame)
    tile:SetSize(opts.width, TILE_H)
    tile:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, y)
    tile:SetFrameLevel(parentFrame:GetFrameLevel() + 1)

    local bg = tile:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, opts.selected and 0.06 or 0)

    if opts.selected then
        local accent = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        accent:SetSize(2, TILE_H)
        accent:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        if opts.inheritedTooltip then
            accent:SetColorTexture(INH_R, INH_G, INH_B, 1)
        else
            local ac = EllesmereUI.ELLESMERE_GREEN
            if ac then accent:SetColorTexture(ac.r, ac.g, ac.b, 1)
            else accent:SetColorTexture(0.05, 0.82, 0.62, 1) end
        end
    elseif opts.inheritedTooltip then
        local edge = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        edge:SetSize(2, TILE_H)
        edge:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        edge:SetColorTexture(INH_R, INH_G, INH_B, 0.45)
    end

    local textRight = opts.showToggle and -52 or -16

    local titleFS = tile:CreateFontString(nil, "OVERLAY")
    titleFS:SetFont(fontPath, 13, "")
    titleFS:SetPoint("TOPLEFT", tile, "TOPLEFT", 12, -10)
    titleFS:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
    titleFS:SetJustifyH("LEFT")
    titleFS:SetWordWrap(false)
    titleFS:SetText(opts.title or "")
    if opts.inheritedTooltip then
        titleFS:SetTextColor(INH_R, INH_G, INH_B)
    else
        titleFS:SetTextColor(1, 1, 1)
    end

    if opts.subtitle or opts.subtitleFn then
        local sub = tile:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontPath, 11, "")
        sub:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -4)
        sub:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)
        sub:SetText(opts.subtitleFn and opts.subtitleFn() or opts.subtitle)
        if opts.inheritedTooltip then
            sub:SetTextColor(INH_R, INH_G, INH_B, 0.55)
        else
            sub:SetTextColor(0.4, 0.4, 0.4)
        end
        -- subtitleFn (vs. a static subtitle string): re-read on every lightweight
        -- RefreshPage() pass, e.g. after a Filters/Extra Spells checkbox toggle in
        -- the detail pane -- those call apply() + RefreshPage() (non-force) rather
        -- than a full page rebuild, since a full rebuild would close the open
        -- checkbox dropdown mid multi-select. Without this, the sidebar tile's
        -- subtitle would only update on the next full page rebuild (bar select,
        -- add, delete, ...), not live.
        if opts.subtitleFn then
            EllesmereUI.RegisterWidgetRefresh(function() sub:SetText(opts.subtitleFn()) end)
        end
    end

    tile:SetScript("OnEnter", function()
        if not opts.selected then bg:SetColorTexture(1, 1, 1, 0.04) end
        if opts.inheritedTooltip then
            EllesmereUI.ShowWidgetTooltip(tile, opts.inheritedTooltip)
        end
    end)
    tile:SetScript("OnLeave", function()
        bg:SetColorTexture(1, 1, 1, opts.selected and 0.06 or 0)
        if opts.inheritedTooltip then
            EllesmereUI.HideWidgetTooltip()
        end
    end)
    -- Right-click routes to opts.onContext (the "Add To" menu) when the
    -- caller provides it; tiles without it ignore right-clicks.
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            if opts.onContext then opts.onContext(tile) end
            return
        end
        if opts.onSelect then opts.onSelect() end
    end)

    if opts.showToggle then
        local toggleH = 16
        local toggleBtn = CreateFrame("Button", nil, tile)
        toggleBtn:SetSize(32, toggleH)
        toggleBtn:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -8)
        toggleBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        -- Inherited rows: the pill is the per-spec CONTROL and stays
        -- full-brightness even when the row dims (opts.dimmed) or wears the
        -- inherited tint -- SetAlpha on the tile inherits to children.
        if opts.inheritedTooltip and toggleBtn.SetIgnoreParentAlpha then
            toggleBtn:SetIgnoreParentAlpha(true)
        end
        local toggleBg = toggleBtn:CreateTexture(nil, "BACKGROUND")
        toggleBg:SetAllPoints()
        local toggleKnob = toggleBtn:CreateTexture(nil, "ARTWORK")
        toggleKnob:SetSize(toggleH - 4, toggleH - 4)
        local function UpdateToggleVisual()
            toggleKnob:ClearAllPoints()
            if opts.enabled then
                local acr, acg, acb = 0.05, 0.82, 0.62
                if EllesmereUI.ResolveActiveAccent then
                    acr, acg, acb = EllesmereUI.ResolveActiveAccent()
                end
                toggleBg:SetColorTexture(acr, acg, acb, 1)
                toggleKnob:SetPoint("RIGHT", toggleBtn, "RIGHT", -2, 0)
                toggleKnob:SetColorTexture(1, 1, 1, 1)
            else
                toggleBg:SetColorTexture(0.25, 0.25, 0.25, 1)
                toggleKnob:SetPoint("LEFT", toggleBtn, "LEFT", 2, 0)
                toggleKnob:SetColorTexture(0.5, 0.5, 0.5, 1)
            end
        end
        UpdateToggleVisual()
        toggleBtn:SetScript("OnClick", function()
            if opts.onToggle then opts.onToggle(not opts.enabled) end
        end)
    end

    local delBtn
    if opts.onDelete then
        delBtn = CreateFrame("Button", nil, tile)
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        delBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local delTex = delBtn:CreateTexture(nil, "OVERLAY")
        delTex:SetAllPoints()
        delTex:SetAtlas("common-icon-delete")
        delTex:SetDesaturated(true)
        delTex:SetVertexColor(0.75, 0.75, 0.75)
        delBtn:SetAlpha(0.5)
        delBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
        delBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
        delBtn:SetScript("OnClick", function() opts.onDelete() end)
    end

    -- Rename icon, left of the delete icon -- same eui-edit.png pencil the
    -- Filter Editor sidebar uses for its own rename affordance
    -- (PABMP_ShowFilterEditor), so renaming reads consistently across the
    -- whole page instead of only being reachable from the Name field.
    if opts.onRename then
        local editBtn = CreateFrame("Button", nil, tile)
        editBtn:SetSize(14, 14)
        if delBtn then
            editBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
        else
            editBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        end
        editBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local editTex = editBtn:CreateTexture(nil, "OVERLAY")
        editTex:SetAllPoints()
        editTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-edit.png")
        editBtn:SetAlpha(0.5)
        editBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
        editBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
        editBtn:SetScript("OnClick", function() opts.onRename() end)
    end

    local sep = tile:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.04)

    -- Dimmed rows (inherited tiles whose GROUP disabled the entry): the
    -- whole tile fades; the pill stays the per-spec layer's own state.
    if opts.dimmed then tile:SetAlpha(0.55) end

    return TILE_H
end

-- Sidebar "Add New" button (Raid Frames Buff Manager parity: solid green
-- accent button, 60% of the sidebar width, centered; background brightens
-- from 0.8 to full alpha on hover).
local function AddNewButton(parentFrame, y, width, label, onClick)
    local btnW = floor(width * 0.6)
    local addBtn = CreateFrame("Button", nil, parentFrame)
    addBtn:SetSize(btnW, 30)
    addBtn:SetPoint("TOP", parentFrame, "TOPLEFT", floor(width / 2), y - 10)
    addBtn:SetFrameLevel(parentFrame:GetFrameLevel() + 1)
    local accentColor = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
    local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
    addBg:SetAllPoints()
    addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    local lbl = addBtn:CreateFontString(nil, "OVERLAY")
    -- Drop shadow via the shadow FontObject, primed BEFORE SetFont
    -- (SetShadowOffset alone does not render). Module font, same as the
    -- sibling managers' Add New labels.
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, true) end
    lbl:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF", 12, "")
    lbl:SetTextColor(1, 1, 1)
    lbl:SetPoint("CENTER")
    lbl:SetText(label)
    addBtn:SetScript("OnEnter", function()
        addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
    end)
    addBtn:SetScript("OnLeave", function()
        addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    end)
    addBtn:SetScript("OnClick", onClick)
    return 50
end

-------------------------------------------------------------------------------
--  Custom Buff Bar detail pane
--  Shares BuildAssignedBuffsFields/BuildCoreFields/BuildDisplayFields with
--  the default Buffs bar -- same cfg shape (filters/spells), same fields.
-------------------------------------------------------------------------------

local function Apply(isBuff, barId)
    if isBuff then
        if ns.PAB_ReloadCustomBuffBar then ns.PAB_ReloadCustomBuffBar(barId) end
    else
        if ns.PAB_ReloadCustomDebuffBar then ns.PAB_ReloadCustomDebuffBar(barId) end
    end
end

-- Title bar: bar.name (falls back to the placeholder used at creation) +
-- a static subtitle, same TOPLEFT title/BOTTOMLEFT desc metrics as
-- BuildDefaultBarDetail's "Buffs"/"Built-in bar. Cannot be deleted."
-- header, so both default and custom bar detail panes look consistent.
-- Naming itself is handled exclusively through the sidebar now -- the
local function BuildBuffBarDetail(frame, fontPath, bar)
    local W = EllesmereUI.Widgets
    if not W then return end
    -- Defensive lane split + enable migration, same as BuildDefaultBarDetail.
    local sPAB = ns.db and ns.db.profile and ns.db.profile.playerAuraBars
    if sPAB and ns.PAB_EnsureBarEnable then ns.PAB_EnsureBarEnable(sPAB) end
    local function ApplyBar() Apply(true, bar.id) end

    local scrollTop = 0
    if ns.PAB_BuildPreviewBox then
        scrollTop = ns.PAB_BuildPreviewBox(frame, fontPath, 0, "buff", bar.id, bar)
    end
    local body = WrapCompensatedBody(frame, scrollTop)
    local by = 0
    by = BuildBarTitle(body, fontPath, L(bar.name or "Buff Bar"), L("Custom buff bar"), by)
    by = BuildAssignedBuffsFields(body, fontPath, by, bar, ApplyBar)
    by = BuildCoreFields(body, fontPath, by, bar, ApplyBar, true)
    by = BuildDisplayFields(body, fontPath, by, bar, ApplyBar, true)
    FinalizeCompensatedBody(body, by)
end

-------------------------------------------------------------------------------
--  Custom Debuff Bar detail pane -- category/class-token based, no SpellID
-- popup (by design: debuffs stay category-based, same as
--  RaidFrames).
-------------------------------------------------------------------------------

local function BuildDebuffBarDetail(frame, fontPath, bar)
    local W = EllesmereUI.Widgets
    if not W then return end
    -- Defensive lane split + enable migration, same as BuildDefaultBarDetail.
    local sPAB = ns.db and ns.db.profile and ns.db.profile.playerAuraBars
    if sPAB and ns.PAB_EnsureBarEnable then ns.PAB_EnsureBarEnable(sPAB) end
    local function ApplyBar() Apply(false, bar.id) end

    local scrollTop = 0
    if ns.PAB_BuildPreviewBox then
        scrollTop = ns.PAB_BuildPreviewBox(frame, fontPath, 0, "debuff", bar.id, bar)
    end
    local body = WrapCompensatedBody(frame, scrollTop)
    local by = 0
    by = BuildBarTitle(body, fontPath, L(bar.name or "Debuff Bar"), L("Custom debuff bar"), by)
    by = BuildAssignedDebuffsFields(body, fontPath, by, bar, ApplyBar)
    by = BuildCoreFields(body, fontPath, by, bar, ApplyBar, false)
    by = BuildDisplayFields(body, fontPath, by, bar, ApplyBar, false)
    by = BuildDispelColorFields(body, fontPath, by, bar, ApplyBar)
    by = BuildFxEffects(body, by, bar, ApplyBar)
    FinalizeCompensatedBody(body, by)
end

-------------------------------------------------------------------------------
--  Filter Editor modal -- 1:1 structural port of ns.BMP_ShowFilterEditor
--  (EUI_RaidFrames_ManagerPages.lua): same dimmer+popup+sidebar+detail
--  shape, same smooth-scroll+thumb, same icon-based sidebar rename/delete,
--  same Search Spells dropdown + Add Spell ID button layout, same class-
--  grouped checkbox-style spell list, same Selected/Presets Extra Spells
--  grouping. Two things differ from a byte-identical port:
--    * ns.PAB_AllPresetSpells() (the universe both Search Spells and Extra
--      Spells' Presets group draw from) is built from BM2_FILTER_SEED, not
--      from a live BM2_DEFAULT_FILTER_SPELLS reference -- same content,
--      just PAB's own copy (see that seed table's doc comment for why).
--    * No preset/custom distinction at the SPELL level -- filters
--      themselves ARE protected once imported (f.preset, see PAB_Filters'
--      doc comment), but every spell row within a filter stays equally
--      editable, unlike BM2 which only shows the delete-X on "custom"
--      (non-curated) spells.
--    * Own-only tracking (ind.ownFilters/ownExtras) -- explicitly out of
--      scope for this pass, matches PAB_ResolveSpells' doc comment.
--  Class grouping/coloring uses ns.PAB_SPELL_CLASS_HINTS (display-only,
--  extracted from the same BM2 source data as the seed filters) --
--  spells with no hint land in "Custom", exactly like BM2's own spells
--  with no curated class land in its Custom group.
-------------------------------------------------------------------------------

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID",
    "DEMONHUNTER", "EVOKER" }

local function PopupButton(parent, w, h, label, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", 0, 0, 0, 0.5); bg:SetAllPoints()
    local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25)
    local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
    lbl:SetAlpha(0.6)
    lbl:SetPoint("CENTER")
    lbl:SetText(L(label))
    local ar, ag, ab = 1, 0.82, 0.30
    if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
    btn:SetScript("OnEnter", function()
        lbl:SetAlpha(0.9)
        if brd and brd.SetColor then brd:SetColor(ar, ag, ab, 0.6) end
    end)
    btn:SetScript("OnLeave", function()
        lbl:SetAlpha(0.6)
        if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.25) end
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- Standard smooth scroll + thin custom scrollbar (verbatim port of AttachEditorScroll
-- from EUI_RaidFrames_ManagerPages.lua). Track shows only on overflow. Returns
-- UpdateThumb and SetScrollTo(v). rightInset (optional, default 2): distance from
-- `scroll`'s OWN right edge to the track. Only WrapCompensatedBody's call needs a
-- bigger value here -- since its `scroll` extends padDiff (~25px) past the pane's true
-- visible right edge (mirrors RaidFrames' settingsScroll), so the default 2 would land
-- the track deep inside the sidebar instead of near the visible edge. The other two
-- callers (Filter Editor's plain, unshifted scrolls) keep the default.
AttachEditorScroll = function(scroll, child, onScroll, rightInset)
    rightInset = rightInset or 2
    local SBAR_W = 4
    local track = CreateFrame("Frame", nil, scroll)
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -rightInset, -2)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -rightInset, 2)
    track:SetWidth(SBAR_W)
    track:SetFrameLevel(scroll:GetFrameLevel() + 5)
    do local tx = track:CreateTexture(nil, "BACKGROUND"); tx:SetAllPoints(); tx:SetColorTexture(1, 1, 1, 0.05) end
    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(SBAR_W); thumb:SetHeight(30)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:EnableMouse(true)
    do local tx = thumb:CreateTexture(nil, "ARTWORK"); tx:SetAllPoints(); tx:SetColorTexture(1, 1, 1, 0.22) end
    track:Hide()

    local function MaxScroll() return max(0, child:GetHeight() - scroll:GetHeight()) end
    local function UpdateThumb()
        local ms = MaxScroll()
        if ms <= 0 then track:Hide(); return end
        track:Show()
        local trackH = track:GetHeight()
        local visH = scroll:GetHeight()
        local thumbH = max(20, trackH * (visH / (visH + ms)))
        thumb:SetHeight(thumbH)
        local ratio = (scroll:GetVerticalScroll() or 0) / ms
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(ratio * (trackH - thumbH)))
    end

    local SCROLL_STEP, SMOOTH_SPEED = 60, 12
    local target = 0
    local smooth = CreateFrame("Frame", nil, scroll)
    smooth:Hide()
    smooth:SetScript("OnUpdate", function(_, elapsed)
        local cur = scroll:GetVerticalScroll()
        local ms = MaxScroll()
        target = max(0, math.min(ms, target))
        local diff = target - cur
        if math.abs(diff) < 0.3 then
            scroll:SetVerticalScroll(target); UpdateThumb(); smooth:Hide()
            if onScroll then onScroll(target) end
            return
        end
        local nv = max(0, math.min(ms, cur + diff * math.min(1, SMOOTH_SPEED * elapsed)))
        scroll:SetVerticalScroll(nv); UpdateThumb()
        if onScroll then onScroll(nv) end
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        if MaxScroll() <= 0 then return end
        local base = smooth:IsShown() and target or scroll:GetVerticalScroll()
        target = max(0, math.min(MaxScroll(), base - delta * SCROLL_STEP))
        smooth:Show()
    end)
    thumb:SetScript("OnMouseDown", function()
        smooth:Hide()
        local _, cy0 = GetCursorPosition()
        local startY = cy0 / scroll:GetEffectiveScale()
        local startScroll = scroll:GetVerticalScroll()
        thumb:SetScript("OnUpdate", function(self2)
            if not IsMouseButtonDown("LeftButton") then self2:SetScript("OnUpdate", nil); return end
            local ms = MaxScroll()
            local travel = track:GetHeight() - thumb:GetHeight()
            if travel <= 0 then return end
            local _, cy = GetCursorPosition(); cy = cy / scroll:GetEffectiveScale()
            local nv = max(0, math.min(ms, startScroll + ((startY - cy) / travel) * ms))
            target = nv
            scroll:SetVerticalScroll(nv); UpdateThumb()
            if onScroll then onScroll(nv) end
        end)
    end)

    local function SetScrollTo(v)
        local ms = MaxScroll()
        if v > ms then v = ms end
        if v < 0 then v = 0 end
        target = v
        scroll:SetVerticalScroll(v)
        UpdateThumb()
        if onScroll then onScroll(v) end
    end
    return UpdateThumb, SetScrollTo
end

function ns.PABMP_ShowFilterEditor()
    if ns._pabFilterEditor then ns._pabFilterEditor:Hide(); ns._pabFilterEditor = nil end
    local filters = SortFiltersCanonical((ns.PAB_Filters and ns.PAB_Filters()) or {})
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
    local ar, ag, ab = 1, 0.82, 0.30
    if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
    local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
    local MEDIA_FE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"

    local POPUP_W, POPUP_H, SIDE_W = 620, 520, 180

    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScript("OnMouseDown", function() dimmer:Hide(); ns._pabFilterEditor = nil end)
    local dimTex = EllesmereUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25); dimTex:SetAllPoints()
    ns._pabFilterEditor = dimmer

    local popup = CreateFrame("Frame", nil, dimmer)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    popup:EnableMouse(true)
    local popBg = EllesmereUI.SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 1); popBg:SetAllPoints()
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15)
    if EllesmereUI.GetPopupScale then popup:SetScale(EllesmereUI.GetPopupScale()) end

    local title = EllesmereUI.MakeFont(popup, 16, "", 1, 1, 1)
    title:SetPoint("TOP", popup, "TOP", 0, -18)
    title:SetText(L("Edit Filters"))

    do
        local close = CreateFrame("Button", nil, popup)
        close:SetSize(19, 19)
        close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -13, -8)
        close:SetFrameLevel(popup:GetFrameLevel() + 5)
        local closeIcon = close:CreateTexture(nil, "ARTWORK")
        closeIcon:SetAllPoints()
        closeIcon:SetTexture(MEDIA_FE .. "eui-close.png")
        closeIcon:SetAlpha(0.40)
        closeIcon:SetSnapToPixelGrid(false)
        closeIcon:SetTexelSnappingBias(0)
        close:SetScript("OnEnter", function() closeIcon:SetAlpha(0.50) end)
        close:SetScript("OnLeave", function() closeIcon:SetAlpha(0.40) end)
        close:SetScript("OnClick", function() dimmer:Hide(); ns._pabFilterEditor = nil end)
    end

    if pabFilterSel then
        local ok = false
        for i = 1, #filters do if filters[i].id == pabFilterSel then ok = true end end
        if not ok then pabFilterSel = nil end
    end
    if not pabFilterSel and filters[1] then pabFilterSel = filters[1].id end

    local function Rebuild() ns.PABMP_ShowFilterEditor() end
    local function ApplyAll()
        if ns.PAB_ApplyLiveConfig then ns.PAB_ApplyLiveConfig(true) end
        -- Every custom bar, editing-spec buckets included: a filter edit
        -- changes any bar assigned to it, whichever bucket owns the bar.
        if ns.PAB_ReloadAllCustomBars then ns.PAB_ReloadAllCustomBars() end
    end
    local function EditorInput(opts)
        EllesmereUI:ShowInputPopup(opts)
        local d = _G.EUIInputDimmer
        if d and ns._pabFilterEditor then
            d:SetFrameLevel(popup:GetFrameLevel() + 40)
            local p = _G.EUIInputPopup
            if p then p:SetFrameLevel(d:GetFrameLevel() + 10) end
        end
    end

    -- RIGHT: filter list.
    local side = CreateFrame("Frame", nil, popup)
    side:SetWidth(SIDE_W)
    side:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, -44)
    side:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 0)
    side:SetFrameLevel(popup:GetFrameLevel() + 1)
    local sideBg = EllesmereUI.SolidTex(side, "BACKGROUND", 0, 0, 0, 0.35); sideBg:SetAllPoints()
    EllesmereUI.MakeBorder(side, 1, 1, 1, 0.10)

    local sideScroll = CreateFrame("ScrollFrame", nil, side)
    sideScroll:SetPoint("TOPLEFT", side, "TOPLEFT", 1, -1)
    sideScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -1, 1)
    sideScroll:SetFrameLevel(side:GetFrameLevel() + 1)
    local sideChild = CreateFrame("Frame", nil, sideScroll)
    sideChild:SetWidth(SIDE_W - 2)
    sideScroll:SetScrollChild(sideChild)

    local fy = -4
    for i = 1, #filters do
        local f = filters[i]
        local isSel = (pabFilterSel == f.id)
        local frow = CreateFrame("Button", nil, sideChild)
        frow:SetHeight(26)
        frow:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 0, fy)
        frow:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", 0, fy)
        frow:SetFrameLevel(sideChild:GetFrameLevel() + 1)
        local rbg = frow:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints(); rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0)
        local rl = EllesmereUI.MakeFont(frow, 12, nil, 1, 1, 1)
        rl:SetAlpha(isSel and 0.95 or 0.6)
        rl:SetPoint("LEFT", frow, "LEFT", 10, 0)
        rl:SetPoint("RIGHT", frow, "RIGHT", f.preset and -8 or -42, 0)
        rl:SetJustifyH("LEFT"); rl:SetWordWrap(false)
        rl:SetText(L(f.name))
        if isSel then
            local accent = frow:CreateTexture(nil, "ARTWORK", nil, 2)
            accent:SetSize(2, 26)
            accent:SetPoint("TOPLEFT", frow, "TOPLEFT", 0, 0)
            accent:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
        end
        frow:SetScript("OnEnter", function() if not isSel then rbg:SetColorTexture(1, 1, 1, 0.04) end end)
        frow:SetScript("OnLeave", function() rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0) end)
        frow:SetScript("OnClick", function()
            pabFilterSel = f.id
            pabFilterScrollPos = 0
            Rebuild()
        end)

        -- Imported Buff Manager presets (f.preset = true) are protected --
        -- not renameable/deletable, matching BM2's own `if not f.preset`
        -- guard exactly. User-created filters keep both icons.
        if not f.preset then
            local del = CreateFrame("Button", nil, frow)
            del:SetSize(14, 14)
            del:SetPoint("RIGHT", frow, "RIGHT", -6, 0)
            del:SetFrameLevel(frow:GetFrameLevel() + 1)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then dx:SetSnapToPixelGrid(false); dx:SetTexelSnappingBias(0) end
            dx:SetTexture(MEDIA_FE .. "eui-close.png")
            del:SetScript("OnEnter", function(self) self:SetAlpha(0.9); EllesmereUI.ShowWidgetTooltip(self, L("Delete")) end)
            del:SetScript("OnLeave", function(self) self:SetAlpha(0.5); EllesmereUI.HideWidgetTooltip() end)
            del:SetScript("OnClick", function()
                EllesmereUI:ShowConfirmPopup({
                    title = L("Delete Filter"),
                    message = L("Delete this filter? It is removed from every bar using it."),
                    confirmText = L("Delete"), cancelText = L("Cancel"),
                    onConfirm = function()
                        ns.PAB_DeleteFilter(f.id)
                        ApplyAll()
                        Rebuild()
                    end,
                })
            end)

            local edit = CreateFrame("Button", nil, frow)
            edit:SetSize(14, 14)
            edit:SetPoint("RIGHT", del, "LEFT", -4, 0)
            edit:SetFrameLevel(frow:GetFrameLevel() + 1)
            edit:SetAlpha(0.5)
            local ex = edit:CreateTexture(nil, "OVERLAY")
            ex:SetAllPoints()
            if ex.SetSnapToPixelGrid then ex:SetSnapToPixelGrid(false); ex:SetTexelSnappingBias(0) end
            ex:SetTexture(MEDIA_FE .. "eui-edit.png")
            edit:SetScript("OnEnter", function(self) self:SetAlpha(0.9); EllesmereUI.ShowWidgetTooltip(self, L("Edit")) end)
            edit:SetScript("OnLeave", function(self) self:SetAlpha(0.5); EllesmereUI.HideWidgetTooltip() end)
            edit:SetScript("OnClick", function()
                EditorInput({
                    title = L("Rename Filter"), placeholder = L(f.name),
                    confirmText = L("Rename"), cancelText = L("Cancel"),
                    onConfirm = function(text) ns.PAB_RenameFilter(f.id, text); Rebuild() end,
                })
            end)
        end
        fy = fy - 27
    end
    local addFilterBtn = PopupButton(sideChild, SIDE_W - 16, 26, "Add Filter", function()
        EditorInput({
            title = L("Add Filter"), message = L("Name the new filter."),
            confirmText = L("Add"), cancelText = L("Cancel"),
            onConfirm = function(text)
                local f = ns.PAB_AddFilter((text and text ~= "" and text) or L("New Filter"))
                if f then pabFilterSel = f.id end
                Rebuild()
            end,
        })
    end)
    addFilterBtn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 8, fy - 8)
    local sideBottom = fy - 8 - 26
    -- One-time copy of the Raid Frames Buff Manager filter library into this
    -- registry (same-named filters replaced, missing ones created; see
    -- PAB_CopyBM2FiltersIn). Hidden while that module is disabled.
    if EllesmereUI._BM2FilterBridge then
        local copyBtn = PopupButton(sideChild, SIDE_W - 16, 26, L("Copy Raid Frames Filters"), function()
            EllesmereUI:ShowConfirmPopup({
                title = L("Copy Raid Frames Filters"),
                message = L("One-time copy of the Raid Frames Buff Manager filters into these filters. Same-named filters are OVERWRITTEN; the two lists stay separate afterwards."),
                confirmText = L("Copy"),
                cancelText = L("Cancel"),
                typeToConfirm = "Confirm",
                onConfirm = function()
                    if ns.PAB_CopyBM2FiltersIn and ns.PAB_CopyBM2FiltersIn() then
                        ApplyAll()
                        Rebuild()
                    end
                end,
            })
        end)
        copyBtn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 8, sideBottom - 6)
        sideBottom = sideBottom - 6 - 26
    end
    sideChild:SetHeight(math.abs(sideBottom) + 8)
    local updSideThumb = AttachEditorScroll(sideScroll, sideChild)
    updSideThumb()

    -- LEFT: selected filter detail.
    local sel
    for i = 1, #filters do if filters[i].id == pabFilterSel then sel = filters[i] end end
    if not sel then return end

    local left = CreateFrame("Frame", nil, popup)
    left:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -44)
    left:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -(SIDE_W + 12), 12)
    left:SetFrameLevel(popup:GetFrameLevel() + 1)

    local nm = EllesmereUI.MakeFont(left, 13, nil, 1, 1, 1)
    nm:SetAlpha(0.9)
    nm:SetPoint("TOPLEFT", left, "TOPLEFT", 2, -2)
    nm:SetText(L(sel.name))
    if not sel.preset then
        local ren = CreateFrame("Button", nil, left)
        ren:SetSize(54, 16)
        ren:SetPoint("LEFT", nm, "RIGHT", 10, 0)
        ren:SetFrameLevel(left:GetFrameLevel() + 2)
        local rl = EllesmereUI.MakeFont(ren, 11, nil, ar, ag, ab)
        rl:SetAlpha(0.9)
        rl:SetPoint("LEFT")
        rl:SetText(L("Rename"))
        ren:SetScript("OnEnter", function() rl:SetAlpha(1) end)
        ren:SetScript("OnLeave", function() rl:SetAlpha(0.9) end)
        ren:SetScript("OnClick", function()
            EditorInput({
                title = L("Rename Filter"), placeholder = L(sel.name),
                confirmText = L("Rename"), cancelText = L("Cancel"),
                onConfirm = function(text) ns.PAB_RenameFilter(sel.id, text); Rebuild() end,
            })
        end)
    end

    -- Search Spells: same curated (deduped) universe as the Extra Spells
    -- dropdown, matching BM2's own search exactly (BM2's comment:
    -- "identical list to the Extra Spells dropdown").
    local searchDD = EllesmereUI.BuildVisOptsCBDropdown(
        left, 170, left:GetFrameLevel() + 5,
        function()
            local universe = DedupedPresetSpellUniverse()
            local out = {}
            for i = 1, #universe do
                local id = universe[i]
                if sel.spells[id] == nil then
                    local nm2 = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                    out[#out + 1] = {
                        key = id, label = nm2 or tostring(id), noCheck = true,
                        icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id),
                    }
                end
            end
            table.sort(out, function(a, b) return tostring(a.label or a.key) < tostring(b.label or b.key) end)
            return out
        end,
        function() return false end,
        function(k, v)
            if v and ns.PAB_AddSpellToFilter and ns.PAB_AddSpellToFilter(sel.id, k) then
                ApplyAll()
                Rebuild()
            end
        end,
        nil, 10, true)
    searchDD:ClearAllPoints()
    searchDD:SetPoint("TOPLEFT", left, "TOPLEFT", 2, -23)
    for _, r in ipairs({ searchDD:GetRegions() }) do
        if r.SetText and r.GetText then
            r:SetText(L("Search Spells"))
            break
        end
    end

    local addSpellBtn = PopupButton(left, 110, 24, "Add Spell ID", function()
        EditorInput({
            title = L("Add Spell ID"), message = L("Enter the spell ID to add to this filter."),
            confirmText = L("Add"), cancelText = L("Cancel"),
            onConfirm = function(text)
                local id = tonumber(text or "")
                if id and ns.PAB_AddSpellToFilter(sel.id, id) then
                    ApplyAll()
                    Rebuild()
                end
            end,
        })
    end)
    addSpellBtn:SetPoint("LEFT", searchDD, "RIGHT", 8, 0)

    -- Spell checkbox list: mirrors the checkbox-dropdown widget's visuals exactly (16px
    -- box, accent fill inset 2, hover wash), grouped by class (via
    -- PAB_SPELL_CLASS_HINTS) with a Custom group for anything without a hint.
    local scroll = CreateFrame("ScrollFrame", nil, left)
    scroll:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -58)
    scroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(POPUP_W - SIDE_W - 40)
    scroll:SetScrollChild(child)
    local _updSpellThumb, setSpellScroll = AttachEditorScroll(scroll, child,
        function(v) pabFilterScrollPos = v end)

    local function NameOf(id)
        return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or tostring(id)
    end

    -- Display-only dedup by name, same reasoning/pattern as DedupedPresetSpellUniverse:
    -- sel.spells legitimately contains both a primary spellID and its rank/talent
    -- `alts` as separate keys (BM2_ FILTER_SEED already flattens alts in -- see that
    -- table's own doc comment), which BM2's own checkbox list never shows as separate
    -- rows (it only iterates primary keys). Without this, curated filters like "Raid
    -- CDs" show the same buff (e.g. Rallying Cry) twice. First (lowest) spellID per
    -- name wins and keeps its row -- ids are visited in sorted order (pairs() has no
    -- defined order) so the winner is deterministic across rebuilds. ResolveSpells
    -- still unions every enabled id in sel.spells regardless of which one has a visible
    -- checkbox, so this changes nothing about which auras get tracked -- only which row
    -- the user toggles them from.
    local hints = ns.PAB_SPELL_CLASS_HINTS or {}
    local allIds = {}
    for id in pairs(sel.spells) do allIds[#allIds + 1] = id end
    table.sort(allIds)
    local byClass, customList = {}, {}
    local seenNames = {}
    for i = 1, #allIds do
        local id = allIds[i]
        local dedupKey = NameOf(id)
        if not seenNames[dedupKey] then
            seenNames[dedupKey] = true
            local cls = hints[id]
            if cls then
                byClass[cls] = byClass[cls] or {}
                table.insert(byClass[cls], id)
            else
                table.insert(customList, id)
            end
        end
    end
    local function ByName(a, b)
        local na, nb = NameOf(a), NameOf(b)
        if na == nb then return a < b end
        return na < nb
    end
    for _, list in pairs(byClass) do table.sort(list, ByName) end
    table.sort(customList, ByName)

    local cy = 0
    local function SpellRow(id, classColor)
        local srow = CreateFrame("Button", nil, child)
        srow:SetHeight(24)
        srow:SetPoint("TOPLEFT", child, "TOPLEFT", 2, cy)
        srow:SetPoint("TOPRIGHT", child, "TOPRIGHT", -2, cy)
        srow:SetFrameLevel(child:GetFrameLevel() + 1)
        local hl = srow:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)
        local box = CreateFrame("Frame", nil, srow)
        box:SetSize(16, 16)
        box:SetPoint("LEFT", srow, "LEFT", 6, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints(); boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
        local boxBrd = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6)
        local chk = box:CreateTexture(nil, "ARTWORK")
        chk:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
        chk:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        chk:SetColorTexture(eg.r, eg.g, eg.b, 1)
        local on = sel.spells[id] and true or false
        local ico = srow:CreateTexture(nil, "ARTWORK")
        ico:SetSize(22, 22)
        ico:SetPoint("LEFT", box, "RIGHT", 6, 0)
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        if tex then ico:SetTexture(tex) end
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        local lr, lg2, lb2 = 1, 1, 1
        if classColor then lr, lg2, lb2 = classColor.r, classColor.g, classColor.b end
        local lbl = EllesmereUI.MakeFont(srow, 13, nil, lr, lg2, lb2)
        lbl:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        lbl:SetPoint("RIGHT", srow, "RIGHT", -24, 0) -- every PAB row is deletable, always reserve the X's space
        lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        lbl:SetText(name or ("Spell " .. tostring(id)))
        local function UpdateRow()
            on = sel.spells[id] and true or false
            if on then
                chk:Show()
                if boxBrd and boxBrd.SetColor then boxBrd:SetColor(eg.r, eg.g, eg.b, 0.8) end
            else
                chk:Hide()
                if boxBrd and boxBrd.SetColor then boxBrd:SetColor(0.4, 0.4, 0.4, 0.6) end
            end
            lbl:SetAlpha(on and 0.9 or 0.45)
            ico:SetAlpha(on and 1 or 0.45)
            ico:SetDesaturated(not on)
        end
        UpdateRow()
        srow:SetScript("OnEnter", function() hl:SetColorTexture(1, 1, 1, 0.04) end)
        srow:SetScript("OnLeave", function() hl:SetColorTexture(1, 1, 1, 0) end)
        srow:SetScript("OnClick", function()
            ns.PAB_SetSpellState(sel.id, id, not on)
            ApplyAll()
            UpdateRow()
        end)
        local del = CreateFrame("Button", nil, srow)
        del:SetSize(14, 14)
        del:SetPoint("RIGHT", srow, "RIGHT", -6, 0)
        del:SetFrameLevel(srow:GetFrameLevel() + 1)
        del:SetAlpha(0.5)
        local dx = del:CreateTexture(nil, "OVERLAY")
        dx:SetAllPoints()
        if dx.SetSnapToPixelGrid then dx:SetSnapToPixelGrid(false); dx:SetTexelSnappingBias(0) end
        dx:SetTexture(MEDIA_FE .. "eui-close.png")
        del:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
        del:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
        del:SetScript("OnClick", function()
            ns.PAB_SetSpellState(sel.id, id, nil)
            ApplyAll()
            Rebuild()
        end)
        cy = cy - 29
    end
    local function GroupHeader(text)
        local hdr = EllesmereUI.MakeFont(child, 14, nil, 0.5, 0.5, 0.5)
        hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 2, cy - 10)
        hdr:SetText(text)
        local line = child:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", hdr, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", child, "RIGHT", -10, 0)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        cy = cy - 30
    end
    if #customList > 0 then
        GroupHeader(L("Custom"))
        for i = 1, #customList do SpellRow(customList[i]) end
    end
    for c = 1, #CLASS_ORDER do
        local cls = CLASS_ORDER[c]
        local list = byClass[cls]
        if list and #list > 0 then
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            local cname = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls] or cls
            GroupHeader(cc and ("|c" .. cc.colorStr .. cname .. "|r") or cname)
            for i = 1, #list do SpellRow(list[i], cc) end
        end
    end
    if cy == 0 then
        local empty = EllesmereUI.MakeFont(child, 12, nil, 1, 1, 1)
        empty:SetAlpha(0.4)
        empty:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -6)
        empty:SetText(L("No spells yet. Add spell IDs above."))
        cy = -30
    end
    child:SetHeight(math.abs(cy) + 10)

    setSpellScroll(pabFilterScrollPos or 0)
end

-------------------------------------------------------------------------------
--  "Add New" popup -- small Name-only popup shown below the Add Buff Bar /
--  Add Debuff Bar button, mirrors RaidFrames' DebuffManager "Add New"
--  popup chrome (dark fill + border, POPUP_PAD/ROW_H metrics, accent
--  Create button, auto-close on outside click, EUI_RaidFrames_ManagerPages
--  .lua ~line 2244) -- simplified to a single Name field since PAB custom
--  bars don't need a type/filter picker at creation time (everything else
--  is editable afterward in the detail pane, unlike DM's tiles). One
--  shared popup instance toggled/repurposed for both buff and debuff
--  creation via `kind`, same as DM's single ns._dmAddPopup.
-------------------------------------------------------------------------------

local pabAddPopup

local function ShowAddBarPopup(anchorBtn, kind, fontPath)
    if pabAddPopup and pabAddPopup:IsShown() and pabAddPopup._kind == kind then
        pabAddPopup:Hide()
        return
    end

    if not pabAddPopup then
        local POPUP_W, POPUP_PAD, ROW_H, LABEL_H, LBL_GAP, GAP = 220, 10, 30, 14, 4, 10
        local popup = CreateFrame("Frame", nil, UIParent)
        popup:SetFrameStrata("DIALOG")
        popup:SetFrameLevel(200)
        popup:SetSize(POPUP_W, POPUP_PAD + LABEL_H + LBL_GAP + ROW_H + GAP + ROW_H + POPUP_PAD)
        popup:EnableMouse(true)
        popup:SetClampedToScreen(true)

        local bg = popup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.2)

        -- Auto-close on outside click, same pattern as DM's Add New popup.
        popup:SetScript("OnShow", function(p2)
            p2:SetScript("OnUpdate", function(m)
                if not (m._anchorBtn and m._anchorBtn:IsMouseOver()) and not m:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                        m:Hide()
                    end
                end
            end)
        end)
        popup:SetScript("OnHide", function(p2)
            p2:SetScript("OnUpdate", nil)
            if p2._nameBox then p2._nameBox:SetText("") end
        end)

        local py = -POPUP_PAD
        local nmLbl = popup:CreateFontString(nil, "OVERLAY")
        nmLbl:SetFont(fontPath, 11, "")
        nmLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
        nmLbl:SetText(L("Name"))
        nmLbl:SetTextColor(1, 1, 1, 0.6)
        py = py - LABEL_H - LBL_GAP

        local ddW = POPUP_W - POPUP_PAD * 2
        local nameBox = CreateFrame("EditBox", nil, popup)
        nameBox:SetSize(ddW, ROW_H)
        nameBox:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
        nameBox:SetAutoFocus(true)
        nameBox:SetFont(fontPath, 12, "")
        nameBox:SetJustifyH("LEFT")
        nameBox:SetTextColor(1, 1, 1, 0.9)
        nameBox:SetTextInsets(10, 10, 0, 0)
        local nbBg = nameBox:CreateTexture(nil, "BACKGROUND")
        nbBg:SetAllPoints()
        nbBg:SetColorTexture(0, 0, 0, 0.5)
        EllesmereUI.MakeBorder(nameBox, 1, 1, 1, 0.2)
        popup._nameBox = nameBox
        py = py - ROW_H - GAP

        local accentColor = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local cBtn = CreateFrame("Button", nil, popup)
        cBtn:SetSize(ddW, ROW_H)
        cBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PAD, py)
        cBtn:SetFrameLevel(popup:GetFrameLevel() + 1)
        local cBg = cBtn:CreateTexture(nil, "BACKGROUND")
        cBg:SetAllPoints()
        cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
        local cTx = cBtn:CreateFontString(nil, "OVERLAY")
        cTx:SetPoint("CENTER")
        cTx:SetFont(fontPath, 12, "")
        cTx:SetText(L("Create"))
        cTx:SetTextColor(1, 1, 1)
        cBtn:SetScript("OnEnter", function() cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1) end)
        cBtn:SetScript("OnLeave", function() cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8) end)
        popup._createBtn = cBtn

        nameBox:SetScript("OnEnterPressed", function() cBtn:Click() end)
        nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); popup:Hide() end)

        pabAddPopup = popup
    end

    local popup = pabAddPopup
    popup._kind = kind
    popup._anchorBtn = anchorBtn
    popup._nameBox:SetText("")
    popup._createBtn:SetScript("OnClick", function()
        local text = popup._nameBox:GetText()
        local name = (text and text ~= "") and text or nil
        local bar
        -- New bars land in the EDITED editing-spec bucket ("allspecs" =
        -- the legacy arrays, today's behavior).
        if kind == "buff" then
            bar = ns.PAB_AddCustomBuffBar and ns.PAB_AddCustomBuffBar(name, pabSpecSel)
        else
            bar = ns.PAB_AddCustomDebuffBar and ns.PAB_AddCustomDebuffBar(name, pabSpecSel)
        end
        popup:Hide()
        if bar then
            pabSel = { kind = kind, id = bar.id }
            pabInhSel = nil
            Apply(kind == "buff", bar.id)
            EllesmereUI:RefreshPage(true)
        end
    end)

    popup:ClearAllPoints()
    local sc = anchorBtn:GetEffectiveScale() / UIParent:GetEffectiveScale()
    popup:SetScale(sc)
    popup:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -12)
    popup:Show()
    popup._nameBox:SetFocus()
end

-------------------------------------------------------------------------------
--  Page entry point
-------------------------------------------------------------------------------

function ns.PABMP_BuildPage(pageName, parent, yOffset)
    local scrollFrame = EllesmereUI._scrollFrame
    if not scrollFrame then return 0 end
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"

    -- Runs every time this page opens, not just when empty: creates any
    -- missing curated presets AND retroactively re-flags already-existing
    -- ones as protected (f.preset = true) -- needed once to fix filters
    -- imported before that flag existed, and keeps future seed-data
    -- changes in sync. Fully idempotent and cheap (name lookup over 10
    -- entries). Presets are no longer deletable via the UI, so there's no
    -- "silently reappears after deletion" concern any more either.
    if ns.PAB_ImportBM2Filters then
        ns.PAB_ImportBM2Filters()
    end

    local parentW = scrollFrame:GetWidth()
    local fullH = scrollFrame:GetHeight()
    local sidebarW = floor(parentW * 0.28) - 20
    local leftW = parentW - sidebarW

    local outerRoot = CreateFrame("Frame", nil, scrollFrame)
    outerRoot:SetAllPoints(scrollFrame)
    outerRoot:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    if ns._pabRoot then ns._pabRoot:Hide(); ns._pabRoot:SetParent(nil) end
    if EllesmereUI._pickMenu then EllesmereUI._pickMenu:Hide() end
    ns._pabRoot = outerRoot

    -- Editing-spec bucket sanity: stale/unknown keys reset to All Specs.
    if pabSpecSel ~= "allspecs" and not SPEC_GROUP_INFO[pabSpecSel]
        and not (type(pabSpecSel) == "string" and pabSpecSel:match("^spec%d")) then
        pabSpecSel = "allspecs"
    end
    local buffBars = ns.PAB_BucketBars and ns.PAB_BucketBars(true, pabSpecSel) or {}
    local debuffBars = ns.PAB_BucketBars and ns.PAB_BucketBars(false, pabSpecSel) or {}

    -- Group buckets this view inherits from (concrete "spec<ID>" views
    -- only): their bars lead each section as read-only tiles.
    local inhGroups = ns.PAB_InheritedGroupsFor and ns.PAB_InheritedGroupsFor(pabSpecSel) or nil

    -- Inherited selection: resolve against the owning group's bucket; drop
    -- it when the view no longer inherits that group or the bar is gone.
    local pabInhBar = nil
    if pabInhSel and inhGroups then
        for gi = 1, #inhGroups do
            if inhGroups[gi] == pabInhSel.group then
                local gl = ns.PAB_BucketBars
                    and ns.PAB_BucketBars(pabInhSel.kind == "buff", pabInhSel.group)
                for i = 1, #(gl or {}) do
                    if gl[i].id == pabInhSel.id then pabInhBar = gl[i] break end
                end
                break
            end
        end
    end
    if not pabInhBar then pabInhSel = nil end

    -- Validate selection against current data (bar may have been deleted
    -- elsewhere, e.g. profile switch). "default" is always valid (the two
    -- fixed built-in bars, not custom-bar list entries).
    if pabSel and pabSel.id ~= "default" then
        local ok = false
        local list = (pabSel.kind == "buff") and buffBars or debuffBars
        for i = 1, #list do if list[i].id == pabSel.id then ok = true end end
        if not ok then pabSel = { kind = "buff", id = "default" } end
    end

    -- Use Blizzard Buffs: the built-in bars stand down (Blizzard's native
    -- display owns buffs/debuffs) and their sidebar tiles hide everywhere.
    local sPABTop = ns.db and ns.db.profile and ns.db.profile.playerAuraBars
    -- Defensive migrations (lane split + empty-bar -> All + disabled): the
    -- default tiles below read cfg.enabled, so the enable migration must
    -- have run.
    if sPABTop and ns.PAB_EnsureBarEnable then ns.PAB_EnsureBarEnable(sPABTop) end
    local useBlizz = (sPABTop and sPABTop.useBlizzardBuffs == true) or false
    -- The default Buffs/Debuffs bars are ALL SPECS content: they list in the
    -- All Specs view (editable) and on concrete spec views (specs show
    -- everything the all-buckets apply to them), but NEVER in the other
    -- group views -- groups don't inherit from each other (BM parity;
    -- All-Specs content is already covered by the All Specs bucket).
    local showDefaults = not useBlizz
        and (pabSpecSel == "allspecs"
            or (type(pabSpecSel) == "string" and pabSpecSel:match("^spec%d") ~= nil))
    -- A "default" selection re-targets the first custom bar (or nothing)
    -- whenever the default tiles are not listed in this view.
    if not showDefaults and pabSel and pabSel.id == "default" then
        local first = buffBars[1] or debuffBars[1]
        if first then
            pabSel = { kind = buffBars[1] and "buff" or "debuff", id = first.id }
        else
            pabSel = nil
        end
    end
    -- Back on a defaults-listing view with nothing selected: re-seed the
    -- default selection so the detail pane never stays blank.
    if showDefaults and not pabSel then
        pabSel = { kind = "buff", id = "default" }
    end

    -- Editing-spec roster, shared by the Editing Spec dropdown and the
    -- right-click "Add To" menu: group buckets, then every spec in the game
    -- as its own "spec<ID>" bucket.
    local function BuildPabSpecRoster()
        local values, order, icons = {}, {}, {}
        for i = 1, #SPEC_GROUP_BUCKETS do
            local g = SPEC_GROUP_BUCKETS[i]
            values[g.key] = L(g.name)
            order[#order + 1] = g.key
            icons[g.key] = g.icon
        end
        order[#order + 1] = "---a"
        for classID = 1, (GetNumClasses and GetNumClasses() or 0) do
            local className = GetClassInfo(classID)
            local numSpecs = GetNumSpecializationsForClassID
                and GetNumSpecializationsForClassID(classID) or 0
            for si = 1, numSpecs do
                local specID, specName, _, sIcon = GetSpecializationInfoForClassID(classID, si)
                if specID then
                    local key = "spec" .. specID
                    values[key] = (specName or "") .. " " .. (className or "")
                    order[#order + 1] = key
                    icons[key] = sIcon
                end
            end
        end
        return values, order, icons
    end

    -- Right-click "Add To" items: the roster minus dividers, the edited
    -- bucket (= the source) disabled.
    local function PabBucketMenuItems()
        local values, order, icons = BuildPabSpecRoster()
        local items = {}
        for i = 1, #order do
            local key = order[i]
            if not key:match("^%-%-%-") then
                items[#items + 1] = {
                    key = key, label = values[key], icon = icons[key],
                    disabled = key == pabSpecSel,
                }
            end
        end
        return items
    end

    -- Page-level "Player Aura Bars" header card removed (by request:
    -- it competed visually with the new per-bar preview box now sitting at the top of
    -- each detail pane). HEADER_H kept at 0 rather than removed outright so `root`'s
    -- offset math below still reads clearly as "below the (now empty) header band".
    local HEADER_H = 0

    local root = CreateFrame("Frame", nil, outerRoot)
    root:SetPoint("TOPLEFT", outerRoot, "TOPLEFT", 0, -HEADER_H)
    root:SetPoint("BOTTOMRIGHT", outerRoot, "BOTTOMRIGHT", 0, 0)
    root:SetFrameLevel(outerRoot:GetFrameLevel() + 1)
    local visibleH = fullH - HEADER_H

    local sidebarOuter = CreateFrame("Frame", nil, root)
    sidebarOuter:SetSize(sidebarW, visibleH)
    sidebarOuter:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -1)
    sidebarOuter:SetFrameLevel(root:GetFrameLevel() + 1)
    local sbBg = sidebarOuter:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(0, 0, 0, 0.25)
    -------------------------------------------------------------------
    --  SECTIONED SIDEBAR (fixed, no outer scroll): top options (Disable
    --  All / Use Blizzard Buffs), Editing Spec, then two independently
    --  scrollable halves (Buff Bars / Debuff Bars).
    -------------------------------------------------------------------
    local fixedY = -6

    -- Toggle row helper (label left, tile-style pill right).
    local function OptionRow(y, label, state, tooltip, onToggle)
        local row = CreateFrame("Frame", nil, sidebarOuter)
        row:SetSize(sidebarW, 26)
        row:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 0, y)
        row:SetFrameLevel(sidebarOuter:GetFrameLevel() + 1)
        row:EnableMouse(true)
        local lbl = row:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(fontPath, 12, "")
        lbl:SetPoint("LEFT", row, "LEFT", 12, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -52, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(label)
        lbl:SetTextColor(1, 1, 1)
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(32, 16)
        btn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        btn:SetFrameLevel(row:GetFrameLevel() + 2)
        local pillBg = btn:CreateTexture(nil, "BACKGROUND")
        pillBg:SetAllPoints()
        local knob = btn:CreateTexture(nil, "ARTWORK")
        knob:SetSize(12, 12)
        if state then
            local acr, acg, acb = 0.05, 0.82, 0.62
            if EllesmereUI.ResolveActiveAccent then
                acr, acg, acb = EllesmereUI.ResolveActiveAccent()
            end
            pillBg:SetColorTexture(acr, acg, acb, 1)
            knob:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            knob:SetColorTexture(1, 1, 1, 1)
        else
            pillBg:SetColorTexture(0.25, 0.25, 0.25, 1)
            knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
            knob:SetColorTexture(0.5, 0.5, 0.5, 1)
        end
        btn:SetScript("OnClick", function() onToggle(not state) end)
        if tooltip then
            row:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(row, tooltip) end)
            row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            btn:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(row, tooltip) end)
            btn:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end
        return y - 26
    end

    -- Disable All: full shutdown, applied live (bars torn down, movers
    -- dropped, Blizzard's native display handed back); a reload is only
    -- recommended cleanup. The page re-covers with the activation overlay,
    -- whose enable action is the way back.
    fixedY = OptionRow(fixedY, L("Disable All"),
        not (ns.PAB_Enabled and ns.PAB_Enabled()),
        L("Turns off Player Aura Bars completely."),
        function(v)
            if not v then return end
            if ns.PAB_SetEnabled then ns.PAB_SetEnabled(false) end
            EllesmereUI:RefreshPage(true)
            if EllesmereUI.ShowConfirmPopup then
                EllesmereUI:ShowConfirmPopup({
                    title       = "Reload Recommended",
                    message     = L("Player Aura Bars are disabled and Blizzard's default display is back. A UI reload is recommended to finish cleanup."),
                    confirmText = "Reload Now",
                    cancelText  = "Later",
                    onConfirm   = function() ReloadUI() end,
                })
            end
        end)

    -- Use Blizzard Buffs: the built-in Buffs/Debuffs bars stand down and
    -- Blizzard's native display returns, all live; custom bars keep working.
    fixedY = OptionRow(fixedY, L("Use Blizzard Buffs"), useBlizz,
        L("Keeps Blizzard's own buff and debuff display and turns off the built-in Buffs and Debuffs bars. Custom bars keep working."),
        function(v)
            if not sPABTop then return end
            sPABTop.useBlizzardBuffs = v and true or nil
            if ns.PAB_ApplyUseBlizzard then ns.PAB_ApplyUseBlizzard() end
            EllesmereUI:RefreshPage(true)
        end)
    -- No divider under the toggles (user call): just breathing room before
    -- the Editing Spec block.
    fixedY = fixedY - 9

    local function SectionDivider(y)
        local div = sidebarOuter:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 8, y - 4)
        div:SetPoint("TOPRIGHT", sidebarOuter, "TOPRIGHT", -8, y - 4)
        div:SetColorTexture(1, 1, 1, 0.08)
        return y - 9
    end

    -------------------------------------------------------------------
    --  EDITING SPEC (fixed block): group buckets lead, then every spec
    --  in the game as its own "spec<ID>" bucket. Bars in the selected
    --  bucket render only on matching specs; concrete views list the
    --  group bars as inherited read-only tiles below.
    -------------------------------------------------------------------
    do
        local specLabel = sidebarOuter:CreateFontString(nil, "OVERLAY")
        specLabel:SetFont(fontPath, 11, "")
        specLabel:SetPoint("TOP", sidebarOuter, "TOPLEFT", floor(sidebarW / 2), fixedY - 8)
        specLabel:SetText(L("EDITING SPEC"))
        specLabel:SetTextColor(0.6, 0.6, 0.6)
        fixedY = fixedY - 27

        -- Roster shared with the right-click "Add To" menu (the menu
        -- rebuilds it lazily per open).
        local specDDValues, specDDOrder, specDDIcons = BuildPabSpecRoster()
        specDDValues._menuOpts = {
            maxHeight = 300,
            icon = function(key) return specDDIcons[key] end,
        }

        local specDD = EllesmereUI.BuildDropdownControl(
            sidebarOuter, sidebarW - 24, sidebarOuter:GetFrameLevel() + 2,
            specDDValues, specDDOrder,
            function() return pabSpecSel or "allspecs" end,
            function(v)
                pabSpecSel = v
                pabSel = { kind = "buff", id = "default" }
                pabInhSel = nil
                EllesmereUI:RefreshPage(true)
            end)
        specDD:SetPoint("TOP", sidebarOuter, "TOPLEFT", floor(sidebarW / 2), fixedY)
        fixedY = fixedY - 36
    end
    fixedY = SectionDivider(fixedY)

    -------------------------------------------------------------------
    --  Split halves (Buff Bars / Debuff Bars), each its own scroll; the
    --  sidebar itself no longer scrolls.
    -------------------------------------------------------------------
    local fixedH = math.abs(fixedY)
    -- Floor keeps the halves from collapsing/overlapping at pathological
    -- window heights (the sidebar also clips its children).
    local half = math.max(60, floor((visibleH - fixedH) / 2))
    sidebarOuter:SetClipsChildren(true)

    local function MakeSection(y, height, headerText)
        local hdr = sidebarOuter:CreateFontString(nil, "OVERLAY")
        hdr:SetFont(fontPath, 11, "")
        hdr:SetPoint("TOP", sidebarOuter, "TOPLEFT", floor(sidebarW / 2), y - 13)
        hdr:SetText(headerText)
        hdr:SetTextColor(0.6, 0.6, 0.6)
        local scroll = CreateFrame("ScrollFrame", nil, sidebarOuter)
        scroll:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 0, y - 32)
        scroll:SetSize(sidebarW, math.max(10, height - 32))
        scroll:SetClipsChildren(true)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(sidebarW)
        scroll:SetScrollChild(child)
        -- The standard smooth scroll + auto-hiding 4px scrollbar.
        local updateThumb = AttachEditorScroll(scroll, child)
        return { child = child, scroll = scroll, top = y, height = height,
            viewH = math.max(10, height - 32), updateThumb = updateThumb }
    end

    -- Finalizes one section: the Add button FLOWS under the tiles while
    -- everything fits, and PINS to the section bottom (always visible) once
    -- the list overflows -- the viewport then ends above the button band and
    -- the scrollbar appears.
    local ADD_AREA = 50 -- AddNewButton's consumed height (pad + button + pad)
    local function FinishSection(sec, tilesY, label, onClick)
        local contentH = math.abs(tilesY)
        if contentH + ADD_AREA <= sec.viewH then
            AddNewButton(sec.child, tilesY, sidebarW, label, onClick)
            sec.child:SetHeight(math.max(10, contentH + ADD_AREA))
        else
            sec.scroll:SetHeight(math.max(10, sec.viewH - ADD_AREA))
            sec.child:SetHeight(contentH + 6)
            AddNewButton(sidebarOuter, sec.top - sec.height + ADD_AREA, sidebarW, label, onClick)
        end
        -- Prime the scrollbar's visibility (it otherwise first paints on the
        -- first wheel/drag).
        if sec.updateThumb then sec.updateThumb() end
    end

    local buffSec = MakeSection(fixedY, half, L("BUFF BARS"))
    local buffChild = buffSec.child
    -- 2% white wash over the whole Buff Bars half (header + list): visual
    -- separation from the debuff half below (user call). BACKGROUND
    -- sublevel 1 sits above the sidebar's own dark bg; tiles render above
    -- both (their frames level higher). Top edge starts at fixedY + 4 --
    -- flush against the divider LINE above (SectionDivider draws it 4px
    -- above the y it returns); bottom edge lands exactly on the
    -- between-halves divider.
    do
        local wash = sidebarOuter:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 0, fixedY + 4)
        wash:SetPoint("TOPRIGHT", sidebarOuter, "TOPRIGHT", 0, fixedY + 4)
        wash:SetHeight(half + 4)
        wash:SetColorTexture(1, 1, 1, 0.02)
    end
    local debuffTop = fixedY - half
    do
        local div = sidebarOuter:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 8, debuffTop)
        div:SetPoint("TOPRIGHT", sidebarOuter, "TOPRIGHT", -8, debuffTop)
        div:SetColorTexture(1, 1, 1, 0.08)
    end
    local debuffSec = MakeSection(debuffTop - 1, visibleH - fixedH - half - 1, L("DEBUFF BARS"))
    local debuffChild = debuffSec.child

    -- Inherited bar tiles for one section (concrete spec views only):
    -- read-only rows -- edit them in their group; the pill toggles ONLY
    -- this spec's enable (ns.PAB_SetInhDisabled). Builds into the given
    -- section child at y; returns the new y cursor.
    local function BuildInheritedBarTiles(sectionChild, tileY, isBuff)
        if not inhGroups then return tileY end
        for gi = 1, #inhGroups do
            local gkey = inhGroups[gi]
            local ginfo = SPEC_GROUP_INFO[gkey]
            local gname = ginfo and L(ginfo.name) or gkey
            local gl = (ns.PAB_BucketBars and ns.PAB_BucketBars(isBuff, gkey)) or {}
            for i = 1, #gl do
                local bar = gl[i]
                local disHere = ns.PAB_InhDisabled and ns.PAB_InhDisabled(pabSpecSel, bar.id)
                local kind = isBuff and "buff" or "debuff"
                tileY = tileY - BuildTile(sectionChild, tileY, {
                    width = sidebarW, fontPath = fontPath,
                    title = L(bar.name or (isBuff and "Buff Bar" or "Debuff Bar")),
                    subtitle = gname,
                    inheritedTooltip = EllesmereUI.Lf("Inherited from %1$s. Editable only there.", gname),
                    selected = (pabInhSel and pabInhSel.kind == kind
                        and pabInhSel.group == gkey and pabInhSel.id == bar.id) and true or false,
                    -- Pill = the PER-SPEC enable only; a group-level disable
                    -- dims the tile instead (the pill must never look dead).
                    dimmed = bar.enabled == false or nil,
                    enabled = (not disHere) and true or false,
                    showToggle = true,
                    onSelect = function()
                        pabInhSel = { kind = kind, group = gkey, id = bar.id }
                        EllesmereUI:RefreshPage(true)
                    end,
                    onToggle = function()
                        if not (ns.PAB_SetInhDisabled and ns.PAB_InhDisabled) then return end
                        ns.PAB_SetInhDisabled(pabSpecSel, bar.id,
                            not ns.PAB_InhDisabled(pabSpecSel, bar.id))
                        Apply(isBuff, bar.id)
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end
        end
        return tileY
    end

    -- Buff bars section (top half): fixed "Buffs" default bar first (hidden
    -- while Use Blizzard Buffs owns the display), then custom bars.
    do
        local sidebarChild = buffChild -- section-scoped: this half's scroll child
        local tileY = 0

        -- Name follows the bar's content (see DefaultBuffBarName). Static, not
        -- a refresh client: every toggle that can change it forces a full page
        -- rebuild, which re-runs this.
        local sPAB = sPABTop
        local defBuffCfg = sPAB and ns.PAB_DefaultBuffsCfg and ns.PAB_DefaultBuffsCfg(sPAB) or nil
        if showDefaults then
        tileY = tileY - BuildTile(sidebarChild, tileY, {
            width = sidebarW, fontPath = fontPath,
            title = DefaultBuffBarName(defBuffCfg),
            subtitle = L("Default"),
            selected = (pabSel and pabSel.kind == "buff" and pabSel.id == "default"
                and not pabInhSel) and true or false,
            -- Enable toggle (cfg.enabled, nil = enabled): disables the bar without
            -- deleting it, custom-bar parity.
            enabled = not (defBuffCfg and defBuffCfg.enabled == false),
            showToggle = defBuffCfg ~= nil,
            onToggle = function(v)
                if not defBuffCfg then return end
                if v then defBuffCfg.enabled = nil else defBuffCfg.enabled = false end
                if ns.PAB_ApplyLiveConfig then ns.PAB_ApplyLiveConfig(true) end
                -- Re-register so an open unlock session drops/restores the mover.
                if ns.PAB_RegisterUnlock then ns.PAB_RegisterUnlock() end
                EllesmereUI:RefreshPage(true)
            end,
            onSelect = function() pabSel = { kind = "buff", id = "default" }; pabInhSel = nil; EllesmereUI:RefreshPage(true) end,
        })
        end
        tileY = BuildInheritedBarTiles(sidebarChild, tileY, true)
        for i = 1, #buffBars do
            local bar = buffBars[i]
            tileY = tileY - BuildTile(sidebarChild, tileY, {
                width = sidebarW, fontPath = fontPath,
                title = L(bar.name or "Buff Bar"),
                subtitleFn = function() return BuildBuffBarSubtitle(bar) end,
                selected = (pabSel and pabSel.kind == "buff" and pabSel.id == bar.id
                    and not pabInhSel) and true or false,
                enabled = bar.enabled and true or false,
                showToggle = true,
                onSelect = function() pabSel = { kind = "buff", id = bar.id }; pabInhSel = nil; EllesmereUI:RefreshPage(true) end,
                -- Right-click: copy this bar into another editing-spec
                -- bucket (full clone, fresh id; the source stays).
                onContext = function(tileFrame)
                    if not EllesmereUI.ShowPickMenu then return end
                    EllesmereUI.ShowPickMenu(tileFrame, {
                        title = L("Add To"),
                        fontPath = fontPath,
                        items = PabBucketMenuItems(),
                        onPick = function(key)
                            local nb = ns.PAB_CopyCustomBar
                                and ns.PAB_CopyCustomBar(true, bar, key)
                            if nb then
                                Apply(true, nb.id)
                                EllesmereUI:RefreshPage(true)
                            end
                        end,
                    })
                end,
                onToggle = function(v)
                    bar.enabled = v and true or false
                    Apply(true, bar.id)
                    EllesmereUI:RefreshPage(true)
                end,
                onRename = function()
                    EllesmereUI:ShowInputPopup({
                        title = L("Rename Bar"), placeholder = L(bar.name or "Buff Bar"),
                        confirmText = L("Rename"), cancelText = L("Cancel"),
                        onConfirm = function(text)
                            if text and text ~= "" then
                                bar.name = text
                                -- Re-registers this bar's Unlock Mode label from
                                -- the new bar.name (RegisterPABCustomUnlock reads
                                -- it live, but only ever re-runs from here) --
                                -- without this, Unlock Mode kept showing the old
                                -- name until the next /reload.
                                Apply(true, bar.id)
                            end
                            EllesmereUI:RefreshPage(true)
                        end,
                    })
                end,
                onDelete = function()
                    EllesmereUI:ShowConfirmPopup({
                        title = L("Delete Bar"),
                        message = L("Delete this buff bar?"),
                        confirmText = L("Delete"), cancelText = L("Cancel"),
                        onConfirm = function()
                            ns.PAB_DeleteCustomBuffBar(bar.id)
                            if pabSel and pabSel.kind == "buff" and pabSel.id == bar.id then
                                pabSel = { kind = "buff", id = "default" }
                            end
                            Apply(true, bar.id)
                            EllesmereUI:RefreshPage(true)
                        end,
                    })
                end,
            })
        end
        FinishSection(buffSec, tileY, L("Add Buff Bar"), function(self)
            ShowAddBarPopup(self, "buff", fontPath)
        end)
    end

    -- Debuff bars section (bottom half): fixed "Debuffs" default bar first
    -- (hidden while Use Blizzard Buffs owns the display), then custom.
    do
        local sidebarChild = debuffChild -- section-scoped: this half's scroll child
        local tileY = 0

        local sPAB2 = sPABTop
        local defDebuffCfg = sPAB2 and ns.PAB_DefaultDebuffsCfg and ns.PAB_DefaultDebuffsCfg(sPAB2) or nil
        if showDefaults then
        tileY = tileY - BuildTile(sidebarChild, tileY, {
            width = sidebarW, fontPath = fontPath,
            title = L("Debuffs"),
            subtitle = L("Default"),
            selected = (pabSel and pabSel.kind == "debuff" and pabSel.id == "default"
                and not pabInhSel) and true or false,
            -- Enable toggle (cfg.enabled, nil = enabled): custom-bar parity.
            enabled = not (defDebuffCfg and defDebuffCfg.enabled == false),
            showToggle = defDebuffCfg ~= nil,
            onToggle = function(v)
                if not defDebuffCfg then return end
                if v then defDebuffCfg.enabled = nil else defDebuffCfg.enabled = false end
                if ns.PAB_ApplyLiveConfig then ns.PAB_ApplyLiveConfig(false) end
                -- Re-register so an open unlock session drops/restores the mover.
                if ns.PAB_RegisterUnlock then ns.PAB_RegisterUnlock() end
                EllesmereUI:RefreshPage(true)
            end,
            onSelect = function() pabSel = { kind = "debuff", id = "default" }; pabInhSel = nil; EllesmereUI:RefreshPage(true) end,
        })
        end

        tileY = BuildInheritedBarTiles(sidebarChild, tileY, false)
        for i = 1, #debuffBars do
            local bar = debuffBars[i]
            tileY = tileY - BuildTile(sidebarChild, tileY, {
                width = sidebarW, fontPath = fontPath,
                title = L(bar.name or "Debuff Bar"),
                subtitleFn = function() return BuildDebuffBarSubtitle(bar) end,
                selected = (pabSel and pabSel.kind == "debuff" and pabSel.id == bar.id
                    and not pabInhSel) and true or false,
                enabled = bar.enabled and true or false,
                showToggle = true,
                onSelect = function() pabSel = { kind = "debuff", id = bar.id }; pabInhSel = nil; EllesmereUI:RefreshPage(true) end,
                -- Right-click: copy this bar into another editing-spec
                -- bucket (full clone, fresh id; the source stays).
                onContext = function(tileFrame)
                    if not EllesmereUI.ShowPickMenu then return end
                    EllesmereUI.ShowPickMenu(tileFrame, {
                        title = L("Add To"),
                        fontPath = fontPath,
                        items = PabBucketMenuItems(),
                        onPick = function(key)
                            local nb = ns.PAB_CopyCustomBar
                                and ns.PAB_CopyCustomBar(false, bar, key)
                            if nb then
                                Apply(false, nb.id)
                                EllesmereUI:RefreshPage(true)
                            end
                        end,
                    })
                end,
                onToggle = function(v)
                    bar.enabled = v and true or false
                    Apply(false, bar.id)
                    EllesmereUI:RefreshPage(true)
                end,
                onRename = function()
                    EllesmereUI:ShowInputPopup({
                        title = L("Rename Bar"), placeholder = L(bar.name or "Debuff Bar"),
                        confirmText = L("Rename"), cancelText = L("Cancel"),
                        onConfirm = function(text)
                            if text and text ~= "" then
                                bar.name = text
                                -- Re-registers this bar's Unlock Mode label from
                                -- the new bar.name (RegisterPABCustomUnlock reads
                                -- it live, but only ever re-runs from here) --
                                -- without this, Unlock Mode kept showing the old
                                -- name until the next /reload.
                                Apply(false, bar.id)
                            end
                            EllesmereUI:RefreshPage(true)
                        end,
                    })
                end,
                onDelete = function()
                    EllesmereUI:ShowConfirmPopup({
                        title = L("Delete Bar"),
                        message = L("Delete this debuff bar?"),
                        confirmText = L("Delete"), cancelText = L("Cancel"),
                        onConfirm = function()
                            ns.PAB_DeleteCustomDebuffBar(bar.id)
                            if pabSel and pabSel.kind == "debuff" and pabSel.id == bar.id then
                                pabSel = { kind = "debuff", id = "default" }
                            end
                            Apply(false, bar.id)
                            EllesmereUI:RefreshPage(true)
                        end,
                    })
                end,
            })
        end
        FinishSection(debuffSec, tileY, L("Add Debuff Bar"), function(self)
            ShowAddBarPopup(self, "debuff", fontPath)
        end)
    end

    local detail = CreateFrame("Frame", nil, root)
    detail:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    detail:SetSize(leftW, visibleH)
    detail:SetFrameLevel(root:GetFrameLevel() + 1)

    if pabInhSel and pabInhBar then
        -- Read-only pane for an INHERITED group bar: where it lives, a jump
        -- link to the owning group, and a pointer at the tile toggle for the
        -- per-spec enable. No settings render -- edits belong to the group.
        local ginfo = SPEC_GROUP_INFO[pabInhSel.group]
        local gname = ginfo and L(ginfo.name) or pabInhSel.group
        local title = detail:CreateFontString(nil, "OVERLAY")
        title:SetFont(fontPath, 18, "")
        title:SetPoint("TOPLEFT", detail, "TOPLEFT", 25, -25)
        title:SetTextColor(0.55, 0.72, 1)
        title:SetText(pabInhBar.name
            or (pabInhSel.kind == "buff" and L("Buff Bar") or L("Debuff Bar")))
        local sub = detail:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontPath, 13, "")
        sub:SetPoint("LEFT", title, "RIGHT", 6, 0)
        sub:SetTextColor(0.75, 0.75, 0.75, 0.65)
        sub:SetText("(" .. EllesmereUI.Lf("Inherited from %1$s", gname) .. ")")
        local info = detail:CreateFontString(nil, "OVERLAY")
        info:SetFont(fontPath, 12, "")
        info:SetPoint("TOPLEFT", detail, "TOPLEFT", 25, -58)
        info:SetPoint("RIGHT", detail, "RIGHT", -35, 0)
        info:SetJustifyH("LEFT")
        info:SetWordWrap(true)
        info:SetText(EllesmereUI.Lf("Inherited from %1$s. Edit it there, or use the tile toggle to enable or disable it for this spec.", gname))
        info:SetTextColor(0.65, 0.65, 0.65)
        local link = CreateFrame("Button", nil, detail)
        link:SetPoint("TOPLEFT", detail, "TOPLEFT", 25, -108)
        link:SetFrameLevel(detail:GetFrameLevel() + 2)
        local linkFS = link:CreateFontString(nil, "OVERLAY")
        linkFS:SetFont(fontPath, 12, "")
        linkFS:SetPoint("TOPLEFT")
        linkFS:SetText(EllesmereUI.Lf("Edit in %1$s", gname))
        local lac = EllesmereUI.ELLESMERE_GREEN
        if lac then linkFS:SetTextColor(lac.r, lac.g, lac.b, 0.85)
        else linkFS:SetTextColor(0.05, 0.82, 0.62, 0.85) end
        link:SetSize(linkFS:GetStringWidth() + 4, 18)
        link:SetScript("OnEnter", function() linkFS:SetAlpha(1) end)
        link:SetScript("OnLeave", function() linkFS:SetAlpha(0.85) end)
        local jumpKind, jumpGroup, jumpId = pabInhSel.kind, pabInhSel.group, pabInhSel.id
        link:SetScript("OnClick", function()
            pabSpecSel = jumpGroup
            pabSel = { kind = jumpKind, id = jumpId }
            pabInhSel = nil
            EllesmereUI:RefreshPage(true)
        end)
    elseif pabSel then
        if pabSel.id == "default" then
            BuildDefaultBarDetail(detail, fontPath, pabSel.kind == "buff")
        elseif pabSel.kind == "buff" then
            local bar = ns.PAB_GetCustomBuffBar and ns.PAB_GetCustomBuffBar(pabSel.id)
            if bar then BuildBuffBarDetail(detail, fontPath, bar) end
        else
            local bar = ns.PAB_GetCustomDebuffBar and ns.PAB_GetCustomDebuffBar(pabSel.id)
            if bar then BuildDebuffBarDetail(detail, fontPath, bar) end
        end
    end

    -- Activation overlay (same chrome as the Debuff Manager page's override/activation
    -- overlay): PAB ships disabled, so the whole page sits under a dark cover with a
    -- single enable action until the user opts in. Built LAST so it covers sidebar +
    -- detail; child of outerRoot so every teardown path destroys it.
    if not (ns.PAB_Enabled and ns.PAB_Enabled()) then
        local ov = CreateFrame("Frame", nil, outerRoot)
        ov:SetAllPoints(outerRoot)
        ov:SetFrameLevel(outerRoot:GetFrameLevel() + 60)
        ov:EnableMouse(true)
        ov._searchIgnore = true
        local bg = ov:CreateTexture(nil, "OVERLAY")
        bg:SetAllPoints()
        bg:SetColorTexture(13/255, 17/255, 25/255, 0.98)
        local title = ov:CreateFontString(nil, "OVERLAY")
        title:SetFont(fontPath, 15, "")
        title:SetPoint("CENTER", ov, "CENTER", 0, 60)
        title:SetTextColor(1, 1, 1, 0.9)
        title:SetText(L("Player Aura Bars"))
        local body = ov:CreateFontString(nil, "OVERLAY")
        body:SetFont(fontPath, 13, "")
        body:SetPoint("TOP", title, "BOTTOM", 0, -14)
        body:SetWidth(floor(parentW * 0.7))
        body:SetJustifyH("CENTER")
        body:SetTextColor(1, 1, 1, 0.56)
        body:SetText(L("Replaces Blizzard's default buff and debuff display with fully customizable bars."))
        local btn = CreateFrame("Button", nil, ov)
        btn:SetSize(240, 28)
        btn:SetPoint("TOP", body, "BOTTOM", 0, -22)
        EllesmereUI.SolidTex(btn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9):SetAllPoints(btn)
        local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.22)
        local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1, 0.85)
        lbl:SetPoint("CENTER")
        lbl:SetText(L("Enable Player Aura Bars"))
        local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.83, b = 0.62 }
        btn:SetScript("OnEnter", function()
            if brd and brd.SetColor then brd:SetColor(eg.r, eg.g, eg.b, 0.9) end
        end)
        btn:SetScript("OnLeave", function()
            if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.22) end
        end)
        btn:SetScript("OnClick", function()
            if ns.PAB_SetEnabled then ns.PAB_SetEnabled(true) end
            EllesmereUI:RefreshPage(true)
        end)
    end

    return 0
end
