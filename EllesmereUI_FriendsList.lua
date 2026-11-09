if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_FriendsList.lua
--  The custom friends list: rows of our own drawn over Blizzard's Social UI
--  friends list, for a tile height and friend groups Blizzard's list cannot
--  have (its row height is fixed when the window loads, and any change to its
--  data taints Battle.net whispers: see EllesmereUI_FriendsKit.lua).
--
--  HOW IT STAYS CLEAN. Blizzard's list keeps running underneath at alpha 0;
--  ours is drawn over it and takes the mouse. Every row carries a frame made
--  from Blizzard's InlineHyperlinkFrameTemplate that holds one invisible
--  Battle.net player link across the row. The template's click handler is
--  Blizzard's own (it calls SetItemRef), so a right click opens the friend
--  menu through the code a click on a friend's name in chat runs, and that
--  menu's Whisper opens the chat box with nothing of ours in between. A left
--  click only selects the friend, as on Blizzard's list: a click layer of
--  ours lies over every row's link and takes every button but the right one,
--  which it passes down to the link (see Clicks), so Blizzard's handler never
--  sees that click, and the release sets nothing but our own selection.
--  Field-checked on WoW Forever 1.60.1 (70790): a whisper through the link,
--  the menu's Whisper and entries added to that menu all stayed
--  Blizzard-secure, while a whisper opened from addon code did not.
--  Rules that keep it so:
--    - never give the link frame a click script (OnClick, OnMouseDown / Up,
--      OnHyperlinkClick): a post-hook on the link click is safe, a
--      replacement is not; a right click is never touched;
--    - never open a whisper or Blizzard's friend menu from our code
--      (ChatFrameUtil.SendBNetTell, UnitPopup_OpenMenu);
--    - our entries reach that menu through Menu.ModifyMenu only, and call
--      plain friend functions (note, favorite, tags, remove) or our own
--      group store;
--    - nothing is written onto a Blizzard frame, and Blizzard's list, its
--      provider and its cards are left alone but for the alpha of the list
--      and its scroll bar.
--
--  The link must be ONE line of text taller than the row: its line box is the
--  live zone (wrapped text is live on its first two lines only, and an inline
--  texture is not clickable).
--
--  Availability: its host starts it, and its host's settings carry its
--  switch, customTiles (false stands it down; settings without the key keep
--  it on). On WoW Forever that is the Friends List card's Custom Friends
--  List Tiles, which follows the card's look until picked: on while the card
--  is skinned, off under Blizz Default, where the host starts for the list
--  alone. The Social UI friends list must exist and the client's menu code
--  must isolate added entries (Menu.IsMenuProxy came with that change). The
--  list stands down under WoW Forever's Gamepad interface style, where a
--  controller drives Blizzard's list.
--
--  The scroll area is the rect of Blizzard's own list, a tile is inset from
--  its sides as Blizzard's cards are, and the scroll bar is a frame of ours
--  made from the template of Blizzard's bar and laid over it: the list looks
--  like the lists of the window's other tabs. It scrolls as they do too: the
--  wheel is that bar's own step, with no easing. An online friend's row
--  wears Blizzard's own card art at the alpha its host gives it (onlineCards;
--  WoW Forever's card: whole under Blizz Default, a quarter under its tiles).
--
--  Cost: at the start one frame is made, a child of the friends view that
--  carries its show and hide edge; nothing else is built, registered or run
--  until that view shows, and then only while it shows. Friend events are
--  coalesced to one rebuild per frame, a change to one friend that moves
--  nothing repaints that row alone, and rows and headers are pooled:
--  scrolling paints only the rows entering view.
--
--  Groups are account data in EllesmereUIDB.global (outside the profiles and
--  outside exports): the group list, order, colours and collapsed state, and
--  each friend's group by BattleTag. A "||EUI:Group||" tag an old Friends
--  build left in a friend note is read once and never written.
--
--  Favorites is Battle.net's own favorite list shown as a section among the
--  groups, and the friend menu offers it as one: a friend's custom group wins
--  over it, and a pick that moves a friend into Favorites, or out of it to
--  the ungrouped friends, sets Battle.net's favorite switch.
-------------------------------------------------------------------------------
local FL = {}
EllesmereUI.FriendsList = FL

local Kit = EllesmereUI.FriendsKit
local T = Kit._tile
local IsSecret = EllesmereUI.IsSecret

