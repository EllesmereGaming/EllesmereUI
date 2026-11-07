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
--  click only selects the friend, as on Blizzard's list: the link frame
--  passes that button on to the row, whose click script touches nothing but
--  our own selection. Field-checked on WoW Forever 1.60.1 (70790): a whisper
--  through the link, the menu's Whisper and entries added to that menu all
--  stayed Blizzard-secure, while a whisper opened from addon code did not.
--  Rules that keep it so:
--    - never give the link frame a click script (OnClick, OnMouseDown / Up,
--      OnHyperlinkClick): a post-hook on the link click is safe, a
--      replacement is not; the row's own click script only selects;
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
--  Availability: the Social UI friends list must exist and the client's menu
--  code must isolate added entries (Menu.IsMenuProxy came with that change).
--  The list stands down under WoW Forever's Gamepad interface style, where a
--  controller drives Blizzard's list.
--
--  Cost: nothing is built, registered or run until the option is on; while
--  on, only while the friends list shows (a child of that view carries the
--  show and hide edge). Friend events are coalesced to one rebuild per frame,
--  a change to one friend that moves nothing repaints that row alone, and
--  rows and headers are pooled: scrolling paints only the rows entering view.
--
--  Groups are account data in EllesmereUIDB.global (outside the profiles and
--  outside exports): the group list, order, colours and collapsed state, and
--  each friend's group by BattleTag. A "||EUI:Group||" tag an old Friends
--  build left in a friend note is read once and never written.
-------------------------------------------------------------------------------
local FL = {}
EllesmereUI.FriendsList = FL

-- Held back: the list is not released yet. While this is set it is available
-- on no client (FL.Available), so nothing is built or started whatever a
-- profile saved, and the options build no row for it. One line to lift.
FL.HELD = true

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
-- Blizzard's own art from its friend cards: the invite button (34 across on
-- its 70-tall card: ours keeps about that share of the tile) and the status
-- icons
local BTN_NORMAL, BTN_PUSHED = "common-button-tertiary-square-normal", "common-button-tertiary-square-pressed"
local BTN_NATIVE, BTN_SHARE, BTN_MIN = 34, 0.52, 16
local STATUS_ATLAS = {
    online = "friends-status-online", away = "friends-status-away",
    busy = "friends-status-busy", offline = "friends-status-offline",
}

local TILE_MIN, TILE_MAX, TILE_DEFAULT = 24, 70, 46
local HEADER_H = 24
local ROW_GAP, GROUP_GAP = 2, 4
local PAD_TOP, PAD_BOTTOM, PAD_LEFT, PAD_RIGHT = 6, 6, 6, 4
local BAR_STRIP = 14            -- kept free on the right for the scroll bar
local TEXT_GAP = 4              -- between the icon square and the text
local CHAR_GAP = 5              -- between the Battle.net name and the character after it
local NOTE_MAX = 127            -- Blizzard's own limit on a friend note
local GROUP_NAME_MAX = 32

local FAV, UNGROUPED = "_favorites", "_ungrouped"
local KIND_HEADER, KIND_FRIEND = 0, 1

-- The kit's host (settings, look, font): set once by FL.Start
local host
local driver, root, sf, content, flusher, ev
local UpdateThumb, ScrollTo     -- the shared scroll bar's, set as the list is built
local active = false            -- live: shown, listening
local covering = false          -- Blizzard's list is hidden under ours
local viewH, rowW = 0, 0
local tileH, tier = TILE_DEFAULT, 2
local ring = 8                  -- pool slots: more than the items one view spans
local styleGen, modelGen, visGen = 0, 0, 0
local dirtyFull, dirtyInvites = false, false
local searchActive = false
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

