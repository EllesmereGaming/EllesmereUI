if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIUnitFrames_PlayerAuraBars.lua
--  12.1 AuraKit-based player buff/debuff bars.
-------------------------------------------------------------------------------

local _, ns = ...

local AK -- EllesmereUI.AuraKit, resolved at first use (parent file loads first)

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
}

-- Curated debuff filter list: exact vocabulary+order parity with Raid Frames' debuff
-- filters (EUI_RaidFrames_ManagerPages.lua TILE_FILTER_ITEMS); shared by Base Filters
-- (ns.PAB_ClassItems) and Icon Effects Filters (ns.PAB_FxClassItems). Values are
-- lowercase ENGINE keys, resolved to .key/.skey per dropdown by ClassByKey. Big
-- Defensive/External Defensive/Not Cast By You are UI-omitted but stay functional for
-- profiles that already set them.
local DEBUFF_FILTER_ORDER = {
    "nonplayer", "priority", "cc", "bossaura", "roleaura", "raid", "raidcombat", "dispellable", "dispeltyped",
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
--  never a search across overlapping records.
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
-- to active-only blocks by PAB_FxListView/style.fxList).
local function PAB_FxBlockFor(list, cat)
    if not (list and cat) then return nil end
    for i = 1, #list do
        local f = list[i].filters
        if f and f[cat] then return list[i] end
    end
end

-- Per-filter Size: first ACTIVE block matching `cat` wins outright (same rule
-- PAB_ApplyDmFx uses for glow/border) -- a later block's Size never overrides an
-- already-claimed category.
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
-- three boolean candidate classes (bossaura/roleaura/priorityaura) have no Blizzard
-- "exclude" counterpart, so their Icon Effects still require Show All Debuffs off plus
-- the matching Base Filter on.
local function PAB_FxSafeToForce(class)
    local c = class.cand
    return not (c and (c.isBossAura ~= nil or c.isRoleAura ~= nil or c.isPriorityAura ~= nil))
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

local function PAB_ApplyDmFx(button, d, style)
    local cat = d.dmCat
    local e = style.fxList and PAB_FxBlockFor(style.fxList, cat) or nil

    local Glows = EllesmereUI.Glows
    local PP = EllesmereUI.PP
    local gType = (e and e.glowType) or 0
    -- ALWAYS remap driver-ticked styles (Pixel/Action Button/Auto-Cast/Shape) to their
    -- FlipBook-safe equivalent. Must NOT gate on AK.AurasRestricted(): that reflects only
    -- whether AURA DATA is secret, while a Lua OnUpdate touching a frame parented to a
    -- 12.1 engine aura button is forbidden UNCONDITIONALLY ("Attempt to access forbidden
    -- object from code tainted by an AddOn" on wrapper:IsVisible() inside
    -- EllesmereUI_Glows.lua's driver). Only FlipBook styles (GCD/Modern/Classic) are
    -- safe: C-side AnimationGroups, never in the driver's IsVisible() polling loop.
    if gType > 0 and Glows and Glows.RestrictionSafeStyle then
        gType = Glows.RestrictionSafeStyle(gType)
    end

    -- Icon Glow overlay: created UNCONDITIONALLY, matching block or not. The first call
    -- lands in the button's one legal creation window (extraInit, see AddGroupToContainer
    -- below); every later call is a RestyleSoon pass, where CreateFrame-parenting a NEW
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
    if gType > 0 and Glows and Glows.StartGlow then
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
    else
        if gov._euiGlowActive and Glows and Glows.StopGlow then Glows.StopGlow(gov) end
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
                    if on then
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

