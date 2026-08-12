if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIChat_Tabs.lua
--
--  Ghost tab visuals over Blizzard's REAL tab strip.
--
--  Blizzard's tabs stay fully alive as the interaction plane: every click,
--  drag-reorder, context menu action (rename, font size, new window, close),
--  and the whole temp-whisper lifecycle is a hardware event on a Blizzard
--  frame, so every dock/selection write stays SECURE. This module never
--  selects, closes, creates, renames, or reorders a window from Lua -- an
--  insecure FCFDock_SelectWindow call taints dock.selected/isDirty, and the
--  secure whisper-window creation chain reads those slots (FCF_DockUpdate ->
--  FCFDock_UpdateTabs) and then dies on secret header math in UpdateHeader.
--  Field-measured via taintLog 2; do not reintroduce ANY management call.
--
--  The stock strip is invisible but clickable: GeneralDockManager:SetAlpha(0)
--  -- alpha does not disable mouse input, the slot is written by nothing in
--  Blizzard code (field-proven by the old skin's dock fade), and per-tab
--  alphas (which FCFTab_UpdateAlpha rewrites constantly) multiply against it
--  to zero. ZERO writes of any kind go to the tabs themselves: no texture
--  strips, no text recolors, no anchors, no children, no fields.
--
--  Our pixels live on GHOSTS: mouse-disabled frames anchored TO each tab
--  (anchor-only, the sanctioned shape -- never parented to them). Anchors
--  resolve in the same render pass, so ghosts track Blizzard's layout
--  pixel-for-pixel with no one-frame lag, including mid-drag, and we never
--  measure a tab or a (possibly secret) label. Ghost text is display-only:
--  SetText accepts secrets; the fontstring is edge-anchored so long names
--  ellipsis-truncate instead of being measured.
--
--  Undocked windows and minimized pills keep their stock Blizzard tabs
--  visible and functional (native drag-to-redock, native menus); only the
--  docked strip is ghosted.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

local ECHAT = ns.ECHAT
if not ECHAT then return end

local CFD = EUI._chatCFD
if not CFD then return end

local issecretvalue = _G.issecretvalue

local function DB()
    return ECHAT.DB()
end

local function TabHeight()
    return DB().tabHeight or 24
end

local function TabFontPath()
    local cfg = DB()
    local fontKey = cfg.tabFont or "__global"
    if fontKey == "__global" then
        return (EUI.GetFontPath and EUI.GetFontPath("chat")) or STANDARD_TEXT_FONT
    end
    return (EUI.ResolveFontName and EUI.ResolveFontName(fontKey)) or STANDARD_TEXT_FONT
end

-- Resolve a color table honoring the shared custom/accent/class mode keys.
local function ResolveModeColor(mode, stored, fallback)
    if mode == "accent" and EUI.GetAccentColor then
        local r, g, b = EUI.GetAccentColor()
        return r, g, b, (stored and stored.a) or fallback.a or 1
    end
    if mode == "class" then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b, (stored and stored.a) or fallback.a or 1 end
    end
    local c = stored or fallback
    local a = c.a
    if a == nil then a = fallback.a end
    if a == nil then a = 1 end
    return c.r or 1, c.g or 1, c.b or 1, a
end

local function SelectedWindow()
    return GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
end

-------------------------------------------------------------------------------
--  Strip: a pure visual layer mirroring the dock manager's rect. It hosts the
--  ghosts (clipping them exactly where Blizzard clips scrolled-out tabs),
--  carries the module fade via _ApplyAlpha, and arms the interaction follower
--  through motion-only mouse flags -- clicks pass through to the real tabs.
-------------------------------------------------------------------------------
local strip = CreateFrame("Frame", nil, UIParent)
strip:SetFrameStrata("MEDIUM")
-- Level 100, like the old tab hosts: the panel border frame occupies MEDIUM
-- levels 96-98 across this exact band and must never draw over the tabs.
strip:SetFrameLevel(100)
strip:SetClipsChildren(true)
if strip.SetMouseClickEnabled then
    strip:SetMouseClickEnabled(false)
    strip:SetMouseMotionEnabled(true)
    -- A motion-enabled frame still participates in click hit-testing and
    -- would swallow clicks meant for the (invisible) tabs beneath; propagate
    -- sends them through. Field-measured: without this, only the sliver of
    -- tab above the strip's rect was clickable.
    if strip.SetPropagateMouseClicks then
        strip:SetPropagateMouseClicks(true)
    end
    -- Motion propagates too: the tab under the cursor must keep receiving
    -- OnEnter/OnLeave (stock tab tooltip). Field-measured: without this the
    -- tooltip died the moment the cursor crossed into the strip's rect.
    if strip.SetPropagateMouseMotion then
        strip:SetPropagateMouseMotion(true)
    end
else
    strip:EnableMouse(false)
end
strip:SetScript("OnEnter", function()
    if ECHAT.FollowArm then ECHAT.FollowArm() end
    -- The strip sits above the idle-fade peek overlay and captures motion
    -- over the tab band; hovering the tabs counts as chat interaction.
    if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
end)
strip:SetScript("OnLeave", function()
    if ECHAT.FollowRelease then ECHAT.FollowRelease() end
end)
strip:Hide()
ns._chatTabStrip = strip

local ghosts = {}      -- pooled ghost frames, index = dock display order
local floatGhosts = {} -- per-window-id ghosts for undocked windows
local floatSeen = {}   -- wiped scratch set for the float surplus sweep

-- Dynamic (whisper) tabs live inside the dock's scroll window: on overflow
-- Blizzard SCROLLS them left and the scroll frame clips them at its left
-- edge (which sits at the last static tab's right edge). Their ghosts must
-- clip at exactly the same edge, or a scrolled-out ghost renders on top of
-- the static tabs. This sub-container mirrors the scroll frame's horizontal
-- bounds with the strip's vertical bounds, live-anchored, so ghost clipping
-- tracks Blizzard's -- including partial clips during the scroll animation.
local dynClip = CreateFrame("Frame", nil, strip)
dynClip:SetClipsChildren(true)
dynClip:EnableMouse(false)
local dynClipAnchored = false
local function EnsureDynClip()
    if dynClipAnchored then return true end
    local dock = _G.GENERAL_CHAT_DOCK
    local sf = dock and dock.scrollFrame
    if not sf then return false end
    dynClip:SetPoint("TOP", strip, "TOP", 0, 0)
    dynClip:SetPoint("BOTTOM", strip, "BOTTOM", 0, 0)
    dynClip:SetPoint("LEFT", sf, "LEFT", 0, 0)
    dynClip:SetPoint("RIGHT", sf, "RIGHT", 0, 0)
    dynClipAnchored = true
    return true
end

local RequestRefresh -- forward declaration

-------------------------------------------------------------------------------
--  Ghost pool
-------------------------------------------------------------------------------
local function BuildGhost()
    local g = CreateFrame("Frame", nil, strip)
    g:EnableMouse(false)

    local bg = g:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    g._bg = bg

    local fs = g:CreateFontString(nil, "OVERLAY")
    -- Edge-anchored: the label is clamped to the ghost's (= tab's) width and
    -- ellipsis-truncates. Nothing is ever measured -- widths are Blizzard's,
    -- and whisper labels can be SECRET values.
    fs:SetWordWrap(false)
    fs:SetJustifyH("CENTER")
    -- A bare fontstring has NO font: SetText before a SetFont is a hard error.
    fs:SetFont(TabFontPath(), DB().tabFontSize or 11, "")
    g._fs = fs

    local PP = EUI.PP
    local onePx = (PP and PP.mult) or 1

    local underline = g:CreateTexture(nil, "OVERLAY", nil, 7)
    underline:SetHeight(onePx)
    underline:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
    underline:Hide()
    if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(underline) end
    g._underline = underline

    local sep = g:CreateTexture(nil, "OVERLAY", nil, 7)
    sep:SetWidth(onePx)
    sep:SetPoint("TOPLEFT", g, "TOPRIGHT", 0, 0)
    sep:SetPoint("BOTTOMLEFT", g, "BOTTOMRIGHT", 0, 0)
    sep:Hide()
    if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(sep) end
    g._sep = sep

    local borderHost = CreateFrame("Frame", nil, g)
    borderHost:SetAllPoints()
    borderHost:EnableMouse(false)
    g._borderHost = borderHost

    -- Whisper alert: Blizzard's own art and cadence. Stock breathes the
    -- tab.glow texture (ChatFrameTab-NewMessage, ADD blend) via
    -- UIFrameFlash(1s in, 1s out, infinite); this is a copy on OUR texture
    -- driven by OUR AnimationGroup -- never their region (their flash
    -- machinery writes it) and never UIFrameFlash (shared registry).
    local glow = g:CreateTexture(nil, "OVERLAY", nil, 6)
    glow:SetTexture("Interface\\ChatFrame\\ChatFrameTab-NewMessage")
    glow:SetBlendMode("ADD")
    -- Desaturated so StyleGhost's vertex color tints it cleanly to the
    -- tab's text color instead of multiplying against the orange art.
    glow:SetDesaturated(true)
    glow:SetPoint("TOPLEFT", g, "TOPLEFT", 8, -11)
    glow:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -8, 0)
    glow:Hide()
    g._glow = glow
    -- Zero idle cost: the group runs C-side only while flashing; Start/Stop
    -- are guarded so repeat alerts never restart the animation.
    local flasher = glow:CreateAnimationGroup()
    flasher:SetLooping("BOUNCE")
    local a = flasher:CreateAnimation("Alpha")
    a:SetFromAlpha(0.25)
    a:SetToAlpha(0.75)
    a:SetDuration(0.5)
    g._flasher = flasher

    function g:StartFlash()
        if not self._flasher:IsPlaying() then
            self._glow:Show()
            self._flasher:Play()
        end
    end
    function g:StopFlash()
        if self._flasher:IsPlaying() then self._flasher:Stop() end
        self._glow:Hide()
    end

    return g
