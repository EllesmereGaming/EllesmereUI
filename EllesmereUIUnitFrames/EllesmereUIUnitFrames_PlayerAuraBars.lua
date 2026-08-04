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
--  "raid"/"raidcombat" were excluded 2026-07-29 (assumed roster-context
--  tokens that don't apply to a standalone player-only display) -- reversed
--  2026-08-03 (Joel, for Icon Effects Per-Filter parity with Raid Frames'
--  own "Raid"/"Raid In Combat" filters): RAID/RAID_IN_COMBAT are per-aura
--  flags (Blizzard's own raid-frame debuff curation baked into the aura
--  definition itself), not roster-size-dependent, so they filter
--  meaningfully even solo. Now wired up as real, functional debuff
--  categories exactly like every other class here.
-------------------------------------------------------------------------------

local HIDDEN_CLASSES = {}

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
    Dispellable       = { "Dispellable By You", "Shows only auras with a dispel type you can dispel" },
    CrowdControl      = { "Crowd Control",      "Shows only crowd-control auras" },
    BigDefensive      = { "Big Defensive",      "Shows only major defensive cooldowns" },
    ExternalDefensive = { "External Defensive", "Shows only external defensive cooldowns cast on the unit" },
    Cancelable        = { "Cancelable",         "Shows only buffs that can be canceled" },
    Stealable         = { "Stealable",          "Shows only buffs you can spellsteal or purge" },
    BossAura          = { "Boss Debuffs",       "Shows only debuffs applied by bosses" },
    RoleAura          = { "Role Debuffs",       "Shows only debuffs flagged for your role" },
    -- "Important" (2026-08-03, renamed from "Priority" for parity with Raid
    -- Frames' own wording for this same isPriorityAura flag).
    PriorityAura      = { "Important",          "Shows only priority debuffs" },
    NonPlayer         = { "Not Cast By You",    "Shows only debuffs not applied by you" }, -- ASSUMPTION, see note above
    -- Any debuff carrying a dispel type, regardless of whether YOU can
    -- remove it -- distinct from "Dispellable By You" above. Mirrors Raid
    -- Frames' "Dispels" filter.
    DispelTyped       = { "Dispels", "Shows any debuff with a dispel type (Magic, Curse, Disease, Poison, Bleed), even if you cannot remove it" },
    Raid              = { "Raid",            "Shows only debuffs from Blizzard's curated raid-frame debuff set" },
    RaidInCombat      = { "Raid In Combat",  "Shows only the stricter in-combat subset of the raid set" },
}

-- Curated debuff filter list (2026-08-03, Joel): exact parity with Raid
-- Frames' own debuff filter vocabulary and order (EUI_RaidFrames_
-- ManagerPages.lua's TILE_FILTER_ITEMS) -- both PAB's Base Filters (display
-- restriction, ns.PAB_ClassItems) and Icon Effects Filters (fx targeting,
-- ns.PAB_FxClassItems) dropdowns show this SAME curated, ordered set now,
-- replacing the previous "every visible class" generic enumeration (which
-- exposed Big Defensive/External Defensive/Not Cast By You -- concepts with
-- no Raid Frames debuff equivalent -- and omitted Raid/Raid In Combat
-- entirely). Values are the lowercase ENGINE keys (TOKEN_CLASSES/
-- CANDIDATE_CLASSES' .key), resolved to either .key or .skey per dropdown
-- by ClassByKey below. Big Defensive/External Defensive/Not Cast By You
-- remain fully functional (BuildChain/ClassEnabled still read them) for any
-- profile that already has them set -- just no longer offered as a fresh
-- pick in either dropdown.
local DEBUFF_FILTER_ORDER = {
    "priority", "cc", "bossaura", "roleaura", "raid", "raidcombat", "dispellable", "dispeltyped",
}

local function ClassByKey(key)
    local uf = ns.UF_TokenClasses
    if uf then
        for i = 1, #uf do if uf[i].key == key then return uf[i] end end
    end
    local cc = ns.UF_CandidateClasses
    if cc then
        for i = 1, #cc do if cc[i].key == key then return cc[i] end end
    end
end

function ns.PAB_ClassItems(isBuff)
    if not isBuff then
        local items = {}
        for i = 1, #DEBUFF_FILTER_ORDER do
            local class = ClassByKey(DEBUFF_FILTER_ORDER[i])
            if class then
                local meta = CLASS_LABELS[class.skey]
                items[#items + 1] = {
                    key = class.skey,
                    label = meta and meta[1] or class.skey,
                    tooltip = meta and meta[2] or nil,
                }
            end
        end
        return items
    end

    -- Buffs: unchanged generic enumeration (kept for signature
    -- compatibility -- ns.PAB_ClassItems is never actually called with
    -- isBuff=true today, buffs use their own Filters/Extra Spells model).
    local items = {}
    local tokenClasses = VisibleTokenClasses()
    local candidateClasses = VisibleCandidateClasses()
    if not (tokenClasses and candidateClasses) then return items end
    local function AddAll(list)
        for i = 1, #list do
            local class = list[i]
            -- isBuff is always true in this branch (isBuff==false already
            -- returned above), so the original ((buffOnly and not isBuff) or
            -- (debuffOnly and isBuff)) exclusion simplifies to just debuffOnly.
            if not class.debuffOnly then
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
--  Icon Effects Per-Filter (debuffs only) -- ported from Raid Frames'
--  DebuffManager fxList system (EUI_RaidFrames_DebuffManager.lua /
--  EUI_RaidFrames_AuraContainers.lua), NOT shared code (same "adapted, not
--  shared" precedent as BuildChain/ClassEnabled below). Each cfg.fxList
--  entry pairs a set of debuff-category filters with an optional Icon Glow,
--  Border override, and Size override; the FIRST entry whose filters
--  include a button's category wins.
--
--  Unlike Raid Frames' independent/overlapping category records, PAB's
--  debuff classes are a mutual-exclusion chain (BuildChain below) -- every
--  displayed debuff icon already belongs to exactly ONE engine group key
--  (a class's .key, or "all" for the catch-all), so matching here is a
--  single dictionary lookup, not a search across overlapping records.
-------------------------------------------------------------------------------

local function PAB_FxEntryActive(e)
    return e.filters ~= nil and next(e.filters) ~= nil
        and (((e.glowType or 0) > 0) or ((e.borderSize or 0) > 0)
            or ((tonumber(e.size) or 0) > 0))
end

local function PAB_FxListView(list)
    if not list then return nil end
    local out
    for i = 1, #list do
        if PAB_FxEntryActive(list[i]) then
            out = out or {}
            out[#out + 1] = list[i]
        end
    end
    return out
end

-- First ACTIVE block whose filters include `cat` wins (list is already
-- pre-filtered to active-only blocks by PAB_FxListView/style.fxList).
local function PAB_FxBlockFor(list, cat)
    if not (list and cat) then return nil end
    for i = 1, #list do
        local f = list[i].filters
        if f and f[cat] then return list[i] end
    end
end

-- Per-filter Size resolution for one engine group key: the first ACTIVE
-- block matching `cat` wins outright, same rule PAB_ApplyDmFx uses for
-- glow/border, so a later block's Size never reaches a category an earlier
-- block already claimed.
local function PAB_FxSizeFor(list, cat)
    if not list then return nil end
    for i = 1, #list do
        local e = list[i]
        if PAB_FxEntryActive(e) then
            local f = e.filters
            if f and f[cat] then
                local sz = tonumber(e.size)
                if sz and sz > 0 then return sz end
                return nil
            end
        end
    end
end

-- Filter vocabulary for the Icon Effects UI (debuffs only): the same
-- curated DEBUFF_FILTER_ORDER list ns.PAB_ClassItems(false) uses, but keyed
-- by the lowercase ENGINE group key (class.key, e.g. "bossaura") instead of
-- the CamelCase classFilters key (class.skey, e.g. "BossAura") -- fxList
-- blocks match against d.dmCat, which is stamped with class.key (see
-- ApplyGroupConfig's extraInit below). No catch-all "all" entry, matching
-- Raid Frames' own TILE_FILTER_ITEMS (which has none either).
function ns.PAB_FxClassItems()
    local items = {}
    for i = 1, #DEBUFF_FILTER_ORDER do
        local class = ClassByKey(DEBUFF_FILTER_ORDER[i])
        if class then
            local meta = CLASS_LABELS[class.skey]
            items[#items + 1] = {
                key = class.key,
                label = meta and meta[1] or class.key,
                tooltip = meta and meta[2] or nil,
            }
        end
    end
    return items
end

-- Ported from Raid Frames' ApplyDmFx (EUI_RaidFrames_AuraContainers.lua):
-- Icon Glow (EllesmereUI.Glows overlay) + Border override (EllesmereUI.PP),
-- keyed off the button's stamped category (d.dmCat, set once at creation by
-- ApplyGroupConfig's extraInit, see below). Cheap no-op for buffs
-- (style.fxList is never set on a buff style) and for debuff buttons whose
-- category matches no active block.
local function PAB_ApplyDmFx(button, d, style)
    local cat = d.dmCat
    local e = style.fxList and PAB_FxBlockFor(style.fxList, cat) or nil

    -- Icon Glow
    local Glows = EllesmereUI.Glows
    local gType = (e and e.glowType) or 0
    if gType > 0 and Glows and Glows.RestrictionSafeStyle then
        gType = Glows.RestrictionSafeStyle(gType)
    end
    local gov = d.pabFxGlow
    if gType > 0 and Glows and Glows.StartGlow then
        if not gov then
            gov = CreateFrame("Frame", nil, button)
            gov:SetAllPoints(button)
            -- Above both the base border and the fx border override, below
            -- the dispel ring and text -- same level ladder Raid Frames'
            -- ApplyDmFx uses (border < fx border < glow < dispel ring < text).
            local base = (d.borderHost and d.borderHost:GetFrameLevel())
                or (button:GetFrameLevel() + 1)
            gov:SetFrameLevel(base + 2)
            gov:EnableMouse(false)
            d.pabFxGlow = gov
        end
        gov:Show()
        local cr, cg, cb = e.glowR or 1.0, e.glowG or 0.776, e.glowB or 0.376
        if e.glowClassColor then
            local _, classFile = UnitClass("player")
            local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
        local sz = style.width or 18
        if (not gov._euiGlowActive) or gov._fxStyle ~= gType or gov._fxW ~= sz
           or gov._fxCR ~= cr or gov._fxCG ~= cg or gov._fxCB ~= cb then
            Glows.StartGlow(gov, gType, sz, cr, cg, cb)
            gov._fxStyle, gov._fxW = gType, sz
            gov._fxCR, gov._fxCG, gov._fxCB = cr, cg, cb
        end
    elseif gov then
        if gov._euiGlowActive and Glows and Glows.StopGlow then Glows.StopGlow(gov) end
        gov:Hide()
    end

    -- Border override
    local PP = EllesmereUI.PP
    local bSize = (e and e.borderSize) or 0
    if bSize > 0 and PP then
        local host = d.pabFxBdr
        if not host then
            host = CreateFrame("Frame", nil, button)
            host:SetAllPoints(button)
            local base = (d.borderHost and d.borderHost:GetFrameLevel())
                or (button:GetFrameLevel() + 1)
            host:SetFrameLevel(base + 1)
            host:EnableMouse(false)
            PP.CreateBorder(host, 0, 0, 0, 1, 1)
            d.pabFxBdr = host
        end
        local bc = e.borderColor or { r = 0, g = 0, b = 0 }
        PP.UpdateBorder(host, bSize, bc.r or 0, bc.g or 0, bc.b or 0, 1)
        host:Show()
    elseif d.pabFxBdr then
        d.pabFxBdr:Hide()
    end
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

-- includeCatchAll (default true, matches every pre-existing caller): the
-- default Debuffs bar and the buff-side {base}-only shortcut both want
-- "every remaining aura of this polarity" appended after the per-class
-- groups. Custom Debuff Bars with Show All Debuffs off do NOT want that --
-- their whole point is to show ONLY the selected classes, but the catch-all
-- was being appended unconditionally, so a bar restricted to e.g. "Big
-- Defensive" also rendered every other debuff via the "all" group. Callers
-- now pass includeCatchAll = false whenever the UI's own "Base Filters
-- dropdown restricts what's shown" promise (see BuildAssignedDebuffsFields'
-- tooltip) needs to actually hold.
local function BuildChain(base, classEnabledFn, includeCatchAll)
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
            chain[#chain + 1] = { key = class.key, tokens = tokens, cand = class.cand, candValue = class.candValue }
        end
    end

    if includeCatchAll ~= false then
        -- Catch-all group LAST: everything not claimed by an enabled class,
        -- negating the full chain built above. With zero classes enabled
        -- this is just { base }, i.e. every aura of that polarity.
        local allTokens = { base }
        for n = 1, #negations do allTokens[#allTokens + 1] = negations[n] end
        chain[#chain + 1] = { key = "all", tokens = allTokens }
    end

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
local STYLE_EXTDEF = "playerAuraBars_extDef"

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
--   rowSpacing                        (optional; row-to-row gap override, i.e.
--                                      lineSpacing/groupLineSpacing only --
--                                      nil falls back to `padding`, same
--                                      value ComputeGrid used for both before
--                                      this field existed. elementSpacing/
--                                      groupSpacing (icon-to-icon within a
--                                      row) always stay tied to `padding`.)
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

    -- hideSwipe (BuildStyle, unconditionally true for every PAB style) only
    -- runs through AK's own ApplyStyleToRegions, which fires at button
    -- CREATION and on explicit Restyle passes -- NOT on ordinary aura
    -- content churn. Blizzard's own engine calls something equivalent to
    -- Cooldown:SetCooldown(...) on d.cooldown internally every time that
    -- slot's aura data refreshes (new aura in the slot, duration change,
    -- ...), and that native Blizzard Cooldown API implicitly re-Shows the
    -- frame as a side effect -- confirmed in-game 2026-08-02: the swipe
    -- disappeared right after a restyle but kept reappearing on ordinary
    -- aura updates, i.e. SetShown(false) was being silently undone by
    -- Blizzard's own code, not failing to apply in the first place. Same
    -- "Blizzard keeps re-showing this" pattern already used in this file
    -- for BuffFrame/DebuffFrame (HideBlizzardPlayerAuras) -- hooksecurefunc
    -- runs AFTER Blizzard's call completes, not from inside it, so this
    -- does not taint anything. Installed once per button (guarded, not
    -- per-restyle) since the hook itself never needs to change -- PAB never
    -- offers a UI toggle for hideSwipe, it is unconditional for every style
    -- this module owns.
    if d.cooldown and not d._pabSwipeHooked then
        d._pabSwipeHooked = true
        hooksecurefunc(d.cooldown, "Show", function() d.cooldown:Hide() end)

        -- Belt-and-suspenders (2026-08-02, after field reports that the
        -- swipe still reappeared post-instance-change despite the Show
        -- hook above): SetAlpha(0) is a visibility property Show()/Hide()
        -- never touch, so it survives whatever internal path Blizzard's
        -- engine used to make the frame visible again -- unlike the Show
        -- hook, it doesn't depend on THAT specific method being the one
        -- Blizzard's engine actually called on that path. Set once, same
        -- guard as the hook above; a Shown-but-alpha-0 cooldown frame is
        -- still invisible regardless of which Show-adjacent call re-armed
        -- it.
        d.cooldown:SetAlpha(0)
    end

    -- Icon Effects Per-Filter (debuffs only): flag-gated so buff buttons,
    -- which never carry style.fxList or fx overlay frames, pay zero cost.
    if style.fxList or d.pabFxGlow or d.pabFxBdr then
        PAB_ApplyDmFx(button, d, style)
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
        -- Always hidden (2026-08-02, Joel's explicit request): the swipe is
        -- the darkening radial overlay CooldownFrameTemplate draws over the
        -- icon as remaining time shrinks -- distinct from the duration
        -- NUMBER text below (hideDurationText), which stays independently
        -- controllable. See EllesmereUI_AuraKit.lua's MakeInitializer:
        -- hideSwipe just does d.cooldown:SetShown(false), no cfg field/UI
        -- toggle needed since it's unconditional here.
        hideSwipe = true,

        -- Right-click to cancel (2026-08-02): mirrors Blizzard's own player
        -- BuffFrame / Edit Mode behavior and EUI_UnitFrames_AuraContainers
        -- .lua's own `cancelButtons = (unit == "player" and isBuff) and
        -- "RightButtonUp"` -- PAB is always the player unit, so only the
        -- isBuff half of that condition applies here (debuffs were never
        -- player-cancelable in Blizzard's own UI either). AK wires this
        -- straight through to the engine's AuraButtonMixin:
        -- SetCancelAuraButtons -- same secure click-to-cancel Blizzard uses,
        -- not a hand-rolled macro/attribute setup.
        cancelButtons = isBuff and "RightButtonUp" or nil,

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

        -- Icon Effects Per-Filter: debuffs only (buffs never get style.fxList,
        -- so PAB_ApplyDmFx's gate in PAB_ApplyExtraText stays a cheap no-op).
        style.fxList = PAB_FxListView(cfg.fxList)
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
-- Resolves a bar cfg's sortMethod/sortDirection into the native
-- AuraContainerSortMethod/AuraContainerSortDirection enum values (globals,
-- confirmed in-game 2026-08-03: AuraContainerSortMethod = {Default=0,
-- BigDefensive=1, UnitFrameDebuff=2, ImportantOnly=3, Expiration=4,
-- ExpirationOnly=5, Name=6, NameOnly=7, AuraInstanceIDOnly=8},
-- AuraContainerSortDirection = {Normal=0, Reverse=1}). Default=0 and
-- Normal=0 are valid values, not "unset" -- callers must compare against
-- nil, never truthiness (same requirement the Nameplates module's own
-- sort wiring documents).
local function ResolveSortMethod(cfg)
    local key = cfg.sortMethod or "Default"
    return AuraContainerSortMethod and AuraContainerSortMethod[key]
end
local function ResolveSortDirection(cfg)
    local key = (cfg.sortDirection == "Reverse") and "Reverse" or "Normal"
    return AuraContainerSortDirection and AuraContainerSortDirection[key]
end

-- "Has Duration" (Assigned Buffs filter, 2026-08-03) -- buffs-only, native
-- `candidateFilters.maxDuration` (verified against Blizzard's actual PTR
-- source, Gethe/wow-ui-source ptr branch, Blizzard_AuraContainerUtil.lua:
-- "Max duration filters implicitly always filter out permanent auras" --
-- `auraData.duration > maxDuration or auraData.duration == 0` excludes the
-- aura). `math.huge` as the cap means the `>` half of that check never
-- trips, so this ONLY excludes permanent (duration=0) buffs, regardless of
-- how long a timed buff's duration actually is.
local function BuffCandidateExtras(cfg)
    if cfg and cfg.hasDuration then
        return { maxDuration = math.huge }
    end
    return nil
end

-- Merges `extra`'s keys onto a copy of `base` (nil-safe both ways). Used to
-- combine a chain-link's own candidateFilters (e.g. debuff class token) with
-- BuffCandidateExtras' maxDuration -- both may be nil, either alone, or both
-- present at once.
local function MergeCandidateFilters(base, extra)
    if not extra then return base end
    if not base then return extra end
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(extra) do out[k] = v end
    return out
end

-- declaredSet is a per-container registry of every group key ever declared
-- on that container: declared.debuffs for the default Debuffs bar/every
-- custom Debuff Bar (class-token chain), declared.buffs for the default
-- Buffs bar's single "Show All Buffs" catch-all group (see CreateBars'
-- doc comment for why buffs still need ONE group alongside their slots).
--
-- cfg is the bar's own settings table (buffCfg/debuffCfg/a custom bar entry)
-- -- read-only here, only used to resolve sortMethod/sortDirection so every
-- chain group on this container gets the bar's configured sort. The direct
-- setter (SetAuraGroupSortMethod, unlike AddAuraGroup's sortMethod field)
-- requires both values non-nil, so it's re-applied every pass, same as
-- MaxFrameCount/Layout below.
--
-- extraCand (optional): additional candidateFilters merged onto every
-- chain-link's own candidateFilters (see MergeCandidateFilters above) --
-- used to thread BuffCandidateExtras' maxDuration onto the Buffs catch-all
-- chain without affecting Debuffs' class-token chains, which pass nil here.
-- Like sortMethod/sortDirection, re-applied live every pass via
-- SetAuraGroupCandidateFilters -- candidateFilters are NOT immutably fixed
-- at declaration once a live setter is used (only the group's FILTER STRING
-- is; see the doc comment above this function).
-- Icon Effects Per-Filter Size override: PAB's icon size is entirely
-- style-driven (ApplyStyleToRegions's button:SetSize(style.width,
-- style.height), EllesmereUI_AuraKit.lua -- a group's own elementWidth/
-- Height in SetAuraGroupLayout feeds the FLOW MATH only, confirmed by that
-- file's own doc comment, and never resizes the button itself). A
-- per-category size therefore needs its OWN style key, not a group-layout
-- tweak (mirrors Raid Frames' DebuffManager EnsureBaseSizeStyle). Keyed by
-- size alone (not size+category): any two categories overridden to the same
-- size can share one variant, since the variant is just the bar's base
-- style with width/height swapped -- everything else (border, dispel
-- colors, fxList, applyExtra) rides along unchanged via the shallow copy.
-- Rebuilt unconditionally every ApplyGroupConfig pass (cheap: settings-apply
-- frequency, not per-frame) rather than fingerprint-cached, matching this
-- file's existing BuildStyle+RestyleSoon convention elsewhere.
local function EnsurePabSizedStyle(baseKey, size)
    local base = AK.styles[baseKey]
    if not base then return baseKey end
    local variantKey = baseKey .. ":sz" .. tostring(size)
    local v = {}
    for k, val in pairs(base) do v[k] = val end
    v.width = size
    v.height = size
    AK.styles[variantKey] = v
    AK.RestyleSoon(variantKey)
    return variantKey
end

local function ApplyGroupConfig(container, chain, declaredSet, styleKey, effectiveMax, gap, rowGap, cfg, extraCand)
    local sortMethod = ResolveSortMethod(cfg)
    local sortDirection = ResolveSortDirection(cfg)
    -- elementSpacing = gap between icons in the same row; lineSpacing = gap
    -- between wrapped rows within a group; group*Spacing = gap to the NEXT
    -- group on the same container. elementSpacing/groupSpacing stay tied to
    -- `gap` (padding); lineSpacing/groupLineSpacing use `rowGap` (defaults to
    -- `gap` when not passed, i.e. the pre-rowSpacing-field behavior) so row-
    -- to-row distance can be overridden independently of icon-to-icon
    -- spacing (see cfg.rowSpacing in the Settings Schema doc comment).
    -- Container-level padding is a THIRD, unrelated concept: the OUTER edge
    -- inset, fixed at 0 elsewhere and never affected by either of these.
    rowGap = rowGap or gap
    local layout = {
        elementSpacing = gap,
        lineSpacing = rowGap,
        groupSpacing = gap,
        groupLineSpacing = rowGap,
    }

    local active = {}
    for i = 1, #chain do
        local link = chain[i]
        -- Icon Effects Per-Filter Size override (debuffs only -- cfg.fxList
        -- is nil for buffs, so szOv is always nil there and effKey ==
        -- link.key, identical to before this feature existed).
        local szOv = PAB_FxSizeFor(cfg.fxList, link.key)
        local effKey = szOv and (link.key .. "|sz") or link.key
        local linkStyleKey = szOv and EnsurePabSizedStyle(styleKey, szOv) or styleKey
        active[effKey] = true
        local candidateFilters
        if link.cand then
            candidateFilters = { [link.cand] = link.candValue or true }
        end
        candidateFilters = MergeCandidateFilters(candidateFilters, extraCand)
        if not declaredSet[effKey] then
            local catKey = link.key
            AK.AddGroupToContainer(container, {
                key = effKey,
                filter = link.tokens,
                style = linkStyleKey,
                maxFrameCount = 0, -- real count applied right below, matches the sibling module's declare-then-set order
                candidateFilters = candidateFilters,
                sortMethod = sortMethod,
                sortDirection = sortDirection,
                -- Icon Effects Per-Filter: stamps this button's category
                -- (matched against fxList blocks by PAB_ApplyDmFx) and arms
                -- the glow/border overlay inside the one legal creation
                -- window, mirroring Raid Frames' DebuffManager tile
                -- extraInit (style.applyExtra runs BEFORE extraInit at
                -- creation, verified in EllesmereUI_AuraKit.lua's
                -- MakeInitializer -- so the first applyExtra pass sees
                -- d.dmCat == nil harmlessly, and this re-arms it right after).
                extraInit = function(button, d, style)
                    d.dmCat = catKey
                    PAB_ApplyDmFx(button, d, style)
                end,
            })
            declaredSet[effKey] = true
        end
        container:SetAuraGroupMaxFrameCount(effKey, effectiveMax)
        container:SetAuraGroupLayout(effKey, layout)
        container:SetAuraGroupCandidateFilters(effKey, candidateFilters)
        if sortMethod ~= nil and sortDirection ~= nil then
            container:SetAuraGroupSortMethod(effKey, sortMethod, sortDirection)
        end
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
--
-- width/height (2026-08-02 fix, trial): N icons need (N-1) gaps, not N --
-- the previous `cols * (iconSize + pad)` baked one extra trailing pad's
-- worth of edge margin into the box (visible as the box being a few px
-- bigger than the icons it actually contains). Surfaced by the External
-- Defensives migration (directly comparable against the old standalone
-- module's tighter `4*iconSize + 3*spacing` formula, which never had this
-- trailing pad). Affects every PAB bar's rendered box size, not just that
-- one -- Joel asked to see this applied before deciding whether to keep it.
-- Confirmed real bug, not preview-only (2026-08-03, Joel asked to check):
-- the live bar's parent frame is sized via this same function
-- (`parent:SetSize(grid.width, grid.height)`, e.g. line ~1500/1619/2586/
-- 2727), computed purely from the bar's uniform cfg.iconSize -- an Icon
-- Effects Size override on one category renders THAT category's icons
-- bigger via a separate sized style variant (EnsurePabSizedStyle), but the
-- surrounding frame/box never grows to match, so the oversized icons simply
-- overflow the frame's bounds (also throwing off the CENTER-anchor
-- recompensation math a few lines below every grid.width/height use, which
-- assumes this size is accurate). Since the container is a FLOW layout
-- mixing possibly-different per-group icon sizes, there is no way to
-- compute an exact box footprint ahead of time (it's data-dependent -- which
-- specific auras are showing right now) -- the same "static worst-case
-- capacity reservation" spirit maxTotal/rows*cols already use here, so the
-- box is sized for the LARGEST icon that could ever appear (base iconSize,
-- or any active fx block's Size override, whichever is bigger) rather than
-- the base size alone. Same fix serves the preview box (RenderPreviewIcons/
-- PAB_BuildPreviewBox both call this same function).
local function MaxIconSizeFor(isBuff, cfg)
    local size = cfg.iconSize or 32
    if not isBuff and cfg.fxList then
        local list = PAB_FxListView(cfg.fxList)
        if list then
            for i = 1, #list do
                local sz = tonumber(list[i].size)
                if sz and sz > size then size = sz end
            end
        end
    end
    return size
end

local function ComputeGrid(isBuff, cfg)
    local iconSize = MaxIconSizeFor(isBuff, cfg)
    local pad = cfg.padding or 5
    local rowGap = cfg.rowSpacing or 12
    local cols = math.max(1, cfg.iconsPerRow or (isBuff and 11 or 8))
    local rows = math.max(1, cfg.maxRows or (isBuff and 3 or 2))
    local configuredMax = cfg.maxTotal or (isBuff and 32 or 16)
    local effectiveMax = math.min(configuredMax, rows * cols)
    -- Actual rows needed for the effective cap, never more than the row limit
    local usedRows = math.min(rows, math.max(1, math.ceil(effectiveMax / cols)))
    -- `lineExtent` is always the AK rowWidth/line-size value (icons-per-line
    -- axis: iconsPerRow icons of iconSize + gaps). `crossExtent` is the
    -- other axis (how many lines are actually used). For horizontal growth a
    -- "line" is a row, so lineExtent -> width; for vertical growth (Up/Down,
    -- 2026-08-04) a "line" is a column, so lineExtent -> height instead --
    -- see CornerFor/BuildContainerSpec's doc comment for the matching
    -- growthH/growthV swap.
    local lineExtent = cols * iconSize + (cols - 1) * pad
    local crossExtent = usedRows * iconSize + (usedRows - 1) * rowGap
    local vertical = (cfg.growDirection == "UP" or cfg.growDirection == "DOWN")
    local width = vertical and crossExtent or lineExtent
    local height = vertical and lineExtent or crossExtent
    return {
        effectiveMax = effectiveMax,
        rowWidth = lineExtent,
        width = width,
        height = height,
        rowGap = rowGap,
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

-- One-time migration from the retired standalone EllesmereUIUnitFrames_
-- ExternalDefensives.lua module (db.profile.externalDefensives) into PAB's
-- own defaultExternalDefensives cfg, run lazily the first time
-- DefaultExternalDefensivesCfg is accessed (mirrors DefaultBuffsCfg/
-- DefaultDebuffsCfg's `s.defaultX = s.defaultX or {}` pattern, just with a
-- real seed body instead of an empty table). Field-name/semantics mapping:
--   enabled/iconSize/borderSize/R/G/B/A: direct 1:1
--   growDirection: old module used lowercase "left"/"right", PAB uses
--     uppercase "LEFT"/"RIGHT"
--   showText -> durationShow: same semantics both sides (nil/true = shown)
--   textSize -> stackTextSize: old module's `textSize` styled the stack/
--     application-count text (btn._count), NOT a duration text -- the old
--     module's duration numbers came from Blizzard's native Cooldown
--     countdown text instead (SetCountdownFont/SetCountdownFormatter on the
--     swipe widget itself), which PAB does not use (AK forces native
--     countdown numbers off unconditionally and renders duration through
--     its own d.duration binding instead, see EllesmereUI_AuraKit.lua's
--     ApplyStyleToRegions doc comment) -- so there is no equivalent source
--     field to migrate FROM for PAB's durationTextSize/durationPosition/etc,
--     they just start at PAB's normal fallbacks (except durationPosition,
--     seeded to "CENTER" below per Joel's explicit request, closer to how
--     the old module's centered native countdown text looked).
-- NOT migrated (PAB's BuildStyle does not expose these fields at all, even
-- though AK's engine border call already accepts them -- flagged 2026-08-02
-- as a follow-up: Joel wants border texture/offset/shift/behind support
-- added across ALL of PAB later, not just for this bar):
--   iconZoom, borderTexture, borderTextureOffset(Y), borderTextureShiftX/Y,
--   borderBehind, durationFormat (colon/seconds compact variants -- already
--   a known, pre-existing PAB-wide gap, see the Settings Schema doc comment
--   near BuildStyle).
local function MigrateExternalDefensives(s)
    local old = ns.db and ns.db.profile and ns.db.profile.externalDefensives
    local cfg = {
        enabled = false,
        iconsPerRow = 4,
        maxRows = 1,
        maxTotal = 4,
        durationPosition = "CENTER",
    }
    if old then
        if old.enabled ~= nil then cfg.enabled = old.enabled end
        if old.iconSize then cfg.iconSize = old.iconSize end
        if old.growDirection then cfg.growDirection = string.upper(old.growDirection) end
        if old.showText ~= nil then cfg.durationShow = old.showText end
        if old.textSize then cfg.stackTextSize = old.textSize end
        if old.borderSize then cfg.borderSize = old.borderSize end
        if old.borderR then cfg.borderR = old.borderR end
        if old.borderG then cfg.borderG = old.borderG end
        if old.borderB then cfg.borderB = old.borderB end
        if old.borderA then cfg.borderA = old.borderA end
        if old.unlockPos and old.unlockPos.point and not s.extDefPos then
            s.extDefPos = {
                point = old.unlockPos.point,
                relPoint = old.unlockPos.relPoint or old.unlockPos.point,
                x = old.unlockPos.x, y = old.unlockPos.y,
            }
        end
    end
    return cfg
end

local function DefaultExternalDefensivesCfg(s)
    s.defaultExternalDefensives = s.defaultExternalDefensives or MigrateExternalDefensives(s)
    return s.defaultExternalDefensives
end
ns.PAB_DefaultExternalDefensivesCfg = DefaultExternalDefensivesCfg

local buffsContainer, debuffsContainer, extDefContainer
local buffsParent, debuffsParent, extDefParent
-- Per-container, per-polarity registry of every group key ever declared
-- (see ApplyGroupConfig above) -- reset only when a container is (re-)
-- created, never cleared on a live settings change.
local declared = { buffs = {}, debuffs = {} } -- buffs: only the "Show All Buffs" catch-all group key ("all"); debuffs: every class-token chain group key
local lastSize = { buffs = nil, debuffs = nil, extdef = nil } -- {w=,h=}, tracks our own last-applied grid size for CENTER-anchor compensation (see ApplyLiveConfig)
local buffsSlotSig -- signature of the default Buffs bar's last-applied resolved spell list (ns.PAB_ResolveSpells), mirrors customBuffSig[barId] for the per-bar slots model
local RegisterPABUnlock -- forward-declared; defined after CreateBars, called from it
local ReloadAllCustomBars -- forward-declared; defined after CreateBars (custom bars section), called from it
local PAB_MaybeRefreshPreview -- forward-declared; assigned in the options-page preview section below, called from every live-apply function so an open bar-detail preview box stays in sync with slider drags without needing to know it exists

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
--
-- Vertical growth (Up/Down, 2026-08-04 addition, Joel): when growDirection is
-- UP/DOWN, the flow's PRIMARY axis becomes vertical (icons fill up/down first)
-- and growthH instead carries the CROSS axis -- which side additional columns
-- wrap to, from the new cfg.iconWrapDirection field ("LEFT"/"RIGHT", default
-- LEFT). Mirrors EUI_RaidFrames_AuraContainers.lua's AnchorDebuffContainer
-- (grow==UP/DOWN branch: gH = wrap, gV = grow) -- same AK primitives, same
-- axis-swap idea, just PAB has no separate wrap dropdown (see the cog-only UI
-- decision in the plan). Horizontal growth (Left/Right) is untouched: growthH
-- stays the primary axis, growthV stays hardcoded Down (rows always wrap
-- downward, as before this feature existed).
local function ToGrowthH(dirStr, wrapStr)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    if not FlowDir then return nil end
    if dirStr == "UP" or dirStr == "DOWN" then
        return wrapStr == "RIGHT" and FlowDir.Right or FlowDir.Left
    end
    return dirStr == "RIGHT" and FlowDir.Right or FlowDir.Left
end
local function ToGrowthV(dirStr)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    if not FlowDir then return nil end
    if dirStr == "UP" then return FlowDir.Up end
    if dirStr == "DOWN" then return FlowDir.Down end
    return FlowDir.Down -- horizontal growth: rows always wrap downward
end
-- Corner = the flow's fixed start point = (opposite of growthV side) +
-- (opposite of growthH side) -- same rule for every direction, horizontal or
-- vertical (verified against the existing LEFT/RIGHT cases: growthV is
-- always Down -> TOP component; growthH Right/Left -> LEFT/RIGHT component).
local function CornerFor(dirStr, wrapStr)
    if dirStr == "UP" or dirStr == "DOWN" then
        local vSide = (dirStr == "UP") and "BOTTOM" or "TOP"
        local hSide = (wrapStr == "RIGHT") and "LEFT" or "RIGHT"
        return vSide .. hSide
    end
    return dirStr == "RIGHT" and "TOPLEFT" or "TOPRIGHT"
end

-- Shared by every container -- default bars (buffs/debuffs) AND custom bars
-- alike: builds the AK.RequestContainer spec's point+layout from a bar-local
-- cfg's growDirection and a precomputed grid (see ComputeGrid). One
-- implementation so default and custom bars can never drift in how they
-- interpret growDirection/rowWidth. Returns the corner too since callers
-- also need it for the container's own SetPoint against its parent frame,
-- and `vertical` since AK.SetContainerAxis is a separate call from
-- AK.ApplyContainerLayout (axis isn't part of the layout table AK consumes).
local function BuildContainerSpec(parent, cfg, grid)
    local dir = cfg.growDirection or "LEFT"
    local wrap = cfg.iconWrapDirection or "LEFT"
    local vertical = (dir == "UP" or dir == "DOWN")
    local corner = CornerFor(dir, wrap)
    return corner, {
        point = { corner, parent, corner, 0, 0 },
        layout = {
            anchorPoint = corner,
            padding = { 0, 0, 0, 0 },
            rowWidth = grid.rowWidth,
            growthH = ToGrowthH(dir, wrap),
            growthV = ToGrowthV(dir),
        },
    }, vertical
end

-- Default anchor when no saved position exists yet. Independent per bar
-- (Joel: bars must be individually movable) -- debuffs no longer chained to
-- buffsParent's BOTTOMRIGHT as in Step A, just a separate default offset so
-- the two don't overlap before either has been dragged.
local DEFAULT_POS = {
    buffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -200 },
    debuffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -260 },
    extdef = { point = "CENTER", relPoint = "CENTER", x = 0, y = -220 }, -- matches the old standalone module's own default
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

-- Same as ApplyBarPosition, kept separate rather than folded into its
-- isBuff-boolean signature: External Defensives is a THIRD, independent
-- position slot (s.extDefPos), not a third value of a two-state toggle.
local function ApplyExtDefPosition(parent)
    local s = PAB()
    local pos = s and s.extDefPos
    local def = DEFAULT_POS.extdef
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

    -- Must run before buffCfg/custom-bar spell resolution below: the 10
    -- curated BM2 presets (Defensives, Offensive CDs, ...) were previously
    -- only imported when the options page opened (EUI_PlayerAuraBars_
    -- ManagerPages.lua's PABMP_BuildPage), so a bar referencing a preset
    -- filter that hadn't been imported yet this session resolved an
    -- incomplete spell set at login, cached that as its signature, and
    -- never re-resolved until something else (e.g. opening the Filter
    -- Editor) forced a signature change. Importing here too closes that
    -- gap for both the default Buffs bar and every custom buff bar.
    if ns.PAB_ImportBM2Filters then ns.PAB_ImportBM2Filters() end

    HideBlizzardPlayerAuras()

    local buffCfg, debuffCfg = DefaultBuffsCfg(s), DefaultDebuffsCfg(s)
    local extDefCfg = DefaultExternalDefensivesCfg(s)

    AK.styles[STYLE_BUFFS] = BuildStyle(true, buffCfg)
    AK.styles[STYLE_DEBUFFS] = BuildStyle(false, debuffCfg)
    AK.styles[STYLE_EXTDEF] = BuildStyle(true, extDefCfg) -- isBuff=true: External Defensives are HELPFUL auras, inherits the same swipe-hide/right-click-cancel treatment every other buff bar gets

    local buffGrid = ComputeGrid(true, buffCfg)
    local debuffGrid = ComputeGrid(false, debuffCfg)
    local extDefGrid = ComputeGrid(true, extDefCfg)

    buffsParent = buffsParent or CreateFrame("Frame", "EllesmereUIPlayerAuraBars_Buffs", UIParent)
    buffsParent:SetSize(buffGrid.width, buffGrid.height)
    ApplyBarPosition(buffsParent, true)
    lastSize.buffs = { w = buffGrid.width, h = buffGrid.height }

    debuffsParent = debuffsParent or CreateFrame("Frame", "EllesmereUIPlayerAuraBars_Debuffs", UIParent)
    debuffsParent:SetSize(debuffGrid.width, debuffGrid.height)
    ApplyBarPosition(debuffsParent, false)
    lastSize.debuffs = { w = debuffGrid.width, h = debuffGrid.height }

    extDefParent = extDefParent or CreateFrame("Frame", "EllesmereUIPlayerAuraBars_ExternalDefensives", UIParent)
    extDefParent:SetSize(extDefGrid.width, extDefGrid.height)
    ApplyExtDefPosition(extDefParent)
    extDefParent:SetShown(extDefCfg.enabled ~= false)
    lastSize.extdef = { w = extDefGrid.width, h = extDefGrid.height }

    local debuffChain = BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, debuffCfg) end, debuffCfg.showAllDebuffs ~= false)

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

    local _, buffSpec, buffVertical = BuildContainerSpec(buffsParent, buffCfg, buffGrid)
    local _, debuffSpec, debuffVertical = BuildContainerSpec(debuffsParent, debuffCfg, debuffGrid)

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
        AK.SetContainerAxis(container, buffVertical)
        declared.buffs = {}
        if buffCfg.showAllBuffs ~= false then
            ApplyGroupConfig(container, buffAllChain, declared.buffs, STYLE_BUFFS, buffGrid.effectiveMax, buffPad, buffGrid.rowGap, buffCfg, BuffCandidateExtras(buffCfg))
        end
        if #buffSpells > 0 then
            local includeMap = {}
            for i = 1, #buffSpells do includeMap[buffSpells[i]] = true end
            AK.AddGroupToContainer(container, {
                key = "spells",
                filter = { "HELPFUL" },
                style = STYLE_BUFFS,
                maxFrameCount = buffGrid.effectiveMax,
                candidateFilters = MergeCandidateFilters({ includeSpellIDs = includeMap }, BuffCandidateExtras(buffCfg)),
                sortMethod = ResolveSortMethod(buffCfg),
                sortDirection = ResolveSortDirection(buffCfg),
            })
            container:SetAuraGroupLayout("spells", {
                elementSpacing = buffPad, lineSpacing = buffGrid.rowGap,
                groupSpacing = buffPad, groupLineSpacing = buffGrid.rowGap,
            })
            declared.buffs.spells = true
        end
    end)
    AK.RequestContainer(debuffsParent, "player", debuffSpec, function(container)
        debuffsContainer = container
        AK.SetContainerAxis(container, debuffVertical)
        declared.debuffs = {}
        ApplyGroupConfig(container, debuffChain, declared.debuffs, STYLE_DEBUFFS, debuffGrid.effectiveMax, debuffPad, debuffGrid.rowGap, debuffCfg)
    end)

    -- External Defensives: fixed engine classification, not a user-selected
    -- spell/class set -- ONE static group declared once and never touched
    -- again (no ApplyGroupConfig chain machinery, no spell-signature
    -- diffing/rebuild like Buffs/Debuffs above -- there is nothing to
    -- diff, the filter can never change). filter={"HELPFUL",
    -- "EXTERNAL_DEFENSIVE"} is AK.Filter-joined into the exact same
    -- "HELPFUL|EXTERNAL_DEFENSIVE" string the old standalone module used
    -- directly against C_UnitAuras.IsAuraFilteredOutByInstanceID.
    local extDefPad = extDefCfg.padding or 5
    local _, extDefSpec, extDefVertical = BuildContainerSpec(extDefParent, extDefCfg, extDefGrid)
    AK.RequestContainer(extDefParent, "player", extDefSpec, function(container)
        extDefContainer = container
        AK.SetContainerAxis(container, extDefVertical)
        AK.AddGroupToContainer(container, {
            key = "extdef",
            filter = { "HELPFUL", "EXTERNAL_DEFENSIVE" },
            style = STYLE_EXTDEF,
            maxFrameCount = extDefGrid.effectiveMax,
            sortMethod = ResolveSortMethod(extDefCfg),
            sortDirection = ResolveSortDirection(extDefCfg),
        })
        container:SetAuraGroupLayout("extdef", {
            elementSpacing = extDefPad, lineSpacing = extDefGrid.rowGap,
            groupSpacing = extDefPad, groupLineSpacing = extDefGrid.rowGap,
        })
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
        -- Bespoke third entry, not MakeBarElement: External Defensives is a
        -- THIRD independent position slot (s.extDefPos via
        -- ApplyExtDefPosition), not a third value of MakeBarElement's
        -- isBuff-boolean-driven BarPositionKey/ApplyBarPosition. isBuff=true
        -- only for getSize's ComputeGrid call (it IS buff-shaped content),
        -- everything position-related is its own accessor.
        MK({
            key = "PAB_ExternalDefensives",
            label = "External Defensives",
            group = "Player Aura Bars",
            order = 702,
            noResize = true,
            noAnchorTarget = true,
            getFrame = function() return extDefParent end,
            isHidden = function()
                local s = PAB()
                local cfg = s and DefaultExternalDefensivesCfg(s)
                return not (cfg and cfg.enabled ~= false)
            end,
            getSize = function()
                local s = PAB()
                if not s then return 32, 32 end
                local grid = ComputeGrid(true, DefaultExternalDefensivesCfg(s))
                return grid.width, grid.height
            end,
            savePos = function(_, point, relPoint, x, y)
                local s = PAB()
                if not s then return end
                s.extDefPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            end,
            loadPos = function()
                local s = PAB()
                local pos = s and s.extDefPos
                if not pos then return nil end
                return { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
            end,
            clearPos = function()
                local s = PAB()
                if s then s.extDefPos = nil end
            end,
            applyPos = function()
                if extDefParent then ApplyExtDefPosition(extDefParent) end
            end,
        }),
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
    AK.styles[STYLE_EXTDEF] = BuildStyle(true, DefaultExternalDefensivesCfg(s))
    AK.RestyleSoon(STYLE_BUFFS)
    AK.RestyleSoon(STYLE_DEBUFFS)
    AK.RestyleSoon(STYLE_EXTDEF)
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

    local corner, liveSpec, vertical = BuildContainerSpec(parent, cfg, grid)
    local pad = cfg.padding or 5

    -- Outer frame anchor is a plain SetPoint, not an AK-managed field --
    -- live-settable directly, same as any other frame anchor.
    container:ClearAllPoints()
    container:SetPoint(corner, parent, corner, 0, 0)
    AK.SetContainerAnchor(container, corner)
    AK.SetContainerAxis(container, vertical)
    if liveSpec.layout.growthH then
        AK.SetContainerGrowth(container, liveSpec.layout.growthH, liveSpec.layout.growthV)
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
            local _, spec, specVertical = BuildContainerSpec(parent, cfg, grid)
            AK.RequestContainer(parent, "player", spec, function(newContainer)
                buffsContainer = newContainer
                AK.SetContainerAxis(newContainer, specVertical)
                declared.buffs = {}
                if cfg.showAllBuffs ~= false then
                    ApplyGroupConfig(newContainer, allChain, declared.buffs, STYLE_BUFFS, grid.effectiveMax, pad, grid.rowGap, cfg, BuffCandidateExtras(cfg))
                end
                if #spells > 0 then
                    local includeMap = {}
                    for i = 1, #spells do includeMap[spells[i]] = true end
                    AK.AddGroupToContainer(newContainer, {
                        key = "spells",
                        filter = { "HELPFUL" },
                        style = STYLE_BUFFS,
                        maxFrameCount = grid.effectiveMax,
                        candidateFilters = MergeCandidateFilters({ includeSpellIDs = includeMap }, BuffCandidateExtras(cfg)),
                        sortMethod = ResolveSortMethod(cfg),
                        sortDirection = ResolveSortDirection(cfg),
                    })
                    newContainer:SetAuraGroupLayout("spells", {
                        elementSpacing = pad, lineSpacing = grid.rowGap,
                        groupSpacing = pad, groupLineSpacing = grid.rowGap,
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
            -- maxFrameCount/layout/sort are refreshed here directly.
            ApplyGroupConfig(container, allChain, declared.buffs, STYLE_BUFFS, grid.effectiveMax, pad, grid.rowGap, cfg, BuffCandidateExtras(cfg))
            if declared.buffs.spells then
                container:SetAuraGroupMaxFrameCount("spells", grid.effectiveMax)
                container:SetAuraGroupLayout("spells", {
                    elementSpacing = pad, lineSpacing = grid.rowGap,
                    groupSpacing = pad, groupLineSpacing = grid.rowGap,
                })
                local liveIncludeMap = {}
                for i = 1, #spells do liveIncludeMap[spells[i]] = true end
                container:SetAuraGroupCandidateFilters("spells",
                    MergeCandidateFilters({ includeSpellIDs = liveIncludeMap }, BuffCandidateExtras(cfg)))
                local sortMethod, sortDirection = ResolveSortMethod(cfg), ResolveSortDirection(cfg)
                if sortMethod ~= nil and sortDirection ~= nil then
                    container:SetAuraGroupSortMethod("spells", sortMethod, sortDirection)
                end
            end
        end
    else
        local chain = BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, cfg) end, cfg.showAllDebuffs ~= false)
        ApplyGroupConfig(container, chain, declared.debuffs, STYLE_DEBUFFS, grid.effectiveMax, pad, grid.rowGap, cfg)
    end

    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview(isBuff and "buff" or "debuff", "default") end
end
ns.PAB_ApplyLiveConfig = ApplyLiveConfig

-- External Defensives' counterpart to ApplyLiveConfig above -- much
-- shorter since there is no spell/class selection to diff or rebuild: the
-- single "extdef" group's filter is permanent, only style/grid/anchor ever
-- change. Also handles the enabled toggle (ApplyLiveConfig has no
-- equivalent -- the two default bars have no enable/disable of their own).
local function ApplyExtDefLiveConfig()
    local s = PAB()
    if not (AK and s) then return end
    local container, parent = extDefContainer, extDefParent
    if not container or not parent then return end

    local cfg = DefaultExternalDefensivesCfg(s)
    local grid = ComputeGrid(true, cfg)
    local prev = lastSize.extdef

    -- Same CENTER-anchor size-change compensation as ApplyLiveConfig.
    local pos = s.extDefPos
    if pos and pos.point == "CENTER" and prev and (prev.w ~= grid.width or prev.h ~= grid.height) then
        pos.x = pos.x + (prev.w - grid.width) / 2
        pos.y = pos.y + (prev.h - grid.height) / 2
        parent:ClearAllPoints()
        parent:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    end
    lastSize.extdef = { w = grid.width, h = grid.height }

    parent:SetSize(grid.width, grid.height)
    parent:SetShown(cfg.enabled ~= false)

    local corner, liveSpec, vertical = BuildContainerSpec(parent, cfg, grid)
    local pad = cfg.padding or 5

    container:ClearAllPoints()
    container:SetPoint(corner, parent, corner, 0, 0)
    AK.SetContainerAnchor(container, corner)
    AK.SetContainerAxis(container, vertical)
    if liveSpec.layout.growthH then
        AK.SetContainerGrowth(container, liveSpec.layout.growthH, liveSpec.layout.growthV)
    end
    AK.SetContainerPadding(container, 0, 0, 0, 0)
    AK.SetContainerRowWidth(container, grid.rowWidth)

    container:SetAuraGroupMaxFrameCount("extdef", grid.effectiveMax)
    container:SetAuraGroupLayout("extdef", {
        elementSpacing = pad, lineSpacing = grid.rowGap,
        groupSpacing = pad, groupLineSpacing = grid.rowGap,
    })
    do
        local sortMethod, sortDirection = ResolveSortMethod(cfg), ResolveSortDirection(cfg)
        if sortMethod ~= nil and sortDirection ~= nil then
            container:SetAuraGroupSortMethod("extdef", sortMethod, sortDirection)
        end
    end

    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview("buff", "extdef") end
end
ns.PAB_ApplyExtDefLiveConfig = ApplyExtDefLiveConfig

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
    if barKey == "PAB_ExternalDefensives" then return DefaultExternalDefensivesCfg(s).growDirection or "LEFT" end
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
    elseif barKey == "PAB_ExternalDefensives" then
        DefaultExternalDefensivesCfg(s).growDirection = dir
        ApplyExtDefLiveConfig()
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
    -- Bug fix (2026-08-02): missing counterpart to RestyleBars' own
    -- AK.RestyleSoon(STYLE_BUFFS)/(STYLE_DEBUFFS) for the two default bars.
    -- Without this, writing AK.styles[styleKey] alone only affects buttons
    -- created AFTER this point (MakeInitializer runs once per button, see
    -- its own doc comment) -- any style-only edit (icon zoom, swipe,
    -- stack/duration position, ...) on a custom bar whose container/buttons
    -- already exist (the "spell list unchanged" cheap path further below)
    -- silently kept rendering the OLD style until the container was
    -- released and rebuilt for an unrelated reason. RestyleSoon re-runs
    -- ApplyStyleToRegions against every already-live button under that key.
    AK.RestyleSoon(styleKey)

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
        local corner, liveSpec, vertical = BuildContainerSpec(parent, bar, grid)
        local container = customBuffContainers[barId]
        container:ClearAllPoints()
        container:SetPoint(corner, parent, corner, 0, 0)
        AK.SetContainerAnchor(container, corner)
        AK.SetContainerAxis(container, vertical)
        if liveSpec.layout.growthH then
            AK.SetContainerGrowth(container, liveSpec.layout.growthH, liveSpec.layout.growthV)
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
                    elementSpacing = livePad, lineSpacing = grid.rowGap,
                    groupSpacing = livePad, groupLineSpacing = grid.rowGap,
                })
                local liveIncludeMap = {}
                for i = 1, #spells do liveIncludeMap[spells[i]] = true end
                container:SetAuraGroupCandidateFilters("spells",
                    MergeCandidateFilters({ includeSpellIDs = liveIncludeMap }, BuffCandidateExtras(bar)))
                local sortMethod, sortDirection = ResolveSortMethod(bar), ResolveSortDirection(bar)
                if sortMethod ~= nil and sortDirection ~= nil then
                    container:SetAuraGroupSortMethod("spells", sortMethod, sortDirection)
                end
            end
            customBuffDeclared[barId] = customBuffDeclared[barId] or {}
            ApplyGroupConfig(container, allChain, customBuffDeclared[barId], styleKey, grid.effectiveMax, bar.padding or 5, grid.rowGap, bar, BuffCandidateExtras(bar))
            return -- nothing structural to rebuild
        end
        AK.ReleaseContainer(container) -- safe: dedicated container, see doc comment above
        customBuffContainers[barId] = nil
    end

    local _, spec, specVertical = BuildContainerSpec(parent, bar, grid)
    local pad = bar.padding or 5
    AK.RequestContainer(parent, "player", spec, function(container)
        customBuffContainers[barId] = container
        AK.SetContainerAxis(container, specVertical)
        customBuffSig[barId] = sig
        customBuffDeclared[barId] = {}
        ApplyGroupConfig(container, allChain, customBuffDeclared[barId], styleKey, grid.effectiveMax, pad, grid.rowGap, bar, BuffCandidateExtras(bar))
        if #spells > 0 then
            local includeMap = {}
            for i = 1, #spells do includeMap[spells[i]] = true end
            AK.AddGroupToContainer(container, {
                key = "spells",
                filter = { "HELPFUL" },
                style = styleKey,
                maxFrameCount = grid.effectiveMax,
                candidateFilters = MergeCandidateFilters({ includeSpellIDs = includeMap }, BuffCandidateExtras(bar)),
                sortMethod = ResolveSortMethod(bar),
                sortDirection = ResolveSortDirection(bar),
            })
            container:SetAuraGroupLayout("spells", {
                elementSpacing = pad, lineSpacing = grid.rowGap,
                groupSpacing = pad, groupLineSpacing = grid.rowGap,
            })
        end
    end)
end

function ns.PAB_ReloadCustomBuffBar(barId)
    ReloadCustomBuffBarImpl(barId)
    RegisterPABCustomUnlock()
    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview("buff", barId) end
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
        -- Bar IDs are never reused, so this container/declared-set entry
        -- will never be looked up again -- drop our own tracking-table
        -- references (the container itself stays alive engine-side, only
        -- our addon-side bookkeeping is cleared) to avoid unbounded growth
        -- of these tables across long sessions of create/delete cycles.
        customDebuffParents[barId], customDebuffContainers[barId], customDebuffDeclared[barId] = nil, nil, nil
        return
    end

    local styleKey = CustomDebuffStyleKey(barId)
    AK.styles[styleKey] = BuildStyle(false, bar)
    -- Same bug fix as ReloadCustomBuffBarImpl above.
    AK.RestyleSoon(styleKey)

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

    local chain = BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, bar) end, bar.showAllDebuffs ~= false)
    local corner, spec, vertical = BuildContainerSpec(parent, bar, grid)
    local pad = bar.padding or 5

    if not customDebuffContainers[barId] then
        AK.RequestContainer(parent, "player", spec, function(container)
            customDebuffContainers[barId] = container
            AK.SetContainerAxis(container, vertical)
            customDebuffDeclared[barId] = {}
            ApplyGroupConfig(container, chain, customDebuffDeclared[barId], styleKey, grid.effectiveMax, pad, grid.rowGap, bar)
        end)
    else
        local container = customDebuffContainers[barId]
        container:ClearAllPoints()
        container:SetPoint(corner, parent, corner, 0, 0)
        AK.SetContainerAnchor(container, corner)
        AK.SetContainerAxis(container, vertical)
        if spec.layout.growthH then
            AK.SetContainerGrowth(container, spec.layout.growthH, spec.layout.growthV)
        end
        AK.SetContainerPadding(container, 0, 0, 0, 0)
        AK.SetContainerRowWidth(container, grid.rowWidth)
        ApplyGroupConfig(container, chain, customDebuffDeclared[barId], styleKey, grid.effectiveMax, pad, grid.rowGap, bar)
    end
end

function ns.PAB_ReloadCustomDebuffBar(barId)
    ReloadCustomDebuffBarImpl(barId)
    RegisterPABCustomUnlock()
    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview("debuff", barId) end
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
--  Options-page preview box (2026-08-02, Joel's explicit direction: embedded
--  inside the bar's own detail page, like Raid Frames' Buff Manager preview
--  -- NOT an on-screen overlay at the bar's real position like Raid Frames'
--  own raid-frame preview or Boss Frames' fake-aura preview). Shows FAKE
--  buffs/debuffs at the bar's REAL configured icon size/grid (iconSize,
--  iconsPerRow, maxRows, maxTotal -- via the same ComputeGrid used by the
--  live bar), styled with the bar's real BuildStyle/dispel-color output, so
--  icon size/count/row-wrap/growth direction/spacing/border/duration+stack
--  formatting all preview live as the user edits a bar's settings -- no
--  real aura data involved, no touching of the real bar/container at all.
--  Debuffs cycle through fake spellIDs carrying real dispel tokens (Magic/
--  Curse/Poison/Disease/Bleed) so BuildDispelColorMap's border coloring
--  previews too.
--
--  Icons are hand-built Frame/Texture/FontString regions, not AK buttons --
--  same reasoning as EllesmereUIUnitFrames.lua's Boss Frame
--  AttachFakeDebuffs/AttachFakeBuffs: AK's AuraContainer has no supported
--  way to receive synthetic aura data.
-------------------------------------------------------------------------------

-- Class-appropriate fake buff pool (2026-08-02, Joel: preview should draw
-- from buffs the player's own class actually has, not a fixed generic
-- list). Best-effort real, well-known spellIDs per class -- purely cosmetic
-- (icon texture only, see PreviewSpellIcon's fallback), a wrong/renamed ID
-- here just shows the generic question-mark icon, nothing else depends on
-- these being exactly right. Keyed by the class FILE token (UnitClass's
-- second return, e.g. "PRIEST"/"DEATHKNIGHT") -- verified WoW convention,
-- not an addon-specific vocabulary.
local CLASS_PREVIEW_BUFFS = {
    WARRIOR     = { 6673, 97462, 871, 12975, 1719, 107574, 184364, 118038, 46924, 3411 },
    PALADIN     = { 465, 6940, 1044, 1022, 31850, 86659, 642, 498, 31884, 105809 },
    HUNTER      = { 186257, 288613, 19574, 186265, 109304, 5384, 34477, 264735, 193530, 90355 },
    ROGUE       = { 13750, 1784, 5277, 31224, 1966, 2983, 13877, 121471, 185311, 1856 },
    PRIEST      = { 21562, 17, 139, 33206, 47788, 586, 47585, 41635, 6346, 64843 },
    DEATHKNIGHT = { 48792, 48707, 55233, 49039, 51052, 42650, 47568, 194844, 194679, 81256 },
    SHAMAN      = { 2825, 108271, 79206, 98008, 108281, 8178, 30823, 51490, 16188, 974 },
    MAGE        = { 1459, 11426, 190319, 45438, 55342, 12042, 108978, 66, 80353, 12051 },
    WARLOCK     = { 104773, 108416, 111400, 6789, 20707, 89808, 108503, 755, 6229, 5697 },
    MONK        = { 115203, 122470, 116849, 122783, 115176, 116841, 124682, 116680, 101643, 322507 },
    DRUID       = { 1126, 774, 22812, 61336, 102342, 106898, 29166, 33891, 192081, 108238 },
    DEMONHUNTER = { 191427, 198589, 196555, 203720, 196718, 258920, 217832, 195072, 191786, 188501 },
    EVOKER      = { 364342, 374348, 355936, 357170, 363916, 358267, 370960, 360995, 359816, 370537 },
}

-- Fallback used when the player's class token isn't recognized (defensive
-- only -- UnitClass always returns one of the tokens above on a live
-- character) or CLASS_PREVIEW_BUFFS is somehow missing an entry.
local PREVIEW_BUFF_SPELLS = { 21562, 1459, 1126, 6673 } -- Fort, Arcane Intellect, Mark of the Wild, Battle Shout

-- Cross-class/consumable buffs for the "All Buffs" preview fill (2026-08-03,
-- Joel: "random aus allen möglichen Buffs... + Zusatzbuffs" -- All Buffs has
-- no finite spell list, real raid buffs come from every class plus food/
-- flask/world-buff-style consumables, not just the player's own class).
-- Same 4 spell IDs EUI_RaidFrames_BuffManager2.lua's curated "consumables"
-- preset already uses (class="ALL" entries, maintainer-verified data,
-- 2026-07-21) -- duplicated here rather than cross-addon-referenced, since
-- RaidFrames' ns table isn't shared with this addon and isn't guaranteed
-- to even be loaded.
local EXTRA_WORLD_PREVIEW_BUFFS = { 1236998, 1236616, 1239479, 1236994 }

-- External Defensives bar preview (2026-08-02, Joel: should reflect actual
-- external-defensive-flavored spells, not the player's own class buffs --
-- these come from OTHER players' classes, so this is a fixed cross-class
-- pool rather than a UnitClass lookup like CLASS_PREVIEW_BUFFS).
local EXTDEF_PREVIEW_SPELLS = {
    33206,  -- Pain Suppression
    47788,  -- Guardian Spirit
    102342, -- Ironbark
    1022,   -- Blessing of Protection
    6940,   -- Blessing of Sacrifice
    116849, -- Life Cocoon
    196718, -- Darkness
    145629, -- Anti-Magic Zone
    98008,  -- Spirit Link Totem
    97462,  -- Rallying Cry
}

-- Shuffles a fresh copy of `source` (Fisher-Yates), never mutating the
-- source table itself.
local function ShuffleCopy(source)
    local out = {}
    for i = 1, #source do out[i] = source[i] end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

-- Builds a freshly shuffled copy of the "All Buffs" preview pool. Called
-- once per ns.PAB_BuildPreviewBox (NOT on every live-apply refresh -- the
-- resulting order is stashed on activePreview and reused by every
-- subsequent RenderPreviewIcons call for that box, so icons don't shuffle
-- their spell identity out from under the user on every slider tick, only
-- their style/position/count).
--
-- 2026-08-03 (Joel): was just the player's OWN class's 10 buffs, cycling
-- via modulo once a bar had more icon slots than that -- looked repetitive
-- for anything above ~10 icons and didn't represent what All Buffs
-- actually shows (every OTHER unit's buffs too, not just the player's
-- class). Now combines every class's curated CLASS_PREVIEW_BUFFS list
-- (13 classes x 10 = 130 entries) plus EXTRA_WORLD_PREVIEW_BUFFS'
-- consumables (134 total), shuffled together with no class priority --
-- Joel: show as many of the combined real class-buff pool as fit, only
-- falling back to something else ("notfalls") if the pool itself runs out,
-- which in practice never happens (134 is far larger than any configured
-- grid, maxTotal defaults to 32). A brief own-class-first variant was
-- tried and reverted the same session -- flat/uniform across all classes
-- is what's wanted.
local function BuildBuffPreviewPool()
    local combined = {}
    for _, spells in pairs(CLASS_PREVIEW_BUFFS) do
        for i = 1, #spells do combined[#combined + 1] = spells[i] end
    end
    for i = 1, #EXTRA_WORLD_PREVIEW_BUFFS do combined[#combined + 1] = EXTRA_WORLD_PREVIEW_BUFFS[i] end
    if #combined == 0 then combined = PREVIEW_BUFF_SPELLS end
    return ShuffleCopy(combined)
end

-- Expanded 2026-08-03 (Joel-supplied list, mostly recent Mythic+/dungeon
-- trash debuffs) from the original 6 entries -- unlike CLASS_PREVIEW_BUFFS,
-- there was no existing verified debuff catalog anywhere in this repo to
-- draw from, so this list came directly from Joel rather than being
-- independently sourced.
local PREVIEW_DEBUFF_SPELLS = {
    { id = 122,   dispel = "Magic" },   -- Frost Nova
    { id = 702,   dispel = "Curse" },   -- Curse of Weakness
    { id = 2823,  dispel = "Poison" },  -- Deadly Poison
    { id = 55095, dispel = "Disease" }, -- Frost Fever
    { id = 772,   dispel = "Bleed" },   -- Rend
    { id = 6788,  dispel = nil },       -- Weakened Soul -- NOT dispellable, previews the plain base border color (no dispel-type override)
    -- Magic
    { id = 434083, dispel = "Magic" }, -- Lightning Bolt Volley
    { id = 426735, dispel = "Magic" }, -- Void Rift
    { id = 428161, dispel = "Magic" }, -- Frost Shock
    { id = 409465, dispel = "Magic" }, -- Astral Bomb
    { id = 397911, dispel = "Magic" }, -- Mystic Vapors
    { id = 385963, dispel = "Magic" }, -- Burnout
    { id = 387564, dispel = "Magic" }, -- Arcane Eruption
    { id = 372749, dispel = "Magic" }, -- Ice Cutter
    { id = 369365, dispel = "Magic" }, -- Curse of Stone (Magic)
    { id = 388777, dispel = "Magic" }, -- Arcane Vulnerability
    -- Curse
    { id = 381692, dispel = "Curse" }, -- Decaying Strength
    { id = 377488, dispel = "Curse" }, -- Cursed Blood
    { id = 384978, dispel = "Curse" }, -- Hextrick Totem
    { id = 328664, dispel = "Curse" }, -- Curse of Desolation
    { id = 322817, dispel = "Curse" }, -- Lingering Curse
    { id = 340288, dispel = "Curse" }, -- Curse of Obliteration
    { id = 426308, dispel = "Curse" }, -- Void Curse
    { id = 433443, dispel = "Curse" }, -- Shadow Curse
    { id = 373509, dispel = "Curse" }, -- Withering Curse
    { id = 375602, dispel = "Curse" }, -- Curse of Decay
    -- Disease
    { id = 373391, dispel = "Disease" }, -- Choking Rotcloud
    { id = 374389, dispel = "Disease" }, -- Rotting Sickness
    { id = 409492, dispel = "Disease" }, -- Diseased Bite
    { id = 322486, dispel = "Disease" }, -- Plague Rot
    { id = 321821, dispel = "Disease" }, -- Viral Contagion
    { id = 330868, dispel = "Disease" }, -- Festering Rot
    { id = 325552, dispel = "Disease" }, -- Necrotic Rot
    { id = 345245, dispel = "Disease" }, -- Putrid Bile
    { id = 426660, dispel = "Disease" }, -- Diseased Claws
    { id = 209858, dispel = "Disease" }, -- Necrotic Rot (different id, same name)
    -- Poison
    { id = 322358, dispel = "Poison" }, -- Venomous Spit
    { id = 324859, dispel = "Poison" }, -- Toxic Pool
    { id = 373614, dispel = "Poison" }, -- Decaying Venom
    { id = 385039, dispel = "Poison" }, -- Venom Strike
    { id = 376149, dispel = "Poison" }, -- Poisoned Spear
    { id = 384620, dispel = "Poison" }, -- Noxious Stench
    { id = 326092, dispel = "Poison" }, -- Poison Bolt
    { id = 257483, dispel = "Poison" }, -- Pile of Bones (Poison)
    { id = 381664, dispel = "Poison" }, -- Toxic Trap
    { id = 428019, dispel = "Poison" }, -- Poisoned Fang
    -- Bleed
    { id = 196497, dispel = "Bleed" }, -- Ravenous Leap
    { id = 257775, dispel = "Bleed" }, -- Gushing Wound
    { id = 381379, dispel = "Bleed" }, -- Jagged Bite
    { id = 373735, dispel = "Bleed" }, -- Bloody Bite
    { id = 391191, dispel = "Bleed" }, -- Savage Peck
    { id = 372718, dispel = "Bleed" }, -- Rending Slash
    { id = 385356, dispel = "Bleed" }, -- Tear Flesh
    { id = 328181, dispel = "Bleed" }, -- Jagged Quarrel
    { id = 381514, dispel = "Bleed" }, -- Serrated Strike
    { id = 424414, dispel = "Bleed" }, -- Brutal Rend
    -- No dispel type
    { id = 240559, dispel = nil }, -- Grievous Wound
    { id = 226512, dispel = nil }, -- Sanguine Ichor
    { id = 257908, dispel = nil }, -- Oozing Leftovers
    { id = 268008, dispel = nil }, -- Snake Charm
    { id = 274358, dispel = nil }, -- Rending Maul
    { id = 320788, dispel = nil }, -- Frozen Binds
    { id = 323043, dispel = nil }, -- Blood Barrier
    { id = 373429, dispel = nil }, -- Gash Frenzy
    { id = 424889, dispel = nil }, -- Brutal Strike
}
local PREVIEW_DURATIONS = { 8, 15, 23, 41, 5, 30, 12, 60, 3, 18 }
local PREVIEW_STACKS = { nil, 3, nil, nil, 2, nil, nil, 5, nil, 1 } -- a few icons show a fake stack count, rest hidden

-- Shuffled once per box build, same reasoning as BuildBuffPreviewPool's own
-- doc comment (icons shouldn't swap identity on every slider tick).
local function BuildDebuffPreviewPool()
    return ShuffleCopy(PREVIEW_DEBUFF_SPELLS)
end

-- Memoized fake-icon texture lookup, same technique as EUI_RaidFrames_
-- BuffManager.lua's GetSpellIcon: C_Spell.GetSpellInfo's iconID, falling
-- back to the generic question-mark icon.
local previewIconCache = {}
local function PreviewSpellIcon(spellID)
    local cached = previewIconCache[spellID]
    if cached then return cached end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local icon = (info and info.iconID) or 134400
    previewIconCache[spellID] = icon
    return icon
end

-- Same memoization for the preview's "Name" sort simulation below.
local previewNameCache = {}
local function PreviewSpellName(spellID)
    local cached = previewNameCache[spellID]
    if cached then return cached end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local name = (info and info.name) or ""
    previewNameCache[spellID] = name
    return name
end

-- Best-effort preview simulation of the 4 curated sort methods (Default/
-- Expiration/Name/ImportantOnly, see EUI_PlayerAuraBars_ManagerPages.lua's
-- SORT_METHOD_VALUES). Verified 2026-08-03 against Blizzard's actual PTR
-- source (Gethe/wow-ui-source, ptr branch, AuraUtil.lua's
-- ExpirationAuraCompare/NameAuraCompare/ImportantOnlyAuraCompare): Expiration
-- = ascending expirationTime, Name = alphabetical spell name,
-- ImportantOnly = `C_Spell.IsSpellImportant(spellId)` first -- a native
-- per-spell flag, NOT dispel-type-based, and NOT debuff-specific (applies
-- equally to buffs; corrects an earlier wrong assumption that treated it as
-- "dispellable debuffs first" and no-opped it for buffs). The real engine's
-- comparators also weight player-cast/priority/canApplyAura ahead of the
-- named criterion and always tie-break on auraInstanceID -- not reproduced
-- here, since the preview's fake entries have no equivalent concepts; this
-- remains a simplified approximation of relative ORDER, not a byte-exact
-- match. `sortDirection == "Reverse"` flips every comparison -- including under
-- Default, since we don't know whether the real engine's Default ordering
-- itself respects direction; best-effort here is to at least reverse the
-- pool's own order rather than silently ignore the direction toggle (bug
-- fixed 2026-08-03: Default previously ignored `reverse` entirely, so
-- flipping only Sort Direction with Sort Method left at Default produced
-- no visible preview change). Never mutates `list` -- returns a fresh
-- array so callers can index it exactly like the original.
local function SortPreviewList(list, isBuff, cfg)
    local method = cfg.sortMethod or "Default"
    local reverse = cfg.sortDirection == "Reverse"
    if method == "Default" then
        if not reverse then return list end
        local out = {}
        local n = #list
        for i = 1, n do out[i] = list[n - i + 1] end
        return out
    end

    local tagged = {}
    for i = 1, #list do tagged[i] = { entry = list[i], idx = i } end

    if method == "Expiration" then
        table.sort(tagged, function(a, b)
            local da = PREVIEW_DURATIONS[((a.idx - 1) % #PREVIEW_DURATIONS) + 1]
            local db = PREVIEW_DURATIONS[((b.idx - 1) % #PREVIEW_DURATIONS) + 1]
            if da ~= db then
                if reverse then return da > db end
                return da < db
            end
            return a.idx < b.idx
        end)
    elseif method == "Name" then
        table.sort(tagged, function(a, b)
            local sa = isBuff and a.entry or a.entry.id
            local sb = isBuff and b.entry or b.entry.id
            local na, nb = PreviewSpellName(sa), PreviewSpellName(sb)
            if na ~= nb then
                if reverse then return na > nb end
                return na < nb
            end
            return a.idx < b.idx
        end)
    elseif method == "ImportantOnly" then
        table.sort(tagged, function(a, b)
            local sa = isBuff and a.entry or a.entry.id
            local sb = isBuff and b.entry or b.entry.id
            local ia = (C_Spell and C_Spell.IsSpellImportant and C_Spell.IsSpellImportant(sa)) and 0 or 1
            local ib = (C_Spell and C_Spell.IsSpellImportant and C_Spell.IsSpellImportant(sb)) and 0 or 1
            if ia ~= ib then
                if reverse then return ia > ib end
                return ia < ib
            end
            return a.idx < b.idx
        end)
    end

    local out = {}
    for i = 1, #tagged do out[i] = tagged[i].entry end
    return out
end

-- Identifies which bar-detail pane currently owns the visible preview box
-- (kind: "buff"/"debuff", id: "default"/"extdef"/a custom bar id), plus
-- that box's icon pool and the fontPath it was built with -- so a live-
-- apply hook can re-render in place without the detail pane rebuilding.
-- Reset to a fresh box every ns.PAB_BuildPreviewBox call, since the owning
-- detail pane itself is always torn down/rebuilt on structural changes
-- (switching bars, add/rename/delete) -- same lifecycle as every other
-- widget BuildCoreFields/BuildDisplayFields places on that pane.
local activePreview

-- Layer order matches the live bar exactly (AK's own ApplyStyleToRegions):
-- icon texture (btn, ARTWORK) below border (child frame, level+1) below
-- duration/stack text (textHost, child frame, level+2, ABOVE the border).
local function CreatePreviewIcon(box)
    local btn = CreateFrame("Frame", nil, box)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    -- "Nothing configured" placeholder (2026-08-03, Joel): a red X centered
    -- over the icon's flat grey fill, shown instead of a fake spell icon
    -- when the bar's real config would show zero buffs (Show All Buffs off,
    -- no Filters/Extra Spells resolved) -- see the noneConfigured check in
    -- RenderPreviewIcons. Reuses the existing close/X media icon rather
    -- than adding a new asset.
    btn.placeholder = btn:CreateTexture(nil, "OVERLAY")
    btn.placeholder:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    btn.placeholder:SetVertexColor(1, 0.2, 0.2, 1)
    btn.placeholder:Hide()
    btn.border = CreateFrame("Frame", nil, btn)
    btn.textHost = CreateFrame("Frame", nil, btn)
    btn.duration = btn.textHost:CreateFontString(nil, "OVERLAY")
    btn.stack = btn.textHost:CreateFontString(nil, "OVERLAY")
    return btn
end

-- Resolves a bar's live cfg + polarity from its (kind,id) identity -- same
-- shape every other engine-side lookup in this file uses (DefaultBuffsCfg/
-- DefaultExternalDefensivesCfg/PAB_GetCustomBuffBar/GetCustomDebuffBar).
local function ResolvePreviewCfg(kind, id)
    local s = PAB()
    if not s then return nil end
    if id == "default" then
        local isBuff = kind == "buff"
        return (isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)), isBuff
    elseif id == "extdef" then
        return DefaultExternalDefensivesCfg(s), true
    elseif kind == "buff" then
        return ns.PAB_GetCustomBuffBar(id), true
    else
        return ns.PAB_GetCustomDebuffBar(id), false
    end
end

-- Options-panel "pixel perfect" compensation (2026-08-02 fix): the whole
-- options window (EllesmereUI._mainFrame) runs at effective scale
-- baseScale*userScale (EllesmereUI.GetPopupScale()), while the real PAB
-- bars are parented directly to UIParent with no extra scale of their own
-- -- so identical iconSize/padding/border/text-size NUMBERS render visibly
-- SMALLER inside the options panel than on the real bar whenever that
-- panel scale is below 1 (the common case, "pixel perfect" scaling is
-- usually <1). Rather than SetScale the preview box itself (which would
-- desync it from the sy layout accounting used to place widgets below it),
-- every size-affecting cfg field is pre-multiplied by 1/GetPopupScale()
-- before being fed into BuildStyle/ComputeGrid, so the ENTIRE preview
-- (icon size, padding, border thickness, duration/stack font size and
-- offsets, box footprint) inflates by exactly the panel's own scale factor
-- and ends up the same TRUE on-screen size as the live bar -- both the
-- panel-scale slider and WoW's own UI Scale setting cancel out
-- algebraically (UIParent's effective scale multiplies both the live bar's
-- and the panel's on-screen size equally, so only the panel's OWN extra
-- SetScale factor matters).
local function PreviewScaleFactor()
    local s = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1
    if not s or s <= 0 then return 1 end
    return 1 / s
end

-- Duplicates BuildStyle's own `or <default>` fallbacks for every field
-- being scaled (32/5/1/11/0/11/0) since a size can't be scaled without
-- first resolving what "unset" means -- keep these in sync if BuildStyle's
-- defaults ever change. Non-size fields (growDirection, iconsPerRow/
-- maxRows/maxTotal, dispel colors, ...) pass through unchanged.
local function ApplyPreviewScale(cfg, comp)
    if comp == 1 then return cfg end
    local out = {}
    for k, v in pairs(cfg) do out[k] = v end
    out.iconSize = (cfg.iconSize or 32) * comp
    out.padding = (cfg.padding or 5) * comp
    out.rowSpacing = cfg.rowSpacing and (cfg.rowSpacing * comp) or nil
    out.borderSize = (cfg.borderSize or 1) * comp
    out.durationTextSize = (cfg.durationTextSize or 11) * comp
    out.durationOffsetX = (cfg.durationOffsetX or 0) * comp
    out.durationOffsetY = (cfg.durationOffsetY or 0) * comp
    out.stackTextSize = (cfg.stackTextSize or 11) * comp
    out.stackOffsetX = (cfg.stackOffsetX or 0) * comp
    out.stackOffsetY = (cfg.stackOffsetY or 0) * comp
    -- Icon Effects Per-Filter Size overrides need the same panel-scale
    -- compensation as iconSize above -- a per-block shallow copy (never
    -- mutating the real saved fxList/its filters/borderColor sub-tables)
    -- with just `.size` rescaled, so the preview's box footprint (see
    -- ComputeGrid's MaxIconSizeFor) and the actual fake-icon SetSize call
    -- (RenderPreviewIcons/ApplyPreviewFx) both read the correct on-screen
    -- pixel value.
    if cfg.fxList then
        local scaledFx = {}
        for i = 1, #cfg.fxList do
            local e = cfg.fxList[i]
            local se = {}
            for k, v in pairs(e) do se[k] = v end
            if se.size then se.size = se.size * comp end
            scaledFx[i] = se
        end
        out.fxList = scaledFx
    end
    return out
end

-- Preview area height budget (2026-08-04, Joel: Up/Down growth with several
-- icons-per-column made the preview box very tall very fast, pushing the
-- rest of the options page down). Applied as an EXTRA proportional shrink on
-- top of the panel-zoom compensation above -- combined into one factor so
-- iconSize/padding/rowSpacing/etc are only scaled once, not twice. Only ever
-- shrinks (extra <= 1); horizontal bars and short vertical ones are
-- unaffected since their unscaled grid.height is normally well under this.
local MAX_PREVIEW_CONTENT_HEIGHT = 330

local function ScaledPreviewCfg(cfg, isBuff)
    local comp = PreviewScaleFactor()
    local extra = 1
    if isBuff ~= nil then
        local probe = ApplyPreviewScale(cfg, comp)
        local grid = ComputeGrid(isBuff, probe)
        if grid.height > MAX_PREVIEW_CONTENT_HEIGHT then
            extra = MAX_PREVIEW_CONTENT_HEIGHT / grid.height
        end
    end
    return ApplyPreviewScale(cfg, comp * extra)
end

-- Renders (or re-renders in place) the fake icon grid using the bar's
-- CURRENT cfg -- safe to call on every live slider tick, only touches
-- plain addon-owned Frame/Texture/FontString regions, never the real bar.
-- Row/column math mirrors ComputeGrid/BuildContainerSpec's own corner-
-- anchored flow layout so the preview wraps exactly like the live bar.
local function HasAnyTrue(map)
    if not map then return false end
    for _, v in pairs(map) do if v then return true end end
    return false
end

-- True when the FILLER portion (whatever's left after real resolved spells,
-- see BuildPreviewSlots) should show fake example icons rather than an
-- empty placeholder. Buffs: ONLY All Buffs justifies fake filler -- it has
-- no finite spell list, so "more buffs than we can show" is a fair
-- approximation. Real Filters/Extra Spells DON'T (2026-08-03 fix, Joel:
-- "nur Icons zeigen, die laut Filter ausgewählt wurden") -- they resolve to
-- a concrete, finite spell set (ns.PAB_ResolveSpells, used directly in
-- BuildPreviewSlots below as real icons), so anything beyond that count is
-- genuinely empty capacity, not more content pretending to exist. Debuffs
-- have no per-spell resolution for class filters (they're AURA FILTER
-- STRING/category tokens, not a concrete spell list), so both Show All
-- Debuffs and any Base Filter class still justify fake filler there --
-- mirrors the exact condition ApplyLiveConfig/ReloadCustomDebuffBarImpl use
-- via BuildChain's includeCatchAll (2026-08-03: re-verified against the
-- current code -- debuffs CAN show truly nothing, contrary to an earlier,
-- stale session note).
local function HasFillerSource(isBuff, cfg)
    if isBuff then
        return cfg.showAllBuffs ~= false
    end
    return cfg.showAllDebuffs ~= false or HasAnyTrue(cfg.classFilters)
end

-- Builds one descriptor per icon slot (length `count`). Buffs: the bar's
-- REAL resolved spells (ns.PAB_ResolveSpells -- Filters' enabled spells +
-- Extra Spells, deliberately NOT including All Buffs, which has no finite
-- list) occupy the LEADING slots as {kind="extra", spellID=}, each with its
-- own real icon rather than the generic fake pool (2026-08-03, Joel: both
-- "Extra Spells always visible" and "only Filter-selected spells shown,
-- padded with placeholders" folded into the same mechanism -- a Filter
-- selection and an Extra Spell are equally "real content" from the
-- preview's point of view). Whatever's left is {kind="fake", entry=} when
-- HasFillerSource is true (All Buffs on), or {kind="placeholder"}
-- otherwise -- e.g. 4 resolved spells with room for 8 icons and All Buffs
-- off renders 4 real icons + 4 placeholders, never 4 fake ones. Debuffs
-- have no per-spell resolution, so every slot is fake-or-placeholder there.
-- ns.PAB_ResolveSpells dedupes by SPELL ID, but a filter's `alts` (rank/
-- alternate spell IDs for the same visual buff, see PAB_AllPresetSpells'
-- doc comment) resolve to DIFFERENT spell IDs sharing the SAME icon --
-- e.g. Mark of the Wild's rank alts would otherwise render as the same
-- icon twice in a row. 2026-08-03 fix (Joel: "manche Icons werden noch
-- doppelt gezeigt"): dedupe the preview's own real-spell list by ICON
-- TEXTURE, keeping the first (lowest spell ID, since ResolveSpells already
-- sorts numerically) occurrence per distinct icon. Preview-only -- the
-- real bar never has this problem, since it shows actual active aura
-- instances on the player, not an enumeration of every possible spell ID.
local function DedupeByIcon(ids)
    local seenIcons, out = {}, {}
    for i = 1, #ids do
        local icon = PreviewSpellIcon(ids[i])
        if not seenIcons[icon] then
            seenIcons[icon] = true
            out[#out + 1] = ids[i]
        end
    end
    return out
end

-- ns.PAB_ResolveSpells unions every selected Filter's + Extra Spells' ids
-- into ONE set, sorted purely numerically by spell id. With more resolved
-- spells than available icon slots, BuildPreviewSlots truncates to the
-- first `count` -- which, sorted by raw id, means whichever selected
-- Filter happens to contain the lowest-numbered spells wins the visible
-- slots outright, and every OTHER selected Filter (plus Extra Spells)
-- never appears at all. 2026-08-03 fix (Joel: "wenn mehrere Filter gewählt
-- sind, sollte die Preview aus einer Mischung... bestehen"): interleave
-- round-robin ACROSS sources (each selected Filter is its own source, Extra
-- Spells is one more) instead of a flat numeric sort, so truncation always
-- samples a bit of everything rather than exhausting one source first.
-- Deterministic (no math.random) on purpose -- unlike the fake buff/debuff
-- pools, this must NOT reshuffle on every live-apply refresh, and a stable
-- interleave achieves that without needing to stash shuffle state on
-- activePreview the way BuildBuffPreviewPool does.
local function BuildMixedRealSpells(cfg)
    local sources = {}
    if cfg.filters then
        local allFilters = ns.PAB_Filters and ns.PAB_Filters()
        if allFilters then
            for i = 1, #allFilters do
                local f = allFilters[i]
                if cfg.filters[f.id] then
                    local ids = {}
                    for id, on in pairs(f.spells) do
                        if on then ids[#ids + 1] = id end
                    end
                    if #ids > 0 then
                        table.sort(ids)
                        sources[#sources + 1] = ids
                    end
                end
            end
        end
    end
    if cfg.spells and #cfg.spells > 0 then
        local extra = {}
        for i = 1, #cfg.spells do extra[i] = cfg.spells[i] end
        sources[#sources + 1] = extra
    end

    local out = {}
    local idx = 1
    while true do
        local addedAny = false
        for s = 1, #sources do
            local id = sources[s][idx]
            if id then
                out[#out + 1] = id
                addedAny = true
            end
        end
        if not addedAny then break end
        idx = idx + 1
    end
    return out
end

local function BuildPreviewSlots(isBuff, cfg, list, listLen, count)
    local hasFiller = HasFillerSource(isBuff, cfg)
    -- Sort Method/Direction must apply to the REAL extra icons too, not
    -- just the fake filler pool (2026-08-03 fix, Joel: "Sort Method und
    -- Sort Direction funktioniert aber nicht wenn ich nicht Show All Buffs
    -- aktiv habe") -- with All Buffs off, content is mostly/only these
    -- real slots, so skipping them left the sort controls looking dead.
    -- SortPreviewList already handles plain buff spellID arrays (the shape
    -- extraIDs is in), same as the fake buff pool.
    --
    -- SELECT before SORT (2026-08-03 fix, Joel: changing Sort Method/
    -- Direction shouldn't "remix" which icons show, only their order):
    -- with more resolved+deduped spells than icon slots, sorting the FULL
    -- list first and truncating afterward meant a different sort put a
    -- different subset into the surviving first `count` -- i.e. changing
    -- sort could swap which spells appear, not just their order. Truncate
    -- to `count` on the stable, sort-independent mixed order FIRST, then
    -- sort only that fixed selection for display order.
    local mixed = isBuff and DedupeByIcon(BuildMixedRealSpells(cfg)) or nil
    local extraIDs
    if mixed then
        local numSelected = math.min(#mixed, count)
        local selected = {}
        for i = 1, numSelected do selected[i] = mixed[i] end
        extraIDs = SortPreviewList(selected, isBuff, cfg)
    end
    local numExtra = extraIDs and #extraIDs or 0
    local numFiller = count - numExtra
    local slots = {}
    for i = 1, numExtra do
        slots[i] = { kind = "extra", spellID = extraIDs[i] }
    end
    if numFiller > 0 then
        if hasFiller then
            -- Same select-before-sort fix as the real extra icons above
            -- (2026-08-03, Joel: applies to All Buffs' fake filler too):
            -- select the fixed filler slice from `list` (stable, shuffled
            -- once per box build, NOT sorted) first, then sort only that
            -- selection -- so Sort Method/Direction reorders the SAME fake
            -- icons already showing instead of pulling different ones in
            -- from elsewhere in the pool.
            local fillerSelected = {}
            for i = 1, numFiller do
                fillerSelected[i] = list[((i - 1) % listLen) + 1]
            end
            fillerSelected = SortPreviewList(fillerSelected, isBuff, cfg)
            for i = 1, numFiller do
                slots[numExtra + i] = { kind = "fake", entry = fillerSelected[i] }
            end
        else
            for i = 1, numFiller do
                slots[numExtra + i] = { kind = "placeholder" }
            end
        end
    end
    return slots
end

-- Icon Effects Per-Filter preview: applies a matched fx block's Glow/Border/
-- Size directly to a fake preview icon. Unlike the live PAB_ApplyDmFx, these
-- are plain addon-owned frames (CreatePreviewIcon), never secure engine
-- buttons -- no creation-window/taint restriction applies, so glow/border
-- hosts are lazily created wherever this first runs, and Glows.StartGlow is
-- called directly (no RestrictionSafeStyle gate -- that gate exists only
-- for the real, combat-lockdown-able aura buttons). `e` is nil when no
-- active fx block matches this icon's assigned preview category (or for
-- buffs/placeholder slots, which never carry one) -- clears any fx left
-- over from a previous render of this reused icon frame.
local function ApplyPreviewFx(btn, e)
    local Glows = EllesmereUI.Glows
    local gType = (e and e.glowType) or 0
    local gov = btn.fxGlow
    if gType > 0 and Glows and Glows.StartGlow then
        if not gov then
            gov = CreateFrame("Frame", nil, btn)
            gov:SetAllPoints(btn)
            gov:SetFrameLevel(btn.border:GetFrameLevel() + 2)
            gov:EnableMouse(false)
            btn.fxGlow = gov
        end
        gov:Show()
        local cr, cg, cb = e.glowR or 1.0, e.glowG or 0.776, e.glowB or 0.376
        if e.glowClassColor then
            local _, classFile = UnitClass("player")
            local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
        local sz = btn:GetWidth() or 18
        if (not gov._euiGlowActive) or gov._fxStyle ~= gType or gov._fxW ~= sz
           or gov._fxCR ~= cr or gov._fxCG ~= cg or gov._fxCB ~= cb then
            Glows.StartGlow(gov, gType, sz, cr, cg, cb)
            gov._fxStyle, gov._fxW = gType, sz
            gov._fxCR, gov._fxCG, gov._fxCB = cr, cg, cb
        end
    elseif gov then
        if gov._euiGlowActive and Glows and Glows.StopGlow then Glows.StopGlow(gov) end
        gov:Hide()
    end

    local PP = EllesmereUI.PP
    local bSize = (e and e.borderSize) or 0
    if bSize > 0 and PP then
        local host = btn.fxBorder
        if not host then
            host = CreateFrame("Frame", nil, btn)
            host:SetAllPoints(btn)
            host:SetFrameLevel(btn.border:GetFrameLevel() + 1)
            host:EnableMouse(false)
            PP.CreateBorder(host, 0, 0, 0, 1, 1)
            btn.fxBorder = host
        end
        local bc = e.borderColor or { r = 0, g = 0, b = 0 }
        PP.UpdateBorder(host, bSize, bc.r or 0, bc.g or 0, bc.b or 0, 1)
        host:Show()
    elseif btn.fxBorder then
        btn.fxBorder:Hide()
    end

    -- Size override is NOT applied here (2026-08-03, moved out): it now
    -- feeds directly into RenderPreviewIcons' own per-icon flow-packing
    -- layout (slotSize/colOffset/rowYOffset), which needs to know each
    -- icon's real footprint BEFORE positioning any of them -- applying it
    -- here, after the anchor is already placed, would either be redundant
    -- with that or (if this ran first) invisible to the layout math.
end

-- `pool` (2026-08-03 renamed from buffPool -- now shuffled once per box
-- build for BOTH polarities, see BuildBuffPreviewPool/BuildDebuffPreviewPool)
-- is the box's own stable, pre-shuffled fake-icon pool.
local function RenderPreviewIcons(box, icons, isBuff, cfg, fontPath, pool)
    cfg = ScaledPreviewCfg(cfg, isBuff)
    local style = BuildStyle(isBuff, cfg)
    local dcMap = (not isBuff) and BuildDispelColorMap(cfg) or nil
    local grid = ComputeGrid(isBuff, cfg)

    -- The box itself (and therefore the header darken band/divider below
    -- it, see ns.PAB_BuildPreviewBox) is FIXED at its build-time size
    -- (2026-08-02, Joel: divider/box should stay put, only the CONTENT
    -- should change on a live settings edit). Icons are instead centered
    -- as a BLOCK inside the box's current (unchanging) width/height, using
    -- box:GetCenter()-relative offsets rather than anchoring to one of the
    -- box's own corners -- growDirection still decides which edge of that
    -- centered block fills first (matches the live bar's own fill order),
    -- it just no longer moves the box/divider around while doing it.
    local growDir = cfg.growDirection or "LEFT"
    local wrapDir = cfg.iconWrapDirection or "LEFT"
    local vertical = (growDir == "UP" or growDir == "DOWN")
    local corner = CornerFor(growDir, wrapDir)
    local pad = cfg.padding or 5
    local rowGap = cfg.rowSpacing or 12
    local iconSize = cfg.iconSize or 32
    local cols = math.max(1, cfg.iconsPerRow or (isBuff and 11 or 8))
    local count = grid.effectiveMax
    -- NOT sorted here anymore (2026-08-03 fix, same "select before sort"
    -- reasoning as the real extra icons below): `list` is much larger than
    -- `count` (the fake pools are 134/66 entries), so sorting the WHOLE
    -- pool before BuildPreviewSlots selects its filler slice would let a
    -- sort change pull a DIFFERENT subset of fake icons into view, not
    -- just reorder the ones already showing. BuildPreviewSlots now selects
    -- the fixed filler slice from this stable, shuffled-once-per-box-build
    -- order FIRST, then sorts only that selection.
    local list = (pool and #pool > 0 and pool) or (isBuff and PREVIEW_BUFF_SPELLS or PREVIEW_DEBUFF_SPELLS)
    local listLen = #list
    local slots = BuildPreviewSlots(isBuff, cfg, list, listLen, count)

    -- Icon Effects Per-Filter preview (debuffs only): deliberately NOT tied
    -- to the bar's own active Base Filters/Show All Debuffs state (2026-08-
    -- 03 fix, Joel: "you won't normally select the same category in both
    -- places" -- requiring a matching Base Filter meant the preview usually
    -- showed nothing, since the two dropdowns serve different purposes and
    -- aren't meant to be set identically). Instead, every ACTIVE fx block
    -- claims 1-2 fake icon slots outright, regardless of which categories
    -- are actually enabled for display -- a simple "here's what this
    -- configured effect looks like" demonstration, not a claim that these
    -- specific icons represent that category on a real bar (which the fake
    -- pool has no Blizzard boss/role/priority/... flags to support anyway).
    local fxBySlot
    if not isBuff then
        local fxListView = PAB_FxListView(cfg.fxList)
        if fxListView and #fxListView > 0 then
            local fakeIdx = {}
            for i = 1, #slots do
                if slots[i].kind == "fake" then fakeIdx[#fakeIdx + 1] = i end
            end
            local nFake = #fakeIdx
            if nFake > 0 then
                fxBySlot = {}
                for bi = 1, #fxListView do
                    local perBlock = math.min(2, nFake)
                    for k = 1, perBlock do
                        local pos = ((bi - 1) * 2 + (k - 1)) % nFake + 1
                        fxBySlot[fakeIdx[pos]] = fxListView[bi]
                    end
                end
            end
        end
    end

    local rows = math.max(1, math.ceil(count / cols))

    -- Real per-icon flow packing (2026-08-03 fix, Joel: the earlier uniform
    -- `cellSize` reservation stopped the oversized-icon overlap but left too
    -- much gap around every OTHER, normal-sized icon -- every cell paid the
    -- worst-case size even when only one icon in the whole grid needed it).
    -- Each slot's OWN actual render size (its fx Size override, or the
    -- bar's base iconSize) now drives its own footprint directly, so
    -- spacing between normal icons stays tight and only an oversized icon's
    -- immediate neighbors get pushed out -- true flow-layout behavior
    -- rather than a uniform cell grid.
    local slotSize = {}
    for i = 1, count do
        local e = fxBySlot and fxBySlot[i]
        local sz = e and tonumber(e.size)
        slotSize[i] = (sz and sz > 0) and sz or iconSize
    end

    local rowWidth, rowHeight, colOffset, rowYOffset = {}, {}, {}, {}
    do
        local runningX, runningY = {}, 0
        for r = 0, rows - 1 do runningX[r] = 0 end
        for i = 1, count do
            local r = math.floor((i - 1) / cols)
            colOffset[i] = runningX[r]
            runningX[r] = runningX[r] + slotSize[i] + pad
            rowHeight[r] = math.max(rowHeight[r] or 0, slotSize[i])
        end
        for r = 0, rows - 1 do
            rowWidth[r] = math.max(0, runningX[r] - pad) -- drop the trailing gap
        end
        for r = 0, rows - 1 do
            rowYOffset[r] = runningY
            runningY = runningY + (rowHeight[r] or 0) + rowGap
        end
    end
    -- blockW/blockH are generic axis extents: "within-line" (rowWidth, the
    -- primary/fill axis) and "across-lines" (the wrap axis) -- screen X/Y
    -- only for horizontal growth. Vertical growth (Up/Down, 2026-08-04) swaps
    -- which one maps to X vs Y in the placement loop below.
    local blockW = 0
    for r = 0, rows - 1 do blockW = math.max(blockW, rowWidth[r] or 0) end
    local blockH = math.max(0, (rowYOffset[rows - 1] or 0) + (rowHeight[rows - 1] or 0))
    local halfPrimary, halfCross = blockW / 2, blockH / 2
    local growUp = (growDir == "UP")
    local wrapRight = (wrapDir == "RIGHT")

    for i = 1, math.max(count, #icons) do
        if i <= count then
            local btn = icons[i]
            if not btn then
                btn = CreatePreviewIcon(box)
                icons[i] = btn
            end

            local row = math.floor((i - 1) / cols)
            local withinLineStep = colOffset[i]
            local acrossLinesStep = rowYOffset[row]
            -- btn's own anchor point is `corner` (matching growDirection/
            -- iconWrapDirection), placed at an offset from the box's CENTER
            -- -- see the block-centering comment above `local rows = ...`.
            -- Vertical growth (Up/Down) swaps which step drives X vs Y: the
            -- within-line step (icons stacking inside one column) becomes Y,
            -- the across-lines step (columns wrapping sideways) becomes X --
            -- mirrors the corner/growthH/growthV swap in CornerFor/
            -- BuildContainerSpec used by the real (non-preview) bars.
            local btnX, btnY
            if vertical then
                btnY = growUp and (-halfPrimary + withinLineStep) or (halfPrimary - withinLineStep)
                btnX = wrapRight and (-halfCross + acrossLinesStep) or (halfCross - acrossLinesStep)
            else
                btnX = (corner == "TOPRIGHT") and (halfPrimary - withinLineStep) or (-halfPrimary + withinLineStep)
                btnY = halfCross - acrossLinesStep
            end
            btn:ClearAllPoints()
            btn:SetPoint(corner, box, "CENTER", btnX, btnY)
            btn:SetSize(slotSize[i], slotSize[i])

            local slot = slots[i]
            local dispel

            if slot.kind == "placeholder" then
                -- Flat grey box + centered red X (see CreatePreviewIcon's
                -- doc comment) instead of a fake spell icon -- nothing
                -- would actually render on the real bar here, so the
                -- preview shouldn't imply otherwise with example buffs.
                -- Border still draws (2026-08-03, Joel) -- only the icon
                -- texture and duration/stack text are placeholder-specific.
                btn.icon:SetTexture(nil)
                btn.icon:SetColorTexture(0.16, 0.16, 0.16, 1)
                btn.placeholder:ClearAllPoints()
                local inset = iconSize * 0.2
                btn.placeholder:SetPoint("TOPLEFT", btn.icon, "TOPLEFT", inset, -inset)
                btn.placeholder:SetPoint("BOTTOMRIGHT", btn.icon, "BOTTOMRIGHT", -inset, inset)
                btn.placeholder:Show()
                btn.textHost:Hide()
            else
                btn.placeholder:Hide()
                btn.textHost:Show()

                local spellID
                if slot.kind == "extra" then
                    -- Real Extra Spell: always its own actual icon, never
                    -- folded into the fake cycling pool.
                    spellID = slot.spellID
                else -- "fake"
                    local entry = slot.entry
                    spellID = isBuff and entry or entry.id
                    dispel = (not isBuff) and entry.dispel or nil
                end

                btn.icon:SetTexture(PreviewSpellIcon(spellID))
                local z = style.iconZoom or 0.055
                btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
            end

            btn.border:SetAllPoints(btn.icon)
            btn.border:SetFrameLevel(btn:GetFrameLevel() + 1)
            local PP = EllesmereUI and EllesmereUI.PanelPP
            if PP and style.border then
                local br, bg, bb, ba = style.border[1], style.border[2], style.border[3], style.border[4]
                if dispel and dcMap and dcMap[dispel] then
                    local c = dcMap[dispel]
                    br, bg, bb, ba = c.r, c.g, c.b, 1
                end
                local size = style.border.size or 1
                -- PP.CreateBorder is create-ONCE-only -- a second call with a
                -- different size/color on an already-created host is a
                -- silent no-op (see EllesmereUI.lua's PP.CreateBorder: early-
                -- returns the cached container without touching bd.borderSize
                -- /borderColor). Live border-size/color changes on an
                -- already-created host must go through PP.UpdateBorder
                -- instead -- exactly the borderMade branch EllesmereUI_
                -- AuraKit.lua's own ApplyStyleToRegions uses for the real
                -- bar's borders. Without this, the preview's border only
                -- ever "moved" by toggling Hide()/Show() at size 0, never
                -- actually re-sized above 0 (bug fixed 2026-08-02).
                if btn.borderMade then
                    PP.UpdateBorder(btn.border, size, br, bg, bb, ba)
                elseif PP.CreateBorder then
                    PP.CreateBorder(btn.border, br, bg, bb, ba, size, "OVERLAY", 7)
                    btn.borderMade = true
                end
                if PP.ShowBorder then PP.ShowBorder(btn.border) else btn.border:Show() end
            else
                if PP and PP.HideBorder then PP.HideBorder(btn.border) else btn.border:Hide() end
            end

            if slot.kind ~= "placeholder" then
                btn.textHost:SetAllPoints(btn)
                btn.textHost:SetFrameLevel(btn:GetFrameLevel() + 2)

                btn.duration:ClearAllPoints()
                btn.duration:SetFont(fontPath, style.durationFontSize or 11, "OUTLINE")
                btn.duration:SetPoint(style.durationPoint or "TOP", btn, style.durationRelPoint or "BOTTOM",
                    style.durationX or 0, style.durationY or 0)
                local dc = style.durationColor
                btn.duration:SetTextColor(dc and dc.r or 1, dc and dc.g or 1, dc and dc.b or 1)
                btn.duration:SetShown(not style.hideDurationText)
                btn.duration:SetText(PREVIEW_DURATIONS[((i - 1) % #PREVIEW_DURATIONS) + 1])

                btn.stack:ClearAllPoints()
                btn.stack:SetFont(fontPath, style.stackFontSize or 11, "OUTLINE")
                btn.stack:SetPoint(style.stackPoint or "TOP", btn, style.stackPoint or "TOP",
                    style.stackX or 0, style.stackY or 0)
                local sc = style.stackColor
                btn.stack:SetTextColor(sc and sc.r or 1, sc and sc.g or 1, sc and sc.b or 1)
                local stackVal = PREVIEW_STACKS[((i - 1) % #PREVIEW_STACKS) + 1]
                btn.stack:SetShown(style.showStacks ~= false and stackVal ~= nil)
                if stackVal then btn.stack:SetText(stackVal) end
            end

            -- Icon Effects Per-Filter preview: nil clears any fx left over on
            -- a reused icon frame from a previous render (slot not claimed
            -- this pass, or block removed/deactivated).
            ApplyPreviewFx(btn, fxBySlot and fxBySlot[i])

            btn:Show()
        elseif icons[i] then
            icons[i]:Hide()
        end
    end
end

-- Public hook for the Options UI: builds this bar's embedded preview box
-- entirely OUTSIDE the scrollable settings area (2026-08-02, Joel: the
-- scrollbar must only scroll the settings fields below, never the preview
-- itself) -- box, "PREVIEW" label, darkened header band, and divider are
-- all children of `outerFrame` directly (the detail pane's own top-level,
-- non-scrolling frame that title/desc already live on), sized to the bar's
-- REAL configured grid (ComputeGrid, same as the live bar) and horizontally
-- centered (anchored TOP-to-TOP rather than TOPLEFT).
--
-- The "PREVIEW" section-header label is wrapped in a small local
-- padDiff-compensated + clipped frame (same CONTENT_PAD-vs-20px trick as
-- EUI_PlayerAuraBars_ManagerPages.lua's WrapCompensatedBody, duplicated in
-- miniature here rather than shared -- W:SectionHeader assumes a 45px
-- CONTENT_PAD margin, but this detail pane only reserves 20px) -- the box
-- itself needs no such compensation since it's positioned via a plain
-- SetPoint, not a W: widget.
--
-- Geometry (box size, header darken band, divider Y, and the caller's
-- scroll-area top offset via the onResize hook -- see PAB_MaybeRefreshPreview
-- below) is recomputed on every live-apply refresh too, not just here at
-- build time -- a row/column/icon-count change (Icons Per Row, Max Rows, Max
-- Total, Icon Size, Row Spacing, ...) changes the grid's real footprint, and
-- a box that stayed the old size would either clip the new icons (grid grew)
-- or leave a stale gap above the settings fields (grid shrank) until the
-- next structural rebuild (switching bars/tabs). 2026-08-02: Joel originally
-- had this fixed at build-time only ("box and divider should stay put") to
-- avoid the settings fields below jumping around on every slider tick --
-- that still holds for icon CONTENT (see RenderPreviewIcons' block-centering
-- comment, unchanged), just not for the box's own footprint, which must
-- track the grid it's supposed to contain.
--   outerFrame: the detail pane's own top-level frame (title/desc's parent)
--   startY: outerFrame-local Y to start placing the PREVIEW label/box at
--           (the caller's fixed offset below title/desc, e.g. -50)
--   kind: "buff" or "debuff"
--   id:   "default" | "extdef" | a custom bar's id
--   cfg:  the same cfg table the caller already resolved for its own
--         ApplyBar/field builders
-- Returns the outerFrame-local Y where the preview area ends -- the caller
-- passes this straight to WrapCompensatedBody(outerFrame, returnedY) as the
-- scrollable settings area's own top offset.
function ns.PAB_BuildPreviewBox(outerFrame, fontPath, startY, kind, id, cfg)
    local isBuff = kind == "buff"
    local sy = startY

    do
        local contentPad = EllesmereUI.CONTENT_PAD or 45
        local padDiff = contentPad - 20
        local visibleW = outerFrame:GetWidth()
        -- 2026-08-03 (Joel: too much dead space between the title/desc and
        -- the actual preview box): was W:SectionHeader, a shared widget
        -- fixed at 40px tall with its label anchored 8px from the BOTTOM of
        -- that block -- meant for spacing consistency among stacked option
        -- rows elsewhere, not this floating title/desc/box context, and it
        -- left ~20px of pure blank padding above the "PREVIEW" text with
        -- nothing else needing that room here. Replaced with a lightweight,
        -- purpose-built label + separator at a fraction of the height,
        -- matching SectionHeader's own look (EllesmereUI.TEXT_SECTION/
        -- BORDER_COLOR, both already exposed on the shared EllesmereUI
        -- table) without touching the shared widget file.
        local hdrH = 18

        -- Shift lives on the clipping frame itself (hdrClip), not on
        -- hdrBody inside it -- mirrors WrapCompensatedBody's own fix in
        -- EUI_PlayerAuraBars_ManagerPages.lua (see that file's doc comment:
        -- a "shift the child instead of the clip frame" structure that's
        -- mathematically equivalent measured a real ~30px extra gap
        -- in-game vs RaidFrames' reference, which shifts the clip/scroll
        -- frame itself).
        local hdrClip = CreateFrame("Frame", nil, outerFrame)
        hdrClip:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", -padDiff, sy)
        hdrClip:SetSize(math.max(visibleW, 1) + padDiff * 2, hdrH)
        hdrClip:SetClipsChildren(true)

        local hdrBody = CreateFrame("Frame", nil, hdrClip)
        hdrBody:SetSize(visibleW + padDiff * 2, hdrH)

        local TS = EllesmereUI.TEXT_SECTION or { r = 0.5, g = 0.5, b = 0.5, a = 1 }
        local label = hdrBody:CreateFontString(nil, "OVERLAY")
        label:SetFont(fontPath, 12, "")
        label:SetTextColor(TS.r, TS.g, TS.b, TS.a or 1)
        label:SetPoint("BOTTOMLEFT", hdrBody, "BOTTOMLEFT", contentPad, 0)
        label:SetText(EllesmereUI.L("PREVIEW"))

        local BC = EllesmereUI.BORDER_COLOR or { r = 1, g = 1, b = 1 }
        local sep = hdrBody:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(BC.r, BC.g, BC.b, 0.02)
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", hdrBody, "BOTTOMLEFT", contentPad, 0)
        sep:SetPoint("BOTTOMRIGHT", hdrBody, "BOTTOMRIGHT", -contentPad, 0)

        sy = sy - hdrH
    end

    -- Sized from the SCALED cfg (see ScaledPreviewCfg/PreviewScaleFactor's
    -- own doc comment) so the box's footprint matches what
    -- RenderPreviewIcons actually draws into it.
    local grid = ComputeGrid(isBuff, ScaledPreviewCfg(cfg, isBuff))
    -- +30 (scaled) extra vertical room for duration/stack text rendering
    -- above/below the icon grid itself -- ComputeGrid's own width/height
    -- are the icon grid's bounding box only (same as the real bar), text
    -- can render outside that box depending on Duration/Stacks Position.
    local boxHeight = grid.height + 30 * PreviewScaleFactor()
    local box = CreateFrame("Frame", nil, outerFrame)
    box:SetPoint("TOP", outerFrame, "TOP", 0, sy)
    box:SetSize(math.max(grid.width, 1), boxHeight)

    local headerBg = outerFrame._pabPreviewHeaderBg
    if not headerBg then
        headerBg = outerFrame:CreateTexture(nil, "BACKGROUND")
        headerBg:SetColorTexture(0, 0, 0, 0.15)
        outerFrame._pabPreviewHeaderBg = headerBg
    end
    headerBg:ClearAllPoints()
    headerBg:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 0, 0)
    headerBg:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, 0)

    local divider = outerFrame._pabPreviewDivider
    if not divider then
        divider = outerFrame:CreateTexture(nil, "OVERLAY")
        divider:SetColorTexture(1, 1, 1, 0.10)
        divider:SetHeight(1)
        outerFrame._pabPreviewDivider = divider
    end

    local bottomY = sy - boxHeight - 10
    headerBg:SetHeight(math.abs(bottomY))
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 0, bottomY)
    divider:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, bottomY)

    local icons = {}
    -- Shuffled once per box build, not per refresh -- see BuildBuffPreviewPool's
    -- own doc comment for why (icons shouldn't swap spell identity on every
    -- slider tick, only their style/position/count). External Defensives
    -- gets its own cross-class pool (EXTDEF_PREVIEW_SPELLS) instead of the
    -- player's class buffs -- those auras come from OTHER players' classes.
    -- Debuffs get BuildDebuffPreviewPool() (2026-08-03, same shuffle-once
    -- treatment extended to the debuff side).
    local pool
    if isBuff then
        pool = (id == "extdef") and ShuffleCopy(EXTDEF_PREVIEW_SPELLS) or BuildBuffPreviewPool()
    else
        pool = BuildDebuffPreviewPool()
    end
    activePreview = {
        kind = kind, id = id, box = box, icons = icons, fontPath = fontPath, pool = pool,
        outerFrame = outerFrame, boxTopY = sy, headerBg = headerBg, divider = divider,
    }
    RenderPreviewIcons(box, icons, isBuff, cfg, fontPath, pool)

    return bottomY
end

-- Registers a callback the caller's WrapCompensatedBody (EUI_PlayerAuraBars_
-- ManagerPages.lua) uses to reposition its scroll frame's top edge whenever
-- PAB_MaybeRefreshPreview resizes the box below -- see that function's doc
-- comment for why the box's footprint isn't fixed at build time anymore.
-- Set on activePreview (not a standalone module-level var) so a callback
-- from a since-torn-down detail pane can never fire against the wrong
-- pane's box after a tab switch rebuilds activePreview.
function ns.PAB_SetPreviewResizeHandler(fn)
    if activePreview then activePreview.onResize = fn end
end

-- Piggyback hook, called at the end of every live-apply path (ApplyLiveConfig,
-- ApplyExtDefLiveConfig, PAB_ReloadCustomBuffBar, PAB_ReloadCustomDebuffBar)
-- so a currently-open preview box stays in sync with slider drags/dropdown
-- changes without EUI_PlayerAuraBars_ManagerPages.lua needing to know the
-- preview exists or wrap its ApplyBar() closures.
PAB_MaybeRefreshPreview = function(kind, id)
    if not (activePreview and activePreview.kind == kind and activePreview.id == id) then return end
    local cfg, isBuff = ResolvePreviewCfg(kind, id)
    if not cfg then return end

    -- Re-derive the box's footprint from the SAME scaled grid RenderPreviewIcons
    -- is about to draw into, exactly mirroring PAB_BuildPreviewBox's own
    -- boxHeight/bottomY math (kept in sync manually -- see that function's
    -- doc comment for why this can't just be skipped/left build-time-only).
    local grid = ComputeGrid(isBuff, ScaledPreviewCfg(cfg, isBuff))
    local boxHeight = grid.height + 30 * PreviewScaleFactor()
    activePreview.box:SetSize(math.max(grid.width, 1), boxHeight)

    local bottomY = activePreview.boxTopY - boxHeight - 10
    if activePreview.headerBg then
        activePreview.headerBg:SetHeight(math.abs(bottomY))
    end
    if activePreview.divider and activePreview.outerFrame then
        activePreview.divider:ClearAllPoints()
        activePreview.divider:SetPoint("TOPLEFT", activePreview.outerFrame, "TOPLEFT", 0, bottomY)
        activePreview.divider:SetPoint("TOPRIGHT", activePreview.outerFrame, "TOPRIGHT", 0, bottomY)
    end
    if activePreview.onResize then activePreview.onResize(bottomY) end

    RenderPreviewIcons(activePreview.box, activePreview.icons, isBuff, cfg, activePreview.fontPath, activePreview.pool)
end

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