local function BuildChain(base, classEnabledFn, includeCatchAll, subtractFn)
    local chain, negations = {}, {}
    local excludeDispelTypes, npOwned, subCand
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

    -- Forward-carried candidate exclusions: candidate classes have no string token
    -- to negate with, so exclusivity rides complementary candidate filters on every
    -- link built AFTER the trigger. Carriers: excludeDispelTypes, the Non-Player
    -- handoff (once nonplayer -- isFromPlayerOrPlayerPet = false -- is in the
    -- chain, later links incl. the catch-all carry the complementary TRUE so the
    -- two sides partition instead of double-displaying), and -- ADD MODE ONLY --
    -- subCand (inverted booleans of hidden pure-boolean classes; in broad mode
    -- subCand stays a catch-all-only payload, legacy parity).
    local function ExtraCand()
        local withSub = addMode and subCand or nil
        if not (excludeDispelTypes or npOwned or withSub) then return nil end
        local t = {}
        if excludeDispelTypes then t.excludeDispelTypes = excludeDispelTypes end
        if npOwned then t.isFromPlayerOrPlayerPet = true end
        if withSub then
            for k, v in pairs(withSub) do t[k] = v end
        end
        return t
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
                    if cc.includeDispelTypes then excludeDispelTypes = cc.includeDispelTypes end
                    if cc.isFromPlayerOrPlayerPet == false then npOwned = true end
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
                chain[#chain + 1] = { key = class.key, tokens = tokens, cand = cc, excludeCand = ExtraCand() }
                if cc.includeDispelTypes then excludeDispelTypes = cc.includeDispelTypes end
                if cc.isFromPlayerOrPlayerPet == false then npOwned = true end
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
                -- set-valued filters (includeDispelTypes) directly in it.
                chain[#chain + 1] = { key = class.key, tokens = tokens, cand = cc, excludeCand = ExtraCand(),
                    hidden = (sub and not en) or nil }
                if cc.includeDispelTypes then excludeDispelTypes = cc.includeDispelTypes end
                if cc.isFromPlayerOrPlayerPet == false then npOwned = true end
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

-------------------------------------------------------------------------------
--  Container spec construction
--
--  style.noRegions is NOT set: AK.MakeInitializer creates the standard
--  icon/cooldown/text regions and styling only layers on top.
-------------------------------------------------------------------------------

local STYLE_BUFFS = "playerAuraBars_buffs"
local STYLE_DEBUFFS = "playerAuraBars_debuffs"

-- Style field names verified against AK's ApplyStyleToRegions (EllesmereUI_AuraKit.lua).
--
-- Settings schema (db.profile.playerAuraBars): default bars (s.defaultBuffs/
-- s.defaultDebuffs) and every custom bar object share ONE cfg shape (no migration
-- from any older schema, deliberate). BuildStyle/ComputeGrid/ClassEnabled take
-- (isBuff, cfg) and don't care which table it came from.
--
-- Shared by every bar: iconSize (button width==height); durationShow/stackShow
-- (independent show/hide); durationTextSize/durationPosition("TOP"/"BOTTOM"/...)/
-- durationOffsetX/Y; durationColorR/G/B (optional, nil=white AK default);
-- stackTextSize/stackPosition/stackOffsetX/Y; stackColorR/G/B (same nil=white rule).
-- Buff/debuff bars additionally: iconZoom (default 0.07, AK's fallback);
-- borderSize/borderR/G/B/A (base border color, per-dispel-type override is separate);
-- padding (single scalar -> all 4 sides); rowSpacing (optional row gap: feeds
-- lineSpacing/groupLineSpacing only, nil falls back to `padding`; elementSpacing/
-- groupSpacing, icon-to-icon within a row, always stay tied to `padding`); maxTotal
-- (overall icon cap); iconsPerRow (row width in columns); maxRows (row cap; with
-- iconsPerRow also bounds maxTotal, see ComputeGrid()); growDirection ("LEFT"/"RIGHT"/
-- "CENTER_HORIZONTAL"/"CENTER_VERTICAL"/"UP"/"DOWN", default LEFT).
-- Buff bars (default AND custom, one model): filters ([filterId]=true, shared PAB
-- Filters registry); spells ({spellID,...}, direct/"Extra Spells"); showAllBuffs
-- (default bar ONLY, custom buff bars never read it; defaults true, else an
-- unconfigured bar shows nothing -- adds an additive catch-all GROUP alongside the
-- spells group, matching Blizzard's player BuffFrame; UI toggle "Show All Buffs",
-- mirrors Show All Debuffs). classFilters has NO effect on buff bars -- BuildChain is
-- used only via the always-catch-all showAllBuffs group, never per-class.
-- Debuff bars (default AND custom): classFilters ([classSkey]=true); showAllDebuffs
-- (bypasses classFilters unless explicitly false; defaults TRUE, nil==on, mirroring
-- showAllBuffs); dispelColorMagic/Curse/Disease/Poison/Bleed (optional Color-like
-- {r,g,b}, falls back to the Raid Frames palette).
--
-- Duration format: AK.GetDurationFormatter(showSecondsUnit) serves two cached
-- variants -- bare seconds under 60 (the suite default) or unit-suffixed
-- ("10s") via the per-bar "Show S for Seconds" cog (style.durationShowSeconds);
-- both keep Xm/Xh/Xd above the minute. No other format variants ("colon" etc.):
-- those would mean new AuraKit breakpoint schemas (shared with Raid Frames).
-- DISPEL_SLOTS below is a local copy of EUI_RaidFrames_AuraContainers.lua's: ns is
-- per-addon-private, so tokens/fallback colors are duplicated on purpose for suite-wide
-- consistency -- a RaidFrames palette change must be mirrored here by hand, no shared source.
local DISPEL_SLOTS = {
    { token = "Magic",   colorKey = "dispelColorMagic",   fallback = { 0.349, 0.475, 1.0 } },
    { token = "Curse",   colorKey = "dispelColorCurse",   fallback = { 0.636, 0.0, 0.64 } },
    { token = "Disease", colorKey = "dispelColorDisease", fallback = { 0.671, 0.384, 0.098 } },
    { token = "Poison",  colorKey = "dispelColorPoison",  fallback = { 0.0, 0.706, 0.286 } },
    { token = "Bleed",   colorKey = "dispelColorBleed",   fallback = { 0.75, 0.15, 0.15 } },
}

-- Dispel-type indicator icon: preview-only atlas/point maps. The LIVE icon is
-- engine-rendered (AK's one-hot dispel-texture channel, style.dispelTypeIcon);
-- these exist so the options preview can paint the same art from the fake
-- entries' plain dispel tokens.
local PV_DISPEL_ICON_ATLAS = {
    Magic   = "RaidFrame-Icon-DebuffMagic",
    Curse   = "RaidFrame-Icon-DebuffCurse",
    Disease = "RaidFrame-Icon-DebuffDisease",
    Poison  = "RaidFrame-Icon-DebuffPoison",
    Bleed   = "RaidFrame-Icon-DebuffBleed",
}
local PV_DISPEL_ICON_POINTS = {
    topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT",
    left = "LEFT", center = "CENTER", right = "RIGHT",
    bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT",
}

-- Same shape as RaidFrames' ns.RFC_DispelBorderColorMap: a customDispelColorMap
-- (dispelName -> Color) for AK's engine-driven border, plus a fingerprint so a
-- palette edit re-registers the border options (style.dispelColorFP).
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

-- Anchor-point mirror for placing duration text OUTSIDE the icon: the text's OWN
-- point is the opposite corner/edge of the icon's anchor, so "TOP" anchors the
-- text's BOTTOM edge to the icon's TOP edge (text sits above).
local OPPOSITE_POINT = {
    TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT",
    TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT",
    BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT",
    CENTER = "CENTER",
}

local function SetTexturePixelSnap(texture, enabled)
    if not (texture and texture.SetSnapToPixelGrid) then return end
    texture:SetSnapToPixelGrid(enabled)
    texture:SetTexelSnappingBias(0)
end

-- Secondary text-styling pass: AK calls style.applyExtra as (button, d, style), where
-- d.duration/d.stack are the FontStrings AK's own initializer creates. Adds what AK has
-- no native field for: duration/stack text color and independent stack-text show/hide
-- (AK's hideDurationText covers duration hide only, no native stack equivalent).
local function PAB_ApplyExtraText(button, d, style)
    -- Own text pipeline (style.noDefaultFonts): fonts ride the user's global/per-module
    -- Unit Frames font and the house icon-text outline rules, resolved once per style
    -- rebuild into style.fontPath/fontFlag (see BuildStyle). Font/anchor writes are
    -- change-guarded (stamp AFTER the calls): SetPoint with the button as relative frame
    -- is policed by the 12.1 button access restriction while auras are secret, so
    -- unchanged values must make zero button-involving calls for restyles to stay live
    -- in-instance.
    local path = style.fontPath or STANDARD_TEXT_FONT
    local flag = style.fontFlag or "OUTLINE"
    if d.duration then
        local fKey = path .. "|" .. (style.durationFontSize or 11) .. "|" .. flag
        if d.pabDurFont ~= fKey then
            d.pabDurFont = fKey
            -- Prime the shadow FontObject before SetFont; Drop Shadow mode (empty
            -- flag) keeps the text legible instead of flat.
            if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(d.duration, flag == "") end
            d.duration:SetFont(path, style.durationFontSize or 11, flag)
        end
        local dp = style.durationPoint or "CENTER"
        local drp = style.durationRelPoint or "CENTER"
        local aKey = dp .. "|" .. drp .. "|" .. (style.durationX or 0) .. "|" .. (style.durationY or 0)
        if d.pabDurAnchor ~= aKey then
            d.duration:ClearAllPoints()
            d.duration:SetPoint(dp, button, drp, style.durationX or 0, style.durationY or 0)
            d.pabDurAnchor = aKey
        end
        local c = style.durationColor
        d.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        -- "Show S for Seconds" rebind: duration opts land once at creation;
        -- re-register when the style's formatter choice changed. The nil
        -- gate skips the creation-time applyExtra pass (the creation block
        -- registers and stamps right after). Stamp-after-success, the
        -- BmRebindDurationCurve rule: a denied registration under the
        -- secret-aura button restriction must leave the stamp unchanged so
        -- the next restyle retries.
        local wantFmt = (style.durationShowSeconds and "s" or "b") .. tostring(style.durationPrecisionThreshold or 0)
        if d.durationFmtS ~= nil and d.durationFmtS ~= wantFmt then
            local AK = EllesmereUI.AuraKit
            local durationOpts = AK.BuildDurationTextOpts(
                AK.GetDurationFormatter(style.durationShowSeconds, style.durationPrecisionThreshold),
                style.durationColorCurve, style.durationUpdateInterval)
            local ok, full = AK.SetDurationTextSafe(button, d.duration, durationOpts)
            if ok and (full or not style.durationColorCurve) then
                d.durationFmtS = wantFmt
            end
        end
    end
    if d.stack then
        local fKey = path .. "|" .. (style.stackFontSize or 11) .. "|" .. flag
        if d.pabStackFont ~= fKey then
            d.pabStackFont = fKey
            if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(d.stack, flag == "") end
            d.stack:SetFont(path, style.stackFontSize or 11, flag)
        end
        local sp = style.stackPoint or "BOTTOMRIGHT"
        local sKey = sp .. "|" .. (style.stackX or 0) .. "|" .. (style.stackY or 0)
        if d.pabStackAnchor ~= sKey then
            d.stack:ClearAllPoints()
            d.stack:SetPoint(sp, button, sp, style.stackX or 0, style.stackY or 0)
            d.pabStackAnchor = sKey
        end
        d.stack:SetShown(style.showStacks ~= false)
        local c = style.stackColor
        d.stack:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
    end

    -- Duration swipe visibility. style.hideSwipe only runs through AK's
    -- ApplyStyleToRegions (SetShown), firing at button CREATION and on explicit
    -- Restyle passes -- NOT on ordinary aura content churn. The engine calls
    -- Cooldown:SetCooldown on d.cooldown whenever that slot's aura data refreshes,
    -- and that native API implicitly re-Shows the frame, silently undoing
    -- SetShown(false). Two extra layers while "Show Duration Swipe" is OFF, both
    -- reading the LIVE flag (d.pabHideSwipe) because a hook cannot uninstall:
    --   1) a Show post-hook that immediately re-hides (hooksecurefunc runs AFTER
    --      Blizzard's call completes; installed once per button),
    --   2) frame alpha 0 -- Show()/Hide() never touch alpha, so it survives internal
    --      engine paths that re-show the frame outside the hooked Lua method
    --      (post-instance-change re-shows do this).
    if d.cooldown then
        d.pabHideSwipe = style.hideSwipe == true
        -- Install lazily on the first apply that actually hides the swipe. The
        -- hook reads the live flag, so a later toggle back on still works, and a
        -- user who never turns the setting off never gets a closure or a secure
        -- hook on this cooldown's Show at all.
        if d.pabHideSwipe and not d._pabSwipeHooked then
            d._pabSwipeHooked = true
            hooksecurefunc(d.cooldown, "Show", function()
                if d.pabHideSwipe then d.cooldown:Hide() end
            end)
        end
        local a = d.pabHideSwipe and 0 or 1
        if d.pabSwipeAlpha ~= a then
            d.pabSwipeAlpha = a
            d.cooldown:SetAlpha(a)
        end
    end

    -- Icon Effects Per-Filter (debuffs only): flag-gated so buff buttons, which never
    -- carry style.fxList or fx overlay frames, pay zero cost.
    if style.fxList or d.pabFxGlow or d.pabFxBdr then
        PAB_ApplyDmFx(button, d, style)
    end

    -- Centered runs can have an odd content width/height, whose CENTER anchor is a
    -- half pixel. Let textures use Blizzard's normal pixel snapping so
    -- icon art cannot bleed over PP's one-pixel border. Edge-growing bars keep EUI's
    -- usual unsnapped rendering.
    d.pabCenteredSnap = style.centeredGrowth == true
    -- Lazy install on the first centered apply: bars that never use centered
    -- growth never pay the closure. Once installed the hook reads the live
    -- flag, so switching back to edge growth costs one boolean per SetTexture.
    if d.pabCenteredSnap and d.icon and not d.pabIconSnapHooked then
        d.pabIconSnapHooked = true
        hooksecurefunc(d.icon, "SetTexture", function(texture)
            if d.pabCenteredSnap then SetTexturePixelSnap(texture, true) end
        end)
    end
    SetTexturePixelSnap(d.icon, d.pabCenteredSnap)
    local border = d.borderHost and EllesmereUI.PP.GetBorders(d.borderHost)
    if border then
        SetTexturePixelSnap(border._top, d.pabCenteredSnap)
        SetTexturePixelSnap(border._bottom, d.pabCenteredSnap)
        SetTexturePixelSnap(border._left, d.pabCenteredSnap)
        SetTexturePixelSnap(border._right, d.pabCenteredSnap)
    end
end

-- Icon-text outline flag for duration/stack text. Default follows the house icon-text
-- rule: crisp "OUTLINE, SLUG" unless Unit Frames is unchecked in Global Settings'
-- "Outline Icon Text", then the global/per-module choice. A per-bar Font Outline pick
-- overrides that; every branch stays slug-gated centrally via "Never Show Slug".
local function ResolveFontFlag(mode)
    if mode == "none" then return "" end
    if mode == "outline" then
        return (EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE"
    end
    if mode == "thick" then
        return (EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("THICKOUTLINE, SLUG")) or "THICKOUTLINE"
    end
    return (EllesmereUI.GetIconTextOutlineFlag and EllesmereUI.GetIconTextOutlineFlag("unitFrames")) or "OUTLINE"
end

local function BuildStyle(isBuff, cfg)
    local iconZoom = cfg.iconZoom
    local borderSize = cfg.borderSize or 1
    local borderR = cfg.borderR or 0
    local borderG = cfg.borderG or 0
    local borderB = cfg.borderB or 0
    local borderA = cfg.borderA or 1

    -- size 0 = no border; no separate "Hide Border" toggle.
    local border
    if borderSize > 0 then
        border = { borderR, borderG, borderB, borderA, size = borderSize }
    end

    -- Positions may arrive mixed-case ("Bottom") rather than the uppercase anchor
    -- constants SetPoint expects; normalized here so a mismatched-case default or
    -- Options write cannot silently mis-anchor or error.
    local durSide = string.upper(cfg.durationPosition or "CENTER")
    local stackSide = string.upper(cfg.stackPosition or "BOTTOMRIGHT")

    -- Snapped to the physical pixel grid (like MaxIconSizeFor and ApplyGroupConfig's
    -- gap snap) so the rendered size agrees with the container's cross-axis extent
    -- math at any UIParent scale.
    local PP = EllesmereUI.PP
    local iconSize = PP.Scale(PabShapedSize(cfg.iconSize or 32, cfg.iconShape))

    local style = {
        width = iconSize,
        height = iconSize,
        centeredGrowth = cfg.growDirection == "CENTER_HORIZONTAL" or cfg.growDirection == "CENTER_VERTICAL",
        iconCrop = true,
        iconZoom = iconZoom or 0.055,

        -- Reverse Swipe cog (Show Duration Swipe toggle), default on. AK's
        -- ApplyStyleToRegions passes this straight to SetReverse.
        cooldownReverse = (cfg.reverseSwipe ~= false),
        -- Duration swipe: the darkening radial overlay CooldownFrameTemplate draws as
        -- remaining time shrinks, distinct from the duration NUMBER text
        -- (hideDurationText), independently controllable. Per-bar "Show Duration
        -- Swipe" toggle, default on; PAB_ApplyExtraText's swipe block handles the
        -- engine re-show problem.
        hideSwipe = (cfg.showSwipe == false),

        -- Right-click to cancel, mirroring Blizzard's player BuffFrame. PAB is always
        -- the player unit, so only the isBuff half of the sibling module's condition
        -- applies (debuffs are never player-cancelable). Routes to the engine's
        -- AuraButtonMixin:SetCancelAuraButtons -- Blizzard's own secure click-to-cancel,
        -- not a hand-rolled macro/attribute setup. Per-bar "Right-Click to
        -- Cancel" toggle, default on; OFF makes the bar CLICK-through -- the
        -- nil here routes AK to SetMouseClickEnabled(false), so every click
        -- passes straight to the world. Hover is deliberately untouched:
        -- click and motion are separate mouse channels, so tooltips keep
        -- following Show Tooltips below either way.
        -- UP phase, matching Blizzard's own AuraButtonMixin ("LeftButtonUp",
        -- "RightButtonUp"). Known limitation, field-reported 2026-08-12: for some
        -- players the right-button PRESS falls through to WorldFrame, which starts
        -- camera mouselook and captures the mouse, so the matching ButtonUp ends the
        -- mouselook instead of reaching the button and the buff survives. Blizzard's
        -- legacy icons consume that press; the engine's intrinsic AuraButton denies
        -- tainted (addon) code the input aspects that would do the same
        -- (Blizzard_AuraButton.xml: ForbiddenAspect AlwaysPropagateInput /
        -- ScriptedInput), and no API re-grants a denied aspect. "RightButtonDown"
        -- works around it but was rejected deliberately: a right-click-drag starting
        -- on an icon would then cancel that buff on press. Do not "fix" this by
        -- registering BOTH phases either -- Blizzard's CanCancelAuraOnClick matches
        -- any registered token, so OnClick fires twice and the engine may have
        -- re-assigned this button's aura instance in between, cancelling a DIFFERENT
        -- aura on the up edge.
        cancelButtons = (isBuff and cfg.rightClickCancel ~= false) and "RightButtonUp" or nil,

        hideDurationText = cfg.durationShow == false,
        -- "Show S for Seconds" (Duration cog, default off): sub-minute
        -- readings keep their unit ("10s"); selects AK's s-variant duration
        -- formatter at creation, PAB_ApplyExtraText rebinds live.
        durationShowSeconds = cfg.durationShowSeconds == true,
        durationPrecisionThreshold = tonumber(cfg.durationPrecisionThreshold),
        -- Show Tooltips (per-bar, default on): AK's noTooltips path kills
        -- hover on this style's buttons; the flip-back handles re-enables.
        noTooltips = (cfg.showTooltips == false) or nil,
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

        -- Own text pipeline: AK's default font/anchor block is skipped; PAB_ApplyExtraText
        -- does it via the house icon-text rules. Font path and outline flag resolve once
        -- per style rebuild (settings-apply frequency), never per applyExtra call.
        noDefaultFonts = true,
        fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or STANDARD_TEXT_FONT,
        fontFlag = ResolveFontFlag(cfg.fontOutline),

        applyExtra = PAB_ApplyExtraText,

        border = border,
    }

    -- Custom icon shape (Square/Circle/Hexagon/etc, same media set as Action Bars
    -- and Unit Frames' detached portraits). ns.PORTRAIT_MASKS/BORDERS/MASK_INSETS are
    -- exposed by EllesmereUIUnitFrames.lua (same addon/ns); AuraKit itself lives in a
    -- separate TOC and never touches ns, so resolved paths travel through style.*.
    local shape = cfg.iconShape
    if PabShapeActive(shape) then
        style.iconShape       = shape
        style.shapeMaskPath   = ns.PORTRAIT_MASKS and ns.PORTRAIT_MASKS[shape]
        style.shapeBorderPath = ns.PORTRAIT_BORDERS and ns.PORTRAIT_BORDERS[shape]
        style.shapeInsetPx    = ns.MASK_INSETS and ns.MASK_INSETS[shape]
        style.shapeBorderSize = cfg.shapeBorderSizeOverride or PabShapeBorderSize(borderSize)
    end

    -- Engine dispel-type border, debuffs only (buffs have no dispel type). AK's gate
    -- (ApplyStyleToRegions) only activates it when `border` above is ALSO non-nil, so
    -- borderSize = 0 disables dispel-type coloring too, not just the static ring --
    -- engine behavior, not a choice made here. borderSize drives BOTH ring widths; a
    -- distinct dispel-ring width would need its own setting split back out.
    if not isBuff then
        local dcMap, dcFP = BuildDispelColorMap(cfg)
        style.dispelBorder = true
        style.dispelBorderPx = borderSize
        style.dispelColorMap = dcMap
        style.dispelColorFP = dcFP

        -- Dispel-type indicator icon (AK's one-hot engine channel; default off).
        -- Independent of borderSize: the icon renders with or without a ring.
        local dip = cfg.dispelIconPosition
        if dip and dip ~= "none" then
            style.dispelTypeIcon = {
                pos = dip,
                -- Scaled like iconSize (button-geometry class); offsets stay raw
                -- like durationX (fine-tune class).
                size = PP.Scale(cfg.dispelIconSize or 16),
                offX = cfg.dispelIconOffsetX or 0,
                offY = cfg.dispelIconOffsetY or 0,
            }
        end

        -- Icon Effects Per-Filter: debuffs only (buffs never get style.fxList, so
        -- PAB_ApplyDmFx's gate in PAB_ApplyExtraText stays a cheap no-op).
        style.fxList = PAB_FxListView(cfg.fxList)
    end

    return style
end

-- ApplyGroupConfig (below) declares/updates every group in `chain` on an existing
-- container. Groups are ADDITIVE and the container is NEVER torn down and rebuilt:
-- ReleaseContainer()+RequestContainer() permanently leaks a 10-button engine batch per
-- group per swap (WoW never frees frames). A class toggle (or grid/padding/growth
-- change) just calls it again on the SAME container.
--
-- A group's filter string is fixed at declaration (AuraContainer has no group filter
-- setter), so an already-declared class keeps its original negation-chain tokens even
-- if an earlier-priority class is toggled later -- a known, accepted limitation shared
-- with the sibling module. Only matters when a re-order changes an ALREADY-DECLARED
-- class's negation set; toggling the SAME class on/off is always correct, since only
-- its maxFrameCount changes.
--
-- Sort resolution uses the native enum globals: AuraContainerSortMethod = {Default=0,
-- BigDefensive=1, UnitFrameDebuff=2, ImportantOnly=3, Expiration=4, ExpirationOnly=5,
-- Name=6, NameOnly=7, AuraInstanceIDOnly=8}, AuraContainerSortDirection = {Normal=0,
-- Reverse=1}. Default=0 and Normal=0 are valid values, not "unset" -- compare against
-- nil, never truthiness.
local function ResolveSortMethod(cfg)
    local key = cfg.sortMethod or "Default"
    return AuraContainerSortMethod and AuraContainerSortMethod[key]
end
local function ResolveSortDirection(cfg)
    local key = (cfg.sortDirection == "Reverse") and "Reverse" or "Normal"
    return AuraContainerSortDirection and AuraContainerSortDirection[key]
end

-- "Has Duration" (Assigned Buffs filter), buffs only: native
-- `candidateFilters.maxDuration`. Blizzard's check excludes an aura when
-- `duration > maxDuration or duration == 0` (max-duration filters implicitly always
-- filter out permanent auras), so a `math.huge` cap never trips the `>` half and this
-- ONLY excludes permanent (duration=0) buffs, whatever a timed buff's duration is.
local function BuffCandidateExtras(cfg)
    local out
    if cfg and cfg.hasDuration then
        out = { maxDuration = math.huge }
    end
    -- Blacklist (Edit Blacklist in the Filters dropdown): applied exactly while the
    -- dropdown offers it (All Buffs or Has Duration on) and rides every buff group via
    -- this extras merge -- catch-all AND spells group -- so a blacklisted spell never
    -- displays. Fresh table per call: merged maps must never alias saved vars.
    if cfg and cfg.blacklist and next(cfg.blacklist)
        and (cfg.showAllBuffs ~= false or cfg.hasDuration == true) then
        out = out or {}
        local ex = {}
        for id in pairs(cfg.blacklist) do ex[id] = true end
        out.excludeSpellIDs = ex
    end
    return out
end

-- Debuff-side twin of BuffCandidateExtras: "Has Duration" narrows every debuff
-- group (class groups AND the catch-all, via the same extras merge) to
-- duration-carrying debuffs with the native maxDuration check. math.huge never
-- trips the `>` half, so this excludes exactly the permanent (duration = 0)
-- debuffs. The inverse ("permanents only") is NOT expressible -- maxDuration is
-- the engine's only duration filter (Blizzard_AuraContainerUtil), so Has
-- Duration exists as a show-side AND-modifier only, never a hide-lane entry.
local function DebuffCandidateExtras(cfg)
    if cfg and cfg.hasDuration then
        return { maxDuration = math.huge }
    end
    return nil
end

-- Has Duration is an AND-MODIFIER (user directive 2026-08-16), not a broad
-- mode: it rides every chain link via DebuffCandidateExtras, so with class
-- filters checked it narrows exactly those. The catch-all only joins when
-- nothing narrower is selected -- All Debuffs on, or Has Duration checked with
-- no class filters picked (alone = every timed debuff).
local function DebuffCatchAllOn(cfg)
    if cfg.showAllDebuffs ~= false then return true end
    if cfg.hasDuration ~= true then return false end
    local cf = cfg.classFilters
    if cf then
        for _, v in pairs(cf) do
            if v == true then return false end
        end
    end
    return true
end

-- MergeCandidateFilters (below) merges `extra` onto a copy of `base`, nil-safe both
-- ways: e.g. a chain-link's own candidateFilters (debuff class token) plus
-- BuffCandidateExtras' maxDuration.
--
-- Order-independent fingerprint of a candidate-filter table. Candidate payloads are
-- DECLARATION-FIXED on an existing group (SetAuraGroupCandidateFilters on a live
-- group does not retake), so any payload change must declare a fresh variant group
-- key. Number-keyed sets (spell ids) fingerprint as count:sum; string-keyed sets
-- (dispel names) join.
local function CandFP(cf)
    if not cf then return "-" end
    local keys = {}
    for k in pairs(cf) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        local v = cf[k]
        if type(v) == "table" then
            local first = next(v)
            if type(first) == "number" then
                local n, sum = 0, 0
                for id in pairs(v) do
                    n = n + 1
                    sum = (sum + id) % 2147483647
                end
                parts[#parts + 1] = k .. "=" .. n .. ":" .. sum
            else
                local names = {}
                for name in pairs(v) do names[#names + 1] = tostring(name) end
                table.sort(names)
                parts[#parts + 1] = k .. "=" .. table.concat(names, "+")
            end
        else
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    return table.concat(parts, ",")
end

local function MergeCandidateFilters(base, extra)
    if not extra then return base end
    if not base then return extra end
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(extra) do
        if k == "excludeSpellIDs" and out[k] then
            -- Exclude maps UNION (never overwrite): the catch-all's subtract set
            -- and the extras' blacklist both survive.
            local m = {}
            for id in pairs(out[k]) do m[id] = true end
            for id in pairs(v) do m[id] = true end
            out[k] = m
        else
            out[k] = v
        end
    end
    return out
end

-- ApplyGroupConfig parameters: declaredSet is a per-container registry of every group
-- key ever declared (declared.debuffs for Debuff bars' class-token chain,
-- declared.buffs for the default Buffs bar's single "Show All Buffs" catch-all -- see
-- CreateBars for why buffs need ONE group alongside their slots). cfg is the bar's
-- settings table, read-only here, used only to resolve sortMethod/sortDirection;
-- SetAuraGroupSortMethod (unlike AddAuraGroup's sortMethod field) requires both
-- non-nil, so it's re-applied every pass, same as MaxFrameCount/Layout. extraCand
-- (optional) is candidateFilters merged onto every chain-link's own, threading
-- BuffCandidateExtras' maxDuration onto the Buffs catch-all without affecting Debuffs'
-- class-token chains (pass nil); re-applied live every pass via
-- SetAuraGroupCandidateFilters, since only the FILTER STRING is fixed at declaration.
--
-- Icon Effects Per-Filter Size override: icon size is entirely style-driven
-- (button:SetSize(style.width, style.height)); a group's own elementWidth/Height in
-- SetAuraGroupLayout feeds the FLOW MATH only, never resizes the button. A per-category
-- size needs its OWN style key, not a group-layout tweak. Keyed by size alone: the
-- variant is the bar's base style with width/height swapped, so two categories at the
-- same size share one variant, everything else riding along via the shallow copy.
-- Rebuilt unconditionally every pass (settings-apply frequency) rather than
-- fingerprint-cached.
local function EnsurePabSizedStyle(baseKey, size, shape)
    local base = AK.styles[baseKey]
    if not base then return baseKey end
    local variantKey = baseKey .. ":sz" .. tostring(size)
    local v = {}
    for k, val in pairs(base) do v[k] = val end
    -- Snapped like BuildStyle's own width/height (same button SetSize path, so a raw
    -- value reintroduces the 1px border/icon disagreement); the variant KEY stays
    -- keyed by the raw size. Shape-expand applies the same as BuildStyle's own
    -- iconSize -- base already carries iconShape/shapeMaskPath/etc via the shallow
    -- copy above, only width/height need recomputing for this variant's own size.
    local PP = EllesmereUI.PP
    v.width = PP.Scale(PabShapedSize(size, shape))
    v.height = PP.Scale(PabShapedSize(size, shape))
    AK.styles[variantKey] = v
    AK.RestyleSoon(variantKey)
    return variantKey
end

local function BuildGroupLayout(cfg, gap, rowGap, size)
    local PP = EllesmereUI.PP
    rowGap = rowGap or gap
    size = PP.Scale(PabShapedSize(size or cfg.iconSize or 32, cfg.iconShape))
    gap = PP.Scale(gap)
    rowGap = PP.Scale(rowGap)
    return {
        elementWidth = size,
        elementHeight = size,
        elementSpacing = gap,
        lineSpacing = rowGap,
        groupSpacing = gap,
        groupLineSpacing = rowGap,
    }
end

local function ApplyGroupConfig(container, chain, declaredSet, styleKey, effectiveMax, gap, rowGap, cfg, extraCand)
    local sortMethod = ResolveSortMethod(cfg)
    local sortDirection = ResolveSortDirection(cfg)
    -- elementSpacing = icon-to-icon gap in a row; lineSpacing = gap between wrapped
    -- rows within a group; group*Spacing = gap to the NEXT group on the same
    -- container. elementSpacing/groupSpacing stay tied to `gap` (padding);
    -- lineSpacing/groupLineSpacing use `rowGap` (defaults to `gap`) so row-to-row
    -- distance is overridable independently of icon-to-icon spacing (cfg.rowSpacing in
    -- the Settings Schema comment). Container-level padding is a THIRD, unrelated
    -- concept: the OUTER edge inset, fixed at 0 elsewhere and never affected by either.
    local active = {}
    for i = 1, #chain do
        local link = chain[i]
        -- Size override, debuffs only: cfg.fxList is nil for buffs, so szOv is always
        -- nil there.
        local szOv = PAB_FxSizeFor(cfg.fxList, link.key)
        local layout = BuildGroupLayout(cfg, gap, rowGap, szOv)
        -- Token strings are declaration-fixed too, so the effective key embeds the
        -- link's token set: a changed negation shape (subtract flips, class-set edits)
        -- declares a fresh variant instead of leaving a stale filter on the old group.
        -- link.key alone stays the fx CATEGORY identity (d.dmCat / PAB_FxSizeFor).
        local effKey = link.key .. "|" .. table.concat(link.tokens, "")
        if szOv then effKey = effKey .. "|sz" end
        local linkStyleKey = szOv and EnsurePabSizedStyle(styleKey, szOv, cfg.iconShape) or styleKey
        local candidateFilters
        if link.cand then
            -- link.cand is from the shared class vocabulary -- copy it so the merges
            -- below never mutate it.
            candidateFilters = {}
            for k, v in pairs(link.cand) do candidateFilters[k] = v end
        end
        candidateFilters = MergeCandidateFilters(candidateFilters, link.excludeCand)
        candidateFilters = MergeCandidateFilters(candidateFilters, extraCand)
        -- Candidate payloads are declaration-fixed (see CandFP): when a link's payload
        -- changes on a live container (catch-all subtracts, buff filter subtract sets,
        -- Has Duration) its fingerprint picks the group variant. A fresh fingerprint
        -- declares a fresh variant and the stale one parks at 0 in the active-set sweep
        -- below, like any disabled class group. Fingerprints REUSE their variant, so
        -- toggling a subtract off and back on reuses the same engine groups rather than
        -- minting a new 10-button batch per flip.
        local fp = CandFP(candidateFilters)
        local meta = declaredSet["__cand|" .. effKey]
        if not meta then
            meta = { n = 0, map = {} }
            declaredSet["__cand|" .. effKey] = meta
        end
        local variant = meta.map[fp]
        if not variant then
            variant = meta.n
            meta.map[fp] = variant
            meta.n = meta.n + 1
        end
        if variant > 0 then effKey = effKey .. "#" .. variant end
        active[effKey] = true
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
                layout = layout,
                -- Icon Effects Per-Filter: stamps this button's category (matched
                -- against fxList blocks by PAB_ApplyDmFx) and arms the glow/border
                -- overlay inside the one legal creation window. style.applyExtra runs
                -- BEFORE extraInit at creation (EllesmereUI_AuraKit.lua's
                -- MakeInitializer), so the first applyExtra pass sees d.dmCat == nil
                -- harmlessly and this re-arms it right after.
                extraInit = function(button, d, style)
                    d.dmCat = catKey
                    PAB_ApplyDmFx(button, d, style)
                end,
            })
            declaredSet[effKey] = true
        end
        -- Hidden links (subtracted classes) stay declared so their chain negations
        -- keep excluding them from the catch-all, but render nothing themselves.
        container:SetAuraGroupMaxFrameCount(effKey, link.hidden and 0 or effectiveMax)
        container:SetAuraGroupLayout(effKey, layout)
        container:SetAuraGroupCandidateFilters(effKey, candidateFilters)
        if sortMethod ~= nil and sortDirection ~= nil then
            container:SetAuraGroupSortMethod(effKey, sortMethod, sortDirection)
        end
    end

    -- Zero out any previously-declared group that fell out of the active chain (class
    -- disabled, or a candidate payload change superseded its variant). Stays declared,
    -- just hidden: it cannot be un-declared. "__cand|" entries are generation
    -- metadata, not group keys.
    for key in pairs(declaredSet) do
        if not active[key] and key:sub(1, 7) ~= "__cand|" then
            container:SetAuraGroupMaxFrameCount(key, 0)
        end
    end
end

-- Retire a container we are abandoning. AuraContainer frames are PERMANENT and a
-- declared group can NEVER be un-declared (the sweep above can only zero one), so
-- AK.ReleaseContainer hides the frame but leaves every group live on it at whatever
-- frame count it last had -- anything that shows that frame again renders the old
-- content. Zero what we know about while we still hold the declared set; "spells"
-- is declared outside the chain, so it goes by name. pcall: zeroing a key this
-- container never declared is not worth an error.
local function RetireContainer(container, declaredSet)
    if not container then return end
    if declaredSet then
        for key in pairs(declaredSet) do
            if key:sub(1, 7) ~= "__cand|" then
                pcall(container.SetAuraGroupMaxFrameCount, container, key, 0)
            end
        end
    end
    pcall(container.SetAuraGroupMaxFrameCount, container, "spells", 0)
    AK.ReleaseContainer(container)
end

-- Grid sizing. AK's flow layout only exposes a row WIDTH (pixels) to wrap on, no
-- native "max lines" cap, so a row cap is enforced indirectly by capping
-- maxFrameCount to rows*cols; the anchor frame's footprint is our own bounding-box
-- estimate from the same three numbers, not something AK reports back.
--
-- Settings: maxTotal (overall cap), iconsPerRow (columns), maxRows. Effective cap =
-- min(maxTotal, maxRows * iconsPerRow) -- e.g. maxTotal=10 on a 5x5 grid still shows
-- at most 10, using 2 rows. iconsPerRow/maxRows/maxTotal fallbacks are
-- isBuff-conditional (11x3=32 buffs, 8x2=16 debuffs), reached only when a bar doesn't
-- set these itself (the two default bars); every custom bar sets all three explicitly
-- (PAB_AddCustomBuffBar/DebuffBar, 8x1=8 for both).
--
-- width/height: N icons need (N-1) gaps, not N -- `cols * (iconSize + pad)` bakes in
-- one extra trailing pad, making the box a few px bigger than its icons. This sizes
-- the LIVE bar's parent frame and the preview box (RenderPreviewIcons/
-- PAB_BuildPreviewBox); the CENTER-anchor recompensation math assumes it's accurate.
-- Because an Icon Effects Size override renders one category's icons bigger via a
-- separate sized style variant (EnsurePabSizedStyle) without growing the frame, the
-- box is sized for the LARGEST icon that could ever appear. An exact footprint is
-- impossible ahead of time -- a FLOW layout mixing per-group icon sizes is
-- data-dependent -- so this follows the same static worst-case capacity reservation
-- spirit maxTotal/rows*cols already use.
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
    -- Snap to the physical pixel grid (same reasoning as ApplyGroupConfig's gap/rowGap
    -- snap): a raw iconSize also feeds the container's cross-axis extent math
    -- (ComputeGrid) at a non-pixel-perfect UIParent scale. Shape-expand applied last so
    -- the bar frame's footprint (ComputeGrid) always matches the buttons' real size.
    local PP = EllesmereUI.PP
    return PP.Scale(PabShapedSize(size, cfg.iconShape))
end

local function ComputeGrid(isBuff, cfg)
    local iconSize = MaxIconSizeFor(isBuff, cfg)
    local pad = cfg.padding or 5
    local rowGap = cfg.rowSpacing or 12
    local layoutPad = EllesmereUI.PP.Scale(pad)
    local layoutRowGap = EllesmereUI.PP.Scale(rowGap)
    local cols = math.max(1, cfg.iconsPerRow or (isBuff and 11 or 8))
    local rows = math.max(1, cfg.maxRows or (isBuff and 3 or 2))
    local configuredMax = cfg.maxTotal or (isBuff and 32 or 16)
    local effectiveMax = math.min(configuredMax, rows * cols)
    -- Actual rows needed for the effective cap, never more than the row limit
    local usedRows = math.min(rows, math.max(1, math.ceil(effectiveMax / cols)))
    -- `lineExtent` is the icons' own extent on the line axis (iconsPerRow
    -- icons of iconSize + gaps); `crossExtent` is the other axis (lines actually used).
    -- Horizontal growth: a "line" is a row, so lineExtent -> width. Vertical growth
    -- modes: a "line" is a column, so lineExtent -> height -- see
    -- CornerFor/BuildContainerSpec for the matching growthH/growthV swap.
    local lineExtent = cols * iconSize + (cols - 1) * layoutPad
    -- Wrap budget handed to the engine. At POSITIVE spacing the engine reserves a
    -- TRAILING elementSpacing after every element (not only between), so a full
    -- line needs cols * (icon + spacing) or the last icon of every row wraps --
    -- field-confirmed twice, most recently 2026-08-14 (11-per-row wrapped at 10
    -- without the trailing pad). At NEGATIVE spacing that same trailing reserve
    -- makes the final icon wrap EARLY, so the budget adds nothing there.
    -- lineExtent still sizes the bar's own frame either way, so the drag box
    -- measures the icons, not the phantom trailing gap.
    local rowWidth = math.max(iconSize, lineExtent) + math.max(0, layoutPad)
    local crossExtent = usedRows * iconSize + (usedRows - 1) * layoutRowGap
    local vertical = (cfg.growDirection == "UP" or cfg.growDirection == "DOWN" or cfg.growDirection == "CENTER_VERTICAL")
    local width = vertical and crossExtent or lineExtent
    local height = vertical and lineExtent or crossExtent
    return {
        effectiveMax = effectiveMax,
        rowWidth = rowWidth,
        width = width,
        height = height,
        rowGap = rowGap,
    }
end

-- Lazily creates and returns the default bars' per-polarity cfg sub-tables: same
-- shape as a custom bar object's shared+category fields, so
-- BuildStyle/ComputeGrid/ClassEnabled cannot tell the two apart.
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

-- True while the default Buffs bar shows NOTHING but weapon enchants: the
-- opt-in is on and neither broad-content mode admits generic buffs. Filters /
-- Extra Spells are deliberately NOT considered -- they resolve to a finite
-- add-set that comes and goes as the user edits it, and letting that flip the
-- bar's name and grid underneath them would be unpredictable.
function ns.PAB_IsWeaponEnchantsOnly(cfg)
    return cfg ~= nil and cfg.showWeaponEnchants == true
        and cfg.showAllBuffs == false and cfg.hasDuration ~= true
end

-- Default Buffs bar display name, following what the bar actually shows.
-- Weapon enchants are a content source of their own, so they rename the bar
-- outright when nothing else is on and append to it otherwise; Has Duration
-- counts as a broad buff mode here, the bar still leads with generic buffs.
--
-- Returns the RAW English key: unlock mode stores element labels untranslated
-- (EUI_UnlockMode.lua's GetBarLabel hands back elem.label verbatim), and the
-- options page wraps the result in L() itself. Defined here, next to the cfg
-- it reads, so the options page and the unlock element cannot drift apart.
function ns.PAB_DefaultBuffsName(cfg)
    if not (cfg and cfg.showWeaponEnchants == true) then return "Buffs" end
    if ns.PAB_IsWeaponEnchantsOnly(cfg) then return "Weapon Enchants" end
    return "Buffs & Weapon Enchants"
end

-- One-time seed of the default Buffs/Debuffs bars' position/size/grid from Blizzard's
-- EditMode Buff/Debuff frame setup, so a first-time PAB user doesn't lose an
-- already-customized Blizzard layout. Guarded by s.pabEditModeSeeded, deliberately NOT
-- a nil-check on s.buffsPos/s.defaultBuffs: Buffs/Debuffs bars already exist for every
-- current user, so a nil-check would treat "never manually moved" as "brand new
-- profile" and silently reposition/resize existing bars.
--
-- Reads live BuffFrame/DebuffFrame state rather than C_EditMode.GetLayouts(): that
-- table is not reliably indexable by `activeLayout` (the pairs-key holding the active
-- layout's data did not match activeLayout's number, no other field to match on).
-- Blizzard has already resolved and applied the active layout onto these two frames by
-- the time addons run, so reading their live AuraContainer fields sidesteps the lookup.
--
-- Field mapping: AuraContainer.iconPadding -> padding (direct pixels).
-- AuraContainer.iconScale (observed 0.5-2.0, Blizzard's 50%-200% slider) -> iconSize =
-- round(32 * scale); assumes Blizzard's 100% matches PAB's 32px default (an
-- approximation, low risk, user can readjust). AuraContainer.iconStride -> iconsPerRow
-- (NOT maxTotal: "stride" = icons per row before wrapping, exact-matched against
-- Blizzard's IconLimitBuffFrame/DebuffFrame setting; no Blizzard equivalent for a true
-- total cap exists, so maxTotal stays unmigrated at PAB's own default).
-- AuraContainer.isHorizontal + .addIconsToRight/.addIconsToTop -> growDirection +
-- iconWrapDirection (the vertical-orientation branch is inferred from PAB's own
-- cross-axis convention, ToGrowthH/CornerFor above, NOT tested -- verification only
-- covered a horizontal Blizzard layout). frame:GetLeft()/GetTop() minus UIParent's own
-- -> buffsPos/debuffsPos, stored as a TOPLEFT-relative-to-UIParent offset --
-- deliberately NOT GetPoint()'s raw relativeTo, since PAB always anchors to UIParent
-- (ApplyBarPosition) while Blizzard's anchor can chain to an arbitrary frame (observed:
-- Buffs relativeTo="DebuffFrame"); absolute screen coordinates sidestep that chain.
local function SeedBarFromEditMode(frame, cfg, posKey, s, isBuff)
    if not (frame and frame.AuraContainer) then return end
    local ac = frame.AuraContainer

    local uiLeft, uiTop = UIParent:GetLeft(), UIParent:GetTop()
    local left, top = frame:GetLeft(), frame:GetTop()
    if uiLeft and uiTop and left and top then
        s[posKey] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = left - uiLeft, y = top - uiTop }
    end

    if ac.iconPadding then cfg.padding = ac.iconPadding end
    if ac.iconScale then cfg.iconSize = math.floor(32 * ac.iconScale + 0.5) end
    if ac.iconStride then
        cfg.iconsPerRow = ac.iconStride
        -- Keep the full icon cap reachable when the migrated row width is narrower
        -- than PAB's default (Blizzard stride=7 vs fallback iconsPerRow=11):
        -- ComputeGrid caps at min(maxTotal, maxRows*iconsPerRow) and maxTotal is NOT
        -- migrated, so maxRows must grow or a narrower stride silently shows fewer
        -- icons than the un-migrated default did. cap matches ComputeGrid's own
        -- isBuff-conditional maxTotal fallback (32/16) exactly.
        local cap = isBuff and 32 or 16
        cfg.maxRows = math.max(1, math.ceil(cap / ac.iconStride))
    end

    if ac.isHorizontal ~= nil then
        if ac.isHorizontal then
            cfg.growDirection = ac.addIconsToRight and "RIGHT" or "LEFT"
        else
            cfg.growDirection = ac.addIconsToTop and "UP" or "DOWN"
            cfg.iconWrapDirection = ac.addIconsToRight and "RIGHT" or "LEFT"
        end
    end
end

-- Migrates the retired Styled Player Auras module (db.profile.playerAuras). That
-- module never controlled position/size/grid (Blizzard drove layout via Edit Mode),
-- so nothing here duplicates SeedBarFromEditMode above; it DID apply border/font
-- styling as ONE shared flat cfg table, not split per polarity. Gated on the old
-- module's own `enabled` flag: only migrate if it was actually on. Field mapping:
-- borderSize/borderR/G/B/A -> same field name on BOTH buffCfg and debuffCfg (one
-- shared old value, not two). showText -> durationShow, both bars (same nil/true =
-- shown). textSize -> BOTH durationTextSize AND stackTextSize on both bars: the old
-- SkinAuraButton sized duration AND stack-count font strings from cfg.textSize, NOT
-- the duration-only/stack-only split the old External Defensives module uses.
-- noBorderDebuffs -> debuffCfg.borderSize = 0 (debuffs-only override, applied after
-- the shared borderSize above). NOT migrated, no PAB cfg field exists (known gap):
-- borderTexture/borderTextureOffset(Y)/borderTextureShiftX/Y/borderBehind,
-- durationFormat. Old buffIconZoom/debuffIconZoom are also skipped -- PAB has its own
-- per-bar iconZoom.
local function MigratePlayerAuraStyle(buffCfg, debuffCfg)
    local old = ns.db and ns.db.profile and ns.db.profile.playerAuras
    if not (old and old.enabled) then return end

    for _, cfg in ipairs({ buffCfg, debuffCfg }) do
        if old.borderSize then cfg.borderSize = old.borderSize end
        if old.borderR then cfg.borderR = old.borderR end
        if old.borderG then cfg.borderG = old.borderG end
        if old.borderB then cfg.borderB = old.borderB end
        if old.borderA then cfg.borderA = old.borderA end
        if old.showText ~= nil then cfg.durationShow = old.showText end
        if old.textSize then
            cfg.durationTextSize = old.textSize
            cfg.stackTextSize = old.textSize
        end
    end

    if old.noBorderDebuffs then
        debuffCfg.borderSize = 0
    end
end

-- One-shot filter-model upgrade (v2, per profile): debuff bars moved to the unified
-- All Debuffs + filters dropdown, where checked classes SUBTRACT while Show All is on.
-- Stale add-mode selections that Show All used to bypass would suddenly subtract
-- content -- clear them once on every Show All debuff bar; add-mode bars keep theirs.
local function EnsureDebuffFilterV2(s)
    if s.pabDebuffFiltersV2 then return end
    s.pabDebuffFiltersV2 = true
    local d = s.defaultDebuffs
    if d and d.showAllDebuffs ~= false then d.classFilters = nil end
    if s.customDebuffBars then
        for i = 1, #s.customDebuffBars do
            local bar = s.customDebuffBars[i]
            if bar.showAllDebuffs ~= false then bar.classFilters = nil end
        end
    end
end

-- One-shot lane split (per profile): the filter dropdowns became two-lane (show/hide),
-- so the single mode-dependent selection splits into cfg.filters/classFilters (SHOW)
-- and cfg.negFilters/negClassFilters (HIDE). A broad-mode bar's checked entries were
-- subtracting -- move them to the hide lane so rendering is bit-identical; add-mode
-- selections already mean SHOW and stay put. Runs after EnsureDebuffFilterV2.
local function EnsureFilterLanes(s)
    if s.pabFilterLanesV1 then return end
    s.pabFilterLanesV1 = true
    local function SplitBuff(bar)
        if not bar then return end
        if (bar.showAllBuffs ~= false or bar.hasDuration == true)
            and bar.filters and next(bar.filters) then
            bar.negFilters = bar.filters
            bar.filters = nil
        end
    end
    local function SplitDebuff(bar)
        if not bar then return end
        if bar.showAllDebuffs ~= false and bar.classFilters and next(bar.classFilters) then
            bar.negClassFilters = bar.classFilters
            bar.classFilters = nil
        end
    end
    SplitBuff(s.defaultBuffs)
    if s.customBuffBars then
        for i = 1, #s.customBuffBars do SplitBuff(s.customBuffBars[i]) end
    end
    SplitDebuff(s.defaultDebuffs)
    if s.customDebuffBars then
        for i = 1, #s.customDebuffBars do SplitDebuff(s.customDebuffBars[i]) end
    end
end
ns.PAB_EnsureFilterLanes = EnsureFilterLanes

-- Content-source tests for the no-empty-selection rule: a bar always keeps at
-- least one content source (a broad mode, a Show-lane filter, an Extra Spell,
-- or -- default Buffs bar only -- Weapon Enchants). The hide lane is not a
-- content source. Shared by the enable migration below and the options
-- dropdowns' guards.
local function BuffBarHasContent(bar, isDefault)
    if bar.showAllBuffs ~= false or bar.hasDuration == true then return true end
    if bar.filters and next(bar.filters) then return true end
    if bar.spells and #bar.spells > 0 then return true end
    if isDefault and bar.showWeaponEnchants == true then return true end
    return false
end
-- Debuff content besides the All Debuffs mode: Show-lane classes, or an Icon
-- Effects block forcing a safe class on ("as if that Base Filter were on" --
-- the chain builders' fx wrapper renders those categories even in add mode, so
-- an fx-only bar is NOT empty).
local function DebuffBarOtherContent(bar)
    if bar.classFilters and next(bar.classFilters) then return true end
    if bar.fxList then
        local function AnyForced(list)
            if not list then return false end
            for i = 1, #list do
                local class = list[i]
                if PAB_FxSafeToForce(class) and PAB_FxWantsCategory(bar.fxList, class.key) then
                    return true
                end
            end
            return false
        end
        if AnyForced(VisibleTokenClasses()) or AnyForced(VisibleCandidateClasses()) then
            return true
        end
    end
    return false
end
local function DebuffBarHasContent(bar)
    if bar.showAllDebuffs ~= false or bar.hasDuration == true then return true end
    return DebuffBarOtherContent(bar)
end
ns.PAB_BuffBarHasContent = BuffBarHasContent
ns.PAB_DebuffBarOtherContent = DebuffBarOtherContent
ns.PAB_DebuffBarHasContent = DebuffBarHasContent

-- One-shot (per profile), HISTORICAL: written when the phase-2 no-empty rule
-- held (dropdown guards kept one content source alive). Those guards are gone
-- (2026-08-15): empty selections are legal again and the options page warns
-- loudly instead (red dropdown + bubble, AttachEmptyFilterWarn). The mapping
-- below still runs once for pre-phase-2 profiles: a LEGACY bar with no
-- content source rendered nothing, so it becomes All + disabled -- the same
-- nothing on screen, with sensible content on re-enable. Post-stamp empties
-- created through the dropdown are left exactly as the user set them. Runs
-- after EnsureFilterLanes (lanes must be split before emptiness is judged;
-- a broad-mode bar is never empty either way).
local function EnsureBarEnable(s)
    EnsureFilterLanes(s)
    if s.pabBarEnableV1 then return end
    s.pabBarEnableV1 = true
    local function MapBuff(bar, isDefault)
        if not bar then return end
        if bar.enabled ~= false and not BuffBarHasContent(bar, isDefault) then
            bar.showAllBuffs = nil -- All Buffs back on (nil = on)
            bar.enabled = false
        end
    end
    local function MapDebuff(bar)
        if not bar then return end
        if bar.enabled ~= false and not DebuffBarHasContent(bar) then
            bar.showAllDebuffs = nil
            bar.enabled = false
        end
    end
    MapBuff(s.defaultBuffs, true)
    if s.customBuffBars then
        for i = 1, #s.customBuffBars do MapBuff(s.customBuffBars[i], false) end
    end
    MapDebuff(s.defaultDebuffs)
    if s.customDebuffBars then
        for i = 1, #s.customDebuffBars do MapDebuff(s.customDebuffBars[i]) end
    end
end
ns.PAB_EnsureBarEnable = EnsureBarEnable

local function SeedDefaultBuffsDebuffsFromLegacySources(s)
    if s.pabEditModeSeeded then return end
    s.pabEditModeSeeded = true -- set first: never retry even if a read below errors/fails partway
    local buffCfg, debuffCfg = DefaultBuffsCfg(s), DefaultDebuffsCfg(s)
    SeedBarFromEditMode(BuffFrame, buffCfg, "buffsPos", s, true)
    SeedBarFromEditMode(DebuffFrame, debuffCfg, "debuffsPos", s, false)
    MigratePlayerAuraStyle(buffCfg, debuffCfg)
end

-- One-shot: the External Defensives bar is a normal custom buff bar carrying the
-- imported "Externals" preset filter (curated external-defensive spell list;
-- PAB_ImportBM2Filters must have run already -- see CreateBars' call order), so it
-- needs zero bespoke machinery. Seeded once per profile, disabled by default like the
-- built-in it replaced. Sources, newest first: the retired built-in bar's saved cfg
-- (s.defaultExternalDefensives), else the pre-PAB standalone module's table
-- (growDirection was lowercase there; showText -> durationShow; textSize styled the
-- stack/application-count text -> stackTextSize), else plain disabled defaults. The
-- retired position slots (s.extDefPos / the legacy module's unlockPos) become the
-- bar's own pos.
local function EnsureExtDefCustomBar(s)
    if s.pabExtDefSeeded == 2 then return end
    local extId
    do
        local list = ns.PAB_Filters and ns.PAB_Filters()
        if list then
            for i = 1, #list do
                if list[i].preset and list[i].name == "Externals" then
                    extId = list[i].id
                    break
                end
            end
        end
    end
    -- v1 of this seed gave the bar a bespoke extDefFilter pseudo-filter (since
    -- removed); convert those bars in place to the preset filter.
    if s.pabExtDefSeeded then
        s.pabExtDefSeeded = 2
        local bars = s.customBuffBars
        if bars and extId then
            for i = 1, #bars do
                local b = bars[i]
                if b.extDefFilter then
                    b.extDefFilter = nil
                    b.showAllBuffs = false
                    b.filters = { [extId] = true }
                end
            end
        end
        return
    end
    s.pabExtDefSeeded = 2
    local src = s.defaultExternalDefensives
    local legacy = ns.db and ns.db.profile and ns.db.profile.externalDefensives
    local from = src or legacy
    s.nextBarId = (s.nextBarId or 1)
    local bar = {
        id = s.nextBarId,
        name = "External Defensives",
        enabled = false,
        showAllBuffs = false,
        filters = extId and { [extId] = true } or {},
        spells = {}, ownOnlySpells = {},
        growDirection = "LEFT",
        iconsPerRow = 4, maxRows = 1, maxTotal = 4,
        durationPosition = "CENTER",
    }
    s.nextBarId = s.nextBarId + 1
    if from then
        if from.enabled ~= nil then bar.enabled = from.enabled == true end
        if from.iconSize then bar.iconSize = from.iconSize end
        if from.growDirection then bar.growDirection = string.upper(from.growDirection) end
        if from.durationShow ~= nil then bar.durationShow = from.durationShow
        elseif from.showText ~= nil then bar.durationShow = from.showText end
        if from.stackTextSize then bar.stackTextSize = from.stackTextSize
        elseif from.textSize then bar.stackTextSize = from.textSize end
        if from.durationPosition then bar.durationPosition = from.durationPosition end
        if from.durationTextSize then bar.durationTextSize = from.durationTextSize end
        if from.durationOffsetX then bar.durationOffsetX = from.durationOffsetX end
        if from.durationOffsetY then bar.durationOffsetY = from.durationOffsetY end
        if from.durationColorR then bar.durationColorR, bar.durationColorG, bar.durationColorB = from.durationColorR, from.durationColorG, from.durationColorB end
        if from.stackShow ~= nil then bar.stackShow = from.stackShow end
        if from.stackPosition then bar.stackPosition = from.stackPosition end
        if from.stackOffsetX then bar.stackOffsetX = from.stackOffsetX end
        if from.stackOffsetY then bar.stackOffsetY = from.stackOffsetY end
        if from.stackColorR then bar.stackColorR, bar.stackColorG, bar.stackColorB = from.stackColorR, from.stackColorG, from.stackColorB end
        if from.iconsPerRow then bar.iconsPerRow = from.iconsPerRow end
        if from.maxRows then bar.maxRows = from.maxRows end
        if from.maxTotal then bar.maxTotal = from.maxTotal end
        if from.padding then bar.padding = from.padding end
        if from.rowSpacing then bar.rowSpacing = from.rowSpacing end
        if from.iconZoom then bar.iconZoom = from.iconZoom end
        if from.showSwipe ~= nil then bar.showSwipe = from.showSwipe end
        if from.reverseSwipe ~= nil then bar.reverseSwipe = from.reverseSwipe end
        if from.fontOutline then bar.fontOutline = from.fontOutline end
        if from.sortMethod then bar.sortMethod = from.sortMethod end
        if from.sortDirection then bar.sortDirection = from.sortDirection end
        if from.borderSize then bar.borderSize = from.borderSize end
        if from.borderR then bar.borderR, bar.borderG, bar.borderB, bar.borderA = from.borderR, from.borderG, from.borderB, from.borderA end
    end
    local pos = s.extDefPos or (legacy and legacy.unlockPos)
    if pos and pos.point then
        bar.pos = { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
    end
    s.customBuffBars = s.customBuffBars or {}
    s.customBuffBars[#s.customBuffBars + 1] = bar
    -- Retire the built-in bar's storage for good.
    s.defaultExternalDefensives = nil
    s.extDefPos = nil
end

local buffsContainer, debuffsContainer
local buffsParent, debuffsParent
-- Per-container, per-polarity registry of every group key ever declared (see
-- ApplyGroupConfig): reset only when a container is (re-)created, never on a live
-- settings change.
local declared = { buffs = {}, debuffs = {} } -- buffs: only the "Show All Buffs" catch-all key ("all"); debuffs: every class-token chain key
local lastSize = { buffs = nil, debuffs = nil } -- {w=,h=} last-applied grid size, for fixed-edge compensation (see ApplyLiveConfig)
local buffsSlotSig -- signature of the default Buffs bar's last-applied resolved spell list (ns.PAB_ResolveSpells), mirrors customBuffSig[barId] for the per-bar slots model
local RegisterPABUnlock -- forward-declared; defined after CreateBars, called from it
local SyncCancelCVar -- forward-declared; defined after RestyleBars, called from CreateBars/RestyleBars/ReloadCustomBuffBarImpl
local vehicleHidden = false -- vehicle ride state (assigned in the recovery section at file bottom); feeds pabSuppressed below
local pabSuppressed = false -- vehicle ride OR degraded-filter window: SetParentShownSafe dims the parents instead of hiding them (see ApplyVehicleHidden)
local ClearDegraded -- forward-declared; defined in the recovery section at file bottom, called from PAB_SetEnabled
-- Last label the Buffs mover was registered under, so ApplyLiveConfig can
-- re-register on a name change without doing it on every slider drag.
local lastUnlockBuffLabel
local ReloadAllCustomBars -- forward-declared; defined after CreateBars (custom bars section), called from it
local PAB_MaybeRefreshPreview -- forward-declared; assigned in the options-page preview section, called from every live-apply function so an open bar-detail preview box tracks slider drags without those functions knowing it exists

-- Last-applied growDirection per live container (weak keys); written by
-- ApplyContainerAnchorAndGrowth, read by the restricted-apply gate below.
local containerDirections = setmetatable({}, { __mode = "k" })

local restrictedApplies = {}
local restrictionHooked = false
-- Defers ONLY the direction-change reconfigure (Hide/SetUnit/UpdateAllAuras +
-- resize) to the restriction lift. Ordinary container-level re-drives are
-- restriction-legal (they ran mid-combat for weeks pre-centered-growth), and
-- the cinematic/faction/vehicle recovery lane DEPENDS on them running inside
-- instanced combat -- a blanket defer would leave restored bars showing
-- degraded content until the combat edge.
local function DeferRestrictedApply(key, fn, container, dir)
    local applied = container and containerDirections[container]
    if not (applied and applied ~= (dir or "LEFT")) then return false end
    AK = AK or (EllesmereUI and EllesmereUI.AuraKit)
    if not (AK and AK.AurasRestricted and AK.AurasRestricted()) then return false end
    restrictedApplies[key] = fn
    if not restrictionHooked then
        restrictionHooked = true
        AK.OnRestrictionLift(function()
            if not next(restrictedApplies) then return end
            local pending = restrictedApplies
            restrictedApplies = {}
            for _, apply in pairs(pending) do apply() end
        end)
    end
    return true
end

-- One-shot OOC reconciler for parent-geometry passes skipped inside lockdown. Every
-- bar parent has the engine aura container ANCHORED to it, which makes the PARENT's
-- own SetSize/ClearAllPoints/SetPoint ADDON_ACTION_BLOCKED in combat (a protected
-- anchor-dependent poisons its anchor ancestor's geometry) -- while the cinematic/
-- faction/vehicle recovery lane legitimately re-drives config mid-combat. Keyed and
-- coalesced; the event is registered only while something is queued, so idle cost is
-- zero.
local pabRegenApplies = {}
local pabRegenFrame
local function QueuePABRegenApply(key, fn)
    pabRegenApplies[key] = fn
    if not pabRegenFrame then
        pabRegenFrame = CreateFrame("Frame")
        pabRegenFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local pending = pabRegenApplies
            pabRegenApplies = {}
            for _, apply in pairs(pending) do apply() end
        end)
    end
    pabRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Combat-safe Show/Hide for a bar PARENT. The engine aura container is a
-- CHILD of the parent, so the parent's own Show/Hide is ADDON_ACTION_BLOCKED
-- in lockdown exactly like its SetSize/SetPoint (field report: the
-- cinematic/faction recovery lane re-asserting the default bars mid-combat).
-- No call at all when the state already matches; in combat the visual verdict
-- lands through alpha (never protected) and the real Show/Hide is replayed at
-- regen via `recompute`, which re-derives the verdict at that time.
-- Suppression (pabSuppressed) rides on alpha OUT of combat too, never on the
-- shown state: it lifts on transitions that routinely land mid-combat, and a
-- real Hide taken while suppressed cannot be undone until the next regen edge.
-- Field report (Kings' Rest, Entomb): the tomb is a vehicle and being inside it
-- drops the player's combat, so the ride's hide replayed for real at that regen
-- and the exit's show was blocked -- the bars stayed gone for the whole boss
-- pulled afterwards.
local function SetParentShownSafe(key, parent, want, recompute)
    want = want and true or false
    local locked = InCombatLockdown()
    local shown = parent:IsShown()
    if issecretvalue and issecretvalue(shown) then shown = nil end
    local alpha = (pabSuppressed or (locked and not want)) and 0 or 1
    if parent:GetAlpha() ~= alpha then parent:SetAlpha(alpha) end
    if shown == want then return end
    if locked then
        QueuePABRegenApply("shown:" .. key, recompute)
        return
    end
    parent:SetShown(want)
end

-- Default-bar enable toggle (cfg.enabled, nil = enabled): the parent hides
-- exactly like a disabled custom bar's. Vehicle suppression still wins while
-- active -- SetParentShownSafe keeps it on alpha, so this pass carries the
-- enable verdict without un-suppressing anything (a bar built mid-ride used to
-- come up at full alpha here).
local function ApplyDefaultBarShown(isBuff)
    local s = PAB()
    if not s then return end
    local parent
    if isBuff then parent = buffsParent else parent = debuffsParent end
    if not parent then return end
    local cfg = isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)
    -- Master enable + Use Blizzard Buffs both stand the defaults down (the
    -- recovery lane can reach this while disabled-awaiting-reload).
    SetParentShownSafe(isBuff and "default-buffs" or "default-debuffs", parent,
        s.enabled == true and cfg.enabled ~= false and s.useBlizzardBuffs ~= true,
        function() ApplyDefaultBarShown(isBuff) end)
end

-- Grow direction. AK.ApplyContainerLayout only applies growth when BOTH growthH and
-- growthV are set. Values are AnchorUtil.FlowDirection members, NOT strings
-- (Blizzard_SharedXMLBase/AnchorUtil.lua: Left=-1, Right=1, Up=1, Down=-1); our
-- settings store uppercase direction strings, matching EUI_UnlockMode.lua's dropdown
-- `val` convention.
--
-- CRITICAL: AnchorUtil.ApplyFlowLayout positions every element via
-- `layout:GetAnchorPoint()` (layout.anchorPoint, a THIRD independent field defaulting
-- to "TOPLEFT"), NOT our outer spec.point. Elements are placed relative to that
-- internal anchor with offsets increasing in the growthH direction, so leaving
-- anchorPoint at default while growthH changes puts the first icon on the wrong side
-- and lets icons drift outside the mover box. Derive ONE corner from the direction and
-- use it for BOTH the outer frame anchor and the internal flow anchorPoint, so the
-- fixed corner and the flow's start corner are the same physical point:
--   growDirection RIGHT -> fixed/start corner TOPLEFT (icons extend right)
--   growDirection LEFT  -> fixed/start corner TOPRIGHT (icons extend left)
--
-- Vertical growth (Up/Down): the flow's PRIMARY axis becomes vertical (icons fill
-- up/down first) and growthH instead carries the CROSS axis -- which side additional
-- columns wrap to, from cfg.iconWrapDirection ("LEFT"/"RIGHT", default LEFT). Mirrors
-- EUI_RaidFrames_AuraContainers.lua's AnchorDebuffContainer (grow==UP/DOWN: gH = wrap,
-- gV = grow), except PAB has no separate wrap dropdown. Horizontal growth keeps
-- growthH as the primary axis and growthV hardcoded Down (rows wrap downward).
local function ToGrowthH(dirStr, wrapStr)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    if not FlowDir then return nil end
    if dirStr == "CENTER_VERTICAL" then return FlowDir.Right end
    if dirStr == "UP" or dirStr == "DOWN" then
        return wrapStr == "RIGHT" and FlowDir.Right or FlowDir.Left
    end
    return (dirStr == "RIGHT" or dirStr == "CENTER_HORIZONTAL") and FlowDir.Right or FlowDir.Left
end
-- Gated on the GROWTH direction, never on the wrap value itself (same shape as
-- ToGrowthH above). iconWrapDirection is one shared field whose Up/Down values are
-- only offered for LEFT/RIGHT growth, so a value left behind by a growth-direction
-- change must stay inert everywhere else: reading it unconditionally flipped
-- CENTER_VERTICAL's columns to grow Up out of its fixed "TOP" anchor, and stacked
-- CENTER_HORIZONTAL's rows upward, from a setting whose cog those modes never show.
local function ToGrowthV(dirStr, wrapStr)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    if not FlowDir then return nil end
    if dirStr == "UP" then return FlowDir.Up end
    if dirStr == "DOWN" then return FlowDir.Down end
    if dirStr == "LEFT" or dirStr == "RIGHT" then
        return wrapStr == "UP" and FlowDir.Up or FlowDir.Down
    end
    return FlowDir.Down -- centered growth: rows always wrap downward
end
-- Corner = the flow's fixed start point = (opposite of growthV side) + (opposite of
-- growthH side), same rule horizontal or vertical (LEFT/RIGHT: growthV is always Down
-- -> TOP component; growthH Right/Left -> LEFT/RIGHT component).
local function CornerFor(dirStr, wrapStr)
    if dirStr == "CENTER_VERTICAL" then return "TOP" end
    if dirStr == "UP" or dirStr == "DOWN" then
        local vSide = (dirStr == "UP") and "BOTTOM" or "TOP"
        local hSide = (wrapStr == "RIGHT") and "LEFT" or "RIGHT"
        return vSide .. hSide
    end
    if dirStr == "LEFT" or dirStr == "RIGHT" then
        local vSide = (wrapStr == "UP") and "BOTTOM" or "TOP"
        local hSide = (dirStr == "RIGHT") and "LEFT" or "RIGHT"
        return vSide .. hSide
    end
    return (dirStr == "CENTER_HORIZONTAL") and "TOPLEFT" or "TOPRIGHT"
end

-- Shared by every container, default and custom alike: builds the AK.RequestContainer
-- spec's point+layout from a bar cfg's growDirection and a precomputed grid
-- (ComputeGrid), so default and custom bars can never drift in how they read
-- growDirection/rowWidth. Also returns the corner (callers need it for the
-- container's own SetPoint against its parent) and `vertical` (AK.SetContainerAxis is
-- a separate call from AK.ApplyContainerLayout -- axis is not part of the layout table).
local function BuildContainerSpec(parent, cfg, grid)
    local dir = cfg.growDirection or "LEFT"
    local wrap = cfg.iconWrapDirection or "LEFT"
    local vertical = (dir == "UP" or dir == "DOWN" or dir == "CENTER_VERTICAL")
    local layoutAnchor = dir == "CENTER_HORIZONTAL" and "LEFT" or CornerFor(dir, wrap)
    local containerAnchor = (dir == "CENTER_HORIZONTAL" or dir == "CENTER_VERTICAL") and "CENTER" or layoutAnchor
    return containerAnchor, {
        point = { containerAnchor, parent, containerAnchor, 0, 0 },
        layout = {
            anchorPoint = layoutAnchor,
            padding = { 0, 0, 0, 0 },
            rowWidth = grid.rowWidth,
            growthH = ToGrowthH(dir, wrap),
            growthV = ToGrowthV(dir, wrap),
        },
    }, vertical
end

-- Re-applies container anchor/axis/growth/padding/rowWidth for an already-created
-- container against `parent`'s current grid. Shared by ApplyLiveConfig and the
-- existing-container branches of ReloadCustomBuffBarImpl/ReloadCustomDebuffBarImpl so
-- the three cannot drift. The outer frame anchor is a plain SetPoint (not AK-managed),
-- so it is live-settable like any other frame anchor.
local function ApplyContainerAnchorAndGrowth(container, parent, cfg, grid)
    local containerAnchor, spec, vertical = BuildContainerSpec(parent, cfg, grid)
    local direction = cfg.growDirection or "LEFT"
    local directionChanged = containerDirections[container] and containerDirections[container] ~= direction
    containerDirections[container] = direction
    if directionChanged then container:Hide() end

    local size = EllesmereUI.PP.Scale(cfg.iconSize or 32)
    container:ClearAllPoints()
    container:SetSize(size, size)
    container:SetPoint(containerAnchor, parent, containerAnchor, 0, 0)
    AK.SetContainerAnchor(container, spec.layout.anchorPoint)
    AK.SetContainerAxis(container, vertical)
    if spec.layout.growthH then
        AK.SetContainerGrowth(container, spec.layout.growthH, spec.layout.growthV)
    end
    AK.SetContainerPadding(container, 0, 0, 0, 0)
    AK.SetContainerRowWidth(container, grid.rowWidth)

    if directionChanged then
        container:SetUnit("player")
        container:UpdateAllAuras()
        container:Show()
    end
end

-- Default anchor when no saved position exists yet. Independent per bar (bars must be
-- individually movable): the two just get separate default offsets so they don't
-- overlap before either has been dragged.
local DEFAULT_POS = {
    buffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -200 },
    debuffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -260 },
}

local function BarPositionKey(isBuff)
    return isBuff and "buffsPos" or "debuffsPos"
end

-- Snaps a saved (x, y) to the physical pixel grid before SetPoint, matching
-- EllesmereUIUnitFrames.lua's ApplyFramePosition. An unsnapped coordinate is only
-- wrong at a non-pixel-perfect UIParent scale (1 coord unit == 1 physical pixel at
-- PP.PixelBestSize()). CENTER/CENTER anchors need SnapCenterForDim -- its odd-
-- dimension handling keeps both edges on whole pixels, while plain SnapForES would
-- round the center itself and push edges onto half pixels; every other anchor point
-- uses SnapForES.
local function SnapBarPos(frame, point, relPoint, x, y)
    if not (x and y) then return x, y end
    local PP = EllesmereUI.PP
    local es = frame:GetEffectiveScale()
    local isCenterAnchor = (point == "CENTER" or point == nil)
        and (relPoint == "CENTER" or relPoint == nil)
    if isCenterAnchor then
        return PP.SnapCenterForDim(x, frame:GetWidth() or 0, es),
            PP.SnapCenterForDim(y, frame:GetHeight() or 0, es)
    end
    return PP.SnapForES(x, es), PP.SnapForES(y, es)
end

-- Centered growth needs a position whose meaning does not change with the mover's
-- configured grid size. Rebase any edge-anchored saved position to CENTER/CENTER at
-- the frame's current visual center before resizing it.
local function RebaseBarPositionToCenter(frame, pos)
    if pos and pos.point == "CENTER" and (pos.relPoint or pos.point) == "CENTER" then return pos end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then return pos end
    local x, y = cx - ux, cy - uy
    local sx, sy = SnapBarPos(frame, "CENTER", "CENTER", x, y)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
    return { point = "CENTER", relPoint = "CENTER", x = x, y = y }
end

-- Applies the saved position (if any) or the default to the given parent frame.
-- Shared between initial creation and the unlock-mode applyPos callback so the two
-- never drift into different SetPoint logic.
local function ApplyBarPosition(parent, isBuff)
    local s = PAB()
    local posKey = BarPositionKey(isBuff)
    local pos = s and s[posKey]
    local def = isBuff and DEFAULT_POS.buffs or DEFAULT_POS.debuffs
    parent:ClearAllPoints()
    if pos and pos.point then
        local x, y = SnapBarPos(parent, pos.point, pos.relPoint or pos.point, pos.x, pos.y)
        parent:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, x, y)
    else
        local x, y = SnapBarPos(parent, def.point, def.relPoint, def.x, def.y)
        parent:SetPoint(def.point, UIParent, def.relPoint, x, y)
    end
    local cfg = s and (isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s))
    if cfg and (cfg.growDirection == "CENTER_HORIZONTAL" or cfg.growDirection == "CENTER_VERTICAL") then
        s[posKey] = RebaseBarPositionToCenter(parent, pos)
    end
end

-- Blizzard's player BuffFrame/DebuffFrame are superseded by this module: hide them so
-- auras aren't shown twice. House pattern for "Blizzard keeps re-showing this": Hide()
-- once, then hooksecurefunc(Show) to immediately re-hide whenever Blizzard's code calls
-- Show() again. hooksecurefunc runs AFTER Blizzard's secure call completes, not from
-- inside it, so nothing is tainted. Neither frame is protected/secure, so plain Hide()
-- is safe with no lockdown concern.
local blizzardAurasHidden = false
-- True while PAB owns the buff/debuff display (the natives must stay
-- hidden): master-enabled and not in Use Blizzard Buffs mode. The re-hide
-- hooks below read this LIVE, so Disable All and Use Blizzard Buffs can
-- hand the display back without a reload.
local function PabOwnsNativeAuras()
    local s = PAB()
    return (s and s.enabled == true and s.useBlizzardBuffs ~= true) and true or false
end

local function HideBlizzardPlayerAuras()
    if blizzardAurasHidden then return end
    blizzardAurasHidden = true
    if BuffFrame then
        BuffFrame:Hide()
        hooksecurefunc(BuffFrame, "Show", function()
            if PabOwnsNativeAuras() then BuffFrame:Hide() end
        end)
    end
    if DebuffFrame then
        DebuffFrame:Hide()
        hooksecurefunc(DebuffFrame, "Show", function()
            if PabOwnsNativeAuras() then DebuffFrame:Hide() end
        end)
    end
end

-- Hands the native display back mid-session (Disable All / Use Blizzard
-- Buffs ON): the hooks above release once PabOwnsNativeAuras() is false, so
-- an explicit Show restores Blizzard's frames without a reload. No-op if
-- the natives were never hidden this session.
local function ShowBlizzardPlayerAuras()
    if not blizzardAurasHidden then return end
    if PabOwnsNativeAuras() then return end
    if BuffFrame then BuffFrame:Show() end
    if DebuffFrame then DebuffFrame:Show() end
end

-- Re-asserts native visibility for the CURRENT profile/mode (profile swaps
-- cross enable/useBlizzard modes in both directions): hide when PAB owns
-- the display -- the first hide installs the hooks, later ones re-assert
-- past the latch -- show when it does not.
local function SyncNativeAuras()
    if PabOwnsNativeAuras() then
        if blizzardAurasHidden then
            if BuffFrame then BuffFrame:Hide() end
            if DebuffFrame then DebuffFrame:Hide() end
        else
            HideBlizzardPlayerAuras()
        end
    else
        ShowBlizzardPlayerAuras()
    end
end

-- Shifts the default Buffs container inward by the active weapon-enchant
-- count (see EUI_UnitFrames_WeaponEnchants.lua): the enchant buttons occupy
-- the bar's first cells and the engine run starts after them -- Blizzard's
-- temp-enchants-first ordering. Zero enchants (or a filtered-out record)
-- leaves the anchor byte-identical. Full rows overflow the reserved grid by
-- the shift while an oil is up -- accepted; the shift is transient.
local function ShiftBuffsForEnchants(container, parent, cfg, grid)
    local n = (cfg.showWeaponEnchants == true and ns.WeaponEnchants_Count and ns.WeaponEnchants_Count()) or 0
    local containerAnchor = BuildContainerSpec(parent, cfg, grid)
    local dir = cfg.growDirection or "LEFT"
    local cell = EllesmereUI.PP.Scale(cfg.iconSize or 32) + EllesmereUI.PP.Scale(cfg.padding or 5)
    container:ClearAllPoints()
    -- Centered modes: the enchant cells must hug the RUN's moving edge, which
    -- only the container's live rect knows. rec.parent must stay the PLAIN bar
    -- frame -- the container carries forbidden aspects
    -- (UntrustedLayoutScriptExecution), and the consumer's secure host frame
    -- hard-errors on SetParent into that subtree ("child object would inherit
    -- forbidden aspects"). rec.anchorTo carries the container for ANCHORING
    -- only (SetPoint relative-to does not reparent), which is the same trust
    -- shape as the buttons' existing anchors into insecurely-positioned frames.
    if dir == "CENTER_HORIZONTAL" then
        local span = n * cell
        container:SetPoint("CENTER", parent, "CENTER", span / 2, 0)
        if ns._weaponEnchPAB then
            ns._weaponEnchPAB.parent = parent
            ns._weaponEnchPAB.anchorTo = container
            ns._weaponEnchPAB.corner = nil
            ns._weaponEnchPAB.point = "LEFT"
            ns._weaponEnchPAB.relativePoint = "LEFT"
            ns._weaponEnchPAB.x = -span
            ns._weaponEnchPAB.y = 0
            ns._weaponEnchPAB.dir = "RIGHT"
        end
        return
    end
    if dir == "CENTER_VERTICAL" then
        local span = n * cell
        container:SetPoint("CENTER", parent, "CENTER", 0, -span / 2)
        if ns._weaponEnchPAB then
            ns._weaponEnchPAB.parent = parent
            ns._weaponEnchPAB.anchorTo = container
            ns._weaponEnchPAB.corner = nil
            ns._weaponEnchPAB.point = "BOTTOM"
            ns._weaponEnchPAB.relativePoint = "TOP"
            ns._weaponEnchPAB.x = 0
            ns._weaponEnchPAB.y = math.max(0, n - 1) * cell + EllesmereUI.PP.Scale(cfg.padding or 5)
            ns._weaponEnchPAB.dir = "DOWN"
        end
        return
    end

    local dx, dy = 0, 0
    if dir == "RIGHT" then dx = 1 elseif dir == "LEFT" then dx = -1
    elseif dir == "UP" then dy = 1 elseif dir == "DOWN" then dy = -1 end
    container:SetPoint(containerAnchor, parent, containerAnchor, dx * n * cell, dy * n * cell)
    if ns._weaponEnchPAB then
        ns._weaponEnchPAB.parent = parent
        ns._weaponEnchPAB.anchorTo = nil
        ns._weaponEnchPAB.corner = containerAnchor
        ns._weaponEnchPAB.point = nil
        ns._weaponEnchPAB.relativePoint = nil
        ns._weaponEnchPAB.x = nil
        ns._weaponEnchPAB.y = nil
        ns._weaponEnchPAB.dir = dir
    end
end

-- Combat-path re-shift for enchant count changes: re-seating the CONTAINER
-- is combat-legal (plain SetPoint, same class as the merged-debuff ride),
-- but the full ApplyLiveConfig is not -- the secure enchant trio anchors
-- into the bar frame's family, which blocks the bar's own SetSize in
-- lockdown. Recomputes the live grid and re-seats ONLY the container,
-- INCLUDING the shift-to-zero reset when the last oil expires.
function ns.PAB_ReShiftEnchants()
    local s = PAB()
    if not (AK and s and buffsContainer and buffsParent) then return end
    local cfg = DefaultBuffsCfg(s)
    local grid = ComputeGrid(true, cfg)
    ShiftBuffsForEnchants(buffsContainer, buffsParent, cfg, grid)
end

local function CreateBars()
    AK = AK or (EllesmereUI and EllesmereUI.AuraKit)
    if not AK then return end -- 12.1 gated at file top; defensive only

    local s = PAB()
    if not s then return end -- ns.db not ready yet; TryCreateBars() below retries

    -- Master enable, default OFF: nothing below runs while disabled -- Blizzard's
    -- BuffFrame/DebuffFrame stay untouched, no containers, no unlock elements, options
    -- page shows an activation overlay. One-shot seed: the retired Styled Player Auras
    -- module's enable toggle carries over, so its users come up enabled.
    if not s.pabEnableSeeded then
        s.pabEnableSeeded = true
        if s.enabled == nil then
            local old = ns.db and ns.db.profile and ns.db.profile.playerAuras
            if old and old.enabled == true then s.enabled = true end
        end
    end
    if s.enabled ~= true then return end

    -- Enablement is confirmed from here down: arm the cinematic/faction/
    -- vehicle recovery lane (defined at file bottom; the whole file has
    -- loaded by the time anything calls CreateBars). Idempotent.
    ns.PAB_ArmRecovery()

    -- Must run before DefaultBuffsCfg/DefaultDebuffsCfg are first called, so seeded
    -- values are what their first lazy-create populates. One-time-ever seed, not a
    -- re-appliable migration (see SeedDefaultBuffsDebuffsFromLegacySources).
    SeedDefaultBuffsDebuffsFromLegacySources(s)
    EnsureDebuffFilterV2(s)
    EnsureFilterLanes(s)
    EnsureBarEnable(s)

    -- Must run before buffCfg/custom-bar spell resolution below: the curated presets
    -- are otherwise only imported when the options page opens, so a bar referencing a
    -- not-yet-imported preset filter would resolve an incomplete spell set at login,
    -- cache it as its signature, and never re-resolve until something else forces a
    -- signature change.
    if ns.PAB_ImportBM2Filters then ns.PAB_ImportBM2Filters() end

    -- After the import: the External Defensives seed references the imported
    -- "Externals" preset filter by id.
    EnsureExtDefCustomBar(s)

    -- Use Blizzard Buffs: PAB stands down for the DEFAULT bars only --
    -- Blizzard's native BuffFrame/DebuffFrame stay untouched and the default
    -- bars never build; custom bars (editing-spec buckets included) still
    -- run in full. Default-bar unlock elements drop via their isHidden.
    if s.useBlizzardBuffs == true then
        RegisterPABUnlock()
        ReloadAllCustomBars()
        SyncCancelCVar()
        return
    end

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

    -- Enable toggles (cfg.enabled, nil = enabled): containers and groups still
    -- build below so a live re-enable needs no reload; a disabled bar just
    -- hides its parent (custom-bar pattern).
    ApplyDefaultBarShown(true)
    ApplyDefaultBarShown(false)

    local debuffChain = BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, debuffCfg) or (PAB_FxSafeToForce(class) and PAB_FxWantsCategory(debuffCfg.fxList, class.key)) end, DebuffCatchAllOn(debuffCfg), DebuffSubtractFn(debuffCfg))

    -- Single scalar padding, feeding ONLY ApplyGroupConfig's per-group
    -- elementSpacing/lineSpacing/groupSpacing/groupLineSpacing (gap BETWEEN icons).
    -- Must NOT also feed the container's outer edge inset (spec.layout.padding /
    -- AK.SetContainerPadding) -- a DIFFERENT concept (container frame edge to first
    -- icon); tying them pushes the whole grid away from its fixed corner as padding
    -- grows. Outer inset is fixed at 0.
    local buffPad = buffCfg.padding or 5
    local debuffPad = debuffCfg.padding or 5

    local buffCorner, buffSpec = BuildContainerSpec(buffsParent, buffCfg, buffGrid)
    local _, debuffSpec = BuildContainerSpec(debuffsParent, debuffCfg, debuffGrid)

    -- Weapon enchant lead icons (oils/imbues are not auras; see
    -- EUI_UnitFrames_WeaponEnchants.lua): opt-in (showWeaponEnchants, default
    -- off -- the cell shift offsets the aura grid), exposed as the "Weapon
    -- Enchants" pinned row in the bar's Filters dropdown. A content source of
    -- its own, NOT gated on the broad-content modes: enchants are not auras
    -- and never come from the catch-all group, so checking the row alone
    -- shows just the enchant cells. They render with the bar's live style, so
    -- every customization follows automatically.
    if buffCfg.showWeaponEnchants == true and buffCfg.enabled ~= false then
        ns._weaponEnchPAB = { parent = buffsParent, corner = buffCorner,
            dir = buffCfg.growDirection or "LEFT",
            -- Snapped like the shift's own cell stride above: the buttons add
            -- this to an already-snapped style.width, so a raw gap would place
            -- them off the engine's grid at a non-native UI scale.
            pad = EllesmereUI.PP.Scale(buffPad), styleKey = STYLE_BUFFS, canCancel = true }
    else
        ns._weaponEnchPAB = nil
    end
    if buffCfg.growDirection ~= "CENTER_HORIZONTAL" and buffCfg.growDirection ~= "CENTER_VERTICAL" and ns.WeaponEnchants_Layout then
        ns.WeaponEnchants_Layout()
    end

    -- Groups are declared additively right after creation (not via spec.groups) so
    -- the same ApplyGroupConfig path handles both initial creation and every later
    -- live settings change.
    --
    -- Buffs: the Filters/Extra-Spells selection and the "Show All Buffs" catch-all
    -- coexist additively on the same container -- both are independent GROUPS,
    -- nothing in AK's model makes them mutually exclusive. The catch-all uses the same
    -- zero-classes-enabled chain as Debuffs' "all" group (just { base }); buffs have no
    -- per-class filtering UI, so it's all-or-nothing, gated only by showAllBuffs.
    -- Defaults ON, else an unconfigured bar shows nothing; ON matches Blizzard's
    -- player BuffFrame (HELPFUL, no category restriction).
    --
    -- The spell selection must be ONE GROUP whose candidateFilters.includeSpellIDs is
    -- the resolved spell-ID set (map shape {[id]=true}, every includeSpellIDs consumer
    -- in the codebase uses a map, never an array). NOT one AK.AddAuraSlot per spellID:
    -- AK's flow layout only positions GROUP content, never slot content -- slots must
    -- self-anchor via extraInit (both other AddAuraSlot consumers,
    -- EUI_RaidFrames_AuraContainers.lua and EUI_ResourceBars_EbonMight121.lua, manually
    -- SetPoint their button). With slots, buttons report shown=true at the right size
    -- but GetPoint(1) returns nil and nothing renders. PAB needs a flowing multi-icon
    -- grid of a DYNAMIC spell set, which slots can't do without reimplementing flow
    -- placement by hand. A group's candidateFilters is fixed at declaration, so a
    -- spell-list change still requires releasing and recreating the container -- hence
    -- the sig-diffing.
    local buffAllChain = BuffBarChain(buffCfg)
    local buffSpells = ns.PAB_ResolveSpells(buffCfg)
    buffsSlotSig = table.concat(buffSpells, ",")
    AK.RequestContainer(buffsParent, "player", buffSpec, function(container)
        buffsContainer = container
        ApplyContainerAnchorAndGrowth(container, buffsParent, buffCfg, buffGrid)
        ShiftBuffsForEnchants(container, buffsParent, buffCfg, buffGrid)
        if ns.WeaponEnchants_Layout then ns.WeaponEnchants_Layout() end
        declared.buffs = {}
        ApplyGroupConfig(container, buffAllChain, declared.buffs, STYLE_BUFFS, buffGrid.effectiveMax, buffPad, buffGrid.rowGap, buffCfg, BuffCandidateExtras(buffCfg))
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
                layout = BuildGroupLayout(buffCfg, buffPad, buffGrid.rowGap),
            })
            declared.buffs.spells = true
        end
    end)
    AK.RequestContainer(debuffsParent, "player", debuffSpec, function(container)
        debuffsContainer = container
        ApplyContainerAnchorAndGrowth(container, debuffsParent, debuffCfg, debuffGrid)
        declared.debuffs = {}
        ApplyGroupConfig(container, debuffChain, declared.debuffs, STYLE_DEBUFFS, debuffGrid.effectiveMax, debuffPad, debuffGrid.rowGap, debuffCfg, DebuffCandidateExtras(debuffCfg))
    end)
    RegisterPABUnlock()
    ReloadAllCustomBars()
    SyncCancelCVar()
