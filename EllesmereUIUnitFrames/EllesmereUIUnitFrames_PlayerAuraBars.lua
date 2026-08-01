-------------------------------------------------------------------------------
--  EllesmereUIUnitFrames_PlayerAuraBars.lua
--  12.1 AuraKit-based replacement for the old BuffFrame/DebuffFrame reskin
--  (EllesmereUIUnitFrames_PlayerAuras.lua, retired -- 12.0.7 support dropped).
--
--  STEP A of the build plan: gate, shared class vocabulary, container
--  creation with default + per-class groups. Styling (icon/duration/stack
--  fonts, padding, border) and the dispel-type border are STEP B/C and are
--  intentionally left as minimal placeholders here (see TODO markers) so
--  this step is independently testable: containers should appear showing
--  bare icons before any cosmetic work is layered on.
-------------------------------------------------------------------------------

local _, ns = ...

-- 12.1 ONLY. 12.0.7 support was dropped for Player Aura Bars (decided
-- 2026-07-29) -- unlike every other AuraKit consumer in the suite, there is
-- no legacy module left running behind this gate. The guard stays anyway as
-- a defensive no-op on a stale/mismatched client rather than an assumption
-- that IS_121 is always true by the time this file loads.
if not (EllesmereUI and EllesmereUI.IS_121) then return end

local AK -- EllesmereUI.AuraKit, resolved at first use (parent file loads first)

-------------------------------------------------------------------------------
--  Settings accessor
-------------------------------------------------------------------------------

-- Falls back to an empty table (never nil) so CreateBars() does not silently
-- bail just because no Options UI has written to this profile table yet.
-- An empty table means every class toggle reads false -- BuildChain() still
-- produces the "all" catch-all group per polarity, so bars should render
-- showing every buff/debuff even before any settings exist.
local function PAB()
    local db = ns.db
    return db and db.profile and db.profile.playerAuraBars
end

