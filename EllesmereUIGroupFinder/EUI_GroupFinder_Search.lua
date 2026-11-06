if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_Search.lua: the premade search panel (rows, menus, filters,
-- list tweaks, bottom buttons).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[ADDON_NAME] then return end -- held back (EllesmereUIGroupFinder.lua)
local FOLDER = ADDON_NAME
local CM = EllesmereUI

local DUNGEONS = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
local DELVES   = GROUP_FINDER_CATEGORY_ID_DELVES or 121
local RAIDS    = GROUP_FINDER_CATEGORY_ID_RAIDS or 3
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0
local MEDIA    = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local COG_TEX  = EllesmereUI.COGS_ICON  -- the inline cogs' icon
local X_TEX    = MEDIA .. "eui-close.png"

local ROW1_Y   = -42  -- row 1 centre
local ROW1_H    = 24
local BTN       = 28  -- row 2 square size (layout resizes it)
local DIFF_W    = 110
local SQ_GAP    = 3  -- gap between everything
local ROW2_Y    = ROW1_Y - ROW1_H / 2 - SQ_GAP
local CD_SEARCH = 2
-- bottom buttons sit this far up (blizzard uses 4).
local BOTTOM_Y = 8
local CD_FAILED = 6

local FFD = setmetatable({}, { __mode = "k" })
-- shared helpers (lua 5.1 caps a chunk at 200 locals).
local XF = {}
-- grey for our white glyphs
XF.GLYPH = 0.78
-- dimmed tooltip lines, gold bountiful line
XF.DIM_HEX = CM.HexColor(0.7, 0.7, 0.7)
XF.GOLD_HEX = CM.HexColor(GOLD_R, GOLD_G, GOLD_B)
-- shared empty list (never written)
XF.EMPTY = {}
-- plain tooltip, extra lines dimmed
function XF.Tip(owner, title, ...)
    local text = title
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then
            if line:sub(1, 2) == "|c" then text = text .. "\n" .. line
            else text = text .. "\n" .. XF.DIM_HEX .. line .. "|r" end
        end
    end
    XF.tipOwner = owner
    CM.ShowWidgetTooltip(owner, text)
end
function XF.ClassLine(classFile, text)
    local c = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
    return c and c:WrapTextInColorCode(text) or text
end
function XF.Untip()
    XF.tipOwner = nil
    CM.HideWidgetTooltip()
end
XF.PERSON_ATLAS = "groupfinder-icon-friend"

-- our text in the module's font
function XF.Font(fs, size, flags)
    CM.ApplyModuleFont(fs, nil, size, ADDON_NAME, flags or "")
end

-- blizzard's frames only move out of combat: queued till it ends
function XF.Defer(key, fn)
    ns.CombatQueue.Defer(key, fn)
end

-- click-outside close for our menus
function XF.ClickOff(m, inside)
    m:SetScript("OnEvent", function(self, _, button)
        if button == "LeftButton" and not inside(self) then self:Hide() end
    end)
    m:HookScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    m:HookScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
end

local SP
local row, diffBtn, menu, resetBtn, refreshBtn, gfFont
local pending = false  -- filters changed since the last search
local cdUntil = 0
local squares = {}
local dungeons  -- this season's dungeons
local delves  -- delves category
local delveByActivity  -- activityID -> groupID, tier
local bountiful = {}  -- delve name -> bountiful today
local delveSquares = {}
local tierBtn, tierMenu
local bosses  -- current raid bosses
local raidByActivity  -- activityID -> journal instance
local bossSquares = {}
local raidList  -- current raids, blizzard's order
local raidBtn, raidMenu
local raidDiffMenu

local DIFFS = {
    { key = "difficultyNormal",     label = PLAYER_DIFFICULTY1 or "Normal" },
    { key = "difficultyHeroic",     label = PLAYER_DIFFICULTY2 or "Heroic" },
    { key = "difficultyMythic",     label = PLAYER_DIFFICULTY6 or "Mythic" },
    { key = "difficultyMythicPlus", label = PLAYER_DIFFICULTY_MYTHIC_PLUS or "Mythic+" },
}

local function Cfg() return ns.Cfg() end
local function Accent()
    local a = CM.ELLESMERE_GREEN
    return a.r, a.g, a.b
end
-- the skin's window engine, so our buttons follow its theme
local function Skin()
    local m = CM._ModuleNS.EllesmereUIBlizzardSkin
    return m and m.WSkin
end
local function ThemeBorder()
    local S = Skin()
    local T = S and S.Theme
    if T and T.brdR then return T.brdR, T.brdG, T.brdB, T.brdA end
    return 0.2, 0.2, 0.2, 1
end
ns.Skin, ns.ThemeBorder = Skin, ThemeBorder
ns.BOTTOM_Y = BOTTOM_Y
local function SetBorderColor(frame, r, g, b, a)
    CM.PanelPP.SetBorderColor(frame, r, g, b, a)
end

-------------------------------------------------------------------------------
-- season dungeons and the advanced filter
-------------------------------------------------------------------------------
local function GroupsFor(filter)
    local ok, groups = pcall(C_LFGList.GetAvailableActivityGroups, DUNGEONS, filter)
    return (ok and type(groups) == "table") and groups or {}
end

local function SeasonFilter()
    local F = Enum.LFGListFilter
    return bit.bor(F.CurrentSeason, F.PvE)
end

