if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_Sidebar.lua
--
--  Sidebar side, icon colour, background and scale, free-moved icons, the
--  portal flyout, the input position and the sidebar width.
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
local HideSidebarIconTooltip = I.HideSidebarIconTooltip
local ShowSidebarIconTooltip = I.ShowSidebarIconTooltip

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local BG_R = I.BG_R
I.bgRSetters[#I.bgRSetters + 1] = function(v) BG_R = v end
local BG_G = I.BG_G
I.bgGSetters[#I.bgGSetters + 1] = function(v) BG_G = v end
local BG_B = I.BG_B
I.bgBSetters[#I.bgBSetters + 1] = function(v) BG_B = v end

-- Flip sidebar to left or right side of chat bg
function ECHAT.ApplySidebarPosition()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb or not CFD(cf1).bg then return end
    local PP = EllesmereUI and EllesmereUI.PP
    local onePx = (PP and PP.mult) or 1
    -- Separate Sidebar: detach from the panel by the configured gap; it keeps
    -- its own bg and gets its own panel-style border (ApplyExtendedBackground).
    local gap = (cfg.sidebarSeparate == true) and (cfg.sidebarSeparateSpacing or 8) or 0
    sb:ClearAllPoints()
    if ECHAT.SB_KIT then
        -- Stock styles: the stock chat button column's own seat.
        ECHAT.SB_Place(sb, CFD(cf1).bg, cfg)
    elseif cfg.sidebarRight then
        sb:SetPoint("TOPLEFT", CFD(cf1).bg, "TOPRIGHT", gap, 0)
        sb:SetPoint("BOTTOMLEFT", CFD(cf1).bg, "BOTTOMRIGHT", gap, 0)
    else
        sb:SetPoint("TOPRIGHT", CFD(cf1).bg, "TOPLEFT", -gap, 0)
        sb:SetPoint("BOTTOMRIGHT", CFD(cf1).bg, "BOTTOMLEFT", -gap, 0)
    end
    -- Divider to the correct edge; hidden in separate mode (it is the joint
    -- line between sidebar and panel).
    if CFD(cf1).sidebarDiv then
        CFD(cf1).sidebarDiv:ClearAllPoints()
        if cfg.sidebarRight then
            CFD(cf1).sidebarDiv:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
            CFD(cf1).sidebarDiv:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0)
        else
            CFD(cf1).sidebarDiv:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
            CFD(cf1).sidebarDiv:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
        end
        -- Hidden borders (the Hide Borders option, and always under the stock
        -- styles) take the divider too, whatever order the passes run in.
        CFD(cf1).sidebarDiv:SetShown(cfg.sidebarSeparate ~= true and not ECHAT.BordersHidden(cfg))
    end

    -- Re-place the behind-tabs divider continuation onto the new edge.
    if ECHAT.ApplyTabPadding then
        ECHAT.ApplyTabPadding()
    elseif ECHAT.ApplyExtendedBackground then
        ECHAT.ApplyExtendedBackground()
    end
end

-- Apply icon color to all sidebar icons
function ECHAT.ApplyIconColor()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end
    -- Stock kits keep their own art and states; the tooltips ride the hooks
    -- the buttons got at creation.
    if ECHAT.SB_KIT then return end
    local r, g, b
    if cfg.iconUseAccent and EllesmereUI.GetAccentColor then
        r, g, b = EllesmereUI.GetAccentColor()
    else
        r, g, b = cfg.iconR or 1, cfg.iconG or 1, cfg.iconB or 1
    end
    local ICON_ALPHA = 0.4
    local ICON_HOVER_ALPHA = 0.9
    local d = CFD(cf1)
    local ICON_LABELS = {
        friendsBtn = "Friends", guildBtn = "Guild", durabilityBtn = "Durability", copyBtn = "Copy Chat",
        portalBtn = "M+ Portals", voiceBtn = "Voice/Channels", chatMenuBtn = "Chat Menu", settingsBtn = "Settings",
        scrollBtn = "Scroll to Bottom",
    }
    local fc = d.friendsCount
    local gc = d.guildCount
    local dp = d.durabilityPct
    for _, key in ipairs({ "friendsBtn", "guildBtn", "durabilityBtn", "copyBtn", "portalBtn", "voiceBtn", "chatMenuBtn",
        "settingsBtn", "scrollBtn" }) do
        local btn = CFD(cf1)[key]
        if btn and btn._icon then
            btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
            local label = ICON_LABELS[key]
            if key == "friendsBtn" and fc then
                fc:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    fc:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, label) end
                end)
                btn:SetScript("OnLeave", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    fc:SetTextColor(r, g, b, 0.5)
                    HideSidebarIconTooltip(self)
                end)
            elseif key == "guildBtn" and gc then
                gc:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    gc:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, label) end
                end)
                btn:SetScript("OnLeave", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    gc:SetTextColor(r, g, b, 0.5)
                    HideSidebarIconTooltip(self)
                end)
            elseif key == "durabilityBtn" and dp then
                dp:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    dp:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, label) end
                end)
                btn:SetScript("OnLeave", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    dp:SetTextColor(r, g, b, 0.5)
                    HideSidebarIconTooltip(self)
                end)
            else
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, label) end
                end)
                btn:SetScript("OnLeave", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    HideSidebarIconTooltip(self)
                end)
            end
        end
    end
