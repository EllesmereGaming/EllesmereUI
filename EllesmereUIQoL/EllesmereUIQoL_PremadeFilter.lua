-------------------------------------------------------------------------------
--  EllesmereUIQoL_PremadeFilter.lua
--  Filter side panel for Blizzard's Premade Groups search results
--  (LFGListFrame.SearchPanel). Never starts a search of its own.
--
--  WHY THIS FILE NEVER TOUCHES panel.results -- read before editing
--
--  This module used to filter the way PremadeGroupsFilter does: copy
--  panel.results, filter/sort the copy, assign it back, call
--  LFGListSearchPanel_UpdateResults. That seam works, and it is why every
--  filter addon uses it -- but on 12.0 it permanently damages Blizzard's Group
--  Finder for the rest of the session. Confirmed live 2026-08-02 with
--  issecurevariable() (/euidiag lfg), run in a dungeon the moment the errors
--  fired; every INSECURE field below named EllesmereUIQoL.
--
--  The mechanism is that three Blizzard fields are READ BEFORE THEY ARE
--  WRITTEN, in the same function:
--      LFGListFrame.activePanel             read 319  -> written 322
--      LFGListApplicationDialog.activityID  read 3392 -> written 3397
--      SearchPanel.previousSearchText       read 2666 -> written 2670
--  A tainted read taints the execution that then performs the write, so once
--  any of them is tainted it can never be written securely again. There is no
--  addon-side cure: insecure code cannot make a secure write, and securecall
--  does not grant secure execution. They stay tainted until /reload.
--
--  Our old seam reached them one interaction removed from itself:
--      we write panel.results
--   -> LFGListSearchPanel_UpdateResults builds {resultID=results[index]}
--      elements while reading our table (2724-2728), so every elementData and
--      every button.resultID (2708) is tainted
--   -> the user clicks a row; LFGListSearchEntry_OnClick reads button.resultID
--   -> LFGListSearchPanel_SelectResult taints panel.selectedResult
--   -> LFGListSearchPanel_SignUp reads it (2861)
--   -> LFGListApplicationDialog_Show runs tainted: activityID is poisoned for
--      the session, and StaticPopupSpecial_Show queues the dialog tainted
--   -> LFGListSearchPanel_OnEvent reads that queue back through
--      StaticPopupSpecial_Hide (2228) on every LFG_LIST_SEARCH_RESULTS_RECEIVED,
--      immediately before LFGListSearchPanel_UpdateResultList (2231)
--   -> Blizzard's own rebuild now sorts tainted, and the comparator compares
--      searchResultInfo.numBNetFriends (3973). Inside an instance that number
--      is secret, and a secret compare under our taint throws.
--  One sign-up from a filtered list is enough, and the resulting errors have
--  pure-Blizzard stacks with our filter nowhere on them. Probing, pausing,
--  defusing the data provider and re-arming were all tried: they are post-hoc,
--  and this damage is written before any of them can react.
--
--  So the ownership seam is gone, and with it any chance of that class of bug.
--  What replaces it is a BEST ATTEMPT at the same feature within what can be
--  done without tainting anything:
--
--   1. REAL filtering runs through Blizzard's own advanced filter --
--      C_LFGList.SaveAdvancedFilter, applied server-side by C_LFGList.Search.
--      It is a C call: nothing we pass becomes Lua state Blizzard reads back,
--      and the results arrive through Blizzard's untainted event path. This
--      genuinely removes rows. It covers leader score, needs-tank/healer,
--      the four dungeon difficulties and the dungeon whitelist.
--      Its limits are Blizzard's: DUNGEONS ONLY (LFGList.lua:2653 nils the
--      advanced filter for every other category) and max level only.
--   2. Everything Blizzard's filter cannot express -- delisted, declined,
--      party fit, the expression box, and all raid filtering -- is applied as
--      a READ-ONLY verdict that dims the row instead of removing it. Reading
--      results taints nothing; only writing does.
--   3. SORTING IS GONE. Reordering means writing the results array (or its
--      elements), which is the same poison by another route. Blizzard's own
--      sort already puts declined last and friends first.
--
--  The remaining rules, unchanged:
--   - We never call LFGListSearchPanel_DoSearch, C_LFGList.Search,
--     LFGListSearchPanel_UpdateResults, LFGListSearchPanel_UpdateResultList or
--     LFGListSearchEntry_Update. Each of them writes Blizzard Lua state on our
--     execution. A saved advanced filter only takes effect on the next search,
--     which is exactly how Blizzard's own dropdown behaves (LFGList.lua:2394).
--   - The panel's click controls DO re-run that search, via the one route that
--     is not our execution: a SecureActionButtonTemplate forwarding the click to
--     SearchPanel.RefreshButton, so Blizzard's SECURE_ACTIONS.click runs DoSearch
--     in its own context. Proven live 2026-08-02 (EllesmereUISecretsDiag T33/T34).
--     Full rules at the "Secure search forwarding" block below -- in particular
--     never give one of those buttons an OnClick, and always register both click
--     edges. The score box is typed rather than clicked, so it carries its own
--     Apply button. Forwarding is switched off outside the dungeon browse, where
--     a search cannot apply the filter anyway.
--   - We write NO key onto any Blizzard frame or table. Module state lives in
--     file-locals; anything keyed by a Blizzard row lives in an external
--     weak-keyed table.
--   - Every per-result read goes through a pcall'd accessor and every consumed
--     field is issecretvalue()-checked. A failed or secret read makes the
--     criterion PASS (fail-open).
--   - Search results come back secret in some content (reported live inside a
--     Mythic+ key). We still PROBE every value before consuming it and stand
--     the verdict pass down entirely if anything is secret -- reading is safe,
--     but a secret value throws on any comparison we make of it.
--     C_ChatInfo.InChatMessagingLockdown() is a fast-path hint, not the
--     detector -- it has been seen false with secret kstrings live.
--   - HookScript (never SetScript) on Blizzard frames. Our own frames are ours.
--   - One deliberate exception, documented at its site: we replace SetPoint on
--     RaiderIO's own anchor frame so its profile window stops landing on top of
--     us. That frame is third-party and non-secure. The same move on a Blizzard
--     frame would be a taint bug.
--   - The user-supplied filter expression runs inside a setfenv'd table holding
--     nothing but sanitised scalars and four math helpers -- no _G, no
--     C_LFGList, no way back out. Every failure mode keeps the result.
--   - No hooks, feature events or UI frames exist until the feature is first
--     enabled; only a lone boot frame listening for PLAYER_LOGIN (the house
--     bootstrap, same as RaidTools) is created unconditionally.
-------------------------------------------------------------------------------

local EUI = EllesmereUI
local issecretvalue = issecretvalue or function() return false end

-- Blizzard_GroupFinder is load-on-demand, so the global may not exist yet when
-- this file loads; resolve it at use time (its value is 2 either way).
local function DungeonCategory()
    return GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
end

-- Unlike dungeons, Blizzard ships NO GROUP_FINDER_CATEGORY_ID_RAIDS global (the
-- dungeon one at LFGList.lua:9 is the only category constant that exists), so we
-- identify the raid category from live data instead of hardcoding it: the
-- category whose activities include a current raid. Resolved once, lazily, and
-- only ever consulted while the search panel is open.
local RAID_CATEGORY_FALLBACK = 3
local _raidCategory

local _rcOut
local function ReadRaidCategory()
    local cats = C_LFGList.GetAvailableCategories(0)
    if not cats or issecretvalue(cats) then return end
    for i = 1, #cats do
        local cat = cats[i]
        if type(cat) == "number" then
            -- nil, not 0: we need every activity in the category, not just the
            -- ungrouped ones (a raid tier's activities all live under a group).
            local acts = C_LFGList.GetAvailableActivities(cat, nil, Enum.LFGListFilter.PvE)
            if acts and not issecretvalue(acts) then
                for j = 1, #acts do
                    local t = C_LFGList.GetActivityInfoTable(acts[j])
                    if t and not issecretvalue(t) and t.isCurrentRaidActivity then
                        _rcOut = cat
                        return
                    end
                end
            end
        end
    end
end

local function RaidCategory()
    if _raidCategory then return _raidCategory end
    if type(C_LFGList.GetAvailableCategories) ~= "function"
        or type(C_LFGList.GetAvailableActivities) ~= "function"
        or type(C_LFGList.GetActivityInfoTable) ~= "function"
        or not (Enum and Enum.LFGListFilter and Enum.LFGListFilter.PvE) then
        _raidCategory = RAID_CATEGORY_FALLBACK
        return _raidCategory
    end
    _rcOut = nil
    pcall(ReadRaidCategory)
    _raidCategory = _rcOut or RAID_CATEGORY_FALLBACK
    return _raidCategory
end

-- Dungeon group composition we filter against (1 tank / 1 healer / 3 dps).
local SLOTS_TANK, SLOTS_HEALER, SLOTS_DPS = 1, 1, 3

-- Widened from 220 when the dungeon icon grid landed.
local PANEL_W = 260

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        premadeFilter = {
            enabled               = false,
            panelCollapsed        = false,
            minLeaderScoreEnabled = false,
            minLeaderScore        = 2000,
            needsTank             = false,
            needsHealer           = false,
            myRoleAvailable       = false,
            partyFit              = false,
            hideDeclined          = false,
            hideDelisted          = true,
            sortMode              = "DEFAULT",  -- DEFAULT | SCORE | AGE
            sortDescending        = true,
            friendsFirst          = true,
            -- Difficulty is filtered client-side on purpose: routing it through
            -- C_LFGList.SaveAdvancedFilter would rewrite the user's own
            -- Blizzard advanced-filter dropdown state behind their back.
            diffNormal            = false,
            diffHeroic            = false,
            diffMythic            = false,
            diffMythicPlus        = false,
            -- [activityGroupID] = true. Empty table means "every dungeon".
            dungeonWhitelist      = {},
            -- Raids get their own difficulty keys so switching category does not
            -- inherit a dungeon-shaped selection (and there is no raid M+).
            raidDiffNormal        = false,
            raidDiffHeroic        = false,
            raidDiffMythic        = false,
            raidWhitelist         = {},
            expressionEnabled     = false,
            expression            = "",
            -- Owned by EllesmereUIQoL_PremadeFilterDisplay.lua; the defaults
            -- live here because this file owns the shared DB registration.
            showLeaderScore       = false,
            memberDisplay         = "DEFAULT",
        },
    },
}

local db
local function P()
    return db and db.profile and db.profile.premadeFilter
end
local function Enabled()
    local p = P()
    return p and p.enabled and true or false
end

-------------------------------------------------------------------------------
--  Look & feel -- in-suite precedent (EUI_UpgradeCalc / EllesmereUIFriends):
--  plain frames painted with EllesmereUI.SolidTex + PP.CreateBorder, fonts via
--  GetFontPath/GetFontOutlineFlag. The S skin facade is the third-party entry
--  point only, so we use the namespace helpers directly like every other
--  in-suite window does.
-------------------------------------------------------------------------------
local function PP()
    return EUI and (EUI.PanelPP or EUI.PP)
end

local function SolidTex(parent, layer, r, g, b, a)
    if EUI and EUI.SolidTex then return EUI.SolidTex(parent, layer, r, g, b, a) end
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function Accent()
    local g = (EUI and EUI.ELLESMERE_GREEN) or nil
    if g and g.r then return g.r, g.g, g.b end
    return 0.047, 0.824, 0.616
end

local function PanelFont()
    return (EUI and EUI.GetFontPath and EUI.GetFontPath("extras")) or STANDARD_TEXT_FONT
end
local function PanelOutline()
    return (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("extras")) or ""
end

local function MFont(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local flags = PanelOutline()
    if EUI and EUI.PrimeFontShadow then EUI.PrimeFontShadow(fs, flags == "") end
    fs:SetFont(PanelFont(), size, flags)
    fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
    return fs
end

local function Border(frame, r, g, b, a, level)
    local pp = PP()
    if pp and pp.CreateBorder then
        pp.CreateBorder(frame, r, g, b, a, 1, "OVERLAY", level or 7)
    end
end

-------------------------------------------------------------------------------
--  Guarded result reads
--
--  Both readers run through pcall with their arguments passed in upvalues so
--  the guarded call never allocates a closure. Every consumed field is checked
--  with issecretvalue() before it can reach a comparison or the panel.
-------------------------------------------------------------------------------
-- issecretvalue() leads in all three: it is the one test a secret value never
-- throws on, and issecretvalue(nil) is false so the nil check still short-
-- circuits everything after it.
local function Num(v)
    if issecretvalue(v) or v == nil or type(v) ~= "number" then return nil end
    return v
end
local function Bool(v)
    if issecretvalue(v) or v == nil then return nil end
    return v and true or false
end
local function Str(v)
    if issecretvalue(v) or v == nil or type(v) ~= "string" then return nil end
    return v
end

-- C_LFGList's search-result readers are SecretInChatMessagingLockdown (see
-- LFGListInfoDocumentation.lua), and results do come back secret in a Mythic+
-- key (reported live). InChatMessagingLockdown() has been observed returning
-- FALSE while the result kstrings were already secret, so it is a fast-path
-- hint only -- the per-result probe below is the authority.
-- The probe still earns its keep now that nothing is written back. Reading a
-- secret value is harmless; COMPARING one under our taint throws, and every
-- criterion in the verdict pass is a comparison. So a single secret anywhere in
-- a result stands the whole pass down rather than letting it throw per row.
--
-- Historical note worth keeping, because it is what proves guarding our own
-- reads was never sufficient: Blizzard's row initializer consumes far more of
-- each result than we do -- it indexes searchResultInfo.activityIDs
-- (LFGList.lua:3187), and it does self.Name:SetText(searchResultInfo.name) and
-- then compares self.Name:GetWidth() (LFGList.lua:3236), because a fontstring
-- holding secret text returns a secret width. Both threw for every row while
-- this module still wrote panel.results, and that is exactly the exposure the
-- rewrite removed: Blizzard's renderer now never runs on our execution.
local _secretResults = false     -- a secret result read was seen this pass

