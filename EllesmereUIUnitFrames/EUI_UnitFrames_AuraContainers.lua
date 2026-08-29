if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_UnitFrames_AuraContainers.lua
-- 12.1 aura displays for unit frames: AuraKit containers replace the oUF aura
-- element for migrated units. This file is a pure VIEW over the existing
-- per-unit settings keys -- zero migration, every current option keeps working.
--
-- Classification model: the old element fetched with a broad base filter and
-- union-OR'd the class toggles per aura. Containers cannot OR filters, so each
-- class is its own group, made mutually exclusive with '!' negation, declared
-- once up-front (groups are add-only) and enabled by flipping maxFrameCount.
-- Known behavior deltas vs the old element (documented for patch notes):
--   * icon caps apply per enabled class, not as one total across the union
--   * sorting applies within each class group, not across all shown icons
--   * sated/always-hidden spellID excludes are inert on assistable units
--     (engine identity gate); enemy units filter exactly as before

local _, ns = ...

local AK -- EllesmereUI.AuraKit, resolved at first use (parent loads first)

local AURA_CROP_HEIGHT = 0.80
local AURA_ZOOM = 0.07
local FALLBACK_FONT = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

local SATED_DEBUFFS = {
    [57723] = true, [57724] = true, [80354] = true, [95809] = true,
    [160455] = true, [264689] = true, [390435] = true,
}
local ALWAYS_HIDE_DEBUFFS = {
    [1254550] = true, -- Arcane Empowerment
    [308312]  = true, -- Time Trial Practice
}

-- Filter classes (verified 12.1 vocabulary = AuraUtil.AuraFilters; IMPORTANT
-- does not exist as a token). Token classes become groups made mutually
-- exclusive by negating the ENABLED classes before them in priority order --
-- negating disabled classes would eat auras that belong to an enabled class
-- (union semantics, not chain semantics). Candidate classes are engine
-- boolean selectors that cannot be token-negated; they sit after the token
-- chain and may rarely duplicate an aura matching two candidate classes.
-- Because group filter strings are fixed at declaration (no group filter
-- setter exists), a change to the enabled set swaps in a fresh container.
local TOKEN_CLASSES = {
    { key = "raid",        token = "RAID",                    skey = "Raid" },
    { key = "raidcombat",  token = "RAID_IN_COMBAT",          skey = "RaidInCombat" },
    { key = "dispellable", token = "RAID_PLAYER_DISPELLABLE", skey = "Dispellable" },
    { key = "cc",          token = "CROWD_CONTROL",           skey = "CrowdControl" },
    { key = "bigdef",      token = "BIG_DEFENSIVE",           skey = "BigDefensive" },
    { key = "extdef",      token = "EXTERNAL_DEFENSIVE",      skey = "ExternalDefensive" },
    { key = "cancel",      token = "CANCELABLE",              skey = "Cancelable", buffOnly = true },
}
local CANDIDATE_CLASSES = {
    -- Player-frame only: debuffs not caused by ANY player or player pet (engine
    -- boolean, evaluated secret-safe engine-side). The legacy !PLAYER token this
    -- replaced only excluded YOUR casts; the boolean also drops other players' noise
    -- (Sated, Forbearance, gateway debuffs). Sits FIRST so the classes below take the
    -- complementary boolean and own the player-caused leftovers (mirrors the old
    -- PLAYER-token handoff; see BuildChain).
    { key = "nonplayer", cand = { isFromPlayerOrPlayerPet = false }, skey = "NonPlayer",
      debuffOnly = true, playerUnitOnly = true },
    { key = "bossaura", cand = { isBossAura = true },     skey = "BossAura",     debuffOnly = true },
    { key = "roleaura", cand = { isRoleAura = true },     skey = "RoleAura",     debuffOnly = true },
    -- Important: two Blizzard importance concepts, combined per unit in BuildChain. The
    -- class default (isPriorityAura) is the raid-frame priority curation -- the concept
    -- for debuffs on FRIENDLY units (the player frame and Player Aura Bars use it
    -- alone; Raid Frames' DebuffManager uses the same flag). Non-player frames
    -- (target/focus/boss -- dynamically friendly OR hostile) render BOTH: this group
    -- plus a second one for nameplateShowPersonal (the flag default nameplates display
    -- by, covering enemies), partitioned so a doubly-flagged aura renders once
    -- (PRIORITY_NONPLAYER_CAND). The IMPORTANT filter TOKEN is NOT usable for any of
    -- this: per AuraUtil.lua it flags HELPFUL auras (enemy-nameplate buff
    -- importance), so HARMFUL|IMPORTANT is an empty set.
    { key = "priority", cand = { isPriorityAura = true }, skey = "PriorityAura", debuffOnly = true },
    { key = "steal",    cand = { isStealable = true },    skey = "Stealable",    buffOnly = true },
    -- Any debuff carrying a dispel type (Magic/Curse/Disease/Poison/Bleed),
    -- regardless of whether the PLAYER can remove it -- distinct from the
    -- "dispellable" token above (RAID_PLAYER_DISPELLABLE, dispellable-by-you
    -- only). Same native set Raid Frames' DebuffManager verifies against
    -- Blizzard's source (EUI_RaidFrames_DebuffManager.lua's TYPED_DEBUFFS) --
    -- kept as this module's own copy rather than a cross-addon reference.
    -- Set-valued candidate (includeDispelTypes takes a SET table, not a
    -- boolean); rides the same cand-table merge as every class above.
    -- Offered by Player Aura Bars only: no per-unit options widget writes
    -- debuffDispelTyped, so ClassEnabled never turns it on for unit frames.
    { key = "dispeltyped",
      cand = { includeDispelTypes = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true } },
      skey = "DispelTyped", debuffOnly = true },
}

-- Shared with EllesmereUIUnitFrames_PlayerAuraBars.lua: same class vocabulary, same
-- mutual-exclusion semantics (token classes negate every enabled class before them;
-- candidate classes are engine-side selectors carried as candidate-filter tables, incl.
-- the nonplayer complementary handoff). One source of truth so a class addition/removal
-- here cannot silently drift from what Player Aura Bars offers.
ns.UF_TokenClasses = TOKEN_CLASSES
ns.UF_CandidateClasses = CANDIDATE_CLASSES

-- Important's SECOND group payload for NON-player frames (see the
-- priority class comment above): the nameplate-importance flag,
-- partitioned by isPriorityAura = false so an aura carrying BOTH flags
-- renders exactly once (the primary isPriorityAura group owns it). False-valued
-- candidate booleans are field-proven (Raid Frames DM subtract, the nonplayer handoff).
-- Static table: BuildChain runs per settings apply.
local PRIORITY_NONPLAYER_CAND = { nameplateShowPersonal = true, isPriorityAura = false }

-- Order-independent fingerprint of a candidate-filter table. Candidate payloads are
-- DECLARATION-FIXED on an existing group (field truth from the sibling modules:
-- SetAuraGroupCandidateFilters on a live group does not retake) -- so any payload
-- change must land in the group KEY and declare a fresh variant. Number-keyed sets
-- (spell ids) fingerprint as count:sum; string-keyed sets join outright.
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

-- The "priority" candidate payload (isPriorityAura), shared by the
-- non-player debuff modes below and the class vocabulary above.
local PRIORITY_CAND
for i = 1, #CANDIDATE_CLASSES do
    if CANDIDATE_CLASSES[i].key == "priority" then PRIORITY_CAND = CANDIDATE_CLASSES[i].cand end
end

-- Non-player DEBUFF filter (target/focus/boss): ONE single-select mode,
-- a pure VIEW over the legacy keys -- nothing is rewritten on update.
--   s.debuffFilterMode      explicit pick from the Debuff Filter dropdown
--   else derived:  Important + Own Only checked -> "importantOwn"
--                  Important checked            -> "important"
--                  Own Only checked             -> "own" (the boss default)
--                  nothing                      -> "all"
-- Tracked Auras never enter the derivation: they are ADDITIONAL tracking in
-- every mode (caster scope = the per-entry MINE tag, never the filter), and
-- only the explicit "tracked" mode makes them the whole display.
local MODE_VALID = {
    all = true, tracked = true, own = true,
    important = true, importantOwn = true, importantOrOwn = true,
}
local function HasActiveIncludes(s)
    local inc = s.debuffInclude
    if not inc then return false end
    for _, v in pairs(inc) do
        if v then return true end
    end
    return false
end
local function DebuffFilterMode(s)
    local m = s.debuffFilterMode
    if m and MODE_VALID[m] then return m end
    local own = s.onlyPlayerDebuffs == true
    if s.debuffPriorityAura == true then
        if own then return "importantOwn" end
        return "important"
    end
    if own then return "own" end
    return "all"
end
ns.UF_DebuffFilterMode = DebuffFilterMode
ns.UF_DebuffHasIncludes = HasActiveIncludes

-- Tracked Auras include links (target/focus/boss): the unit's explicit
-- always-show spells, additive in every mode. Caster scope lives in the
-- filter STRING, so the two scopes are two links: "inc" any caster,
-- "incmine" your casts (PLAYER). Boss entries default to your casts with an
-- any-caster OPT-OUT map (s.debuffIncludeAnyCaster); target/focus entries
-- default to any caster with a MINE OPT-IN map (s.debuffIncludeMine). Each
-- key embeds its id-set fingerprint so list/tag edits declare a fresh
-- variant (stale ones park at 0); the cand overrides BOTH spell-ID sets in
-- the config sweep -- includeSpellIDs = the actives, excludeSpellIDs = {}
-- so the shared excludes (which hide the actives from every OTHER group,
-- see ApplyGroupConfig) never blank these.
local function AppendIncludeLinks(chain, s, unit)
    local inc = s.debuffInclude
    if not inc then return end
    local isBoss = unit:match("^boss") ~= nil
    local anym = isBoss and s.debuffIncludeAnyCaster or nil
    local minem = (not isBoss) and s.debuffIncludeMine or nil
    local m, mm
    for id, v in pairs(inc) do
        if v then
            local mine
            if isBoss then
                mine = not (anym and anym[id])
            else
                mine = minem ~= nil and minem[id] == true
            end
            if mine then
                mm = mm or {}; mm[id] = true
            else
                m = m or {}; m[id] = true
            end
        end
    end
    if m then
        chain[#chain + 1] = { key = "inc|" .. CandFP({ includeSpellIDs = m }),
            tokens = { "HARMFUL" },
            cand = { includeSpellIDs = m, excludeSpellIDs = {} }, inc = true }
    end
    if mm then
        chain[#chain + 1] = { key = "incmine|" .. CandFP({ includeSpellIDs = mm }),
            tokens = { "HARMFUL", "PLAYER" },
            cand = { includeSpellIDs = mm, excludeSpellIDs = {} }, inc = true }
    end
end

-- Non-player DEBUFF chain: a fixed, mutually exclusive group set per mode.
-- Own Only is the PLAYER filter token (the isFromPlayerOrPlayerPet candidate
-- is identity-gated on hostile units; the token filters everywhere), and
-- "Important or Own" partitions with !PLAYER so an aura renders once.
-- Important covers both importance concepts (see PRIORITY_NONPLAYER_CAND).
-- Show All emits no include links: the catch-all already shows the tracked
-- spells, and ApplyGroupConfig leaves them un-excluded when no link renders
-- them. Only Tracked Auras with an empty list = an empty chain = nothing.
local function NonPlayerDebuffChain(s, unit)
    local mode = DebuffFilterMode(s)
    local chain = {}
    if mode == "all" then
        chain[1] = { key = "all", tokens = { "HARMFUL" } }
        return chain
    end
    if mode == "own" then
        chain[1] = { key = "own", tokens = { "HARMFUL", "PLAYER" } }
    elseif mode == "important" then
        chain[1] = { key = "priority",   tokens = { "HARMFUL" }, cand = PRIORITY_CAND }
        chain[2] = { key = "prioritynp", tokens = { "HARMFUL" }, cand = PRIORITY_NONPLAYER_CAND }
    elseif mode == "importantOwn" then
        chain[1] = { key = "priorityown",   tokens = { "HARMFUL", "PLAYER" }, cand = PRIORITY_CAND }
        chain[2] = { key = "prioritynpown", tokens = { "HARMFUL", "PLAYER" }, cand = PRIORITY_NONPLAYER_CAND }
    elseif mode == "importantOrOwn" then
        chain[1] = { key = "own",           tokens = { "HARMFUL", "PLAYER" } }
        chain[2] = { key = "priorityoth",   tokens = { "HARMFUL", "!PLAYER" }, cand = PRIORITY_CAND }
        chain[3] = { key = "prioritynpoth", tokens = { "HARMFUL", "!PLAYER" }, cand = PRIORITY_NONPLAYER_CAND }
    end
    AppendIncludeLinks(chain, s, unit)
    return chain