end

-- Hide/show the sidebar background texture
function ECHAT.ApplySidebarBackground()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end
    -- Stock styles: no sidebar backdrop (icons over Blizzard's own art).
    local show = not cfg.hideSidebarBg and not ns.ChatStock()
    local sbBg = sb:GetRegions()
    if sbBg and sbBg.SetShown then
        sbBg:SetShown(show)
    end
    if PP.GetBorders(sb) then
        PP.GetBorders(sb):SetShown(show)
    end
    -- Blizzard Style: the stock column backdrop follows Hide Sidebar Background.
    local bd = CFD(cf1).sbBackdrop
    if bd then
        bd:SetShown(not cfg.hideSidebarBg)
        if not cfg.hideSidebarBg and ECHAT.SB_SyncBackdrop then ECHAT.SB_SyncBackdrop(true) end
    end
    -- Hide the sidebar extension too when the sidebar background is hidden.
    if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
end

-- Scale sidebar icon buttons and friends count text
function ECHAT.ApplySidebarIconScale()
    local cfg = ECHAT.DB()
    local scale = cfg.sidebarIconScale or 1.0
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end
    -- Stock kits size from their own art (a memo no-op at login and refresh).
    if ECHAT.SB_KIT then ECHAT.SB_ApplyScale(CFD(cf1), scale); return end

    local BASE_FRIEND = 26
    local BASE_ICON = 22
    local BASE_FONT = 9

    -- _freeMoveH mirrors each icon's height from these constants so
    -- TopYFromSidebarTop never calls GetHeight() -- a geometry resolve that
    -- can taint the Edit-Mode ChatFrame1. Our own frames, so writing is safe.
    for _, key in ipairs({ "durabilityBtn", "copyBtn", "portalBtn", "voiceBtn", "chatMenuBtn", "settingsBtn", "scrollBtn" }) do
        local btn = CFD(cf1)[key]
        if btn then
            btn:SetSize(BASE_ICON * scale, BASE_ICON * scale)
            btn._freeMoveH = BASE_ICON * scale
        end
    end
    if CFD(cf1).friendsBtn then
        CFD(cf1).friendsBtn:SetSize(BASE_FRIEND * scale, BASE_FRIEND * scale)
        CFD(cf1).friendsBtn._freeMoveH = BASE_FRIEND * scale
    end
    if CFD(cf1).friendsCount then
        CFD(cf1).friendsCount:SetFont(GetFont(), max(7, BASE_FONT * scale), "")
        CFD(cf1).friendsCount._freeMoveH = max(7, BASE_FONT * scale)
    end

    if CFD(cf1).guildBtn then
        CFD(cf1).guildBtn:SetSize(BASE_FRIEND * scale, BASE_FRIEND * scale)
        CFD(cf1).guildBtn._freeMoveH = BASE_FRIEND * scale
    end
    if CFD(cf1).guildCount then
        CFD(cf1).guildCount:SetFont(GetFont(), max(7, BASE_FONT * scale), "")
        CFD(cf1).guildCount._freeMoveH = max(7, BASE_FONT * scale)
    end

    if CFD(cf1).durabilityPct then
        CFD(cf1).durabilityPct:SetFont(GetFont(), max(7, BASE_FONT * scale), "")
        CFD(cf1).durabilityPct._freeMoveH = max(7, BASE_FONT * scale)
    end
end

-- Free move: shift+drag sidebar icons to custom positions
local _freeMoveIconHooked = {}

local function GetIconOffset(key)
    local cfg = ECHAT.DB()
    if not cfg.freeMoveIcons or not cfg.iconPositions then return 0, 0 end
    local pos = cfg.iconPositions[key]
    if not pos then return 0, 0 end
    return pos.x or 0, pos.y or 0
end

local function SaveIconOffset(key, x, y)
    local cfg = ECHAT.DB()
    if not cfg.iconPositions then cfg.iconPositions = {} end
    cfg.iconPositions[key] = { x = x, y = y }
end

-- Y offset of `frame`'s TOP edge below the SIDEBAR's TOP edge, from GetPoint (stored
-- anchor data, no resolve) plus each frame's STORED height (_freeMoveH, from
-- ApplySidebarIconScale's size constants). CRITICAL: NEVER call
-- GetHeight/GetWidth/GetCenter or any other geometry- RESOLVING getter here -- they
-- walk the anchor chain icon -> sidebar -> chat bg -> ChatFrame1, and ChatFrame1 is
-- Edit-Mode-secured, so resolving its layout from insecure code TAINTS it (intermittent
-- HistoryKeeper/FCFManager whisper errors, only when geometry was still unresolved at
-- walk time, e.g. login timing). The pre-stored _freeMoveH avoids the resolve entirely.
local function TopYFromSidebarTop(frame, sb, depth)
    if frame == sb or (depth or 0) > 12 then return 0 end
    local point, relTo, relPoint, _, dy = frame:GetPoint(1)
    if not point or not relTo then return 0 end
    local relTopY = TopYFromSidebarTop(relTo, sb, (depth or 0) + 1)
    local relH = (relTo ~= sb) and (relTo._freeMoveH or 0) or 0
    local relEdgeY = relTopY
    if relPoint and relPoint:find("BOTTOM") then
        relEdgeY = relTopY - relH
    elseif relPoint == "CENTER" or relPoint == "LEFT" or relPoint == "RIGHT" then
        relEdgeY = relTopY - relH / 2
    end
    local edgeY = relEdgeY + (dy or 0)
    if point:find("TOP") then return edgeY end
    if point:find("BOTTOM") then return edgeY + (frame._freeMoveH or 0) end
    return edgeY + (frame._freeMoveH or 0) / 2
end

-- Capture each icon's natural sidebar-EDGE offset (TOP/BOTTOM) once, so
-- re-applies never read live geometry and offsets never compound.
local function CaptureNatural(btn, sb)
    -- Stock sidebar kits: a hidden icon was never laid out by the kit's
    -- chain (a hidden sidebar skips re-anchoring), so its anchors are still
    -- the build-time ones; the pass that first shows it captures from the
    -- real layout. The EllesmereUI look captures as it always has (saved
    -- offsets are relative to that baseline).
    if btn._freeMoveNat or (ECHAT.SB_KIT and not btn:IsShown()) then return end
    local point = btn:GetPoint(1)
    if not point then return end
    if point:find("BOTTOM") then
        local _, _, _, _, dy = btn:GetPoint(1)
        btn._freeMoveNat = { edge = "BOTTOM", y = dy or 0 }
    else
        btn._freeMoveNat = { edge = "TOP", y = TopYFromSidebarTop(btn, sb, 0) }
    end
end

-- Re-anchor an icon DIRECTLY to its sidebar edge at natural + saved offset, so
-- each icon moves independently (no chain, no compounding).
local function ApplyIconOffset(btn, sb)
    if not btn or not sb or not btn:IsShown() then return end
    local nat = btn._freeMoveNat
    if not nat then return end
    local ox, oy = GetIconOffset(btn._freeMoveKey)
    btn:ClearAllPoints()
    btn:SetPoint(nat.edge, sb, nat.edge, ox, nat.y + oy)
end

local function EnableIconFreeMove(btn)
    if not btn or _freeMoveIconHooked[btn] then return end
    _freeMoveIconHooked[btn] = true

    local key = btn._freeMoveKey
    if not key then return end

    btn:SetMovable(true)
    btn:SetClampedToScreen(true)

    local origClick = btn:GetScript("OnClick")
    if origClick then
        btn:SetScript("OnClick", function(self, ...)
            if self._freeMoveJustDragged then return end
            origClick(self, ...)
        end)
    end

    local startX, startY, baseOX, baseOY

    -- Drag re-anchors to the icon's own sidebar edge at natural + (offset+delta).
    -- GetEffectiveScale walks the PARENT chain (button->sidebar->UIParent), not
    -- the anchor chain to ChatFrame1, so it is taint-safe; GetParent() == sidebar.
    local function FreeMoveOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then
            self:SetScript("OnUpdate", nil)
            C_Timer.After(0, function() self._freeMoveJustDragged = nil end)
            return
        end
        local nat = self._freeMoveNat
        if not nat then return end
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local nx = baseOX + (cx / es - startX)
        local ny = baseOY + (cy / es - startY)
        self:ClearAllPoints()
        self:SetPoint(nat.edge, self:GetParent(), nat.edge, nx, nat.y + ny)
        SaveIconOffset(key, nx, ny)
    end

    btn:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not IsShiftKeyDown() then return end
        local cfg = ECHAT.DB()
        if not cfg.freeMoveIcons or not self._freeMoveNat then return end
        self._freeMoveJustDragged = true
        local es = self:GetEffectiveScale()
        startX, startY = GetCursorPosition()
        startX, startY = startX / es, startY / es
        baseOX, baseOY = GetIconOffset(key)
        self:SetScript("OnUpdate", FreeMoveOnUpdate)
    end)

    btn:HookScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        C_Timer.After(0, function() self._freeMoveJustDragged = nil end)
    end)