local function InChatLockdown()
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not f then return false end
    local ok, v = pcall(f)
    return (ok and v) and true or false
end

local _rID, _rD

-- activityIDs is a nested table, so it gets its own guard: a throw while
-- reading it must not cost us the fields we already banked in ReadInfo.
local _rInfo
local _probeInfo          -- the info table ReadInfo fetched, for ProbeResult
local function ReadActivityIDs()
    local acts = _rInfo.activityIDs
    -- issecretvalue() first: testing a secret value for truth throws just as
    -- readily as consuming it, and a throw here would cost us the flag.
    if issecretvalue(acts) then _secretResults = true; return end
    if not acts then return end
    _rD.activityID = Num(acts[1])
end

local function ReadInfo()
    local info = C_LFGList.GetSearchResultInfo(_rID)
    if issecretvalue(info) then _secretResults = true; return end
    if not info then return end
    -- Stash before banking anything: if a field read below throws, the outer
    -- pcall swallows it and ProbeResult must still get the table.
    _probeInfo = info
    local d = _rD
    d.numMembers  = Num(info.numMembers)
    d.isDelisted  = Bool(info.isDelisted)
    d.age         = Num(info.age)
    d.score       = Num(info.leaderOverallDungeonScore)
    d.partyGUID   = Str(info.partyGUID)
    d.ilvl        = Num(info.requiredItemLevel)
    d.warMode     = Bool(info.isWarMode)
    local bn = Num(info.numBNetFriends) or 0
    local cf = Num(info.numCharFriends) or 0
    local gm = Num(info.numGuildMates) or 0
    d.friends  = bn + cf + gm
    d.friendly = d.friends > 0
    d.have = true

    _rInfo = info
    pcall(ReadActivityIDs)
    _rInfo = nil
end

-- Secret probe. Our own reads only touch the scalars this filter needs, so
-- they miss the fields Blizzard's initializer consumes and we do not -- the
-- name/comment/voiceChat kstrings above all. Anything secret anywhere in the
-- data that initializer reaches stands the whole pass down.
local PROBE_DEPTH = 3

local function ProbeTable(t, depth)
    -- pairs() over a non-secret table holding secret values is safe; the keys
    -- and values are not. issecretvalue() therefore comes before every truth
    -- test, type() call and index -- a secret value throws on all three. Keys
    -- get the same treatment Blizzard's own RestrictedInfrastructure gives them.
    for k, v in pairs(t) do
        if issecretvalue(k) or issecretvalue(v) then _secretResults = true; return end
        if depth < PROBE_DEPTH and type(v) == "table" then
            ProbeTable(v, depth + 1)
            if _secretResults then return end
        end
    end
end

local function ProbeResult()
    -- The info table ReadInfo already fetched (nested: activityIDs,
    -- leaderDungeonScoreInfo, leaderPvpRatingInfo, leaderBestDungeonScoreInfo).
    if _probeInfo then
        ProbeTable(_probeInfo, 1)
        if _secretResults then return end
    end

    -- Blizzard compares the TANK/HEALER/DAMAGER and class counts at
    -- LFGList.lua:3040-3050 and hands the table to LFGListGroupDataDisplay_Update.
    if C_LFGList.GetSearchResultMemberCounts then
        local counts = C_LFGList.GetSearchResultMemberCounts(_rID)
        if issecretvalue(counts) then _secretResults = true; return end
        if counts then
            ProbeTable(counts, 1)
            if _secretResults then return end
        end
    end

    -- appStatus/pendingStatus are compared and appDuration is used in
    -- arithmetic (LFGList.lua:3093-3183); the OnUpdate expiration path compares
    -- the derived value at 3264.
    if C_LFGList.GetApplicationInfo then
        local a, b, c, e = C_LFGList.GetApplicationInfo(_rID)
        if issecretvalue(a) or issecretvalue(b) or issecretvalue(c) or issecretvalue(e) then
            _secretResults = true
        end
    end
end

local function ReadApp()
    -- Undocumented at 12.0; guarded like everything else.
    local _, appStatus = C_LFGList.GetApplicationInfo(_rID)
    _rD.appStatus = Str(appStatus)
end

local function ReadMembers()
    local d = _rD
    local t, h, dps = 0, 0, 0
    for i = 1, d.numMembers do
        local mi = C_LFGList.GetSearchResultPlayerInfo(_rID, i)
        if mi and not issecretvalue(mi) then
            local role = Str(mi.assignedRole)
            if role == "TANK" then t = t + 1
            elseif role == "HEALER" then h = h + 1
            elseif role == "DAMAGER" then dps = dps + 1 end
        end
    end
    d.tanks, d.healers, d.dps = t, h, dps
    -- Only trust the composition if every member was accounted for; a partial
    -- roster must not make us claim a group "needs a tank".
    d.roleOK = ((t + h + dps) == d.numMembers)
end

-------------------------------------------------------------------------------
--  Per-pass cache. Entry tables are recycled through a pool so repeated passes
--  allocate nothing after the first search.
-------------------------------------------------------------------------------
local _cache, _pool = {}, {}

