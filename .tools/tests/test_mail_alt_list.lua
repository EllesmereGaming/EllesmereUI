-- Run from the repository root: lua .tools/tests/test_mail_alt_list.lua
-- The Mail card's Alt List (EllesmereUIBlizzardSkin_MailAlts.lua) over game stubs: the WoW Forever list with its
-- Characters / Guild / Friends tabs under Blizzard's look, then retail under the EllesmereUI look. The player's
-- own characters come from the parent's character roster (the real one, cut from EllesmereUI.lua).
local FILE = "EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_MailAlts.lua"

-- realmHidden: this character's realm name does not read yet
local function Load(forever, style, realmHidden)
    local S = { frames = {}, tips = {}, menus = {}, rosterAsked = 0, friendReads = 0, coords = 0, combat = false,
        realmHidden = realmHidden }

    -- Textures and font strings.
    local function Widget()
        local w = { _shown = true }
        return setmetatable(w, { __index = function(_, k)
            if k == "SetText" then return function(self, s) self._text = s end end
            if k == "GetText" then return function(self) return self._text end end
            if k == "GetStringHeight" then return function() return 12 end end
            if k == "SetTexture" or k == "SetAtlas" then return function(self, v) self._tex = v end end
            if k == "SetAlpha" then return function(self, a) self._alpha = a end end
            if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
            if k == "Show" then return function(self) self._shown = true end end
            if k == "Hide" then return function(self) self._shown = false end end
            if type(k) == "string" and k:match("^%u") then return function() end end
        end })
    end

    local METHODS = {
        SetScript = function(self, n, fn) self._scripts[n] = fn end,
        GetScript = function(self, n) return self._scripts[n] end,
        RegisterEvent = function(self, e) self._events[e] = true end,
        UnregisterEvent = function(self, e) self._events[e] = nil end,
        CreateTexture = function() return Widget() end,
        CreateFontString = function() return Widget() end,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        IsShown = function(self) return self._shown end,
        IsVisible = function(self)
            local f = self
            while f do
                if not f._shown then return false end
                f = f._parent
            end
            return true
        end,
        SetHeight = function(self, h) self._h = h; S.heightSet = (S.heightSet or 0) + 1 end,
        GetHeight = function(self) return self._h or 0 end,
        SetAlpha = function(self, a) self._alpha = a end,
        GetEffectiveScale = function() return 1 end,
        GetLeft = function() return 0 end, GetRight = function() return 100 end,
        GetTop = function() return 100 end, GetBottom = function() return 0 end,
        GetFrameLevel = function() return 1 end,
        SetNormalTexture = function(self, t) self._normal = t; self._normalTex = Widget() end,
        GetNormalTexture = function(self) return self._normalTex end,
        GetTitleText = function(self) return self._title end,
        SetText = function(self, s) self._text = s end,
        GetText = function(self) return self._text end,
    }
    local FMT = { __index = function(_, k)
        local m = METHODS[k]
        if m then return m end
        if type(k) == "string" and k:match("^%u") then return function() end end
    end }
    local function Frame(kind, name, parent, template)
        local f = { _kind = kind, _parent = parent, _template = template, _scripts = {}, _events = {}, _shown = true }
        S.frames[#S.frames + 1] = f
        setmetatable(f, FMT)
        if template == "DefaultPanelTemplate" then
            f._title = Widget()
            rawset(f, "TitleContainer", Frame("Frame", nil, f))
        end
        return f
    end
    CreateFrame = Frame
    S.Frame = Frame

    UIParent = Frame("Frame")
    MailFrame = Frame("Frame", nil, UIParent)
    SendMailFrame = Frame("Frame", nil, MailFrame)
    OpenMailFrame = Frame("Frame", nil, UIParent)
    OpenMailFrame._shown = false
    SendMailNameEditBox = Frame("EditBox", nil, SendMailFrame)
    S.blizzard = #S.frames   -- frames up to here are the game's
    InboxFrame = Frame("Frame", nil, MailFrame)
    S.hooks = {}
    function MailFrameTab_OnClick() end
    if forever then
        InboxFrame_Update = nil
        rawset(InboxFrame, "Update", function() end)
    else
        function InboxFrame_Update() end
    end
    hooksecurefunc = function(a, b, c)
        if type(a) == "string" then
            local orig = _G[a]
            _G[a] = function(...) orig(...); b(...) end
            S.hooks[a] = true
        else
            local orig = a[b]
            rawset(a, b, function(...) orig(...); c(...) end)
            S.hooks[b] = true
        end
    end

    EUI_CLIENT_BLOCKED = nil
    time = function() return 1000000 end
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    strcmputf8i = function(a, b) a, b = a:lower(), b:lower() return a < b and -1 or (a > b and 1 or 0) end
    Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
    Mixin = function(t, m) for k, v in pairs(m) do rawset(t, k, v) end return t end
    BackdropTemplateMixin = {
        SetBackdrop = function(self, info) self._backdrop = info end,
        SetupTextureCoordinates = function(self) S.coords = S.coords + 1; S.coordsAfterHeight = S.heightSet end,
    }
    GetMouseFoci = function() return {} end
    InCombatLockdown = function() return S.combat end
    C_AddOns = { IsAddOnLoaded = function() return true end }
    UNIT_TYPE_LEVEL_TEMPLATE = "Level %d %s"
    LOCALIZED_CLASS_NAMES_MALE = {}
    FOREIGN_SERVER_LABEL = " (*)"
    CLASS_ICON_TCOORDS = {}
    BNET_CLIENT_WOW, WOW_PROJECT_ID = "WoW", forever and 18 or 1
    GetMaxLevelForLatestExpansion = function() return forever and 60 or 90 end
    C_CreatureInfo = { GetClassInfo = function(id) return id == 8 and { classFile = "MAGE" } or nil end }
    C_AutoComplete = { GetAutoCompleteRealms = function() return { "Area52", "Connected" } end }

    -- This character.
    UnitGUID = function() return "Player-1-ME" end
    UnitName = function() return "Anna", forever and "Stark" or nil end
    UnitNameUnmodified = function() S.unmodified = true; return "Anna", forever and "Stark" or nil end
    UnitClass = function() return "Warrior", "WARRIOR" end
    UnitLevel = function() return 50 end
    UnitFactionGroup = function() return "Alliance" end
    -- WoW Forever's realm names as the game gives them (the last letters are the ruleset)
    GetRealmName = function() return forever and "CAMWOW EU5 Realm 7 PvE" or "Area 52" end
    GetNormalizedRealmName = function()
        if S.realmHidden then return nil end
        return forever and "CAMWOWEU5Realm7PvE" or "Area52"
    end

    -- The guild: an online member, one last seen two days ago, and this character.
    S.guild = {
        { "Eve Gold", 30, true, "PRIEST", "Player-1-G1" },
        { "Finn Hale", 25, false, "ROGUE", "Player-1-G2" },
        { "Anna Stark", 50, true, "WARRIOR", "Player-1-ME" },
    }
    IsInGuild = function() return true end
    GetNumGuildMembers = function() return #S.guild end
    GetGuildRosterInfo = function(i)
        local m = S.guild[i]
        return m[1], nil, nil, m[2], nil, nil, nil, nil, m[3], nil, m[4], nil, nil, nil, nil, nil, m[5]
    end
    GetGuildRosterLastOnline = function(i) if not S.guild[i][3] then return 0, 0, 2, 0 end end
    Ambiguate = function(name) return name end
    C_GuildInfo = { GuildRoster = function() S.rosterAsked = S.rosterAsked + 1 end }

    -- Battle.net friends: one on another realm of this ruleset, one in another region (and on another
    -- ruleset), one playing another game, one on another ruleset of this region, and two whose realm name
    -- tells no ruleset (none given, another form).
    local function Friend(name, near, project, realm)
        return { gameAccountInfo = { isOnline = true, clientProgram = "WoW", wowProjectID = project or WOW_PROJECT_ID,
            characterName = name, classID = 8, className = "Mage", characterLevel = 40, factionName = "Alliance",
            isInCurrentRegion = near, realmName = realm } }
    end
    S.friends = { Friend("Cara Field", true, nil, "CAMWOWEU5Realm3PvE"), Friend("Dan Far", false, nil, "CAMWOWUS2Realm10RPPvP"),
        Friend("Other Game", true, 99), Friend("Erin Rule", true, nil, "CAMWOWEU5Realm9PvP"), Friend("Gus Plain", true),
        Friend("Hal Odd", true, nil, "Silvermoon") }
    BNGetNumFriends = function() return #S.friends end
    C_BattleNet = { GetFriendAccountInfo = function(i) S.friendReads = S.friendReads + 1; return S.friends[i] end }

    EllesmereUIDB = {}
    EllesmereUI = {
        IS_FOREVER = forever, COGS_ICON = "the suite's cog", _dmGen = 1,
        COLOR_CODES = { DIM = "" }, CLASS_ICON_SPRITE_COORDS = {},
        IsSecret = function() return false end,
        PlainString = function(v) if type(v) == "string" then return v end end,
        RealmGroupName = function() return forever and "Normal" or "Area 52" end,
        WithSurname = function(name, surname)
            if not forever or type(surname) ~= "string" or surname == "" then return name end
            return name .. " " .. surname
        end,
        ClassTokenFromLocalized = function() return nil end,
        GetClassColor = function() return { r = 1, g = 1, b = 1 } end,
        HexColor = function() return "" end,
        ShowWidgetTooltip = function(owner, text) S.tips[#S.tips + 1] = text end,
        HideWidgetTooltip = function() end,
        _WidgetTooltipOwner = function() return nil end,
        ShowContextMenu = function(owner, menu) S.menus[#S.menus + 1] = menu end,
        ShowConfirmPopup = function(_, popup) S.confirm = popup end,
        ContextMenuOwner = function() return nil end,
        CloseContextMenu = function() end,
        IsShown = function() return false end,
        RefreshPage = function() end,
        L = function(s) return s end,
        Lf = function(s, ...) return s:format(...) end,
    }
    -- The parent's own reader of a WoW Forever realm name, cut out of EllesmereUI.lua
    do
        local f = assert(io.open("EllesmereUI.lua", "rb"))
        local src = f:read("*a"):gsub("\r\n", "\n")
        f:close()
        local a = assert(src:find("function EllesmereUI.RealmRulesetSuffix(realm)\n", 1, true), "the parent's realm name helper not found")
        local b = assert(src:find("\nend\n", a, true))
        assert(loadstring(src:sub(a, b + 4), "=EllesmereUI.lua"))()
    end
    -- The parent's character roster, with its identity recorder (S.who.fire runs it)
    S.who = dofile(".tools/tests/char_roster_stub.lua")(EllesmereUI, { guid = "Player-1-ME", name = "Anna",
        surname = forever and "Stark" or nil, realm = forever and "CAMWOW EU5 Realm 7 PvE" or "Area 52",
        class = "WARRIOR", level = 50, faction = "Alliance" })
    local ns = { WSkin = {
        Theme = { fontPath = "font" }, GetStyle = function() return style end, ResolveTheme = function() end,
        Font = function() end, FontFamily = function() end, AddBorder = function() end,
        OnStylesChanged = function() end, GetModernBG = function() return 0, 0, 0, 1 end, CoverFit = function() end,
    } }
    assert(loadfile(FILE))("EllesmereUIBlizzardSkin", ns)

    S.ns = ns
    S.ev = S.frames[S.blizzard + 2]   -- the file's own event frame, its first CreateFrame
    assert(S.ev._scripts.OnEvent, "the event frame")
    S.Fire = function(event, ...) S.ev._scripts.OnEvent(S.ev, event, ...) end
    -- The rows on screen, in order; a frame of ours under the Send Mail page.
    S.Rows = function()
        local out = {}
        for _, f in ipairs(S.frames) do
            if rawget(f, "_mailAltRow") and f._shown and rawget(f, "_guid") then out[#out + 1] = f end
        end
        return out
    end
    S.Under = function(f)
        f = f._parent
        while f do
            if f == SendMailFrame then return true end
            f = f._parent
        end
        return false
    end
    S.Tab = function(label)
        for _, f in ipairs(S.frames) do
            local t = rawget(f, "_text")
            if f._kind == "Button" and type(t) == "table" and t._text == label then return f end
        end
    end
    S.Click = function(f, button) f._scripts.OnClick(f, button or "LeftButton") end
    return S
end

-------------------------------------------------------------------------------
--  WoW Forever, Blizzard's look
-------------------------------------------------------------------------------
local F = Load(true, "off")
F.who.fire("PLAYER_LOGIN")
F.Fire("PLAYER_LOGIN")
local me = EllesmereUIDB.chars["Player-1-ME"]
assert(me and me.name == "Anna Stark" and me.realm == "Normal" and me.realmKey == "Normal", "the roster holds this character by its full name and ruleset")
assert(EllesmereUIDB.mailAltRoster == nil, "the list keeps no roster of its own")
assert(not F.ev._events.GUILD_ROSTER_UPDATE and not F.ev._events.BN_FRIEND_INFO_CHANGED and not next(F.hooks),
    "off: no hook and no guild or Battle.net event")

EllesmereUIDB.chars["Player-1-B"] = { name = "Bob Builder", realm = "Normal", realmKey = "Normal",
    class = "MAGE", level = 20, faction = "Alliance", seen = 5, gold = { money = 7 } }
EllesmereUIDB.chars["Player-1-H"] = { name = "Hard Core", realm = "Hardcore", realmKey = "Hardcore",
    class = "MAGE", level = 20, faction = "Alliance", seen = 9 }
-- an entry another feature made for a character that has not logged in since: no name yet, not listed
EllesmereUIDB.chars["Player-1-N"] = { gold = { money = 3 } }
EllesmereUIDB.mailAltList = true
F.ns.MailAlts.Refresh()
assert(F.ev._events.GUILD_ROSTER_UPDATE and F.ev._events.BN_FRIEND_INFO_CHANGED, "on: the two contact events")
assert(F.hooks.MailFrameTab_OnClick and F.hooks.Update, "on: the tab hook and the mixin inbox's Update hook")

-- Zero taint by construction: nothing of ours under the Send Mail page carries a show, hide or size script, and
-- the dialog box is a plain frame with the backdrop mixin (BackdropTemplate brings OnSizeChanged).
local ours = 0
for i, f in ipairs(F.frames) do
    if i > F.blizzard and F.Under(f) then
        ours = ours + 1
        assert(not f._scripts.OnShow and not f._scripts.OnHide and not f._scripts.OnSizeChanged, "a show / hide / size script under SendMailFrame")
        assert(f._template ~= "BackdropTemplate", "BackdropTemplate under SendMailFrame")
    end
end
assert(ours > 5, "the panel, its tabs and rows were built under the Send Mail page")
assert(F.coords > 0 and F.coordsAfterHeight == F.heightSet, "the dialog box's edges are refreshed after each resize")

-- Characters: the same ruleset only, named and addressed "Name Surname".
local rows = F.Rows()
assert(#rows == 1 and rows[1]._name._text == "Bob Builder", "the other ruleset's character is left out; the row reads Name Surname")
F.Click(rows[1])
assert(SendMailNameEditBox._text == "Bob Builder", "a click addresses the full name")
rows[1]._scripts.OnEnter(rows[1])
assert(F.tips[#F.tips]:find("Bob Builder", 1, true), "the tooltip's head carries the surname")
local entries = F.ns.MailAlts.Entries()
local names = {}
for _, e in ipairs(entries) do names[e.name] = true end
assert(names["Bob Builder"] and names["Anna Stark"], "Shown Characters lists full names")
assert(#entries == 3, "Shown Characters lists the three characters the roster names, not the nameless entry")

-- Shown Characters reads and writes the character's own roster entry.
local MA = F.ns.MailAlts
assert(MA.IsShown("Player-1-B") and MA.IsShown("Player-1-H") and MA.IsShown("Player-1-N") and MA.IsShown("Player-none"),
    "every character starts shown")
MA.SetShown("Player-1-B", false)
assert(not MA.IsShown("Player-1-B") and MA.IsShown("Player-1-H"), "an unticked character reads as hidden, the others as shown")
assert(EllesmereUIDB.chars["Player-1-B"].mailAltHidden == true and #F.Rows() == 0, "it is marked on its roster entry and leaves the list")
MA.SetShown("Player-none", false)
assert(EllesmereUIDB.chars["Player-none"] == nil, "hiding a character the roster does not know makes no entry")
MA.SetShown("Player-1-B", true)
assert(MA.IsShown("Player-1-B") and EllesmereUIDB.chars["Player-1-B"].mailAltHidden == nil and #F.Rows() == 1, "ticked again it is back")
-- The row's menu: Ignore This Character is the same mark.
local function MenuItem(text)
    for _, it in ipairs(F.menus[#F.menus]) do if it.text == text then return it end end
end
F.Click(F.Rows()[1], "RightButton")
assert(MenuItem("Ignore This Character") and MenuItem("Remove Character"), "a character row's menu")
MenuItem("Ignore This Character").onClick()
assert(not MA.IsShown("Player-1-B") and #F.Rows() == 0, "Ignore This Character hides it")
MA.SetShown("Player-1-B", true)
-- Remove Character asks first, then takes the character off the list and out of Shown Characters; its roster
-- entry (other features' data) stays, and its own next login brings it back.
F.Click(F.Rows()[1], "RightButton")
F.confirm = nil
MenuItem("Remove Character").onClick()
assert(F.confirm and F.confirm.message:find("Bob Builder", 1, true) and #F.Rows() == 1, "Remove Character asks first, by the full name")
F.confirm.onConfirm()
local bob = EllesmereUIDB.chars["Player-1-B"]
assert(#F.Rows() == 0 and bob and bob.mailAltRemoved == true and bob.gold.money == 7, "a removed character leaves the list and keeps its roster entry")
assert(#MA.Entries() == 2, "and leaves Shown Characters")
EllesmereUIDB.chars["Player-1-ME"].mailAltRemoved = true
F.Fire("PLAYER_LOGIN")
assert(EllesmereUIDB.chars["Player-1-ME"].mailAltRemoved == nil, "logging into a removed character brings it back")
bob.mailAltRemoved = nil
MA.Refresh()

-- Guild: asked for on the pick; online first, then by last time online; this character left out; no menu.
local guildTab = assert(F.Tab("Guild"), "the Guild tab")
F.Click(guildTab)
assert(EllesmereUIDB.mailAltListTab == "guild" and F.rosterAsked == 1, "the pick is saved and the roster asked for")
rows = F.Rows()
assert(#rows == 2 and rows[1]._name._text == "Eve Gold" and rows[2]._name._text == "Finn Hale", "online first, then last online; not this character")
F.Click(rows[1])
assert(SendMailNameEditBox._text == "Eve Gold", "a guild click addresses the member")
local menus = #F.menus
F.Click(rows[1], "RightButton")
assert(#F.menus == menus, "a guild member has no menu")
-- A repaint (a roster update while the tab shows) reuses one table per member.
local function Upvalue(fn, name, seen)
    seen = seen or {}
    if type(fn) ~= "function" or seen[fn] then return end
    seen[fn] = true
    for i = 1, math.huge do
        local key, value = debug.getupvalue(fn, i)
        if not key then return end
        if key == name then return value end
        if type(value) == "function" then
            local found = Upvalue(value, name, seen)
            if found ~= nil then return found end
        end
    end
end
local pool = assert(Upvalue(F.ns.MailAlts.Refresh, "guildEntries"), "the guild entry pool")
local first, second = pool[1], pool[2]
assert(#pool == 2 and first and second, "one entry per listed member")
F.guild[1][2] = 31
for _ = 1, 20 do F.Fire("GUILD_ROSTER_UPDATE") end
assert(#pool == 2 and pool[1] == first and pool[2] == second, "repaints reuse the same entries")
assert(#F.Rows() == 2 and F.Rows()[1]._lvl._text == 31, "and show the member's new level")

-- Friends: Battle.net friends playing this game are remembered; another region is listed dimmed.
F.Click(assert(F.Tab("Friends"), "the Friends tab"))
rows = F.Rows()
assert(#rows == 5, "the five friends in this game; the one in another game is not listed")
local store = EllesmereUIDB.mailAltFriends
assert(store["Cara Field"] and store["Dan Far"] and not store["Other Game"], "remembered by character")
local far
for _, r in ipairs(rows) do if r._name._text == "Dan Far" then far = r end end
assert(far and far._alpha == 0.55 and far._limited == "region", "a friend in another region shows dimmed")
far._scripts.OnEnter(far)
assert(F.tips[#F.tips]:find("Your mail cannot reach another region.", 1, true), "and its tooltip says why")
assert(store["Dan Far"].rules == "RPPvP", "its ruleset is remembered too; the region is named first")

-- Another ruleset of this region: dimmed too. A ruleset is the letters a realm name ends in, a friend's
-- against this character's (CAMWOWEU5Realm7PvE); another realm of the same ruleset is in reach, and so is a
-- friend whose realm name tells none.
local function Row(name)
    for _, r in ipairs(F.Rows()) do if r._name._text == name then return r end end
end
-- Every friend read again and the list repainted: away to another tab and back (a click on the shown
-- tab does nothing).
local function Reseen()
    F.Click(F.Tab("Characters"))
    F.Click(F.Tab("Friends"))
end
local rule = Row("Erin Rule")
assert(rule and rule._alpha == 0.55 and rule._limited == "ruleset", "a friend on another ruleset shows dimmed")
rule._scripts.OnEnter(rule)
assert(F.tips[#F.tips]:find("Your mail cannot reach another ruleset.", 1, true), "and its tooltip says why")
assert(not F.tips[#F.tips]:find("another region", 1, true) and not F.tips[#F.tips]:find("other faction", 1, true), "and nothing else")
assert(store["Erin Rule"].rules == "PvP" and store["Cara Field"].rules == "PvE", "the ruleset is remembered with the character")
local near = Row("Cara Field")
assert(near and near._alpha == 1 and not near._limited, "another realm of this ruleset is in reach")
assert(store["Gus Plain"].rules == nil and store["Hal Odd"].rules == nil, "a realm name of another form tells no ruleset")
assert(Row("Gus Plain")._alpha == 1 and not Row("Gus Plain")._limited and not Row("Hal Odd")._limited,
    "a friend whose realm name tells no ruleset stays in reach")
-- seen again with no realm name: the remembered ruleset stays
F.friends[4].gameAccountInfo.realmName = nil
Reseen()
assert(store["Erin Rule"].rules == "PvP" and Row("Erin Rule")._limited == "ruleset", "a sighting with no realm name keeps the remembered ruleset")
-- seen on another realm of this ruleset: in reach again
F.friends[4].gameAccountInfo.realmName = "CAMWOW EU5 Realm 12 PvE"
Reseen()
assert(store["Erin Rule"].rules == "PvE" and not Row("Erin Rule")._limited and Row("Erin Rule")._alpha == 1,
    "a friend seen on this ruleset is in reach again (the spaced form reads too)")
F.friends[4].gameAccountInfo.realmName = "CAMWOWEU5Realm9PvP"
Reseen()
-- the other faction still dims, with its own line
F.friends[1].gameAccountInfo.factionName = "Horde"
Reseen()
near = Row("Cara Field")
assert(near._limited == true and near._alpha == 0.55, "the other faction still shows dimmed")
near._scripts.OnEnter(near)
assert(F.tips[#F.tips]:find("Your mail cannot reach the other faction.", 1, true), "with the faction's own line")
F.friends[1].gameAccountInfo.factionName = "Alliance"
Reseen()
-- the guild and this character's own list are not held back by it
F.Click(F.Tab("Guild"))
for _, r in ipairs(F.Rows()) do assert(not r._limited, "a guild member held back") end
F.Click(F.Tab("Friends"))
-- the parent's reader itself
local Suffix = EllesmereUI.RealmRulesetSuffix
assert(Suffix("CAMWOWEU5Realm7PvE") == "PvE" and Suffix("CAMWOW EU5 Realm 7 PvE") == "PvE", "both forms of a realm name")
assert(Suffix("CAMWOWUS2Realm10RPPvP") == "RPPvP" and Suffix("CAMWOWUS1Realm3PvP") == "PvP" and Suffix("CAMWOWEU1Realm2RP") == "RP", "every ruleset")
-- as online friends carry them on the live client (a two-digit realm number runs straight into the letters)
assert(Suffix("CAMWOWUS2Realm11RP") == "RP" and Suffix("CAMWOWUS2Realm9RPPvP") == "RPPvP" and Suffix("CAMWOWUS1Realm8PvP") == "PvP"
    and Suffix("CAMWOWUS2Realm1PvE") == "PvE", "the realm names live friends carry")
assert(Suffix("Silvermoon") == nil and Suffix("Area52") == nil and Suffix("CAMWOWEU5Realm7") == nil and Suffix("RealmPvE") == nil
    and Suffix("") == nil and Suffix(nil) == nil and Suffix(7) == nil and Suffix({}) == nil, "any other name tells none")
menus = #F.menus
F.Click(far, "RightButton")
assert(#F.menus == menus + 1, "a remembered friend has a menu")

-- A friend update away from the mailbox: remembered out of combat, skipped in combat.
F.Click(F.Tab("Characters"))
store["Cara Field"] = nil
local reads = F.friendReads
F.combat = true
F.Fire("BN_FRIEND_INFO_CHANGED", 1)
assert(F.friendReads == reads and not store["Cara Field"], "in combat the update reads nothing")
F.combat = false
F.Fire("BN_FRIEND_INFO_CHANGED", 1)
assert(F.friendReads == reads + 1 and store["Cara Field"], "out of combat it remembers the friend")

-- Off again: the events go and the panel hides.
EllesmereUIDB.mailAltList = false
F.ns.MailAlts.Refresh()
assert(not F.ev._events.GUILD_ROSTER_UPDATE and not F.ev._events.BN_FRIEND_INFO_CHANGED, "off: the contact events are unregistered")
assert(#F.Rows() == 0 or not F.Rows()[1]:IsVisible(), "off: the panel is hidden")

-- This character's own realm name does not read yet: nobody is held back by ruleset. Once it reads, the
-- friend on another ruleset is, and the name is read no more.
local U = Load(true, "off", true)
U.who.fire("PLAYER_LOGIN")
U.Fire("PLAYER_LOGIN")
EllesmereUIDB.mailAltList = true
U.ns.MailAlts.Refresh()
U.Click(assert(U.Tab("Friends"), "the Friends tab"))
local function URow(name)
    for _, r in ipairs(U.Rows()) do if r._name._text == name then return r end end
end
assert(URow("Erin Rule") and not URow("Erin Rule")._limited and URow("Dan Far")._limited == "region",
    "with this character's realm name unread, only the region holds a friend back")
U.realmHidden = false
U.Click(U.Tab("Characters"))
U.Click(U.Tab("Friends"))
assert(URow("Erin Rule")._limited == "ruleset", "once it reads, another ruleset is out of reach")
U.realmHidden = true
U.Click(U.Tab("Characters"))
U.Click(U.Tab("Friends"))
assert(URow("Erin Rule")._limited == "ruleset", "and it is kept for the session")

-------------------------------------------------------------------------------
--  Retail, the EllesmereUI look: no tabs, no contact events, realms
-------------------------------------------------------------------------------
local R = Load(false, "eui")
R.who.fire("PLAYER_LOGIN")
R.Fire("PLAYER_LOGIN")
local mine = EllesmereUIDB.chars["Player-1-ME"]
assert(mine and mine.name == "Anna" and mine.realm == "Area 52" and mine.realmKey == "Area52", "retail: the roster holds the name, the realm and the realm as mail addresses it")
EllesmereUIDB.chars["Player-1-B"] = { name = "Bob", realm = "Area 52", realmKey = "Area52", class = "MAGE", level = 80, faction = "Horde", seen = 9 }
EllesmereUIDB.chars["Player-2-Z"] = { name = "Zed", realm = "Stormrage", realmKey = "Stormrage", class = "MAGE", level = 80, faction = "Alliance", seen = 5 }
EllesmereUIDB.mailAltList = true
EllesmereUIDB.mailAltListTab = "guild"   -- a tab saved on WoW Forever is not read here
R.ns.MailAlts.Refresh()
assert(not R.ev._events.GUILD_ROSTER_UPDATE and not R.ev._events.BN_FRIEND_INFO_CHANGED, "retail never registers the contact events")
assert(R.hooks.MailFrameTab_OnClick and R.hooks.InboxFrame_Update, "retail hooks the inbox's global update")
assert(not R.Tab("Characters") and not R.Tab("Guild") and not R.Tab("Friends"), "retail builds no tabs")
rows = R.Rows()
assert(#rows == 2 and rows[1]._name._text == "Bob" and rows[2]._name._text == "Zed (*)", "this realm first by last played; another realm is marked")
R.Click(rows[1])
assert(SendMailNameEditBox._text == "Bob", "this realm: the name alone")
R.Click(rows[2])
assert(SendMailNameEditBox._text == "Zed-Stormrage" and rows[2]._alpha == 0.55, "another realm: Name-Realm, dimmed")
assert(not rows[1]._limited, "the other faction on this realm takes any mail")
local cog
for i, f in ipairs(R.frames) do
    if i > R.blizzard and f._kind == "Button" and f._normal then cog = f end
end
assert(cog and cog._normal == EllesmereUI.COGS_ICON, "the title cog wears the suite's cog art")
assert(R.rosterAsked == 0 and R.friendReads == 0, "retail asks for no guild roster and reads no friend")

print("mail alt list OK")