end

function ECHAT.ApplyIconFreeMove()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end

    -- Free move is opt-in: OFF does NOTHING here -- no anchor-chain capture, no
    -- drag-hook install, no offsets. This gate is required: CaptureNatural walks the
    -- icon anchor chain, and for users whose chat geometry is still unresolved at
    -- login, that walk resolves up through and TAINTS the Edit-Mode ChatFrame1. Turning
    -- the toggle on re-runs ApplySidebarIcons -> ApplyIconFreeMove, installing hooks
    -- immediately; untouched icons keep their natural chain layout.
    if not cfg.freeMoveIcons then return end

    local btns = {
        { ref = "friendsBtn",    key = "friends" },
        { ref = "guildBtn",      key = "guild" },
        { ref = "durabilityBtn", key = "durability" },
        { ref = "copyBtn",       key = "copy" },
        { ref = "portalBtn",     key = "portals" },
        { ref = "voiceBtn",      key = "voice" },
        { ref = "chatMenuBtn",   key = "chatmenu" },
        { ref = "settingsBtn",   key = "settings" },
        { ref = "scrollBtn",     key = "scroll" },
    }

    -- PHASE 1 -- capture every icon's natural anchor (GetPoint data + stored heights,
    -- never a geometry-resolving getter; see TopYFromSidebarTop) and install drag
    -- hooks. MUST complete for ALL icons before Phase 2's re-anchoring: interleaving
    -- would let a later icon's chain-walk read an earlier icon's already-applied offset
    -- and bake it into its "natural" position -- drift on every reload.
    for _, info in ipairs(btns) do
        local btn = CFD(cf1)[info.ref]
        -- The chat-anchored scroll button is outside the sidebar chain; free
        -- move must not capture or re-anchor it.
        if info.ref == "scrollBtn" and cfg.scrollButtonOnChat then btn = nil end
        if btn then
            btn._freeMoveKey = info.key
            CaptureNatural(btn, sb)
            EnableIconFreeMove(btn)
        end
    end

    -- PHASE 2 -- re-anchor each icon to its sidebar edge at natural + saved
    -- offset, so icons move independently.
    for _, info in ipairs(btns) do
        local btn = CFD(cf1)[info.ref]
        if info.ref == "scrollBtn" and cfg.scrollButtonOnChat then btn = nil end
        if btn then ApplyIconOffset(btn, sb) end
    end
