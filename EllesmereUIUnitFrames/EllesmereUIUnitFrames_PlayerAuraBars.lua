if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIUnitFrames_PlayerAuraBars.lua
--  12.1 AuraKit-based player buff/debuff bars.
-------------------------------------------------------------------------------

local _, ns = ...

-------------------------------------------------------------------------------
--  Settings accessor
-------------------------------------------------------------------------------

-- Never nil, so CreateBars() never bails before Options has written this profile
-- table. Unconfigured -> every class toggle false, but BuildChain() still emits
-- the "all" catch-all per polarity, so bars show everything before settings exist.
local function PAB()
    local db = ns.db
    return db and db.profile and db.profile.playerAuraBars
end
-- WoW Forever: every read passes the one-time buff clear first
-- (EllesmereUI_Migration.lua; "fvBuffWipe" is its frozen mark). The table is
-- cleared in place, so the same table returns; a marked one costs one field
-- read. Nothing here runs on other clients.
if EllesmereUI.FvBW then
    local fv = EllesmereUI.FvBW
    PAB = function()
        local db = ns.db
        local s = db and db.profile and db.profile.playerAuraBars
        if s and s.fvBuffWipe == nil then fv.ProcessUF(db.profile, nil, "live") end
        return s
    end
end

-------------------------------------------------------------------------------
--  Shared class vocabulary (from EUI_UnitFrames_AuraContainers.lua)
--  RAID/RAID_IN_COMBAT count as real debuff categories: they are per-aura flags
--  (Blizzard's raid-frame curation baked into the aura), not roster-size-dependent,
--  so they filter meaningfully solo.
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

-- No candidate class is hidden today; kept behind an accessor so a future hide is one line.
local function VisibleCandidateClasses()
    return ns.UF_CandidateClasses
end

-- Display metadata for the Options class-toggle dropdown, keyed by .skey (matches
-- ClassEnabled's db-field convention). Label/tooltip text is verbatim from
-- EUI_UnitFrames_Options.lua's buffFilterItems/debuffFilterItems for suite-wide consistency.
local CLASS_LABELS = {
    Dispellable       = { "Dispellable By You", "Shows only auras with a dispel type you can dispel" },
    CrowdControl      = { "Crowd Control",      "Shows only crowd-control auras" },
    BigDefensive      = { "Big Defensive",      "Shows only major defensive cooldowns" },
    ExternalDefensive = { "External Defensive", "Shows only external defensive cooldowns cast on the unit" },
    Cancelable        = { "Cancelable",         "Shows only buffs that can be canceled" },
    Stealable         = { "Stealable",          "Shows only buffs you can spellsteal or purge" },
    BossAura          = { "Boss Debuffs",       "Shows only debuffs applied by bosses" },
    RoleAura          = { "Role Debuffs",       "Shows only debuffs flagged for your role" },
    -- "Important" matches Raid Frames' wording for this isPriorityAura flag.
    PriorityAura      = { "Important",          "Shows only debuffs Blizzard flags as important" },
    NonPlayer         = { "Non-Player Auras",   "Shows only debuffs not caused by any player or player pet (this is what shows most pve debuffs, do not check this while All Debuffs is selected!" },
    -- Any dispel-typed debuff whether removable or not; distinct from "Dispellable
    -- By You". Mirrors Raid Frames' "Dispels" filter.
    DispelTyped       = { "Dispels", "Shows any debuff with a dispel type (Magic, Curse, Disease, Poison, Bleed), even if you cannot remove it" },
    Raid              = { "Raid",            "Shows only debuffs from Blizzard's curated raid-frame debuff set" },
    RaidInCombat      = { "Raid In Combat",  "Shows only the stricter in-combat subset of the raid set" },
    -- Less common filters (below the divider in the Filters dropdown).
    CastByMe          = { "Cast By You",     "Debuffs applied by you or your pet" },
    AnyPlayer         = { "From Any Player", "Debuffs caused by any player or player pet. The opposite of Non-Player Auras; checking one clears the other" },
    DispelMagic       = { "Magic",           "Debuffs with the Magic dispel type" },
    DispelCurse       = { "Curse",           "Debuffs with the Curse dispel type" },
    DispelPoison      = { "Poison",          "Debuffs with the Poison dispel type" },
    DispelDisease     = { "Disease",         "Debuffs with the Disease dispel type" },
    DispelBleed       = { "Bleed",           "Debuffs with the Bleed dispel type" },
    CanApply          = { "Can Apply Aura",  "Debuffs your own class is able to apply" },
}

-- Non-Player Auras and From Any Player share one engine field: checking either
-- (in either lane) clears the other from both lanes. Keyed by .skey.
local EXCLUSIVE_SKEY = { NonPlayer = "AnyPlayer", AnyPlayer = "NonPlayer" }
ns.PAB_ExclusiveSkey = EXCLUSIVE_SKEY

-- Curated debuff filter list: exact vocabulary+order parity with Raid Frames' debuff
-- filters (EUI_RaidFrames_ManagerPages.lua TILE_FILTER_ITEMS); shared by Base Filters
-- (ns.PAB_ClassItems) and Icon Effects Filters (ns.PAB_FxClassItems). Values are
-- lowercase ENGINE keys, resolved to .key/.skey per dropdown by ClassByKey. Big
-- Defensive/External Defensive/Not Cast By You are UI-omitted but stay functional for
-- profiles that already set them.
local DEBUFF_FILTER_ORDER = {
    "nonplayer", "priority", "cc", "bossaura", "roleaura", "raid", "raidcombat", "dispellable", "dispeltyped",
    -- Divider sentinel (ClassByKey resolves nothing for it; PAB_ClassItems emits a
    -- header row, PAB_FxClassItems skips it), then the less common filters.
    "__less",
    "castbyme", "anyplayer", "magic", "curse", "poison", "disease", "bleed", "canapply",
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
            local key = DEBUFF_FILTER_ORDER[i]
            if key == "__less" then
                items[#items + 1] = { isHeader = true, label = "Less Common Filters" }
            else
                local class = ClassByKey(key)
                if class then
                    local meta = CLASS_LABELS[class.skey]
                    items[#items + 1] = {
                        key = class.skey,
                        label = meta and meta[1] or class.skey,
                        tooltip = meta and meta[2] or nil,
                    }
                end
            end
        end
        return items
    end

    -- Buffs: generic enumeration kept for signature compatibility; never called
    -- with isBuff=true today (buffs use Filters/Extra Spells).
    local items = {}
    local tokenClasses = VisibleTokenClasses()
    local candidateClasses = VisibleCandidateClasses()
    if not (tokenClasses and candidateClasses) then return items end
    local function AddAll(list)
        for i = 1, #list do
            local class = list[i]
            -- isBuff is always true here (false returned above), so polarity
            -- exclusion reduces to just debuffOnly.
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
--  Icon Effects Per-Filter (debuffs only). Adapted from Raid Frames' DebuffManager
--  fxList system, not shared code (same "adapted, not shared" precedent as
--  BuildChain/ClassEnabled below). Each cfg.fxList entry pairs debuff-category
--  filters with optional Icon Glow/Border/Size overrides; the FIRST entry whose
--  filters include a button's category wins. PAB's debuff classes are a mutual-
--  exclusion chain (BuildChain), so every displayed icon belongs to exactly ONE
--  engine group key (a class .key, or "all"): matching is one dictionary lookup,
--  never a search across overlapping records. A Match All group (DebuffChainFor)
--  stamps a category LIST instead: every member belongs to each listed category,
--  so the first entry naming any of them wins.
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

-- First ACTIVE block whose filters include `cat` wins (list is already pre-filtered
-- to active-only blocks by PAB_FxListView/style.fxList). `cat` is one category key,
-- or a Match All group's category list (any listed category matches).
local function PAB_FxBlockFor(list, cat)
    if not (list and cat) then return nil end
    local many = type(cat) == "table"
    for i = 1, #list do
        local f = list[i].filters
        if f then
            if many then
                for j = 1, #cat do
                    if f[cat[j]] then return list[i] end
                end
            elseif f[cat] then
                return list[i]
            end
        end
    end
end

-- Per-filter Size: first ACTIVE block matching `cat` wins outright (same rule
-- PAB_ApplyDmFx uses for glow/border) -- a later block's Size never overrides an
-- already-claimed category. `cat` takes a category list like PAB_FxBlockFor.
local function PAB_FxSizeFor(list, cat)
    if not (list and cat) then return nil end
    local many = type(cat) == "table"
    for i = 1, #list do
        local e = list[i]
        if PAB_FxEntryActive(e) then
            local f = e.filters
            local hit = false
            if f then
                if many then
                    for j = 1, #cat do
                        if f[cat[j]] then hit = true; break end
                    end
                else
                    hit = f[cat] and true or false
                end
            end
            if hit then
                local sz = tonumber(e.size)
                if sz and sz > 0 then return sz end
                return nil
            end
        end
    end
end

-- True if any ACTIVE fx block targets this engine class key. Forces a real per-
-- category group to exist even when Show All Debuffs/Base Filters would route
-- everything through the catch-all: fx entries can never match "all", and 12.1
-- aura data is engine-secret so a shown aura's category can't be read back off
-- the button (style.dispelBorder/dispelColorMap write-only). Fix: give fx-targeted
-- categories their own group, as if that Base Filter were on.
local function PAB_FxWantsCategory(list, key)
    if not (list and key) then return false end
    for i = 1, #list do
        local e = list[i]
        if PAB_FxEntryActive(e) and e.filters and e.filters[key] then return true end
    end
    return false
end

-- Whether PAB_FxWantsCategory may force a class active while the catch-all is also
-- present: forcing without a forward-exclusion carrier duplicates every matching debuff
-- (once via its own group, once via catch-all). Token classes are always safe (BuildChain
-- negates them "!TOKEN" forward); so is dispel-typed (forwards excludeDispelTypes). The
-- four boolean candidate classes (Boss, Role, Can Apply, Important) have exact false
-- values that BuildChain carries forward from a shown link, but they are never forced
-- here: forcing one would add a group beside the catch-all on every Show All bar with
-- such an Icon Effect, a regrouping this gate leaves out. Their Icon Effects still
-- require Show All Debuffs off plus the matching Base Filter on.
local function PAB_FxSafeToForce(class)
    local c = class.cand
    return not (c and (c.isBossAura ~= nil or c.isRoleAura ~= nil or c.isPriorityAura ~= nil
        or c.canApplyAura ~= nil))
end

-- Filter vocabulary for the Icon Effects UI (debuffs only): same curated
-- DEBUFF_FILTER_ORDER as ns.PAB_ClassItems(false), but keyed by lowercase ENGINE
-- key (class.key) not CamelCase classFilters key (class.skey), since fxList blocks
-- match d.dmCat (stamped with class.key by ApplyGroupConfig's extraInit). No
-- catch-all "all" entry, matching Raid Frames' TILE_FILTER_ITEMS.
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

-- Icon Glow (EllesmereUI.Glows overlay) + Border override (EllesmereUI.PP), keyed
-- off the button's stamped category (d.dmCat, set once at creation by ApplyGroupConfig's
-- extraInit). No-op for buffs (never carry fxList). Debuff buttons always pre-make the
-- glow/border overlay frames even with no matching block -- a small one-time per-button
-- cost (same trade-off as EllesmereUI_AuraKit.lua's dispelHolder) so a later Icon
-- Effects change never needs a /reload.

-- Icon-size expansion for a masked shape's overhang beyond its logical iconSize
-- (mirrors EllesmereUIActionBars.lua's SHAPE_BTN_EXPAND).
local PAB_SHAPE_EXPAND = 8
local function PabShapeActive(shape)
    return shape ~= nil and shape ~= "none"
end

-- Shape borders only render two visually distinct states at aura-icon sizes, same as
-- Action Bars' own ns.BORDER_THICKNESS table: thin/normal/heavy all carry shape=0,
-- only strong carries shape=7. Border Size's 0-4 levels mirror that table 1:1 (see
-- EUI_PlayerAuraBars_ManagerPages.lua's BORDER_SIZE_LEVELS).
local function PabShapeBorderSize(v)
    return ((v or 0) >= 4) and 7 or 0
end
local function PabShapedSize(rawSize, shape)
    if PabShapeActive(shape) then return rawSize + PAB_SHAPE_EXPAND end
    return rawSize
end

-- Nearest physical pixel at UIParent scale, for every PAB grid number (icon size,
-- padding, row gap). Not PP.Scale: it truncates, and the per-icon loss adds up
-- along a row, so a bar measured a different number of UI units per resolution.
-- PP.ToPixels rounds with the 0.001 tie guard, so an exact half pixel cannot flip
-- between sessions.
local function PabSnap(x)
    local PP = EllesmereUI.PP
    if x == 0 or PP.mult == 1 then return x end
    return PP.FromPixels(PP.ToPixels(x))
end

-- On ns, not file locals. The need
-- table names the engine glow families the Icon Glow menu offers (Pixel and
-- the flipbooks, no Blizzard Border), so a prewarm builds only those.
ns.PAB_GLOW_SPEC = {}
ns.PAB_GLOW_NEED = { ants = true, flip = true }
local function PAB_ApplyDmFx(button, d, style, arming)
    local cat = d.dmCat
    local e = style.fxList and PAB_FxBlockFor(style.fxList, cat) or nil

    local Glows = EllesmereUI.Glows
    local PP = EllesmereUI.PP
    -- Engine host: a Lua OnUpdate touching a frame parented to a 12.1 engine aura
    -- button is forbidden unconditionally, so only C-side animations render here
    -- (StartSpecGlow's engine path: Pixel as animated ants, ABG as its FlipBook twin).
    local spec = e and Glows.SpecFromPrefix(ns.PAB_GLOW_SPEC, e, "glow", 1.0, 0.776, 0.376)
    local sz = style.width or 18

    -- Icon Glow overlay: created UNCONDITIONALLY, matching block or not. The first call
    -- lands in the button's one legal creation window (extraInit, see AddGroupToContainer
    -- in EUI_PlayerAuraBars_Groups.lua); every later call is a RestyleSoon pass, where CreateFrame-parenting a NEW
    -- frame to the secure engine button is not guaranteed legal (same reasoning as
    -- AuraKit's dispelHolder). Pre-making it keeps a later glow toggle to Show/Hide +
    -- StartGlow/StopGlow, which is always legal.
    local gov = d.pabFxGlow
    if not gov then
        gov = CreateFrame("Frame", nil, button)
        gov:SetAllPoints(button)
        -- Level ladder: base border(+1) < fx border(+2) < glow(+3) < dispel ring(+4)
        -- < text(+5). The glow gets its own level, never shared with the fx border's.
        local base = (d.borderHost and d.borderHost:GetFrameLevel())
            or (button:GetFrameLevel() + 1)
        gov:SetFrameLevel(base + 3)
        gov:EnableMouse(false)
        gov:Hide()
        d.pabFxGlow = gov
    end
    -- The extraInit call (arming) is the button's creation window. While any
    -- Icon Effect of this style carries a glow, the button's glow regions are
    -- built there whatever its own category, so a glow added to that category
    -- later only reconfigures them. Buff bars (never fxList) and styles with no
    -- Icon Glow keep the one empty frame.
    if arming and style.fxList then
        local fx = style.fxList
        for i = 1, #fx do
            if (fx[i].glowType or 0) > 0 then
                Glows.PrewarmEngineHost(gov, sz, style.height or sz, ns.PAB_GLOW_NEED)
                break
            end
        end
    end
    -- Bound once, on the button's first glow: the button runs the glow's
    -- animations itself (12.1.5), Blizzard playing them while it shows an
    -- aura and stopping them when it has none (false where it cannot: no
    -- API). Binding registers nothing; the start below does, in the creation
    -- window or at a later restyle out of restriction (a glow block added
    -- later). Bound, every button carries the glow. Unbound, the animation
    -- plays while hidden too, so only buttons the group can ever show run one.
    if spec and d.pabFxBound == nil then d.pabFxBound = Glows.BindEngineHost(gov, button, d) end
    if spec and (d.pabFxBound or EllesmereUI.AuraKit.ButtonCanShow(button)) then
        gov:Show()
        Glows.StartSpecGlow(gov, spec, sz, style.height or sz, "engine")
    else
        if gov._euiGlowActive then Glows.StopGlow(gov) end
        gov:Hide()
    end

    -- Border override: same creation-window pre-make as the glow. PP.CreateBorder's
    -- container is created lazily below (non-shaped branch only) -- a shaped bar
    -- uses PP.ApplyMaskedShapeBorder instead, which owns its own child texture.
    local bSize = (e and e.borderSize) or 0
    local host = d.pabFxBdr
    if not host and PP then
        host = CreateFrame("Frame", nil, button)
        host:SetAllPoints(button)
        local base = (d.borderHost and d.borderHost:GetFrameLevel())
            or (button:GetFrameLevel() + 1)
        host:SetFrameLevel(base + 1)
        host:EnableMouse(false)
        host:Hide()
        d.pabFxBdr = host
    end
    if bSize > 0 and host and PP then
        local bc = e.borderColor or { r = 0, g = 0, b = 0 }
        if style.iconShape and style.iconShape ~= "none" and style.shapeBorderPath and d.shapeMask then
            PP:ApplyMaskedShapeBorder(host, d.shapeMask, style.shapeBorderPath, PabShapeBorderSize(bSize), bc.r or 0, bc.g or 0, bc.b or 0, 1)
        else
            PP:HideMaskedShapeBorder(host)
            PP.CreateBorder(host, 0, 0, 0, 1, 1)
            PP.UpdateBorder(host, bSize, bc.r or 0, bc.g or 0, bc.b or 0, 1)
        end
        host:Show()
    elseif host then
        host:Hide()
    end
end

-------------------------------------------------------------------------------
--  Class-enabled check and mutual-exclusion chain builder
--
--  Adapted from EUI_UnitFrames_AuraContainers.lua's ClassEnabled/BuildChain, not
--  shared as functions (only the two class tables above are sanctioned sharing).
--  Token classes negate every earlier-enabled token class (mutual exclusion,
--  priority = declaration order); candidate classes sit after the full token
--  negation chain as boolean engine selectors, not addable to the token chain.
-------------------------------------------------------------------------------

local function ClassEnabled(class, isBuff, cfg)
    if class.buffOnly and not isBuff then return false end
    if class.debuffOnly and isBuff then return false end
    -- "Show All Debuffs": bypasses every class toggle without touching saved
    -- classFilters, so turning it back off restores exactly what was configured.
    -- Debuffs only -- buffs never read classFilters. ~= false not == true: nil
    -- (unconfigured bar) means ON, matching showAllBuffs' "nil == on". Has
    -- Duration is a MODIFIER, not a mode: it never bypasses class toggles.
    if not isBuff and cfg.showAllDebuffs ~= false then return false end
    -- playerUnitOnly classes ("nonplayer") always apply: player unit only.
    return cfg.classFilters and cfg.classFilters[class.skey] == true
end

-- Curated FAMILIES (a primary plus its `alts`: rank/talent ids for one buff, and
-- multi-state buffs like Aspect of Harmony whose aura swaps spell ID as it advances)
-- expand at RESOLUTION, as the Raid Frames Buff Manager does in BmIncludeMap. Not at
-- write time: the Filter Editor and both spell dropdowns collapse a family into ONE
-- same-named row, so only one member is ever reachable to add, and saved filters hold
-- that member alone. `blocked` is the owning filter's spell map, where an explicit
-- `false` wins. Show lane and hide lane both expand, or a hide filter carrying one id
-- of a family would leak the rest.
local function ExpandFamily(set, id, blocked)
    local fam = ns.PAB_SPELL_FAMILY and ns.PAB_SPELL_FAMILY[id]
    if not fam then return end
    for i = 1, #fam do
        if not (blocked and blocked[fam[i]] == false) then set[fam[i]] = true end
    end
end

-- BuildChain contract: includeCatchAll (default true) appends "every remaining aura
-- of this polarity" after the per-class groups; callers pass false wherever the UI
-- promises the Base Filters dropdown restricts what is shown (Custom Debuff Bars with
-- Show All Debuffs off), otherwise a bar limited to one class still renders every
-- other debuff via the "all" group. excludeDispelTypes propagation: candidate classes
-- have no string token to negate forward with, so once the dispel-typed class is
-- enabled every chain link built AFTER it (incl. the catch-all) gets a matching
-- excludeDispelTypes candidateFilter -- else PAB_FxWantsCategory forcing it active
-- while the catch-all is included duplicates every matching debuff (same mechanism
-- RaidFrames' DebuffManager uses via cf.excludeDispelTypes = TYPED_DEBUFFS).
--
-- Catch-all chain for a buff bar (Show All Buffs, default on). HIDE-lane filters
-- (cfg.negFilters) SUBTRACT their resolved spells via excludeSpellIDs, re-applied every
-- ApplyGroupConfig pass so edits stay live. ApplyGroupConfig self-zeroes any group
-- falling out of the returned chain, so callers pass this UNGATED; an empty chain is
-- the correct "nothing" case.
local function BuffBarChain(cfg)
    -- All Buffs and Has Duration are mutually exclusive broad-content modes (options
    -- setters enforce it): either builds the catch-all (Has Duration narrowed to
    -- duration-carrying buffs via the maxDuration extras merge) and hide-lane filters
    -- SUBTRACT from it. With neither on, show-lane filters ADD through the spells
    -- group (minus the hide lane, resolved in PAB_ResolveSpells).
    if cfg.showAllBuffs == false and cfg.hasDuration ~= true then return {} end
    local link = { key = "all", tokens = { "HELPFUL" } }
    if cfg.negFilters then
        local ex
        for filterId in pairs(cfg.negFilters) do
            local f = ns.PAB_GetFilter and ns.PAB_GetFilter(filterId)
            if f and f.spells then
                for id, on in pairs(f.spells) do
                    if on and not ns.PAB_OtherClientSpell(f, id) then
                        ex = ex or {}
                        ex[id] = true
                        ExpandFamily(ex, id, f.spells)
                    end
                end
            end
        end
        if ex then link.cand = { excludeSpellIDs = ex } end
    end
    return { link }
end

-- Unified filter model (debuffs, Raid Frames DM parity): HIDE-lane classes
-- (cfg.negClassFilters) SUBTRACT in BOTH modes -- from the catch-all while Show All
-- Debuffs is on, from the show-lane class groups in add mode. Returns the per-class
-- hide-lane test as BuildChain's subtractFn; nil when nothing is hidden.
local function DebuffSubtractFn(cfg)
    local neg = cfg.negClassFilters
    if not (neg and next(neg)) then return nil end
    return function(class)
        if class.buffOnly then return false end
        return neg[class.skey] == true
    end
end

-- Union of two dispel-type sets as a NEW table (the shared vocabulary tables
-- are never mutated); nil-safe on the accumulator. Several per-type classes
-- can forward at once, so the carrier accumulates instead of overwriting.
local function MergeTypes(acc, add)
    local out = {}
    if acc then for k, v in pairs(acc) do out[k] = v end end
    for k, v in pairs(add) do out[k] = v end
    return out
end

local function BuildChain(base, classEnabledFn, includeCatchAll, subtractFn)
    local chain, negations = {}, {}
    local excludeDispelTypes, npOwned, anyOwned, prOwned, boolOwned, subCand
    local tokenClasses = VisibleTokenClasses()
    local candidateClasses = VisibleCandidateClasses()
    if not (tokenClasses and candidateClasses) then return chain end
    -- TWO structures, picked by mode. BROAD mode (catch-all included) keeps the
    -- LEGACY single interleaved pass bit-for-bit: hidden and fx-forced links emit
    -- in vocabulary order, an fx-forced class sees only earlier-vocab negations,
    -- and subCand lands ONLY on the catch-all -- pre-lanes configs (Show All +
    -- subtractions + Icon Effects) must keep their exact link shapes. ADD mode
    -- (no catch-all, hide lane possible only post-lanes) runs the HIDDEN PASS
    -- FIRST so every hidden class's negations/forward excludes/inverted booleans
    -- reach every positive link -- there is nothing legacy to preserve there.
    local addMode = includeCatchAll == false

    -- Boss / Role / Can Apply: the engine field a link of one of those classes
    -- owns, else nil. Each is an exact NOT when set false (like isPriorityAura).
    local function OwnedBool(cc)
        if cc.isBossAura == true then return "isBossAura" end
        if cc.isRoleAura == true then return "isRoleAura" end
        if cc.canApplyAura == true then return "canApplyAura" end
    end

    -- One linear owner order, each shown class carrying its complement onto every
    -- later link (see ExtraCand): Non-Player / From Any Player > Boss > Role >
    -- Can Apply > shown types > Important > Dispels. Important owns its overlap
    -- with Non-Player (the Raid Frames owner too), and Non-Player sits FIRST in
    -- the vocabulary, so the pair is pre-scanned: while both are shown (npFlip)
    -- every class ranked above Important must rank above Non-Player too, or the
    -- order cycles (an NPC Important debuff of a shown type, or an NPC Boss
    -- debuff that is Important, would match no link at all). So Boss, Role, Can
    -- Apply, the per-type rows and Important skip the Non-Player handoff, and the
    -- Non-Player link carries their complements instead: isPriorityAura = false,
    -- the shown types' exclude, and false for each shown Boss / Role / Can Apply.
    -- Flip order: Boss > Role > Can Apply > shown types > Important > Non-Player
    -- > Dispels. Nothing changes unless both are shown.
    local npFlip, flipTypes, flipBools
    do
        local npShown, prShown, types, bools
        for i = 1, #candidateClasses do
            local class = candidateClasses[i]
            local cc = class.cand
            if cc and classEnabledFn(class) then
                local bk = OwnedBool(cc)
                if cc.isFromPlayerOrPlayerPet == false then npShown = true
                elseif cc.isPriorityAura == true then prShown = true
                elseif bk then
                    bools = bools or {}
                    bools[bk] = false
                elseif cc.includeDispelTypes and not prShown then
                    types = MergeTypes(types, cc.includeDispelTypes)
                end
            end
        end
        if npShown and prShown then npFlip, flipTypes, flipBools = true, types, bools end
    end

    -- Forward-carried candidate exclusions: candidate classes have no string token
    -- to negate with, so exclusivity rides complementary candidate filters on every
    -- link built AFTER the trigger. Carriers: excludeDispelTypes, the Non-Player
    -- handoff (once nonplayer -- isFromPlayerOrPlayerPet = false -- is in the
    -- chain, later links incl. the catch-all carry the complementary TRUE so the
    -- two sides partition instead of double-displaying), a shown Important
    -- (isPriorityAura = false on every later link), a shown Boss / Role / Can
    -- Apply (its field false on every later link, boolOwned), and -- ADD MODE
    -- ONLY -- subCand (inverted booleans of hidden pure-boolean classes; in broad
    -- mode subCand stays a catch-all-only payload, legacy parity). skipNp drops
    -- the Non-Player handoff for the links that outrank Non-Player (see npFlip);
    -- noBools drops the Boss / Role / Can Apply carry (a link that matches
    -- nothing keeps its payload and key).
    local function ExtraCand(skipNp, noBools)
        local withSub = addMode and subCand or nil
        local np = npOwned and not skipNp
        local bo = (not noBools) and boolOwned or nil
        if not (excludeDispelTypes or np or anyOwned or prOwned or bo or withSub) then return nil end
        local t = {}
        if excludeDispelTypes then t.excludeDispelTypes = excludeDispelTypes end
        -- Non-Player and From Any Player are the same field; the options
        -- setters keep them exclusive, nonplayer wins if stale data disagrees.
        if npOwned then
            if np then t.isFromPlayerOrPlayerPet = true end
        elseif anyOwned then t.isFromPlayerOrPlayerPet = false end
        if prOwned then t.isPriorityAura = false end
        if bo then
            for k, v in pairs(bo) do t[k] = v end
        end
        if withSub then
            for k, v in pairs(withSub) do t[k] = v end
        end
        return t
    end

    -- excludeCand for a SHOWN candidate link: ExtraCand plus the npFlip ownership.
    -- A dispel-type link whose every type the forwarded exclude already drops
    -- (Dispels hidden) matches nothing: it takes no Boss / Role / Can Apply carry.
    local function ShownCand(cc)
        local dead = cc.includeDispelTypes ~= nil and excludeDispelTypes ~= nil
        if dead then
            for k in pairs(cc.includeDispelTypes) do
                if not excludeDispelTypes[k] then dead = false; break end
            end
        end
        if not npFlip then return ExtraCand(nil, dead) end
        local ex = ExtraCand(cc.isPriorityAura == true or OwnedBool(cc) ~= nil
            or (cc.includeDispelTypes ~= nil and not prOwned), dead)
        if cc.isFromPlayerOrPlayerPet == false then
            ex = ex or {}
            ex.isPriorityAura = false
            if flipTypes then ex.excludeDispelTypes = MergeTypes(ex.excludeDispelTypes, flipTypes) end
            if flipBools then
                for k, v in pairs(flipBools) do ex[k] = v end
            end
        end
        return ex
    end

    local function CollectSub(cc)
        subCand = subCand or {}
        for k, v in pairs(cc) do
            if type(v) == "boolean" then subCand[k] = not v end
        end
    end

    if addMode and subtractFn then
        -- HIDDEN PASS -- subtracted classes join FIRST as parked links: group
        -- filter strings are declaration-fixed, so subtraction must ride the same
        -- negation machinery enabling a class does, never a re-tokened catch-all.
        -- An fx-forced class stays visible (effect wins) and is emitted by the
        -- positive pass instead.
        for i = 1, #tokenClasses do
            local class = tokenClasses[i]
            if subtractFn(class) and not classEnabledFn(class) then
                local tokens = { base, class.token }
                for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
                chain[#chain + 1] = { key = class.key, tokens = tokens, excludeCand = ExtraCand(),
                    hidden = true }
                negations[#negations + 1] = class.neg or ("!" .. class.token)
            end
        end
        for i = 1, #candidateClasses do
            local class = candidateClasses[i]
            local cc = class.cand
            if cc and subtractFn(class) and not classEnabledFn(class) then
                -- Forward-capable candidate classes (dispeltyped's include map,
                -- nonplayer's complementary boolean) subtract through the hidden-
                -- link + forward-exclude route; pure boolean classes (bossaura/
                -- roleaura/priority) invert onto subCand instead.
                local forward = cc.includeDispelTypes ~= nil or cc.isFromPlayerOrPlayerPet ~= nil
                if forward then
                    local tokens = { base }
                    for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
                    chain[#chain + 1] = { key = class.key, tokens = tokens, cand = cc, excludeCand = ExtraCand(),
                        hidden = true }
                    if cc.includeDispelTypes then excludeDispelTypes = MergeTypes(excludeDispelTypes, cc.includeDispelTypes) end
                    if cc.isFromPlayerOrPlayerPet == false then npOwned = true
                    elseif cc.isFromPlayerOrPlayerPet == true then anyOwned = true end
                else
                    CollectSub(cc)
                end
            end
        end
        -- POSITIVE PASS -- the legacy loop shape; negations arrive pre-seeded.
        for i = 1, #tokenClasses do
            local class = tokenClasses[i]
            if classEnabledFn(class) then
                local tokens = { base, class.token }
                for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
                chain[#chain + 1] = { key = class.key, tokens = tokens, excludeCand = ExtraCand() }
                negations[#negations + 1] = class.neg or ("!" .. class.token)
            end
        end
        for i = 1, #candidateClasses do
            local class = candidateClasses[i]
            local cc = class.cand
            if cc and classEnabledFn(class) then
                local tokens = { base }
                for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
                -- class.cand is a candidate-filter TABLE; the shared vocabulary
                -- carries set-valued filters (includeDispelTypes) directly in it.
                chain[#chain + 1] = { key = class.key, tokens = tokens, cand = cc, excludeCand = ShownCand(cc) }
                if cc.includeDispelTypes then excludeDispelTypes = MergeTypes(excludeDispelTypes, cc.includeDispelTypes) end
                if cc.isFromPlayerOrPlayerPet == false then npOwned = true
                elseif cc.isFromPlayerOrPlayerPet == true then anyOwned = true end
                if cc.isPriorityAura == true then prOwned = true end
                local bk = OwnedBool(cc)
                if bk then
                    boolOwned = boolOwned or {}
                    boolOwned[bk] = false
                end
            end
        end
        return chain
    end

    -- BROAD mode (and add mode with an empty hide lane): the legacy single
    -- interleaved pass, verbatim. Subtracted classes (subtractFn checked, not
    -- otherwise enabled) join as HIDDEN links in vocabulary order: the group
    -- parks at 0 frames while its negations/forward excludes still remove it
    -- from the catch-all. An fx-forced class stays visible (effect wins).
    for i = 1, #tokenClasses do
        local class = tokenClasses[i]
        local en = classEnabledFn(class)
        local sub = subtractFn and subtractFn(class) or false
        if en or sub then
            local tokens = { base, class.token }
            for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
            chain[#chain + 1] = { key = class.key, tokens = tokens, excludeCand = ExtraCand(),
                hidden = (sub and not en) or nil }
            negations[#negations + 1] = class.neg or ("!" .. class.token)
        end
    end
    for i = 1, #candidateClasses do
        local class = candidateClasses[i]
        local en = classEnabledFn(class)
        local sub = subtractFn and subtractFn(class) or false
        local cc = class.cand
        if (en or sub) and cc then
            -- Forward-capable candidate classes (dispeltyped's include map, nonplayer's
            -- complementary boolean) subtract through the same hidden-link + forward-
            -- exclude route as token classes. Pure boolean classes (bossaura/roleaura/
            -- priority) have no forward machinery: a subtract-only check inverts their
            -- booleans onto the catch-all's candidates (which re-apply every pass).
            local forward = cc.includeDispelTypes ~= nil or cc.isFromPlayerOrPlayerPet ~= nil
            if en or forward then
                local tokens = { base }
                for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
                -- class.cand is a candidate-filter TABLE; the shared vocabulary carries
                -- set-valued filters (includeDispelTypes) directly in it. ShownCand
                -- may return nil on purpose, so no and/or shortcut here.
                local ex
                if en then ex = ShownCand(cc) else ex = ExtraCand() end
                chain[#chain + 1] = { key = class.key, tokens = tokens, cand = cc, excludeCand = ex,
                    hidden = (sub and not en) or nil }
                if cc.includeDispelTypes then excludeDispelTypes = MergeTypes(excludeDispelTypes, cc.includeDispelTypes) end
                if cc.isFromPlayerOrPlayerPet == false then npOwned = true
                elseif cc.isFromPlayerOrPlayerPet == true then anyOwned = true end
                if en and cc.isPriorityAura == true then prOwned = true end
                local bk = en and OwnedBool(cc)
                if bk then
                    boolOwned = boolOwned or {}
                    boolOwned[bk] = false
                end
            else
                CollectSub(cc)
            end
        end
    end

    if includeCatchAll ~= false then
        -- Catch-all LAST: everything not claimed by an enabled class, negating the
        -- full chain above. Zero classes enabled = just { base }, every aura of
        -- that polarity.
        local allTokens = { base }
        for n = 1, #negations do allTokens[#allTokens + 1] = negations[n] end
        local ex = ExtraCand()
        if subCand then
            ex = ex or {}
            for k, v in pairs(subCand) do
                if ex[k] == nil then ex[k] = v end
            end
        end
        chain[#chain + 1] = { key = "all", tokens = allTokens, excludeCand = ex }
    end

    return chain
end

-- Main-chunk locals the EUI_PlayerAuraBars_*.lua files re-import by name.
-- AKSetters and the lists beside it: every file that reads one of these
-- keeps its own copy and adds a setter here; each place that assigns it
-- writes through the Set<Name> function built below, which runs them all.
-- broken: true while an EUI_PlayerAuraBars_*.lua file loads; a file that
-- fails leaves it set, and the files behind it return at their first lines.
EllesmereUI.NewInternals(ns, "_pabInternals", {
    BuffBarChain = BuffBarChain, BuildChain = BuildChain, ClassByKey = ClassByKey,
    ClassEnabled = ClassEnabled, DEBUFF_FILTER_ORDER = DEBUFF_FILTER_ORDER,
    DebuffSubtractFn = DebuffSubtractFn, ExpandFamily = ExpandFamily, MergeTypes = MergeTypes,
    PAB = PAB, PAB_ApplyDmFx = PAB_ApplyDmFx, PAB_FxEntryActive = PAB_FxEntryActive,
    PAB_FxListView = PAB_FxListView, PAB_FxSafeToForce = PAB_FxSafeToForce,
    PAB_FxSizeFor = PAB_FxSizeFor, PAB_FxWantsCategory = PAB_FxWantsCategory,
    PabShapeActive = PabShapeActive, PabShapeBorderSize = PabShapeBorderSize,
    PabShapedSize = PabShapedSize, PabSnap = PabSnap,
    VisibleCandidateClasses = VisibleCandidateClasses,
    VisibleTokenClasses = VisibleTokenClasses,
    AKSetters = {}, buffsContainerSetters = {}, debuffsContainerSetters = {},
    buffsParentSetters = {}, debuffsParentSetters = {}, buffsSlotSigSetters = {},
    pabSuppressedSetters = {}, reloadAllSetters = {}, previewRefreshSetters = {},
}, {
    SetAK = "AKSetters", SetBuffsContainer = "buffsContainerSetters",
    SetDebuffsContainer = "debuffsContainerSetters", SetBuffsParent = "buffsParentSetters",
    SetDebuffsParent = "debuffsParentSetters", SetBuffsSlotSig = "buffsSlotSigSetters",
    SetPabSuppressed = "pabSuppressedSetters", SetReloadAllCustomBars = "reloadAllSetters",
    SetMaybeRefreshPreview = "previewRefreshSetters",
})
