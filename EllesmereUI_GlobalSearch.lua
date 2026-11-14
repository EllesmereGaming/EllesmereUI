if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_GlobalSearch.lua
--  Unified fuzzy search across every registered EllesmereUI sub-addon's
--  options.
--
--  Optional / modular by design: TagOptionRow and SectionHeader in
--  EllesmereUI_Widgets.lua call EllesmereUI._RegisterSearchEntry only if it
--  exists, so this file can be added (or removed) independently of the rest
--  of the addon with no other changes required.
-------------------------------------------------------------------------------

-- The module registry is the core's private one (EllesmereUI.lua), shared
-- through this addon's namespace. It holds suite modules and plugin modules.
local _, ns = ...
ns = ns.__euiCoreNS or ns  -- standalone builds: the core's own table (EllesmereUI.lua)

-- Breadcrumb separator: the house right-arrow glyph rendered inline in the
-- sub text (module -> page), sized to sit with the 10pt breadcrumb font.
local BREADCRUMB_ARROW = " |TInterface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-right.png:12:12|t "

-- Display name of a registered module. Plugin modules read as
-- "Section > Module" so results name the plugin they belong to.
local function ModuleLabel(config, folder)
    local title = EllesmereUI.L(config.title or folder)
    if config._pluginLabel then
        return EllesmereUI.L(config._pluginLabel) .. BREADCRUMB_ARROW .. title, config._pluginLabel .. " " .. title
    end
    return title, title
end

-- A page's name as its tab shows it (EUI_NS.GetTabLabel), localized.
local function PageLabel(folder, page)
    return EllesmereUI.L(ns.GetTabLabel(folder, page))
end