end

local function AcquireGhost(index)
    local g = ghosts[index]
    if g then return g end
    g = BuildGhost()
    ghosts[index] = g
    return g
end

-------------------------------------------------------------------------------
--  Undocked tabs: no container sits between them and UIParent, and per-tab
--  FRAME alpha is rewritten constantly by FCFTab_UpdateAlpha -- but nothing
--  in Blizzard code writes the REGIONS' own alpha channel (the frame alpha
--  and SetTextColor ride different slots). One-way region SetAlpha(0) is the
--  same suppression class as the FontStringContainer: C-state only, nothing
--  secure ever reads it, re-asserted by the sweep in case a vertex-color
--  path ever touches an art texture's alpha slot.
-------------------------------------------------------------------------------
local function SuppressTabRegions(tab)
    for i = 1, select("#", tab:GetRegions()) do
        local region = select(i, tab:GetRegions())
        if region and region.SetAlpha and region:GetAlpha() ~= 0 then
            region:SetAlpha(0)
        end
    end
end

-------------------------------------------------------------------------------
--  Ghost styling: everything the owned strip drew, unchanged, minus any
--  geometry authority.
-------------------------------------------------------------------------------
local function StyleGhost(g, isActive)
    local cfg = DB()
    local state = g.state
    local fs = g._fs

    fs:SetFont(TabFontPath(), cfg.tabFontSize or 11, "")
    local tr, tg, tb, ta
    if state.isTemp then
        -- Conversation tabs keep the whisper chat color as their marker,
        -- like the old skin (which left Blizzard's coloring in place).
        local info = ChatTypeInfo[state.bn and "BN_WHISPER" or "WHISPER"]
        tr, tg, tb, ta = (info and info.r) or 1, (info and info.g) or 0.5, (info and info.b) or 1, 1
    elseif isActive then
        tr, tg, tb, ta = ResolveModeColor(cfg.tabFontColorActiveMode or "custom",
            cfg.tabFontColorActive, { r = 1, g = 1, b = 1, a = 1 })
    else
        tr, tg, tb, ta = ResolveModeColor(cfg.tabFontColorMode or "custom",
            cfg.tabFontColor, { r = 1, g = 1, b = 1, a = 0.65 })
    end
    fs:SetTextColor(tr, tg, tb, ta)
    -- The alert glow wears the tab's text color (desaturated art + tint).
    g._glow:SetVertexColor(tr, tg, tb)

    -- Background: color or texture, active/inactive variants.
    local bgc
    if isActive then
        local stored = cfg.tabBackgroundColorActive or { r = .03, g = .045, b = .05, a = .65 }
        local br, bgc2, bb, ba = ResolveModeColor(cfg.tabBackgroundColorActiveMode or "custom",
            stored, { r = .03, g = .045, b = .05, a = .65 })
        bgc = { r = br, g = bgc2, b = bb, a = ba }
    else
        local c = cfg.tabBackgroundColor or { r = .03, g = .045, b = .05, a = .44 }
        bgc = { r = c.r or .03, g = c.g or .045, b = c.b or .05, a = c.a == nil and .44 or c.a }
    end
    local texKey = cfg.tabBackgroundTexture or "none"
    local texPath
    if texKey ~= "none" then
        if ECHAT.RefreshBgTextureCatalogue then ECHAT.RefreshBgTextureCatalogue() end
        if EUI.ResolveTexturePath then
            texPath = EUI.ResolveTexturePath(ns.chatBgTextures, texKey, nil)
        else
            texPath = ns.chatBgTextures and ns.chatBgTextures[texKey]
        end
    end
    if texPath then
        g._bg:SetTexture(texPath)
        g._bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
    else
        g._bg:SetVertexColor(1, 1, 1, 1)
        g._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a)
    end

    -- Active underline.
    local underline = g._underline
    if cfg.activeUnderline ~= false and isActive then
        local mode = cfg.activeUnderlineColorMode or "accent"
        if mode == "border" then mode = "custom" end
        local ur, ug, ub, ua = ResolveModeColor(mode, cfg.activeUnderlineColor,
            { r = .05, g = .82, b = .61, a = 1 })
        underline:SetColorTexture(ur, ug, ub, ua)
        underline:Show()
    else
        underline:Hide()
    end

    -- Separator (extended mode): the 1px divider in Blizzard's inter-tab gap.
    local showSep = cfg.extendBgBehindTabs == true and not cfg.hideBorders
    if showSep then
        local r, gg, b, a
        if cfg.innerBorderColorMode == "accent" and EUI.GetAccentColor then
            r, gg, b = EUI.GetAccentColor()
            a = (cfg.innerBorderColor and cfg.innerBorderColor.a) or 0.06
        else
            local c = cfg.innerBorderColor or { r = 1, g = 1, b = 1, a = 0.06 }
            r, gg, b, a = c.r or 1, c.g or 1, c.b or 1, c.a == nil and 0.06 or c.a
        end
        g._sep:SetColorTexture(r, gg, b, a)
        g._sep:Show()
    else
        g._sep:Hide()
    end

    -- Per-tab border (only when tabs are visual islands outside the panel).
    local host = g._borderHost
    if EUI.ApplyBorderStyle then
        local showBorder = cfg.extendBgBehindTabs ~= true
        local sync = cfg.syncTabBorder ~= false
        local prefix = sync and "panelBorder" or "tabBorder"
        local function K(suffix, fallback)
            local v = cfg[prefix .. suffix]
            if v == nil then return fallback end
            return v
        end
        local sizes = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
        local thicknessKey = K("Thickness", "none")
        local size = sizes[thicknessKey] or 1
        local br, bgr, bb, ba = ResolveModeColor(K("ColorMode", "custom"),
            K("Color", nil), { r = 1, g = 1, b = 1, a = K("Opacity", nil)
                or ((K("ColorMode", "custom") == "custom") and 0.18 or 0.5) })
        if cfg.activeTabBorder ~= false and isActive and cfg.tabBorderColorActive then
            local ac = cfg.tabBorderColorActive
            br, bgr, bb = ac.r or br, ac.g or bgr, ac.b or bb
            ba = ac.a == nil and ba or ac.a
        end
        EUI.ApplyBorderStyle(host, showBorder and size or 0, br, bgr, bb, ba,
            K("Texture", "solid"), K("OffsetX", nil), K("OffsetY", nil),
            K("ShiftX", nil), K("ShiftY", nil), "chat", thicknessKey)
        host:SetShown(showBorder and size > 0)
    end