-------------------------------------------------------------------------------
--  Shared class vocabulary (from EUI_UnitFrames_AuraContainers.lua)
--
--  Player Aura Bars excludes "raid" and "raidcombat" (roster-context tokens
--  that don't apply to a standalone player-only display) -- confirmed with
--  Joel 2026-07-29. Every other class from the shared tables is offered.
-------------------------------------------------------------------------------

local HIDDEN_CLASSES = { raid = true, raidcombat = true }

local function VisibleTokenClasses()
    local uf = ns.UF_TokenClasses
    if not uf then return nil end
    local out = {}
    for i = 1, #uf do
        if not HIDDEN_CLASSES[uf[i].key] then out[#out + 1] = uf[i] end
    end
    return out
end

-- Candidate classes carry no hidden entries currently (bossaura/roleaura/
-- priority/steal all apply to a player-only display) -- passed through
-- unfiltered, but through the same accessor so a future hide is one line.
local function VisibleCandidateClasses()
    return ns.UF_CandidateClasses
end

-- Display metadata for the Options UI's class-toggle dropdown (one entry per
-- VisibleTokenClasses/VisibleCandidateClasses entry, keyed by .skey to match
-- ClassEnabled's db-field convention: "buff"/"debuff" .. skey). Label/
-- tooltip text is copied VERBATIM from EUI_UnitFrames_Options.lua's existing
-- buffFilterItems/debuffFilterItems list (same skey vocabulary already used
-- for Target/Focus/Boss frames -- confirmed consistent wording across the
-- suite), with ONE exception: "NonPlayer" has no counterpart anywhere else
-- in the codebase (that per-unit list never offers it). Its label below is
-- my own pick, not sourced from existing UI text -- flag if different
-- wording is wanted.
local CLASS_LABELS = {
    Dispellable       = { "Dispellable",       "Shows only auras with a dispel type you can dispel" },
    CrowdControl      = { "Crowd Control",      "Shows only crowd-control auras" },
    BigDefensive      = { "Big Defensive",      "Shows only major defensive cooldowns" },
    ExternalDefensive = { "External Defensive", "Shows only external defensive cooldowns cast on the unit" },
    Cancelable        = { "Cancelable",         "Shows only buffs that can be canceled" },
    Stealable         = { "Stealable",          "Shows only buffs you can spellsteal or purge" },
    BossAura          = { "Boss Auras",         "Shows only debuffs applied by bosses" },
    RoleAura          = { "Role Auras",         "Shows only debuffs flagged for your role" },
    PriorityAura      = { "Priority",           "Shows only priority debuffs" },
    NonPlayer         = { "Not Cast By You",    "Shows only debuffs not applied by you" }, -- ASSUMPTION, see note above
}

function ns.PAB_ClassItems(isBuff)
    local items = {}
    local tokenClasses = VisibleTokenClasses()
    local candidateClasses = VisibleCandidateClasses()
    if not (tokenClasses and candidateClasses) then return items end
    local function AddAll(list)
        for i = 1, #list do
            local class = list[i]
            if not ((class.buffOnly and not isBuff) or (class.debuffOnly and isBuff)) then
                local meta = CLASS_LABELS[class.skey]
                items[#items + 1] = {
                    key = class.skey,
                    label = meta and meta[1] or class.skey,
                    tooltip = meta and meta[2] or nil,
                }
            end
        end
    end
    AddAll(tokenClasses)
    AddAll(candidateClasses)
    return items
end

-------------------------------------------------------------------------------
--  Class-enabled check and mutual-exclusion chain builder
--
--  Adapted from EUI_UnitFrames_AuraContainers.lua's ClassEnabled/BuildChain
--  (not shared as functions -- only Joel-approved sharing is the two class
--  tables above; the settings-lookup shape here is Player Aura Bars' own).
--  Same algorithm: token classes negate every earlier-enabled token class
--  before them (mutual exclusion, priority = declaration order); candidate
--  classes sit after the full token negation chain and are boolean engine
--  selectors, not addable to the token chain itself.
-------------------------------------------------------------------------------

local function ClassEnabled(class, isBuff, cfg)
    if class.buffOnly and not isBuff then return false end
    if class.debuffOnly and isBuff then return false end
    -- "Show All Debuffs": bypass every class toggle without touching the
    -- saved classFilters table, so turning it back off restores exactly
    -- what was configured before. Debuffs only -- buffs no longer read
    -- classFilters at all (BM2/filters model, see engine-wiring section).
    -- ~= false (not == true): defaults to ON like showAllBuffs, so nil
    -- (unconfigured bar) behaves the same as an explicit true -- 2026-08-02
    -- symmetry fix, matches showAllBuffs' own "nil == on" convention (see
    -- BuildAssignedBuffsFields' doc comment, which used to flag this as the
    -- one deliberate asymmetry between the two).
    if not isBuff and cfg.showAllDebuffs ~= false then return false end
    -- playerUnitOnly classes (currently just "nonplayer") always apply --
    -- this module only ever targets the player unit.
    return cfg.classFilters and cfg.classFilters[class.skey] == true
end

local function BuildChain(base, classEnabledFn)
    local chain, negations = {}, {}
    local tokenClasses = VisibleTokenClasses()
    local candidateClasses = VisibleCandidateClasses()
    if not (tokenClasses and candidateClasses) then return chain end

    for i = 1, #tokenClasses do
        local class = tokenClasses[i]
        if classEnabledFn(class) then
            local tokens = { base, class.token }
            for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
            chain[#chain + 1] = { key = class.key, tokens = tokens }
            negations[#negations + 1] = class.neg or ("!" .. class.token)
        end
    end
    for i = 1, #candidateClasses do
        local class = candidateClasses[i]
        if classEnabledFn(class) then
            local tokens = { base }
            for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
            chain[#chain + 1] = { key = class.key, tokens = tokens, cand = class.cand }
        end
    end

    -- Catch-all group LAST: everything not claimed by an enabled class,
    -- negating the full chain built above. Always present -- with zero
    -- classes enabled this is just { base }, i.e. every aura of that polarity.
    local allTokens = { base }
    for n = 1, #negations do allTokens[#allTokens + 1] = negations[n] end
    chain[#chain + 1] = { key = "all", tokens = allTokens }

    return chain
end

-------------------------------------------------------------------------------
--  Container spec construction
--
--  STEP A style: bare initializer (icon only, no cooldown/duration/stack/
--  border yet). AK.MakeInitializer with extra=nil still creates the standard
--  icon/cooldown/text regions (see AuraKit.lua's MakeInitializer) since
--  style.noRegions is not set -- this deliberately does NOT use noRegions,
--  so Step B only has to ADD styling, not restructure region creation.
-------------------------------------------------------------------------------

local STYLE_BUFFS = "playerAuraBars_buffs"
local STYLE_DEBUFFS = "playerAuraBars_debuffs"

-- STEP B: real styling. Field names verified against AK's own
-- ApplyStyleToRegions (EllesmereUI_AuraKit.lua) -- not guessed.
--
-- Settings schema (db.profile.playerAuraBars), Step B fields moved into
-- per-bar cfg tables during the Custom Bars increment: s.defaultBuffs /
-- s.defaultDebuffs (DefaultBuffsCfg/DefaultDebuffsCfg below), and every
-- custom bar object (see the CRUD section further down) carries the same
-- shape. No migration from the old flat s.iconSize/s.buffIconZoom/etc
-- fields, or from the old db.profile.playerAuras fields before that --
-- see Joel's "keine Migration, aber Default Buffs/Debuffs anlegen" note.
-- BuildStyle/ComputeGrid/ClassEnabled all take (isBuff, cfg) and don't care
-- which of the above a given cfg table came from.
--
-- Shared by every bar:
--   iconSize                          (button width == height)
--   durationShow, stackShow           (independent show/hide, replaces the
--                                      old combined showText -- no migration,
--                                      same "leave the old field stale"
--                                      precedent as everywhere else here)
--   durationTextSize, durationPosition ("TOP"/"BOTTOM"/...), durationOffsetX/Y
--   durationColorR/G/B                (optional; nil = white, AK default)
--   stackTextSize, stackPosition, stackOffsetX/Y
--   stackColorR/G/B                   (optional; nil = white, AK default)
-- Buff/debuff bars additionally:
--   iconZoom                          (default 0.07, matches AK's own fallback)
--   borderSize, borderR/G/B/A         (base border color; per-dispel-type
--                                      override is Step C, not this)
--   padding                           (single scalar -> applied to all 4 sides)
--   maxTotal                          (overall icon cap)
--   iconsPerRow                       (row width in icon columns)
--   maxRows                           (row cap; combined with iconsPerRow this
--                                      also bounds maxTotal -- see ComputeGrid())
--   growDirection                     ("LEFT"/"RIGHT"; default LEFT, matches a
--                                      TOPRIGHT anchor growing inward like
--                                      Blizzard's own BuffFrame)
-- Buff bars (default AND custom -- unified onto one model 2026-08-01):
--   filters                           ([filterId]=true, references the
--                                      shared PAB Filters registry)
--   spells                            ({spellID,...}, direct/"Extra Spells")
--   showAllBuffs                      (default bar ONLY -- custom buff bars
--                                      never read this. Defaults to true:
--                                      without it, an unconfigured bar
--                                      (no Filters/Extra Spells) would show
--                                      nothing; true adds one additive
--                                      catch-all GROUP alongside the
--                                      spells group, matching both
--                                      Blizzard's own player BuffFrame and
--                                      this bar's pre-redesign default. UI
--                                      toggle: "Show All Buffs" in
--                                      BuildAssignedBuffsFields, mirrors
--                                      Show All Debuffs.)
--   (classFilters has NO effect on buff bars any more -- BuildChain is only
--   used via the always-catch-all showAllBuffs group, never per-class.)
-- Debuff bars (default AND custom):
--   classFilters                      ([classSkey]=true)
--   showAllDebuffs                    (bypasses classFilters entirely unless
--                                      explicitly false. Defaults to TRUE
--                                      (nil == on) as of 2026-08-02, mirroring
--                                      showAllBuffs' own default -- previously
--                                      defaulted to false/off, unlike
--                                      RaidFrames' DebuffManager "Show All"
--                                      which always defaulted to true)
--   dispelColorMagic/Curse/Disease/Poison/Bleed  (optional Color-like {r,g,b};
--                                      falls back to the same palette as
--                                      Raid Frames if unset)
--
-- NOT carried over from the old module: durationFormat variants ("colon"/
-- "seconds"). AK.GetDurationFormatter() returns ONE shared formatter instance
-- (the default rule-based style: bare seconds under 60, then Xm/Xh/Xd) -- it
-- does not expose a way to pick a different formatter per style. Supporting
-- the old colon/seconds variants would mean extending AuraKit itself (shared
-- file, used by Raid Frames too), not something to do silently inside this
-- module. Flagging this rather than dropping it without a word -- let me know
-- if that variant matters enough to be worth extending AK for.
-- Local copy of the dispel-token/fallback-color table from
-- EUI_RaidFrames_AuraContainers.lua's DISPEL_SLOTS. NOT a cross-addon
-- reference (ns is per-addon-private, confirmed with Joel 2026-07-29,
-- RaidFrames and UnitFrames are separate addons) -- duplicated here on
-- purpose, keeping the same tokens/fallback colors so dispel-type coloring
-- looks consistent across the whole suite. If the RaidFrames palette
-- changes, this needs to be updated by hand; there is no shared source.
local DISPEL_SLOTS = {
    { token = "Magic",   colorKey = "dispelColorMagic",   fallback = { 0.349, 0.475, 1.0 } },
    { token = "Curse",   colorKey = "dispelColorCurse",   fallback = { 0.636, 0.0, 0.64 } },
    { token = "Disease", colorKey = "dispelColorDisease", fallback = { 0.671, 0.384, 0.098 } },
    { token = "Poison",  colorKey = "dispelColorPoison",  fallback = { 0.0, 0.706, 0.286 } },
    { token = "Bleed",   colorKey = "dispelColorBleed",   fallback = { 0.75, 0.15, 0.15 } },
}

-- Same shape as RaidFrames' ns.RFC_DispelBorderColorMap: a
-- customDispelColorMap (dispelName string -> Color) for AK's engine-driven
-- border, plus a fingerprint string so a palette edit re-registers the
-- border options (see AK's style.dispelColorFP usage).
local function BuildDispelColorMap(cfg)
    local map, fp = {}, {}
    for i = 1, #DISPEL_SLOTS do
        local def = DISPEL_SLOTS[i]
        local c = cfg[def.colorKey]
        local r = (c and c.r) or def.fallback[1]
        local g = (c and c.g) or def.fallback[2]
        local b = (c and c.b) or def.fallback[3]
        map[def.token] = CreateColor(r, g, b, 1)
        fp[#fp + 1] = string.format("%.3f,%.3f,%.3f", r, g, b)
    end
    return map, table.concat(fp, ";")
end

-- Standard WoW anchor-point mirror, used to place duration text OUTSIDE the
-- icon on a chosen side: text's OWN point is the opposite corner/edge of the
-- icon's anchor point, so e.g. picking "TOP" anchors the text's BOTTOM edge
-- to the icon's TOP edge (text sits above, growing upward) rather than the
-- other way around.
local OPPOSITE_POINT = {
    TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT",
    TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT",
    BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT",
    CENTER = "CENTER",
}

-- Secondary text-styling pass, run by AK on top of its own native
-- position/size handling (verified field/hook: EUI_UnitFrames_AuraContainers
-- .lua's BuildStyle sets `applyExtra = ApplyUFText`, called as
-- (button, d, style); `d.duration`/`d.stack` are the FontStrings AK's own
-- initializer creates). Deliberately does NOT touch font/position/size --
-- those are already handled correctly by AK's native durationPoint/
-- durationX/Y/stackPoint/stackX/Y fields below (Step B, already live) --
-- this hook ONLY adds what AK has no native field for: duration/stack text
-- color and independent stack-text show/hide (AK's own hideDurationText
-- covers duration hide already; there is no equivalent native field for
-- stacks, confirmed by its absence from every AK-native style field used
-- in this file so far).
local function PAB_ApplyExtraText(button, d, style)
    if d.duration then
        local c = style.durationColor
        d.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
    end
    if d.stack then
        d.stack:SetShown(style.showStacks ~= false)
        local c = style.stackColor
        d.stack:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
    end
end

local function BuildStyle(isBuff, cfg)
    local iconZoom = cfg.iconZoom
    local borderSize = cfg.borderSize or 1
    local borderR = cfg.borderR or 0
    local borderG = cfg.borderG or 0
    local borderB = cfg.borderB or 0
    local borderA = cfg.borderA or 1

    -- size 0 = no border (matches the Options page: the old separate "Hide
    -- Border" toggle was removed since Border Size = 0 already achieves it).
    local border
    if borderSize > 0 then
        border = { borderR, borderG, borderB, borderA, size = borderSize }
    end

    -- Duration/Stack position: defaults may arrive as "Bottom"/"Top" (mixed
    -- case) rather than the exact uppercase Blizzard anchor constants
    -- SetPoint expects -- normalized here so a mismatched-case default or
    -- Options write can't silently mis-anchor or error.
    local durSide = string.upper(cfg.durationPosition or "BOTTOM")
    local stackSide = string.upper(cfg.stackPosition or "TOP")

    local style = {
        width = cfg.iconSize or 32,
        height = cfg.iconSize or 32,
        iconCrop = true,
        iconZoom = iconZoom or 0.055,

        cooldownReverse = true,
        hideSwipe = false,

        hideDurationText = cfg.durationShow == false,
        durationFontSize = cfg.durationTextSize or 11,
        durationPoint = OPPOSITE_POINT[durSide] or "TOP",
        durationRelPoint = durSide,
        durationX = cfg.durationOffsetX or 0,
        durationY = cfg.durationOffsetY or 0,
        durationColor = cfg.durationColorR and
            { r = cfg.durationColorR, g = cfg.durationColorG, b = cfg.durationColorB } or nil,

        stackFontSize = cfg.stackTextSize or 11,
        stackPoint = stackSide,
        stackX = cfg.stackOffsetX or 0,
        stackY = cfg.stackOffsetY or 0,
        showStacks = cfg.stackShow ~= false,
        stackColor = cfg.stackColorR and
            { r = cfg.stackColorR, g = cfg.stackColorG, b = cfg.stackColorB } or nil,

        applyExtra = PAB_ApplyExtraText,

        border = border,
    }

    -- STEP C: engine dispel-type border. Debuffs only -- buffs have no
    -- dispel type. Per AK's own gate (ApplyStyleToRegions), this only
    -- activates when `border` above is ALSO non-nil -- i.e. borderSize = 0
    -- disables dispel-type coloring too, not just the static ring. That is
    -- the engine's behavior, not a choice made here.
    -- borderSize drives BOTH the static ring width above AND this engine
    -- dispel-color ring width -- the separate dispelBorderSize field/UI row
    -- was merged away; if a distinct dispel-ring width is wanted again
    -- later, split this back out into its own setting.
    if not isBuff then
        local dcMap, dcFP = BuildDispelColorMap(cfg)
        style.dispelBorder = true
        style.dispelBorderPx = borderSize
        style.dispelColorMap = dcMap
        style.dispelColorFP = dcFP
    end

    return style
end

-- Declares/updates every group in `chain` on an existing (already-created)
-- container. Groups are ADDITIVE and the container is NEVER torn down and
-- rebuilt: AK.ReleaseContainer()+RequestContainer() would work but permanently
-- leaks a 10-button engine batch per group per swap (frames are never freed
-- by WoW) -- confirmed as an accepted-then-fixed problem in the sibling
-- module's history (EUI_UnitFrames_AuraContainers.lua: "The old swap path
-- permanently leaked a 10-button batch per group per toggle"). This function
-- mirrors that module's ApplyGroupConfig instead: a class toggle (or grid/
-- padding/growth change) just calls this again on the SAME container.
--
-- A group's filter string is fixed at declaration (no group filter setter
-- exists on AuraContainer), so a class that was already declared under one
-- set of enabled classes keeps its original negation-chain tokens even if an
-- earlier-priority class gets enabled/disabled later -- the same known,
-- accepted limitation the sibling module carries (not something introduced
-- here). In practice this only matters if the user re-orders which classes
-- are active in a way that changes an ALREADY-DECLARED class's negation set;
-- toggling the SAME class on/off again is always correct since its own
-- filter never needs to change, only its maxFrameCount.
--
-- declaredSet is a per-container registry of every group key ever declared
-- on that container: declared.debuffs for the default Debuffs bar/every
-- custom Debuff Bar (class-token chain), declared.buffs for the default
-- Buffs bar's single "Show All Buffs" catch-all group (see CreateBars'
-- doc comment for why buffs still need ONE group alongside their slots).
local function ApplyGroupConfig(container, chain, declaredSet, styleKey, effectiveMax, gap)
    -- elementSpacing = gap between icons in the same row; lineSpacing = gap
    -- between wrapped rows within a group; group*Spacing = gap to the NEXT
    -- group on the same container. All four use the same scalar (matches the
    -- old module's single "padding" value) -- container-level padding is the
    -- OUTER edge inset only and does not affect icon-to-icon gaps.
    local layout = {
        elementSpacing = gap,
        lineSpacing = gap,
        groupSpacing = gap,
        groupLineSpacing = gap,
    }

    local active = {}
    for i = 1, #chain do
        local link = chain[i]
        active[link.key] = true
        if not declaredSet[link.key] then
            local candidateFilters
            if link.cand then
                candidateFilters = { [link.cand] = true }
            end
            AK.AddGroupToContainer(container, {
                key = link.key,
                filter = link.tokens,
                style = styleKey,
                maxFrameCount = 0, -- real count applied right below, matches the sibling module's declare-then-set order
                candidateFilters = candidateFilters,
            })
            declaredSet[link.key] = true
        end
        container:SetAuraGroupMaxFrameCount(link.key, effectiveMax)
        container:SetAuraGroupLayout(link.key, layout)
    end

    -- Zero out any previously-declared group that fell out of the active
    -- chain (a class just got disabled). It stays declared -- just hidden --
    -- since it can't be un-declared.
    for key in pairs(declaredSet) do
        if not active[key] then
            container:SetAuraGroupMaxFrameCount(key, 0)
        end
    end
end

-- Grid sizing. AK's flow layout only exposes a row WIDTH (pixels) to wrap
-- on -- there is no native "max lines" cap (verified: Blizzard_AuraContainer-
-- FlowLayout.lua only has SetMaximumLineSize, nothing row-count based). A
-- row cap is therefore enforced indirectly by capping maxFrameCount to
-- rows*cols, and the anchor frame's real footprint is our own bounding-box
-- estimate from the same three numbers -- not something AK reports back.
--
-- New settings (Step D addition, alongside maxTotal, the existing overall
-- cap): iconsPerRow (columns), maxRows. Effective cap = min(configured
-- maxTotal, maxRows * iconsPerRow) -- e.g. maxTotal=10 with a 5x5 grid
-- still shows at most 10, using 2 rows.
--
-- iconsPerRow/maxRows/maxTotal fallbacks are isBuff-conditional (11x3=32 for
-- buffs, 8x2=16 for debuffs) -- only reached when a bar doesn't set these
-- fields itself, i.e. the two default bars (Joel's chosen starting values,
-- 2026-08-02). Every custom bar sets all three explicitly at creation
-- (PAB_AddCustomBuffBar/DebuffBar, 8x1=8 for both), so this fallback is
-- default-bar-only in practice.
local function ComputeGrid(isBuff, cfg)
    local iconSize = cfg.iconSize or 32
    local pad = cfg.padding or 5
    local cols = math.max(1, cfg.iconsPerRow or (isBuff and 11 or 8))
    local rows = math.max(1, cfg.maxRows or (isBuff and 3 or 2))
    local configuredMax = cfg.maxTotal or (isBuff and 32 or 16)
    local effectiveMax = math.min(configuredMax, rows * cols)
    -- Actual rows needed for the effective cap, never more than the row limit
    local usedRows = math.min(rows, math.max(1, math.ceil(effectiveMax / cols)))
    local cell = iconSize + pad
    return {
        effectiveMax = effectiveMax,
        rowWidth = cols * cell,
        width = cols * cell,
        height = usedRows * cell,
    }
end

-- Lazily creates and returns the default bars' per-polarity cfg sub-tables.
-- Same shape as a custom bar object's shared+category fields (see the CRUD
-- section below) -- BuildStyle/ComputeGrid/ClassEnabled don't know or care
-- whether a cfg came from here or from a custom bar entry.
local function DefaultBuffsCfg(s)
    s.defaultBuffs = s.defaultBuffs or {}
    return s.defaultBuffs
end
local function DefaultDebuffsCfg(s)
    s.defaultDebuffs = s.defaultDebuffs or {}
    return s.defaultDebuffs
end
ns.PAB_DefaultBuffsCfg = DefaultBuffsCfg
ns.PAB_DefaultDebuffsCfg = DefaultDebuffsCfg

local buffsContainer, debuffsContainer
local buffsParent, debuffsParent
-- Per-container, per-polarity registry of every group key ever declared
-- (see ApplyGroupConfig above) -- reset only when a container is (re-)
-- created, never cleared on a live settings change.
local declared = { buffs = {}, debuffs = {} } -- buffs: only the "Show All Buffs" catch-all group key ("all"); debuffs: every class-token chain group key
local lastSize = { buffs = nil, debuffs = nil } -- {w=,h=}, tracks our own last-applied grid size for CENTER-anchor compensation (see ApplyLiveConfig)
local buffsSlotSig -- signature of the default Buffs bar's last-applied resolved spell list (ns.PAB_ResolveSpells), mirrors customBuffSig[barId] for the per-bar slots model
local RegisterPABUnlock -- forward-declared; defined after CreateBars, called from it
local ReloadAllCustomBars -- forward-declared; defined after CreateBars (custom bars section), called from it

-- Grow direction. AK.ApplyContainerLayout only applies growth when BOTH
-- growthH and growthV are set (verified: `if layout.growthH and
-- layout.growthV then ... end`) -- growthV is always Down regardless of the
-- user's L/R choice (rows still wrap downward). Values are
-- AnchorUtil.FlowDirection members, NOT strings -- verified against
-- Blizzard_SharedXMLBase/AnchorUtil.lua: Left=-1, Right=1, Up=1, Down=-1. Our
-- own settings still store "LEFT"/"RIGHT" strings (matches EUI_UnlockMode.
-- lua's dropdown `val` convention).
--
-- CRITICAL, found 2026-07-30: AnchorUtil.ApplyFlowLayout positions every
-- element via `layout:GetAnchorPoint()` (default "TOPLEFT", a THIRD,
-- independent field -- layout.anchorPoint -- we never set) -- NOT via our
-- outer spec.point. Elements are placed relative to that internal anchor
-- with offsets increasing in the growthH direction. Leaving anchorPoint
-- stuck at its default while growthH changed is exactly what put the first
-- icon on the wrong side / let icons drift outside the mover box. Fix:
-- derive ONE corner from the direction and use it for BOTH the outer frame
-- anchor (against buffsParent/debuffsParent) and the internal flow
-- anchorPoint, so the "fixed" corner and the flow's start corner are always
-- the same physical point:
--   growDirection RIGHT -> fixed/start corner TOPLEFT (icons extend right)
--   growDirection LEFT  -> fixed/start corner TOPRIGHT (icons extend left)
-- This is derived directly from AnchorUtil's source, not copied from a
-- working Blizzard example -- no other Blizzard UI uses this new flow layout
-- system yet to cross-check against. Confirmed in-game 2026-07-30 (Joel).
local function ToGrowthH(dirStr)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    if not FlowDir then return nil end
    return dirStr == "RIGHT" and FlowDir.Right or FlowDir.Left
end
local function CornerFor(dirStr)
    return dirStr == "RIGHT" and "TOPLEFT" or "TOPRIGHT"
end

-- Shared by every container -- default bars (buffs/debuffs) AND custom bars
-- alike: builds the AK.RequestContainer spec's point+layout from a bar-local
-- cfg's growDirection and a precomputed grid (see ComputeGrid). One
-- implementation so default and custom bars can never drift in how they
-- interpret growDirection/rowWidth. Returns the corner too since callers
-- also need it for the container's own SetPoint against its parent frame.
local function BuildContainerSpec(parent, cfg, grid)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    local dir = cfg.growDirection or "LEFT"
    local corner = CornerFor(dir)
    return corner, {
        point = { corner, parent, corner, 0, 0 },
        layout = {
            anchorPoint = corner,
            padding = { 0, 0, 0, 0 },
            rowWidth = grid.rowWidth,
            growthH = ToGrowthH(dir),
            growthV = FlowDir and FlowDir.Down,
        },
    }
end

-- Default anchor when no saved position exists yet. Independent per bar
-- (Joel: bars must be individually movable) -- debuffs no longer chained to
-- buffsParent's BOTTOMRIGHT as in Step A, just a separate default offset so
-- the two don't overlap before either has been dragged.
local DEFAULT_POS = {
    buffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -200 },
    debuffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -260 },
}

local function BarPositionKey(isBuff)
    return isBuff and "buffsPos" or "debuffsPos"
end

-- Applies the saved position (if any) or the default to the given parent
-- frame. Shared between initial creation and the unlock-mode applyPos
-- callback so the two never drift into different SetPoint logic.
local function ApplyBarPosition(parent, isBuff)
    local s = PAB()
    local pos = s and s[BarPositionKey(isBuff)]
    local def = isBuff and DEFAULT_POS.buffs or DEFAULT_POS.debuffs
    parent:ClearAllPoints()
    if pos and pos.point then
        parent:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        parent:SetPoint(def.point, UIParent, def.relPoint, def.x, def.y)
    end
end

-- Blizzard's own player BuffFrame/DebuffFrame are now fully superseded by
-- this module -- hide them so auras aren't shown twice. Same pattern
-- already used elsewhere in this addon for "Blizzard keeps re-showing this"
-- cases: Hide() once, then hooksecurefunc(Show) to immediately re-hide any
-- time Blizzard's own code calls Show() again (e.g. on an aura update).
-- hooksecurefunc runs AFTER Blizzard's secure call completes, not from
-- inside it, so this does not taint anything. Neither frame is a protected/
-- secure frame itself -- plain Hide() is safe outside of any special
-- lockdown concern.
local blizzardAurasHidden = false
local function HideBlizzardPlayerAuras()
    if blizzardAurasHidden then return end
    blizzardAurasHidden = true
    if BuffFrame then
        BuffFrame:Hide()
        hooksecurefunc(BuffFrame, "Show", function() BuffFrame:Hide() end)
    end
    if DebuffFrame then
        DebuffFrame:Hide()
        hooksecurefunc(DebuffFrame, "Show", function() DebuffFrame:Hide() end)
    end
end

local function CreateBars()
    AK = AK or (EllesmereUI and EllesmereUI.AuraKit)
    if not AK then return end -- 12.1 gated at file top; defensive only

    local s = PAB()
    if not s then return end -- ns.db not ready yet; TryCreateBars() below retries

    HideBlizzardPlayerAuras()

    local buffCfg, debuffCfg = DefaultBuffsCfg(s), DefaultDebuffsCfg(s)

    AK.styles[STYLE_BUFFS] = BuildStyle(true, buffCfg)
    AK.styles[STYLE_DEBUFFS] = BuildStyle(false, debuffCfg)

    local buffGrid = ComputeGrid(true, buffCfg)
    local debuffGrid = ComputeGrid(false, debuffCfg)

    buffsParent = buffsParent or CreateFrame("Frame", "EllesmereUIPlayerAuraBars_Buffs", UIParent)
    buffsParent:SetSize(buffGrid.width, buffGrid.height)
    ApplyBarPosition(buffsParent, true)
    lastSize.buffs = { w = buffGrid.width, h = buffGrid.height }

    debuffsParent = debuffsParent or CreateFrame("Frame", "EllesmereUIPlayerAuraBars_Debuffs", UIParent)
    debuffsParent:SetSize(debuffGrid.width, debuffGrid.height)
    ApplyBarPosition(debuffsParent, false)
    lastSize.debuffs = { w = debuffGrid.width, h = debuffGrid.height }

    local debuffChain = BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, debuffCfg) end)

    -- Single scalar padding (matches the old module's paddingBuffs/
    -- paddingDebuffs) -- feeds ONLY ApplyGroupConfig's per-group
    -- elementSpacing/lineSpacing/groupSpacing/groupLineSpacing below (the
    -- gap between icons). Must NOT also feed the container's own outer edge
    -- inset (spec.layout.padding / AK.SetContainerPadding) -- that's a
    -- DIFFERENT concept (margin from the container frame edge to the first
    -- icon) and was wrongly tied to this same value before, which pushed
    -- the whole grid away from its fixed corner as padding grew instead of
    -- only widening gaps between icons. Outer edge inset is fixed at 0
    -- below instead.
    local buffPad = buffCfg.padding or 5
    local debuffPad = debuffCfg.padding or 5

    local _, buffSpec = BuildContainerSpec(buffsParent, buffCfg, buffGrid)
    local _, debuffSpec = BuildContainerSpec(debuffsParent, debuffCfg, debuffGrid)

    -- Groups are declared additively right after creation (not via
    -- spec.groups) so the exact same ApplyGroupConfig path handles both
    -- initial creation and every later live settings change -- see
    -- ApplyGroupConfig's doc comment above.
    --
    -- Buffs: the Filters/Extra-Spells selection and the "Show All Buffs"
    -- catch-all GROUP coexist additively on the same container -- both are
    -- GROUPS now (2026-08-02 fix, see below), independent declarations,
    -- nothing in AK's model makes them mutually exclusive.
    -- The catch-all uses the SAME zero-classes-enabled chain trick as
    -- Debuffs' "all" group (BuildChain's own doc comment: "with zero
    -- classes enabled this is just { base }, i.e. every aura of that
    -- polarity") -- there is no per-class filtering UI for buffs, so this
    -- is unconditionally all-or-nothing, gated only by showAllBuffs.
    -- Defaults ON: without it, an unconfigured bar (no filters/extra
    -- spells) would show nothing; ON matches both Blizzard's own player
    -- BuffFrame (FrameXML BuffFrame.lua filters HELPFUL with no category
    -- restriction) and this bar's pre-redesign default behavior (empty
    -- classFilters = catch-all).
    --
    -- 2026-08-02 FIX: the Filters/Extra-Spells selection was originally
    -- built as one AK.AddAuraSlot per resolved spellID. Field-verified (via
    -- temporary instrumentation: extraInit fired, buttons reported
    -- shown=true/correct size, but GetPoint(1) returned nil and nothing
    -- rendered on screen -- even an UNRESTRICTED slot with no
    -- candidateFilters at all never appeared) that AK's flow layout only
    -- positions GROUP content (AddAuraGroup), not slot content
    -- (AddAuraSlot) -- slots are apparently meant to be self-anchored via
    -- extraInit (confirmed by both other AddAuraSlot consumers in this
    -- codebase, EUI_RaidFrames_AuraContainers.lua's chain slots and
    -- EUI_ResourceBars_EbonMight121.lua, which both manually SetPoint their
    -- slot button in extraInit rather than relying on the container flow).
    -- PAB wants a flowing multi-icon grid of a DYNAMIC spell set, which
    -- slots don't support without reimplementing flow placement by hand.
    -- Fix: use ONE GROUP whose candidateFilters.includeSpellIDs is the
    -- resolved spell-ID set (map shape {[id]=true}, verified against every
    -- other includeSpellIDs consumer in the codebase -- BmIncludeMap,
    -- BmSimpleCand, EbonMight121's own candidateFilters -- all use a map,
    -- never an array). A group's candidateFilters is fixed at declaration
    -- (see ApplyGroupConfig's own doc comment), so a spell-list change
    -- still requires releasing and recreating the container -- same
    -- sig-diffing this file already used for the slot version.
    local buffAllChain = BuildChain("HELPFUL", function() return false end)
    local buffSpells = ns.PAB_ResolveSpells(buffCfg)
    buffsSlotSig = table.concat(buffSpells, ",")
    AK.RequestContainer(buffsParent, "player", buffSpec, function(container)
        buffsContainer = container
        declared.buffs = {}
        if buffCfg.showAllBuffs ~= false then
            ApplyGroupConfig(container, buffAllChain, declared.buffs, STYLE_BUFFS, buffGrid.effectiveMax, buffPad)
        end
        if #buffSpells > 0 then
            local includeMap = {}
            for i = 1, #buffSpells do includeMap[buffSpells[i]] = true end
            AK.AddGroupToContainer(container, {
                key = "spells",
                filter = { "HELPFUL" },
                style = STYLE_BUFFS,
                maxFrameCount = buffGrid.effectiveMax,
                candidateFilters = { includeSpellIDs = includeMap },
            })
            container:SetAuraGroupLayout("spells", {
                elementSpacing = buffPad, lineSpacing = buffPad,
                groupSpacing = buffPad, groupLineSpacing = buffPad,
            })
            declared.buffs.spells = true
        end
    end)
    AK.RequestContainer(debuffsParent, "player", debuffSpec, function(container)
        debuffsContainer = container
        declared.debuffs = {}
        ApplyGroupConfig(container, debuffChain, declared.debuffs, STYLE_DEBUFFS, debuffGrid.effectiveMax, debuffPad)
    end)

    RegisterPABUnlock()
    ReloadAllCustomBars()
end

-- Unlock-mode registration, patterned directly on
-- EllesmereUIDamageMeters.lua's ns.RegisterDMUnlock / MakeSATimerUnlockElement
-- (the only two real usage examples available -- EUI.MakeUnlockElement's own
-- source was not provided, so this mirrors observed field usage rather than
-- a verified schema). Both bars: noResize (AuraKit sizes the container
-- itself based on active aura count, nothing here to drag-resize) and
-- noAnchorTarget (same reasoning as the combat timer: a dynamically-resizing
-- frame is a bad anchor target for other elements -- confirmed with Joel
-- 2026-07-29).
function RegisterPABUnlock()
    if not (EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local MK = EllesmereUI.MakeUnlockElement

    local function MakeBarElement(key, label, order, isBuff, getParent)
        return MK({
            key = key,
            label = label,
            group = "Player Aura Bars",
            order = order,
            noResize = true,
            noAnchorTarget = true,
            getFrame = function() return getParent() end,
            -- Deliberately NOT container:GetWidth()/GetHeight(): AuraContainer
            -- geometry is a Secret Value while execution is tainted (field
            -- confirmed 2026-07-30 -- EUI_UnlockMode.lua:6250 threw comparing
            -- a secret baseW). noResize is set anyway, so an exact live size
            -- isn't needed here, just a public number for the mover's label.
            getSize = function()
                local s = PAB()
                if not s then return 32, 32 end
                local grid = ComputeGrid(isBuff, isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s))
                return grid.width, grid.height
            end,
            savePos = function(_, point, relPoint, x, y)
                local s = PAB()
                if not s then return end
                s[BarPositionKey(isBuff)] = { point = point, relPoint = relPoint or point, x = x, y = y }
            end,
            loadPos = function()
                local s = PAB()
                local pos = s and s[BarPositionKey(isBuff)]
                if not pos then return nil end
                return { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
            end,
            clearPos = function()
                local s = PAB()
                if s then s[BarPositionKey(isBuff)] = nil end
            end,
            applyPos = function()
                local parent = getParent()
                if parent then ApplyBarPosition(parent, isBuff) end
            end,
        })
    end

    local elements = {
        MakeBarElement("PAB_Buffs", "Buffs", 700, true, function() return buffsParent end),
        MakeBarElement("PAB_Debuffs", "Debuffs", 701, false, function() return debuffsParent end),
    }
    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIUnitFrames")
end

-- Public hook for the Options UI: rebuild both style tables from current
-- settings and re-decorate every existing button. Purely a re-skin -- does
-- NOT touch groups, filters, container layout, or parent frame size. Call
-- for style-only fields (colors, fonts, border, dispel colors, cooldown/
-- stack text, icon zoom). For iconSize specifically, also call
-- ApplyLiveConfig for both polarities, since icon size affects grid geometry
-- too, not just per-button style.
local function RestyleBars()
    local s = PAB()
    if not (AK and s) then return end
    AK.styles[STYLE_BUFFS] = BuildStyle(true, DefaultBuffsCfg(s))
    AK.styles[STYLE_DEBUFFS] = BuildStyle(false, DefaultDebuffsCfg(s))
    AK.RestyleSoon(STYLE_BUFFS)
    AK.RestyleSoon(STYLE_DEBUFFS)
end
ns.PAB_Restyle = RestyleBars

-- Public hook for the Options UI: live counterpart to RestyleBars for
-- everything spec-level (class toggles, grid: iconsPerRow/maxRows/padding/
-- maxBuffs-or-Debuffs, grow direction). Applies to ONE polarity's container;
-- callers touching a shared field (iconSize) call this for both. No-op
-- before the container exists yet (TryCreateBars will call CreateBars(),
-- which ends up here anyway once ns.db is ready).
local function ApplyLiveConfig(isBuff)
    local s = PAB()
    if not (AK and s) then return end
    local container = isBuff and buffsContainer or debuffsContainer
    local parent = isBuff and buffsParent or debuffsParent
    if not container or not parent then return end

    local cfg = isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)
    local grid = ComputeGrid(isBuff, cfg)
    local sizeKey = isBuff and "buffs" or "debuffs"
    local prev = lastSize[sizeKey]

    -- Compensate for CENTER-anchored saved positions: SetSize on a
    -- CENTER/CENTER point grows/shrinks symmetrically in all directions, so
    -- any height/width change would visibly shift the icons. Shift the
    -- saved position by half the delta so the CENTER point stays put. Uses
    -- OUR OWN last-applied size (lastSize), not parent:GetWidth/GetHeight --
    -- querying the live frame was jitter-prone across rapid successive
    -- calls (e.g. dragging a slider), since there's no guarantee the
    -- frame's rendered size already reflects the previous call before this
    -- one reads it. Skipped entirely when the size hasn't actually changed.
    local posKey = BarPositionKey(isBuff)
    local pos = s[posKey]
    if pos and pos.point == "CENTER" and prev and (prev.w ~= grid.width or prev.h ~= grid.height) then
        pos.x = pos.x + (prev.w - grid.width) / 2
        pos.y = pos.y + (prev.h - grid.height) / 2
        parent:ClearAllPoints()
        parent:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    end
    lastSize[sizeKey] = { w = grid.width, h = grid.height }

    parent:SetSize(grid.width, grid.height)

    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    local corner = CornerFor(cfg.growDirection or "LEFT")
    local pad = cfg.padding or 5

    -- Outer frame anchor is a plain SetPoint, not an AK-managed field --
    -- live-settable directly, same as any other frame anchor.
    container:ClearAllPoints()
    container:SetPoint(corner, parent, corner, 0, 0)
    AK.SetContainerAnchor(container, corner)
    if FlowDir then
        AK.SetContainerGrowth(container, ToGrowthH(cfg.growDirection or "LEFT"), FlowDir.Down)
    end
    AK.SetContainerPadding(container, 0, 0, 0, 0)
    AK.SetContainerRowWidth(container, grid.rowWidth)

    if isBuff then
        local spells = ns.PAB_ResolveSpells(cfg)
        local sig = table.concat(spells, ",")
        local allChain = (cfg.showAllBuffs ~= false) and BuildChain("HELPFUL", function() return false end) or {}
        if sig ~= buffsSlotSig then
            -- Safe to fully release+rebuild: the default Buffs container
            -- holds only the catch-all group + the spells group, nothing
            -- else shares it (same reasoning as PAB_ReloadCustomBuffBar's
            -- doc comment). The new container's anchor/growth/rowWidth
            -- come from `spec` below -- the live SetContainerAnchor/etc
            -- calls above already ran against the OLD container and are
            -- harmless overhead here. A group's candidateFilters is fixed
            -- at declaration (see ApplyGroupConfig's doc comment), so a
            -- spell-list change requires this release+rebuild -- same as
            -- the old per-spell-slot version did.
            AK.ReleaseContainer(container)
            local _, spec = BuildContainerSpec(parent, cfg, grid)
            AK.RequestContainer(parent, "player", spec, function(newContainer)
                buffsContainer = newContainer
                declared.buffs = {}
                if cfg.showAllBuffs ~= false then
                    ApplyGroupConfig(newContainer, allChain, declared.buffs, STYLE_BUFFS, grid.effectiveMax, pad)
                end
                if #spells > 0 then
                    local includeMap = {}
                    for i = 1, #spells do includeMap[spells[i]] = true end
                    AK.AddGroupToContainer(newContainer, {
                        key = "spells",
                        filter = { "HELPFUL" },
                        style = STYLE_BUFFS,
                        maxFrameCount = grid.effectiveMax,
                        candidateFilters = { includeSpellIDs = includeMap },
                    })
                    newContainer:SetAuraGroupLayout("spells", {
                        elementSpacing = pad, lineSpacing = pad,
                        groupSpacing = pad, groupLineSpacing = pad,
                    })
                    declared.buffs.spells = true
                end
            end)
            buffsSlotSig = sig
        else
            -- Spell list unchanged -- only Show All Buffs and/or grid
            -- (icon size, padding, ...) may have changed. ApplyGroupConfig
            -- is idempotent and self-zeroes the catch-all group when
            -- `allChain` is empty, so this single call covers both on
            -- and off without a separate branch. The spells group (if
            -- declared) isn't part of that chain-based path, so its
            -- maxFrameCount/layout are refreshed here directly.
            ApplyGroupConfig(container, allChain, declared.buffs, STYLE_BUFFS, grid.effectiveMax, pad)
            if declared.buffs.spells then
                container:SetAuraGroupMaxFrameCount("spells", grid.effectiveMax)
                container:SetAuraGroupLayout("spells", {
                    elementSpacing = pad, lineSpacing = pad,
                    groupSpacing = pad, groupLineSpacing = pad,
                })
            end
        end
    else
        local chain = BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, cfg) end)
        ApplyGroupConfig(container, chain, declared.debuffs, STYLE_DEBUFFS, grid.effectiveMax, pad)
    end
end
ns.PAB_ApplyLiveConfig = ApplyLiveConfig

-- Bridge for EllesmereUF:GetGrowDirectionForBar/SetGrowDirectionForBar (see
-- snippet to add in EllesmereUIUnitFrames.lua). Kept here, not inlined
-- there, so the settings-field names stay defined in one place.
--
-- Also handles custom-bar keys ("PAB_CustomBuff_<id>" / "PAB_CustomDebuff_
-- <id>", the unlock-mode keys RegisterPABCustomUnlock registers below) --
-- EUI_UnlockMode.lua's Grow dropdown dispatches to this bridge for ANY
-- barKey prefixed "PAB_", not just the two default bars, so custom bars
-- need their own branch here or the dropdown silently no-ops on them
-- (2026-08-02 fix: originally only recognized the two literal default keys).
-- ns.PAB_ReloadCustomBuffBar/DebuffBar are called (not a direct
-- BuildContainerSpec/SetContainerGrowth call) since the spell/class
-- signature is unchanged and they already re-apply corner + growth on that
-- cheap path -- see those functions' own doc comments.
function ns.PAB_GetGrowDirection(barKey)
    local s = PAB()
    if not s then return "LEFT" end
    if barKey == "PAB_Buffs" then return DefaultBuffsCfg(s).growDirection or "LEFT" end
    if barKey == "PAB_Debuffs" then return DefaultDebuffsCfg(s).growDirection or "LEFT" end
    local buffId = barKey:match("^PAB_CustomBuff_(%d+)$")
    if buffId then
        local bar = ns.PAB_GetCustomBuffBar(tonumber(buffId))
        return bar and (bar.growDirection or "LEFT") or "LEFT"
    end
    local debuffId = barKey:match("^PAB_CustomDebuff_(%d+)$")
    if debuffId then
        local bar = ns.PAB_GetCustomDebuffBar(tonumber(debuffId))
        return bar and (bar.growDirection or "LEFT") or "LEFT"
    end
    return "LEFT"
end

function ns.PAB_SetGrowDirection(barKey, dir)
    local s = PAB()
    if not s then return end
    if barKey == "PAB_Buffs" then
        DefaultBuffsCfg(s).growDirection = dir
        ApplyLiveConfig(true)
        return
    elseif barKey == "PAB_Debuffs" then
        DefaultDebuffsCfg(s).growDirection = dir
        ApplyLiveConfig(false)
        return
    end
    local buffId = barKey:match("^PAB_CustomBuff_(%d+)$")
    if buffId then
        local bar = ns.PAB_GetCustomBuffBar(tonumber(buffId))
        if bar then
            bar.growDirection = dir
            ns.PAB_ReloadCustomBuffBar(bar.id)
        end
        return
    end
    local debuffId = barKey:match("^PAB_CustomDebuff_(%d+)$")
    if debuffId then
        local bar = ns.PAB_GetCustomDebuffBar(tonumber(debuffId))
        if bar then
            bar.growDirection = dir
            ns.PAB_ReloadCustomDebuffBar(bar.id)
        end
        return
    end
end

-------------------------------------------------------------------------------
--  Custom bars (free bar creator)
--
--  Buffs: SpellID-based (BM2 model) -- customBuffBars entries carry
--  filters={[filterId]=true}, spells={id,...}, ownOnlySpells={[id]=bool}.
--  Same shape and same PAB_ResolveSpells() union the default Buffs bar
--  uses as of 2026-08-01 (see CreateBars/ApplyLiveConfig above) -- default
--  Buffs and custom Buff Bars are now ONE model, not two. Resolution/
--  rendering (one candidateFilters-restricted GROUP into the bar's own
--  dedicated container, signature-gated rebuild -- see PAB_ReloadCustomBuffBar's
--  own doc comment for why this is a group, not per-spell slots) lives here
--  for custom bars; this section is the data layer for the CRUD, engine
--  wiring is further down.
--
--  Debuffs: category-based (DM model, same as RaidFrames) -- customDebuffBars
--  entries carry classFilters={[classKey]=true} and render through the
--  EXISTING BuildChain/ApplyGroupConfig path used by the two default groups,
--  no new engine machinery needed.
--
--  ID scheme mirrors ns.BM2_AddFilter (EUI_RaidFrames_BuffManager2.lua):
--  a single monotonically increasing counter, never reused, so deleted
--  bars' engine-side declarations (which are ADD-ONLY on the container,
--  see ApplyGroupConfig's doc comment) never collide with a later bar.
-------------------------------------------------------------------------------

-- Ensures db.profile.playerAuraBars itself exists before writing to it --
-- PAB() alone is read-only and may return nil (Bug 3 from the Step E
-- history: reading via `PAB() or {}` silently wrote into a throwaway table
-- that never persisted). Only CRUD (write) functions call this.
local function PABEnsure()
    local db = ns.db
    if not (db and db.profile) then return nil end
    db.profile.playerAuraBars = db.profile.playerAuraBars or {}
    return db.profile.playerAuraBars
end

local function NextBarId(s)
    s.nextBarId = (s.nextBarId or 1)
    local id = s.nextBarId
    s.nextBarId = id + 1
    return id
end

-------------------------------------------------------------------------------
--  Buff Filters (BM2-style named spell sets)
--
--  Global registry (db.profile.playerAuraBars.pabFilters), same shape as
--  RaidFrames' ns.BM2_Filters storage (EUI_RaidFrames_BuffManager2.lua:
--  b.filters = { nextId = 1, list = {} }) -- id/name/nextId counter pattern
--  mirrored 1:1. User-created filters are fully renameable/deletable; the
--  10 curated BM2 presets (Defensives, Raid CDs, Externals, etc.) imported
--  via ns.PAB_ImportBM2Filters carry `f.preset = true` -- same protected-
--  preset flag as BM2_Filters, not renameable/deletable (see the Filter
--  Editor's sidebar/detail-header guards). Spell-level checkboxes within a
--  preset filter stay fully editable either way -- only the filter's own
--  name/existence is protected.
--
--  Referenced by id from any buff-side cfg's `filters` table
--  ([filterId]=true) -- the default Buffs bar and every custom buff bar
--  share ONE filter registry, same as BM2 indicators sharing one filter
--  list. Own-only tracking (BM2's ownFilters/ownExtras) is intentionally
--  NOT implemented here -- out of scope for this pass, not requested;
--  bar.ownOnlySpells stays reserved-but-unused, same status as before.
-------------------------------------------------------------------------------

local function FilterStore(s)
    s.pabFilters = s.pabFilters or { nextId = 1, list = {} }
    return s.pabFilters
end

function ns.PAB_Filters()
    local s = PAB()
    local store = s and s.pabFilters
    return store and store.list or nil
end

function ns.PAB_GetFilter(id)
    local list = ns.PAB_Filters()
    if not list then return nil end
    for i = 1, #list do
        if list[i].id == id then return list[i] end
    end
end

function ns.PAB_AddFilter(name)
    local s = PABEnsure()
    if not s then return nil end
    local store = FilterStore(s)
    local f = { id = store.nextId, name = name or "New Filter", spells = {} }
    store.nextId = store.nextId + 1
    store.list[#store.list + 1] = f
    return f
end

function ns.PAB_RenameFilter(id, name)
    local f = ns.PAB_GetFilter(id)
    if f and name and name ~= "" then f.name = name end
end

-- Also strips the filter's assignment from every buff-side cfg that could
-- reference it (default Buffs bar + every custom buff bar) -- mirrors
-- BM2_DeleteFilter stripping ind.filters[id] off every indicator.
function ns.PAB_DeleteFilter(id)
    local s = PAB()
    if not (s and s.pabFilters) then return end
    local list = s.pabFilters.list
    for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i) end
    end
    if s.defaultBuffs and s.defaultBuffs.filters then s.defaultBuffs.filters[id] = nil end
    local customBuffBars = s.customBuffBars
    if customBuffBars then
        for i = 1, #customBuffBars do
            local bar = customBuffBars[i]
            if bar.filters then bar.filters[id] = nil end
        end
    end
end

-- Checkbox state for one spell within one filter. state=nil removes the
-- spell entirely (matches BM2_SetSpellState's custom-spell-removal path --
-- every PAB filter spell is "custom", there is no curated/preset spell to
-- fall back to).
function ns.PAB_SetSpellState(filterId, spellID, state)
    local f = ns.PAB_GetFilter(filterId)
    if not f then return end
    if state == nil then
        f.spells[spellID] = nil
    else
        f.spells[spellID] = state and true or false
    end
end

function ns.PAB_AddSpellToFilter(filterId, spellID)
    local f = ns.PAB_GetFilter(filterId)
    if not (f and spellID and spellID > 0) then return false end
    if f.spells[spellID] ~= nil then return false end -- already present
    f.spells[spellID] = true
    return true
end

-- Union of a buff-side cfg's direct spells (cfg.spells) + the enabled
-- spells of every filter it references (cfg.filters). Mirrors
-- BM2_ResolveSpellsOwn's Add()/set-union logic, minus own-only tracking
-- (see doc comment above). Sorted so the caller's signature diffing stays
-- deterministic (same reasoning as CustomBuffSpellSignature).
function ns.PAB_ResolveSpells(cfg)
    local set = {}
    local spells = cfg.spells
    if spells then
        for i = 1, #spells do set[spells[i]] = true end
    end
    local filters = cfg.filters
    if filters then
        for filterId in pairs(filters) do
            local f = ns.PAB_GetFilter(filterId)
            if f then
                for id, on in pairs(f.spells) do
                    if on then set[id] = true end
                end
            end
        end
    end
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

function ns.PAB_CustomBuffBars()
    local s = PAB()
    return s and s.customBuffBars or nil
end

-------------------------------------------------------------------------------
--  Buff Manager filter import (Joel, 2026-08-01): all 10 curated preset
--  filters from RaidFrames' Buff Manager 2 (Defensives, Raid CDs,
--  Externals, Core/Lesser Healing Buffs, Support, Offensive CDs, Movement,
--  Utility, Consumables) -- ported as a starting point for PAB Filters.
--
--  Spell IDs extracted programmatically from EUI_RaidFrames_BuffManager2
--  .lua's PRESET_FILTERS + DEFAULT_FILTER_SPELLS tables (primary ids +
--  their `alts` flattened into one flat list each -- PAB's Filters have no
--  primary/alt grouping concept, every id is just its own checkbox row) --
--  NOT retyped by hand, to rule out transcription errors. `disabled`
--  entries are imported too (matching BM2's own list, which keeps them
--  visible-but-unchecked) but start unchecked here as well.
-------------------------------------------------------------------------------

-- Display-only hint: which class a curated (imported) spell belongs to,
-- so the Filter Editor can group/color rows the same way BM2's does.
-- Purely cosmetic -- PAB_ResolveSpells/PAB_SetSpellState never consult
-- this table, a filter's spells are always just a flat {id=bool} set.
-- Extracted from the same PRESET_FILTERS/DEFAULT_FILTER_SPELLS source as
-- BM2_FILTER_SEED below (254 unique entries, "ALL"-class spells omitted
-- since those don't get a class header in BM2 either).
local SPELL_CLASS_HINTS = {
    [47585] = "PRIEST",
    [404381] = "EVOKER",
    [427912] = "DEMONHUNTER",
    [258920] = "DEMONHUNTER",
    [48792] = "DEATHKNIGHT",
    [184662] = "PALADIN",
    [108416] = "WARLOCK",
    [114216] = "PRIEST",
    [114214] = "PRIEST",
    [193065] = "PRIEST",
    [1266616] = "DEMONHUNTER",
    [394933] = "DEMONHUNTER",
    [212800] = "DEMONHUNTER",
    [192081] = "DRUID",
    [374349] = "EVOKER",
    [472708] = "HUNTER",
    [184364] = "WARRIOR",
    [498] = "PALADIN",
    [403876] = "PALADIN",
    [22842] = "DRUID",
    [235450] = "MAGE",
    [31224] = "ROGUE",
    [147833] = "WARRIOR",
    [11426] = "MAGE",
    [45438] = "MAGE",
    [414658] = "MAGE",
    [49039] = "DEATHKNIGHT",
    [642] = "PALADIN",
    [264735] = "HUNTER",
    [61336] = "DRUID",
    [186265] = "HUNTER",
    [5277] = "ROGUE",
    [385391] = "WARRIOR",
    [393903] = "DRUID",
    [45242] = "PRIEST",
    [426401] = "PRIEST",
    [118038] = "WARRIOR",
    [104773] = "WARLOCK",
    [363916] = "EVOKER",
    [1966] = "ROGUE",
    [108271] = "SHAMAN",
    [190456] = "WARRIOR",
    [1277297] = "WARRIOR",
    [22812] = "DRUID",
    [122783] = "MONK",
    [48707] = "DEATHKNIGHT",
    [444741] = "DEATHKNIGHT",
    [442715] = "DEMONHUNTER",
    [342246] = "MAGE",
    [586] = "PRIEST",
    [19236] = "PRIEST",
    [235313] = "MAGE",
    [115203] = "MONK",
    [120954] = "MONK",
    [145629] = "DEATHKNIGHT",
    [51052] = "DEATHKNIGHT",
    [209426] = "DEMONHUNTER",
    [196718] = "DEMONHUNTER",
    [374227] = "EVOKER",
    [359816] = "EVOKER",
    [362361] = "EVOKER",
    [81782] = "PRIEST",
    [62618] = "PRIEST",
    [740] = "DRUID",
    [157982] = "DRUID",
    [1264623] = "DRUID",
    [31821] = "PALADIN",
    [317929] = "PALADIN",
    [363534] = "EVOKER",
    [64843] = "PRIEST",
    [64844] = "PRIEST",
    [97463] = "WARRIOR",
    [97462] = "WARRIOR",
    [325174] = "SHAMAN",
    [98008] = "SHAMAN",
    [102342] = "DRUID",
    [116849] = "MONK",
    [33206] = "PRIEST",
    [6940] = "PALADIN",
    [357170] = "EVOKER",
    [387804] = "PALADIN",
    [53480] = "HUNTER",
    [204018] = "PALADIN",
    [47788] = "PRIEST",
    [1022] = "PALADIN",
    [1309794] = "PALADIN",
    [156910] = "PALADIN",
    [376788] = "EVOKER",
    [409895] = "EVOKER",
    [474754] = "DRUID",
    [474750] = "DRUID",
    [155777] = "DRUID",
    [48438] = "DRUID",
    [419344] = "DRUID",
    [450769] = "MONK",
    [450521] = "MONK",
    [450711] = "MONK",
    [450526] = "MONK",
    [450531] = "MONK",
    [33763] = "DRUID",
    [419207] = "DRUID",
    [1227806] = "DRUID",
    [1291636] = "EVOKER",
    [409678] = "EVOKER",
    [1244893] = "PALADIN",
    [1245369] = "PALADIN",
    [1278914] = "DRUID",
    [8936] = "DRUID",
    [419287] = "DRUID",
    [53563] = "PALADIN",
    [355941] = "EVOKER",
    [355936] = "EVOKER",
    [382614] = "EVOKER",
    [432502] = "PALADIN",
    [363502] = "EVOKER",
    [156322] = "PALADIN",
    [461432] = "PALADIN",
    [207400] = "SHAMAN",
    [450805] = "MONK",
    [1253593] = "PRIEST",
    [1300009] = "PRIEST",
    [774] = "DRUID",
    [419204] = "DRUID",
    [444490] = "SHAMAN",
    [383648] = "SHAMAN",
    [974] = "SHAMAN",
    [194384] = "PRIEST",
    [467281] = "MONK",
    [427296] = "MONK",
    [453846] = "PRIEST",
    [453850] = "PRIEST",
    [439530] = "DRUID",
    [77489] = "PRIEST",
    [367364] = "EVOKER",
    [139] = "PRIEST",
    [17] = "PRIEST",
    [1246768] = "PRIEST",
    [1254306] = "PRIEST",
    [1300008] = "PRIEST",
    [41635] = "PRIEST",
    [469703] = "PALADIN",
    [61295] = "SHAMAN",
    [431381] = "PALADIN",
    [431522] = "PALADIN",
    [200025] = "PALADIN",
    [115175] = "MONK",
    [1260617] = "MONK",
    [198533] = "MONK",
    [119611] = "MONK",
    [388513] = "MONK",
    [124682] = "MONK",
    [364343] = "EVOKER",
    [1292922] = "MONK",
    [373862] = "EVOKER",
    [366155] = "EVOKER",
    [445740] = "EVOKER",
    [373267] = "EVOKER",
    [360827] = "EVOKER",
    [410263] = "EVOKER",
    [395152] = "EVOKER",
    [395296] = "EVOKER",
    [413984] = "EVOKER",
    [369459] = "EVOKER",
    [410089] = "EVOKER",
    [106951] = "DRUID",
    [191427] = "DEMONHUNTER",
    [187827] = "DEMONHUNTER",
    [321067] = "DEMONHUNTER",
    [321068] = "DEMONHUNTER",
    [186254] = "HUNTER",
    [1235388] = "HUNTER",
    [1285912] = "HUNTER",
    [19574] = "HUNTER",
    [190319] = "MAGE",
    [50334] = "DRUID",
    [1249658] = "DEATHKNIGHT",
    [152279] = "DEATHKNIGHT",
    [471306] = "DEMONHUNTER",
    [1217605] = "DEMONHUNTER",
    [1225789] = "DEMONHUNTER",
    [473671] = "DEMONHUNTER",
    [1217607] = "DEMONHUNTER",
    [42650] = "DEATHKNIGHT",
    [10060] = "PRIEST",
    [365350] = "MAGE",
    [107574] = "WARRIOR",
    [194223] = "DRUID",
    [375087] = "EVOKER",
    [114050] = "SHAMAN",
    [114051] = "SHAMAN",
    [114052] = "SHAMAN",
    [288613] = "HUNTER",
    [403631] = "EVOKER",
    [1249625] = "MONK",
    [79206] = "SHAMAN",
    [192082] = "SHAMAN",
    [444754] = "MAGE",
    [443569] = "MONK",
    [48265] = "DEATHKNIGHT",
    [252216] = "DRUID",
    [118922] = "HUNTER",
    [212552] = "DEATHKNIGHT",
    [58875] = "SHAMAN",
    [90328] = "SHAMAN",
    [119085] = "MONK",
    [111400] = "WARLOCK",
    [276111] = "PALADIN",
    [221886] = "PALADIN",
    [221883] = "PALADIN",
    [276112] = "PALADIN",
    [254474] = "PALADIN",
    [254472] = "PALADIN",
    [254471] = "PALADIN",
    [221885] = "PALADIN",
    [254473] = "PALADIN",
    [363608] = "PALADIN",
    [294133] = "PALADIN",
    [221887] = "PALADIN",
    [1272854] = "PALADIN",
    [453804] = "PALADIN",
    [1253874] = "PALADIN",
    [1253723] = "PALADIN",
    [1253881] = "PALADIN",
    [101545] = "MONK",
    [186257] = "HUNTER",
    [186258] = "HUNTER",
    [202164] = "WARRIOR",
    [121557] = "PRIEST",
    [2983] = "ROGUE",
    [1850] = "DRUID",
    [61684] = "DRUID",
    [106898] = "DRUID",
    [77761] = "DRUID",
    [77764] = "DRUID",
    [3714] = "DEATHKNIGHT",
    [406732] = "EVOKER",
    [406789] = "EVOKER",
    [390386] = "EVOKER",
    [466904] = "HUNTER",
    [115834] = "ROGUE",
    [114018] = "ROGUE",
    [408233] = "EVOKER",
    [2825] = "SHAMAN",
    [116841] = "MONK",
    [29166] = "DRUID",
    [1044] = "PALADIN",
    [299256] = "PALADIN",
    [80353] = "MAGE",
    [264667] = "HUNTER",
    [357650] = "HUNTER",
    [32182] = "SHAMAN",
    [1224810] = "HUNTER",
    [54216] = "HUNTER",
    [62305] = "HUNTER",
}
ns.PAB_SPELL_CLASS_HINTS = SPELL_CLASS_HINTS

local BM2_FILTER_SEED = {
    { name = "Defensives",
      enabled = {498, 586, 642, 1966, 5277, 19236, 22812, 22842, 31224, 45438, 47585, 48707, 48792, 61336, 104773, 108271, 108416, 115203, 118038, 120954, 122783, 147833, 184364, 186265, 190456, 193065, 212800, 264735, 342246, 363916, 374349, 385391, 403876, 404381, 414658, 444741, 1277297},
      disabled = {11426, 45242, 49039, 114214, 114216, 184662, 192081, 235313, 235450, 258920, 393903, 394933, 426401, 427912, 442715, 472708, 1266616} },
    { name = "Raid CDs",
      enabled = {31821, 51052, 62618, 81782, 97462, 97463, 98008, 145629, 196718, 209426, 317929, 325174, 374227},
      disabled = {740, 64843, 64844, 157982, 359816, 362361, 363534, 1264623} },
    { name = "Externals",
      enabled = {1022, 6940, 33206, 47788, 53480, 102342, 116849, 204018, 357170, 387804, 1309794},
      disabled = {} },
    { name = "Core Healing Buffs",
      enabled = {974, 33763, 53563, 119611, 156910, 194384, 200025, 364343, 373267, 383648, 419207, 474750, 474754, 1227806, 1244893, 1245369},
      disabled = {17, 139, 774, 8936, 41635, 48438, 61295, 77489, 115175, 124682, 155777, 156322, 198533, 207400, 355936, 355941, 363502, 366155, 367364, 373862, 376788, 382614, 388513, 409678, 409895, 419204, 419287, 419344, 427296, 431381, 431522, 432502, 439530, 444490, 445740, 450521, 450526, 450531, 450711, 450769, 450805, 453846, 453850, 461432, 467281, 469703, 1246768, 1253593, 1254306, 1260617, 1278914, 1291636, 1292922, 1300008, 1300009} },
    { name = "Lesser Healing Buffs",
      enabled = {17, 139, 774, 8936, 41635, 48438, 61295, 77489, 115175, 124682, 155777, 156322, 198533, 355936, 355941, 366155, 367364, 373267, 376788, 382614, 409895, 419204, 419287, 419344, 431381, 431522, 432502, 444490, 450521, 450526, 450531, 450711, 450769, 461432, 469703, 1246768, 1253593, 1254306, 1260617, 1278914, 1292922, 1300008, 1300009},
      disabled = {974, 33763, 53563, 119611, 156910, 194384, 200025, 207400, 363502, 364343, 373862, 383648, 388513, 409678, 419207, 427296, 439530, 445740, 450805, 453846, 453850, 467281, 474750, 474754, 1227806, 1244893, 1245369, 1291636} },
    { name = "Support",
      enabled = {360827, 395152, 395296, 410089},
      disabled = {369459, 410263, 413984} },
    { name = "Offensive CDs",
      enabled = {10060, 19574, 42650, 50334, 106951, 107574, 114050, 114051, 114052, 152279, 186254, 187827, 190319, 191427, 194223, 288613, 321067, 321068, 365350, 375087, 403631, 471306, 473671, 1217605, 1217607, 1225789, 1235388, 1249625, 1249658, 1285912},
      disabled = {} },
    { name = "Movement",
      enabled = {1850, 2983, 48265, 58875, 61684, 77761, 77764, 79206, 90328, 106898, 111400, 118922, 119085, 121557, 186257, 186258, 192082, 202164, 212552, 221883, 221885, 221886, 221887, 252216, 254471, 254472, 254473, 254474, 276111, 276112, 294133, 363608, 443569, 444754, 453804, 1253723, 1253874, 1253881, 1272854},
      disabled = {101545} },
    { name = "Utility",
      enabled = {1044, 3714, 29166, 54216, 62305, 114018, 115834, 116841, 299256, 406732, 406789, 1224810},
      disabled = {2825, 32182, 80353, 264667, 357650, 390386, 408233, 466904} },
    { name = "Consumables",
      enabled = {1236616, 1236994, 1236998, 1239479},
      disabled = {} },
}

-- Idempotent: skips any seed entry whose exact name already exists as a
-- filter (so re-clicking Import doesn't create duplicates). Returns the
-- number of filters actually created.
-- Equivalent of ns.BM2_AllPresetSpells() -- every spell ID across all 10
-- curated presets (enabled AND disabled entries both count, same as BM2's
-- own `for id in pairs(spells)`, which doesn't check the disabled flag
-- either). One honest divergence from a byte-identical port: BM2_FILTER_
-- SEED already has `alts` flattened into its enabled/disabled lists (see
-- that table's own doc comment), so this returns a superset of real
-- spell IDs BM2_AllPresetSpells would -- more complete for PAB's purposes
-- (alts ARE valid trackable buff spell IDs), not a bug.
function ns.PAB_AllPresetSpells()
    local set = {}
    for i = 1, #BM2_FILTER_SEED do
        local seed = BM2_FILTER_SEED[i]
        for j = 1, #seed.enabled do set[seed.enabled[j]] = true end
        for j = 1, #seed.disabled do set[seed.disabled[j]] = true end
    end
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

function ns.PAB_ImportBM2Filters()
    local byName = {}
    local list = ns.PAB_Filters() or {}
    for i = 1, #list do byName[list[i].name] = list[i] end

    local created = 0
    for i = 1, #BM2_FILTER_SEED do
        local seed = BM2_FILTER_SEED[i]
        local f = byName[seed.name]
        if not f then
            f = ns.PAB_AddFilter(seed.name)
            if f then
                for j = 1, #seed.enabled do f.spells[seed.enabled[j]] = true end
                for j = 1, #seed.disabled do f.spells[seed.disabled[j]] = false end
                created = created + 1
            end
        end
        -- Retroactively flags filters imported before f.preset existed
        -- (idempotent-by-name previously meant they were silently skipped
        -- forever and never got the protection flag) -- runs every call,
        -- not just on fresh creation.
        if f then f.preset = true end
    end
    return created
end

function ns.PAB_CustomDebuffBars()
    local s = PAB()
    return s and s.customDebuffBars or nil
end

function ns.PAB_GetCustomBuffBar(id)
    local list = ns.PAB_CustomBuffBars()
    if not list then return nil end
    for i = 1, #list do
        if list[i].id == id then return list[i] end
    end
end

function ns.PAB_GetCustomDebuffBar(id)
    local list = ns.PAB_CustomDebuffBars()
    if not list then return nil end
    for i = 1, #list do
        if list[i].id == id then return list[i] end
    end
end

-- Bar objects (both kinds) also carry the same shared+category cfg fields
-- as DefaultBuffsCfg/DefaultDebuffsCfg (iconSize, durationShow/stackShow,
-- durationPosition/TextSize/OffsetX/Y/ColorR/G/B, stackPosition/TextSize/
-- OffsetX/Y/ColorR/G/B; buff/debuff bars additionally borderSize/R/G/B/A,
-- iconZoom, padding, iconsPerRow, maxRows, maxTotal; debuff bars additionally
-- dispelColorMagic/Curse/Disease/Poison/Bleed) -- NOT pre-populated here,
-- same as DefaultBuffsCfg/DefaultDebuffsCfg
-- starting as {}. BuildStyle/ComputeGrid apply the same `or <default>`
-- fallbacks regardless of whether the field is simply unset or the table
-- was just created, so a fresh bar renders with sane defaults immediately
-- and the Options UI only ever needs to write the fields the user touches.
function ns.PAB_AddCustomBuffBar(name)
    local s = PABEnsure()
    if not s then return nil end
    s.customBuffBars = s.customBuffBars or {}
    local bar = {
        id = NextBarId(s),
        name = name or "New Buff Bar",
        enabled = true,
        filters = {},         -- [filterId] = true (BM2-style assigned filters)
        spells = {},           -- {spellID, ...} direct/custom spells
        ownOnlySpells = {},    -- [spellID] = bool
        growDirection = "LEFT",
        -- Starting grid (2026-08-02, Joel's chosen values): a compact
        -- single row, distinct from the default bars' own ComputeGrid
        -- fallback (11x3 for buffs) -- a freshly-added custom bar is meant
        -- to start small, not inherit the default bar's larger grid.
        iconsPerRow = 8,
        maxRows = 1,
        maxTotal = 8,
    }
    s.customBuffBars[#s.customBuffBars + 1] = bar
    return bar
end

function ns.PAB_AddCustomDebuffBar(name)
    local s = PABEnsure()
    if not s then return nil end
    s.customDebuffBars = s.customDebuffBars or {}
    local bar = {
        id = NextBarId(s),
        name = name or "New Debuff Bar",
        enabled = true,
        classFilters = {},    -- [classKey] = true, same vocabulary as BuildChain
        growDirection = "LEFT",
        -- Same starting-grid reasoning as PAB_AddCustomBuffBar above.
        iconsPerRow = 8,
        maxRows = 1,
        maxTotal = 8,
    }
    s.customDebuffBars[#s.customDebuffBars + 1] = bar
    return bar
end

-- Deletion only strips the DB entry; it deliberately does NOT try to remove
-- the bar's engine-side group/slots (containers are add-only, see
-- ApplyGroupConfig doc comment). The engine-wiring layer must instead detect
-- the missing DB entry and set maxFrameCount = 0 / hide the bar's frames,
-- mirroring how disabled default groups are handled today.
function ns.PAB_DeleteCustomBuffBar(id)
    local s = PABEnsure()
    if not (s and s.customBuffBars) then return end
    for i = #s.customBuffBars, 1, -1 do
        if s.customBuffBars[i].id == id then table.remove(s.customBuffBars, i) end
    end
end

function ns.PAB_DeleteCustomDebuffBar(id)
    local s = PABEnsure()
    if not (s and s.customDebuffBars) then return end
    for i = #s.customDebuffBars, 1, -1 do
        if s.customDebuffBars[i].id == id then table.remove(s.customDebuffBars, i) end
    end
end

-------------------------------------------------------------------------------
--  Custom bars -- engine wiring
--
--  Debuffs: one dedicated container per bar (own parent frame, own
--  AK.RequestContainer), groups declared through the SAME BuildChain/
--  ApplyGroupConfig path the two default bars use -- just fed the bar
--  itself as cfg (bar objects share DefaultBuffsCfg/DefaultDebuffsCfg's
--  field shape, see the CRUD section above). Nothing new engine-side: this
--  is "one more container using an already-proven path."
--
--  Buffs: SpellID-based (per Joel: no class-token checkboxes for custom
--  buff bars -- selection is via filters/direct spells only). Each bar's
--  container holds ONE GROUP for that bar's resolved spell set
--  (candidateFilters.includeSpellIDs, map shape {[id]=true} -- verified
--  against EUI_RaidFrames_AuraContainers.lua's BmIncludeMap/BmSimpleCand
--  and EUI_ResourceBars_EbonMight121.lua). 2026-08-02: this was originally
--  one AK.AddAuraSlot per spellID, but field-verified instrumentation
--  showed AK's flow layout only positions GROUP content -- slots never got
--  a real anchor point (GetPoint(1) nil) and never rendered, even
--  unrestricted ones. See CreateBars' matching doc comment for the full
--  writeup. Still flows through the SAME ComputeGrid/BuildContainerSpec
--  grid (padding/iconsPerRow/maxRows/maxTotal/growDirection) as every
--  other bar. Unlike RaidFrames' Buff Manager -- where custom-spell content
--  shares a container with structurally-stable chain/simple groups, so
--  only a dedicated sub-container gets released on a spell-list change
--  (see BmSignature / the "Release the SLOTS container only" comment) -- a
--  custom buff bar's container here holds nothing else. Releasing and
--  rebuilding the WHOLE bar container on a spell-list change is therefore
--  safe: there is no other shared group on it to lose frames. Deliberate
--  simplification of the RaidFrames pattern for PAB's dedicated-per-bar-
--  container design, not a partial copy of it.
--
--  2026-08-01: bar.filters is now resolved (see ns.PAB_ResolveSpells and
--  the Filter Editor, EUI_PlayerAuraBars_ManagerPages.lua) -- the signature
--  below folds resolved filter spells in alongside bar.spells, same as the
--  default Buffs bar. bar.ownOnlySpells remains UNCONSULTED -- own-only
--  tracking (BM2's ownFilters/ownExtras) was explicitly out of scope for
--  this pass, not a partial miss; add it the same way BM2 does if wanted.
-------------------------------------------------------------------------------

local customBuffParents, customBuffContainers, customBuffSig, customBuffDeclared = {}, {}, {}, {}
local customDebuffParents, customDebuffContainers, customDebuffDeclared = {}, {}, {}

-- Tracks which unlock-mode keys are currently registered for custom bars,
-- so RegisterPABCustomUnlock can retire keys for bars deleted since the
-- previous call. See that function's doc comment.
local pabRegisteredCustomBuffKeys, pabRegisteredCustomDebuffKeys

local function CustomBuffStyleKey(barId) return "playerAuraBars_customBuff_" .. barId end
local function CustomDebuffStyleKey(barId) return "playerAuraBars_customDebuff_" .. barId end

-- Default anchor for a bar with no saved position yet -- the SAME fixed
-- spot (screen center, slight upward offset) for every bar, not staggered
-- by barId (2026-08-02, Joel's explicit request): since this is only ever
-- read as a fallback for a bar that has no bar.pos, a bar that's been
-- dragged elsewhere keeps its own saved position regardless, while any
-- bar still untouched -- 1st, 2nd, 3rd, ... -- always starts from this
-- same default until the user moves it.
local function DefaultCustomPos(barId)
    return { point = "CENTER", relPoint = "CENTER", x = 0, y = 80 }
end

-- Applies bar.pos (or the default) to a custom bar's parent frame. Mirrors
-- ApplyBarPosition for the two default bars -- kept separate since custom
-- bars key off bar.pos on the bar object, not a fixed s[BarPositionKey]
-- slot, but the SetPoint logic itself is identical.
local function ApplyCustomBarPosition(parent, bar, barId)
    local pos = bar.pos or DefaultCustomPos(barId)
    parent:ClearAllPoints()
    parent:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
end

local function CustomBuffSpellSignature(spells)
    return table.concat(spells, ",")
end

-- Unlock-mode registration for custom bars, patterned on RegisterPABUnlock
-- (the two default bars) for the per-element schema, and on
-- EllesmereUICdmBuffBars.lua's ns.RegisterTBBUnlockElements for the "dynamic
-- list" shape: rebuilds the FULL element list (every currently-persisted
-- custom buff + debuff bar) on every call and re-registers it, rather than
-- trying to diff adds/removes incrementally. Cheap at PAB's expected bar
-- counts, and it means a freshly-added bar just appears next call with no
-- separate registration path.
--
-- Unlike TBB (index-keyed, so a deleted mid-list bar reshuffles every
-- higher key and its links), PAB custom bars carry a permanent NextBarId
-- that's never reused or renumbered, so the "never unregister, just hide"
-- caution from TBB's doc comment doesn't apply here: a genuinely deleted
-- bar's key is retired for good, so calling UnregisterUnlockElement for it
-- is correct, not lossy. Still noResize/noAnchorTarget for the same reason
-- as the default bars: AuraKit sizes the container itself, and a
-- dynamically-resizing frame is a bad anchor target for other elements.
local function RegisterPABCustomUnlock()
    if not (EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local MK = EllesmereUI.MakeUnlockElement

    local prevBuffKeys, prevDebuffKeys = pabRegisteredCustomBuffKeys, pabRegisteredCustomDebuffKeys
    pabRegisteredCustomBuffKeys, pabRegisteredCustomDebuffKeys = {}, {}

    local function MakeCustomBarElement(barId, bar, order, isBuff, parents)
        local key = (isBuff and "PAB_CustomBuff_" or "PAB_CustomDebuff_") .. barId
        return key, MK({
            key = key,
            label = "PAB: " .. (bar.name or (isBuff and "Buff Bar" or "Debuff Bar")),
            group = "Player Aura Bars",
            order = order,
            noResize = true,
            noAnchorTarget = true,
            isHidden = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                return not b or b.enabled == false
            end,
            getFrame = function() return parents[barId] end,
            getSize = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                if not b then return 32, 32 end
                local grid = ComputeGrid(isBuff, b)
                return grid.width, grid.height
            end,
            savePos = function(_, point, relPoint, x, y)
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                if not b then return end
                b.pos = { point = point, relPoint = relPoint or point, x = x, y = y }
            end,
            loadPos = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                return b and b.pos or nil
            end,
            clearPos = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                if b then b.pos = nil end
            end,
            applyPos = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                local parent = parents[barId]
                if b and parent then ApplyCustomBarPosition(parent, b, barId) end
            end,
        })
    end

    local elements = {}
    local buffList = ns.PAB_CustomBuffBars()
    if buffList then
        for i = 1, #buffList do
            local bar = buffList[i]
            local key, el = MakeCustomBarElement(bar.id, bar, 702, true, customBuffParents)
            elements[#elements + 1] = el
            pabRegisteredCustomBuffKeys[key] = true
        end
    end
    local debuffList = ns.PAB_CustomDebuffBars()
    if debuffList then
        for i = 1, #debuffList do
            local bar = debuffList[i]
            local key, el = MakeCustomBarElement(bar.id, bar, 703, false, customDebuffParents)
            elements[#elements + 1] = el
            pabRegisteredCustomDebuffKeys[key] = true
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIUnitFrames")
    end

    -- Retire keys for bars deleted since the last call -- safe here (unlike
    -- TBB) because PAB custom-bar ids are permanent, see doc comment above.
    if prevBuffKeys then
        for key in pairs(prevBuffKeys) do
            if not pabRegisteredCustomBuffKeys[key] then EllesmereUI:UnregisterUnlockElement(key) end
        end
    end
    if prevDebuffKeys then
        for key in pairs(prevDebuffKeys) do
            if not pabRegisteredCustomDebuffKeys[key] then EllesmereUI:UnregisterUnlockElement(key) end
        end
    end
end
ns.PAB_RegisterCustomUnlock = RegisterPABCustomUnlock

-- Public hook for the Options UI: (re)builds one custom buff bar's engine
-- state to match its current DB entry. Safe to call after ANY change to
-- that bar (spell add/remove, any cfg field, enable toggle, delete) -- it
-- diffs the spell signature itself and only pays for a container rebuild
-- when the spell list actually changed; everything else (style, grid,
-- anchor) is cheap to just re-apply every time, same as the default bars'
-- RestyleBars/ApplyLiveConfig split does across two calls -- one combined
-- call here keeps the Options UI's call sites simple.
--
-- Wrapped below so unlock-mode registration stays in sync on every exit
-- path (deleted, disabled, spell-list-unchanged, and full rebuild) without
-- duplicating the RegisterPABCustomUnlock() call at each of this function's
-- several early returns.
local function ReloadCustomBuffBarImpl(barId)
    AK = AK or (EllesmereUI and EllesmereUI.AuraKit)
    if not AK then return end

    local bar = ns.PAB_GetCustomBuffBar(barId)
    if not bar then
        -- Deleted: release the container (frees its slot-button tracking,
        -- see AK.ReleaseContainer's doc comment -- the engine frames
        -- themselves are never destroyed, same as everywhere else in AK)
        -- and hide the now-orphaned parent frame.
        if customBuffContainers[barId] then AK.ReleaseContainer(customBuffContainers[barId]) end
        if customBuffParents[barId] then customBuffParents[barId]:Hide() end
        customBuffContainers[barId], customBuffParents[barId], customBuffSig[barId], customBuffDeclared[barId] = nil, nil, nil, nil
        return
    end

    local styleKey = CustomBuffStyleKey(barId)
    AK.styles[styleKey] = BuildStyle(true, bar)

    local parent = customBuffParents[barId]
    if not parent then
        parent = CreateFrame("Frame", "EllesmereUIPlayerAuraBars_CustomBuff" .. barId, UIParent)
        customBuffParents[barId] = parent
    end
    ApplyCustomBarPosition(parent, bar, barId)
    parent:SetShown(bar.enabled ~= false)
    if bar.enabled == false then return end

    local grid = ComputeGrid(true, bar)
    parent:SetSize(grid.width, grid.height)

    local spells = ns.PAB_ResolveSpells(bar)
    local sig = CustomBuffSpellSignature(spells)
    -- Show All Buffs: functional for custom buff bars too (2026-08-02 fix --
    -- bar.showAllBuffs previously wasn't read anywhere in this function, so
    -- the UI toggle had no engine effect). Mirrors the default Buffs bar's
    -- catch-all group exactly (BuildChain zero-classes trick, "all" key),
    -- via the same ApplyGroupConfig path used for custom debuff bars'
    -- category chain -- ApplyGroupConfig is generic over any {key,tokens}
    -- chain, not debuff-specific.
    local allChain = (bar.showAllBuffs ~= false) and BuildChain("HELPFUL", function() return false end) or {}

    if customBuffContainers[barId] then
        -- Style/grid-only change (icon size, padding, grow direction, ...):
        -- the container already exists and the spell list hasn't changed,
        -- so just re-apply the live anchor/growth/rowWidth, same fields
        -- ApplyLiveConfig live-updates for the default bars.
        local corner, _ = BuildContainerSpec(parent, bar, grid)
        local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
        local container = customBuffContainers[barId]
        container:ClearAllPoints()
        container:SetPoint(corner, parent, corner, 0, 0)
        AK.SetContainerAnchor(container, corner)
        if FlowDir then
            AK.SetContainerGrowth(container, ToGrowthH(bar.growDirection or "LEFT"), FlowDir.Down)
        end
        AK.SetContainerPadding(container, 0, 0, 0, 0)
        AK.SetContainerRowWidth(container, grid.rowWidth)

        if customBuffSig[barId] == sig then
            -- Spell list unchanged -- still refresh the spells group's
            -- maxFrameCount/layout in case grid (icon size, padding, ...)
            -- changed without the spell list changing, and re-apply the
            -- catch-all chain (ApplyGroupConfig is idempotent and
            -- self-zeroes it when Show All Buffs is off).
            if #spells > 0 then
                local livePad = bar.padding or 5
                container:SetAuraGroupMaxFrameCount("spells", grid.effectiveMax)
                container:SetAuraGroupLayout("spells", {
                    elementSpacing = livePad, lineSpacing = livePad,
                    groupSpacing = livePad, groupLineSpacing = livePad,
                })
            end
            customBuffDeclared[barId] = customBuffDeclared[barId] or {}
            ApplyGroupConfig(container, allChain, customBuffDeclared[barId], styleKey, grid.effectiveMax, bar.padding or 5)
            return -- nothing structural to rebuild
        end
        AK.ReleaseContainer(container) -- safe: dedicated container, see doc comment above
        customBuffContainers[barId] = nil
    end

    local _, spec = BuildContainerSpec(parent, bar, grid)
    local pad = bar.padding or 5
    AK.RequestContainer(parent, "player", spec, function(container)
        customBuffContainers[barId] = container
        customBuffSig[barId] = sig
        customBuffDeclared[barId] = {}
        ApplyGroupConfig(container, allChain, customBuffDeclared[barId], styleKey, grid.effectiveMax, pad)
        if #spells > 0 then
            local includeMap = {}
            for i = 1, #spells do includeMap[spells[i]] = true end
            AK.AddGroupToContainer(container, {
                key = "spells",
                filter = { "HELPFUL" },
                style = styleKey,
                maxFrameCount = grid.effectiveMax,
                candidateFilters = { includeSpellIDs = includeMap },
            })
            container:SetAuraGroupLayout("spells", {
                elementSpacing = pad, lineSpacing = pad,
                groupSpacing = pad, groupLineSpacing = pad,
            })
        end
    end)
end

function ns.PAB_ReloadCustomBuffBar(barId)
    ReloadCustomBuffBarImpl(barId)
    RegisterPABCustomUnlock()
end

-- Public hook for the Options UI: (re)builds one custom debuff bar's engine
-- state to match its current DB entry. Groups are additive and never
-- released (same reasoning as ApplyGroupConfig's doc comment for the two
-- default bars) -- a class toggle, grid change, or style edit just re-runs
-- this on the same container.
--
-- Wrapped below for the same reason as PAB_ReloadCustomBuffBar: keeps
-- unlock-mode registration in sync on every exit path.
local function ReloadCustomDebuffBarImpl(barId)
    AK = AK or (EllesmereUI and EllesmereUI.AuraKit)
    if not AK then return end

    local bar = ns.PAB_GetCustomDebuffBar(barId)
    if not bar then
        if customDebuffContainers[barId] then
            -- Groups can't be un-declared (see ApplyGroupConfig doc
            -- comment) -- zero every group's frame count instead so a
            -- deleted bar's icons disappear even though the container
            -- itself is never released.
            for key in pairs(customDebuffDeclared[barId] or {}) do
                customDebuffContainers[barId]:SetAuraGroupMaxFrameCount(key, 0)
            end
        end
        if customDebuffParents[barId] then customDebuffParents[barId]:Hide() end
        customDebuffParents[barId] = nil
        return
    end

    local styleKey = CustomDebuffStyleKey(barId)
    AK.styles[styleKey] = BuildStyle(false, bar)

    local parent = customDebuffParents[barId]
    if not parent then
        parent = CreateFrame("Frame", "EllesmereUIPlayerAuraBars_CustomDebuff" .. barId, UIParent)
        customDebuffParents[barId] = parent
    end
    ApplyCustomBarPosition(parent, bar, barId)
    parent:SetShown(bar.enabled ~= false)
    if bar.enabled == false then return end

    local grid = ComputeGrid(false, bar)
    parent:SetSize(grid.width, grid.height)

    local chain = BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, bar) end)
    local corner, spec = BuildContainerSpec(parent, bar, grid)
    local pad = bar.padding or 5

    if not customDebuffContainers[barId] then
        AK.RequestContainer(parent, "player", spec, function(container)
            customDebuffContainers[barId] = container
            customDebuffDeclared[barId] = {}
            ApplyGroupConfig(container, chain, customDebuffDeclared[barId], styleKey, grid.effectiveMax, pad)
        end)
    else
        local container = customDebuffContainers[barId]
        local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
        container:ClearAllPoints()
        container:SetPoint(corner, parent, corner, 0, 0)
        AK.SetContainerAnchor(container, corner)
        if FlowDir then
            AK.SetContainerGrowth(container, ToGrowthH(bar.growDirection or "LEFT"), FlowDir.Down)
        end
        AK.SetContainerPadding(container, 0, 0, 0, 0)
        AK.SetContainerRowWidth(container, grid.rowWidth)
        ApplyGroupConfig(container, chain, customDebuffDeclared[barId], styleKey, grid.effectiveMax, pad)
    end
end

function ns.PAB_ReloadCustomDebuffBar(barId)
    ReloadCustomDebuffBarImpl(barId)
    RegisterPABCustomUnlock()
end

-- Rebuilds every persisted custom bar's engine state. Called once from
-- TryCreateBars alongside the two default bars, and safe to call again any
-- time (e.g. profile switch) -- both reload functions above are idempotent
-- no-ops when nothing actually changed.
local function ReloadAllCustomBarsImpl()
    local buffList = ns.PAB_CustomBuffBars()
    if buffList then
        for i = 1, #buffList do ns.PAB_ReloadCustomBuffBar(buffList[i].id) end
    end
    local debuffList = ns.PAB_CustomDebuffBars()
    if debuffList then
        for i = 1, #debuffList do ns.PAB_ReloadCustomDebuffBar(debuffList[i].id) end
    end
end
ReloadAllCustomBars = ReloadAllCustomBarsImpl
ns.PAB_ReloadAllCustomBars = ReloadAllCustomBarsImpl

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------

-- ns.db is set by EllesmereUIUnitFrames.lua's SetupOptionsPanel(), which
-- EnableBody() itself only schedules via C_Timer.After(0, SetupOptionsPanel)
-- -- i.e. one frame AFTER PLAYER_LOGIN's handlers finish running. A single
-- PLAYER_LOGIN listener here would run BEFORE ns.db exists (confirmed via
-- debug print: PAB() returned nil at that point). Rather than depend on the
-- exact relative timing between two independent C_Timer.After(0, ...) calls
-- in different files (not a stable guarantee), retry with a capped, gently
-- backing-off timer until ns.db is actually populated.
local RETRY_CAP = 40 -- ~ a few seconds worst case at the backed-off interval; then give up loudly
local retryCount = 0

local function TryCreateBars()
    if PAB() then
        CreateBars()
        return
    end
    retryCount = retryCount + 1
    if retryCount > RETRY_CAP then
        geterrorhandler()("EllesmereUIUnitFrames_PlayerAuraBars: ns.db never became "
            .. "available after " .. RETRY_CAP .. " retries -- Player Aura Bars did not load.")
        return
    end
    C_Timer.After(0, TryCreateBars)
end

ns.PAB_CreateBars = CreateBars

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        TryCreateBars()
    end
end)

