if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Sort.lua
--
--  Show Self First, the Prioritize Class lists, the FrameSort provider and
--  ApplySortToHeaders.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local ipairs       = ipairs
local wipe         = wipe
local type         = type
local tostring     = tostring
local UnitName              = UnitName
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local UnitIsUnit            = UnitIsUnit
local IsInRaid              = IsInRaid
local IsInGroup             = IsInGroup
local InCombatLockdown      = InCombatLockdown
local GetNumGroupMembers    = GetNumGroupMembers
local issecretvalue         = issecretvalue

local separatedHdrs = I.separatedHdrs

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local containerFrame
I.containerFrameSetters[#I.containerFrameSetters + 1] = function(v) containerFrame = v end

-------------------------------------------------------------------------------
--  Show Self First (raid, OOC only): the player's subgroup header sorts via a
--  per-group nameList listing every member with the player first, so the
--  secure header orders natively -- no SetPoint override, no flicker.
--  showPlayer can't exclude the player in a raid, so the party-style self
--  button doesn't apply here. Merged mode pins the player via a whole-raid
--  nameList instead (ns._BuildMergedSelfNameList below).
-------------------------------------------------------------------------------
-- Player's raid subgroup (1-8). Party/solo collapses to group 1.
function ns._GetPlayerSubgroup()
    if not IsInRaid() then return 1 end
    local n = GetNumGroupMembers()
    for i = 1, n do
        if UnitIsUnit("raid" .. i, "player") then
            local _, _, subgroup = GetRaidRosterInfo(i)
            return subgroup
        end
    end
    return nil
end

-- A nameList is a FILTER as much as an order: the secure header re-matches
-- every member's CURRENT name against the list on its own, in combat too,
-- and a member whose name is not listed is hidden outright. Names are not
-- stable: the UNKNOWNOBJECT placeholder stands in while a roster entry has
-- not populated yet (zoning, mid-loadscreen join) AND whenever a rename
-- effect resolves a unit to it mid-fight, when the attribute cannot be
-- rewritten. Every list therefore ends with the placeholder token, so a
-- member carrying it stays visible (sorted last) until the next rebuild
-- re-lists them under their real name. Builders skip in-set placeholders
-- (the token covers them) and bail to nil when a placeholder exists OUTSIDE
-- their set: the token would pull that member into a header that must not
-- show them, so the engine path (everyone visible, native order) runs until
-- names resolve. Pass the sorted member entries (each carrying .name).
-- noToken: per-group lists that cover EVERY separated header (Prioritize
-- Class, FrameSort) leave the token off -- it would pull a placeholder that
-- appears mid-fight into all of those headers at once; such a member waits
-- for the regen rebuild instead, and the builders drop a group whose own
-- roster holds a placeholder to its native path.
function ns._FinishNameList(members, noToken)
    local names = ns._nlBuf
    if names then wipe(names) else names = {}; ns._nlBuf = names end
    for i = 1, #members do names[i] = members[i].name end
    if not noToken then names[#names + 1] = UNKNOWNOBJECT end
    return table.concat(names, ",")
end

-- Reused member records and per-group buckets for the list builders, which
-- run on every LayoutGroups pass (options slider drags included). One builder
-- runs at a time and returns finished strings, so the pool is free again when
-- it returns; each builder writes every field its comparator reads.
function ns._NLRec(i)
    local pool = ns._nlPool
    if not pool then pool = {}; ns._nlPool = pool end
    local m = pool[i]
    if not m then m = {}; pool[i] = m end
    return m
end

function ns._NLGroups()
    local groups, bad = ns._nlGroups, ns._nlBad
    if groups then
        for g = 1, 8 do wipe(groups[g]) end
        wipe(bad)
    else
        groups, bad = {}, {}
        for g = 1, 8 do groups[g] = {} end
        ns._nlGroups, ns._nlBad = groups, bad
    end
    return groups, bad
end

-- Build a "player first" nameList for the player's raid subgroup. Names come from
-- GetRaidRosterInfo (same source the secure header matches against, range-independent),
-- so nothing can vanish. Others follow the active sort: role order (ROLE mode, via
-- EllesmereUI.UnitEffectiveRole) else raid index. selfLast orders the player LAST instead.
function ns._BuildSelfFirstNameList(playerGroup, sortByRole, roleOrder, selfLast)
    if not IsInRaid() or not playerGroup then return nil end
    local pri
    if sortByRole then
        pri = {}
        for p, r in ipairs(roleOrder) do pri[r] = p end
    end
    local members = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup = GetRaidRosterInfo(i)
        -- A nil name = roster not populated at all; the subgroup is not
        -- trustworthy either. Bail (see ns._FinishNameList).
        if not name then return nil end
        if subgroup == playerGroup then
            if name ~= UNKNOWNOBJECT then
                local unit = "raid" .. i
                local rp = 99
                if pri then rp = pri[EllesmereUI.UnitEffectiveRole(unit)] or 99 end
                members[#members + 1] = {
                    name = name,
                    isPlayer = UnitIsUnit(unit, "player"),
                    rolePri = rp,
                    index = i,
                }
            end
        elseif name == UNKNOWNOBJECT then
            return nil
        end
    end
    if #members == 0 then return nil end
    table.sort(members, function(a, b)
        -- Player to the top (self-first) or bottom (self-last). Exactly one of
        -- a/b is the player inside this branch, so the XOR with selfLast flips it.
        if a.isPlayer ~= b.isPlayer then return a.isPlayer ~= selfLast end
        if sortByRole and a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
        return a.index < b.index
    end)
    return ns._FinishNameList(members)
end

-- Default class sort order: real player classes only, alphabetical by
-- localized name, enumerated via GetNumClasses + C_CreatureInfo.GetClassInfo
-- so non-class entries (Adventurer/Traveler in LOCALIZED_CLASS_NAMES_MALE) are
-- excluded. Also populates ns._classNameByToken (token -> localized name) for
-- the options list. Cached on ns.
function ns._GetDefaultClassOrder()
    if ns._defaultClassOrderCache then return ns._defaultClassOrderCache end
    local list, names = {}, {}
    local n = (GetNumClasses and GetNumClasses()) or 0
    for i = 1, n do
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(i)
        if info and info.classFile then
            list[#list + 1] = info.classFile
            names[info.classFile] = info.className or info.classFile
        end
    end
    table.sort(list, function(a, b) return (names[a] or a) < (names[b] or b) end)
    ns._classNameByToken = names
    if #list > 0 then ns._defaultClassOrderCache = list end
    return list
end

-- Build a class-priority nameList for the party header. Lists the party members
-- the header shows (player only when includePlayer), ordered by role (optional
-- primary) -> class -> name. Names use the same UnitName + "-realm" format
-- Blizzard's GetGroupRosterInfo produces for party units, so the secure header
-- matches them. nameList is only honored when groupFilter is cleared.
function ns._BuildPartyClassNameList(includePlayer, sortByRole, roleOrder, classOrder)
    if not IsInGroup() then return nil end
    classOrder = classOrder or ns._GetDefaultClassOrder()
    local classPri = {}
    for i, c in ipairs(classOrder) do classPri[c] = i end
    local rolePri
    if sortByRole then
        rolePri = {}
        for i, r in ipairs(roleOrder) do rolePri[r] = i end
    end
    local members = {}
    local units = {}
    if includePlayer then units[#units + 1] = "player" end
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name, server = UnitName(unit)
            if not name then return nil end
            -- Every unit here is in the header's set: a placeholder name is
            -- covered by the trailing token (see ns._FinishNameList).
            if name ~= UNKNOWNOBJECT then
                if server and server ~= "" then name = name .. "-" .. server end
                local _, classToken = UnitClass(unit)
                members[#members + 1] = {
                    name = name,
                    rolePri = (rolePri and rolePri[EllesmereUI.UnitEffectiveRole(unit)]) or 99,
                    classPri = classPri[classToken] or 99,
                }
            end
        end
    end
    if #members == 0 then return nil end
    table.sort(members, function(a, b)
        if sortByRole and a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
        if a.classPri ~= b.classPri then return a.classPri < b.classPri end
        return a.name < b.name
    end)
    return ns._FinishNameList(members)
end

-- Party header nameList for ARENA, where the header is bound to raid1-5.
-- showPlayer cannot exclude the player in a raid group and the static self
-- button cannot reorder them; a NAMELIST does both (Hide Self; Self
-- First/Last). Rest follow role order (ROLE mode) else raid index. Names come
-- from GetRaidRosterInfo (what the header matches against). Placeholder
-- names follow the ns._FinishNameList rules (a hidden self is out of set).
function ns._BuildArenaNameList(hideSelf, selfFirst, selfLast, sortByRole, roleOrder, onlyGroup)
    if not IsInRaid() then return nil end
    local pri
    if sortByRole then
        pri = {}
        for p, r in ipairs(roleOrder) do pri[r] = p end
    end
    local members = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if not name then return nil end
        -- Small Raid mode: members outside the kept subgroup are simply not
        -- listed (the header hides them); the player included.
        if not (onlyGroup and subgroup ~= onlyGroup) then
            local unit = "raid" .. i
            local isPlayer = UnitIsUnit(unit, "player")
            if not (hideSelf and isPlayer) then
                if name ~= UNKNOWNOBJECT then
                    local rp = 99
                    if pri then rp = pri[EllesmereUI.UnitEffectiveRole(unit)] or 99 end
                    members[#members + 1] = {
                        name = name,
                        isPlayer = isPlayer,
                        rolePri = rp,
                        index = i,
                    }
                end
            elseif name == UNKNOWNOBJECT then
                return nil
            end
        elseif name == UNKNOWNOBJECT then
            -- Outside the kept subgroup: the token would pull them in.
            return nil
        end
    end
    if #members == 0 then return nil end
    table.sort(members, function(a, b)
        -- Player to top (self-first) or bottom (self-last); exactly one of a/b
        -- is the player in this branch, so the XOR with selfLast flips it.
        if (selfFirst or selfLast) and a.isPlayer ~= b.isPlayer then
            return a.isPlayer ~= selfLast
        end
        if sortByRole and a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
        return a.index < b.index
    end)
    return ns._FinishNameList(members)
end

-- Whole-raid nameList for Merge Groups + Self Position: player pinned first
-- (or last), everyone else in the active sort (role blocks in ROLE mode, raid
-- index otherwise). Replaces the flat header's groupFilter, so members of
-- groups hidden via Show Groups are simply not listed. Placeholder names
-- follow the ns._FinishNameList rules (hidden groups are out of set); the
-- caller falls back to the engine path on a bail.
function ns._BuildMergedSelfNameList(sortByRole, roleOrder, selfLast, visibleGroups)
    if not IsInRaid() then return nil end
    local pri
    if sortByRole then
        pri = {}
        for p, r in ipairs(roleOrder) do pri[r] = p end
    end
    local members = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if not name then return nil end
        if not visibleGroups or visibleGroups[subgroup] ~= false then
            if name ~= UNKNOWNOBJECT then
                local unit = "raid" .. i
                local rp = 99
                if pri then rp = pri[EllesmereUI.UnitEffectiveRole(unit)] or 99 end
                members[#members + 1] = {
                    name = name,
                    isPlayer = UnitIsUnit(unit, "player"),
                    rolePri = rp,
                    index = i,
                }
            end
        elseif name == UNKNOWNOBJECT then
            return nil
        end
    end
    if #members == 0 then return nil end
    table.sort(members, function(a, b)
        -- Player to top (self-first) or bottom (self-last); exactly one of a/b
        -- is the player in this branch, so the XOR with selfLast flips it.
        if a.isPlayer ~= b.isPlayer then return a.isPlayer ~= selfLast end
        if sortByRole and a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
        return a.index < b.index
    end)
    return ns._FinishNameList(members)
end

-------------------------------------------------------------------------------
--  Raid Prioritize Class lists: role (Sort By = Role) -> class (the Class
--  Order list) -> name, the same order as the party header's
--  ns._BuildPartyClassNameList, with Self Position pinning the player first
--  or last. Group sort + Prioritize Class needs no list at all (the headers'
--  own CLASS grouping gives this order and stays live in combat, see
--  ApplySortToHeaders); lists serve Role + Class (a header groups by one key
--  only), Self Position's group, and merged mode. Separated mode returns one
--  list per subgroup, without the placeholder token (see ns._FinishNameList),
--  and leaves out any group whose roster holds a placeholder (native path).
--  onlyGroup (Self Position's one header) and merged mode return a single
--  list WITH the token, under the ns._FinishNameList rules: a placeholder in
--  the set rides the token, one outside it bails. Names come from
--  GetRaidRosterInfo (what the header matches against).
-------------------------------------------------------------------------------
function ns._RCLess(a, b)
    -- Exactly one of a/b is the player here, so the XOR with the Self Last
    -- flag sends them to the top (Self First) or the bottom (Self Last).
    if a.isPlayer ~= b.isPlayer then return a.isPlayer ~= ns._rcSelfLast end
    if a.rolePri ~= b.rolePri then return a.rolePri < b.rolePri end
    if a.classPri ~= b.classPri then return a.classPri < b.classPri end
    return a.name < b.name
end

function ns._BuildRaidClassLists(merged, visibleGroups, sortByRole, roleOrder, classOrder, selfFirst, selfLast, onlyGroup)
    if not IsInRaid() then return nil end
    local classPri = ns._rcClassPri
    if classPri then wipe(classPri) else classPri = {}; ns._rcClassPri = classPri end
    for i, c in ipairs(classOrder or ns._GetDefaultClassOrder()) do classPri[c] = i end
    local rolePri = ns._rcRolePri
    if rolePri then wipe(rolePri) else rolePri = {}; ns._rcRolePri = rolePri end
    if sortByRole then
        for i, r in ipairs(roleOrder) do rolePri[r] = i end
    end
    ns._rcSelfLast = selfLast == true
    local pin = (selfFirst or selfLast) and true or false
    local tok = ns._FsRaidTok()
    local groups, bad = ns._NLGroups()
    local used = 0
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup, _, _, classToken = GetRaidRosterInfo(i)
        if not name or not subgroup then return nil end
        local skip = (merged and visibleGroups and visibleGroups[subgroup] == false)
            or (onlyGroup ~= nil and subgroup ~= onlyGroup)
        if name == UNKNOWNOBJECT then
            if merged or onlyGroup then
                -- One header carrying the token: a placeholder in its set
                -- rides it, one outside would be pulled in.
                if skip then return nil end
            elseif not skip then
                bad[subgroup] = true
            end
        elseif not skip then
            used = used + 1
            local m = ns._NLRec(used)
            local unit = tok[i]
            m.name = name
            m.isPlayer = pin and UnitIsUnit(unit, "player") == true
            m.rolePri = (sortByRole and rolePri[EllesmereUI.UnitEffectiveRole(unit)]) or 99
            m.classPri = classPri[classToken] or 99
            local g = groups[merged and 1 or subgroup]
            g[#g + 1] = m
        end
    end
    if merged then
        local list = groups[1]
        if #list == 0 then return nil end
        table.sort(list, ns._RCLess)
        return ns._FinishNameList(list)
    end
    if onlyGroup then
        local list = groups[onlyGroup]
        if not list or #list == 0 then return nil end
        table.sort(list, ns._RCLess)
        return ns._FinishNameList(list)
    end
    local out = ns._rcOut
    if out then wipe(out) else out = {}; ns._rcOut = out end
    for g = 1, 8 do
        local list = groups[g]
        if #list > 0 and not bad[g] then
            table.sort(list, ns._RCLess)
            out[g] = ns._FinishNameList(list, true)
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  FrameSort provider (compatibility shim for the FrameSort addon). With
--  Sort By = FrameSort the headers take their order from FrameSort's sorted
--  friendly unit list through a nameList built from OUR roster: every member
--  a header shows is listed (a nameList is a filter), members the list does
--  not rank sort last by index, and the ns._FinishNameList placeholder rules
--  apply. FrameSort never reads or moves our frames (self-managed provider);
--  its list is read in place, never modified. Everything below costs nothing
--  unless the mode is picked, and nothing at all when FrameSort is absent.
-------------------------------------------------------------------------------
function ns._FrameSortApi()
    local api = _G.FrameSortApi
    api = api and api.v3
    if api and api.Sorting and api.Sorting.GetFriendlyUnits then return api end
    return nil
end

-- The party mode is live only while FrameSort is loaded: a saved choice with
-- the addon gone runs the native order, and the self button keeps its job.
function ns._FsPartyMode()
    local p = db and db.profile
    return p ~= nil and (p.partySortMode or p.sortMode) == "FRAMESORT" and ns._FrameSortApi() ~= nil
end

-- rank[token] = position in FrameSort's list, players only (pets and the
-- tank-target tokens are not header members), in a reused map. nil when
-- FrameSort is absent or the list ranks no player. `fresh` drops FrameSort's
-- cache first: our own roster handlers can run before its invalidation and
-- would otherwise read the previous roster's order.
function ns._FrameSortRanks(fresh)
    local api = ns._FrameSortApi()
    if not api then return nil end
    if fresh and api.Caching and api.Caching.Invalidate then api.Caching:Invalidate() end
    local units = api.Sorting:GetFriendlyUnits()
    if type(units) ~= "table" then return nil end
    local ok = ns._fsTokenOK
    if not ok then
        ok = { player = true }
        for i = 1, 4 do ok["party" .. i] = true end
        for i = 1, 40 do ok["raid" .. i] = true end
        ns._fsTokenOK = ok
    end
    local rank = ns._fsRank
    if rank then wipe(rank) else rank = {}; ns._fsRank = rank end
    local n = 0
    for i = 1, #units do
        local tok = units[i]
        if type(tok) == "string" and ok[tok] and not rank[tok] then
            n = n + 1
            rank[tok] = n
        end
    end
    if n == 0 then return nil end
    return rank
end

function ns._FsMemberLess(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.index < b.index
end

function ns._FsRaidTok()
    local tok = ns._raidTok
    if not tok then
        tok = {}
        for i = 1, 40 do tok[i] = "raid" .. i end
        ns._raidTok = tok
    end
    return tok
end

-- Raid: separated mode returns one nameList per subgroup, without the
-- placeholder token (see ns._FinishNameList); a group missing from the result
-- (none of its members listed, or a placeholder in its roster) keeps the
-- native path. Merged mode returns the whole-raid list for the visible groups:
-- a placeholder in a hidden group bails, one in a visible group rides the
-- token. Names come from GetRaidRosterInfo (what the header matches against).
function ns._BuildFrameSortRaidLists(rank, merged, visibleGroups)
    if not IsInRaid() then return nil end
    local tok = ns._FsRaidTok()
    local groups, bad = ns._NLGroups()
    local used = 0
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if not name or not subgroup then return nil end
        local hidden = merged and visibleGroups and visibleGroups[subgroup] == false
        if name == UNKNOWNOBJECT then
            if merged then
                if hidden then return nil end
            else
                bad[subgroup] = true
            end
        elseif not hidden then
            used = used + 1
            local m = ns._NLRec(used)
            m.name, m.rank, m.index = name, rank[tok[i]] or 99, i
            local g = groups[merged and 1 or subgroup]
            g[#g + 1] = m
        end
    end
    if merged then
        local list = groups[1]
        if #list == 0 then return nil end
        table.sort(list, ns._FsMemberLess)
        return ns._FinishNameList(list)
    end
    local out = ns._fsGroupLists
    if out then wipe(out) else out = {}; ns._fsGroupLists = out end
    for g = 1, 8 do
        local list = groups[g]
        if #list > 0 and not bad[g] then
            table.sort(list, ns._FsMemberLess)
            out[g] = ns._FinishNameList(list, true)
        end
    end
    return out
end

-- Party header on party units: the same UnitName + "-realm" form as
-- ns._BuildPartyClassNameList. Names can be secret in restricted content:
-- a secret or missing name bails to the native path.
function ns._BuildFrameSortPartyNameList(rank, includePlayer)
    if not IsInGroup() then return nil end
    local members = {}
    for i = includePlayer and 0 or 1, 4 do
        local unit = (i == 0) and "player" or ("party" .. i)
        if UnitExists(unit) then
            local name, server = UnitName(unit)
            if (issecretvalue and (issecretvalue(name) or issecretvalue(server)))
                or type(name) ~= "string" then
                return nil
            end
            if name ~= UNKNOWNOBJECT then
                if server and server ~= "" then name = name .. "-" .. server end
                members[#members + 1] = { name = name, rank = rank[unit] or 99, index = i }
            end
        end
    end
    if #members == 0 then return nil end
    table.sort(members, ns._FsMemberLess)
    return ns._FinishNameList(members)
end

-- Party header bound to raid units (arena, Small Raid): the arena builder's
-- membership rules (Hide Self, one kept subgroup) in FrameSort's order.
function ns._BuildFrameSortRaidPartyNameList(rank, hideSelf, onlyGroup)
    if not IsInRaid() then return nil end
    local tok = ns._FsRaidTok()
    local members = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if not name then return nil end
        if not (onlyGroup and subgroup ~= onlyGroup) then
            local unit = tok[i]
            if not (hideSelf and UnitIsUnit(unit, "player")) then
                if name ~= UNKNOWNOBJECT then
                    members[#members + 1] = { name = name, rank = rank[unit] or 99, index = i }
                end
            elseif name == UNKNOWNOBJECT then
                return nil
            end
        elseif name == UNKNOWNOBJECT then
            -- Outside the kept subgroup: the token would pull them in.
            return nil
        end
    end
    if #members == 0 then return nil end
    table.sort(members, ns._FsMemberLess)
    return ns._FinishNameList(members)
end

-- FrameSort's sort request (and its settings-changed callback): re-apply the
-- headers from its list. Out of combat only (attribute writes); a request in
-- combat rides the regen flush. Returns whether any header attribute changed,
-- which FrameSort's post-sort callbacks key on.
function ns._FrameSortApply()
    -- Zero cost unless the mode is picked (FrameSort calls in on its own runs
    -- and settings edits whatever our choice).
    local p = db and db.profile
    if not (p and (p.sortMode == "FRAMESORT" or (p.partySortMode or p.sortMode) == "FRAMESORT")) then
        return false
    end
    if InCombatLockdown() then
        ns._rosterDirtyInCombat = true
        return false
    end
    if not ns._FrameSortApi() then return false end
    ns._fsChanged = false
    ns._fsFromProvider = true
    if ns._raidFramesVisible and ns._ApplySortToHeaders then ns._ApplySortToHeaders() end
    if ns._partyFramesVisible and ns._LayoutPartyFrames then ns._LayoutPartyFrames() end
    ns._fsFromProvider = nil
    return ns._fsChanged == true
end

-- Registers once FrameSort's API exists (FrameSort loads after this addon).
-- A provider registered before FrameSort's own init is asked for Init, so
-- one is supplied; Containers is read on every provider at combat start.
-- Name is spliced into a secure attribute key and Enabled is written as an
-- attribute value, so both return plain values only.
function ns._FrameSortRegister()
    if ns._fsRegistered then return end
    local api = ns._FrameSortApi()
    if not (api and api.Sorting.RegisterFrameProvider) then return end
    local none = {}
    local provider = {
        Name = function() return "EllesmereUI" end,
        Enabled = function()
            local p = db and db.profile
            return p ~= nil and (p.sortMode == "FRAMESORT" or (p.partySortMode or p.sortMode) == "FRAMESORT")
        end,
        IsVisible = function()
            return ns._raidFramesVisible == true or ns._partyFramesVisible == true
        end,
        IsSelfManaged = true,
        Containers = function() return none end,
        Init = function() end,
        Sort = function() return ns._FrameSortApply() end,
    }
    if api.Sorting:RegisterFrameProvider(provider) then
        ns._fsRegistered = true
        if api.Options and api.Options.RegisterConfigurationChangedCallback then
            api.Options:RegisterConfigurationChangedCallback(function() ns._FrameSortApply() end)
        end
    end
end

-------------------------------------------------------------------------------
--  Apply sort attributes to all headers. Show Self First (raid) uses the
--  per-group nameList (see the Show Self First banner above); merged mode
--  uses the whole-raid nameList (ns._BuildMergedSelfNameList). Expensive
--  Hide/Show runs only when an attribute actually changed.
-------------------------------------------------------------------------------
local function ApplySortToHeaders()
    if not containerFrame or InCombatLockdown() then return end
    local s = db.profile
    local sortByRole = s.sortMode == "ROLE"
    local roleOrder = s.roleOrder or { "TANK", "HEALER", "DAMAGER" }
    -- A raid set the group state hides takes no nameList (FrameSort, Role +
    -- Class, Self Position): a nameList is also a filter, and the visibility
    -- driver can show the set mid-fight, when no list can be rebuilt, so a stale
    -- list would drop every member it does not name. The shown pass applies them.
    local live = ns._RFVisWanted()
    -- Sort By = FrameSort: its list owns the order (Self Position included);
    -- with FrameSort absent, or no list yet, the Group sort runs (Prioritize
    -- Class and Self Position included).
    local fsRank = live and (s.sortMode == "FRAMESORT") and ns._FrameSortRanks(not ns._fsFromProvider) or nil
    -- Prioritize Class (FrameSort's list wins). Group sort + class runs on the
    -- headers' own CLASS grouping (Class Order, then name), so membership
    -- stays live in combat. A header groups by one key only, so Role + Class
    -- takes nameLists on every header instead: like Self Position's list, a
    -- member who joins mid-fight appears at the regen rebuild.
    local classOn = s.prioritizeClass == true and not fsRank and IsInRaid()
    local classNative = classOn and not sortByRole
    local classLists = live and classOn and sortByRole
    local selfOn = live and (s.showSelfFirst or s.showSelfLast) and IsInRaid()
    local selfLast = s.showSelfLast

    local baseGroupBy, baseSortMethod, baseGroupingOrder
    if classNative then
        baseGroupBy = "CLASS"
        baseSortMethod = "NAME"
        baseGroupingOrder = table.concat(s.classOrder or ns._GetDefaultClassOrder(), ",")
    else
        baseGroupBy = sortByRole and "ASSIGNEDROLE" or nil
        baseSortMethod = sortByRole and "NAME" or "INDEX"
        baseGroupingOrder = sortByRole and (table.concat(roleOrder, ",") .. ",NONE") or ""
    end

    -- gf = desired groupFilter. nameList is only honored when groupFilter is
    -- CLEARED (with one present the engine ignores nameList and uses
    -- roster/index order); the nameList lists every group member, so clearing
    -- groupFilter shows the same members in nameList order.
    local function applySortTo(hdr, gb, sm, go, nl, gf)
        local needsHideShow = (hdr:GetAttribute("groupBy") ~= gb)
            or (hdr:GetAttribute("sortMethod") ~= sm)
            or (hdr:GetAttribute("groupingOrder") ~= go)
            or (hdr:GetAttribute("nameList") ~= nl)
            or (hdr:GetAttribute("groupFilter") ~= gf)
        if needsHideShow then
            ns._fsChanged = true
            -- Hide/Show makes a shown header re-read the set; one LayoutGroups
            -- hid (a hidden or empty group, the idle flat header) stays hidden
            -- and reads it when LayoutGroups shows it.
            local shown = hdr:IsShown()
            if shown then hdr:Hide() end
            hdr:SetAttribute("groupFilter", gf)
            hdr:SetAttribute("groupBy", gb)
            hdr:SetAttribute("sortMethod", sm)
            hdr:SetAttribute("groupingOrder", go)
            hdr:SetAttribute("nameList", nl)
            if shown then hdr:Show() end
        end
    end

    if s.mergeGroups and ns._flatHeader then
        -- Self Position in merged mode: a whole-raid nameList owns the order
        -- (player pinned, rest by the active sort), so groupFilter must be
        -- CLEARED -- the list itself only names visible groups' members --
        -- and groupBy nil so the list order is what the header uses (same
        -- combo as the non-merged player's-group path). While names are
        -- unresolved (builder bailed) the engine path runs instead, with
        -- LayoutGroups' groupFilter restored from ns._flatGfStr. FrameSort
        -- mode and Prioritize Class (Role + Class, or with Self Position) use
        -- the same whole-raid list shape; Group + Class alone runs native.
        local mergedList
        if fsRank then
            mergedList = ns._BuildFrameSortRaidLists(fsRank, true, ns._VisibleGroups())
        end
        if not mergedList and (classLists or (classNative and selfOn)) then
            mergedList = ns._BuildRaidClassLists(true, ns._VisibleGroups(), sortByRole, roleOrder,
                s.classOrder, s.showSelfFirst, selfLast)
        end
        if not mergedList and selfOn then
            mergedList = ns._BuildMergedSelfNameList(sortByRole, roleOrder, selfLast, ns._VisibleGroups())
        end
        if mergedList then
            applySortTo(ns._flatHeader, nil, "NAMELIST", "", mergedList, nil)
        else
            applySortTo(ns._flatHeader, baseGroupBy, baseSortMethod, baseGroupingOrder, nil,
                ns._flatGfStr or ns._flatHeader:GetAttribute("groupFilter"))
        end
    else
        local groupLists
        if fsRank then
            groupLists = ns._BuildFrameSortRaidLists(fsRank, false)
        elseif classLists then
            groupLists = ns._BuildRaidClassLists(false, nil, true, roleOrder,
                s.classOrder, s.showSelfFirst, selfLast)
        end
        -- Self Position: the player's group takes a player-pinned nameList
        -- (Class Order under Group + Class) whenever no per-group list covers
        -- it -- also the fallback while a list builder waits on names.
        local playerGroup = selfOn and ns._GetPlayerSubgroup() or nil
        if playerGroup and groupLists and groupLists[playerGroup] then playerGroup = nil end
        local selfNameList
        if playerGroup then
            if classOn then
                selfNameList = ns._BuildRaidClassLists(false, nil, sortByRole, roleOrder,
                    s.classOrder, s.showSelfFirst, selfLast, playerGroup)
            end
            selfNameList = selfNameList or ns._BuildSelfFirstNameList(playerGroup, sortByRole, roleOrder, selfLast)
            if not selfNameList then playerGroup = nil end
        end
        for group = 1, 8 do
            local hdr = separatedHdrs[group]
            if not hdr then break end
            local groupList = groupLists and groupLists[group]
            if groupList then
                applySortTo(hdr, nil, "NAMELIST", "", groupList, nil)
            elseif playerGroup and group == playerGroup then
                -- Player's group: ordered by nameList -- clear groupFilter, nil
                -- groupBy so the nameList order is what the header uses.
                applySortTo(hdr, nil, "NAMELIST", "", selfNameList, nil)
            else
                applySortTo(hdr, baseGroupBy, baseSortMethod, baseGroupingOrder, nil, tostring(group))
            end
        end
    end
end
ns._ApplySortToHeaders = ApplySortToHeaders

I.ApplySortToHeaders = ApplySortToHeaders
I.broken = false