end

-------------------------------------------------------------------------------
--  Float ghost refresh (file-scope, explicit args: no per-refresh closure).
-------------------------------------------------------------------------------
local function RefreshFloatGhost(cf, height, fontPath, fontSize, padX, seen)
    local id = cf:GetID()
    local tab = _G[cf:GetName() .. "Tab"]
    local d = CFD(cf)
    if not (tab and d and d.bg) then return end
    local g = floatGhosts[id]
    if not g then
        g = BuildGhost()
        -- Float ghosts arm the geometry follower themselves -- the
        -- strip's motion catcher only covers the dock band, and the
        -- armed follower is what makes this window's panel (and the
        -- text frame anchored inside it) follow a native tab drag
        -- per-frame instead of freezing until the next deferred pass.
        -- Motion-only + full propagation: the tab beneath keeps its
        -- tooltip, clicks, and the drag itself.
        if g.SetMouseClickEnabled then
            g:SetMouseClickEnabled(false)
            g:SetMouseMotionEnabled(true)
            if g.SetPropagateMouseClicks then g:SetPropagateMouseClicks(true) end
            if g.SetPropagateMouseMotion then g:SetPropagateMouseMotion(true) end
            g:SetScript("OnEnter", function()
                if ECHAT.FollowArm then ECHAT.FollowArm() end
                if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
            end)
            g:SetScript("OnLeave", function()
                if ECHAT.FollowRelease then ECHAT.FollowRelease() end
            end)
        end
        floatGhosts[id] = g
    end
    if g:GetParent() ~= d.bg then g:SetParent(d.bg) end
    local isTemp = cf.isTemporary and true or false
    local st = g.state
    if not st then st = {}; g.state = st end
    st.cf, st.id, st.isTemp, st.bn = cf, id, isTemp, nil
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    g:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
    g:SetHeight(height)
    local fs = g._fs
    fs:SetFont(fontPath, fontSize, "")
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", g, "LEFT", padX, 0)
    fs:SetPoint("RIGHT", g, "RIGHT", -padX, 0)
    if isTemp then
        -- Same secret discipline as the docked path.
        local label = cf.chatTarget
        st.bn = cf.chatType == "BN_WHISPER"
        if issecretvalue and issecretvalue(label) then
            fs:SetText(label)
        elseif label ~= nil then
            fs:SetText(label)
        else
            fs:SetText("...")
        end
    else
        local name = GetChatWindowInfo(id)
        fs:SetText(name or ("Window " .. id))
    end
    StyleGhost(g, cf:IsShown())
    g:Show()
    seen[id] = true
