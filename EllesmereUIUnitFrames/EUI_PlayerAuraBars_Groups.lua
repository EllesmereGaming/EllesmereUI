if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_Groups.lua
--
--  Debuff match mode, the candidate filters, the group layout and
--  ApplyGroupConfig.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._pabInternals
-- EllesmereUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not I or I.broken then return end
I.broken = true

local BuildChain, ClassByKey, ClassEnabled = I.BuildChain, I.ClassByKey, I.ClassEnabled
local DEBUFF_FILTER_ORDER, DebuffSubtractFn = I.DEBUFF_FILTER_ORDER, I.DebuffSubtractFn
local MergeTypes, PAB_ApplyDmFx = I.MergeTypes, I.PAB_ApplyDmFx
local PAB_FxEntryActive, PAB_FxSafeToForce = I.PAB_FxEntryActive, I.PAB_FxSafeToForce
local PAB_FxSizeFor, PAB_FxWantsCategory = I.PAB_FxSizeFor, I.PAB_FxWantsCategory
local PabShapedSize, PabSnap = I.PabShapedSize, I.PabSnap
local VisibleCandidateClasses = I.VisibleCandidateClasses
local VisibleTokenClasses, DebuffCatchAllOn = I.VisibleTokenClasses, I.DebuffCatchAllOn
local ResolveSortDirection, ResolveSortMethod = I.ResolveSortDirection, I.ResolveSortMethod

