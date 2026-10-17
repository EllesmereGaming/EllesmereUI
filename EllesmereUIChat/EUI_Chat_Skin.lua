if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_Skin.lua
--
--  SkinChatFrame: panel, sidebar and its buttons, scroll bar and the rest
--  of one chat frame's chrome.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIChat.lua or an earlier EUI_Chat_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = _G.EllesmereUI
local ECHAT = ns.ECHAT
local PP = EUI.PP
local min, max = min, max

local CFD, GetEditBoxHeight, GetFont = I.CFD, I.GetEditBoxHeight, I.GetFont
local GetFrameFontSize, GetInnerBorderColor = I.GetFrameFontSize, I.GetInnerBorderColor
local GetOutlineFlag, GetTabAreaHeight = I.GetOutlineFlag, I.GetTabAreaHeight
local HideSidebarIconTooltip = I.HideSidebarIconTooltip
local ShowSidebarIconTooltip = I.ShowSidebarIconTooltip
local RequestPassthroughSweep, SetAlphaFrames = I.RequestPassthroughSweep, I.SetAlphaFrames
local OnHyperlinkEnter, OnHyperlinkLeave = I.OnHyperlinkEnter, I.OnHyperlinkLeave
local ReadActiveChatText, ShowCopyPopup = I.ReadActiveChatText, I.ShowCopyPopup
local _skinned, SkinEditBox = I._skinned, I.SkinEditBox
local SetSidebarFadeTarget = I.SetSidebarFadeTarget
local SetSidebarLayoutVisible = I.SetSidebarLayoutVisible

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local BG_R = I.BG_R
I.bgRSetters[#I.bgRSetters + 1] = function(v) BG_R = v end
local BG_G = I.BG_G
I.bgGSetters[#I.bgGSetters + 1] = function(v) BG_G = v end
local BG_B = I.BG_B
I.bgBSetters[#I.bgBSetters + 1] = function(v) BG_B = v end
local BG_A = I.BG_A
I.bgASetters[#I.bgASetters + 1] = function(v) BG_A = v end
local _sidebarMouseoverLayoutVisible = I._sidebarMouseoverLayoutVisible
I.sidebarLayoutVisibleSetters[#I.sidebarLayoutVisibleSetters + 1] = function(v) _sidebarMouseoverLayoutVisible = v end
local _sidebarFadeFrame
I.sidebarFadeFrameSetters[#I.sidebarFadeFrameSetters + 1] = function(v) _sidebarFadeFrame = v end

local function SkinChatFrame(cf)
    if not cf or _skinned[cf] then return end
    _skinned[cf] = true
    SetAlphaFrames(nil)
    -- A frame skinned while the panel is fully hidden must join the passthrough
    -- set; deferred so it runs after this skin completes.
    RequestPassthroughSweep()
    local name = cf:GetName()
    if not name then return end

    -- Undock drop guard: 12.1's StopMovingOrSizing can end a tab-drag undock
    -- with the frame's anchors stripped and never re-baked; the next line of
    -- Blizzard's secure drag-stop then crashes on GetLeft (nil) and loops the
    -- tab's OnUpdate until the script suspends. This post-hook fires between
    -- the strip and that read: re-anchor the point-less frame at the cursor
    -- (the drop spot) so the position save completes cleanly. Same shipped
    -- object-hook shape as the ApplySystemAnchor guard; fires only when a
    -- chat frame stops moving (user drag), self-gates to the broken state.
    hooksecurefunc(cf, "StopMovingOrSizing", function(f)
        if f.isDocked then return end
        if f:GetNumPoints() == 0 then
            -- TOPLEFT, matching Blizzard's own undock anchor convention (the
            -- tab drag grabs near the frame's top-left, so a later re-attach
            -- by anchor point lands without a jump; CENTER produced one).
            local issec = _G.issecretvalue
            local mx, my = GetCursorPosition()
            local es = f:GetEffectiveScale()
            local w, h = f:GetWidth() or 430, f:GetHeight() or 120
            if mx and my and es and es > 0
                and not (issec and (issec(mx) or issec(my) or issec(w) or issec(h))) then
                f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                    mx / es - w / 2, my / es + h / 2)
            else
                f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    end)

    -- Tab-drag ownership for undockable frames: 12.1's StartMoving capture is
    -- broken for chat frames -- measured: zero-offset init (frame teleports
    -- to the screen corner at drag start), center-snapped to the cursor with
    -- the grab offset discarded, anchor rewritten to CENTER, and the final
    -- bake stripping all points every drag. The grip lane instead: end the
    -- capture the moment it engages and drive the drag with plain per-tick
    -- corner anchors (grab offset preserved, rect readable throughout, so
    -- the panel+text follow natively). Blizzard's drag-stop bookkeeping
    -- (redock, tab position, position save) runs unchanged on our geometry;
    -- its no-op StopMovingOrSizing at release strips nothing.
    local dragTab = _G[name .. "Tab"]
    if dragTab and cf ~= _G.ChatFrame1 then
        dragTab:HookScript("OnDragStart", function()
            if cf.isDocked then return end
            pcall(function() cf:StopMovingOrSizing() end)
            local dcf = CFD(cf)
            -- Grab reference: the frame's last at-rest rect from the follower
            -- cache -- the capture has already scrambled the live rect by the
            -- time this post-hook runs. Fresh undocks (cache still says
            -- docked) start from the live rect instead: the drop guard just
            -- re-anchored them centered under the cursor, the stock undock
            -- feel. Immediate SetPoint pins the choice before this frame
            -- renders, so re-drags never flash at the guard's spot.
            local l, t
            if not dcf._cfWasDocked and dcf._cfL and dcf._cfT then
                l, t = dcf._cfL, dcf._cfT
            else
                l, t = cf:GetLeft(), cf:GetTop()
            end
            local mx, my = GetCursorPosition()
            local es = cf:GetEffectiveScale()
            local issec = _G.issecretvalue
            if not (l and t and mx and my and es and es > 0) then return end
            if issec and (issec(l) or issec(t) or issec(mx) or issec(my)) then return end
            pcall(function()
                cf:ClearAllPoints()
                cf:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
            end)
            dcf._tabDragOffX = l - mx / es
            dcf._tabDragOffY = t - my / es
            local tk = dcf._tabDragTicker
            if not tk then
                tk = CreateFrame("Frame")
                tk:Hide()
                tk:SetScript("OnUpdate", function()
                    if cf.isDocked or not IsMouseButtonDown("LeftButton") then
                        tk:Hide()
                        return
                    end
                    local cx, cy = GetCursorPosition()
                    local es2 = cf:GetEffectiveScale()
                    local isec2 = _G.issecretvalue
                    if not (cx and cy and es2 and es2 > 0) then return end
                    if isec2 and (isec2(cx) or isec2(cy)) then return end
                    cf:ClearAllPoints()
                    cf:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                        cx / es2 + dcf._tabDragOffX, cy / es2 + dcf._tabDragOffY)
                end)
                dcf._tabDragTicker = tk
            end
            tk:Show()
        end)
    end

    -- NEVER HookScript("OnEvent") on chat frames -- even post-hooks taint the
    -- C-level event dispatcher. Idle reset + pulse detection live on standalone
    -- event frames (sections 5/6 in EUI_Chat_Init.lua).

    -- Unified dark background (covers chat + edit box as one panel). Parented to
    -- UIParent, NEVER to the chat frame: an insecure frame parented to a Blizzard chat
    -- tab/frame is exactly what this module's host design forbids, and the resulting
    -- taint poisons ChatFrame.isLocked tens of seconds away from any callback of ours
    -- -- it comes from structure, not from code we run.
    --
    -- Two things a real parent would have provided are replaced by the state watcher
    -- instead: draw order (strata + level, re-asserted because Blizzard moves chat
    -- frames between levels on dock passes) and visibility (a UIParent child does not
    -- hide with the chat frame, and anchors still resolve against a hidden one).
    -- Deliberately NOT an OnShow hook on the chat frame.
    if not CFD(cf).bg then
        local bg = CreateFrame("Frame", nil, UIParent)
        -- NO SetPoint to cf/eb: the panel is placed NUMERICALLY from the chat
        -- frame's rect (PositionChatPanel), like the tab hosts, so nothing of
        -- ours sits in Blizzard's rect chain.
        -- Stock styles: one strata above the chat frame, whose revealed
        -- background would otherwise draw over our text (see
        -- SyncChatFrameState); the chat frame's own strata otherwise.
        bg:SetFrameStrata(ns.ChatStockArt() and "MEDIUM" or cf:GetFrameStrata())
        bg:SetFrameLevel(ns.ChatStockArt() and (cf:GetFrameLevel() + 1) or max(0, cf:GetFrameLevel() - 1))
        bg:SetShown(cf:IsShown())

        local bgTex = bg:CreateTexture(nil, "BACKGROUND")
        bgTex._euiOwned = true
        bgTex:SetAllPoints()
        -- Unpainted under the stock styles (Blizzard's own background shows;
        -- WoW Forever fills its own framed boxes).
        bgTex:SetColorTexture(BG_R, BG_G, BG_B, ns.ChatStock() and 0 or BG_A)

        -- NO cf:HookScript("OnShow") to mirror visibility: FCF_OpenTemporary- Window
        -- shows the pooled frame partway through (via SetShown), so on any frame
        -- skinned while hidden (pooled temp window between conversations, or restored
        -- by reload with a whisper open) that closure would run INSIDE the open and
        -- taint the rest of it. The state watcher carries shown-state instead.
        CFD(cf).bg = bg
        -- WoW Forever: the bronze message and input frames, on our panel.
        if ns.ChatForever() then ECHAT.FV_BuildPanel(cf, bg, GetEditBoxHeight()) end
    end

    -- Sidebar: icon panel beside the main chat frame. Parented to UIParent so it
    -- stays visible regardless of the active tab.
    if name == "ChatFrame1" and not CFD(cf).sidebar then
        -- Stock styles dress the sidebar as the stock chat button column
        -- (EllesmereUIChat_SidebarStock.lua); ECHAT.SB_KIT is nil otherwise.
        if ECHAT.SB_Latch then ECHAT.SB_Latch() end
        local sidebar = CreateFrame("Frame", nil, UIParent)
        sidebar:SetWidth(min(100, max(30, ECHAT.DB().sidebarWidth
            or (ECHAT.SidebarWidthDefault and ECHAT.SidebarWidthDefault() or 40))))
        sidebar:SetPoint("TOPRIGHT", CFD(cf).bg, "TOPLEFT", 0, 0)
        sidebar:SetPoint("BOTTOMRIGHT", CFD(cf).bg, "BOTTOMLEFT", 0, 0)
        -- Stock column: MEDIUM, as Blizzard's own column buttons and the stock
        -- panel (the chat frame's toplevel LOW art would draw over it).
        sidebar:SetFrameStrata(ECHAT.SB_KIT and "MEDIUM" or cf:GetFrameStrata())
        sidebar:SetFrameLevel(cf:GetFrameLevel() + 1)

        local sbBg = sidebar:CreateTexture(nil, "BACKGROUND")
        sbBg:SetAllPoints()
        sbBg:SetColorTexture(BG_R, BG_G, BG_B, ns.ChatStock() and 0 or BG_A)
        if ECHAT.SB_KIT and ECHAT.SB_KIT.backdrop then ECHAT.SB_BuildBackdrop(sidebar, CFD(cf)) end

        sidebar:EnableMouse(true)
        sidebar:SetScript("OnEnter", function()
            local cfg = ECHAT.DB()
            if cfg.sidebarVisibility == "mouseover" then
                -- Fade target MUST be set before the layout pass: the icon
                -- shown-state in ApplySidebarIcons reads it to decide whether
                -- the faded-out cutoff still applies.
                SetSidebarFadeTarget(1)
                if not _sidebarMouseoverLayoutVisible then
                    SetSidebarLayoutVisible(true)
                    if ECHAT.ApplyTabPadding then
                        ECHAT.ApplyTabPadding()
                    elseif ECHAT.ApplyExtendedBackground then
                        ECHAT.ApplyExtendedBackground()
                    end
                end
                if _sidebarFadeFrame then _sidebarFadeFrame:Show() end
            end
        end)
        sidebar:SetScript("OnLeave", function()
            local cfg = ECHAT.DB()
            if cfg.sidebarVisibility == "mouseover" then
                C_Timer.After(0, function()
                    local over = sidebar:IsMouseOver()
                    if issecretvalue and issecretvalue(over) then over = false end
                    if not over then
                        SetSidebarFadeTarget(0)
                        if _sidebarFadeFrame then _sidebarFadeFrame:Show() end
                    end
                end)
            end
        end)

        local onePx = (PP and PP.mult) or 1
        local sbDiv = sidebar:CreateTexture(nil, "OVERLAY", nil, 7)
        sbDiv._euiOwned = true
        sbDiv:SetWidth(onePx)
        sbDiv:SetColorTexture(GetInnerBorderColor(ECHAT.DB()))
        sbDiv:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
        sbDiv:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
        if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(sbDiv) end
        if ECHAT.BordersHidden(ECHAT.DB()) then sbDiv:Hide() end
        CFD(cf).sidebarDiv = sbDiv

        local MEDIA = "Interface\\AddOns\\EllesmereUIChat\\Media\\"
        local ICON_SIZE = 22
        local ICON_SPACING = 10
        local ICON_ALPHA = 0.4
        local ICON_HOVER_ALPHA = 0.9

        local function MakeSidebarIcon(parent, texPath, anchorTo, anchorPoint, yOff, key)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(ICON_SIZE, ICON_SIZE)
            if anchorTo then
                btn:SetPoint("TOP", anchorTo, "BOTTOM", 0, -ICON_SPACING)
            else
                btn:SetPoint(anchorPoint or "TOP", parent, anchorPoint or "TOP", 0, yOff or -ICON_SPACING)
            end
            local icon = btn:CreateTexture(nil, "ARTWORK")
            -- Stock styles: the kit dresses the button (no EllesmereUI tint,
            -- alpha or hover hooks).
            if ECHAT.SB_KIT and key then
                btn._icon = icon
                if key == "scroll" then ECHAT.SB_DressScroll(btn, "sidebar") else ECHAT.SB_Dress(btn, key) end
                return btn
            end
            icon:SetAllPoints()
            icon:SetTexture(texPath)
            icon:SetDesaturated(true)
            icon:SetVertexColor(1, 1, 1, ICON_ALPHA)
            btn:HookScript("OnEnter", function() icon:SetVertexColor(1, 1, 1, ICON_HOVER_ALPHA) end)
            btn:HookScript("OnLeave", function() icon:SetVertexColor(1, 1, 1, ICON_ALPHA) end)
            btn._icon = icon
            return btn
        end

        -- Visibility + ordering config is read once, at creation time.
        local icfg = ECHAT.DB()
        local showFriends    = icfg.showFriends ~= false
        local showGuild      = icfg.showGuild ~= false
        local showDurability = icfg.showDurability ~= false

        -- Extended background grows the sidebar upward by the tab-strip height,
        -- so chain-anchored icons shift up the same amount to keep the top gap.
        -- Skipped under free-move: those icons are user-positioned, not chained.
        local iconTopShift = (ECHAT.ExtendBgBehindTabs(icfg) and not icfg.freeMoveIcons) and GetTabAreaHeight() or 0

        -- Chain icons are created in the saved order (drag-to-reorder in the
        -- options dropdown; a new order takes effect on the next reload).
        local anchor = nil
        local friendsBtn, friendsCount, durabilityBtn, durabilityPct, copyBtn, portalBtn, voiceBtn, settingsBtn
        local guildBtn, guildCount, chatMenuBtn

        local function ChainAnchor(btn)
            btn:ClearAllPoints()
            if anchor then
                btn:SetPoint("TOP", anchor, "BOTTOM", 0, -ICON_SPACING)
            else
                btn:SetPoint("TOP", sidebar, "TOP", 0, -ICON_SPACING + iconTopShift)
            end
        end

        local function CreateFriendsIcon()
            friendsBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_friends.png", nil, nil, nil, "friends")
            friendsBtn:SetSize(26, 26)
            ChainAnchor(friendsBtn)

            if ECHAT.SB_KIT then
                friendsCount = ECHAT.SB_MakeCount(friendsBtn, sidebar, "friends")
            else
            friendsCount = sidebar:CreateFontString(nil, "OVERLAY")
            friendsCount:SetFont(GetFont(), 9, "")
            friendsCount:SetTextColor(1, 1, 1, 0.5)
            friendsCount:SetPoint("TOP", friendsBtn, "BOTTOM", 0, 7)
            end
            friendsCount:SetText("0")

            friendsBtn:HookScript("OnEnter", function(self)
                if not ECHAT.SB_KIT then friendsCount:SetTextColor(1, 1, 1, 0.9) end
                if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, "Friends") end
            end)
            friendsBtn:HookScript("OnLeave", function(self)
                if not ECHAT.SB_KIT then friendsCount:SetTextColor(1, 1, 1, 0.5) end
                HideSidebarIconTooltip(self)
            end)

            local fcLast
            local function UpdateFriendsCount()
                if InCombatLockdown() then
                    ns.CombatQueue.Defer(UpdateFriendsCount, UpdateFriendsCount)
                    return
                end
                local _, numOnline = BNGetNumFriends()
                local wowOnline = C_FriendList.GetNumOnlineFriends() or 0
                local total = numOnline + wowOnline
                if total ~= fcLast then
                    fcLast = total
                    friendsCount:SetText(total)
                end
            end

            local fcEvents = CreateFrame("Frame")
            fcEvents:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
            fcEvents:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
            fcEvents:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
            fcEvents:RegisterEvent("FRIENDLIST_UPDATE")
            fcEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            fcEvents:RegisterEvent("BN_CONNECTED")
            fcEvents:RegisterEvent("BN_DISCONNECTED")
            -- Recount inline on the exact edges -- the narrow account
            -- online/offline pair (the same field-proven set the DataBars
            -- micromenu count uses), NOT the BN_FRIEND_INFO_CHANGED presence
            -- firehose, so nothing fires between real login/logout edges.
            -- Two cached count reads plus one compare, no timers, and the
            -- label only rewrites when the number changed. In combat nothing
            -- recounts at all -- the count defers itself once to the combat
            -- queue and settles on the regen edge.
            fcEvents:SetScript("OnEvent", UpdateFriendsCount)

            CFD(cf).friendsCount = friendsCount
            -- A count inside its button (the stock QuickJoin plate) is not a
            -- tail: the chain hangs off the button.
            anchor = friendsBtn._sbTailInside and friendsBtn or friendsCount
        end

        local function CreateGuildIcon()
            guildBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_guild.png", nil, nil, nil, "guild")
            guildBtn:SetSize(26, 26)
            ChainAnchor(guildBtn)

            if ECHAT.SB_KIT then
                guildCount = ECHAT.SB_MakeCount(guildBtn, sidebar, "guild")
            else
            guildCount = sidebar:CreateFontString(nil, "OVERLAY")
            guildCount:SetFont(GetFont(), 9, "")
            guildCount:SetTextColor(1, 1, 1, 0.5)
            guildCount:SetPoint("TOP", guildBtn, "BOTTOM", 0, 7)
            end
            guildCount:SetText("0")

            guildBtn:HookScript("OnEnter", function(self)
                if not ECHAT.SB_KIT then guildCount:SetTextColor(1, 1, 1, 0.9) end
                if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, "Guild") end
            end)
            guildBtn:HookScript("OnLeave", function(self)
                if not ECHAT.SB_KIT then guildCount:SetTextColor(1, 1, 1, 0.5) end
                HideSidebarIconTooltip(self)
            end)

            -- Online guildmate count (GetNumGuildMembers 2nd return). The roster
            -- request MUST stay throttled: GuildRoster() itself fires
            -- GUILD_ROSTER_UPDATE, which re-enters this and loops.
            local lastRoster = 0
            local function UpdateGuildCount()
                if not IsInGuild() then guildCount:SetText(0); return end
                local now = GetTime()
                if not InCombatLockdown() and (now - lastRoster) >= 15 then
                    lastRoster = now
                    C_GuildInfo.GuildRoster()
                end
                local _, online = GetNumGuildMembers()
                guildCount:SetText(online)
            end

            local gcEvents = CreateFrame("Frame")
            gcEvents:RegisterEvent("GUILD_ROSTER_UPDATE")
            gcEvents:RegisterEvent("PLAYER_GUILD_UPDATE")
            gcEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            gcEvents:SetScript("OnEvent", UpdateGuildCount)

            CFD(cf).guildCount = guildCount
            anchor = guildCount
        end

        local function CreateDurabilityIcon()
            durabilityBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_durability.png", nil, nil, nil, "durability")
            ChainAnchor(durabilityBtn)

            if ECHAT.SB_KIT then
                durabilityPct = ECHAT.SB_MakeCount(durabilityBtn, sidebar, "durability")
            else
            durabilityPct = sidebar:CreateFontString(nil, "OVERLAY")
            durabilityPct:SetFont(GetFont(), 9, "")
            durabilityPct:SetTextColor(1, 1, 1, 0.5)
            durabilityPct:SetPoint("TOP", durabilityBtn, "BOTTOM", 0, 0)
            end
            durabilityPct:SetText("100%")

            durabilityBtn:HookScript("OnEnter", function(self)
                if not ECHAT.SB_KIT then durabilityPct:SetTextColor(1, 1, 1, 0.9) end
                if not self._freeMoveJustDragged then
                    ShowSidebarIconTooltip(self, "Equipment Durability")
                end
            end)
            durabilityBtn:HookScript("OnLeave", function(self)
                if not ECHAT.SB_KIT then durabilityPct:SetTextColor(1, 1, 1, 0.5) end
                HideSidebarIconTooltip(self)
            end)

            local lastDurText
            local function UpdateDurability()
                local lowest = 100
                for slot = 1, 18 do
                    local cur, mx = GetInventoryItemDurability(slot)
                    if cur and mx and mx > 0 then
                        local pct = (cur / mx) * 100
                        if pct < lowest then lowest = pct end
                    end
                end
                local txt = math.floor(lowest) .. "%"
                if txt ~= lastDurText then
                    lastDurText = txt
                    durabilityPct:SetText(txt)
                end
                -- Stock styles: the doll takes Blizzard's alert tint.
                if ECHAT.SB_KIT then ECHAT.SB_DurabilityAlert(durabilityBtn) end
            end

            -- Durability + alert events land together per damaged slot; one
            -- recount after the frame settles. Self-repair items fire only the
            -- alert event.
            local durPending = false
            local function FlushDurability()
                durPending = false
                UpdateDurability()
            end
            local durEvents = CreateFrame("Frame")
            durEvents:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
            durEvents:RegisterEvent("UPDATE_INVENTORY_ALERTS")
            durEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            durEvents:SetScript("OnEvent", function()
                if durPending then return end
                durPending = true
                C_Timer.After(0, FlushDurability)
            end)

            CFD(cf).durabilityPct = durabilityPct
            -- A percent inside its button is not a tail (as friends above).
            anchor = durabilityBtn._sbTailInside and durabilityBtn or durabilityPct
        end

        -- Friends/Guild/Durability have bespoke creators (count or percent text
        -- plus events); the rest are plain sidebar icons.
        local SPECIAL_CREATORS = {
            showFriends    = { show = showFriends,    create = CreateFriendsIcon },
            showGuild      = { show = showGuild,      create = CreateGuildIcon },
            showDurability = { show = showDurability, create = CreateDurabilityIcon },
        }
        local MIDDLE_DEFS = {
            showCopy     = { tex = "chat_copy.png", key = "copy" },
            showPortals  = { tex = "chat_portal.png", size = 26, key = "portals" },
            showVoice    = { tex = "chat_voice.png", key = "voice" },
            showChatMenu = { path = ECHAT.CHAT_MENU_GLYPH, key = "chatmenu" },
            showSettings = { tex = "chat_settings.png", key = "settings" },
        }
        local middleBtns = {}
        local chainOrder = ECHAT.ResolveSidebarIconOrder()
        -- Classic WoW UI dresses Chat Menu in Blizzard's chat bubble, which
        -- Settings wears otherwise (ECHAT.SB_Dress reads this before either
        -- button is made).
        ECHAT.SB_ChatMenuOn = icfg.showChatMenu ~= false and tContains(chainOrder, "showChatMenu") or nil
        for _, key in ipairs(chainOrder) do
            local special = SPECIAL_CREATORS[key]
            if special then
                if special.show then special.create() end
            else
                local def = MIDDLE_DEFS[key]
                if def and icfg[key] ~= false then
                    local btn = MakeSidebarIcon(sidebar, def.path or (MEDIA .. def.tex), nil, nil, nil, def.key)
                    if def.size then btn:SetSize(def.size, def.size) end
                    ChainAnchor(btn)
                    anchor = btn
                    middleBtns[key] = btn
                end
            end
        end
        copyBtn     = middleBtns["showCopy"]
        portalBtn   = middleBtns["showPortals"]
        voiceBtn    = middleBtns["showVoice"]
        chatMenuBtn = middleBtns["showChatMenu"]
        settingsBtn = middleBtns["showSettings"]

        -- Scroll is pinned to the sidebar bottom, outside the chain.
        local scrollBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_scroll2.png", nil, nil, nil, "scroll")
        scrollBtn:SetSize(22, 22)
        scrollBtn:ClearAllPoints()
        -- Stock column: its bottom-button slot, flush with the column's foot.
        scrollBtn:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, ECHAT.SB_KIT and 0 or ICON_SPACING)

        local function HookIconTooltip(btn, label)
            btn:HookScript("OnEnter", function(self)
                if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, label) end
            end)
            btn:HookScript("OnLeave", function(self)
                HideSidebarIconTooltip(self)
            end)
        end
        if copyBtn then HookIconTooltip(copyBtn, "Copy Chat") end
        if voiceBtn then HookIconTooltip(voiceBtn, "Voice/Channels") end
        if settingsBtn then HookIconTooltip(settingsBtn, "Settings") end
        HookIconTooltip(scrollBtn, "Scroll to Bottom")
        -- No click of ours: Blizzard's own button takes it (ECHAT.AttachChatMenu).
        if chatMenuBtn then
            HookIconTooltip(chatMenuBtn, "Chat Menu")
            ECHAT.AttachChatMenu(chatMenuBtn)
        end

        -- Scroll to bottom: acts on OUR message frame for the selected window.
        scrollBtn:SetScript("OnClick", function()
            local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
                and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
            if ECHAT.EngineScrollToBottom then
                ECHAT.EngineScrollToBottom(selected or ChatFrame1)
            end
        end)

        -- Copy chat history from the active tab (reads directly from the frame)
        if copyBtn then
        copyBtn:SetScript("OnClick", function()
            local fullText = ReadActiveChatText()
            if fullText == "" then fullText = "(No chat history)" end
            ShowCopyPopup(fullText)
        end)
        end

        if friendsBtn then
        friendsBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
                return
            end
            ToggleFriendsFrame()
        end)
        end

        if guildBtn then
        guildBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
                return
            end
            ToggleGuildFrame()
        end)
        end

        if portalBtn then
        portalBtn:SetScript("OnClick", function(self)
            if InCombatLockdown() then return end
            ECHAT.TogglePortalFlyout(self)
        end)
        HookIconTooltip(portalBtn, "M+ Portals")
        end

        if voiceBtn then
        voiceBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            ToggleChannelFrame()
        end)
        -- Blizzard Style: the headset while a voice channel is active.
        if ECHAT.SB_KIT and ECHAT.SB_KIT.voiceState then ECHAT.SB_WatchVoice(voiceBtn) end
        end

        if settingsBtn then
        settingsBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            local mf = EUI._mainFrame
            -- Folded to the mini window: fall through to ShowModule, which unfolds it.
            if mf and mf:IsShown() and not EUI._panelCollapsed and EUI:GetActiveModule() == "EllesmereUIChat" then
                mf:Hide()
            else
                EUI:ShowModule("EllesmereUIChat")
                -- Scroll the sidebar to the bottom so Chat is visible.
                C_Timer.After(0, function()
                    local sf = EUI._addonScrollFrame
                    if sf then
                        local max = sf:GetVerticalScrollRange() or 0
                        sf:SetVerticalScroll(max)
                        -- Poke the scroll child so OnScrollRangeChanged fires
                        -- and the thumb updates.
                        local sc = sf:GetScrollChild()
                        if sc then
                            local h = sc:GetHeight()
                            sc:SetHeight(h + 0.01)
                            sc:SetHeight(h)
                        end
                    end
                end)
            end
        end)
        end

        local sbd = CFD(cf)
        sbd.friendsBtn = friendsBtn
        sbd.guildBtn = guildBtn
        sbd.durabilityBtn = durabilityBtn
        sbd.copyBtn = copyBtn
        sbd.portalBtn = portalBtn
        sbd.voiceBtn = voiceBtn
        sbd.chatMenuBtn = chatMenuBtn
        sbd.settingsBtn = settingsBtn
        sbd.scrollBtn = scrollBtn
        -- Order snapshot for ApplySidebarIcons: live visibility toggles keep this
        -- session's layout; a changed saved order applies on reload.
        sbd._iconChainOrder = chainOrder
        -- Stock kit: sizes, pads and free-move heights stamped before the
        -- login chain lays the column out and captures free-move naturals.
        if ECHAT.SB_KIT then
            ECHAT.SB_ApplyScale(sbd, ECHAT.DB().sidebarIconScale or 1, true)
            if ECHAT.SB_FlashSync then ECHAT.SB_FlashSync() end
        end

        CFD(cf).sidebar = sidebar
    end

    -- Horizontal divider above the input field. The bg guard is load-bearing: a
    -- frame can reach here without a panel, and an unguarded index throws and
    -- aborts the rest of SkinChatFrame.
    if not CFD(cf).inputDiv and CFD(cf).bg then
        local onePx = (PP and PP.mult) or 1
        local div = CFD(cf).bg:CreateTexture(nil, "OVERLAY", nil, 7)
        div._euiOwned = true
        div:SetHeight(onePx)
        div:SetColorTexture(GetInnerBorderColor(ECHAT.DB()))
        div:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", -10, -8)
        div:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 10, -8)
        if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(div) end
        -- Stock styles: no divider (Blizzard's own input box is below the frame).
        if ns.ChatStock() then div:Hide() end
        CFD(cf).inputDiv = div
    end

    -- Font/shadow/fade, one-time at login. The Blizzard frame still gets the
    -- font: its invisible text layout must stay congruent with OUR visible
    -- copy so its hyperlink hit-zones sit under the same characters, and the
    -- hosted combat log renders through it.
    local cfId = cf:GetID()
    do
        -- Family over raw file (CJK members) -- same object the engine view
        -- uses, keeping both layouts congruent.
        local fam = ECHAT.EngineFontFamily
            and ECHAT.EngineFontFamily(cfId, GetFont(), GetFrameFontSize(cfId), GetOutlineFlag())
        if fam then
            cf:SetFontObject(fam)
        else
            cf:SetFont(GetFont(), GetFrameFontSize(cfId), GetOutlineFlag())
        end
    end
    if cf.SetShadowOffset then cf:SetShadowOffset(1, -1) end
    if cf.SetShadowColor then cf:SetShadowColor(0, 0, 0, 0.8) end
    cf:SetFading(false)
    -- Must match win.smf's SetIndentedWordWrap(true) (Engine.lua CreateWindowSMF):
    -- Blizzard's own hyperlink hit-zone positions for this frame are computed
    -- against ITS OWN indent setting, not just its text. Leaving this at the
    -- default (false) here while our visible copy indents wrapped lines desyncs
    -- every hyperlink hit-zone from the visible glyphs on that line -- root
    -- cause of player-name/channel-tag links (e.g. whispers, party chat)
    -- clicking several characters off from where the name is drawn.
    cf:SetIndentedWordWrap(true)

    -- 3. Hyperlink handlers: hover tooltip only. Blizzard's invisible text
    --    layer owns hyperlink hit-testing (its clicks run SetItemRef from
    --    ITS secure scripts; the global SetItemRef hook catches our URL
    --    links) and these hooks fire on hover. The engine's buffer
    --    write-back keeps that layer's zones laid out under our rendered
    --    text even for width-transformed lines.
    if not CFD(cf).hyperlinkHooked then
        CFD(cf).hyperlinkHooked = true
        cf:HookScript("OnHyperlinkEnter", function(...)
            OnHyperlinkEnter(...)
        end)
        cf:HookScript("OnHyperlinkLeave", function(...)
            OnHyperlinkLeave(...)
        end)
    end

    -- 4. Edit box
    SkinEditBox(cf)

    -- 5. Tabs are the owned strip's business now (EllesmereUIChat_Tabs.lua);
    --    nothing of Blizzard's tab is skinned or touched here.

    -- 6. Hide Blizzard's button frame -- ALPHA, NEVER SetParent. FCF_DockFrame
    -- calls FCF_SetButtonSide (ClearAllPoints+SetPoint on chatFrame.
    -- buttonFrame against chatFrame.Background) then FCF_SetLocked, whose
    -- `chatFrame.isLocked = ...` write is the field measured tainted. Parenting
    -- the button frame to ours would put Blizzard manipulating an insecure-owned frame
    -- mid-dock, tainting the rest of that dock -- that one field feeds both reported
    -- error classes: FCF_Tab_SetupMenu (tab menu) and FCF_UpdateResizeButton
    -- (temp-window open) both read it. On an undocked window FCF_FadeIn/OutChatFrame
    -- animate this frame's alpha every frame (to 1 on hover, 0.2 after), which no
    -- alpha assert outpaces, and a SetAlpha hook would run inside those fades and
    -- the dock pass. Blizzard never re-textures the frame or its minimize button, so
    -- their art is emptied once instead: the fades then have nothing to draw.
    local btnFrame = _G[name .. "ButtonFrame"]
    if btnFrame then
        btnFrame:SetAlpha(0)
        btnFrame:EnableMouse(false)
        -- Empty the border/background textures so btnFrame's own hover/undock
        -- alpha fades (0.2-1, never fully off) have nothing left to draw. The
        -- minimize button is left alone: a separate child object, Blizzard
        -- fades it in with btnFrame's alpha on hover the same as any other
        -- chat window, and its own alpha/mouse state were never touched here.
        local regions = { btnFrame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region:IsObjectType("Texture") then region:SetTexture("") end
        end
    end

    -- Restyle Blizzard's resize button to align with our bg (undocked-capable
    -- frames only; ChatFrame1 gets OUR grip below -- Blizzard never shows the
    -- main window's own button, and ApplyLockChatSize keeps it dead).
    local resizeBtn = cf ~= _G.ChatFrame1 and _G[name .. "ResizeButton"] or nil
    if resizeBtn then
        -- DEFERRED for the same reason panel placement is (PositionChatPanel):
        -- this runs from the skin pass, which fires while a temp whisper
        -- window is opening, and re-anchoring this button resolves geometry
        -- against the chat frame inside Blizzard's dock pass, tainting it.
        C_Timer.After(0, function()
            -- Stock styles keep Blizzard's own size grabber (art, anchor and
            -- alpha); only the follower arming below applies. WoW Forever
            -- strips Blizzard's frame art, so it takes ours.
            local stock = ns.ChatStockArt()
            if not stock then
            resizeBtn:SetSize(18, 18)
            resizeBtn:ClearAllPoints()
            -- Anchored to the CHAT FRAME, NEVER our panel: Blizzard anchors the chat
            -- frame's own ScrollBar to this button (FCF_UpdateScrollbarAnchors), so
            -- pointing it at our panel pulls an addon frame into Blizzard's chat layout
            -- chain (an anchor cycle) and Edit Mode can no longer commit a chat move --
            -- the drag releases unanchored and UpdateSystemAnchorInfo writes nil,
            -- leaving chat unmovable and unresizable.
            resizeBtn:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -2, 2)
            resizeBtn:SetFrameStrata("HIGH")
            if resizeBtn.GetRegions then
                local regions = { resizeBtn:GetRegions() }
                for ri = 1, #regions do
                    local region = regions[ri]
                    if region and region:IsObjectType("Texture") then
                        region:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png")
                        region:SetDesaturated(true)
                        region:SetVertexColor(1, 1, 1)
                        region:SetAllPoints()
                    end
                end
            end
            resizeBtn:SetAlpha(0.4)
            end -- not stock
            -- Arms the interaction follower: a resize drag starts and stays on
            -- this button, and the panel must follow it live.
            resizeBtn:HookScript("OnEnter", function(self)
                if not stock then self:SetAlpha(0.75) end
                if ECHAT.FollowArm then ECHAT.FollowArm() end
            end)
            resizeBtn:HookScript("OnLeave", function(self)
                if not stock then self:SetAlpha(0.4) end
                if ECHAT.FollowRelease then ECHAT.FollowRelease() end
            end)
        end)
    end

    -- Main chat: our grip is the sole resize surface (engine-driven sizing;
    -- see BuildMainChatResizeGrip for the hard constraints).
    if cf == _G.ChatFrame1 and ns._BuildMainChatResizeGrip then
        ns._BuildMainChatResizeGrip(cf)
    end

    -- Same class as the button frame above: FCF_UpdateScrollbarAnchors anchors
    -- Blizzard's own ScrollBar TO this button, and FCF_SetLocked reaches it via
    -- FCF_UpdateResizeButton during the dock. Alpha, NOT SetParent.
    if cf.ScrollToBottomButton then
        local sb = cf.ScrollToBottomButton
        sb:SetAlpha(0)
        sb:EnableMouse(false)
        -- Blizzard ANIMATES this button's alpha (UIFrameFadeIn to .65 on
        -- activity, SetAlpha(1) while its Flash texture is UIFrameFlashing),
        -- so no alpha assert can ever win. Hidden wins: their fade-in
        -- re-Shows it and this post-hook re-hides it in the same execution,
        -- before anything renders (the Prat button-hide shape).
        if not CFD(sb).hideHooked then
            CFD(sb).hideHooked = true
            sb:HookScript("OnShow", sb.Hide)
        end
        sb:Hide()
    end

    -- Strip ALL Blizzard textures from the chat frame. Texture objects only, and
    -- skips anything we created (marked with _euiOwned). The stock styles skip
    -- the strip: that art -- the chat background and border Blizzard's own
    -- hover fade animates -- IS their look (a pure skip, no new write). WoW
    -- Forever strips it (its bronze frames are ours).
    local stockArt = ns.ChatStockArt()
    if cf.GetRegions and not stockArt then
        local regions = { cf:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region:IsObjectType("Texture") and not region._euiOwned then
                region:SetTexture("")
                region:SetAtlas("")
                region:SetAlpha(0)
            end
        end
    end
    if cf.Background and not stockArt then
        cf.Background:SetAlpha(0)
        if cf.Background.GetRegions then
            local regions = { cf.Background:GetRegions() }
            for i = 1, #regions do
                local region = regions[i]
                if region and region:IsObjectType("Texture") then
                    region:SetAlpha(0)
                end
            end
        end
    end

    cf:SetHyperlinksEnabled(true)

    -- Combat Log: replace Blizzard's filter tab bar with a dark bar matching
    -- the chat panel's width and style (the stock styles keep Blizzard's bar).
    if name == "ChatFrame2" and not stockArt then
        local qbf = _G.CombatLogQuickButtonFrame_Custom
        if qbf and not CFD(qbf).skinned then
            CFD(qbf).skinned = true
            -- WoW Forever: the bar keeps Blizzard's seat, inside the kit's
            -- frame round the combat log (ApplyInputPosition), on its fill.
            local fv = ns.ChatForever()

            if qbf.GetRegions then
                local regions = { qbf:GetRegions() }
                for i = 1, #regions do
                    local region = regions[i]
                    if region and region:IsObjectType("Texture") then
                        region:SetAlpha(0)
                    end
                end
            end

            -- Flush: filter bar bottom meets bg top (cf top + 3), width matches
            -- the panel.
            if not fv then
            qbf:ClearAllPoints()
            qbf:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -10, 3)
            qbf:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 10, 3)
            qbf:SetHeight(24)

            local qbfBg = qbf:CreateTexture(nil, "BACKGROUND")
            qbfBg:SetAllPoints()
            qbfBg:SetColorTexture(BG_R, BG_G, BG_B, 1)
            end


            -- Bottom divider separating filter tabs from messages
            local onePx = (PP and PP.mult) or 1
            local qbfDiv = qbf:CreateTexture(nil, "OVERLAY", nil, 7)
            qbfDiv._euiOwned = true
            qbfDiv:SetHeight(onePx)
            qbfDiv:SetColorTexture(1, 1, 1, 0.06)
            qbfDiv:SetPoint("BOTTOMLEFT", qbf, "BOTTOMLEFT", 0, 0)
            qbfDiv:SetPoint("BOTTOMRIGHT", qbf, "BOTTOMRIGHT", 0, 0)
            if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(qbfDiv) end

            -- Restyle filter buttons; accent-color the active one.
            local EG = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
            local clFilterBtns = {}
            local function UpdateCLFilterColors()
                for _, btn in ipairs(clFilterBtns) do
                    local fs = btn:GetFontString()
                    if not fs then return end
                    local isActive = btn.GetChecked and btn:GetChecked()
                    if fv then
                        -- WoW Forever: the kit's gold and tan.
                        local c = isActive and ECHAT.FV.gold or ECHAT.FV.tan
                        fs:SetTextColor(c[1], c[2], c[3], isActive and 1 or 0.8)
                    elseif isActive then
                        local eg = EUI.ELLESMERE_GREEN or EG
                        fs:SetTextColor(eg.r, eg.g, eg.b, 1)
                    else
                        fs:SetTextColor(1, 1, 1, 0.5)
                    end
                end
            end
            if qbf.GetChildren then
                local children = { qbf:GetChildren() }
                for i = 1, #children do
                    local btn = children[i]
                    if btn and btn:IsObjectType("CheckButton") or (btn and btn:IsObjectType("Button")) then
                        clFilterBtns[#clFilterBtns + 1] = btn
                        if btn.GetRegions then
                            local regions = { btn:GetRegions() }
                            for j = 1, #regions do
                                local rgn = regions[j]
                                if rgn and rgn:IsObjectType("Texture") then
                                    rgn:SetAlpha(0)
                                end
                            end
                        end
                        local fs = btn:GetFontString()
                        if fs then
                            fs:SetFont(GetFont(), 12, "")
                        end
                        btn:HookScript("OnClick", UpdateCLFilterColors)
                    end
                end
            end
            UpdateCLFilterColors()
            EUI.RegAccent({ type = "callback", fn = UpdateCLFilterColors })

            -- One-time alpha set. NEVER hooksecurefunc SetAlpha here -- that
            -- taints execution during whisper/tab processing.
            qbf:SetAlpha(1)

            -- The chat bg is NOT extended upward: the filter bar has its own bg,
            -- and keeping both chat frame bgs the same size stops the visual
            -- jump when switching between General and Combat Log tabs.
        end
    end

    -- Blizzard's scrollbar (and its arrows) lives in the engine's hidden
    -- container; our windows carry their own thin scrollbar instead.
end

I.SkinChatFrame = SkinChatFrame
I.broken = false