local TEMPLATE = "InlineHyperlinkFrameTemplate"
-- name : account id : line id : chat type : chat target (the chat frame's own form)
local LINK_FORMAT = "|HBNplayer:%s:%d:0:BN_WHISPER:%s|h%s|h"
-- More letters than any row needs: the text is cut at the block's width
local LINK_FILLER = string.rep("M", 64)
-- The link text against its row: font size over the row's height, and how far
-- above the row's top it starts
local LINK_TALLER, LINK_ABOVE = 8, 5
local MENU_TAGS = { "MENU_UNIT_BN_FRIEND", "MENU_UNIT_BN_FRIEND_OFFLINE" }
local ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
-- Blizzard's own art from its friend cards: the invite button and the status
-- icons. The button is 34 across on Blizzard's 70-tall card; ours is halfway
-- between that share of the tile and a flat 28, plus BTN_EXTRA (StyleRow):
-- 26 on the default tile.
local BTN_NORMAL, BTN_PUSHED = "common-button-tertiary-square-normal", "common-button-tertiary-square-pressed"
local BTN_NATIVE, BTN_SHARE, BTN_MIN, BTN_FLAT, BTN_EXTRA = 34, 0.52, 16, 28, 2
local STATUS_ATLAS = {
    online = "friends-status-online", away = "friends-status-away",
    busy = "friends-status-busy", offline = "friends-status-offline",
}
-- The status icon against the end of the text before it: its art keeps empty
-- edges, so it sits a little into the text's box and above its middle
local STATUS_DX, STATUS_DY = -1, 2

local TILE_MIN, TILE_MAX, TILE_DEFAULT = 24, 70, 40
local HEADER_H = 24
local ROW_GAP, GROUP_GAP = 2, 4
local PAD_TOP, PAD_BOTTOM = 6, 6
-- A tile's inset from the sides of the scroll area: those of Blizzard's own
-- list, so a tile is as wide as one of its cards
local PAD_LEFT, PAD_RIGHT = 10, 7
local TEXT_GAP = 4              -- between the icon square and the text
local CHAR_GAP = 5              -- between the Battle.net name and the character after it
local CHAR_LIFT = 1             -- the character text's bottom above the name's
local EDGE_PAD = 4              -- between a row's right edge and what sits there
local NOTE_MAX = 127            -- Blizzard's own limit on a friend note
local GROUP_NAME_MAX = 32

local FAV, UNGROUPED = "_favorites", "_ungrouped"
local KIND_HEADER, KIND_FRIEND = 0, 1

-- The kit's host (settings, look, font): set once by FL.Start
local host
local driver, root, sf, content, bar, flusher, ev, filterX
local active = false            -- live: shown, listening
local covering = false          -- Blizzard's list is hidden under ours
local viewH, rowW = 0, 0
local tileH, tier = TILE_DEFAULT, 2
local ring = 8                  -- pool slots: more than the items one view spans
local styleGen, modelGen, visGen = 0, 0, 0
local dirtyFull, dirtyInvites = false, false
local searchActive = false
local searchCollapsed = {}      -- sections folded during a search, for that search alone
local hoverRow
local selectedId                -- the selected friend's account id (a left click picks it)
local rowPool, headerPool = {}, {}     -- by ring slot
local rowList, headerList = {}, {}     -- every frame made, in order
local items, itemCount = {}, 0
local records, recordCount = {}, 0
local byId, byIndex = {}, {}
local rendered, renderedCount = {}, 0
local menuHandles = {}

local function Settings()
    return host and host.Settings()
end

local function View()
    local f = _G.SocialUIFrame
    return f and f.FriendsList
end

local function ClampTile(v)
    v = tonumber(v) or TILE_DEFAULT
    return math.max(TILE_MIN, math.min(TILE_MAX, math.floor(v + 0.5)))
end

-------------------------------------------------------------------------------
--  Group store
-------------------------------------------------------------------------------
local function Store()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local g = EllesmereUIDB.global
    if type(g) ~= "table" then g = {}; EllesmereUIDB.global = g end
    if type(g.friendGroups) ~= "table" then g.friendGroups = {} end
    if type(g.friendGroupsByTag) ~= "table" then g.friendGroupsByTag = {} end
    if type(g.friendGroupColors) ~= "table" then g.friendGroupColors = {} end
    if type(g.friendGroupOrder) ~= "table" then g.friendGroupOrder = {} end
    return g
end

local function FindGroup(g, name)
    local list = g.friendGroups
    for i = 1, #list do
        if list[i].name == name then return list[i], i end
    end
end

-- The section order with every section in it once: the saved order first,
-- then Favorites on top, new groups above the ungrouped friends, and those
-- last. The saved list is rewritten only when it was not already that.
local orderBuf, orderSeen = {}, {}
local function ValidOrder(g)
    local saved = g.friendGroupOrder
    wipe(orderBuf)
    wipe(orderSeen)
    local n = 0
    for i = 1, #saved do
        local key = saved[i]
        if not orderSeen[key] and (key == FAV or key == UNGROUPED or FindGroup(g, key)) then
            n = n + 1
            orderBuf[n] = key
            orderSeen[key] = true
        end
    end
    if not orderSeen[FAV] then
        table.insert(orderBuf, 1, FAV)
        orderSeen[FAV] = true
        n = n + 1
    end
    local list = g.friendGroups
    for i = 1, #list do
        local name = list[i].name
        if not orderSeen[name] then
            local at = n + 1
            for k = 1, n do
                if orderBuf[k] == UNGROUPED then at = k; break end
            end
            table.insert(orderBuf, at, name)
            orderSeen[name] = true
            n = n + 1
        end
    end
    if not orderSeen[UNGROUPED] then
        n = n + 1
        orderBuf[n] = UNGROUPED
    end
    local same = #saved == n
    if same then
        for i = 1, n do
            if saved[i] ~= orderBuf[i] then same = false; break end
        end
    end
    if not same then
        local fresh = {}
        for i = 1, n do fresh[i] = orderBuf[i] end
        g.friendGroupOrder = fresh
    end
    return orderBuf, n
end

local function IsCollapsed(g, key)
    if key == FAV then return g.friendFavCollapsed == true end
    if key == UNGROUPED then return g.friendUngroupedCollapsed == true end
    local grp = FindGroup(g, key)
    return grp ~= nil and grp.collapsed == true
end

local function CleanGroupName(text)
    if type(text) ~= "string" then return nil end
    local name = strtrim(text)
    if name == "" or name == FAV or name == UNGROUPED then return nil end
    if #name > GROUP_NAME_MAX then name = name:sub(1, GROUP_NAME_MAX) end
    return name
end

-------------------------------------------------------------------------------
--  Friend facts
-------------------------------------------------------------------------------
-- A friend's key in the group store: the BattleTag, or for a friend added by
-- character (no BattleTag) the character Blizzard whispers. Kept per account
-- id until the friend list changes size.
local keyById, sortById = {}, {}
local function FriendKey(info)
    local id = info.bnetAccountID
    local key = keyById[id]
    if key ~= nil then return key or nil end
    local tag = info.battleTag
    if type(tag) == "string" and not IsSecret(tag) and tag ~= "" then
        key = tag
    elseif C_BattleNet.GetDefaultTitleWhisperTarget then
        local target = C_BattleNet.GetDefaultTitleWhisperTarget(id)
        if type(target) == "string" and not IsSecret(target) and target ~= "" then
            key = "title:" .. target
        end
    end
    keyById[id] = key or false
    return key
end

local function SortName(info)
    local id = info.bnetAccountID
    local name = sortById[id]
    if name then return name end
    local tag = info.battleTag
    if type(tag) == "string" and not IsSecret(tag) and tag ~= "" then
        name = tag:lower()
        name = name:match("^(.-)#") or name
    else
        name = ""
    end
    sortById[id] = name
    return name
end

-- 1 online in this game, 2 another WoW, 3 another game, 4 the app, 5 offline
local function Priority(gi)
    if gi and gi.isOnline then
        local cp = gi.clientProgram
        if cp == BNET_CLIENT_WOW then
            return (gi.wowProjectID == WOW_PROJECT_ID or gi.wowProjectID == nil) and 1 or 2
        end
        if not cp or cp == "" or cp == "BSAp" or cp == "App" then return 4 end
        return 3
    end
    return 5
end

-- Whether a friend counts as a favorite: Battle.net's flag, or what a menu
-- pick asked Battle.net for until its answer arrives, so the friend sits
-- where it was put at once. Kept per account id while the list shows; a flag
-- the game keeps secret counts as not set.
local favAsked = {}
local function IsFavorite(info)
    local fav = info.isFavorite
    fav = not IsSecret(fav) and fav == true
    local id = info.bnetAccountID
    local asked = favAsked[id]
    if asked == nil then return fav end
    if asked == fav then favAsked[id] = nil end
    return asked
end

-- The section a friend sits in: its custom group first, then Favorites for a
-- favorite, else the ungrouped friends
local function BucketOf(g, info, key)
    local name = key and g.friendGroupsByTag[key]
    if name and FindGroup(g, name) then return name end
    if IsFavorite(info) then return FAV end
    return UNGROUPED
end

-- The group an old Friends build wrote into a friend note, read once so those
-- groups come back. Nothing is written to the note.
local function MigrateNoteTags(g)
    if g.friendGroupsTagMigrated then return end
    local total = BNGetNumFriends() or 0
    if total == 0 then return end
    g.friendGroupsTagMigrated = true
    for i = 1, total do
        local info = C_BattleNet.GetFriendAccountInfo(i)
        local note = info and info.note
        if type(note) == "string" and not IsSecret(note) then
            local s = note:find("||EUI:", 1, true)
            local e = s and note:find("||", s + 6, true)
            local name = e and CleanGroupName(note:sub(s + 6, e - 1))
            local key = name and FriendKey(info)
            if key and not g.friendGroupsByTag[key] then
                if not FindGroup(g, name) then
                    g.friendGroups[#g.friendGroups + 1] = { name = name, collapsed = false }
                end
                g.friendGroupsByTag[key] = name
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Search: Blizzard's own search box and filter menu keep working. The game
--  refuses the friend search call to an addon (C_BattleNet.SearchFriends: a
--  blocked action), so the list never makes it: Blizzard's list, alive under
--  ours, runs each search itself and holds the answer in its tree of
--  sections, and the friends that passed are read from there. Plain getters
--  only: nothing of Blizzard's is written or asked to work.
-------------------------------------------------------------------------------
local allowedSet = {}

-- One of Blizzard's filters is ticked
local function FiltersOn(view)
    local selected = view.selectedSearchFilterOptions
    if type(selected) == "table" then
        for _, on in pairs(selected) do
            if on then return true end
        end
    end
    return false
end

-- Blizzard's search box holds text
local function SearchTextOn(view)
    local bar = view.FilterBar and view.FilterBar.SearchBar
    local text = bar and bar.GetText and bar:GetText()
    return IsSecret(text) or (type(text) == "string" and text ~= "")
end

-- The friends in Blizzard's list: its sections, then the friends under each
-- (a section Blizzard shows collapsed still holds its friends)
local function ReadBlizzardList(view, into)
    local sections = view.ScrollBox:GetDataProvider():GetRootNode():GetNodes()
    for i = 1, #sections do
        local nodes = sections[i]:GetNodes()
        for k = 1, #nodes do
            local data = nodes[k]:GetData()
            local index = data and data.friendIndex
            if index then into[index] = true end
        end
    end
end

-- The friend indexes a search or filter lets through; nil with none active,
-- and when Blizzard's list cannot be read (every friend shows then)
local function SearchSet(view, filtered)
    if not (filtered or SearchTextOn(view)) then return nil end
    wipe(allowedSet)
    if not pcall(ReadBlizzardList, view, allowedSet) then return nil end
    return allowedSet
end

-------------------------------------------------------------------------------
--  Model: friends read into records, sorted into sections, laid out as items
-------------------------------------------------------------------------------
local buckets, onlineIn = {}, {}

local function CompareRecords(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    if a.sortName ~= b.sortName then return a.sortName < b.sortName end
    return a.index < b.index
end

local function NewItem(kind, y, h)
    itemCount = itemCount + 1
    local it = items[itemCount]
    if not it then
        it = {}
        items[itemCount] = it
    end
    it.kind, it.y, it.h, it.gen, it.rec = kind, y, h, modelGen, nil
    return it
end

local function Rebuild()
    local g = Store()
    MigrateNoteTags(g)
    modelGen = modelGen + 1

    local view = View()
    local filtered = FiltersOn(view)
    if filterX then filterX:SetShown(filtered) end
    local allowed = SearchSet(view, filtered)
    -- The sections folded during a search open again as it ends
    if searchActive and not allowed then wipe(searchCollapsed) end
    searchActive = allowed ~= nil

    for _, list in pairs(buckets) do wipe(list) end
    wipe(onlineIn)
    wipe(byId)
    wipe(byIndex)

    local total = BNGetNumFriends() or 0
    local n = 0
    for i = 1, total do
        if not allowed or allowed[i] then
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info then
                n = n + 1
                local rec = records[n]
                if not rec then
                    rec = {}
                    records[n] = rec
                end
                local gi = info.gameAccountInfo
                local id = info.bnetAccountID
                rec.index, rec.id, rec.info = i, id, info
                rec.online = gi ~= nil and gi.isOnline == true
                rec.priority = Priority(gi)
                rec.sortName = SortName(info)
                rec.key = FriendKey(info)
                rec.bucket = BucketOf(g, info, rec.key)
                byId[id] = rec
                byIndex[i] = rec
                local list = buckets[rec.bucket]
                if not list then
                    list = {}
                    buckets[rec.bucket] = list
                end
                list[#list + 1] = rec
                if rec.online then onlineIn[rec.bucket] = (onlineIn[rec.bucket] or 0) + 1 end
            end
        end
    end
    for i = n + 1, recordCount do records[i].info = nil end
    recordCount = n

    local order, orderCount = ValidOrder(g)

    renderedCount = 0
    for i = 1, orderCount do
        local key = order[i]
        local list = buckets[key]
        if list and #list > 0 then
            renderedCount = renderedCount + 1
            rendered[renderedCount] = key
        end
    end
    for i = renderedCount + 1, #rendered do rendered[i] = nil end

    itemCount = 0
    local y = PAD_TOP
    for i = 1, renderedCount do
        local key = rendered[i]
        local list = buckets[key]
        table.sort(list, CompareRecords)
        local head = NewItem(KIND_HEADER, y, HEADER_H)
        head.key = key
        head.custom = key ~= FAV and key ~= UNGROUPED
        head.first, head.last = i == 1, i == renderedCount
        local name = key
        if key == FAV then
            name = FAVORITES or EllesmereUI.L("Favorites")
        elseif key == UNGROUPED then
            name = FRIENDS or EllesmereUI.L("Friends")
        end
        head.label = ("%s  (%d/%d)"):format(name, onlineIn[key] or 0, #list)
        y = y + HEADER_H + ROW_GAP
        -- A search opens every section it finds a friend in, until a click
        -- on the section's header folds it for that search
        local open
        if searchActive then
            open = not searchCollapsed[key]
        else
            open = not IsCollapsed(g, key)
        end
        if open then
            for k = 1, #list do
                NewItem(KIND_FRIEND, y, tileH).rec = list[k]
                y = y + tileH + ROW_GAP
            end
        end
        y = y + GROUP_GAP
    end
    for i = itemCount + 1, #items do items[i].rec = nil end
    content:SetHeight(math.max(1, y + PAD_BOTTOM))
end

-------------------------------------------------------------------------------
--  Group changes (each one redraws at once: it is the user's own click)
-------------------------------------------------------------------------------
local Refill   -- defined with the layout below

local function CreateGroup(text, assignKey)
    local name = CleanGroupName(text)
    if not name then return end
    local g = Store()
    if not FindGroup(g, name) then
        g.friendGroups[#g.friendGroups + 1] = { name = name, collapsed = false }
    end
    if assignKey then g.friendGroupsByTag[assignKey] = name end
    if active then Refill() end
end

local function RenameGroup(old, text)
    local name = CleanGroupName(text)
    local g = Store()
    local grp = FindGroup(g, old)
    if not (name and grp) or name == old or FindGroup(g, name) then return end
    grp.name = name
    if g.friendGroupColors[old] then
        g.friendGroupColors[name] = g.friendGroupColors[old]
        g.friendGroupColors[old] = nil
    end
    local order = g.friendGroupOrder
    for i = 1, #order do
        if order[i] == old then order[i] = name; break end
    end
    for key, grpName in pairs(g.friendGroupsByTag) do
        if grpName == old then g.friendGroupsByTag[key] = name end
    end
    if active then Refill() end
end

local function DeleteGroup(name)
    local g = Store()
    local _, at = FindGroup(g, name)
    if not at then return end
    table.remove(g.friendGroups, at)
    for key, grpName in pairs(g.friendGroupsByTag) do
        if grpName == name then g.friendGroupsByTag[key] = nil end
    end
    g.friendGroupColors[name] = nil
    if active then Refill() end
end

-- Battle.net's favorite switch for a friend, sent only when the friend is not
-- already that, or on its way to it
local function AskFavorite(id, want)
    local info = C_BattleNet.GetAccountInfoByID(id)
    if not info or IsFavorite(info) == want then return end
    favAsked[id] = want
    BNSetFriendFavoriteFlag(id, want)
end

-- Puts a friend in one section: a custom group (ours alone; it wins over
-- Favorites, so Battle.net is not asked), Favorites or the ungrouped friends
-- (no custom group, and Battle.net's favorite switch on or off)
local function PlaceFriend(id, key, target)
    local byTag = Store().friendGroupsByTag
    if target == FAV or target == UNGROUPED then
        if key then byTag[key] = nil end
        AskFavorite(id, target == FAV)
    elseif key then
        byTag[key] = target
    else
        return
    end
    if active then Refill() end
end

local function ToggleCollapsed(key)
    local g = Store()
    if key == FAV then
        g.friendFavCollapsed = not g.friendFavCollapsed
    elseif key == UNGROUPED then
        g.friendUngroupedCollapsed = not g.friendUngroupedCollapsed
    else
        local grp = FindGroup(g, key)
        if grp then grp.collapsed = not grp.collapsed end
    end
    if active then Refill() end
end

-- Swaps a section with the next one shown above (-1) or below (1) it
local function MoveGroup(key, dir)
    local at
    for i = 1, renderedCount do
        if rendered[i] == key then at = i; break end
    end
    local other = at and rendered[at + dir]
    if not other then return end
    local g = Store()
    ValidOrder(g)
    local order = g.friendGroupOrder
    local a, b
    for i = 1, #order do
        if order[i] == key then a = i elseif order[i] == other then b = i end
    end
    if a and b then
        order[a], order[b] = order[b], order[a]
        if active then Refill() end
    end
end

local function PromptNewGroup(assignKey)
    EllesmereUI:ShowInputPopup({
        title       = "New Friend Group",
        message     = "Enter a name for the new group:",
        placeholder = "Enter name...",
        confirmText = "Create",
        cancelText  = "Cancel",
        maxLetters  = GROUP_NAME_MAX,
        onConfirm   = function(text) CreateGroup(text, assignKey) end,
    })
end

local function PromptDeleteGroup(name)
    EllesmereUI:ShowConfirmPopup({
        title       = "Delete Friend Group",
        message     = EllesmereUI.Lf("Delete the group %1$s? Its friends go back to Favorites or the Friends section.", name),
        confirmText = "Delete",
        cancelText  = "Cancel",
        onConfirm   = function() DeleteGroup(name) end,
    })
end

-------------------------------------------------------------------------------
--  Tooltips (ours: never the game tooltip)
-------------------------------------------------------------------------------
local tipBuf = {}
local function FriendTooltip(rec)
    local info = rec.info
    local gi = info.gameAccountInfo
    local U = FriendsListUtil
    wipe(tipBuf)
    local n = 1
    tipBuf[1] = T.Name(info)
    if rec.online and gi then
        if rec.priority == 1 and gi.characterName then
            local realm = gi.realmDisplayName or gi.realmName
            n = n + 1
            tipBuf[n] = (realm and realm ~= "") and (gi.characterName .. "-" .. realm) or gi.characterName
            if gi.characterLevel and gi.className and FRIENDS_LEVEL_TEMPLATE then
                n = n + 1
                tipBuf[n] = FRIENDS_LEVEL_TEMPLATE:format(gi.characterLevel, gi.className)
            end
            if gi.areaName and gi.areaName ~= "" then
                n = n + 1
                tipBuf[n] = gi.areaName
            end
        elseif gi.richPresence and gi.richPresence ~= "" then
            n = n + 1
            tipBuf[n] = gi.richPresence
        end
    elseif U and U.GetLastOnlineText then
        n = n + 1
        tipBuf[n] = U.GetLastOnlineText(info)
    end
    local note = EllesmereUI.StripFriendNoteTag(info.note)
    if note then
        n = n + 1
        tipBuf[n] = EllesmereUI.COLOR_CODES.DIM .. note .. "|r"
    end
    local broadcast = U and U.BuildTooltipBroadcastText and U.BuildTooltipBroadcastText(info)
    if broadcast then
        n = n + 1
        tipBuf[n] = broadcast
    end
    return table.concat(tipBuf, "\n", 1, n)
end

local TIP_OPTS = { anchor = "right", justify = "LEFT" }

-- A row is lit while the pointer is on it or its friend is selected: one look
-- for both, the kit's hover.
local function Light(f)
    local on = hoverRow == f or f.selected == true
    f.d.hoverBar:SetShown(on)
    f.d.hoverFill:SetShown(on)
end

-- The pointer comes onto a row: the hover look and the friend's tooltip.
-- Over a link the game runs a frame's hyperlink hover scripts in place of its
-- plain ones (Blizzard's Quick Join rows forward them the same way), and the
-- link covers the row, so both land here.
local function RowEnter(hit)
    local f = hit:GetParent()
    if hoverRow == f then return end
    local old = hoverRow
    hoverRow = f
    if old then Light(old) end
    Light(f)
    if f.rec and f.rec.info then
        EllesmereUI.ShowWidgetTooltip(f, FriendTooltip(f.rec), TIP_OPTS)
    end
end

local function RowLeave(hit)
    local f = hit:GetParent()
    if hoverRow ~= f then return end
    hoverRow = nil
    Light(f)
    EllesmereUI.HideWidgetTooltip()
end

-------------------------------------------------------------------------------
--  Selection: a left click selects a friend, as on Blizzard's list, and a
--  second one lets go. A selected row keeps the hover look.
-------------------------------------------------------------------------------
local function SetSelected(f, on)
    f.selected = on
    Light(f)
end

local function ToggleSelected(f)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    selectedId = (selectedId ~= f.rec.id) and f.rec.id or nil
    for i = 1, #rowList do
        local row = rowList[i]
        if row.item then SetSelected(row, row.rec.id == selectedId) end
    end
end

-------------------------------------------------------------------------------
--  Clicks. The link covers the row, and Blizzard's handler for it opens the
--  friend menu on the right button and whispers on any other. The game has
--  settled which frame a click belongs to by the time it tells a press, so
--  nothing done at the press can take a click back from the link. A left
--  click is to select, so every row carries a click layer of ours over its
--  link, there all the time: it takes every button but the right one, which
--  it passes down to the link, so that click stays Blizzard's from press to
--  menu. The pointer's movement is passed down too: the link keeps the hover.
--  Both routings are refused in combat on every frame, so a row made in
--  combat gets its layer as combat ends and keeps the link's own left click
--  (a whisper) until then.
-------------------------------------------------------------------------------
local unrouted = {}     -- rows made in combat: their click layer still to route

local function SetLink(f)
    local info = f.rec.info
    -- SetFormattedText, so a name the game keeps secret still goes in
    pcall(f.link.SetFormattedText, f.link, LINK_FORMAT, info.accountName, f.rec.id, info.accountName, LINK_FILLER)
end

-- A release on the click layer: the left button selects
local function CatchRelease(catch, button)
    local f = catch:GetParent()
    if button == "LeftButton" and f.item and f.rec and catch:IsMouseOver() then ToggleSelected(f) end
end

-- The layer's routing (out of combat only), then the layer goes over the link
local function RouteCatch(f)
    local catch = f.catch
    catch:SetPassThroughButtons("RightButton")
    catch:SetPropagateMouseMotion(true)
    catch:Show()
end

local function RoutePending()
    for i = #unrouted, 1, -1 do
        RouteCatch(unrouted[i])
        unrouted[i] = nil
    end
end

-------------------------------------------------------------------------------
--  Invite button (Blizzard's own rules through its friends list helpers)
-------------------------------------------------------------------------------
-- The friend's index, only while it still names this friend (the game
-- renumbers friends as they come and go; a rebuild follows within a frame)
local function LiveIndex(rec)
    local info = rec and C_BattleNet.GetFriendAccountInfo(rec.index)
    if info and info.bnetAccountID == rec.id then return rec.index end
end

-- What the button would do, and in red why it cannot (Blizzard's invite
-- restriction)
local function InviteEnter(btn)
    local index = LiveIndex(btn:GetParent().rec)
    local U = FriendsListUtil
    if not (index and U and U.GetBattleNetFriendInviteInfo) then return end
    local text = U.GetBattleNetFriendInviteTypeLabel(U.GetBattleNetFriendInviteInfo(index).inviteType) or ""
    local why
    if not btn:IsEnabled() and btn.restriction and U.GetBattleNetFriendPartyInviteRestrictionText then
        why = U.GetBattleNetFriendPartyInviteRestrictionText(btn.restriction)
    end
    if why and why ~= "" then
        why = EllesmereUI.COLOR_CODES.BAD .. why .. "|r"
        text = text ~= "" and (text .. "\n" .. why) or why
    end
    if text ~= "" then EllesmereUI.ShowWidgetTooltip(btn, text) end
end

local function InviteLeave()
    EllesmereUI.HideWidgetTooltip()
end

-- The icon steps down and right while the button is held, as Blizzard's does
local function InvitePress(btn)
    if btn:IsEnabled() then btn.icon:SetPoint("CENTER", btn, "CENTER", 1, -1) end
end

local function InviteRelease(btn)
    btn.icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
end

-- An atlas's own size (the icon keeps it, scaled with the button)
local atlasSize = {}
local function AtlasSize(atlas)
    local size = atlasSize[atlas]
    if not size then
        local info = C_Texture.GetAtlasInfo(atlas)
        size = { info and info.width or 20, info and info.height or 20 }
        atlasSize[atlas] = size
    end
    return size[1], size[2]
end

-- A friend on several characters: which one to invite
local function ShowAccountMenu(btn, index)
    local U = FriendsListUtil
    local none = BattleNetFriendPartyInviteRestrictionType.None
    local menu = {}
    for i = 1, C_BattleNet.GetFriendNumGameAccounts(index) do
        local gi = C_BattleNet.GetFriendGameAccountInfo(index, i)
        if gi then
            local canInvite = U.IsPlayingWoW(gi) and U.GetGameAccountPartyInviteRestriction(gi) == none
            local label = gi.characterName or gi.richPresence or ""
            if gi.characterLevel and gi.className and FRIENDS_LEVEL_TEMPLATE and U.IsPlayingWoW(gi) then
                label = label .. "  " .. FRIENDS_LEVEL_TEMPLATE:format(gi.characterLevel, gi.className)
            end
            local accountID = gi.gameAccountID
            menu[#menu + 1] = {
                text = label, noLoc = true,
                isDisabled = function() return not canInvite end,
                onClick = function()
                    local fresh = C_BattleNet.GetGameAccountInfoByID(accountID)
                    if fresh and fresh.playerGuid then
                        U.InviteOrRequestToJoin(fresh.playerGuid, accountID)
                    end
                end,
            }
        end
    end
    if #menu > 0 then EllesmereUI.ShowContextMenu(btn, menu) end
end

local function InviteClick(btn)
    if not btn:IsEnabled() then return end
    local index = LiveIndex(btn:GetParent().rec)
    local U = FriendsListUtil
    if not (index and U and U.InviteOrRequestToJoin) then return end
    local direct = U.GetBattleNetFriendGameAccountInfoIfExactlyOneDirectInviteTargetExists(index)
    if direct then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        U.InviteOrRequestToJoin(direct.playerGuid, direct.gameAccountID)
    elseif U.HasMultipleGameAccounts(index) then
        ShowAccountMenu(btn, index)
    end
end

-- Only a friend playing this game has the button (f.playing: the row shows
-- their character): an offline friend, or one in another game, has nobody to
-- invite. Off, with its icon greyed, while Blizzard's rules do not let you
-- invite them. Returns whether the button shows.
local function UpdateInvite(f, rec)
    local btn = f.PartyButton
    local U = FriendsListUtil
    if not (f.playing and U and U.GetBattleNetFriendPartyInviteRestriction and BattleNetFriendPartyInviteRestrictionType) then
        btn:Hide()
        return false
    end
    local restriction = U.GetBattleNetFriendPartyInviteRestriction(rec.index)
    local enabled = restriction == BattleNetFriendPartyInviteRestrictionType.None
    local guid = rec.info.gameAccountInfo.playerGuid
    local inGroup = guid ~= nil and C_SocialQueue ~= nil and C_SocialQueue.IsSystemSupported ~= nil
        and C_SocialQueue.IsSystemSupported() and C_SocialQueue.GetGroupForPlayer(guid) ~= nil
    btn.restriction = restriction
    if btn.on ~= enabled then
        btn.on = enabled
        btn:SetEnabled(enabled)
    end
    local atlas
    if inGroup then
        atlas = enabled and "friends-icon-friendsInGroup" or "friends-icon-friendsInGroup-dis"
    else
        atlas = enabled and "friends-icon-friendsAvailable" or "friends-icon-friendsAvailable-dis"
    end
    if btn.atlas ~= atlas or btn.iconFor ~= f.btnSize then
        btn.atlas, btn.iconFor = atlas, f.btnSize
        local w, h = AtlasSize(atlas)
        local k = f.btnSize / BTN_NATIVE
        btn.icon:SetAtlas(atlas)
        btn.icon:SetSize(w * k, h * k)
    end
    btn:Show()
    return true
end

-------------------------------------------------------------------------------
--  Friend rows
-------------------------------------------------------------------------------
local function MakeRow(slot)
    local f = CreateFrame("Frame", nil, content)
    -- Tile art and the text lines: the kit's, as on Blizzard's cards. Its
    -- state for this frame is the kit's frame data. The status after the
    -- name is Blizzard's own icon here, not the kit's orb.
    local d = T.Skin(f)
    f.d = d
    d.orb:Hide()
    f.status = f:CreateTexture(nil, "OVERLAY", nil, 3)
    -- Blizzard's own card, which an online friend's row wears (PaintRow), at
    -- the host's alpha for it: whole, it takes the place of the tile's shade
    -- and online tint; fainter, it lies under them
    if host.onlineCards then
        f.card = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.card:SetAllPoints()
        f.card:SetAlpha(host.onlineCards)
        f.card:Hide()
        f.cardWhole = host.onlineCards >= 1
    end

    -- The invite button, in the art of the one on Blizzard's card. Named as
    -- there: the kit hangs its region icon beside it.
    local btn = CreateFrame("Button", nil, f)
    btn:SetFrameLevel(f:GetFrameLevel() + 6)
    btn:SetPoint("RIGHT", f, "RIGHT", -EDGE_PAD, 0)
    btn:SetNormalAtlas(BTN_NORMAL)
    btn:SetPushedAtlas(BTN_PUSHED)
    btn:SetHighlightAtlas(BTN_NORMAL, "ADD")
    btn:SetMotionScriptsWhileDisabled(true)
    btn.icon = btn:CreateTexture(nil, "OVERLAY")
    btn.icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn:SetScript("OnClick", InviteClick)
    btn:SetScript("OnEnter", InviteEnter)
    btn:SetScript("OnLeave", InviteLeave)
    btn:SetScript("OnMouseDown", InvitePress)
    btn:SetScript("OnMouseUp", InviteRelease)
    f.PartyButton = btn

    -- The link layer. Its click script stays the template's: Blizzard's.
    -- The hover scripts are ours (the template's ask the game tooltip for the
    -- link): the frame's and the link's both, since the link covers the row.
    local hit = CreateFrame("Frame", nil, f, TEMPLATE)
    hit:SetAllPoints(f)
    hit:SetFrameLevel(f:GetFrameLevel() + 3)
    hit:EnableMouse(true)
    hit:SetScript("OnHyperlinkEnter", RowEnter)
    hit:SetScript("OnHyperlinkLeave", RowLeave)
    hit:SetScript("OnEnter", RowEnter)
    hit:SetScript("OnLeave", RowLeave)
    f.hit = hit

    -- The click layer over the link (see Clicks): under the invite button,
    -- hidden until its routing is set
    local catch = CreateFrame("Frame", nil, f)
    catch:SetAllPoints(f)
    catch:SetFrameLevel(f:GetFrameLevel() + 4)
    catch:EnableMouse(true)
    catch:SetScript("OnMouseUp", CatchRelease)
    catch:SetScript("OnEnter", RowEnter)
    catch:SetScript("OnLeave", RowLeave)
    catch:Hide()
    f.catch = catch
    if InCombatLockdown() then
        unrouted[#unrouted + 1] = f
        EllesmereUI.CombatQueue.Defer("FriendsListRoute", RoutePending)
    else
        RouteCatch(f)
    end

    local link = hit:CreateFontString(nil, "ARTWORK")
    link:SetJustifyH("LEFT")
    link:SetJustifyV("TOP")
    link:SetWordWrap(false)
    link:SetAlpha(0)
    f.link = link

    f:Hide()
    rowPool[slot] = f
    rowList[#rowList + 1] = f
    return f
end

-- Size and fonts for the tile height in force. The text is two lines, or a
-- single line on a short tile; a tall tile takes the larger name.
local function StyleRow(f)
    local d = f.d
    local font = T.FontPath()
    f.style = styleGen
    f.layKey, f.layStop, f.nameW, f.charW, f.iconMode = nil, nil, nil, nil, nil
    f:SetSize(rowW, tileH)

    -- One line of text taller than the row that starts above and left of it
    -- (the sizes checked in game on rows of 24, 40 and 64): its line box is
    -- the link's live zone. The text is cut to whole letters, so the block
    -- runs two letters past the row's right edge.
    local size = tileH + LINK_TALLER
    f.link:SetFont(STANDARD_TEXT_FONT, size, "")
    f.link:ClearAllPoints()
    f.link:SetPoint("TOPLEFT", f.hit, "TOPLEFT", -4, LINK_ABOVE)
    f.link:SetPoint("RIGHT", f.hit, "RIGHT", 2 * size + 12, 0)

    local share = math.max(BTN_MIN, math.min(BTN_NATIVE, tileH * BTN_SHARE))
    local btnSize = math.floor((share + math.min(BTN_FLAT, tileH - 6)) / 2 + 0.5) + BTN_EXTRA
    f.btnSize = btnSize
    f.PartyButton:SetSize(btnSize, btnSize)

    local nameSize, lineSize = 15, 12
    if tier == 2 then nameSize = 14 elseif tier == 1 then nameSize, lineSize = 13, 11 end
    -- The kit's lines are font families (they show friends' names and notes)
    EllesmereUI.SetFontFamily(d.name, font, nameSize, "", true)
    EllesmereUI.SetFontFamily(d.charLine, font, lineSize, "", true)
    EllesmereUI.SetFontFamily(d.info, font, lineSize, "", true)
    d.name:SetTextColor(1, 1, 1, 1)
    d.charLine:SetTextColor(1, 1, 1, 1)
    d.info:SetTextColor(1, 1, 1, 1)
    d.info:SetJustifyH(tier == 1 and "RIGHT" or "LEFT")
    f.status:SetSize(nameSize, nameSize)
    f.nameSize, f.lineSize = nameSize, lineSize
end

-- Line 1 is the Battle.net name, the character in brackets after it and the
-- status icon; the place (with the note) is the line below, or the right end
-- of a one-line tile. The texts stop at the leftmost of the invite button and
-- the region icon (stop; false with neither, and they run to the row's
-- edge): reserve is the width those keep on the right.
local function LayoutText(f, hasChar, stop, reserve)
    local d = f.d
    local name, char = d.name, d.charLine
    local x = tileH + TEXT_GAP
    local avail = rowW - x - reserve - 6
    local statusW = f.nameSize + STATUS_DX

    -- The name keeps its own width unless it would crowd the rest out
    local maxName
    if tier == 1 then
        maxName = avail * (hasChar and 0.4 or 0.55)
    else
        maxName = hasChar and avail * 0.6 or avail - statusW
    end
    if maxName < 20 then maxName = 20 end
    local nameW = 0
    local nw = name:GetUnboundedStringWidth()
    local known = not IsSecret(nw)
    if known and nw > maxName then
        nameW, nw = maxName, maxName
    end
    if f.nameW ~= nameW then
        f.nameW = nameW
        name:SetWidth(nameW)
    end

    -- The character takes what the line has left, and goes when that is too
    -- little
    local showChar = hasChar
    if hasChar then
        local charW = 0
        if known then
            local room = avail - nw - CHAR_GAP - statusW
            if tier == 1 then room = math.min(room, avail * 0.3) end
            if room < 30 then
                showChar = false
            else
                local cw = char:GetUnboundedStringWidth()
                if not IsSecret(cw) and cw > room then charW = room end
            end
        end
        if showChar and f.charW ~= charW then
            f.charW = charW
            char:SetWidth(charW)
        end
    end
    char:SetShown(showChar)

    local key = showChar and 1 or 0
    if f.layKey == key and f.layStop == stop then return end
    f.layKey, f.layStop = key, stop
    local info, status = d.info, f.status
    name:ClearAllPoints()
    char:ClearAllPoints()
    info:ClearAllPoints()
    status:ClearAllPoints()
    char:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", CHAR_GAP, CHAR_LIFT)
    -- The status icon keeps one height on every row, STATUS_DY above the
    -- name's middle. Beside the character it is set by its bottom against the
    -- character's, which stands CHAR_LIFT above the name's; the icon is as
    -- tall as the name, so that is the same height.
    if showChar then
        status:SetPoint("BOTTOMLEFT", char, "BOTTOMRIGHT", STATUS_DX, STATUS_DY - CHAR_LIFT)
    else
        status:SetPoint("LEFT", name, "RIGHT", STATUS_DX, STATUS_DY)
    end
    if tier == 1 then
        name:SetPoint("LEFT", f, "LEFT", x, 0)
        info:SetPoint("LEFT", status, "RIGHT", 8, -STATUS_DY)
    else
        local gap = tier == 3 and 5 or 3
        local block = f.nameSize + gap + f.lineSize
        name:SetPoint("TOPLEFT", f, "TOPLEFT", x, -math.max(0, (tileH - block) / 2))
        info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -gap)
    end
    if stop then
        info:SetPoint("RIGHT", stop, "LEFT", -6, 0)
    else
        info:SetPoint("RIGHT", f, "RIGHT", -EDGE_PAD - 6, 0)
    end
end

-- The character line in brackets, the brackets in the colour of its level
local bracketCache = setmetatable({}, { __mode = "k" })
local function Bracketed(info, text)
    local color = T.LevelColor(info)
    if not (color and color.WrapTextInColorCode) then return "(" .. text .. ")" end
    local pair = bracketCache[color]
    if not pair then
        pair = { color:WrapTextInColorCode("("), color:WrapTextInColorCode(")") }
        bracketCache[color] = pair
    end
    return pair[1] .. text .. pair[2]
end

-- Blizzard's own reading of a friend's status. Away and busy can arrive as
-- values the game keeps secret: one that cannot be read counts as not set.
local function Presence(info)
    local gi = info.gameAccountInfo
    if not (gi and gi.isOnline) then return "offline" end
    local afk, gameAfk = info.isAFK, gi.isGameAFK
    if (not IsSecret(afk) and afk) or (not IsSecret(gameAfk) and gameAfk) then return "away" end
    local dnd, gameBusy = info.isDND, gi.isGameBusy
    if (not IsSecret(dnd) and dnd) or (not IsSecret(gameBusy) and gameBusy) then return "busy" end
    return "online"
end

local function UpdateIcon(f, info, p)
    local icon = f.d.classIcon
    if p and p.showClassIcons == false then
        icon:Hide()
        return
    end
    local state = T.State(info)
    local h = tileH - 4
    if state == "retail" then
        local classFile = T.ClassFile(info)
        if not classFile then
            icon:Hide()
            return
        end
        if f.iconMode ~= 1 then
            f.iconMode = 1
            local size = h - 2 * math.floor(h * 0.025 + 0.5)
            icon:ClearAllPoints()
            icon:SetSize(size, size)
            icon:SetPoint("LEFT", f, "LEFT", 4 + (h - size) / 2, 0)
        end
        T.ClassIconTex(icon, (p and p.iconStyle) or "modern", classFile)
        icon:SetAlpha(1)
    else
        if f.iconMode ~= 2 then
            f.iconMode = 2
            local size = math.floor(h * 0.75)
            icon:ClearAllPoints()
            icon:SetSize(size, size)
            icon:SetPoint("LEFT", f, "LEFT", 4 + math.floor((h - size) / 2), 0)
        end
        icon:SetTexCoord(0, 1, 0, 1)
        if state == "other_game" and C_Texture.SetTitleIconTexture then
            local gi = info.gameAccountInfo
            C_Texture.SetTitleIconTexture(icon, gi.clientProgram, Enum.TitleIconVersion.Medium, gi.subIcon)
            icon:SetAlpha(1)
        else
            icon:SetTexture(T.OFFLINE_ICON)
            icon:SetAlpha(0.5)
        end
    end
    icon:SetDesaturated(false)
    icon:Show()
end

local function PaintRow(f, it)
    local rec = it.rec
    local info = rec.info
    local d = f.d
    if f.style ~= styleGen then StyleRow(f) end
    f.item, f.gen, f.rec = it, it.gen, rec

    SetLink(f)

    -- Every string arrives wrapped in Blizzard's colour codes
    local charText = T.CharLine(info)
    local hasChar = charText ~= ""
    f.playing = hasChar

    local p = Settings()
    T.Region(f, d, info)
    -- The kit sizes its region icon once, as it makes it, and hangs it left of
    -- the invite button: ours follows the tile, and takes the button's place
    -- on a row without one
    local region = d.regionBtn
    local regionSize = math.min(28, math.floor(tileH * 0.8))
    if region and f.regionFor ~= tileH then
        f.regionFor = tileH
        region:SetSize(regionSize, regionSize)
    end
    local invite = UpdateInvite(f, rec)
    if region and f.regionBy ~= invite then
        f.regionBy = invite
        region:ClearAllPoints()
        if invite then
            region:SetPoint("RIGHT", f.PartyButton, "LEFT", -2, 0)
        else
            region:SetPoint("RIGHT", f, "RIGHT", -EDGE_PAD, 0)
        end
    end
    local regionShown = region ~= nil and region:IsShown()

    d.name:SetText(T.Name(info))
    if hasChar then d.charLine:SetText(Bracketed(info, charText)) end
    d.info:SetText(T.Info(info))
    LayoutText(f, hasChar, regionShown and region or (invite and f.PartyButton),
        EDGE_PAD + (invite and f.btnSize or 0) + (regionShown and regionSize or 0)
            + ((invite and regionShown) and 2 or 0))

    local presence = Presence(info)
    if f.presence ~= presence then
        f.presence = presence
        f.status:SetAtlas(STATUS_ATLAS[presence])
    end

    UpdateIcon(f, info, p)
    if f.card then
        -- An online friend's row wears Blizzard's own card, as on its list: a
        -- game-level friend's or a Battle.net friend's, picked as Blizzard picks
        -- it (a level the game keeps secret counts as Battle.net). Whole, it
        -- hides the tile's shade (MakeRow). The file is at Lua's local cap,
        -- hence no constants of its own.
        local atlas
        if rec.online then
            local level, levels = info.friendLevel, Enum.BattleNetFriendLevel
            atlas = (levels and not IsSecret(level) and level == levels.Title) and "friends-card-default"
                or "friends-card-battleNet"
        end
        if f.cardAtlas ~= atlas then
            f.cardAtlas = atlas
            if atlas then f.card:SetAtlas(atlas, false) end
            f.card:SetShown(atlas ~= nil)
            if f.cardWhole then d.tileBg:SetShown(atlas == nil) end
        end
    end
    if not f.cardWhole then d.onlineBg:SetShown(rec.online) end
    T.Faction(f, d, info)
    SetSelected(f, rec.id == selectedId)

    -- A reused row under the pointer shows the new friend's tooltip
    if hoverRow == f then
        EllesmereUI.ShowWidgetTooltip(f, FriendTooltip(rec), TIP_OPTS)
    end
end

-------------------------------------------------------------------------------
--  Section headers
-------------------------------------------------------------------------------
local ICON_ALPHA, ICON_HOVER, ICON_OFF = 0.35, 0.7, 0.06

local function AccentRGB()
    local r, g, b = EllesmereUI.GetAccentColor()
    if r then return r, g, b end
    local eg = EllesmereUI.ELLESMERE_GREEN
    return eg.r, eg.g, eg.b
end

-- A header icon under the pointer: its hover look and what it does, unless it
-- is switched off (the first section's up arrow, the last one's down arrow)
local function HeaderIconEnter(btn)
    if btn.off then
        EllesmereUI.HideWidgetTooltip()
        return
    end
    btn:SetAlpha(ICON_HOVER)
    local tip = btn.tip
    if type(tip) == "function" then tip = tip(btn) end
    EllesmereUI.ShowWidgetTooltip(btn, tip)
end

local function HeaderIconLeave(btn)
    btn:SetAlpha(btn.off and ICON_OFF or ICON_ALPHA)
    EllesmereUI.HideWidgetTooltip()
end

-- tip: the tooltip, or a function of the button that returns it
local function HeaderIcon(parent, texture, onClick, tip)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(14, 14)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints()
    icon:SetTexture(ICONS .. texture)
    btn:SetAlpha(ICON_ALPHA)
    btn.tip = tip
    btn:SetScript("OnEnter", HeaderIconEnter)
    btn:SetScript("OnLeave", HeaderIconLeave)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- Folds or opens the section; during a search, for that search alone (the
-- saved state is the one the list keeps without a search)
local function HeaderClick(h)
    if not searchActive then
        ToggleCollapsed(h.key)
        return
    end
    searchCollapsed[h.key] = not searchCollapsed[h.key] or nil
    if active then Refill() end
end

local function HeaderEnter(h)
    h.hover:Show()
end

local function HeaderLeave(h)
    h.hover:Hide()
end

local function HeaderUp(btn)
    if not btn.off then MoveGroup(btn:GetParent().key, -1) end
end

local function HeaderDown(btn)
    if not btn.off then MoveGroup(btn:GetParent().key, 1) end
end

local function HeaderDelete(btn)
    PromptDeleteGroup(btn:GetParent().key)
end

-- A section name's colour: the one picked for it, else the accent
local function SectionRGB(key)
    local color = Store().friendGroupColors[key]
    if color then return color.r, color.g, color.b end
    return AccentRGB()
end

local RepaintHeaders   -- defined with the header painter below

-- The colour picker for a section's name (it lives in the options addon,
-- which the game will not load in combat). Each pick repaints the section
-- names in view, and a cancel puts the old colour back.
local function PickSectionColor(key, anchor, onChange)
    if not key or InCombatLockdown() then return end
    EllesmereUI:EnsureLoaded()
    if not EllesmereUI.ShowColorPicker then return end
    local colors = Store().friendGroupColors
    local was, picked = colors[key], nil
    local function Set(color)
        colors[key] = color
        RepaintHeaders()
        if onChange then onChange() end
    end
    local r, g, b = SectionRGB(key)
    EllesmereUI:ShowColorPicker({
        r = r, g = g, b = b,
        hasOpacity = false,
        swatchFunc = function()
            local popup = EllesmereUI._colorPickerPopup
            if not popup then return end
            picked = picked or {}
            picked.r, picked.g, picked.b = popup:GetColorRGB()
            Set(picked)
        end,
        cancelFunc = function() Set(was) end,
    }, anchor)
end

-- A custom group's name and colour in one popup: the swatch beside the name
-- opens the colour picker, whose own OK and Cancel keep or drop the colour
-- (the popup's buttons are the name's alone).
local function PromptEditGroup(name)
    EllesmereUI:ShowInputPopup({
        title       = "Rename Friend Group",
        message     = "Enter a new name for this group:",
        initialText = name,
        placeholder = "Enter name...",
        confirmText = "Rename",
        cancelText  = "Cancel",
        maxLetters  = GROUP_NAME_MAX,
        swatch      = {
            get     = function() return SectionRGB(name) end,
            onClick = function(swatch, repaint) PickSectionColor(name, swatch, repaint) end,
            tooltip = "Color",
        },
        onConfirm   = function(text) RenameGroup(name, text) end,
    })
end

-- The pencil: a custom group's popup, or the colour alone for a section that
-- cannot be renamed
local function HeaderEdit(btn)
    local h = btn:GetParent()
    if h.custom then
        PromptEditGroup(h.key)
    else
        PickSectionColor(h.key, btn)
    end
end

local function EditTip(btn)
    return btn:GetParent().custom and "Edit Group" or "Change Color"
end

local function MakeHeader(slot)
    local h = CreateFrame("Button", nil, content)
    h:SetHeight(HEADER_H)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.04)
    h.hover = h:CreateTexture(nil, "ARTWORK", nil, -5)
    h.hover:SetAllPoints()
    h.hover:SetColorTexture(1, 1, 1, 0.06)
    h.hover:Hide()

    -- A group's name, as the player typed it: a font family, set by PaintHeader
    h.label = h:CreateFontString(nil, "OVERLAY")
    h.label:SetPoint("CENTER", h, "CENTER", 0, 0)

    h.up = HeaderIcon(h, "eui-arrow-up3.png", HeaderUp, "Move Up")
    h.down = HeaderIcon(h, "eui-arrow-down3.png", HeaderDown, "Move Down")
    h.edit = HeaderIcon(h, "eui-edit.png", HeaderEdit, EditTip)
    h.x = HeaderIcon(h, "eui-close.png", HeaderDelete, "Delete Group")
    h.up:SetPoint("LEFT", h, "LEFT", 8, 0)
    h.down:SetPoint("RIGHT", h, "RIGHT", -8, 0)
    h.edit:SetPoint("LEFT", h.up, "RIGHT", 4, 0)
    h.x:SetPoint("RIGHT", h.down, "LEFT", -4, 0)

    h.lineL = h:CreateTexture(nil, "OVERLAY")
    h.lineL:SetColorTexture(1, 1, 1, 0.1)
    h.lineL:SetHeight(1)
    h.lineL:SetPoint("LEFT", h.edit, "RIGHT", 6, 0)
    h.lineL:SetPoint("RIGHT", h.label, "LEFT", -6, 0)
    h.lineR = h:CreateTexture(nil, "OVERLAY")
    h.lineR:SetColorTexture(1, 1, 1, 0.1)
    h.lineR:SetHeight(1)

    -- A click anywhere on the bar but its icons, the name included, collapses
    h:SetScript("OnClick", HeaderClick)
    h:SetScript("OnEnter", HeaderEnter)
    h:SetScript("OnLeave", HeaderLeave)
    h:Hide()
    headerPool[slot] = h
    headerList[#headerList + 1] = h
    return h
end

local function SetIconOff(btn, off)
    btn.off = off
    btn:SetAlpha(off and ICON_OFF or ICON_ALPHA)
end

local function PaintHeader(h, it)
    h.item, h.gen, h.key = it, it.gen, it.key
    if h.style ~= styleGen then
        h.style = styleGen
        h.custom = nil
        h:SetWidth(rowW)
        EllesmereUI.SetFontFamily(h.label, T.FontPath(), 12, "", true)
    end
    h.label:SetText(it.label)
    local r, g, b = SectionRGB(it.key)
    h.label:SetTextColor(r, g, b, 1)
    SetIconOff(h.up, it.first)
    SetIconOff(h.down, it.last)
    -- Only a custom group can be deleted; every section has the pencil
    if h.custom ~= it.custom then
        h.custom = it.custom
        h.x:SetShown(it.custom)
        h.lineR:ClearAllPoints()
        h.lineR:SetPoint("LEFT", h.label, "RIGHT", 6, 0)
        h.lineR:SetPoint("RIGHT", it.custom and h.x or h.down, "LEFT", -6, 0)
    end
    -- Painted again under the pointer (a click on an arrow moved the
    -- sections): the hovered icon's look and tooltip follow what it does now
    if h.up:IsMouseMotionFocus() then HeaderIconEnter(h.up) end
    if h.down:IsMouseMotionFocus() then HeaderIconEnter(h.down) end
    if h.edit:IsMouseMotionFocus() then HeaderIconEnter(h.edit) end
end

RepaintHeaders = function()
    for i = 1, #headerList do
        local h = headerList[i]
        if h.item and h:IsShown() then PaintHeader(h, h.item) end
    end
end

-------------------------------------------------------------------------------
--  Layout: only the items in view hold a frame. An item keeps one pool slot
--  (its index around the ring), so scrolling repaints only what enters view.
-------------------------------------------------------------------------------
local function FirstVisible(top)
    local lo, hi = 1, itemCount
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local it = items[mid]
        if it.y + it.h < top then lo = mid + 1 else hi = mid end
    end
    return lo
end

local function HideUnseen(list)
    for i = 1, #list do
        local f = list[i]
        if f.vis ~= visGen and f.item then
            f.item, f.rec = nil, nil
            if hoverRow == f then
                hoverRow = nil
                EllesmereUI.HideWidgetTooltip()
            end
            f:Hide()
        end
    end
end

local function LayoutVisible()
    if not active then return end
    visGen = visGen + 1
    if itemCount > 0 and viewH > 0 then
        local top = sf:GetVerticalScroll()
        local bottom = top + viewH
        for i = FirstVisible(top), itemCount do
            local it = items[i]
            if it.y >= bottom then break end
            local slot = (i - 1) % ring + 1
            local f
            if it.kind == KIND_FRIEND then
                f = rowPool[slot] or MakeRow(slot)
                if f.item ~= it or f.gen ~= it.gen or f.style ~= styleGen then PaintRow(f, it) end
            else
                f = headerPool[slot] or MakeHeader(slot)
                if f.item ~= it or f.gen ~= it.gen or f.style ~= styleGen then PaintHeader(f, it) end
            end
            if f.posY ~= it.y then
                f.posY = it.y
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_LEFT, -it.y)
            end
            f.vis = visGen
            f:Show()
        end
    end
    HideUnseen(rowList)
    HideUnseen(headerList)
end

-------------------------------------------------------------------------------
--  The scroll bar: a frame of ours made from the template of Blizzard's own
--  bar and laid over that bar, so the two lists look alike. It follows the
--  list (how much is in view, where the view stands, one tile per arrow
--  press), and a drag of its thumb or a press on an arrow or its track
--  scrolls the list. So does the wheel, over the list as over the bar: it is
--  the bar's own wheel step, two tiles a tick, at once, as on Blizzard's list.
-------------------------------------------------------------------------------
local barBusy = false   -- the bar and the list are telling each other one spot

local function ScrollRange()
    return math.max(0, content:GetHeight() - sf:GetHeight())
end

-- Where the view stands, after a scroll step of the list
local function SyncBarSpot()
    local range = ScrollRange()
    barBusy = true
    bar:SetScrollPercentage(range > 0 and sf:GetVerticalScroll() / range or 0, true)
    barBusy = false
end

-- The whole bar, after the list or the view changed size
local function SyncBar()
    local range = ScrollRange()
    barBusy = true
    bar:SetVisibleExtentPercentage(range > 0 and sf:GetHeight() / content:GetHeight() or 1)
    bar:SetPanExtentPercentage(range > 0 and (tileH + ROW_GAP) / range or 0)
    bar:SetScrollPercentage(range > 0 and sf:GetVerticalScroll() / range or 0, true)
    barBusy = false
end

-- The list moved: the rows in view, and the bar unless the bar moved it
local function OnListScroll()
    LayoutVisible()
    if not barBusy then SyncBarSpot() end
end

-- The list to a spot inside its range, at once
local function ScrollTo(v)
    sf:SetVerticalScroll(v)
    OnListScroll()
end

-- The bar moved by hand
local function OnBarScroll(_, percentage)
    if barBusy then return end
    barBusy = true
    ScrollTo(percentage * ScrollRange())
    barBusy = false
end

-- Everything from the friend data up: model, scroll range, the rows in view.
-- The view keeps its spot; only a spot past the new end is pulled back.
Refill = function()
    Rebuild()
    local range = ScrollRange()
    if sf:GetVerticalScroll() > range then
        ScrollTo(range)
    else
        LayoutVisible()
    end
    SyncBar()
end

-- The tile height in force and what follows from it
local function ApplyMetrics()
    local p = Settings()
    tileH = ClampTile(p and p.tileHeight)
    tier = tileH >= 52 and 3 or (tileH >= 34 and 2 or 1)
    viewH = sf:GetHeight() or 0
    rowW = math.max(1, (sf:GetWidth() or 0) - PAD_LEFT - PAD_RIGHT)
    content:SetWidth(math.max(1, sf:GetWidth() or 0))
    -- Slots for every item one view can span, and a few to spare
    ring = math.ceil(viewH / (math.min(tileH, HEADER_H) + ROW_GAP)) + 4
    -- Every row and header in view restyles on the next layout; one the new
    -- layout no longer reaches still holds its item, so that pass hides it
    styleGen = styleGen + 1
    -- Every row those slots can need is made now, so a scroll never has to
    -- make one
    if viewH > 0 then
        for slot = 1, ring do
            if not rowPool[slot] then MakeRow(slot) end
        end
    end
end

-- One friend changed and nothing that places it did: its row alone repaints
local function TryRowDelta(index)
    if searchActive then return false end
    local rec = byIndex[index]
    if not rec then return false end
    local info = C_BattleNet.GetFriendAccountInfo(index)
    if not info or info.bnetAccountID ~= rec.id then return false end
    local gi = info.gameAccountInfo
    if (gi ~= nil and gi.isOnline == true) ~= rec.online or Priority(gi) ~= rec.priority
        or BucketOf(Store(), info, rec.key) ~= rec.bucket then
        return false
    end
    rec.info = info
    for i = 1, #rowList do
        local f = rowList[i]
        if f.rec == rec and f.item then
            PaintRow(f, f.item)
            break
        end
    end
    return true
end

local function RepaintInvites()
    for i = 1, #rowList do
        local f = rowList[i]
        if f.item and f.rec and f.rec.info then UpdateInvite(f, f.rec) end
    end
end

local function OnEvent(_, event, arg1)
    if event == "GROUP_ROSTER_UPDATE" then
        dirtyInvites = true
    else
        if event == "BN_FRIEND_LIST_SIZE_CHANGED" then
            wipe(keyById)
            wipe(sortById)
        end
        -- A rebuild is on its way already, or one friend changed in place
        if dirtyFull then return end
        if event == "BN_FRIEND_INFO_CHANGED" and arg1 and TryRowDelta(arg1) then return end
        dirtyFull = true
    end
    flusher:Show()
end

local function OnFlush(self)
    self:Hide()
    if not active then return end
    if dirtyFull then
        dirtyFull, dirtyInvites = false, false
        Refill()
    elseif dirtyInvites then
        dirtyInvites = false
        RepaintInvites()
    end
end

-- Blizzard's search box or filter menu changed what its own list shows
local function OnBlizzardSearch()
    if active then
        dirtyFull = true
        flusher:Show()
    end
end

-------------------------------------------------------------------------------
--  Our entries on Blizzard's friend menu, only for a menu opened from a row of
--  this list (the pointer is on it while the menu is built)
-------------------------------------------------------------------------------
local function PromptNote(id)
    local info = C_BattleNet.GetAccountInfoByID(id)
    if not info then return end
    EllesmereUI:ShowInputPopup({
        title       = "Set Note",
        message     = "Enter a note for this friend:",
        initialText = EllesmereUI.StripFriendNoteTag(info.note) or "",
        placeholder = "Enter note...",
        confirmText = "Save",
        cancelText  = "Cancel",
        maxLetters  = NOTE_MAX,
        allowEmpty  = true,     -- an empty note deletes it
        onConfirm   = function(text) BNSetFriendNote(id, text or "") end,
    })
end

local function PromptRemove(id)
    EllesmereUI:ShowConfirmPopup({
        title       = "Remove Friend",
        message     = "Remove this friend from your friends list?",
        confirmText = "Remove",
        cancelText  = "Cancel",
        onConfirm   = function() BNRemoveFriend(id) end,
    })
end

-- Blizzard's friend tags as checkboxes: one set for the interests and the
-- roles, sent whole on every tick
local function AddTagEntries(sub, id, info)
    local set = {}
    local have = info.friendTags
    if type(have) == "table" then
        for i = 1, #have do set[have[i]] = true end
    end
    local function IsOn(tag) return set[tag] == true end
    local function Toggle(tag)
        set[tag] = not set[tag] or nil
        local list = {}
        for t in pairs(set) do list[#list + 1] = t end
        C_BattleNet.SetFriendTags(id, list)
    end
    local function Add(tags)
        if type(tags) ~= "table" then return end
        for i = 1, #tags do
            sub:CreateCheckbox(SocialUIUtil.GetLabelForBattleNetFriendTag(tags[i]), IsOn, Toggle, tags[i])
        end
    end
    Add(SocialUIUtil.GetSupportedBattleNetFriendTagInterestsForCurrentGameType())
    Add(SocialUIUtil.GetSupportedBattleNetFriendTagRolesForCurrentGameType())
end

local registering = false
local function AddMenuEntries(_, menu, contextData)
    if registering or not (active and root:IsMouseOver()) then return end
    if type(contextData) ~= "table" or contextData.friendsList then return end
    local rec = byId[tonumber(contextData.bnetIDAccount) or 0]
    local info = rec and rec.info
    if not info then return end
    local id, key = rec.id, rec.key
    local g = Store()
    local current = BucketOf(g, info, key)

    -- The friend entries Blizzard's menu offers only from its own list. No
    -- divider before them: they join its last section, as there. The
    -- favorite line does what the Favorites entries further down do.
    menu:CreateButton(SET_NOTE or EllesmereUI.L("Set Note"), function() PromptNote(id) end)
    if current == FAV then
        menu:CreateButton(REMOVE_FAVORITE_STATUS or EllesmereUI.L("Remove Favorite"),
            function() PlaceFriend(id, key, UNGROUPED) end)
    else
        menu:CreateButton(ADD_FAVORITE_STATUS or EllesmereUI.L("Add Favorite"),
            function() PlaceFriend(id, key, FAV) end)
    end
    if SocialUIUtil and C_BattleNet.AreFriendTagsEnabled and C_BattleNet.AreFriendTagsEnabled()
        and C_BattleNet.SetFriendTags then
        AddTagEntries(menu:CreateButton(SOCIAL_UI_BATTLE_NET_FRIEND_TAGS_LABEL or EllesmereUI.L("Tags")), id, info)
    end
    menu:CreateButton(REMOVE_FRIEND or EllesmereUI.L("Remove Friend"), function() PromptRemove(id) end)

    -- Our own sections, after them: Favorites and the custom groups alike,
    -- less the one the friend sits in
    if key then
        menu:CreateDivider()
        menu:CreateTitle("EllesmereUI")
        local grouped = current ~= UNGROUPED
        local sub = menu:CreateButton(grouped and EllesmereUI.L("Move to Group") or EllesmereUI.L("Add to Group"))
        sub:CreateButton(EllesmereUI.L("New Group..."), function() PromptNewGroup(key) end)
        local list = g.friendGroups
        if current ~= FAV or #list > 0 then sub:CreateDivider() end
        if current ~= FAV then
            sub:CreateButton(FAVORITES or EllesmereUI.L("Favorites"), function() PlaceFriend(id, key, FAV) end)
        end
        for i = 1, #list do
            local name = list[i].name
            if name ~= current then
                sub:CreateButton(name, function() PlaceFriend(id, key, name) end)
            end
        end
        if grouped then
            sub:CreateDivider()
            sub:CreateButton(EllesmereUI.L("Remove from Group"), function() PlaceFriend(id, key, UNGROUPED) end)
        end
    end
end

-------------------------------------------------------------------------------
--  Build (once), show and stand down
-------------------------------------------------------------------------------
local function Build()
    local view = View()
    root = CreateFrame("Frame", nil, view)
    -- Over Blizzard's list and its scroll bar: as wide as the view's top
    -- divider and a little past it, down to the bottom one. Above every
    -- card, and it takes the mouse, so the list underneath gets none.
    root:SetPoint("TOPLEFT", view.TopDivider, "TOPLEFT", 0, -5)
    root:SetPoint("TOPRIGHT", view.TopDivider, "TOPRIGHT", 3, -5)
    root:SetPoint("BOTTOM", view.BottomDivider, "TOP", 0, 1)
    root:SetFrameLevel(view:GetFrameLevel() + 40)
    root:EnableMouse(true)
    root:Hide()

    -- The scroll area is the one Blizzard's list has
    sf = CreateFrame("ScrollFrame", nil, root)
    sf:SetAllPoints(view.ScrollBox)
    content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    bar = CreateFrame("EventFrame", nil, root, "MinimalScrollBar")
    bar:SetAllPoints(view.ScrollBar)
    bar:RegisterCallback(ScrollBarMixin.Event.OnScroll, OnBarScroll, bar)
    -- The wheel over the list is the bar's own (the template's handler over
    -- the bar): two tiles a tick, at once
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta) bar:OnMouseWheel(delta) end)
    sf:SetScript("OnSizeChanged", function()
        if not active then return end
        ApplyMetrics()
        Refill()
    end)

    -- Blizzard's friends filter shows nothing while a filter is ticked, so
    -- the house X sits where a filter menu's reset button does. It takes no
    -- mouse: a click on it reaches the Filter button under it, whose menu
    -- unticks the filters (a filter changed from our code would run the
    -- friend search as ours, which the game refuses).
    local dd = view.FilterBar and view.FilterBar.SearchFilterDropdown
    if dd then
        filterX = CreateFrame("Frame", nil, root)
        filterX:SetSize(10, 10)
        filterX:SetPoint("CENTER", dd, "TOPRIGHT", -3, 0)
        local x = filterX:CreateTexture(nil, "OVERLAY", nil, 7)
        x:SetAllPoints()
        x:SetAtlas("uitools-icon-close", false)
        x:SetVertexColor(1, 1, 1, 0.9)
        filterX:Hide()
    end

    -- Friend events mark the list; this hidden frame redraws it once, on the
    -- next frame, then hides again
    flusher = CreateFrame("Frame")
    flusher:Hide()
    flusher:SetScript("OnUpdate", OnFlush)

    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", OnEvent)

    -- The one hook on Blizzard's view: its search box and filter menu both
    -- end in this call. A post-hook; it only marks our list.
    if view.RefreshSearchResults then
        hooksecurefunc(view, "RefreshSearchResults", OnBlizzardSearch)
    end

    -- A new accent colour repaints the section names that follow it
    EllesmereUI.RegAccent({
        type = "callback",
        fn = function()
            if not active then return end
            styleGen = styleGen + 1
            LayoutVisible()
        end,
    })
end

local function WantActive()
    local p = Settings()
    if not (p and p.enabled ~= false and p.customTiles ~= false) then return false end
    if not FL.Available() or EllesmereUI.PadGamepadUI() then return false end
    if C_SocialRestrictions and C_SocialRestrictions.IsFriendsDisabled
        and C_SocialRestrictions.IsFriendsDisabled() then
        return false
    end
    return true
end

-- The friends view hid: nothing of ours runs until it shows again. Blizzard's
-- list stays covered, so its cards are not painted for nothing meanwhile.
local function Park()
    if not active then return end
    active = false
    root:Hide()
    flusher:Hide()
    dirtyFull, dirtyInvites = false, false
    ev:UnregisterAllEvents()
    for i = #menuHandles, 1, -1 do
        menuHandles[i]:Unregister()
        menuHandles[i] = nil
    end
    hoverRow, selectedId = nil, nil
    wipe(favAsked)
    wipe(searchCollapsed)
    EllesmereUI.HideWidgetTooltip()
end

-- The list stands down: Blizzard's own list shows again
local function Uncover()
    if not covering then return end
    covering = false
    Kit._listShown = false
    local view = View()
    if view then
        view.ScrollBox:SetAlpha(1)
        view.ScrollBar:SetAlpha(1)
    end
    -- Blizzard's cards the kit left unpainted while ours covered them
    Kit.RedecorateTiles()
end

local function Activate()
    if not root then Build() end
    if not covering then
        covering = true
        Kit._listShown = true
        local view = View()
        -- Top-level alpha only: Blizzard's list keeps running underneath
        view.ScrollBox:SetAlpha(0)
        view.ScrollBar:SetAlpha(0)
    end
    local opening = not active
    if opening then
        active = true
        root:Show()
        ev:RegisterEvent("BN_FRIEND_INFO_CHANGED")
        ev:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
        ev:RegisterEvent("BN_CONNECTED")
        ev:RegisterEvent("BN_DISCONNECTED")
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        -- ModifyMenu replays the callback at once on the last menu built
        registering = true
        for i = 1, #MENU_TAGS do
            menuHandles[#menuHandles + 1] = Menu.ModifyMenu(MENU_TAGS[i], AddMenuEntries)
        end
        registering = false
    end
    ApplyMetrics()
    Refill()
    -- A filter left ticked: Blizzard's list fills as the view shows, which may
    -- come after this, so the friends it keeps are read once more next frame
    if opening and searchActive then
        dirtyFull = true
        flusher:Show()
    end
end

-- The friends view showed, or a setting changed. The list is live only while
-- the view shows; it stays over Blizzard's hidden list until it stands down.
local function Sync()
    if not WantActive() then
        Park()
        Uncover()
    elseif driver and driver:IsVisible() then
        Activate()
    else
        Park()
    end
end

-------------------------------------------------------------------------------
--  Public
-------------------------------------------------------------------------------
-- The Social UI friends list exists, and entries added to Blizzard's friend
-- menu are isolated on this client
function FL.Available()
    return View() ~= nil and Menu ~= nil and Menu.ModifyMenu ~= nil and Menu.IsMenuProxy ~= nil
end

-- Lowest, highest and default Tile Height, for the options slider
function FL.TileRange()
    return TILE_MIN, TILE_MAX, TILE_DEFAULT
end

-- A setting changed (the host's options call this), or the list starts
function FL.Refresh()
    if not host then return end
    local p = Settings()
    if not (p and p.enabled ~= false and p.customTiles ~= false and FL.Available()) then
        if driver then driver:Hide() end
        Park()
        Uncover()
        return
    end
    if not driver then
        -- A child of the friends view: its show and hide are the list's
        driver = CreateFrame("Frame", nil, View())
        driver:SetScript("OnShow", Sync)
        driver:SetScript("OnHide", Park)
    end
    driver:Show()
    Sync()
end

-- Starts the list for the session, once, after the kit's tiles
-- (Kit.StartTiles, with or without its cards): it draws with the same
-- host's settings and font, and only under the EllesmereUI look (a stock
-- look keeps Blizzard's list).
function FL.Start()
    if host then return end
    local h = T.Host()
    if not h or h.style ~= "eui" then return end
    host = h
    FL.Refresh()
end