end

-- Portal flyout: EllesmereUI.CreatePortalFlyout, built on first open.
local _portalFlyout

function ECHAT.TogglePortalFlyout(anchorBtn)
    if InCombatLockdown() then return end
    if not _portalFlyout then
        _portalFlyout = EUI.CreatePortalFlyout({
            -- unitEvents: the cast events it watches only ever matter for the player.
            name = "EUIChat", bg = { BG_R, BG_G, BG_B }, labelFont = GetFont(), unitEvents = true,
            labelFlags = (EUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG",
        })
    end
    local flyout = _portalFlyout
    -- Visibility, not the shown flag: leaving the house editor hides our host
    -- out from under a flyout that is still flagged shown, and a stale flag
    -- would eat the next click.
    if flyout:IsVisible() then
        flyout:Hide()
    else
        -- Absolute screen position: a protected frame cannot anchor to a
        -- non-secure region.
        local bs = anchorBtn:GetEffectiveScale()
        local fs = flyout:GetEffectiveScale()
        local bTop = anchorBtn:GetTop() * bs
        local cfg = ECHAT.DB()
        flyout:ClearAllPoints()
        if cfg.sidebarRight then
            local bLeft = anchorBtn:GetLeft() * bs
            flyout:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fs, (bTop + 4) / fs)
        else
            local bRight = anchorBtn:GetRight() * bs
            flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bRight + 4) / fs, (bTop + 4) / fs)
        end
        ECHAT.HostPopup(flyout)
        flyout:Show()
    end
