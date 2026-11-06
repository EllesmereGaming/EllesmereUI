-- Stub harness: loads the friends kit and the custom friends list outside the
-- game and drives the list through its paths: off, live, scrolling, friend
-- events, groups, the friend menu, search, tile heights, the text lines, the
-- left-click selection with its click routing, and every stand-down.
--   lua .tools/tests/test_friends_list.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local KIT_SRC = ReadSource("EllesmereUI_FriendsKit.lua")
local LIST_SRC = ReadSource("EllesmereUI_FriendsList.lua")

-- The widget methods the two files call: a mock frame answers those, and any
-- other field that was never set reads nil, as on a real frame
local METHODS = {}
for _, src in ipairs({ KIT_SRC, LIST_SRC }) do
    for name in src:gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end
end

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
local allFrames = {}
local TEST = { frames = allFrames, tooltips = 0, popups = {}, ctxMenus = {}, hooks = {},
    searchResult = nil, searchCalls = 0, invites = {}, notes = {}, favs = {}, removed = {}, tagsSet = {},
    gamepad = false, modify = {}, methods = METHODS, replayMenus = {}, ffd = {}, thumbUpdates = 0,
    combat = false, deferred = {}, sounds = 0 }

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
format = string.format
function issecretvalue() return false end
function InCombatLockdown() return TEST.combat == true end
function PlaySound() TEST.sounds = TEST.sounds + 1 end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
BNET_CLIENT_WOW = "WoW"
WOW_PROJECT_ID = 1
FAVORITES, FRIENDS = "Favorites", "Friends"
FRIENDS_LEVEL_TEMPLATE = "Level %d %s"
SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT = "Lvl %d"
SOCIAL_UI_FRIENDS_LIST_PARTY_BUTTON_OFFLINE_TOOLTIP = "Friend is offline"
FRIENDS_GRAY_COLOR = { WrapTextInColorCode = function(_, text) return "|cff808080" .. text .. "|r" end }
DARKGRAY_COLOR = { WrapTextInColorCode = function(_, text) return "|cff404040" .. text .. "|r" end }
SET_NOTE, REMOVE_FRIEND = "Set Note", "Remove Friend"
ADD_FAVORITE_STATUS, REMOVE_FAVORITE_STATUS = "Add Favorite", "Remove Favorite"
RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.7, b = 1 } }
function GetClassInfo(id) return "Mage", "MAGE" end
function GetCurrentRegion() return 1 end
Enum = { TitleIconVersion = { Medium = 1, Small = 0 } }

