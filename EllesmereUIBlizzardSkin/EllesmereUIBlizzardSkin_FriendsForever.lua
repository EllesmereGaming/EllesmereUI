if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Friends list on WoW Forever
--
--  The Friends module (the retail friends list) stays off the Forever client,
--  and the Social UI pack in EllesmereUIBlizzardSkin_WindowPacks.lua skins
--  only the Social UI window, so Blizzard's legacy friends window took no
--  treatment. This gives it the standard window treatment under the
--  SAME "Friends List" card and key the Social UI pack uses (winKey
--  "socialui", enable key reskinSocialUI, the per-window style dropdown), so
--  every standard option applies and no enable or style key is added (the
--  card's own settings, friendsListCard, joined the export allowlist and the
--  module's reset list):
--    - the shell, border, top bar and house close button through the engine;
--      the corner portrait art, the nested inset box and the stock tab art
--      gone; the title in the house font;
--    - the contacts tab row across the top, the Battle.net strip with its
--      broadcast popup (panel, input, buttons), the status dropdown, the
--      Add Friend / Send Message buttons, the ignore list's own framed
--      window, the raid and quick-join panels' art and buttons, and every
--      thin scrollbar under the window;
--    - the pooled list rows keep Blizzard's own row colouring and icons and
--      take the house font; the category headers lose their art.
--  The card also hosts what the Friends module gives retail's friends list,
--  from the shared friends kit (EllesmereUI_FriendsKit.lua), with its own
--  settings on the card (EllesmereUIDB.friendsListCard): the EllesmereUI
--  tiles on the Social UI window's friend cards while the card is skinned,
--  and auto-accepting group invites from friends whatever the card's skin.
--  The custom friends list, the parent's EllesmereUI_FriendsList.lua, starts
--  here after the tiles: rows of our own over Blizzard's list, for the card's
--  Tile Height and friend groups. Its switch, Custom Friends List Tiles,
--  follows the card's look until picked (on while the card is skinned,
--  EllesmereUI or Modern; off under Blizz Default, where the kit's host
--  starts for the list alone and Blizzard's cards stay Blizzard's own).
--
--  Cost: a one-time pass at login on frames that already exist, then one
--  font pass per row initialisation (Blizzard's own, on rows it recycles),
--  and the kit's paint per card initialisation; auto-accept's invite event
--  only while it is on. Under Blizz Default with the custom list off,
--  nothing of the kit or the list starts. Nothing here runs on retail
--  (IS_FOREVER is false).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
local WSkin = ns.WSkin
if not (WSkin and WSkin.RegisterWindow and WSkin.Shell) then return end

local WIN = "socialui"

local FFD, GetFFD = EllesmereUI.NewFrameData()

-- One pooled list frame: a category header (carries a Title) loses its art
-- and takes the house font; a friend or ignore row keeps Blizzard's colours
-- and icons and only takes the font on its text.
local function SkinListRow(btn)
    if not btn or (btn.IsForbidden and btn:IsForbidden()) then return end
    local d = GetFFD(btn)
    if d.done then return end
    d.done = true
    if btn.Title then
        WSkin.FadeRegions(btn)
        WSkin.Font(btn.Title)
        WSkin.White(btn.Title)
        return
    end
    -- A friend's or ignored player's name and its info line (place, broadcast):
    -- font families, which draw the scripts the house font lacks
    if btn.name then WSkin.FontFamily(btn.name) end
    if btn.info then WSkin.FontFamily(btn.info) end
end

-- The rows are recycled by the scroll box: the frames alive now, then every
-- initialisation from here on (the event hands owner, frame, elementData).
local function HookRows(box)
    if not box or GetFFD(box).hooked then return end
    GetFFD(box).hooked = true
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(box, function(_, frame) SkinListRow(frame) end, nil, false)
        if box.ForEachFrame then box:ForEachFrame(function(frame) SkinListRow(frame) end) end
    end
end

local function SkinButton(b)
    if b then WSkin.Button(b); WSkin.WhiteButtonLabel(b) end
end

local function SkinFriends()
    local f = _G.FriendsFrame
    if not f then return end
    local d = GetFFD(f)
    if d.done then return end
    d.done = true

    WSkin.Shell(WIN, f)
    WSkin.RemovePortrait(f)
    -- The Battle.net portrait art that rides the corner beside the portrait.
    if _G.FriendsFrameIcon then _G.FriendsFrameIcon:SetAlpha(0) end
    WSkin.CommonChrome(f, "FriendsFrame")
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    if f.Inset then WSkin.Inset(f.Inset) end
    local title = _G.FriendsFrameTitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if title then WSkin.Font(title); WSkin.White(title) end

    -- Contacts / ignore tab row across the top, the Battle.net strip and the
    -- status dropdown, all owned by the tab header that spans the frame.
    local hdr = f.FriendsTabHeader
    if hdr then
        if hdr.TabSystem then WSkin.TabSystem(hdr.TabSystem, { darkActive = true }) end
        local bn = hdr.BattlenetFrame or _G.FriendsFrameBattlenetFrame
        if bn then
            WSkin.FadeRegions(bn)
            if bn.Tag then WSkin.FontFamily(bn.Tag); WSkin.White(bn.Tag) end
            if bn.UnavailableLabel then WSkin.Font(bn.UnavailableLabel) end
            local bf = bn.BroadcastFrame
            if bf then
                WSkin.Panel(bf)
                if bf.Border then WSkin.FadeRegions(bf.Border) end
                if bf.EditBox then WSkin.EditBox(bf.EditBox) end
                SkinButton(bf.UpdateButton)
                SkinButton(bf.CancelButton)
            end
        end
        local dd = hdr.StatusDropdown or _G.FriendsFrameStatusDropdown
        if dd then WSkin.Dropdown(dd) end
    end

    -- The friends list: its bottom buttons, its rows and headers.
    local list = _G.FriendsListFrame
    if list then
        SkinButton(_G.FriendsFrameAddFriendButton)
        SkinButton(_G.FriendsFrameSendMessageButton)
        if list.FriendsDisabledText then WSkin.Font(list.FriendsDisabledText) end
        HookRows(list.ScrollBox)
    end

    -- The ignore list: a framed window of its own inside the frame.
    local ig = f.IgnoreListWindow
    if ig then
        WSkin.Shell(WIN, ig)
        WSkin.RemovePortrait(ig)
        WSkin.CommonChrome(ig, "FriendsFrameIgnoreList")
        if ig.NineSlice then WSkin.FadeNineSlice(ig.NineSlice) end
        if ig.Inset then WSkin.Inset(ig.Inset) end
        local it = ig.TitleContainer and ig.TitleContainer.TitleText
        if it then WSkin.Font(it); WSkin.White(it) end
        SkinButton(ig.UnignorePlayerButton)
        HookRows(ig.ScrollBox)
    end

    -- The raid and quick-join panels Blizzard parents in when their tab is
    -- picked, where the client ships them: art off, buttons flattened.
    local raid = _G.RaidFrame
    if raid then WSkin.FadeArtIn(raid); WSkin.ButtonsIn(raid) end
    local qj = _G.QuickJoinFrame
    if qj then WSkin.FadeArtIn(qj); WSkin.ButtonsIn(qj) end

    -- Every thin scrollbar under the window: both lists and the panels.
    WSkin.ScrollBarsIn(f)

    -- Bottom tabs (the client numbers them with a gap).
    local tabs = {}
    for i = 1, 4 do
        local t = _G["FriendsFrameTab" .. i]
        if t then WSkin.Tab(t, { darkActive = true }); tabs[#tabs + 1] = t end
    end
    WSkin.NormalizeTabRow(tabs)
end

-- The engine applies it at login when the card is on, and refreshes the
-- style live; the frame is not load-on-demand, so no addon gate.
WSkin.RegisterWindow({
    key   = WIN,
    apply = SkinFriends,
})

--------------------------------------------------------------------------------
--  The card's own settings: the friends kit reads them through a view that
--  looks like the Friends module's profile table (an unset key reads that
--  module's default); the options card writes through FriendsCardSet.
--------------------------------------------------------------------------------
local CARD_DEFAULTS = {
    enabled = true, showClassIcons = true, iconStyle = "modern", classColorNames = true,
    factionBanners = false, showRegionIcons = true,
    autoAcceptFriendInvites = false, autoAcceptGuildInvites = false,
    -- The custom friends list (EllesmereUI_FriendsList.lua): the tile height
    -- starts at that list's own default
    tileHeight = select(3, EllesmereUI.FriendsList.TileRange()),
}
-- Custom Friends List Tiles (customTiles) unset: the card's look decides, on
-- while the card is skinned (EllesmereUI or Modern) and off under Blizz
-- Default. A pick is kept only where it differs from that (FriendsCardSet),
-- so a card that never deviated keeps following its look.
local function CustomTilesDefault()
    return EllesmereUI.GetBlizzWindowStyle(WIN) ~= "off"
end

local cardView = setmetatable({}, { __index = function(_, k)
    local t = EllesmereUIDB and EllesmereUIDB.friendsListCard
    local v = t and t[k]
    if v == nil then
        if k == "customTiles" then return CustomTilesDefault() end
        v = CARD_DEFAULTS[k]
    end
    return v
end })
local function CardSettings() return cardView end

-- The card's look as it stood at login: the tiles on Blizzard's cards follow
-- it for the session (a change across Blizz Default reloads)
local loggedIn, skinnedAtLogin = false, false

-- The kit's host, then the custom friends list, which draws with it: each
-- once per session, the list's switch deciding whether it shows. The kit
-- hooks Blizzard's cards only while the card was skinned at login; under
-- Blizz Default the host serves the list alone, so it may also start later,
-- when the switch is first turned on. The list's online friends wear
-- Blizzard's own card art at the alpha given here (onlineCards): whole under
-- Blizz Default, a quarter of it under the card's own tiles.
local function StartHost()
    if not loggedIn then return end
    EllesmereUI.FriendsKit.StartTiles({ Settings = CardSettings, style = "eui", fontKey = "blizzardSkin",
        cards = skinnedAtLogin, onlineCards = skinnedAtLogin and 0.25 or 1 })
    EllesmereUI.FriendsList.Start()
end

function ns.FriendsCardGet(k)
    return cardView[k]
end

function ns.FriendsCardSet(k, v)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local t = EllesmereUIDB.friendsListCard
    if not t then t = {}; EllesmereUIDB.friendsListCard = t end
    if k == "customTiles" and v == CustomTilesDefault() then v = nil end
    t[k] = v
    if k == "autoAcceptFriendInvites" or k == "autoAcceptGuildInvites" then
        EllesmereUI.FriendsKit.SyncAutoAccept(CardSettings)
    else
        if k == "customTiles" and cardView.customTiles then StartHost() end
        EllesmereUI.FriendsKit.RedecorateTiles()
        EllesmereUI.FriendsList.Refresh()
    end
end

-- After a reset cleared the settings
function ns.FriendsCardRefresh()
    EllesmereUI.FriendsKit.SyncAutoAccept(CardSettings)
    if cardView.customTiles then StartHost() end
    EllesmereUI.FriendsKit.RedecorateTiles()
    EllesmereUI.FriendsList.Refresh()
end

-- At PLAYER_LOGIN, before any card exists: the kit's host while the card is
-- skinned or the custom list is on; auto-accept runs whatever the skin.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    EllesmereUI.FriendsKit.SyncAutoAccept(CardSettings)
    loggedIn = true
    skinnedAtLogin = EllesmereUI.GetBlizzWindowStyle(WIN) ~= "off"
    if skinnedAtLogin or cardView.customTiles then StartHost() end
end)
