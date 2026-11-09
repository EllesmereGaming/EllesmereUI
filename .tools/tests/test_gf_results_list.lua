-- Stub harness: loads the Group Finder results list outside the game and drives
-- it: the full collect and paint, one group's update (only its row repaints),
-- filter and secrecy changes and the sort modes (the whole list), the row
-- layout memo, a raid row's score anchor, the sign-up timer frame, the window
-- look and the hand-back to Blizzard's list; a first visit to Quests or Custom
-- (the list stays hidden, its results unread), a hidden sign-up status and our
-- frame levels over Blizzard's faded list.
--   lua .tools/tests/test_gf_results_list.lua      (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource("EllesmereUIGroupFinder/EUI_GroupFinder_ResultsList.lua")

-- the widget methods the file calls: a mock answers those, any other field reads nil
local METHODS = {}
for name in SRC:gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end

local T = { frames = {}, now = 100, enabled = true, db = {}, cfg = {}, pass = {}, apps = {}, status = {},
    secretInfo = {}, fills = {}, collects = 0, redecorates = 0, results = {}, info = {}, players = {},
    counts = {}, acts = {} }

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
EUI_CLIENT_BLOCKED = nil

local function MakeObj(kind, parent)
    local o = { _kind = kind, _parent = parent, _scripts = {}, _events = {}, _shown = true, _alpha = 1,
        _w = 100, _h = 20, _text = "", _level = 1, _points = {} }
    setmetatable(o, { __index = function(t, k)
        if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
        if k == "SetScript" then return function(self, n, fn) self._scripts[n] = fn end end
        if k == "GetScript" then return function(self, n) return self._scripts[n] end end
        if k == "HookScript" then
            return function(self, n, fn)
                local prev = self._scripts[n]
                self._scripts[n] = prev and function(...) prev(...) fn(...) end or fn
            end
        end
        if k == "Show" then
            return function(self)
                local was = self._shown
                self._shown = true
                if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
            end
        end
        if k == "Hide" then
            return function(self)
                local was = self._shown
                self._shown = false
                if was and self._scripts.OnHide then self._scripts.OnHide(self) end
            end
        end
        if k == "SetShown" then return function(self, v) if v then self:Show() else self:Hide() end end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "IsVisible" then
            return function(self)
                local f = self
                while f do
                    if not f._shown then return false end
                    f = f._parent
                end
                return true
            end
        end
        if k == "GetParent" then return function(self) return self._parent end end
        if k == "SetAlpha" then return function(self, a) self._alpha = a end end
        if k == "GetAlpha" then return function(self) return self._alpha end end
        if k == "SetSize" then return function(self, w, h) self._w, self._h = w, h end end
        if k == "SetWidth" then return function(self, w) self._w = w end end
        if k == "SetHeight" then return function(self, h) self._h = h end end
        if k == "GetWidth" then return function(self) return self._w end end
        if k == "GetHeight" then return function(self) return self._h end end
        if k == "SetPoint" then
            return function(self, point, rel, relPoint, x, y)
                self._points[point] = { rel, relPoint, x, y }
            end
        end
        if k == "ClearAllPoints" then return function(self) self._points = {} end end
        if k == "RegisterEvent" then return function(self, e) self._events[e] = true end end
        if k == "UnregisterAllEvents" then return function(self) wipe(self._events) end end
        if k == "SetText" then return function(self, s) self._text = s == nil and "" or tostring(s) end end
        if k == "GetText" then return function(self) return self._text end end
        if k == "GetStringWidth" then return function(self) return #self._text * 6 end end
        if k == "SetFont" then
            return function(self, path, size, flags)
                self._font, self._size = path, size
                self._fontSets = (self._fontSets or 0) + 1
                self._plainSets = (self._plainSets or 0) + 1
            end
        end
        if k == "GetFont" then return function(self) return "Fonts\\FRIZQT__.TTF", self._size or 12, "" end end
        if k == "SetTextColor" then return function(self, ...) self._color = { ... } end end
        if k == "GetTextColor" then return function() return 1, 1, 1, 1 end end
        if k == "SetFrameLevel" then return function(self, l) self._level = l end end
        if k == "GetFrameLevel" then return function(self) return self._level end end
        if k == "SetEnabled" then return function(self, v) self._enabled = v and true or false end end
        if k == "IsEnabled" then return function(self) return self._enabled ~= false end end
        if k == "SetClipsChildren" then return function(self, v) self._clips = v end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateMaskTexture" then
            return function(self) return MakeObj(k, self) end
        end
        if METHODS[k] then return function() end end
        return nil
    end })
    T.frames[#T.frames + 1] = o
    return o
end

function CreateFrame(kind, name, parent) return MakeObj(kind, parent) end
function hooksecurefunc(a, b, c)
    if type(a) == "string" then
        T["hook_" .. a] = b
        return
    end
    local orig = a[b]
    rawset(a, b, function(self, ...)
        orig(self, ...)
        c(self, ...)
    end)
end
function GetTime() return T.now end
function PlaySound() end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
function IsInGroup() return false end
function GetNumGroupMembers() return 0 end
function GroupHasOfflineMember() return false end
function IsShiftKeyDown() return false end
function LFGListUtil_GetActiveQueueMessage() return nil end
function LFGListUtil_IsAppEmpowered() return true end
function LFGListUtil_SetSearchEntryTooltip() end
function LFGList_ReportListing() end
function LFGList_ReportAdvertisement() end
GameTooltip = MakeObj("GameTooltip")
function GameTooltip_Hide() end
DEFAULT_CHAT_FRAME = MakeObj("Frame")
C_ClassColor = { GetClassColor = function() return { r = 0.5, g = 0.5, b = 0.5 } end }
Enum = { LFGListDisplayType = { RoleCount = 0, RoleEnumerate = 1, ClassEnumerate = 2, HideAll = 3, PlayerCount = 4,
    Comment = 5 } }

-- secrecy: a result whose info table is marked reads as secret
local SECRET = {}
function issecretvalue(v) return type(v) == "table" and v[SECRET] == true end
function canaccesstable(t) return not (type(t) == "table" and t[SECRET] == true) end

C_LFGList = {
    GetSearchResultInfo = function(id)
        if T.secretInfo[id] then return { [SECRET] = true } end
        return T.info[id]
    end,
    GetApplicationInfo = function(id)
        T.appReads = (T.appReads or 0) + 1
        local s = T.status[id] or "none"
        return id, s, false, s == "applied" and 240 or 0
    end,
    GetApplications = function()
        T.collects = T.collects + 1
        local list = {}
        for _, id in ipairs(T.apps) do list[#list + 1] = id end
        return list
    end,
    GetActivityInfoTable = function(act) return T.acts[act] end,
    GetSearchResultPlayerInfo = function(id, k)
        if k == 1 then T.fills[id] = (T.fills[id] or 0) + 1 end
        local p = T.players[id]
        return p and p[k]
    end,
    GetSearchResultMemberCounts = function(id) return T.counts[id] end,
    GetNumApplications = function() return #T.apps, #T.apps end,
    GetAvailableRoles = function() return true, true, true end,
    IsCurrentlyApplying = function() return false end,
    CancelApplication = function() end,
}

EllesmereUI = {
    IsSecret = function(v) return v ~= nil and issecretvalue(v) end,
    HELD_BACK_ADDONS = {},
    L = function(s) return s end,
    Lf = function(s) return s end,
    MakeBorder = function() return { SetColor = function() end } end,
    PanelPP = {},
    ShowWidgetTooltip = function() end,
    HideWidgetTooltip = function() end,
    ShowContextMenu = function() end,
    ELLESMERE_GREEN = { r = 0.05, g = 0.82, b = 0.62 },
    BuildFullName = function(n) return n end,
    GetBorderStyleSelectDefaults = function() return { r = 1, g = 1, b = 1 } end,
    ApplyBorderStyle = function() T.borderApplies = (T.borderApplies or 0) + 1 end,
    -- the font family helper: counts every call (the layout memo's measure) and
    -- keeps what the string was given
    SetFontFamily = function(fs, path, size, flags, shadow)
        fs._fontSets = (fs._fontSets or 0) + 1
        fs._famFace, fs._size, fs._famFlags, fs._famShadow = path, size, flags, shadow
    end,
    _ModuleNS = {},
}

-- Blizzard's search panel, alive underneath
local SP = MakeObj("Frame")
SP.ScrollBox = MakeObj("Frame", SP)
SP.ScrollBar = MakeObj("Frame", SP)
SP.SignUpButton = MakeObj("Button", SP)
SP.SearchingSpinner = MakeObj("Frame", SP)
SP.categoryID = 2
SP.searching = false
LFGListFrame = { SearchPanel = SP }
function LFGListSearchPanel_DoSearch() end
function LFGListSearchPanel_UpdateResults() end

-- the module's other files, reduced to what this one asks of them
local ns = {
    Enabled = function() return T.enabled end,
    OwnListDB = function() return T.db end,
    Cfg = function() return T.cfg end,
    DEFAULTS = { iconSize = 125 },
    ExtraPasses = function(id) return T.pass[id] ~= false end,
    ExtraResultsSecret = function() return false end,
    GFOpt = function() return true end,
    GFRatingColor = function() return 1, 1, 1 end,
    ThemeBorder = function() return 1, 1, 1 end,
    GFShortName = function() return nil end,
    RegionList = function() return nil end,
    WhenGroupFinder = function(fn) T.whenGF = fn end,
    RedecorateRows = function() T.redecorates = T.redecorates + 1 end,
}

-- thirty dungeon groups; group 2 is a raid (role counts instead of icons)
T.acts[1] = { fullName = "Some Dungeon", maxNumPlayers = 5 }
T.acts[2] = { fullName = "Some Raid", maxNumPlayers = 20 }
for id = 1, 30 do
    T.results[id] = id
    T.info[id] = { name = "Group " .. id, activityIDs = { id == 2 and 2 or 1 }, leaderName = "Lead" .. id,
        isDelisted = false, numMembers = 2, leaderOverallDungeonScore = 3000 - id, generalPlaystyle = 1 }
    T.players[id] = { { classFilename = "MAGE", assignedRole = "DAMAGER", isLeader = true },
        { classFilename = "PRIEST", assignedRole = "HEALER" } }
    T.counts[id] = { TANK_REMAINING = 1, HEALER_REMAINING = 0, DAMAGER_REMAINING = 2, TANK = 0, HEALER = 1, DAMAGER = 1 }
end
T.counts[2] = { TANK = 2, HEALER = 4, DAMAGER = 10 }
local function SetResults()
    local list = {}
    for _, id in ipairs(T.results) do list[#list + 1] = id end
    SP.results = list
end
SetResults()

assert(loadstring(SRC, "=EUI_GroupFinder_ResultsList.lua"))("EllesmereUIGroupFinder", ns)

-------------------------------------------------------------------------------
--  helpers
-------------------------------------------------------------------------------
local function Find(pred)
    for _, f in ipairs(T.frames) do if pred(f) then return f end end
end
local frame, body, ticker, flusher
local function Rows()
    local list = {}
    for _, f in ipairs(T.frames) do
        if f._parent == body and rawget(f, "resultID") and f._shown then list[#list + 1] = f end
    end
    table.sort(list, function(a, b) return a.resultID < b.resultID end)
    return list
end
local function RowFor(id)
    for _, r in ipairs(Rows()) do if r.resultID == id then return r end end
end
local function Flush()
    if flusher._shown then flusher._scripts.OnUpdate(flusher, 0.016) end
end
local function Event(name, ...) frame._scripts.OnEvent(frame, name, ...) end
local function ResetCounts()
    wipe(T.fills)
    T.collects = 0
end

-------------------------------------------------------------------------------
--  0. a first visit to a category our list leaves to Blizzard's (outside the
--     five it covers) builds the list hidden (an empty list frame shown there
--     took every click and scroll from Blizzard's list) and walks no result
--     for secrecy
-------------------------------------------------------------------------------
assert(T.whenGF, "the list waits for blizzard's group finder")
T.whenGF()
SP.categoryID = 4
T.appReads = 0
ns.OwnListRefresh()
frame = Find(function(f) return f._parent == SP and f._scripts.OnMouseWheel ~= nil end)
assert(frame, "the list was not built")
assert(ns.OwnListActive() == false and not frame._shown and SP.ScrollBox._alpha == 1,
    "the empty list frame shows over blizzard's list on a first visit to a category it leaves alone")
assert(T.appReads == 0, "the results were walked for secrecy on a category our list leaves alone")
SP.categoryID = 7
ns.OwnListRefresh()
assert(not frame._shown, "the empty list frame shows on a second category it leaves alone")
SP.categoryID = 2

-------------------------------------------------------------------------------
--  1. the list takes over: built once, Blizzard's list faded, events while it shows
-------------------------------------------------------------------------------
ns.OwnListRefresh()
frame = Find(function(f) return f._parent == SP and f._scripts.OnMouseWheel ~= nil end)
assert(frame and frame._shown, "our list was not built over blizzard's")
body = Find(function(f) return f._parent == frame and f._clips end)
ticker = Find(function(f) return f._parent == frame and f._scripts.OnUpdate ~= nil end)
flusher = Find(function(f) return f._parent == nil and f._scripts.OnUpdate ~= nil end)
assert(body and ticker and flusher, "body, ticker and flusher")
assert(SP.ScrollBox._alpha == 0 and SP.ScrollBar._alpha == 0, "blizzard's list is not faded")
assert(frame._events.LFG_LIST_SEARCH_RESULT_UPDATED and frame._events.LFG_LIST_APPLICATION_STATUS_UPDATED)
assert(ns.OwnListActive() == true)
body._h = 300
frame._scripts.OnSizeChanged(frame)
local first = Rows()
assert(#first >= 5, "too few rows in view: " .. #first)
assert(first[1].resultID == 1, "the list does not start at the first group")
assert(not ticker._shown, "the timer ticks with no signed-up group in view")

-------------------------------------------------------------------------------
--  2. one group changes: its row alone repaints, on the next frame, no full collect
-------------------------------------------------------------------------------
ResetCounts()
T.info[3].name = "Renamed"
Event("LFG_LIST_SEARCH_RESULT_UPDATED", 3)
assert(flusher._shown and T.fills[3] == nil, "the update painted before the next frame")
Event("LFG_LIST_SEARCH_RESULT_UPDATED", 3)
Flush()
assert(not flusher._shown)
assert(T.fills[3] == 1 and T.collects == 0, "a one-group update repainted more than its row")
for id, n in pairs(T.fills) do assert(id == 3, "row " .. id .. " repainted for group 3's update") end
assert(RowFor(3).name._text == "Renamed", "the row did not take the group's new name")

-- a group out of view changes and still passes the filters: nothing repaints
ResetCounts()
Event("LFG_LIST_SEARCH_RESULT_UPDATED", 29)
Flush()
assert(next(T.fills) == nil and T.collects == 0, "a group out of view repainted")

-- a group no longer on the list (not in the results): ignored
ResetCounts()
Event("LFG_LIST_SEARCH_RESULT_UPDATED", 999)
Flush()
assert(next(T.fills) == nil and T.collects == 0)

-------------------------------------------------------------------------------
--  3. a group's filter pass changes: the whole list collects again
-------------------------------------------------------------------------------
ResetCounts()
T.pass[4] = false
Event("LFG_LIST_SEARCH_RESULT_UPDATED", 4)
Flush()
assert(T.collects == 1, "a changed filter pass did not collect the list again")
assert(RowFor(4) == nil, "a group the filters now leave out is still listed (hidden mode)")
-- dimmed mode keeps it, faded
T.db.visibility = "dimmed"
ns.SetOwnListValue("visibility", "dimmed")
local four = RowFor(4)
assert(four and four._alpha == 0.35, "dimmed mode does not keep the left-out group faded")
T.pass[4] = nil
T.db.visibility = nil
ns.SetOwnListValue("visibility", nil)

-------------------------------------------------------------------------------
--  4. a sort that follows score or size collects again on every update
-------------------------------------------------------------------------------
T.cfg.extraSortBy = "high"
ns.OwnListRefresh()
ResetCounts()
Event("LFG_LIST_SEARCH_RESULT_UPDATED", 3)
Flush()
assert(T.collects == 1, "a score sort did not reorder on an update")
T.cfg.extraSortBy = nil
ns.OwnListRefresh()

-------------------------------------------------------------------------------
--  5. the row layout runs again only for a new height or a display change
-------------------------------------------------------------------------------
local r1 = RowFor(1)
local sets = r1.name._fontSets
ns.OwnListRefresh()
frame._scripts.OnMouseWheel(frame, -1)
frame._scripts.OnMouseWheel(frame, 1)
assert(r1.name._fontSets == sets, "the layout ran again with nothing changed")
ns.SetOwnListSize("titleSize", 14)
assert(r1.name._fontSets == sets + 1 and r1.name._size == 14, "a new text size did not lay the rows out again")
ns.SetOwnListSize("titleSize", nil)
-- another profile's sizes, switched while the window was closed: laid out as the panel shows
T.db.titleSize = 16
SP._shown = false
SP:Show()
assert(r1.name._size == 16, "the panel opened on the old profile's layout")
T.db.titleSize = nil
SP._shown = false
SP:Show()

-------------------------------------------------------------------------------
--  6. a raid row moves the score beside its role counts; the slot's next group puts it back
-------------------------------------------------------------------------------
local raidRow = RowFor(2)
assert(raidRow and raidRow.scoreRaid, "the raid row did not move its score")
local slot = raidRow
frame._scripts.OnMouseWheel(frame, -1)  -- one row down: the slot shows another group
assert(slot.resultID ~= 2 and not slot.scoreRaid, "the slot kept the raid's score anchor")
assert(slot.score._points.RIGHT[3] == slot.scoreX, "the score is not back beside the icons")
frame._scripts.OnMouseWheel(frame, 1)

-------------------------------------------------------------------------------
--  7. the sign-up timer ticks only while a signed-up group is in view
-------------------------------------------------------------------------------
T.apps = { 5 }
T.status[5] = "applied"
Event("LFG_LIST_APPLICATION_STATUS_UPDATED", 5, "applied", "none")
Flush()
assert(ticker._shown, "no timer for the signed-up group in view")
T.now = T.now + 61
ticker._scripts.OnUpdate(ticker, 1.0)
local five = RowFor(5)
-- signed up with 240 s left of 300 (60 s gone), then 61 s more
assert(five and five.timer._text == "2:01", "the timer did not count: " .. tostring(five and five.timer._text))
T.apps = {}
T.status[5] = nil
Event("LFG_LIST_APPLICATION_STATUS_UPDATED", 5, "none", "applied")
Flush()
assert(not ticker._shown, "the timer still ticks with no signed-up group in view")

-------------------------------------------------------------------------------
--  8. the window look: nothing while group finder is off
-------------------------------------------------------------------------------
T.db.windowBgColor, T.db.windowBgOpacity = { r = 0, g = 0, b = 0 }, 50
local col, op = EllesmereUI._ShellLooks.lfg()
assert(col == T.db.windowBgColor and op == 50)
T.enabled = false
col, op = EllesmereUI._ShellLooks.lfg()
assert(col == nil and op == nil, "the window look applies with group finder off")
T.enabled = true

-------------------------------------------------------------------------------
--  9. a group gone secret hands the panel back to blizzard's list, rows redecorated
-------------------------------------------------------------------------------
T.secretInfo[6] = true
Event("LFG_LIST_SEARCH_RESULT_UPDATED", 6)
Flush()
assert(ns.OwnListActive() == false, "a secret group did not hand the panel back")
assert(SP.ScrollBox._alpha == 1 and not frame._shown, "blizzard's list did not come back")
assert(next(frame._events) == nil, "our list still listens after handing back")
assert(T.redecorates == 1, "blizzard's rows did not take their look again")
T.secretInfo[6] = nil
ns.OwnListRefresh()
assert(ns.OwnListActive() == true and SP.ScrollBox._alpha == 0, "our list did not come back")

-- another category: blizzard's list
SP.categoryID = 4
ns.OwnListRefresh()
assert(ns.OwnListActive() == false and T.redecorates == 2)
SP.categoryID = 2
ns.OwnListRefresh()

-------------------------------------------------------------------------------
--  10. a group's title takes a font family (other players' writing): its
--      template's face and outline, the template's shadow, never a plain
--      SetFont; the short dungeon name before it keeps a plain font in the
--      title's face and size
-------------------------------------------------------------------------------
local t1 = Rows()[1]
assert(t1.name._famFace == "Fonts\\FRIZQT__.TTF" and t1.name._famFlags == "" and t1.name._famShadow == true,
    "the group title did not take a font family in its template's face with its shadow")
assert(not t1.name._plainSets, "a plain SetFont reached the group title")
ns.GFShortName = function() return "SD" end
T.db.rowHeight = 16
ns.OwnListRefresh()
t1 = Rows()[1]
assert(t1.short._shown and t1.short._font == "Fonts\\FRIZQT__.TTF" and t1.short._size == 12,
    "the short dungeon name did not take the title's face and size")
assert(not t1.name._plainSets, "a plain SetFont reached the group title")
ns.GFShortName = function() return nil end
T.db.rowHeight = nil
ns.OwnListRefresh()

-------------------------------------------------------------------------------
--  11. a hidden sign-up status hands the panel back to Blizzard's list (our rows
--      cannot tell whether that group can be picked), through a refresh and
--      through one group's update; ours comes back once it reads again
-------------------------------------------------------------------------------
T.status[7] = { [SECRET] = true }
ns.OwnListRefresh()
assert(ns.OwnListActive() == false and not frame._shown and SP.ScrollBox._alpha == 1,
    "a hidden sign-up status kept our list")
T.status[7] = nil
ns.OwnListRefresh()
assert(ns.OwnListActive() == true and frame._shown, "our list did not come back")
T.status[8] = { [SECRET] = true }
Event("LFG_LIST_SEARCH_RESULT_UPDATED", 8)
Flush()
assert(ns.OwnListActive() == false, "a group's update with a hidden sign-up status kept our list")
T.status[8] = nil
ns.OwnListRefresh()
assert(ns.OwnListActive() == true, "our list did not come back after the update")

-------------------------------------------------------------------------------
--  12. something raises Blizzard's faded list and button: ours go back above
--      them on the next refresh, and a level already above is left alone
-------------------------------------------------------------------------------
local signBtn = Find(function(f) return f._kind == "Button" and f._parent == SP and f ~= SP.SignUpButton end)
assert(signBtn, "no sign up button of ours")
SP.ScrollBox._level, SP.SignUpButton._level = 40, 30
ns.OwnListRefresh()
assert(frame._level >= 50 and signBtn._level >= 35, "our list or sign up button stayed under blizzard's")
frame._level = 99
ns.OwnListRefresh()
assert(frame._level == 99, "a level already above was rewritten")

-------------------------------------------------------------------------------
--  13. Quests and Custom take our list too
-------------------------------------------------------------------------------
SP.categoryID = 1
ns.OwnListRefresh()
assert(ns.OwnListActive() == true and frame._shown and SP.ScrollBox._alpha == 0, "Quests did not take our list")
SP.categoryID = 6
ns.OwnListRefresh()
assert(ns.OwnListActive() == true and frame._shown, "Custom did not take our list")
SP.categoryID = 2
ns.OwnListRefresh()

-------------------------------------------------------------------------------
--  14. a row's member side follows its activity's display type, as Blizzard's
--      rows do: a player count (a grey circle, the count above), nothing for
--      HideAll and for a type Blizzard's rows do not draw, role counts for a
--      RoleCount activity of five; no display type read keeps the size rule
-------------------------------------------------------------------------------
local DT = Enum.LFGListDisplayType
T.acts[3] = { fullName = "Some Zone", maxNumPlayers = 0, displayType = DT.PlayerCount }
T.acts[4] = { fullName = "Hidden", maxNumPlayers = 5, displayType = DT.HideAll }
T.acts[5] = { fullName = "Some Quest", maxNumPlayers = 5, displayType = DT.RoleCount }
T.acts[6] = { fullName = "Commented", maxNumPlayers = 5, displayType = DT.Comment }
local function Side(r)
    local icons, circles = 0, 0
    for k = 1, 5 do if r.icons[k]._shown then icons = icons + 1 end end
    for k = 1, 3 do if r.rr[k].bg._shown then circles = circles + 1 end end
    return icons, circles, r.rr[4].bg._shown and r.rr[4].count._text or nil
end
local function WithActivity(id, act)
    T.info[id].activityIDs = { act }
    Event("LFG_LIST_SEARCH_RESULT_UPDATED", id)
    Flush()
    return RowFor(id)
end
local row = WithActivity(3, 3)
local icons, circles, players = Side(row)
assert(icons == 0 and circles == 0 and players == "2" and row.scoreRaid,
    "a player count activity: " .. icons .. " icons, " .. circles .. " circles, " .. tostring(players))
for id, act in pairs({ [4] = 4, [6] = 6 }) do
    row = WithActivity(id, act)
    icons, circles, players = Side(row)
    assert(icons == 0 and circles == 0 and players == nil and not row.scoreRaid,
        "activity " .. act .. " drew a member side: " .. icons .. " icons, " .. circles .. " circles")
end
row = WithActivity(5, 5)
icons, circles, players = Side(row)
assert(icons == 0 and circles == 3 and players == nil, "a RoleCount activity of five did not show role counts")
icons, circles = Side(RowFor(1))
assert(icons > 0 and circles == 0, "a five-player activity with no display type lost its member icons")
icons, circles = Side(RowFor(2))
assert(icons == 0 and circles == 3, "a raid with no display type lost its role counts")
for id = 3, 6 do WithActivity(id, 1) end

-------------------------------------------------------------------------------
--  15. the count circles wear the member icons' border: a ring around a round
--      circle, the border size out from it; on square icons an edge frame whose
--      style is applied once per border setting
-------------------------------------------------------------------------------
local rp = RowFor(2).rr[1]
assert(rp.ring._shown and not rp.edge._shown, "a round role count circle has no ring")
assert(rp.ring._points.TOPLEFT[3] == -1 and rp.ring._points.TOPLEFT[4] == 1, "the ring is not the border size out")
T.db.iconShape = "square"
ns.SetOwnListValue("iconShape", "square")
rp = RowFor(2).rr[1]
assert(rp.edge._shown and not rp.ring._shown, "a square role count circle has no border frame")
local applies = T.borderApplies or 0
ns.OwnListRefresh()
assert((T.borderApplies or 0) == applies, "an unchanged border was styled again")
T.db.iconShape = nil
ns.SetOwnListValue("iconShape", nil)

print("group finder results list harness: ok")