end

-------------------------------------------------------------------------------
--  Strip placement: mirror the dock manager's rect exactly (live anchors).
-------------------------------------------------------------------------------
local function PositionStrip()
    local gdm = _G.GeneralDockManager
    if not gdm then return end
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", gdm, "TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMRIGHT", gdm, "BOTTOMRIGHT", 0, 0)
    -- Never re-show over an engaged full hide or passthrough: their
    -- remember-restores own the reveal.
    strip:SetShown(not ns._chatStackHidden and not ns._chatPassthrough)
end

-------------------------------------------------------------------------------
--  Refresh: enumerate the dock (reads only), anchor one ghost per docked tab.
--  Geometry is entirely Blizzard's; a ghost follows its tab through every
--  move, resize, drag, and scroll in the same render pass.
-------------------------------------------------------------------------------
local function RefreshNow()
    PositionStrip()
    local cfg = DB()
    local selected = SelectedWindow()
    local height = TabHeight()
    local fontPath = TabFontPath()
    local fontSize = cfg.tabFontSize or 11
    local padX = cfg.tabInnerPaddingX or 12

    -- The chat panel extends left of ChatFrame1 by its inset while Blizzard's
    -- dock starts at the frame edge; the FIRST ghost (and the strip's clip
    -- rect) stretch left to the panel edge so the row lines up with the
    -- panel. Visual-only: the extra pixels have no tab under them. Deferred
    -- numeric rect reads, the module's shipped-safe class.
    local leftExtend = 0
    do
        local cf1 = _G.ChatFrame1
        local bg1 = cf1 and CFD(cf1).bg
        local firstCF = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
            and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES[1]
        local firstTab = firstCF and _G[firstCF:GetName() .. "Tab"]
        local bgLeft = bg1 and bg1:GetLeft()
        local tabLeft = firstTab and firstTab:GetLeft()
        if bgLeft and tabLeft then
            local delta = bgLeft - tabLeft
            if delta < 0 and delta > -60 then leftExtend = delta end
        end
    end
    if leftExtend ~= 0 then
        local gdm = _G.GeneralDockManager
        if gdm then
            strip:SetPoint("TOPLEFT", gdm, "TOPLEFT", leftExtend, 0)
        end
    end

    local dockList = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
    local count = 0
    if type(dockList) == "table" then
        for i = 1, #dockList do
            local cf = dockList[i]
            local tab = cf and _G[cf:GetName() .. "Tab"]
            if tab then
                count = count + 1
                local g = AcquireGhost(count)
                local isTemp = cf.isTemporary and true or false
                -- State tables are reused across refreshes (no alloc churn).
                local st = g.state
                if not st then st = {}; g.state = st end
                st.cf, st.id, st.isTemp, st.bn = cf, cf:GetID(), isTemp, nil

                -- Whisper-tab ghosts clip at the dock scroll window's edges,
                -- like their tabs; static-tab ghosts clip at the strip's.
                local wantParent = (isTemp and EnsureDynClip()) and dynClip or strip
                if g:GetParent() ~= wantParent then g:SetParent(wantParent) end

                g:ClearAllPoints()
                local band = ns._chatBgExt
                if band and band:IsShown() then
                    -- Band mode: vertical extent from the band frame ITSELF
                    -- (horizontal from the tab), with ONE PHYSICAL PIXEL of
                    -- top slack. The inset chain runs on raw UI units, so at
                    -- non-1 scales every derived edge sits at its own
                    -- physical-pixel fraction and per-texture rounding can
                    -- push a flush-rect fill one row above the band's
                    -- rendered top (field-isolated to the bg fill; rect
                    -- sharing alone did not close it). Starting the ghost a
                    -- pixel inside the band makes poking above impossible
                    -- at any position or scale; the slack row reads as band
                    -- background.
                    local onePx = (EUI.PP and EUI.PP.mult) or 1
                    g:SetPoint("TOP", band, "TOP", 0, -onePx)
                    g:SetPoint("BOTTOM", band, "BOTTOM", 0, 0)
                    g:SetPoint("LEFT", tab, "LEFT", count == 1 and leftExtend or 0, 0)
                    g:SetPoint("RIGHT", tab, "RIGHT", 0, 0)
                else
                    -- Island tabs: bottom-aligned to the tab, our height.
                    g:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", count == 1 and leftExtend or 0, 0)
                    g:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                    g:SetHeight(height)
                end

                local fs = g._fs
                fs:SetFont(fontPath, fontSize, "")
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", g, "LEFT", padX, 0)
                fs:SetPoint("RIGHT", g, "RIGHT", -padX, 0)

                if isTemp then
                    -- Conversation label: may be a SECRET value. issecretvalue
                    -- comes FIRST (even a nil-compare on a secret errors);
                    -- secrets go straight to SetText, the display-only sink.
                    local label = cf.chatTarget
                    g.state.bn = cf.chatType == "BN_WHISPER"
                    if issecretvalue and issecretvalue(label) then
                        fs:SetText(label)
                    elseif label ~= nil then
                        fs:SetText(label)
                    else
                        fs:SetText("...")
                    end
                else
                    local name = GetChatWindowInfo(cf:GetID())
                    fs:SetText(name or ("Window " .. cf:GetID()))
                end

                local isActive = cf == selected
                StyleGhost(g, isActive)
                -- Blizzard's own alert state is authoritative here: their
                -- handler sets tab.alerting the moment a flash-worthy
                -- message hits a hidden window (including the message that
                -- CREATES a conversation window -- our ghost is born one
                -- pass later and would miss the observer's flash), and
                -- clears it on select.
                if isActive then
                    g:StopFlash()
                elseif tab.alerting then
                    g:StartFlash()
                else
                    g:StopFlash()
                end
                g:Show()
            end
        end
    end
    for i = count + 1, #ghosts do
        local g = ghosts[i]
        if g.state then g.state.cf = nil end
        g:StopFlash()
        g:Hide()
    end

    -- Undocked windows: one ghost pinned to each window's (region-suppressed)
    -- tab, parented to that window's panel so it inherits the panel's shown
    -- state and fade. The tab itself stays fully live: native drag-to-redock,
    -- menu, tooltip.
    table.wipe(floatSeen)
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and not cf.isDocked and cf:IsShown() then
            RefreshFloatGhost(cf, height, fontPath, fontSize, padX, floatSeen)
        end
    end
    local frames = _G.CHAT_FRAMES
    if type(frames) == "table" then
        for i = 11, #frames do
            local cf = _G[frames[i]]
            if cf and cf.isTemporary and cf.inUse and not cf.isDocked and cf:IsShown() then
                RefreshFloatGhost(cf, height, fontPath, fontSize, padX, floatSeen)
            end
        end
    end
    for id, g in pairs(floatGhosts) do
        if not floatSeen[id] then
            if g.state then g.state.cf = nil end
            g:StopFlash()
            g:Hide()
        end
    end
end

local refreshQueued = false
RequestRefresh = function()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        RefreshNow()
    end)