end

-- Unlock-mode registration, patterned on EllesmereUIDamageMeters.lua's
-- ns.RegisterDMUnlock/MakeSATimerUnlockElement (observed EUI.MakeUnlockElement field
-- usage, not a verified schema). Both bars use noResize (AuraKit sizes the container
-- from the active aura count, nothing to drag-resize) and noAnchorTarget (a
-- dynamically-resizing frame is a bad anchor target for other elements).
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
            -- Enable toggle: a disabled default bar keeps no mover (custom-bar
            -- parity). Master-disabled and Use Blizzard Buffs stand the
            -- defaults down entirely, mover included.
            isHidden = function()
                local s = PAB()
                if not s or s.enabled ~= true or s.useBlizzardBuffs == true then return true end
                local cfg = isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)
                return cfg.enabled == false
            end,
            getFrame = function() return getParent() end,
            -- Deliberately NOT container:GetWidth()/GetHeight(): AuraContainer geometry
            -- is a Secret Value while tainted (throws in EUI_UnlockMode.lua comparing a
            -- secret baseW). noResize is set anyway, so only a public number for the
            -- mover's label is needed.
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

    -- Buffs mover carries the bar's content-derived name (see
    -- ns.PAB_DefaultBuffsName), so an enchants-only bar reads "Weapon Enchants"
    -- in unlock mode instead of "Buffs". Baked in at registration --
    -- EUI_UnlockMode.lua's GetBarLabel returns the stored string -- which is why
    -- ApplyLiveConfig re-registers when the name changes.
    local s = PAB()
    local buffLabel = ns.PAB_DefaultBuffsName(s and DefaultBuffsCfg(s) or nil)
    lastUnlockBuffLabel = buffLabel

    local elements = {
        MakeBarElement("PAB_Buffs", buffLabel, 700, true, function() return buffsParent end),
        MakeBarElement("PAB_Debuffs", "Debuffs", 701, false, function() return debuffsParent end),
    }
    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIUnitFrames")
    -- Registration alone only updates the element table; a mover already built
    -- this session keeps the label CreateMover baked into its FontString. No-op
    -- before the first unlock session, so it is safe on the CreateBars path too.
    if EllesmereUI.RefreshUnlockElementLabel then
        EllesmereUI.RefreshUnlockElementLabel("PAB_Buffs")
    end