local function BeginPass()
    _secretResults = false
    for id, d in pairs(_cache) do
        wipe(d)
        _pool[#_pool + 1] = d
        _cache[id] = nil
    end
end

local function GetData(id)
    local d = _cache[id]
    if d then return d end
    local n = #_pool
    if n > 0 then d = _pool[n]; _pool[n] = nil else d = {} end
    _cache[id] = d

    _rID, _rD = id, d
    _probeInfo = nil
    local ok = pcall(ReadInfo)
    d.readOK = (ok and d.have) and true or false
    -- A probe that throws means it met something secret it could not test for
    -- first; treat it as a positive.
    if not pcall(ProbeResult) then _secretResults = true end
    _probeInfo = nil
    return d
end

local function EnsureApp(id, d)
    if d.appTried then return end
    d.appTried = true
    if not C_LFGList.GetApplicationInfo then return end
    _rID, _rD = id, d
    pcall(ReadApp)
end

local function EnsureRoles(id, d)
    if d.roleTried then return end
    d.roleTried = true
    local n = d.numMembers
    if not n or n < 1 or n > 40 then return end
    _rID, _rD = id, d
    pcall(ReadMembers)
end

-------------------------------------------------------------------------------
--  Activity cache. Activity metadata is static for the whole session, so this
--  one is NOT wiped per pass -- unlike the search-result cache above. Entries
--  are only ever created for activity IDs a search result actually referenced,
--  so the table stays a handful of rows. `false` is a negative cache entry
--  (the read failed once; do not keep hammering the API for it).
-------------------------------------------------------------------------------
local _activity = {}

local _aID, _aOut
local function ReadActivity()
    local t = C_LFGList.GetActivityInfoTable(_aID)
    if not t or issecretvalue(t) then return end
    local o = _aOut
    o.normal     = Bool(t.isNormalActivity) or false
    o.heroic     = Bool(t.isHeroicActivity) or false
    o.mythic     = Bool(t.isMythicActivity) or false
    o.mythicplus = Bool(t.isMythicPlusActivity) or false
    o.activityID = _aID
    o.groupID    = Num(t.groupFinderActivityGroupID)
    o.name       = Str(t.fullName)
    o.mapID      = Num(t.mapID)
    -- Raid activities do not carry the is*Activity flags above -- those are set
    -- for the dungeon browser only -- so difficulty has to come from here.
    o.diffID     = Num(t.difficultyID)
    o.rDiffID    = Num(t.redirectedDifficultyID)
    o.have = true
end

-------------------------------------------------------------------------------
--  Raid difficulty buckets.
--
--  LFGList.lua only ever reads isNormalActivity/isHeroicActivity/
--  isMythicActivity for GROUP_FINDER_CATEGORY_ID_DUNGEONS, and raid activities
--  leave them unset -- which is why difficulty filtering had to be keyed off
--  difficultyID for raids. IDs mirror DifficultyUtil.ID
--  (Blizzard_FrameXMLUtil/DifficultyUtil.lua:3-22); we read that table live when
--  it exists so the numbers are Blizzard's, not ours.
-------------------------------------------------------------------------------
local RAID_DIFF_BUCKET

local function BuildRaidDiffBuckets()
    if RAID_DIFF_BUCKET then return RAID_DIFF_BUCKET end
    local D = DifficultyUtil and DifficultyUtil.ID or {}
    local function id(name, fallback)
        local v = D[name]
        if type(v) == "number" then return v end
        return fallback
    end
    RAID_DIFF_BUCKET = {
        [id("Raid10Normal", 3)]        = "normal",
        [id("Raid25Normal", 4)]        = "normal",
        [id("Raid40", 9)]              = "normal",
        [id("PrimaryRaidNormal", 14)]  = "normal",
        [id("Raid10Heroic", 5)]        = "heroic",
        [id("Raid25Heroic", 6)]        = "heroic",
        [id("PrimaryRaidHeroic", 15)]  = "heroic",
        [id("PrimaryRaidMythic", 16)]  = "mythic",
        [id("RaidMythicFlexible", 233)]= "mythic",
        -- LFR, Timewalking and Story are real difficulties with no button of
        -- their own. They get a named bucket rather than being left unknown, so
        -- ticking "Normal" means Normal and does not quietly also keep LFR.
        [id("RaidLFR", 7)]             = "other",
        [id("PrimaryRaidLFR", 17)]     = "other",
        [id("RaidTimewalker", 33)]     = "other",
        [id("RaidStory", 220)]         = "other",
    }
    return RAID_DIFF_BUCKET
end

-- Always one of "normal" | "heroic" | "mythic" | "other" for an activity we
-- successfully read. An activity that reads fine but carries no difficulty we
-- recognise -- absent, 0, or an ID outside the table -- is a KNOWN state, not a
-- read failure, so it buckets as "other" and is excluded whenever a difficulty
-- box is ticked (World Bosses land here, matching PGF). Fail-open is reserved
-- for genuinely unreadable data, which is `a == nil` and handled by the caller.
local function RaidBucket(a)
    if a.normal then return "normal" end
    if a.heroic then return "heroic" end
    if a.mythic then return "mythic" end
    local map = BuildRaidDiffBuckets()
    return (a.diffID and map[a.diffID]) or (a.rDiffID and map[a.rDiffID]) or "other"
end

-- Returns the cached activity record, or nil when it could not be read (every
-- caller treats nil as "criterion passes").
local function ActivityInfo(activityID)
    if not activityID then return nil end
    local a = _activity[activityID]
    if a ~= nil then return a or nil end
    if type(C_LFGList.GetActivityInfoTable) ~= "function" then
        _activity[activityID] = false
        return nil
    end
    a = {}
    _aID, _aOut = activityID, a
    local ok = pcall(ReadActivity)
    if not (ok and a.have) then a = false end
    _activity[activityID] = a
    return a or nil
end

-------------------------------------------------------------------------------
--  Available dungeon list, enumerated exactly the way Blizzard's own advanced
--  filter dropdown does (current season, then the rest of the expansion, then
--  Timerunning). Nothing here is hardcoded, so it never needs per-season
--  maintenance.
-------------------------------------------------------------------------------
-- ordered { id = activityGroupID, name = string, season = bool }
local _dungeons = {}
local _dungeonSeen = {}
-- Checksum of the current id set. RefreshVisibility rebuilds this list on every
-- show, so the expensive icon work downstream keys off "did it actually change"
-- rather than "was it rebuilt".
local _dungeonSig = 0

local _dgFilter, _dgSeason
local function ReadDungeonGroups()
    local groups = C_LFGList.GetAvailableActivityGroups(DungeonCategory(), _dgFilter)
    if not groups or issecretvalue(groups) then return end
    for i = 1, #groups do
        local id = Num(groups[i])
        if id and not _dungeonSeen[id] then
            local name = Str(C_LFGList.GetActivityGroupInfo(id))
            if name then
                _dungeonSeen[id] = true
                _dungeons[#_dungeons + 1] = { id = id, name = name, season = _dgSeason }
            end
        end
    end
end

local function AddDungeonGroups(filter, season)
    if not filter then return end
    _dgFilter, _dgSeason = filter, season and true or false
    pcall(ReadDungeonGroups)
end

-- Returns true when the id set changed since the last call.
local function BuildDungeonList()
    wipe(_dungeons)
    wipe(_dungeonSeen)

    local F = Enum and Enum.LFGListFilter
    if F and F.PvE
        and type(C_LFGList.GetAvailableActivityGroups) == "function"
        and type(C_LFGList.GetActivityGroupInfo) == "function" then
        if F.CurrentSeason then
            AddDungeonGroups(bit.bor(F.CurrentSeason, F.PvE), true)
        end
        if F.CurrentExpansion and F.NotCurrentSeason then
            AddDungeonGroups(bit.bor(F.CurrentExpansion, F.NotCurrentSeason, F.PvE), false)
        end
        if F.Timerunning and PlayerIsTimerunning and PlayerIsTimerunning() then
            AddDungeonGroups(bit.bor(F.Timerunning, F.PvE), false)
        end
    end

    local sig = #_dungeons * 1000003
    for i = 1, #_dungeons do sig = sig + _dungeons[i].id * i end
    local changed = (sig ~= _dungeonSig)
    _dungeonSig = sig
    return changed
end

-------------------------------------------------------------------------------
--  Available raid list.
--
--  NOTE for the next reader: there is no Blizzard raid equivalent to copy here.
--  The advanced-filter dropdown (and EntryStillSatisfiesFilters) is gated to
--  GROUP_FINDER_CATEGORY_ID_DUNGEONS throughout LFGList.lua, so raids have no
--  Blizzard activity-group dropdown at all. This mirrors the *shape* of the
--  dungeon enumeration above -- narrow filter first so current content sorts to
--  the top, then a broad sweep, deduped -- using only real Enum.LFGListFilter
--  members. Still no hardcoded content: a new raid tier appears on its own.
-------------------------------------------------------------------------------
--  WHITELIST KEY SCHEME (shared by _raids entries and p.raidWhitelist):
--    grouped raid tier        -> [activityGroupID]   (always positive)
--    standalone raid activity -> [-activityID]       (always negative)
--  Collision is impossible by construction rather than by convention, and both
--  key forms stay plain numbers so the saved variable serialises unchanged.
--  WhitelistKey() below is the single place a search result is resolved to one.
local _raids = {}
local _raidSeen = {}
-- The (categoryID, filters) pair the current list was built for.
local _raidListCat, _raidListFilters

-- Mirror of LFGList.lua:122-129. Dungeons force Recommended and strip
-- NotRecommended; every other category uses its filters verbatim.
local function ResolveCategoryFilters(categoryID, filters)
    if categoryID == DungeonCategory() then
        local F = Enum and Enum.LFGListFilter
        if not F or not F.Recommended or not F.NotRecommended then return filters end
        return bit.band(bit.bnot(F.NotRecommended), bit.bor(filters, F.Recommended))
    end
    return filters
end

-- The filter set Blizzard itself would use for whatever the search panel is
-- currently showing. This is the crux of current-vs-legacy: "Raids" and
-- "Legacy Raids" are the SAME categoryID, split only by a Recommended /
-- NotRecommended bit that LFGListCategorySelection_UpdateCategoryButtons puts
-- on two buttons (LFGList.lua:562-565) and LFGListSearchPanel_SetCategory
-- stores as panel.filters (:2638-2641). Reading it is what keeps our list in
-- step with the tab the user is actually on; picking our own filter constants
-- is what made both tabs show the same wrong thing.
local function PanelFilters(panel)
    if not panel then return nil end
    local cat = panel.categoryID
    if not cat then return nil end
    local base = Num(panel.preferredFilters) or 0
    local own  = Num(panel.filters) or 0
    return bit.bor(base, ResolveCategoryFilters(cat, own)), cat
end

local _rgCat, _rgFilter
local function ReadRaidGroups()
    local groups = C_LFGList.GetAvailableActivityGroups(_rgCat, _rgFilter)
    if not groups or issecretvalue(groups) then return end
    for i = 1, #groups do
        local id = Num(groups[i])
        if id and not _raidSeen[id] then
            local name = Str(C_LFGList.GetActivityGroupInfo(id))
            if name then
                _raidSeen[id] = true
                _raids[#_raids + 1] = { id = id, name = name }
            end
        end
    end
end

-- World Bosses and friends are UNGROUPED activities: no activity group exists
-- for them, so GetAvailableActivityGroups cannot see them. Blizzard pairs the
-- group list with the groupID-0 form of GetAvailableActivities under the very
-- same filters and renders the two together (LFGList.lua:795-796) -- so these
-- follow the current/legacy split automatically, with no currency test of our
-- own to get wrong.
local function ReadRaidActivities()
    local acts = C_LFGList.GetAvailableActivities(_rgCat, 0, _rgFilter)
    if not acts or issecretvalue(acts) then return end
    for i = 1, #acts do
        local aid = Num(acts[i])
        local key = aid and -aid
        if key and not _raidSeen[key] then
            local t = C_LFGList.GetActivityInfoTable(aid)
            if t and not issecretvalue(t) then
                local name = Str(t.fullName)
                if name then
                    _raidSeen[key] = true
                    _raids[#_raids + 1] = { id = key, name = name, standalone = true }
                end
            end
        end
    end
end

-- Rebuilds only when the panel moved to a different category/filter pair, so
-- flipping between Raids and Legacy Raids re-enumerates but repeated shows of
-- the same tab do not.
local function BuildRaidList(panel)
    local filters, cat = PanelFilters(panel)
    if not filters then return end
    if cat == _raidListCat and filters == _raidListFilters then return end

    wipe(_raids)
    wipe(_raidSeen)
    _raidListCat, _raidListFilters = cat, filters

    if type(C_LFGList.GetAvailableActivityGroups) ~= "function" then return end
    if type(C_LFGList.GetActivityGroupInfo) ~= "function" then return end

    _rgCat, _rgFilter = cat, filters
    pcall(ReadRaidGroups)

    if type(C_LFGList.GetAvailableActivities) == "function"
        and type(C_LFGList.GetActivityInfoTable) == "function" then
        pcall(ReadRaidActivities)
    end
end

-------------------------------------------------------------------------------
--  Mythic+ dungeon icons.
--
--  C_ChallengeMode.GetMapTable() is the current season's keystone dungeon list,
--  so using it as the icon source keeps the grid season-accurate with no table
--  to maintain. GetMapUIInfo's `texture` return is a file ID usable directly in
--  SetTexture, the same as ChallengesDungeonIconMixin:SetUp. We DIVERGE from
--  Blizzard on the empty case: SetUp substitutes a stock placeholder icon
--  (Blizzard_ChallengesUI.lua:472-474) because its grid is a fixed set of
--  slots that must all render. Ours is a filter list, where a row of identical
--  placeholders would be worse than useless, so a missing texture drops the
--  dungeon to a labelled text row instead.
--
--  Maps are tied to activity groups by localized-name equality: both sides come
--  from the client in the same locale, so this is locale-safe without any
--  string massaging. GroupFinderActivityInfo.mapID gives a second, independent
--  route that repairs the mapping opportunistically as results stream in (see
--  NoteActivityMap) -- worth having because name equality is the kind of thing
--  that breaks quietly if Blizzard ever renames one side.
-------------------------------------------------------------------------------
local _mapByName = {}     -- localized dungeon name -> map record
local _mapByMapID = {}    -- GroupFinderActivityInfo.mapID -> map record
local _iconByGroup = {}   -- activityGroupID -> map record
-- Set when a filter pass repairs a mapping; the pass repaints the grid once.
local _iconsDirty = false

-- Reimplementation of AbbrevDungeon from EllesmereUIBags/EllesmereUIBags.lua
-- (~line 146) -- the house convention for keystone short names. Copied rather
-- than called because EllesmereUIBags may not be loaded.
local _abbrevSkip = {
    ["of"] = true, ["the"] = true, ["a"] = true, ["an"] = true,
    ["из"] = true, ["за"] = true, ["в"] = true, ["на"] = true,
    ["и"] = true, ["под"] = true, ["с"] = true,
}

local _abbrevCache = {}

local function Abbrev(name)
    if not name or name == "" then return "" end
    local hit = _abbrevCache[name]
    if hit then return hit end
    local abbr = ""
    -- Split on whitespace AND hyphens so "Nexus-Point Xenas" becomes NPX.
    for word in name:gmatch("[^%s%-]+") do
        if not _abbrevSkip[word:lower()] then
            -- First whole UTF-8 character: sub(1,1) would cut a Cyrillic or
            -- Hangul name mid-codepoint.
            local firstChar = word:upper():match("^[%z\1-\127\194-\244][\128-\191]*")
            abbr = abbr .. (firstChar or "")
        end
    end
    local ov = EUI and EUI._dungeonAbbrevOverride
    if ov and ov[abbr] then abbr = ov[abbr] end
    _abbrevCache[name] = abbr
    return abbr
end

local function ReadChallengeMaps()
    local maps = C_ChallengeMode.GetMapTable()
    if not maps or issecretvalue(maps) then return end
    for i = 1, #maps do
        local cmID = Num(maps[i])
        if cmID then
            local name, _, _, texture, _, mapID = C_ChallengeMode.GetMapUIInfo(cmID)
            name = Str(name)
            texture = Num(texture)
            mapID = Num(mapID)
            -- The field is nilable and 0 is Blizzard's "no icon" sentinel
            -- (it swaps in a placeholder at that point; we drop to a text row).
            if texture == 0 then texture = nil end
            if name and texture then
                local rec = { cmID = cmID, name = name, texture = texture, mapID = mapID }
                _mapByName[name] = rec
                if mapID then _mapByMapID[mapID] = rec end
            end
        end
    end
end

-- Third route, and in practice the one that carries the grid: walk the dungeon
-- category's activities up front and pair each activity group with its map by
-- mapID. Name equality alone leaves real gaps -- LFG activity-group names and
-- challenge-mode map names genuinely diverge for a number of dungeons -- and
-- waiting for the search results to supply the mapID means those dungeons sit
-- in the text list until the user happens to see one. This closes both.
local _adFilter
local function ReadDungeonActivityMaps()
    -- groupID nil = every activity in the category. Passing 0 would mean
    -- "ungrouped only" (LFGList.lua:796 renders that list beside the groups),
    -- which for dungeons is empty -- every dungeon activity belongs to a group.
    local acts = C_LFGList.GetAvailableActivities(DungeonCategory(), nil, _adFilter)
    if not acts or issecretvalue(acts) then return end
    for i = 1, #acts do
        local t = C_LFGList.GetActivityInfoTable(acts[i])
        if t and not issecretvalue(t) then
            local gid = Num(t.groupFinderActivityGroupID)
            local mid = Num(t.mapID)
            if gid and mid and not _iconByGroup[gid] then
                local rec = _mapByMapID[mid]
                if rec then _iconByGroup[gid] = rec end
            end
        end
    end
end

local function AddActivityMaps(filter)
    if not filter then return end
    _adFilter = filter
    pcall(ReadDungeonActivityMaps)
end

-- Second route: an activity we have actually seen carries both its group ID and
-- its mapID, which attaches an icon whose name never matched. Returns true when
-- it newly mapped a group, so the caller knows the grid needs repainting.
local function NoteActivityMap(a)
    if not a or not a.groupID or not a.mapID then return false end
    if _iconByGroup[a.groupID] then return false end
    local rec = _mapByMapID[a.mapID]
    if not rec then return false end
    _iconByGroup[a.groupID] = rec
    return true
end

-- Only current-season groups can own a keystone icon, so they alone decide
-- whether the expensive activity walks below are still worth running.
local function SeasonGroupsMapped()
    for i = 1, #_dungeons do
        local e = _dungeons[i]
        if e.season and not _iconByGroup[e.id] then return false end
    end
    return true
end

-- True once the activity walk has run for the current group set. RefreshVisibility
-- is wired to eight hooks and fires several times per Group Finder open, so
-- without this the walk would re-read every activity in the category each time.
local _iconWalkDone = false

-- `listChanged` comes from BuildDungeonList: a season rollover or a Timerunning
-- character swap changes the id set and forces the whole thing to be redone.
local function BuildDungeonIcons(listChanged)
    if _iconWalkDone and not listChanged then return end

    wipe(_mapByName)
    wipe(_mapByMapID)
    wipe(_iconByGroup)

    if not C_ChallengeMode
        or type(C_ChallengeMode.GetMapTable) ~= "function"
        or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then
        _iconWalkDone = true
        return
    end
    pcall(ReadChallengeMaps)

    for i = 1, #_dungeons do
        local e = _dungeons[i]
        local rec = _mapByName[e.name]
        if rec then _iconByGroup[e.id] = rec end
    end

    -- Then close the name-mismatch gaps from the activity list itself. Each
    -- walk is skipped once every season group already has an icon -- in the
    -- common case the narrow walk finishes the job and the broad one, which
    -- reads every activity in the category, never runs at all.
    if type(C_LFGList.GetAvailableActivities) == "function" then
        local F = Enum and Enum.LFGListFilter
        if F and F.PvE then
            if F.CurrentSeason and not SeasonGroupsMapped() then
                AddActivityMaps(bit.bor(F.CurrentSeason, F.PvE))
            end
            if not SeasonGroupsMapped() then
                AddActivityMaps(F.PvE)
            end
        end
    end

    -- Replay the mapID route over every activity already in the session cache,
    -- so a name mismatch is repaired for the grid's FIRST paint instead of
    -- waiting for the next filter pass to stumble over that activity.
    for _, a in pairs(_activity) do
        if a then NoteActivityMap(a) end
    end

    _iconWalkDone = true
end

-------------------------------------------------------------------------------
--  Player / party role context (recomputed once per pass)
-------------------------------------------------------------------------------
local _myRole, _needT, _needH, _needD

local function MySpecRole()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getRole = GetSpecializationRole
        or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole)
    if not getSpec or not getRole then return "DAMAGER" end
    local spec = getSpec()
    if not spec then return "DAMAGER" end
    return getRole(spec) or "DAMAGER"
end

local function RefreshRoleContext()
    _myRole = MySpecRole()
    _needT, _needH, _needD = 0, 0, 0
    local n = GetNumGroupMembers() or 0
    local inParty = (n > 1) and not IsInRaid()
    if not inParty then
        if _myRole == "TANK" then _needT = 1
        elseif _myRole == "HEALER" then _needH = 1
        else _needD = 1 end
        return
    end
    for i = 0, n - 1 do
        local unit = (i == 0) and "player" or ("party" .. i)
        if UnitExists(unit) then
            local role = UnitGroupRolesAssigned(unit)
            if (not role or role == "NONE") and i == 0 then role = _myRole end
            if role == "TANK" then _needT = _needT + 1
            elseif role == "HEALER" then _needH = _needH + 1
            else _needD = _needD + 1 end
        end
    end
end

-------------------------------------------------------------------------------
--  Criteria
-------------------------------------------------------------------------------
-- Soft decline lookup on LFGListFrame.declines (read-only; we never write to
-- it). Guarded like every other per-result read in case the table itself ever
-- becomes secret.
local _dqGuid, _dqOut
local function ReadDecline()
    -- The existence test lives in here too: evaluating a secret value as a
    -- condition would throw just as readily as indexing it.
    local declines = LFGListFrame and LFGListFrame.declines
    if not declines then return end
    _dqOut = Str(declines[_dqGuid])
end

local function IsDeclined(id, d)
    local guid = d.partyGUID
    if guid then
        _dqGuid, _dqOut = guid, nil
        pcall(ReadDecline)
        local st = _dqOut
        if st == "declined" or st == "declined_full" or st == "declined_delisted" then
            return true
        end
    end
    EnsureApp(id, d)
    local st = d.appStatus
    return st == "declined" or st == "declined_full" or st == "declined_delisted"
end

-- Difficulty. Bucketing is Blizzard's own (LFGList.lua EntryStillSatisfiesFilters):
-- with no box ticked nothing is filtered, otherwise a result is rejected when
-- the activity carries a difficulty flag whose box is unticked. An activity we
-- cannot read, or one that carries no difficulty flag at all, passes.
local function DifficultyPasses(p, a, raid)
    if raid then
        -- Raids get positive matching rather than Blizzard's reject-form: the
        -- bucket is derived explicitly (see RaidBucket), so "tick Heroic" can
        -- mean exactly Heroic instead of "anything not flagged otherwise".
        -- There is no Blizzard raid filter to mirror here, and reject-form
        -- would quietly keep LFR whenever any box was ticked.
        local kN, kH, kM = p.raidDiffNormal, p.raidDiffHeroic, p.raidDiffMythic
        if not (kN or kH or kM) then return true end
        -- Only an unreadable activity fails open. Anything we did read gets a
        -- bucket, so a listing with no usable difficulty is excluded rather
        -- than surviving every tick.
        if not a then return true end
        local bucket = RaidBucket(a)
        if bucket == "normal" then return kN and true or false end
        if bucket == "heroic" then return kH and true or false end
        if bucket == "mythic" then return kM and true or false end
        return false                    -- LFR / Timewalking / Story / no difficulty
    end

    -- Dungeons keep Blizzard's own bucketing verbatim.
    local kN, kH, kM, kP = p.diffNormal, p.diffHeroic, p.diffMythic, p.diffMythicPlus
    if not (kN or kH or kM or kP) then return true end
    if not a then return true end
    if (a.normal and not kN)
        or (a.heroic and not kH)
        or (a.mythic and not kM)
        or (a.mythicplus and not kP) then
        return false
    end
    return true
end

-- Resolves an activity to its whitelist key: the activity group when it has
-- one, otherwise the standalone form. Mirrors how BuildRaidList keys entries.
local function WhitelistKey(a)
    if not a then return nil end
    local gid = a.groupID
    if gid and gid ~= 0 then return gid end
    if a.activityID then return -a.activityID end
    return nil
end

-- THE WHITELIST RULE
--
-- A whitelist filters by the entries it has IN COMMON with the list currently
-- enumerated for the active tab. If that intersection is empty, nothing is
-- filtered -- which makes "empty table means everything passes" a special case
-- of one rule rather than a separate branch, and makes a selection that cannot
-- apply here inert instead of catastrophic:
--
--   * Whitelist two current raids, switch to Legacy Raids: the saved keys match
--     nothing enumerated there, so Legacy shows everything. The user never
--     filtered Legacy, so Legacy is unfiltered.
--   * A season rolls over: last season's dungeon groupIDs intersect nothing in
--     the new enumeration, so the grid shows everything instead of an
--     inexplicably empty result list.
--
-- Recomputed once per pass into a reused table (never per result), so this
-- costs one walk of a ~10-entry list and allocates nothing.
local _wlActive, _wlActiveCount = {}, 0

local function BuildActiveWhitelist(p, dungeon, raid)
    wipe(_wlActive)
    _wlActiveCount = 0

    -- Explicit branch, not `raid and p.raidWhitelist or p.dungeonWhitelist`:
    -- that idiom silently falls through to the DUNGEON list if the raid one is
    -- ever missing. A missing table must mean "no filter", never "wrong table".
    local wl, list
    if raid then wl, list = p.raidWhitelist, _raids
    elseif dungeon then wl, list = p.dungeonWhitelist, _dungeons
    else return end
    if not wl then return end

    for i = 1, #list do
        local id = list[i].id
        if wl[id] then
            _wlActive[id] = true
            _wlActiveCount = _wlActiveCount + 1
        end
    end
end

local function WhitelistPasses(a)
    if _wlActiveCount == 0 then return true end
    local key = WhitelistKey(a)
    if not key then return true end
    return _wlActive[key] and true or false
end

-------------------------------------------------------------------------------
--  Expression engine (PGF-style), sandboxed.
--
--  The chunk is compiled ONCE per expression text and setfenv'd into _exprEnv,
--  which is the only table it can see: no _G, no C_LFGList, no os/io, no
--  metatable to climb (__metatable is false and __newindex swallows attempts to
--  create new globals). Everything the expression can read comes out of the
--  Num/Bool/Str-sanitised per-pass cache, so no secret value can enter it.
--  A compile failure, a runtime error or a non-boolean result all fail OPEN.
--
--  Two things the env deliberately does NOT stop, both self-inflicted only:
--   - Lua 5.1 hangs the string metatable off every string literal, so method
--     syntax like activity:rep(n) or ("").format still resolves. That reaches
--     the string library, not _G -- there is no loadstring/getfenv/getmetatable
--     in here to climb back out with.
--   - "return (...)" can contain a function literal, so a user can write an
--     expression that loops forever and wedges their own client. WoW gives
--     addons no instruction-count hook to pre-empt that; PGF and WeakAuras
--     carry the same exposure.
-------------------------------------------------------------------------------
local _exprEnv = setmetatable({}, {
    __newindex  = function() end,   -- expressions cannot add globals
    __metatable = false,            -- ...nor reach the metatable to undo that
})

-- Field list is also the refill list: every key exists up front so the
-- per-result refill is a plain rawset-equivalent store (__newindex only fires
-- for new keys) and allocates nothing.
local EXPR_FIELDS = {
    "score", "members", "tanks", "heals", "dps", "ilvl", "age", "friends",
    "delisted", "declined", "warmode",
    "normal", "heroic", "mythic", "mythicplus", "activity",
    "floor", "min", "max", "abs", "find",
}
for i = 1, #EXPR_FIELDS do rawset(_exprEnv, EXPR_FIELDS[i], false) end

local function ExprFind(s)
    if type(s) ~= "string" then return false end
    local a = _exprEnv.activity
    if type(a) ~= "string" then return false end
    return string.find(a:lower(), s:lower(), 1, true) ~= nil
end

local _exprChunk, _exprSrc, _exprCompileErr, _exprRunErr

local function ExpressionError()
    return _exprCompileErr or _exprRunErr
end

-- Compiles p.expression if it changed. Returns true when the error state moved.
local function CompileExpression(expr)
    if expr == _exprSrc then return false end
    _exprSrc = expr
    _exprChunk, _exprCompileErr, _exprRunErr = nil, nil, nil

    if not expr or expr == "" then return true end
    if type(loadstring) ~= "function" or type(setfenv) ~= "function" then
        _exprCompileErr = EllesmereUI.L("Lua expressions are not available in this client")
        return true
    end

    local chunk, err = loadstring("return (" .. expr .. ")", "EUIPremadeFilterExpression")
    if not chunk then
        _exprCompileErr = err or EllesmereUI.L("syntax error")
        return true
    end
    setfenv(chunk, _exprEnv)
    _exprChunk = chunk
    return true
end

local function ExpressionActive(p)
    return (p.expressionEnabled and _exprChunk) and true or false
end

local function ExprPasses(id, d, a)
    local e = _exprEnv

    e.score    = d.score or 0
    e.members  = d.numMembers or 0
    e.ilvl     = d.ilvl or 0
    e.age      = d.age or 0
    e.friends  = d.friends or 0
    e.delisted = d.isDelisted == true
    e.warmode  = d.warMode == true
    e.declined = IsDeclined(id, d)

    EnsureRoles(id, d)
    if d.roleOK then
        e.tanks, e.heals, e.dps = d.tanks, d.healers, d.dps
    else
        e.tanks, e.heals, e.dps = 0, 0, 0
    end

    e.normal     = (a and a.normal) or false
    e.heroic     = (a and a.heroic) or false
    e.mythic     = (a and a.mythic) or false
    e.mythicplus = (a and a.mythicplus) or false
    e.activity   = (a and a.name) or ""

    -- Restored every pass so an expression that clobbers a helper only breaks
    -- its own evaluation, never the next result's.
    e.floor, e.min, e.max, e.abs = math.floor, math.min, math.max, math.abs
    e.find = ExprFind

    local ok, res = pcall(_exprChunk)
    if not ok then
        _exprRunErr = tostring(res)
        return true
    end
    if type(res) ~= "boolean" then
        _exprRunErr = EllesmereUI.L("expression must evaluate to true or false")
        return true
    end
    return res
end

-- Returns true to KEEP the result. Every unreadable criterion passes.
local function Passes(id, d, p, dungeon, expr, raid)
    if not d.readOK then return true end

    if p.hideDelisted and d.isDelisted == true then return false end
    if p.hideDeclined and IsDeclined(id, d) then return false end

    local a = ActivityInfo(d.activityID)

    if expr and not ExprPasses(id, d, a) then return false end

    -- Difficulty and whitelist are the two criteria both categories share; the
    -- rest below this point stay dungeon-only.
    if raid then
        if not DifficultyPasses(p, a, true) then return false end
        if not WhitelistPasses(a) then return false end
        return true
    end

    if not dungeon then return true end

    -- A repair discovered here changes what the grid should draw; the pass
    -- records it and repaints once at the end rather than per result.
    if NoteActivityMap(a) then _iconsDirty = true end

    if not DifficultyPasses(p, a, false) then return false end
    if not WhitelistPasses(a) then return false end

    if p.minLeaderScoreEnabled then
        local s = d.score
        if s and s < (p.minLeaderScore or 0) then return false end
    end

    local wantRoles = p.needsTank or p.needsHealer or p.myRoleAvailable or p.partyFit
    if not wantRoles then return true end

    EnsureRoles(id, d)
    if not d.roleOK then return true end

    if p.needsTank and d.tanks >= SLOTS_TANK then return false end
    if p.needsHealer and d.healers >= SLOTS_HEALER then return false end

    local openT = SLOTS_TANK - d.tanks
    local openH = SLOTS_HEALER - d.healers
    local openD = SLOTS_DPS - d.dps

    if p.myRoleAvailable then
        local open
        if _myRole == "TANK" then open = openT
        elseif _myRole == "HEALER" then open = openH
        else open = openD end
        if open < 1 then return false end
    end

    if p.partyFit then
        if openT < _needT or openH < _needH or openD < _needD then return false end
    end

    return true
end

-------------------------------------------------------------------------------
--  Sorting: REMOVED, and it cannot come back.
--
--  Every way of reordering the browse writes Blizzard Lua state on our
--  execution. Assigning a sorted panel.results is the poison documented at the
--  top of this file; table.sort'ing Blizzard's own array in a post-hook on
--  LFGListUtil_SortSearchResults is the same thing one level down, because it
--  writes the array's elements and LFGListSearchPanel_UpdateResults then reads
--  them back into every elementData.
--
--  What is lost is smaller than it looks: Blizzard's own comparator
--  (LFGListUtil_SortSearchResultsCB, LFGList.lua:3944) already sorts declined
--  groups last, groups with a slot for your role first, then by Battle.net
--  friends, character friends and guildmates -- which is what "friends first"
--  did. Score and age ordering are genuinely gone; the score is still shown on
--  each row by the display module, so it stays readable, just not sortable.
--
--  The p.sortMode / p.sortDescending / p.friendsFirst keys are left in the
--  saved-variable defaults on purpose: profiles in the wild already carry them
--  and silently dropping keys makes profile diffs lie. Nothing reads them.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Native filter -- the only thing here that actually removes rows
--
--  Blizzard's advanced filter is C-side state: C_LFGList.GetAdvancedFilter reads
--  it, C_LFGList.SaveAdvancedFilter writes it, C_LFGList.Search applies it when
--  the next search runs. Nothing we pass through it becomes Lua state Blizzard
--  reads back, so driving it taints nothing at all -- which is the whole reason
--  this module was rebuilt around it (see the header).
--
--  Two Blizzard-imposed limits, both worth knowing before adding a control:
--   - DUNGEONS ONLY. LFGListSearchPanel_DoSearch nils the advanced filter for
--     every category except GROUP_FINDER_CATEGORY_ID_DUNGEONS (LFGList.lua:2653).
--     Raids get no native filtering whatsoever; raid criteria dim instead.
--   - It applies at SEARCH time. Saving does not re-filter what is already on
--     screen, and we cannot re-run the search ourselves -- both
--     LFGListSearchPanel_DoSearch and C_LFGList.Search would run Blizzard's
--     rebuild on our execution. The panel's click controls get around that by
--     forwarding the click to SearchPanel.RefreshButton through a
--     SecureActionButtonTemplate, so the search runs in Blizzard's context and
--     the save lands immediately (see "Secure search forwarding"). The typed
--     score box has no click to forward, so it carries an Apply button and the
--     count text reads "Searching to apply..." until the results arrive.
--
--  While the panel is enabled it is the AUTHORITY for the nine fields it owns
--  (needsTank/Healer/Damage, minimumRating, the four difficulties, activities);
--  editing those in Blizzard's dropdown will be overwritten on our next sync.
--  The other seven (needsMyClass, hasTank, hasHealer, generalPlaystyle1-4) are
--  merged through untouched. The user's whole pre-takeover filter is
--  snapshotted the first time we enable and restored when the feature is
--  switched off, so this is not a one-way door into a rewritten dropdown --
--  which was the original objection to using this API at all.
-------------------------------------------------------------------------------
local _userFilter          -- the user's own advanced filter, pre-takeover
local _lastNative          -- last filter we saved, for change detection
local _nativeDirty = false -- saved filter has not reached the list on screen yet
local _nativeActivities = {}

local function CopyFilter(src)
    if type(src) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(src) do
        if k == "activities" then
            local a = {}
            if type(v) == "table" then
                for i = 1, #v do a[i] = v[i] end
            end
            out[k] = a
        else
            out[k] = v
        end
    end
    if not out.activities then out.activities = {} end
    return out
end

-- Wrapped whole: the documented structure is all plain scalars, but a secret
-- value anywhere in it would throw on the length test rather than on the copy.
local function ReadNativeFilter()
    if not (C_LFGList and C_LFGList.GetAdvancedFilter) then return nil end
    local ok, f = pcall(function() return CopyFilter(C_LFGList.GetAdvancedFilter()) end)
    if not ok then return nil end
    return f
end

local function WriteNativeFilter(f)
    if not f or not (C_LFGList and C_LFGList.SaveAdvancedFilter) then return false end
    return (pcall(C_LFGList.SaveAdvancedFilter, f))
end

local function SnapshotUserFilter()
    if _userFilter then return end
    _userFilter = ReadNativeFilter()
end

-- Blizzard matches enabled.activities against infoTable.groupFinderActivityGroupID
-- (EntryStillSatisfiesFilters, LFGList.lua:3057), so only positive group IDs mean
-- anything natively. Our whitelist also stores standalone activities as negative
-- keys (see WHITELIST KEY SCHEME); those have no native representation and are
-- left to the dimming pass.
--
-- Intersecting with the CURRENT enumeration keeps THE WHITELIST RULE intact: a
-- selection that matches nothing on this tab sends an empty list, which Blizzard
-- reads as "no activity filter" rather than "nothing matches".
local function NativeActivities(p)
    wipe(_nativeActivities)
    local wl = p.dungeonWhitelist
    if not wl or not next(wl) then return _nativeActivities end
    -- The enumeration is a session cache built when the panel first draws, but a
    -- saved whitelist can need translating before that ever happens (login with
    -- the feature already on). Build it on demand rather than silently sending
    -- an empty activity list, which Blizzard would read as "no filter".
    if #_dungeons == 0 then
        BuildDungeonIcons(BuildDungeonList())
    end
    for i = 1, #_dungeons do
        local id = _dungeons[i].id
        if id and id > 0 and wl[id] then
            _nativeActivities[#_nativeActivities + 1] = id
        end
    end
    return _nativeActivities
end

local function BuildNativeFilter(p)
    local f = ReadNativeFilter()
    if not f then return nil end

    f.minimumRating = (p.minLeaderScoreEnabled and tonumber(p.minLeaderScore)) or 0

    -- "A slot for my role" has no field of its own; natively it is the needs<role>
    -- flag for whatever the player queues as. ORing it into the explicit ticks
    -- gives the same conjunction the dimming pass applies.
    local role = MySpecRole()
    f.needsTank   = (p.needsTank   or (p.myRoleAvailable and role == "TANK"))   and true or false
    f.needsHealer = (p.needsHealer or (p.myRoleAvailable and role == "HEALER")) and true or false
    f.needsDamage = (p.myRoleAvailable and role ~= "TANK" and role ~= "HEALER") and true or false

    f.difficultyNormal     = p.diffNormal     and true or false
    f.difficultyHeroic     = p.diffHeroic     and true or false
    f.difficultyMythic     = p.diffMythic     and true or false
    f.difficultyMythicPlus = p.diffMythicPlus and true or false

    f.activities = NativeActivities(p)
    return f
end

-- Only the fields we own -- a change in one of Blizzard's own boxes is the
-- user's business and must not make our panel nag about refreshing.
local function NativeFilterChanged(f)
    local o = _lastNative
    if not o then return true end
    if f.minimumRating ~= o.minimumRating
        or f.needsTank ~= o.needsTank
        or f.needsHealer ~= o.needsHealer
        or f.needsDamage ~= o.needsDamage
        or f.difficultyNormal ~= o.difficultyNormal
        or f.difficultyHeroic ~= o.difficultyHeroic
        or f.difficultyMythic ~= o.difficultyMythic
        or f.difficultyMythicPlus ~= o.difficultyMythicPlus then
        return true
    end
    local a, b = f.activities, o.activities
    if #a ~= #b then return true end
    for i = 1, #a do
        if a[i] ~= b[i] then return true end
    end
    return false
end

local UpdateCountText     -- fwd (UI section)
local UpdateExprError     -- fwd (UI section)
local RepaintWhitelists   -- fwd (UI section)

-- Repaint the rows on screen. The display module owns every pixel we change,
-- and its refresh is read-only iteration over its own frames -- we never call
-- LFGListSearchEntry_Update, which would write Blizzard row state on our
-- execution (that is the poison the header describes).
local function RepaintRows()
    local fn = _G._EUI_RefreshPremadeFilterDisplay
    if fn then pcall(fn) end
end

local function SyncNativeFilter()
    local p = P()
    if not p or not p.enabled then return end
    SnapshotUserFilter()
    local f = BuildNativeFilter(p)
    if not f then return end
    if NativeFilterChanged(f) then
        if WriteNativeFilter(f) then
            _lastNative = CopyFilter(f)
            _nativeDirty = true
        end
    end
end

-- Put the user's own dropdown back exactly as we found it.
local function RestoreUserFilter()
    if _userFilter then
        WriteNativeFilter(_userFilter)
        _userFilter = nil
    end
    _lastNative = nil
    _nativeDirty = false
end

-------------------------------------------------------------------------------
--  Verdict pass
--
--  Read-only by construction: it reads results, evaluates the criteria and
--  records a pass/fail per resultID. It writes nothing outside this file. The
--  display module turns a false verdict into a dimmed row.
--
--  This covers BOTH kinds of criterion on purpose. The native ones will have
--  removed their rows at the next search, but until then dimming them is honest
--  feedback; the non-native ones (delisted, declined, party fit, expression, and
--  everything on the raid tab) never get removed at all, so dimming is the whole
--  of their effect.
--
--  Reading a secret value is safe -- only comparing one under our taint throws --
--  but every criterion here is a comparison, so a secret anywhere in the result
--  still stands the pass down completely rather than guessing.
-------------------------------------------------------------------------------
local _pristine = {}          -- resultIDs from the last rebuild, in Blizzard order
local _pristineCategory       -- categoryID that snapshot belongs to
local _shown, _total          -- last "N of M match", nil when not evaluating
local _paused                 -- true while secret results have the pass stood down
local _verdict = {}           -- [resultID] = false for a row that fails

-- Published for the display module. nil means "no opinion" (feature off, pass
-- stood down, or a result we never saw) and must render as a normal row.
_G._EUI_PremadeFilter_Verdict = function(resultID)
    if _paused then return nil end
    if resultID == nil then return nil end
    return _verdict[resultID]
end

_G._EUI_PremadeFilter_Pending = function()
    return _nativeDirty and true or false
end

local function ClearVerdicts()
    if next(_verdict) then
        wipe(_verdict)
        return true
    end
    return false
end

-- Stand down without hiding anything. Blizzard keeps rendering its own results
-- untouched and the panel says why nothing is being marked.
local function PauseForSecrets()
    _paused = true
    _shown, _total = nil, nil
    ClearVerdicts()
    UpdateCountText()
    RepaintRows()
end

local function EvaluatePass(panel)
    local p = P()
    if not p or not p.enabled then return end
    if not panel or #_pristine == 0 then return end
    if panel.categoryID ~= _pristineCategory then return end

    -- Nothing to mark while the panel is off screen, and the rows will be
    -- rebuilt on reopen anyway: LFGListSearchPanel_OnShow calls
    -- LFGListSearchPanel_UpdateResultList itself, so our post-hook re-fires.
    -- IsVisible(), not IsShown() -- the SearchPanel's own shown flag stays true
    -- while PVEFrame is closed.
    if not panel:IsVisible() then return end

    -- Cheap hint only -- the predicate has been seen returning false with
    -- secret result kstrings on the wire. The per-result probe decides.
    if InChatLockdown() then return PauseForSecrets() end

    local dungeon = (panel.categoryID == DungeonCategory())
    local raid = (not dungeon) and (panel.categoryID == RaidCategory())

    CompileExpression(p.expression or "")
    local expr = ExpressionActive(p)
    -- Runtime errors describe this pass only; compile errors survive it.
    _exprRunErr = nil

    -- The whitelist rule needs the enumeration for THIS tab, and the pass can
    -- run while the panel is collapsed (the panel-show path is not enough).
    -- Both builders are cached, so this is a no-op on the common path.
    if raid then
        BuildRaidList(panel)
    elseif dungeon and #_dungeons == 0 then
        BuildDungeonIcons(BuildDungeonList())
    end
    BuildActiveWhitelist(p, dungeon, raid)

    BeginPass()
    RefreshRoleContext()

    local failures = 0
    local n = #_pristine
    local passed = 0
    ClearVerdicts()
    for i = 1, n do
        local id = _pristine[i]
        local d = GetData(id)
        d.order = i
        if not d.readOK then failures = failures + 1 end
        if Passes(id, d, p, dungeon, expr, raid) then
            passed = passed + 1
        else
            _verdict[id] = false
        end
    end

    -- Anything secret in any result invalidates every comparison above.
    if _secretResults then return PauseForSecrets() end
    _paused = false

    UpdateExprError()

    -- A mapID repair during this pass moved a dungeon from the text list into
    -- the icon grid; repaint once, here, rather than per result.
    if _iconsDirty then
        _iconsDirty = false
        RepaintWhitelists()
    end

    -- A pass that could read nothing tells us nothing: mark nothing rather than
    -- dimming the whole list blind.
    if failures >= n then
        _shown, _total = nil, nil
        ClearVerdicts()
        UpdateCountText()
        RepaintRows()
        return
    end

    _total, _shown = n, passed
    UpdateCountText()
    RepaintRows()
end

-- Post-hook on Blizzard's rebuild. Reads panel.results and nothing else; the
-- snapshot is ours, the table it copies from stays Blizzard's.
local function OnUpdateResultList(panel)
    if not LFGListFrame or panel ~= LFGListFrame.SearchPanel then return end

    -- A rebuild is a search result reaching the screen, so whatever we last
    -- saved is now what produced this list.
    _nativeDirty = false

    -- Exit before reading anything else while we are off.
    if not Enabled() then
        if ClearVerdicts() then RepaintRows() end
        return
    end

    -- Keep the saved filter in step with the settings. Needed here and not only
    -- on control changes: at login the settings can already describe a filter
    -- nothing has saved yet, and the dungeon enumeration a whitelist translates
    -- through only exists once the browse has been opened.
    SyncNativeFilter()

    local src = panel.results
    wipe(_pristine)
    _pristineCategory = panel.categoryID
    if src then
        for i = 1, #src do _pristine[i] = src[i] end
    end
    if #_pristine == 0 then
        _shown, _total = nil, nil
        ClearVerdicts()
        UpdateCountText()
        return
    end
    EvaluatePass(panel)
end

-- Re-evaluate after a control changed. Never searches; the native half lands on
-- the next refresh, the dimming half is immediate.
local function Refilter()
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    if Enabled() then
        SyncNativeFilter()
    else
        RestoreUserFilter()
        _paused = nil
        _shown, _total = nil, nil
        ClearVerdicts()
        UpdateCountText()
        RepaintRows()
        return
    end
    -- IsVisible(), not IsShown(): same reason as EvaluatePass's gate.
    if not panel or not panel:IsVisible() then
        UpdateCountText()
        return
    end
    EvaluatePass(panel)
end

-------------------------------------------------------------------------------
--  UI
-------------------------------------------------------------------------------
local toggleBtn, sidePanel
local rows = {}          -- ordered list of laid-out rows
local ctl = {}           -- named controls, for SyncControls
local countFS
local RefreshVisibility  -- fwd
local LayoutPanel        -- fwd
local SyncControls       -- fwd (needed by Secure.Watch's deferred rebuild)

local ROW_H, GAP, PAD = 20, 4, 10

local function IsDungeonBrowse()
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    return panel and panel.categoryID == DungeonCategory()
end

local function IsRaidBrowse()
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    if not panel or panel.categoryID == DungeonCategory() then return false end
    return panel.categoryID == RaidCategory()
end

-------------------------------------------------------------------------------
--  Secure search forwarding
--
--  Changing a filter is only half the job: the native advanced filter is read
--  by Blizzard at search time (LFGList.lua:2652), so nothing moves until a
--  search re-runs. We cannot re-run one ourselves -- C_LFGList.Search is
--  HasRestrictions, and calling LFGListSearchPanel_DoSearch (or :Click()ing
--  RefreshButton) from our code writes SearchPanel.previousSearchText on our
--  execution, which poisons it for the session because Blizzard reads it at
--  2666 before writing it at 2670. See this file's header.
--
--  The one route that works, proven live 2026-08-02 with EllesmereUISecretsDiag
--  T33/T34: a SecureActionButtonTemplate carrying type="click" and
--  clickbutton=SearchPanel.RefreshButton. Blizzard's SECURE_ACTIONS.click
--  (SecureTemplates.lua:554) performs delegate:Click() in ITS OWN execution, so
--  DoSearch runs untainted even though we set the attributes -- measured by
--  sampling issecurevariable(panel, "previousSearchText") inside a post-hook on
--  DoSearch itself, one click, 1-of-1 calls attributed, still secure.
--
--  Rules that keep it that way:
--    * NEVER SetScript("OnClick") on one of these. That slot belongs to
--      SecureActionButton_OnClick; our work goes in PreClick, which T34 proved
--      does not bleed taint into the forwarded click. PostClick would be safe
--      too but runs after the search, so every toggle would apply one behind.
--    * Register BOTH click edges. Addons cannot supply
--      SecureActionButton_OnClick's isKeyPress/isSecureAction arguments
--      (SecureTemplates.xml:6), so useOnKeyDown collapses to the
--      ActionButtonUseKeyDown CVar and only one edge produces an action.
--      Registering a single edge silently does nothing when the CVar disagrees
--      -- the click still fires PostClick, so it looks like it worked.
--    * PreClick therefore fires TWICE per physical click, once per edge. Act on
--      the down edge only: it precedes the action under either CVar setting, so
--      the setting is saved before the search reads it, exactly once.
--    * SetAttribute and RegisterForClicks are locked in combat, so wiring is
--      deferred to PLAYER_REGEN_ENABLED when necessary.
--    * No debouncing is possible. A timer- or coalesce-driven search would run
--      on OUR execution, i.e. the tainted path. One click, one search.
-------------------------------------------------------------------------------
--  Combat: the panel's filter controls are secure frames now, and secure frames
--  cannot be shown, hidden, moved or given attributes while in combat. Layout
--  work is therefore deferred to PLAYER_REGEN_ENABLED rather than attempted and
--  blocked -- a browse panel has no business relaying out mid-fight anyway. The
--  same watcher wires up any control that was built during combat.
--
--  One table rather than several file-level locals: this chunk runs close to
--  Lua's 200-locals-per-chunk ceiling, and adding them separately overruns it.
--  Forwarding is DUNGEONS ONLY. LFGListSearchPanel_DoSearch discards the
--  advanced filter for every other category (LFGList.lua:2653), so a forwarded
--  search on Raids or Legacy Raids cannot act on the change that triggered it --
--  it just spends one search against the server throttle. On those tabs the
--  clickbutton attribute is cleared, which SECURE_ACTIONS.click handles by doing
--  nothing (it tests `delegate and not delegate:IsForbidden()` before clicking).
--  PreClick still fires either way, so the control's own work still happens and
--  the dimming pass still re-runs; only the search is suppressed. Defaults to
--  forwarding: an unnecessary search is cheap, a dungeon filter that silently
--  fails to apply is not.
local Secure = { pending = {}, buttons = {}, forward = true }

function Secure.Watch()
    if Secure.watcher then return end
    Secure.watcher = CreateFrame("Frame")
    Secure.watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    Secure.watcher:SetScript("OnEvent", function()
        Secure.Flush()
        if Secure.dirty then
            Secure.dirty = nil
            if SyncControls then SyncControls() end
            if LayoutPanel then LayoutPanel() end
        end
    end)
end

-- True when the caller must not touch secure frame layout right now. Records
-- that a rebuild is owed so it happens the moment combat drops.
function Secure.Blocked()
    if not InCombatLockdown() then return false end
    Secure.dirty = true
    Secure.Watch()
    return true
end

function Secure.Target()
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    local target = panel and panel.RefreshButton
    return type(target) == "table" and target or nil
end

function Secure.Wire(b)
    if b._euiWired then return true end
    if InCombatLockdown() then return false end
    local target = Secure.Target()
    if not target then return false end
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "click")
    b:SetAttribute("clickbutton", Secure.forward and target or nil)
    b._euiWired = true
    Secure.buttons[#Secure.buttons + 1] = b
    return true
end

-- Turn the forwarded search on or off for every wired control at once. Called
-- from LayoutPanel, which already runs on every category change.
function Secure.SetForwarding(on)
    on = on and true or false
    if on == Secure.forward then return end
    if InCombatLockdown() then
        Secure.dirty = true
        Secure.Watch()
        return
    end
    local target = Secure.Target()
    if on and not target then return end
    Secure.forward = on
    for i = 1, #Secure.buttons do
        Secure.buttons[i]:SetAttribute("clickbutton", on and target or nil)
    end
end

-- Retry anything that could not be wired at creation (in combat, or before
-- Blizzard_GroupFinder built the search panel).
function Secure.Flush()
    local q = Secure.pending
    for i = #q, 1, -1 do
        if Secure.Wire(q[i]) then table.remove(q, i) end
    end
end

-- A button that performs `work` and then re-runs Blizzard's search, on one
-- click, without tainting anything.
function Secure.Button(parent, work)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:SetScript("PreClick", function(self, _, down)
        -- Down edge only; see the header note on double firing.
        if not down then return end
        work(self)
    end)
    if not Secure.Wire(b) then
        Secure.pending[#Secure.pending + 1] = b
        Secure.Watch()
    end
    return b
end

--  Checkbox --------------------------------------------------------------
local function MakeCheck(parent, label, key, dungeonOnly, onChange)
    local row = Secure.Button(parent, function(self)
        local p = P(); if not p then return end
        p[key] = not p[key]
        self.Sync()
        if onChange then onChange() end
        Refilter()
    end)
    row:SetHeight(ROW_H)
    row.dungeonOnly = dungeonOnly

    local box = CreateFrame("Frame", nil, row)
    box:SetSize(13, 13)
    box:SetPoint("LEFT", row, "LEFT", 0, 0)
    SolidTex(box, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints(box)
    Border(box, 1, 1, 1, 0.15, 7)

    local check = SolidTex(box, "ARTWORK", Accent())
    check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
    check:Hide()

    local fs = MFont(row, 11, 0.85, 0.85, 0.85, 1)
    fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
    fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(label)

    row.Sync = function()
        local p = P()
        check:SetShown(p and p[key] and true or false)
    end
    row:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1, 1) end)
    row:SetScript("OnLeave", function() fs:SetTextColor(0.85, 0.85, 0.85, 1) end)
    -- No OnClick here: the toggle work lives in the PreClick set up by
    -- SecureButton, so this row also re-runs the search.

    rows[#rows + 1] = row
    ctl[key] = row
    return row
end

--  Section header --------------------------------------------------------
local function MakeHeader(parent, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(16)
    local fs = MFont(row, 10, Accent())
    fs:SetPoint("LEFT", row, "LEFT", 0, 0)
    fs:SetText(text)
    row.Sync = function() end
    rows[#rows + 1] = row
    return row
end

--  Small flat button -----------------------------------------------------
-- Pass `work` to get a button that also re-runs the search on the same click
-- (see the secure-forwarding notes above). Omit it for controls that change no
-- filter -- the panel show/hide toggle and the collapse headers -- so they do
-- not spend a search each.
local function MakeFlatButton(parent, w, h, work)
    local b = work and Secure.Button(parent, work) or CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    local bg = SolidTex(b, "BACKGROUND", 0, 0, 0, 0.5)
    bg:SetAllPoints(b)
    b.bg = bg
    Border(b, 1, 1, 1, 0.12, 7)
    b.label = MFont(b, 11, 0.85, 0.85, 0.85, 1)
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.09) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0.5) end)
    return b
end

--  Tooltip helper ---------------------------------------------------------
--
--  The house widget tooltip, never GameTooltip. Driving GameTooltip from here
--  leaves our taint on it, and Blizzard's own row tooltip reads the secret
--  fields of searchResultInfo (LFGList.lua:4195) -- so one hover over a panel
--  checkbox would make every later row hover throw for the rest of the
--  session. The house tooltip draws on its own frame and never touches
--  Blizzard's, which is also why EUI's style rules ask for it.
-------------------------------------------------------------------------------
local function ShowTip(owner, title, body, bodyR, bodyG, bodyB)
    local show = EllesmereUI.ShowWidgetTooltip
    if not show then return end
    local text = title or ""
    if body and body ~= "" then
        text = (text ~= "" and (text .. "\n\n") or "") .. body
    end
    if text == "" then return end
    if bodyR then
        show(owner, text, { color = { bodyR, bodyG, bodyB } })
    else
        show(owner, text)
    end
end

local function HideTip()
    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
end

local CONTENT_W = PANEL_W - 2 * PAD

--  Numeric edit box ------------------------------------------------------
local function MakeScoreBox(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.dungeonOnly = true

    local eb = CreateFrame("EditBox", nil, row)
    eb:SetSize(64, 18)
    eb:SetPoint("LEFT", row, "LEFT", 19, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(5)
    eb:SetJustifyH("LEFT")
    eb:SetTextInsets(5, 5, 0, 0)
    eb:SetFont(PanelFont(), 11, "")
    eb:SetTextColor(1, 1, 1, 0.9)
    SolidTex(eb, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints(eb)
    Border(eb, 1, 1, 1, 0.12, 7)

    local fs = MFont(row, 11, 0.55, 0.55, 0.55, 1)
    fs:SetPoint("LEFT", eb, "RIGHT", 6, 0)
    fs:SetText(EllesmereUI.L("min score"))

    -- ClearFocus() fires OnEditFocusLost, so Escape has to suppress the commit
    -- it would otherwise trigger on its way out.
    local cancelling = false
    local function commit()
        if cancelling then return end
        local p = P(); if not p then return end
        local v = tonumber(eb:GetText()) or 0
        if v < 0 then v = 0 elseif v > 99999 then v = 99999 end
        eb:SetText(tostring(v))
        eb:ClearFocus()
        -- Enter also drops focus, so commit runs twice; only the first one
        -- actually changes anything and only that one re-filters.
        if v == p.minLeaderScore then return end
        p.minLeaderScore = v
        Refilter()
    end
    eb:SetScript("OnEnterPressed", commit)
    eb:SetScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function(self)
        cancelling = true
        self:ClearFocus()
        cancelling = false
        row.Sync()
    end)

    -- Every other control on the panel re-runs the search on its own click, but
    -- typing and pressing Enter is not a click, so a score change cannot forward
    -- one. This button is the score row's click: it commits the typed value and
    -- then re-runs the search, exactly like a toggle. Committing here first
    -- means the focus-loss commit that follows sees an unchanged value and does
    -- nothing.
    -- Anchored to the row, NOT to the "min score" fontstring beside it: this is
    -- a secure frame, and a protected frame cannot be anchored to a region
    -- ("Cannot anchor protected frames to regions"). Only frames are legal
    -- targets. Rows span the panel via TOPLEFT+TOPRIGHT, so right-aligning here
    -- matches the whitelist header's All/None.
    local apply = MakeFlatButton(row, 44, 18, commit)
    apply:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    apply.label:SetText(EllesmereUI.L("Apply"))
    apply:HookScript("OnEnter", function(self)
        ShowTip(self, EllesmereUI.L("Apply"), EllesmereUI.L(
            "Commit the score and search again. The other filters apply as you click them; a typed score needs this."))
    end)
    apply:HookScript("OnLeave", HideTip)

    row.Sync = function()
        local p = P()
        if not p then return end
        if not eb:HasFocus() then eb:SetText(tostring(p.minLeaderScore or 0)) end
        local on = p.minLeaderScoreEnabled and true or false
        eb:EnableMouse(on)
        eb:SetAlpha(on and 1 or 0.35)
        fs:SetAlpha(on and 1 or 0.35)
        apply:SetAlpha(on and 1 or 0.35)
        apply:EnableMouse(on)
    end

    rows[#rows + 1] = row
    ctl.minLeaderScore = row
    return row
end

--  Difficulty toggles -----------------------------------------------------
local DIFFS_DUNGEON = {
    { key = "diffNormal",     label = "N",  name = "Normal" },
    { key = "diffHeroic",     label = "H",  name = "Heroic" },
    { key = "diffMythic",     label = "M",  name = "Mythic" },
    { key = "diffMythicPlus", label = "M+", name = "Mythic Keystone" },
}
-- Separate keys, so a dungeon selection never leaks into the raid browse.
local DIFFS_RAID = {
    { key = "raidDiffNormal", label = "N",  name = "Normal" },
    { key = "raidDiffHeroic", label = "H",  name = "Heroic" },
    { key = "raidDiffMythic", label = "M",  name = "Mythic" },
}

local DIFF_TIP = "Keep only groups of the ticked difficulties. With none ticked, difficulty is not filtered."

local function MakeDifficultyRow(parent, defs, raidOnly)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.dungeonOnly = not raidOnly
    row.raidOnly = raidOnly

    local n = #defs
    local bw = math.floor((CONTENT_W - (n - 1) * 4) / n)
    local buttons = {}

    for i, def in ipairs(defs) do
        local b = MakeFlatButton(row, bw, 18, function()
            local p = P(); if not p then return end
            p[def.key] = not p[def.key]
            row.Sync()
            Refilter()
        end)
        b:SetPoint("LEFT", row, "LEFT", (i - 1) * (bw + 4), 0)
        b.label:SetText(def.label)
        b:HookScript("OnEnter", function(self)
            ShowTip(self, EllesmereUI.L(def.name), EllesmereUI.L(DIFF_TIP))
        end)
        b:HookScript("OnLeave", HideTip)
        buttons[i] = b
    end

    row.Sync = function()
        local p = P(); if not p then return end
        local ar, ag, ab = Accent()
        for i, def in ipairs(defs) do
            if p[def.key] then
                buttons[i].label:SetTextColor(ar, ag, ab, 1)
            else
                buttons[i].label:SetTextColor(0.5, 0.5, 0.5, 1)
            end
        end
    end

    rows[#rows + 1] = row
    return row
end

--  Dungeon whitelist ------------------------------------------------------
-- Panel-session state only (not saved settings -- the profile key list for this
-- feature is fixed). Both sections start collapsed so the panel opens compact.
local _dungeonsCollapsed = true
local _raidsCollapsed = true

local DCHECK_H = 16
local DCOL_W = math.floor((CONTENT_W - 4) / 2)

-- Icon grid geometry. 4 columns x 60px = 240 = CONTENT_W exactly, so a normal
-- 8-dungeon season lays out as two tidy rows of four.
local ICON_SZ    = 36
local GRID_COLS  = 4
local GRID_CELL_W = math.floor(CONTENT_W / GRID_COLS)   -- 60
local GRID_CELL_H = ICON_SZ + 14                        -- icon + short name

-- Body repaint hooks, one per whitelist section.
local whitelistBodies = {}

function RepaintWhitelists()
    if #whitelistBodies == 0 then return end
    for i = 1, #whitelistBodies do whitelistBodies[i]() end
    LayoutPanel()
end

--  One whitelist section (header + body), shared by dungeons and raids -----
--  `spec` supplies everything category-specific: the entry list, the profile
--  key, and whether icons are wanted.
local function MakeWhitelistSection(parent, spec)
    local checks, icons = {}, {}
    local body
    local RefreshBody

    local function Whitelist()
        local p = P(); if not p then return nil end
        local wl = p[spec.key]
        if not wl then wl = {}; p[spec.key] = wl end
        return wl
    end

    local function Toggle(groupID, widget)
        local wl = Whitelist(); if not wl or not groupID then return end
        wl[groupID] = (not wl[groupID]) or nil
        widget:Sync()
        Refilter()
    end

    --  Icon cell (current-season keystone dungeons) ------------------------
    local function MakeIconCell()
        local b = Secure.Button(body, function(self) Toggle(self.groupID, self) end)
        b:SetSize(GRID_CELL_W, GRID_CELL_H)

        -- Accent ring: a solid quad one pixel proud of the icon, so the icon
        -- painted on top of it leaves a visible border only when selected.
        local ring = SolidTex(b, "BACKGROUND", Accent())
        ring:SetPoint("TOPLEFT", b, "TOPLEFT", (GRID_CELL_W - ICON_SZ) / 2 - 1, -1)
        ring:SetSize(ICON_SZ + 2, ICON_SZ + 2)
        ring:Hide()

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", (GRID_CELL_W - ICON_SZ) / 2, -2)
        icon:SetSize(ICON_SZ, ICON_SZ)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local fs = MFont(b, 9, 0.8, 0.8, 0.8, 1)
        fs:SetPoint("TOP", icon, "BOTTOM", 0, -1)
        fs:SetWidth(GRID_CELL_W)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)

        b.SetEntry = function(_, id, name, rec)
            b.groupID, b.fullName = id, name
            icon:SetTexture(rec.texture)
            -- Abbreviate the name we actually show in the tooltip (the activity
            -- group's), not the challenge map's -- the mapID repair route can
            -- pair a group with a map whose name reads differently.
            fs:SetText(Abbrev(name))
            b:Sync()
        end
        b.Sync = function()
            local wl = Whitelist()
            local on = (wl and b.groupID and wl[b.groupID]) and true or false
            ring:SetShown(on)
            icon:SetDesaturated(not on)
            icon:SetAlpha(on and 1 or 0.45)
            fs:SetTextColor(on and 1 or 0.55, on and 1 or 0.55, on and 1 or 0.55, 1)
        end

        b:SetScript("OnEnter", function(self)
            ShowTip(self, self.fullName or "", EllesmereUI.L(spec.tip))
        end)
        b:SetScript("OnLeave", HideTip)
        return b
    end

    --  Text row (anything with no icon: other expansions, timerunning, raids)
    local function MakeTextCheck()
        local b = Secure.Button(body, function(self) Toggle(self.groupID, self) end)
        b:SetHeight(DCHECK_H)
        b:SetWidth(DCOL_W)

        local box = CreateFrame("Frame", nil, b)
        box:SetSize(11, 11)
        box:SetPoint("LEFT", b, "LEFT", 0, 0)
        SolidTex(box, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints(box)
        Border(box, 1, 1, 1, 0.15, 7)

        local check = SolidTex(box, "ARTWORK", Accent())
        check:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
        check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        check:Hide()

        local fs = MFont(b, 10, 0.8, 0.8, 0.8, 1)
        fs:SetPoint("LEFT", box, "RIGHT", 4, 0)
        fs:SetPoint("RIGHT", b, "RIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)

        b.SetEntry = function(_, id, name)
            b.groupID, b.fullName = id, name
            fs:SetText(name)
            b:Sync()
        end
        b.Sync = function()
            local wl = Whitelist()
            check:SetShown((wl and b.groupID and wl[b.groupID]) and true or false)
        end

        b:SetScript("OnEnter", function(self)
            fs:SetTextColor(1, 1, 1, 1)
            ShowTip(self, self.fullName or "", EllesmereUI.L(spec.tip))
        end)
        b:SetScript("OnLeave", function()
            fs:SetTextColor(0.8, 0.8, 0.8, 1)
            HideTip()
        end)
        return b
    end

    -- Scoped to what this tab currently enumerates -- never wipe(wl), which
    -- would silently discard the other tab's selections. Keys left behind by
    -- another tab or a past season stay in the table but are inert: the
    -- whitelist rule only ever considers the intersection with this
    -- enumeration, so they cost nothing and are not worth a cleanup pass.
    local function SetAll(on)
        local wl = Whitelist(); if not wl then return end
        local list = spec.list()
        for i = 1, #list do
            wl[list[i].id] = on and true or nil
        end
        RefreshBody()
        Refilter()
    end

    --  Header ---------------------------------------------------------------
    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(16)
    header.dungeonOnly = not spec.raid
    header.raidOnly = spec.raid
    -- An empty enumeration means the whole section stays out of the layout.
    header.shouldShow = function() return #spec.list() > 0 end

    local hfs = MFont(header, 10, Accent())
    hfs:SetPoint("LEFT", header, "LEFT", 0, 0)

    -- All/None stay live while collapsed: resetting the filter should not
    -- require expanding the section first.
    local none = MakeFlatButton(header, 38, 14, function() SetAll(false) end)
    none:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    none.label:SetText(EllesmereUI.L("None"))
    none:HookScript("OnEnter", function(self)
        ShowTip(self, EllesmereUI.L("None"), EllesmereUI.L("Clear the selection. An empty selection filters nothing out."))
    end)
    none:HookScript("OnLeave", HideTip)

    local all = MakeFlatButton(header, 32, 14, function() SetAll(true) end)
    all:SetPoint("RIGHT", none, "LEFT", -4, 0)
    all.label:SetText(EllesmereUI.L("All"))
    all:HookScript("OnEnter", function(self)
        ShowTip(self, EllesmereUI.L("All"), EllesmereUI.L("Select everything, ready to untick the few you do not want."))
    end)
    all:HookScript("OnLeave", HideTip)

    header.Sync = function()
        hfs:SetText((spec.collapsed() and "+ " or "- ") .. EllesmereUI.L(spec.title))
    end
    header:SetScript("OnClick", function()
        spec.setCollapsed(not spec.collapsed())
        header.Sync()
        LayoutPanel()
    end)
    rows[#rows + 1] = header

    --  Body -----------------------------------------------------------------
    body = CreateFrame("Frame", nil, parent)
    body:SetHeight(DCHECK_H)
    body.dungeonOnly = not spec.raid
    body.raidOnly = spec.raid
    body.shouldShow = function() return not spec.collapsed() and #spec.list() > 0 end
    body.Sync = function() RefreshBody() end
    rows[#rows + 1] = body

    -- Entries that resolve an icon go to the grid; the rest fall back to text
    -- rows underneath it. Both are pooled and only ever grow.
    function RefreshBody()
        -- Cells are secure frames: creating, anchoring and showing them is all
        -- blocked in combat, so defer the whole rebuild.
        if Secure.Blocked() then return end
        local list = spec.list()
        local nIcon, nText = 0, 0
        local y = 0

        if spec.icons then
            for i = 1, #list do
                local e = list[i]
                local rec = _iconByGroup[e.id]
                if rec then
                    nIcon = nIcon + 1
                    local c = icons[nIcon]
                    if not c then c = MakeIconCell(); icons[nIcon] = c end
                    c:SetEntry(e.id, e.name, rec)
                    local col = (nIcon - 1) % GRID_COLS
                    local line = math.floor((nIcon - 1) / GRID_COLS)
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", body, "TOPLEFT", col * GRID_CELL_W, -line * GRID_CELL_H)
                    c:Show()
                end
            end
            y = math.ceil(nIcon / GRID_COLS) * GRID_CELL_H
            if nIcon > 0 then y = y + 2 end
        end

        for i = 1, #list do
            local e = list[i]
            if not (spec.icons and _iconByGroup[e.id]) then
                nText = nText + 1
                local c = checks[nText]
                if not c then c = MakeTextCheck(); checks[nText] = c end
                c:SetEntry(e.id, e.name)
                local col = (nText - 1) % 2
                local line = math.floor((nText - 1) / 2)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", body, "TOPLEFT", col * (DCOL_W + 4), -(y + line * DCHECK_H))
                c:Show()
            end
        end
        y = y + math.ceil(nText / 2) * DCHECK_H

        for i = nIcon + 1, #icons do icons[i]:Hide() end
        for i = nText + 1, #checks do checks[i]:Hide() end

        body:SetHeight(math.max(DCHECK_H, y))
    end

    whitelistBodies[#whitelistBodies + 1] = RefreshBody
    return header, body
end

--  Expression -------------------------------------------------------------
local exprErrFS
local EXPR_HELP =
    "score, members, tanks, heals, dps, ilvl, age, friends,\n"
    .. "delisted, declined, warmode,\n"
    .. "normal, heroic, mythic, mythicplus, activity,\n"
    .. "floor, min, max, abs, find(\"text\")\n\n"
    .. "Example: score >= 2500 and tanks == 0 and find(\"halls\")\n\n"
    .. "Anything the expression cannot answer is kept."

local function ExprEnabled()
    local p = P()
    return (p and p.expressionEnabled) and true or false
end

local function MakeExpressionRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.shouldShow = ExprEnabled

    local eb = CreateFrame("EditBox", nil, row)
    eb:SetHeight(18)
    eb:SetPoint("LEFT", row, "LEFT", 0, 0)
    eb:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(240)
    eb:SetJustifyH("LEFT")
    eb:SetTextInsets(5, 5, 0, 0)
    eb:SetFont(PanelFont(), 11, "")
    eb:SetTextColor(1, 1, 1, 0.9)
    SolidTex(eb, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints(eb)
    Border(eb, 1, 1, 1, 0.12, 7)

    exprErrFS = MFont(row, 13, 0.95, 0.25, 0.25, 1)
    exprErrFS:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    exprErrFS:SetText("!")
    exprErrFS:Hide()

    -- The error lamp needs a hover target of its own; a font string has none.
    local errHit = CreateFrame("Button", nil, row)
    errHit:SetSize(14, 18)
    errHit:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    errHit:SetScript("OnEnter", function(self)
        local err = ExpressionError()
        if not err then return end
        ShowTip(self, EllesmereUI.L("Expression error"), err, 1, 0.4, 0.4)
    end)
    errHit:SetScript("OnLeave", HideTip)
    row.errHit = errHit

    eb:SetScript("OnEnter", function(self)
        ShowTip(self, EllesmereUI.L("Filter expression"), EllesmereUI.L(EXPR_HELP))
    end)
    eb:SetScript("OnLeave", HideTip)

    local cancelling = false
    local function commit()
        if cancelling then return end
        local p = P(); if not p then return end
        local text = eb:GetText() or ""
        eb:ClearFocus()
        if text == (p.expression or "") then return end
        p.expression = text
        -- Compile eagerly so a syntax error lights the lamp on commit rather
        -- than waiting for the next result list.
        CompileExpression(text)
        UpdateExprError()
        Refilter()
    end
    eb:SetScript("OnEnterPressed", commit)
    eb:SetScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function(self)
        cancelling = true
        self:ClearFocus()
        cancelling = false
        row.Sync()
    end)

    row.Sync = function()
        local p = P(); if not p then return end
        if not eb:HasFocus() then eb:SetText(p.expression or "") end
        UpdateExprError()
    end

    rows[#rows + 1] = row
    ctl.expression = row
    return row
end

function UpdateExprError()
    if not exprErrFS then return end
    local show = ExprEnabled() and ExpressionError() and true or false
    exprErrFS:SetShown(show)
    if ctl.expression and ctl.expression.errHit then
        ctl.expression.errHit:EnableMouse(show)
    end
end

--  Layout ----------------------------------------------------------------
function LayoutPanel()
    if not sidePanel then return end
    -- Rows are secure frames; Show/Hide/SetPoint on them is blocked in combat.
    if Secure.Blocked() then return end
    -- Safety net for controls built while attributes were locked. No-op once the
    -- queue drains.
    if Secure.pending[1] then Secure.Flush() end
    local dungeon = IsDungeonBrowse()
    local raid = IsRaidBrowse()
    -- Only a dungeon search can apply what these controls save.
    Secure.SetForwarding(dungeon)
    local y = -PAD - 22  -- below the title strip
    for _, row in ipairs(rows) do
        if (row.dungeonOnly and not dungeon)
            or (row.raidOnly and not raid)
            or (row.shouldShow and not row.shouldShow()) then
            row:Hide()
        else
            row:Show()
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", PAD, y)
            row:SetPoint("TOPRIGHT", sidePanel, "TOPRIGHT", -PAD, y)
            y = y - row:GetHeight() - GAP
        end
    end
    countFS:ClearAllPoints()
    countFS:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", PAD, y - 2)
    countFS:SetPoint("TOPRIGHT", sidePanel, "TOPRIGHT", -PAD, y - 2)
    sidePanel:SetHeight(math.max(60, -y + 14 + PAD))
end

-- Three states, in priority order: the pass stood down, a saved dungeon filter
-- that has not reached the list yet, and the ordinary match count. Every click
-- control now re-runs the search on its own click, so the pending line is
-- normally a brief flash between the click and the results arriving. It still
-- earns its place for the score box, which is typed rather than clicked and so
-- waits for its Apply button.
function UpdateCountText()
    if not countFS then return end
    if _paused then
        countFS:SetText(EllesmereUI.L("Marking paused while group data is protected"))
        countFS:Show()
    elseif _nativeDirty and #_pristine > 0 then
        -- Only worth saying when there is a stale list to be stale ABOUT; with
        -- no results on screen the next search is going to happen anyway.
        countFS:SetText(EllesmereUI.L("Searching to apply the new filters..."))
        countFS:Show()
    elseif _shown and _total and _shown < _total then
        countFS:SetFormattedText(EllesmereUI.L("%d of %d groups match"), _shown, _total)
        countFS:Show()
    else
        countFS:SetText("")
        countFS:Hide()
    end
end

function SyncControls()
    for _, row in ipairs(rows) do
        if row.Sync then row.Sync() end
    end
    UpdateCountText()
end

-------------------------------------------------------------------------------
--  RaiderIO coexistence
--
--  RaiderIO parks its profile window on a global anchor frame that, absent the
--  real PremadeGroupsFilter addon, is pinned to PVEFrame TOPLEFT->TOPRIGHT --
--  i.e. straight on top of our panel. We substitute the relativeTo argument so
--  it lands to our right instead (the same trick ElvUI_WindTools uses).
--
--  The raw method override below is only acceptable because the anchor is a
--  third-party, non-secure frame owned by RaiderIO. NEVER do this to a Blizzard
--  frame: replacing a method there taints every execution path that touches it.
--  If the real PremadeGroupsFilter is also loaded we do nothing at all --
--  RaiderIO already has a rule for it and we don't arbitrate between two
--  filter addons.
-------------------------------------------------------------------------------
local _rioAnchor, _rioDone

local function InstallRaiderIOAnchor()
    if _rioDone then return end
    local anchor = _G.RaiderIO_ProfileTooltipAnchor
    -- No anchor yet just means RaiderIO has not loaded; try again next show.
    if not anchor or type(anchor.SetPoint) ~= "function" then return end
    _rioDone = true

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("PremadeGroupsFilter") then
        return
    end

    local orig = anchor.SetPoint
    anchor.SetPoint = function(self, point, rel, relPoint, x, y, ...)
        if rel == PVEFrame or (sidePanel and rel == sidePanel) then
            rel = (sidePanel and sidePanel:IsShown()) and sidePanel or PVEFrame
        end
        return orig(self, point, rel, relPoint, x, y, ...)
    end
    _rioAnchor = anchor
end

-- Re-run RaiderIO's last placement through the wrapper so it moves the moment
-- our panel appears or disappears.
local function ReanchorRaiderIO()
    local anchor = _rioAnchor
    if not anchor then return end
    if (anchor:GetNumPoints() or 0) < 1 then return end
    local point, rel, relPoint, x, y = anchor:GetPoint(1)
    if not point or not rel then return end
    anchor:ClearAllPoints()
    anchor:SetPoint(point, rel, relPoint, x, y)
end

--  Frame construction (lazy) ---------------------------------------------
local function BuildSidePanel()
    if sidePanel then return end

    sidePanel = CreateFrame("Frame", "EllesmereUIPremadeFilterPanel", PVEFrame)
    sidePanel:SetWidth(PANEL_W)
    sidePanel:SetHeight(200)
    sidePanel:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", 2, 0)
    sidePanel:SetFrameStrata(PVEFrame:GetFrameStrata())
    sidePanel:SetFrameLevel(PVEFrame:GetFrameLevel() + 5)
    sidePanel:EnableMouse(true)
    sidePanel:Hide()

    SolidTex(sidePanel, "BACKGROUND", 0.08, 0.08, 0.08, 0.92):SetAllPoints(sidePanel)
    Border(sidePanel, 0.2, 0.2, 0.2, 1, 7)

    local titleBg = SolidTex(sidePanel, "BORDER", 0, 0, 0, 0.25)
    titleBg:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", 1, -1)
    titleBg:SetPoint("TOPRIGHT", sidePanel, "TOPRIGHT", -1, -1)
    titleBg:SetHeight(20)

    local title = MFont(sidePanel, 12, 1, 1, 1, 1)
    title:SetPoint("LEFT", titleBg, "LEFT", PAD, 0)
    title:SetText(EllesmereUI.L("Premade Filter"))

    countFS = MFont(sidePanel, 10, 0.55, 0.55, 0.55, 1)
    countFS:SetJustifyH("LEFT")
    countFS:Hide()

    MakeHeader(sidePanel, EllesmereUI.L("FILTERS"))
    MakeCheck(sidePanel, EllesmereUI.L("Dim delisted groups"), "hideDelisted", false)
    MakeCheck(sidePanel, EllesmereUI.L("Dim declined groups"), "hideDeclined", false)
    MakeCheck(sidePanel, EllesmereUI.L("Minimum leader score"), "minLeaderScoreEnabled", true, function()
        if ctl.minLeaderScore then ctl.minLeaderScore.Sync() end
    end)
    MakeScoreBox(sidePanel)
    MakeCheck(sidePanel, EllesmereUI.L("Needs a tank"), "needsTank", true)
    MakeCheck(sidePanel, EllesmereUI.L("Needs a healer"), "needsHealer", true)
    MakeCheck(sidePanel, EllesmereUI.L("My role available"), "myRoleAvailable", true)
    MakeCheck(sidePanel, EllesmereUI.L("Fits my whole party"), "partyFit", true)

    MakeHeader(sidePanel, EllesmereUI.L("DIFFICULTY")).dungeonOnly = true
    MakeDifficultyRow(sidePanel, DIFFS_DUNGEON, false)

    MakeWhitelistSection(sidePanel, {
        title = "DUNGEONS",
        key   = "dungeonWhitelist",
        raid  = false,
        icons = true,
        tip   = "Selected dungeons are kept. With none selected, every dungeon is kept. Sent to Blizzard's own filter, so ticking one removes non-matching groups straight away.",
        list  = function() return _dungeons end,
        collapsed    = function() return _dungeonsCollapsed end,
        setCollapsed = function(v) _dungeonsCollapsed = v end,
    })

    MakeHeader(sidePanel, EllesmereUI.L("DIFFICULTY")).raidOnly = true
    MakeDifficultyRow(sidePanel, DIFFS_RAID, true)

    MakeWhitelistSection(sidePanel, {
        title = "RAIDS",
        key   = "raidWhitelist",
        raid  = true,
        icons = false,
        tip   = "Selected raids are kept. With none selected, every raid is kept. Blizzard's filter is dungeons-only, so non-matching raid groups are shaded rather than removed.",
        list  = function() return _raids end,
        collapsed    = function() return _raidsCollapsed end,
        setCollapsed = function(v) _raidsCollapsed = v end,
    })

    MakeHeader(sidePanel, EllesmereUI.L("EXPRESSION")).shouldShow = ExprEnabled
    MakeExpressionRow(sidePanel)

    -- No SORT section: reordering the browse means writing the results array,
    -- which is the taint documented at the top of this file. Blizzard's own
    -- comparator already sorts declined last and friends first.

    -- Our own frame, so SetScript is ours to use.
    sidePanel:SetScript("OnShow", function()
        InstallRaiderIOAnchor()
        ReanchorRaiderIO()
    end)
    sidePanel:SetScript("OnHide", ReanchorRaiderIO)

    BuildDungeonIcons(BuildDungeonList())
    BuildRaidList(LFGListFrame and LFGListFrame.SearchPanel)
    SyncControls()
    LayoutPanel()
end

local function BuildToggleButton()
    if toggleBtn then return end
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    if not sp or not sp.RefreshButton then return end

    toggleBtn = MakeFlatButton(sp, 54, 20)
    toggleBtn:SetPoint("RIGHT", sp.RefreshButton, "LEFT", -6, -1)
    toggleBtn.label:SetText(EllesmereUI.L("Filters"))
    toggleBtn:SetScript("OnClick", function()
        local p = P(); if not p then return end
        p.panelCollapsed = not p.panelCollapsed
        RefreshVisibility()
    end)
    toggleBtn:Hide()
end

-------------------------------------------------------------------------------
--  Visibility
-------------------------------------------------------------------------------
local function SearchPanelActive()
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    return sp and sp:IsShown() and PVEFrame and PVEFrame:IsShown()
end

function RefreshVisibility()
    local p = P()
    local on = p and p.enabled and true or false

    -- Self-heal: BuildToggleButton bails if SearchPanel.RefreshButton was not
    -- there yet at install time, and this button is the only control for
    -- panelCollapsed -- so retry until it sticks. The build is idempotent.
    if on and not toggleBtn then BuildToggleButton() end

    if toggleBtn then
        toggleBtn:SetShown((on and SearchPanelActive()) and true or false)
        if on then
            if p.panelCollapsed then
                toggleBtn.label:SetTextColor(0.85, 0.85, 0.85, 1)
            else
                local ar, ag, ab = Accent()
                toggleBtn.label:SetTextColor(ar, ag, ab, 1)
            end
        end
    end

    if not sidePanel then
        if on and not p.panelCollapsed and SearchPanelActive() then
            BuildSidePanel()
        else
            return
        end
    end

    if on and not p.panelCollapsed and SearchPanelActive() then
        -- Keeps the lists honest across a season rollover or a Timerunning
        -- character swap. The group enumeration is a handful of IDs; the icon
        -- walk behind it is cached and only redone if that id set changed.
        if IsDungeonBrowse() then
            BuildDungeonIcons(BuildDungeonList())
        elseif IsRaidBrowse() then
            BuildRaidList(LFGListFrame and LFGListFrame.SearchPanel)
        end
        -- Sync first: the dungeon list rebuilds its own height in there, and
        -- the layout needs that height to be current.
        SyncControls()
        LayoutPanel()
        sidePanel:Show()
    else
        sidePanel:Hide()
    end
end

-------------------------------------------------------------------------------
--  Install. hooksecurefunc is permanent, so once installed the hook bodies
--  gate themselves on the enabled flag; nothing at all is installed until the
--  feature is enabled for the first time.
-------------------------------------------------------------------------------
local _installed = false

local function InstallHooks()
    if _installed then return end
    if type(LFGListSearchPanel_UpdateResultList) ~= "function" then return end
    if type(LFGListSearchPanel_UpdateResults) ~= "function" then return end
    if not LFGListFrame or not LFGListFrame.SearchPanel or not PVEFrame then return end
    _installed = true

    -- Post-hook only, and its body reads panel.results without ever writing it.
    hooksecurefunc("LFGListSearchPanel_UpdateResultList", OnUpdateResultList)

    if type(LFGListFrame_SetActivePanel) == "function" then
        hooksecurefunc("LFGListFrame_SetActivePanel", function() RefreshVisibility() end)
    end
    if type(LFGListSearchPanel_SetCategory) == "function" then
        hooksecurefunc("LFGListSearchPanel_SetCategory", function() RefreshVisibility() end)
    end
    if type(PVEFrame_ShowFrame) == "function" then
        hooksecurefunc("PVEFrame_ShowFrame", function() RefreshVisibility() end)
    end
    if type(GroupFinderFrame_ShowGroupFrame) == "function" then
        hooksecurefunc("GroupFinderFrame_ShowGroupFrame", function() RefreshVisibility() end)
    end

    PVEFrame:HookScript("OnShow", function() RefreshVisibility() end)
    PVEFrame:HookScript("OnHide", function() RefreshVisibility() end)
    LFGListFrame.SearchPanel:HookScript("OnShow", function() RefreshVisibility() end)
    LFGListFrame.SearchPanel:HookScript("OnHide", function() RefreshVisibility() end)

    BuildToggleButton()

    -- Take over the advanced filter as soon as we are live, so a session that
    -- starts with the feature already on does not wait for the first control
    -- change to describe itself to Blizzard.
    SyncNativeFilter()

    -- Results may already be on screen when the user first enables us; seed the
    -- pristine snapshot from them (they are unfiltered, we were off).
    local sp = LFGListFrame.SearchPanel
    if sp.results and #sp.results > 0 then
        wipe(_pristine)
        _pristineCategory = sp.categoryID
        for i = 1, #sp.results do _pristine[i] = sp.results[i] end
    end
end

local _waiting = false
local waiter

-- Blizzard_GroupFinder is DefaultState:enabled so it is normally already there
-- at PLAYER_LOGIN; InstallHooks self-guards on the globals, and the
-- ADDON_LOADED wait is only the fallback for a delayed load.
local function EnsureInstalled()
    if _installed or not Enabled() then return end
    InstallHooks()
    if _installed or _waiting then return end
    _waiting = true
    waiter = waiter or CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:SetScript("OnEvent", function(self, _, name)
        if name ~= "Blizzard_GroupFinder" then return end
        self:UnregisterAllEvents()
        _waiting = false
        InstallHooks()
        RefreshVisibility()
        Refilter()
    end)
end

-------------------------------------------------------------------------------
--  Public entry points (options page coupling, house _G pattern)
-------------------------------------------------------------------------------
local function Refresh()
    if not db then return end
    EnsureInstalled()
    RefreshVisibility()
    Refilter()
end

_G._EUI_PremadeFilter_DB = function() return db end
_G._EUI_RefreshPremadeFilter = Refresh

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_LOGOUT")
boot:SetScript("OnEvent", function(self, event)
    -- The advanced filter is client state that OUTLIVES the session, so hand it
    -- back on the way out. Without this the snapshot taken on the next login
    -- would be of our own values, and the user's real filter would be lost the
    -- first time they reloaded -- restoring it on disable would then restore
    -- ours. This is the only reason PLAYER_LOGOUT is registered.
    if event == "PLAYER_LOGOUT" then
        RestoreUserFilter()
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.Lite or not EllesmereUI.Lite.NewDB then return end
    EUI = EllesmereUI
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", defaults, true)
    -- Nothing is hooked, framed or registered while the feature is off.
    EnsureInstalled()
end)
