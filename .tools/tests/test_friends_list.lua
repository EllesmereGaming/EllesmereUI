-- Stub harness: loads the friends kit and the custom friends list outside the
-- game and drives the list through its paths: start, live, scrolling, friend
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
    gamepad = false, modify = {}, methods = METHODS, replayMenus = {}, ffd = {},
    combat = false, deferred = {}, sounds = 0 }

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
format = string.format
function issecretvalue() return false end
function InCombatLockdown() return TEST.combat == true end
-- The frame under the pointer, as the game lists it, and the buttons held
function GetMouseFoci() return { TEST.mouseFocus } end
function IsMouseButtonDown(button) return TEST.held ~= nil and TEST.held[button] == true end
function PlaySound() TEST.sounds = TEST.sounds + 1 end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
BNET_CLIENT_WOW = "WoW"
WOW_PROJECT_ID = 1
FAVORITES, FRIENDS = "Favorites", "Friends"
FRIENDS_LEVEL_TEMPLATE = "Level %d %s"
SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT = "Lvl %d"
FRIENDS_GRAY_COLOR = { WrapTextInColorCode = function(_, text) return "|cff808080" .. text .. "|r" end }
DARKGRAY_COLOR = { WrapTextInColorCode = function(_, text) return "|cff404040" .. text .. "|r" end }
SET_NOTE, REMOVE_FRIEND = "Set Note", "Remove Friend"
ADD_FAVORITE_STATUS, REMOVE_FAVORITE_STATUS = "Add Favorite", "Remove Favorite"
RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.7, b = 1 } }
function GetClassInfo(id) return "Mage", "MAGE" end
function GetCurrentRegion() return 1 end
Enum = { TitleIconVersion = { Medium = 1, Small = 0 }, BattleNetFriendLevel = { BattleTag = 2, Title = 3 } }

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
        if k == "IsMouseMotionFocus" then return function(self) return TEST.motionFocus == self end end
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
        -- The game refuses click and motion routing in combat, on every frame
        if k == "SetPassThroughButtons" then
            return function(self, ...)
                assert(not TEST.combat, "click routing set in combat")
                self._pass = { ... }
            end
        end
        if k == "SetPropagateMouseMotion" then
            return function(self, v)
                assert(not TEST.combat, "motion routing set in combat")
                self._motionDown = v
            end
        end
        if k == "SetFrameLevel" then return function(self, level) self._level = level end end
        if k == "SetMouseClickEnabled" then return function(self, v) self._clicks = v end end
        if k == "SetMouseMotionEnabled" then return function(self, v) self._motion = v end end
        if k == "EnableMouse" then return function(self, v) self._mouse = v end end
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
        if k == "SetTextColor" then return function(self, ...) self._color = { ... } end end
        if k == "GetText" then return function(self) return self._text end end
        if k == "SetFont" then
            return function(self, path, size)
                assert(type(path) == "string" and type(size) == "number" and size > 0, "bad SetFont")
                -- A plain SetFont pins a string's face: never on one that has a font family
                assert(not self._family, "plain SetFont on a font family string")
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
        if k == "SetAllPoints" then return function(self, rel) self._allPoints = rel end end
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

-- Blizzard's scroll bar, reduced to what binds it to a list: every change of its spot tells its
-- listener, the list's own writes included, and an arrow press or a wheel tick tells it twice, as
-- the game's does. A wheel tick is the game's step: twice the arrow's, at once (no easing).
ScrollBarMixin = { Event = { OnScroll = "OnScroll" } }
local function MakeScrollBar(o)
    local function Unit(v) return math.max(0, math.min(1, v)) end
    o._pct, o._visible, o._pan, o._sets, o._ranges = 0, 0, 0.1, 0, 0
    function o:RegisterCallback(event, fn, owner)
        assert(event == "OnScroll" and type(fn) == "function" and self._listener == nil, "one OnScroll listener")
        self._listener = function(pct) fn(owner, pct) end
    end
    function o:SetVisibleExtentPercentage(v)
        self._visible, self._ranges = Unit(v), self._ranges + 1
    end
    function o:SetPanExtentPercentage(v) self._pan = Unit(v) end
    function o:SetScrollPercentage(v)
        self._pct, self._sets = Unit(v), self._sets + 1
        if self._listener then self._listener(self._pct) end
    end
    function o:ScrollStepInDirection(direction)
        self:SetScrollPercentage(self._pct + self._pan * direction)
        if self._listener then self._listener(self._pct) end
    end
    function o:OnMouseWheel(value)
        local direction = value < 0 and 1 or -1
        self:SetScrollPercentage(self._pct + Unit(self._pan * 2) * direction)
        if self._listener then self._listener(self._pct) end
    end
    -- The template's own wheel script
    o._scripts.OnMouseWheel = function(self, value) self:OnMouseWheel(value) end
    TEST.bar = o
end

function CreateFrame(kind, name, parent, template)
    assert(type(kind) == "string")
    local o = MakeObj(kind, parent, template)
    if template == "MinimalScrollBar" then MakeScrollBar(o) end
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
        gameAccountInfo = gi, friendLevel = f.friendLevel,
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
    -- The game refuses this call to an addon (a blocked action): the list must never make it
    SearchFriends = function() error("C_BattleNet.SearchFriends called from addon code") end,
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
view.FilterBar = { SearchBar = MakeObj("EditBox", view), SearchFilterDropdown = MakeObj("DropdownButton", view) }
view.selectedSearchFilterOptions = {}
view.RefreshSearchResults = function() end
-- Blizzard's own list keeps the friends its search let through as a tree: a section per header
-- (Favorites, Friends), each opening with a spacer, and a spacer between the two.
-- TEST.searchResult = the friend indexes that passed (nil: every friend).
local function TreeNode(data, kids)
    return { GetData = function() return data end, GetNodes = function() return kids or {} end }
end
view.ScrollBox.GetDataProvider = function()
    TEST.searchCalls = TEST.searchCalls + 1
    if TEST.providerBroken then error("no view") end
    local list = TEST.searchResult
    if not list then
        list = {}
        for i = 1, #TEST.friends do list[i] = i end
    end
    local favorites, others = { TreeNode({ isSpacer = true }) }, { TreeNode({ isSpacer = true }) }
    for _, index in ipairs(list) do
        local into = TEST.friends[index].fav and favorites or others
        into[#into + 1] = TreeNode({ friendIndex = index, accountInfo = {} })
    end
    local root = TreeNode(nil, {
        TreeNode({ headerType = 1 }, favorites), TreeNode({ isSpacer = true }), TreeNode({ headerType = 2 }, others),
    })
    return { GetRootNode = function() return root end }
end
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
function EllesmereUI.PrimeFontShadow(fs)
    assert(not (fs and fs._family), "PrimeFontShadow on a font family string")
end
-- The shared font family helper, as far as the list reads it back: the face and size
TEST.families = 0
function EllesmereUI.SetFontFamily(fs, path, size, flags, shadow)
    assert(type(path) == "string" and type(size) == "number" and size > 0, "bad SetFontFamily")
    assert(type(flags) == "string" and type(shadow) == "boolean", "bad SetFontFamily flags or shadow")
    fs._font, fs._fontSize, fs._family = path, size, true
    TEST.families = TEST.families + 1
end
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
function EllesmereUI.HideWidgetTooltip() TEST.tipHides = (TEST.tipHides or 0) + 1 end
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
-- The list scrolls as Blizzard's does, with no easing: it takes no smooth scroll helper
function EllesmereUI.AttachSmoothScrollbar()
    error("the list took the smooth scroll helper")
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
    factionBanners = false, showRegionIcons = true, tileHeight = 46 }
local function Settings() return settings end

-- friends: a favorite, two carrying an old note tag, one added by character, then a crowd
T.AddFriend({ id = 101, tag = "Alpha#1", online = true, char = "Alphachar", level = 60, class = "Mage",
    area = "Stormwind", guid = "Player-1", fav = true })