end
-- Exported for the default-bar enable toggles: re-registering re-runs unlock
-- mode's Sync, which re-reads isHidden and drops a disabled bar's mover
-- mid-session instead of waiting for the next natural Sync.
ns.PAB_RegisterUnlock = function() RegisterPABUnlock() end

-- Public hook for the Options UI: rebuild both style tables and re-decorate every
-- existing button. Purely a re-skin -- does NOT touch groups, filters, container
-- layout, or parent frame size. Call for style-only fields (colors, fonts, border,
-- dispel colors, cooldown/stack text, icon zoom). iconSize also needs ApplyLiveConfig
-- for both polarities, since it affects grid geometry.
local function RestyleBars()
    local s = PAB()
    if not (AK and s) then return end
    AK.styles[STYLE_BUFFS] = BuildStyle(true, DefaultBuffsCfg(s))
    AK.styles[STYLE_DEBUFFS] = BuildStyle(false, DefaultDebuffsCfg(s))
    AK.RestyleSoon(STYLE_BUFFS)
    AK.RestyleSoon(STYLE_DEBUFFS)
    SyncCancelCVar()
end
ns.PAB_Restyle = RestyleBars

-- CursorFreelookStartDelta is the fraction of the screen the cursor must move before a
-- held mouse button counts as camera freelook instead of a click; Blizzard's own
-- shipped default is 0.001 (verified against the client's cvar list, not assumed). At
-- 0 -- the most aggressive setting, zero movement required -- ANY right-click on an
-- aura icon is claimed for freelook before the release reaches our button, silently
-- eating the "Right-Click to Cancel" click (field-reported 2026-08-12, twice
-- independently). Players land on 0 via third-party "camera feel" addons/macros (a
-- dedicated community addon, CursorDeltaFix, does exactly this:
-- SetCVar("CursorFreelookStartDelta", 0)) or a manual /console tweak, not from
-- anything EllesmereUI does.
--
-- Repair only, never a nudge above Blizzard's default: we only ever touch this CVar
-- when it is caught sitting at the pathological 0, restoring it to Blizzard's own
-- 0.001 -- never raised past that, and never touched at all if it's anywhere else
-- (including a deliberately-tuned non-zero, non-default value). Conditional on some
-- right-click-cancelable buff surface actually being live, so a player who never uses
-- the feature never has this CVar touched by EllesmereUI at all.
local CANCEL_CVAR = "CursorFreelookStartDelta"
local CANCEL_CVAR_BROKEN = 0
local CANCEL_CVAR_DEFAULT = "0.001"

--- True while some right-click-cancelable player buff display is live: the default
--- Buffs bar (rightClickCancel defaults ON), any enabled custom buff bar with its own
--- toggle ON, or the classic Unit Frames player-buffs display (EUI_UnitFrames_
--- AuraContainers.lua's cancelButtons is unconditional whenever unit=="player" and
--- isBuff, gated only on the element being shown at all).
local function AnyRightClickCancelActive(s)
    -- Use Blizzard Buffs: the NATIVE BuffFrame owns the display and its
    -- right-click cancel breaks on the same CVar -- always repair.
    if s.useBlizzardBuffs == true then return true end
    local dbc = DefaultBuffsCfg(s)
    if dbc.enabled ~= false and dbc.rightClickCancel ~= false then return true end
    local customBuffBars = s.customBuffBars
    if customBuffBars then
        for i = 1, #customBuffBars do
            local bar = customBuffBars[i]
            if bar.enabled ~= false and bar.rightClickCancel ~= false then return true end
        end
    end
    -- Editing-spec bucket buff bars count too (enable-toggle test only,
    -- matching the legacy loop: the CVar repair may run while the spec is
    -- mid-change, so err on the permissive side).
    if s.pabSpecBars then
        for _, b in pairs(s.pabSpecBars) do
            local bl = b.buffBars
            if bl then
                for i = 1, #bl do
                    local bar = bl[i]
                    if bar.enabled ~= false and bar.rightClickCancel ~= false then return true end
                end
            end
        end
    end
    local db = ns.db
    local playerCfg = db and db.profile and db.profile.player
    if playerCfg and playerCfg.showBuffs ~= false then return true end
    return false
end

function SyncCancelCVar()
    local s = PAB()
    if not s or s.enabled ~= true then return end
    if not AnyRightClickCancelActive(s) then return end
    if InCombatLockdown() then return end
    if tonumber(GetCVar(CANCEL_CVAR)) == CANCEL_CVAR_BROKEN then
        SetCVar(CANCEL_CVAR, CANCEL_CVAR_DEFAULT)
    end
end

-- Public hook for the Options UI: live counterpart to RestyleBars for everything
-- spec-level (class toggles, grid: iconsPerRow/maxRows/padding/maxBuffs-or-Debuffs,
-- grow direction). Applies to ONE polarity's container; callers touching a shared
-- field (iconSize) call it for both. No-op before the container exists
-- (TryCreateBars calls CreateBars() once ns.db is ready).
local function ApplyLiveConfig(isBuff)
    local s = PAB()
    if not (AK and s) then return end
    if DeferRestrictedApply(isBuff and "default-buffs" or "default-debuffs",
        function() ApplyLiveConfig(isBuff) end,
        isBuff and buffsContainer or debuffsContainer,
        (isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)).growDirection) then return end
    local container = isBuff and buffsContainer or debuffsContainer
    local parent = isBuff and buffsParent or debuffsParent
    if not container or not parent then return end

    local cfg = isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)
    -- Enable toggle: a disabled bar hides its parent and skips every live
    -- apply below (geometry, enchant publish, group work) -- re-enabling runs
    -- the full pass. Same shape as the custom bars' early return. Use
    -- Blizzard Buffs and the MASTER disable stand the default bars down the
    -- same way (weapon-enchant events still reach this while disabled --
    -- their registration outlives the module).
    ApplyDefaultBarShown(isBuff)
    if s.enabled ~= true or cfg.enabled == false or s.useBlizzardBuffs == true then
        if isBuff then
            ns._weaponEnchPAB = nil
            if ns.WeaponEnchants_Layout then ns.WeaponEnchants_Layout() end
        end
        return
    end
    local grid = ComputeGrid(isBuff, cfg)
    local sizeKey = isBuff and "buffs" or "debuffs"
    local prev = lastSize[sizeKey]

    -- Edge-growing containers use a fixed parent corner, so move a CENTER-saved parent
    -- by half the size delta to keep that corner fixed. Centered growth deliberately
    -- skips this: the parent center is its fixed anchor. Uses lastSize rather than live
    -- geometry so rapid slider updates cannot read a stale prior size.
    local posKey = BarPositionKey(isBuff)
    local pos = s[posKey]
    local centered = cfg.growDirection == "CENTER_HORIZONTAL" or cfg.growDirection == "CENTER_VERTICAL"
    -- The engine aura container anchored to `parent` makes the PARENT's own geometry
    -- protected in combat (anchor-ancestor rule): the SetSize/ClearAllPoints/SetPoint
    -- below are ADDON_ACTION_BLOCKED inside lockdown -- and the cinematic/faction/
    -- vehicle recovery lane runs this function in instanced combat BY DESIGN (see
    -- DeferRestrictedApply). A recovery re-drive carries an UNCHANGED grid, so
    -- skipping the geometry cluster drops nothing there; a genuinely changed grid
    -- (options edited mid-combat) or a still-pending centered rebase reconciles once
    -- at the regen edge. lastSize stays untouched on the skip so the deferred pass
    -- still sees the real last-applied size (the fixed-corner compensation needs it),
    -- and the stored pos is not mutated for a resize that never landed.
    if InCombatLockdown() then
        local sizeChanged = not (prev and prev.w == grid.width and prev.h == grid.height)
        local rebasePending = centered
            and not (pos and pos.point == "CENTER" and (pos.relPoint or pos.point) == "CENTER")
        if sizeChanged or rebasePending then
            QueuePABRegenApply(sizeKey, function() ApplyLiveConfig(isBuff) end)
        end
    else
        if centered then
            pos = RebaseBarPositionToCenter(parent, pos)
            s[posKey] = pos
        end
        if not centered and pos and pos.point == "CENTER"
            and prev and (prev.w ~= grid.width or prev.h ~= grid.height) then
            pos.x = pos.x + (prev.w - grid.width) / 2
            pos.y = pos.y + (prev.h - grid.height) / 2
            -- Snap against the NEW grid.width/height (what parent:SetSize is about to
            -- apply), not parent:GetWidth/GetHeight -- those still read the OLD size, the
            -- resize hasn't run yet. The STORED pos keeps the raw accumulation; only the
            -- SetPoint values are snapped.
            local PP = EllesmereUI.PP
            local es = parent:GetEffectiveScale()
            local sx = PP.SnapCenterForDim(pos.x, grid.width, es)
            local sy = PP.SnapCenterForDim(pos.y, grid.height, es)
            parent:ClearAllPoints()
            parent:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
        end
        lastSize[sizeKey] = { w = grid.width, h = grid.height }
        parent:SetSize(grid.width, grid.height)
    end

    local pad = cfg.padding or 5
    ApplyContainerAnchorAndGrowth(container, parent, cfg, grid)

    if isBuff then
        -- Keep the weapon-enchant cells riding the bar's live geometry and
        -- filter state (opt-in only -- an independent content source, see the
        -- publish in CreateBars), then shift the engine run inward past them.
        if cfg.showWeaponEnchants == true then
            local liveCorner = BuildContainerSpec(parent, cfg, grid)
            ns._weaponEnchPAB = { parent = parent, corner = liveCorner,
                dir = cfg.growDirection or "LEFT",
                -- Snapped, as in CreateBars' publish above.
                pad = EllesmereUI.PP.Scale(pad), styleKey = STYLE_BUFFS, canCancel = true }
        else
            ns._weaponEnchPAB = nil
        end
        ShiftBuffsForEnchants(container, parent, cfg, grid)
        if ns.WeaponEnchants_Layout then ns.WeaponEnchants_Layout() end

        -- Unlock mode bakes the mover's label at registration, so a Filters
        -- change would leave the old name on it until the next CreateBars.
        -- Re-register only when the name actually changed -- this function runs
        -- on every slider drag.
        local label = ns.PAB_DefaultBuffsName(cfg)
        if label ~= lastUnlockBuffLabel and RegisterPABUnlock then
            RegisterPABUnlock()
        end
    end

    if isBuff then
        local spells = ns.PAB_ResolveSpells(cfg)
        local sig = table.concat(spells, ",")
        local allChain = BuffBarChain(cfg)
        if sig ~= buffsSlotSig then
            -- Safe to fully release+rebuild: the default Buffs container holds only the
            -- catch-all group + the spells group, nothing else shares it. The new
            -- container's anchor/growth/rowWidth come from `spec` below -- the live
            -- SetContainerAnchor/etc calls above ran against the OLD container and are
            -- harmless overhead. A group's candidateFilters is fixed at declaration, so a
            -- spell-list change requires this release+rebuild.
            RetireContainer(container, declared.buffs)
            local _, spec = BuildContainerSpec(parent, cfg, grid)
            AK.RequestContainer(parent, "player", spec, function(newContainer)
                buffsContainer = newContainer
                ApplyContainerAnchorAndGrowth(newContainer, parent, cfg, grid)
                ShiftBuffsForEnchants(newContainer, parent, cfg, grid)
                if ns.WeaponEnchants_Layout then ns.WeaponEnchants_Layout() end
                declared.buffs = {}
                ApplyGroupConfig(newContainer, allChain, declared.buffs, STYLE_BUFFS, grid.effectiveMax, pad, grid.rowGap, cfg, BuffCandidateExtras(cfg))
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
                        layout = BuildGroupLayout(cfg, pad, grid.rowGap),
                    })
                    declared.buffs.spells = true
                end
            end)
            buffsSlotSig = sig
        else
            -- Spell list unchanged: only Show All Buffs and/or grid (icon size,
            -- padding, ...) may have changed. ApplyGroupConfig is idempotent and self-
            -- zeroes the catch-all when `allChain` is empty, so one call covers on and
            -- off. The spells group isn't part of that chain path, so its
            -- maxFrameCount/layout/sort are refreshed here directly.
            ApplyGroupConfig(container, allChain, declared.buffs, STYLE_BUFFS, grid.effectiveMax, pad, grid.rowGap, cfg, BuffCandidateExtras(cfg))
            if declared.buffs.spells then
                container:SetAuraGroupMaxFrameCount("spells", grid.effectiveMax)
                container:SetAuraGroupLayout("spells", BuildGroupLayout(cfg, pad, grid.rowGap))
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
        local chain = BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, cfg) or (PAB_FxSafeToForce(class) and PAB_FxWantsCategory(cfg.fxList, class.key)) end, DebuffCatchAllOn(cfg), DebuffSubtractFn(cfg))
        ApplyGroupConfig(container, chain, declared.debuffs, STYLE_DEBUFFS, grid.effectiveMax, pad, grid.rowGap, cfg, DebuffCandidateExtras(cfg))
    end

    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview(isBuff and "buff" or "debuff", "default") end
