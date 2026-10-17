if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_SidebarIcons.lua
--
--  Which sidebar icons show, their order and the chain that anchors the
--  visible ones, and the Chat Menu icon over Blizzard's chat menu button.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIChat.lua or an earlier EUI_Chat_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local ECHAT = ns.ECHAT

local CFD, GetTabAreaHeight = I.CFD, I.GetTabAreaHeight

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local _sidebarFadeTarget = I._sidebarFadeTarget
I.sidebarFadeTargetSetters[#I.sidebarFadeTargetSetters + 1] = function(v) _sidebarFadeTarget = v end
local _sidebarFadeAlpha = I._sidebarFadeAlpha
I.sidebarFadeAlphaSetters[#I.sidebarFadeAlphaSetters + 1] = function(v) _sidebarFadeAlpha = v end

-- Show/hide individual sidebar icons and re-anchor visible ones to close gaps
-- Chain refs for ApplySidebarIcons (static: that pass runs on every sidebar
-- fade edge).
ECHAT.SIDEBAR_CHAIN_REFS = {
    showFriends    = { btn = "friendsBtn",    tail = "friendsCount" },
    showGuild      = { btn = "guildBtn",      tail = "guildCount" },
    showDurability = { btn = "durabilityBtn", tail = "durabilityPct" },
    showCopy       = { btn = "copyBtn" },
    showPortals    = { btn = "portalBtn" },
    showVoice      = { btn = "voiceBtn" },
    showChatMenu   = { btn = "chatMenuBtn" },
    showSettings   = { btn = "settingsBtn" },
}
function ECHAT.ApplySidebarIcons()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end

    -- Stock kits pack their column like the stock one: their own spacing
    -- (the visible gap between art; each button's transparent pads come off).
    local kit = ECHAT.SB_KIT
    local ICON_GAP = kit and (cfg.stockIconSpacing or kit.gap) or (cfg.sidebarIconSpacing or 10)
    -- Shift the chain up by the tab-strip height when the background is extended
    -- and free-move is off. Matches the offset applied at icon creation.
    local iconTopShift = (ECHAT.ExtendBgBehindTabs(cfg) and not cfg.freeMoveIcons) and GetTabAreaHeight() or 0
    local sbd = CFD(cf1)

    -- Re-anchor the chain in the creation-time order snapshot. Options-dropdown
    -- order edits intentionally do NOT apply live -- rebuilt on next reload.
    -- Icons never created (enabled after login) are skipped so the chain hangs
    -- off the last icon that actually exists.
    local CHAIN_REFS = ECHAT.SIDEBAR_CHAIN_REFS
    local chainOrder = sbd._iconChainOrder or ECHAT.ResolveSidebarIconOrder()

    -- An alpha-0 sidebar still leaves child Buttons hoverable/clickable (motion is a
    -- separate channel from EnableMouse), so invisible icons must be HIDDEN: always in
    -- "never" mode, and in "mouseover" while fully faded out (shown children would eat
    -- the hover meant to reveal the sidebar). Both fade edges re-run this via
    -- ApplyTabPadding, so shown state tracks the fade with no extra wiring.
    local sbMode = cfg.sidebarVisibility or "always"
    local sbHidden = sbMode == "never"
        or (sbMode == "mouseover" and _sidebarFadeTarget == 0 and _sidebarFadeAlpha == 0)
        or ns._chatPassthrough == true

    local anchor, prevPadB = nil, 0
    for _, key in ipairs(chainOrder) do
        local refs = CHAIN_REFS[key]
        local btn = refs and sbd[refs.btn]
        if btn then
            local shown = cfg[key] ~= false and not sbHidden
            btn:SetShown(shown)
            local tail = refs.tail and sbd[refs.tail]
            if tail then tail:SetShown(shown) end
            if shown then
                -- Pads are nil on the EllesmereUI look (the maths there is
                -- unchanged); the stock column starts at the sidebar's top.
                local padT = btn._sbPadT or 0
                btn:ClearAllPoints()
                if anchor then
                    btn:SetPoint("TOP", anchor, "BOTTOM", 0, -(ICON_GAP - prevPadB - padT))
                elseif kit then
                    btn:SetPoint("TOP", sb, "TOP", 0, 0)
                else
                    btn:SetPoint("TOP", sb, "TOP", 0, -ICON_GAP + iconTopShift)
                end
                if tail and not btn._sbTailInside then
                    anchor, prevPadB = tail, 0
                else
                    anchor, prevPadB = btn, (btn._sbPadB or 0)
                end
            end
        end
    end

    -- Scroll is independent; when anchored to the chat panel it is exempt
    -- from the hidden-sidebar cutoff.
    if sbd.scrollBtn then
        sbd.scrollBtn:SetShown(cfg.showScroll ~= false
            and (not sbHidden
                or (cfg.scrollButtonOnChat == true and ns._chatPassthrough ~= true)))
    end
    if ECHAT.ApplyScrollButtonPosition then ECHAT.ApplyScrollButtonPosition() end

    -- Re-apply free move offsets after chain layout
    if ECHAT.ApplyIconFreeMove then ECHAT.ApplyIconFreeMove() end
end

-- Map of sidebar-icon visibility key -> its CFD button reference. Buttons are
-- only created at login for icons enabled at that time, so enabling a
-- previously-disabled icon needs a reload before it has a frame. The options
-- panel uses this to fire a reload prompt only when adding a new icon
-- (scrollBtn is always created, so it never needs one).
local SIDEBAR_ICON_REFS = {
    showFriends    = "friendsBtn",
    showGuild      = "guildBtn",
    showDurability = "durabilityBtn",
    showCopy       = "copyBtn",
    showPortals    = "portalBtn",
    showVoice      = "voiceBtn",
    showChatMenu   = "chatMenuBtn",
    showSettings   = "settingsBtn",
    showScroll     = "scrollBtn",
}

-- Canonical chain-icon keys and fallback order values. Explicit numbers in
-- cfg.sidebarIconOrder win; unlisted keys fall back here. Friends/Durability
-- sit below zero so profiles whose saved map only holds the four middle keys
-- still order Friends, Durability, then the middle group. Scroll is not part
-- of the chain -- it stays pinned at the sidebar bottom.
local SIDEBAR_CHAIN_KEYS = {
    "showFriends", "showGuild", "showDurability", "showCopy", "showPortals", "showVoice", "showChatMenu",
    "showSettings",
}
-- No keystones on Forever, so no season portals (the Minimap button is never
-- built there either): the M+ Portals icon leaves the chain, which also drops
-- it from creation and from the options icon list. Every button reader guards.
if EllesmereUI.IS_FOREVER then
    for i = #SIDEBAR_CHAIN_KEYS, 1, -1 do
        if SIDEBAR_CHAIN_KEYS[i] == "showPortals" then table.remove(SIDEBAR_CHAIN_KEYS, i) end
    end
end
-- Chat Menu leaves the chain under WoW Forever's Gamepad interface style: it
-- hooks Blizzard's chat menu button, which that style's navigation drives
-- from secure code. Decided once logged in, when the style reads reliably,
-- and kept for the session like the suite's other gamepad stand-downs.
local chatMenuPadOff
local function ChatMenuPadOff()
    if chatMenuPadOff == nil then
        if not IsLoggedIn() then return EllesmereUI.PadGamepadUI() end
        chatMenuPadOff = EllesmereUI.PadGamepadUI()
    end
    return chatMenuPadOff
end
local SIDEBAR_FALLBACK_ORDER = {
    showFriends = -20, showGuild = -15, showDurability = -10,
    showCopy = 1, showPortals = 2, showVoice = 3, showChatMenu = 4, showSettings = 4,
}
-- An icon with no saved place takes its neighbour's (a tie goes to list
-- position): Chat Menu sorts just above Settings in any saved order, and no
-- other icon moves.
local SIDEBAR_FALLBACK_WITH = { showChatMenu = "showSettings" }

-- Chain-icon keys sorted into the user's saved order. Used by the sidebar
-- creation pass (reload-time source of truth), by ApplySidebarIcons when no
-- creation snapshot exists, and by the options dropdown to list its rows.
function ECHAT.ResolveSidebarIconOrder()
    local cfg = ECHAT.DB()
    local map = (cfg and cfg.sidebarIconOrder) or {}
    local keyIndex = {}
    local keys = {}
    local padOff = ChatMenuPadOff()
    for i = 1, #SIDEBAR_CHAIN_KEYS do
        local key = SIDEBAR_CHAIN_KEYS[i]
        if not (padOff and key == "showChatMenu") then
            keys[#keys + 1] = key
            keyIndex[key] = i
        end
    end
    local function OrderOf(key)
        local o = map[key]
        if type(o) == "number" then return o end
        local with = SIDEBAR_FALLBACK_WITH[key]
        o = with and map[with]
        if type(o) == "number" then return o end
        return SIDEBAR_FALLBACK_ORDER[key] or 999
    end
    table.sort(keys, function(a, b)
        local oa, ob = OrderOf(a), OrderOf(b)
        if oa ~= ob then return oa < ob end
        return keyIndex[a] < keyIndex[b]
    end)
    return keys
end

function ECHAT.SidebarIconExists(key)
    local ref = SIDEBAR_ICON_REFS[key]
    if not ref then return true end
    local cf1 = _G.ChatFrame1
    if not cf1 then return true end
    return CFD(cf1)[ref] ~= nil
end

-------------------------------------------------------------------------------
--  Chat Menu: Blizzard's own chat menu button (chat types, emotes, the spoken
--  language) behind our sidebar icon. Our chat keeps that button invisible;
--  under the icon it stays at alpha 0 with its mouse back on, so the click
--  lands on Blizzard's button and the menu, the language pick and the
--  new-language help tip all run in Blizzard's code. Picking the language
--  from our code would leave the edit box's language written by us, read by
--  every message the player sends. Only the top-level button is touched
--  (anchors, fixed strata and level, mouse), never a key of ours on it, and
--  its parent stays Blizzard's: its OnShow re-validates the language, so our
--  code must never be what shows it. Its mouse follows the icon's shown
--  state, so nothing invisible takes clicks while the icon or the sidebar is
--  hidden. Hover and press reach the icon through the button's post-hooks
--  (the menu opens in the button's own handler first); a Shift press opens
--  no menu, so Free Move drags the icon as usual.
-------------------------------------------------------------------------------
ECHAT.CHAT_MENU_GLYPH = "Interface\\AddOns\\EllesmereUI\\media\\micromenu\\menu-options.png"
do
    local host  -- our sidebar icon, once attached

    local function Fwd(event, ...)
        if host:GetScript(event) then ExecuteFrameScript(host, event, ...) end
    end
    local function OnEnter(_, motion)
        host:LockHighlight()
        Fwd("OnEnter", motion)
    end
    local function OnLeave(_, motion)
        host:UnlockHighlight()
        Fwd("OnLeave", motion)
    end
    local function OnMouseDown(_, button)
        if button == "LeftButton" then host:SetButtonState("PUSHED") end
        Fwd("OnMouseDown", button)
    end
    local function OnMouseUp(_, button)
        host:SetButtonState("NORMAL")
        Fwd("OnMouseUp", button)
    end

    -- Called once, as the icon is built (only with Chat Menu on at login).
    function ECHAT.AttachChatMenu(btn)
        local mb = _G.ChatFrameMenuButton
        if host or not mb then return end
        host = btn
        mb:HookScript("OnEnter", OnEnter)
        mb:HookScript("OnLeave", OnLeave)
        mb:HookScript("OnMouseDown", OnMouseDown)
        mb:HookScript("OnMouseUp", OnMouseUp)
        btn:HookScript("OnShow", function() mb:EnableMouse(true) end)
        btn:HookScript("OnHide", function()
            mb:EnableMouse(false)
            btn:UnlockHighlight()
            btn:SetButtonState("NORMAL")
        end)
        ECHAT.SeatChatMenu()
    end

    -- The button over the icon, pinned one level above it. The sidebar's
    -- strata and level are set once at build, and fixed values keep Blizzard's
    -- re-levels of the chat frames from carrying the button below the icon.
    -- Re-run after the login pass that hides Blizzard's chat buttons.
    function ECHAT.SeatChatMenu()
        local mb = _G.ChatFrameMenuButton
        if not (host and mb) then return end
        mb:ClearAllPoints()
        mb:SetAllPoints(host)
        mb:SetFrameStrata(host:GetFrameStrata())
        mb:SetFixedFrameStrata(true)
        mb:SetFrameLevel(host:GetFrameLevel() + 2)
        mb:SetFixedFrameLevel(true)
        mb:EnableMouse(host:IsVisible())
    end
end

I.broken = false