-------------------------------------------------------------------------------
--  Index storage
-------------------------------------------------------------------------------
local _searchIndex = {}
-- Registration key -> entry (also the pick history's key).
local _seenKeys = {}

-- Picked results (frecency), key -> { count, last time }, capped; the least
-- valuable pick makes room. On unless turned off (EllesmereUIDB.searchPicksOff);
-- off keeps no history.
local PICKS_MAX = 200
function EllesmereUI.SearchPicksOn()
    return not (EllesmereUIDB and EllesmereUIDB.searchPicksOff)
end
function EllesmereUI.SetSearchPicksOn(on)
    EllesmereUIDB = EllesmereUIDB or {}
    EllesmereUIDB.searchPicksOff = not on or nil
    if not on then EllesmereUIDB.searchPicks = nil end
end
local function PickValue(p, now)
    return p[1] / (1 + (now - p[2]) / 604800) -- a week-old pick counts half
end
local function PickKey(e)
    if e.kind == "page" then return "\2" .. e.module .. "\1" .. e.page end
    local key = e.module .. "\1" .. e.page .. "\1" .. e.label
    if e.host or e.cogTitle then key = key .. "\1" .. (e.host or "") .. "\1" .. (e.cogTitle or "") end
    return key
end
local function RecordPick(entry)
    if not EllesmereUI.SearchPicksOn() then return end
    EllesmereUIDB = EllesmereUIDB or {}
    local picks = EllesmereUIDB.searchPicks or {}
    EllesmereUIDB.searchPicks = picks
    local key, now = PickKey(entry), time()
    local p = picks[key]
    if p then
        p[1], p[2] = p[1] + 1, now
        return
    end
    local n, worstKey, worst = 0, nil, math.huge
    for k, q in pairs(picks) do
        n = n + 1
        local v = PickValue(q, now)
        if v < worst then worstKey, worst = k, v end
    end
    if n >= PICKS_MAX then picks[worstKey] = nil end
    picks[key] = { 1, now }
end
function EllesmereUI.ClearSearchPicks()
    if EllesmereUIDB then EllesmereUIDB.searchPicks = nil end
end

-- Registered by TagOptionRow / SectionHeader as each option row / section
-- header is built during normal navigation, and by the one-time pre-build
-- pass below for pages nobody has opened yet this session.
-- Set once the index pass has finished (dev-mode coverage report below).
local _prebuildComplete = false

-- Where an entry lives, lowercased once: module, page, Window Skins card,
-- section, and for a cog row its host row and popup title, each also in its
-- localized form when that differs. Rows register in page order, so the
-- last path is reused while it repeats: no tables or concat on a hit.
local _ctxArgs, _ctxText = {}, nil
local function ContextText(folder, page, card, section, host, cogTitle)
    local a = _ctxArgs
    if _ctxText and a[1] == folder and a[2] == page and a[3] == card and a[4] == section
       and a[5] == host and a[6] == cogTitle then
        return _ctxText
    end
    a[1], a[2], a[3], a[4], a[5], a[6] = folder, page, card, section, host, cogTitle
    local config = ns.modules and ns.modules[folder]
    local parts = { config and select(2, ModuleLabel(config, folder)) or folder, PageLabel(folder, page) }
    for _, s in ipairs({ card or false, section or false, host or false, cogTitle or false }) do
        if s and s ~= "" then
            parts[#parts + 1] = s
            local loc = EllesmereUI.L(s)
            if loc ~= s then parts[#parts + 1] = loc end
        end
    end
    _ctxText = table.concat(parts, " "):lower()
    return _ctxText
end

-- host / cogTitle: set for a row inside an inline cog popup (_RegisterCogSearch).
function EllesmereUI._RegisterSearchEntry(label, labelLoc, tooltip, moduleFolder, page, sectionName, selectorSetter, selectorKey, isSection, host, cogTitle)
    -- Opt-out for whole UI regions: a builder sets this around widget
    -- construction it wants excluded from the search entirely (e.g. the QoL
    -- Macro Factory, whose rows must never be indexed or deep-linked).
    if EllesmereUI._searchIndexSuppress then return end
    -- Composite labels (DualRow/TripleRow with an empty slot) can come in as whitespace
    -- only (e.g. a single joining space with nothing on either side) -- trim before the
    -- emptiness check so those don't register as inert, unmatchable junk entries.
    if label then label = label:match("^%s*(.-)%s*$") end
    if not label or label == "" or not moduleFolder or not page then return end
    -- Cog rows repeat their labels ("Size") across a page: keyed by host and popup too.
    local key = moduleFolder .. "\1" .. page .. "\1" .. label
    if host or cogTitle then key = key .. "\1" .. (host or "") .. "\1" .. (cogTitle or "") end
    if _seenKeys[key] then return end
    if (host or cogTitle) and _prebuildComplete and not EllesmereUI._prebuilding and EllesmereUI.IsDevModeActive() then
        print("|cffff6060EUI GlobalSearch:|r cog row \"" .. label .. "\" (" .. moduleFolder .. "::" .. page
            .. ") was not indexed by the pass -- its cog call is not reached while prebuilding, or it depends on state set after the pass.")
    end
    if labelLoc == "" then labelLoc = nil end
    if type(tooltip) ~= "string" or tooltip == "" then tooltip = nil end
    local card = EllesmereUI._searchContext
    local entry = {
        ctx = ContextText(moduleFolder, page, card, sectionName, host, cogTitle),
        label = label,
        -- Lowercased once here so a keystroke never re-lowers the whole index.
        lLabel = label:lower(),
        lLoc = labelLoc and labelLoc:lower(),
        lTip = tooltip and tooltip:lower(),
        -- Space-free copies: "castbar" finds "Cast Bar", "mouse over" finds "Mouseover".
        nLabel = (label:lower():gsub(" ", "")),
        nLoc = labelLoc and (labelLoc:lower():gsub(" ", "")),
        nTip = tooltip and (tooltip:lower():gsub(" ", "")),
        labelLoc = labelLoc,
        tooltip = tooltip,
        module = moduleFolder,
        section = sectionName,
        page = page,
        -- Present only for entries built while a page's own internal selector (CDM bar
        -- / action bar / unit dropdown) was set to a specific value -- lets
        -- JumpToResult restore that exact selection before navigating, so a setting
        -- that only exists under one selector value (e.g. HoverCast-only options) is
        -- actually there to find and highlight instead of silently not matching.
        selectorSetter = selectorSetter,
        selectorKey = selectorKey,
        -- True for SectionHeader registrations: results render these as
        -- "Section: Title Case" destinations instead of option rows.
        isSection = isSection,
    }
    -- Set after: in the constructor they would double every entry's hash part.
    if card then entry.card = card end
    if host or cogTitle then entry.host, entry.cogTitle = host, cogTitle end
    _searchIndex[#_searchIndex + 1] = entry
    _seenKeys[key] = entry
end

-------------------------------------------------------------------------------
--  Fuzzy scoring: subsequence match, ranked below any exact substring by
--  ScoreEntry's tiers. Cheap enough to run per keystroke over the whole
--  index -- no Levenshtein needed.
-------------------------------------------------------------------------------
-- The needle split into one-character strings, once per query.
local _fuzzyNeedle, _fuzzyChars = nil, {}
local function FuzzyScore(haystack, needle)
    local nLen = #needle
    if needle ~= _fuzzyNeedle then
        _fuzzyNeedle, _fuzzyChars = needle, {}
        for i = 1, nLen do _fuzzyChars[i] = needle:sub(i, i) end
    end
    -- Forward pass only finds where the earliest full match ends: a plain
    -- find per needle character, so the scan between them runs in C.
    local hi, find = 0, string.find
    for i = 1, nLen do
        hi = find(haystack, _fuzzyChars[i], hi + 1, true)
        if not hi then return nil end -- not every needle char found in order
    end
    local lastMatch = hi
    -- Backward pass from there finds the latest start, so the match is not
    -- anchored on a stray early letter ("stats" on "secondary stat display"
    -- must start at "stat", not at the "s" of "secondary").
    local consecutiveRun, score = 0, 0
    local ni
    hi, ni = lastMatch, nLen
    while ni >= 1 do
        if haystack:byte(hi) == needle:byte(ni) then
            consecutiveRun = consecutiveRun + 1
            score = score + consecutiveRun -- reward tight clustering (a run of k scores 1+2+...+k)
            ni = ni - 1
        else
            consecutiveRun = 0
        end
        hi = hi - 1
    end
    local firstMatch = hi + 1

    -- Reject overly sparse matches. Without this, a long enough haystack makes almost
    -- any needle findable as SOME subsequence somewhere in it (e.g. "combat" scattering
    -- across "Consumables Talent" in a coarse module+page label) -- that's noise, not a
    -- real fuzzy match. Flat +8 slack keeps short abbreviations ("aoc" over "Auto Open
    -- Containers") alive while capping how far a longer word may scatter.
    local span = lastMatch - firstMatch + 1
    if span > nLen + 8 then return nil end

    return (score * 100) / span -- density: tighter matches for the same needle score higher
end

-- Tiers, best first: label exact, label plural-stem exact, tooltip exact,
-- tooltip stem, label fuzzy, tooltip fuzzy. A tier always outranks the one
-- below it. Within a substring tier (best first): the match starts a word,
-- or the field; the caller's bonus (the hit is in the entry's own name; it is
-- a page or section); the share of the field the query covers.
local TIER = 10000
local function IsWordByte(c)
    return c and ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c >= 128)
end
local function Within(h, i, n, bonus)
    local w = 0
    if i == 1 then w = 4500 elseif not IsWordByte(h:byte(i - 1)) then w = 4000 end
    return w + bonus + math.floor(999 * n / #h)
end
local function FieldScore(h, nh, needle, stem, ns, exactTier, fuzzyTier, bonus)
    if not h then return nil end
    local i = h:find(needle, 1, true)
    if i then return exactTier * TIER + Within(h, i, #needle, bonus) end
    if stem then
        -- Singular form must end its word: "stat" in "stat display", not "status".
        i = h:find(stem, 1, true)
        while i do
            if not IsWordByte(h:byte(i + #stem)) then
                return (exactTier - 1) * TIER + Within(h, i, #stem, bonus)
            end
            i = h:find(stem, i + 1, true)
        end
    end
    -- Space-free: word starts are not known here.
    i = nh:find(ns, 1, true)
    if i then return (exactTier - 1) * TIER + bonus + math.floor(999 * #ns / #nh) end
    local s = FuzzyScore(h, needle)
    if s then return fuzzyTier * TIER + math.min(s, TIER - 1) end
end

local OWN_BONUS, DEST_BONUS = 2000, 1000
local function ScoreEntry(entry, needle, stem, ns, words)
    local isPage = entry.kind == "page"
    local dest = (isPage or entry.isSection) and DEST_BONUS or 0
    -- A page's label is "module page": the hit counts as its own name only
    -- when a query word is in the page name ("party frames" on Party).
    local own = OWN_BONUS
    if isPage then
        own = 0
        for k = 1, #words do
            if entry.lPage:find(words[k], 1, true) then own = OWN_BONUS; break end
        end
    end
    local a = FieldScore(entry.lLabel, entry.nLabel, needle, stem, ns, 5, 1, own + dest)
    local b = FieldScore(entry.lLoc, entry.nLoc, needle, stem, ns, 5, 1, OWN_BONUS + dest)
    local c = FieldScore(entry.lTip, entry.nTip, needle, stem, ns, 3, 0, 0)
    -- Page results also score on the tab name alone: "fonts" hits "Fonts" at
    -- position 1 instead of late in "Global Settings Fonts".
    local d = FieldScore(entry.lPage, entry.nPage, needle, stem, ns, 5, 1, OWN_BONUS + dest)
    if b and (not a or b > a) then a = b end
    if c and (not a or c > a) then a = c end
    if d and (not a or d > a) then a = d end
    return a
end

-- Tie-break for equal scores: whole text equals the query, then shorter
-- text, then a fixed order (page, section, option; module in sidebar order,
-- Global Settings first, plugins last; page; label), since table.sort is not
-- stable and the candidates come from pairs().
local KIND_RANK = { page = 1 }
-- The sidebar's order is its groups' (read at load, before any other addon runs);
-- every key outside them (plugins, other addons' pages) takes 1000.
local _moduleRank = { [EllesmereUI.GLOBAL_KEY] = 0 }
do
    local n = 0
    for _, group in ipairs(EllesmereUI.ADDON_GROUPS) do
        for _, folder in ipairs(group.members) do
            n = n + 1
            _moduleRank[folder] = n
        end
    end
end
local function SortResults(a, b)
    if a.score ~= b.score then return a.score > b.score end
    local xa, xb = a.exact == true, b.exact == true
    if xa ~= xb then return xa end
    local ea, eb = a.entry, b.entry
    local ta = ea.displayLabel or ea.label
    local tb = eb.displayLabel or eb.label
    if #ta ~= #tb then return #ta < #tb end
    -- Cog rows last: their short labels ("Size") tie with the page's own rows.
    local ka = KIND_RANK[ea.kind] or (ea.isSection and 2 or ((ea.host or ea.cogTitle) and 4 or 3))
    local kb = KIND_RANK[eb.kind] or (eb.isSection and 2 or ((eb.host or eb.cogTitle) and 4 or 3))
    if ka ~= kb then return ka < kb end
    if ea.module ~= eb.module then
        local ra, rb = _moduleRank[ea.module] or 1000, _moduleRank[eb.module] or 1000
        if ra ~= rb then return ra < rb end
        return ea.module < eb.module
    end
    if ea.order and eb.order and ea.order ~= eb.order then return ea.order < eb.order end
    if ea.page ~= eb.page then return ea.page < eb.page end
    return ea.label < eb.label
end

-------------------------------------------------------------------------------
--  Coarse (whole-page) candidates: "Damage Meters -> Spell History" as a
--  single jump target, not just its individual options. Built directly from
--  the module registry's static config (title/pages), so unlike the
--  fine-grained index above it needs no build pass or navigation to exist --
--  page/module identity is known the moment a sub-addon registers, before
--  any of its widgets are ever constructed.
-------------------------------------------------------------------------------
local _coarseCandidates
local _pageByKey -- pick key -> page candidate

local function BuildCoarseCandidates()
    _coarseCandidates, _pageByKey = {}, {}
    for folder, config in pairs(ns.modules or {}) do
        if config.pages then
            -- moduleText is the plain-text form used in the haystack.
            local moduleLabel, moduleText = ModuleLabel(config, folder)
            for order, page in ipairs(config.pages) do
                local pageLabel = PageLabel(folder, page)
                -- A relabeled tab stays findable by its page identity too.
                local pageText = pageLabel
                if ns.GetTabLabel(folder, page) ~= page then
                    pageText = pageLabel .. " " .. EllesmereUI.L(page)
                end
                _coarseCandidates[#_coarseCandidates + 1] = {
                    kind = "page",
                    -- Combined haystack so a query spanning both module and page words
                    -- (e.g. "damage spell") still matches, not just one half of it.
                    label = moduleText .. " " .. pageText,
                    lLabel = (moduleText .. " " .. pageText):lower(),
                    nLabel = ((moduleText .. pageText):lower():gsub(" ", "")),
                    lPage = pageLabel:lower(),
                    nPage = (pageLabel:lower():gsub(" ", "")),
                    order = order,
                    displayLabel = pageLabel,
                    moduleLabel = moduleLabel,
                    module = folder,
                    page = page,
                }
                _pageByKey["\2" .. folder .. "\1" .. page] = _coarseCandidates[#_coarseCandidates]
            end
        end
    end
end

-- Module-name filter: "raid frames border style" should search "border style" WITHIN
-- Raid Frames, not fuzzy-match the whole phrase everywhere. Lazily built alias list
-- (module titles + sidebar display names, both localized), longest alias first so "raid
-- frames" can never lose to a shorter overlapping alias. Only a FULL alias at the START
-- of the query (followed by more words) activates the filter -- single overlapping
-- words ("raid" also appears in other modules' option labels) never do.
local _moduleAliases

local function BuildModuleAliases()
    _moduleAliases = {}
    local seen = {}
    local function Add(alias, folder, wholeOnly)
        if not alias then return end
        alias = alias:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if alias == "" then return end
        local key = alias .. "\1" .. folder
        if seen[key] then return end
        seen[key] = true
        _moduleAliases[#_moduleAliases + 1] = { alias = alias, folder = folder, wholeOnly = wholeOnly }
    end
    for folder, config in pairs(ns.modules or {}) do
        Add(config.title and EllesmereUI.L(config.title), folder)
        -- A plugin's section label filters to all of that plugin's modules.
        if config._pluginLabel then Add(EllesmereUI.L(config._pluginLabel), folder) end
    end
    if EllesmereUI.ADDON_ROSTER then
        for _, entry in ipairs(EllesmereUI.ADDON_ROSTER) do
            if ns.modules and ns.modules[entry.folder] then
                Add(entry.display and EllesmereUI.L(entry.display), entry.folder)
            end
        end
    end
    -- Hand-curated shorthands on top of the titles/display names, matching
    -- how players actually abbreviate the modules. Folders that never
    -- registered a module simply don't get their shorthands.
    local EXTRA_ALIASES = {
        EllesmereUIMythicTimer     = { "m+ timer", "m+", "m+ tools", "mythic+ timer" },
        EllesmereUICooldownManager = { "cdm" },
        -- Without the "+", and the module's former name.
        EllesmereUIBlizzardSkin    = { "blizzard skins", "blizz ui enhanced" },
        EllesmereUIQuickdraw       = { "radial", "wheel", "ring menu", "palette", "grid", "arc", "fan", "action wheel", "action palette", "action menu" },
        EllesmereUILoadoutManager  = { "gear swap", "talent swap", "equipment manager", "loadouts" },
        -- The module's former name.
        EllesmereUIRaidFrames      = { "raid frames" },
    }
    -- Typed in full only: as a prefix, "h" or "gen" would put Global Settings first.
    -- Not a bare "settings": a full alias anywhere in a query filters to the module.
    if ns.modules and ns.modules[EllesmereUI.GLOBAL_KEY] then
        Add("home", EllesmereUI.GLOBAL_KEY, true)
        Add("general settings", EllesmereUI.GLOBAL_KEY, true)
    end
    for folder, list in pairs(EXTRA_ALIASES) do
        if ns.modules and ns.modules[folder] then
            for _, a in ipairs(list) do Add(a, folder) end
        end
    end
    table.sort(_moduleAliases, function(a, b) return #a.alias > #b.alias end)
end

-- Alternate spellings a query may use for a feature whose option labels
-- name it differently; see the synonym pass in SearchIndex. Terms are
-- plain lowercase words (no pattern characters) and engage from their
-- first SYNONYM_MIN_PREFIX letters (shorter terms need all of theirs).
-- Only add pairs whose alternate really appears in option labels.
local QUERY_SYNONYMS = {
    { "skyriding",       { "dragon riding", "dragonriding" } },
    { "sky riding",      { "dragon riding", "dragonriding" } },
    -- Abbreviations
    { "cd",              { "cooldown" } },
    { "cds",             { "cooldown" } },
    { "global cooldown", { "gcd" } },
    { "hp",              { "health" } },
    { "ab",              { "action bar" } },
    { "uf",              { "unit frame" } },
    { "rf",              { "raid frame" } },
    { "experience",      { "xp" } },
    { "lfg",             { "group finder", "queue" } },
    { "m+",              { "mythic", "keystone" } },
    { "mplus",           { "mythic", "keystone" } },
    -- Other words for the same thing
    { "transparency",    { "opacity" } },
    { "alpha",           { "opacity" } },
    { "kick",            { "interrupt" } },
    { "interrupt",       { "kick" } },
    { "cleanse",         { "dispel" } },
    { "purge",           { "dispel" } },
    { "decurse",         { "dispel" } },
    { "aggro",           { "threat" } },
    { "hotkey",          { "keybind" } },
    { "keybind",         { "hotkey" } },
    { "binding",         { "hotkey" } },
    { "inventory",       { "bag" } },
    { "bags",            { "bag" } },
    { "colour",          { "color" } },
    { "shield",          { "absorb" } },
    { "absorb",          { "shield" } },
    { "stacks",          { "charges" } },
    { "charges",         { "stacks" } },
    { "plates",          { "nameplate" } },
    { "hotbar",          { "action bar" } },
    { "buffs",           { "aura" } },
    { "debuffs",         { "aura" } },
    { "aura",            { "buff", "debuff" } },
    { "move",            { "position", "unlock" } },
    { "drag",            { "position", "unlock" } },
    { "layer",           { "strata" } },
    { "level",           { "strata" } },
    { "combo points",    { "resource" } },
    { "holy power",      { "resource" } },
    { "chi",             { "resource" } },
    { "soul shards",     { "resource" } },
    { "runes",           { "resource" } },
    { "mouse",           { "mouseover" } },
    { "hover",           { "mouseover" } },
    { "transparent",     { "fade" } },
    { "hide when",       { "fade" } },
    { "quest",           { "objective", "tracker" } },
    -- A choice inside a dropdown (dropdown values are not indexed): its row
    { "compact",         { "bag display", "bank display" } },
}
-- WoW Forever's Name Format (first or last names; Forever Essentials > General).
if EllesmereUI.IS_FOREVER then
    QUERY_SYNONYMS[#QUERY_SYNONYMS + 1] = { "surname", { "name format" } }
end
local SYNONYM_MIN_PREFIX = 3

-- Multi-word queries: every word must appear in the label, tooltip or the
-- entry's path (ctx), and at least one in the label or tooltip, so a bare
-- path ("character sheet") does not list every row under it. Plain finds
-- only; words found in the label rank first, then the tooltip.
local WORD_TIER_ALL, WORD_TIER_SOME = 4, 2
local MAX_GROUP_MEMBERS = 50
local function WordPass(words)
    local scored, nw = {}, #words
    local function Consider(list)
        for _, entry in ipairs(list) do
            do
                local lab, loc, tip, ctx = entry.lLabel, entry.lLoc, entry.lTip, entry.ctx or ""
                local inLabel, inTip, first = 0, 0, 99
                for k = 1, nw do
                    local w = words[k]
                    local p = lab:find(w, 1, true) or (loc and loc:find(w, 1, true))
                    if p then
                        inLabel = inLabel + 1
                        if p < first then first = p end
                    elseif tip and tip:find(w, 1, true) then
                        inTip = inTip + 1
                    elseif not ctx:find(w, 1, true) then
                        inLabel = -1
                        break
                    end
                end
                if inLabel >= 0 and inLabel + inTip > 0 then
                    local tier = inLabel == nw and WORD_TIER_ALL or WORD_TIER_SOME
                    scored[#scored + 1] = { entry = entry, score = tier * TIER
                        + math.min(inLabel, 9) * 1000 + math.min(inTip, 9) * 100 + math.max(0, 99 - first) }
                end
            end
        end
    end
    Consider(_searchIndex)
    Consider(_coarseCandidates)
    return scored
end

local function SearchIndex(query, maxResults)
    maxResults = maxResults or 30
    local needle = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if needle == "" then return {} end
    if not _coarseCandidates then BuildCoarseCandidates() end
    if not _moduleAliases then BuildModuleAliases() end
    -- Split once; every pass reads the query's words, none changes them.
    local qWords = {}
    for w in needle:gmatch("%S+") do qWords[#qWords + 1] = w end

    -- Detect a module name ANYWHERE in the query (whole words only, longest alias
    -- first) and split it off as an ADDITIVE boost: "raid frames border style" and
    -- "border style raid frames" both surface "border style" within Raid Frames on top
    -- of the plain full-query results (merged below -- never replacing them).
    local filterSet, subNeedle
    for _, m in ipairs(_moduleAliases) do
        local a = m.alias
        local s, e = needle:find(a, 1, true)
        while s do
            local beforeOk = s == 1 or needle:sub(s - 1, s - 1) == " "
            local afterOk = e == #needle or needle:sub(e + 1, e + 1) == " "
            if beforeOk and afterOk then
                -- Several modules can share one alias (a plugin section label).
                filterSet = {}
                for _, other in ipairs(_moduleAliases) do
                    if other.alias == a then filterSet[other.folder] = true end
                end
                subNeedle = (needle:sub(1, s - 1) .. " " .. needle:sub(e + 1))
                    :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                break
            end
            s, e = needle:find(a, s + 1, true)
        end
        if filterSet then break end
    end

    -- Progressive variant: while a module name is still being TYPED, the
    -- trailing word(s) act as a module-name PREFIX -- "border style r"
    -- (then "ra", "raid f", ...) already narrows to every module whose name
    -- starts that way, engaging the filter long before the full name is
    -- typed. Longest trailing chunk wins; all prefix-matching modules are
    -- searched as a union, so ambiguity ("r") just means a wider net.
    if not filterSet then
        local words = qWords
        for i = 1, #words do
            local chunk = table.concat(words, " ", i, #words)
            local set
            for _, m in ipairs(_moduleAliases) do
                if not m.wholeOnly and m.alias:sub(1, #chunk) == chunk then
                    set = set or {}
                    set[m.folder] = true
                end
            end
            if set then
                filterSet = set
                subNeedle = i > 1 and table.concat(words, " ", 1, i - 1) or ""
                break
            end
        end
    end

    -- One scoring pass over both indexes. With a module filter active, only
    -- those modules' entries are considered, matched against the remainder
    -- of the query; a BARE module name (or name prefix) lists pages.
    local function ScorePass(folderSet, n)
        local scored = {}
        -- "stats" also finds "stat" as a near-exact hit, one tier down.
        local stem = #n >= 4 and n:sub(-1) == "s" and n:sub(1, -2) or nil
        local ns = n:gsub(" ", "")
        local words = qWords
        if n ~= needle then
            words = {}
            for w in n:gmatch("%S+") do words[#words + 1] = w end
        end
        local function Consider(list)
            for _, entry in ipairs(list) do
                if not folderSet or folderSet[entry.module] then
                    if n == "" then
                        if entry.kind == "page" then
                            -- Bare module name: pages in tab order.
                            scored[#scored + 1] = { entry = entry, score = TIER - entry.order }
                        end
                    else
                        local s = ScoreEntry(entry, n, stem, ns, words)
                        if s then
                            local exact = entry.lLabel == n or entry.lLoc == n or entry.lPage == n
                            scored[#scored + 1] = { entry = entry, score = s, exact = exact }
                        end
                    end
                end
            end
        end
        Consider(_searchIndex)
        Consider(_coarseCandidates)
        return scored
    end

    -- ADDITIVE module filter: the plain full-query pass ALWAYS runs, and a
    -- detected module name layers its remainder-scoped hits ON TOP (boosted
    -- above plain hits so the targeted interpretation ranks first). The
    -- filter must never REMOVE cross-module matches: typing "hide b"
    -- (trailing "b" = a Bags/Blizz UI prefix) must not drop QoL's "Hide
    -- Blizzard Party Panel", which still matches the plain query.
    local scored = ScorePass(nil, needle)
    local seenEntries = {}
    for _, sc in ipairs(scored) do seenEntries[sc.entry] = sc end
    -- Merge a further pass by entry: an entry already present keeps its
    -- best score, a new one joins the list.
    local function Merge(list, boost)
        for _, sc in ipairs(list) do
            local s = sc.score + boost
            local existing = seenEntries[sc.entry]
            if existing then
                if s > existing.score then existing.score = s; existing.exact = sc.exact end
            else
                sc.score = s
                seenEntries[sc.entry] = sc
                scored[#scored + 1] = sc
            end
        end
    end
    -- Query synonyms: a term players type for a feature whose labels still
    -- carry another name. The term engages while it is still being TYPED:
    -- the longest prefix of it (at least SYNONYM_MIN_PREFIX letters) that
    -- sits in the query on word boundaries, or runs to the end of the
    -- query, is swapped for each alternate spelling and that variant runs
    -- as one more plain pass at the same score -- "sky", "skyr" and
    -- "skyriding" all surface every "Dragon Riding" control. Variants are
    -- deduped so two terms sharing a prefix do not score twice.
    local altNeedles
    for _, syn in ipairs(QUERY_SYNONYMS) do
        local term = syn[1]
        local matched = false
        for len = #term, math.min(SYNONYM_MIN_PREFIX, #term), -1 do
            local pre = term:sub(1, len)
            local s, e = needle:find(pre, 1, true)
            while s do
                local beforeOk = s == 1 or needle:sub(s - 1, s - 1) == " "
                local afterOk = e == #needle or needle:sub(e + 1, e + 1) == " "
                if beforeOk and afterOk then
                    altNeedles = altNeedles or {}
                    for _, alt in ipairs(syn[2]) do
                        altNeedles[needle:sub(1, s - 1) .. alt .. needle:sub(e + 1)] = true
                    end
                    matched = true
                    break
                end
                s, e = needle:find(pre, s + 1, true)
            end
            if matched then break end
        end
    end
    if altNeedles then
        for altNeedle in pairs(altNeedles) do
            Merge(ScorePass(nil, altNeedle), 0)
        end
    end
    if filterSet then
        Merge(ScorePass(filterSet, subNeedle), 6 * TIER) -- above every tier
    end
    if #qWords > 1 then Merge(WordPass(qWords), 0) end

    -- Picked before: up to most of a tier's spread on top, never into the next tier.
    local picks = EllesmereUIDB and EllesmereUIDB.searchPicks
    -- Left by an import that turned Remember Picks off.
    if picks and not EllesmereUI.SearchPicksOn() then EllesmereUIDB.searchPicks, picks = nil, nil end
    -- A bare module name lists its pages in tab order, unboosted.
    if picks and not (filterSet and subNeedle == "") then
        local now = time()
        for key, p in pairs(picks) do
            local e = _seenKeys[key] or _pageByKey[key]
            local sc = e and seenEntries[e]
            if sc then
                local within = sc.score % TIER
                sc.score = sc.score - within + math.min(TIER - 1, within + math.floor(math.min(999, 250 * PickValue(p, now))))
            end
        end
    end

    table.sort(scored, SortResults)
    local out = {}
    -- Merge similar results: rows that read the same (kind and label) fold
    -- into the best-ranked one's place, its members in rank order. A typed
    -- word that tells them apart leaves one match, which shows on its own.
    local slotOf = { p = {}, s = {}, o = {} }
    for _, sc in ipairs(scored) do
        local e = sc.entry
        local kind = e.kind == "page" and "p" or (e.isSection and "s" or "o")
        local text = kind == "p" and e.lPage or e.lLabel
        local i = slotOf[kind][text]
        if i then
            local g = out[i]
            if not g.isGroup then
                g = setmetatable({ isGroup = true, members = { g } }, { __index = g })
                out[i] = g
            end
            if #g.members < MAX_GROUP_MEMBERS then g.members[#g.members + 1] = e end
        elseif #out < maxResults then
            out[#out + 1] = e
            slotOf[kind][text] = #out
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  One-time, staggered, off-screen pre-build pass.
--  Populates the index for pages the user hasn't opened yet this session,
--  without ever showing that UI. The hidden root frame is never shown, so
--  nothing built under it ever renders or runs OnUpdate scripts -- WoW gates
--  both on the frame's (and its ancestors') shown state. Rebuilt fresh every
--  login (no SavedVariables caching), so the index can never go stale
--  relative to the actual option code.
-------------------------------------------------------------------------------
local _prebuildDone = false
local _hiddenParent

-- The main panel's content-header chrome is ONE real, shared frame -- not scoped to
-- whatever parent/wrapper a buildPage happens to be given -- and several sub-addons
-- call these directly from buildPage. For real navigation that's fine (there's only
-- ever one visible page), but during a hidden pre-build it would overwrite whatever
-- header the user is actually looking at. These methods are also nil outright until
-- the panel's first Show() (they're defined inside CreateMainFrame), which a plain
-- guard clause inside them can't help with -- so stub them out here for the
-- duration of each pre-build call instead, then restore whatever was there before
-- (nil or the real function).
local _CONTENT_HEADER_METHODS = {
    "SetContentHeader", "UpdateContentHeaderHeight", "SetContentHeaderHeightSilent",
    "ClearContentHeader", "HideContentHeader",
}

-- A single hidden build of one (folder, page). Optionally switches the
-- page's own internal selector (CDM bar / action bar key / unit) to
-- selectorKey first via selectorSetter, so options gated behind a
-- non-default selector value get indexed too -- otherwise they'd only ever
-- be searchable after the player manually visits that selector value once.
-------------------------------------------------------------------------------
--  FRAMELESS INDEX PASS (2026-08-03, user directive: the index pass must
--  never build frames -- the old hidden prebuild created ~48 real pages =
--  10-25MB of permanent frames, and WoW frames are never freed).
--
--  The pass still RUNS every page builder (attribution, data-driven rows,
--  selector variants and localization all keep working), but the builders
--  run against a stub widget factory: EllesmereUI.Widgets is swapped to
--  AbsorberW for exactly the synchronous buildPage call. Every stub reads
--  the SAME declarative fields the real factory's TagOptionRow /
--  IndexSlotForSearch lines read (verified 1:1 against EllesmereUI_Widgets
--  2026-08-03) and registers the same index entries -- then returns an
--  "absorber" instead of a frame.
--
--  The absorber survives anything a builder does to a widget: any string
--  key yields another absorber, any call no-ops, arithmetic on it yields
--  plain numbers (y-offset math), NUMERIC keys yield nil so ipairs/# see an
--  empty array (an auto-vivifying [1] would never terminate). Builders'
--  own direct CreateFrame chrome still lands on the real (reused, hidden)
--  wrapper -- a handful of small frames on the few custom-chrome pages,
--  not the widget mass. A builder the absorber cannot survive is caught by
--  the existing pcall and that page falls back to live-navigation indexing,
--  loudly in dev mode.
--
--  MAINTENANCE CONTRACT: a NEW WidgetFactory method that registers search
--  entries needs a matching stub here, or its rows are invisible to search
--  until the page is built live. Mirror the real factory's registration
--  lines exactly (which args/fields, which slots).
-------------------------------------------------------------------------------
local _absSection = nil
local _absWrapper = nil
local _absorberMeta
_absorberMeta = {
    __index = function(_, k)
        -- Numeric keys read as ABSENT so ipairs()/#/array probes terminate.
        if type(k) == "number" then return nil end
        return setmetatable({}, _absorberMeta)
    end,
    __call = function() return setmetatable({}, _absorberMeta) end,
    __add = function() return 100 end,
    __sub = function() return 100 end,
    __mul = function() return 100 end,
    __div = function() return 1 end,
    __mod = function() return 0 end,
    __pow = function() return 1 end,
    __unm = function() return -100 end,
    __concat = function() return "" end,
    __len = function() return 0 end,
    __lt = function() return false end,
    __le = function() return false end,
    __tostring = function() return "EUIAbsorber" end,
}
local function NewAbsorber()
    return setmetatable({}, _absorberMeta)
end

-- Absorber rows keep what a cog reads off its host (the slot cfg, the row
-- label, the Blizzard Style hidden flag), so cogs register during the pass.
local function AbsorberLabeled(text)
    local a = NewAbsorber()
    if type(text) == "string" then rawset(a, "_labelText", text) end
    return a
end
local function AbsorberRow(leftCfg, rightCfg, midCfg, hidden)
    local row = NewAbsorber()
    for key, cfg in pairs({ _leftRegion = leftCfg or false, _rightRegion = rightCfg or false, _midRegion = midCfg or false }) do
        local rgn = NewAbsorber()
        if cfg then rawset(rgn, "_widgetCfg", cfg) end
        if hidden then rawset(rgn, "_searchIgnore", true) end
        rawset(row, key, rgn)
    end
    return row
end

-- Mirrors IndexSlotForSearch in EllesmereUI_Widgets.lua exactly: empty
-- labels skip, localized form rides along only when it differs, section is
-- the absorber pass's own tracker (the real path reads it off the parent
-- frame; the absorber parent is shared, so the pass tracks it here), and
-- the selector context comes from the same global the live path uses.
local function AbsorberRegister(labelText, tooltipText, isSection)
    if not EllesmereUI._RegisterSearchEntry then return end
    if type(labelText) ~= "string" or labelText == "" then return end
    local loc = EllesmereUI.L(labelText)
    local sel = EllesmereUI._buildingSelector
    EllesmereUI._RegisterSearchEntry(labelText, loc ~= labelText and loc or nil,
        type(tooltipText) == "string" and tooltipText or nil,
        EllesmereUI._buildingModule, EllesmereUI._buildingPage,
        isSection and labelText or _absSection,
        sel and sel.setter, sel and sel.key, isSection or nil)
end

local AbsorberW = {}
function AbsorberW:SectionHeader(parent, text, yOffset)
    _absSection = text
    AbsorberRegister(text, nil, true)
    return NewAbsorber(), 40
end
function AbsorberW:Toggle(parent, text, yOffset, getValue, setValue, tooltip)
    AbsorberRegister(text, tooltip)
    return AbsorberLabeled(text), 40
end
function AbsorberW:Slider(parent, text, yOffset, minVal, maxVal, step, getValue, setValue, tooltip, pixel)
    AbsorberRegister(text, tooltip)
    return AbsorberLabeled(text), 40
end
function AbsorberW:Dropdown(parent, text, yOffset, values, getValue, setValue, order, tooltip)
    AbsorberRegister(text, tooltip)
    return AbsorberLabeled(text), 40
end
function AbsorberW:Checkbox(parent, text, yOffset, getValue, setValue, tooltip)
    AbsorberRegister(text, tooltip)
    return AbsorberLabeled(text), 40
end
function AbsorberW:ColorPicker(parent, text, yOffset, getValue, setValue, hasAlpha)
    AbsorberRegister(text, nil)
    return NewAbsorber(), 40
end
function AbsorberW:Button(parent, text, yOffset, onClick)
    AbsorberRegister(text, nil)
    return NewAbsorber(), 40
end
function AbsorberW:WideButton(parent, text, yOffset, onClick, btnWidth)
    AbsorberRegister(text, nil)
    return NewAbsorber(), 40
end
function AbsorberW:DualRow(parent, yOffset, leftCfg, rightCfg)
    -- A row the live factory hides for Blizzard Style has nothing to find.
    local BS = EllesmereUI.BlizzStyle
    if BS and BS.RowHidden and BS.RowHidden(leftCfg, rightCfg) then return AbsorberRow(leftCfg, rightCfg, nil, true), 0 end
    AbsorberRegister(leftCfg and leftCfg.text, leftCfg and leftCfg.tooltip)
    AbsorberRegister(rightCfg and rightCfg.text, rightCfg and rightCfg.tooltip)
    return AbsorberRow(leftCfg, rightCfg), 40
end
function AbsorberW:TripleRow(parent, yOffset, leftCfg, midCfg, rightCfg, splits)
    AbsorberRegister(leftCfg and leftCfg.text, leftCfg and leftCfg.tooltip)
    AbsorberRegister(midCfg and midCfg.text, midCfg and midCfg.tooltip)
    AbsorberRegister(rightCfg and rightCfg.text, rightCfg and rightCfg.tooltip)
    return AbsorberRow(leftCfg, rightCfg, midCfg), 40
end
function AbsorberW:MultiSwatchRow(parent, yOffset, cfg)
    AbsorberRegister(cfg and cfg.text, nil)
    return AbsorberLabeled(cfg and cfg.text), 40
end
function AbsorberW:DropdownWithOffsets(parent, yOffset, dropdownCfg, xSliderCfg, ySliderCfg)
    AbsorberRegister(dropdownCfg and dropdownCfg.text, dropdownCfg and dropdownCfg.tooltip)
    AbsorberRegister(xSliderCfg and xSliderCfg.text, xSliderCfg and xSliderCfg.tooltip)
    AbsorberRegister(ySliderCfg and ySliderCfg.text, ySliderCfg and ySliderCfg.tooltip)
    -- The live row's slot labels (DropdownWithOffsets)
    local row = AbsorberRow()
    rawset(row._leftRegion, "_slotLabel", dropdownCfg and dropdownCfg.text or "")
    rawset(row._rightRegion, "_slotLabel", (xSliderCfg and xSliderCfg.text or "") .. " " .. (ySliderCfg and ySliderCfg.text or ""))
    return row, 40
end
function AbsorberW:WideDualButton(parent, text1, text2, yOffset, onClick1, onClick2, btnWidth)
    AbsorberRegister(text1, nil)
    AbsorberRegister(text2, nil)
    return NewAbsorber(), 40
end
function AbsorberW:WideTripleButton(parent, text1, text2, text3, yOffset, onClick1, onClick2, onClick3, btnWidth, disabledOpts)
    AbsorberRegister(text1, nil)
    AbsorberRegister(text2, nil)
    AbsorberRegister(text3, nil)
    return NewAbsorber(), 40
end
function AbsorberW:WideDropdown(parent, title, yOffset, values, getValue, setValue, order, btnWidth, disabledValuesFn)
    AbsorberRegister(title, nil)
    return AbsorberLabeled(title), 40
end
function AbsorberW:TripleDropdown(parent, configs, yOffset)
    AbsorberRegister(configs and configs[1] and configs[1][1], nil)
    AbsorberRegister(configs and configs[2] and configs[2][1], nil)
    AbsorberRegister(configs and configs[3] and configs[3][1], nil)
    return NewAbsorber(), 40
end
function AbsorberW:TripleSlider(parent, configs, yOffset)
    -- Parity with the real factory: it tags an EMPTY row label and indexes
    -- no slots, so the absorber registers nothing either.
    return NewAbsorber(), 40
end
function AbsorberW:Spacer(parent, yOffset, height)
    return NewAbsorber(), height or 20
end
-- Any factory method NOT stubbed above (added later, or missed): absorb it
-- rather than erroring the whole page -- the page still indexes everything
-- its known widgets register; dev mode announces the gap so the stub gets
-- added per the maintenance contract.
setmetatable(AbsorberW, { __index = function(_, k)
    if EllesmereUI.IsDevModeActive() then
        print("|cffff6060EUI GlobalSearch:|r no absorber stub for W:" .. tostring(k)
            .. " -- its rows are invisible to search until built live. Add a stub.")
    end
    return function() return NewAbsorber(), 40 end
end })

local function CogSearchKey(module, page, host, title)
    return module .. "\1" .. page .. "\1" .. (host or "") .. "\1" .. (title or "")
end

-- Indexes an inline cog popup's rows (called first thing by BuildInlineCog,
-- live and in the index pass). Context as CogDot.Key reads it: the host
-- row's section and label, and the popup title. rawget throughout: the
-- region may be an absorber.
function EllesmereUI._RegisterCogSearch(rgn, opts)
    if type(rgn) ~= "table" or type(opts) ~= "table" then return end
    local rows = opts.rows
    if opts.sections then
        rows = {}
        for _, sec in ipairs(opts.sections) do
            for _, r in ipairs(sec.rows or {}) do rows[#rows + 1] = r end
        end
    end
    if type(rows) ~= "table" or not rows[1] then return end
    if rawget(rgn, "_searchIgnore") then return end
    local section
    if getmetatable(rgn) == _absorberMeta then
        section = _absSection
    else
        local row = rgn.GetParent and rgn:GetParent()
        if row and rawget(row, "_searchIgnore") then return end
        local sec = rawget(rgn, "_sectionHeader") or (row and rawget(row, "_sectionHeader"))
        if not sec and row and row.GetParent then sec = rawget(row:GetParent() or {}, "_currentSection") end
        section = sec and rawget(sec, "_sectionName")
    end
    local cfg = rawget(rgn, "_widgetCfg") or rawget(rgn, "_cfg")
    local host = cfg and cfg.text
    if type(host) ~= "string" or host == "" then host = rawget(rgn, "_labelText") end
    if type(host) ~= "string" or host == "" then host = rawget(rgn, "_slotLabel") end
    local title = type(opts.title) == "string" and opts.title or nil
    -- No host label: "" still keys the row apart from a page row of the same name.
    if type(host) ~= "string" or host:match("^%s*$") then host = title or "" end
    local sel = EllesmereUI._buildingSelector
    -- As CogDot.Key: a cog built after its page build (a lazily built panel) takes the shown page.
    local module = EllesmereUI._buildingModule or (EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule())
    local page = EllesmereUI._buildingPage or (EllesmereUI.GetActivePage and EllesmereUI:GetActivePage())
    for _, r in ipairs(rows) do
        local label = type(r) == "table" and r.label
        if type(label) == "string" and label ~= "" then
            local loc = EllesmereUI.L(label)
            EllesmereUI._RegisterSearchEntry(label, loc ~= label and loc or nil,
                type(r.tooltip) == "string" and r.tooltip or nil,
                module, page, section, sel and sel.setter, sel and sel.key, nil, host, title)
        end
    end
    -- The cog's identity, for MarkSearchCog after a jump to one of its rows.
    if module and page then return CogSearchKey(module, page, host, title) end
end

-- ONE reused wrapper for every job: with the widget factory absorbed,
-- the only things ever created on it are the rare custom-chrome frames
-- a few builders make directly -- not the per-page widget mass.
local function HiddenWrapper()
    if not _absWrapper then
        _hiddenParent = CreateFrame("Frame", nil, UIParent)
        _hiddenParent:Hide()
        _absWrapper = CreateFrame("Frame", nil, _hiddenParent)
        _absWrapper:SetSize(1030, 4000)
    end
    return _absWrapper
end

-- Live builds queue their index-only builds until the pass starts, so a
-- player who never searches never pays for them.
-- While the pass runs, a queued build is one more of its jobs.
local _queuedIndexBuilds, _passJobs = {}, nil
function EllesmereUI._QueueIndexBuild(fn, ...)
    if _prebuildDone and not _passJobs then return EllesmereUI._IndexOnlyBuild(fn, ...) end
    local q = {
        fn = fn, n = select("#", ...), args = { ... }, card = EllesmereUI._searchContext,
        module = EllesmereUI._buildingModule or (EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()),
        page = EllesmereUI._buildingPage or (EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()),
        sel = EllesmereUI._buildingSelector,
    }
    if _passJobs then _passJobs[#_passJobs + 1] = { queued = q }
    else _queuedIndexBuilds[#_queuedIndexBuilds + 1] = q end
end

local function RunQueuedIndexBuild(q)
    EllesmereUI._buildingModule, EllesmereUI._buildingPage = q.module, q.page
    EllesmereUI._buildingSelector, EllesmereUI._searchContext = q.sel, q.card
    EllesmereUI._IndexOnlyBuild(q.fn, unpack(q.args, 1, q.n))
    EllesmereUI._buildingModule, EllesmereUI._buildingPage = nil, nil
    EllesmereUI._buildingSelector, EllesmereUI._searchContext = nil, nil
end

-- Builds fn(wrapper, ...) as the index pass would, from inside a live build:
-- for settings a live page leaves unbuilt (a closed Window Skins card), which
-- the pass never sees once the page is cached. Refreshes it registers are dropped.
function EllesmereUI._IndexOnlyBuild(fn, ...)
    local wrapper = HiddenWrapper()
    local wasPre, realWidgets, sec = EllesmereUI._prebuilding, EllesmereUI.Widgets, _absSection
    local refreshSnap = EllesmereUI._SnapshotAndClearWidgetRefreshList()
    EllesmereUI._prebuilding, EllesmereUI.Widgets, _absSection = true, AbsorberW, nil
    local ok, err = pcall(fn, wrapper, ...)
    EllesmereUI._prebuilding, EllesmereUI.Widgets, _absSection = wasPre, realWidgets, sec
    if refreshSnap then EllesmereUI._RestoreWidgetRefreshList(refreshSnap) end
    if not ok and EllesmereUI.IsDevModeActive() then
        print("|cffff6060EUI GlobalSearch:|r index-only build failed: " .. tostring(err))
    end
end

local function PrebuildOnce(config, folder, page, selectorSetter, selectorKey)
    if selectorSetter and selectorKey then selectorSetter(selectorKey) end
    local wrapper = HiddenWrapper()
    EllesmereUI._buildingModule = folder
    EllesmereUI._buildingPage = page
    EllesmereUI._prebuilding = true

    -- Isolate the shared widget-refresh registry so this off-screen build's
    -- widgets can never leak their refresh closures into whatever page the
    -- user is actually looking at (or into that page's cache snapshot).
    local refreshSnap = EllesmereUI._SnapshotAndClearWidgetRefreshList()
    -- buildPage functions call some live game APIs (currency lists, class info)
    -- directly during construction, not only inside getValue closures. pcall so one
    -- module's edge case can never block indexing the rest; any such page simply falls
    -- back to being indexed by live navigation instead. Surfaced in dev mode so a
    -- genuinely broken builder is not silently swallowed forever by the indexing pass.
    -- FRAMELESS: the widget factory is swapped to the absorber for exactly
    -- this synchronous call (builders fetch `local W = EllesmereUI.Widgets`
    -- inside their bodies -- verified no file-scope captures 2026-08-03),
    -- and restored on EVERY exit before anything else can read it.
    _absSection = nil
    local realWidgets = EllesmereUI.Widgets
    EllesmereUI.Widgets = AbsorberW
    local ok, err = pcall(config.buildPage, page, wrapper, -6)
    EllesmereUI.Widgets = realWidgets
    if not ok and EllesmereUI.IsDevModeActive() then
        print("|cffff6060EUI GlobalSearch:|r prebuild failed for "
            .. tostring(folder) .. "::" .. tostring(page) .. ": " .. tostring(err))
    end
    if refreshSnap then EllesmereUI._RestoreWidgetRefreshList(refreshSnap) end
    EllesmereUI._searchContext = nil

    -- Some buildPage implementations register cleanup (event listeners, etc.) via
    -- parent:HookScript("OnHide", ...), expecting it to fire once the user navigates
    -- away. Hide the wrapper on the chance that helps -- but don't rely on it: a frame
    -- that's never been effectively visible (its ancestor, _hiddenParent, was hidden
    -- before wrapper was ever shown) may not fire OnHide just because wrapper:Hide() is
    -- called on it. Any buildPage that registers session-long listeners (event frames,
    -- etc.) must guard their creation with EllesmereUI._prebuilding itself rather than
    -- depend on this to clean them up.
    wrapper:Hide()

    EllesmereUI._buildingModule = nil
    EllesmereUI._buildingPage = nil
    EllesmereUI._buildingSelector = nil
    EllesmereUI._prebuilding = nil
end

-- One job = ONE hidden page build. Selector variants are expanded into
-- separate jobs at list-build time (not looped synchronously inside a single
-- job) because the variant pages are the suite's heaviest; the per-frame
-- budget in RunPrebuildPass then spreads them across frames.
local function PrebuildJob(job)
    if job.queued then return RunQueuedIndexBuild(job.queued) end
    local config = job.config
    if not config.buildPage then return end
    -- Re-check (not just at job-list-build time): the staggered pass spans many
    -- frames, so the player may have visited and cached this exact page live in the
    -- meantime -- rebuilding it hidden would be a redundant, wasted build. The selector
    -- restore still runs: the live visit happened at whatever selection the player made
    -- themselves, but an EARLIER variant job may have left the module's selector moved.
    local cacheKey = job.folder .. "::" .. job.page
    if not (ns.pageCache and ns.pageCache[cacheKey] and not ns.pageCache[cacheKey].stale) then
        local savedMethods = {}
        for _, name in ipairs(_CONTENT_HEADER_METHODS) do
            savedMethods[name] = EllesmereUI[name]
            EllesmereUI[name] = function() end
        end
        PrebuildOnce(config, job.folder, job.page, job.selectorSetter, job.selectorKey)
        for _, name in ipairs(_CONTENT_HEADER_METHODS) do
            EllesmereUI[name] = savedMethods[name]
        end
    end
    -- Set on the LAST variant job of a page: restore whatever the player actually had
    -- selected so a later live visit isn't left showing the last-built variant.
    if job.restoreSetter and job.restoreKey then
        job.restoreSetter(job.restoreKey)
    end
end

-- Deliberately NOT run at login: even frameless, running every page builder costs real
-- CPU, so only users who actually use the search ever pay it. Since 2026-08-03 the pass
-- builds NO frames (absorber layer above): its entire footprint is the index strings
-- plus transient garbage, versus the old hidden-build's 10-25MB of permanent page
-- frames. Focusing the search box (or its first query) triggers this pass (see
-- EnsureSearchUI); coarse module/page results need no build and show immediately,
-- and onComplete re-runs the query so late-indexed rows appear without retyping.
local PREBUILD_BUDGET_MS = 4

local function RunPrebuildPass(onComplete)
    if _prebuildDone then return end
    _prebuildDone = true

    local jobs = {}
    for folder, config in pairs(ns.modules or {}) do
        -- Plugins can opt a module out of the hidden pass (searchPrebuild =
        -- false); its pages are then indexed by live navigation only.
        if config.pages and config._searchPrebuild ~= false then
            for _, page in ipairs(config.pages) do
                -- Already indexed by live navigation -- skip it. Rebuilding it
                -- hidden would be redundant, and would also reassign whatever
                -- module-global closures (header builders, etc.) that page's
                -- buildPage captures to hidden-build versions that a later
                -- cache-restore could pick up instead of the live ones.
                local cacheKey = folder .. "::" .. page
                -- A link tab (config.pageLinks) has no page of its own to build.
                if not (ns.pageCache and ns.pageCache[cacheKey] and not ns.pageCache[cacheKey].stale)
                   and not (config.pageLinks and config.pageLinks[page]) then
                    -- Selector-driven pages (CDM bar / unit dropdowns) expand to one
                    -- job PER variant so each tick stays one build; the last variant
                    -- job carries the restore of the player's own selection.
                    local variants = config.getPrebuildVariants and config.getPrebuildVariants(page)
                    if variants and variants.keys and #variants.keys > 0 then
                        for k, key in ipairs(variants.keys) do
                            local job = {
                                folder = folder, page = page, config = config,
                                selectorSetter = variants.setter, selectorKey = key,
                            }
                            if k == #variants.keys and variants.setter and variants.currentKey then
                                job.restoreSetter = variants.setter
                                job.restoreKey = variants.currentKey
                            end
                            jobs[#jobs + 1] = job
                        end
                    else
                        jobs[#jobs + 1] = { folder = folder, page = page, config = config }
                    end
                end
            end
        end
    end

    for _, q in ipairs(_queuedIndexBuilds) do jobs[#jobs + 1] = { queued = q } end
    _queuedIndexBuilds, _passJobs = nil, jobs
    local i, workMs, frames, entries0, worstFrame = 0, 0, 0, #_searchIndex, 0
    -- Dev mode: what the pass cost, to compare branches in game. The worst
    -- frame and the slowest builds are what a player could feel.
    local function Report()
        if not EllesmereUI.IsDevModeActive() then return end
        print(("|cff60c0ffEUI GlobalSearch:|r index pass %.1f ms over %d frames (worst %.1f ms), %d builds, %d entries (%d total)")
            :format(workMs, frames, worstFrame, #jobs, #_searchIndex - entries0, #_searchIndex))
        local function What(j)
            local q = j.queued
            return q and ("card " .. tostring(q.card) .. " (" .. tostring(q.module) .. "::" .. tostring(q.page) .. ")")
                or (j.folder .. "::" .. j.page .. (j.selectorKey and (" [" .. tostring(j.selectorKey) .. "]") or ""))
        end
        table.sort(jobs, function(a, b) return a.ms > b.ms end)
        for k = 1, math.min(10, #jobs) do
            print(("   %.1f ms, %d entries: %s"):format(jobs[k].ms, jobs[k].entries, What(jobs[k])))
        end
        -- Builds that indexed nothing new (skipped jobs cost ~0 ms).
        local idle, idleMs = {}, 0
        for _, j in ipairs(jobs) do
            if j.entries == 0 and j.ms >= 0.5 then idle[#idle + 1] = What(j); idleMs = idleMs + j.ms end
        end
        if idle[1] then print(("   %.1f ms in %d builds that added no entries: %s"):format(idleMs, #idle, table.concat(idle, ", "))) end
    end
    local function StepJob()
        -- A full page build is a multi-millisecond main-thread hit; never do
        -- that during combat. Pause the pass and resume once combat ends.
        if InCombatLockdown() then
            EllesmereUI.CombatQueue.Defer(StepJob, function() C_Timer.After(0.05, StepJob) end)
            return
        end
        -- As many builds as fit in a small per-frame budget (at least one),
        -- then yield a frame: fast to finish without a visible hitch.
        local t0 = debugprofilestop()
        frames = frames + 1
        repeat
            i = i + 1
            local job = jobs[i]
            if not job then
                _passJobs = nil
                local spent = debugprofilestop() - t0
                workMs = workMs + spent
                if spent > worstFrame then worstFrame = spent end
                _prebuildComplete = true
                Report()
                if onComplete then onComplete() end
                return
            end
            local j0, n0 = debugprofilestop(), #_searchIndex
            PrebuildJob(job)
            job.ms, job.entries = debugprofilestop() - j0, #_searchIndex - n0
        until debugprofilestop() - t0 > PREBUILD_BUDGET_MS
        local spent = debugprofilestop() - t0
        workMs = workMs + spent
        if spent > worstFrame then worstFrame = spent end
        C_Timer.After(0, StepJob)
    end
    if not jobs[1] then _passJobs = nil end
    if jobs[1] then
        -- Next frame, not synchronously: the trigger is a keystroke handler
        -- and the first page build should not lag the typing.
        C_Timer.After(0, StepJob)
    else
        _prebuildComplete = true
        if onComplete then onComplete() end
    end
end

-------------------------------------------------------------------------------
--  Persistent search entry point + results popup.
--
--  Reuses the existing always-visible sidebar search box (placeholder
--  "Search Features...", EllesmereUI._sidebarSearchBox) as the entry point
--  rather than adding a new button/box of our own -- it's already the
--  natural, always-visible "search" affordance in the panel. We only add a
--  results popup beneath it via HookScript, so the box's existing behavior
--  (filtering the sidebar addon/page list) is untouched.
-------------------------------------------------------------------------------
local _searchUIBuilt = false
local popup, resultRows
local results, selIdx = {}, 1 -- last shown results; Tab/arrows move selIdx, Enter opens it

local RESULT_ROW_H = 34
local RESULT_ROW_GAP = 4   -- breathing room between result rows
local MAX_VISIBLE_RESULTS = 12  -- popup height in rows; more scroll
local MAX_RESULTS = 50
local ROW_STEP = RESULT_ROW_H + RESULT_ROW_GAP

local function GetModuleDisplayName(folder)
    local config = ns.modules and ns.modules[folder]
    if config and config.title then return (ModuleLabel(config, folder)) end
    if EllesmereUI.ADDON_ROSTER then
        for _, entry in ipairs(EllesmereUI.ADDON_ROSTER) do
            if entry.folder == folder then return EllesmereUI.L(entry.display) end
        end
    end
    return folder
end

local function JoinBreadcrumb(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v and v ~= "" then parts[#parts + 1] = v end
    end
    return table.concat(parts, BREADCRUMB_ARROW)
end

-- Section headers are ALL CAPS in the option pages ("GLOBAL OPTIONS");
-- results display them as Title Case ("Global Options"). ASCII-only word
-- matching: non-Latin localized names pass through unchanged, which is the
-- safe outcome. Display-only -- the index keeps the raw name for matching.
local function TitleCaseSection(s)
    -- Only ALL-CAPS names need the conversion. Already mixed-case section
    -- labels (window-skin card titles like "LFG Menu") pass through
    -- untouched -- lowering them first would mangle acronyms ("Lfg Menu").
    if s ~= s:upper() then return s end
    return (s:lower():gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end))
end

local function JumpToResult(entry, sidebarSearchBox)
    RecordPick(entry)
    -- Coarse (whole-page) results have no single option to highlight -- just land on
    -- the page. Fine-grained option/section results scroll to and glow the specific
    -- matching row via EllesmereUI:NavigateToElementSettings (the same deep-link
    -- machinery the What's New page uses) instead of ApplyInlineSearch: that function
    -- is a *filter* -- it hides every section that doesn't match -- so reusing it
    -- here to "highlight" a single row could collapse the whole page down to just
    -- that one row's section, or even to nothing at all if the matched row isn't part
    -- of the page's current state (e.g. a CDM bar-type-specific option while a
    -- different bar is selected). NavigateToElementSettings only scrolls + glows; it
    -- never hides anything, so a row it can't currently find (same bar-type case)
    -- just means no scroll/glow happens -- the page is left exactly as the player
    -- already had it, not blanked out.
    if entry.kind == "page" or not entry.section then
        EllesmereUI:SelectModule(entry.module)
        EllesmereUI:SelectPage(entry.page)
    else
        -- Some pages (CDM Bars, Action Bars Display, Unit Frames) show
        -- entirely different content depending on an internal selector --
        -- which bar/unit is picked via that page's own dropdown -- so the
        -- matched row may not exist under whatever selection happens to be
        -- active right now. If this entry was registered under a specific
        -- selection, restore that exact selection first (NavigateToElement-
        -- Settings' preSelectFn) so the row is actually there to find.
        local preSelectFn
        if entry.selectorSetter and entry.selectorKey then
            preSelectFn = function() entry.selectorSetter(entry.selectorKey) end
        end
        -- A cog row is not on the page: glow the row whose cog holds it.
        -- An empty host would match the section's first row: glow nothing then.
        local glow = entry.label
        if entry.host or entry.cogTitle then glow = entry.host ~= "" and entry.host or nil end
        EllesmereUI:NavigateToElementSettings(entry.module, entry.page, entry.section, preSelectFn, glow)
    end
    -- Mark the cog that holds the row once the jump's row glow has run
    -- (any other jump clears the mark).
    if EllesmereUI.MarkSearchCog then
        local key = (entry.host or entry.cogTitle) and CogSearchKey(entry.module, entry.page, entry.host, entry.cogTitle)
        C_Timer.After(0.25, function() EllesmereUI.MarkSearchCog(key) end)
    end
    if popup then popup:Hide() end
    if sidebarSearchBox then sidebarSearchBox:SetText("") end
end

local function EnsureSearchUI()
    if _searchUIBuilt then return end
    local clickArea = EllesmereUI._clickArea
    local sidebarSearchBox = EllesmereUI._sidebarSearchBox
    if not clickArea or not sidebarSearchBox then return end
    _searchUIBuilt = true

    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
    local fontPath = (EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"

    -- Results popup, anchored below the existing sidebar search box.
    popup = CreateFrame("Frame", nil, clickArea)
    popup:SetSize(380, MAX_VISIBLE_RESULTS * ROW_STEP - RESULT_ROW_GAP + 8)
    popup:SetPoint("TOPLEFT", sidebarSearchBox, "BOTTOMLEFT", 0, -4)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(220)
    popup:SetClampedToScreen(true)
    popup:Hide()
    local popupBg = popup:CreateTexture(nil, "BACKGROUND")
    popupBg:SetAllPoints()
    popupBg:SetColorTexture(0.098, 0.090, 0.082, 0.97)
    popup._brd = EllesmereUI.MakeRoundedBorder(popup, 1, 1, 1, 0.12, popupBg)

    local scroll = CreateFrame("ScrollFrame", nil, popup)
    -- Sized with its content, not from anchors: the bar hides only when the
    -- two heights match exactly, and an anchored height reads stale or rounded.
    scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4)
    scroll:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
    scroll:SetHeight(MAX_VISIBLE_RESULTS * ROW_STEP - RESULT_ROW_GAP)
    local resultsFrame = CreateFrame("Frame", nil, scroll)
    resultsFrame:SetSize(popup:GetWidth() - 8, ROW_STEP)
    scroll:SetScrollChild(resultsFrame)
    local UpdateThumb, ScrollTo = EllesmereUI.AttachSmoothScrollbar(scroll, {
        child = resultsFrame, step = ROW_STEP * 2, rightInset = 2, topInset = 6,
        trackParent = popup, panelWheel = true, passWheel = true,
    })

    -- What the rows show: the results, with an expanded merged row's members
    -- listed under it (depth 1). Rows are made as first needed, then reused.
    local display, expanded = {}, nil
    resultRows = {}
    local Activate
    local function PlaceText(row, indent)
        row._label:ClearAllPoints()
        row._label:SetPoint("LEFT", row, "LEFT", 8 + indent, 8)
        row._label:SetPoint("RIGHT", row, "RIGHT", -8, 8)
        row._sub:ClearAllPoints()
        row._sub:SetPoint("LEFT", row, "LEFT", 8 + indent, -9)
        row._sub:SetPoint("RIGHT", row, "RIGHT", -8, -9)
    end
    local function MakeRow(i)
        local row = CreateFrame("Button", nil, resultsFrame)
        row:SetHeight(RESULT_ROW_H)
        -- Right inset leaves room for the scrollbar.
        row:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 1, -(i - 1) * ROW_STEP)
        row:SetPoint("TOPRIGHT", resultsFrame, "TOPRIGHT", -6, -(i - 1) * ROW_STEP)

        local hl = row:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0)

        local lbl = row:CreateFontString(nil, "OVERLAY")
        EllesmereUI.PrimeFontShadow(lbl, true)
        lbl:SetFont(fontPath, 14, "")
        lbl:SetTextColor(0.85, 0.85, 0.88, 1)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)

        local sub = row:CreateFontString(nil, "OVERLAY")
        EllesmereUI.PrimeFontShadow(sub, true)
        sub:SetFont(fontPath, 12, "")
        sub:SetTextColor(1, 1, 1, 0.45)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)

        row:SetScript("OnEnter", function() hl:SetColorTexture(1, 1, 1, 0.08) end)
        row:SetScript("OnLeave", function() hl:SetColorTexture(1, 1, 1, (i == selIdx and display[i]) and 0.08 or 0) end)
        row:SetScript("OnClick", function() Activate(i) end)

        row._hl = hl
        row._label = lbl
        row._sub = sub
        PlaceText(row, 0)
        row:Hide()
        resultRows[i] = row
        return row
    end
    MakeRow(1)

    -- scrollIntoView: keep a keyboard selection on screen.
    local function SetSelected(i, scrollIntoView)
        if resultRows[selIdx] then resultRows[selIdx]._hl:SetColorTexture(1, 1, 1, 0) end
        selIdx = i
        resultRows[selIdx]._hl:SetColorTexture(1, 1, 1, 0.08)
        if scrollIntoView then
            local top, cur, visH = (i - 1) * ROW_STEP, scroll:GetVerticalScroll(), scroll:GetHeight()
            if top < cur then
                ScrollTo(top)
            elseif top + RESULT_ROW_H > cur + visH then
                ScrollTo(top + RESULT_ROW_H - visH)
            end
        end
    end

    -- The label and breadcrumb of one result row.
    local function EntryText(entry, accentHex)
        if entry.kind == "page" then
            -- Coarse whole-page result: prefixed like sections so it
            -- reads as "go to this page", not a specific option on it.
            return accentHex .. EllesmereUI.L("Page") .. ":|r " .. entry.displayLabel, entry.moduleLabel
        elseif entry.isSection then
            local name = TitleCaseSection(entry.label)
            if entry.labelLoc then
                name = name .. "  (" .. TitleCaseSection(entry.labelLoc) .. ")"
            end
            return accentHex .. EllesmereUI.L("Section") .. ":|r " .. name,
                JoinBreadcrumb(GetModuleDisplayName(entry.module), PageLabel(entry.module, entry.page),
                    entry.card and EllesmereUI.L(entry.card))
        end
        local cogHost = entry.host ~= "" and entry.host or entry.cogTitle
        return entry.labelLoc and (entry.label .. "  (" .. entry.labelLoc .. ")") or entry.label,
            JoinBreadcrumb(GetModuleDisplayName(entry.module), PageLabel(entry.module, entry.page),
                entry.card and EllesmereUI.L(entry.card), cogHost and EllesmereUI.L(cogHost))
    end

    -- A merged row's sub-line names what tells its members apart: the first
    -- of module, page, card, popup host, section that differs among them.
    local PLACE_LEVELS = {
        function(e) return GetModuleDisplayName(e.module) end,
        function(e) return PageLabel(e.module, e.page) end,
        function(e) return e.card and EllesmereUI.L(e.card) end,
        function(e)
            local h = e.host ~= "" and e.host or e.cogTitle
            return h and EllesmereUI.L(h)
        end,
        function(e) return e.section and TitleCaseSection(e.section) end,
    }
    local function GroupPlaces(g)
        local names
        for _, level in ipairs(PLACE_LEVELS) do
            local list, seen = {}, {}
            for _, e in ipairs(g.members) do
                local n = level(e)
                if n and not seen[n] then seen[n] = true; list[#list + 1] = n end
            end
            names = names or list
            if #list > 1 then names = list break end
        end
        local count = #g.members >= MAX_GROUP_MEMBERS and (MAX_GROUP_MEMBERS .. "+") or #g.members
        return EllesmereUI.Lf("%s places: %s", count, table.concat(names, ", "))
    end

    -- Paints the display list; the scroll position and selection stay put.
    local function Render()
        local EG = EllesmereUI.ELLESMERE_GREEN
        local accentHex = EG and EllesmereUI.HexColor(EG.r, EG.g, EG.b) or EllesmereUI.COLOR_CODES.WHITE
        for i = #resultRows + 1, #display do MakeRow(i) end
        for i, row in ipairs(resultRows) do
            local item = display[i]
            if item then
                local entry, indent = item.entry, item.depth * 14
                local text, crumb = EntryText(entry, accentHex)
                if entry.isGroup then
                    text = text .. "  " .. accentHex .. (entry == expanded and "-" or "+") .. "|r"
                    crumb = GroupPlaces(entry)
                end
                row._label:SetText(text)
                row._sub:SetText(crumb)
                PlaceText(row, indent)
                row._hl:SetColorTexture(1, 1, 1, i == selIdx and 0.08 or 0)
                row:EnableMouse(true)
                row:Show()
            else
                row:Hide()
            end
        end
        local shown = #display
        if shown > 0 then
            local visH = math.min(shown, MAX_VISIBLE_RESULTS) * ROW_STEP - RESULT_ROW_GAP
            popup:SetHeight(visH + 8)
            scroll:SetHeight(visH)
            resultsFrame:SetHeight(shown * ROW_STEP - RESULT_ROW_GAP)
            -- Retyped while shown: refit the outline's bottom edge.
            popup._brd:Fit()
            popup:Show()
            UpdateThumb()
        end
        return shown
    end

    local function BuildDisplay()
        display = {}
        for _, entry in ipairs(results) do
            display[#display + 1] = { entry = entry, depth = 0 }
            if entry == expanded then
                for _, m in ipairs(entry.members) do display[#display + 1] = { entry = m, depth = 1 } end
            end
        end
    end

    -- A merged row opens or closes in place (one open at a time); any other row jumps.
    Activate = function(i)
        local item = display[i]
        if not item then return end
        local entry = item.entry
        if not entry.isGroup then return JumpToResult(entry, sidebarSearchBox) end
        expanded = expanded ~= entry and entry or nil
        BuildDisplay()
        for k, it in ipairs(display) do
            if it.entry == entry then selIdx = k break end
        end
        Render()
        -- Closing a long list can leave the offset past the end: clamp it.
        ScrollTo(scroll:GetVerticalScroll())
        SetSelected(selIdx, true)
    end

    local RunSearch
    -- Set once the index pass has finished: before that, 0 results may only
    -- mean "not indexed yet", so the "No results" row waits for it.
    local indexReady = false
    -- Started on focus, before the first letter, so the index is usually
    -- complete by the time a query is typed.
    local function StartPrebuild()
        if _prebuildDone then return end
        RunPrebuildPass(function()
            indexReady = true
            if sidebarSearchBox:GetText() ~= "" then RunSearch(true) end
        end)
    end
    sidebarSearchBox:HookScript("OnEditFocusGained", StartPrebuild)

    -- keepPlace: the index grew under an open popup; keep its open merged
    -- row, selection and scroll where the player left them.
    RunSearch = function(keepPlace)
        local query = sidebarSearchBox:GetText()
        local wasOpen, wasSel, wasScroll = expanded, selIdx, scroll:GetVerticalScroll()
        -- The index pass normally started on focus; a query typed without focus
        -- (e.g. pasted) starts it here. Coarse module/page results show immediately;
        -- the pass re-runs the query when it finishes. While a search is active, every "Show
        -- Less Common" section renders force-expanded with no link line; clearing the
        -- box collapses them back to their session state (transitions rebuild -- see
        -- SetLessCommonSearchActive in EllesmereUI_Widgets.lua).
        if EllesmereUI.SetLessCommonSearchActive then
            EllesmereUI.SetLessCommonSearchActive(query ~= "")
        end
        if query ~= "" then StartPrebuild() end
        results, expanded = SearchIndex(query, MAX_RESULTS), nil
        if keepPlace == true and wasOpen then
            for _, e in ipairs(results) do
                if e.isGroup and e.kind == wasOpen.kind and e.isSection == wasOpen.isSection
                   and e.lLabel == wasOpen.lLabel then expanded = e break end
            end
        end
        BuildDisplay()
        selIdx = keepPlace == true and math.max(1, math.min(wasSel, #display)) or 1
        local shown = Render()
        if shown == 0 and indexReady and query:match("%S") then
            -- Inert "No results" row instead of an empty popup. Pipes are
            -- shown literally so the query cannot inject escape codes.
            local row = resultRows[1]
            local q = query:gsub("||", "|"):gsub("|", "||")
            row._label:SetText(EllesmereUI.Lf("No results for %s", "\"" .. q .. "\""))
            row._sub:SetText(EllesmereUI.L("Check the spelling or try a different word"))
            row._hl:SetColorTexture(1, 1, 1, 0)
            row:EnableMouse(false)
            row:Show()
            popup:SetHeight(RESULT_ROW_H + 8)
            scroll:SetHeight(RESULT_ROW_H)
            resultsFrame:SetHeight(RESULT_ROW_H)
            popup._brd:Fit()
            popup:Show()
            UpdateThumb()
        elseif shown == 0 then
            popup:Hide()
        end
        ScrollTo(keepPlace == true and wasScroll or 0)
    end

    -- HookScript adds to the box's existing handlers rather than replacing
    -- them, so the sidebar addon/page filtering it already does keeps working.
    sidebarSearchBox:HookScript("OnTextChanged", RunSearch)
    sidebarSearchBox:HookScript("OnEnterPressed", function() Activate(selIdx) end)
    local function Step(d)
        local n = #display
        if n > 0 and popup:IsShown() then SetSelected((selIdx - 1 + d) % n + 1, true) end
    end
    sidebarSearchBox:HookScript("OnTabPressed", function() Step(IsShiftKeyDown() and -1 or 1) end)
    sidebarSearchBox:HookScript("OnArrowPressed", function(_, key)
        if key == "UP" then Step(-1) elseif key == "DOWN" then Step(1) end
    end)

    -- Click-anywhere-else closes the results: a global mouse-down listener
    -- registered only while the popup is shown (the same pattern as the
    -- dropdown widgets) -- non-blocking, world clicks pass through, and no
    -- per-frame OnUpdate work. Row clicks fire on mouse UP, and the DOWN
    -- lands while the cursor is over the popup, so results stay clickable.
    local clickOff = CreateFrame("Frame")
    clickOff:SetScript("OnEvent", function()
        if not popup:IsMouseOver() and not sidebarSearchBox:IsMouseOver() then
            popup:Hide()
        end
    end)
    popup:SetScript("OnShow", function() clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    popup:SetScript("OnHide", function() clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
end

-------------------------------------------------------------------------------
--  Wire the search hooks into the panel the first time it's opened, via any
--  entry point (Show / Toggle / ShowModule all funnel through the panel's
--  internal CreateMainFrame, which is what creates the sidebar search box
--  this file hooks into). No edits to EllesmereUI.lua needed for this --
--  standard same-addon method wrapping from a later-loaded file.
-------------------------------------------------------------------------------
for _, methodName in ipairs({ "Show", "Toggle", "ShowModule" }) do
    local original = EllesmereUI[methodName]
    if original then
        EllesmereUI[methodName] = function(self, ...)
            original(self, ...)
            EnsureSearchUI()
        end
    end
end