end

local function ClassEnabled(class, isBuff, s, unit)
    if class.buffOnly and not isBuff then return false end
    if class.debuffOnly and isBuff then return false end
    -- Player-frame-only classes: offered nowhere else in the UI, and a
    -- stale key on another unit's settings must have no effect.
    if class.playerUnitOnly and unit ~= "player" then return false end
    -- Non-player BUFF vocabulary is Stealable / Big Defensive / Dispellable only
    -- (zero-migration rule: retired checkbox keys go unread). Non-player DEBUFFS
    -- never reach the class system -- NonPlayerDebuffChain owns them.
    if isBuff and unit ~= "player" and class.key ~= "steal"
        and class.key ~= "bigdef" and class.key ~= "dispellable" then
        return false
    end
    local prefix = "debuff"
    if isBuff then prefix = "buff" end
    return s[prefix .. class.skey] == true
end

-- Hide-lane test (two-lane filter dropdowns): mirrors ClassEnabled's per-unit
-- vocabulary limits, reading the negative sets (s.buffNegClasses /
-- s.debuffNegClasses, keyed by class.skey). The options setters keep the two
-- lanes mutually exclusive; if stale data ever disagrees, show wins (the hidden
-- pass skips enabled classes).
local function ClassNegated(class, isBuff, s, unit)
    if class.buffOnly and not isBuff then return false end
    if class.debuffOnly and isBuff then return false end
    if class.playerUnitOnly and unit ~= "player" then return false end
    if isBuff and unit ~= "player" and class.key ~= "steal"
        and class.key ~= "bigdef" and class.key ~= "dispellable" then
        return false
    end
    local negs
    if isBuff then negs = s.buffNegClasses else negs = s.debuffNegClasses end
    return negs ~= nil and negs[class.skey] == true
end