end
ECHAT.TabsRefresh = RequestRefresh
ECHAT.TabsRefreshNow = RefreshNow

-------------------------------------------------------------------------------
--  Adopt Blizzard's strip: invisible but fully clickable. One container-alpha
--  write; per-tab alphas multiply against it so FCFTab_UpdateAlpha can keep
--  writing whatever it likes. The overflow button and its list pop back to
--  full visibility (stock look) via ignoreParentAlpha -- without it they
--  would be invisible click targets.
--
--  Passthrough / full hide: invisible tabs must not eat world clicks, so the
--  exact set (each docked tab + the overflow button) gets click-disabled
--  while either mode is engaged; the sweep re-asserts on late joiners.
-------------------------------------------------------------------------------
local function SetTabClickable(tab, on)
    if tab.SetMouseClickEnabled then
        tab:SetMouseClickEnabled(on)
        if CFD then CFD(tab).clickOff = (not on) or nil end
    end
end

function ECHAT.TabsSweepBlizzard()
    local gdm = _G.GeneralDockManager
    if gdm then
        -- Full hide owns the dock's shown state (SetChatStackShown hides it
        -- with a remember); the sweep only heals a wrongly-hidden dock when
        -- no full hide is engaged.
        if not gdm:IsShown() and not ns._chatStackHidden then gdm:Show() end
        if gdm:GetAlpha() ~= 0 then gdm:SetAlpha(0) end
        local ob = gdm.overflowButton
        if ob then
            if ob.SetIgnoreParentAlpha and not ob:IsIgnoringParentAlpha() then
                ob:SetIgnoreParentAlpha(true)
            end
            local list = ob.list
            if list and list.SetIgnoreParentAlpha and not list:IsIgnoringParentAlpha() then
                list:SetIgnoreParentAlpha(true)
            end
        end
    end

    -- Click-state for the interaction plane, exact set, both directions.
    local wantOff = (ns._chatPassthrough or ns._chatStackHidden) and true or false
    local dockList = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
    if type(dockList) == "table" then
        for i = 1, #dockList do
            local cf = dockList[i]
            local tab = cf and _G[cf:GetName() .. "Tab"]
            if tab then
                local isOff = CFD(tab).clickOff and true or false
                if isOff ~= wantOff then SetTabClickable(tab, not wantOff) end
            end
        end
    end
    if gdm and gdm.overflowButton then
        local ob = gdm.overflowButton
        local isOff = CFD(ob).clickOff and true or false
        if isOff ~= wantOff then SetTabClickable(ob, not wantOff) end
    end

    -- Undocked windows: suppress their tabs' region pixels (ghosts paint
    -- instead; re-asserted every sweep in case a vertex-color path touches
    -- an art texture's alpha slot) and mirror the passthrough click-state.
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and not cf.isDocked then
            local tab = _G["ChatFrame" .. i .. "Tab"]
            if tab then
                SuppressTabRegions(tab)
                local isOff = CFD(tab).clickOff and true or false
                if isOff ~= wantOff then SetTabClickable(tab, not wantOff) end
            end
        end
    end

    -- Combat log quick-button bar: Blizzard parents it to ChatFrame2Tab at
    -- its OnLoad purely for tab-alpha inheritance; under the alpha-0 dock it
    -- would inherit invisibility. Re-home it onto ChatFrame2 itself -- the
    -- frame its anchors already target -- keeping the tree fully
    -- Blizzard-owned (its secure Show/Hide and progress-bar writes never
    -- cross an insecure parent). Position is stock; it rides the chat fade
    -- via cf2's alpha and the frame's own dock show/hide. Idempotent;
    -- self-heals if the combat log addon loads (and re-parents) after a
    -- sweep.
    local qb = _G.CombatLogQuickButtonFrame_Custom
    local cf2 = _G.ChatFrame2
    if qb and cf2 and qb:GetParent() ~= cf2 then
        qb:SetParent(cf2)
    end
