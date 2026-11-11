if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_MailAlts.lua
--  The Mail card's Alt List (opt-in, EllesmereUIDB.mailAltList): beside the
--  Send Mail page, the player's other characters. Those on this realm or a
--  connected one take any mail, whatever their faction (your own characters of
--  the other faction there receive items and gold too); those on another realm
--  take Warbound items only, which reach every character on the account, and
--  show dimmed. A click puts the name in the To: box; a right
--  click offers Ignore This Character and Remove Character.
--  The card also keeps Shown Characters (EllesmereUIDB.mailAltHidden, by
--  player GUID) and, in the toggle's cog, Sort By (mailAltListSort), Max
--  Characters Shown (mailAltListMax) and Minimum Level (mailAltListMinLevel).
--  The cog in the title opens the list's own menu, on the spot: the ignored
--  characters shown too (dimmed and marked, this session only), Sort By, Max
--  Characters Shown and Minimum Level. A right click on an ignored character
--  offers Show This Character Again. Nothing here opens the EllesmereUI options.
--
--  Tabs under the title pick what the list shows (mailAltListTab): Characters
--  (the roster), Guild (the guild roster, by last time online) or Friends (the
--  game's friend list; where the game has none, as on WoW Forever, the
--  Battle.net friends seen in this game, each character kept in
--  EllesmereUIDB.mailAltFriends so it stays listed while its player is away).
--  Sort By, Max Characters Shown and Minimum Level apply to every tab;
--  ignoring is for the player's own characters. The tabs are plain buttons of
--  ours (no Blizzard tab template, whose OnShow would sit under SendMailFrame).
--
--  The roster, EllesmereUIDB.mailAltRoster (by player GUID, which a rename
--  keeps), is written at every login and logout even while the list is off
--  (owner decision 2026-10-24): two small writes a session and nothing during
--  play, so every character played since is listed the first time the list is
--  turned on.
--
--  Zero taint: none of our code runs inside Blizzard's mail code.
--   - The panel is a child of SendMailFrame, and no frame of ours under it
--     carries an OnShow, OnHide or OnSizeChanged script, so it shows and hides
--     with the Send Mail page with nothing of ours inside Blizzard's Show or
--     Hide calls.
--   - Its placement follows two hooksecurefunc post-hooks, installed on the
--     first enable and returning at once while off: MailFrameTab_OnClick (the
--     tab switches, Reply's included) and InboxFrame_Update (which every close
--     of the letter window runs, from OpenMailFrame_OnHide).
--   - A click only calls SendMailNameEditBox:SetText. The box's OnTextChanged
--     runs in our execution, and for a name Blizzard's handler writes no Lua
--     state (AutoCompleteEditBox_OnTextChanged acts on typed text or an empty
--     box only; SendMailFrame_CanSend only enables the Send button). The tab is
--     never switched and keyboard focus never moved for the player: both run
--     Blizzard code that writes state its secure send and autocomplete paths
--     read later. For the same reason a click leaves Blizzard's name
--     suggestions open when the player had started typing (Tab or the arrows
--     can then pick one; a typed key or Escape refreshes or closes them).
--
--  WoW Forever (no realms, surnames): a character is kept with its surname,
--  UnitName's second return there, and mail addresses it as "Name Surname"
--  (the first name alone is refused); its "realm" is the ruleset
--  (EllesmereUI.RealmGroupName), and only characters of the same ruleset and
--  faction can be mailed, so the others are left out or dimmed. The letter
--  window's close runs InboxFrame:Update there, not InboxFrame_Update.
--
--  The panel's look is latched at login with the mail window's own skin
--  (which applies at login, its style changes needing a reload): EllesmereUI
--  and Modern draw the window theme (eui <-> modern repaints live), Blizz
--  Default draws Blizzard's own DefaultPanelTemplate (on WoW Forever, the
--  game's plain dialog box, and Forever's class icons).
-------------------------------------------------------------------------------
local _, ns = ...
local WSkin = ns.WSkin
if not WSkin then return end

local EUI = EllesmereUI
local FOREVER = EUI.IS_FOREVER
local Theme = WSkin.Theme
local IsSecret, PlainString = EUI.IsSecret, EUI.PlainString
local wipe, sort = wipe, table.sort