local function BucketOf(g, info, key)
    if info.isFavorite then return FAV end
    local name = key and g.friendGroupsByTag[key]
    if name and FindGroup(g, name) then return name end
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
--  Search: Blizzard's own search box and filter menu keep working. The same
--  friends Blizzard's list would show are asked for with the state it keeps.
-------------------------------------------------------------------------------
local searchInfo = {
    searchText = "", isOnline = false, isOffline = false, isDND = false, isAFK = false,
    isInQueue = false, isAvailableForQueue = false, tags = {},
}
local allowedSet = {}
local function SearchSet()
    local view = View()
    local bar = view.FilterBar and view.FilterBar.SearchBar
    local text = bar and bar.GetText and bar:GetText() or ""
    if type(text) ~= "string" or IsSecret(text) then text = "" end
    local any = text ~= ""
    searchInfo.isOnline, searchInfo.isOffline, searchInfo.isDND, searchInfo.isAFK = false, false, false, false
    searchInfo.isInQueue, searchInfo.isAvailableForQueue = false, false
    local tags = searchInfo.tags
    wipe(tags)
    local selected = view.selectedSearchFilterOptions
    if type(selected) == "table" then
        for option, on in pairs(selected) do
            local si = on and type(option) == "table" and option.searchInfo
            if type(si) == "table" then
                any = true
                if si.tags then
                    for i = 1, #si.tags do tags[#tags + 1] = si.tags[i] end
                else
                    for field, value in pairs(si) do
                        searchInfo[field] = searchInfo[field] or value
                    end
                end
            end
        end
    end
    if not any then return nil end
    searchInfo.searchText = text
    local ok, result = pcall(C_BattleNet.SearchFriends, searchInfo)
    if not ok or type(result) ~= "table" then return nil end
    wipe(allowedSet)
    for i = 1, #result do allowedSet[result[i]] = true end
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

    local allowed = SearchSet()
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

    local p = Settings()
    local showUngrouped = not p or p.showUngrouped ~= false
    local order, orderCount = ValidOrder(g)

    renderedCount = 0
    for i = 1, orderCount do
        local key = order[i]
        local list = buckets[key]
        if list and #list > 0 and (key ~= UNGROUPED or showUngrouped) then
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
        -- A search opens every section it finds a friend in
        if searchActive or not IsCollapsed(g, key) then
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

local function SetFriendGroup(key, name)
    if not key then return end
    Store().friendGroupsByTag[key] = name
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

local function PromptRenameGroup(old)
    EllesmereUI:ShowInputPopup({
        title       = "Rename Friend Group",
        message     = "Enter a new name for this group:",
        initialText = old,
        placeholder = "Enter name...",
        confirmText = "Rename",
        cancelText  = "Cancel",
        maxLetters  = GROUP_NAME_MAX,
        onConfirm   = function(text) RenameGroup(old, text) end,
    })
end