end

-- How far below the chat frame's top edge the overlaid input sits. Keeps the
-- box's vertically-centered text off the tab band at small editBoxHeight
-- values (the box grows downward from a fixed top anchor, so shrinking it
-- otherwise walks the text up toward a flush top edge). THREE places consume
-- it and must agree or the parts separate: the edit box anchor, the reserved
-- strip height, and the divider that marks the box's lower edge.
local INPUT_TOP_DROP = 5

-- Input-on-top overlays the top strip of the text area, and OUR message frame
-- hands that strip back (_smfTopExtra) so no line renders under the input.
-- Reserving it permanently costs a line of chat even while nothing is being
-- typed -- the strip sits empty and the topmost message is clipped -- so the
-- reservation follows the edit box's SHOWN state on the permanent frames 1-10,
-- whose edit boxes may be script-hooked. Temp windows (11+) must never be
-- hooked (see SkinEditBox's taint note) and keep the static reservation.
-- The box overlaying a window is NOT always that window's own. Blizzard's
-- DEFAULT chatStyle ("classic") routes every window's input through
-- DEFAULT_CHAT_FRAME's box -- ChatFrameUtil.ChooseBoxForSend returns
-- DEFAULT_CHAT_FRAME.editBox outright in that mode, before it ever looks at
-- the preferred frame -- so on any tab but the first, ChatFrame1EditBox is
-- what appears over the text while that tab's OWN edit box stays hidden.
-- Keying the strip off cf's own box therefore leaves every other tab unmasked
-- and reserves a strip on ChatFrame1's hidden window instead. Docked windows
-- share one rect, so a box shown on any docked frame is drawn over whichever
-- docked frame is currently visible.
local function DockedEditBoxShown()
    for i = 1, 10 do
        local owner = _G["ChatFrame" .. i]
        local box = owner and _G["ChatFrame" .. i .. "EditBox"]
        if box and box:IsShown() and owner.isDocked then return true end
    end
    return false
end

function ECHAT.InputTopStripActive(cf)
    if not ECHAT.InputOnTop(ECHAT.DB()) then return false end
    local name = cf:GetName()
    local eb = name and _G[name .. "EditBox"]
    if not eb then return false end
    local idx = tonumber(name:match("ChatFrame(%d+)"))
    if not (idx and idx <= 10) then return true end
    -- Own box up: "im" style, and any undocked window, keep the old rule.
    if eb:IsShown() then return true end
    return (cf.isDocked and cf:IsShown() and DockedEditBoxShown()) and true or false
end

-- Every managed frame, not just one: the box that showed belongs to ChatFrame1
-- while the strip is owed to the selected tab (see InputTopStripActive), so a
-- single-frame re-derive off the edit box hooks updates the wrong window.
function ECHAT.RefreshInputTopStrips()
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and CFD(cf).bg then ECHAT.ApplyInputTopStrip(cf) end
    end
end

-- Re-derive one frame's reserved strip. Only the text area moves: the panel
-- rect stays put (input-on-top never changed _bgIns), so nothing outside our
-- message frame is touched. The divider marks the input's edge and would cut
-- across a message once the strip is released, so it follows the same state.
function ECHAT.ApplyInputTopStrip(cf)
    local d = CFD(cf)
    if not d.bg then return end
    local cfg = ECHAT.DB()
    local active = ECHAT.InputTopStripActive(cf)
    -- The strip reaches INPUT_TOP_DROP further than the box is tall, since the
    -- box starts that far down from cf's top edge.
    local want = active and (GetEditBoxHeight() + 4 + INPUT_TOP_DROP) or nil
    local changed = d._smfTopExtra ~= want
    d._smfTopExtra = want
    -- The `not cfg.inputOnTop` arm is load-bearing, not redundant: bottom mode
    -- leaves the divider to ApplyBorders, and the toggle-off pass reaches here
    -- without ever calling it -- dropping the arm strands the divider hidden.
    if d.inputDiv then
        d.inputDiv:SetShown(not ECHAT.BordersHidden(cfg) and (not ECHAT.InputOnTop(cfg) or active))
    end
    if changed and ECHAT.EngineLayoutWindow then ECHAT.EngineLayoutWindow(cf) end
end

-- Flip edit box between bottom (default) and top of chat panel
function ECHAT.ApplyInputPosition()
    local cfg = ECHAT.DB()
    local onTop = ECHAT.InputOnTop(cfg)
    local inputHeight = GetEditBoxHeight()
    -- Stock styles: Blizzard's own input box keeps Blizzard's own height and
    -- anchor shape (SeatStockBackground only moves it sideways with the
    -- background, on the permanent windows), and the panel -- which carries no
    -- paint there, only the sidebar's anchor -- spans the revealed frame art
    -- out to its border (the background re-seated STOCK_BG_X past each side,
    -- +3 above and -6 below, then 4px corners; see SeatStockBackground), so
    -- the sidebar sits flush against Blizzard's border.
    local stock = ns.ChatStock()
    local stockX = ECHAT.STOCK_BG_X + 4
    -- WoW Forever: our input box in its own bronze frame under the message
    -- frame (EllesmereUIChat_Forever.lua records the panel insets).
    local fv = ns.ChatForever()

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and CFD(cf).bg then
            local name = cf:GetName()
            if not name then break end
            local eb = _G[name .. "EditBox"]
            local bg = CFD(cf).bg
            local div = CFD(cf).inputDiv

            if fv then
                ECHAT.FV_SeatInput(cf, eb, inputHeight)
                ECHAT.ApplyInputTopStrip(cf)
                if ECHAT.PositionChatPanel then ECHAT.PositionChatPanel(cf) end
            elseif stock then
                CFD(cf)._bgIns = { l = -stockX, r = stockX, t = 7, b = -10 }
                ECHAT.ApplyInputTopStrip(cf)
                if ECHAT.PositionChatPanel then ECHAT.PositionChatPanel(cf) end
            else
            if eb then
                eb:ClearAllPoints()
                if onTop then
                    -- Below the tab band, INSIDE the panel: the input
                    -- overlays the top strip of the text area (the space
                    -- above the frame is the tab band's home, and tab
                    -- geometry is Blizzard's -- never moved for us). Our
                    -- message frame hands the strip back via _smfTopExtra;
                    -- line alignment with Blizzard's invisible text is
                    -- unaffected because chat renders bottom-up from a
                    -- shared bottom edge, and the input covers the
                    -- hit-zones of the lines it hides.
                    eb:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, -INPUT_TOP_DROP)
                    eb:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -INPUT_TOP_DROP)
                    local bgLvl = CFD(cf).bg:GetFrameLevel() or 1
                    if eb:GetFrameLevel() < bgLvl + 5 then
                        eb:SetFrameLevel(bgLvl + 5)
                    end
                else
                    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -10, -8)
                    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -8)
                end
                eb:SetHeight(inputHeight)
            end

            if div then
                div:ClearAllPoints()
                if onTop then
                    -- Flush with the box's LOWER edge, which starts
                    -- INPUT_TOP_DROP down from cf's top and runs inputHeight
                    -- tall -- miss the drop and the line cuts through the box.
                    local divY = -(inputHeight + INPUT_TOP_DROP)
                    div:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, divY)
                    div:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 10, divY)
                else
                    div:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", -10, -8)
                    div:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 10, -8)
                end
            end

            if bg then
                -- The panel is placed NUMERICALLY, never anchored to cf (see
                -- PositionChatPanel): record the insets this input layout wants
                -- and let the positioner apply them against the chat frame's
                -- rect. Anchoring here would put our frame back into
                -- Blizzard's rect chain -- the whole bug. Only the vertical
                -- edge may expand; horizontal geometry stays independent.
                local d = CFD(cf)
                d._bgIns = {
                    l = -10,
                    r = 10,
                    t = 3,
                    b = onTop and -6 or (eb and -(12 + inputHeight) or -6),
                }
                -- Input-on-top: the panel keeps its normal rect; only OUR
                -- message frame's text area shrinks under the overlaid input,
                -- and only while that input is actually up (see
                -- ECHAT.ApplyInputTopStrip). EngineLayoutWindows at the tail
                -- of this function relayouts every window either way.
                ECHAT.ApplyInputTopStrip(cf)
                if ECHAT.PositionChatPanel then ECHAT.PositionChatPanel(cf) end
            end
            end -- not stock

        end
    end
    -- Our message frames derive their text area from the recorded insets.
    if ECHAT.EngineLayoutWindows then ECHAT.EngineLayoutWindows() end
end

function ECHAT.ApplySidebarWidth()
    local cf1 = _G.ChatFrame1
    local sidebar = cf1 and CFD(cf1).sidebar
    if not sidebar then return end
    sidebar:SetWidth(min(100, max(30, ECHAT.DB().sidebarWidth
        or (ECHAT.SidebarWidthDefault and ECHAT.SidebarWidthDefault() or 40))))
    if ECHAT.ApplySidebarPosition then ECHAT.ApplySidebarPosition() end
end

I.broken = false