end
ns.PAB_ApplyLiveConfig = ApplyLiveConfig
-- Bridge for EllesmereUF:GetGrowDirectionForBar/SetGrowDirectionForBar, kept here
-- rather than in EllesmereUIUnitFrames.lua so the settings-field names stay defined
-- in one place.
--
-- Also handles custom-bar keys ("PAB_CustomBuff_<id>"/"PAB_CustomDebuff_<id>", the
-- unlock-mode keys RegisterPABCustomUnlock registers below): EUI_UnlockMode.lua's Grow
-- dropdown dispatches here for ANY barKey prefixed "PAB_", so without these branches it
-- silently no-ops on custom bars. Calls ns.PAB_ReloadCustomBuffBar/DebuffBar rather than
-- BuildContainerSpec/SetContainerGrowth directly, since the spell/class signature is
-- unchanged and those already re-apply corner + growth cheaply.
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
        RestyleBars()
        ApplyLiveConfig(true)
        return
    elseif barKey == "PAB_Debuffs" then
        DefaultDebuffsCfg(s).growDirection = dir
        RestyleBars()
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
--  Buffs: SpellID-based -- customBuffBars entries carry filters={[filterId]=true},
--  spells={id,...}, ownOnlySpells={[id]=bool}. Same shape and same
--  PAB_ResolveSpells() union the default Buffs bar uses: default Buffs and custom
--  Buff Bars are ONE model, not two. Rendering is one candidateFilters-restricted
--  GROUP into the bar's own dedicated container with a signature-gated rebuild (see
--  PAB_ReloadCustomBuffBar for why a group, not per-spell slots). This section is
--  the CRUD data layer; engine wiring is further down.
--
--  Debuffs: category-based (same as RaidFrames) -- customDebuffBars entries carry
--  classFilters={[classKey]=true} and render through the EXISTING
--  BuildChain/ApplyGroupConfig path, no new engine machinery.
--
--  ID scheme mirrors ns.BM2_AddFilter: a single monotonically increasing counter,
--  never reused, so a deleted bar's engine-side declarations (ADD-ONLY on the
--  container) never collide with a later bar.
-------------------------------------------------------------------------------

-- Ensures db.profile.playerAuraBars exists before writing: PAB() alone is read-only
-- and may return nil, and `PAB() or {}` silently writes into a throwaway table that
-- never persists. Only CRUD (write) functions call this.
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
--  RaidFrames' ns.BM2_Filters storage ({ nextId = 1, list = {} }), id/name/nextId
--  counter pattern mirrored 1:1. User-created filters are fully renameable/deletable;
--  the 10 curated presets imported via ns.PAB_ImportBM2Filters carry `f.preset = true`
--  and are NOT renameable or deletable (Filter Editor sidebar/detail-header guards).
--  Spell-level checkboxes stay editable in a preset -- only its name/existence is
--  protected.
--
--  Referenced by id from any buff-side cfg's `filters` table ([filterId]=true): the
--  default Buffs bar and every custom buff bar share ONE filter registry. Own-only
--  tracking (BM2's ownFilters/ownExtras) is NOT implemented here; bar.ownOnlySpells
--  stays reserved-but-unused.
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

-- Also strips the filter's assignment from every buff-side cfg that could reference
-- it: default Buffs bar + every custom buff bar (both lanes), plus the player UNIT
-- FRAME's buff filter lanes -- it shares this registry through its own keys
-- (buffFilters/buffNegFilters, see PlayerBuffChain in EUI_UnitFrames_AuraContainers.lua).
function ns.PAB_DeleteFilter(id)
    local s = PAB()
    if not (s and s.pabFilters) then return end
    local list = s.pabFilters.list
    for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i) end
    end
    local function Strip(bar, isDefault)
        if bar.filters then bar.filters[id] = nil end
        if bar.negFilters then bar.negFilters[id] = nil end
        -- No-empty rule: deleting an ENABLED bar's last content source falls
        -- back to All Buffs, same as unchecking it in the Filters dropdown
        -- would. Disabled bars keep their stored state untouched (the
        -- EnsureBarEnable invariant).
        if bar.enabled ~= false and not BuffBarHasContent(bar, isDefault) then
            bar.showAllBuffs = nil
        end
    end
    if s.defaultBuffs then Strip(s.defaultBuffs, true) end
    local customBuffBars = s.customBuffBars
    if customBuffBars then
        for i = 1, #customBuffBars do
            Strip(customBuffBars[i], false)
        end
    end
    -- Editing-spec bucket bars share the same filter registry.
    if s.pabSpecBars then
        for _, b in pairs(s.pabSpecBars) do
            local bl = b.buffBars
            if bl then
                for i = 1, #bl do Strip(bl[i], false) end
            end
        end
    end
    local ps = ns.db and ns.db.profile and ns.db.profile.player
    if ps then
        if ps.buffFilters then ps.buffFilters[id] = nil end
        if ps.buffNegFilters then ps.buffNegFilters[id] = nil end
        -- Same fallback for the player frame's buff filter (shared registry).
        if ps.buffShowAll == false and ps.buffHasDuration ~= true
            and not (ps.buffFilters and next(ps.buffFilters))
            and not (ps.buffSpells and #ps.buffSpells > 0) then
            ps.buffShowAll = nil
        end
        -- The player FRAME's buff container resolves this registry through the
        -- UF reload pass, not through the PAB apply the caller runs.
        if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    end
end

-- Checkbox state for one spell within one filter. state=nil removes the spell
-- entirely: every PAB filter spell is "custom", no curated/preset spell to fall back to.
-- The write applies to the whole SAME-NAME FAMILY within the filter: PAB flattens
-- curated alternates into their own keys, and the Filter Editor shows one row per
-- NAME (lowest id), so a click on the visible row must carry the hidden alternates
-- with it -- otherwise a disabled-seeded family like Divine Hymn (64843 + alt
-- 64844) checks only the primary while the buff that actually lands is the alt
-- (field report 2026-08-16: "64844 not tracked"). Name-matching mirrors the
-- editor's dedup exactly (both fall back to the id when the name is uncached).
function ns.PAB_SetSpellState(filterId, spellID, state)
    local f = ns.PAB_GetFilter(filterId)
    if not f then return end
    local function Write(id)
        if state == nil then
            f.spells[id] = nil
        else
            f.spells[id] = state and true or false
        end
    end
    Write(spellID)
    -- Members of a curated family follow the clicked row, deletes included: the editor
    -- shows one row per NAME, so a member under a different name has a row of its own
    -- but is still the same buff, and would otherwise linger as a tracked id with no
    -- row left to clear it from. Only ids the filter already holds are rewritten.
    local fam = ns.PAB_SPELL_FAMILY and ns.PAB_SPELL_FAMILY[spellID]
    if fam then
        for i = 1, #fam do
            if fam[i] ~= spellID and f.spells[fam[i]] ~= nil then Write(fam[i]) end
        end
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if name then
        for id in pairs(f.spells) do
            if id ~= spellID and C_Spell.GetSpellName(id) == name then Write(id) end
        end
    end
end

function ns.PAB_AddSpellToFilter(filterId, spellID)
    local f = ns.PAB_GetFilter(filterId)
    if not (f and spellID and spellID > 0) then return false end
    if f.spells[spellID] ~= nil then return false end -- already present
    f.spells[spellID] = true
    return true
end

-- Union of a buff-side cfg's direct spells (cfg.spells) and the enabled spells of
-- every filter it references (cfg.filters), minus own-only tracking (see above).
-- Sorted so the caller's signature diffing stays deterministic.
function ns.PAB_ResolveSpells(cfg)
    local set = {}
    local direct
    local spells = cfg.spells
    if spells then
        direct = {}
        for i = 1, #spells do
            set[spells[i]] = true
            direct[spells[i]] = true
            ExpandFamily(direct, spells[i])
            ExpandFamily(set, spells[i])
        end
    end
    -- Under the broad modes (All Buffs / Has Duration) the hide-lane filters leave via
    -- the catch-all's excludeSpellIDs (see BuffBarChain), so the spells group carries
    -- only Extra Spells there. In add mode the show-lane filters union in, minus the
    -- hide lane. Extra Spells stay additive in both modes and win over the hide lane.
    local addMode = cfg.showAllBuffs == false and cfg.hasDuration ~= true
    local filters = addMode and cfg.filters or nil
    if filters then
        for filterId in pairs(filters) do
            local f = ns.PAB_GetFilter(filterId)
            if f then
                for id, on in pairs(f.spells) do
                    if on then
                        set[id] = true
                        ExpandFamily(set, id, f.spells)
                    end
                end
            end
        end
    end
    local negFilters = addMode and cfg.negFilters or nil
    if negFilters then
        local hide = {}
        for filterId in pairs(negFilters) do
            local f = ns.PAB_GetFilter(filterId)
            if f then
                for id, on in pairs(f.spells) do
                    if on then
                        hide[id] = true
                        ExpandFamily(hide, id, f.spells)
                    end
                end
            end
        end
        for id in pairs(hide) do
            if not (direct and direct[id]) then set[id] = nil end
        end
    end
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

-------------------------------------------------------------------------------
--  One-time filter copies between this registry and the Raid Frames Buff
--  Manager library (via the parent-published EllesmereUI._BM2FilterBridge --
--  absent when that module is disabled, and both editor buttons hide). The
--  registries stay fully independent: a copy matches filters by NAME in the
--  TARGET's own id space (missing filters are created, same-named ones have
--  their spell content replaced), so no assignment on either side ever needs
--  remapping and nothing stays linked afterward.
-------------------------------------------------------------------------------

local function NameToId(list)
    local m = {}
    for i = 1, #list do
        local f = list[i]
        if m[f.name] == nil then m[f.name] = f.id end
    end
    return m
end

-- "Copy Raid Frames Filters" (our Filter Editor): one-time copy of the Buff
-- Manager library into this registry. The library stores curated PRIMARY ids
-- and expands talent/rank alternates at resolution; this registry flattens
-- alternates into their own keys (seed convention), so each copied primary
-- fans out to its alternates with the same state.
function ns.PAB_CopyBM2FiltersIn()
    local br = EllesmereUI._BM2FilterBridge
    local s = PABEnsure()
    if not (br and s) then return false end
    local src = br.Filters() or {}
    local altsMap = br.PresetAlts and br.PresetAlts() or nil
    local nameToId = NameToId(FilterStore(s).list)
    for i = 1, #src do
        local sf = src[i]
        local tid = nameToId[sf.name]
        local tf = tid and ns.PAB_GetFilter(tid)
        if not tf then
            tf = ns.PAB_AddFilter(sf.name)
        end
        if tf then
            local spells = {}
            for id, on in pairs(sf.spells) do
                local state = on and true or false
                spells[id] = state
                local a = altsMap and altsMap[id]
                if a then
                    for j = 1, #a do spells[a[j]] = state end
                end
            end
            tf.spells = spells
        end
    end
    -- The player FRAME's buff container resolves this registry through the UF
    -- reload pass, not through the PAB apply the caller runs.
    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    return true
end

-- "Copy Player Auras Filters" (Buff Manager side): one-time copy of this
-- registry's filter setups INTO the Buff Manager library by name -- same-
-- named filters take our spell states wholesale, missing filters are created.
-- Library ids never change, so indicator assignments and banked spec-override
-- forks stay valid.
function ns.PAB_CopyOwnFiltersIntoBM2()
    local br = EllesmereUI._BM2FilterBridge
    local s = PAB()
    if not (br and s) then return false end
    -- Alt id -> primary: our registry flattens talent/rank alternates into
    -- their own keys; the Buff Manager library stores primaries and expands
    -- alternates at resolution, so alternates fold onto their primary here.
    local altToPrimary = {}
    local altsMap = br.PresetAlts and br.PresetAlts() or nil
    if altsMap then
        for primary, alts in pairs(altsMap) do
            for i = 1, #alts do altToPrimary[alts[i]] = primary end
        end
    end
    local own = FilterStore(s).list
    local nameToId = NameToId(br.Filters() or {})
    for i = 1, #own do
        local of = own[i]
        local tid = nameToId[of.name]
        if not tid then
            local nf = br.AddFilter(of.name)
            tid = nf and nf.id
        end
        local tf = tid and br.GetFilter(tid)
        if tf then
            local desired = {}
            for id, on in pairs(of.spells) do
                local p = altToPrimary[id]
                if p then
                    -- Primary's own explicit state wins over an alternate's.
                    if of.spells[p] == nil and desired[p] == nil then desired[p] = on and true or false end
                else
                    desired[id] = on and true or false
                end
            end
            local curated = tf.preset and br.CuratedSpells and br.CuratedSpells(tf.preset) or nil
            for id, on in pairs(desired) do
                if tf.spells[id] == nil and not (curated and curated[id]) then
                    -- New non-curated id must carry the custom marker or the
                    -- library's curation prune strips it on the next merge.
                    br.AddCustomSpell(tid, id)
                end
                br.SetSpellState(tid, id, on)
            end
            -- Our version is authoritative: ids we don't carry go unchecked
            -- (false, not nil -- a nil curated id gets re-seeded to its
            -- default) and foreign custom ids are removed.
            for id in pairs(tf.spells) do
                if desired[id] == nil then
                    if tf.custom and tf.custom[id] then
                        br.SetSpellState(tid, id, nil)
                    else
                        br.SetSpellState(tid, id, false)
                    end
                end
            end
        end
    end
    br.Refresh()
    return true
end

-- Parent-published counterpart of _BM2FilterBridge: lets the Buff Manager's
-- Filter Editor drive its one-time copy from its side. Absent = this module
-- is disabled, and its button hides.
EllesmereUI._PABFilterBridge = {
    CopyIntoBM2 = function() return ns.PAB_CopyOwnFiltersIntoBM2() end,
}

function ns.PAB_CustomBuffBars()
    local s = PAB()
    return s and s.customBuffBars or nil
end

-------------------------------------------------------------------------------
-- Buff Manager filter import: the 10 curated preset filters (Defensives, Raid CDs,
--  Externals, Core/Lesser Healing Buffs, Support, Offensive CDs, Movement, Utility,
--  Consumables) as a starting point for PAB Filters.
--
--  Both tables below derive AT LOAD from the parent's canonical
--  EllesmereUI.BUFF_PRESETS catalogue (EllesmereUI_BuffPresets.lua -- THE
--  single curation source, bound directly by the RF Buff Manager, so the two
--  systems can never drift). PAB flattens `alts` into their own rows (PAB
--  Filters have no primary/alt grouping: every id is its own checkbox row);
--  alts inherit their primary's disabled state and class hint. `disabled`
--  entries import unchecked here too. One pass over ~250 entries at load.
-------------------------------------------------------------------------------