local DEFAULT_MAX, DEFAULT_MIN_LEVEL, DEFAULT_SORT = 10, 1, "recent"
local MAX_ROWS   = 20       -- the Max Characters Shown slider's top
-- WoW Forever lists "Name Surname": a wider panel.
local PANEL_W    = EllesmereUI.IS_FOREVER and 200 or 170
local ROW_H      = 22
local TAB_H      = 20       -- the tab strip under the title
local ICON_SIZE  = 16
local LIST_PAD   = 4        -- above the first row and below the last
local EMPTY_PAD  = 10       -- around the empty-list note
local LIMITED_ALPHA = 0.55  -- a row that takes Warbound items only
local IGNORED_ALPHA = 0.45  -- an ignored character, shown on request
-- The two looks' geometry: the title band's height, the list's side inset and
-- the gap to the window beside it (Blizzard's metal corners reach past their frame).
local EUI_TOP, EUI_INSET, EUI_GAP       = 25, 1, 4
local BLIZZ_TOP, BLIZZ_INSET, BLIZZ_GAP = 21, 8, 10
local FOREVER_TOP, FOREVER_INSET        = 28, 8   -- the dialog box: title inside its border
local EUI_CLASS_ICONS   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\modern.tga"
local BLIZZ_CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local SHELL_ART         = "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png"

local ev = CreateFrame("Frame")
local panel, title, emptyNote
local bgArt, bgShade, bgFlat      -- the EllesmereUI look's backdrop layers
local rows = {}
local dirty = true                -- the shown list needs a repaint
local hooked = false
local blizzLook                   -- latched at login: the mail window wears Blizzard's look
local topH, inset, gap
local placedTo, placedSide        -- the panel's current anchor
local connected                   -- this realm's connected realms, read once a session
local shown = {}                  -- player GUIDs in display order (reused)
local mailable = 0                -- characters this page could mail before the card's filters
local sortRoster                  -- the roster the comparators read during one sort
local menuGuid                    -- the row the right-click menu was opened on
local myGuid                      -- this character, read at login (never in its own list)
local paintedGen, paintedFaction  -- the class colour palette and faction the list was painted with
local MENU, IGNORED_MENU, Changed, BuildTabs
local showIgnored = false         -- the title's right click: ignored characters listed too (this session)
local ignoredShown = {}           -- player GUIDs of the ignored characters in the shown list
local ignoredCount = 0            -- ignored characters this page could mail
local tabs = {}                   -- the tab buttons, by tab key
local contacts = {}               -- the Guild or Friends entries of one paint, by mail address
local source                      -- the map the shown keys index: the roster, or contacts
local listTop                     -- where the rows start: below the title band and the tabs

-------------------------------------------------------------------------------
--  Settings and the roster
-------------------------------------------------------------------------------
local function Enabled()
    return EllesmereUIDB and EllesmereUIDB.mailAltList == true
end

local function Setting(key, default)
    local v = EllesmereUIDB and EllesmereUIDB[key]
    if v == nil then return default end
    return v
end

local function NumberSetting(key, default)
    local v = tonumber(Setting(key, default))
    return v and math.floor(v) or default
end

local function Roster()
    local db = EllesmereUIDB
    if type(db) ~= "table" then return nil end
    local r = db.mailAltRoster
    if type(r) ~= "table" then
        r = {}
        db.mailAltRoster = r
    end
    return r
end

local TAB_KEYS = { alts = true, guild = true, friends = true }
local function Tab()
    local t = Setting("mailAltListTab", "alts")
    return TAB_KEYS[t] and t or "alts"
end

local function Hidden()
    local h = EllesmereUIDB and EllesmereUIDB.mailAltHidden
    return type(h) == "table" and h or nil
end

-- This character as the roster keeps it. A read that comes back unknown keeps
-- the stored value (a level read before the character is in the world).
local function RecordPlayer()
    local guid = PlainString(UnitGUID("player"))
    if guid then myGuid = guid end
    local name, surname = UnitName("player")
    name = PlainString(name)
    local realm = PlainString(FOREVER and EUI.RealmGroupName() or GetRealmName())
    local _, class = UnitClass("player")
    class = PlainString(class)
    if not (guid and name and realm and class) then return end
    -- The realm as mail addresses it ("Area52"): the normalized name. WoW
    -- Forever has none: the ruleset groups the characters.
    local realmKey = FOREVER and realm or PlainString(GetNormalizedRealmName()) or (realm:gsub("[%s%-]", ""))
    local roster = Roster()
    if not roster then return end
    local e = roster[guid]
    if type(e) ~= "table" then
        e = {}
        roster[guid] = e
    end
    e.name, e.realm, e.realmKey, e.class = name, realm, realmKey, class
    if FOREVER then e.surname = PlainString(surname) end
    local level = UnitLevel("player")
    if type(level) == "number" and not IsSecret(level) and level > 0 then e.level = level end
    local faction = PlainString((UnitFactionGroup("player")))
    if faction then e.faction = faction end
    e.seen = time()
    dirty = true
end

-- "Level 80 Mage, Horde": the hover line of a list row and of the Shown
-- Characters entries, in Blizzard's own strings.
local function Describe(e)
    local class = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[e.class]) or e.class or ""
    local text = e.level and UNIT_TYPE_LEVEL_TEMPLATE:format(e.level, class) or class
    local faction = e.faction and _G["FACTION_" .. e.faction:upper()]
    if faction then text = text .. ", " .. faction end
    return text
end

-------------------------------------------------------------------------------
--  Who the list shows: every other character, minus Shown Characters and
--  Minimum Level. Any mail reaches this realm or a connected one, either
--  faction; Warbound items reach every character on the account.
-------------------------------------------------------------------------------
-- This character's realm key, as RecordPlayer stores it.
local function OwnRealmKey()
    if FOREVER then return PlainString(EUI.RealmGroupName()) end
    return PlainString(GetNormalizedRealmName())
end

local function ConnectedRealms()
    if connected then return connected end
    local own = OwnRealmKey()
    local set = {}
    if own then set[own] = true end
    local list = not FOREVER and C_AutoComplete.GetAutoCompleteRealms()
    if type(list) == "table" then
        for i = 1, #list do
            local r = PlainString(list[i])
            if r then set[r] = true end
        end
    end
    -- Kept once this realm is known: the set never changes in a session.
    if own then connected = set end
    return set
end

local function ByName(a, b)
    local ea, eb = sortRoster[a], sortRoster[b]
    if ea.name ~= eb.name then return strcmputf8i(ea.name, eb.name) < 0 end
    if ea.realmKey ~= eb.realmKey then return ea.realmKey < eb.realmKey end
    return a < b