end

-------------------------------------------------------------------------------
--  Flash: driven by the engine tail. Suppression semantics come free -- a
--  message suppressed by Blizzard's handler never reaches AddMessage, so it
--  never reaches this observer. New conversation tabs appear via the same
--  observer (their first message queues a refresh).
-------------------------------------------------------------------------------
-- Whisper types only, matching Blizzard's FlashTabIfNotShown: the flashTab /
-- flashTabOnGeneral flags gate it AND the type must be a whisper.
local FLASH_TYPES = {
    WHISPER = true, BN_WHISPER = true,
    WHISPER_INFORM = false, BN_WHISPER_INFORM = false,
}

local function GhostFor(cf)
    for i = 1, #ghosts do
        local g = ghosts[i]
        if g.state and g.state.cf == cf then return g end
    end
    for _, g in pairs(floatGhosts) do
        if g.state and g.state.cf == cf then return g end
    end
    return nil
end

local function OnTabMessage(cf, event)
    -- A message for a window with no ghost yet (fresh temp frame, or a dock
    -- change we have not seen) re-enumerates on the next tick. Hidden
    -- undocked windows are excluded: they get no ghost until shown, and
    -- re-queueing per message would churn.
    if not GhostFor(cf) and (cf.isDocked or cf:IsShown()) then
        RequestRefresh()
    end
    if not event then return end
    local chatType = strsub(event, 10)
    if not FLASH_TYPES[chatType] then return end
    local selected = SelectedWindow()
    if cf == selected or not cf.isDocked then return end
    local info = ChatTypeInfo[chatType]
    if not info then return end
    if cf == _G.DEFAULT_CHAT_FRAME then
        if not info.flashTabOnGeneral then return end
        -- Popout modes carry the alert on the conversation tab; Blizzard
        -- suppresses the general-tab flash there too.
        if GetCVar("whisperMode") ~= "inline" then return end
    elseif not info.flashTab then
        return
    end
    -- A conversation window CREATED by this message has no ghost yet; the
    -- queued refresh above builds it and the tab.alerting mirror in the
    -- refresh starts its flash.
    local g = GhostFor(cf)
    if g and g:IsShown() then g:StartFlash() end
