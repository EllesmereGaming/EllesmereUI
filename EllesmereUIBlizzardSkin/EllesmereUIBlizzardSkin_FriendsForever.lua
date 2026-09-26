if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Friends list on WoW Forever
--
--  The Friends module (the retail friends list) stays off the Forever client,
--  and the Social UI pack in EllesmereUIBlizzardSkin_WindowPacks.lua never
--  applies there (its addon does not load), so Blizzard's own friends window
--  took no treatment. This gives it the standard window treatment under the
--  SAME "Friends List" card and key the Social UI pack uses (winKey
--  "socialui", enable key reskinSocialUI, the per-window style dropdown), so
--  every standard option applies and no retail table gains a key:
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
--
--  Cost: a one-time pass at login on frames that already exist, then one
--  font pass per row initialisation (Blizzard's own, on rows it recycles).
--  No events of our own. Nothing here runs on retail (IS_FOREVER is false).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
local WSkin = ns.WSkin
if not (WSkin and WSkin.RegisterWindow and WSkin.Shell) then return end

local WIN = "socialui"

local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

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
    if btn.name then WSkin.Font(btn.name) end
    if btn.info then WSkin.Font(btn.info) end
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
            if bn.Tag then WSkin.Font(bn.Tag); WSkin.White(bn.Tag) end
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