local function MakeObj(kind, parent, template)
    local o = { _kind = kind, _parent = parent, _template = template, _scripts = {}, _hooks = {}, _events = {},
        _shown = true, _text = "", _alpha = 1, _w = 100, _h = 20, _scroll = 0, _points = 0 }
    local mt = {}
    mt.__index = function(t, k)
        if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
        if k == "fontString" or k == "elementData" or k == "Icon" then return nil end
        if k == "SetScript" then return function(self, name, fn) self._scripts[name] = fn end end
        if k == "HookScript" then return function(self, name, fn) self._hooks[name] = fn end end
        if k == "GetScript" then return function(self, name) return self._scripts[name] end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateMaskTexture" then
            return function(self) return MakeObj(k, self) end
        end
        if k == "Show" then
            return function(self)
                local was = self._shown
                self._shown = true
                if not was and self._scripts.OnShow and self:IsVisible() then self._scripts.OnShow(self) end
            end
        end
        if k == "Hide" then
            return function(self)
                local was = self._shown and self:IsVisible()
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
        if k == "IsMouseOver" then return function(self) return TEST.mouseOver == self end end
        if k == "SetAlpha" then return function(self, a) self._alpha = a end end
        if k == "GetAlpha" then return function(self) return self._alpha end end
        if k == "SetSize" then return function(self, w, h) self._w, self._h = w, h end end
        if k == "SetWidth" then return function(self, w) self._w = w end end
        if k == "SetHeight" then return function(self, h) self._h = h end end
        if k == "GetWidth" then return function(self) return self._w end end
        if k == "GetHeight" then return function(self) return self._h end end
        if k == "GetStringWidth" or k == "GetUnboundedStringWidth" then
            return function(self) return #self._text * 6 end
        end
        -- The game refuses click routing in combat, on every frame
        if k == "SetPassThroughButtons" then
            return function(self, ...)
                assert(not TEST.combat, "click routing set in combat")
                self._pass = { ... }
            end
        end
        if k == "SetMouseClickEnabled" then return function(self, v) self._clicks = v end end
        if k == "SetMouseMotionEnabled" then return function(self, v) self._motion = v end end
        if k == "SetEnabled" then return function(self, v) self._enabled = v and true or false end end
        if k == "IsEnabled" then return function(self) return self._enabled ~= false end end
        if k == "SetNormalAtlas" then return function(self, a) self._normalAtlas = a end end
        if k == "SetPushedAtlas" then return function(self, a) self._pushedAtlas = a end end
        if k == "SetHighlightAtlas" then return function(self, a) self._highlightAtlas = a end end
        if k == "GetFrameLevel" then return function() return 3 end end
        if k == "SetVerticalScroll" then return function(self, v) self._scroll = v end end
        if k == "GetVerticalScroll" then return function(self) return self._scroll end end
        if k == "SetScrollChild" then return function(self, c) self._child = c end end
        if k == "SetText" then
            return function(self, s)
                assert(type(s) == "string" or type(s) == "number", "SetText needs a string, got " .. type(s))
                self._text = tostring(s)
            end
        end
        if k == "SetFormattedText" then return function(self, fmt, ...) self._text = string.format(fmt, ...) end end
        if k == "GetText" then return function(self) return self._text end end
        if k == "SetFont" then
            return function(self, path, size)
                assert(type(path) == "string" and type(size) == "number" and size > 0, "bad SetFont")
                self._font, self._fontSize = path, size
            end
        end
        if k == "SetPoint" then
            return function(self, point, rel, relPoint, x, y)
                assert(type(point) == "string", "SetPoint needs a point")
                assert(rel == nil or type(rel) == "table" or type(rel) == "number", "bad anchor target")
                self._points = self._points + 1
                self._lastPoint = { point, rel, relPoint, x, y }
            end
        end
        if k == "ClearAllPoints" then return function(self) self._points = 0 end end
        if k == "RegisterEvent" then return function(self, e) self._events[e] = true end end
        if k == "UnregisterEvent" then return function(self, e) self._events[e] = nil end end
        if k == "UnregisterAllEvents" then return function(self) wipe(self._events) end end
        if k == "SetAtlas" then return function(self, a) assert(type(a) == "string") self._atlas = a end end
        if k == "SetTexture" then return function(self, a) self._tex = a end end
        -- Only names the files under test call as methods answer; any other field that was never set reads nil,
        -- as on a real frame
        if TEST.methods[k] then return function() end end
        return nil
    end
    setmetatable(o, mt)
    allFrames[#allFrames + 1] = o
    return o
end
TEST.MakeObj = MakeObj

function CreateFrame(kind, name, parent, template)
    assert(type(kind) == "string")
    local o = MakeObj(kind, parent, template)
    if name then _G[name] = o end
    return o
end
UIParent = MakeObj("Frame")

function hooksecurefunc(a, b, c)
    if type(a) == "table" then
        TEST.hooks[#TEST.hooks + 1] = { target = a, name = b, fn = c }
    else
        TEST.hooks[#TEST.hooks + 1] = { name = a, fn = b }
    end
end

C_Timer = { After = function(d, fn) fn() end }
C_Texture = {
    GetAtlasInfo = function(atlas)
        if atlas:find("^friends%-icon") then return { width = 22, height = 20 } end
        return nil
    end,
    SetTitleIconTexture = function(tex, program, version, sub)
        assert(type(program) == "string" and version ~= nil, "bad title icon call")
    end,
}
C_SocialRestrictions = { IsFriendsDisabled = function() return false end }
C_SocialQueue = { IsSystemSupported = function() return true end, GetGroupForPlayer = function() return nil end }
BattleNetFriendPartyInviteRestrictionType = { None = 0, Client = 1 }

-- The friends
local friends = {}
TEST.friends = friends
function TEST.AddFriend(f) friends[#friends + 1] = f end
function BNGetNumFriends() return #friends, 0, 0, 0 end
local function Info(i)
    local f = friends[i]
    if not f then return nil end
    local gi = { isOnline = f.online or false, clientProgram = f.program or (f.online and "WoW" or ""),
        wowProjectID = f.project or 1, characterName = f.char, characterLevel = f.level, className = f.class,
        classID = f.class and 8 or nil, areaName = f.area, realmName = f.realm, playerGuid = f.guid,
        richPresence = f.rich, gameAccountID = 900 + i, factionName = f.faction, isInCurrentRegion = true }
    return { bnetAccountID = f.id, accountName = "|Kq" .. f.id .. "|k", battleTag = f.tag or "", isFavorite = f.fav or false,
        note = f.note or "", friendTags = f.tags or {}, isAFK = f.afk or false, isDND = f.dnd or false,
        gameAccountInfo = gi,
        customMessage = "", lastOnlineTime = 0 }
end
C_BattleNet = {
    GetFriendAccountInfo = Info,
    GetAccountInfoByID = function(id)
        for i = 1, #friends do if friends[i].id == id then return Info(i) end end
    end,
    GetDefaultTitleWhisperTarget = function(id)
        for i = 1, #friends do if friends[i].id == id then return friends[i].title end end
    end,
    SearchFriends = function(info)
        TEST.searchCalls = TEST.searchCalls + 1
        assert(type(info) == "table" and type(info.tags) == "table" and type(info.searchText) == "string")
        return TEST.searchResult or {}
    end,
    AreFriendTagsEnabled = function() return true end,
    SetFriendTags = function(id, list) TEST.tagsSet[#TEST.tagsSet + 1] = { id, #list } end,
    GetFriendNumGameAccounts = function(i) return friends[i] and (friends[i].accounts or 1) or 0 end,
    GetFriendGameAccountInfo = function(i, k) local info = Info(i); return info and info.gameAccountInfo end,
    GetGameAccountInfoByID = function(id) local info = Info(id - 900); return info and info.gameAccountInfo end,
}
function BNSetFriendNote(id, text) TEST.notes[#TEST.notes + 1] = { id, text } end
function BNSetFriendFavoriteFlag(id, v) TEST.favs[#TEST.favs + 1] = { id, v } end
function BNRemoveFriend(id) TEST.removed[#TEST.removed + 1] = id end
FriendsListUtil = {
    BuildFriendNameDisplayText = function(info) return "|cff82c5ff" .. info.accountName .. "|r" end,
    BuildLocationDisplayText = function(info) return info.gameAccountInfo.areaName or "Offline" end,
    GetLastOnlineText = function() return "Last online 2 days ago" end,
    BuildTooltipBroadcastText = function() return nil end,
    GetBattleNetFriendPartyInviteRestriction = function(i) return friends[i].restricted and 1 or 0 end,
    GetBattleNetFriendPartyInviteRestrictionText = function() return "Cannot invite" end,
    GetBattleNetFriendInviteInfo = function() return { inviteType = "INVITE" } end,
    GetBattleNetFriendInviteTypeLabel = function() return "Invite" end,
    GetBattleNetFriendGameAccountInfoIfExactlyOneDirectInviteTargetExists = function(i)
        local f = friends[i]
        if (f.accounts or 1) == 1 then return { playerGuid = f.guid, gameAccountID = 900 + i } end
    end,
    HasMultipleGameAccounts = function(i) return (friends[i].accounts or 1) > 1 end,
    InviteOrRequestToJoin = function(guid, accountID) TEST.invites[#TEST.invites + 1] = { guid, accountID } end,
    IsPlayingWoW = function(gi) return gi.clientProgram == "WoW" end,
    GetGameAccountPartyInviteRestriction = function() return 0 end,
}
SocialUIUtil = {
    GetLabelForBattleNetFriendTag = function(tag) return "Tag " .. tostring(tag) end,
    GetSupportedBattleNetFriendTagInterestsForCurrentGameType = function() return { 1, 2 } end,
    GetSupportedBattleNetFriendTagRolesForCurrentGameType = function() return { 7 } end,
}

Menu = {
    IsMenuProxy = function() return false end,
    ModifyMenu = function(tag, cb)
        local rec = { tag = tag, cb = cb, live = true }
        TEST.modify[#TEST.modify + 1] = rec
        -- as the game does: an immediate replay on the last menu built
        local replay = TEST.MockMenu()
        TEST.replayMenus[#TEST.replayMenus + 1] = replay
        cb(nil, replay, { bnetIDAccount = "101", chatType = "BN_WHISPER" })
        return { Unregister = function() rec.live = false end }
    end,
}
function TEST.MockMenu()
    local made = {}
    local function Element(kind, text, fn)
        local e = { kind = kind, text = text, fn = fn, children = {} }
        function e:CreateButton(t, f)
            assert(type(t) == "string", "menu button needs a label")
            local c = Element("button", t, f)
            self.children[#self.children + 1] = c
            return c
        end
        function e:CreateCheckbox(t, isSel, setSel, data)
            assert(type(t) == "string" and type(isSel) == "function" and type(setSel) == "function")
            local c = Element("checkbox", t)
            c.isSel, c.setSel, c.data = isSel, setSel, data
            self.children[#self.children + 1] = c
            return c
        end
        function e:CreateDivider() self.children[#self.children + 1] = Element("divider") end
        made[#made + 1] = e
        return e
    end
    local root = { made = made }
    function root:CreateDivider() return Element("divider") end
    function root:CreateTitle(t)
        assert(type(t) == "string")
        return Element("title", t)
    end
    function root:CreateButton(t, f)
        assert(type(t) == "string", "menu button needs a label")
        return Element("button", t, f)
    end
    return root
end

-- The Social UI friends view
local view = MakeObj("Frame", UIParent)
view._shown = false
view.TopDivider = MakeObj("Texture", view)
view.BottomDivider = MakeObj("Texture", view)
view.ScrollBox = MakeObj("Frame", view)
view.ScrollBar = MakeObj("Frame", view)
view.FilterBar = { SearchBar = MakeObj("EditBox", view) }
view.selectedSearchFilterOptions = {}
view.RefreshSearchResults = function() end
SocialUIFrame = { FriendsList = view }
TEST.view = view

-- EllesmereUI
EllesmereUIDB = {}
EllesmereUI = {
    CLASS_ICON_SPRITE_COORDS = { MAGE = { 0, 0.25, 0, 0.25 } },
    COLOR_CODES = { DIM = "|cff888888", BAD = "|cffff5959" },
    ELLESMERE_GREEN = { r = 0.05, g = 0.82, b = 0.62 },
    _accentElements = {},
}
-- The shared combat queue: its functions run as combat ends
EllesmereUI.CombatQueue = { Defer = function(key, fn) TEST.deferred[key] = fn end }
function TEST.EndCombat()
    TEST.combat = false
    local run = TEST.deferred
    TEST.deferred = {}
    for _, fn in pairs(run) do fn() end
end
function EllesmereUI.RegAccent(entry)
    assert(entry.type == "callback" and type(entry.fn) == "function")
    EllesmereUI._accentElements[#EllesmereUI._accentElements + 1] = entry
end
function EllesmereUI.NewFrameData()
    local t = setmetatable({}, { __mode = "k" })
    TEST.ffd[#TEST.ffd + 1] = t
    return t, function(f)
        local d = t[f]
        if not d then d = {}; t[f] = d end
        return d
    end
end
function EllesmereUI.HexColor(r, g, b) return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255) end
function EllesmereUI.GetFontPath() return "Fonts\\Custom.ttf" end
function EllesmereUI.PrimeFontShadow() end
function EllesmereUI.PadTaintStandDown() return false end
function EllesmereUI.PadGamepadUI() return TEST.gamepad end
function EllesmereUI.IsSecret(v) return issecretvalue(v) end
function EllesmereUI.ClassTokenFromLocalized() return "MAGE" end
function EllesmereUI.GetAccentColor() return 0.05, 0.82, 0.62 end
function EllesmereUI.L(s) assert(type(s) == "string", "L needs a string") return s end
function EllesmereUI.Lf(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)%$s", function(n) return tostring(args[tonumber(n)]) end))
end
function EllesmereUI.StripFriendNoteTag(note)
    if type(note) ~= "string" or note == "" then return nil end
    local s = note:find("||EUI:", 1, true)
    if s and note:find("||", s + 6, true) then
        note = note:sub(1, s - 1):match("^(.-)%s*$")
        if note == "" then return nil end
    end
    return note
end
function EllesmereUI.ShowWidgetTooltip(anchor, text, opts)
    assert(type(anchor) == "table" and type(text) == "string" and text ~= "", "bad tooltip call")
    TEST.tooltips = TEST.tooltips + 1
    TEST.lastTip = text
end
function EllesmereUI.HideWidgetTooltip() end
function EllesmereUI:ShowInputPopup(opts)
    assert(type(opts.title) == "string" and type(opts.onConfirm) == "function")
    TEST.popups[#TEST.popups + 1] = opts
end
function EllesmereUI:ShowConfirmPopup(opts)
    assert(type(opts.title) == "string" and type(opts.message) == "string" and type(opts.onConfirm) == "function")
    TEST.popups[#TEST.popups + 1] = opts
end
function EllesmereUI.ShowContextMenu(anchor, items)
    assert(type(items) == "table" and #items > 0)
    TEST.ctxMenus[#TEST.ctxMenus + 1] = items
end
function EllesmereUI:EnsureLoaded() end
function EllesmereUI:ShowColorPicker(info, anchor)
    assert(type(info.swatchFunc) == "function" and type(info.cancelFunc) == "function")
    TEST.picker = info
    EllesmereUI._colorPickerPopup = { GetColorRGB = function() return 1, 0, 0 end }
end
-- The shared scroll bar, reduced to what the list uses of it
function EllesmereUI.AttachSmoothScrollbar(sf, opts)
    assert(opts.child and type(opts.onScroll) == "function" and opts.trackParent)
    local function Max() return math.max(0, opts.child:GetHeight() - sf:GetHeight()) end
    local function ScrollTo(v)
        v = math.max(0, math.min(Max(), v))
        sf:SetVerticalScroll(v)
        opts.onScroll(v)
    end
    TEST.ScrollTo, TEST.MaxScroll = ScrollTo, Max
    return function() TEST.thumbUpdates = TEST.thumbUpdates + 1 end, ScrollTo
end

-------------------------------------------------------------------------------
--  The files under test, then the scenarios
-------------------------------------------------------------------------------
assert(loadstring(KIT_SRC, "=EllesmereUI_FriendsKit.lua"))("EllesmereUI", {})
assert(loadstring(LIST_SRC, "=EllesmereUI_FriendsList.lua"))("EllesmereUI", {})

local T = TEST
local SECRET_MARK = {}
local Kit, FL = EllesmereUI.FriendsKit, EllesmereUI.FriendsList
local view = T.view
local out = {}
local function note(s) out[#out + 1] = s end

local settings = { enabled = true, showClassIcons = true, iconStyle = "modern", classColorNames = true,
    factionBanners = false, showRegionIcons = true, customList = false, tileHeight = 46, showUngrouped = true }
local function Settings() return settings end

-- friends: a favorite, two carrying an old note tag, one added by character, then a crowd
T.AddFriend({ id = 101, tag = "Alpha#1", online = true, char = "Alphachar", level = 60, class = "Mage",
    area = "Stormwind", guid = "Player-1", fav = true })
T.AddFriend({ id = 102, tag = "Bravo#2", online = true, char = "Bravochar", level = 44, class = "Mage",
    area = "Orgrimmar", guid = "Player-2", note = "raid buddy ||EUI:Raiders||" })
T.AddFriend({ id = 103, tag = "Charlie#3", online = false, note = "||EUI:Raiders||" })
T.AddFriend({ id = 104, title = "Deltachar", online = true, char = "Deltachar", level = 12, class = "Mage",
    area = "Elwynn", guid = "Player-4" })
T.AddFriend({ id = 105, tag = "Echo#5", online = true, char = "Echochar", level = 30, class = "Mage",
    area = "Darkshire", guid = "Player-5", accounts = 2 })
T.AddFriend({ id = 106, tag = "Foxtrot#6", online = true, char = "Foxchar", level = 30, class = "Mage",
    area = "Westfall", guid = "Player-6", restricted = true })
T.AddFriend({ id = 107, tag = "Golf#7", online = true, program = "Pro", rich = "Playing another game" })
for i = 108, 140 do
    T.AddFriend({ id = i, tag = ("Friend%03d#%d"):format(i, i), online = i % 3 == 0, char = "Char" .. i,
        level = 20, class = "Mage", area = "Zone" .. i, guid = "Player-" .. i })
end
T.AddFriend({ id = 141, tag = "Aaway#141", online = true, char = "Awaychar", level = 9, class = "Mage",
    area = "Awayzone", guid = "Player-141", afk = true })
T.AddFriend({ id = 142, tag = "Abusy#142", online = true, char = "Busychar", level = 9, class = "Mage",
    area = "Busyzone", guid = "Player-142", dnd = true })

local function Frames(pred)
    local list = {}
    for _, f in ipairs(T.frames) do
        if pred(f) then list[#list + 1] = f end
    end
    return list
end
local function One(pred, what)
    local list = Frames(pred)
    assert(#list == 1, ("expected one %s, found %d"):format(what, #list))
    return list[1]
end

-- 0. the kit's tiles start; the list starts off
FriendsListSocialCardMixin = { Initialize = function() end, SetSelected = function() end }
local before = #T.frames
Kit.StartTiles({ Settings = Settings, style = "eui", fontKey = "blizzardSkin" })
-- While the list is held back it is available nowhere: a profile that saved
-- it on builds nothing. The scenarios below run with the hold lifted.
if FL.HELD then
    settings.customList = true
    FL.Start()
    FL.Refresh()
    assert(FL.Available() == false and #T.frames == before, "a held list started")
    settings.customList = false
    FL.HELD = false
end
FL.Start()
assert(#T.frames == before, "the list built a frame while the option is off")
assert(FL.Available() == true)
local lo, hi, def = FL.TileRange()
assert(lo == 24 and hi == 70 and def == 46)

-- 1. on: only the driver exists until the view shows
settings.customList = true
FL.Refresh()
local driver = One(function(f) return f._parent == view and f._scripts.OnShow ~= nil end, "driver")
assert(#T.frames == before + 1, "more than the driver was built before the view showed")
assert(view.ScrollBox._alpha == 1)

local function ShowView()
    view._shown = true
    driver._scripts.OnShow(driver)
end
local function HideView()
    driver._scripts.OnHide(driver)
    view._shown = false
end

ShowView()
local sf = One(function(f) return f._kind == "ScrollFrame" end, "scroll frame")
local root, content = sf._parent, sf._child
assert(root._parent == view and content, "list frames not under the view")
sf._w, sf._h = 380, 400
sf._scripts.OnSizeChanged(sf)

local function Rows()
    return Frames(function(f) return f._parent == content and rawget(f, "hit") ~= nil and f._shown end)
end
local function Headers()
    local list = Frames(function(f) return f._parent == content and rawget(f, "label") ~= nil and f._shown end)
    table.sort(list, function(a, b) return a.posY < b.posY end)
    return list
end
local function HeaderFor(key)
    for _, h in ipairs(Headers()) do
        if h.key == key then return h end
    end
end
local function RowFor(id)
    for _, r in ipairs(Rows()) do
        if r.rec and r.rec.id == id then return r end
    end
end
local function Reveal(id)
    for at = 0, T.MaxScroll() + 40, 40 do
        T.ScrollTo(at)
        local r = RowFor(id)
        if r then return r end
    end
    error("friend " .. id .. " has no row at any scroll spot")
end
local ev = One(function(f) return f._scripts.OnEvent ~= nil and f._parent == nil end, "event frame")
local flusher = One(function(f) return f._scripts.OnUpdate ~= nil and f._parent == nil end, "flusher")
local function Flush()
    if flusher._shown then flusher._scripts.OnUpdate(flusher) end
end
local function LiveMenus()
    local n = 0
    for _, m in ipairs(T.modify) do if m.live then n = n + 1 end end
    return n
end

-- 2. live: Blizzard's list covered, events and menu entries registered
assert(view.ScrollBox._alpha == 0 and view.ScrollBar._alpha == 0, "Blizzard's list not covered")
assert(Kit._listShown == true)
assert(ev._events.BN_FRIEND_INFO_CHANGED and ev._events.GROUP_ROSTER_UPDATE)
assert(LiveMenus() == 2, "menu entries not registered")
assert(root._shown)

-- 3. the old note tags came back as a group; the character friend has a key
local g = EllesmereUIDB.global
assert(g.friendGroupsTagMigrated == true)
assert(#g.friendGroups == 1 and g.friendGroups[1].name == "Raiders")
assert(g.friendGroupsByTag["Bravo#2"] == "Raiders" and g.friendGroupsByTag["Charlie#3"] == "Raiders")

local rows, headers = Rows(), Headers()
assert(#rows > 3 and #headers >= 2, ("rows %d headers %d"):format(#rows, #headers))
assert(headers[1].key == "_favorites" and headers[1].label._text == "Favorites  (1/1)", headers[1].label._text)
assert(headers[2].key == "Raiders" and headers[2].label._text == "Raiders  (1/2)", headers[2].label._text)
for _, r in ipairs(rows) do
    assert(r.link._text:find("^|HBNplayer:|Kq%d+|k:%d+:0:BN_WHISPER:|Kq%d+|k|hM+|h$"), "bad link: " .. r.link._text:sub(1, 60))
    assert(r.link._fontSize == 54, "link font must be the tile height + 8")
    assert(r.hit._scripts.OnClick == nil and r.hit._scripts.OnMouseUp == nil and r.hit._scripts.OnMouseDown == nil
        and r.hit._scripts.OnHyperlinkClick == nil, "a click script on the link layer")
    assert(r.hit._template == "InlineHyperlinkFrameTemplate", "the link layer is not Blizzard's template")
    assert(next(r.hit._hooks) == nil, "a script hook on the link layer")
    assert(#r.hit._pass == 1 and r.hit._pass[1] == "LeftButton", "the link layer must pass the left button on")
    assert(r._scripts.OnMouseUp ~= nil and r._scripts.OnClick == nil and r._clicks == true and r._motion == false,
        "the row takes the left click and no hover")
    assert(r._h == 46 and r._w == 380 - 6 - 4)
end
note(("live: %d rows, %d headers in view; content %d tall"):format(#rows, #headers, content._h))

-- 4. scrolling: to the bottom and back, the last friend comes into view
T.ScrollTo(T.MaxScroll())
local bottomRows = Rows()
assert(#bottomRows > 3)
local sawOffline = false
for _, r in ipairs(bottomRows) do
    if not r.rec.online then sawOffline = true end
end
assert(sawOffline, "offline friends sort last")
for step = 0, T.MaxScroll(), 37 do T.ScrollTo(step) end
T.ScrollTo(0)
assert(#Rows() == #rows and #Headers() == #headers, "the view changed after scrolling back")
note(("scroll: max %d, frames made: %d rows, %d headers"):format(T.MaxScroll(),
    #Frames(function(f) return f._parent == content and rawget(f, "hit") ~= nil end),
    #Frames(function(f) return f._parent == content and rawget(f, "label") ~= nil end)))

-- 5. events: one friend in place repaints its row; a move rebuilds on the next frame
local r1 = RowFor(101)
assert(r1, "favorite friend not in view")
T.friends[1].area = "Ironforge"
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", 1)
assert(not flusher._shown, "an in-place change asked for a rebuild")
assert(r1.d.info._text:find("Ironforge"), "the row did not repaint: " .. r1.d.info._text)
T.friends[1].online = false
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", 1)
assert(flusher._shown, "a status change must rebuild")
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", 2)
Flush()
assert(not flusher._shown)
assert(Headers()[1].label._text == "Favorites  (0/1)", Headers()[1].label._text)
T.friends[1].online = true
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED")
Flush()
ev._scripts.OnEvent(ev, "GROUP_ROSTER_UPDATE")
Flush()
ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 150)
Flush()

-- 6. headers: collapse, reorder, colour, rename, delete
local raid = HeaderFor("Raiders")
local shownBefore = #Rows()
raid._scripts.OnClick(raid)
assert(g.friendGroups[1].collapsed == true)
assert(RowFor(102) == nil, "a collapsed section still shows its friends")
raid = HeaderFor("Raiders")
raid._scripts.OnClick(raid)
assert(RowFor(102) ~= nil)
raid = HeaderFor("Raiders")
assert(raid.up.off ~= true and raid.edit._shown and raid.x._shown, "custom section controls")
local fav = HeaderFor("_favorites")
assert(fav.up.off == true and not fav.edit._shown, "Favorites is first and has no edit")
raid.up._scripts.OnClick(raid.up)
assert(Headers()[1].key == "Raiders", "the section did not move up")
raid = HeaderFor("Raiders")
raid.down._scripts.OnClick(raid.down)
assert(Headers()[1].key == "_favorites")
raid = HeaderFor("Raiders")
raid.pick._scripts.OnClick(raid.pick)
T.picker.swatchFunc()
assert(g.friendGroupColors.Raiders and g.friendGroupColors.Raiders.r == 1)
T.picker.cancelFunc()
assert(g.friendGroupColors.Raiders == nil)
raid = HeaderFor("Raiders")
raid.edit._scripts.OnClick(raid.edit)
T.popups[#T.popups].onConfirm("  Raid Team  ")
assert(g.friendGroups[1].name == "Raid Team" and g.friendGroupsByTag["Bravo#2"] == "Raid Team")
assert(HeaderFor("Raid Team"))

-- 7. the menu: only for a menu opened from a row of ours
local function MenuFor(context, over)
    T.mouseOver = over
    local menu = T.MockMenu()
    for _, m in ipairs(T.modify) do
        if m.live and m.tag == "MENU_UNIT_BN_FRIEND" then m.cb(nil, menu, context) end
    end
    T.mouseOver = nil
    return menu
end
local function Entry(menu, text)
    for _, e in ipairs(menu.made) do
        if e.text == text then return e end
    end
end
assert(#MenuFor({ bnetIDAccount = "108", chatType = "BN_WHISPER" }, nil).made == 0, "entries without the pointer on the list")
assert(#MenuFor({ bnetIDAccount = 108, friendsList = true }, root).made == 0, "entries on Blizzard's own list menu")
assert(#MenuFor(nil, root).made == 0)
assert(#MenuFor({ bnetIDAccount = "9999" }, root).made == 0, "entries for a friend the list does not hold")
local menu = MenuFor({ bnetIDAccount = "108", chatType = "BN_WHISPER" }, root)
assert(Entry(menu, "EllesmereUI") and Entry(menu, "Set Note") and Entry(menu, "Add Favorite")
    and Entry(menu, "Remove Friend"), "menu entries missing")
local function At(m, text)
    for i, e in ipairs(m.made) do
        if e.text == text then return i end
    end
end
assert(At(menu, "Set Note") == 1, "the friend entries come first, with no divider before them")
assert(At(menu, "Set Note") < At(menu, "Add Favorite") and At(menu, "Add Favorite") < At(menu, "Tags")
    and At(menu, "Tags") < At(menu, "Remove Friend"), "friend entries out of order")
assert(At(menu, "Remove Friend") < At(menu, "EllesmereUI") and At(menu, "EllesmereUI") < At(menu, "Add to Group"),
    "our group must come after Remove Friend")
assert(menu.made[At(menu, "EllesmereUI") - 1].kind == "divider", "our group starts with a divider")
local add = Entry(menu, "Add to Group")
assert(add and add.children[1].text == "New Group...", "group entries missing")
local tags = Entry(menu, "Tags") or Entry(menu, SOCIAL_UI_BATTLE_NET_FRIEND_TAGS_LABEL or "Tags")
assert(tags and #tags.children == 3, "three tag checkboxes")
tags.children[1].setSel(tags.children[1].data)
tags.children[3].setSel(tags.children[3].data)
assert(#T.tagsSet == 2 and T.tagsSet[2][2] == 2, "tags are sent whole")
assert(tags.children[1].isSel(tags.children[1].data) == true)
-- an existing group, then a new one
local toRaid
for _, c in ipairs(add.children) do
    if c.text == "Raid Team" then toRaid = c end
end
assert(toRaid, "existing group not offered")
toRaid.fn()
assert(g.friendGroupsByTag["Friend108#108"] == "Raid Team")
menu = MenuFor({ bnetIDAccount = "108", chatType = "BN_WHISPER" }, root)
local move = Entry(menu, "Move to Group")
assert(move, "a grouped friend is offered Move to Group")
assert(move.children[#move.children].text == "Remove from Group")
move.children[1].fn()
T.popups[#T.popups].onConfirm("Guildies")
assert(g.friendGroupsByTag["Friend108#108"] == "Guildies" and #g.friendGroups == 2)
assert(HeaderFor("Guildies"), "the new section is not shown")
Entry(menu, "Set Note").fn()
assert(T.popups[#T.popups].maxLetters == 127)
T.popups[#T.popups].onConfirm("hello")
assert(T.notes[1][1] == 108 and T.notes[1][2] == "hello")
Entry(menu, "Add Favorite").fn()
assert(T.favs[1][1] == 108 and T.favs[1][2] == true)
Entry(menu, "Remove Friend").fn()
T.popups[#T.popups].onConfirm()
assert(T.removed[1] == 108)
-- a favorite: no group entries, the favorite entry flips
menu = MenuFor({ bnetIDAccount = "101" }, root)
assert(not Entry(menu, "Add to Group") and not Entry(menu, "Move to Group") and Entry(menu, "Remove Favorite"))
assert(not Entry(menu, "EllesmereUI"), "a favorite has no group: no empty titled section")
for _, e in ipairs(menu.made) do assert(e.kind ~= "divider" or e ~= menu.made[#menu.made]) end
-- the friend added by character has a key of its own
menu = MenuFor({ bnetIDAccount = "104" }, root)
local addChar = Entry(menu, "Add to Group")
assert(addChar, "a character friend can be grouped")
for _, c in ipairs(addChar.children) do
    if c.text == "Guildies" then c.fn() end
end
assert(g.friendGroupsByTag["title:Deltachar"] == "Guildies")

-- delete a group: its friends go back to the ungrouped section
local guild = HeaderFor("Guildies")
guild.x._scripts.OnClick(guild.x)
T.popups[#T.popups].onConfirm()
assert(#g.friendGroups == 1 and g.friendGroupsByTag["title:Deltachar"] == nil)

-- 8. search: Blizzard's search box drives the list
view.FilterBar.SearchBar._text = "alp"
T.searchResult = { 1 }
local hook
for _, h in ipairs(T.hooks) do
    if h.target == view and h.name == "RefreshSearchResults" then hook = h.fn end
end
assert(hook, "the search hook is missing")
hook()
Flush()
assert(#Rows() == 1 and #Headers() == 1 and Rows()[1].rec.id == 101, "search result not applied")
-- an in-place change during a search rebuilds (it may change what matches)
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", 1)
assert(flusher._shown)
Flush()
-- a filter with no text
view.FilterBar.SearchBar._text = ""
view.selectedSearchFilterOptions[{ searchInfo = { isOnline = true } }] = true
view.selectedSearchFilterOptions[{ searchInfo = { tags = { 3 } } }] = true
T.searchResult = { 2, 5 }
hook()
Flush()
assert(#Rows() == 2, "filter result not applied")
wipe(view.selectedSearchFilterOptions)
T.searchResult = nil
hook()
Flush()
assert(#Rows() > 3)

-- 9. tile heights: one line, two lines, the larger name
for _, size in ipairs({ 24, 33, 34, 51, 52, 70, 46 }) do
    settings.tileHeight = size
    FL.Refresh()
    local list = Rows()
    assert(#list > 0)
    for _, r in ipairs(list) do
        assert(r._h == size and r.link._fontSize == size + 8, "row not restyled at " .. size)
        assert(r.d.name._text ~= "" and r.link._text ~= "")
    end
end
settings.tileHeight = 500
FL.Refresh()
assert(Rows()[1]._h == 70, "tile height not clamped")
settings.tileHeight = 46
FL.Refresh()

-- 10. invite button and tooltips
local function BtnFor(id)
    local r = Reveal(id)
    return r.PartyButton, r
end
local b1 = BtnFor(101)
assert(b1._shown and b1:IsEnabled() and b1.atlas == "friends-icon-friendsAvailable")
assert(b1._normalAtlas == "common-button-tertiary-square-normal"
    and b1._pushedAtlas == "common-button-tertiary-square-pressed" and b1._highlightAtlas == b1._normalAtlas,
    "the invite button is not in Blizzard's art")
assert(b1._w == 24 and b1._h == 24, "the invite button is 24 across on a 46 tile")
assert(b1.icon._atlas == "friends-icon-friendsAvailable" and math.abs(b1.icon._w - 22 * 24 / 34) < 0.01,
    "the icon keeps its atlas size, scaled with the button")
b1._scripts.OnClick(b1)
assert(#T.invites == 1 and T.invites[1][1] == "Player-1")
b1._scripts.OnEnter(b1)
local b2 = BtnFor(105)
b2._scripts.OnClick(b2)
assert(#T.ctxMenus == 1, "a friend on several characters opens the picker")
T.ctxMenus[1][1].onClick()
assert(#T.invites == 2)
local b3 = BtnFor(106)
assert(not b3:IsEnabled() and b3.atlas == "friends-icon-friendsAvailable-dis")
b3._scripts.OnClick(b3)
assert(#T.invites == 2, "a restricted friend was invited")
local tipsBefore = T.tooltips
b3._scripts.OnEnter(b3)
assert(T.tooltips == tipsBefore + 1 and T.lastTip:find("Cannot invite"))
-- an offline friend keeps the button, off, and says why
local offBtn, offRow = BtnFor(103)
assert(offBtn._shown and not offBtn:IsEnabled() and offBtn.atlas == "friends-icon-friendsAvailable-dis")
offBtn._scripts.OnEnter(offBtn)
assert(T.tooltips == tipsBefore + 2 and T.lastTip:find("Friend is offline"), T.lastTip)
offBtn._scripts.OnClick(offBtn)
assert(#T.invites == 2, "an offline friend was invited")
-- the hover arrives as the frame's or as the link's: one highlight, one tooltip
local _, row = BtnFor(101)
row.hit._scripts.OnHyperlinkEnter(row.hit, "link")
assert(T.tooltips == tipsBefore + 3 and T.lastTip:find("Alphachar"), T.lastTip)
assert(row.d.hoverBar._shown and row.d.hoverFill._shown, "no hover highlight")
row.hit._scripts.OnEnter(row.hit)
assert(T.tooltips == tipsBefore + 3, "the second hover script repeated the tooltip")
row.hit._scripts.OnLeave(row.hit)
assert(not row.d.hoverBar._shown and not row.d.hoverFill._shown, "the hover highlight stayed")
row.hit._scripts.OnHyperlinkLeave(row.hit)
local other = Reveal(107)
other.hit._scripts.OnEnter(other.hit)
assert(T.lastTip:find("Playing another game"), T.lastTip)
other.hit._scripts.OnLeave(other.hit)
T.ScrollTo(0)

-- 11. ungrouped section off
settings.showUngrouped = false
FL.Refresh()
assert(HeaderFor("_ungrouped") == nil)
settings.showUngrouped = true
FL.Refresh()
assert(HeaderFor("_ungrouped"))

-- 12. the view hides: nothing listens; Blizzard's list stays covered
HideView()
assert(next(ev._events) == nil and LiveMenus() == 0 and not root._shown)
assert(view.ScrollBox._alpha == 0 and Kit._listShown == true)
ShowView()
assert(ev._events.BN_FRIEND_INFO_CHANGED and LiveMenus() == 2 and root._shown)

-- 13. a controller interface: the list stands down and Blizzard's shows
HideView()
T.gamepad = true
ShowView()
assert(not root._shown and view.ScrollBox._alpha == 1 and Kit._listShown == false and LiveMenus() == 0)
HideView()
T.gamepad = false
ShowView()
assert(root._shown and view.ScrollBox._alpha == 0)

-- 14. the option off: everything stands down, the driver hides
settings.customList = false
FL.Refresh()
assert(not root._shown and view.ScrollBox._alpha == 1 and view.ScrollBar._alpha == 1 and Kit._listShown == false)
assert(next(ev._events) == nil and LiveMenus() == 0 and not driver._shown)
settings.customList = true
FL.Refresh()
assert(root._shown and view.ScrollBox._alpha == 0 and #Rows() > 3)

-- 15. an empty friends list and a dropped connection
local saved = {}
for i = #T.friends, 1, -1 do saved[i] = table.remove(T.friends, i) end
ev._scripts.OnEvent(ev, "BN_DISCONNECTED")
Flush()
assert(#Rows() == 0 and #Headers() == 0)
for i = 1, #saved do T.friends[i] = saved[i] end
ev._scripts.OnEvent(ev, "BN_CONNECTED")
Flush()
assert(#Rows() > 3)

-- 16. a menu callback replayed at registration adds nothing, pointer on the list or not
HideView()
T.mouseOver = root
local replaysBefore = #T.replayMenus
ShowView()
T.mouseOver = nil
assert(#T.replayMenus == replaysBefore + 2, "two menu tags register on show")
for i = replaysBefore + 1, #T.replayMenus do
    assert(#T.replayMenus[i].made == 0, "a replayed menu got entries")
end

-- 17. Blizzard's cards stay unpainted under the list and are caught up when it stands down
local cardHook
for _, h in ipairs(T.hooks) do
    if h.target == FriendsListSocialCardMixin and h.name == "Initialize" then cardHook = h.fn end
end
assert(cardHook, "the kit's card hook is missing")
local card = T.MakeObj("Button", view.ScrollBox)
card.elementData = { friendIndex = 1, accountInfo = C_BattleNet.GetFriendAccountInfo(1) }
card.PartyButton = T.MakeObj("Button", card)
cardHook(card)
local kitData = T.ffd[1][card]
assert(kitData and not kitData.skinned, "a covered card was painted")
settings.customList = false
FL.Refresh()
assert(kitData.skinned == true, "the card was not caught up as the list stood down")
settings.customList = true
FL.Refresh()
-- our own rows are in the kit's frame data too, and the catch-up leaves them alone
for _, r in ipairs(Rows()) do
    assert(T.ffd[1][r] and r.elementData == nil)
end

-- 18. a reused row under the pointer shows the new friend; a row leaving view drops the hover
T.ScrollTo(0)
local first = Rows()
table.sort(first, function(a, b) return a.posY < b.posY end)
local hovered = first[1]
local hoveredId = hovered.rec.id
hovered.hit._scripts.OnEnter(hovered.hit)
assert(hovered.d.hoverBar._shown and T.lastTip ~= nil)
local tipsNow = T.tooltips
-- the friend under the pointer changes in place: the tooltip follows
T.friends[1].area = "Booty Bay"
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", 1)
if hoveredId == 101 then
    assert(T.tooltips == tipsNow + 1 and T.lastTip:find("Booty Bay"), "the hovered row's tooltip did not follow")
end
-- scrolled away: the row hides, and with it the hover
T.ScrollTo(T.MaxScroll())
assert(not hovered._shown or hovered.rec.id ~= hoveredId, "the hovered row is still on its old friend")
T.ScrollTo(0)

-- 19. a rebuild keeps the scroll spot, and pulls back a scroll past the new end
T.ScrollTo(T.MaxScroll())
local atEnd = sf._scroll
assert(atEnd > 0)
local thumbBefore = T.thumbUpdates
ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 150)
Flush()
assert(sf._scroll == atEnd, "a rebuild moved the scroll")
assert(T.thumbUpdates > thumbBefore, "the scroll bar was not synced after a rebuild")
-- collapse the big section while scrolled to its end
local big = HeaderFor("_ungrouped")
if not big then
    T.ScrollTo(0)
    big = HeaderFor("_ungrouped")
    T.ScrollTo(T.MaxScroll())
end
EllesmereUIDB.global.friendUngroupedCollapsed = true
ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 150)
Flush()
assert(sf._scroll <= T.MaxScroll(), "the scroll was left past the end")
assert(#Headers() >= 1, "nothing in view after the list shrank")
EllesmereUIDB.global.friendUngroupedCollapsed = false
ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 150)
Flush()
T.ScrollTo(0)

-- 20. every shown row sits where its item says and no two share a spot
local seen = {}
for _, r in ipairs(Rows()) do
    assert(r.item and r.posY == r.item.y, "a shown row is off its item")
    assert(not seen[r.posY], "two rows share a spot")
    seen[r.posY] = true
end
for _, h in ipairs(Headers()) do
    assert(h.item and h.posY == h.item.y and not seen[h.posY], "a header overlaps")
    seen[h.posY] = true
end

-- 21. a setting changed while the friends window is closed keeps Blizzard's list covered
HideView()
settings.tileHeight = 40
FL.Refresh()
assert(view.ScrollBox._alpha == 0 and Kit._listShown == true, "a settings change with the window closed uncovered the list")
assert(next(ev._events) == nil and not root._shown)
ShowView()
assert(root._shown and Rows()[1]._h == 40, "the new tile height was not taken at the next show")
settings.tileHeight = 46
FL.Refresh()
assert(Rows()[1]._h == 46)
-- friends disabled by the game: the list stands down at the next show
HideView()
C_SocialRestrictions.IsFriendsDisabled = function() return true end
ShowView()
assert(not root._shown and view.ScrollBox._alpha == 1 and Kit._listShown == false)
HideView()
C_SocialRestrictions.IsFriendsDisabled = function() return false end
ShowView()
assert(root._shown and view.ScrollBox._alpha == 0)

-- 22. a new accent colour repaints the section names
assert(#EllesmereUI._accentElements == 1, "one accent callback")
local headBefore = Headers()[1]
headBefore.style = -1
EllesmereUI._accentElements[1].fn()
assert(Headers()[1].style ~= -1, "the accent callback did not restyle")

-- 23. the lines: the Battle.net name, the character in brackets, the status icon; the place below
T.ScrollTo(0)
local alpha = Reveal(101)
assert(alpha.d.name._text:find("Kq101", 1, true) and not alpha.d.name._text:find("Alphachar", 1, true),
    "line 1 starts with the Battle.net name alone: " .. alpha.d.name._text)
assert(alpha.d.charLine._shown, "the character is not shown")
assert(alpha.d.charLine._text:find("^|cff808080%(|r.*Alphachar.*Lvl 60.*|cff808080%)|r$"),
    "the character must sit in brackets: " .. alpha.d.charLine._text)
assert(not alpha.d.info._text:find("Alphachar", 1, true) and alpha.d.info._text ~= "",
    "the line below holds the place alone: " .. alpha.d.info._text)
assert(alpha.d.name._fontSize == 14 and alpha.d.charLine._fontSize == 12 and alpha.d.info._fontSize == 12,
    "text sizes changed")
assert(alpha.status._shown and alpha.status._atlas == "friends-status-online" and not alpha.d.orb._shown,
    "Blizzard's status icon, not the kit's orb")
assert(alpha.status._lastPoint[2] == alpha.d.charLine, "the status icon follows the character")
assert(Reveal(103).status._atlas == "friends-status-offline")
assert(Reveal(141).status._atlas == "friends-status-away")
assert(Reveal(142).status._atlas == "friends-status-busy")
local golf = Reveal(107)
assert(not golf.d.charLine._shown and golf.status._lastPoint[2] == golf.d.name,
    "a friend in another game has no character: the status follows the name")
-- a status the game keeps secret counts as not set
T.friends[41].afk = SECRET_MARK
issecretvalue = function(v) return v == SECRET_MARK end
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED")
Flush()
assert(Reveal(141).status._atlas == "friends-status-online", "a secret status was read")
issecretvalue = function() return false end
T.friends[41].afk = true
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED")
Flush()
T.ScrollTo(0)

-- 24. a left click selects, a second lets go, another row takes over; a right click is not ours
local one, two = Rows()[1], Rows()[2]
local sounds = T.sounds
T.mouseOver = one
one._scripts.OnMouseUp(one, "RightButton")
assert(not one.selected, "a right click selected")
one._scripts.OnMouseUp(one, "LeftButton")
assert(one.selected and one.d.selBar._shown and one.d.selFill._shown, "no selected look")
assert(T.sounds == sounds + 1)
T.mouseOver = two
two._scripts.OnMouseUp(two, "LeftButton")
assert(two.selected and two.d.selBar._shown and not one.selected and not one.d.selBar._shown,
    "the selection did not move")
T.mouseOver = nil
two._scripts.OnMouseUp(two, "LeftButton")
assert(two.selected, "a release off the row changed the selection")
-- it follows the friend through a rebuild and a scroll
local picked = two.rec.id
ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 150)
Flush()
assert(RowFor(picked).selected and RowFor(picked).d.selBar._shown, "the selection was lost in a rebuild")
T.ScrollTo(T.MaxScroll())
for _, r in ipairs(Rows()) do
    assert(r.selected == (r.rec.id == picked), "a reused row kept the selected look")
end
T.ScrollTo(0)
T.mouseOver = RowFor(picked)
RowFor(picked)._scripts.OnMouseUp(RowFor(picked), "LeftButton")
assert(not RowFor(picked).selected and not RowFor(picked).d.selBar._shown, "a second click did not let go")
RowFor(picked)._scripts.OnMouseUp(RowFor(picked), "LeftButton")
T.mouseOver = nil
-- closing the window lets go
HideView()
ShowView()
for _, r in ipairs(Rows()) do assert(not r.selected and not r.d.selBar._shown, "the selection outlived the window") end

-- 25. every row is made ahead with its routing; one made in combat is routed as combat ends
local function AllRows()
    return Frames(function(f) return f._parent == content and rawget(f, "hit") ~= nil end)
end
for _, r in ipairs(AllRows()) do assert(r.routed and r.hit._pass, "a row made out of combat is not routed") end
local madeBefore = #AllRows()
T.combat = true
sf._h = 2400
sf._scripts.OnSizeChanged(sf)
local fresh = 0
for _, r in ipairs(AllRows()) do
    if not r.routed then
        fresh = fresh + 1
        assert(r.hit._pass == nil)
    end
end
assert(#AllRows() > madeBefore and fresh == #AllRows() - madeBefore, "rows made in combat must wait")
assert(T.deferred.FriendsListRoute, "the routing was not queued for the end of combat")
T.EndCombat()
for _, r in ipairs(AllRows()) do
    assert(r.routed and r.hit._pass[1] == "LeftButton", "a row was left unrouted after combat")
end
sf._h = 400
sf._scripts.OnSizeChanged(sf)

note(("popups shown: %d, tooltips: %d, search calls: %d"):format(#T.popups, T.tooltips, T.searchCalls))
print(table.concat(out, "\n"))
print("friends list harness: ok")