end

-------------------------------------------------------------------------------
--  Passthrough (full hide): our visuals hide; the invisible interaction plane
--  is click-disabled by the sweep (called by the module's passthrough flow).
-------------------------------------------------------------------------------
function ECHAT.TabsSetPassthrough(on)
    if on then
        if strip:IsShown() then
            ns._stripWasShown = true
            strip:Hide()
        end
    else
        if ns._stripWasShown then
            ns._stripWasShown = nil
            strip:Show()
        end
    end
    ECHAT.TabsSweepBlizzard()
end

-------------------------------------------------------------------------------
--  Options-contract exports: same names the options page (and the module's
--  own appliers) call. All styling-only now -- geometry belongs to Blizzard.
-------------------------------------------------------------------------------
function ECHAT.ApplyTabAppearance() RequestRefresh() end
function ECHAT.ApplyTabBorders() RequestRefresh() end
function ECHAT.ApplyTabSeparators() RequestRefresh() end
function ECHAT.ApplyTabSpacing() RequestRefresh() end

function ECHAT.ApplyTabLayout()
    PositionStrip()
    RequestRefresh()
end

function ECHAT.ApplyTabPadding()
    PositionStrip()
    if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
    if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
    RequestRefresh()
end

-------------------------------------------------------------------------------
--  Init: wired by the module root once panels exist (TabsInit), then kept
--  fresh by the module's existing deferred passes (QueueTabPass/QueueFullPass
--  call TabsRefresh + TabsSweepBlizzard).
-------------------------------------------------------------------------------
function ECHAT.TabsInit()
    if ECHAT.EngineSetTabObserver then
        ECHAT.EngineSetTabObserver(OnTabMessage)
    end
    ECHAT.TabsSweepBlizzard()
    RefreshNow()
end