end
local function ByLevel(a, b)
    local la, lb = sortRoster[a].level or 0, sortRoster[b].level or 0
    if la ~= lb then return la > lb end
    return ByName(a, b)
end
local function ByRecent(a, b)
    local sa, sb = sortRoster[a].seen or 0, sortRoster[b].seen or 0
    if sa ~= sb then return sa > sb end
    return ByName(a, b)
end
local SORTS = { recent = ByRecent, level = ByLevel, name = ByName }

local function PlainLevel(level)
    if type(level) == "number" and not IsSecret(level) and level > 0 then return level end
end

local function ClassFile(classID, localized)
    local info = classID and not IsSecret(classID) and C_CreatureInfo.GetClassInfo(classID)
    if info and info.classFile then return info.classFile end
    return EUI.ClassTokenFromLocalized(localized)
end

-- Guild: every member but this character, online ones seen now and the
-- others at their last time online (the game counts it in hours).
local function GatherGuild(me, now)
    if not IsInGuild() then return end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, _, _, _, online, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        name, class = PlainString(name), PlainString(class)
        if name and class and PlainString(guid) ~= me then
            local seen = now
            if not online and GetGuildRosterLastOnline then
                local y, m, d, h = GetGuildRosterLastOnline(i)
                seen = now - ((((y or 0) * 12 + (m or 0)) * 30 + (d or 0)) * 24 + (h or 0)) * 3600
            end
            local target = Ambiguate(name, "mail")
            contacts[target] = { name = Ambiguate(name, "guild"), target = target, class = class,
                level = PlainLevel(level), seen = seen }
        end
    end
end

-- The Battle.net friends' characters seen in this game, by mail address.
local function Friends()
    local db = EllesmereUIDB
    if type(db) ~= "table" then return nil end
    if type(db.mailAltFriends) ~= "table" then db.mailAltFriends = {} end
    return db.mailAltFriends
end

-- A Battle.net friend playing this game: its character kept.
local function RememberFriend(acc, now)
    local ga = acc and acc.gameAccountInfo
    if not (ga and ga.isOnline and ga.clientProgram == BNET_CLIENT_WOW) then return end
    if ga.wowProjectID and ga.wowProjectID ~= WOW_PROJECT_ID then return end
    local name = PlainString(ga.characterName)
    local class = ClassFile(ga.classID, ga.className)
    local store = Friends()
    if not (name and class and store) then return end
    local e = store[name]
    if type(e) ~= "table" then
        e = {}
        store[name] = e
    end
    e.name, e.target, e.class = name, name, class
    e.level = PlainLevel(ga.characterLevel) or e.level
    e.faction = PlainString(ga.factionName) or e.faction
    e.seen = now
end

-- The game's friend list where it has one; else the Battle.net friends'
-- characters, those online now recorded first.
local function LegacyFriends()
    return C_FriendList.IsLegacyFriendSystemEnabled()
end

local function GatherFriends(now)
    if LegacyFriends() then
        for i = 1, C_FriendList.GetNumFriends() do
            local f = C_FriendList.GetFriendInfoByIndex(i)
            local name = f and PlainString(f.name)
            local class = f and ClassFile(nil, f.className)
            if name and class then
                contacts[name] = { name = Ambiguate(name, "guild"), target = name, class = class,
                    level = PlainLevel(f.level), seen = f.connected and now or 0 }
            end
        end
        return
    end
    for i = 1, BNGetNumFriends() do RememberFriend(C_BattleNet.GetFriendAccountInfo(i), now) end
    local store = Friends()
    if not store then return end
    for key, e in pairs(store) do
        if type(e) == "table" and type(e.name) == "string" and e.class then contacts[key] = e end
    end
end