-- Display-only hint: which class a curated (imported) spell belongs to, so the
-- Filter Editor can group/color rows. Purely cosmetic -- PAB_ResolveSpells/
-- PAB_SetSpellState never consult it; a filter's spells are always a flat {id=bool}
-- set. "ALL"-class spells get no hint (no class header row for them).
local SPELL_CLASS_HINTS = {}
local BM2_FILTER_SEED = {}
-- Curated primary -> alts (own copy: the RF bridge is absent when that
-- module is disabled, and the family heal below must not depend on it).
local PRESET_ALTS = {}
do
    local BP = EllesmereUI.BUFF_PRESETS
    for i = 1, #BP.filters do
        local def = BP.filters[i]
        local list = BP.spells[def.key]
        local enabled, disabled = {}, {}
        if list then
            for id, info in pairs(list) do
                local dst = info.disabled and disabled or enabled
                dst[#dst + 1] = id
                if info.class ~= "ALL" then SPELL_CLASS_HINTS[id] = info.class end
                if info.alts then
                    PRESET_ALTS[id] = info.alts
                    for j = 1, #info.alts do
                        local alt = info.alts[j]
                        dst[#dst + 1] = alt
                        if info.class ~= "ALL" then SPELL_CLASS_HINTS[alt] = info.class end
                    end
                end
            end
        end
        table.sort(enabled)
        table.sort(disabled)
        BM2_FILTER_SEED[#BM2_FILTER_SEED + 1] =
            { name = def.name, enabled = enabled, disabled = disabled }
    end
    -- Every member of a curated family (primary + its alternates) maps to the whole
    -- member list, so PAB_ResolveSpells can expand from whichever id the user has.
    -- Families are disjoint, so one carried by two preset filters rewrites an equal entry.
    local fams = {}
    for primary, alts in pairs(PRESET_ALTS) do
        local fam = { primary }
        for i = 1, #alts do fam[#fam + 1] = alts[i] end
        for i = 1, #fam do fams[fam[i]] = fam end
    end
    ns.PAB_SPELL_FAMILY = fams
end
ns.PAB_SPELL_CLASS_HINTS = SPELL_CLASS_HINTS

-- PAB_ImportBM2Filters (below) is idempotent: it skips any seed entry whose exact
-- name already exists, so re-clicking Import creates no duplicates, and returns the
-- number of filters actually created.
--
-- PAB_AllPresetSpells returns every spell ID across all 10 curated presets (enabled
-- AND disabled entries both count). Because BM2_FILTER_SEED already has `alts`
-- flattened into its lists, this is a superset of what BM2_AllPresetSpells returns --
-- intended, alts ARE valid trackable buff IDs.
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
        -- Runs every call, not just on fresh creation, so filters the idempotent-by-name
        -- skip would otherwise leave unflagged forever still get the protection flag.
        if f then
            f.preset = true
            -- Additive curation merge (mirrors BM2's EnsureFilters): curated ids
            -- NEW since this filter was created join it with their seed state;
            -- ids the user already has (either state) are never overwritten.
            -- No prune counterpart: PAB has no custom-vs-curated marker, so
            -- removing non-seed ids would delete user additions.
            for j = 1, #seed.enabled do
                local id = seed.enabled[j]
                if f.spells[id] == nil then f.spells[id] = true end
            end
            for j = 1, #seed.disabled do
                local id = seed.disabled[j]
                if f.spells[id] == nil then f.spells[id] = false end
            end
            -- Family heal: a checked PRIMARY whose curated alternates were left
            -- unchecked (the pre-fix editor toggled only the visible row) pulls
            -- its alternates up. Enable-only, primary->alt only, curated
            -- families only: never disables, never touches user-added ids.
            for primary, alts in pairs(PRESET_ALTS) do
                if f.spells[primary] == true then
                    for k = 1, #alts do
                        if f.spells[alts[k]] == false then f.spells[alts[k]] = true end
                    end
                end
            end
        end
    end
    return created
end

function ns.PAB_CustomDebuffBars()
    local s = PAB()
    return s and s.customDebuffBars or nil
end

-- Both lookups search the legacy array first, then every editing-spec
-- bucket (ids are globally unique). Second return = the owning bucket key
-- ("allspecs" for the legacy array) for callers that gate on applicability.
function ns.PAB_GetCustomBuffBar(id)
    local list = ns.PAB_CustomBuffBars()
    if list then
        for i = 1, #list do
            if list[i].id == id then return list[i], "allspecs" end
        end
    end
    local s = PAB()
    local st = s and s.pabSpecBars
    if st then
        for key, b in pairs(st) do
            local bl = b.buffBars
            if bl then
                for i = 1, #bl do
                    if bl[i].id == id then return bl[i], key end
                end
            end
        end
    end
end

function ns.PAB_GetCustomDebuffBar(id)
    local list = ns.PAB_CustomDebuffBars()
    if list then
        for i = 1, #list do
            if list[i].id == id then return list[i], "allspecs" end
        end
    end
    local s = PAB()
    local st = s and s.pabSpecBars
    if st then
        for key, b in pairs(st) do
            local bl = b.debuffBars
            if bl then
                for i = 1, #bl do
                    if bl[i].id == id then return bl[i], key end
                end
            end
        end
    end
end

-- Bar objects (both kinds) also carry the same shared+category cfg fields as
-- DefaultBuffsCfg/DefaultDebuffsCfg (iconSize, durationShow/stackShow,
-- durationPosition/TextSize/OffsetX/Y/ColorR/G/B, stackPosition/TextSize/OffsetX/
-- Y/ColorR/G/B; buff/debuff bars additionally borderSize/R/G/B/A, iconZoom, padding,
-- iconsPerRow, maxRows, maxTotal; debuff bars additionally dispelColorMagic/Curse/
-- Disease/Poison/Bleed). NOT pre-populated, same as those two starting as {}:
-- BuildStyle/ComputeGrid apply the same `or <default>` fallbacks either way, so a
-- fresh bar renders with sane defaults and Options only writes fields the user touches.
function ns.PAB_AddCustomBuffBar(name, bucketKey)
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
        -- Starting grid: a compact single row, deliberately distinct from the default
        -- bars' ComputeGrid fallback (11x3 for buffs) -- a fresh custom bar starts
        -- small rather than inheriting the larger grid.
        iconsPerRow = 8,
        maxRows = 1,
        maxTotal = 8,
    }
    -- The edited editing-spec bucket owns the new bar; ids come from the ONE
    -- shared counter regardless of bucket.
    local target = ns.PAB_BucketBars(true, bucketKey, true) or s.customBuffBars
    target[#target + 1] = bar
    return bar
end

function ns.PAB_AddCustomDebuffBar(name, bucketKey)
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
    local target = ns.PAB_BucketBars(false, bucketKey, true) or s.customDebuffBars
    target[#target + 1] = bar
    return bar
end

-- Deletion only strips the DB entry; it deliberately does NOT remove the bar's
-- engine-side group/slots (containers are add-only). The engine-wiring layer must
-- instead detect the missing DB entry and set maxFrameCount = 0 / hide the bar's
-- frames, like disabled default groups.
-- Deep-copies a custom bar into another editing-spec bucket (the right-click
-- "Add To" menu): full settings clone -- position included -- under a fresh
-- global id; the source is untouched.
function ns.PAB_CopyCustomBar(isBuff, src, bucketKey)
    local s = PABEnsure()
    if not (s and src) then return nil end
    local target = ns.PAB_BucketBars(isBuff, bucketKey, true)
    if not target then return nil end
    local function Copy(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, v2 in pairs(v) do o[k] = Copy(v2) end
        return o
    end
    local bar = Copy(src)
    bar.id = NextBarId(s)
    target[#target + 1] = bar
    return bar
end

-- Shared by both deletes: strip the id from every editing-spec bucket and
-- sweep its per-spec disable keys (ids are global and never reused, so a
-- deleted bar's key could only leak).
local function DeleteFromSpecBuckets(s, id, listField)
    local st = s.pabSpecBars
    if not st then return end
    for _, b in pairs(st) do
        local bl = b[listField]
        if bl then
            for i = #bl, 1, -1 do
                if bl[i].id == id then table.remove(bl, i) end
            end
        end
        if b.inhDis then b.inhDis[id] = nil end
    end
end

function ns.PAB_DeleteCustomBuffBar(id)
    local s = PABEnsure()
    if not s then return end
    if s.customBuffBars then
        for i = #s.customBuffBars, 1, -1 do
            if s.customBuffBars[i].id == id then table.remove(s.customBuffBars, i) end
        end
    end
    DeleteFromSpecBuckets(s, id, "buffBars")
end

function ns.PAB_DeleteCustomDebuffBar(id)
    local s = PABEnsure()
    if not s then return end
    if s.customDebuffBars then
        for i = #s.customDebuffBars, 1, -1 do
            if s.customDebuffBars[i].id == id then table.remove(s.customDebuffBars, i) end
        end
    end
    DeleteFromSpecBuckets(s, id, "debuffBars")
end

-------------------------------------------------------------------------------
--  Editing-spec buckets. The legacy arrays (s.customBuffBars /
--  s.customDebuffBars) ARE the "All Specs" bucket, in place: zero migration,
--  and profiles opened by older builds keep rendering them. Every other
--  bucket lives under s.pabSpecBars[key] = { buffBars, debuffBars, inhDis },
--  key = "nonhealer"/"tanks"/"dps"/"healers" (group buckets) or "spec<ID>"
--  (a concrete spec; healer specs included). Bar ids stay globally unique
--  across buckets (the one shared s.nextBarId), so per-spec disables key on
--  the bare id. Absent pabSpecBars = feature unused = every path below
--  degenerates to the legacy behavior at zero cost.
-------------------------------------------------------------------------------

-- Role group for a specialization ID. Mirrors the RaidFrames helper
-- (ns.BM_RoleBucketForSpecID lives in a different addon namespace, hence a
-- local twin): healers/Aug = HEALER role or Augmentation (1473), keeping
-- "All Non Healers/Aug" its exact complement.
local function RoleBucketForSpecID(specID)
    if not specID then return nil end
    if specID == 1473 then return "healers" end
    local role = GetSpecializationInfoByID and select(5, GetSpecializationInfoByID(specID))
    if role == "HEALER" then return "healers" end
    if role == "TANK" then return "tanks" end
    if role then return "dps" end
    -- Unknown spec/unavailable API: no role bucket beats a wrong one.
    return nil
end
ns.PAB_RoleBucketForSpecID = RoleBucketForSpecID

local function CurrentSpecID()
    local idx = GetSpecialization and GetSpecialization()
    return idx and GetSpecializationInfo and GetSpecializationInfo(idx) or nil
end

-- Group buckets a concrete "spec<ID>" view inherits from, in display order.
-- nil for group views and unknown keys.
function ns.PAB_InheritedGroupsFor(bucketKey)
    local m = type(bucketKey) == "string" and bucketKey:match("^spec(%d+)$")
    local sid = m and tonumber(m)
    if not sid then return nil end
    local out = { "allspecs" }
    local roleKey = RoleBucketForSpecID(sid)
    if roleKey ~= "healers" then out[#out + 1] = "nonhealer" end
    if roleKey then out[#out + 1] = roleKey end
    return out
end

local function SpecBarBucket(s, key, create)
    local st = s.pabSpecBars
    if not st then
        if not create then return nil end
        st = {}; s.pabSpecBars = st
    end
    local b = st[key]
    if not b then
        if not create then return nil end
        b = { buffBars = {}, debuffBars = {}, inhDis = {} }
        st[key] = b
    end
    b.buffBars = b.buffBars or {}
    b.debuffBars = b.debuffBars or {}
    b.inhDis = b.inhDis or {}
    return b
end

-- Bucket bar array for an EDITED view ("allspecs"/nil = the legacy arrays).
function ns.PAB_BucketBars(isBuff, key, create)
    local s = create and PABEnsure() or PAB()
    if not s then return nil end
    if not key or key == "allspecs" then
        if isBuff then
            if create then s.customBuffBars = s.customBuffBars or {} end
            return s.customBuffBars
        end
        if create then s.customDebuffBars = s.customDebuffBars or {} end
        return s.customDebuffBars
    end
    local b = SpecBarBucket(s, key, create)
    if not b then return nil end
    if isBuff then return b.buffBars end
    return b.debuffBars
end

-- Per-spec disable of a GROUP bucket's bar, stored on the viewing spec's
-- concrete "spec<ID>" bucket (ids are global, the bare id suffices).
function ns.PAB_InhDisabled(concreteKey, id)
    local s = PAB()
    local b = s and SpecBarBucket(s, concreteKey, false)
    return (b and b.inhDis and b.inhDis[id]) and true or false
end

function ns.PAB_SetInhDisabled(concreteKey, id, disabled)
    local s = PABEnsure()
    if not (s and concreteKey and id) then return end
    local b = SpecBarBucket(s, concreteKey, true)
    b.inhDis[id] = disabled and true or nil
end

-- Does bucketKey's content render for the given spec?
local function BucketApplies(bucketKey, sid)
    if not bucketKey or bucketKey == "allspecs" then return true end
    local m = bucketKey:match("^spec(%d+)$")
    if m then return sid == tonumber(m) end
    if not sid then return false end
    local roleKey = RoleBucketForSpecID(sid)
    if bucketKey == "nonhealer" then return roleKey ~= "healers" end
    return bucketKey == roleKey
end

-- Render verdict for a custom bar: the MODULE is on (Disable All is a full
-- stand-down, custom bars included -- the field bug was custom bars
-- lingering), the bar's own toggle is on, its owning bucket applies to the
-- CURRENT spec, and (group buckets, All Specs included) this spec hasn't
-- per-spec disabled it. bucketKey nil = legacy = "allspecs".
function ns.PAB_BarActive(bar, bucketKey)
    if not bar or bar.enabled == false then return false end
    local sMaster = PAB()
    if not sMaster or sMaster.enabled ~= true then return false end
    local sid = CurrentSpecID()
    if not BucketApplies(bucketKey, sid) then return false end
    local isOwn = bucketKey and bucketKey:match("^spec%d") and true or false
    if not isOwn and sid then
        local s = PAB()
        local con = s and s.pabSpecBars and s.pabSpecBars["spec" .. sid]
        if con and con.inhDis and con.inhDis[bar.id] then return false end
    end
    return true
end

-------------------------------------------------------------------------------
--  Custom bars -- engine wiring
--
--  Debuffs: one dedicated container per bar (own parent frame, own
--  AK.RequestContainer), groups declared through the SAME BuildChain/ApplyGroupConfig
--  path the default bars use, fed the bar itself as cfg (shares
--  DefaultBuffsCfg/DefaultDebuffsCfg's field shape).
--
--  Buffs: SpellID-based by design -- no class-token checkboxes, selection is
--  filters/direct spells only. Each bar's container holds ONE GROUP for its resolved
--  spell set (candidateFilters.includeSpellIDs, map shape {[id]=true}). NOT one
--  AK.AddAuraSlot per spellID: AK's flow layout only positions GROUP content, so
--  slots never get a real anchor (GetPoint(1) nil) and never render, even
--  unrestricted (see CreateBars). Flows through the SAME ComputeGrid/
--  BuildContainerSpec grid as every other bar. Unlike RaidFrames' Buff Manager (where
--  custom-spell content shares a container with structurally-stable groups, so only a
--  dedicated sub-container is released on a spell-list change), a custom buff bar's
--  container holds nothing else, so releasing and rebuilding the WHOLE container is
--  safe: no other shared group can lose frames.
--
--  bar.filters is resolved via ns.PAB_ResolveSpells, folded into the signature
--  alongside bar.spells, same as the default Buffs bar. bar.ownOnlySpells stays
--  UNCONSULTED -- own-only tracking is not implemented.
-------------------------------------------------------------------------------

local customBuffParents, customBuffContainers, customBuffSig, customBuffDeclared = {}, {}, {}, {}
local customDebuffParents, customDebuffContainers, customDebuffDeclared = {}, {}, {}

-- Which unlock-mode keys are currently registered for custom bars, so RegisterPABCustomUnlock
-- can retire keys for bars deleted since the last call.
local pabRegisteredCustomBuffKeys, pabRegisteredCustomDebuffKeys

local function CustomBuffStyleKey(barId) return "playerAuraBars_customBuff_" .. barId end
local function CustomDebuffStyleKey(barId) return "playerAuraBars_customDebuff_" .. barId end

-- Default anchor for a bar with no saved position yet: the SAME fixed spot (screen
-- center, slight upward offset) for every bar, deliberately not staggered by barId.
-- Only read as a fallback when bar.pos is absent, so a dragged bar keeps its saved
-- position and every untouched bar starts here.
local function DefaultCustomPos(barId)
    return { point = "CENTER", relPoint = "CENTER", x = 0, y = 80 }
end

-- Applies bar.pos (or the default) to a custom bar's parent frame. Same SetPoint
-- logic as ApplyBarPosition, kept separate only because custom bars key off bar.pos
-- on the bar object, not a fixed s[BarPositionKey] slot.
local function ApplyCustomBarPosition(parent, bar, barId)
    local pos = bar.pos or DefaultCustomPos(barId)
    parent:ClearAllPoints()
    local x, y = SnapBarPos(parent, pos.point, pos.relPoint or pos.point, pos.x, pos.y)
    parent:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, x, y)
    if bar.growDirection == "CENTER_HORIZONTAL" or bar.growDirection == "CENTER_VERTICAL" then
        local centeredPos = RebaseBarPositionToCenter(parent, pos)
        if bar.pos or centeredPos ~= pos then bar.pos = centeredPos end
    end
end

local function CustomBuffSpellSignature(spells)
    return table.concat(spells, ",")
end

-- Unlock-mode registration for custom bars: per-element schema from
-- RegisterPABUnlock, "dynamic list" shape from EllesmereUICdmBuffBars.lua's
-- ns.RegisterTBBUnlockElements -- rebuild the FULL element list (every persisted
-- custom buff + debuff bar) and re-register it on every call rather than diffing
-- adds/removes. Cheap at PAB's bar counts, and a freshly-added bar just appears next
-- call with no separate registration path.
--
-- Unlike TBB (index-keyed, where deleting a mid-list bar reshuffles every higher key
-- and its links), PAB custom bars carry a permanent NextBarId that is never reused or
-- renumbered, so TBB's "never unregister, just hide" caution does not apply: a deleted
-- bar's key is retired for good and calling UnregisterUnlockElement is correct, not
-- lossy. Still noResize/noAnchorTarget for the same reason as the default bars.
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
                local b, bk
                if isBuff then b, bk = ns.PAB_GetCustomBuffBar(barId)
                else b, bk = ns.PAB_GetCustomDebuffBar(barId) end
                -- Bucket-scoped bars drop their mover on specs they do not
                -- render for (or were per-spec disabled on).
                return not (b and ns.PAB_BarActive(b, bk))
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
    -- Editing-spec bucket bars register too (every bucket -- isHidden drops
    -- the mover on specs a bar doesn't render for).
    do
        local s = PAB()
        local st = s and s.pabSpecBars
        if st then
            for _, b in pairs(st) do
                local bl = b.buffBars
                if bl then
                    for i = 1, #bl do
                        local bar = bl[i]
                        local key, el = MakeCustomBarElement(bar.id, bar, 702, true, customBuffParents)
                        elements[#elements + 1] = el
                        pabRegisteredCustomBuffKeys[key] = true
                    end
                end
                local dl = b.debuffBars
                if dl then
                    for i = 1, #dl do
                        local bar = dl[i]
                        local key, el = MakeCustomBarElement(bar.id, bar, 703, false, customDebuffParents)
                        elements[#elements + 1] = el
                        pabRegisteredCustomDebuffKeys[key] = true
                    end
                end
            end
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIUnitFrames")
    end

    -- Retire keys for bars deleted since the last call -- safe here (unlike TBB)
    -- because PAB custom-bar ids are permanent, see doc comment above.
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

-- Public hook for the Options UI: (re)builds one custom buff bar's engine state to
-- match its current DB entry. Safe after ANY change to that bar (spell add/remove, any
-- cfg field, enable toggle, delete): it diffs the spell signature itself and only pays
-- for a container rebuild when the spell list actually changed, while style/grid/anchor
-- are cheap to re-apply every time. One combined call (vs the default bars'
-- RestyleBars/ApplyLiveConfig split) keeps the Options UI's call sites simple.
--
-- Wrapped below so unlock-mode registration stays in sync on every exit path (deleted,
-- disabled, spell-list-unchanged, full rebuild) without repeating
-- RegisterPABCustomUnlock() at each early return.
local function ReloadCustomBuffBarImpl(barId)
    AK = AK or (EllesmereUI and EllesmereUI.AuraKit)
    if not AK then return end
    local bar, barBucket = ns.PAB_GetCustomBuffBar(barId)
    if not bar then
        -- Deleted: release the container (frees its slot-button tracking; engine
        -- frames themselves are never destroyed) and hide the now-orphaned parent.
        if customBuffContainers[barId] then RetireContainer(customBuffContainers[barId], customBuffDeclared[barId]) end
        if customBuffParents[barId] then customBuffParents[barId]:Hide() end
        customBuffContainers[barId], customBuffParents[barId], customBuffSig[barId], customBuffDeclared[barId] = nil, nil, nil, nil
        return
    end
    if DeferRestrictedApply("custom-buff-" .. barId,
        function() ns.PAB_ReloadCustomBuffBar(barId) end,
        customBuffContainers[barId], bar.growDirection) then return end

    local styleKey = CustomBuffStyleKey(barId)
    AK.styles[styleKey] = BuildStyle(true, bar)
    -- Counterpart to RestyleBars' AK.RestyleSoon for the default bars. REQUIRED:
    -- writing AK.styles[styleKey] alone only affects buttons created after this point
    -- (MakeInitializer runs once per button), so a style-only edit on a bar whose
    -- buttons already exist (the "spell list unchanged" path below) would keep
    -- rendering the OLD style until the container was rebuilt for an unrelated reason.
    -- RestyleSoon re-runs ApplyStyleToRegions against every already-live button
    -- under that key.
    AK.RestyleSoon(styleKey)
    SyncCancelCVar()

    local grid = ComputeGrid(true, bar)
    local parent = customBuffParents[barId]
    local fresh = false
    if not parent then
        parent = CreateFrame("Frame", "EllesmereUIPlayerAuraBars_CustomBuff" .. barId, UIParent)
        customBuffParents[barId] = parent
        parent:SetSize(grid.width, grid.height)
        fresh = true
    end
    -- Same anchor-ancestor rule as ApplyLiveConfig: an EXISTING parent has the engine
    -- container anchored to it, so its position/size writes are blocked in lockdown --
    -- skip them and reconcile with one full reload at the regen edge (position deltas
    -- are not tracked per bar, so the queue is unconditional on the skip). A parent
    -- created THIS pass has no container anchored yet and stays fully writable. The
    -- config re-drive below still runs -- that is what the in-combat recovery needs.
    local geomLocked = not fresh and InCombatLockdown()
    if geomLocked then
        QueuePABRegenApply("custom-buff-" .. barId, function() ns.PAB_ReloadCustomBuffBar(barId) end)
    else
        ApplyCustomBarPosition(parent, bar, barId)
    end
    -- Effective render verdict: the bar's own toggle AND its editing-spec
    -- bucket's applicability to the current spec AND this spec's per-spec
    -- disable of group bars. Inactive parks exactly like disabled.
    local barActive = ns.PAB_BarActive(bar, barBucket)
    SetParentShownSafe("custom-buff-" .. barId, parent, barActive,
        function() ns.PAB_ReloadCustomBuffBar(barId) end)
    if not barActive then return end

    if not geomLocked then
        parent:SetSize(grid.width, grid.height)
    end

    local spells = ns.PAB_ResolveSpells(bar)
    local sig = CustomBuffSpellSignature(spells)
    -- Show All Buffs works on custom buff bars too: mirrors the default Buffs bar's
    -- catch-all group (BuildChain zero-classes, "all" key) via the same
    -- ApplyGroupConfig path custom debuff bars use for their category chain --
    -- ApplyGroupConfig is generic over any {key,tokens} chain.
    local allChain = BuffBarChain(bar)

    if customBuffContainers[barId] then
        -- Style/grid-only change (icon size, padding, grow direction, ...): container
        -- exists and the spell list is unchanged, so just re-apply the live
        -- anchor/growth/rowWidth, the same fields ApplyLiveConfig live-updates for
        -- the default bars.
        local container = customBuffContainers[barId]
        ApplyContainerAnchorAndGrowth(container, parent, bar, grid)

        if customBuffSig[barId] == sig then
            -- Spell list unchanged: still refresh the spells group's
            -- maxFrameCount/layout in case the grid changed, and re-apply the
            -- catch-all chain (ApplyGroupConfig is idempotent and self-zeroes it
            -- when Show All Buffs is off).
            if #spells > 0 then
                local livePad = bar.padding or 5
                container:SetAuraGroupMaxFrameCount("spells", grid.effectiveMax)
                container:SetAuraGroupLayout("spells", BuildGroupLayout(bar, livePad, grid.rowGap))
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
        RetireContainer(container, customBuffDeclared[barId]) -- safe: dedicated container, nothing else on it
        customBuffContainers[barId] = nil
    end

    local _, spec = BuildContainerSpec(parent, bar, grid)
    local pad = bar.padding or 5
    AK.RequestContainer(parent, "player", spec, function(container)
        customBuffContainers[barId] = container
        ApplyContainerAnchorAndGrowth(container, parent, bar, grid)
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
                layout = BuildGroupLayout(bar, pad, grid.rowGap),
            })
        end
    end)
end

function ns.PAB_ReloadCustomBuffBar(barId)
    ReloadCustomBuffBarImpl(barId)
    RegisterPABCustomUnlock()
    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview("buff", barId) end
end

-- Public hook for the Options UI: (re)builds one custom debuff bar's engine state to
-- match its current DB entry. Groups are additive and never released (see
-- ApplyGroupConfig) -- a class toggle, grid change, or style edit just re-runs this on
-- the same container. Wrapped for the same reason as PAB_ReloadCustomBuffBar: unlock-
-- mode registration stays in sync on every exit path.
local function ReloadCustomDebuffBarImpl(barId)
    AK = AK or (EllesmereUI and EllesmereUI.AuraKit)
    if not AK then return end
    local bar, barBucket = ns.PAB_GetCustomDebuffBar(barId)
    if not bar then
        if customDebuffContainers[barId] then
            -- Groups cannot be un-declared, so zero every group's frame count instead:
            -- icons disappear even though the container itself is never released.
            -- "__cand|" entries are generation metadata, not group keys (same skip
            -- as ApplyGroupConfig's active-set sweep) -- passing one to the engine
            -- errors with "aura group was not found".
            for key in pairs(customDebuffDeclared[barId] or {}) do
                if key:sub(1, 7) ~= "__cand|" then
                    customDebuffContainers[barId]:SetAuraGroupMaxFrameCount(key, 0)
                end
            end
        end
        if customDebuffParents[barId] then customDebuffParents[barId]:Hide() end
        -- Bar IDs are never reused, so this entry is never looked up again: drop our
        -- tracking-table references (container stays alive engine-side, only
        -- addon-side bookkeeping clears) so tables don't grow unbounded over time.
        customDebuffParents[barId], customDebuffContainers[barId], customDebuffDeclared[barId] = nil, nil, nil
        return
    end
    if DeferRestrictedApply("custom-debuff-" .. barId,
        function() ns.PAB_ReloadCustomDebuffBar(barId) end,
        customDebuffContainers[barId], bar.growDirection) then return end

    local styleKey = CustomDebuffStyleKey(barId)
    AK.styles[styleKey] = BuildStyle(false, bar)
    -- Required for the same reason as ReloadCustomBuffBarImpl above.
    AK.RestyleSoon(styleKey)

    local grid = ComputeGrid(false, bar)
    local parent = customDebuffParents[barId]
    local fresh = false
    if not parent then
        parent = CreateFrame("Frame", "EllesmereUIPlayerAuraBars_CustomDebuff" .. barId, UIParent)
        customDebuffParents[barId] = parent
        parent:SetSize(grid.width, grid.height)
        fresh = true
    end
    -- Same lockdown rule as the custom buff reload above (anchor-ancestor geometry
    -- block; full-reload reconcile at regen; fresh parents stay writable).
    local geomLocked = not fresh and InCombatLockdown()
    if geomLocked then
        QueuePABRegenApply("custom-debuff-" .. barId, function() ns.PAB_ReloadCustomDebuffBar(barId) end)
    else
        ApplyCustomBarPosition(parent, bar, barId)
    end
    -- Same effective-render verdict as the custom buff reload above.
    local barActive = ns.PAB_BarActive(bar, barBucket)
    SetParentShownSafe("custom-debuff-" .. barId, parent, barActive,
        function() ns.PAB_ReloadCustomDebuffBar(barId) end)
    if not barActive then return end

    if not geomLocked then
        parent:SetSize(grid.width, grid.height)
    end

    local chain = BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, bar) or (PAB_FxSafeToForce(class) and PAB_FxWantsCategory(bar.fxList, class.key)) end, DebuffCatchAllOn(bar), DebuffSubtractFn(bar))
    local _, spec = BuildContainerSpec(parent, bar, grid)
    local pad = bar.padding or 5

    if not customDebuffContainers[barId] then
        AK.RequestContainer(parent, "player", spec, function(container)
            customDebuffContainers[barId] = container
            ApplyContainerAnchorAndGrowth(container, parent, bar, grid)
            customDebuffDeclared[barId] = {}
            ApplyGroupConfig(container, chain, customDebuffDeclared[barId], styleKey, grid.effectiveMax, pad, grid.rowGap, bar, DebuffCandidateExtras(bar))
        end)
    else
        local container = customDebuffContainers[barId]
        ApplyContainerAnchorAndGrowth(container, parent, bar, grid)
        ApplyGroupConfig(container, chain, customDebuffDeclared[barId], styleKey, grid.effectiveMax, pad, grid.rowGap, bar, DebuffCandidateExtras(bar))
    end
end

function ns.PAB_ReloadCustomDebuffBar(barId)
    ReloadCustomDebuffBarImpl(barId)
    RegisterPABCustomUnlock()
    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview("debuff", barId) end
end

-- Rebuilds every persisted custom bar's engine state. Called once from TryCreateBars
-- alongside the default bars, and safe to call again any time (profile switch, spec
-- change): both reload functions above are idempotent no-ops when nothing changed.
-- Iterates the legacy arrays AND every editing-spec bucket -- each per-bar reload
-- resolves its own effective verdict, so bars from now-inactive buckets park their
-- frames exactly like disabled ones.
local function ReloadAllCustomBarsImpl()
    local presentBuff, presentDebuff = {}, {}
    local buffList = ns.PAB_CustomBuffBars()
    if buffList then
        for i = 1, #buffList do
            presentBuff[buffList[i].id] = true
            ns.PAB_ReloadCustomBuffBar(buffList[i].id)
        end
    end
    local debuffList = ns.PAB_CustomDebuffBars()
    if debuffList then
        for i = 1, #debuffList do
            presentDebuff[debuffList[i].id] = true
            ns.PAB_ReloadCustomDebuffBar(debuffList[i].id)
        end
    end
    local s = PAB()
    local st = s and s.pabSpecBars
    if st then
        for _, b in pairs(st) do
            local bl = b.buffBars
            if bl then
                for i = 1, #bl do
                    presentBuff[bl[i].id] = true
                    ns.PAB_ReloadCustomBuffBar(bl[i].id)
                end
            end
            local dl = b.debuffBars
            if dl then
                for i = 1, #dl do
                    presentDebuff[dl[i].id] = true
                    ns.PAB_ReloadCustomDebuffBar(dl[i].id)
                end
            end
        end
    end
    -- STALE SWEEP (field bug: a bar from the PREVIOUS profile stayed on
    -- screen after a profile swap): addon-side parents/containers are keyed
    -- by bar id and outlive the profile table. Any id the CURRENT profile no
    -- longer carries takes the per-bar reload's deleted-bar branch, which
    -- retires the container, hides the parent and clears the bookkeeping.
    -- (Lua 5.1: clearing the CURRENT key during pairs() is legal; the
    -- deleted-bar branch nils exactly the iterated id.)
    for barId in pairs(customBuffParents) do
        if not presentBuff[barId] then ns.PAB_ReloadCustomBuffBar(barId) end
    end
    for barId in pairs(customDebuffParents) do
        if not presentDebuff[barId] then ns.PAB_ReloadCustomDebuffBar(barId) end
    end
end
ReloadAllCustomBars = ReloadAllCustomBarsImpl
ns.PAB_ReloadAllCustomBars = ReloadAllCustomBarsImpl

-------------------------------------------------------------------------------
-- Options-page preview box, embedded inside the bar's own detail page (NOT an
--  on-screen overlay at the bar's real position). Shows FAKE buffs/debuffs at the
--  bar's REAL configured icon size/grid (iconSize, iconsPerRow, maxRows, maxTotal,
--  via the same ComputeGrid the live bar uses), styled with the bar's real
--  BuildStyle/dispel-color output, so size/count/row-wrap/growth/spacing/border/
--  duration+stack formatting all preview live. No real aura data, and the real
--  bar/container is never touched. Debuffs cycle through fake spellIDs carrying real
--  dispel tokens (Magic/Curse/Poison/Disease/Bleed) so BuildDispelColorMap's border
--  coloring previews too.
--
--  Icons are hand-built Frame/Texture/FontString regions, not AK buttons: AK's
--  AuraContainer has no supported way to receive synthetic aura data.
-------------------------------------------------------------------------------

-- Class-appropriate fake buff pool: the preview draws from buffs the player's class
-- actually has, not a fixed generic list. Purely cosmetic (icon texture only, see
-- PreviewSpellIcon's fallback), so a wrong/renamed ID just shows the question-mark
-- icon. Keyed by the class FILE token (UnitClass's 2nd return, e.g. "PRIEST").
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

-- Fallback for an unrecognized class token (defensive only) or a missing entry.
local PREVIEW_BUFF_SPELLS = { 21562, 1459, 1126, 6673 } -- Fort, Arcane Intellect, Mark of the Wild, Battle Shout

-- Cross-class/consumable buffs for the "All Buffs" preview fill: All Buffs has no
-- finite spell list, and real raid buffs come from every class plus food/flask/
-- world-buff consumables, not just the player's class. Same 4 IDs as
-- EUI_RaidFrames_BuffManager2.lua's curated "consumables" preset (class="ALL"
-- entries), duplicated rather than cross-addon-referenced: RaidFrames' ns table is
-- not shared with this addon and may not be loaded.
local EXTRA_WORLD_PREVIEW_BUFFS = { 1236998, 1236616, 1239479, 1236994 }

-- Shuffles a fresh copy of `source` (Fisher-Yates), never mutating the source table.
local function ShuffleCopy(source)
    local out = {}
    for i = 1, #source do out[i] = source[i] end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

-- Builds a freshly shuffled copy of the "All Buffs" preview pool. Called ONCE per
-- ns.PAB_BuildPreviewBox, not per live-apply refresh: the order is stashed on
-- activePreview and reused by every RenderPreviewIcons call for that box, so icons
-- keep their spell identity across slider ticks and only style/position/count changes.
--
-- Combines every class's CLASS_PREVIEW_BUFFS (13 x 10 = 130) plus
-- EXTRA_WORLD_PREVIEW_BUFFS' consumables (134 total), shuffled flat with NO class
-- priority (own-class-first is explicitly not wanted). 134 is far larger than any
-- configured grid (maxTotal defaults to 32), so the pool-exhausted fallback
-- effectively never triggers.
local function BuildBuffPreviewPool()
    local combined = {}
    for _, spells in pairs(CLASS_PREVIEW_BUFFS) do
        for i = 1, #spells do combined[#combined + 1] = spells[i] end
    end
    for i = 1, #EXTRA_WORLD_PREVIEW_BUFFS do combined[#combined + 1] = EXTRA_WORLD_PREVIEW_BUFFS[i] end
    if #combined == 0 then combined = PREVIEW_BUFF_SPELLS end
    return ShuffleCopy(combined)
end

-- Curated by hand (mostly recent Mythic+/dungeon trash debuffs): no verified debuff
-- catalog in this repo to source from, unlike CLASS_PREVIEW_BUFFS.
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

-- Shuffled once per box build, same reasoning as BuildBuffPreviewPool: icons must
-- not swap identity on every slider tick.
local function BuildDebuffPreviewPool()
    return ShuffleCopy(PREVIEW_DEBUFF_SPELLS)
end

-- Memoized fake-icon texture lookup: C_Spell.GetSpellInfo's iconID, falls back to
-- the generic question-mark icon.
local previewIconCache = {}
local function PreviewSpellIcon(spellID)
    local cached = previewIconCache[spellID]
    if cached then return cached end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local icon = (info and info.iconID) or 134400
    previewIconCache[spellID] = icon
    return icon
end

-- Weapon-enchant preview cells, leading the bar exactly like the live ones
-- (EUI_UnitFrames_WeaponEnchants.lua publishes them ahead of the engine run).
-- Main hand + off hand only: those are the two slots reachable in current
-- retail content, even though both that module's SLOTS and Blizzard's
-- UpdateTemporaryEnchantmentBuffs still poll a third (ranged) -- so a bar sized
-- for three enchants shows one placeholder cell of genuine spare capacity here,
-- which is what the live bar would do too.
--
-- Paints the player's OWN equipped weapon icons rather than an invented sample:
-- that is literally what the live buttons draw (PaintContent ->
-- GetInventoryItemTexture), so the preview matches the real thing instead of
-- approximating it. 134400 is the codebase's standard unknown-icon fallback,
-- used when a slot is empty.
local PREVIEW_ENCHANT_SLOTS = { INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17 }

-- Only slots actually holding a weapon get a cell. With a two-hander (or any
-- empty off hand) there is no second weapon to enchant, and drawing the
-- unknown-icon question mark there would advertise a cell the player can never
-- fill. An unarmed character still gets the single main-hand cell, so ticking
-- the option always previews as something rather than silently nothing.
local function PreviewEnchantSlots()
    local out = {}
    for i = 1, #PREVIEW_ENCHANT_SLOTS do
        local slot = PREVIEW_ENCHANT_SLOTS[i]
        if GetInventoryItemTexture("player", slot) then out[#out + 1] = slot end
    end
    if #out == 0 then out[1] = PREVIEW_ENCHANT_SLOTS[1] end
    return out
end

-- Empty-slot art per weapon slot, for a character with nothing equipped:
-- Blizzard's own character-pane silhouette reads as "a weapon goes here", where
-- the generic unknown-icon question mark reads as "something is broken".
-- C_PaperDollInfo.GetInventorySlotInfo(slotName) -> id, textureName, checkRelic
-- (verified against Blizzard_UIPanels_Game/PaperDollFrame.lua, which uses the
-- same namespaced call).
local PREVIEW_ENCHANT_SLOT_NAMES = { [INVSLOT_MAINHAND or 16] = "MainHandSlot",
    [INVSLOT_OFFHAND or 17] = "SecondaryHandSlot" }
local function PreviewEnchantIcon(slot)
    local tex = GetInventoryItemTexture("player", slot)
    if tex then return tex end
    local name = PREVIEW_ENCHANT_SLOT_NAMES[slot]
    if name and C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo then
        local _, slotTex = C_PaperDollInfo.GetInventorySlotInfo(name)
        if slotTex then return slotTex end
    end
    return 134400
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

-- Best-effort preview simulation of the 4 curated sort methods (Default/Expiration/
-- Name/ImportantOnly, see EUI_PlayerAuraBars_ManagerPages.lua's SORT_METHOD_VALUES).
-- Per Blizzard's AuraUtil.lua comparators: Expiration = ascending expirationTime,
-- Name = alphabetical spell name, ImportantOnly = `C_Spell.IsSpellImportant(spellId)`
-- first (a native per-spell flag, NOT dispel-type-based, applies equally to buffs).
-- The real comparators also weight player-cast/priority/canApplyAura ahead of the
-- named criterion and tie-break on auraInstanceID -- not reproduced here (fake
-- entries have no equivalent), so this approximates relative ORDER only.
-- `sortDirection == "Reverse"` flips every comparison INCLUDING under Default: whether
-- the engine's Default ordering respects direction is unknown, and reversing the
-- pool's own order beats ignoring the toggle. Never mutates `list`.
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

-- Which bar-detail pane owns the visible preview box (kind: "buff"/"debuff", id:
-- "default" or a custom bar id), plus that box's icon pool and the fontPath it was
-- built with, so a live-apply hook can re-render in place without rebuilding the
-- detail pane. Reset to a fresh box on every ns.PAB_BuildPreviewBox call, since the
-- owning pane is always torn down and rebuilt on structural changes (switching bars,
-- add/rename/delete).
local activePreview

-- Stable random preview swipe seeds (fraction remaining, 0.2-0.9), keyed by slot
-- index: generated once and reused so re-renders never reshuffle frozen swipe positions.
local pvCDSeeds = {}
local function GetPvCDSeed(i)
    local v = pvCDSeeds[i]
    if not v then v = 0.2 + math.random() * 0.7; pvCDSeeds[i] = v end
    return v
end

-- Layer order matches the live bar exactly (AK's own ApplyStyleToRegions): icon
-- texture (btn, ARTWORK) below border (child frame, level+1) below duration/stack
-- text (textHost, child frame, level+2, ABOVE the border).
local function CreatePreviewIcon(box)
    local btn = CreateFrame("Frame", nil, box)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    -- "Nothing configured" placeholder: a red X over the icon's flat grey fill,
    -- shown instead of a fake spell icon when the bar's real config would show zero
    -- buffs (Show All Buffs off, no Filters/Extra Spells resolved) -- see
    -- RenderPreviewIcons' noneConfigured check. Reuses the existing close/X media icon.
    btn.placeholder = btn:CreateTexture(nil, "OVERLAY")
    btn.placeholder:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    btn.placeholder:SetVertexColor(1, 0.2, 0.2, 1)
    btn.placeholder:Hide()
    -- Duration-swipe preview: same CooldownFrameTemplate child the live bar's
    -- buttons carry. Created hidden; armed per refresh from the bar's Show Duration
    -- Swipe setting. Created BEFORE the border/text hosts so it renders above the
    -- icon but below both (live ladder).
    btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints()
    btn.cooldown:SetDrawEdge(false)
    btn.cooldown:SetHideCountdownNumbers(true)
    btn.cooldown:Hide()
    btn.border = CreateFrame("Frame", nil, btn)
    -- Plain preview region, not a real AuraKit button -- masking is unguarded here.
    btn.shapeMask = btn:CreateMaskTexture()
    btn.shapeMask:Hide()
    btn.textHost = CreateFrame("Frame", nil, btn)
    btn.duration = btn.textHost:CreateFontString(nil, "OVERLAY")
    btn.stack = btn.textHost:CreateFontString(nil, "OVERLAY")
    return btn
end

-- Resolves a bar's live cfg + polarity from its (kind,id) identity, via the same
-- lookups every other engine-side path uses.
local function ResolvePreviewCfg(kind, id)
    local s = PAB()
    if not s then return nil end
    if id == "default" then
        local isBuff = kind == "buff"
        return (isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)), isBuff
    elseif kind == "buff" then
        return ns.PAB_GetCustomBuffBar(id), true
    else
        return ns.PAB_GetCustomDebuffBar(id), false
    end
end

-- Options-panel "pixel perfect" compensation: the options window runs at effective
-- scale baseScale*userScale (EllesmereUI.GetPopupScale()), while real PAB bars are
-- parented straight to UIParent with no extra scale, so identical iconSize/padding/
-- border/text-size NUMBERS render visibly SMALLER in the panel whenever that scale is
-- below 1 (the common case). Do NOT SetScale the preview box itself -- that desyncs it
-- from the sy layout accounting placing widgets below it. Instead every size-affecting
-- cfg field is pre-multiplied by 1/GetPopupScale() before reaching
-- BuildStyle/ComputeGrid, so the ENTIRE preview inflates by exactly the panel's scale
-- factor and lands at the same TRUE on-screen size as the live bar. WoW's own UI Scale
-- cancels out algebraically (UIParent's effective scale multiplies both equally), so
-- only the panel's OWN extra SetScale factor matters.
local function PreviewScaleFactor()
    local s = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1
    if not s or s <= 0 then return 1 end
    return 1 / s
end

-- Duplicates BuildStyle's own `or <default>` fallbacks for every scaled field
-- (32/5/1/11/0/11/0) since a size can't be scaled without first resolving what
-- "unset" means -- keep in sync if BuildStyle's defaults change. Non-size fields
-- (growDirection, iconsPerRow/maxRows/maxTotal, dispel colors, ...) pass through.
local function ApplyPreviewScale(cfg, comp)
    if comp == 1 then return cfg end
    local out = {}
    for k, v in pairs(cfg) do out[k] = v end
    out.iconSize = (cfg.iconSize or 32) * comp
    out.padding = (cfg.padding or 5) * comp
    out.rowSpacing = cfg.rowSpacing and (cfg.rowSpacing * comp) or nil
    out.borderSize = (cfg.borderSize or 1) * comp
    -- PabShapeBorderSize is keyed by the raw 0-4 level, so it must run BEFORE scaling
    -- (unlike out.borderSize above) -- resolve the level, then scale the result,
    -- mirroring iconSize's own scale-after-resolve treatment. BuildStyle prefers this
    -- over recomputing from the already-scaled out.borderSize when present.
    out.shapeBorderSizeOverride = PabShapeBorderSize(cfg.borderSize or 1) * comp
    out.durationTextSize = (cfg.durationTextSize or 11) * comp
    out.durationOffsetX = (cfg.durationOffsetX or 0) * comp
    out.durationOffsetY = (cfg.durationOffsetY or 0) * comp
    out.dispelIconSize = (cfg.dispelIconSize or 16) * comp
    out.dispelIconOffsetX = (cfg.dispelIconOffsetX or 0) * comp
    out.dispelIconOffsetY = (cfg.dispelIconOffsetY or 0) * comp
    out.stackTextSize = (cfg.stackTextSize or 11) * comp
    out.stackOffsetX = (cfg.stackOffsetX or 0) * comp
    out.stackOffsetY = (cfg.stackOffsetY or 0) * comp
    -- Icon Effects Per-Filter Size overrides need the same panel-scale compensation
    -- as iconSize: a per-block shallow copy (never mutating the real saved fxList or
    -- its filters/borderColor sub-tables) with only `.size` rescaled, so both the
    -- preview's box footprint (ComputeGrid's MaxIconSizeFor) and the fake-icon
    -- SetSize read the right pixel value.
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

-- Preview area height budget: Up/Down growth with several icons-per-column makes the
-- box very tall very fast, pushing the rest of the options page down. Applied as an
-- EXTRA proportional shrink on top of the panel-zoom compensation, combined into ONE
-- factor so iconSize/padding/rowSpacing/etc are scaled once, not twice. Only ever
-- shrinks (extra <= 1); horizontal and short vertical bars are unaffected.
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

-- Renders (or re-renders in place) the fake icon grid using the bar's CURRENT cfg --
-- safe on every live slider tick, only touches plain addon-owned
-- Frame/Texture/FontString regions, never the real bar. Row/column math mirrors
-- ComputeGrid/BuildContainerSpec's own corner-anchored flow layout so the preview
-- wraps exactly like the live bar.
local function HasAnyTrue(map)
    if not map then return false end
    for _, v in pairs(map) do if v then return true end end
    return false
end

-- True when the FILLER portion (whatever is left after real resolved spells, see
-- BuildPreviewSlots) should show fake example icons rather than empty placeholders.
-- Buffs: ONLY All Buffs justifies fake filler, since it has no finite spell list --
-- Filters/Extra Spells resolve to a concrete finite set (ns.PAB_ResolveSpells, drawn
-- as real icons), so anything beyond that count is genuinely empty capacity, not
-- content pretending to exist. Debuffs have no per-spell resolution for class filters
-- (aura filter string/category tokens), so Show All Debuffs OR any Base Filter class
-- justifies fake filler (mirrors BuildChain's includeCatchAll condition); debuffs CAN
-- show truly nothing.
local function HasFillerSource(isBuff, cfg)
    if isBuff then
        return cfg.showAllBuffs ~= false or cfg.hasDuration == true
    end
    return cfg.showAllDebuffs ~= false or cfg.hasDuration == true or HasAnyTrue(cfg.classFilters)
end

-- BuildPreviewSlots (below) builds one descriptor per icon slot (length `count`).
-- Buffs: the bar's REAL resolved spells (ns.PAB_ResolveSpells -- Filters' enabled
-- spells + Extra Spells, deliberately NOT All Buffs, which has no finite list) take
-- the LEADING slots as {kind="extra", spellID=} with their own real icons; a Filter
-- selection and an Extra Spell are equally "real content" to the preview. Whatever is
-- left is {kind="fake", entry=} when HasFillerSource is true, else
-- {kind="placeholder"} -- e.g. 4 resolved spells in room for 8 with All Buffs off
-- renders 4 real + 4 placeholders, never 4 fake. Debuffs have no per-spell
-- resolution, so every slot there is fake-or-placeholder.
--
-- DedupeByIcon: ns.PAB_ResolveSpells dedupes by SPELL ID, but a filter's `alts`
-- (rank/alternate ids for the same visual buff) are DIFFERENT ids sharing the SAME
-- icon, rendering it twice. Dedupe the preview's real-spell list by ICON TEXTURE,
-- keeping the first occurrence (lowest spell ID, ResolveSpells sorts numerically).
-- Preview-only: the real bar shows active aura instances, not an enumeration of
-- possible spell IDs.
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

-- ns.PAB_ResolveSpells unions every selected Filter's + Extra Spells' ids into ONE
-- numerically sorted set. Truncating that to the first `count` would let whichever
-- Filter holds the lowest-numbered spells win every visible slot while other Filters
-- never appear. Instead interleave round-robin ACROSS sources (each selected Filter is
-- a source, Extra Spells is one more), so truncation samples a bit of everything.
-- Deterministic (no math.random) on purpose: unlike the fake pools this must NOT
-- reshuffle on every live-apply refresh.
local function BuildMixedRealSpells(cfg)
    local sources = {}
    -- Broad modes render through the catch-all, so show-lane real icons only exist in
    -- add mode; the hide lane (cfg.negFilters) drops its spells from these sources the
    -- same way the live spells group resolves (PAB_ResolveSpells) -- Extra Spells are
    -- a separate source below and win over the hide lane there too.
    if cfg.filters and cfg.showAllBuffs == false and cfg.hasDuration ~= true then
        local negSet
        if cfg.negFilters then
            for filterId in pairs(cfg.negFilters) do
                local nf = ns.PAB_GetFilter and ns.PAB_GetFilter(filterId)
                if nf and nf.spells then
                    for id, on in pairs(nf.spells) do
                        if on then
                            negSet = negSet or {}
                            negSet[id] = true
                            ExpandFamily(negSet, id, nf.spells)
                        end
                    end
                end
            end
        end
        local allFilters = ns.PAB_Filters and ns.PAB_Filters()
        if allFilters then
            for i = 1, #allFilters do
                local f = allFilters[i]
                if cfg.filters[f.id] then
                    local ids = {}
                    for id, on in pairs(f.spells) do
                        if on and not (negSet and negSet[id]) then ids[#ids + 1] = id end
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
    -- Sort Method/Direction must apply to the REAL extra icons too, not just the fake
    -- filler pool: with All Buffs off the content is mostly/only these real slots, so
    -- skipping them leaves the sort controls looking dead.
    --
    -- SELECT before SORT: with more resolved+deduped spells than icon slots, sorting
    -- the FULL list and truncating afterward puts a DIFFERENT subset into the
    -- surviving first `count` per sort, so changing sort would swap WHICH spells
    -- appear, not just their order. Truncate to `count` on the stable, sort-
    -- independent mixed order FIRST, then sort that fixed selection for display.
    -- Weapon enchants take the LEADING cells and are never sorted into the aura
    -- content: they are not auras. They are also ADDITIVE, not a slice of the
    -- bar's capacity -- the live container keeps its full maxFrameCount and is
    -- shifted past them wholesale (ShiftBuffsForEnchants), so an enchant never
    -- costs an aura its slot.
    local numEnch, enchSlots = 0, nil
    if isBuff and cfg.showWeaponEnchants == true then
        enchSlots = PreviewEnchantSlots()
        numEnch = #enchSlots
    end
    -- The two modes are genuinely different shapes and the preview mirrors both:
    --   * alongside auras -- the container keeps its full maxFrameCount and is
    --     shifted past the enchants wholesale, so they cost no aura its slot and
    --     the first row overflows the reserved grid by the shift.
    --   * enchants-only -- the grid was auto-sized FOR the enchants
    --     (SyncWeaponEnchantsGrid) and the container holds no groups, so the
    --     cells sit INSIDE that reserved width. The leftover cells stay as
    --     placeholders on purpose: they are what explains where the bar's width
    --     comes from, and dropping them made the 3-wide frame look arbitrary.
    local avail = count
    if isBuff and ns.PAB_IsWeaponEnchantsOnly(cfg) then
        avail = math.max(0, count - numEnch)
    end

    local mixed = isBuff and DedupeByIcon(BuildMixedRealSpells(cfg)) or nil
    local extraIDs
    if mixed then
        local numSelected = math.min(#mixed, avail)
        local selected = {}
        for i = 1, numSelected do selected[i] = mixed[i] end
        extraIDs = SortPreviewList(selected, isBuff, cfg)
    end
    local numExtra = extraIDs and #extraIDs or 0
    local numFiller = avail - numExtra
    local slots = {}
    for i = 1, numEnch do
        slots[i] = { kind = "enchant", slot = enchSlots[i] }
    end
    for i = 1, numExtra do
        slots[numEnch + i] = { kind = "extra", spellID = extraIDs[i] }
    end
    if numFiller > 0 then
        if hasFiller then
            -- Buff subtract mode (broad mode + hide-lane filters): the filler pool
            -- drops every subtracted spell, matching what the live catch-all's
            -- excludeSpellIDs removes.
            local subSet
            if isBuff and (cfg.showAllBuffs ~= false or cfg.hasDuration == true) and cfg.negFilters then
                for filterId in pairs(cfg.negFilters) do
                    local f = ns.PAB_GetFilter and ns.PAB_GetFilter(filterId)
                    if f and f.spells then
                        for id, on in pairs(f.spells) do
                            if on then
                                subSet = subSet or {}
                                subSet[id] = true
                                ExpandFamily(subSet, id, f.spells)
                            end
                        end
                    end
                end
            end
            -- Same select-before-sort fix as the real extra icons above, applied to
            -- All Buffs' fake filler too: select the fixed filler slice from `list`
            -- (stable, shuffled once per box build, NOT sorted) first, then sort only
            -- that selection -- so Sort Method/Direction reorders the SAME fake icons
            -- already showing instead of pulling different ones from the pool.
            local fillerSelected = {}
            if subSet then
                local n = 0
                for scan = 1, listLen do
                    if n >= numFiller then break end
                    local e = list[scan]
                    if not subSet[e] then
                        n = n + 1
                        fillerSelected[n] = e
                    end
                end
            else
                for i = 1, numFiller do
                    fillerSelected[i] = list[((i - 1) % listLen) + 1]
                end
            end
            fillerSelected = SortPreviewList(fillerSelected, isBuff, cfg)
            for i = 1, numFiller do
                local e = fillerSelected[i]
                slots[numEnch + numExtra + i] = e and { kind = "fake", entry = e } or { kind = "placeholder" }
            end
        else
            for i = 1, numFiller do
                slots[numEnch + numExtra + i] = { kind = "placeholder" }
            end
        end
    end
    return slots, numEnch
end

-- Icon Effects Per-Filter preview: applies a matched fx block's Glow/Border to a
-- fake preview icon. These are plain addon-owned frames (CreatePreviewIcon), never
-- secure engine buttons, so no creation-window/taint restriction applies: glow/border
-- hosts are created lazily and Glows.StartGlow is called directly, with no
-- RestrictionSafeStyle gate (real aura buttons only). `e` is nil when no active fx
-- block matches this icon's category (or for buff/placeholder slots), clearing any fx
-- left over from a previous render of this reused frame.
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

    -- Size override is deliberately NOT applied here: it feeds RenderPreviewIcons'
    -- per-icon flow packing (slotSize/colOffset/rowYOffset), which must know each
    -- icon's footprint BEFORE positioning any of them.
end

-- `pool` is the box's own stable, pre-shuffled fake-icon pool (shuffled once per box
-- build for BOTH polarities, see BuildBuffPreviewPool/BuildDebuffPreviewPool).
local function RenderPreviewIcons(box, icons, isBuff, cfg, fontPath, pool)
    cfg = ScaledPreviewCfg(cfg, isBuff)
    local style = BuildStyle(isBuff, cfg)
    local dcMap = (not isBuff) and BuildDispelColorMap(cfg) or nil
    local grid = ComputeGrid(isBuff, cfg)

    -- The box itself (and the header darken band/divider below it, see
    -- ns.PAB_BuildPreviewBox) is FIXED at its build-time size: divider/box stay put,
    -- only the CONTENT changes on a live settings edit. Icons are instead centered as
    -- a BLOCK inside the box's current (unchanging) width/height, using
    -- box:GetCenter()-relative offsets rather than anchoring to one of the box's own
    -- corners -- growDirection still decides which edge of that centered block fills
    -- first (matches the live bar's own fill order), it just doesn't move the
    -- box/divider while doing it.
    local growDir = cfg.growDirection or "LEFT"
    local wrapDir = cfg.iconWrapDirection or "LEFT"
    local centeredVertical = growDir == "CENTER_VERTICAL"
    local vertical = (growDir == "UP" or growDir == "DOWN" or centeredVertical)
    local corner = CornerFor(growDir, wrapDir)
    local pad = cfg.padding or 5
    local rowGap = cfg.rowSpacing or 12
    local iconSize = cfg.iconSize or 32
    local cols = math.max(1, cfg.iconsPerRow or (isBuff and 11 or 8))
    local count = grid.effectiveMax
    -- NOT sorted here (same "select before sort" reasoning as the real extra icons
    -- below): `list` is much larger than `count` (fake pools are 134/66 entries), so
    -- sorting the WHOLE pool before BuildPreviewSlots selects its filler slice would
    -- let a sort change pull a DIFFERENT subset of fake icons into view. BuildPreviewSlots
    -- selects the fixed filler slice from this stable, shuffled-once order FIRST, sorts after.
    local list = (pool and #pool > 0 and pool) or (isBuff and PREVIEW_BUFF_SPELLS or PREVIEW_DEBUFF_SPELLS)
    local listLen = #list
    local slots, numEnch = BuildPreviewSlots(isBuff, cfg, list, listLen, count)
    -- Enchants are additive leading cells, so the rendered total exceeds the
    -- bar's aura capacity by however many are showing.
    local total = #slots
    local auraCount = total - numEnch

    -- Icon Effects Per-Filter preview (debuffs only): deliberately NOT tied to the
    -- bar's own active Base Filters/Show All Debuffs state -- requiring a matching
    -- Base Filter meant the preview usually showed nothing, since the two dropdowns
    -- serve different purposes and aren't meant to be set identically. Instead every
    -- ACTIVE fx block claims 1-2 fake icon slots outright regardless of which
    -- categories are actually enabled -- a "here's what this effect looks like"
    -- demonstration, not a claim these icons represent that category on a real bar
    -- (the fake pool has no Blizzard boss/role/priority flags to support that anyway).
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

    local rows = math.max(1, math.ceil(auraCount / cols))

    -- Real per-icon flow packing: each slot's OWN actual render size (its fx Size
    -- override, or the bar's base iconSize) drives its own footprint directly, so
    -- spacing between normal icons stays tight and only an oversized icon's immediate
    -- neighbors get pushed out -- true flow-layout behavior rather than a uniform
    -- worst-case cell grid (which left too much gap around every normal icon). Shape-
    -- expanded the same as the live bar's own button SetSize (BuildStyle/
    -- EnsurePabSizedStyle), so preview spacing/footprint matches the real bar.
    local slotSize = {}
    for i = 1, total do
        local e = fxBySlot and fxBySlot[i]
        local sz = e and tonumber(e.size)
        slotSize[i] = PabShapedSize((sz and sz > 0) and sz or iconSize, cfg.iconShape)
    end

    local rowWidth, rowHeight, colOffset, rowYOffset = {}, {}, {}, {}
    do
        -- Weapon enchants lead row 0 at the bar's own corner, and the aura block
        -- starts past them on EVERY row -- ShiftBuffsForEnchants moves the whole
        -- container, not just its first line, so lower rows stay indented by the
        -- same amount and the first row overflows the reserved grid by the
        -- shift. That asymmetry is the real bar's behavior; packing enchants as
        -- plain leading members of one uniform flow would wrap row 2 back to the
        -- bar's edge and misrepresent it.
        local enchShift = 0
        for k = 1, numEnch do
            colOffset[k] = enchShift
            enchShift = enchShift + slotSize[k] + pad
            rowHeight[0] = math.max(rowHeight[0] or 0, slotSize[k])
        end

        local runningX, runningY = {}, 0
        for r = 0, rows - 1 do runningX[r] = enchShift end
        for i = numEnch + 1, total do
            local r = math.floor((i - numEnch - 1) / cols)
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
    -- blockW/blockH are generic axis extents: "within-line" (rowWidth, primary/fill
    -- axis) and "across-lines" (wrap axis) -- screen X/Y only for horizontal growth.
    -- Vertical growth (Up/Down) swaps which maps to X vs Y below.
    local blockW = 0
    for r = 0, rows - 1 do blockW = math.max(blockW, rowWidth[r] or 0) end
    local blockH = math.max(0, (rowYOffset[rows - 1] or 0) + (rowHeight[rows - 1] or 0))
    local halfPrimary, halfCross = blockW / 2, blockH / 2
    local growUp = (growDir == "UP")
    local wrapRight = (wrapDir == "RIGHT")
    -- Read the wrap-up state off the CORNER, not off wrapDir: CornerFor only emits a
    -- BOTTOM component where an Up wrap is actually in effect, so the preview cannot
    -- drift from the real bars or inherit a stale wrap in the centered modes.
    local wrapUp = (corner == "BOTTOMLEFT" or corner == "BOTTOMRIGHT")

    for i = 1, math.max(total, #icons) do
        if i <= total then
            local btn = icons[i]
            if not btn then
                btn = CreatePreviewIcon(box)
                icons[i] = btn
            end

            -- Enchant cells all live on row 0; aura slots index into their own
            -- block, which starts after them (see the packing block above).
            local row = (i <= numEnch) and 0
                or math.floor((i - numEnch - 1) / cols)
            local withinLineStep = colOffset[i]
            local acrossLinesStep = rowYOffset[row]
            -- btn's own anchor point is `corner` (matching growDirection/
            -- iconWrapDirection), placed at an offset from the box's CENTER -- see the
            -- block-centering comment above `local rows = ...`. Vertical growth
            -- swaps which step drives X vs Y: the within-line step (icons
            -- stacking inside one column) becomes Y, the across-lines step (columns
            -- wrapping sideways) becomes X -- mirrors the corner/growthH/growthV swap
            -- in CornerFor/BuildContainerSpec used by the real (non-preview) bars.
            local btnX, btnY
            if centeredVertical then
                btnY = halfPrimary - withinLineStep - slotSize[i] / 2
                btnX = -halfCross + acrossLinesStep + slotSize[i] / 2
            elseif vertical then
                btnY = growUp and (-halfPrimary + withinLineStep) or (halfPrimary - withinLineStep)
                btnX = wrapRight and (-halfCross + acrossLinesStep) or (halfCross - acrossLinesStep)
            else
                btnY = wrapUp and (-halfCross + acrossLinesStep) or (halfCross - acrossLinesStep)
                btnX = (corner == "TOPRIGHT" or corner == "BOTTOMRIGHT") and (halfPrimary - withinLineStep) or (-halfPrimary + withinLineStep)
            end
            btn:ClearAllPoints()
            btn:SetPoint(centeredVertical and "CENTER" or corner, box, "CENTER", btnX, btnY)
            btn:SetSize(slotSize[i], slotSize[i])

            local slot = slots[i]
            local dispel

            if slot.kind == "placeholder" then
                -- Flat grey box + centered red X (see CreatePreviewIcon) instead of a
                -- fake spell icon -- nothing would actually render on the real bar
                -- here. Border still draws -- only icon texture and duration/stack
                -- text are placeholder-specific.
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

                if slot.kind == "enchant" then
                    -- Weapon enchant: an ITEM texture, not a spell icon -- the
                    -- live buttons paint the equipped weapon the same way.
                    btn.icon:SetTexture(PreviewEnchantIcon(slot.slot))
                else
                    local spellID
                    if slot.kind == "extra" then
                        -- Real Extra Spell: always its own actual icon, never folded into
                        -- the fake cycling pool.
                        spellID = slot.spellID
                    else -- "fake"
                        local entry = slot.entry
                        spellID = isBuff and entry or entry.id
                        dispel = (not isBuff) and entry.dispel or nil
                    end
                    btn.icon:SetTexture(PreviewSpellIcon(spellID))
                end
                local z = style.iconZoom or 0.055
                btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
            end

            -- Mirrors EllesmereUI_AuraKit.lua's ApplyStyleToRegions, unguarded (plain regions).
            local shapeActive = style.iconShape and style.iconShape ~= "none" and style.shapeMaskPath
            if shapeActive then
                btn.shapeMask:SetTexture(style.shapeMaskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                btn.shapeMask:SetAllPoints(btn)
                btn.shapeMask:Show()
                local sz = slotSize[i]
                local zoom = style.iconZoom or 0.055
                local shapeKey = style.iconShape .. "|" .. sz .. "|" .. zoom
                if btn._shapeApplied ~= shapeKey then
                    pcall(btn.icon.RemoveMaskTexture, btn.icon, btn.shapeMask)
                    btn.icon:AddMaskTexture(btn.shapeMask)
                    local insetPx = style.shapeInsetPx or 17
                    local visRatio = (128 - 2 * insetPx) / 128
                    local fullExpand = ((1 / visRatio) - 1) * 0.5
                    -- Coupled to Icon Zoom, same as the live bar (EllesmereUI_AuraKit.lua).
                    local expand = math.max(fullExpand * (zoom / 0.055), 0)
                    btn.icon:ClearAllPoints()
                    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", -expand * sz, expand * sz)
                    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", expand * sz, -expand * sz)
                    btn._shapeApplied = shapeKey
                end
            else
                if btn._shapeApplied then
                    pcall(btn.icon.RemoveMaskTexture, btn.icon, btn.shapeMask)
                    btn.icon:ClearAllPoints()
                    btn.icon:SetAllPoints()
                    btn._shapeApplied = nil
                end
                btn.shapeMask:Hide()
            end

            btn.border:SetAllPoints(shapeActive and btn or btn.icon)
            btn.border:SetFrameLevel(btn:GetFrameLevel() + 1)
            local PP = EllesmereUI and EllesmereUI.PanelPP
            if PP and style.border then
                local br, bg, bb, ba = style.border[1], style.border[2], style.border[3], style.border[4]
                if dispel and dcMap and dcMap[dispel] then
                    local c = dcMap[dispel]
                    br, bg, bb, ba = c.r, c.g, c.b, 1
                end
                local size = style.border.size or 1
                if shapeActive and style.shapeBorderPath and PP.ApplyMaskedShapeBorder then
                    PP:ApplyMaskedShapeBorder(btn.border, btn.shapeMask, style.shapeBorderPath, style.shapeBorderSize or size, br, bg, bb, ba)
                    if PP.ShowBorder then PP.ShowBorder(btn.border) end
                    btn.border:Show()
                else
                    if PP.HideMaskedShapeBorder then PP:HideMaskedShapeBorder(btn.border)
                    elseif btn.border._shapeBorderTex then btn.border._shapeBorderTex:Hide() end
                    -- PP.CreateBorder is create-once-only; live size/color changes on an
                    -- already-created host go through PP.UpdateBorder instead.
                    if btn.borderMade then
                        PP.UpdateBorder(btn.border, size, br, bg, bb, ba)
                    elseif PP.CreateBorder then
                        PP.CreateBorder(btn.border, br, bg, bb, ba, size, "OVERLAY", 7)
                        btn.borderMade = true
                    end
                    if PP.ShowBorder then PP.ShowBorder(btn.border) else btn.border:Show() end
                end
            else
                if PP and PP.HideBorder then PP.HideBorder(btn.border) else btn.border:Hide() end
                if PP and PP.HideMaskedShapeBorder then PP:HideMaskedShapeBorder(btn.border)
                elseif btn.border._shapeBorderTex then btn.border._shapeBorderTex:Hide() end
            end

            -- Dispel-type indicator icon (style.dispelTypeIcon): the live bar's
            -- engine channel picks the art per aura; here the fake entry's own
            -- dispel token does. Drawn above the border on the button itself.
            local ti = style.dispelTypeIcon
            if ti and dispel and PV_DISPEL_ICON_ATLAS[dispel] then
                if not btn.typeIcon then
                    btn.typeIcon = btn:CreateTexture(nil, "OVERLAY", nil, 3)
                end
                btn.typeIcon:SetAtlas(PV_DISPEL_ICON_ATLAS[dispel])
                -- Geometry from the (panel-scaled) cfg, like iconSize above --
                -- style carries the live PP.Scale'd size, wrong units here.
                local tiSz = cfg.dispelIconSize or 16
                btn.typeIcon:SetSize(tiSz, tiSz)
                btn.typeIcon:ClearAllPoints()
                local tiPt = PV_DISPEL_ICON_POINTS[ti.pos] or "CENTER"
                btn.typeIcon:SetPoint(tiPt, btn, tiPt,
                    cfg.dispelIconOffsetX or 0, cfg.dispelIconOffsetY or 0)
                btn.typeIcon:Show()
            elseif btn.typeIcon then
                btn.typeIcon:Hide()
            end

            local cdMaskKey = shapeActive and style.iconShape or nil
            if btn._cdShapeApplied ~= cdMaskKey then
                if cdMaskKey then
                    pcall(btn.cooldown.AddMaskTexture, btn.cooldown, btn.shapeMask)
                    if btn.cooldown.SetSwipeTexture then
                        pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, style.shapeMaskPath)
                    end
                else
                    pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, btn.shapeMask)
                    if btn.cooldown.SetSwipeTexture then pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, "") end
                end
                btn._cdShapeApplied = cdMaskKey
            end

            if slot.kind ~= "placeholder" then
                btn.textHost:SetAllPoints(btn)
                btn.textHost:SetFrameLevel(btn:GetFrameLevel() + 2)

                btn.duration:ClearAllPoints()
                btn.duration:SetFont(fontPath, style.durationFontSize or 11, "OUTLINE")
                btn.duration:SetPoint(style.durationPoint or "CENTER", btn, style.durationRelPoint or "CENTER",
                    style.durationX or 0, style.durationY or 0)
                local dc = style.durationColor
                btn.duration:SetTextColor(dc and dc.r or 1, dc and dc.g or 1, dc and dc.b or 1)
                btn.duration:SetShown(not style.hideDurationText)
                btn.duration:SetText(PREVIEW_DURATIONS[((i - 1) % #PREVIEW_DURATIONS) + 1])

                btn.stack:ClearAllPoints()
                btn.stack:SetFont(fontPath, style.stackFontSize or 11, "OUTLINE")
                btn.stack:SetPoint(style.stackPoint or "BOTTOMRIGHT", btn, style.stackPoint or "BOTTOMRIGHT",
                    style.stackX or 0, style.stackY or 0)
                local sc = style.stackColor
                btn.stack:SetTextColor(sc and sc.r or 1, sc and sc.g or 1, sc and sc.b or 1)
                local stackVal = PREVIEW_STACKS[((i - 1) % #PREVIEW_STACKS) + 1]
                btn.stack:SetShown(style.showStacks ~= false and stackVal ~= nil)
                if stackVal then btn.stack:SetText(stackVal) end
            end

            -- Duration-swipe preview: randomized FROZEN sweep -- a stable per-slot
            -- fraction on an hour-long cooldown, so each icon shows a varied
            -- mid-flight state without visibly animating. Reverse per the bar's
            -- Reverse Swipe cog; placeholder slots carry no swipe.
            local cd = btn.cooldown
            if cd then
                if slot.kind ~= "placeholder" and style.hideSwipe ~= true then
                    local dur = 3600
                    cd:SetReverse(style.cooldownReverse ~= false)
                    cd:SetCooldown(GetTime() - dur * (1 - GetPvCDSeed(i)), dur)
                    cd:Show()
                else
                    cd:SetCooldown(0, 0)
                    cd:Hide()
                end
            end

            -- nil clears any fx left over on a reused icon frame from a previous
            -- render (slot not claimed this pass, or block removed/deactivated).
            ApplyPreviewFx(btn, fxBySlot and fxBySlot[i])

            btn:Show()
        elseif icons[i] then
            icons[i]:Hide()
        end
    end
end

-- Public hook for the Options UI: builds this bar's embedded preview box entirely
-- OUTSIDE the scrollable settings area (the scrollbar must only scroll the settings
-- fields, never the preview) -- box, "PREVIEW" label, darkened header band, and divider
-- are all children of `outerFrame` (the detail pane's top-level, non-scrolling frame
-- title/desc already live on), sized to the bar's REAL configured grid (ComputeGrid,
-- same as the live bar), horizontally centered (TOP-to-TOP anchor).
--
-- The "PREVIEW" label is wrapped in a small padDiff-compensated + clipped frame (same
-- CONTENT_PAD-vs-20px trick as EUI_PlayerAuraBars_ManagerPages.lua's
-- WrapCompensatedBody, duplicated rather than shared -- W:SectionHeader assumes a 45px
-- margin but this pane only reserves 20px); the box itself needs no such compensation,
-- positioned via a plain SetPoint not a W: widget.
--
-- Geometry (box size, header band, divider Y, and the caller's scroll-area top offset
-- via the onResize hook -- see PAB_MaybeRefreshPreview) is recomputed on every
-- live-apply refresh too, not just at build time: a row/column/icon-count change
-- (Icons Per Row, Max Rows, Max Total, Icon Size, Row Spacing, ...) changes the grid's
-- real footprint, and a stale-size box would clip new icons or leave a gap until the
-- next rebuild. Box/divider position stays fixed at build time (so settings fields
-- don't jump on slider ticks) but the box's own footprint must track its grid.
--   outerFrame: detail pane's top-level frame (title/desc's parent). startY:
--   outerFrame-local Y to start the PREVIEW label/box (caller's fixed offset below
--   title/desc, e.g. -50). kind: "buff" or "debuff"; id: "default" | a custom bar's
--   id. cfg: the same cfg table the caller already resolved for its own field builders.
-- Returns the outerFrame-local Y where the preview area ends -- passed straight to
-- WrapCompensatedBody(outerFrame, returnedY) as the scroll area's top offset.
function ns.PAB_BuildPreviewBox(outerFrame, fontPath, startY, kind, id, cfg)
    local isBuff = kind == "buff"
    local sy = startY

    do
        local contentPad = EllesmereUI.CONTENT_PAD or 45
        local padDiff = contentPad - 20
        local visibleW = outerFrame:GetWidth()
        -- Was W:SectionHeader, a shared widget fixed at 40px tall with its label
        -- anchored 8px from the BOTTOM -- meant for spacing consistency among stacked
        -- option rows elsewhere, not this floating title/desc/box context, and it left
        -- ~20px of blank padding above "PREVIEW" with nothing needing that room here.
        -- Replaced with a lightweight, purpose-built label + separator at a fraction
        -- of the height, matching SectionHeader's look (EllesmereUI.TEXT_SECTION/
        -- BORDER_COLOR) without touching the shared widget file.
        local hdrH = 18

        -- Shift lives on the clipping frame (hdrClip), not hdrBody inside it --
        -- mirrors WrapCompensatedBody's own fix in EUI_PlayerAuraBars_
        -- ManagerPages.lua ("shift the child instead of the clip frame" measured a
        -- real ~30px extra gap in-game vs shifting the clip/scroll frame itself).
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

    -- Sized from the SCALED cfg (see ScaledPreviewCfg/PreviewScaleFactor) so the
    -- box's footprint matches what RenderPreviewIcons actually draws into it.
    local grid = ComputeGrid(isBuff, ScaledPreviewCfg(cfg, isBuff))
    -- +30 (scaled) extra vertical room for duration/stack text above/below the icon
    -- grid -- ComputeGrid's width/height are the icon grid's bounding box only (same
    -- as the real bar), text can render outside it depending on Duration/Stacks Position.
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
    -- The tinted band covers the PREVIEW header + box only, starting at startY --
    -- the pane's own title row above it stays on the plain background.
    headerBg:ClearAllPoints()
    headerBg:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 0, startY)
    headerBg:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, startY)

    local divider = outerFrame._pabPreviewDivider
    if not divider then
        divider = outerFrame:CreateTexture(nil, "OVERLAY")
        divider:SetColorTexture(1, 1, 1, 0.10)
        divider:SetHeight(1)
        outerFrame._pabPreviewDivider = divider
    end

    local bottomY = sy - boxHeight - 10
    headerBg:SetHeight(startY - bottomY)
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 0, bottomY)
    divider:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, bottomY)

    local icons = {}
    -- Shuffled once per box build, not per refresh (see BuildBuffPreviewPool: icons
    -- shouldn't swap spell identity on every slider tick, only style/position/count).
    -- Debuffs get the same treatment via BuildDebuffPreviewPool().
    local pool
    if isBuff then
        pool = BuildBuffPreviewPool()
    else
        pool = BuildDebuffPreviewPool()
    end
    activePreview = {
        kind = kind, id = id, box = box, icons = icons, fontPath = fontPath, pool = pool,
        outerFrame = outerFrame, boxTopY = sy, bandTopY = startY,
        headerBg = headerBg, divider = divider,
    }
    RenderPreviewIcons(box, icons, isBuff, cfg, fontPath, pool)

    return bottomY
end

-- Registers a callback the caller's WrapCompensatedBody (EUI_PlayerAuraBars_
-- ManagerPages.lua) uses to reposition its scroll frame's top edge whenever
-- PAB_MaybeRefreshPreview resizes the box below. Set on activePreview (not a
-- standalone module-level var) so a callback from a since-torn-down detail pane can
-- never fire against the wrong pane's box after a tab switch rebuilds activePreview.
function ns.PAB_SetPreviewResizeHandler(fn)
    if activePreview then activePreview.onResize = fn end
end

-- Piggyback hook, called at the end of every live-apply path (ApplyLiveConfig,
-- PAB_ReloadCustomBuffBar, PAB_ReloadCustomDebuffBar) so a currently-open preview box
-- stays in sync with slider drags/dropdown changes without EUI_PlayerAuraBars_
-- ManagerPages.lua needing to know the preview exists or wrap its ApplyBar() closures.
PAB_MaybeRefreshPreview = function(kind, id)
    if not (activePreview and activePreview.kind == kind and activePreview.id == id) then return end
    local cfg, isBuff = ResolvePreviewCfg(kind, id)
    if not cfg then return end

    -- Re-derive the box's footprint from the SAME scaled grid RenderPreviewIcons is
    -- about to draw into, mirroring PAB_BuildPreviewBox's own boxHeight/bottomY math
    -- (kept in sync manually).
    local grid = ComputeGrid(isBuff, ScaledPreviewCfg(cfg, isBuff))
    local boxHeight = grid.height + 30 * PreviewScaleFactor()
    activePreview.box:SetSize(math.max(grid.width, 1), boxHeight)

    local bottomY = activePreview.boxTopY - boxHeight - 10
    if activePreview.headerBg then
        activePreview.headerBg:SetHeight((activePreview.bandTopY or 0) - bottomY)
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
-- EnableBody() only schedules via C_Timer.After(0, SetupOptionsPanel) -- one frame
-- AFTER PLAYER_LOGIN's handlers finish. A single PLAYER_LOGIN listener here would run
-- BEFORE ns.db exists (confirmed: PAB() returned nil at that point). Rather than
-- depend on the exact relative timing between two independent C_Timer.After(0, ...)
-- calls in different files, retry with a capped, gently backing-off timer until ns.db
-- is actually populated.
local RETRY_CAP = 40 -- ~ a few seconds worst case at the backed-off interval; then give up loudly
local retryCount = 0

local function TryCreateBars()
    -- Module-disabled stand-down: EnableBody stamps ns._eufEnabled before this
    -- handler can run (same PLAYER_LOGIN dispatch, parent enable-drain first,
    -- module router second, this file's handler third). No stamp = the Unit
    -- Frames module is off this session, ns.db will never arrive, and erroring
    -- would spam every login for users who simply disabled the module.
    if not ns._eufEnabled then return end
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

function ns.PAB_Enabled()
    local s = PAB()
    return (s and s.enabled == true) or false
end

-- Called by the options page's activation overlay and the sidebar's Disable
-- All toggle. Enabling builds the bars live (CreateBars guards its own
-- re-entry; container creation is combat-legal). Disabling is reload-bound
-- for the BLIZZARD side (the corner-frame
-- hide latches for the session) but stands every PAB frame down NOW -- the
-- field bug was custom bars lingering through the "Later" window while the
-- default bars hid: Disable All must be a complete visual no-op.
function ns.PAB_SetEnabled(v)
    local s = PAB()
    if not s then return end
    s.enabled = v and true or nil
    if v then
        -- A stand-down latched before the module went off has no lane to lift
        -- it while disabled, and the rebuild below would come up dimmed.
        ClearDegraded()
        CreateBars()
        return
    end
    if buffsParent then buffsParent:Hide() end
    if debuffsParent then debuffsParent:Hide() end
    for _, parent in pairs(customBuffParents) do parent:Hide() end
    for _, parent in pairs(customDebuffParents) do parent:Hide() end
    ns._weaponEnchPAB = nil
    if ns.WeaponEnchants_Layout then ns.WeaponEnchants_Layout() end
    -- The re-hide hooks release once the master is off: hand Blizzard's
    -- native display back live.
    ShowBlizzardPlayerAuras()
    -- Re-registering re-reads isHidden (master gate now false everywhere), so
    -- an open unlock session drops every PAB mover immediately.
    RegisterPABUnlock()
    RegisterPABCustomUnlock()
end

function ns.PAB_UseBlizzard()
    local s = PAB()
    return (s and s.useBlizzardBuffs == true) or false
end

-- Profile-grade resync, called from the _EUF_ReloadFrames tail (profile
-- switches, imports, spec-override swaps all land there): re-asserts the
-- CURRENT profile's enable/useBlizzard modes across the default-bar
-- visibility, the native frames and the default unlock movers. Builds the
-- module late when a swap crosses from a disabled-at-login state into an
-- enabled profile (nothing else would). Deliberately does NOT run
-- ApplyLiveConfig: its size-rebase writes assume lastSize belongs to the
-- SAME profile and would corrupt the new profile's saved positions.
function ns.PAB_ProfileResync()
    local s = PAB()
    if s and s.enabled == true and s.useBlizzardBuffs ~= true
        and not (buffsParent or debuffsParent) then
        -- Enabled profile, module never built this session: full build
        -- (covers customs + unlock + natives itself).
        CreateBars()
        return
    end
    ApplyDefaultBarShown(true)
    ApplyDefaultBarShown(false)
    SyncNativeAuras()
    RegisterPABUnlock()
end

-- Live apply for the Use Blizzard Buffs toggle. ON: the default bars stand
-- down and the natives come back NOW (the re-hide hooks read ownership
-- live). OFF: a full CreateBars pass rebuilds the default bars and hides
-- the natives again, entirely live. Custom bars run in both modes.
function ns.PAB_ApplyUseBlizzard()
    local s = PAB()
    if not (s and s.enabled == true) then return end
    if s.useBlizzardBuffs == true then
        ApplyDefaultBarShown(true)
        ApplyDefaultBarShown(false)
        ns._weaponEnchPAB = nil
        if ns.WeaponEnchants_Layout then ns.WeaponEnchants_Layout() end
        ShowBlizzardPlayerAuras()
        RegisterPABUnlock()
    else
        CreateBars()
        RegisterPABUnlock()
    end
end

-- Cinematic / faction-flip recovery. Two triggers, one degradation class:
-- an addon-cancelled cinematic (CINEMATIC_STOP) puts the engine aura
-- containers through a hide/re-show whose re-parse can land while the
-- teardown's filter state is still degraded, and EVERY cinematic
-- (in-world cutscenes included) fires UNIT_FACTION for the player at start
-- and end -- the unit briefly stops being assistable, which silently
-- disables spell-ID candidate filters engine-side (authors-channel
-- consensus 2026-08-13: same mechanism community-wide; UNIT_FLAGS does NOT
-- fire, UNIT_FACTION is the only edge). Filtered bars then render the FULL
-- buff set, and with no aura event following, the wrong content sticks.
-- The one lever Lua holds over engine-owned content is config: re-run the
-- group config for every live container (candidate filters are the
-- live-changeable channel, so re-setting them forces a fresh parse), one
-- tick after the event so the transition has finished. Coalesced; the
-- start+end UNIT_FACTION burst collapses to one re-drive.
-- Vehicle suppression: assistability stays down for the WHOLE ride, so the
-- exit re-drive alone still left the ride itself showing the full buff set.
-- Match the raid frames' gate by standing the bar parents down -- the
-- vehicle has its own UI -- and restoring on exit, where the recovery
-- re-drive repaints from clean filter state. The stand-down is alpha, not a
-- Hide (SetParentShownSafe): the exit routinely lands inside lockdown, where
-- a Show is blocked. A suppressed ride therefore costs what ordinary play
-- costs -- the containers stay registered behind alpha 0.
-- vehicleHidden and pabSuppressed are forward-declared at the top of the state
-- section (every parent-visibility pass reads the latter).
-- Bare apply, no state guard: the recovery lane re-asserts the CURRENT
-- state after its reload paths (which Show() the parents as a side effect).
-- Restoring (hidden = false) honors each bar's OWN enable toggle -- a
-- vehicle exit must never re-show a disabled bar's fully-populated grid.
-- Probe-verified self-assist state (the RF AssistProbe self-branch, ported):
-- the engine's spell-ID filter degradation tracks ASSISTABILITY, not any event's
-- timing. A clean false = degraded (hide, never render the full-set parse);
-- unreadable answers fail OPEN (the historical self-exemption -- never
-- retry-loop against secrecy).
local pabDegraded = false
local pabSettleTicker
local function PabAssistProbe()
    local probe = UnitUsingVehicle or UnitInVehicle
    if probe("player") then return false end
    local ok, canSelf = pcall(UnitCanAssist, "player", "player")
    if ok and not (issecretvalue and issecretvalue(canSelf)) and canSelf == false then
        return false
    end
    return true
end

local function ApplyVehicleHidden(hidden)
    -- One suppression state, two causes: a vehicle ride and a probe-degraded
    -- window (cinematic / faction flip) hide the same parents -- degraded
    -- filter output must never render, exactly like the RF assist gate.
    hidden = hidden or pabDegraded
    -- The suppression itself lands on alpha inside SetParentShownSafe; `want`
    -- below stays the durable render verdict, so a bar disabled mid-ride still
    -- hides for real and a reload that runs during the ride cannot un-suppress
    -- the parents behind our back.
    pabSuppressed = hidden
    local s = PAB()
    -- Regen replay re-derives from the LIVE vehicle state, not the argument.
    local function recompute() ApplyVehicleHidden(vehicleHidden) end
    -- Master enable + Use Blizzard Buffs both stand the defaults down: a
    -- vehicle exit during the disabled "Later" window must not re-show them.
    if buffsParent then
        SetParentShownSafe("vehicle-buffs", buffsParent, (not s
            or (s.enabled == true and DefaultBuffsCfg(s).enabled ~= false
                and s.useBlizzardBuffs ~= true)), recompute)
    end
    if debuffsParent then
        SetParentShownSafe("vehicle-debuffs", debuffsParent, (not s
            or (s.enabled == true and DefaultDebuffsCfg(s).enabled ~= false
                and s.useBlizzardBuffs ~= true)), recompute)
    end
    -- Restore honors the FULL render verdict (master enable + bar toggle +
    -- editing-spec bucket applicability + per-spec disable): a vehicle exit
    -- must never re-show a parked bar's fully-populated grid. Orphan parents
    -- (bar gone after a delete/profile switch) stay hidden -- the old
    -- `not bar` show-fallback punched through every gate.
    for barId, parent in pairs(customBuffParents) do
        local bar, bk = ns.PAB_GetCustomBuffBar(barId)
        SetParentShownSafe("vehicle-cb-" .. barId, parent,
            bar ~= nil and ns.PAB_BarActive(bar, bk), recompute)
    end
    for barId, parent in pairs(customDebuffParents) do
        local bar, bk = ns.PAB_GetCustomDebuffBar(barId)
        SetParentShownSafe("vehicle-cd-" .. barId, parent,
            bar ~= nil and ns.PAB_BarActive(bar, bk), recompute)
    end
end
local function SetVehicleHidden(hidden)
    if vehicleHidden == hidden then return end
    vehicleHidden = hidden
    -- Lifting: the containers kept parsing behind alpha 0 (dimmed, not hidden,
    -- so their engine events stayed live) and the spell-ID filters are still
    -- degraded through the exit transition -- un-dimming on the raw event edge
    -- would paint the full-set parse. Hand the stand-down to the degraded lane
    -- instead: the same event arms it, and it un-dims and forces the clean
    -- re-parse in one execution. Both callers reach the lane immediately, and
    -- every lane exit clears the latch (ClearDegraded below).
    if not hidden then pabDegraded = true end
    ApplyVehicleHidden(hidden)
end

-- The latch is only ever meaningful while the recovery lane is live: every
-- early exit down there hands it back, or a stand-down set on a transition
-- outlives the thing that caused it and every later bar comes up dimmed.
-- Forward-declared at the top of the state section (the enable path clears a
-- latch that was set while the module was off, where no lane runs at all).
function ClearDegraded()
    if not pabDegraded then return end
    pabDegraded = false
    ApplyVehicleHidden(vehicleHidden)
end

local cineFixPending = false
local function ReapplyAllAfterCinematic()
    if cineFixPending then return end
    -- Custom containers count as live consumers too: under Use Blizzard
    -- Buffs the default containers never exist, but custom bars still need
    -- the filter-degradation repair.
    if not (buffsContainer or debuffsContainer
        or next(customBuffContainers) or next(customDebuffContainers)) then
        ClearDegraded()
        return
    end
    cineFixPending = true
    C_Timer.After(0, function()
        cineFixPending = false
        -- Master-disabled (awaiting reload): nothing to repair, and the
        -- re-drives below must not touch parked frames.
        local sM = PAB()
        if not sM or sM.enabled ~= true then
            ClearDegraded()
            return
        end
        -- Suppressed ride: a re-drive is pointless -- the bars are dimmed and
        -- the exit edge re-drives for real. UNIT_FACTION fires on the boarding
        -- transition and funnels straight here, so this is the common path.
        -- Re-assert and stop.
        if vehicleHidden then
            ApplyVehicleHidden(true)
            return
        end
        -- Probe before acting (the RF regain model): a re-drive that lands
        -- while the player is STILL non-assistable re-bakes the degraded
        -- full-set parse, and if that was the last UNIT_FACTION edge nothing
        -- ever repairs it (field: full buff set stuck after cinematics).
        -- Degraded at this tick: stand the parents down and wait. No event
        -- marks "assistability restored" when the restore lags the event, so a
        -- settle watcher exists ONLY while degraded and self-cancels on the
        -- first clean probe. It deliberately never gives up: the stand-down is
        -- alpha-only now, so nothing else re-shows the bars, and a watcher that
        -- stopped early would leave them invisible for the rest of the session.
        -- Two C calls per quarter-second, and only while degraded.
        if not PabAssistProbe() then
            if not pabDegraded then
                pabDegraded = true
                ApplyVehicleHidden(vehicleHidden)
            end
            if not pabSettleTicker then
                pabSettleTicker = C_Timer.NewTicker(0.25, function()
                    if PabAssistProbe() then
                        pabSettleTicker:Cancel()
                        pabSettleTicker = nil
                        ReapplyAllAfterCinematic()
                    end
                end)
            end
            return
        end
        if pabSettleTicker then pabSettleTicker:Cancel(); pabSettleTicker = nil end
        if pabDegraded then
            -- Verified regain: un-dim here and force the re-parse below in the
            -- same execution, so no frame paints the stand-down's stale content.
            pabDegraded = false
            ApplyVehicleHidden(vehicleHidden)
        end
        ApplyLiveConfig(true)
        ApplyLiveConfig(false)
        -- Every custom bar, editing-spec buckets included: the recovery
        -- exists to repair engine-degraded candidate filters, and an active
        -- bucket bar degrades exactly like a legacy one.
        ReloadAllCustomBars()
        -- Force the re-parse outright. The config re-drive above cannot: a
        -- live group's candidate payload does not retake (see CandFP), and the
        -- engine caches membership per aura instance -- UNIT_AURA re-parses only
        -- what changed, so a spell-ID group parsed while the player was
        -- non-assistable keeps serving the full buff set until something marks a
        -- full rebuild. UpdateAllAuras is that lever (the same one the RF assist
        -- regain, UF player lane and CDM FakeActive use); the vehicle path only
        -- got it for free through the parents' Hide/Show. Bounded to this
        -- coalesced edge: one full parse per live container per cinematic edge.
        if buffsContainer then buffsContainer:UpdateAllAuras() end
        if debuffsContainer then debuffsContainer:UpdateAllAuras() end
        for _, c in pairs(customBuffContainers) do c:UpdateAllAuras() end
        for _, c in pairs(customDebuffContainers) do c:UpdateAllAuras() end
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        TryCreateBars()
        -- NOTE: recovery events are NOT registered here. ns.db is routinely
        -- absent during this same PLAYER_LOGIN dispatch (that is what
        -- TryCreateBars' retry loop exists for), so an enabled check taken
        -- synchronously reads nil and skips registration for enabled users.
        -- CreateBars calls ns.PAB_ArmRecovery() once it has confirmed the
        -- module is enabled -- login retry path and live enable both.
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if vehicleHidden then
            local probe = UnitUsingVehicle or UnitInVehicle
            if not probe("player") then
                SetVehicleHidden(false)
                ReapplyAllAfterCinematic()
            end
        end
        -- Editing-spec buckets: the login reload can run before
        -- GetSpecialization() answers, parking every bucket bar until the
        -- next spec change. Re-drive once per world entry (gated = one
        -- table read for profiles without buckets; idempotent otherwise).
        local s = PAB()
        if s and s.pabSpecBars then ReloadAllCustomBars() end
        return
    end
    if event == "UNIT_ENTERING_VEHICLE" or event == "UNIT_ENTERED_VEHICLE" then
        SetVehicleHidden(true)
        return
    end
    if event == "UNIT_EXITED_VEHICLE" then
        SetVehicleHidden(false)
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Editing-spec bucket bars activate/park with the spec. Gated to
        -- profiles that actually built buckets -- everyone else pays one
        -- table read per spec change. Unlock elements re-sync through the
        -- per-bar reload wrappers.
        local s = PAB()
        if s and s.pabSpecBars then
            ReloadAllCustomBars()
        end
        return
    end
    ReapplyAllAfterCinematic()
end)

-- Called by CreateBars once it has passed its own enabled check -- the only
-- point where "PAB is actually running" is known to be true (at PLAYER_LOGIN
-- ns.db may not exist yet; see the login handler note above). Idempotent:
-- CreateBars can run more than once per session (login retry, live enable).
local recoveryArmed = false
function ns.PAB_ArmRecovery()
    if recoveryArmed then return end
    recoveryArmed = true
    initFrame:RegisterEvent("CINEMATIC_STOP")
    -- Player-only registration: cinematics fire UNIT_FACTION for every unit;
    -- the player edge is the one that degrades these containers' filters.
    -- Also covers non-cinematic faction flips (Pandaren faction choice) --
    -- rare, and the re-drive is cheap.
    initFrame:RegisterUnitEvent("UNIT_FACTION", "player")
    -- Vehicles are the third trigger of the same class: boarding drops the
    -- player's assistability for the whole ride. The bars SUPPRESS for the
    -- duration (SetVehicleHidden) and the exit edge re-drives -- same
    -- trigger set as the RF assist gate and the UF player lane.
    initFrame:RegisterUnitEvent("UNIT_ENTERING_VEHICLE", "player")
    initFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    initFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    -- Safety net only: an exit that never fires EXITED (teleport out of a
    -- vehicle). Zero work on ordinary loading screens.
    initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Editing-spec buckets: bucket bars follow the player's spec (handler
    -- early-returns for profiles without buckets).
    initFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
end