local AK -- EllesmereUI.AuraKit, resolved at first use (see SetAK)
I.AKSetters[#I.AKSetters + 1] = function(v) AK = v end

-------------------------------------------------------------------------------
--  Debuff Match Mode (cfg.debuffMatch: nil = Match Any, "all" = Match All)
--
--  Match Any is the BuildChain union, untouched. Match All ANDs every Show pick into
--  ONE group: HARMFUL + every shown token + every shown candidate field, with the
--  Hide lane as a plain veto (!TOKEN, the opposite boolean, excludeDispelTypes), so
--  a debuff renders at most once. The dispel types stay one OR'd axis (a debuff has
--  one type: Magic + Curse = either; Dispels beside a type adds nothing). Runs only
--  with All Debuffs off and at least two Show picks; anything less builds today's
--  chain. Only rows the Filters dropdown lists take part, so a retired row's stale
--  key cannot silently empty the bar.
--
--  Icon Effects only PAINT here (they never add content, and Hide beats them): a
--  block naming a category every member already belongs to paints the whole group;
--  a block naming another category X splits it into (group AND X, painted) and
--  (group AND NOT X) -- exact, never duplicating (every category has an exact
--  complement: the negated token, the opposite boolean, or the remaining dispel
--  types; Boss, Role and Can Apply split like Important). Buttons stamp the
--  group's category LIST (link.cats) and the key names that list, since a
--  button's category is stamped once at creation. Settings-apply time only.
-------------------------------------------------------------------------------
local DebuffChainFor
do
    local LISTED = {}
    for i = 1, #DEBUFF_FILTER_ORDER do LISTED[DEBUFF_FILTER_ORDER[i]] = true end

    -- Types of `a` also in / not in `b`, as a fresh set; nil when none are left.
    local function TypesAnd(a, b)
        local out
        for k in pairs(a) do
            if b[k] then out = out or {}; out[k] = true end
        end
        return out
    end
    local function TypesMinus(a, b)
        local out
        for k in pairs(a) do
            if not (b and b[k]) then out = out or {}; out[k] = true end
        end
        return out
    end

    local function CopyPart(p)
        local t, c = {}, {}
        for i = 1, #p.tokens do t[i] = p.tokens[i] end
        for k, v in pairs(p.cand) do c[k] = v end
        return { tokens = t, cand = c }
    end

    local function HasToken(p, tok)
        for i = 1, #p.tokens do
            if p.tokens[i] == tok then return true end
        end
        return false
    end

    -- The group. nil = Match All does not apply; false = the picks can never match
    -- together (Non-Player with Cast By You, Cast By You with From Any Player hidden,
    -- a dispel type with Dispels hidden); else the part and the categories every
    -- member belongs to.
    local function MatchBase(cfg)
        if cfg.debuffMatch ~= "all" or cfg.showAllDebuffs ~= false then return nil end
        local tokenClasses, candidateClasses = VisibleTokenClasses(), VisibleCandidateClasses()
        if not (tokenClasses and candidateClasses) then return nil end
        local neg = cfg.negClassFilters
        local tokens, cand, cats = { "HARMFUL" }, {}, {}
        local picks, nTypes, clash = 0, 0, false
        local inc, anyType, exc, typeKey, playerTok, hideBool, dispTok
        for i = 1, #tokenClasses do
            local class = tokenClasses[i]
            if LISTED[class.key] then
                if ClassEnabled(class, false, cfg) then
                    picks = picks + 1
                    tokens[#tokens + 1] = class.token
                    cats[#cats + 1] = class.key
                    if class.key == "castbyme" then playerTok = true end
                    if class.key == "dispellable" then dispTok = true end
                elseif neg and neg[class.skey] == true then
                    tokens[#tokens + 1] = class.neg or ("!" .. class.token)
                end
            end
        end
        for i = 1, #candidateClasses do
            local class = candidateClasses[i]
            local cc = class.cand
            if cc and LISTED[class.key] then
                if ClassEnabled(class, false, cfg) then
                    picks = picks + 1
                    if class.key == "dispeltyped" then
                        anyType = cc.includeDispelTypes
                        cats[#cats + 1] = class.key
                    elseif cc.includeDispelTypes then
                        inc = MergeTypes(inc, cc.includeDispelTypes)
                        nTypes, typeKey = nTypes + 1, class.key
                    else
                        for k, v in pairs(cc) do
                            -- Two picks on one field (stale data only: the setters keep
                            -- Non-Player and From Any Player exclusive) never match.
                            if cand[k] ~= nil and cand[k] ~= v then clash = true end
                            cand[k] = v
                        end
                        cats[#cats + 1] = class.key
                    end
                elseif neg and neg[class.skey] == true then
                    if cc.includeDispelTypes then
                        exc = MergeTypes(exc, cc.includeDispelTypes)
                    else
                        hideBool = hideBool or {}
                        for k, v in pairs(cc) do
                            if type(v) == "boolean" then hideBool[k] = not v end
                        end
                    end
                end
            end
        end
        if picks < 2 then return nil end
        -- A Show pick owns its field; the Hide lane vetoes only what is left open.
        if hideBool then
            for k, v in pairs(hideBool) do
                if cand[k] == nil then cand[k] = v end
            end
        end
        -- Every per-type set sits inside Dispels' any-type set, so Dispels ANDed onto
        -- shown types changes nothing. Always a fresh set (never a vocabulary table).
        local typed = inc or anyType
        if typed then
            typed = TypesMinus(typed, exc)
            if not typed then clash = true end
            cand.includeDispelTypes = typed
            -- One shown type: every member carries it (with two, neither is certain).
            if nTypes == 1 then cats[#cats + 1] = typeKey end
        elseif exc then
            cand.excludeDispelTypes = exc
            -- Dispellable By You passes only debuffs of a dispellable type, so
            -- hiding all five leaves it nothing.
            if dispTok and exc.Magic and exc.Curse and exc.Disease and exc.Poison and exc.Bleed then
                clash = true
            end
        end
        -- PLAYER (Cast By You: you, your pet or vehicle) inside isFromPlayerOrPlayerPet
        -- = false (a shown Non-Player, or a hidden From Any Player) is always empty.
        if playerTok and cand.isFromPlayerOrPlayerPet == false then clash = true end
        if clash then return false end
        return { tokens = tokens, cand = cand }, cats
    end

    -- How category `class` relates to part p: "in" when every member belongs to it;
    -- nil when no member can; else "split" under `probe`, or the (p AND class,
    -- p AND NOT class) parts.
    local function Relate(p, class, probe)
        if class.token then
            if HasToken(p, class.token) then return "in" end
            local negTok = class.neg or ("!" .. class.token)
            if HasToken(p, negTok) then return nil end
            if probe then return "split" end
            local a, b = CopyPart(p), CopyPart(p)
            a.tokens[#a.tokens + 1] = class.token
            b.tokens[#b.tokens + 1] = negTok
            return a, b
        end
        local cc = class.cand
        if not cc then return nil end
        local set = cc.includeDispelTypes
        if set then
            local inc, exc = p.cand.includeDispelTypes, p.cand.excludeDispelTypes
            if inc and not TypesMinus(inc, set) then return "in" end
            local pos
            if inc then pos = TypesAnd(inc, set) else pos = set end
            if pos then pos = TypesMinus(pos, exc) end
            if not pos then return nil end
            if probe then return "split" end
            local a, b = CopyPart(p), CopyPart(p)
            a.cand.includeDispelTypes = pos
            a.cand.excludeDispelTypes = nil
            if inc then
                b.cand.includeDispelTypes = TypesMinus(inc, set)
            else
                b.cand.excludeDispelTypes = MergeTypes(exc, set)
            end
            return a, b
        end
        local k, v = next(cc)
        if p.cand[k] ~= nil then
            if p.cand[k] == v then return "in" end
            return nil
        end
        if probe then return "split" end
        local a, b = CopyPart(p), CopyPart(p)
        a.cand[k] = v
        b.cand[k] = not v
        return a, b
    end

    local function MatchLink(p, cats)
        local sorted = {}
        for i = 1, #cats do sorted[i] = cats[i] end
        table.sort(sorted)
        return { key = "and:" .. table.concat(sorted, "+"), tokens = p.tokens,
            cand = next(p.cand) and p.cand or nil, cats = sorted }
    end

    -- nil when Match All does not apply; empty when its picks can never match; else
    -- the painted splits (block order) followed by the rest of the group.
    local function MatchAllChain(cfg)
        local rest, cats = MatchBase(cfg)
        if rest == nil then return nil end
        if not rest then return {} end
        local chain = {}
        local list = cfg.fxList
        if list then
            local inSet, seen = {}, {}
            for i = 1, #cats do inSet[cats[i]] = true end
            for i = 1, #list do
                local e = list[i]
                local f = e.filters
                if f and PAB_FxEntryActive(e) then
                    -- First block wins: one naming a category the rest already
                    -- belongs to paints all of it, and no later block reaches it.
                    local hit = false
                    for j = 1, #DEBUFF_FILTER_ORDER do
                        local key = DEBUFF_FILTER_ORDER[j]
                        if f[key] then
                            if inSet[key] then
                                hit = true
                            else
                                local class = ClassByKey(key)
                                if class and Relate(rest, class, true) == "in" then
                                    inSet[key] = true
                                    cats[#cats + 1] = key
                                    hit = true
                                end
                            end
                        end
                    end
                    if hit then break end
                    for j = 1, #DEBUFF_FILTER_ORDER do
                        local key = DEBUFF_FILTER_ORDER[j]
                        if f[key] and not seen[key] then
                            seen[key] = true
                            local class = ClassByKey(key)
                            local a, b
                            if class then a, b = Relate(rest, class) end
                            if type(a) == "table" then
                                local pc = {}
                                for n = 1, #cats do pc[n] = cats[n] end
                                pc[#pc + 1] = key
                                chain[#chain + 1] = MatchLink(a, pc)
                                rest = b
                            end
                        end
                    end
                end
            end
        end
        chain[#chain + 1] = MatchLink(rest, cats)
        return chain
    end

    -- The debuff chain for a bar: Match All when it applies, else the union.
    DebuffChainFor = function(cfg)
        local chain = MatchAllChain(cfg)
        if chain then return chain end
        return BuildChain("HARMFUL", function(class) return ClassEnabled(class, false, cfg) or (PAB_FxSafeToForce(class) and PAB_FxWantsCategory(cfg.fxList, class.key)) end, DebuffCatchAllOn(cfg), DebuffSubtractFn(cfg))
    end

    -- Options-page empty warning: Match All picks that can never match together.
    -- The builder's own test, so the two never disagree. ns.PAB_DebuffBarHasContent
    -- stays as it is (the one-shot EnsureBarEnable migration reads it).
    function ns.PAB_DebuffMatchEmpty(cfg)
        return cfg ~= nil and MatchBase(cfg) == false
    end
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
    v.width = PabSnap(PabShapedSize(size, shape))
    v.height = PabSnap(PabShapedSize(size, shape))
    AK.styles[variantKey] = v
    AK.RestyleSoon(variantKey)
    return variantKey
end

local function BuildGroupLayout(cfg, gap, rowGap, size)
    rowGap = rowGap or gap
    size = PabSnap(PabShapedSize(size or cfg.iconSize or 32, cfg.iconShape))
    gap = PabSnap(gap)
    rowGap = PabSnap(rowGap)
    return {
        elementWidth = size,
        elementHeight = size,
        elementSpacing = gap,
        lineSpacing = rowGap,
        -- ZERO on purpose: the engine's flow layout advances the cursor by
        -- elementSpacing AFTER every element, the last one of a group
        -- included, so a group boundary already carries one `gap`. Adding
        -- groupSpacing on top doubled it -- visible as a wider seam between
        -- the weapon-enchant cells and the first buff, and between the
        -- catch-all and spells groups.
        groupSpacing = 0,
        groupLineSpacing = rowGap,
    }
end

local function ApplyGroupConfig(container, chain, declaredSet, styleKey, effectiveMax, gap, rowGap, cfg, extraCand)
    local sortMethod = ResolveSortMethod(cfg)
    local sortDirection = ResolveSortDirection(cfg)
    -- elementSpacing = icon-to-icon gap in a row, and it also separates two
    -- groups on one line (see BuildGroupLayout's zero groupSpacing);
    -- lineSpacing = gap between wrapped rows within a group, tied to `rowGap`
    -- (defaults to `gap`) so row-to-row distance is overridable independently of
    -- icon-to-icon spacing (cfg.rowSpacing in the Settings Schema comment).
    -- Container-level padding is a THIRD, unrelated concept: the OUTER edge inset,
    -- fixed at 0 elsewhere and never affected by either.
    local active = {}
    for i = 1, #chain do
        local link = chain[i]
        -- Size override, debuffs only: cfg.fxList is nil for buffs, so szOv is always
        -- nil there.
        local szOv = PAB_FxSizeFor(cfg.fxList, link.cats or link.key)
        local layout = BuildGroupLayout(cfg, gap, rowGap, szOv)
        -- Token strings are declaration-fixed too, so the effective key embeds the
        -- link's token set: a changed negation shape (subtract flips, class-set edits)
        -- declares a fresh variant instead of leaving a stale filter on the old group.
        -- link.key alone stays the fx CATEGORY identity (d.dmCat / PAB_FxSizeFor);
        -- a Match All link carries a category list instead (link.cats, named by its key).
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
            local catKey = link.cats or link.key
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
                    PAB_ApplyDmFx(button, d, style, true)
                end,
            })
            declaredSet[effKey] = true
        end
        -- Hidden links (subtracted classes) stay declared so their chain negations
        -- keep excluding them from the catch-all, but render nothing themselves.
        EllesmereUI.AuraKit.SetGroupCap(container, effKey, link.hidden and 0 or effectiveMax)
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
            EllesmereUI.AuraKit.SetGroupCap(container, key, 0)
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
                pcall(EllesmereUI.AuraKit.SetGroupCap, container, key, 0)
            end
        end
    end
    pcall(EllesmereUI.AuraKit.SetGroupCap, container, "spells", 0)
    AK.ReleaseContainer(container)
end

I.ApplyGroupConfig, I.BuildGroupLayout = ApplyGroupConfig, BuildGroupLayout
I.DebuffChainFor, I.MergeCandidateFilters = DebuffChainFor, MergeCandidateFilters
I.RetireContainer = RetireContainer
I.broken = false