local function AllDungeonGroups()
    local F = Enum.LFGListFilter
    local all = {}
    for _, g in ipairs(GroupsFor(SeasonFilter())) do all[#all + 1] = g end
    for _, g in ipairs(GroupsFor(bit.bor(F.CurrentExpansion, F.NotCurrentSeason, F.PvE))) do all[#all + 1] = g end
    return all
end

local function BuildDungeons()
    local CMode = C_ChallengeMode
    local maps = CMode and CMode.GetMapTable and CMode.GetMapTable()
    if type(maps) ~= "table" or #maps == 0 then return nil end
    local byMap, byName = {}, {}
    for _, gid in ipairs(GroupsFor(SeasonFilter())) do
        local gname = C_LFGList.GetActivityGroupInfo(gid)
        if gname then byName[gname] = gid end
        for _, aid in ipairs(C_LFGList.GetAvailableActivities(DUNGEONS, gid) or {}) do
            local info = C_LFGList.GetActivityInfoTable(aid)
            if info and info.mapID then byMap[info.mapID] = gid end
        end
    end
    local out = {}
    for _, cmID in ipairs(maps) do
        local name, _, _, tex, _, mapID = CMode.GetMapUIInfo(cmID)
        local gid = (mapID and byMap[mapID]) or (name and byName[name])
        if gid then out[#out + 1] = { cmID = cmID, name = name, icon = tex, groupID = gid } end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return #out > 0 and out or nil
end

-- season dungeons, rebuilt after the m+ maps update
function XF.Dungeons()
    if not dungeons or XF.dungeonsDirty then
        XF.dungeonsDirty = nil
        dungeons = BuildDungeons() or dungeons
    end
    return dungeons
end

local function Contains(list, v)
    for i = 1, #list do if list[i] == v then return i end end
    return nil
end

-- no dungeon restriction: none or all picked
local function DungeonsDefault(f)
    local acts = f.activities or {}
    if #acts == 0 or not dungeons then return true end
    for _, d in ipairs(dungeons) do
        if not Contains(acts, d.groupID) then return false end
    end
    return true
end

local function DiffAllOrNone(f)
    local n = 0
    for _, d in ipairs(DIFFS) do if f[d.key] then n = n + 1 end end
    return n == 0 or n == #DIFFS, n
end

local Paint, PaintRefresh

-- dimmed: blizzard's search goes wide so left out groups come back to dim, the
-- picks stay with us and get checked on our side
local PICK_KEYS = { "activities", "minimumRating", "hasTank", "hasHealer", "needsTank", "needsHealer", "needsDamage",
    "needsMyClass", "difficultyNormal", "difficultyHeroic", "difficultyMythic", "difficultyMythicPlus",
    "generalPlaystyle1", "generalPlaystyle2", "generalPlaystyle3", "generalPlaystyle4" }

local function DimOn() return ns.OwnListGet and ns.OwnListGet("visibility") == "dimmed" end

local function Picks(f)
    local p = {}
    for _, k in ipairs(PICK_KEYS) do p[k] = f[k] end
    return p
end

local function Widen(f)
    f.activities = AllDungeonGroups()
    f.minimumRating = 0
    f.hasTank, f.hasHealer = false, false
    f.needsTank, f.needsHealer, f.needsDamage, f.needsMyClass = false, false, false, false
    for _, d in ipairs(DIFFS) do f[d.key] = true end
    for i = 1, 4 do f["generalPlaystyle" .. i] = true end
end

-- keep this character's picks so another character's don't carry over
function XF.Remember(f)
    if f then ns.SetCharBlizzFilter(Picks(f)) end
end

function XF.GetFilter()
    local f = C_LFGList.GetAdvancedFilter()
    local p = f and DimOn() and Cfg().dimPicks
    if type(p) == "table" then
        for _, k in ipairs(PICK_KEYS) do f[k] = p[k] end
    end
    return f
end

-- filter changes only save, the search waits for search again
local function Apply(f)
    if DimOn() then
        Cfg().dimPicks = Picks(f)
        Widen(f)
    end
    C_LFGList.SaveAdvancedFilter(f)
    XF.Remember(f)
    pending = true
    Paint()
    PaintRefresh()
end

-- once per session: put back this character's picks, or blizzard's defaults the first time
function XF.RestoreCharFilter()
    if XF.filterRestored then return end
    local f = C_LFGList.GetAdvancedFilter()
    if not f then return end
    local saved = ns.CharBlizzFilter()
    if type(saved) == "table" then
        for _, k in ipairs(PICK_KEYS) do f[k] = saved[k] end
    else
        local wide = AllDungeonGroups()
        if #wide == 0 then return end
        Widen(f)
    end
    XF.filterRestored = true
    -- dimmed keeps the picks with us and blizzard's search wide
    local c = Cfg()
    if DimOn() then
        if type(c.dimPicks) ~= "table" then c.dimPicks = Picks(f) end
        Widen(f)
    elseif type(c.dimPicks) == "table" then
        for _, k in ipairs(PICK_KEYS) do f[k] = c.dimPicks[k] end
        c.dimPicks = nil
    end
    C_LFGList.SaveAdvancedFilter(f)
    XF.Remember(f)
end

local function ToggleDungeon(gid)
    local f = XF.GetFilter()
    if DungeonsDefault(f) then
        f.activities = { gid }
    else
        local acts = f.activities
        local at = Contains(acts, gid)
        if at then table.remove(acts, at) else acts[#acts + 1] = gid end
        if #acts == 0 or DungeonsDefault(f) then f.activities = AllDungeonGroups() end
    end
    Apply(f)
end

local function SetDifficulty(key, on)
    local f = XF.GetFilter()
    local _, n = DiffAllOrNone(f)
    if n == 0 then for _, d in ipairs(DIFFS) do f[d.key] = true end end
    if key then f[key] = on else for _, d in ipairs(DIFFS) do f[d.key] = true end end
    local _, after = DiffAllOrNone(f)
    if after == 0 then for _, d in ipairs(DIFFS) do f[d.key] = true end end
    Apply(f)
end

-------------------------------------------------------------------------------
-- region filter (us regions, eu languages)
-------------------------------------------------------------------------------
-- the list comes from EUI_GroupFinder_Regions.lua (us regions, eu languages)
local function Regions() return ns.RegionList() or XF.EMPTY end

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function RegionsAvailable() return ns.RegionList() ~= nil end

local function ChosenRegions()
    local c = Cfg()
    return type(c.regions) == "table" and c.regions or nil
end

local function RegionFilterActive()
    local r = RegionsAvailable() and ChosenRegions()
    if not r then return false end
    local n = 0
    for _, d in ipairs(Regions()) do if r[d.key] then n = n + 1 end end
    return n > 0 and n < #Regions()
end

local function ResultInfo(resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or IsSecret(info) or (canaccesstable and not canaccesstable(info)) then return nil end
    return info
end

function XF.Num(counts, key)
    local v = counts[key]
    return (type(v) == "number" and not IsSecret(v)) and v or nil
end

-- activity info, cached per session
XF.actInfo = {}
function XF.ActInfo(act)
    local ai = XF.actInfo[act]
    if ai == nil then
        ai = C_LFGList.GetActivityInfoTable(act)
        if type(ai) ~= "table" then return nil end
        XF.actInfo[act] = ai
    end
    return ai
end

-- realm -> region, cached
XF.regionByRealm = {}
local function LeaderRegion(info)
    local leader = info and info.leaderName
    if not leader or IsSecret(leader) then return nil end
    local realm = leader:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or IsSecret(realm) then return nil end
    local region = XF.regionByRealm[realm]
    if not region then
        region = ns.RegionOfRealm(realm)
        XF.regionByRealm[realm] = region
    end
    return region
end

-------------------------------------------------------------------------------
-- delves: a square per delve, gold underline for bountiful, tier menu
-------------------------------------------------------------------------------
local SKIP_WORDS = { the = true, of = true, a = true, an = true }

-- up to 3 letters: initials, or a single word's first three (utf-8 safe)
local function Abbrev(name)
    local initials = {}
    for word in (name:gsub("\226\128\153", " ")):gmatch("[^%s%-':]+") do
        if not SKIP_WORDS[word:lower()] then
            initials[#initials + 1] = word
        end
    end
    local firstChar = function(w) return w:match("^[%z\1-\127\194-\244][\128-\191]*") or "" end
    if #initials == 1 then
        local w, out, n = initials[1], {}, 0
        for ch in w:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            n = n + 1
            out[n] = (n == 1) and ch:upper() or ch:lower()
            if n == 3 then break end
        end
        return table.concat(out)
    end
    local out = {}
    for i = 1, math.min(3, #initials) do out[i] = firstChar(initials[i]):upper() end
    return table.concat(out)
end

-- tier from the activity name; '?' is 12 and '??' is 13.
function XF.TierOf(fullName)
    if type(fullName) ~= "string" or IsSecret(fullName) then return nil end
    local n = tonumber(fullName:match("(%d+)%D*$"))
    if n then return n end
    local q = fullName:match("(%?+)[^%?]*$")
    if q == "??" then return 13 elseif q == "?" then return 12 end
    return nil
end
XF.TierLabel = function(t)
    if t == 12 then return EllesmereUI.L("Tier ?") elseif t == 13 then return EllesmereUI.L("Tier ??") end
    return EllesmereUI.Lf("Tier %d", t)
end

local function BuildDelves()
    local F = Enum.LFGListFilter
    local seen, list, byAct = {}, {}, {}
    for _, filter in ipairs({ bit.bor(F.CurrentExpansion, F.PvE), bit.bor(F.CurrentSeason, F.PvE) }) do
        local ok, groups = pcall(C_LFGList.GetAvailableActivityGroups, DELVES, filter)
        for _, gid in ipairs(ok and type(groups) == "table" and groups or {}) do
            if not seen[gid] then
                seen[gid] = true
                local name = C_LFGList.GetActivityGroupInfo(gid)
                if name then
                    list[#list + 1] = { groupID = gid, name = name, abbr = Abbrev(name) }
                    for _, aid in ipairs(C_LFGList.GetAvailableActivities(DELVES, gid) or {}) do
                        local info = C_LFGList.GetActivityInfoTable(aid)
                        local tier = XF.TierOf(info and info.fullName)
                        byAct[aid] = { groupID = gid, tier = tier }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    if #list == 0 then return nil end
    return list, byAct
end

-- Bountiful delves today: check the delve pins for the bountiful art. Only
-- this season's delves count. At most once a minute. The first scan walks
-- every zone under the world map and remembers the zones that hold delves;
-- later scans check only those.
XF.bountifulScanAt = nil
XF.delveZones = nil  -- map IDs of the zones with delve pins
function XF.ScanZone(POI, mapID, season)
    local okPins, pins = pcall(POI.GetDelvesForMap, mapID)
    if not (okPins and type(pins) == "table") then return false end
    for _, poiID in ipairs(pins) do
        local pin = POI.GetAreaPOIInfo(mapID, poiID)
        local name, art = pin and pin.name, pin and pin.atlasName
        if name and season[name] and type(art) == "string" and art:find("bountiful", 1, true) then
            bountiful[name] = true
        end
    end
    return #pins > 0
end
local function ScanBountiful()
    local now = GetTime()
    if XF.bountifulScanAt and now - XF.bountifulScanAt < 60 then return end
    local POI, MAP = C_AreaPoiInfo, C_Map
    if not (POI and POI.GetDelvesForMap and POI.GetAreaPOIInfo and MAP and MAP.GetMapChildrenInfo) then return end
    local season = {}
    for _, d in ipairs(delves or {}) do season[d.name] = true end
    if not next(season) then return end
    XF.bountifulScanAt = now
    wipe(bountiful)
    if XF.delveZones then
        for _, mapID in ipairs(XF.delveZones) do XF.ScanZone(POI, mapID, season) end
        return
    end
    local found = {}
    local okZones, zones = pcall(MAP.GetMapChildrenInfo, 946, Enum.UIMapType.Zone, true)
    for _, zone in ipairs(okZones and type(zones) == "table" and zones or {}) do
        if XF.ScanZone(POI, zone.mapID, season) then found[#found + 1] = zone.mapID end
    end
    if #found > 0 then XF.delveZones = found end
end

local function ChosenDelves()
    local c = Cfg()
    return type(c.delves) == "table" and next(c.delves) and c.delves or nil
end

local MAX_TIER = 13  -- 1-11, then ? and ??

local function ChosenTiers()
    local t = Cfg().delveTiers
    if type(t) ~= "table" then return nil end
    local n = 0
    for i = 1, MAX_TIER do if t[i] then n = n + 1 end end
    return (n > 0 and n < MAX_TIER) and t or nil, n
end

local function DelveFilterActive()
    return SP and SP.categoryID == DELVES and (ChosenDelves() ~= nil or ChosenTiers() ~= nil) or false
end

-- delve / tier filter (unknown activity passes).
local function DelveKeep(info)
    local acts = info and info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local d = act and not IsSecret(act) and delveByActivity and delveByActivity[act]
    if not d then return true end
    local chosen = ChosenDelves()
    if chosen and not chosen[d.groupID] then return false end
    local tiers = ChosenTiers()
    if tiers and d.tier and not tiers[d.tier] then return false end
    return true
end

-------------------------------------------------------------------------------
-- raid bosses: a square per boss with its journal portrait.
-------------------------------------------------------------------------------
local function RaidsCurrent()
    local f = SP and SP.filters
    return SP and SP.categoryID == RAIDS and type(f) == "number"
        and bit.band(f, Enum.LFGListFilter.Recommended) ~= 0 or false
end

-- fallback: newest tier's journal raids by name.
local function JournalRaidsByName()
    local out = {}
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return out end
    local prev = EJ_GetCurrentTier and EJ_GetCurrentTier()
    EJ_SelectTier(EJ_GetNumTiers())
    for i = 1, 20 do
        local jid, name = EJ_GetInstanceByIndex(i, true)
        if not jid then break end
        out[name] = jid
    end
    if prev then EJ_SelectTier(prev) end
    return out
end

local function RaidGroups()
    local F = Enum.LFGListFilter
    local ok, groups = pcall(C_LFGList.GetAvailableActivityGroups, RAIDS, bit.bor(F.Recommended, F.PvE))
    return ok and type(groups) == "table" and groups or {}
end

local function JournalInstance(info, groupName, byName)
    local CEJ = C_EncounterJournal
    local jid = info and info.mapID and CEJ and CEJ.GetInstanceForGameMap and CEJ.GetInstanceForGameMap(info.mapID)
    if jid then return jid end
    return groupName and byName()[groupName] or nil
end

local RAID_DIFFS = { 14, 15, 16, 17 }
local function Encounters(jid)
    local out = {}
    if not (EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then return out end
    local EJ = EncounterJournal
    local prevInst = EJ and EJ.instanceID
    local prevDiff = EJ_GetDifficulty and EJ_GetDifficulty()
    EJ_SelectInstance(jid)
    for _, diff in ipairs(RAID_DIFFS) do
        if EJ_SetDifficulty and EJ_IsValidInstanceDifficulty and EJ_IsValidInstanceDifficulty(diff) then
            EJ_SetDifficulty(diff)
            break
        end
    end
    for i = 1, 30 do
        local name, _, encID = EJ_GetEncounterInfoByIndex(i)
        if not name then break end
        local icon = EJ_GetCreatureInfo and select(5, EJ_GetCreatureInfo(1, encID))
        out[#out + 1] = { key = encID, name = name, icon = icon }
    end
    if prevInst then EJ_SelectInstance(prevInst) end
    if prevDiff and EJ_SetDifficulty then EJ_SetDifficulty(prevDiff) end
    return out
end

-- current raid bosses in blizzard's order, nil till the journal has data
-- this season's raids: the season filter, else the journal's newest tier
function XF.SeasonRaidSets()
    local F = Enum.LFGListFilter
    local groups = {}
    local ok, g = pcall(C_LFGList.GetAvailableActivityGroups, RAIDS, bit.bor(F.CurrentSeason, F.PvE))
    if ok and type(g) == "table" then for _, gid in ipairs(g) do groups[gid] = true end end
    local tier = {}
    if EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex then
        local prev = EJ_GetCurrentTier and EJ_GetCurrentTier()
        EJ_SelectTier(EJ_GetNumTiers())
        for i = 1, 20 do
            local jid = EJ_GetInstanceByIndex(i, true)
            if not jid then break end
            tier[jid] = true
        end
        if prev then EJ_SelectTier(prev) end
    end
    return groups, tier
end

local function BuildBosses()
    if not (EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then return nil end
    local seasonGroups, seasonTier = XF.SeasonRaidSets()
    local byGroup, byTier = {}, {}
    local list, byAct, seen, raids = {}, {}, {}, {}
    local current = {}
    local names
    local function byName() names = names or JournalRaidsByName(); return names end
    for _, gid in ipairs(RaidGroups()) do
        local groupName = C_LFGList.GetActivityGroupInfo(gid)
        for _, aid in ipairs(C_LFGList.GetAvailableActivities(RAIDS, gid) or {}) do
            local info = C_LFGList.GetActivityInfoTable(aid)
            local jid = JournalInstance(info, groupName, byName)
            if jid then
                byAct[aid] = jid
                if info and info.isCurrentRaidActivity then current[jid] = true end
                if seasonGroups[gid] then byGroup[jid] = true end
                if seasonTier[jid] then byTier[jid] = true end
                if not seen[jid] then
                    seen[jid] = true
                    local raidName = EJ_GetInstanceInfo and EJ_GetInstanceInfo(jid)
                    local n = #list
                    for _, b in ipairs(Encounters(jid)) do
                        b.raid, b.raidName = jid, raidName
                        list[#list + 1] = b
                    end
                    if #list > n then raids[#raids + 1] = { jid = jid, name = raidName or groupName or "?" } end
                end
            end
        end
    end
    if #list == 0 then return nil end
    -- none flagged = all count
    wipe(XF.raidCurrent)
    if next(byGroup) then current = byGroup elseif next(byTier) then current = byTier end
    if next(current) then
        for _, raid in ipairs(raids) do XF.raidCurrent[raid.jid] = current[raid.jid] == true end
    end
    return list, byAct, raids
end

-- current season only, older raids are out
XF.raidCurrent = {}
function XF.SeasonOnly() return Cfg().extraSeasonRaids ~= false end
function XF.RaidEligible(jid)
    return not (XF.SeasonOnly() and XF.raidCurrent[jid] == false)
end

-- raids show unless hidden in the raid menu
local function RaidShown(jid)
    if not XF.RaidEligible(jid) then return false end
    local h = Cfg().raidsHidden
    if not (type(h) == "table" and h[jid]) then return true end
    for _, raid in ipairs(raidList or {}) do
        if XF.RaidEligible(raid.jid) and not h[raid.jid] then return false end
    end
    return true
end

function XF.AnyRaidHidden()
    for _, raid in ipairs(raidList or {}) do
        if XF.RaidEligible(raid.jid) and not RaidShown(raid.jid) then return true end
    end
    return false
end

local function ChosenBosses()
    local c = Cfg()
    return type(c.bosses) == "table" and next(c.bosses) and c.bosses or nil
end

local function BossFilterActive()
    return RaidsCurrent() and ChosenBosses() ~= nil or false
end

-- scratch set of a group's killed bosses
XF.dead = {}
local function BossKeep(resultID, info)
    local acts = info and info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local raid = act and not IsSecret(act) and raidByActivity and raidByActivity[act]
    if not raid then return true end
    local done = C_LFGList.GetSearchResultEncounterInfo(resultID)
    if done and (IsSecret(done) or (canaccesstable and not canaccesstable(done))) then return true end
    local dead = wipe(XF.dead)
    for _, name in ipairs(done or XF.EMPTY) do
        if IsSecret(name) then return true end
        dead[name] = true
    end
    -- c.bosses[key]: true = must be alive, "dead" = must be dead
    local chosen, wanted = ChosenBosses(), false
    for _, b in ipairs(bosses or {}) do
        local pick = b.raid == raid and chosen[b.key]
        if pick then
            if (pick == "dead") ~= (dead[b.name] == true) then return false end
            wanted = true
        end
    end
    return wanted
end

-------------------------------------------------------------------------------
-- raids: difficulty and world bosses
-------------------------------------------------------------------------------
local RAID_DIFFS_MENU = {
    { key = "normal", label = PLAYER_DIFFICULTY1 or "Normal" },
    { key = "heroic", label = PLAYER_DIFFICULTY2 or "Heroic" },
    { key = "mythic", label = PLAYER_DIFFICULTY6 or "Mythic" },
}

local function ChosenRaidDiffs()
    local t = Cfg().raidDiffs
    if type(t) ~= "table" then return nil, 0 end
    local n = 0
    for _, d in ipairs(RAID_DIFFS_MENU) do if t[d.key] then n = n + 1 end end
    return (n > 0 and n < #RAID_DIFFS_MENU) and t or nil, n
end

local function HideWorldBosses() return Cfg().hideWorldBosses == true end

-- playstyles (generalPlaystyle 1-4).
local PLAYSTYLES = {
    GROUP_FINDER_GENERAL_PLAYSTYLE1 or "Learning",
    GROUP_FINDER_GENERAL_PLAYSTYLE2 or "Relaxed",
    GROUP_FINDER_GENERAL_PLAYSTYLE3 or "Competitive",
    GROUP_FINDER_GENERAL_PLAYSTYLE4 or "Carry Offered",
}

local function ChosenRaidPlaystyles()
    local t = Cfg().raidPlaystyles
    if type(t) ~= "table" then return nil, 0 end
    local n = 0
    for i = 1, #PLAYSTYLES do if t[i] then n = n + 1 end end
    return (n > 0 and n < #PLAYSTYLES) and t or nil, n
end

-- dungeon playstyles from the advanced filter; nil when all or none.
local function DungeonPlaystyles(f)
    local n = 0
    for i = 1, #PLAYSTYLES do if f["generalPlaystyle" .. i] then n = n + 1 end end
    return (n > 0 and n < #PLAYSTYLES) and f or nil, n
end

-- roles (the advanced filter's needs* keys).
local ROLES = {
    { key = "needsTank",   label = EllesmereUI.L("Tank Available") },
    { key = "needsHealer", label = EllesmereUI.L("Healer Available") },
    { key = "needsDamage", label = EllesmereUI.L("Damage Available") },
}

local function ChosenRaidRoles()
    local t = Cfg().raidRoles
    return type(t) == "table" and next(t) and t or nil
end

local function DungeonRolesSet(f)
    for _, r in ipairs(ROLES) do if f[r.key] then return true end end
    return (f.needsMyClass or f.hasTank or f.hasHealer) and true or false
end

local function RaidListFilterActive()
    return SP and SP.categoryID == RAIDS
        and (ChosenRaidDiffs() ~= nil or HideWorldBosses() or ChosenRaidPlaystyles() ~= nil or ChosenRaidRoles() ~= nil
            or XF.AnyRaidHidden()) or false
end

-- difficultyID first since the is*activity flags aren't reliable on raids.
local RAID_DIFF_BY_ID = { [14] = "normal", [15] = "heroic", [16] = "mythic", [3] = "normal", [4] = "normal", [5] = "heroic", [6] = "heroic", [9] = "normal" }
XF.DIFF_WORDS = { mythic = PLAYER_DIFFICULTY6 or "Mythic", heroic = PLAYER_DIFFICULTY2 or "Heroic", normal = PLAYER_DIFFICULTY1 or "Normal" }
local function ActivityDiffKey(ai)
    local byID = RAID_DIFF_BY_ID[ai.difficultyID] or RAID_DIFF_BY_ID[ai.redirectedDifficultyID]
    if byID then return byID end
    if ai.isMythicActivity then return "mythic" end
    if ai.isHeroicActivity then return "heroic" end
    if ai.isNormalActivity then return "normal" end
    -- last resort: the difficulty word in the name.
    local name = ai.fullName
    if type(name) == "string" and not IsSecret(name) then
        for key, word in pairs(XF.DIFF_WORDS) do
            if name:find(word, 1, true) then return key end
        end
    end
    return nil
end

local function IsWorldBoss(ai)
    local g = ai and ai.groupFinderActivityGroupID
    return ai and ai.categoryID == RAIDS and (g == nil or g == 0) or false
end

local function RaidListKeep(resultID, info)
    local acts = info and info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local ai = act and not IsSecret(act) and XF.ActInfo(act)
    if not ai then return true end
    if HideWorldBosses() and IsWorldBoss(ai) then return false end
    local jid = raidByActivity and raidByActivity[act]
    if jid and not RaidShown(jid) then return false end
    local diffs = ChosenRaidDiffs()
    local key = diffs and ActivityDiffKey(ai)
    if key and not diffs[key] then return false end
    local styles = ChosenRaidPlaystyles()
    local ps = styles and info.generalPlaystyle
    if type(ps) == "number" and not IsSecret(ps) and ps >= 1 and ps <= #PLAYSTYLES and not styles[ps] then return false end
    local roles = ChosenRaidRoles()
    if roles then
        local c = C_LFGList.GetSearchResultMemberCounts(resultID)
        if type(c) == "table" and not IsSecret(c) then
            local num = XF.Num
            -- match any role
            if ns.ExtraRolesAny and ns.ExtraRolesAny() then
                return (roles.needsTank and (num(c, "TANK_REMAINING") or 1) > 0)
                    or (roles.needsHealer and (num(c, "HEALER_REMAINING") or 1) > 0)
                    or (roles.needsDamage and (num(c, "DAMAGER_REMAINING") or 1) > 0) or false
            end
            if roles.needsTank and (num(c, "TANK_REMAINING") or 1) <= 0 then return false end
            if roles.needsHealer and (num(c, "HEALER_REMAINING") or 1) <= 0 then return false end
            if roles.needsDamage and (num(c, "DAMAGER_REMAINING") or 1) <= 0 then return false end
        end
    end
    return true
end

-------------------------------------------------------------------------------
-- extra filters (filters menu, client side)
-------------------------------------------------------------------------------
XF.LUST_CLASSES = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
XF.BREZ_CLASSES = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }
XF.COUNT_ROLES = {
    { key = "TANK",    label = EllesmereUI.L("Tanks") },
    { key = "HEALER",  label = EllesmereUI.L("Healers") },
    { key = "DAMAGER", label = EllesmereUI.L("DPS") },
}
XF.COUNT_OPS = {
    { key = "lt", label = "<  " .. EllesmereUI.L("Less Than") },
    { key = "gt", label = ">  " .. EllesmereUI.L("More Than") },
    { key = "eq", label = "=  " .. EllesmereUI.L("Equal To") },
}
XF.COUNT_OP_LABEL = { lt = "<", gt = ">", eq = "=" }
-- member-count keys for the open slots of each role.
XF.REMAINING = { TANK = "TANK_REMAINING", HEALER = "HEALER_REMAINING", DAMAGER = "DAMAGER_REMAINING" }
XF.PARTY = { "party1", "party2", "party3", "party4" }

function XF.CountRule(role)
    local t = Cfg().roleCounts
    local r = type(t) == "table" and t[role]
    local n = type(r) == "table" and r.on and tonumber(r.n)
    if n then return r.op or "lt", n end
    return nil
end

function XF.ExtraFilterActive()
    if not SP or (SP.categoryID ~= DUNGEONS and SP.categoryID ~= RAIDS) then return false end
    local c = Cfg()
    if c.partyFit or c.notDeclined or c.hasLust or c.hasBrez then return true end
    if ns.ExtraClassKeep and c.extraMyClass then return true end
    if ns.ExtraExprActive and ns.ExtraExprActive() then return true end
    for _, r in ipairs(XF.COUNT_ROLES) do if XF.CountRule(r.key) then return true end end
    return false
end

-- info: the result's readable info, or false when it has none.
function XF.IsDeclinedResult(id, info)
    local _, status = C_LFGList.GetApplicationInfo(id)
    if IsSecret(status) then return false end
    if status == "declined" or status == "declined_full" or status == "declined_delisted" then return true end
    local guid = info and info.partyGUID
    local declines = LFGListFrame and LFGListFrame.declines
    return (declines and guid and not IsSecret(guid) and declines[guid]) and true or false
end

-- your party's roles, nil while one reads secret
function XF.PartyNeeds(need)
    need.TANK, need.HEALER, need.DAMAGER = 0, 0, 0
    local members = IsInRaid() and 0 or GetNumSubgroupMembers()
    for i = 0, math.min(members, #XF.PARTY) do
        local role, secret = CM.UnitEffectiveRole(i == 0 and "player" or XF.PARTY[i])
        if secret then return nil end
        if role == "TANK" or role == "HEALER" then need[role] = need[role] + 1 else need.DAMAGER = need.DAMAGER + 1 end
    end
    return need
end

function XF.ExtraKeep(id, info, need)
    local c = Cfg()
    if c.notDeclined and XF.IsDeclinedResult(id, info) then return false end
    local counts = C_LFGList.GetSearchResultMemberCounts(id)
    if type(counts) == "table" and not IsSecret(counts) then
        local num = XF.Num
        if c.partyFit and need then
            for role, n in pairs(need) do
                local left = num(counts, XF.REMAINING[role])
                if left and left < n then return false end
            end
        end
        -- match any role
        local any = ns.ExtraRolesAny and ns.ExtraRolesAny()
        local anySet, anyHit = false, false
        for _, r in ipairs(XF.COUNT_ROLES) do
            local op, n = XF.CountRule(r.key)
            local have = op and num(counts, r.key)
            if have then
                local ok = (op == "lt" and have < n) or (op == "gt" and have > n) or (op == "eq" and have == n)
                if any then
                    anySet, anyHit = true, anyHit or ok
                elseif not ok then
                    return false
                end
            end
        end
        if anySet and not anyHit then return false end
    end
    -- the expressions box
    if ns.ExtraExprKeep and not ns.ExtraExprKeep(id, info) then return false end
    -- has / missing bloodlust, battle res and your class
    if ns.ExtraClassKeep then
        if not ns.ExtraClassKeep(id, info, c) then return false end
    elseif c.hasLust or c.hasBrez then
        local n = info and info.numMembers
        if type(n) == "number" and not IsSecret(n) then
            local lust, brez = false, false
            for i = 1, n do
                local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
                local cls = p and p.classFilename
                if cls and not IsSecret(cls) then
                    if XF.LUST_CLASSES[cls] then lust = true end
                    if XF.BREZ_CLASSES[cls] then brez = true end
                end
            end
            if c.hasLust and not lust then return false end
            if c.hasBrez and not brez then return false end
        end
    end
    return true
end

-- results are secret in restricted content: filters stay out of it.
function XF.ResultsSecret()
    local res = SP and SP.results
    local first = type(res) == "table" and res[1]
    if not first then return false end
    if IsSecret(first) then return true end
    local info = C_LFGList.GetSearchResultInfo(first)
    if not info then return false end
    if IsSecret(info) or (canaccesstable and not canaccesstable(info)) then return true end
    return IsSecret(info.activityIDs) and true or false
end

-- one pass shares secrecy, active filters and party fit's needs (once per frame)
XF.pass = { needT = { TANK = 0, HEALER = 0, DAMAGER = 0 } }
function XF.Pass()
    local P = XF.pass
    local now = GetTime()
    local res = SP and SP.results
    if P.at == now and P.res == res then return P end
    P.at, P.res = now, res
    P.secret = XF.ResultsSecret()
    P.regions = RegionFilterActive()
    P.delveOn = DelveFilterActive()
    P.bossOn = BossFilterActive()
    P.raidOn = RaidListFilterActive()
    P.extraOn = XF.ExtraFilterActive()
    P.dimOn = XF.DimActive()
    P.any = P.regions or P.delveOn or P.bossOn or P.raidOn or P.extraOn or P.dimOn
    P.need = (P.extraOn and Cfg().partyFit) and XF.PartyNeeds(P.needT) or nil
    return P
end
function XF.NewPass() XF.pass.at = nil end

-- any picks waiting on our side?
function XF.DimActive()
    local p = SP and SP.categoryID == DUNGEONS and DimOn() and Cfg().dimPicks
    if type(p) ~= "table" then return false end
    return (not DungeonsDefault(p) or not DiffAllOrNone(p) or DungeonPlaystyles(p) or DungeonRolesSet(p)
        or (tonumber(p.minimumRating) or 0) > 0) and true or false
end

-- blizzard's search would have done this if it wasn't wide
function XF.DimKeep(id, info)
    local p = Cfg().dimPicks
    if not info then return true end
    local acts = info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local ai = act and not IsSecret(act) and C_LFGList.GetActivityInfoTable(act)
    if ai and not IsSecret(ai) then
        local gid = ai.groupFinderActivityGroupID
        if not DungeonsDefault(p) and not IsSecret(gid) and not Contains(p.activities, gid) then return false end
        if not DiffAllOrNone(p) then
            local key = ActivityDiffKey(ai)
            if ai.isMythicPlusActivity then key = "difficultyMythicPlus"
            elseif key then key = "difficulty" .. key:sub(1, 1):upper() .. key:sub(2) end
            if key and not p[key] then return false end
        end
    end
    local min = tonumber(p.minimumRating) or 0
    local score = info.leaderOverallDungeonScore
    if min > 0 and not IsSecret(score) and type(score) == "number" and score < min then return false end
    local ps = info.generalPlaystyle
    if DungeonPlaystyles(p) and not IsSecret(ps) and type(ps) == "number" and ps > 0 and not p["generalPlaystyle" .. ps] then
        return false
    end
    if DungeonRolesSet(p) then
        local counts = C_LFGList.GetSearchResultMemberCounts(id)
        if type(counts) == "table" and not IsSecret(counts) then
            local num = XF.Num
            if p.hasTank and (num(counts, "TANK") or 1) < 1 then return false end
            if p.hasHealer and (num(counts, "HEALER") or 1) < 1 then return false end
            if p.needsTank and (num(counts, "TANK_REMAINING") or 1) < 1 then return false end
            if p.needsHealer and (num(counts, "HEALER_REMAINING") or 1) < 1 then return false end
            if p.needsDamage and (num(counts, "DAMAGER_REMAINING") or 1) < 1 then return false end
        end
        if p.needsMyClass then
            local _, mine = UnitClass("player")
            local n = info.numMembers
            for i = 1, (type(n) == "number" and not IsSecret(n)) and n or 0 do
                local m = C_LFGList.GetSearchResultPlayerInfo(id, i)
                local cls = m and m.classFilename
                if cls and not IsSecret(cls) and cls == mine then return false end
            end
        end
    end
    return true
end

-- visibility switched: move the picks to where they now belong
function ns.DimFiltersChanged()
    if not SP then return end
    local f = C_LFGList.GetAdvancedFilter()
    if not f then return end
    local c = Cfg()
    if DimOn() then
        c.dimPicks = Picks(f)
        Widen(f)
    else
        local p = c.dimPicks
        if type(p) == "table" then
            for _, k in ipairs(PICK_KEYS) do f[k] = p[k] end
        end
        c.dimPicks = nil
    end
    C_LFGList.SaveAdvancedFilter(f)
    XF.Remember(f)
    pending = true
    Paint()
    PaintRefresh()
end

-- does a group pass the client-side filters? info: readable info, false if none,
-- nil to fetch it
function XF.PassesFilters(id, info)
    local P = XF.Pass()
    if not SP or P.secret or not P.any then return true end
    local c = Cfg()
    local _, appStatus = C_LFGList.GetApplicationInfo(id)
    if IsSecret(appStatus) then return true end
    if info == nil then info = ResultInfo(id) or false end
    if appStatus and appStatus ~= "none" then
        -- applied groups stay lit, unless declined with not declined on.
        return not (P.extraOn and c.notDeclined and XF.IsDeclinedResult(id, info))
    end
    if P.dimOn and not XF.DimKeep(id, info) then return false end
    if P.regions then
        local region = LeaderRegion(info)
        if region ~= nil and not ChosenRegions()[region] then return false end
    end
    if P.delveOn and not DelveKeep(info) then return false end
    if P.bossOn and not BossKeep(id, info) then return false end
    if P.raidOn and not RaidListKeep(id, info) then return false end
    if P.extraOn and not XF.ExtraKeep(id, info, P.need) then return false end
    return true
end

-- read-only filter checks for our results list
ns.ExtraPasses = function(id) return XF.PassesFilters(id) end
ns.ExtraResultsSecret = function() return XF.ResultsSecret() end

-- filters changed: re-fade the visible rows, no search.
function XF.RefilterEntry(entry)
    local id = entry.resultID
    if id then entry:SetAlpha(XF.PassesFilters(id) and 1 or XF.DIM_ALPHA) end
end
local function Refilter()
    XF.NewPass()
    if ns.ExtraRefilter then ns.ExtraRefilter() end  -- our results list
    if not (SP and SP:IsVisible()) then return end
    local box = SP.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(XF.RefilterEntry) end
end

-------------------------------------------------------------------------------
-- result rows and tooltip
-------------------------------------------------------------------------------
local function Opt(key)
    local v = Cfg()[key]
    if v == nil then return true end
    return v and true or false
end

local seenResults, prevResults = {}, nil  -- latest / previous search's result IDs
local prevCategory

-- spec icons by class + spec name (the search API only gives names).
local specIcon, specIconAny
local function SpecIcon(classFile, specName)
    if not specName then return nil end
    if not specIcon then
        specIcon, specIconAny = {}, {}
        for c = 1, (GetNumClasses and GetNumClasses() or 0) do
            local _, file, classID = GetClassInfo(c)
            if file and classID then
                specIcon[file] = {}
                for sx = 1, 5 do
                    local id, name, _, icon = GetSpecializationInfoForClassID(classID, sx)
                    if not id then break end
                    if name then
                        specIcon[file][name] = icon
                        specIconAny[name] = specIconAny[name] or icon
                    end
                end
            end
        end
    end
    return (specIcon[classFile] and specIcon[classFile][specName]) or specIconAny[specName]
end

-- locked to this activity's instance and difficulty?
local function LockedOut(ai, resultID)
    if not (ai and ai.mapID and GetNumSavedInstances) then return false end
    for i = 1, GetNumSavedInstances() do
        local _, _, _, diffID, locked, _, _, _, _, _, numBosses, _, _, instanceID = GetSavedInstanceInfo(i)
        if locked and instanceID == ai.mapID and diffID == ai.difficultyID then
            local perBoss = (ai.maxNumPlayers or 5) > 5 and diffID ~= 16
            if not perBoss then return true end
            if not (GetSavedInstanceEncounterInfo and resultID) then return false end
            local done = C_LFGList.GetSearchResultEncounterInfo(resultID)
            if done and (IsSecret(done) or (canaccesstable and not canaccesstable(done))) then return false end
            local dead = wipe(XF.dead)
            for _, name in ipairs(done or XF.EMPTY) do
                if IsSecret(name) then return false end
                dead[name] = true
            end
            local anyAlive = false
            for j = 1, (tonumber(numBosses) or 0) do
                local boss, _, killed = GetSavedInstanceEncounterInfo(i, j)
                if boss and not dead[boss] then
                    anyAlive = true
                    if not killed then return false end
                end
            end
            return anyAlive
        end
    end
    return false
end

-- raider.io's api, looked up once (each global read logs a taint line)
local rioApi
local function RatingColor(score)
    if rioApi == nil then rioApi = _G.RaiderIO or false end
    if Opt("rioRatingColors") and rioApi and rioApi.GetScoreColor then
        local ok, r, g, b = pcall(rioApi.GetScoreColor, score)
        if ok and type(r) == "number" then return r, g, b end
    end
    local c = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local ROLE_BY_ATLAS
local function AtlasRole(atlas)
    if not ROLE_BY_ATLAS then
        ROLE_BY_ATLAS = {
            ["groupfinder-icon-role-micro-tank"] = "TANK",
            ["groupfinder-icon-role-micro-heal"] = "HEALER",
            ["groupfinder-icon-role-micro-dps"] = "DAMAGER",
        }
        for role, a in pairs(LFG_LIST_GROUP_DATA_ATLASES or {}) do
            if role == "TANK" or role == "HEALER" or role == "DAMAGER" then ROLE_BY_ATLAS[a] = role end
        end
    end
    return atlas and ROLE_BY_ATLAS[atlas]
end
local MISSING_ATLAS = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal", DAMAGER = "groupfinder-icon-role-micro-dps" }

-- our own drawing over one of blizzard's role icons.
local function IconLayer(icon)
    local d = FFD[icon]
    if d then return d end
    d = {}
    FFD[icon] = d
    local f = CreateFrame("Frame", nil, icon)
    f:SetAllPoints(icon)
    f:SetFrameLevel(icon:GetFrameLevel() + 2)
    f:EnableMouse(false)
    d.frame = f
    d.circle = f:CreateTexture(nil, "ARTWORK", nil, 1)
    d.circle:SetSize(16, 16)
    d.circle:SetPoint("CENTER")
    d.ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
    d.ring:SetSize(18, 18)
    d.ring:SetPoint("CENTER")
    d.spec = f:CreateTexture(nil, "ARTWORK", nil, 2)
    d.spec:SetSize(16, 16)
    d.spec:SetPoint("CENTER")
    d.spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- past the icon art's own border
    for _, tex in ipairs({ d.ring, d.spec }) do
        local mask = f.CreateMaskTexture and f:CreateMaskTexture()
        if mask then
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(tex)
            tex:AddMaskTexture(mask)
        end
    end
    d.role = f:CreateTexture(nil, "ARTWORK", nil, 3)
    d.role:SetSize(12, 12)
    d.role:SetPoint("CENTER")
    d.full = f:CreateTexture(nil, "ARTWORK", nil, 1)
    d.full:SetAllPoints(f)
    d.crown = f:CreateTexture(nil, "OVERLAY")
    d.crown:SetAtlas("groupfinder-icon-leader", false)
    d.crown:SetSize(10, 6)
    d.crown:SetPoint("BOTTOM", icon, "TOP", 0, 1)
    -- blizzard's leaver mark is under our layer, so it's drawn again up here
    d.leaver = f:CreateTexture(nil, "OVERLAY", nil, 1)
    d.leaver:SetAtlas("groupfinder-icon-leaver", false)
    d.leaver:SetSize(12, 12)
    d.leaver:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 4, 2)
    return d
end

local function ClearLayer(d)
    d.circle:Hide(); d.ring:Hide(); d.spec:Hide(); d.role:Hide(); d.full:Hide(); d.crown:Hide(); d.leaver:Hide()
end

-- clear our layers on rows we skip (recycled rows keep old art)
function XF.ClearIcons(entry)
    local enum = entry.DataDisplay and entry.DataDisplay.Enumerate
    local icons = enum and enum.Icons
    if not icons then return end
    for i = 1, #icons do
        local d = FFD[icons[i]]
        if d then ClearLayer(d) end
    end
end

XF.members, XF.used, XF.missing = {}, {}, {}
XF.ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }
XF.ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
XF.FIVE_SLOTS = { TANK = 1, HEALER = 1, DAMAGER = 3 }  -- a 5-player group's roles
function XF.ByOrder(x, y) return x._cmOrder < y._cmOrder end

local function DecorateIcons(entry, resultID, info, ai)
    local enum = entry.DataDisplay and entry.DataDisplay.Enumerate
    local icons = enum and enum.Icons
    if not icons then return end
    local shown = enum:IsShown()
    -- none = no missing roles
    local crownOn, specOn = Opt("leaderCrown"), Opt("specIcons")
    local missOn = not (ns.OwnListGet and ns.OwnListGet("missingIcons") == "none")
    local disabled = (not IsSecret(info.isDelisted) and info.isDelisted) and true or false
    -- sort like blizzard fills its icons
    local members = wipe(XF.members)
    local n = info.numMembers
    if shown and (crownOn or specOn) and type(n) == "number" and not IsSecret(n) then
        for i = 1, n do
            local p = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
            if p and not IsSecret(p.classFilename) and not IsSecret(p.assignedRole) then
                members[#members + 1] = p
            end
        end
        for k, p in ipairs(members) do p._cmOrder = (XF.ROLE_RANK[p.assignedRole] or 4) * 100 + k end
        table.sort(members, XF.ByOrder)
    end
    local maxN = ai and ai.maxNumPlayers or 0
    local counts = shown and missOn and maxN == 5 and C_LFGList.GetSearchResultMemberCounts(resultID)
    local missing
    if type(counts) == "table" and not IsSecret(counts) then
        missing = wipe(XF.missing)
        for _, role in ipairs(XF.ROLE_ORDER) do
            local have = counts[role]
            if IsSecret(have) then missing = nil; break end
            for _ = 1, math.max(0, XF.FIVE_SLOTS[role] - (tonumber(have) or 0)) do missing[#missing + 1] = role end
        end
    end
    local used, mi = wipe(XF.used), 0
    -- right to left like blizzard; empty slots end up leftmost.
    for i = #icons, 1, -1 do
        local icon = icons[i]
        local d = IconLayer(icon)
        ClearLayer(d)
        local live = shown and icon:IsShown()
        local cc, ri, bg = icon.ClassCircle, icon.RoleIcon, icon.RoleIconWithBackground
        local ccAtlas = live and cc and cc:IsShown() and cc:GetAtlas()
        local riAtlas = live and ri and ri:IsShown() and ri:GetAtlas()
        local bgAtlas = live and bg and bg:IsShown() and bg:GetAtlas()
        if live and (IsSecret(ccAtlas) or IsSecret(riAtlas) or IsSecret(bgAtlas)) then
            -- restricted row: its art reads secret, blizzard's stays
            local a = disabled and 0.5 or 1
            if cc then cc:SetAlpha(a) end
            if ri then ri:SetAlpha(a) end
            if bg then bg:SetAlpha(a) end
        elseif live then
            if bgAtlas == "groupfinder-icon-emptyslot" then
                if cc then cc:SetAlpha(0) end
                if ri then ri:SetAlpha(0) end
                if bg then bg:SetAlpha(0) end
                mi = mi + 1
                local role = missing and missing[mi]
                if role then
                    d.role:SetAtlas(MISSING_ATLAS[role], false)
                    d.role:SetDesaturated(true)
                    d.role:SetAlpha(0.6)
                    d.role:Show()
                else
                    d.full:SetAtlas(bgAtlas, false)
                    d.full:SetDesaturated(disabled)
                    d.full:SetAlpha(disabled and 0.5 or 1)
                    d.full:Show()
                end
            else
                local role, class
                if ccAtlas then
                    class = ccAtlas:match("^groupfinder%-icon%-class%-color%-(.+)$")
                    role = AtlasRole(riAtlas)
                else
                    role = AtlasRole(bgAtlas)
                end
                -- match role + class, then role, then whoever's next.
                local m
                for pass = 1, 3 do
                    for k, p in ipairs(members) do
                        if not used[k] and (pass == 3 or (p.assignedRole == role
                            and (pass == 2 or not class or p.classFilename == class))) then
                            used[k] = true
                            m = p
                            break
                        end
                    end
                    if m then break end
                end
                if not specOn then
                    -- spec icons off: the game's icons stay, only the crown is ours
                    local a = disabled and 0.5 or 1
                    if cc then cc:SetAlpha(a) end
                    if ri then ri:SetAlpha(a) end
                    if bg then bg:SetAlpha(a) end
                else
                    if cc then cc:SetAlpha(0) end
                    if ri then ri:SetAlpha(0) end
                    if bg then bg:SetAlpha(0) end
                    local spec = m and m.specName and not IsSecret(m.specName) and SpecIcon(m.classFilename, m.specName)
                    if ccAtlas then
                        d.circle:SetAtlas(ccAtlas, false)
                        d.circle:SetDesaturated(disabled)
                        d.circle:SetAlpha(disabled and 0.5 or 1)
                        d.circle:Show()
                        if spec then
                            d.circle:Hide()
                            local r, g, b = ThemeBorder()
                            d.ring:SetColorTexture(r, g, b, disabled and 0.5 or 1)
                            d.ring:Show()
                            d.spec:SetTexture(spec)
                            d.spec:SetDesaturated(disabled)
                            d.spec:SetAlpha(disabled and 0.5 or 1)
                            d.spec:Show()
                        elseif riAtlas then
                            d.role:SetAtlas(riAtlas, false)
                            d.role:SetDesaturated(disabled)
                            d.role:SetAlpha(disabled and 0.5 or 1)
                            d.role:Show()
                        end
                    elseif bgAtlas then
                        if spec then
                            d.circle:Hide()
                            local r, g, b = ThemeBorder()
                            d.ring:SetColorTexture(r, g, b, disabled and 0.5 or 1)
                            d.ring:Show()
                            d.spec:SetTexture(spec)
                            d.spec:SetDesaturated(disabled)
                            d.spec:SetAlpha(disabled and 0.5 or 1)
                            d.spec:Show()
                        else
                            d.full:SetAtlas(bgAtlas, false)
                            d.full:SetDesaturated(disabled)
                            d.full:SetAlpha(disabled and 0.5 or 1)
                            d.full:Show()
                        end
                    end
                    local lv = icon.LeaverIcon
                    local leaver = lv and lv:IsShown()
                    if not IsSecret(leaver) and leaver then
                        d.leaver:SetDesaturated(disabled)
                        d.leaver:SetAlpha(disabled and 0.5 or 1)
                        d.leaver:Show()
                    end
                end
                if m and crownOn and not IsSecret(m.isLeader) and m.isLeader then
                    d.crown:SetDesaturated(disabled)
                    d.crown:Show()
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- cancel oldest application
-------------------------------------------------------------------------------
-- the pending application closest to timing out.
function XF.OldestApplication()
    local oldest, left = nil, math.huge
    for _, id in ipairs(C_LFGList.GetApplications() or {}) do
        local _, status, pendingStatus, duration = C_LFGList.GetApplicationInfo(id)
        if status == "applied" and not pendingStatus and type(duration) == "number" and duration < left then
            oldest, left = id, duration
        end
    end
    return oldest
end

-- at the limit and hovering a group you could sign up to.
function XF.ShouldCancelOldest(resultID)
    if not Cfg().cancelOldest or not resultID or XF.ResultsSecret() then return false end
    local _, active = C_LFGList.GetNumApplications()
    if type(active) ~= "number" or active < (MAX_LFG_LIST_APPLICATIONS or 5) then return false end
    local _, status, pendingStatus = C_LFGList.GetApplicationInfo(resultID)
    if status ~= "none" or pendingStatus then return false end
    local info = ResultInfo(resultID)
    return info ~= nil and not IsSecret(info.isDelisted) and not info.isDelisted
end

-- same for our rows
function ns.GFCancelOldest(resultID)
    if not XF.ShouldCancelOldest(resultID) then return end
    local oldest = XF.OldestApplication()
    if oldest then C_LFGList.CancelApplication(oldest) end
end

-- rows decorate only while the panel shows
local function DecorateEntry(entry)
    local resultID = entry and entry.resultID
    if not resultID or not SP or not SP:IsVisible() then return end
    local fd = FFD[entry]
    if not fd then
        fd = {}
        FFD[entry] = fd
        local f = CreateFrame("Frame", nil, entry)
        f:SetAllPoints(entry)
        f:SetFrameLevel(entry:GetFrameLevel() + 3)
        f:EnableMouse(false)
        fd.rating = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fd.rating:SetJustifyH("RIGHT")
        entry:HookScript("OnClick", function(self, button)
            if button ~= "LeftButton" or not XF.ShouldCancelOldest(self.resultID) then return end
            local oldest = XF.OldestApplication()
            if oldest then C_LFGList.CancelApplication(oldest) end
        end)
    end
    fd.rating:Hide()
    entry:SetAlpha(1)
    XF.CancelLook(entry)
    -- secret results: leave the row alone.
    if XF.Pass().secret then XF.ClearIcons(entry) return end
    local info = ResultInfo(resultID)
    -- filtered out: faded
    if not XF.PassesFilters(resultID, info or false) then entry:SetAlpha(XF.DIM_ALPHA) end
    if not info then XF.ClearIcons(entry) return end
    local acts = info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local ai = act and not IsSecret(act) and XF.ActInfo(act)

    -- name colour (blizzard already reds declined ones).
    local delisted, censored = info.isDelisted, info.censored
    if IsSecret(delisted) or IsSecret(censored) then XF.ClearIcons(entry) return end
    if Opt("nameColors") and entry.Name and not delisted and not censored then
        local _, appStatus = C_LFGList.GetApplicationInfo(resultID)
        local declined = appStatus == "declined" or appStatus == "declined_full" or appStatus == "declined_delisted"
        if declined or LockedOut(ai, resultID) then
            entry.Name:SetTextColor(1, 0.25, 0.25)
        elseif prevResults and not prevResults[resultID] and (appStatus == "none" or appStatus == nil) then
            entry.Name:SetTextColor(0.3, 1, 0.3)
        end
    end

    local enum = entry.DataDisplay and entry.DataDisplay.Enumerate
    local score = info.leaderOverallDungeonScore
    if Opt("leaderRating") and enum and enum:IsShown() and entry.DataDisplay:IsShown()
        and type(score) == "number" and not IsSecret(score) and score > 0 then
        local n = ai and ai.maxNumPlayers or 5
        local left = enum.Icons and enum.Icons[math.min(n, #enum.Icons)]
        if left then
            fd.rating:ClearAllPoints()
            fd.rating:SetPoint("RIGHT", left, "LEFT", -4, 0)
            fd.rating:SetFormattedText("%d", math.floor(score))
            fd.rating:SetTextColor(RatingColor(score))
            fd.rating:Show()
        end
    end

    -- scale the icon strip and trim names to fit (out of combat only)
    local scale = math.max(1, math.min(2, (tonumber(Cfg().iconSize) or 125) / 100))
    if enum and enum.SetScale and InCombatLockdown() then
        XF.Defer("rows", XF.Redecorate)
    elseif enum and enum.SetScale then
        enum:SetScale(scale)
        local extra = math.floor((scale - 1) * 102 + 0.5)  -- 5 icons 18 apart + 12 gap
        if extra > 0 then
            local actName = entry.ActivityName
            if actName then actName:SetWidth(176 - extra) end
            local name = entry.Name
            if name and not censored then
                local ok, w = pcall(name.GetWidth, name)
                local cap = (entry.isApplication and 165 or 176) - extra
                if ok and type(w) == "number" and not IsSecret(w) and w > cap then name:SetWidth(cap) end
            end
        end
    end

    DecorateIcons(entry, resultID, info, ai)
end

-- our rows use the same settings
ns.GFRatingColor = RatingColor
ns.GFOpt = Opt
ns.GFSpecIcon = SpecIcon
-- the name colour a row gets (nil = blizzard's own): red when declined or
-- locked out, green when new since the last search
function ns.GFNameColor(resultID, info, ai)
    if not Opt("nameColors") then return nil end
    local delisted, censored = info.isDelisted, info.censored
    if IsSecret(delisted) or IsSecret(censored) or delisted or censored then return nil end
    local _, appStatus = C_LFGList.GetApplicationInfo(resultID)
    if IsSecret(appStatus) then return nil end
    local declined = appStatus == "declined" or appStatus == "declined_full" or appStatus == "declined_delisted"
    if declined or LockedOut(ai, resultID) then return 1, 0.25, 0.25 end
    if prevResults and not prevResults[resultID] and (appStatus == "none" or appStatus == nil) then return 0.3, 1, 0.3 end
    return nil
end

-- display settings changed: redecorate the visible rows.
function XF.Redecorate()
    XF.NewPass()
    if not (SP and SP:IsVisible()) then return end
    local box = SP.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(DecorateEntry) end
    if ns.ExtraRedecorate then ns.ExtraRedecorate() end
end

-- tooltip hint while a click would cancel your oldest application.
function XF.CancelHint(tooltip, resultID)
    if not (tooltip and tooltip.IsShown and tooltip:IsShown()) or not XF.ShouldCancelOldest(resultID) then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(EllesmereUI.L("Click: cancel your oldest application to sign up here"), 1, 0.35, 0.35, true)
    tooltip:Show()
end

-- member list in the tooltip, tanks then healers then dps.
local ROLE_ICON = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal", DAMAGER = "groupfinder-icon-role-micro-dps" }
local function AddClassesByRole(tooltip, resultID)
    if not Opt("classTooltip") or not (tooltip and tooltip.IsShown and tooltip:IsShown()) then return end
    if XF.ResultsSecret() then return end
    local info = ResultInfo(resultID)
    if not info or IsSecret(info.isDelisted) or info.isDelisted then return end
    local acts = info.activityIDs
    local act = type(acts) == "table" and not IsSecret(acts) and acts[1]
    local ai = act and not IsSecret(act) and XF.ActInfo(act)
    if not ai then return end
    local n = info.numMembers
    if type(n) ~= "number" or IsSecret(n) or n < 1 then return end
    local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
    for i = 1, n do
        local p = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
        local role, class = p and p.assignedRole, p and p.classFilename
        if role and class and not IsSecret(role) and not IsSecret(class) and byRole[role] then
            local list = byRole[role]
            list[#list + 1] = p
        end
    end
    -- dungeons/arenas already list roles and classes, so just add the names.
    local DT = Enum.LFGListDisplayType
    if DT and (ai.displayType == DT.RoleEnumerate or ai.displayType == DT.ClassEnumerate) then
        local names = {}
        for _, role in ipairs(XF.ROLE_ORDER) do
            for _, p in ipairs(byRole[role]) do
                local name = p.name and not IsSecret(p.name) and p.name
                if name then
                    local col = RAID_CLASS_COLORS[p.classFilename]
                    names[#names + 1] = (col and col.colorStr) and ("|c" .. col.colorStr .. name .. "|r") or name
                end
            end
        end
        if #names == 0 then return end
        tooltip:AddLine(" ")
        tooltip:AddLine(EllesmereUI.L("Names:") .. " " .. table.concat(names, XF.DIM_HEX .. ",|r "), 1, 0.82, 0, true)
        tooltip:Show()
        return
    end
    local added = false
    for _, role in ipairs(XF.ROLE_ORDER) do
        for _, p in ipairs(byRole[role]) do
            if not added then tooltip:AddLine(" "); added = true end
            local col = RAID_CLASS_COLORS[p.classFilename] or NORMAL_FONT_COLOR
            local className = (not IsSecret(p.className) and p.className)
                or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.classFilename]) or p.classFilename
            local spec = p.specName and not IsSecret(p.specName) and p.specName
            local icon = CreateAtlasMarkup and CreateAtlasMarkup(ROLE_ICON[role], 12, 12) or ""
            local crown = (p.isLeader and CreateAtlasMarkup) and (" " .. CreateAtlasMarkup("groupfinder-icon-leader", 12, 8)) or ""
            local left = icon .. " " .. (spec and (spec .. " ") or "") .. className .. crown
            local name = p.name and not IsSecret(p.name) and p.name or ""
            tooltip:AddDoubleLine(left, name, col.r, col.g, col.b, col.r, col.g, col.b)
        end
    end
    if added then tooltip:Show() end
end

local ITEM_H, CHECK_SZ, ITEM_FONT = 20, 12, 9

local function ThemeFill()
    local S = Skin()
    local T = S and S.Theme
    if T and T.bgR then return T.bgR, T.bgG, T.bgB end
    return 0.08, 0.08, 0.08
end

local function MenuItem(parent, y, text, onClick)
    local item = CreateFrame("Button", nil, parent)
    item:SetHeight(ITEM_H)
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -y)
    item:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -y)
    local cb = CreateFrame("Frame", nil, item)
    cb:SetSize(CHECK_SZ, CHECK_SZ)
    cb:SetPoint("LEFT", item, "LEFT", 8, 0)
    local cbBg = cb:CreateTexture(nil, "BACKGROUND")
    cbBg:SetAllPoints()
    cbBg:SetColorTexture(0.12, 0.12, 0.12, 1)
    item.ring = CM.MakeBorder(cb, 0.25, 0.25, 0.25, 0.6, CM.PanelPP)
    item.fill = cb:CreateTexture(nil, "ARTWORK")
    item.fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    item.fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    local tR, tG, tB, tA = CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A
    item.label = item:CreateFontString(nil, "OVERLAY")
    XF.Font(item.label, ITEM_FONT)
    item.label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
    item.label:SetPoint("RIGHT", item, "RIGHT", -4, 0)
    item.label:SetJustifyH("LEFT")
    item.label:SetWordWrap(false)
    item.label:SetText(text)
    item.label:SetTextColor(tR, tG, tB, tA)
    local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0)
    item:SetScript("OnEnter", function() item.label:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A) end)
    item:SetScript("OnLeave", function() item.label:SetTextColor(tR, tG, tB, tA); hl:SetColorTexture(1, 1, 1, 0) end)
    item:SetScript("OnClick", onClick)
    -- dimmed + unclickable
    function item:SetDimmed(off)
        self:EnableMouse(not off)
        self:SetAlpha(off and 0.35 or 1)
    end
    function item:SetChecked(on)
        local r, g, b = Accent()
        self.fill:SetColorTexture(r, g, b, 1)
        self.fill:SetShown(on)
        if on then self.ring:SetColor(r, g, b, 0.8) else self.ring:SetColor(0.25, 0.25, 0.25, 0.6) end
    end
    return item
end

-- section title, with a divider above all but the first.
local function AddSection(m, y, title)
    if y > 4 then
        local div = m:CreateTexture(nil, "ARTWORK")
        div:SetHeight(CM.PP.mult)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", m, "TOPLEFT", 10, -y - 3)
        div:SetPoint("TOPRIGHT", m, "TOPRIGHT", -10, -y - 3)
        y = y + 7
    else
        y = y + 2
    end
    local fs = m:CreateFontString(nil, "OVERLAY")
    XF.Font(fs, ITEM_FONT)
    fs:SetTextColor(0.55, 0.55, 0.55, 1)
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", m, "TOPLEFT", 9, -y - 2)
    fs:SetText(title)
    return y + 14
end

-- playstyles: dungeons apply on search again, raids right away
local function AddPlaystyleItems(m, y, raids)
    y = AddSection(m, y, EllesmereUI.L("Playstyle"))
    for i, label in ipairs(PLAYSTYLES) do
        m.items["style_" .. i] = MenuItem(m, y, label, function()
            if raids then
                local c = Cfg()
                if type(c.raidPlaystyles) ~= "table" then c.raidPlaystyles = {} end
                c.raidPlaystyles[i] = (not c.raidPlaystyles[i]) or nil
                local _, n = ChosenRaidPlaystyles()
                if n == #PLAYSTYLES then wipe(c.raidPlaystyles) end
                Refilter()
                Paint()
            else
                local f = XF.GetFilter()
                local key = "generalPlaystyle" .. i
                if DungeonPlaystyles(f) == nil then
                    for k = 1, #PLAYSTYLES do f["generalPlaystyle" .. k] = (k == i) end
                else
                    f[key] = not f[key]
                    local _, n = DungeonPlaystyles(f)
                    if n == 0 or n == #PLAYSTYLES then
                        for k = 1, #PLAYSTYLES do f["generalPlaystyle" .. k] = true end
                    end
                end
                Apply(f)
            end
        end)
        y = y + ITEM_H
    end
    return y
end

local function PaintPlaystyleItems(m, raids)
    local chosen
    if raids then chosen = ChosenRaidPlaystyles() else chosen = DungeonPlaystyles(XF.GetFilter()) end
    for i = 1, #PLAYSTYLES do
        local item = m.items["style_" .. i]
        if item then
            local on
            if raids then on = chosen ~= nil and chosen[i] == true else on = chosen ~= nil and chosen["generalPlaystyle" .. i] == true end
            item:SetChecked(on)
        end
    end
end

local function AddRoleItems(m, y, raids)
    y = AddSection(m, y, EllesmereUI.L("Roles"))
    -- helpers for our rows
    local K = ns.ExtraClassRows and { Cfg = Cfg, Refilter = Refilter, Paint = Paint, Font = XF.Font,
        ITEM_H = ITEM_H, ITEM_FONT = ITEM_FONT, CHECK_SZ = CHECK_SZ, ThemeBorder = ThemeBorder, ThemeFill = ThemeFill,
        ClickOff = XF.ClickOff, Tip = XF.Tip, Untip = XF.Untip, Accent = Accent, parent = SP,
        MenuItem = MenuItem, ClassLine = XF.ClassLine, FLAG_KEYS = XF.FLAG_KEYS,
        AddCountRow = XF.AddCountRow, COUNT_ROLES = XF.COUNT_ROLES,
        OpListOver = function() return XF.opList and XF.opList:IsShown() and XF.opList:IsMouseOver() or false end }
    for _, r in ipairs(ROLES) do
        local key = r.key
        m.items["role_" .. key] = MenuItem(m, y, r.label, function()
            if raids then
                local c = Cfg()
                if type(c.raidRoles) ~= "table" then c.raidRoles = {} end
                c.raidRoles[key] = (not c.raidRoles[key]) or nil
                Refilter()
                Paint()
            else
                local f = XF.GetFilter()
                f[key] = not f[key]
                Apply(f)
            end
        end)
        y = y + ITEM_H
    end
    if K and ns.ExtraClassRows then
        y = ns.ExtraClassRows(m, y, K)  -- has / missing dropdown rows
    else
    y = XF.AddFlagItem(m, y, "hasLust", EllesmereUI.L("Has Bloodlust"), {
        EllesmereUI.L("A member whose class has one of these spells:"),
        XF.ClassLine("SHAMAN", EllesmereUI.L("Bloodlust / Heroism (Shaman)")),
        XF.ClassLine("MAGE", EllesmereUI.L("Time Warp (Mage)")),
        XF.ClassLine("HUNTER", EllesmereUI.L("Primal Rage (Hunter pet)")),
        XF.ClassLine("EVOKER", EllesmereUI.L("Fury of the Aspects (Evoker)")),
        EllesmereUI.L("Drums and other items don't count.") })
    y = XF.AddFlagItem(m, y, "hasBrez", EllesmereUI.L("Has Battle Res"), {
        EllesmereUI.L("A member whose class has one of these spells:"),
        XF.ClassLine("DRUID", EllesmereUI.L("Rebirth (Druid)")),
        XF.ClassLine("DEATHKNIGHT", EllesmereUI.L("Raise Ally (Death Knight)")),
        XF.ClassLine("WARLOCK", EllesmereUI.L("Soulstone (Warlock)")),
        XF.ClassLine("PALADIN", EllesmereUI.L("Intercession (Paladin)")),
        EllesmereUI.L("Engineering and other items don't count.") })
    end
    -- match any / exactly + count rows under one button
    if K and ns.ExtraRoleCounts then
        y = ns.ExtraRoleCounts(m, y, K)
    else
        for _, r in ipairs(XF.COUNT_ROLES) do y = XF.AddCountRow(m, y, r.key, r.label) end
    end
    return y
end

-- shared less than / more than / equal to list.
function XF.OpenOpList(btn, role)
    local L = XF.opList
    if not L then
        L = CreateFrame("Frame", nil, SP)
        XF.opList = L
        L:SetFrameStrata("FULLSCREEN_DIALOG")
        L:SetFrameLevel(330)
        L:SetClampedToScreen(true)
        L:EnableMouse(true)
        L:SetWidth(92)
        local bg = L:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 1)
        CM.MakeBorder(L, ThemeBorder())
        L.items = {}
        for i, o in ipairs(XF.COUNT_OPS) do
            local it = CreateFrame("Button", nil, L)
            it:SetHeight(ITEM_H)
            it:SetPoint("TOPLEFT", L, "TOPLEFT", 1, -(2 + (i - 1) * ITEM_H))
            it:SetPoint("TOPRIGHT", L, "TOPRIGHT", -1, -(2 + (i - 1) * ITEM_H))
            it.text = it:CreateFontString(nil, "OVERLAY")
            XF.Font(it.text, ITEM_FONT)
            it.text:SetPoint("LEFT", it, "LEFT", 8, 0)
            it.text:SetText(o.label)
            local hl = it:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A)
            it.opKey = o.key
            it:SetScript("OnClick", function()
                local c = Cfg()
                if type(c.roleCounts) ~= "table" then c.roleCounts = {} end
                local r = c.roleCounts[L.role] or {}
                r.op = o.key
                c.roleCounts[L.role] = r
                L:Hide()
                Refilter()
                Paint()
            end)
            L.items[i] = it
        end
        L:SetHeight(4 + #XF.COUNT_OPS * ITEM_H)
        XF.ClickOff(L, function(self)
            return self:IsMouseOver() or (self.owner and self.owner:IsMouseOver())
        end)
        L:Hide()
    end
    if L:IsShown() and L.owner == btn then L:Hide(); return end
    L.owner, L.role = btn, role
    local rule = (Cfg().roleCounts or XF.EMPTY)[role]
    local cur = (type(rule) == "table" and rule.op) or "lt"
    local ar, ag, ab = Accent()
    local tR, tG, tB, tA = CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A
    for _, it in ipairs(L.items) do
        if it.opKey == cur then it.text:SetTextColor(ar, ag, ab, 1) else it.text:SetTextColor(tR, tG, tB, tA) end
    end
    L:ClearAllPoints()
    L:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    L:Show()
end

-- small black input box.
function XF.MenuBox(parent, w, letters)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(w, 16)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(letters)
    XF.Font(box, ITEM_FONT)
    box:SetTextColor(1, 1, 1, 1)
    box:SetJustifyH("CENTER")
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    CM.MakeBorder(box, ThemeBorder())
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- 'Tanks [Less Than] [n]' row; empty box means no check.
function XF.AddCountRow(m, y, role, text)
    local function Rule()
        local c = Cfg()
        if type(c.roleCounts) ~= "table" then c.roleCounts = {} end
        local r = c.roleCounts[role] or {}
        c.roleCounts[role] = r
        return r
    end
    local rowF = CreateFrame("Frame", nil, m)
    rowF:SetHeight(ITEM_H + 2)
    rowF:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
    rowF:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -y)
    local sw = CreateFrame("Button", nil, rowF)
    sw:SetSize(CHECK_SZ, CHECK_SZ)
    sw:SetPoint("LEFT", rowF, "LEFT", 8, 0)
    local sbg = sw:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(0.12, 0.12, 0.12, 1)
    sw.ring = CM.MakeBorder(sw, 0.25, 0.25, 0.25, 0.6, CM.PanelPP)
    sw.fill = sw:CreateTexture(nil, "ARTWORK")
    sw.fill:SetPoint("TOPLEFT", sw, "TOPLEFT", 3, -3)
    sw.fill:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -3, 3)
    sw:SetScript("OnClick", function()
        local r = Rule()
        r.on = (not r.on) or nil
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Refilter()
        Paint()
        if r.on and m.counts and m.counts[role] then m.counts[role].box:SetFocus() end
    end)
    local op = CreateFrame("Button", nil, rowF)
    op:SetSize(20, 16)
    op:SetPoint("LEFT", sw, "RIGHT", 7, 0)
    local obg = op:CreateTexture(nil, "BACKGROUND")
    obg:SetAllPoints()
    obg:SetColorTexture(0, 0, 0, 1)
    CM.MakeBorder(op, ThemeBorder())
    op.text = op:CreateFontString(nil, "OVERLAY")
    XF.Font(op.text, ITEM_FONT + 1)
    op.text:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    op.text:SetPoint("CENTER", 0, 1)
    local hl = op:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    op:SetScript("OnClick", function(self) XF.OpenOpList(self, role) end)
    local box = XF.MenuBox(rowF, 22, 2)
    box:SetPoint("LEFT", op, "RIGHT", 3, 0)
    box:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        Rule().n = tonumber(self:GetText())
        Refilter()
        Paint()
    end)
    local label = rowF:CreateFontString(nil, "OVERLAY")
    XF.Font(label, ITEM_FONT)
    label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(text)
    m.counts = m.counts or {}
    m.counts[role] = { box = box, op = op, sw = sw, label = label }
    return y + ITEM_H + 2
end

function XF.PaintCountRows(m)
    for _, r in ipairs(XF.COUNT_ROLES) do
        local row = m.counts and m.counts[r.key]
        if row then
            local rule = (Cfg().roleCounts or XF.EMPTY)[r.key]
            local on = type(rule) == "table" and rule.on == true
            row.op.text:SetText(XF.COUNT_OP_LABEL[(type(rule) == "table" and rule.op) or "lt"])
            if not row.box:HasFocus() then
                local n = type(rule) == "table" and tonumber(rule.n)
                row.box:SetText(n and tostring(n) or "")
            end
            local sw = row.sw
            local ar, ag, ab = Accent()
            sw.fill:SetColorTexture(ar, ag, ab, 1)
            sw.fill:SetShown(on)
            if on then sw.ring:SetColor(ar, ag, ab, 0.8) else sw.ring:SetColor(0.25, 0.25, 0.25, 0.6) end
            local a = on and 1 or 0.4
            row.op:SetAlpha(a)
            row.box:SetAlpha(a)
            if not on and row.box:HasFocus() then row.box:ClearFocus() end
            row.box:SetEnabled(on)
            row.label:SetAlpha(a)
        end
    end
end

-- toggles both menus share
function XF.AddFlagItem(m, y, key, text, tip)
    local item = MenuItem(m, y, text, function()
        local c = Cfg()
        c[key] = (not c[key]) or nil
        Refilter()
        Paint()
    end)
    m.items["flag_" .. key] = item
    if tip then
        item:HookScript("OnEnter", function(self)
            if type(tip) == "table" then XF.Tip(self, text, unpack(tip)) else XF.Tip(self, text, tip) end
        end)
        item:HookScript("OnLeave", XF.Untip)
    end
    return y + ITEM_H
end

XF.FLAG_KEYS = { "partyFit", "notDeclined", "hasLust", "hasBrez" }
function XF.PaintFlagItems(m)
    local c = Cfg()
    for _, key in ipairs(XF.FLAG_KEYS) do
        local item = m.items["flag_" .. key]
        if item then item:SetChecked(c[key] == true) end
    end
end

local function PaintRoleItems(m, raids)
    local src = raids and (ChosenRaidRoles() or XF.EMPTY) or XF.GetFilter()
    for _, r in ipairs(ROLES) do
        local item = m.items["role_" .. r.key]
        if item then item:SetChecked(src[r.key] == true) end
    end
    XF.PaintFlagItems(m)
    XF.PaintCountRows(m)
end

-- min. rating: the leader's m+ rating, applied on search again
local function AddRatingRow(m, y)
    local function Send()
        local c = Cfg()
        local v = c.ratingOn and (tonumber(c.ratingValue) or 0) or 0
        local f = XF.GetFilter()
        if (f.minimumRating or 0) ~= v then
            f.minimumRating = v
            Apply(f)
        end
    end
    local rowF = CreateFrame("Frame", nil, m)
    rowF:SetHeight(ITEM_H + 4)
    rowF:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
    rowF:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -y)
    local RATING = EllesmereUI.L("Min. Rating")
    local RATING_TIP = EllesmereUI.L("Only groups whose leader has at least this Mythic+ rating. Applied on Search Again.")
    rowF:EnableMouse(true)
    rowF:SetScript("OnEnter", function(self) XF.Tip(self, RATING, RATING_TIP) end)
    rowF:SetScript("OnLeave", XF.Untip)
    local cb = CreateFrame("Button", nil, rowF)
    cb:SetSize(CHECK_SZ, CHECK_SZ)
    cb:SetPoint("LEFT", rowF, "LEFT", 8, 0)
    cb:SetScript("OnEnter", function(self) XF.Tip(self, RATING, RATING_TIP) end)
    cb:SetScript("OnLeave", XF.Untip)
    local cbg = cb:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(0.12, 0.12, 0.12, 1)
    cb.ring = CM.MakeBorder(cb, 0.25, 0.25, 0.25, 0.6, CM.PanelPP)
    cb.fill = cb:CreateTexture(nil, "ARTWORK")
    cb.fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    cb.fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    cb:SetScript("OnClick", function()
        local c = Cfg()
        c.ratingOn = (not c.ratingOn) or nil
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Send()
        Paint()
        if c.ratingOn and m.rating then m.rating.box:SetFocus() end
    end)
    local label = rowF:CreateFontString(nil, "OVERLAY")
    XF.Font(label, ITEM_FONT)
    label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
    label:SetText(RATING)
    local box = XF.MenuBox(rowF, 44, 4)
    box:SetPoint("RIGHT", rowF, "RIGHT", -7, 0)
    box:SetScript("OnEditFocusLost", function(self)
        Cfg().ratingValue = tonumber(self:GetText())
        Send()
        Paint()
    end)
    m.rating = { box = box, cb = cb, label = label }
    return y + ITEM_H + 4
end

-- restore the saved rating when ticked again.
function XF.AdoptRating()
    local c = Cfg()
    if c.ratingOn ~= nil or c.ratingValue ~= nil then return end
    local f = XF.GetFilter()
    local v = f and tonumber(f.minimumRating) or 0
    if v > 0 then c.ratingOn, c.ratingValue = true, v end
end

function XF.PaintRating(m)
    local r = m and m.rating
    if not r then return end
    local c = Cfg()
    local on = c.ratingOn == true
    local ar, ag, ab = Accent()
    r.cb.fill:SetColorTexture(ar, ag, ab, 1)
    r.cb.fill:SetShown(on)
    if on then r.cb.ring:SetColor(ar, ag, ab, 0.8) else r.cb.ring:SetColor(0.25, 0.25, 0.25, 0.6) end
    if not r.box:HasFocus() then
        local v = tonumber(c.ratingValue)
        r.box:SetText(v and v > 0 and tostring(v) or "")
    end
    local a = on and 1 or 0.4
    r.label:SetAlpha(a)
    r.box:SetAlpha(a)
    if not on and r.box:HasFocus() then r.box:ClearFocus() end
    r.box:SetEnabled(on)
end

local function AddRegionItems(m, y)
    if not RegionsAvailable() then return y end
    -- eu lists languages, short names in two columns
    local lang = ns.RegionIsLanguage()
    y = AddSection(m, y, lang and EllesmereUI.L("Language") or EllesmereUI.L("Region"))
    for i, r in ipairs(Regions()) do
        local key = r.key
        local item = MenuItem(m, y, lang and r.tag or r.label, function()
            local c = Cfg()
            if type(c.regions) ~= "table" then c.regions = {} end
            c.regions[key] = (not c.regions[key]) or nil
            local n = 0
            for _, o in ipairs(Regions()) do if c.regions[o.key] then n = n + 1 end end
            if n == #Regions() then wipe(c.regions) end
            Refilter()
            Paint()
        end)
        m.items["region_" .. key] = item
        if lang then
            item:ClearAllPoints()
            if i % 2 == 1 then
                item:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
                item:SetPoint("TOPRIGHT", m, "TOP", 0, -y)
            else
                item:SetPoint("TOPLEFT", m, "TOP", 0, -y)
                item:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -y)
            end
            if i % 2 == 0 or i == #Regions() then y = y + ITEM_H end
        else
            y = y + ITEM_H
        end
    end
    return y
end

local function PaintRegionItems(m)
    local chosen = RegionFilterActive() and ChosenRegions()
    for _, r in ipairs(Regions()) do
        local item = m.items["region_" .. r.key]
        if item then item:SetChecked(chosen and chosen[r.key] == true or false) end
    end
end

local function PaintMenu()
    if raidDiffMenu and raidDiffMenu:IsShown() then
        local chosen = ChosenRaidDiffs()
        for _, d in ipairs(RAID_DIFFS_MENU) do
            raidDiffMenu.items[d.key]:SetChecked(chosen ~= nil and chosen[d.key] == true)
        end
        PaintRoleItems(raidDiffMenu, true)
        XF.PaintFlagItems(raidDiffMenu.side)
        PaintRegionItems(raidDiffMenu.side)
        PaintPlaystyleItems(raidDiffMenu.side, true)
    end
    if not (menu and menu:IsShown()) then return end
    local f = XF.GetFilter()
    local all = DiffAllOrNone(f)
    for _, d in ipairs(DIFFS) do
        menu.items[d.key]:SetChecked(not all and f[d.key] == true)
    end
    XF.PaintRating(menu.side)
    PaintRoleItems(menu, false)
    XF.PaintFlagItems(menu.side)
    PaintRegionItems(menu.side)
    PaintPlaystyleItems(menu.side, false)
end

-- filters menu side panel: region, playstyle, then the extra toggles.
XF.DIM_ALPHA = 0.35
local function DimForMenu(on)
    local a = on and XF.DIM_ALPHA or 1
    if row then row:SetAlpha(a) end
    local face = XF.FilterFace()
    if face then face:SetAlpha(a) end
    if SP.ScrollBox then SP.ScrollBox:SetAlpha(a) end
    if SP.ScrollBar then SP.ScrollBar:SetAlpha(a) end
    if ns.ExtraOnDim then ns.ExtraOnDim(on) end  -- row 1 blocked too
end

local function BuildSidePanel(m, raids)
    local side = CreateFrame("Frame", nil, SP)
    side:SetFrameStrata("FULLSCREEN_DIALOG")
    side:EnableMouse(true)
    side:SetFrameLevel(300)
    side:SetClampedToScreen(true)
    side:SetWidth(140)
    side:SetPoint("TOPRIGHT", m, "TOPLEFT", 0, 0)
    local bg = side:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    side.items = {}
    local y = 3
    y = AddRegionItems(side, y)
    y = AddPlaystyleItems(side, y, raids)
    side.extraMiscY = y  -- where misc starts
    y = AddSection(side, y, EllesmereUI.L("Misc"))
    side.extraMiscRowsY = y
    y = XF.AddFlagItem(side, y, "partyFit", EllesmereUI.L("Party Fit"),
        EllesmereUI.L("Only groups with open slots for your role, or for your whole party's roles."))
    y = XF.AddFlagItem(side, y, "notDeclined", EllesmereUI.L("Not Declined"),
        EllesmereUI.L("Hides groups that have declined you this session."))
    if not raids then y = AddRatingRow(side, y) end
    side.extraEndY = y
    -- both columns the same height, one border around them
    local h = math.max(y + 3, m:GetHeight() or 0)
    side:SetHeight(h)
    m:SetHeight(h)
    local edge = CreateFrame("Frame", nil, side)
    edge:SetPoint("TOPLEFT", side, "TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
    edge:SetFrameLevel(m:GetFrameLevel() + 10)
    edge:EnableMouse(false)
    local S = Skin()
    if S and S.AddBorder then S.AddBorder(edge) else CM.MakeBorder(edge, ThemeBorder()) end
    side:Hide()
    m.side = side
    m:SetScript("OnShow", function() side:Show(); DimForMenu(true) end)
    m:SetScript("OnHide", function()
        side:Hide()
        DimForMenu(false)
        if XF.opList then XF.opList:Hide() end
    end)
    XF.ClickOff(m, XF.FiltersInside)
    return side
end

-- clicks on the menu, side panel, button or operator list keep it open
function XF.FiltersInside(m)
    return m:IsMouseOver() or (diffBtn and diffBtn:IsMouseOver()) or m.side:IsMouseOver()
        or (XF.opList and XF.opList:IsShown() and XF.opList:IsMouseOver())
        or (ns.ExtraInside and ns.ExtraInside())  -- our dropdowns
        or false
end

-- filters menu, border around it and the side panel
local function BuildMenu()
    menu = CreateFrame("Frame", nil, SP)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    menu:SetFrameLevel(300)
    menu:SetClampedToScreen(true)
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    menu.items = {}
    local y = 3
    y = AddSection(menu, y, EllesmereUI.L("Difficulty"))
    for _, d in ipairs(DIFFS) do
        local key = d.key
        menu.items[key] = MenuItem(menu, y, d.label, function()
            local f = XF.GetFilter()
            local all = DiffAllOrNone(f)
            if all then
                for _, o in ipairs(DIFFS) do f[o.key] = (o.key == key) end
                Apply(f)
            else
                SetDifficulty(key, not f[key])
            end
        end)
        y = y + ITEM_H
    end
    y = AddRoleItems(menu, y, false)
    menu:SetHeight(y + 3)
    BuildSidePanel(menu, false)
    if ns.ExtraDecorateMenu then ns.ExtraDecorateMenu(menu, menu.side) end
    menu:Hide()
end

-- raids version of the filters menu (no mythic+), applies right away.
local function BuildRaidDiffMenu()
    local m = CreateFrame("Frame", nil, SP)
    raidDiffMenu = m
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:EnableMouse(true)
    m:SetFrameLevel(300)
    m:SetClampedToScreen(true)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local function Diffs()
        local c = Cfg()
        if type(c.raidDiffs) ~= "table" then c.raidDiffs = {} end
        return c.raidDiffs
    end
    m.items = {}
    local y = 3
    y = AddSection(m, y, EllesmereUI.L("Difficulty"))
    for _, d in ipairs(RAID_DIFFS_MENU) do
        local key = d.key
        m.items[key] = MenuItem(m, y, d.label, function()
            local t = Diffs()
            t[key] = (not t[key]) or nil
            local _, n = ChosenRaidDiffs()
            if n == #RAID_DIFFS_MENU then wipe(t) end
            Refilter()
            Paint()
        end)
        y = y + ITEM_H
    end
    -- gap for the missing m+ row, keeps roles lined up
    if ns.ExtraClassRows then y = y + math.max(0, #DIFFS - #RAID_DIFFS_MENU) * ITEM_H end
    y = AddRoleItems(m, y, true)
    m:SetHeight(y + 3)
    BuildSidePanel(m, true)
    if ns.ExtraDecorateMenu then ns.ExtraDecorateMenu(m, m.side) end
    m:Hide()
end

-- show specialization changed: redraw (icon size stays put)
function XF.SpecIconsChanged(menu)
    if menu and menu.items then
        for _, it in ipairs(menu.items) do it:Paint() end
    end
    XF.Redecorate()
end

-- group settings menu (person button): list look and sign-up options.
XF.GROUP_MENU = {
    { title = EllesmereUI.L("Listing") },
    { key = "leaderRating",   label = EllesmereUI.L("Leader Rating"),
      tip = EllesmereUI.L("Shows the group leader's Mythic+ rating next to the role icons.") },
    { key = "specIcons",      label = EllesmereUI.L("Show Specialization"),
      tip = EllesmereUI.L("Shows each member's specialization icon in place of the game's class and role icons. Off, the game's own icons stay."),
      onToggle = function(menu) XF.SpecIconsChanged(menu) end },
    { key = "leaderCrown",    label = EllesmereUI.L("Show Group Leader"),
      tip = EllesmereUI.L("Puts a small crown above the group leader's icon.") },
    { key = "classTooltip",   label = EllesmereUI.L("Members in Tooltip"),
      tip = EllesmereUI.L("Group tooltips add each member's name (dungeons and arenas, where Blizzard already lists the roles and classes), or a line per member with role, specialization, class and name (other groups).") },
    { title = EllesmereUI.L("Sign Up") },
    { key = "cancelOldest",   label = EllesmereUI.L("Cancel Oldest Application"),
      tip = EllesmereUI.L("At the application limit, clicking a group cancels your oldest pending application so you can sign up.") },
    { key = "persistSignupNote", label = EllesmereUI.L("Persistent Signup Note"), core = "_applyPersistSignupNote",
      tip = EllesmereUI.L("Keeps the note you typed in the Sign Up dialog between sign ups.") },
    { title = EllesmereUI.L("Misc") },
    { key = "dungeonAbbr",    label = EllesmereUI.L("Dungeon Names"),
      tip = EllesmereUI.L("Each dungeon square shows the dungeon's short name (e.g. KR for Kings' Rest)."),
      onToggle = function() ns.Search_Layout() end },
    { key = "dungeonScore",   label = EllesmereUI.L("Dungeon Keystone Level"),
      tip = EllesmereUI.L("Each dungeon square shows your best keystone level this season, colored by its score rarity."),
      onToggle = function() ns.Search_Layout() end },
}
XF.MENU_SW_W, XF.MENU_SW_H = 22, 12

function XF.GroupOpt(key, default)
    local v = Cfg()[key]
    if v == nil then v = ns.DEFAULTS[key] end
    if v == nil then v = default end
    return v and true or false
end

function XF.ItemOn(spec)
    if spec.core then return EllesmereUIDB[spec.key] and true or false end
    return XF.GroupOpt(spec.key, spec.default)
end

-- menu row with a small switch; click anywhere to flip it.
function XF.SwitchItem(m, y, spec)
    local item = CreateFrame("Button", nil, m)
    item:SetHeight(ITEM_H)
    item:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
    item:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -y)
    local sw = CreateFrame("Frame", nil, item)
    sw:SetSize(XF.MENU_SW_W, XF.MENU_SW_H)
    sw:SetPoint("LEFT", item, "LEFT", 8, 0)
    sw:EnableMouse(false)
    sw.track = sw:CreateTexture(nil, "BACKGROUND")
    sw.track:SetAllPoints()
    sw.knob = sw:CreateTexture(nil, "ARTWORK")
    sw.knob:SetSize(XF.MENU_SW_H - 4, XF.MENU_SW_H - 4)
    item.sw = sw
    local tR, tG, tB, tA = CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A
    item.label = item:CreateFontString(nil, "OVERLAY")
    XF.Font(item.label, ITEM_FONT)
    item.label:SetPoint("LEFT", sw, "RIGHT", 7, 0)
    item.label:SetPoint("RIGHT", item, "RIGHT", -6, 0)
    item.label:SetJustifyH("LEFT")
    item.label:SetWordWrap(false)
    item.label:SetText(spec.label)
    item.label:SetTextColor(tR, tG, tB, tA)
    local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0)
    item:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 1, 1, 1)
        hl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A)
        if spec.tip then XF.Tip(self, spec.label, spec.tip) end
    end)
    item:SetScript("OnLeave", function(self)
        self.label:SetTextColor(tR, tG, tB, tA)
        hl:SetColorTexture(1, 1, 1, 0)
        XF.Untip()
    end)
    function item:Paint()
        local on = XF.ItemOn(spec)
        self.sw.knob:ClearAllPoints()
        if on then
            local r, g, b = Accent()
            self.sw.track:SetColorTexture(r, g, b, 0.75)
            self.sw.knob:SetColorTexture(1, 1, 1, 1)
            self.sw.knob:SetPoint("RIGHT", self.sw, "RIGHT", -2, 0)
        else
            self.sw.track:SetColorTexture(0.267, 0.267, 0.267, 0.65)
            self.sw.knob:SetColorTexture(1, 1, 1, 0.5)
            self.sw.knob:SetPoint("LEFT", self.sw, "LEFT", 2, 0)
        end
    end
    item:SetScript("OnClick", function(self)
        if spec.core then
            EllesmereUIDB[spec.key] = not XF.ItemOn(spec)
            CM[spec.core]()
        else
            Cfg()[spec.key] = not XF.GroupOpt(spec.key, spec.default)
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        self:Paint()
        if spec.onToggle then spec.onToggle(m) else XF.Redecorate() end
    end)
    item:Paint()
    return item
end

function XF.BuildGroupMenu()
    local m = CreateFrame("Frame", nil, SP)
    XF.groupMenu = m
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:EnableMouse(true)
    m:SetFrameLevel(300)
    m:SetClampedToScreen(true)
    m:SetWidth(200)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local S = Skin()
    if S and S.AddBorder then S.AddBorder(m) else CM.MakeBorder(m, ThemeBorder()) end
    m.items = {}
    local y = 3
    local list = ns.ExtraGroupMenu and ns.ExtraGroupMenu(XF.GROUP_MENU) or XF.GROUP_MENU
    if ns.ExtraGroupColumns then
        -- two-column layout
        y = ns.ExtraGroupColumns(m, list, { AddSection = AddSection, SwitchItem = XF.SwitchItem,
            ITEM_H = ITEM_H,
            -- for the sort dropdown
            Cfg = Cfg, Refilter = Refilter, Paint = Paint, Font = XF.Font, ITEM_FONT = ITEM_FONT,
            ThemeBorder = ThemeBorder, ClickOff = XF.ClickOff, Tip = XF.Tip, Untip = XF.Untip,
            Accent = Accent, parent = SP })
    else
    for _, spec in ipairs(list) do
        if spec.title then
            y = AddSection(m, y, spec.title)
        else
            m.items[#m.items + 1] = XF.SwitchItem(m, y, spec)
            y = y + ITEM_H
        end
    end
    end
    m:SetHeight(y + 3)
    m:SetScript("OnShow", function(self)
        for _, it in ipairs(self.items) do it:Paint() end
        DimForMenu(true)
        local face = XF.FilterFace()
        if face then face:SetAlpha(1) end
    end)
    m:SetScript("OnHide", function() DimForMenu(false) end)
    XF.ClickOff(m, function(self)
        return self:IsMouseOver() or (self.owner and self.owner:IsMouseOver())
            or (ns.ExtraInside and ns.ExtraInside()) or false  -- the sort dropdown's list
    end)
    m:Hide()
end

function XF.ToggleGroupMenu(owner)
    if not XF.groupMenu then XF.BuildGroupMenu() end
    local m = XF.groupMenu
    if m:IsShown() then m:Hide(); return end
    m.owner = owner
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -SQ_GAP)
    if ns.ExtraGroupMenuPlace then ns.ExtraGroupMenuPlace(m, owner, refreshBtn) end
    m:Show()
end

local function ToggleMenu()
    if SP.categoryID == RAIDS then
        if not raidDiffMenu then BuildRaidDiffMenu() end
        if raidDiffMenu:IsShown() then raidDiffMenu:Hide(); return end
        raidDiffMenu:ClearAllPoints()
        raidDiffMenu:SetPoint("TOPLEFT", diffBtn, "BOTTOMLEFT", 0, -SQ_GAP)
        raidDiffMenu:SetPoint("TOPRIGHT", refreshBtn or diffBtn, "BOTTOMRIGHT", 0, -SQ_GAP)
        if ns.ExtraWidenMenu then ns.ExtraWidenMenu(raidDiffMenu, diffBtn, SQ_GAP, refreshBtn or diffBtn) end
        raidDiffMenu:Show()
        PaintMenu()
        return
    end
    if not menu then BuildMenu() end
    if menu:IsShown() then menu:Hide(); return end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", diffBtn, "BOTTOMLEFT", 0, -SQ_GAP)
    menu:SetPoint("TOPRIGHT", refreshBtn or diffBtn, "BOTTOMRIGHT", 0, -SQ_GAP)
    if ns.ExtraWidenMenu then ns.ExtraWidenMenu(menu, diffBtn, SQ_GAP, refreshBtn or diffBtn) end
    menu:Show()
    PaintMenu()
end

-------------------------------------------------------------------------------
-- buttons
-------------------------------------------------------------------------------
-- button in the skin's look (WSkin.button).
local function SkinnedButton(parent, w, h, keepKeys, decorate)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b:SetNormalFontObject("GameFontHighlight")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontDisable")
    b:SetText(" ")
    if decorate then decorate(b) end
    local S = Skin()
    if S and S.Button then
        S.Button(b, keepKeys)
    else
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CM.MakeBorder(b, 0.25, 0.25, 0.25, 1, CM.PanelPP)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
    end
    return b
end

local function DropButton(parent, w, h)
    local b = SkinnedButton(parent, w, h, { "Arrow" }, function(btn)
        btn.Arrow = btn:CreateTexture(nil, "OVERLAY")
        btn.Arrow:SetAtlas("Azerite-PointingArrow")
        btn.Arrow:SetDesaturated(true)
        btn.Arrow:SetVertexColor(1, 1, 1, 0.8)
        btn.Arrow:SetSize(11, 8)
        btn.Arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    end)
    local fs = b:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", b, "LEFT", 9, 0)
    fs:SetPoint("RIGHT", b.Arrow, "LEFT", -4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    b.label = fs
    return b
end

-- square glyph button; atlas = true means tex is an atlas.
local function GlyphButton(parent, size, tex, atlas)
    return SkinnedButton(parent, size, size, { "Glyph" }, function(btn)
        btn:SetText("")
        btn.Glyph = btn:CreateTexture(nil, "OVERLAY")
        if atlas then
            btn.Glyph:SetAtlas(tex, false)
            btn.Glyph:SetDesaturated(true)
        else
            btn.Glyph:SetTexture(tex)
        end
        btn.Glyph:SetPoint("CENTER")
        btn.Glyph:SetAlpha(0.8)
    end)
end

-- blizzard's cancel x restyled, its button still gets the click
function XF.CancelLook(entry)
    local cb = entry and entry.CancelButton
    if type(cb) ~= "table" or not cb.GetRegions then return end
    local d = FFD[cb]
    if not d then
        d = {}
        FFD[cb] = d
        for _, r in ipairs({ cb:GetRegions() }) do r:SetAlpha(0) end
        local hl = cb.GetHighlightTexture and cb:GetHighlightTexture()
        if hl then hl:SetAlpha(0) end
        local look = GlyphButton(cb, ROW1_H - 4, X_TEX)
        look:EnableMouse(false)
        look:SetPoint("CENTER", cb, "CENTER", 0, 0)
        look:SetFrameLevel(cb:GetFrameLevel() + 1)
        look.Glyph:SetSize(11, 11)
        look.Glyph:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH, 1)
        d.look = look
        cb:HookScript("OnEnter", function(self)
            if not self:IsEnabled() then return end
            SetBorderColor(d.look, 1, 0.15, 0.15, 1)
            d.look.Glyph:SetVertexColor(1, 0.15, 0.15, 1)
            d.look.Glyph:SetAlpha(1)
        end)
        cb:HookScript("OnLeave", function(self)
            SetBorderColor(d.look, ThemeBorder())
            d.look.Glyph:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH, 1)
            d.look.Glyph:SetAlpha(self:IsEnabled() and 0.8 or 0.35)
        end)
    end
    d.look.Glyph:SetAlpha(cb:IsEnabled() and 0.8 or 0.35)
end

ns.GlyphButton = GlyphButton
ns.GLYPH = XF.GLYPH
ns.Redecorate = XF.Redecorate  -- for the settings page

local function SquareEnter(self)
    local d = self.dungeon
    if not d then return end
    XF.Tip(self, d.name or "?", EllesmereUI.L("Click to toggle"))
end

-- dungeon square: a skinned button with the icon inset 1px.
local function MakeSquare(parent)
    local px = CM.PP.mult
    local b = SkinnedButton(parent, BTN, BTN, { "Icon" }, function(btn)
        btn:SetText("")
        btn.Icon = btn:CreateTexture(nil, "ARTWORK")
        btn.Icon:SetPoint("TOPLEFT", btn, "TOPLEFT", px, -px)
        btn.Icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -px, px)
        btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end)
    b.icon = b.Icon
    b:SetScript("OnEnter", SquareEnter)
    b:SetScript("OnLeave", XF.Untip)
    b:SetScript("OnClick", function(self)
        if self.dungeon then ToggleDungeon(self.dungeon.groupID) end
        if XF.tipOwner == self then SquareEnter(self) end
    end)
    return b
end

local function DelveEnter(self)
    local d = self.delve
    if not d then return end
    XF.Tip(self, d.name or "?", bountiful[d.name] and (XF.GOLD_HEX .. EllesmereUI.L("Bountiful today") .. "|r") or nil,
        EllesmereUI.L("Click to toggle"))
end

-- delve square: same button with the short name.
local function MakeDelveSquare(parent)
    local b = SkinnedButton(parent, BTN, BTN, nil, function(btn) btn:SetText("") end)
    local fs = b:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("CENTER")
    fs:SetWordWrap(false)
    local function Layer(level)
        local f = CreateFrame("Frame", nil, b)
        f:SetAllPoints(b)
        f:SetFrameLevel(b:GetFrameLevel() + level)
        f:EnableMouse(false)
        return f
    end
    b.gold = Layer(2)
    b.edge = Layer(3)
    local line = b.gold:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -1)
    line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -1)
    line:SetHeight(2)
    local r, g, bl, a = ThemeBorder()
    CM.PanelPP.CreateBorder(b.edge, r, g, bl, a, 1, "OVERLAY", 7)
    b.gold:Hide()
    b:SetScript("OnEnter", DelveEnter)
    b:SetScript("OnLeave", XF.Untip)
    b:SetScript("OnClick", function(self)
        local d = self.delve
        if not d then return end
        local c = Cfg()
        if type(c.delves) ~= "table" then c.delves = {} end
        c.delves[d.groupID] = (not c.delves[d.groupID]) or nil
        local n = 0
        for _, o in ipairs(delves or {}) do if c.delves[o.groupID] then n = n + 1 end end
        if n == #(delves or {}) then wipe(c.delves) end
        Refilter()
        Paint()
        if XF.tipOwner == self then DelveEnter(self) end
    end)
    return b
end

-- grid slot i after the reset, right-aligned, wrapping.
local function PlaceGrid(list, i, size, after, cols, slots)
    local sq = list[i]
    sq:SetSize(size, size)
    sq:ClearAllPoints()
    if i == 1 then
        sq:SetPoint("LEFT", after, "RIGHT", SQ_GAP + (slots - cols) * (size + SQ_GAP), 0)
    elseif (i - 1) % cols == 0 then
        sq:SetPoint("TOPLEFT", list[i - cols], "BOTTOMLEFT", 0, -SQ_GAP)
    else
        sq:SetPoint("LEFT", list[i - 1], "RIGHT", SQ_GAP, 0)
    end
    sq:Show()
end

local function LayoutDelves(size, after, show, cols, slots)
    local list = delves or {}
    local font = gfFont or "GameFontHighlight"
    -- one scrolling line, like the raid bosses
    if ns.ExtraDelveStrip then
        ns.GFDressDelve = function(sq, d)
            sq:SetNormalFontObject(font)
            sq:SetHighlightFontObject(font)
            sq:SetText(d.abbr)
        end
        return ns.ExtraDelveStrip(list, delveSquares, function() return MakeDelveSquare(row) end,
            size, after, show, cols, slots, row, SQ_GAP, function() Paint() end)
    end
    for i = 1, math.max(#list, #delveSquares) do
        local d = list[i]
        local sq = delveSquares[i]
        if d and show then
            if not sq then sq = MakeDelveSquare(row); delveSquares[i] = sq end
            sq.delve = d
            sq:SetNormalFontObject(font)
            sq:SetHighlightFontObject(font)
            sq:SetText(d.abbr)
            PlaceGrid(delveSquares, i, size, after, cols, slots)
        elseif sq then
            sq.delve = nil
            sq:Hide()
        end
    end
    return (show and #list > 0) and math.ceil(#list / cols) or 1
end

local function BossEnter(self)
    local b = self.boss
    if not b then return end
    local pick = Cfg().bosses
    pick = type(pick) == "table" and pick[b.key]
    XF.Tip(self, b.name or "?", b.raidName,
        pick == "dead" and EllesmereUI.L("Groups with this boss dead")
        or pick and EllesmereUI.L("Groups with this boss alive")
        or EllesmereUI.L("Click to filter by this boss"))
end

-- boss pick: one list under the clicked square, as wide as it
local BOSS_PICKS = {
    { value = true, tex = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\eui-heart.png", tip = EllesmereUI.L("Boss Alive"), r = 0.2, g = 1, b = 0.3 },
    { value = "dead", tex = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\eui-skull.png", tip = EllesmereUI.L("Boss Dead"), r = 1, g = 0.15, b = 0.15 },
    { tex = X_TEX, tip = EllesmereUI.L("No Filter"), r = 0.6, g = 0.6, b = 0.6 },
}
local bossPick

local function BossPickList()
    if bossPick then return bossPick end
    local list = CreateFrame("Frame", nil, SP)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(330)
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    local bg = list:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    CM.MakeBorder(list, ThemeBorder())
    list.rows = {}
    for i, p in ipairs(BOSS_PICKS) do
        local it = CreateFrame("Button", nil, list)
        it.Icon = it:CreateTexture(nil, "ARTWORK")
        it.Icon:SetTexture(p.tex)
        it.Icon:SetPoint("CENTER")
        it.Icon:SetVertexColor(p.r, p.g, p.b)
        it.cur = it:CreateTexture(nil, "BACKGROUND")
        it.cur:SetAllPoints()
        it.cur:SetColorTexture(1, 1, 1, 0.12)
        local hl = it:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A or 0.08)
        it:SetScript("OnEnter", function(self) XF.Tip(self, p.tip) end)
        it:SetScript("OnLeave", XF.Untip)
        it:SetScript("OnClick", function()
            local d = list.owner and list.owner.boss
            list:Hide()
            if not d then return end
            local c = Cfg()
            if type(c.bosses) ~= "table" then c.bosses = {} end
            c.bosses[d.key] = p.value
            Refilter()
            Paint()
        end)
        list.rows[i] = it
    end
    XF.ClickOff(list, function(self)
        return self:IsMouseOver() or (self.owner and self.owner:IsMouseOver())
    end)
    list:SetScript("OnHide", XF.Untip)
    list:Hide()
    bossPick = list
    -- a strip that scrolls takes the square away from its list
    ns.ExtraHideBossPick = function() list:Hide() end
    return list
end

local function OpenBossPick(sq)
    local list = BossPickList()
    if list:IsShown() and list.owner == sq then list:Hide() return end
    XF.Untip()
    list.owner = sq
    local w = sq:GetWidth()
    local icon = math.floor(w * 0.6 + 0.5)
    local c = Cfg()
    local cur = type(c.bosses) == "table" and sq.boss and c.bosses[sq.boss.key] or nil
    for i, it in ipairs(list.rows) do
        it:SetSize(w, w)
        it:ClearAllPoints()
        it:SetPoint("TOP", list, "TOP", 0, -(i - 1) * w)
        it.Icon:SetSize(icon, icon)
        -- a light wash behind the current pick
        it.cur:SetShown(BOSS_PICKS[i].value == cur)
    end
    list:SetSize(w, w * #BOSS_PICKS)
    list:ClearAllPoints()
    list:SetPoint("TOP", sq, "BOTTOM", 0, -2)
    list:Show()
end

-- boss square with the journal portrait cropped to the middle.
local function MakeBossSquare(parent)
    local b = MakeSquare(parent)
    b.icon:SetTexCoord(0.25, 0.75, 0, 1)
    b:SetScript("OnEnter", BossEnter)
    b:SetScript("OnClick", function(self)
        if self.boss then OpenBossPick(self) end
    end)
    return b
end

local function LayoutBosses(size, after, show, cols, slots)
    local list = {}
    for _, b in ipairs(bosses or {}) do
        if RaidShown(b.raid) then list[#list + 1] = b end
    end
    -- one scrolling line instead of a grid
    if ns.ExtraBossStrip then
        return ns.ExtraBossStrip(list, bossSquares, function() return MakeBossSquare(row) end,
            size, after, show, cols, slots, row, SQ_GAP, function() Paint() end)
    end
    for i = 1, math.max(#list, #bossSquares) do
        local d = list[i]
        local sq = bossSquares[i]
        if d and show then
            if not sq then sq = MakeBossSquare(row); bossSquares[i] = sq end
            sq.boss = d
            sq.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            PlaceGrid(bossSquares, i, size, after, cols, slots)
        elseif sq then
            sq.boss = nil
            sq:Hide()
        end
    end
    return (show and #list > 0) and math.ceil(#list / cols) or 1
end

-- raid menu (map button): a toggle per current raid.
local function BuildRaidMenu()
    raidMenu = CreateFrame("Frame", nil, SP)
    raidMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    raidMenu:EnableMouse(true)
    raidMenu:SetFrameLevel(300)
    raidMenu:SetClampedToScreen(true)
    raidMenu:SetWidth(190)
    local bg = raidMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local S = Skin()
    if S and S.AddBorder then S.AddBorder(raidMenu) else CM.MakeBorder(raidMenu, ThemeBorder()) end
    raidMenu.items = {}
    local y = 3
    -- current season only, older raids dimmed and out
    raidMenu.items.season = MenuItem(raidMenu, y, EllesmereUI.L("Current Season Only"), function()
        local c = Cfg()
        c.extraSeasonRaids = not XF.SeasonOnly()
        if type(c.bosses) == "table" then
            for _, bo in ipairs(bosses or {}) do
                if not RaidShown(bo.raid) then c.bosses[bo.key] = nil end
            end
        end
        ns.Search_Layout()
        Refilter()
    end)
    y = y + ITEM_H
    local sdiv = raidMenu:CreateTexture(nil, "ARTWORK")
    sdiv:SetHeight(1)
    sdiv:SetColorTexture(1, 1, 1, 0.10)
    sdiv:SetPoint("TOPLEFT", raidMenu, "TOPLEFT", 1, -y - 3)
    sdiv:SetPoint("TOPRIGHT", raidMenu, "TOPRIGHT", -1, -y - 3)
    y = y + 7
    for _, raid in ipairs(raidList or {}) do
        local jid = raid.jid
        raidMenu.items[jid] = MenuItem(raidMenu, y, raid.name, function()
            local c = Cfg()
            if type(c.raidsHidden) ~= "table" then c.raidsHidden = {} end
            if RaidShown(jid) then
                -- keep at least one raid ticked.
                local shown = 0
                for _, o in ipairs(raidList or {}) do if RaidShown(o.jid) then shown = shown + 1 end end
                if shown <= 1 then return end
            end
            c.raidsHidden[jid] = (not c.raidsHidden[jid]) or nil
            if c.raidsHidden[jid] and type(c.bosses) == "table" then
                for _, bo in ipairs(bosses or {}) do
                    if bo.raid == jid then c.bosses[bo.key] = nil end
                end
            end
            ns.Search_Layout()
            Refilter()
        end)
        y = y + ITEM_H
    end
    local div = raidMenu:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOPLEFT", raidMenu, "TOPLEFT", 1, -y - 3)
    div:SetPoint("TOPRIGHT", raidMenu, "TOPRIGHT", -1, -y - 3)
    y = y + 7
    raidMenu.items.worldBosses = MenuItem(raidMenu, y, EllesmereUI.L("World Bosses"), function()
        local c = Cfg()
        c.hideWorldBosses = (not c.hideWorldBosses) or nil
        Refilter()
        Paint()
    end)
    y = y + ITEM_H
    raidMenu:SetHeight(y + 3)
    XF.ClickOff(raidMenu, function(m)
        return m:IsMouseOver() or (raidBtn and raidBtn:IsMouseOver())
    end)
    raidMenu:Hide()
end

local function PaintRaidMenu()
    if not (raidMenu and raidMenu:IsShown()) then return end
    for _, raid in ipairs(raidList or {}) do
        local item = raidMenu.items[raid.jid]
        if item then
            item:SetChecked(RaidShown(raid.jid))
            item:SetDimmed(not XF.RaidEligible(raid.jid))
        end
    end
    if raidMenu.items.season then raidMenu.items.season:SetChecked(XF.SeasonOnly()) end
    if raidMenu.items.worldBosses then raidMenu.items.worldBosses:SetChecked(not HideWorldBosses()) end
end

local function ToggleRaidMenu()
    if not raidMenu then BuildRaidMenu() end
    if raidMenu:IsShown() then raidMenu:Hide(); return end
    raidMenu:ClearAllPoints()
    raidMenu:SetPoint("TOPLEFT", raidBtn, "BOTTOMLEFT", 0, -SQ_GAP)
    raidMenu:Show()
    PaintRaidMenu()
end

-- tier menu: all + tiers, applies right away.
local function BuildTierMenu()
    tierMenu = CreateFrame("Frame", nil, SP)
    tierMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    tierMenu:EnableMouse(true)
    tierMenu:SetFrameLevel(300)
    tierMenu:SetClampedToScreen(true)
    local bg = tierMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local r, g, b = ThemeFill()
    bg:SetColorTexture(r, g, b, 0.98)
    local S = Skin()
    if S and S.AddBorder then S.AddBorder(tierMenu) else CM.MakeBorder(tierMenu, ThemeBorder()) end
    local function Tiers()
        local c = Cfg()
        if type(c.delveTiers) ~= "table" then c.delveTiers = {} end
        return c.delveTiers
    end
    tierMenu.items = {}
    local y = 3
    tierMenu.items.all = MenuItem(tierMenu, y, ALL or "All", function()
        wipe(Tiers())
        Refilter()
        Paint()
    end)
    y = y + ITEM_H
    local div = tierMenu:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOPLEFT", tierMenu, "TOPLEFT", 1, -y - 3)
    div:SetPoint("TOPRIGHT", tierMenu, "TOPRIGHT", -1, -y - 3)
    y = y + 7
    for tier = 1, MAX_TIER do
        tierMenu.items[tier] = MenuItem(tierMenu, y, XF.TierLabel(tier), function()
            local t = Tiers()
            t[tier] = (not t[tier]) or nil
            local _, n = ChosenTiers()
            if n == MAX_TIER then wipe(t) end
            Refilter()
            Paint()
        end)
        y = y + ITEM_H
    end
    tierMenu:SetHeight(y + 3)
    tierMenu:SetScript("OnShow", function() DimForMenu(true) end)
    tierMenu:SetScript("OnHide", function() DimForMenu(false) end)
    XF.ClickOff(tierMenu, function(m)
        return m:IsMouseOver() or (tierBtn and tierBtn:IsMouseOver())
    end)
    tierMenu:Hide()
end

local function PaintTierMenu()
    if not (tierMenu and tierMenu:IsShown()) then return end
    local chosen = ChosenTiers()
    tierMenu.items.all:SetChecked(chosen == nil)
    for tier = 1, MAX_TIER do
        tierMenu.items[tier]:SetChecked(chosen ~= nil and chosen[tier] == true)
    end
end

local function ToggleTierMenu()
    if not tierMenu then BuildTierMenu() end
    if tierMenu:IsShown() then tierMenu:Hide(); return end
    tierMenu:ClearAllPoints()
    tierMenu:SetPoint("TOPLEFT", tierBtn, "BOTTOMLEFT", 0, -SQ_GAP)
    tierMenu:SetPoint("TOPRIGHT", refreshBtn or tierBtn, "BOTTOMRIGHT", 0, -SQ_GAP)
    tierMenu:Show()
    PaintTierMenu()
end

local function BuildRow()
    row = CreateFrame("Frame", nil, SP)
    row:SetHeight(BTN)
    row:SetFrameLevel(SP:GetFrameLevel() + 5)
    diffBtn = DropButton(SP, DIFF_W, ROW1_H)
    diffBtn:SetFrameLevel(SP:GetFrameLevel() + 5)
    diffBtn:SetScript("OnClick", ToggleMenu)
    diffBtn:SetScript("OnHide", function()
        if menu then menu:Hide() end
        if raidDiffMenu then raidDiffMenu:Hide() end
    end)
    diffBtn:SetScript("OnLeave", XF.PaintLabel)
    tierBtn = DropButton(SP, DIFF_W, ROW1_H)
    tierBtn:SetFrameLevel(SP:GetFrameLevel() + 5)
    tierBtn:SetScript("OnClick", ToggleTierMenu)
    tierBtn:SetScript("OnHide", function() if tierMenu then tierMenu:Hide() end end)
    tierBtn:SetScript("OnLeave", XF.PaintLabel)
end

-- a drop button's label color from its last paint
function XF.PaintLabel(btn)
    if btn.active then btn.label:SetTextColor(Accent()) else btn.label:SetTextColor(1, 1, 1, 1) end
end

-- repaint the filter row
Paint = function()
    if not SP then return end
    local f = XF.GetFilter()
    if not f then return end
    if diffBtn then
        local active
        if SP.categoryID == RAIDS then
            active = ChosenRaidDiffs() or ChosenRaidPlaystyles() or ChosenRaidRoles()
        else
            active = not DiffAllOrNone(f) or DungeonPlaystyles(f) or DungeonRolesSet(f) or (f.minimumRating or 0) ~= 0
        end
        diffBtn.active = (active or RegionFilterActive() or XF.ExtraFilterActive()) and true or false
        -- green edge while a filter's on, same as the expressions button
        if not diffBtn.activeEdge then
            local edge = CreateFrame("Frame", nil, diffBtn)
            edge:SetAllPoints()
            edge:SetFrameLevel(diffBtn:GetFrameLevel() + 3)
            edge:EnableMouse(false)
            CM.MakeBorder(edge, 0.3, 0.85, 0.4, 1, CM.PanelPP)
            diffBtn.activeEdge = edge
        end
        diffBtn.activeEdge:SetShown(diffBtn.active)
        diffBtn:SetText(EllesmereUI.L("Filters"))
        XF.PaintLabel(diffBtn)
    end
    if tierBtn then
        local chosen, n = ChosenTiers()
        if chosen then
            local text = EllesmereUI.Lf("Tier (%d)", n)
            if n == 1 then for i = 1, MAX_TIER do if chosen[i] then text = XF.TierLabel(i) end end end
            tierBtn:SetText(text)
        else
            tierBtn:SetText(EllesmereUI.L("Tier"))
        end
        tierBtn.active = chosen ~= nil
        XF.PaintLabel(tierBtn)
    end
    local chosenDelves = ChosenDelves()
    for _, sq in ipairs(delveSquares) do
        if sq:IsShown() and sq.delve then
            local on = chosenDelves and chosenDelves[sq.delve.groupID] == true or false
            sq.on = on
            sq:GetFontString():SetAlpha(on and 1 or 0.4)
            if on then SetBorderColor(sq.edge, 1, 1, 1, 1) else SetBorderColor(sq.edge, ThemeBorder()) end
            sq.gold:SetShown(bountiful[sq.delve.name] == true)
        end
    end
    PaintTierMenu()
    PaintRaidMenu()
    if raidBtn then
        local hidden = false
        for _, raid in ipairs(raidList or XF.EMPTY) do if XF.RaidEligible(raid.jid) and not RaidShown(raid.jid) then hidden = true end end
        if HideWorldBosses() then hidden = true end
        if hidden then raidBtn.Glyph:SetVertexColor(Accent()) else raidBtn.Glyph:SetVertexColor(1, 1, 1) end
    end
    -- bosses: all coloured until one's picked, then the rest grey out.
    local chosenBosses = ChosenBosses()
    for _, sq in ipairs(bossSquares) do
        if sq:IsShown() and sq.boss then
            local pick = chosenBosses and chosenBosses[sq.boss.key]
            local on = pick and true or false
            sq.on = on
            sq.icon:SetDesaturated(chosenBosses ~= nil and not on)
            sq.icon:SetAlpha((chosenBosses == nil or on) and 1 or 0.45)
            -- green: alive, red: dead
            if pick == "dead" then SetBorderColor(sq, 1, 0.15, 0.15, 1)
            elseif on then SetBorderColor(sq, 0.2, 1, 0.3, 1)
            else SetBorderColor(sq, ThemeBorder()) end
        end
    end
    local def = DungeonsDefault(f)
    for _, sq in ipairs(squares) do
        if sq:IsShown() and sq.dungeon then
            local on = not def and Contains(f.activities, sq.dungeon.groupID) ~= nil
            sq.on = on
            sq.icon:SetDesaturated(not def and not on)
            sq.icon:SetAlpha((def or on) and 1 or 0.45)
            if on then SetBorderColor(sq, 1, 1, 1, 1) else SetBorderColor(sq, ThemeBorder()) end
        end
    end
    local filter = SP.FilterButton
    local fd = filter and FFD[filter]
    if fd then
        local cb = filter.isDefaultCallback
        local isDefault = true
        if cb then
            local ok, v = pcall(cb)
            isDefault = (not ok) or (v and true or false)
        end
        if XF.DimActive() then isDefault = false end
        if RegionFilterActive() or DelveFilterActive() or BossFilterActive() or (ChosenRaidDiffs() or ChosenRaidPlaystyles() or ChosenRaidRoles()) and SP.categoryID == RAIDS or XF.ExtraFilterActive() then isDefault = false end
        if resetBtn then
            resetBtn.active = not isDefault
            resetBtn.Glyph:SetAlpha(isDefault and 0.35 or 0.9)
        end
    end
    PaintMenu()
end

-- search again glyph: dim on cooldown, accent when filters changed.
PaintRefresh = function()
    if not refreshBtn then return end
    if refreshBtn.cover then refreshBtn.cover:SetShown(GetTime() < cdUntil) end
    local g = refreshBtn.Glyph
    if GetTime() < cdUntil then
        g:SetVertexColor(1, 1, 1)
        g:SetAlpha(0.3)
    elseif pending then
        g:SetVertexColor(Accent())
        g:SetAlpha(1)
    else
        g:SetVertexColor(1, 1, 1)
        g:SetAlpha(refreshBtn.hover and 1 or 0.8)
    end
end

local function StartCooldown(sec)
    local now = GetTime()
    if now + sec <= cdUntil then return end
    cdUntil = now + sec
    if refreshBtn and refreshBtn.cd then refreshBtn.cd:SetCooldown(now, sec) end
    PaintRefresh()
    C_Timer.After(sec, PaintRefresh)
end

-------------------------------------------------------------------------------
-- layout
-------------------------------------------------------------------------------
-- the group settings button as seen
function XF.FilterFace()
    local f = SP and SP.FilterButton
    local d = f and FFD[f]
    return d and d.face or f
end
ns.GFFilterFace = XF.FilterFace

-- blizzard's filter dropdown becomes our cog.
local function CogFilterButton(btn)
    if not btn or FFD[btn] then return end
    local d = { size = BTN }
    FFD[btn] = d
    if btn.Text then btn.Text:SetAlpha(0) end
    if btn.Background then btn.Background:SetAlpha(0) end
    -- our own fixed-size face. blizzard's button grows with its text and
    -- only shrinks out of combat, so the row anchors to this
    btn:SetAlpha(0)
    d.face = SkinnedButton(SP, BTN, BTN)
    d.face:EnableMouse(false)  -- the catcher takes clicks
    d.face:SetFrameLevel(row:GetFrameLevel() + 3)
    d.cogFrame = CreateFrame("Frame", nil, d.face)
    d.cogFrame:SetAllPoints(d.face)
    d.cogFrame:SetFrameLevel(d.face:GetFrameLevel() + 3)
    d.cogFrame:EnableMouse(false)
    d.cog = d.cogFrame:CreateTexture(nil, "OVERLAY")
    if ns.ExtraPersonTex then d.cog:SetTexture(ns.ExtraPersonTex) else d.cog:SetAtlas(XF.PERSON_ATLAS, false) end
    d.cog:SetDesaturated(true)
    d.cog:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH)
    d.cog:SetPoint("CENTER")
    d.cog:SetAlpha(0.8)
    if btn.ResetButton then
        btn.ResetButton:SetAlpha(0)
        btn.ResetButton:EnableMouse(false)
    end
    -- blizzard resizes it with its text; size it back (after combat if in it).
    hooksecurefunc(btn, "UpdateText", function(self)
        local fd = FFD[self]
        if not fd then return end
        if InCombatLockdown() then XF.Defer("layout", XF.Layout) return end
        self:SetSize(fd.size, fd.size)
    end)
    -- opens our group settings menu: a click catcher sits over it
    btn:EnableMouse(false)
    local catcher = CreateFrame("Button", nil, row)
    catcher:SetAllPoints(d.face)
    catcher:SetFrameLevel(d.face:GetFrameLevel() + 6)
    local wash = catcher:CreateTexture(nil, "HIGHLIGHT")
    wash:SetAllPoints()
    wash:SetColorTexture(1, 1, 1, 0.1)
    catcher:SetScript("OnEnter", function(self)
        d.cog:SetAlpha(1)
        XF.Tip(self, EllesmereUI.L("Group Settings"))
    end)
    catcher:SetScript("OnLeave", function()
        d.cog:SetAlpha(0.8)
        XF.Untip()
    end)
    catcher:SetScript("OnClick", function(self)
        XF.Untip()
        XF.ToggleGroupMenu(self)
    end)
    catcher:SetScript("OnHide", function() if XF.groupMenu then XF.groupMenu:Hide() end end)
    d.catcher = catcher

    -- reset uses blizzard's own defaults.
    resetBtn = GlyphButton(row, BTN, X_TEX)
    resetBtn.Glyph:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH)
    resetBtn:SetScript("OnClick", function()
        local f = XF.GetFilter()
        f.needsTank, f.needsHealer, f.needsDamage, f.needsMyClass = false, false, false, false
        f.hasTank, f.hasHealer = false, false
        f.minimumRating = 0
        Cfg().ratingOn = nil
        for i = 1, 4 do f["generalPlaystyle" .. i] = true end
        for _, d in ipairs(DIFFS) do f[d.key] = true end
        f.activities = AllDungeonGroups()
        local c = Cfg()
        if type(c.regions) == "table" then wipe(c.regions) end
        if type(c.delves) == "table" then wipe(c.delves) end
        if type(c.delveTiers) == "table" then wipe(c.delveTiers) end
        if type(c.bosses) == "table" then wipe(c.bosses) end
        if type(c.raidDiffs) == "table" then wipe(c.raidDiffs) end
        if type(c.raidPlaystyles) == "table" then wipe(c.raidPlaystyles) end
        if type(c.raidRoles) == "table" then wipe(c.raidRoles) end
        c.partyFit, c.notDeclined, c.hasLust, c.hasBrez = nil, nil, nil, nil
        c.extraMyClass = nil
        if ns.ExtraExprReset then ns.ExtraExprReset() end
        if type(c.roleCounts) == "table" then wipe(c.roleCounts) end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Apply(f)
        Refilter()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self.Glyph:SetAlpha(1)
        XF.Tip(self, EllesmereUI.L("Reset Filters"), not self.active and EllesmereUI.L("No filters set") or nil)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        XF.Untip()
        self.Glyph:SetAlpha(self.active and 0.9 or 0.35)
    end)
end

-- short dungeon name ('Altar of Fangs' -> AoF)
XF.SMALL_WORDS = { of = true, the = true, ["and"] = true, to = true, ["in"] = true, on = true, at = true }
function XF.Abbr(name)
    if type(name) ~= "string" then return "" end
    name = name:match("^([^,:]+)") or name
    local out = {}
    for word in name:gmatch("[^%s%-]+") do
        local w = word:gsub("[^%a]", "")
        if w ~= "" then
            local c = w:sub(1, 1)
            if #out > 0 and XF.SMALL_WORDS[w:lower()] then c = c:lower() else c = c:upper() end
            out[#out + 1] = c
        end
    end
    local abbr = table.concat(out)
    if abbr == "" then abbr = Abbrev(name) end
    if abbr == "" then abbr = name end
    local ov = EllesmereUI._dungeonAbbrevOverride
    if ov and ov[abbr] then abbr = ov[abbr] end
    return abbr
end

-- the season's portal label when it's a seasonal dungeon, else initials
local portalShort, portalsDone
function XF.ShortName(name)
    if type(name) ~= "string" or IsSecret(name) then return "" end
    if not portalsDone then
        -- dungeon names can be missing right after login, so keep asking until they're all in
        portalShort, portalsDone = {}, true
        for _, e in ipairs(EllesmereUI.SEASON_PORTALS or XF.EMPTY) do
            for _, n in ipairs(e.names) do portalShort[n] = e.short end
            local localized = GetLFGDungeonInfo and GetLFGDungeonInfo(e.dungeonID)
            if type(localized) == "string" then
                portalShort[localized:lower()] = e.short
            else
                portalsDone = false
            end
        end
    end
    local base = name:gsub("%s*%b()", "")
    local short = portalShort[base:lower()]
    return short and EllesmereUI.L(short) or XF.Abbr(base)
end
ns.GFShortName = XF.ShortName

-- text layer over a square, above its border
function XF.SquareOverlay(sq)
    local f = sq.overlay
    if not f then
        f = CreateFrame("Frame", nil, sq)
        f:SetAllPoints(sq)
        f:SetFrameLevel(sq:GetFrameLevel() + 3)
        f:EnableMouse(false)
        sq.overlay = f
    end
    return f
end

-- short name on a square: at the top when keystone level shows too
function XF.SquareAbbr(sq, d, size)
    local on = Cfg().dungeonAbbr == true and d ~= nil
    if on and not sq.abbr then
        sq.abbr = XF.SquareOverlay(sq):CreateFontString(nil, "OVERLAY")
        sq.abbr:SetJustifyH("CENTER")
        sq.abbr:SetWordWrap(false)
    end
    if not sq.abbr then return end
    if on then
        sq.abbr:ClearAllPoints()
        if Cfg().dungeonScore == true then
            sq.abbr:SetPoint("TOPLEFT", sq, "TOPLEFT", -4, -2)
            sq.abbr:SetPoint("TOPRIGHT", sq, "TOPRIGHT", 4, -2)
            sq.abbr:SetJustifyV("TOP")
        else
            sq.abbr:SetPoint("LEFT", sq, "LEFT", -4, 0)
            sq.abbr:SetPoint("RIGHT", sq, "RIGHT", 4, 0)
            sq.abbr:SetJustifyV("MIDDLE")
        end
        local fs = math.max(8, math.floor(size * 0.36))
        XF.Font(sq.abbr, fs, "OUTLINE")
        sq.abbr:SetText(XF.ShortName(d.name))
        while fs > 8 and ((sq.abbr.GetUnboundedStringWidth and sq.abbr:GetUnboundedStringWidth()) or 0) > size - 4 do
            fs = fs - 1
            XF.Font(sq.abbr, fs, "OUTLINE")
        end
        sq.abbr:SetTextColor(1, 1, 1, 1)
    end
    sq.abbr:SetShown(on)
end

-- best keystone level on a square, colored by its score
function XF.SquareScore(sq, d, size)
    local best
    if Cfg().dungeonScore == true and d ~= nil then
        local intime, overtime = C_MythicPlus.GetSeasonBestForMap(d.cmID)
        best = intime
        if overtime and (not best or overtime.dungeonScore >= best.dungeonScore) then best = overtime end
        if best and best.level <= 0 then best = nil end
    end
    if best and not sq.score then
        sq.score = XF.SquareOverlay(sq):CreateFontString(nil, "OVERLAY")
        sq.score:SetWordWrap(false)
    end
    local fs = sq.score
    if not fs then return end
    if best then
        local _, overall = C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(d.cmID)
        local color = C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor(overall or best.dungeonScore)
        XF.Font(fs, math.max(8, math.floor(size * 0.42)), "")
        fs:ClearAllPoints()
        if Cfg().dungeonAbbr == true then
            fs:SetPoint("BOTTOM", sq, "BOTTOM", 0, 2)
        else
            fs:SetPoint("CENTER", sq, "CENTER", 0, 0)
        end
        fs:SetText(best.level)
        if color then fs:SetTextColor(color.r, color.g, color.b, 1) else fs:SetTextColor(1, 1, 1, 1) end
    end
    fs:SetShown(best ~= nil)
end

local function LayoutSquares(size, after, show)
    local list = dungeons or {}
    local prev = after
    for i = 1, math.max(#list, #squares) do
        local d = list[i]
        local sq = squares[i]
        if d and show then
            if not sq then sq = MakeSquare(row); squares[i] = sq end
            sq.dungeon = d
            sq:SetSize(size, size)
            sq:ClearAllPoints()
            sq:SetPoint("LEFT", prev, "RIGHT", SQ_GAP, 0)
            sq.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            XF.SquareScore(sq, d, size)
            XF.SquareAbbr(sq, d, size)
            sq:Show()
            prev = sq
        elseif sq then
            sq.dungeon = nil
            sq:Hide()
        end
    end
end

-- back / sign up's font, a size smaller
function XF.ButtonFont()
    local src = SP and (SP.BackButton or SP.SignUpButton)
    local fs = src and src.GetFontString and src:GetFontString()
    local path, size, flags
    if fs then path, size, flags = fs:GetFont() end
    if not path then return nil end
    if not gfFont then gfFont = CreateFont("EUIGroupFinderButtonFont") end
    gfFont:SetFont(path, math.max(8, size - 1), flags or "")
    gfFont:SetTextColor(1, 1, 1)
    return gfFont
end

local function MatchButtonFont(box)
    if not XF.ButtonFont() then return end
    diffBtn:SetNormalFontObject(gfFont)
    diffBtn:SetHighlightFontObject(gfFont)
    tierBtn:SetNormalFontObject(gfFont)
    tierBtn:SetHighlightFontObject(gfFont)
    if box then
        box:SetFontObject(gfFont)
        if box.Instructions then
            box.Instructions:SetFontObject(gfFont)
            box.Instructions:SetTextColor(0.4, 0.4, 0.4)
        end
    end
end

-- row positions, for the applications card.
function ns.Search_Rows()
    local pad = tonumber(Cfg().padding) or 12
    local w = SP and SP:GetWidth()
    if not w or w < 100 then w = 338 end
    local list = XF.Dungeons()
    local n = (list and #list > 0) and #list or 8
    return ROW1_Y, ROW2_Y, math.max(18, (w - pad * 2 - (n + 1) * SQ_GAP) / (n + 2)), ROW1_H
end

-- lays the panel out. blizzard's frames only move out of combat
local function Layout()
    if not (SP and SP:IsVisible()) then return end
    if InCombatLockdown() then XF.Defer("layout", XF.Layout); Paint(); return end
    XF.NewPass()
    local c = Cfg()
    local pad = tonumber(c.padding) or 12
    local showFilters = SP.categoryID == DUNGEONS
    local showDiff = SP.categoryID == DUNGEONS or SP.categoryID == RAIDS
    local showDelves = SP.categoryID == DELVES
    local showBosses = RaidsCurrent()
    if not row then BuildRow() end
    local list = XF.Dungeons()
    if showDelves then
        if not delves then delves, delveByActivity = BuildDelves() end
        ScanBountiful()
    end
    if showBosses and not bosses then bosses, raidByActivity, raidList = BuildBosses() end

    -- one square size that fills row 2 exactly.
    local rowW = (SP:GetWidth() or 338) - pad * 2
    local n = (list and #list > 0) and #list or 8
    local size = math.max(18, (rowW - (n + 1) * SQ_GAP) / (n + 2))

    -- row 1: search box, filters, search again.
    local filter, box, title = SP.FilterButton, SP.SearchBox, SP.CategoryName
    if title then title:SetAlpha(0) end
    if not refreshBtn then
        local blz = SP.RefreshButton
        refreshBtn = GlyphButton(SP, ROW1_H, "UI-RefreshButton", true)
        refreshBtn:SetFrameLevel(SP:GetFrameLevel() + 5)
        refreshBtn:EnableMouse(false)  -- blizzard's button underneath takes the click
        refreshBtn.Glyph:SetSize(14, 14)
        local px = CM.PP.mult
        local cd = CreateFrame("Cooldown", nil, refreshBtn, "CooldownFrameTemplate")
        cd:SetPoint("TOPLEFT", refreshBtn, "TOPLEFT", px, -px)
        cd:SetPoint("BOTTOMRIGHT", refreshBtn, "BOTTOMRIGHT", -px, px)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.65) end
        refreshBtn.cd = cd
        local function Tip(owner)
            refreshBtn.hover = true
            refreshBtn:LockHighlight()
            PaintRefresh()
            XF.Tip(owner, LFG_LIST_SEARCH_AGAIN or "Search Again",
                EllesmereUI.Lf("Limited to every %d seconds to prevent lock-out", CD_SEARCH),
                pending and EllesmereUI.L("Filters changed: search to update the list") or nil)
        end
        local function Untip()
            refreshBtn.hover = nil
            refreshBtn:UnlockHighlight()
            PaintRefresh()
            XF.Untip()
        end
        if blz then
            blz:SetAlpha(0)
            blz:HookScript("OnEnter", Tip)
            blz:HookScript("OnLeave", Untip)
        end
        local cover = CreateFrame("Button", nil, SP)
        cover:SetAllPoints(refreshBtn)
        cover:SetFrameLevel(refreshBtn:GetFrameLevel() + 8)
        cover:SetScript("OnEnter", Tip)
        cover:SetScript("OnLeave", Untip)
        cover:Hide()
        refreshBtn.cover = cover
        PaintRefresh()
    end
    refreshBtn:ClearAllPoints()
    refreshBtn:SetPoint("RIGHT", SP, "TOPRIGHT", -pad, ROW1_Y)
    local blzRefresh = SP.RefreshButton
    if blzRefresh then
        blzRefresh:ClearAllPoints()
        blzRefresh:SetAllPoints(refreshBtn)
        blzRefresh:SetFrameLevel(refreshBtn:GetFrameLevel() + 4)
    end
    -- a button left of refresh; row 1 ends at it
    local row1End = refreshBtn
    if ns.ExtraExprButton then
        row1End = ns.ExtraExprButton(SP, refreshBtn, SP.categoryID == DUNGEONS or SP.categoryID == RAIDS,
            { GlyphButton = GlyphButton, ROW1_H = ROW1_H, GAP = SQ_GAP, Refilter = Refilter, Tip = XF.Tip,
              Untip = XF.Untip, ClickOff = XF.ClickOff, Font = XF.Font, ThemeFill = ThemeFill,
              ThemeBorder = ThemeBorder, Accent = Accent, GLYPH = XF.GLYPH, Dim = DimForMenu,
              Filters = diffBtn, DIM_ALPHA = XF.DIM_ALPHA,
              FiltersOpen = function() return (menu and menu:IsShown()) or (raidDiffMenu and raidDiffMenu:IsShown()) or false end }) or refreshBtn
    end
    diffBtn:ClearAllPoints()
    diffBtn:SetPoint("RIGHT", row1End, "LEFT", -SQ_GAP, 0)
    diffBtn:SetShown(showDiff)
    if not showDiff or SP.categoryID ~= RAIDS then if raidDiffMenu then raidDiffMenu:Hide() end end
    if SP.categoryID ~= DUNGEONS and menu then menu:Hide() end
    tierBtn:ClearAllPoints()
    tierBtn:SetPoint("RIGHT", row1End, "LEFT", -SQ_GAP, 0)
    tierBtn:SetShown(showDelves)
    if box then
        box:ClearAllPoints()
        box:SetPoint("LEFT", SP, "TOPLEFT", pad, ROW1_Y)
        box:SetPoint("RIGHT", (showDiff and diffBtn) or (showDelves and tierBtn) or row1End, "LEFT", -SQ_GAP, 0)
        box:SetHeight(ROW1_H)
        SetBorderColor(box, ThemeBorder())
        -- shorter prompt (runs after blizzard sets its own).
        if box.Instructions then box.Instructions:SetText(EllesmereUI.Lf("%s (e.g. 10-12)", SEARCH or "Search")) end
    end
    MatchButtonFont(box)

    -- row 2: cog, reset, dungeon squares.
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", SP, "TOPLEFT", pad, ROW2_Y)
    row:SetPoint("TOPRIGHT", SP, "TOPRIGHT", -pad, ROW2_Y)
    row:SetHeight(size)
    row:Show()
    if filter then
        CogFilterButton(filter)
        local fd = FFD[filter]
        fd.size = size
        fd.cog:SetSize(math.floor(size * 0.55), math.floor(size * 0.55))
        filter:SetSize(size, size)
        filter:ClearAllPoints()
        filter:SetPoint("LEFT", row, "LEFT", 0, 0)
        fd.face:SetSize(size, size)
        fd.face:ClearAllPoints()
        fd.face:SetPoint("LEFT", row, "LEFT", 0, 0)
        fd.face:Show()
        filter = fd.face  -- the row anchors to our face from here
    end
    if resetBtn then
        resetBtn:SetSize(size, size)
        resetBtn.Glyph:SetSize(math.floor(size * 0.5), math.floor(size * 0.5))
        resetBtn:ClearAllPoints()
        if filter then resetBtn:SetPoint("LEFT", filter, "RIGHT", SQ_GAP, 0)
        else resetBtn:SetPoint("LEFT", row, "LEFT", 0, 0) end
        resetBtn:Show()
    end
    LayoutSquares(size, resetBtn or filter, showFilters)
    -- delves: right-aligned grid, list moves down for extra lines.
    local lines = LayoutDelves(size, resetBtn or filter, showDelves, math.max(1, n - 1), n)
    -- raids: map button after the reset, bosses in the grid.
    if showBosses and not raidBtn then
        raidBtn = GlyphButton(row, BTN, ns.ExtraRaidTex)
        raidBtn:SetScript("OnClick", ToggleRaidMenu)
        raidBtn:SetScript("OnHide", function() if raidMenu then raidMenu:Hide() end end)
        raidBtn:SetScript("OnEnter", function(self)
            self.Glyph:SetAlpha(1)
            XF.Tip(self, EllesmereUI.L("Raids"), EllesmereUI.L("Choose which raids' bosses are shown"))
        end)
        raidBtn:SetScript("OnLeave", function(self)
            self.Glyph:SetAlpha(0.8)
            XF.Untip()
        end)
    end
    if raidBtn then
        raidBtn:SetShown(showBosses and raidList ~= nil)
        raidBtn:SetSize(size, size)
        raidBtn.Glyph:SetSize(math.floor(size * 0.55), math.floor(size * 0.55))
        raidBtn:ClearAllPoints()
        local after = resetBtn or filter
        if after then raidBtn:SetPoint("LEFT", after, "RIGHT", SQ_GAP, 0)
        else raidBtn:SetPoint("LEFT", row, "LEFT", 0, 0) end
    end
    lines = math.max(lines, LayoutBosses(size, resetBtn or filter, showBosses, math.max(1, n - 1), n))

    -- result list fills the space between row 2 and the bottom buttons.
    local ROW_INSET = 3
    local top = ROW2_Y - lines * size - (lines - 1) * SQ_GAP - SQ_GAP
    local bottom = BOTTOM_Y + 22 + SQ_GAP
    local scroll, bar, inset = SP.ScrollBox, SP.ScrollBar, SP.ResultsInset
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOP", SP, "TOPRIGHT", -pad / 2, top)
        bar:SetPoint("BOTTOM", SP, "BOTTOMRIGHT", -pad / 2, bottom)
    end
    if scroll then
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", SP, "TOPLEFT", pad - ROW_INSET, top)
        scroll:SetPoint("BOTTOMRIGHT", SP, "BOTTOMRIGHT", -pad + ROW_INSET, bottom)
    end
    if inset then
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", SP, "TOPLEFT", pad, top)
        inset:SetPoint("BOTTOMRIGHT", SP, "BOTTOMRIGHT", -pad, bottom)
    end
    XF.PinBottomButtons(SP, XF.SEARCH_LEFT, "SignUpButton")
    Paint()
end
ns.Search_Layout = Layout
XF.Layout = Layout
XF.SEARCH_LEFT = { "BackButton", "BackToGroupButton" }

-- first show asks for this season's m+ maps
function XF.PanelShown()
    XF.RestoreCharFilter()
    if not XF.mapInfoAsked then
        XF.mapInfoAsked = true
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
    end
    Layout()
end

-- bottom rows
XF.COG_H = 22
function XF.SettingsCog(panel)
    if not (panel and LFGListFrame) then return nil end
    local cog = XF.cog
    if not cog then
        cog = GlyphButton(LFGListFrame, XF.COG_H, COG_TEX)
        cog.Glyph:SetSize(14, 14)
        cog.Glyph:SetVertexColor(XF.GLYPH, XF.GLYPH, XF.GLYPH)
        cog:SetScript("OnEnter", function(self)
            self.Glyph:SetAlpha(1)
            XF.Tip(self, EllesmereUI.L("Group Filters Settings"))
        end)
        cog:SetScript("OnLeave", function(self) self.Glyph:SetAlpha(0.8); XF.Untip() end)
        cog:SetScript("OnClick", function()
            XF.Untip()
            if InCombatLockdown() then
                CM.PrintError(EllesmereUI.L("Cannot open options during combat."))
                return
            end
            CM:ShowModule(ADDON_NAME)
        end)
        XF.cog = cog
    end
    local pad = tonumber(Cfg().padding) or 12
    if cog:GetParent() ~= panel then cog:SetParent(panel) end
    cog:ClearAllPoints()
    cog:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", pad, BOTTOM_Y)
    cog:SetFrameLevel(panel:GetFrameLevel() + 10)
    cog:Show()
    return cog
end

-- bottom row: cog, then the buttons split the rest of the width.
local function PinBottomButtons(panel, lefts, right)
    if not panel or InCombatLockdown() then return end
    if type(lefts) ~= "table" then lefts = { lefts } end
    local pad = tonumber(Cfg().padding) or 12
    local cog = XF.SettingsCog(panel)
    local x0 = pad + (cog and (XF.COG_H + SQ_GAP) or 0)
    local pw = panel:GetWidth()
    local w = (type(pw) == "number" and pw > 0) and (pw - pad - x0 - SQ_GAP) / 2 or nil
    for _, k in ipairs(lefts) do
        local b = panel[k]
        if type(b) == "table" then
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x0, BOTTOM_Y)
            if w then b:SetWidth(w) end
        end
    end
    local rb = panel[right]
    if type(rb) == "table" then
        rb:ClearAllPoints()
        rb:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -pad, BOTTOM_Y)
        if w then rb:SetWidth(w) end
    end
end
XF.PinBottomButtons = PinBottomButtons

-- category list spans the side padding (out of combat, else once it ends).
local function LayoutCategoryList()
    if InCombatLockdown() then XF.Defer("categoryList", LayoutCategoryList) return end
    local CS = LFGListFrame and LFGListFrame.CategorySelection
    local c = Cfg()
    if not (CS and type(CS.CategoryButtons) == "table") then return end
    local pad = tonumber(c.padding) or 12
    for i, b in ipairs(CS.CategoryButtons) do
        b:ClearAllPoints()
        if i == 1 then
            b:SetPoint("TOPLEFT", CS, "TOPLEFT", pad, -77)
            b:SetPoint("TOPRIGHT", CS, "TOPRIGHT", -pad, -77)
        else
            local prev = CS.CategoryButtons[i - 1]
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -3)
            b:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -3)
        end
    end
end

local function LayoutCategoryButtons()
    if InCombatLockdown() then XF.Defer("categoryButtons", LayoutCategoryButtons) return end
    PinBottomButtons(LFGListFrame and LFGListFrame.CategorySelection, { "StartGroupButton" }, "FindGroupButton")
    LayoutCategoryList()
end

-- blizzard dropdown in our filters button look.
local function StyleEntryDropdown(dd)
    if not dd then return end
    SetBorderColor(dd, ThemeBorder())
    local label = dd.Text
    local font = gfFont or XF.ButtonFont()
    if label and font then
        label:SetFontObject(font)
        label:SetTextColor(1, 1, 1, 1)
        label:ClearAllPoints()
        label:SetPoint("LEFT", dd, "LEFT", 9, 0)
        label:SetPoint("RIGHT", dd, "RIGHT", -24, 0)
        label:SetJustifyH("LEFT")
    end
    for _, r in ipairs({ dd:GetRegions() }) do
        if r.GetAtlas and r:GetAtlas() == "Azerite-PointingArrow" then
            r:SetDesaturated(true)
            r:SetVertexColor(1, 1, 1, 0.8)
            r:SetSize(11, 8)
            r:ClearAllPoints()
            r:SetPoint("RIGHT", dd, "RIGHT", -8, 0)
        end
    end
end

-- start a group option rows
XF.ENTRY_BOX_ROWS = { "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "VoiceChat" }
XF.ENTRY_CHECK_ROWS = { "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "VoiceChat", "CrossFactionGroup" }
XF.ENTRY_SWITCH_ROWS = { "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "VoiceChat", "CrossFactionGroup", "PrivateGroup" }
XF.TXT_X, XF.TXT_Y = 6, 4  -- text padding inside the boxes

-- start a group: lined up on the bottom buttons' padding
local function LayoutEntryFields()
    if InCombatLockdown() then XF.Defer("entryFields", LayoutEntryFields) return end
    local EC = LFGListFrame and LFGListFrame.EntryCreation
    local c = Cfg()
    if not EC then return end
    local pad = tonumber(c.padding) or 12
    local W = EC:GetWidth()
    if type(W) ~= "number" or W <= 0 then return end
    local inner = W - pad * 2
    local group, act = EC.GroupDropdown, EC.ActivityDropdown
    if group then
        group:ClearAllPoints()
        group:SetPoint("TOPLEFT", EC, "TOPLEFT", pad, -76)
        if act and act:IsShown() then
            local half = (inner - SQ_GAP) / 2
            group:SetWidth(half)
            act:ClearAllPoints()
            act:SetPoint("LEFT", group, "RIGHT", SQ_GAP, 0)
            act:SetWidth(half)
        else
            group:SetWidth(inner)
        end
    end
    local nameLabel, descLabel = EC.NameLabel, EC.DescriptionLabel
    if nameLabel then
        nameLabel:ClearAllPoints()
        nameLabel:SetPoint("TOPLEFT", EC, "TOPLEFT", pad, -120)
    end
    local name = EC.Name
    if name and nameLabel then
        name:ClearAllPoints()
        name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -5)
        name:SetPoint("TOPRIGHT", nameLabel, "BOTTOMLEFT", inner, -5)
    end
    local desc = EC.Description
    if desc and descLabel then
        desc:ClearAllPoints()
        desc:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -10)
        desc:SetPoint("TOPRIGHT", descLabel, "BOTTOMLEFT", inner, -10)
        if desc.EditBox then desc.EditBox:SetWidth(inner - 18) end
    end
    local TXT_X, TXT_Y = XF.TXT_X, XF.TXT_Y
    if name and name.SetTextInsets then
        pcall(name.SetTextInsets, name, TXT_X, TXT_X, 0, 0)
        local ins = name.Instructions
        if type(ins) == "table" then
            ins:ClearAllPoints()
            ins:SetPoint("TOPLEFT", name, "TOPLEFT", TXT_X, 0)
            ins:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", -TXT_X, 0)
        end
    end
    local deb = desc and desc.EditBox
    if deb and deb.SetTextInsets then
        pcall(deb.SetTextInsets, deb, TXT_X, TXT_X, TXT_Y, TXT_Y)
        if type(deb.Instructions) == "table" then
            deb.Instructions:ClearAllPoints()
            deb.Instructions:SetPoint("TOPLEFT", deb, "TOPLEFT", TXT_X, -TXT_Y)
            deb.Instructions:SetWidth(inner - TXT_X * 2)
        end
    end
    -- shorter placeholders (voice chat says discord).
    local vc = EC.VoiceChat and EC.VoiceChat.EditBox
    if vc and type(vc.Instructions) == "table" then vc.Instructions:SetText("Discord") end
    local il = EC.ItemLevel and EC.ItemLevel.EditBox
    if il and type(il.Instructions) == "table" then il.Instructions:SetAlpha(0) end
    local style = EC.PlayStyleDropdown
    if style and desc then
        style:ClearAllPoints()
        style:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
        style:SetPoint("TOPRIGHT", desc, "BOTTOMRIGHT", 0, -20)
    end
    StyleEntryDropdown(group)
    StyleEntryDropdown(act)
    StyleEntryDropdown(style)
    -- option rows line up a frame later, once the layout settles
    if not XF.alignQueued then
        XF.alignQueued = true
        C_Timer.After(0, XF.AlignEntryRows)
    end
end

-- option row alignment
function XF.AlignEntryRows()
    XF.alignQueued = nil
    if InCombatLockdown() then XF.Defer("entryFields", LayoutEntryFields) return end
    local EC = LFGListFrame and LFGListFrame.EntryCreation
    local style = EC and EC.PlayStyleDropdown
    local sr = style and style:GetRight()
    if not sr then return end
    local TXT_X = XF.TXT_X
    local lg = EC.ListGroupButton
    local bw = type(lg) == "table" and lg:GetWidth()
    for _, k in ipairs(XF.ENTRY_BOX_ROWS) do
        local row = EC[k]
        local box = type(row) == "table" and row.EditBox
        local rr = type(row) == "table" and row.GetRight and row:GetRight()
        if box and rr then
            local off = sr - rr
            box:ClearAllPoints()
            box:SetPoint("RIGHT", row, "RIGHT", off, 0)
            box:SetWidth((type(bw) == "number" and bw > 0) and bw or (125 + 5 + off))
            if box.SetTextInsets then pcall(box.SetTextInsets, box, TXT_X, TXT_X, 0, 0) end
            local ins = box.Instructions
            if type(ins) == "table" then
                ins:ClearAllPoints()
                ins:SetPoint("LEFT", box, "LEFT", TXT_X, 0)
                ins:SetPoint("RIGHT", box, "RIGHT", -TXT_X, 0)
            end
        end
    end
    local sl = style:GetLeft()
    for _, k in ipairs(XF.ENTRY_CHECK_ROWS) do
        local row = EC[k]
        local cb = type(row) == "table" and row.CheckButton
        local rl = type(row) == "table" and row.GetLeft and row:GetLeft()
        if type(cb) == "table" and sl and rl then
            cb:ClearAllPoints()
            cb:SetPoint("LEFT", row, "LEFT", sl - rl, 0)
            if row.Label then
                row.Label:ClearAllPoints()
                row.Label:SetPoint("LEFT", cb, "LEFT", 30 + 6, 0)  -- switch width + 6
            end
        end
    end
    local vbox = EC.VoiceChat and EC.VoiceChat.EditBox
    local prow = EC.PrivateGroup
    local pcb = type(prow) == "table" and prow.CheckButton
    local bl = type(vbox) == "table" and vbox:GetLeft()
    local pl = type(prow) == "table" and prow.GetLeft and prow:GetLeft()
    if type(pcb) == "table" and bl and pl then
        pcb:ClearAllPoints()
        pcb:SetPoint("LEFT", prow, "LEFT", bl - pl, 0)
        if prow.Label then
            prow.Label:ClearAllPoints()
            prow.Label:SetPoint("LEFT", pcb, "LEFT", 30 + 6, 0)  -- switch width + 6
        end
    end
end

-------------------------------------------------------------------------------
-- start a group options (min. iLvl, min. rating, voice chat, ...) as switches
-------------------------------------------------------------------------------
local SW_W, SW_H, SW_PAD = 30, 16, 2

-- checked state; it can be secret (e.g. editing a listing mid-encounter), then
-- returns nil, true.
local function CheckedState(cb)
    local v = cb:GetChecked()
    if IsSecret(v) then return nil, true end
    return v and true or false, false
end

local function PaintSwitch(cb)
    local d = FFD[cb]
    if not d then return end
    local raw = cb:GetChecked()
    local enabled = cb:IsEnabled()
    local sw = d.switch
    local r, g, b = Accent()
    sw.trackOn:SetColorTexture(r, g, b, 0.75)
    if IsSecret(raw) then
        -- secret: draw both looks and let the value pick one.
        sw.trackOn:SetAlphaFromBoolean(raw, 1, 0)
        sw.knobOn:SetAlphaFromBoolean(raw, 1, 0)
        sw.trackOff:SetAlphaFromBoolean(raw, 0, 1)
        sw.knobOff:SetAlphaFromBoolean(raw, 0, 1)
        sw:SetAlpha(enabled and 1 or 0.4)
        return
    end
    local on = raw and true or false
    sw.trackOn:SetAlpha(on and 1 or 0)
    sw.knobOn:SetAlpha(on and 1 or 0)
    sw.trackOff:SetAlpha(on and 0 or 1)
    sw.knobOff:SetAlpha(on and 0 or 1)
    sw:SetAlpha(enabled and 1 or 0.4)
    local row = d.row
    local dim = (on and enabled) and 1 or 0.45
    if row and row.Label then row.Label:SetAlpha(dim) end
    local box = row and row.EditBox
    if box then
        box:SetAlpha(dim)
        -- no typing while it's off.
        if not (on and enabled) and box.HasFocus and box:HasFocus() then box:ClearFocus() end
        if box.SetEnabled then box:SetEnabled(on and enabled) end
    end
end

local function SwitchCheckbox(row)
    if type(row) ~= "table" then return end
    local cb = row.CheckButton
    if type(cb) ~= "table" then return end
    if not FFD[cb] then
        local d = { row = row }
        FFD[cb] = d
        for _, child in ipairs({ cb:GetChildren() }) do child:SetAlpha(0) end
        local sw = CreateFrame("Frame", nil, cb)
        sw:SetSize(SW_W, SW_H)
        sw:SetPoint("LEFT", cb, "LEFT", 0, 0)
        sw:SetFrameLevel(cb:GetFrameLevel() + 3)
        sw:EnableMouse(false)
        sw.trackOff = sw:CreateTexture(nil, "BACKGROUND")
        sw.trackOff:SetAllPoints()
        sw.trackOff:SetColorTexture(0.267, 0.267, 0.267, 0.65)
        sw.trackOn = sw:CreateTexture(nil, "BACKGROUND", nil, 1)
        sw.trackOn:SetAllPoints()
        sw.knobOff = sw:CreateTexture(nil, "ARTWORK")
        sw.knobOff:SetSize(SW_H - SW_PAD * 2, SW_H - SW_PAD * 2)
        sw.knobOff:SetPoint("LEFT", sw, "LEFT", SW_PAD, 0)
        sw.knobOff:SetColorTexture(1, 1, 1, 0.5)
        sw.knobOn = sw:CreateTexture(nil, "ARTWORK", nil, 1)
        sw.knobOn:SetSize(SW_H - SW_PAD * 2, SW_H - SW_PAD * 2)
        sw.knobOn:SetPoint("RIGHT", sw, "RIGHT", -SW_PAD, 0)
        sw.knobOn:SetColorTexture(1, 1, 1, 1)
        d.switch = sw
        if row.Label then
            row.Label:ClearAllPoints()
            row.Label:SetPoint("LEFT", row, "LEFT", SW_W + 6, 0)
        end
        d.curOn = CheckedState(cb)
        hooksecurefunc(cb, "SetChecked", function(self, v)
            local fd = FFD[self]
            if fd then
                -- don't remember secret values.
                local now = nil
                if not IsSecret(v) then now = v and true or false end
                fd.prevOn, fd.curOn, fd.setAt = fd.curOn, now, GetTime()
            end
            PaintSwitch(self)
        end)
        if cb.SetEnabled then hooksecurefunc(cb, "SetEnabled", PaintSwitch) end
        cb:HookScript("OnClick", function(self)
            local fd = FFD[self]
            local on = CheckedState(self)
            if fd then fd.curOn = on end
            PaintSwitch(self)
            -- blizzard focuses the box before we enable it.
            local box = fd and fd.row and fd.row.EditBox
            if box and on and box.SetFocus then box:SetFocus() end
        end)
        if row.EditBox and row.EditBox.HookScript then
            -- blizzard re-enables these, so refuse focus while off
            row.EditBox:HookScript("OnEditFocusGained", function(box)
                if CheckedState(cb) == false then box:ClearFocus() end
            end)
            if row.EditBox.SetEnabled then
                hooksecurefunc(row.EditBox, "SetEnabled", function(box, v)
                    if not IsSecret(v) and v and CheckedState(cb) == false and not FFD[cb].reEnable then
                        FFD[cb].reEnable = true
                        box:SetEnabled(false)
                        FFD[cb].reEnable = nil
                    end
                end)
            end
            row.EditBox:HookScript("OnEditFocusLost", function()
                local fd = FFD[cb]
                if fd and fd.prevOn and fd.curOn == false and fd.setAt == GetTime() then
                    cb:SetChecked(true)
                end
            end)
        end
    end
    PaintSwitch(cb)
end

-- option check buttons as switches
local function LayoutEntrySwitches()
    if InCombatLockdown() then XF.Defer("entrySwitches", LayoutEntrySwitches) return end
    local EC = LFGListFrame and LFGListFrame.EntryCreation
    if not EC then return end
    for _, k in ipairs(XF.ENTRY_SWITCH_ROWS) do
        SwitchCheckbox(EC[k])
    end
end

local function LayoutEntryButtons()
    if InCombatLockdown() then XF.Defer("entryButtons", LayoutEntryButtons) return end
    PinBottomButtons(LFGListFrame and LFGListFrame.EntryCreation, { "CancelButton" }, "ListGroupButton")
    LayoutEntryFields()
    LayoutEntrySwitches()
end
ns.Search_LayoutEntry = LayoutEntryButtons

-- the listed group's bottom row: cog, then three equal buttons
local function LayoutViewerButtons(AV)
    local pad = tonumber(Cfg().padding) or 12
    local cog = XF.SettingsCog(AV)
    local x0 = pad + (cog and (XF.COG_H + SQ_GAP) or 0)
    local pw = AV:GetWidth()
    if not (type(pw) == "number" and pw > 0) then return end
    local w = (pw - pad - x0 - SQ_GAP * 2) / 3
    local browse, delist, edit = AV.BrowseGroupsButton, AV.RemoveEntryButton, AV.EditButton
    browse:ClearAllPoints()
    browse:SetPoint("BOTTOMLEFT", AV, "BOTTOMLEFT", x0, BOTTOM_Y)
    browse:SetWidth(w)
    delist:ClearAllPoints()
    delist:SetPoint("BOTTOMLEFT", AV, "BOTTOMLEFT", x0 + w + SQ_GAP, BOTTOM_Y)
    delist:SetWidth(w)
    edit:ClearAllPoints()
    edit:SetPoint("BOTTOMRIGHT", AV, "BOTTOMRIGHT", -pad, BOTTOM_Y)
    edit:SetWidth(w)
end

-- same look as search again, blizzard's button underneath takes the click
local function LayoutViewerRefresh(AV)
    local blz = AV.RefreshButton
    if not XF.viewerRefresh then
        local look = GlyphButton(AV, ROW1_H, "UI-RefreshButton", true)
        look:SetFrameLevel(AV:GetFrameLevel() + 5)
        look:EnableMouse(false)
        look.Glyph:SetSize(14, 14)
        local px = CM.PP.mult
        local cd = CreateFrame("Cooldown", nil, look, "CooldownFrameTemplate")
        cd:SetPoint("TOPLEFT", look, "TOPLEFT", px, -px)
        cd:SetPoint("BOTTOMRIGHT", look, "BOTTOMRIGHT", -px, px)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.65) end
        blz:HookScript("OnClick", function() cd:SetCooldown(GetTime(), 1) end)
        blz:SetAlpha(0)
        blz:HookScript("OnEnter", function()
            look:LockHighlight()
            look.Glyph:SetAlpha(1)
        end)
        blz:HookScript("OnLeave", function()
            look:UnlockHighlight()
            look.Glyph:SetAlpha(0.8)
        end)
        XF.viewerRefresh = look
    end
    local look = XF.viewerRefresh
    look:Show()
    blz:SetAlpha(0)
    local pad = tonumber(Cfg().padding) or 12
    local ar, ir = AV:GetRight(), AV.Inset:GetRight()
    look:ClearAllPoints()
    -- 3 in from the rows' edge, over the decline buttons
    look:SetPoint("BOTTOMRIGHT", AV.Inset, "TOPRIGHT", (ar and ir) and (ar - ir - pad - 3) or 0, 0)
    blz:ClearAllPoints()
    blz:SetAllPoints(look)
    blz:SetFrameLevel(look:GetFrameLevel() + 4)
end

-- own list off: back to blizzard's layout
local function RestoreViewer(AV)
    if not XF.viewerLaid then return end
    XF.viewerLaid = nil
    AV.BrowseGroupsButton:ClearAllPoints()
    AV.BrowseGroupsButton:SetPoint("BOTTOMLEFT", AV, "BOTTOMLEFT", -3, 4)
    AV.BrowseGroupsButton:SetWidth(145)
    AV.RemoveEntryButton:SetWidth(90)
    AV.RemoveEntryButton:ClearAllPoints()
    if UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME) then
        AV.RemoveEntryButton:SetPoint("LEFT", AV.BrowseGroupsButton, "RIGHT", 15, 0)
    else
        AV.RemoveEntryButton:SetPoint("BOTTOMLEFT", AV, "BOTTOMLEFT", -3, 4)
    end
    AV.EditButton:ClearAllPoints()
    AV.EditButton:SetPoint("BOTTOMRIGHT", AV, "BOTTOMRIGHT", -3, 4)
    AV.EditButton:SetWidth(90)
    if XF.cog and XF.cog:GetParent() == AV then XF.cog:Hide() end
    XF.viewerRefresh:Hide()
    local blz = AV.RefreshButton
    blz:SetAlpha(1)
    blz:ClearAllPoints()
    blz:SetPoint("BOTTOMRIGHT", AV.Inset, "TOPRIGHT", 21, 0)
    blz:SetFrameLevel(AV:GetFrameLevel() + 1)
end

local function LayoutViewer()
    local AV = LFGListFrame and LFGListFrame.ApplicationViewer
    if not (AV and AV:IsVisible()) then return end
    if InCombatLockdown() then XF.Defer("viewerLayout", LayoutViewer) return end
    if not ns.ApplicantListOn() then
        RestoreViewer(AV)
        return
    end
    XF.viewerLaid = true
    LayoutViewerButtons(AV)
    LayoutViewerRefresh(AV)
end
ns.LayoutViewer = LayoutViewer

-------------------------------------------------------------------------------
-- boot
-------------------------------------------------------------------------------
local function Init()
    SP = LFGListFrame and LFGListFrame.SearchPanel
    if not SP then return end
    XF.RestoreCharFilter()
    SP:HookScript("OnShow", XF.PanelShown)
    local CS = LFGListFrame.CategorySelection
    if CS then
        CS:HookScript("OnShow", LayoutCategoryButtons)
        if LFGListCategorySelection_AddButton then
            hooksecurefunc("LFGListCategorySelection_AddButton", LayoutCategoryList)
        end
        if CS:IsShown() then LayoutCategoryButtons() end
    end
    local EC = LFGListFrame.EntryCreation
    if EC then
        EC:HookScript("OnShow", LayoutEntryButtons)
        if LFGListEntryCreation_Select then
            hooksecurefunc("LFGListEntryCreation_Select", function()
                if EC:IsShown() then LayoutEntryFields(); LayoutEntrySwitches() end
            end)
        end
        if EC:IsShown() then LayoutEntryButtons() end
    end
    local AV = LFGListFrame.ApplicationViewer
    if AV and AV.Inset and AV.RefreshButton and AV.BrowseGroupsButton and AV.RemoveEntryButton and AV.EditButton then
        AV:HookScript("OnShow", LayoutViewer)
        -- blizzard re-anchors delist on every update
        if LFGListApplicationViewer_UpdateInfo then
            hooksecurefunc("LFGListApplicationViewer_UpdateInfo", LayoutViewer)
        end
        LayoutViewer()
    end
    -- A new category: the row filters start over.
    hooksecurefunc("LFGListSearchPanel_SetCategory", function()
        XF.NewPass()
        Layout()
    end)
    -- remember results for the new-group color
    hooksecurefunc("LFGListSearchPanel_UpdateResultList", function()
        local res = SP.results
        if SP.searching or type(res) ~= "table" or not SP:IsVisible() then return end
        for i = 1, #res do
            local id = res[i]
            if not IsSecret(id) then seenResults[id] = true end
        end
    end)
    if LFGListUtil_SetSearchEntryTooltip then
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", AddClassesByRole)
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", XF.CancelHint)
    end
    if LFGListSearchEntry_Update then hooksecurefunc("LFGListSearchEntry_Update", DecorateEntry) end
    -- every search clears the changed hint and starts the sweep
    hooksecurefunc("LFGListSearchPanel_DoSearch", function()
        -- previous search, same category only.
        prevResults = (prevCategory == SP.categoryID) and seenResults or nil
        prevCategory = SP.categoryID
        seenResults = {}
        if XF.filterRestored then XF.Remember(C_LFGList.GetAdvancedFilter()) end
        pending = false
        StartCooldown(CD_SEARCH)
        if SP:IsVisible() then Paint() end
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    ev:RegisterEvent("LFG_LIST_SEARCH_FAILED")
    XF.AdoptRating()
    ev:SetScript("OnEvent", function(_, event)
        if event == "LFG_LIST_SEARCH_FAILED" then
            -- server refused a search: wait longer.
            pending = true
            StartCooldown(CD_FAILED)
            return
        end
        -- new m+ maps: squares rebuild on the next layout
        XF.dungeonsDirty = true
        Layout()
    end)
    Layout()
end

function ns.Search_OnEnable()
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and LFGListFrame then
        Init()
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_GroupFinder" then
            self:UnregisterEvent("ADDON_LOADED")
            Init()
        end
    end)
end