local function Collect()
    wipe(shown)
    wipe(ignoredShown)
    mailable, ignoredCount = 0, 0
    local roster = Roster()
    local faction = PlainString((UnitFactionGroup("player")))
    paintedFaction = faction
    -- A character without a faction yet has no mail.
    if not roster or not faction or faction == "Neutral" then return end
    local me = myGuid or PlainString(UnitGUID("player"))
    local hidden = Hidden()
    local minLevel = NumberSetting("mailAltListMinLevel", DEFAULT_MIN_LEVEL)
    local tab = Tab()
    if tab == "alts" then
        source = roster
        -- WoW Forever: another ruleset is out of reach altogether.
        local own = FOREVER and OwnRealmKey()
        for guid, e in pairs(roster) do
            if guid ~= me and type(e) == "table" and type(e.name) == "string" and e.realmKey
               and (not own or e.realmKey == own) then
                mailable = mailable + 1
                if hidden and hidden[guid] then
                    ignoredCount = ignoredCount + 1
                    if showIgnored then ignoredShown[guid] = true end
                elseif (e.level or 0) >= minLevel then
                    shown[#shown + 1] = guid
                end
            end
        end
    else
        wipe(contacts)
        source = contacts
        if tab == "guild" then GatherGuild(me, time()) else GatherFriends(time()) end
        for key, e in pairs(contacts) do
            mailable = mailable + 1
            if (e.level or 0) >= minLevel then shown[#shown + 1] = key end
        end
    end
    local comparator = SORTS[Setting("mailAltListSort", DEFAULT_SORT)] or ByRecent
    sortRoster = source
    sort(shown, comparator)
    for i = #shown, Clamp(NumberSetting("mailAltListMax", DEFAULT_MAX), 1, MAX_ROWS) + 1, -1 do shown[i] = nil end
    -- The ignored ones, when asked: after the others, up to the list's top.
    if showIgnored then
        local extra = {}
        for guid in pairs(ignoredShown) do extra[#extra + 1] = guid end
        sort(extra, comparator)
        for i = 1, #extra do
            if #shown >= MAX_ROWS then ignoredShown[extra[i]] = nil else shown[#shown + 1] = extra[i] end
        end
    end
    sortRoster = nil
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local Paint, Place

local MenuFor

local function RowEnter(self)
    local e = self._guid and source and source[self._guid]
    if type(e) ~= "table" then return end
    local c = EUI.GetClassColor(e.class)
    local head = e.name
    if self._foreign then head = head .. " - " .. (e.realm or e.realmKey) end
    local text = EUI.HexColor(c.r, c.g, c.b) .. head .. "|r\n" .. Describe(e)
    if self._ignored then
        text = text .. "\n" .. EllesmereUI.L("Ignored: right-click to show it again.")
    end
    if self._limited then
        text = text .. "\n" .. (FOREVER and EllesmereUI.L("Your mail cannot reach the other faction.")
            or EllesmereUI.L("Only Warbound items can be mailed to this character."))
    end
    EUI.ShowWidgetTooltip(self, text .. "\n" .. EUI.COLOR_CODES.DIM
        .. (MenuFor(self) and EllesmereUI.L("Click to mail, right-click for options.")
            or EllesmereUI.L("Click to mail.")) .. "|r",
        { anchor = "right", justify = "LEFT" })
end

local function RowLeave()
    EUI.HideWidgetTooltip()
end

local function RowClick(self, button)
    if not self._guid then return end
    if button == "RightButton" then
        local menu = MenuFor(self)
        if menu then
            menuGuid = self._guid
            EUI.ShowContextMenu(self, menu)
        end
        return
    end
    local box = SendMailNameEditBox
    if box and self._target then box:SetText(self._target) end
end

local function NewRow(i)
    local r = CreateFrame("Button", nil, panel)
    r._mailAltRow = true
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if blizzLook then
        hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
        hl:SetBlendMode("ADD")
        hl:SetVertexColor(0.196, 0.388, 0.8)
    else
        hl:SetColorTexture(1, 1, 1, 0.08)
    end
    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    local lvl = r:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontDisableSmall" or nil)
    local name = r:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontHighlightSmall" or nil)
    if not blizzLook then
        WSkin.Font(lvl, 0.6, 0.6, 0.6, 11)
        -- A character's name: a font family, which draws the scripts the font lacks
        WSkin.FontFamily(name, nil, nil, nil, 12)
    end
    lvl:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    lvl:SetJustifyH("RIGHT")
    name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    name:SetPoint("RIGHT", lvl, "LEFT", -4, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    r._icon, r._name, r._lvl = icon, name, lvl
    r:SetScript("OnClick", RowClick)
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", RowLeave)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -(listTop + LIST_PAD + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -inset, -(listTop + LIST_PAD + (i - 1) * ROW_H))
    rows[i] = r
    return r
end

local function DressIcon(tex, class)
    local coords
    if blizzLook and FOREVER then
        -- WoW Forever: its own class icons (the character-create sheet there
        -- is laid out differently from retail's coordinates).
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas("classicon-" .. tostring(class):lower())
        tex:Show()
        return
    elseif blizzLook then
        coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then tex:SetTexture(BLIZZ_CLASS_ICONS) end
    else
        coords = EUI.CLASS_ICON_SPRITE_COORDS[class]
        if coords then tex:SetTexture(EUI_CLASS_ICONS) end
    end
    if coords then
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        tex:Show()
    else
        tex:Hide()
    end
end

-- A repaint under a resting cursor: the row now there shows its own tooltip.
local function ReplayHover()
    local foci = GetMouseFoci()
    for i = 1, #foci do
        local f = foci[i]
        if f and f._mailAltRow and f:IsVisible() then
            RowEnter(f)
            return
        end
    end
end

-------------------------------------------------------------------------------
--  The panel
-------------------------------------------------------------------------------
local function PaintBackdrop()
    if blizzLook or not panel then return end
    local modern = WSkin.GetStyle("mail") == "modern"
    bgArt:SetAlpha(modern and 0 or 1)
    bgShade:SetAlpha(modern and 0 or 1)
    if modern then
        bgFlat:SetColorTexture(WSkin.GetModernBG())
    else
        bgFlat:SetColorTexture(0, 0, 0, 0)
    end
end

-- The tab strip: plain buttons, the shown tab bright and underlined.
local TAB_LIST = { "alts", "guild", "friends" }

local function PaintTabs()
    local cur = Tab()
    for key, b in pairs(tabs) do
        b._text:SetAlpha(key == cur and 1 or 0.5)
        b._line:SetShown(key == cur)
    end
end

local function SetTab(key)
    if not EllesmereUIDB or Tab() == key then return end
    EllesmereUIDB.mailAltListTab = key
    if key == "guild" and IsInGuild() then C_GuildInfo.GuildRoster() end
    PaintTabs()
    Changed()
end

BuildTabs = function()
    -- Clear of the title band (Blizz Default's frame edge reaches into it).
    local top = topH + 2
    listTop = top + TAB_H
    local w = (PANEL_W - inset * 2) / #TAB_LIST
    local labels = { alts = EllesmereUI.L("Characters"), guild = EllesmereUI.L("Guild"),
        friends = EllesmereUI.L("Friends") }
    for i, key in ipairs(TAB_LIST) do
        local b = CreateFrame("Button", nil, panel)
        b:SetSize(w, TAB_H)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", inset + (i - 1) * w, -top)
        local text = b:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontNormalSmall" or nil)
        if not blizzLook then WSkin.Font(text, 1, 1, 1, 11) end
        text:SetPoint("LEFT", 2, 0)
        text:SetPoint("RIGHT", -2, 0)
        text:SetWordWrap(false)
        text:SetText(labels[key])
        local line = b:CreateTexture(nil, "ARTWORK")
        line:SetHeight(2)
        line:SetPoint("BOTTOMLEFT", 6, 0)
        line:SetPoint("BOTTOMRIGHT", -6, 0)
        if blizzLook then line:SetColorTexture(1, 0.82, 0, 0.9) else line:SetColorTexture(1, 1, 1, 0.8) end
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        b._text, b._line = text, line
        b:SetScript("OnClick", function() SetTab(key) end)
        tabs[key] = b
    end
    PaintTabs()
end

local function Build()
    if not Theme.fontPath then WSkin.ResolveTheme() end
    -- Named: a frame of ours the window skin's art sweeps leave alone.
    if blizzLook then
        topH, inset, gap = BLIZZ_TOP, BLIZZ_INSET, BLIZZ_GAP
        if FOREVER then
            -- WoW Forever: its frame borders are built for a portrait and a
            -- close button (their top corners stand above the frame), so the
            -- list takes the game's plain dialog box instead. A plain frame
            -- with the backdrop mixin, not BackdropTemplate, whose
            -- OnSizeChanged script would sit in SendMailFrame's subtree: Paint
            -- refreshes the edge coordinates itself after each resize.
            topH, inset = FOREVER_TOP, FOREVER_INSET
            panel = CreateFrame("Frame", "EllesmereUIMailAltList", SendMailFrame)
            Mixin(panel, BackdropTemplateMixin)
            panel:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24,
                insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
            title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            title:SetPoint("TOP", panel, "TOP", 0, -10)
        else
            panel = CreateFrame("Frame", "EllesmereUIMailAltList", SendMailFrame, "DefaultPanelTemplate")
            panel:SetTitleOffsets(6, -6)
            title = panel:GetTitleText()
        end
    else
        topH, inset, gap = EUI_TOP, EUI_INSET, EUI_GAP
        panel = CreateFrame("Frame", "EllesmereUIMailAltList", SendMailFrame)
        -- The mail window's own shell layers: the atlas under a black wash
        -- (EllesmereUI), or the one Modern colour. Built here rather than through
        -- WSkin.Shell, which hooks OnSizeChanged: no script of ours may sit in
        -- SendMailFrame's subtree.
        bgArt = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
        bgArt:SetTexture(SHELL_ART)
        bgArt:SetAllPoints()
        bgShade = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
        bgShade:SetColorTexture(0, 0, 0, 0.62)
        bgShade:SetAllPoints()
        bgFlat = panel:CreateTexture(nil, "BACKGROUND", nil, -6)
        bgFlat:SetAllPoints()
        local band = panel:CreateTexture(nil, "BACKGROUND", nil, -5)
        band:SetColorTexture(0, 0, 0, 0.5)
        band:SetPoint("TOPLEFT")
        band:SetPoint("TOPRIGHT")
        band:SetHeight(topH)
        WSkin.AddBorder(panel)
        title = panel:CreateFontString(nil, "OVERLAY")
        WSkin.Font(title, 1, 1, 1, 12)
        title:SetPoint("CENTER", band, "CENTER", 0, 0)
        PaintBackdrop()
        WSkin.OnStylesChanged(PaintBackdrop)
    end
    title:SetText(EllesmereUI.L("Alts"))
    BuildTabs()
    -- A cog in the title band: the list's own menu, on the spot.
    -- On Blizzard's DefaultPanelTemplate the border (NineSlice) sits at frame
    -- level 500, over any plain child: the cog lives in the title's container
    -- (510) there.
    local cog = CreateFrame("Button", nil, (blizzLook and not FOREVER) and panel.TitleContainer or panel)
    cog:SetSize(14, 14)
    local cogY = blizzLook and (FOREVER and -17 or -11) or -(topH / 2)
    cog:SetPoint("RIGHT", panel, "TOPRIGHT", -(inset + 6), cogY)
    cog:SetNormalTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\cogs.png")
    cog:GetNormalTexture():SetAlpha(0.6)
    cog:SetHighlightTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\cogs.png", "ADD")
    cog:SetScript("OnClick", function(self)
        EUI.HideWidgetTooltip()
        local function Set(key, value)
            if EllesmereUIDB then EllesmereUIDB[key] = value end
            Changed()
        end
        local sort = Setting("mailAltListSort", DEFAULT_SORT)
        local function SortItem(value, label)
            return { text = label, isActive = sort == value, onClick = function() Set("mailAltListSort", value) end }
        end
        EUI.ShowContextMenu(self, {
            { text = showIgnored and "Hide Ignored Characters" or "Show Ignored Characters",
              onClick = function()
                  showIgnored = not showIgnored
                  Changed()
              end },
            "---",
            { text = "Sort By", children = {
                SortItem("recent", "Last Played"), SortItem("level", "Level"), SortItem("name", "Name"),
            } },
            { text = "Max Characters Shown", isInput = true, min = 1,
              getValue = function() return Clamp(NumberSetting("mailAltListMax", DEFAULT_MAX), 1, MAX_ROWS) end,
              setValue = function(v) Set("mailAltListMax", Clamp(v, 1, MAX_ROWS)) end },
            { text = "Minimum Level", isInput = true, min = 1,
              getValue = function() return NumberSetting("mailAltListMinLevel", DEFAULT_MIN_LEVEL) end,
              setValue = function(v) Set("mailAltListMinLevel", Clamp(v, 1, GetMaxLevelForLatestExpansion())) end },
        })
    end)
    cog:SetScript("OnEnter", function(self)
        EUI.ShowWidgetTooltip(self, EllesmereUI.L("Alts") .. "\n" .. EUI.COLOR_CODES.DIM
            .. EllesmereUI.L("Click for the list's options.") .. "|r", { anchor = "right", justify = "LEFT" })
    end)
    cog:SetScript("OnLeave", RowLeave)
    panel:SetWidth(PANEL_W)
    panel:SetClampedToScreen(true)
    -- It hangs outside the window: a click on its empty parts stays off the world.
    panel:EnableMouse(true)
    emptyNote = panel:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontDisableSmall" or nil)
    if not blizzLook then WSkin.Font(emptyNote, 0.6, 0.6, 0.6, 11) end
    -- Its own width, never one from anchors: the note is measured before the
    -- panel is first placed, and a width taken from unplaced anchors measures
    -- the text as one unwrapped line (a panel too short, the note cut off).
    emptyNote:SetWidth(PANEL_W - EMPTY_PAD * 2)
    emptyNote:SetPoint("TOP", panel, "TOP", 0, -(listTop + EMPTY_PAD))
    emptyNote:SetJustifyH("CENTER")
    emptyNote:SetSpacing(2)
end

-- Why the shown tab lists nobody.
local function EmptyText()
    local tab = Tab()
    if tab == "guild" then
        if not IsInGuild() then return ERR_GUILD_PLAYER_NOT_IN_GUILD or "" end
        if mailable == 0 then
            return GetNumGuildMembers() == 0 and (RETRIEVING_DATA or "")
                or EllesmereUI.L("No one else is in your guild.")
        end
    elseif tab == "friends" then
        if mailable == 0 then
            return LegacyFriends() and EllesmereUI.L("Your friends list is empty.")
                or EllesmereUI.L("Your Battle.net friends' characters show here once seen in this game.")
        end
    else
        if mailable == 0 then return EllesmereUI.L("Log into your other characters to list them here.") end
        return EllesmereUI.L("Your other characters are hidden by Shown Characters or Minimum Level.")
            .. (ignoredCount > 0 and ("\n" .. EllesmereUI.L("The cog shows the ignored ones.")) or "")
    end
    return EllesmereUI.L("Everyone here is hidden by Minimum Level.")
end

Paint = function()
    dirty = false
    paintedGen = EUI._dmGen
    Collect()
    local own = OwnRealmKey()
    local realms = ConnectedRealms()
    local myFaction = FOREVER and paintedFaction
    local n = #shown
    for i = 1, n do
        local guid = shown[i]
        local e = source[guid]
        local r = rows[i] or NewRow(i)
        -- A guild member or a friend (e.target): its mail address as the game gave it.
        local foreign = not e.target and e.realmKey ~= own
        -- Any mail reaches this realm or a connected one, either faction;
        -- another realm takes Warbound items only and shows dimmed. WoW
        -- Forever: the same ruleset only (Collect), and the same faction.
        local limited
        if e.target then
            limited = FOREVER and myFaction ~= nil and e.faction ~= nil and e.faction ~= myFaction
        elseif FOREVER then
            limited = myFaction ~= nil and e.faction ~= nil and e.faction ~= myFaction
        else
            limited = not realms[e.realmKey]
        end
        local ignored = ignoredShown[guid] == true
        r._guid, r._foreign, r._limited, r._ignored = guid, foreign, limited, ignored
        -- Mail addresses another realm's character as "Name-Realm", and a
        -- WoW Forever character by its full name, "Name Surname".
        if e.target then
            r._target = e.target
        elseif FOREVER then
            r._target = e.surname and (e.name .. " " .. e.surname) or e.name
        else
            r._target = foreign and (e.name .. "-" .. e.realmKey) or e.name
        end
        DressIcon(r._icon, e.class)
        local c = EUI.GetClassColor(e.class)
        if e.target then
            r._name:SetText(e.name)
        elseif FOREVER then
            r._name:SetText(e.surname and (e.name .. " " .. e.surname) or e.name)
        else
            r._name:SetText(foreign and (e.name .. FOREIGN_SERVER_LABEL) or e.name)
        end
        if ignored then r._name:SetText(r._name:GetText() .. " " .. EUI.COLOR_CODES.DIM .. EllesmereUI.L("(ignored)") .. "|r") end
        r._name:SetTextColor(c.r, c.g, c.b)
        r._lvl:SetText(e.level or "")
        r:SetAlpha(ignored and IGNORED_ALPHA or (limited and LIMITED_ALPHA or 1))
        r:Show()
    end
    local owner = EUI._WidgetTooltipOwner()
    for i = n + 1, #rows do
        local r = rows[i]
        if owner == r then EUI.HideWidgetTooltip(true) end
        r:Hide()
        r._guid, r._target, r._limited, r._ignored = nil, nil, nil, nil
    end
    local h
    if n > 0 then
        emptyNote:Hide()
        h = listTop + LIST_PAD * 2 + n * ROW_H
    else
        emptyNote:SetText(EmptyText())
        emptyNote:Show()
        h = listTop + EMPTY_PAD * 2 + math.ceil(emptyNote:GetStringHeight())
    end
    if blizzLook then h = h + (FOREVER and 8 or 2) end   -- the frame's bottom edge
    panel:SetHeight(h)
    if panel.SetupTextureCoordinates then panel:SetupTextureCoordinates() end
    if bgArt then WSkin.CoverFit(bgArt, PANEL_W, h) end
    if owner then ReplayHover() end
end

local function ScreenRect(f)
    local s = f:GetEffectiveScale()
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) or IsSecret(l) or IsSecret(r) or IsSecret(t) or IsSecret(b) then return nil end
    return l * s, r * s, t * s, b * s
end

local function Anchor(to, side)
    if placedTo == to and placedSide == side then return end
    placedTo, placedSide = to, side
    panel:ClearAllPoints()
    if side == "left" then
        panel:SetPoint("TOPRIGHT", to, "TOPLEFT", -gap, 0)
    else
        panel:SetPoint("TOPLEFT", to, "TOPRIGHT", gap, 0)
    end
end

-- Beside the mail window; past an open letter it would cover; on the window's
-- left when the screen has no room on its right.
Place = function()
    local mf, letter = MailFrame, OpenMailFrame
    local to, side = mf, "right"
    local ml, mr, mt = ScreenRect(mf)
    if mr then
        local s = panel:GetEffectiveScale()
        local w, h, g = PANEL_W * s, panel:GetHeight() * s, gap * s
        local left = mr + g
        if letter and letter:IsShown() then
            local ll, lr, lt, lb = ScreenRect(letter)
            if ll and left < lr and left + w > ll and mt - h < lt and mt > lb then
                to, left = letter, lr + g
            end
        end
        local screen = UIParent:GetRight() * UIParent:GetEffectiveScale()
        if left + w > screen and ml - g - w >= 0 then
            to, side = mf, "left"
        end
    end
    Anchor(to, side)
end

-- Shown before the paint: a font string measures its height only while visible.
-- Repainted when the list changed, a class colour was edited since (the colour
-- palette's generation) or this character has picked its faction since.
local function ShowPanel()
    if not panel then Build() end
    panel:Show()
    -- Guild members and friends come and go: their tabs repaint on every show.
    local tab = Tab()
    if tab == "guild" and IsInGuild() then C_GuildInfo.GuildRoster() end
    if dirty or tab ~= "alts" or paintedGen ~= EUI._dmGen or paintedFaction ~= PlainString((UnitFactionGroup("player"))) then
        Paint()
    end
    Place()
end

-- A change from the right-click menu: the list, and the open options page's
-- Shown Characters summary.
Changed = function()
    dirty = true
    if panel and panel:IsVisible() then
        Paint()
        Place()
    end
    if EUI:IsShown() then EUI:RefreshPage() end
end

local function SetShown(guid, on)
    if not EllesmereUIDB then return end
    local h = EllesmereUIDB.mailAltHidden
    if on then
        if type(h) == "table" then
            h[guid] = nil
            if not next(h) then EllesmereUIDB.mailAltHidden = nil end
        end
    else
        if type(h) ~= "table" then
            h = {}
            EllesmereUIDB.mailAltHidden = h
        end
        h[guid] = true
    end
    dirty = true
end

MENU = {
    { text = "Ignore This Character",
      tooltip = "Hides it until ticked again in Shown Characters.",
      onClick = function()
          if menuGuid then SetShown(menuGuid, false); Changed() end
      end },
    { text = "Remove Character",
      tooltip = "Forgets a deleted or moved character.",
      onClick = function()
          local roster = Roster()
          local guid = menuGuid
          local e = guid and roster and roster[guid]
          if type(e) ~= "table" then return end
          -- Asked first: a misclick would drop a rarely played alt until it next logs in.
          EUI:ShowConfirmPopup({
              title       = "Remove Character",
              message     = EllesmereUI.Lf("Remove %s from the Alt List? It comes back when you next log into it.", e.name),
              confirmText = "Remove",
              cancelText  = "Cancel",
              onConfirm   = function()
                  roster[guid] = nil
                  local h = Hidden()
                  if h and h[guid] then SetShown(guid, true) end
                  Changed()
              end,
          })
      end },
}

-- A Battle.net friend's character: forget it (a moved or deleted one).
local FRIEND_MENU = {
    { text = "Remove Character",
      tooltip = "Forgets this character until it is seen online again.",
      onClick = function()
          local store = Friends()
          if store and menuGuid then
              store[menuGuid] = nil
              Changed()
          end
      end },
}

-- An ignored character (shown on request): undo the ignore, or forget it.
IGNORED_MENU = {
    { text = "Show This Character Again",
      tooltip = "Lists it again, as if ticked in Shown Characters.",
      onClick = function()
          if menuGuid then SetShown(menuGuid, true); Changed() end
      end },
    MENU[2],
}

-- A row's right-click menu: the player's own characters and the remembered
-- Battle.net friends have one; the guild and the game's friend list none.
MenuFor = function(row)
    local tab = Tab()
    if tab == "alts" then return row._ignored and IGNORED_MENU or MENU end
    if tab == "friends" and not LegacyFriends() then return FRIEND_MENU end
end

-------------------------------------------------------------------------------
--  Hooks: tab switches and the letter window
-------------------------------------------------------------------------------
local function OnTab()
    if not Enabled() or not SendMailFrame:IsVisible() then return end
    ShowPanel()
end

local function OnInboxUpdate()
    if panel and panel:IsVisible() and Enabled() then Place() end
end

local function HookMail()
    if hooked or type(_G.MailFrameTab_OnClick) ~= "function" then return end
    -- WoW Forever's inbox is a mixin: its update is InboxFrame:Update.
    local inbox = _G.InboxFrame
    local mixinUpdate = type(_G.InboxFrame_Update) ~= "function" and inbox and type(inbox.Update) == "function"
    if type(_G.InboxFrame_Update) ~= "function" and not mixinUpdate then return end
    hooked = true
    hooksecurefunc("MailFrameTab_OnClick", OnTab)
    if mixinUpdate then
        hooksecurefunc(inbox, "Update", OnInboxUpdate)
    else
        hooksecurefunc("InboxFrame_Update", OnInboxUpdate)
    end
end

-- While the list is on: a guild or friend list update repaints its shown tab,
-- and a Battle.net friend entering this game is remembered.
local CONTACT_EVENTS = { "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED" }
local function WatchContacts(on)
    for i = 1, #CONTACT_EVENTS do
        if on then ev:RegisterEvent(CONTACT_EVENTS[i]) else ev:UnregisterEvent(CONTACT_EVENTS[i]) end
    end
end

local function OnContacts(event, arg1)
    if event == "BN_FRIEND_INFO_CHANGED" and arg1 and not LegacyFriends() then
        RememberFriend(C_BattleNet.GetFriendAccountInfo(arg1), time())
    end
    local tab = Tab()
    if tab == "alts" or not (panel and panel:IsVisible()) then return end
    if (event == "GUILD_ROSTER_UPDATE") == (tab == "guild") then
        Paint()
        Place()
    end
end

local function Install()
    WatchContacts(true)
    if hooked then return end
    if C_AddOns.IsAddOnLoaded("Blizzard_MailFrame") then
        HookMail()
    else
        ev:RegisterEvent("ADDON_LOADED")
    end
end

-------------------------------------------------------------------------------
--  The Mail card's options (EUI_BlizzardSkin_Options.lua)
-------------------------------------------------------------------------------
ns.MailAlts = {
    DEFAULT_MAX = DEFAULT_MAX, DEFAULT_MIN_LEVEL = DEFAULT_MIN_LEVEL,
    DEFAULT_SORT = DEFAULT_SORT, MAX_ROWS = MAX_ROWS,
    Describe = Describe,
}

-- A setting changed: the hooks on the first enable, the open Send Mail page
-- repainted, the panel put away when turned off.
function ns.MailAlts.Refresh()
    dirty = true
    if Enabled() then
        Install()
        -- Visible, not shown: SendMailFrame keeps its shown flag while the
        -- mailbox is closed, and the panel paints only where it can measure.
        if hooked and SendMailFrame:IsVisible() then ShowPanel() end
    else
        WatchContacts(false)
        if not panel then return end
        panel:Hide()
        local owner = EUI.ContextMenuOwner()
        if owner and owner._mailAltRow then EUI.CloseContextMenu() end
    end
end

-- Every recorded character, for Shown Characters: by realm (this one first),
-- then by name. A fresh list per call (the menu builds on open).
function ns.MailAlts.Entries()
    local out = {}
    local roster = Roster()
    if not roster then return out end
    for guid, e in pairs(roster) do
        if type(e) == "table" and type(e.name) == "string" then
            out[#out + 1] = { guid = guid, name = e.name, realm = e.realm or e.realmKey or "",
                class = e.class, level = e.level, faction = e.faction }
        end
    end
    local own = FOREVER and EUI.RealmGroupName() or GetRealmName()
    sort(out, function(a, b)
        if a.realm ~= b.realm then
            if a.realm == own then return true end
            if b.realm == own then return false end
            return strcmputf8i(a.realm, b.realm) < 0
        end
        if a.name ~= b.name then return strcmputf8i(a.name, b.name) < 0 end
        return a.guid < b.guid
    end)
    return out
end

function ns.MailAlts.IsShown(guid)
    local h = Hidden()
    return not (h and h[guid])
end

function ns.MailAlts.SetShown(guid, on)
    SetShown(guid, on)
    if panel and panel:IsVisible() then
        Paint()
        Place()
    end
end

-------------------------------------------------------------------------------
--  Boot: the roster at login and logout; the hooks once the list is on
-------------------------------------------------------------------------------
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        blizzLook = WSkin.GetStyle("mail") == "off"
        RecordPlayer()
        if Enabled() then Install() end
    elseif event == "PLAYER_LOGOUT" then
        RecordPlayer()
    elseif event ~= "ADDON_LOADED" then
        OnContacts(event, arg1)
    elseif arg1 == "Blizzard_MailFrame" then
        self:UnregisterEvent("ADDON_LOADED")
        HookMail()
    end
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