local function PromptDeleteGroup(name)
    EllesmereUI:ShowConfirmPopup({
        title       = "Delete Friend Group",
        message     = EllesmereUI.Lf("Delete the group %1$s? Its friends go back to the Friends section.", name),
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

-- The pointer comes onto a row: the kit's hover look and the friend's
-- tooltip. Over a link the game runs a frame's hyperlink hover scripts in
-- place of its plain ones (Blizzard's Quick Join rows forward them the same
-- way), and the link covers the row, so both land here.
local function RowEnter(hit)
    local f = hit:GetParent()
    if hoverRow == f then return end
    hoverRow = f
    f.d.hoverBar:Show()
    f.d.hoverFill:Show()
    if f.rec and f.rec.info then
        EllesmereUI.ShowWidgetTooltip(f, FriendTooltip(f.rec), TIP_OPTS)
    end
end

local function RowLeave(hit)
    local f = hit:GetParent()
    if hoverRow ~= f then return end
    hoverRow = nil
    f.d.hoverBar:Hide()
    f.d.hoverFill:Hide()
    EllesmereUI.HideWidgetTooltip()
end

-------------------------------------------------------------------------------
--  Selection: a left click selects a friend, as on Blizzard's list, and a
--  second one lets go. The look is the kit's selected tile.
-------------------------------------------------------------------------------
local function SetSelected(f, on)
    if f.selected == on then return end
    f.selected = on
    f.d.selBar:SetShown(on)
    f.d.selFill:SetShown(on)
end

local function RowClick(f, button)
    local rec = f.rec
    if button ~= "LeftButton" or not (rec and f.item) or not f:IsMouseOver() then return end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    selectedId = (selectedId ~= rec.id) and rec.id or nil
    for i = 1, #rowList do
        local row = rowList[i]
        if row.item then SetSelected(row, row.rec.id == selectedId) end
    end
end

-------------------------------------------------------------------------------
--  Click routing: the link frame passes the left button on to the row under
--  it, so a left click selects and only the right click is Blizzard's (its
--  friend menu). The game refuses click routing in combat on every frame, so
--  the rows are made ahead, out of combat (ApplyMetrics); one made in combat
--  keeps the link's own left click, a whisper, until combat ends.
-------------------------------------------------------------------------------
local needRoute = false
local RouteRows

local function Route(f)
    if InCombatLockdown() then
        if not needRoute then
            needRoute = true
            EllesmereUI.CombatQueue.Defer("FriendsListRoute", RouteRows)
        end
        return
    end
    f.hit:SetPassThroughButtons("LeftButton")
    f.routed = true
end

RouteRows = function()
    needRoute = false
    for i = 1, #rowList do
        local f = rowList[i]
        if not f.routed then Route(f) end
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

-- What the button would do, and in red why it cannot (offline, or Blizzard's
-- invite restriction)
local function InviteEnter(btn)
    local rec = btn:GetParent().rec
    local index = LiveIndex(rec)
    local U = FriendsListUtil
    if not (index and U and U.GetBattleNetFriendInviteInfo) then return end
    local text = U.GetBattleNetFriendInviteTypeLabel(U.GetBattleNetFriendInviteInfo(index).inviteType) or ""
    local why
    if not rec.online then
        why = SOCIAL_UI_FRIENDS_LIST_PARTY_BUTTON_OFFLINE_TOOLTIP
    elseif not btn:IsEnabled() and btn.restriction and U.GetBattleNetFriendPartyInviteRestrictionText then
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

-- As on Blizzard's card: always there, off (and its icon greyed) for a friend
-- who is offline or cannot be invited
local function UpdateInvite(f, rec)
    local btn = f.PartyButton
    local U = FriendsListUtil
    if not (U and U.GetBattleNetFriendPartyInviteRestriction and BattleNetFriendPartyInviteRestrictionType) then
        btn:Hide()
        return
    end
    local restriction = U.GetBattleNetFriendPartyInviteRestriction(rec.index)
    local enabled = rec.online and restriction == BattleNetFriendPartyInviteRestrictionType.None
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

    -- A left click selects the friend: it reaches the row through the link
    -- frame above it, which passes that button on (Route)
    f:SetMouseClickEnabled(true)
    f:SetMouseMotionEnabled(false)
    f:SetScript("OnMouseUp", RowClick)

    -- The invite button, in the art of the one on Blizzard's card. Named as
    -- there: the kit hangs its region icon beside it.
    local btn = CreateFrame("Button", nil, f)
    btn:SetFrameLevel(f:GetFrameLevel() + 6)
    btn:SetPoint("RIGHT", f, "RIGHT", -4, 0)
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

    -- The click layer. Its click script stays the template's: Blizzard's.
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

    local link = hit:CreateFontString(nil, "ARTWORK")
    link:SetJustifyH("LEFT")
    link:SetJustifyV("TOP")
    link:SetWordWrap(false)
    link:SetAlpha(0)
    f.link = link

    f:Hide()
    rowPool[slot] = f
    rowList[#rowList + 1] = f
    Route(f)
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

    local btnSize = math.max(BTN_MIN, math.min(BTN_NATIVE, math.floor(tileH * BTN_SHARE + 0.5)))
    f.btnSize = btnSize
    f.PartyButton:SetSize(btnSize, btnSize)

    local nameSize, lineSize = 15, 12
    if tier == 2 then nameSize = 14 elseif tier == 1 then nameSize, lineSize = 13, 11 end
    d.name:SetFont(font, nameSize, "")
    d.charLine:SetFont(font, lineSize, "")
    d.info:SetFont(font, lineSize, "")
    d.name:SetTextColor(1, 1, 1, 1)
    d.charLine:SetTextColor(1, 1, 1, 1)
    d.info:SetTextColor(1, 1, 1, 1)
    d.info:SetJustifyH(tier == 1 and "RIGHT" or "LEFT")
    f.status:SetSize(nameSize, nameSize)
    f.nameSize, f.lineSize = nameSize, lineSize
end

-- Line 1 is the Battle.net name, the character in brackets after it and the
-- status icon; the place (with the note) is the line below, or the right end
-- of a one-line tile. The texts stop at the invite button, or at the region
-- icon beside it: reserve is the width those keep on the right.
local function LayoutText(f, hasChar, stop, reserve)
    local d = f.d
    local name, char = d.name, d.charLine
    local x = tileH + TEXT_GAP
    local avail = rowW - x - reserve - 6
    local statusW = f.nameSize + 3

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
    char:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", CHAR_GAP, 0)
    status:SetPoint("LEFT", showChar and char or name, "RIGHT", 3, 0)
    if tier == 1 then
        name:SetPoint("LEFT", f, "LEFT", x, 0)
        info:SetPoint("LEFT", status, "RIGHT", 8, 0)
    else
        local gap = tier == 3 and 5 or 3
        local block = f.nameSize + gap + f.lineSize
        name:SetPoint("TOPLEFT", f, "TOPLEFT", x, -math.max(0, (tileH - block) / 2))
        info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -gap)
    end
    info:SetPoint("RIGHT", stop, "LEFT", -6, 0)
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

    -- The link: SetFormattedText, so a name the game keeps secret still goes in
    pcall(f.link.SetFormattedText, f.link, LINK_FORMAT, info.accountName, rec.id, info.accountName, LINK_FILLER)

    local p = Settings()
    T.Region(f, d, info)
    -- The kit sizes its region icon once, as it makes it: ours follows the tile
    local region = d.regionBtn
    local regionSize = math.min(28, math.floor(tileH * 0.8))
    if region and f.regionFor ~= tileH then
        f.regionFor = tileH
        region:SetSize(regionSize, regionSize)
    end
    UpdateInvite(f, rec)
    local regionShown = region ~= nil and region:IsShown()

    -- Every string arrives wrapped in Blizzard's colour codes
    local charText = T.CharLine(info)
    local hasChar = charText ~= ""
    d.name:SetText(T.Name(info))
    if hasChar then d.charLine:SetText(Bracketed(info, charText)) end
    d.info:SetText(T.Info(info))
    LayoutText(f, hasChar, regionShown and region or f.PartyButton,
        4 + f.btnSize + (regionShown and (2 + regionSize) or 0))

    local presence = Presence(info)
    if f.presence ~= presence then
        f.presence = presence
        f.status:SetAtlas(STATUS_ATLAS[presence])
    end

    UpdateIcon(f, info, p)
    d.onlineBg:SetShown(rec.online)
    T.Faction(f, d, info)
    SetSelected(f, rec.id == selectedId)

    -- A reused row under the pointer shows the new friend's tooltip
    if hoverRow == f then
        EllesmereUI.ShowWidgetTooltip(f, FriendTooltip(rec), TIP_OPTS)
    else
        d.hoverBar:Hide()
        d.hoverFill:Hide()
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

local function HeaderIconEnter(btn)
    if not btn.off then btn:SetAlpha(ICON_HOVER) end
end

local function HeaderIconLeave(btn)
    btn:SetAlpha(btn.off and ICON_OFF or ICON_ALPHA)
end

local function HeaderIcon(parent, texture, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(14, 14)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints()
    icon:SetTexture(ICONS .. texture)
    btn:SetAlpha(ICON_ALPHA)
    btn:SetScript("OnEnter", HeaderIconEnter)
    btn:SetScript("OnLeave", HeaderIconLeave)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function HeaderClick(h)
    ToggleCollapsed(h.key)
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

local function HeaderRename(btn)
    PromptRenameGroup(btn:GetParent().key)
end

local function HeaderDelete(btn)
    PromptDeleteGroup(btn:GetParent().key)
end

-- A click on the section's name picks its colour (the picker lives in the
-- options addon, which the game will not load in combat)
local function HeaderColor(btn)
    local key = btn:GetParent().key
    if not key or InCombatLockdown() then return end
    EllesmereUI:EnsureLoaded()
    if not EllesmereUI.ShowColorPicker then return end
    local colors = Store().friendGroupColors
    local was = colors[key]
    local r, g, b
    if was then r, g, b = was.r, was.g, was.b else r, g, b = AccentRGB() end
    EllesmereUI:ShowColorPicker({
        r = r, g = g, b = b,
        hasOpacity = false,
        swatchFunc = function()
            local popup = EllesmereUI._colorPickerPopup
            if not popup then return end
            local nr, ng, nb = popup:GetColorRGB()
            colors[key] = { r = nr, g = ng, b = nb }
            if active then Refill() end
        end,
        cancelFunc = function()
            colors[key] = was
            if active then Refill() end
        end,
    }, btn)
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

    h.label = h:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(h.label, true)
    h.label:SetPoint("CENTER", h, "CENTER", 0, 0)

    h.up = HeaderIcon(h, "eui-arrow-up3.png", HeaderUp)
    h.down = HeaderIcon(h, "eui-arrow-down3.png", HeaderDown)
    h.edit = HeaderIcon(h, "eui-edit.png", HeaderRename)
    h.x = HeaderIcon(h, "eui-close.png", HeaderDelete)
    h.up:SetPoint("LEFT", h, "LEFT", 8, 0)
    h.down:SetPoint("RIGHT", h, "RIGHT", -8, 0)
    h.edit:SetPoint("LEFT", h.up, "RIGHT", 4, 0)
    h.x:SetPoint("RIGHT", h.down, "LEFT", -4, 0)

    h.lineL = h:CreateTexture(nil, "OVERLAY")
    h.lineL:SetColorTexture(1, 1, 1, 0.1)
    h.lineL:SetHeight(1)
    h.lineR = h:CreateTexture(nil, "OVERLAY")
    h.lineR:SetColorTexture(1, 1, 1, 0.1)
    h.lineR:SetHeight(1)

    -- Over the name: a click there picks the colour instead of collapsing
    h.pick = CreateFrame("Button", nil, h)
    h.pick:SetFrameLevel(h:GetFrameLevel() + 3)
    h.pick:SetHeight(HEADER_H)
    h.pick:SetPoint("CENTER", h.label, "CENTER", 0, 0)
    h.pick:SetScript("OnClick", HeaderColor)

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
        h.label:SetFont(T.FontPath(), 12, "")
    end
    h.label:SetText(it.label)
    local color = Store().friendGroupColors[it.key]
    if color then
        h.label:SetTextColor(color.r, color.g, color.b, 1)
    else
        h.label:SetTextColor(AccentRGB())
    end
    h.pick:SetWidth((h.label:GetStringWidth() or 40) + 8)
    SetIconOff(h.up, it.first)
    SetIconOff(h.down, it.last)
    if h.custom ~= it.custom then
        h.custom = it.custom
        h.edit:SetShown(it.custom)
        h.x:SetShown(it.custom)
        h.lineL:ClearAllPoints()
        h.lineR:ClearAllPoints()
        h.lineL:SetPoint("LEFT", it.custom and h.edit or h.up, "RIGHT", 6, 0)
        h.lineL:SetPoint("RIGHT", h.label, "LEFT", -6, 0)
        h.lineR:SetPoint("LEFT", h.label, "RIGHT", 6, 0)
        h.lineR:SetPoint("RIGHT", it.custom and h.x or h.down, "LEFT", -6, 0)
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

-- Everything from the friend data up: model, scroll range, the rows in view.
-- A wheel scroll in flight keeps going (its own steps clamp to the new range
-- and lay the rows out); only a scroll past the new end is pulled back.
Refill = function()
    Rebuild()
    local maxScroll = math.max(0, content:GetHeight() - sf:GetHeight())
    if sf:GetVerticalScroll() > maxScroll then
        ScrollTo(maxScroll)
    else
        UpdateThumb()
        LayoutVisible()
    end
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
    -- Every row those slots can need is made now, while its click routing
    -- can be set (Route): scrolling in combat then finds it ready
    if viewH > 0 and not InCombatLockdown() then
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

    -- The friend entries Blizzard's menu offers only from its own list. No
    -- divider before them: they join its last section, as there.
    menu:CreateButton(SET_NOTE or EllesmereUI.L("Set Note"), function() PromptNote(id) end)
    if info.isFavorite then
        menu:CreateButton(REMOVE_FAVORITE_STATUS or EllesmereUI.L("Remove Favorite"),
            function() BNSetFriendFavoriteFlag(id, false) end)
    else
        menu:CreateButton(ADD_FAVORITE_STATUS or EllesmereUI.L("Add Favorite"),
            function() BNSetFriendFavoriteFlag(id, true) end)
    end
    if SocialUIUtil and C_BattleNet.AreFriendTagsEnabled and C_BattleNet.AreFriendTagsEnabled()
        and C_BattleNet.SetFriendTags then
        AddTagEntries(menu:CreateButton(SOCIAL_UI_BATTLE_NET_FRIEND_TAGS_LABEL or EllesmereUI.L("Tags")), id, info)
    end
    menu:CreateButton(REMOVE_FRIEND or EllesmereUI.L("Remove Friend"), function() PromptRemove(id) end)

    -- Our own group, after them: the friend's group (a favorite sits in
    -- Favorites and has none)
    if key and not info.isFavorite then
        menu:CreateDivider()
        menu:CreateTitle("EllesmereUI")
        local current = g.friendGroupsByTag[key]
        if current and not FindGroup(g, current) then current = nil end
        local sub = menu:CreateButton(current and EllesmereUI.L("Move to Group") or EllesmereUI.L("Add to Group"))
        sub:CreateButton(EllesmereUI.L("New Group..."), function() PromptNewGroup(key) end)
        local list = g.friendGroups
        if #list > 0 then sub:CreateDivider() end
        for i = 1, #list do
            local name = list[i].name
            if name ~= current then
                sub:CreateButton(name, function() SetFriendGroup(key, name) end)
            end
        end
        if current then
            sub:CreateDivider()
            sub:CreateButton(EllesmereUI.L("Remove from Group"), function() SetFriendGroup(key, nil) end)
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

    sf = CreateFrame("ScrollFrame", nil, root)
    sf:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -BAR_STRIP, 0)
    content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    UpdateThumb, ScrollTo = EllesmereUI.AttachSmoothScrollbar(sf, {
        child = content, onScroll = LayoutVisible, step = 60,
        trackParent = root, rightInset = 5, topInset = PAD_TOP, bottomInset = PAD_BOTTOM,
    })
    sf:SetScript("OnSizeChanged", function()
        if not active then return end
        ApplyMetrics()
        Refill()
    end)

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
    if not (p and p.enabled ~= false and p.customList == true) then return false end
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
    if not active then
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
-- The list is released (not FL.HELD), the Social UI friends list exists, and
-- entries added to Blizzard's friend menu are isolated on this client
function FL.Available()
    return not FL.HELD and View() ~= nil and Menu ~= nil and Menu.ModifyMenu ~= nil and Menu.IsMenuProxy ~= nil
end

-- Lowest, highest and default Tile Height, for the options slider
function FL.TileRange()
    return TILE_MIN, TILE_MAX, TILE_DEFAULT
end

-- A setting changed (the host's options call this), or the list starts
function FL.Refresh()
    if not host then return end
    local p = Settings()
    if not (p and p.enabled ~= false and p.customList == true and FL.Available()) then
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
-- (Kit.StartTiles): it draws with the same host's settings and font, and
-- only under the EllesmereUI look (a stock look keeps Blizzard's list).
function FL.Start()
    if host then return end
    local h = T.Host()
    if not h or h.style ~= "eui" then return end
    host = h
    FL.Refresh()
end