local function BuildChain(base, isBuff, s, unit)
    -- Non-player DEBUFFS run the mode model (one dropdown value, see
    -- NonPlayerDebuffChain). The class chain below serves the non-player BUFF
    -- elements and the player frame's debuff legacy path (PlayerDebuffChain
    -- delegates here for the class-checkbox model).
    if not isBuff and unit ~= "player" then return NonPlayerDebuffChain(s, unit) end
    local chain, negations = {}, {}
    local subCand, negDispelTypes, npNegOwned

    -- HIDDEN PASS -- hide-lane classes join FIRST as parked links so their
    -- negations / forward excludes / inverted booleans reach every positive link
    -- (and the show-all catch-all below, when one is emitted). These link keys
    -- self-describe (tokens embedded, PlayerDebuffChain's convention) because
    -- their shapes change with the lane selection; with an empty hide lane this
    -- pass emits nothing and every legacy key below stays byte-identical.
    for i = 1, #TOKEN_CLASSES do
        local class = TOKEN_CLASSES[i]
        if ClassNegated(class, isBuff, s, unit) and not ClassEnabled(class, isBuff, s, unit) then
            local tokens = { base, class.token }
            for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
            chain[#chain + 1] = { key = class.key .. "|" .. table.concat(tokens, ""),
                tokens = tokens, hidden = true }
            negations[#negations + 1] = class.neg or ("!" .. class.token)
        end
    end
    for i = 1, #CANDIDATE_CLASSES do
        local class = CANDIDATE_CLASSES[i]
        local cc = class.cand
        if cc and ClassNegated(class, isBuff, s, unit) and not ClassEnabled(class, isBuff, s, unit) then
            -- Forward-capable candidate classes (dispeltyped's include map,
            -- nonplayer's complementary boolean) subtract through the hidden-link
            -- + forward-exclude route; pure boolean classes invert onto subCand
            -- (false-valued candidate booleans, field-proven).
            local forward = cc.includeDispelTypes ~= nil or cc.isFromPlayerOrPlayerPet ~= nil
            if forward then
                local tokens = { base }
                for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
                chain[#chain + 1] = { key = class.key .. "|" .. table.concat(tokens, ""),
                    tokens = tokens, cand = cc, hidden = true }
                if cc.includeDispelTypes then negDispelTypes = cc.includeDispelTypes end
                if cc.isFromPlayerOrPlayerPet == false then npNegOwned = true end
            else
                subCand = subCand or {}
                for k, v in pairs(cc) do
                    if type(v) == "boolean" then subCand[k] = not v end
                end
                -- Non-player "Important" renders through TWO groups (priority +
                -- prioritynp below); hiding it must exclude both faces.
                if class.key == "priority" and unit ~= "player" then
                    subCand.nameplateShowPersonal = false
                end
            end
        end
    end

    local lanesActive = #chain > 0 or subCand ~= nil
    -- Merge the hide lane's candidate-side exclusions over a positive/catch-all
    -- group's own cand (copy-on-write: the vocabulary tables are shared and must
    -- never be mutated). Identity-preserving no-op while the hide lane is empty.
    local function NegCand(baseCand)
        if not lanesActive then return baseCand end
        local out
        if baseCand then
            out = {}
            for k, v in pairs(baseCand) do out[k] = v end
        end
        if subCand then
            out = out or {}
            for k, v in pairs(subCand) do
                if out[k] == nil then out[k] = v end
            end
        end
        if negDispelTypes and not (out and out.includeDispelTypes) then
            out = out or {}
            out.excludeDispelTypes = negDispelTypes
        end
        if npNegOwned then
            out = out or {}
            if out.isFromPlayerOrPlayerPet == nil then out.isFromPlayerOrPlayerPet = true end
        end
        return out
    end
    -- Candidate payloads (and token sets) are declaration-fixed, so lane-shaped
    -- links need self-describing keys; legacy plain keys survive untouched
    -- configs byte-identically.
    local function LaneKey(key, tokens, cand)
        if not lanesActive then return key end
        return key .. "|" .. table.concat(tokens, "") .. "|" .. CandFP(cand)
    end

    -- POSITIVE PASS -- the legacy chain verbatim when the hide lane is empty
    -- (negations arrive pre-seeded with the hidden pass).
    for i = 1, #TOKEN_CLASSES do
        local class = TOKEN_CLASSES[i]
        if ClassEnabled(class, isBuff, s, unit) then
            local tokens = { base, class.token }
            for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
            local cand = NegCand(nil)
            chain[#chain + 1] = { key = LaneKey(class.key, tokens, cand), tokens = tokens, cand = cand }
            negations[#negations + 1] = class.neg or ("!" .. class.token)
        end
    end
    -- Non-Player exclusivity handoff: once the nonplayer class (boolean
    -- isFromPlayerOrPlayerPet = false) is in the chain, every later
    -- candidate class carries the complementary TRUE so the two sides
    -- partition instead of double-displaying (an aura is shown by exactly
    -- one group; candidate booleans cannot be token-negated).
    local npOwned = false
    for i = 1, #CANDIDATE_CLASSES do
        local class = CANDIDATE_CLASSES[i]
        if ClassEnabled(class, isBuff, s, unit) then
            local tokens = { base }
            for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
            local cand = class.cand
            if npOwned then
                local src = cand
                cand = {}
                for k, v in pairs(src) do cand[k] = v end
                cand.isFromPlayerOrPlayerPet = true
            end
            cand = NegCand(cand)
            chain[#chain + 1] = { key = LaneKey(class.key, tokens, cand), tokens = tokens, cand = cand }
            -- Important on non-player frames covers BOTH importance concepts (the
            -- unit's hostility is dynamic -- a target can be an ally or an enemy): a
            -- second group adds the nameplate-importance flag, partitioned against the
            -- primary isPriorityAura group (see PRIORITY_NONPLAYER_CAND). The nonplayer
            -- handoff never applies here (that class is player-frame only, so npOwned
            -- is always false off-player).
            if class.key == "priority" and unit ~= "player" then
                local pnp = NegCand(PRIORITY_NONPLAYER_CAND)
                chain[#chain + 1] = { key = LaneKey("prioritynp", tokens, pnp), tokens = tokens, cand = pnp }
            end
            if class.key == "nonplayer" then npOwned = true end
        end
    end

    -- Hide lane with NOTHING positive on a non-player unit: the legacy show-all
    -- fallback (plain "all" group, ApplyGroupConfig) cannot carry the negations,
    -- so an explicit catch-all link takes its place -- everything minus the hide
    -- lane. Player frames keep PAB semantics: nothing positive = show nothing.
    if lanesActive and unit ~= "player" then
        local hasPositive = false
        for i = 1, #chain do
            if not chain[i].hidden then hasPositive = true break end
        end
        if not hasPositive then
            local allTokens = { base }
            for n = 1, #negations do allTokens[#allTokens + 1] = negations[n] end
            local cand = NegCand(nil)
            chain[#chain + 1] = { key = LaneKey("nall", allTokens, cand), tokens = allTokens, cand = cand }
        end
    end
    return chain
end

-- One-shot lane split for the player frame's two-lane filter dropdowns (stamp on
-- the player unit's settings table; an imported older profile lacks the stamp and
-- re-splits). Broad-mode selections were SUBTRACTING under the old one-lane model --
-- move them to the hide lane (s.buffNegFilters / s.debuffNegClasses) so rendering
-- is bit-identical; add-mode selections already mean SHOW and stay put.
local function EnsurePlayerAuraLanes(s)
    if s.auraFilterLanesV1 then return end
    s.auraFilterLanesV1 = true
    if (s.buffShowAll ~= false or s.buffHasDuration == true)
        and s.buffFilters and next(s.buffFilters) then
        s.buffNegFilters = s.buffFilters
        s.buffFilters = nil
    end
    if s.debuffShowAll ~= false then
        local neg
        local function Move(list)
            for i = 1, #list do
                local class = list[i]
                if not class.buffOnly and s["debuff" .. class.skey] == true then
                    neg = neg or {}
                    neg[class.skey] = true
                    s["debuff" .. class.skey] = nil
                end
            end
        end
        Move(TOKEN_CLASSES)
        Move(CANDIDATE_CLASSES)
        if neg then s.debuffNegClasses = neg end
    end
end
ns.UF_EnsurePlayerAuraLanes = EnsurePlayerAuraLanes

-- Player-frame buffs run the Player Aura Bars content model (the shared
-- PAB_Filters registry + All Buffs / Has Duration / Own Only, two-lane
-- semantics -- identical dropdown, identical engine behavior; see the
-- player branch in EUI_UnitFrames_Options.lua's Buff Filter slot). Keys:
--   buffShowAll     (nil = on) -- All Buffs
--   buffFilters     ([filterId] = true, SHOW lane, shared ns.PAB_Filters registry)
--   buffNegFilters  ([filterId] = true, HIDE lane)
--   buffSpells      ({ spellID, ... } -- reserved for Extra Spells parity)
--   buffHasDuration (true = hide permanent buffs, candidate maxDuration)
-- Chain keys embed each link's candidate fingerprint: payload changes
-- declare fresh variants through the existing sig/declare machinery and
-- stale variants park at 0. Hide-lane filters SUBTRACT their resolved
-- spells via the catch-all's excludeSpellIDs in the broad modes and drop
-- out of the include group's union in add mode (Extra Spells win over the
-- hide lane). The legacy buff class checkboxes no longer apply to the
-- player frame (stale class keys stay inert); an empty chain = add mode
-- with nothing selected = show nothing, exactly like an empty Player Aura
-- Bar.
local pbImportEnsured
local function PlayerBuffChain(s)
    EnsurePlayerAuraLanes(s)
    if not pbImportEnsured
        and ((s.buffFilters and next(s.buffFilters))
            or (s.buffNegFilters and next(s.buffNegFilters))) then
        -- Selected registry filters (either lane) need the curated presets
        -- materialized (idempotent; normally PAB/options do this, but PAB can
        -- be disabled while the player frame still uses the registry).
        pbImportEnsured = true
        if ns.PAB_ImportBM2Filters then ns.PAB_ImportBM2Filters() end
    end
    -- Curated spell families (a primary plus its alts: rank/talent ids and
    -- multi-state buffs whose aura swaps spell ID as it advances) expand at
    -- resolution, exactly as PAB_ResolveSpells does for this same shared filter
    -- registry, so the player frame and Player Aura Bars agree on what a filter
    -- tracks. An explicit false in the owning filter wins.
    local function ExpandBuffFamily(set, id, blocked)
        local fam = ns.PAB_SPELL_FAMILY and ns.PAB_SPELL_FAMILY[id]
        if not fam then return end
        for i = 1, #fam do
            local m = fam[i]
            if not (blocked and blocked[m] == false) then set[m] = true end
        end
    end
    local chain = {}
    local dur = s.buffHasDuration == true
    -- All Buffs and Has Duration are mutually exclusive broad-content modes (the
    -- options setters enforce it): either one builds the catch-all -- Has Duration's is
    -- narrowed to duration-carrying buffs by maxDuration below -- and checked filters
    -- SUBTRACT from it. With neither on, filters ADD through the spells group.
    local broad = s.buffShowAll ~= false or dur
    -- Blacklist (Edit Blacklist in the Filters dropdown): applied exactly while the
    -- dropdown offers it -- All Buffs or Has Duration on -- and excluded from every
    -- content group below, so a blacklisted spell never displays.
    local bl
    if s.buffBlacklist and next(s.buffBlacklist) and broad then
        bl = s.buffBlacklist
    end
    if broad then
        local cand
        local ex
        if s.buffNegFilters then
            for filterId in pairs(s.buffNegFilters) do
                local f = ns.PAB_GetFilter and ns.PAB_GetFilter(filterId)
                if f and f.spells then
                    for id, on in pairs(f.spells) do
                        if on then
                            ex = ex or {}
                            ex[id] = true
                            ExpandBuffFamily(ex, id, f.spells)
                        end
                    end
                end
            end
        end
        if bl then
            ex = ex or {}
            for id in pairs(bl) do ex[id] = true end
        end
        if ex then cand = { excludeSpellIDs = ex } end
        if dur then
            cand = cand or {}
            cand.maxDuration = math.huge
        end
        chain[#chain + 1] = { key = "pball|" .. CandFP(cand), tokens = { "HELPFUL" }, cand = cand }
    end
    local inc, n
    if s.buffSpells then
        for i = 1, #s.buffSpells do
            local id = s.buffSpells[i]
            inc = inc or {}
            if not inc[id] then
                inc[id] = true
                n = (n or 0) + 1
            end
            ExpandBuffFamily(inc, id)
        end
    end
    if not broad and s.buffFilters then
        for filterId in pairs(s.buffFilters) do
            local f = ns.PAB_GetFilter and ns.PAB_GetFilter(filterId)
            if f and f.spells then
                for id, on in pairs(f.spells) do
                    if on then
                        inc = inc or {}
                        if not inc[id] then
                            inc[id] = true
                            n = (n or 0) + 1
                        end
                        ExpandBuffFamily(inc, id, f.spells)
                    end
                end
            end
        end
    end
    -- Add-mode hide lane: drop hidden filters' spells from the union. Direct
    -- Extra Spells (s.buffSpells) win over the hide lane.
    if not broad and inc and s.buffNegFilters then
        local direct
        if s.buffSpells then
            direct = {}
            for i = 1, #s.buffSpells do
                direct[s.buffSpells[i]] = true
                ExpandBuffFamily(direct, s.buffSpells[i])
            end
        end
        -- Hidden filters expand as families too, or one hidden id of a family
        -- would leak its siblings; direct Extra Spells still win.
        local hide = {}
        for filterId in pairs(s.buffNegFilters) do
            local f = ns.PAB_GetFilter and ns.PAB_GetFilter(filterId)
            if f and f.spells then
                for id, on in pairs(f.spells) do
                    if on then
                        hide[id] = true
                        ExpandBuffFamily(hide, id, f.spells)
                    end
                end
            end
        end
        for id in pairs(hide) do
            if not (direct and direct[id]) then inc[id] = nil end
        end
        if next(inc) == nil then inc = nil end
    end
    if inc then
        local cand = { includeSpellIDs = inc }
        if dur then cand.maxDuration = math.huge end
        if bl then
            local m = {}
            for id in pairs(bl) do m[id] = true end
            cand.excludeSpellIDs = m
        end
        chain[#chain + 1] = { key = "pbsp|" .. CandFP(cand), tokens = { "HELPFUL" }, cand = cand }
    end
    return chain
end

-- Player-frame debuffs run the Player Aura Bars debuff model (identical
-- dropdown, identical engine behavior; see the player branch of the
-- Debuff Filter slot in EUI_UnitFrames_Options.lua). Two-lane keys:
-- s.debuff<SKey> booleans = the SHOW lane (add mode via the legacy
-- class-chain model, which now also honors the hide lane through
-- BuildChain); s.debuffNegClasses = the HIDE lane, subtracting in both
-- modes -- under All Debuffs (s.debuffShowAll, nil = on) hidden classes
-- become parked links whose negations / forward excludes remove them from
-- the catch-all, and pure boolean classes invert onto the catch-all's
-- candidates (the shared complementary-boolean mechanism).
-- Link keys embed their token sets (token strings are declaration-fixed, same as
-- candidates) plus the catch-all's candidate fingerprint, so every payload shape
-- declares its own variant through the existing sig/declare machinery and stale
-- variants park at 0. The sated/ always-hide excludes ride the catch-all's DECLARED
-- candidates and its fingerprint.
local function PlayerDebuffChain(s)
    EnsurePlayerAuraLanes(s)
    if s.debuffShowAll == false then
        return BuildChain("HARMFUL", false, s, "player")
    end
    local chain, negations = {}, {}
    local subCand, excludeDispelTypes, npOwned
    local function Checked(class)
        if class.buffOnly then return false end
        local neg = s.debuffNegClasses
        return neg ~= nil and neg[class.skey] == true
    end
    for i = 1, #TOKEN_CLASSES do
        local class = TOKEN_CLASSES[i]
        if Checked(class) then
            local tokens = { "HARMFUL", class.token }
            for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
            chain[#chain + 1] = { key = class.key .. "|" .. table.concat(tokens, ""),
                tokens = tokens, hidden = true }
            negations[#negations + 1] = class.neg or ("!" .. class.token)
        end
    end
    for i = 1, #CANDIDATE_CLASSES do
        local class = CANDIDATE_CLASSES[i]
        local cc = class.cand
        if Checked(class) and cc then
            local forward = cc.includeDispelTypes ~= nil or cc.isFromPlayerOrPlayerPet ~= nil
            if forward then
                local tokens = { "HARMFUL" }
                for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
                chain[#chain + 1] = { key = class.key .. "|" .. table.concat(tokens, ""),
                    tokens = tokens, cand = cc, hidden = true }
                if cc.includeDispelTypes then excludeDispelTypes = cc.includeDispelTypes end
                if cc.isFromPlayerOrPlayerPet == false then npOwned = true end
            else
                subCand = subCand or {}
                for k, v in pairs(cc) do
                    if type(v) == "boolean" then subCand[k] = not v end
                end
            end
        end
    end
    local ex = {}
    for id in pairs(ALWAYS_HIDE_DEBUFFS) do ex[id] = true end
    for id in pairs(SATED_DEBUFFS) do ex[id] = true end
    local cand = { excludeSpellIDs = ex }
    if subCand then
        for k, v in pairs(subCand) do cand[k] = v end
    end
    if excludeDispelTypes then cand.excludeDispelTypes = excludeDispelTypes end
    if npOwned then cand.isFromPlayerOrPlayerPet = true end
    local allTokens = { "HARMFUL" }
    for n = 1, #negations do allTokens[#allTokens + 1] = negations[n] end
    chain[#chain + 1] = { key = "pdall|" .. table.concat(allTokens, "") .. "|" .. CandFP(cand),
        tokens = allTokens, cand = cand }
    return chain
end

local function ChainSignature(chain)
    local sig = {}
    for i = 1, #chain do sig[i] = chain[i].key end
    return table.concat(sig, ",")
end

-- [unitKey] = { frame, buffs, debuffs, dispel, sig = {buffs=,debuffs=} }.
-- Entries carry `building = true` while the deferred stepper is still
-- constructing them; every reload/refresh path skips building entries (the
-- stepper's final stage clears the flag and runs the first real reload).
local registry = {}

-- The PLAYER_LOGIN shell stash lived here until 68914 made container
-- creation combat-legal (/euit3 field PASS): builds now birth their own
-- shells inline wherever the job runs, combat included.

local function SettingsFor(unit)
    if ns.UF_GetSettings then return ns.UF_GetSettings(unit) end
    local db = ns.db
    if not db then return nil end
    local key = unit:match("^boss%d+$") and "boss" or unit
    return db.profile[key]
end

-- Anchor/growth tables: initial anchor, frame point + offset direction, and
-- the growth pair per anchor position.
local ANCHOR_IA = {
    topleft = "BOTTOMLEFT", topright = "BOTTOMRIGHT",
    bottomleft = "TOPLEFT", bottomright = "TOPRIGHT",
    left = "RIGHT", right = "LEFT",
}
local ANCHOR_FP = {
    topleft = { "TOPLEFT", 0, 1 }, topright = { "TOPRIGHT", 0, 1 },
    bottomleft = { "BOTTOMLEFT", 0, -1 }, bottomright = { "BOTTOMRIGHT", 0, -1 },
    left = { "LEFT", -1, 0 }, right = { "RIGHT", 1, 0 },
}
local AUTO_GROWTH = {
    topleft = { "RIGHT", "UP" }, topright = { "LEFT", "UP" },
    bottomleft = { "RIGHT", "DOWN" }, bottomright = { "LEFT", "DOWN" },
    left = { "LEFT", "DOWN" }, right = { "RIGHT", "DOWN" },
}
local EXPLICIT_GROWTH = {
    right = { "RIGHT", "UP" }, left = { "LEFT", "UP" },
    up = { "RIGHT", "UP" }, down = { "RIGHT", "DOWN" },
}

local function ResolveLayout(anchor, growth)
    anchor = anchor or "topleft"
    local ia = ANCHOR_IA[anchor] or "BOTTOMLEFT"
    local fp = ANCHOR_FP[anchor] or ANCHOR_FP.topleft
    local g
    if growth and growth ~= "auto" then g = EXPLICIT_GROWTH[growth] end
    g = g or AUTO_GROWTH[anchor] or AUTO_GROWTH.topleft
    return ia, fp[1], fp[2], fp[3], g[1], g[2]
end

-- Column cap from the growth SETTING string: explicit per-row cap wins;
-- explicit vertical growth = one column; anything else = unlimited row.
local function ResolveColumns(growth, maxCount, maxPerRow)
    if maxPerRow and maxPerRow >= 1 and maxPerRow < maxCount then return maxPerRow end
    if growth == "up" or growth == "down" then return 1 end
    return nil
end

local FLOWDIR = { RIGHT = nil, LEFT = nil, UP = nil, DOWN = nil } -- filled on first use
local function FlowDir(token)
    if FLOWDIR.RIGHT == nil then
        FLOWDIR.RIGHT = AnchorUtil.FlowDirection.Right
        FLOWDIR.LEFT = AnchorUtil.FlowDirection.Left
        FLOWDIR.UP = AnchorUtil.FlowDirection.Up
        FLOWDIR.DOWN = AnchorUtil.FlowDirection.Down
    end
    return FLOWDIR[token]
end

-- zoom (optional) overrides the default AURA_ZOOM crop; per-unit/per-category
-- Icon Zoom values flow in here, defaulting to AURA_ZOOM so unset = unchanged.
local function CropCoords(cropped, w, h, zoom)
    local z = zoom or AURA_ZOOM
    if cropped and w and h and w > 0 then
        local uSpan = 1 - 2 * z
        local vSpan = uSpan * (h / w)
        local v0 = 0.5 - vSpan / 2
        return { z, 1 - z, v0, 1 - v0 }
    end
    return { z, 1 - z, z, 1 - z }
end

local STACK_POINTS = {
    bottomright = { "BOTTOMRIGHT", -1 }, bottomleft = { "BOTTOMLEFT", 1 },
    topright = { "TOPRIGHT", -1 }, topleft = { "TOPLEFT", 1 },
    center = { "CENTER", 0 },
}

local function CK(c)
    if not c then return "-" end
    return string.format("%.3f,%.3f,%.3f",
        c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0)
end

-- Module text pass: fonts through the shared icon-text pipeline (outline slug
-- rules live there), duration text centered like cooldown countdown text.
-- Restyles hit every registered button, so SetFont is change-guarded (it
-- costs real time even with identical values; font key = path|size, so an
-- outline-only module font change slips until a size touch -- accepted,
-- same as the RF pass). The duration string is ALWAYS fonted, hidden or
-- not: the engine SetText()s every registered duration string on display
-- updates, and an unfonted FontString hard-errors inside that engine call
-- (visibility is handled by AuraKit via SetShown). Text color is likewise
-- change-guarded via CK() fingerprints (d.ufDurColor/d.ufStackColor) --
-- SetTextColor costs real time too, same reasoning as the font guard above.
local function ApplyUFText(button, d, style)
    local path = style.fontPath or FALLBACK_FONT
    if d.duration then
        local fontKey = path .. "|" .. (style.cdTextSize or 10)
        if d.ufDurFont ~= fontKey then
            d.ufDurFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.duration, path, style.cdTextSize or 10, "unitFrames")
        end
        local c = style.cdTextColor
        local cKey = CK(c)
        if d.ufDurColor ~= cKey then
            d.ufDurColor = cKey
            d.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        end
        -- Anchor change-guarded (stamp AFTER the calls): SetPoint with the
        -- button as the relative frame is policed by the 12.1 button access
        -- restriction while auras are secret; unchanged offsets must make
        -- zero button-involving calls so restyles stay live in-instance.
        local aKey = (style.cdOffX or 0) .. "|" .. (style.cdOffY or 0)
        if d.ufDurAnchor ~= aKey then
            d.duration:ClearAllPoints()
            d.duration:SetPoint("CENTER", button, "CENTER", style.cdOffX or 0, style.cdOffY or 0)
            d.ufDurAnchor = aKey
        end
        -- Duration formatter options are registered once when an AuraKit button
        -- is created. Re-register when the user changes the precision threshold;
        -- a normal style restyle alone does not change the engine binding.
        -- SAME stamp key + shape as MakeInitializer's creation write ("b" --
        -- UF styles never set durationShowSeconds -- plus the threshold), so
        -- untouched configs compare equal to the creation stamp and never
        -- rebind: zero cost while the feature is off.
        local wantFmt = "b" .. tostring(style.durationPrecisionThreshold or 0)
        if d.durationFmtS ~= wantFmt then
            local AK = EllesmereUI.AuraKit
            local opts = AK.BuildDurationTextOpts(
                AK.GetDurationFormatter(nil, style.durationPrecisionThreshold))
            local ok = AK.SetDurationTextSafe(button, d.duration, opts)
            if ok then d.durationFmtS = wantFmt end
        end
    end
    if d.stack then
        local fontKey = path .. "|" .. (style.stackSize or 14)
        if d.ufStackFont ~= fontKey then
            d.ufStackFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.stack, path, style.stackSize or 14, "unitFrames")
        end
        local c = style.stackColor
        local cKey = CK(c)
        if d.ufStackColor ~= cKey then
            d.ufStackColor = cKey
            d.stack:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        end
        local sp = STACK_POINTS[style.stackPos or "bottomright"] or STACK_POINTS.bottomright
        local sKey = sp[1] .. "|" .. (sp[2] + (style.stackOffX or 0)) .. "|" .. (style.stackOffY or 0)
        if d.ufStackAnchor ~= sKey then
            d.stack:ClearAllPoints()
            d.stack:SetPoint(sp[1], button, sp[1], sp[2] + (style.stackOffX or 0), style.stackOffY or 0)
            d.ufStackAnchor = sKey
        end
    end
end

local function StyleKey(unit, base)
    return "uf:" .. unit .. ":" .. base
end

-- Settings fingerprints (same discipline as the RF containers file): every
-- engine setter is a dirty mark that costs real engine work even when the
-- value is unchanged, and a restyle touches every pre-created button of the
-- style (10-button engine batches per group add up fast). Reload paths
-- fingerprint what each pass reads and skip the work whose inputs did not
-- change. Numbers round to 2 decimals: scaled values carry float noise.
local ufFP = {}

local function FP(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "number" then
            t[i] = string.format("%.2f", v)
        else
            t[i] = tostring(v)
        end
    end
    return table.concat(t, "|")
end

-- Fingerprint of a BUILT style table (BuildStyle is a pure function of the settings, so
-- hashing its scalar output covers every input, including the boss-simple sizing and
-- scale). Constant cooldown/cancel fields are omitted; every user-configurable border
-- scalar must participate so layer-only edits schedule an immediate AuraKit restyle.
local function StyleTableFP(st, font)
    local tc = st.texCoord
    local b = st.border
    return FP(font, st.width, st.height, tc[1], tc[2], tc[3], tc[4],
        st.hideDurationText, st.durationPrecisionThreshold, st.cdTextSize, CK(st.cdTextColor), st.cdOffX, st.cdOffY,
        st.stackSize, CK(st.stackColor), st.stackPos, st.stackOffX, st.stackOffY,
        b and b.texture, b and b.size, b and b[1], b and b[2], b and b[3], b and b[4],
        b and b.offsetX, b and b.offsetY, b and b.shiftX, b and b.shiftY,
        b and b.behind, b and b.behindUnitFrame, b and b.unitFrameLevel,
        st.noTooltips)
end

-- Declares one chain group and records it in the element's declared-set
-- registry (filter strings are declaration-fixed, so every distinct token set
-- is its own group; containers are never swapped -- the ever-used set
-- accumulates and inactive groups sit at count 0). Used at creation and by
-- the additive reload path (AddAuraGroup on an existing container is
-- combat-legal -- probe T1/T1b).
local function DeclareElementGroup(container, declared, styleKey, key, tokens, cand)
    AK.AddGroupToContainer(container, {
        key = key, filter = tokens, maxFrameCount = 0, style = styleKey,
        -- Candidates ride the declaration too: payloads are declaration- fixed on a
        -- live group, and the player-buff chain keys embed a candidate fingerprint
        -- precisely so a changed payload arrives here as a fresh variant (the config
        -- pass still live-sets candidates on top for the shared debuff excludes).
        candidateFilters = cand or nil,
    })
    declared[key] = { cand = cand or false }
end

-- Explicit either/or (never `cond and a or b`: a falsy setting must not fall
-- through to the other element's key).
local function Pick(isBuff, a, b)
    if isBuff then return a end
    return b
end

-- Boss "simple" side display: returns whether it is on and which side.
local function BossSimple(unit, base, s)
    if not unit:match("^boss") then return false, "none" end
    local mode
    if base == "HELPFUL" then
        mode = ns.GetBossSimpleBuffMode and ns.GetBossSimpleBuffMode(s) or "none"
    else
        mode = ns.GetBossSimpleDebuffMode and ns.GetBossSimpleDebuffMode(s) or "none"
    end
    return mode ~= "none", mode
end

-- Element pixel size; boss simple mode matches the frame's bar-stack height.
local function ElementSize(unit, base, s)
    local isBuff = (base == "HELPFUL")
    local size = Pick(isBuff, s.buffSize, s.debuffSize) or 22
    local simpleOn = BossSimple(unit, base, s)
    if simpleOn then
        local PP = EllesmereUI.PP
        local powerPos = s.powerPosition or "below"
        local powerH = 0
        if powerPos == "below" or powerPos == "above" then powerH = s.powerHeight or 0 end
        size = PP.Scale((s.healthHeight or 0) + powerH)
    end
    local cropped = Pick(isBuff, s.buffCropIcons, s.debuffCropIcons)
    local h = size
    if cropped then h = math.floor(size * AURA_CROP_HEIGHT + 0.5) end
    return size, h, cropped
end

local function BuildStyle(unit, base, s, unitFrame)
    local isBuff = (base == "HELPFUL")
    local size, h, cropped = ElementSize(unit, base, s)
    local p = Pick(isBuff, "buff", "debuff")

    -- Boss simple side displays read their own cooldown-text keys.
    local simpleOn = BossSimple(unit, base, s)
    local showCdKey, cdSizeKey = p .. "ShowCooldownText", p .. "CooldownTextSize"
    local cdSizeDefault = 10
    if simpleOn then
        showCdKey = "simple" .. p:gsub("^%l", string.upper) .. "ShowCooldownText"
        cdSizeKey = "simple" .. p:gsub("^%l", string.upper) .. "CooldownTextSize"
        cdSizeDefault = 14
    end

    return {
        width = size,
        height = h,
        texCoord = CropCoords(cropped, size, h, Pick(isBuff, s.buffIconZoom, s.debuffIconZoom)),
        border = {
            s.auraBorderR or 0, s.auraBorderG or 0, s.auraBorderB or 0, s.auraBorderA or 1,
            size = s.auraBorderSize or 1,
            texture = s.auraBorderTexture or "solid",
            offsetX = s.auraBorderTextureOffset,
            offsetY = s.auraBorderTextureOffsetY,
            shiftX = s.auraBorderTextureShiftX,
            shiftY = s.auraBorderTextureShiftY,
            behind = s.auraBorderBehind,
            behindUnitFrame = s.auraBorderBehindUnitFrame,
            unitFrameLevel = unitFrame and unitFrame:GetFrameLevel() or 1,
        },
        cooldownReverse = true,
        cooldownDrawEdge = false,
        noDefaultFonts = true,
        hideDurationText = not s[showCdKey],
        durationPrecisionThreshold = tonumber(s[p .. "CooldownTextPrecision"]),
        cdTextSize = s[cdSizeKey] or cdSizeDefault,
        cdTextColor = s[p .. "CooldownTextColor"],
        cdOffX = s[p .. "CooldownTextOffsetX"] or 0,
        cdOffY = s[p .. "CooldownTextOffsetY"] or 0,
        stackSize = s[p .. "StackTextSize"] or 14,
        stackColor = s[p .. "StackTextColor"],
        stackPos = s[p .. "StackTextPosition"],
        stackOffX = s[p .. "StackTextOffsetX"] or 0,
        stackOffY = s[p .. "StackTextOffsetY"] or 0,
        cancelButtons = (unit == "player" and isBuff) and "RightButtonUp" or nil,
        -- Show Tooltip For -> Buffs & Debuffs (per-unit, default on). Motion
        -- goes off with the tooltips; clicks (player buff cancel) unaffected.
        noTooltips = (s.showAuraTooltips == false) or nil,
        -- Dispel-type border recolor (per-unit debuffDispelBorder): the engine
        -- shows the ring only on typed (dispellable) debuffs and picks the
        -- dispel color itself -- the user palette cannot apply under secrecy
        -- (same documented delta as the RF debuff border).
        dispelBorder = (not isBuff and s.debuffDispelBorder) and true or nil,
        -- Resolved once per (fingerprint-gated) style rebuild instead of on
        -- every ApplyUFText call -- GetFontPath's result only changes when
        -- font settings change, which already forces a fresh style table.
        fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or FALLBACK_FONT,
        applyExtra = ApplyUFText,
    }
end

-- Does the unit's cast bar occupy the strip directly below the frame -- the
-- space a bottom-anchored aura stack would otherwise take? Answered from LIVE
-- GEOMETRY, not from "has the user ever moved it": a bar that was free-moved in
-- unlock mode but still parks under its frame (the common case) keeps the
-- reserve, and only a bar genuinely somewhere else drops it.
--
-- The previous rule read ns.db, which is assigned one frame LATER than every
-- other input here (SetupOptionsPanel runs off C_Timer.After(0), while the
-- settings come from ns.UF_GetSettings, live since frame creation). Whether the
-- deferred container build landed before or after that frame decided the answer,
-- so the reserve differed between a cold login and a /reload with identical
-- saved data.
--
-- Fails toward KEEPING the reserve: no frame, no bounds yet (pre-layout) or a
-- unit with no movable cast bar of its own (boss) all answer true, which is what
-- the bottom-anchor path did before. The saved cast bar position lands on the
-- unlock system's deferred pass, so the settle timers further down re-run this
-- once the bar is actually where the user put it.
local CB_STRIP_SLACK = 8 -- physical pixels of tolerance on the strip's edges
local CB_FRAME_NAMES = {
    player = "EllesmereUIUnitFrames_Player",
    target = "EllesmereUIUnitFrames_Target",
    focus  = "EllesmereUIUnitFrames_Focus",
}
local function CastbarBelowFrame(unit, frame)
    if not CB_FRAME_NAMES[unit] then return true end
    frame = frame or _G[CB_FRAME_NAMES[unit]]
    -- frame.Castbar is the status bar; its PARENT is the holder the unlock
    -- system moves (see CreateCastBar in EllesmereUIUnitFrames.lua).
    local cb = frame and frame.Castbar and frame.Castbar:GetParent()
    if not cb then return true end
    local fl, fr, fb = frame:GetLeft(), frame:GetRight(), frame:GetBottom()
    local cl, cr, ct, cbot = cb:GetLeft(), cb:GetRight(), cb:GetTop(), cb:GetBottom()
    if not (fl and fr and fb and cl and cr and ct and cbot) then return true end
    -- Physical pixels: the holder is positioned independently of the frame and
    -- can carry its own effective scale, so raw coordinates are not comparable.
    local fs, cs = frame:GetEffectiveScale(), cb:GetEffectiveScale()
    fl, fr, fb = fl * fs, fr * fs, fb * fs
    cl, cr, ct, cbot = cl * cs, cr * cs, ct * cs, cbot * cs
    -- Beside the frame rather than under it: nothing to reserve.
    if cl >= fr or cr <= fl then return false end
    -- How far the bar's top edge hangs below the frame's bottom: 0 is flush, a
    -- hand-aligned bar is a few pixels either way. The reserve itself is a fixed
    -- -castbarHeight, so it only ever clears a bar sitting AT the frame's edge;
    -- once the drop reaches a full bar height the reserve would park the icons
    -- on top of the bar rather than above it, so the stack docks to the frame
    -- instead. Overlap into the frame stays allowed within the tolerance.
    local h = ct - cbot
    if h <= 0 then h = 14 end
    local drop = fb - ct
    return drop < h and drop >= -CB_STRIP_SLACK
end
ns.UF_CastbarBelowFrame = CastbarBelowFrame
-- Cross-addon: the options preview mirrors this decision so its layout matches
-- the live frames (EllesmereUIOptions/EUI_UnitFrames_Options.lua).
EllesmereUI.UF_CastbarBelowFrame = CastbarBelowFrame

-- Container anchoring: mirrors the legacy element's SetPoint(ia, frame, fp,
-- ox + userX, oy + castbarPush + userY) with gap = 1.
-- buffContainer (HARMFUL calls only): the unit's buff container, needed by
-- the Anchor Buffs with Debuffs mode below.
local function AnchorContainer(container, frame, unit, base, s, buffContainer)
    local isBuff = (base == "HELPFUL")

    -- Boss simple side display: forced side anchoring flush with the frame
    -- top, growing away from the chosen edge, own offsets, no castbar push.
    local simpleOn, simpleMode = BossSimple(unit, base, s)
    if simpleOn then
        local ia, fp
        if simpleMode == "right" then ia, fp = "TOPLEFT", "TOPRIGHT" else ia, fp = "TOPRIGHT", "TOPLEFT" end
        local offX, offY
        if isBuff then
            offX, offY = ns.GetBossSimpleBuffOffset(s)
        else
            offX, offY = ns.GetBossSimpleDebuffOffset(s)
        end
        container:ClearAllPoints()
        container:SetPoint(ia, frame, fp, offX or 0, offY or 0)
        AK.SetContainerAnchor(container, ia)
        local gX = "LEFT"
        if simpleMode == "right" then gX = "RIGHT" end
        AK.SetContainerGrowth(container, FlowDir(gX), FlowDir("DOWN"))
        return simpleMode
    end

    local anchor = Pick(isBuff, s.buffAnchor, s.debuffAnchor)
    if anchor == nil then anchor = Pick(isBuff, "topleft", "none") end

    -- Anchor Buffs with Debuffs (per-unit debuffAnchorBuffs, non-boss):
    -- buffs adopt the debuff anchor/growth/offsets and become the stack's first rows;
    -- the debuff container then rides the BUFF CONTAINER's leading edge. The engine
    -- re-sizes that container to its rows every layout pass, so the push is
    -- engine-driven -- full rows only, and no aura reads (secret-safe in combat). The
    -- merge OWNS buff visibility: it renders buffs even with Buff Display at None
    -- (showBuffs false), which is the state the options auto-select on enable.
    local merged = s.debuffAnchorBuffs == true and not unit:match("^boss")
        and (s.debuffAnchor or "none") ~= "none"
    local mergedBuff = merged and isBuff
    if mergedBuff then anchor = s.debuffAnchor end
    if anchor == "none" then
        -- Player buffs hidden: retire the weapon-enchant lead strip too.
        if unit == "player" and isBuff and ns._weaponEnchUF then
            ns._weaponEnchUF = nil
            if ns.WeaponEnchants_Layout then ns.WeaponEnchants_Layout() end
        end
        return anchor
    end

    local growth = Pick(isBuff, s.buffGrowth, s.debuffGrowth)
    if mergedBuff then growth = s.debuffGrowth end
    local ia, fp, ox, oy, gX, gY = ResolveLayout(anchor, growth)

    local cbOff = 0
    local showCb, cbH
    if unit == "player" then
        showCb, cbH = s.showPlayerCastbar, s.playerCastbarHeight
    else
        showCb, cbH = s.showCastbar, s.castbarHeight
    end
    -- Bottom anchors ONLY: they stack below the frame, where an attached cast
    -- bar hangs, so they reserve its height. Side anchors (left/right) are
    -- vertically CENTERED on the frame and clear the bar by construction --
    -- including them here pushed centered icons DOWN by the full bar height
    -- (field case: boss left-anchored debuffs sat ~castbarHeight low). The
    -- oUF-element anchor path has always been bottom-only; this matches it.
    if showCb and (anchor == "bottomleft" or anchor == "bottomright")
        and CastbarBelowFrame(unit, frame) then
        if not cbH or cbH <= 0 then cbH = 14 end
        cbOff = -cbH
    end

    local offX = Pick(isBuff, s.buffOffsetX, s.debuffOffsetX) or 0
    local offY = Pick(isBuff, s.buffOffsetY, s.debuffOffsetY) or 0
    if mergedBuff then
        offX = s.debuffOffsetX or 0
        offY = s.debuffOffsetY or 0
    end

    container:ClearAllPoints()
    if merged and not isBuff and buffContainer then
        -- Ride the buff container: horizontal side from the layout anchor,
        -- vertical side from the wrap direction, one debuff line-gap
        -- between the blocks. Debuffs never share a row with buffs.
        local PP = EllesmereUI.PP
        local horiz = ""
        if ia:find("LEFT") then horiz = "LEFT" elseif ia:find("RIGHT") then horiz = "RIGHT" end
        local vert, relVert, gapSign
        if gY == "UP" then
            vert, relVert, gapSign = "BOTTOM", "TOP", 1
        else
            vert, relVert, gapSign = "TOP", "BOTTOM", -1
        end
        local gap = PP.FromPixels(s.debuffSpacingY or 1)
        container:SetPoint(vert .. horiz, buffContainer, relVert .. horiz, 0, gap * gapSign)
        AK.SetContainerAnchor(container, vert .. horiz)
    else
        -- Side anchors ("left"/"right") pin the container's vertical CENTER to
        -- the frame's LEFT/RIGHT point -- a center-class axis. An odd-physical-
        -- pixel frame height parks that center on a half pixel, so every icon
        -- edge lands on X.5: the icon texture (default pixel snapping) rounds
        -- to whole pixel rows while the snap-disabled 1px border strips
        -- straddle two rows at the true fractional edges -- the icon visibly
        -- bleeds past the border. Standing parity rule (see the pixel-perfect
        -- half-pixel conventions): the perpendicular axis of an edge anchor
        -- snaps via SnapCenterForDim against the ELEMENT dimension. Correct
        -- offY so the row's center sits on the parity grid for the icon size.
        -- Reading our own frame's live geometry is legal under aura
        -- restriction; nil (pre-layout window) keeps the raw offset and a
        -- later anchor pass corrects it.
        if anchor == "left" or anchor == "right" then
            local PP = EllesmereUI.PP
            if PP and PP.SnapCenterForDim and PP.SnapForES then
                local es = container:GetEffectiveScale()
                local _, fcY = frame:GetCenter()
                if fcY then
                    local iconH = Pick(isBuff, s.buffSize, s.debuffSize) or 22
                    local rawY = fcY + oy + cbOff + offY
                    offY = offY + (PP.SnapCenterForDim(rawY, iconH, es) - rawY)
                end
                -- Growth (horizontal) axis is EDGE-class: the container's edge
                -- pins to the frame's edge, so the absolute X snaps to a whole
                -- physical pixel (SnapForES). A fractional frame edge otherwise
                -- lands every icon's vertical edges on partial pixels -- same
                -- bleed as the parity case, on the left/right borders. Integer
                -- icon widths keep the far edge whole once this edge is.
                local fx = (anchor == "left") and frame:GetLeft() or frame:GetRight()
                if fx then
                    local rawX = fx + ox + offX
                    offX = offX + (PP.SnapForES(rawX, es) - rawX)
                end
            end
        end
        container:SetPoint(ia, frame, fp, ox + offX, oy + cbOff + offY)
        AK.SetContainerAnchor(container, ia)
        if unit == "player" and isBuff then
            -- Weapon enchant lead icons (oils/imbues are not auras; see
            -- EUI_UnitFrames_WeaponEnchants.lua): ride the SAME resolved
            -- anchor as the player's buff container so the strip leads it.
            -- Published only while the broad-content mode admits generic
            -- duration buffs (All Buffs or Has Duration -- the catch-all
            -- gate) AND the buff display itself is on; renders with the
            -- container's live style so customizations follow.
            local broad = s.buffShowAll ~= false or s.buffHasDuration == true
            local shownBuffs = (s.showBuffs ~= false)
                or (s.debuffAnchorBuffs == true and (s.debuffAnchor or "none") ~= "none")
            if broad and shownBuffs then
                ns._weaponEnchUF = { frame = frame, ia = ia, fp = fp,
                    x = ox + offX, y = oy + cbOff + offY, gX = gX,
                    pad = EllesmereUI.PP.FromPixels(s.buffSpacingX or 1),
                    styleKey = StyleKey("player", "HELPFUL") }
                -- Shift the engine run inward past the enchant cells (main
                -- hand adjacent to the run; zero enchants = zero shift).
                local n = (ns.WeaponEnchants_Count and ns.WeaponEnchants_Count()) or 0
                if n > 0 then
                    local st = AK.styles[StyleKey("player", "HELPFUL")]
                    local w = (st and st.width) or 22
                    local sign = (gX == "RIGHT") and 1 or -1
                    local shift = sign * n * (w + EllesmereUI.PP.FromPixels(s.buffSpacingX or 1))
                    container:ClearAllPoints()
                    container:SetPoint(ia, frame, fp, ox + offX + shift, oy + cbOff + offY)
                end
            else
                ns._weaponEnchUF = nil
            end
            if ns.WeaponEnchants_Layout then ns.WeaponEnchants_Layout() end
        end
    end
    AK.SetContainerGrowth(container, FlowDir(gX), FlowDir(gY))

    return anchor
end

local function ApplyGroupConfig(container, unit, base, s, chain, declared)
    local PP = EllesmereUI.PP
    local isBuff = (base == "HELPFUL")
    local anyClass = #chain > 0

    local simpleOn = BossSimple(unit, base, s)

    -- Anchor Buffs with Debuffs: the merge owns buff visibility (Buff
    -- Display reads None while the stack renders the buffs), and the buff
    -- groups wrap like the debuff stack they join.
    local mergedAB = s.debuffAnchorBuffs == true and not unit:match("^boss")
        and (s.debuffAnchor or "none") ~= "none"

    local shown
    if isBuff then
        shown = (s.showBuffs ~= false) or simpleOn or mergedAB
    else
        shown = ((s.debuffAnchor or "none") ~= "none") or simpleOn
    end

    local num = 0
    if shown then
        num = Pick(isBuff, s.maxBuffs or 4, s.maxDebuffs or 28)
    end

    local size, h = ElementSize(unit, base, s)
    local spX, spY
    if unit:match("^boss") then
        -- Boss uses a single spacing value (its simple-display key when the
        -- simple mode is active).
        local sp
        if isBuff then sp = ns.GetBossBuffSpacing(s, simpleOn) else sp = ns.GetBossDebuffSpacing(s, simpleOn) end
        spX = PP.FromPixels(sp or 1)
        spY = spX
    else
        spX = PP.FromPixels(Pick(isBuff, s.buffSpacingX, s.debuffSpacingX) or 1)
        spY = PP.FromPixels(Pick(isBuff, s.buffSpacingY, s.debuffSpacingY) or 1)
    end

    local growth = Pick(isBuff, s.buffGrowth, s.debuffGrowth)
    if simpleOn then growth = "auto" end
    if mergedAB and isBuff then growth = s.debuffGrowth end
    local maxPerRow = Pick(isBuff, s.buffMaxPerRow, s.debuffMaxPerRow)
    local cols = ResolveColumns(growth, num > 0 and num or 1, maxPerRow)
    local rowWidth = nil
    if cols then
        rowWidth = cols * size + (cols - 1) * spX + 0.4
    end
    AK.SetContainerRowWidth(container, rowWidth)

    -- Candidate filters: (debuffs) the sated/always-hide excludes. Caster
    -- scope rides the chain links' own PLAYER tokens, never this table.
    local cand = nil
    if not isBuff then
        local ex = {}
        for id in pairs(ALWAYS_HIDE_DEBUFFS) do ex[id] = true end
        for id in pairs(SATED_DEBUFFS) do ex[id] = true end
        -- Tracked Auras (target/focus/boss): user excludes hide everywhere; active
        -- INCLUDES are excluded from every OTHER group while an include link renders
        -- them (its own cand overrides both spell-ID sets). Show All carries no
        -- include link, so its catch-all keeps them. Player units carry neither key.
        local uex = s.debuffExclude
        if uex then
            for id, v in pairs(uex) do if v then ex[id] = true end end
        end
        local uinc = s.debuffInclude
        if uinc then
            local incLink = false
            for i = 1, #chain do
                if chain[i].inc then incLink = true break end
            end
            if incLink then
                for id, v in pairs(uinc) do if v then ex[id] = true end end
            end
        end
        cand = cand or {}
        cand.excludeSpellIDs = ex
    end

    local layout = { elementWidth = size, elementHeight = h, elementSpacing = spX, lineSpacing = spY }

    -- Active set = "all" (a non-player BUFF element with no classes enabled)
    -- or each chain link. Every other declared group -- disabled classes and
    -- retired variants -- parks at count 0 (declared sets only ever grow;
    -- setters run per declared key only).
    local active, hiddenKeys = {}, nil
    if num > 0 then
        if anyClass then
            for i = 1, #chain do
                local c = chain[i]
                active[c.key] = c.cand or false
                -- Subtracted classes (the player PAB model) stay declared
                -- so their negations keep them out of the catch-all, but
                -- render nothing themselves.
                if c.hidden then
                    hiddenKeys = hiddenKeys or {}
                    hiddenKeys[c.key] = true
                end
            end
        elseif isBuff and unit ~= "player" then
            -- Non-player buffs keep the legacy show-all fallback (no classes =
            -- everything). Player elements run the PAB content model (an empty
            -- chain = add mode with nothing selected = show nothing), and
            -- non-player debuff chains carry their catch-all explicitly (Show
            -- All) or mean nothing at all (Only Tracked Auras, empty list).
            active.all = false
        end
    end
    for eff, info in pairs(declared) do
        if active[eff] ~= nil then
            container:SetAuraGroupMaxFrameCount(eff, (hiddenKeys and hiddenKeys[eff]) and 0 or num)
            local groupCand = cand
            -- Candidate-class groups carry their defining booleans on top of the shared
            -- candidates (fresh table: setter securecopies). Read from the CURRENT
            -- chain (active), not the declared registry: the Non-Player handoff changes
            -- a class's boolean set when the enabled set changes, and groups persist
            -- across those toggles (declared sets only ever grow).
            local ac = active[eff]
            if ac then
                groupCand = {}
                if cand then
                    for k, v in pairs(cand) do groupCand[k] = v end
                end
                for k, v in pairs(ac) do groupCand[k] = v end
            end
            container:SetAuraGroupCandidateFilters(eff, groupCand)
            container:SetAuraGroupLayout(eff, layout)
        else
            container:SetAuraGroupMaxFrameCount(eff, 0)
        end
    end

    container:SetShown(shown)
    return shown
end

-- Sorted value-sensitive fingerprint of a tri-state spell list
-- ({ [id] = true|false }): disabled entries prefix "-", so an enable
-- flip moves the print (CandFP's count:sum ignores values).
local function TriListFP(list)
    if not list or next(list) == nil then return "-" end
    local o = {}
    for id, v in pairs(list) do
        o[#o + 1] = (v and "" or "-") .. id
    end
    table.sort(o)
    return table.concat(o, ",")
end

-- Fingerprint over every input AnchorContainer + ApplyGroupConfig read
-- (computed values like ElementSize and the pixel-scaled spacings capture
-- scale changes implicitly). The chain composition is covered separately by
-- entry.sig; a sig change swaps the container and forces this pass anyway.
local function CfgFP(unit, base, s, frame)
    local PP = EllesmereUI.PP
    local isBuff = (base == "HELPFUL")
    local size, h = ElementSize(unit, base, s)
    local simpleOn, simpleMode = BossSimple(unit, base, s)
    local spX, spY
    if unit:match("^boss") then
        local sp
        if isBuff then sp = ns.GetBossBuffSpacing(s, simpleOn) else sp = ns.GetBossDebuffSpacing(s, simpleOn) end
        spX = PP.FromPixels(sp or 1)
        spY = spX
    else
        spX = PP.FromPixels(Pick(isBuff, s.buffSpacingX, s.debuffSpacingX) or 1)
        spY = PP.FromPixels(Pick(isBuff, s.buffSpacingY, s.debuffSpacingY) or 1)
    end
    local sOffX, sOffY = 0, 0
    if simpleOn then
        if isBuff then sOffX, sOffY = ns.GetBossSimpleBuffOffset(s) else sOffX, sOffY = ns.GetBossSimpleDebuffOffset(s) end
    end
    local showCb, cbH
    if unit == "player" then
        showCb, cbH = s.showPlayerCastbar, s.playerCastbarHeight
    else
        showCb, cbH = s.showCastbar, s.castbarHeight
    end
    -- Anchor Buffs with Debuffs inputs ride BOTH elements' fingerprints,
    -- but ONLY while the toggle is on: the buff element reads the debuff
    -- anchor set while merged, and the debuff element re-anchors when the
    -- merge flag or buff visibility flips. Off (the default), the extra
    -- slots are constant nils so no existing fingerprint ever moves.
    local mAB = s.debuffAnchorBuffs == true
    return FP(size, h, spX, spY, simpleOn, simpleMode, sOffX, sOffY,
        Pick(isBuff, s.buffAnchor, s.debuffAnchor), Pick(isBuff, s.buffGrowth, s.debuffGrowth),
        Pick(isBuff, s.buffOffsetX, s.debuffOffsetX), Pick(isBuff, s.buffOffsetY, s.debuffOffsetY),
        showCb, cbH, Pick(isBuff, s.maxBuffs, s.maxDebuffs),
        Pick(isBuff, s.buffMaxPerRow, s.debuffMaxPerRow), s.showBuffs,
        mAB, mAB and s.debuffAnchor or nil, mAB and s.debuffGrowth or nil,
        mAB and s.debuffOffsetX or nil, mAB and s.debuffOffsetY or nil,
        mAB and s.debuffSpacingY or nil,
        CastbarBelowFrame(unit, frame),
        -- Tracked Auras lists: ApplyGroupConfig reads both (the shared
        -- excludes), and TRI-STATE flips don't move the chain sig -- an
        -- entry's enable checkbox must re-drive this pass. The caster-scope
        -- maps (boss any-caster opt-out, target/focus MINE opt-in) move an
        -- include between the two scope links.
        TriListFP(s.debuffExclude), TriListFP(s.debuffInclude),
        TriListFP(s.debuffIncludeAnyCaster), TriListFP(s.debuffIncludeMine))
end

------------------------------------------------------------------------------
-- Player dispel overlay -> dispel slots
--
-- One bare slot per dispel type, filtered engine-side; each renders our overlay texture
-- pre-colored from the user palette, so the display works while auras are secret
-- without the addon ever reading dispel data. The engine shows/hides the slot button;
-- the overlay is its child. Priority when multiple debuff types are present: fixed
-- layer order (Magic on top), replacing the old first-by-scan-index behavior.
------------------------------------------------------------------------------

local DISPEL_SLOTS = {
    { key = "magic",   colorKey = "dispelColorMagic",   fallback = { 0.349, 0.475, 1.0 },  level = 5 },
    { key = "curse",   colorKey = "dispelColorCurse",   fallback = { 0.636, 0.0, 0.64 },   level = 4 },
    { key = "disease", colorKey = "dispelColorDisease", fallback = { 0.671, 0.384, 0.098 }, level = 3 },
    { key = "poison",  colorKey = "dispelColorPoison",  fallback = { 0.0, 0.706, 0.286 },  level = 2 },
    { key = "bleed",   colorKey = "dispelColorBleed",   fallback = { 0.75, 0.15, 0.15 },   level = 1 },
}
local DISPEL_TYPE_TOKENS = { magic = "Magic", curse = "Curse", disease = "Disease", poison = "Poison", bleed = "Bleed" }

-- A dispel type RAID_PLAYER_DISPELLABLE can never match (bleeds via the dwarf
-- racial, poison on a shaman via Poison Cleansing Totem -- the token knows class
-- and spec dispels only) is handled here by keeping the PLAIN slot lit for such
-- a type rather than giving the by-me twin a filter that would match it: two
-- slots declaring one filter string share a single engine parse batch (see
-- AK.Filter) and both are not guaranteed to receive the aura. The rule itself
-- lives with the legacy overlay in EllesmereUIUnitFrames.lua, which needs the
-- same answer.
local function TokenBlindDispelSlot(slotKey)
    return ns.UF_TokenBlindDispel ~= nil and ns.UF_TokenBlindDispel(slotKey)
end
local GRADIENT_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga"
local GRADIENT_SHARP_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-sharp.tga"

-- applyExtra for dispel slots: builds/updates the overlay texture from the
-- style (mode, color, opacity, health refs). Runs at init and every Restyle.
local function ApplyDispelSlotStyle(button, d, style)
    local health = style.healthFrame
    if not health then return end

    if not d.overlay then
        -- Sublevel 2+level (3..7): higher-priority types get the higher
        -- sublevel, since every slot shares one frame level (see below).
        d.overlay = button:CreateTexture(nil, "ARTWORK", nil, 2 + (style.level or 1))
    end
    local tex = d.overlay
    local c = style.color
    local alpha = (style.opacity or 100) / 100

    -- Change-guarded, stamped AFTER the call: SetFrameLevel on the slot
    -- button is denied while auras are secret (12.1 access restriction).
    -- At creation this runs inside the initializeFrame window (always
    -- legal); on later restyles the level rarely changes, and a denied
    -- attempt throws so the worker defers this key to the lift re-queue.
    -- The health bar's own level, where the legacy overlay texture lived:
    -- below the shield and heal-absorb bars at hpBar+1, so fill/full overlays
    -- never cover them. All slots share this level; the Magic > Curse > ...
    -- priority is encoded in the overlay's ARTWORK sublevel above.
    local lvl = health:GetFrameLevel()
    if d.lvl ~= lvl then
        button:SetFrameLevel(lvl)
        d.lvl = lvl
    end

    tex:ClearAllPoints()
    if style.mode == "gradient" or style.mode == "gradient_sharp" then
        tex:SetAllPoints(health)
        tex:SetTexture(style.mode == "gradient_sharp" and GRADIENT_SHARP_TEXTURE or GRADIENT_TEXTURE)
        tex:SetVertexColor(c.r, c.g, c.b, alpha)
    elseif style.mode == "fill" then
        local fillTex = health.GetStatusBarTexture and health:GetStatusBarTexture()
        -- Both corners come off the fill texture so the overlay follows vertical and
        -- reverse fills; anchoring TOPLEFT to the bar only tracks left-to-right.
        if fillTex then
            tex:SetAllPoints(fillTex)
        else
            tex:SetAllPoints(health)
        end
        tex:SetColorTexture(c.r, c.g, c.b, alpha)
        tex:SetVertexColor(1, 1, 1, 1)
    else -- "full"
        tex:SetAllPoints(health)
        tex:SetColorTexture(c.r, c.g, c.b, alpha)
        tex:SetVertexColor(1, 1, 1, 1)
    end
end

local function DispelStyleKey(slotKey)
    return "uf:player:dispel:" .. slotKey
end

local function BuildDispelStyles(frame)
    local p = ns.UF_GetProfile and ns.UF_GetProfile()
    if not p then return "none" end
    local mode = p.dispelOverlay or "none"
    -- "Only Dispellable by You": slot filters are fixed at declaration and
    -- containers are never swapped (engine buttons leak), so BOTH filter
    -- variants exist as slots from creation and the INACTIVE variant is
    -- styled to opacity 0. Toggling the option only restyles.
    local byMe = p.dispelOverlayByMe == true
    local op = p.dispelOverlayOpacity or 100
    for i = 1, #DISPEL_SLOTS do
        local slot = DISPEL_SLOTS[i]
        -- A type the engine token can never match keeps using the PLAIN slot in
        -- "by me" mode: its by-me twin stays dark and would swallow the setting
        -- entirely.
        local tokenBlind = TokenBlindDispelSlot(slot.key)
        local col = p[slot.colorKey]
        local color = { r = col and col.r or slot.fallback[1], g = col and col.g or slot.fallback[2], b = col and col.b or slot.fallback[3] }
        AK.styles[DispelStyleKey(slot.key)] = {
            width = 1, height = 1,
            noRegions = true,
            mode = mode,
            color = color,
            opacity = (byMe and not tokenBlind) and 0 or op,
            level = slot.level,
            healthFrame = frame.Health,
            applyExtra = ApplyDispelSlotStyle,
        }
        AK.styles[DispelStyleKey(slot.key .. "_byme")] = {
            width = 1, height = 1,
            noRegions = true,
            mode = mode,
            color = color,
            opacity = (byMe and not tokenBlind) and op or 0,
            level = slot.level,
            healthFrame = frame.Health,
            applyExtra = ApplyDispelSlotStyle,
        }
    end
    return mode
end

local function CreateDispelSlots(frame, entry)
    local mode = BuildDispelStyles(frame)

    local container = entry.dispel
    if not container then
        container = AK.CreateContainerShell(frame, {
            point = { "CENTER", frame, "CENTER" },
        })
        -- Stashed BEFORE the slot adds so a watchdog-killed build resumes on
        -- the same container instead of birthing a second one.
        entry.dispel = container
    end

    -- `dispelAdds` counts completed slot declarations: a resumed build skips
    -- what already landed instead of re-declaring existing slot keys.
    local n = 0
    for i = 1, #DISPEL_SLOTS do
        local slot = DISPEL_SLOTS[i]
        local function ParkSlot(slotButton)
            -- Park the slot button on the health bar center (the overlay textures
            -- anchor to the health bar independently). Anchored HERE, inside the
            -- creation window: SetPoint on the returned button is denied while
            -- auras are secret (12.1 button access restriction), and this build
            -- path runs on in-instance reloads.
            slotButton:SetPoint("CENTER", frame.Health or frame, "CENTER")
        end
        n = n + 1
        if n > (entry.dispelAdds or 0) then
            AK.AddSlotToContainer(container, {
                key = slot.key,
                filter = { "HARMFUL" },
                candidateFilters = { includeDispelTypes = { [DISPEL_TYPE_TOKENS[slot.key]] = true } },
                style = DispelStyleKey(slot.key),
                extraInit = ParkSlot,
            })
            entry.dispelAdds = n
        end
        -- "Only Dispellable by You" variant: identical slot with the engine
        -- by-me filter token added. Declared upfront -- slot filters cannot
        -- change after declaration -- and mutually exclusive with the plain
        -- slot via style opacity (BuildDispelStyles zeroes the inactive one).
        n = n + 1
        if n > (entry.dispelAdds or 0) then
            AK.AddSlotToContainer(container, {
                key = slot.key .. "_byme",
                filter = { "HARMFUL", "RAID_PLAYER_DISPELLABLE" },
                candidateFilters = { includeDispelTypes = { [DISPEL_TYPE_TOKENS[slot.key]] = true } },
                style = DispelStyleKey(slot.key .. "_byme"),
                extraInit = ParkSlot,
            })
            entry.dispelAdds = n
        end
    end
    AK.FinishContainer(container, "player")

    container:SetShown(mode ~= "none")
end

local function DispelFP(p)
    -- The poison capability is a talent (Poison Cleansing Totem), so it rides
    -- the fingerprint; race can't change mid-session.
    return FP(p.dispelOverlay, p.dispelOverlayOpacity, p.dispelOverlayByMe == true,
        TokenBlindDispelSlot("poison") and 1 or 0,
        CK(p.dispelColorMagic), CK(p.dispelColorCurse),
        CK(p.dispelColorDisease), CK(p.dispelColorPoison), CK(p.dispelColorBleed))
end

local function ReloadDispelSlots(frame, entry)
    if not entry.dispel then return end
    local p = ns.UF_GetProfile and ns.UF_GetProfile()
    if not p then return end
    local v = DispelFP(p)
    if ufFP.dispel ~= v then
        ufFP.dispel = v
        BuildDispelStyles(frame)
        for i = 1, #DISPEL_SLOTS do
            AK.RestyleSoon(DispelStyleKey(DISPEL_SLOTS[i].key))
            AK.RestyleSoon(DispelStyleKey(DISPEL_SLOTS[i].key .. "_byme"))
        end
    end
    entry.dispel:SetShown((p.dispelOverlay or "none") ~= "none")
end

-- Options-panel poke (via ns.UpdatePlayerDispelOverlay): re-run the
-- fingerprinted dispel reload for the live player frame so dropdown/cog
-- edits apply without waiting for a full container pass.
function ns.UF_ReloadPlayerDispelSlots()
    local entry = registry.player
    if entry and entry.frame and not entry.building then
        ReloadDispelSlots(entry.frame, entry)
    end
end

-- The poison capability behind UF_TokenBlindDispel is a talent (Poison
-- Cleansing Totem). Talent edits fire no spec event, and IsPlayerSpell can lag
-- the trait event itself (the spellbook grant lands with SPELLS_CHANGED), so
-- shamans re-check on both; the reload runs only when the cached capability
-- actually flips. No combat gate: the restyle routes through AK.RestyleSoon,
-- whose worker defers secrecy-denied writes to the restriction-lift re-queue.
do
    local _, class = UnitClass("player")
    if class == "SHAMAN" then
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
        ev:RegisterEvent("SPELLS_CHANGED")
        ev:SetScript("OnEvent", function()
            if ns.UF_RefreshPoisonTotem and ns.UF_RefreshPoisonTotem() then
                ns.UF_ReloadPlayerDispelSlots()
            end
        end)
    end
end

-- Boss preview (fake auras) suppresses the real containers; ReloadFrames
-- restores them when the preview ends.
function ns.UF_HideAuraContainers(frame)
    for _unitKey, entry in pairs(registry) do
        if entry.frame == frame then
            if entry.buffs then entry.buffs:Hide() end
            if entry.debuffs then entry.debuffs:Hide() end
            -- Hidden outside the fingerprinted flow: the next reload must
            -- re-drive visibility even if no setting changed.
            entry.previewHid = true
            return
        end
    end
end

function ns.UF_ReloadAuraContainers(frame, unit)
    local s = SettingsFor(unit)
    local entry = registry[unit]
    if not s or not entry then return end
    -- Still under construction by the deferred stepper: its final stage
    -- runs this reload once the containers are complete.
    if entry.building then return end

    if unit:match("^boss") and ns._bossPreviewActive then
        if entry.buffs then entry.buffs:Hide() end
        if entry.debuffs then entry.debuffs:Hide() end
        entry.previewHid = true
        return
    end

    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or ""
    -- Containers hidden outside the fingerprinted flow (boss preview) must
    -- re-drive anchor/config/visibility even with matching fingerprints.
    -- cfgDirty: the degradation-recovery lane below (cinematic/faction/
    -- vehicle) needs the same force -- re-setting candidates is what makes
    -- the engine re-honor spell-ID filters after an assistability flip, and
    -- the fingerprints never change across one.
    local forceCfg = (entry.previewHid or entry.cfgDirty) and true or false
    entry.previewHid = nil
    entry.cfgDirty = nil

    for base, field in pairs({ HELPFUL = "buffs", HARMFUL = "debuffs" }) do
        local key = StyleKey(unit, base)
        local st = ufFP[key]
        if not st then st = {}; ufFP[key] = st end

        -- Restyle only when the built style actually differs; the deferred
        -- time-sliced restyler spreads the button decoration work out.
        local style = BuildStyle(unit, base, s, entry.frame)
        local styleV = StyleTableFP(style, font)
        if st.style ~= styleV then
            st.style = styleV
            AK.styles[key] = style
            AK.RestyleSoon(key)
        end

        -- Groups are ADDITIVE and the container is NEVER swapped: a changed chain
        -- declares any missing groups on the existing container (combat-legal --
        -- probe T1/T1b), and the config pass zeroes whatever fell out of the active
        -- set. The old swap path permanently leaked a 10-button batch per group per
        -- toggle (engine frames are never freed).
        local chain
        if unit == "player" and base == "HELPFUL" then
            chain = PlayerBuffChain(s)
        elseif unit == "player" then
            chain = PlayerDebuffChain(s)
        else
            chain = BuildChain(base, base == "HELPFUL", s, unit)
        end
        local sig = ChainSignature(chain)
        local force = forceCfg
        local container = entry[field]
        local declared = (entry.groups and entry.groups[field]) or {}
        -- Additive declaration requires the REAL registry: declaring into a
        -- fallback table would lose track and double-declare next change.
        if entry.sig[field] ~= sig and container and entry.groups then
            entry.sig[field] = sig
            if not declared.all then
                DeclareElementGroup(container, declared, key, "all", { base }, nil)
            end
            for i = 1, #chain do
                local c = chain[i]
                if not declared[c.key] then
                    DeclareElementGroup(container, declared, key, c.key, c.tokens, c.cand)
                end
            end
            force = true
        end

        if container then
            local cfgV = CfgFP(unit, base, s, frame)
            if force or st.cfg ~= cfgV then
                st.cfg = cfgV
                AnchorContainer(container, frame, unit, base, s, entry.buffs) -- self-skips on anchor "none"
                ApplyGroupConfig(container, unit, base, s, chain, declared)
            end
        end
    end

    if unit == "player" then
        ReloadDispelSlots(frame, entry)
    end
end

-- Dynamic unit tokens ("target", "focus", "bossN") re-resolve silently: the
-- engine only re-parses on UNIT_AURA or show/hide, so a target swap while the
-- frame stays shown would display the previous unit's auras. Blizzard's own
-- container exposes UpdateAllAuras for exactly this; poke it on unit changes.
local function RefreshUnit(unitKey)
    local entry = registry[unitKey]
    if not entry or entry.building then return end
    if entry.buffs then entry.buffs:UpdateAllAuras() end
    if entry.debuffs then entry.debuffs:UpdateAllAuras() end
    if entry.dispel then entry.dispel:UpdateAllAuras() end
end

-- Degradation recovery for the PLAYER frame's containers: cinematics
-- (UNIT_FACTION fires for every unit at start+end while assistability
-- briefly drops; UNIT_FLAGS does NOT fire -- authors-channel etrace,
-- 2026-08-13), addon-cancelled cinematics (CINEMATIC_STOP's hide/re-show
-- can parse mid-degradation), and vehicles (assistability stays down for
-- the whole ride) all silently disable spell-ID candidate filters
-- engine-side -- the player buff chain's Extra Spells / filter includes
-- degrade to the FULL buff set, and no aura edge is guaranteed to follow
-- the restore. Same trigger set as the PAB lane and the RF assist gate.
-- Recovery = BOTH levers, coalesced one tick after each edge: a forced
-- config pass (cfgDirty -- re-setting candidates is what makes the engine
-- re-honor them) plus a reparse. Cost while idle: a handful of registered
-- events that fire only on cinematics/faction flips/vehicle transitions.
do
    local pending = false
    local w = CreateFrame("Frame")
    w:RegisterUnitEvent("UNIT_FACTION", "player")
    w:RegisterEvent("CINEMATIC_STOP")
    w:RegisterUnitEvent("UNIT_ENTERING_VEHICLE", "player")
    w:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    w:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    w:SetScript("OnEvent", function(_, event)
        if pending then return end
        pending = true
        C_Timer.After(0, function()
            pending = false
            local entry = registry.player
            if not entry or entry.building then return end
            entry.cfgDirty = true
            if entry.frame and ns.UF_ReloadAuraContainers then
                ns.UF_ReloadAuraContainers(entry.frame, "player")
            end
            RefreshUnit("player")
        end)
    end)
end

-- The 12.1 ping-receiver strip workaround lived here until build 68914
-- fixed SendUnitPing upstream (PingManager securecopys the receiver info at
-- the secure boundary); contextual pings on our frames are legal again.

local unitWatcher = CreateFrame("Frame")
unitWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
unitWatcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
unitWatcher:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
unitWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
unitWatcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        RefreshUnit("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        RefreshUnit("focus")
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Filter-set swaps requested during combat run now.
        for unitKey, entry in pairs(registry) do
            if entry.pendingSwap then
                entry.pendingSwap = nil
                ns.UF_ReloadAuraContainers(entry.frame, unitKey)
            end
        end
    else
        for i = 1, 5 do RefreshUnit("boss" .. i) end
    end
end)

-- Called by the main file at the end of every real (throttled) reload pass.
-- A direct call, not a wrap: ns.ReloadFrames is a throttle-arming stub that
-- gets (re)assigned during login setup, which makes wrap timing unreliable.
function ns.UF_ReloadAllAuraContainers()
    for unitKey, entry in pairs(registry) do
        if entry.frame then
            ns.UF_ReloadAuraContainers(entry.frame, unitKey)
        end
    end
end

-- Cast bar settle: the bar's saved position is applied by the unlock system's
-- deferred login pass (EUI_UnlockMode.lua fires it ~1.5s after
-- PLAYER_ENTERING_WORLD, or CDM owns it), which lands AFTER these containers
-- anchored -- so the bottom-anchor reserve was decided against the bar's
-- provisional position. Re-run the pass once the positions are in, and again
-- whenever unlock mode closes (the bar may have been dragged into or out of the
-- strip below the frame). Both are no-ops unless the reserve actually changed:
-- UF_ReloadAuraContainers only re-anchors on a config fingerprint change.
-- A profile swap needs no trigger of its own: it runs through RefreshAllAddons
-- -> ReloadFrames, which ends in UF_ReloadAllAuraContainers already.
-- Cost: two login timers, one unlock listener. No per-frame work, no allocation
-- on any chatty event.
--
-- Deliberately NOT a hook on EllesmereUI._applySavedPositions: that field is
-- passed by reference into C_Timer.After by the action bars module
-- (EllesmereUIActionBars.lua), and replacing it there made that call raise.
do
    local pending = false
    local function Settle()
        pending = false
        ns.UF_ReloadAllAuraContainers()
    end
    local function Queue()
        if pending then return end
        pending = true
        C_Timer.After(0, Settle)
    end
    local settleWatcher = CreateFrame("Frame")
    settleWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    settleWatcher:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Two passes: the first clears the unlock system's own deferred pass
        -- (~1.5s after this event), the second covers a CDM-owned run of it,
        -- which waits for async icon population and can land later. Whichever
        -- lands second is a no-op unless the reserve actually changed.
        C_Timer.After(2, Queue)
        C_Timer.After(5, Queue)
    end)
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener("EUF_AuraContainers", function(unlockActive)
            if not unlockActive then Queue() end
        end)
    end
end

-- One element shell, born directly on our frame (combat-legal since 68914).
local function AdoptShell(frame, unit, field)
    return AK.CreateContainerShell(frame, {
        point = { "CENTER", frame, "CENTER" }, -- provisional; reload anchors properly
    })
end

local ELEMENT_ORDER = { { "HELPFUL", "buffs" }, { "HARMFUL", "debuffs" } }

-- Builds one unit's containers as a RESUMABLE STEPPER: each invocation does one bounded
-- atom of work and returns "again" until done. The expensive atom is a single group
-- declaration (an eager 10-button engine batch through AuraKit's full region
-- initializer); running them one per invocation lets the shared worker's per-frame
-- budget apply between atoms, where the old whole-unit job could balloon past the
-- client watchdog under login contention ("script ran too long" -- and the killed job
-- left the unit half-built). Every stage is existence-guarded, so a watchdog-killed
-- invocation resumes cleanly: an aborted engine declare never stamps its
-- declared/progress mark and simply re-runs.
local function BuildUnitContainers(frame, unit)
    local s = SettingsFor(unit)
    if not (AK and s) then return end
    local entry = registry[unit]
    if entry and not entry.building then return end

    -- Stage 1: entry + both element shells (cheap; no engine batches;
    -- combat-legal since 68914).
    if not entry then
        -- Styles must exist before group declaration: initializeFrame
        -- consumes them for the pre-created button batches. Prime their
        -- fingerprints too: the final-stage reload would otherwise queue a
        -- restyle of buttons that were decorated from these exact tables.
        local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or ""
        for _, base in ipairs({ "HELPFUL", "HARMFUL" }) do
            local key = StyleKey(unit, base)
            local style = BuildStyle(unit, base, s, frame)
            AK.styles[key] = style
            ufFP[key] = { style = StyleTableFP(style, font) }
        end

        entry = { frame = frame, building = true, sig = {}, groups = { buffs = {}, debuffs = {} } }
        entry.buffs = AdoptShell(frame, unit, "buffs")
        entry.debuffs = AdoptShell(frame, unit, "debuffs")
        registry[unit] = entry
        return "again"
    end

    -- Stage 2: one missing group declaration per invocation (the expensive
    -- atom).
    for e = 1, 2 do
        local base, field = ELEMENT_ORDER[e][1], ELEMENT_ORDER[e][2]
        local chain
        if unit == "player" and base == "HELPFUL" then
            chain = PlayerBuffChain(s)
        elseif unit == "player" then
            chain = PlayerDebuffChain(s)
        else
            chain = BuildChain(base, base == "HELPFUL", s, unit)
        end
        local declared = entry.groups[field]
        local styleKey = StyleKey(unit, base)
        if not declared.all then
            DeclareElementGroup(entry[field], declared, styleKey, "all", { base }, nil)
            return "again"
        end
        for i = 1, #chain do
            local c = chain[i]
            if not declared[c.key] then
                DeclareElementGroup(entry[field], declared, styleKey, c.key, c.tokens, c.cand)
                return "again"
            end
        end
    end

    -- Stage 3: finish both containers (SetUnit + full refresh). Stamped
    -- after the calls; re-finishing on a resumed run is harmless.
    if not entry.finished then
        AK.FinishContainer(entry.buffs, unit)
        AK.FinishContainer(entry.debuffs, unit)
        entry.finished = true
        return "again"
    end

    -- Stage 4: player dispel slots (batch-1 slot adds; internally resumable
    -- via entry.dispel / entry.dispelAdds).
    if unit == "player" and not entry.dispelDone then
        CreateDispelSlots(frame, entry)
        entry.dispelDone = true
        -- Prime the dispel fingerprint: creation just applied these exact
        -- settings, so the final-stage reload must not queue a redundant
        -- restyle (harmless noise OOC, but denied button writes when built
        -- under restriction -- the in-instance /reload case).
        local p = ns.UF_GetProfile and ns.UF_GetProfile()
        if p then ufFP.dispel = DispelFP(p) end
        return "again"
    end

    -- Final stage: the first real reload declares nothing new (entry.sig is
    -- still unset, so its additive path walks the declared sets as no-ops,
    -- stamps the signatures, and force-applies anchor/config/visibility).
    entry.building = nil
    ns.UF_ReloadAuraContainers(frame, unit)
end

-- Deferred through the shared AuraKit build scheduler (budgeted per frame, never ticks
-- during loading screens; combat-runnable via the stash shells). One QUEUED job per
-- unit, but the job is a stepper: it returns "again" after each bounded atom (one
-- engine group batch) so the worker's budget check runs between atoms -- the return
-- propagates BuildUnitContainers' verdict.
function ns.UF_CreateAuraContainers(frame, unit)
    AK = AK or EllesmereUI.AuraKit
    if not (AK and AK.QueueBuildJob) then return end
    if registry[unit] then return end
    AK.QueueBuildJob(function()
        return BuildUnitContainers(frame, unit)
    end, "uf:unit")
end