T.AddFriend({ id = 102, tag = "Bravo#2", online = true, char = "Bravochar", level = 44, class = "Mage",
    area = "Orgrimmar", guid = "Player-2", note = "raid buddy ||EUI:Raiders||" })
T.AddFriend({ id = 103, tag = "Charlie#3", online = false, note = "||EUI:Raiders||" })
T.AddFriend({ id = 104, title = "Deltachar", online = true, char = "Deltachar", level = 12, class = "Mage",
    area = "Elwynn", guid = "Player-4", friendLevel = Enum.BattleNetFriendLevel.Title })
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

-- 0. the kit's tiles start (the WoW Forever card's host under its own tiles: online friends' rows wear
--    Blizzard's card art at a quarter)
FriendsListSocialCardMixin = { Initialize = function() end, SetSelected = function() end }
local before = #T.frames
Kit.StartTiles({ Settings = Settings, style = "eui", fontKey = "blizzardSkin", onlineCards = 0.25 })
assert(#T.frames == before, "the tiles built a frame as they started")
assert(FL.Available() == true)
local lo, hi, def = FL.TileRange()
assert(lo == 24 and hi == 70 and def == 40)

-- 1. the list starts with its host (whose settings leave its switch, customTiles, unset), and only
--    its driver exists until the view shows
FL.Start()
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
-- The list moves the way a drag of the bar's thumb moves it
function T.MaxScroll() return math.max(0, content:GetHeight() - sf:GetHeight()) end
function T.ScrollTo(v)
    local max = T.MaxScroll()
    T.bar:SetScrollPercentage(max > 0 and math.max(0, math.min(max, v)) / max or 0)
end
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
-- One hidden one-shot frame: the redraw
local oneShots = Frames(function(f) return f._scripts.OnUpdate ~= nil and f._parent == nil end)
assert(#oneShots == 1 and not oneShots[1]._shown, "expected one hidden one-shot frame")
local flusher = oneShots[1]
local function Flush()
    if flusher._shown then flusher._scripts.OnUpdate(flusher) end
end
-- A click on a row as the game routes it. The row's click layer, while it shows, lies over the
-- link and takes every button it does not pass down; a button it passes down, or any button while
-- the layer is hidden, reaches the link, where Blizzard's handler runs (the friend menu on the
-- right button, a whisper on any other). Returns which of the two took the click; `reached`
-- lists what Blizzard's handler saw. over = false: the pointer left the row before the release.
local reached = {}
local function Click(r, button, over)
    local catch = r.catch
    if catch._shown then
        local passed = false
        for _, b in ipairs(catch._pass or {}) do
            if b == button then passed = true end
        end
        if not passed then
            T.mouseOver = over ~= false and catch or nil
            local up = catch._scripts.OnMouseUp
            if up then up(catch, button) end
            T.mouseOver = nil
            return "layer"
        end
    end
    reached[#reached + 1] = { r.rec.id, button }
    return "link"
end
local function LinkUp(r) return r.link._text:find("^|HBNplayer:") ~= nil and r.hit._clicks ~= false end
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
-- Texts that show players' writing take font families: the group names and the tile lines
for _, h in ipairs(headers) do assert(h.label._family and h.label._fontSize == 12, "header name not a font family") end
for _, r in ipairs(rows) do
    assert(r.d.name._family and r.d.charLine._family and r.d.info._family, "tile line not a font family")
    assert(not r.link._family, "the link layer keeps its plain font")
    assert(r.link._text:find("^|HBNplayer:|Kq%d+|k:%d+:0:BN_WHISPER:|Kq%d+|k|hM+|h$"), "bad link: " .. r.link._text:sub(1, 60))
    assert(r.link._fontSize == 54, "link font must be the tile height + 8")
    assert(r.hit._scripts.OnClick == nil and r.hit._scripts.OnMouseUp == nil and r.hit._scripts.OnMouseDown == nil
        and r.hit._scripts.OnHyperlinkClick == nil, "a click script on the link layer")
    assert(r.hit._template == "InlineHyperlinkFrameTemplate", "the link layer is not Blizzard's template")
    assert(next(r.hit._hooks) == nil, "a script hook on the link layer")
    assert(r.hit._pass == nil and r.hit._clicks == nil, "the link layer's own clicks were touched")
    assert(r._scripts.OnMouseUp == nil and r._scripts.OnClick == nil, "a click script on the row itself")
    assert(LinkUp(r), "a row at rest has its link and takes clicks")
    -- the click layer: a frame of ours over the link and under the invite button, there all the
    -- time, taking every button but the right one and handing the pointer's movement down
    local catch = r.catch
    assert(catch and catch._kind == "Frame" and catch._parent == r and catch._template == nil and catch._shown,
        "no click layer of ours over the link")
    assert(catch._level == r.hit._level + 1 and catch._level < r.PartyButton._level,
        "the click layer is not between the link and the invite button")
    assert(#catch._pass == 1 and catch._pass[1] == "RightButton", "the click layer does not pass the right button alone down")
    assert(catch._motionDown == true, "the click layer keeps the pointer's movement from the link")
    assert(catch._scripts.OnMouseUp ~= nil and catch._scripts.OnClick == nil and catch._scripts.OnMouseDown == nil)
    assert(r._h == 46 and r._w == 380 - 10 - 7, "a tile is not inset as Blizzard's cards are")
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
assert(fav.up.off == true and fav.edit._shown and not fav.x._shown,
    "Favorites is first, has the pencil for its colour and cannot be deleted")
raid.up._scripts.OnClick(raid.up)
assert(Headers()[1].key == "Raiders", "the section did not move up")
raid = HeaderFor("Raiders")
raid.down._scripts.OnClick(raid.down)
assert(Headers()[1].key == "_favorites")
-- each icon says what it does on hover; an arrow that cannot move says nothing
local function TipOf(btn)
    local shown = T.tooltips
    T.lastTip = nil
    btn._scripts.OnEnter(btn)
    local tip = T.tooltips > shown and T.lastTip or nil
    btn._scripts.OnLeave(btn)
    return tip
end
raid, fav = HeaderFor("Raiders"), HeaderFor("_favorites")
assert(TipOf(raid.up) == "Move Up" and TipOf(raid.down) == "Move Down", "an arrow has no tooltip")
assert(TipOf(raid.edit) == "Edit Group" and TipOf(raid.x) == "Delete Group", "a custom group's pencil or X has no tooltip")
assert(TipOf(fav.edit) == "Change Color", "the pencil of Favorites does not say it changes the colour")
assert(TipOf(fav.up) == nil and TipOf(fav.down) == "Move Down", "the first section's up arrow offers a move it cannot make")
local hides = T.tipHides or 0
raid.x._scripts.OnEnter(raid.x)
raid.x._scripts.OnLeave(raid.x)
assert(T.tipHides == hides + 1, "an icon's tooltip stays after the pointer leaves")
-- painted again under the pointer (here by a new accent colour, which repaints every header in
-- view): the hovered icon shows what it does now, and an arrow that cannot move drops its tooltip
local function AccentChanged()
    for _, e in ipairs(EllesmereUI._accentElements) do e.fn() end
end
T.motionFocus = fav.edit
local shownNow = T.tooltips
AccentChanged()
assert(T.tooltips == shownNow + 1 and T.lastTip == "Change Color", "a hovered icon painted again lost its tooltip")
T.motionFocus = fav.up
shownNow, hides = T.tooltips, T.tipHides
AccentChanged()
assert(T.tooltips == shownNow and T.tipHides == hides + 1, "a hovered arrow that cannot move kept a tooltip")
T.motionFocus = nil
-- the name is part of the bar: nothing but the four icons lies over it, so a click on the name
-- collapses like a click anywhere else on the bar
for _, h in ipairs(Headers()) do
    assert(rawget(h, "pick") == nil, "a button over a section's name still takes its click")
    for _, f in ipairs(Frames(function(f) return f._parent == h and (f._kind == "Button" or f._kind == "Frame") end)) do
        assert(f == h.up or f == h.down or f == h.edit or f == h.x, "a frame over a header besides its four icons")
    end
end
-- a custom group's colour is picked in its edit popup, on the swatch beside the name; the pick
-- repaints the section names alone (the friends are not read again)
local infoReads, realInfo = 0, C_BattleNet.GetFriendAccountInfo
C_BattleNet.GetFriendAccountInfo = function(i) infoReads = infoReads + 1; return realInfo(i) end
raid = HeaderFor("Raiders")
raid.edit._scripts.OnClick(raid.edit)
local edit = T.popups[#T.popups]
assert(edit.title == "Rename Friend Group" and edit.initialText == "Raiders" and type(edit.swatch) == "table",
    "the edit popup has no colour swatch")
local cr, cg, cb = edit.swatch.get()
assert(cr == 0.05 and cg == 0.82 and cb == 0.62, "a group with no colour of its own does not show the accent")
T.combat = true
T.picker = nil
edit.swatch.onClick(raid.edit, function() error("repainted with no pick") end)
assert(T.picker == nil, "the colour picker opened in combat")
T.combat = false
local repaints = 0
edit.swatch.onClick(raid.edit, function() repaints = repaints + 1 end)
assert(T.picker and T.picker.r == 0.05 and T.picker.hasOpacity == false, "the swatch did not open the colour picker")
T.picker.swatchFunc()
assert(g.friendGroupColors.Raiders and g.friendGroupColors.Raiders.r == 1 and repaints == 1)
cr, cg, cb = edit.swatch.get()
assert(cr == 1 and cg == 0 and cb == 0, "the swatch does not show the picked colour")
local shownColor = HeaderFor("Raiders").label._color
assert(shownColor[1] == 1 and shownColor[2] == 0 and shownColor[3] == 0, "the section name did not take the picked colour")
-- the picker's own cancel puts the old colour back
T.picker.cancelFunc()
assert(g.friendGroupColors.Raiders == nil and repaints == 2 and HeaderFor("Raiders").label._color[1] == 0.05)
-- a colour kept in the picker stays when the popup is cancelled: its buttons are the name's alone
assert(edit.onCancel == nil and edit.onDismiss == nil, "cancelling the rename takes a kept colour back")
-- kept and renamed: the colour moves with the name
edit.swatch.onClick(raid.edit, function() end)
T.picker.swatchFunc()
assert(infoReads == 0, "a colour pick read the friends again")
C_BattleNet.GetFriendAccountInfo = realInfo
edit.onConfirm("  Raid Team  ")
assert(g.friendGroups[1].name == "Raid Team" and g.friendGroupsByTag["Bravo#2"] == "Raid Team")
assert(g.friendGroupColors["Raid Team"] and g.friendGroupColors["Raid Team"].r == 1 and g.friendGroupColors.Raiders == nil,
    "the colour did not move with the new name")
assert(HeaderFor("Raid Team") and HeaderFor("Raid Team").label._color[1] == 1)
g.friendGroupColors["Raid Team"] = nil
-- Favorites cannot be renamed: its pencil opens the colour picker alone
local popupsBefore = #T.popups
T.picker = nil
fav = HeaderFor("_favorites")
fav.edit._scripts.OnClick(fav.edit)
assert(#T.popups == popupsBefore and T.picker, "the pencil of Favorites did not open the colour picker alone")
T.picker.swatchFunc()
assert(g.friendGroupColors._favorites.r == 1 and HeaderFor("_favorites").label._color[1] == 1)
T.picker.cancelFunc()
assert(g.friendGroupColors._favorites == nil and HeaderFor("_favorites").label._color[1] == 0.05)
-- a colour that was kept comes back whole when a later pick is cancelled
fav.edit._scripts.OnClick(fav.edit)
T.picker.swatchFunc()
fav.edit._scripts.OnClick(fav.edit)
assert(T.picker.r == 1 and T.picker.g == 0, "the picker did not open on the section's own colour")
EllesmereUI._colorPickerPopup.GetColorRGB = function() return 0, 1, 0 end
T.picker.swatchFunc()
assert(g.friendGroupColors._favorites.g == 1 and HeaderFor("_favorites").label._color[2] == 1)
T.picker.cancelFunc()
assert(g.friendGroupColors._favorites.r == 1 and g.friendGroupColors._favorites.g == 0,
    "a cancelled pick changed the colour that was kept before it")
g.friendGroupColors._favorites = nil

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
-- an emptied note saves, and deletes the note (the popup must let empty text through)
Entry(menu, "Set Note").fn()
assert(T.popups[#T.popups].allowEmpty == true, "the note popup refuses an empty note, so a note cannot be deleted")
T.popups[#T.popups].onConfirm("")
assert(T.notes[2][1] == 108 and T.notes[2][2] == "", "an emptied note was not cleared")
-- the favorite line does what picking Favorites does: Battle.net is asked, the friend leaves its
-- group and sits in Favorites at once, before Battle.net answers
Entry(menu, "Add Favorite").fn()
assert(#T.favs == 1 and T.favs[1][1] == 108 and T.favs[1][2] == true)
assert(g.friendGroupsByTag["Friend108#108"] == nil, "a friend made a favorite kept its custom group")
assert(Reveal(108).rec.bucket == "_favorites", "the friend waits for Battle.net outside Favorites")
T.ScrollTo(0)
-- and out again before that answer: the second ask is sent too
menu = MenuFor({ bnetIDAccount = "108" }, root)
assert(Entry(menu, "Remove Favorite") and not Entry(menu, "Add Favorite"), "the favorite line did not flip")
Entry(menu, "Remove Favorite").fn()
assert(#T.favs == 2 and T.favs[2][1] == 108 and T.favs[2][2] == false, "an ask was dropped while another was on its way")
assert(Reveal(108).rec.bucket == "_ungrouped")
T.ScrollTo(0)
Entry(menu, "Remove Friend").fn()
T.popups[#T.popups].onConfirm()
assert(T.removed[1] == 108)
-- a favorite is offered the sections like any other friend, less Favorites, the one it sits in
menu = MenuFor({ bnetIDAccount = "101" }, root)
local favMove = Entry(menu, "Move to Group")
assert(Entry(menu, "EllesmereUI") and favMove and not Entry(menu, "Add to Group"), "a favorite has no sections to move to")
assert(Entry(menu, "Remove Favorite") and not Entry(menu, "Add Favorite"))
local favKids = {}
for i, c in ipairs(favMove.children) do favKids[i] = c.kind == "divider" and "-" or c.text end
assert(table.concat(favKids, "|") == "New Group...|-|Raid Team|Guildies|-|Remove from Group", table.concat(favKids, "|"))
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

-- 8. search: Blizzard's search box and filter menu drive the list. Blizzard's own list runs the
--    search (the call is refused to addons); ours reads which friends it kept.
local readsBefore = T.searchCalls
ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 150)
Flush()
assert(T.searchCalls == readsBefore, "Blizzard's list was read with no search or filter on")
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
assert(T.searchCalls == readsBefore + 1, "one search, one read of Blizzard's list")
-- Blizzard's filter shows nothing while a filter is ticked, so ours does: the house X, a frame of
-- ours where a filter menu's reset button sits. A search alone does not show it (the search box
-- has its own clear button).
local filterDD = view.FilterBar.SearchFilterDropdown
local filterX = One(function(f) return f._lastPoint ~= nil and f._lastPoint[2] == filterDD end, "active-filter X")
assert(filterX._parent == root and filterX._kind == "Frame", "the active-filter X is not a frame of ours under the list")
local fxPoint = filterX._lastPoint
assert(fxPoint[1] == "CENTER" and fxPoint[3] == "TOPRIGHT" and fxPoint[4] == -3 and fxPoint[5] == 0,
    "the X is not where a filter menu's reset button sits")
assert(One(function(f) return f._parent == filterX end, "X glyph")._atlas == "uitools-icon-close")
assert(not filterX._shown, "the X shows for a search with no filter ticked")
-- an in-place change during a search rebuilds (it may change what matches)
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", 1)
assert(flusher._shown)
Flush()
-- a filter with no text; the friends come from both of Blizzard's sections
view.FilterBar.SearchBar._text = ""
view.selectedSearchFilterOptions[{ searchInfo = { isOnline = true } }] = true
view.selectedSearchFilterOptions[{ searchInfo = { tags = { 3 } } }] = true
T.searchResult = { 1, 2, 5 }
hook()
Flush()
assert(#Rows() == 3, "filter result not applied")
-- a filter is ticked: the X shows. It takes no mouse, so a click on it reaches Blizzard's Filter
-- button under it (whose menu unticks the filters); nothing of ours is set on that button.
assert(filterX._shown, "no X while a filter is ticked")
assert(filterX._mouse == nil and filterX._clicks == nil and filterX._motion == nil
    and next(filterX._scripts) == nil and next(filterX._hooks) == nil, "the X takes the mouse")
assert(next(filterDD._scripts) == nil and next(filterDD._hooks) == nil and filterDD._shown,
    "a script of ours on Blizzard's Filter button")
-- a click on a header during a search folds that section for the search alone: the saved state is
-- not touched, a rebuild keeps the fold, and a second click opens it
local raidSaved, favSaved = g.friendGroups[1].collapsed, g.friendFavCollapsed
local head = HeaderFor("Raid Team")
head._scripts.OnClick(head)
assert(RowFor(102) == nil and #Rows() == 2, "a header click during a search did not fold the section")
assert(g.friendGroups[1].collapsed == raidSaved, "a fold during a search changed the saved state")
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", 1)
Flush()
assert(RowFor(102) == nil, "a rebuild during the search opened a folded section")
head = HeaderFor("_favorites")
head._scripts.OnClick(head)
assert(RowFor(101) == nil and g.friendFavCollapsed == favSaved, "Favorites did not fold for the search alone")
head = HeaderFor("Raid Team")
head._scripts.OnClick(head)
assert(RowFor(102) ~= nil and RowFor(101) == nil and #Rows() == 2, "a second click did not open the section")
-- a filter nobody passes shows nobody
T.searchResult = {}
hook()
Flush()
assert(#Rows() == 0, "an empty result still shows friends")
-- Blizzard's list cannot be read: every friend shows, and nothing errors
T.providerBroken = true
hook()
Flush()
assert(#Rows() > 3, "an unreadable list hid the friends")
T.providerBroken = nil
assert(filterX._shown, "the X left while a filter is still ticked")
wipe(view.selectedSearchFilterOptions)
T.searchResult = nil
hook()
Flush()
assert(#Rows() > 3)
assert(not filterX._shown, "the X stayed after the last filter was unticked")
assert(RowFor(101) ~= nil and g.friendFavCollapsed == favSaved, "a fold made during the search outlived it")
-- a new search starts with every section open
view.FilterBar.SearchBar._text = "alp"
T.searchResult = { 1 }
hook()
Flush()
assert(RowFor(101) ~= nil, "a new search kept the folds of the last one")
view.FilterBar.SearchBar._text = ""
T.searchResult = nil
hook()
Flush()

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
-- no height saved: the default, two lines, with the invite button sized for it
settings.tileHeight = nil
FL.Refresh()
do
    local r = Reveal(101)
    assert(r._h == 40 and r.PartyButton._w == 26 and r.PartyButton._h == 26, "an unset tile height is not the 40 default")
    assert(r.d.info._shown ~= false and r.d.info._text ~= "", "the default tile lost its second line")
end
T.ScrollTo(0)
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
assert(b1._w == 28 and b1._h == 28, "the invite button is 28 across on a 46 tile")
assert(b1.icon._atlas == "friends-icon-friendsAvailable" and math.abs(b1.icon._w - 22 * 28 / 34) < 0.01,
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
-- an offline friend has no invite button, nor has one in another game: the
-- text runs on to the row's edge
local offBtn, offRow = BtnFor(103)
assert(not offBtn._shown, "an offline friend shows an invite button")
local offStop = offRow.d.info._lastPoint
assert(offStop[1] == "RIGHT" and offStop[2] == offRow and offStop[3] == "RIGHT" and offStop[4] == -10,
    "an offline friend's text does not use the button's room")
local gameBtn = BtnFor(107)
assert(not gameBtn._shown, "a friend in another game shows an invite button")
-- a friend playing this game keeps it, and the text stops at it
local _, row = BtnFor(101)
local onStop = row.d.info._lastPoint
assert(row.PartyButton._shown and onStop[2] == row.PartyButton and onStop[3] == "LEFT" and onStop[4] == -6)
-- a row handed from one kind of friend to the other follows the friend
T.friends[1].online = false
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", 1)
Flush()
local wasOn = BtnFor(101)
assert(not wasOn._shown, "a friend who went offline keeps the invite button")
T.friends[1].online = true
ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", 1)
Flush()
_, row = BtnFor(101)
assert(row.PartyButton._shown and row.PartyButton:IsEnabled(), "a friend back in the game has no invite button")
-- the hover arrives as the frame's or as the link's: one highlight, one tooltip
row.hit._scripts.OnHyperlinkEnter(row.hit, "link")
assert(T.tooltips == tipsBefore + 2 and T.lastTip:find("Alphachar"), T.lastTip)
assert(row.d.hoverBar._shown and row.d.hoverFill._shown, "no hover highlight")
row.hit._scripts.OnEnter(row.hit)
assert(T.tooltips == tipsBefore + 2, "the second hover script repeated the tooltip")
row.hit._scripts.OnLeave(row.hit)
assert(not row.d.hoverBar._shown and not row.d.hoverFill._shown, "the hover highlight stayed")
row.hit._scripts.OnHyperlinkLeave(row.hit)
local other = Reveal(107)
other.hit._scripts.OnEnter(other.hit)
assert(T.lastTip:find("Playing another game"), T.lastTip)
other.hit._scripts.OnLeave(other.hit)
T.ScrollTo(0)

-- 11. the ungrouped friends always show: a Show Ungrouped Friends switch an older build saved is not read
assert(HeaderFor("_ungrouped"))
settings.showUngrouped = false
FL.Refresh()
assert(HeaderFor("_ungrouped"), "a saved Show Ungrouped Friends switch hid the ungrouped friends")
settings.showUngrouped = nil

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

-- 14. a Custom Friends List switch an older build saved is not read; a client without the menu fix
--     stands everything down, the driver hides
settings.customList = false
FL.Refresh()
assert(root._shown and view.ScrollBox._alpha == 0, "a saved Custom Friends List switch stood the list down")
settings.customList = nil
local menuProxy = Menu.IsMenuProxy
Menu.IsMenuProxy = nil
FL.Refresh()
assert(not root._shown and view.ScrollBox._alpha == 1 and view.ScrollBar._alpha == 1 and Kit._listShown == false)
assert(next(ev._events) == nil and LiveMenus() == 0 and not driver._shown)
Menu.IsMenuProxy = menuProxy
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
Menu.IsMenuProxy = nil
FL.Refresh()
assert(kitData.skinned == true, "the card was not caught up as the list stood down")
Menu.IsMenuProxy = menuProxy
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
local rangesBefore = T.bar._ranges
ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 150)
Flush()
assert(sf._scroll == atEnd, "a rebuild moved the scroll")
assert(T.bar._ranges > rangesBefore, "the scroll bar was not synced after a rebuild")
-- collapse the big section while scrolled to its end
local big = HeaderFor("_ungrouped")
if not big then
    T.ScrollTo(0)
    big = HeaderFor("_ungrouped")
    T.ScrollTo(T.MaxScroll())
end
EllesmereUIDB.global.friendUngroupedCollapsed = true
local scrollWrites = 0
sf.SetVerticalScroll = function(self, v) scrollWrites = scrollWrites + 1; self._scroll = v end
ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 150)
Flush()
sf.SetVerticalScroll = nil
assert(sf._scroll <= T.MaxScroll(), "the scroll was left past the end")
assert(scrollWrites == 1, "the pull back came back from the bar")
local shrunkMax = T.MaxScroll()
if shrunkMax > 0 then
    assert(math.abs(T.bar._pct - sf._scroll / shrunkMax) < 1e-6, "the bar did not follow the pull back")
else
    assert(sf._scroll == 0 and T.bar._pct == 0, "the bar did not follow the pull back")
end
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
    "text sizes: the name 14, the character and the place 12")
assert(alpha.status._shown and alpha.status._atlas == "friends-status-online" and not alpha.d.orb._shown,
    "Blizzard's status icon, not the kit's orb")
-- the character stands 1 above the name's bottom line, the status icon after it
local charAt, statusAt = alpha.d.charLine._lastPoint, alpha.status._lastPoint
assert(charAt[1] == "BOTTOMLEFT" and charAt[2] == alpha.d.name and charAt[3] == "BOTTOMRIGHT" and charAt[4] == 5
    and charAt[5] == 1, "the character is not 1 above the name's bottom line")
assert(statusAt[1] == "BOTTOMLEFT" and statusAt[2] == alpha.d.charLine and statusAt[3] == "BOTTOMRIGHT"
    and statusAt[4] == -1 and statusAt[5] == 1, "the status icon does not follow the character")
assert(Reveal(103).status._atlas == "friends-status-offline")
assert(Reveal(141).status._atlas == "friends-status-away")
assert(Reveal(142).status._atlas == "friends-status-busy")
local golf = Reveal(107)
local loneAt = golf.status._lastPoint
assert(not golf.d.charLine._shown and loneAt[1] == "LEFT" and loneAt[2] == golf.d.name and loneAt[3] == "RIGHT"
    and loneAt[4] == -1 and loneAt[5] == 2, "a friend in another game has no character: the status follows the name")
-- the status icon stands at one height on every row, measured from the name's bottom line: its
-- middle beside a character (the character's lift, its own, half its height) and after a bare name
-- (half the name's height, its own lift)
alpha = Reveal(101)
assert(alpha.status._h == 14 and charAt[5] + statusAt[5] + alpha.status._h / 2 == golf.d.name._fontSize / 2 + loneAt[5],
    "the status icon is not level between a row with a character and one without")
-- the other tile sizes: the character is the place line's size, and the invite button a little
-- over halfway between its share of the tile and a flat 28
for _, pair in ipairs({ { 24, 13, 11, 11, 19 }, { 52, 15, 12, 12, 30 }, { 70, 15, 12, 12, 33 } }) do
    settings.tileHeight = pair[1]
    FL.Refresh()
    local row = Reveal(101)
    local d = row.d
    assert(d.name._fontSize == pair[2] and d.charLine._fontSize == pair[3] and d.info._fontSize == pair[4],
        "text sizes at a tile height of " .. pair[1])
    assert(row.PartyButton._w == pair[5] and row.PartyButton._h == pair[5],
        ("the invite button is %s across at a tile height of %d"):format(tostring(row.PartyButton._w), pair[1]))
end
settings.tileHeight = 46
FL.Refresh()
T.ScrollTo(0)
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

-- 24. a left click selects, a second lets go, another row takes over; the right click is Blizzard's.
--     The selected look is the hover look. A click layer of ours lies over each row's link and
--     takes every button but the right one, so Blizzard's handler (a whisper on anything but the
--     right button) sees right clicks alone.
local function Lit(r) return r.d.hoverBar._shown and r.d.hoverFill._shown end
local one, two = Rows()[1], Rows()[2]
local sounds = T.sounds
-- the right button goes down to the link untouched, and selects nothing
assert(Click(one, "RightButton") == "link" and #reached == 1 and reached[1][1] == one.rec.id
    and reached[1][2] == "RightButton", "a right click did not reach Blizzard's link")
assert(not one.selected and LinkUp(one), "a right click selected")
one.catch._scripts.OnMouseUp(one.catch, "RightButton")
assert(not one.selected, "the click layer acts on the right button")
-- every other button stays with the layer: Blizzard's handler never sees it, so nothing whispers
for _, button in ipairs({ "MiddleButton", "Button4", "Button5" }) do
    assert(Click(one, button) == "layer" and #reached == 1 and not one.selected, button .. " reached the link or selected")
end
assert(Click(one, "LeftButton") == "layer" and #reached == 1, "a left click reached Blizzard's link: it would whisper")
assert(one.selected and Lit(one), "no selected look")
assert(LinkUp(one), "a click took the link away")
assert(not one.d.selBar._shown and not one.d.selFill._shown, "the selected look is not the hover look")
assert(T.sounds == sounds + 1)
-- a second click lets go
Click(one, "LeftButton")
assert(not one.selected and not Lit(one), "a second click did not let go")
Click(one, "LeftButton")
assert(one.selected)
-- a release after the pointer left the row changes nothing
Click(two, "LeftButton", false)
assert(one.selected and not two.selected, "a release off the row selected")
-- the hover is the link's and the layer's alike: one highlight, one tooltip
local tipsAt = T.tooltips
two.catch._scripts.OnEnter(two.catch)
two.hit._scripts.OnEnter(two.hit)
assert(Lit(two) and T.tooltips == tipsAt + 1, "the layer and the link both showed the tooltip")
two.hit._scripts.OnLeave(two.hit)
two.catch._scripts.OnLeave(two.catch)
assert(not Lit(two), "an unselected row stayed lit")
-- the pointer passing over a selected row leaves it lit
one.hit._scripts.OnEnter(one.hit)
one.hit._scripts.OnLeave(one.hit)
assert(Lit(one), "a selected row lost its look when the pointer left")
Click(two, "LeftButton")
assert(two.selected and Lit(two) and not one.selected and not Lit(one), "the selection did not move")
-- it follows the friend through a rebuild and a scroll
local picked = two.rec.id
ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 150)
Flush()
assert(RowFor(picked).selected and Lit(RowFor(picked)), "the selection was lost in a rebuild")
T.ScrollTo(T.MaxScroll())
for _, r in ipairs(Rows()) do
    assert(r.selected == (r.rec.id == picked) and Lit(r) == r.selected, "a reused row kept the selected look")
end
T.ScrollTo(0)
Click(RowFor(picked), "LeftButton")
assert(not RowFor(picked).selected and not Lit(RowFor(picked)), "a second click did not let go")
Click(RowFor(picked), "LeftButton")
-- closing the window lets go
HideView()
ShowView()
for _, r in ipairs(Rows()) do assert(not r.selected and not Lit(r), "the selection outlived the window") end
-- the list listens to no mouse press of the whole game
assert(not ev._events.GLOBAL_MOUSE_DOWN and not ev._events.GLOBAL_MOUSE_UP, "the list hears every mouse press")
assert(#reached == 1, "a click other than the one right click reached Blizzard's link")

-- 25. combat: the game refuses click routing on every frame then, so a row made in combat keeps its
--     click layer hidden and gets it as combat ends. Until then its clicks are the link's own,
--     Blizzard's (the menu on the right button, a whisper on the left); rows made before keep theirs.
local function AllRows()
    return Frames(function(f) return f._parent == content and rawget(f, "hit") ~= nil end)
end
local madeBefore = #AllRows()
T.combat = true
sf._h = 2400
sf._scripts.OnSizeChanged(sf)
assert(#AllRows() > madeBefore, "the taller view made no rows")
local early, late
for _, r in ipairs(Rows()) do
    if r.catch._shown then early = early or r else late = late or r end
end
assert(early and late, "expected rows from before the fight and rows made in it")
assert(late.catch._pass == nil and late.catch._motionDown == nil, "a row made in combat was routed in combat")
assert(type(T.deferred.FriendsListRoute) == "function", "the routing of rows made in combat is not queued for its end")
assert(Click(early, "LeftButton") == "layer" and early.selected, "a row from before the fight does not select in combat")
Click(early, "LeftButton")
reached = {}
assert(Click(late, "RightButton") == "link" and Click(late, "LeftButton") == "link" and #reached == 2 and not late.selected,
    "a row made in combat: its clicks are the link's until combat ends")
T.EndCombat()
assert(next(T.deferred) == nil)
for _, r in ipairs(AllRows()) do
    assert(r.catch._shown and #r.catch._pass == 1 and r.catch._pass[1] == "RightButton" and r.catch._motionDown == true,
        "a row was left without its click layer after combat")
end
reached = {}
assert(Click(late, "LeftButton") == "layer" and late.selected and #reached == 0, "a row made in combat does not select after it")
Click(late, "LeftButton")
-- a second fight: nothing is routed again, nothing queued
T.combat = true
sf._scripts.OnSizeChanged(sf)
assert(next(T.deferred) == nil, "rows that have their layer were queued again")
T.combat = false
sf._h = 400
sf._scripts.OnSizeChanged(sf)

-- 26. a filter left ticked while the window was closed: Blizzard's list fills as the view shows,
--     which may come after ours, so ours reads it once more on the next frame
do
    view.selectedSearchFilterOptions[{ searchInfo = { isOnline = true } }] = true
    T.searchResult = { 1, 2 }
    hook()
    Flush()
    assert(#Rows() == 2)
    -- a section folded during the search opens again with the window
    local folded = HeaderFor("Raid Team")
    folded._scripts.OnClick(folded)
    assert(#Rows() == 1, "the fold did not take")
    HideView()
    ShowView()
    assert(#Rows() == 2, "a fold made during a search outlived the window")
    assert(filterX._shown, "the X is not back with the window while a filter is ticked")
    assert(flusher._shown, "no second read after the view showed with a filter on")
    T.searchResult = { 1 }
    Flush()
    assert(#Rows() == 1 and Rows()[1].rec.id == 101, "the list kept the friends from before the view hid")
    -- a setting changed while it shows asks for no second read
    FL.Refresh()
    assert(not flusher._shown, "a settings change asked for a second read")
    -- with no filter the view shows without a second pass
    wipe(view.selectedSearchFilterOptions)
    T.searchResult = nil
    HideView()
    ShowView()
    assert(not flusher._shown, "a second pass with no search or filter on")
    assert(#Rows() > 3)
    assert(not filterX._shown, "the X shows with no filter ticked")
end

-- 27. Favorites is a section among the groups: a custom group wins over it, the menu offers it like
--     a group, and a pick that moves a friend into it, or out of it to no group, sets Battle.net's
--     favorite switch. The friend sits where it was put at once; Battle.net's answer follows.
do
    T.ScrollTo(0)
    local function IndexOf(id)
        for i, f in ipairs(T.friends) do
            if f.id == id then return i end
        end
    end
    -- Battle.net's own word on a friend's favorite flag, as its event tells it
    local function Answer(id, fav)
        local i = IndexOf(id)
        T.friends[i].fav = fav
        ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", i)
        Flush()
    end
    local function Bucket(id)
        local bucket = Reveal(id).rec.bucket
        T.ScrollTo(0)
        return bucket
    end
    -- The friend's sections entry, then the whole menu
    local function Sub(id)
        local m = MenuFor({ bnetIDAccount = tostring(id) }, root)
        return Entry(m, "Move to Group") or Entry(m, "Add to Group"), m
    end
    local function Child(entry, text)
        for _, c in ipairs(entry.children) do
            if c.text == text then return c end
        end
    end
    local asks = #T.favs
    local function Asked(n, id, fav)
        if #T.favs ~= asks + n then return false end
        local last = T.favs[#T.favs]
        return id == nil or (last[1] == id and last[2] == fav)
    end

    -- a friend in a custom group who is a Battle.net favorite stays in the group
    Answer(102, true)
    assert(Bucket(102) == "Raid Team", "Favorites won over a custom group")
    local sub, m = Sub(102)
    assert(sub.text == "Move to Group" and Child(sub, "Favorites") and Child(sub, "Remove from Group")
        and not Child(sub, "Raid Team"), "a grouped favorite's sections")
    assert(Entry(m, "Add Favorite") and not Entry(m, "Remove Favorite"), "the favorite line follows the flag, not the section")
    -- into Favorites: Battle.net holds the flag already and is not asked
    Child(sub, "Favorites").fn()
    assert(Asked(0) and g.friendGroupsByTag["Bravo#2"] == nil and Bucket(102) == "_favorites")
    sub, m = Sub(102)
    assert(sub.text == "Move to Group" and not Child(sub, "Favorites") and Child(sub, "Raid Team")
        and Child(sub, "Remove from Group") and Entry(m, "Remove Favorite"), "a favorite's sections")
    -- out of Favorites to no group: one ask, and the friend is among the ungrouped at once
    Child(sub, "Remove from Group").fn()
    assert(Asked(1, 102, false), "leaving Favorites did not take the favorite off")
    assert(Bucket(102) == "_ungrouped", "the friend waits in Favorites for Battle.net's answer")
    Answer(102, false)
    assert(Bucket(102) == "_ungrouped" and Asked(1))
    -- once Battle.net agrees the ask is forgotten: a change made elsewhere is followed
    Answer(102, true)
    assert(Bucket(102) == "_favorites", "an answered ask still decided the section")
    Answer(102, false)
    sub = Sub(102)
    local kids = {}
    for i, c in ipairs(sub.children) do kids[i] = c.kind == "divider" and "-" or c.text end
    assert(sub.text == "Add to Group" and table.concat(kids, "|") == "New Group...|-|Favorites|Raid Team",
        "an ungrouped friend's sections: " .. table.concat(kids, "|"))
    -- a custom group is ours alone: Battle.net is not asked
    Child(sub, "Raid Team").fn()
    assert(Asked(1) and g.friendGroupsByTag["Bravo#2"] == "Raid Team", "a custom group asked Battle.net")
    -- from a group into Favorites: one ask, and never a stop among the ungrouped friends
    Child(Sub(102), "Favorites").fn()
    assert(Asked(2, 102, true) and g.friendGroupsByTag["Bravo#2"] == nil)
    assert(Bucket(102) == "_favorites", "a friend moved from a group to Favorites passed through the ungrouped friends")
    T.friends[IndexOf(102)].fav = true
    ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED", IndexOf(102))
    assert(not flusher._shown, "Battle.net's answer to a pick rebuilt the list")
    assert(Bucket(102) == "_favorites" and Asked(2))
    -- a favorite moved into a custom group stays a Battle.net favorite; out of the group to no
    -- section at all takes the favorite off too
    Child(Sub(102), "Raid Team").fn()
    assert(Asked(2) and Bucket(102) == "Raid Team")
    Child(Sub(102), "Remove from Group").fn()
    assert(Asked(3, 102, false) and g.friendGroupsByTag["Bravo#2"] == nil)
    assert(Bucket(102) == "_ungrouped", "Remove from Group left the friend in Favorites")
    Answer(102, false)
    -- the favorite line on a grouped favorite moves the friend into Favorites
    Answer(102, true)
    Child(Sub(102), "Raid Team").fn()
    _, m = Sub(102)
    Entry(m, "Add Favorite").fn()
    assert(Asked(3) and g.friendGroupsByTag["Bravo#2"] == nil and Bucket(102) == "_favorites")
    -- a deleted group's friends go back to their own sections: a favorite to Favorites
    Child(Sub(102), "New Group...").fn()
    T.popups[#T.popups].onConfirm("Temp")
    assert(Bucket(102) == "Temp" and Asked(3))
    Child(Sub(110), "Temp").fn()
    local temp = HeaderFor("Temp")
    assert(temp, "the new section is not in view")
    temp.x._scripts.OnClick(temp.x)
    assert(T.popups[#T.popups].message:find("Favorites", 1, true), "the delete prompt does not say where favorites go")
    T.popups[#T.popups].onConfirm()
    assert(Bucket(102) == "_favorites" and Bucket(110) == "_ungrouped" and Asked(3),
        "a deleted group's friends did not go back to their own sections")
    -- an ask Battle.net never answered is forgotten when the window closes
    Child(Sub(110), "Favorites").fn()
    assert(Asked(4, 110, true) and Bucket(110) == "_favorites")
    HideView()
    ShowView()
    assert(Bucket(110) == "_ungrouped", "an unanswered ask outlived the window")
    -- a friend with no BattleTag and no character to whisper has no key: no sections of ours,
    -- and the favorite line still works
    T.AddFriend({ id = 143, online = true, char = "Nokeychar", level = 5, class = "Mage", area = "Nowhere",
        guid = "Player-143" })
    ev._scripts.OnEvent(ev, "BN_FRIEND_LIST_SIZE_CHANGED", 151)
    Flush()
    m = MenuFor({ bnetIDAccount = "143" }, root)
    assert(Entry(m, "Add Favorite") and not Entry(m, "EllesmereUI") and not Entry(m, "Add to Group"),
        "a friend with no key was offered sections")
    Entry(m, "Add Favorite").fn()
    assert(Asked(5, 143, true) and Bucket(143) == "_favorites")
    -- a favorite flag the game keeps secret counts as not set
    T.friends[1].fav = SECRET_MARK
    issecretvalue = function(v) return v == SECRET_MARK end
    ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED")
    Flush()
    assert(Bucket(101) == "_ungrouped", "a secret favorite flag was read")
    issecretvalue = function() return false end
    T.friends[1].fav = true
    ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED")
    Flush()
    assert(Bucket(101) == "_favorites")
    note(("favorites: %d asks sent to Battle.net by the menu"):format(#T.favs))
end

-- 28. the scroll area and its bar match Blizzard's list: the list takes the rect of Blizzard's
--     scroll box, its tiles the insets of Blizzard's cards, and the bar is a frame of ours made from
--     the template of Blizzard's bar, laid over it. The bar follows the list and moves it.
do
    local bar = T.bar
    assert(bar and bar._kind == "EventFrame" and bar._template == "MinimalScrollBar" and bar._parent == root,
        "the scroll bar is not made from Blizzard's template under the list")
    assert(#Frames(function(f) return f._template == "MinimalScrollBar" end) == 1, "more than one scroll bar was made")
    assert(bar._allPoints == view.ScrollBar and sf._allPoints == view.ScrollBox,
        "the list and its bar do not take the rects of Blizzard's")
    assert(view.ScrollBar._alpha == 0, "Blizzard's own bar shows under ours")
    local function Near(a, b) return math.abs(a - b) < 1e-6 end
    T.ScrollTo(0)
    for _, f in ipairs(Rows()) do
        assert(f._w == sf._w - 10 - 7 and f._lastPoint[2] == content and f._lastPoint[4] == 10, "a tile's insets")
    end
    for _, f in ipairs(Headers()) do
        assert(f._w == sf._w - 10 - 7 and f._lastPoint[4] == 10, "a section header's insets")
    end
    -- how much is in view, and one tile per arrow press
    local max = T.MaxScroll()
    assert(max > 0 and Near(bar._visible, sf._h / content._h), "the thumb does not show how much is in view")
    assert(Near(bar._pan, (46 + 2) / max), "an arrow press is not one tile")
    assert(bar._pct == 0)
    -- the thumb is dragged: the list follows at once, and does not write the bar back
    local sets = bar._sets
    bar:SetScrollPercentage(0.5)
    assert(Near(sf._scroll, max / 2), "the list did not follow the bar")
    assert(bar._sets == sets + 1, "the list wrote the bar back while the bar was moving it")
    assert(#Rows() > 3, "no tiles at the spot the bar scrolled to")
    for _, f in ipairs(Rows()) do
        assert(f.posY + f._h > sf._scroll and f.posY < sf._scroll + sf._h, "a tile out of view is shown")
    end
    -- an arrow is pressed: one tile further
    local before = sf._scroll
    bar:ScrollStepInDirection(1)
    assert(Near(sf._scroll, before + 48) and Near(bar._pct, sf._scroll / max), "an arrow press did not move one tile")
    bar:ScrollStepInDirection(-1)
    assert(Near(sf._scroll, before))
    -- the wheel is the bar's own step, over the list as over the bar: two tiles a tick, the spot
    -- moved before any frame has passed (no easing)
    sf._scripts.OnMouseWheel(sf, -1)
    assert(Near(sf._scroll, before + 2 * 48) and Near(bar._pct, sf._scroll / max), "a wheel tick is not two tiles at once")
    bar._scripts.OnMouseWheel(bar, -1)
    assert(Near(sf._scroll, before + 4 * 48), "the wheel over the bar is not the list's")
    sf._scripts.OnMouseWheel(sf, 1)
    bar._scripts.OnMouseWheel(bar, 1)
    assert(Near(sf._scroll, before) and Near(bar._pct, before / max))
    -- it stops at both ends
    for _ = 1, 100 do sf._scripts.OnMouseWheel(sf, -1) end
    assert(Near(sf._scroll, max) and Near(bar._pct, 1), "the wheel ran past the end")
    for _ = 1, 100 do sf._scripts.OnMouseWheel(sf, 1) end
    assert(sf._scroll == 0 and bar._pct == 0, "the wheel ran past the top")
    -- a list that fits: all of it in view, nothing to scroll
    view.FilterBar.SearchBar._text = "alp"
    T.searchResult = { 1 }
    hook()
    Flush()
    assert(T.MaxScroll() == 0 and bar._visible == 1 and bar._pan == 0 and bar._pct == 0 and sf._scroll == 0,
        "a list that fits still shows something to scroll")
    view.FilterBar.SearchBar._text = ""
    T.searchResult = nil
    hook()
    Flush()
    assert(bar._visible < 1 and Near(bar._pan, 48 / T.MaxScroll()))
    -- another tile height: the arrow step follows
    settings.tileHeight = 24
    FL.Refresh()
    assert(Near(bar._pan, (24 + 2) / T.MaxScroll()), "the arrow step kept the old tile height")
    settings.tileHeight = 46
    FL.Refresh()
    T.ScrollTo(0)
    note(("scroll bar: %d spot changes told, %d range changes"):format(bar._sets, bar._ranges))
end

-- 29. the list's switch (customTiles, the Forever card's Custom Friends List Tiles): off stands the
--     list down and Blizzard's list shows, its cards caught up; on brings the list back
do
    local card = T.MakeObj("Button", view.ScrollBox)
    card.elementData = { friendIndex = 2, accountInfo = C_BattleNet.GetFriendAccountInfo(2) }
    card.PartyButton = T.MakeObj("Button", card)
    cardHook(card)
    local d = T.ffd[1][card]
    assert(d and not d.skinned, "a covered card was painted")
    settings.customTiles = false
    FL.Refresh()
    assert(not root._shown and view.ScrollBox._alpha == 1 and view.ScrollBar._alpha == 1 and Kit._listShown == false,
        "the switch did not stand the list down")
    assert(next(ev._events) == nil and LiveMenus() == 0 and not driver._shown, "the list still runs while off")
    assert(d.skinned == true, "Blizzard's card was not caught up as the switch stood the list down")
    settings.customTiles = true
    FL.Refresh()
    assert(root._shown and view.ScrollBox._alpha == 0 and Kit._listShown == true and #Rows() > 3,
        "the switch did not bring the list back")
    assert(ev._events.BN_FRIEND_INFO_CHANGED and LiveMenus() == 2)
    settings.customTiles = nil
    FL.Refresh()
    assert(root._shown and view.ScrollBox._alpha == 0, "settings without the switch stood the list down")
    -- the switch turned off with no refresh (an import): read as the view shows again
    HideView()
    settings.customTiles = false
    ShowView()
    assert(not root._shown and view.ScrollBox._alpha == 1 and Kit._listShown == false and LiveMenus() == 0,
        "the view showed the list while its switch was off")
    settings.customTiles = nil
    FL.Refresh()
    assert(root._shown and view.ScrollBox._alpha == 0)
end

-- 30. Blizzard's online card art (onlineCards). Under the card's own tiles (this harness's host) an
--     online friend's row wears it at a quarter, under the tile's shade and online tint, which show as
--     before. Then a host without its cards (the Forever card under Blizz Default with Custom Friends
--     List Tiles on), started later in the session: a fresh kit and list. Nothing hooks Blizzard's
--     cards, the list draws its own tiles over Blizzard's list, its online friends' rows wear the card
--     whole in place of the shade and tint, and standing it down leaves Blizzard's cards be.
do
    Flush()
    local seen0 = { online = 0, offline = 0, title = 0 }
    for _, r in ipairs(Rows()) do
        local card, d = rawget(r, "card"), r.d
        assert(card and card._alpha == 0.25 and rawget(r, "cardWhole") == false,
            "a row under the card's own tiles has no faint card")
        assert(d.tileBg._shown, "a row under the card's own tiles lost the tile's shade")
        if r.rec.online then
            local want = r.rec.id == 104 and "friends-card-default" or "friends-card-battleNet"
            assert(card._shown and card._atlas == want and d.onlineBg._shown,
                "an online friend's row under the card's own tiles: " .. tostring(r.rec.id))
            seen0.online = seen0.online + 1
            if r.rec.id == 104 then seen0.title = seen0.title + 1 end
        else
            assert(not card._shown and not d.onlineBg._shown, "an offline friend's row wears the card or the tint")
            seen0.offline = seen0.offline + 1
        end
    end
    assert(seen0.online > 0 and seen0.offline > 0,
        ("the rows in view: %d online, %d offline"):format(seen0.online, seen0.offline))
    if seen0.title == 0 then
        local r = Reveal(104)
        assert(r.card._shown and r.card._atlas == "friends-card-default" and r.d.onlineBg._shown,
            "a game-level friend's row under the card's own tiles")
    end
    -- a friend going offline drops the card and the tint, coming back brings both back
    local r101 = Reveal(101)
    T.friends[1].online = false
    ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED")
    Flush()
    r101 = RowFor(101)
    assert(r101 and not r101.card._shown and not r101.d.onlineBg._shown and r101.d.tileBg._shown,
        "a friend gone offline kept the card or the tint")
    T.friends[1].online = true
    ev._scripts.OnEvent(ev, "BN_FRIEND_INFO_CHANGED")
    Flush()
    r101 = RowFor(101)
    assert(r101 and r101.card._shown and r101.card._atlas == "friends-card-battleNet" and r101.d.onlineBg._shown
        and r101.d.tileBg._shown, "a friend back online did not take the card and the tint back")

    settings.customTiles = false
    FL.Refresh()
    assert(view.ScrollBox._alpha == 1 and LiveMenus() == 0)
    local hooksBefore, ffdBefore, framesBefore = #T.hooks, #T.ffd, #T.frames
    assert(loadstring(KIT_SRC, "=EllesmereUI_FriendsKit.lua"))("EllesmereUI", {})
    assert(loadstring(LIST_SRC, "=EllesmereUI_FriendsList.lua"))("EllesmereUI", {})
    local Kit2, FL2 = EllesmereUI.FriendsKit, EllesmereUI.FriendsList
    assert(Kit2 ~= Kit and FL2 ~= FL and #T.ffd == ffdBefore + 1)
    local function NewFrames(pred)
        local list = {}
        for i = framesBefore + 1, #T.frames do
            if pred(T.frames[i]) then list[#list + 1] = T.frames[i] end
        end
        return list
    end
    local s2 = { enabled = true, showClassIcons = true, iconStyle = "modern", classColorNames = true,
        factionBanners = false, showRegionIcons = true, tileHeight = 40, customTiles = true }
    local host2 = { Settings = function() return s2 end, style = "eui", fontKey = "blizzardSkin", cards = false,
        onlineCards = 1 }
    Kit2.StartTiles(host2)
    assert(#T.hooks == hooksBefore, "a host without its cards hooked Blizzard's cards")
    assert(Kit2._tile.Host() == host2, "the list's host did not start")
    FL2.Start()
    local drivers = NewFrames(function(f) return f._parent == view and f._scripts.OnShow ~= nil end)
    assert(#drivers == 1, "expected one driver for the second list")
    drivers[1]._scripts.OnShow(drivers[1])
    local sf2 = NewFrames(function(f) return f._kind == "ScrollFrame" end)[1]
    assert(sf2 and sf2._parent._parent == view and sf2._parent._shown, "the list did not show under a host without cards")
    assert(view.ScrollBox._alpha == 0 and Kit2._listShown == true and LiveMenus() == 2)
    sf2._w, sf2._h = 380, 400
    sf2._scripts.OnSizeChanged(sf2)
    local rows2 = NewFrames(function(f) return f._parent == sf2._child and rawget(f, "hit") ~= nil and f._shown end)
    assert(#rows2 > 3 and rows2[1].d and rows2[1].d.tileBg, "the list's rows did not take the tile pieces")
    for i = hooksBefore + 1, #T.hooks do
        assert(T.hooks[i].target ~= FriendsListSocialCardMixin, "Blizzard's cards were hooked")
    end
    -- an online friend's row wears Blizzard's card (a game-level friend's or a Battle.net friend's) in place
    -- of the tile's shade and online tint; an offline friend's keeps the tile
    local seen = { online = 0, offline = 0, title = 0 }
    for _, r in ipairs(rows2) do
        local card, d = rawget(r, "card"), r.d
        assert(card and card._alpha == 1 and rawget(r, "cardWhole") == true, "a row under Blizz Default has no card")
        if r.rec.online then
            local want = r.rec.id == 104 and "friends-card-default" or "friends-card-battleNet"
            assert(card._shown and card._atlas == want and not d.tileBg._shown and not d.onlineBg._shown,
                "an online friend's row does not wear Blizzard's card: " .. tostring(r.rec.id))
            seen.online = seen.online + 1
            if r.rec.id == 104 then seen.title = seen.title + 1 end
        else
            assert(not card._shown and d.tileBg._shown, "an offline friend's row wears Blizzard's card")
            seen.offline = seen.offline + 1
        end
    end
    assert(seen.online > 0 and seen.offline > 0 and seen.title == 1,
        ("the rows in view: %d online, %d offline, %d game-level"):format(seen.online, seen.offline, seen.title))
    -- a friend going offline takes the tile back
    local ev2 = NewFrames(function(f) return f._scripts.OnEvent ~= nil and f._parent == nil end)[1]
    local fl2 = NewFrames(function(f) return f._scripts.OnUpdate ~= nil and f._parent == nil end)[1]
    assert(ev2 and fl2, "the second list's event frame or flusher is missing")
    T.friends[1].online = false
    ev2._scripts.OnEvent(ev2, "BN_FRIEND_INFO_CHANGED")
    if fl2._shown then fl2._scripts.OnUpdate(fl2) end
    local row101
    for _, r in ipairs(NewFrames(function(f) return f._parent == sf2._child and rawget(f, "hit") ~= nil and f._shown end)) do
        if r.rec and r.rec.id == 101 then row101 = r end
    end
    assert(row101 and not row101.card._shown and row101.d.tileBg._shown, "a friend gone offline kept Blizzard's card")
    T.friends[1].online = true
    s2.customTiles = false
    FL2.Refresh()
    assert(not sf2._parent._shown and view.ScrollBox._alpha == 1 and Kit2._listShown == false and LiveMenus() == 0,
        "the switch did not stand the list down under a host without cards")
    for frame in pairs(T.ffd[ffdBefore + 1]) do
        assert(frame.elementData == nil, "a Blizzard card was painted by a host without cards")
    end
    note(("host without cards: %d rows drawn, %d hooks added (the view's search)"):format(#rows2, #T.hooks - hooksBefore))
end

note(("popups shown: %d, tooltips: %d, reads of the list under ours: %d"):format(#T.popups, T.tooltips, T.searchCalls))
print(table.concat(out, "\n"))
print("friends list harness: ok")
