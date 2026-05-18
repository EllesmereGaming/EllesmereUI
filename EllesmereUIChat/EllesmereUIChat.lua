-------------------------------------------------------------------------------
--  EllesmereUIChat.lua
--
--  Visual reskin + utility features:
--    - Dark unified background (chat + input as one panel)
--    - Tab restyling (accent underline, flat dark bg — matches CharSheet)
--    - Blizzard chrome removal
--    - Top-edge fade gradient
--    - Timestamps
--    - Thin EUI scrollbar
--    - Copy Chat button (session history)
--    - Search bar to filter messages
-------------------------------------------------------------------------------
local addonName, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

ns.ECHAT = ns.ECHAT or {}
local ECHAT = ns.ECHAT

local min, max, floor, ceil, abs = min, max, floor, ceil, math.abs

-- Per-frame data table. All custom state is stored here instead of writing
-- properties onto Blizzard's chat frame tables (which taints them and causes
-- HistoryKeeper errors in protected instances).
local _cfd = {}
local function CFD(cf)
    local d = _cfd[cf]
    if not d then d = {}; _cfd[cf] = d end
    return d
end
EllesmereUI._chatCFD = CFD

local CHAT_DEFAULTS = {
    profile = {
        chat = {
            enabled    = true,
            visibility = "always",
            bgAlpha    = 0.65,
            bgR        = 0.03,
            bgG        = 0.045,
            bgB        = 0.05,
            timestampFormat = "%I:%M ",
            font = "__global",
            outlineMode = "__global",
            fontSize = 12,
            tabFontSize = 10,
            sidebarVisibility = "always",
            hideBorders = false,
            showFriends = true,
            showCopy = true,
            showPortals = true,
            showVoice = false,
            showSettings = true,
            showScroll = true,
            hideTooltipOnHover = true,
            sidebarRight = false,
            iconR = 1,
            iconG = 1,
            iconB = 1,
            iconUseAccent = false,
            idleFadeDelay = 15,
            idleFadeStrength = 40,
            inputOnTop = false,
            lockChatSize = false,
            hideSidebarBg = false,
            sidebarIconScale = 1.0,
            sidebarIconSpacing = 10,
            freeMoveIcons = false,
            iconPositions = {},
            sidebarIconOrder = {
                showCopy = 1,
                showPortals = 2,
                showVoice = 3,
                showSettings = 4,
            },
            -- Session chat history (see EllesmereUIChat_SessionHistory.lua, SavedVariablesPerCharacter)
            persistChatHistory = true,
            persistChatHistoryMaxLines = 100,
        },
    },
}

local _chatDB
local function EnsureDB()
    if _chatDB then return _chatDB end
    if not EUI.Lite then return nil end
    _chatDB = EUI.Lite.NewDB("EllesmereUIChatDB", CHAT_DEFAULTS)
    _G._ECHAT_DB = _chatDB
    -- One-time migration: mouseover -> always (idle fade replaces it)
    if _chatDB.profile and _chatDB.profile.chat
        and _chatDB.profile.chat.visibility == "mouseover" then
        _chatDB.profile.chat.visibility = "always"
    end
    return _chatDB
end

function ECHAT.DB()
    local d = EnsureDB()
    if d and d.profile and d.profile.chat then
        return d.profile.chat
    end
    return {
        enabled = true,
        visibility = "always",
        persistChatHistory = true,
        persistChatHistoryMaxLines = 100,
    }
end

local PP = EUI.PP
local function GetFont()
    local cfg = ECHAT.DB()
    local fontKey = cfg.font or "__global"
    if fontKey == "__global" then
        return (EUI.GetFontPath and EUI.GetFontPath("chat")) or STANDARD_TEXT_FONT
    end
    return (EUI.ResolveFontName and EUI.ResolveFontName(fontKey)) or STANDARD_TEXT_FONT
end

local function GetOutlineFlag()
    local cfg = ECHAT.DB()
    local mode = cfg.outlineMode or "__global"
    if mode == "__global" then
        return (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("chat")) or ""
    end
    if mode == "outline" then return "OUTLINE" end
    if mode == "thick" then return "THICKOUTLINE" end
    return ""
end

local _hiddenParent = CreateFrame("Frame")
_hiddenParent:Hide()

-- Unified fade system: all alpha changes go through a target + lerp.
local _visChatVisible = true
local function GetIdleFadeAlpha()
    local cfg = ECHAT.DB()
    local strength = min(cfg.idleFadeStrength or 40, 99)
    return 1 - (strength / 100)
end
local _idleFadeActive = false
local FADE_IN_DURATION = 0.35
local FADE_OUT_DURATION = 1.0
local IDLE_FADE_OUT_DURATION = 2.0
local _chatAlphaTarget = 1
local _chatAlphaCurrent = 1
local _chatFadeFrame = CreateFrame("Frame")
_chatFadeFrame:Hide()

-- Batch cursor check: reads cursor position once, tests a frame using
-- pre-fetched raw cursor coords. Avoids repeated GetCursorPosition calls.
local _rawCX, _rawCY = 0, 0
local function RefreshCursorPos()
    _rawCX, _rawCY = GetCursorPosition()
end
local function IsCursorOverCached(frame)
    if not frame or not frame:IsVisible() then return false end
    local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
    if not ok or not left then return false end
    if issecretvalue and issecretvalue(left) then return false end
    local scale = frame:GetEffectiveScale()
    local cx, cy = _rawCX / scale, _rawCY / scale
    return cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height
end

local BG_R, BG_G, BG_B, BG_A = 0.03, 0.045, 0.05, 0.70

local EDIT_BG_R, EDIT_BG_G, EDIT_BG_B = 0.05, 0.065, 0.08

-- Set true once GeneralDockManager has been positioned and styled as our tab bar
local _euiDockStyled = false
-- Chat frame text size is controlled by Blizzard's per-frame setting
-- (right-click tab -> Font Size). We only control font family + outline.
local function GetFrameFontSize(id)
    if FCF_GetChatWindowInfo then
        local _, fontSize = FCF_GetChatWindowInfo(id)
        if fontSize and fontSize > 0 then return fontSize end
    end
    return 12
end
-- GetTabFontSize removed: tab font size hardcoded to 11

-- Apply background settings from DB to all skinned chat frames
function ECHAT.ApplyBackground()
    local p = ECHAT.DB()
    BG_R = p.bgR or 0.03
    BG_G = p.bgG or 0.045
    BG_B = p.bgB or 0.05
    BG_A = p.bgAlpha or 0.65

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and CFD(cf).bg then
            -- Update main bg texture
            local bgTex = CFD(cf).bg:GetRegions()
            if bgTex and bgTex.SetColorTexture then
                bgTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
            end
        end
        -- Update skinned Blizzard tab backgrounds
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and CFD(tab).bg then
            local isActive = CFD(tab).underline and CFD(tab).underline:IsShown()
            CFD(tab).bg:SetColorTexture(BG_R, BG_G, BG_B, isActive and BG_A or (BG_A * 0.67))
        end
    end
    -- Update sidebar bg
    local cf1 = _G.ChatFrame1
    if cf1 and CFD(cf1).sidebar then
        local sbBg = CFD(cf1).sidebar:GetRegions()
        if sbBg and sbBg.SetColorTexture then
            sbBg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
        end
    end
end

-- Re-apply font to all skinned chat frames, tabs, and edit boxes.
-- Chat frame text size is Blizzard's per-frame setting; we only set
-- font family + outline. Tab size is our own setting.
function ECHAT.ApplyFonts()
    local font = GetFont()
    local outline = GetOutlineFlag()
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.SetFont then
            local size = GetFrameFontSize(i)
            cf:SetFont(font, size, outline)
        end
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            local size = GetFrameFontSize(i)
            eb:SetFont(font, size, outline)
            if i <= 10 then
                if eb.header then eb.header:SetFont(font, size, outline) end
                if eb.headerSuffix then eb.headerSuffix:SetFont(font, size, outline) end
            end
        end
    end
end

-- Sidebar visibility: always, mouseover, never
local _sidebarFadeTarget = 1
local _sidebarFadeAlpha = 1
local _sidebarFadeFrame

function ECHAT.ApplySidebarVisibility()
    local cfg = ECHAT.DB()
    local mode = cfg.sidebarVisibility or "always"
    local cf1 = _G.ChatFrame1
    local sidebar = cf1 and CFD(cf1).sidebar
    if not sidebar then return end

    if mode == "never" then
        _sidebarFadeTarget = 0
        _sidebarFadeAlpha = 0
        sidebar:SetAlpha(0)
        sidebar:EnableMouse(false)
    elseif mode == "mouseover" then
        _sidebarFadeTarget = 0
        _sidebarFadeAlpha = 0
        sidebar:SetAlpha(0)
        sidebar:EnableMouse(true)
    else
        _sidebarFadeTarget = 1
        _sidebarFadeAlpha = 1
        sidebar:SetAlpha(1)
        sidebar:EnableMouse(true)
    end

    -- Create fade frame once, reuse
    if not _sidebarFadeFrame then
        _sidebarFadeFrame = CreateFrame("Frame")
        _sidebarFadeFrame:Hide()
        _sidebarFadeFrame:SetScript("OnUpdate", function(self, dt)
            local step = dt * 4  -- 0.25s fade
            if _sidebarFadeTarget > _sidebarFadeAlpha then
                _sidebarFadeAlpha = min(_sidebarFadeTarget, _sidebarFadeAlpha + step)
            else
                _sidebarFadeAlpha = max(_sidebarFadeTarget, _sidebarFadeAlpha - step)
            end
            local sb = _G.ChatFrame1 and CFD(_G.ChatFrame1).sidebar
            if sb then sb:SetAlpha(min(_sidebarFadeAlpha, _chatAlphaCurrent)) end
            if _sidebarFadeAlpha == _sidebarFadeTarget then self:Hide() end
        end)
    end
end

-- Show/hide all borders and dividers (not the active tab underline)
function ECHAT.ApplyBorders()
    local cfg = ECHAT.DB()
    local hide = cfg.hideBorders

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and CFD(cf).bg and PP.GetBorders(CFD(cf).bg) then
            PP.GetBorders(CFD(cf).bg):SetShown(not hide)
        end
        if cf and CFD(cf).inputDiv then
            CFD(cf).inputDiv:SetShown(not hide)
        end
    end
    local cf1 = _G.ChatFrame1
    if cf1 and CFD(cf1).sidebar then
        local sbBgHidden = cfg.hideSidebarBg
        if PP.GetBorders(CFD(cf1).sidebar) then
            PP.GetBorders(CFD(cf1).sidebar):SetShown(not hide and not sbBgHidden)
        end
        if CFD(cf1).sidebarDiv then
            CFD(cf1).sidebarDiv:SetShown(not hide)
        end
    end
end

-- Show/hide individual sidebar icons and re-anchor visible ones to close gaps
function ECHAT.ApplySidebarIcons()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end

    local ICON_GAP = cfg.sidebarIconSpacing or 10
    local showFriends = cfg.showFriends ~= false
    local showCopy = cfg.showCopy ~= false
    local showPortals = cfg.showPortals ~= false
    local showVoice = cfg.showVoice ~= false
    local showSettings = cfg.showSettings ~= false

    -- Friends + count (re-anchor with custom spacing)
    if CFD(cf1).friendsBtn then
        CFD(cf1).friendsBtn:SetShown(showFriends)
        if showFriends then
            CFD(cf1).friendsBtn:ClearAllPoints()
            CFD(cf1).friendsBtn:SetPoint("TOP", sb, "TOP", 0, -ICON_GAP)
        end
    end
    if CFD(cf1).friendsCount then CFD(cf1).friendsCount:SetShown(showFriends) end

    -- Build ordered list of visible top-group buttons, sorted by check order
    local iconOrder = cfg.sidebarIconOrder or {}
    local sbd = CFD(cf1)
    local allMiddle = {
        { key = "showCopy",     ref = "copyBtn" },
        { key = "showPortals",  ref = "portalBtn" },
        { key = "showVoice",    ref = "voiceBtn" },
        { key = "showSettings", ref = "settingsBtn" },
    }
    local topBtns = {}
    for _, info in ipairs(allMiddle) do
        if cfg[info.key] ~= false and sbd[info.ref] then
            local ord = iconOrder[info.key]
            if type(ord) ~= "number" then ord = 999 end
            topBtns[#topBtns + 1] = { btn = sbd[info.ref], order = ord }
        end
    end
    table.sort(topBtns, function(a, b) return a.order < b.order end)

    -- Hide all first
    if CFD(cf1).copyBtn then CFD(cf1).copyBtn:Hide() end
    if CFD(cf1).portalBtn then CFD(cf1).portalBtn:Hide() end
    if CFD(cf1).voiceBtn then CFD(cf1).voiceBtn:Hide() end
    if CFD(cf1).settingsBtn then CFD(cf1).settingsBtn:Hide() end

    -- Re-anchor visible buttons in chain (sorted by order)
    local anchor = showFriends and CFD(cf1).friendsCount or nil
    for _, entry in ipairs(topBtns) do
        entry.btn:ClearAllPoints()
        if anchor then
            entry.btn:SetPoint("TOP", anchor, "BOTTOM", 0, -ICON_GAP)
        else
            entry.btn:SetPoint("TOP", sb, "TOP", 0, -ICON_GAP)
        end
        entry.btn:Show()
        anchor = entry.btn
    end

    -- Scroll is independent
    if CFD(cf1).scrollBtn then CFD(cf1).scrollBtn:SetShown(cfg.showScroll ~= false) end

    -- Re-apply free move offsets after chain layout
    if ECHAT.ApplyIconFreeMove then ECHAT.ApplyIconFreeMove() end
end

-- Chat frame position: owned by EUI unlock mode when a saved position exists.
-- SetPoint hook enforces saved position, blocking Blizzard's Edit Mode.
local _cfIgnoreSetPoint = false
local _cfResizing = false

local function ApplyChatPosition()
    local cfg = ECHAT.DB()
    if not cfg or not cfg.chatPosition then return end
    local pos = cfg.chatPosition
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    local px, py = pos.x, pos.y
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa and px and py then
        local es = cf1:GetEffectiveScale()
        local isCenterAnchor = (pos.point == "CENTER")
            and (pos.relPoint == "CENTER" or pos.relPoint == nil)
        if isCenterAnchor and PPa.SnapCenterForDim then
            px = PPa.SnapCenterForDim(px, cf1:GetWidth() or 0, es)
            py = PPa.SnapCenterForDim(py, cf1:GetHeight() or 0, es)
        elseif PPa.SnapForES then
            px = PPa.SnapForES(px, es)
            py = PPa.SnapForES(py, es)
        end
    end
    if not pos.point or not (px and py) then return end
    _cfIgnoreSetPoint = true
    cf1:ClearAllPoints()
    cf1:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px or 0, py or 0)
    _cfIgnoreSetPoint = false
end

-- Chat frame size: Blizzard is sole authority for chat sizing.
-- We no longer apply saved width/height.
local function ApplyChatSize()
    -- no-op: Blizzard handles all chat frame sizing
end
ECHAT.ApplyChatSize = ApplyChatSize

function ECHAT.ApplyLockChatSize()
    local cfg = ECHAT.DB()
    -- No-op: custom resize grip removed, Blizzard handles sizing.
end

-- Flip sidebar to left or right side of chat bg
function ECHAT.ApplySidebarPosition()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb or not CFD(cf1).bg then return end
    local PP = EllesmereUI and EllesmereUI.PP
    local onePx = (PP and PP.mult) or 1
    sb:ClearAllPoints()
    if cfg.sidebarRight then
        sb:SetPoint("TOPLEFT", CFD(cf1).bg, "TOPRIGHT", 0, 0)
        sb:SetPoint("BOTTOMLEFT", CFD(cf1).bg, "BOTTOMRIGHT", 0, 0)
    else
        sb:SetPoint("TOPRIGHT", CFD(cf1).bg, "TOPLEFT", 0, 0)
        sb:SetPoint("BOTTOMRIGHT", CFD(cf1).bg, "BOTTOMLEFT", 0, 0)
    end
    -- Move the divider to the correct edge
    if CFD(cf1).sidebarDiv then
        CFD(cf1).sidebarDiv:ClearAllPoints()
        if cfg.sidebarRight then
            CFD(cf1).sidebarDiv:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
            CFD(cf1).sidebarDiv:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0)
        else
            CFD(cf1).sidebarDiv:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
            CFD(cf1).sidebarDiv:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
        end
    end

end

-- Apply icon color to all sidebar icons
function ECHAT.ApplyIconColor()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end
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
        friendsBtn = "Friends", copyBtn = "Copy Chat", portalBtn = "M+ Portals",
        voiceBtn = "Voice/Channels", settingsBtn = "Settings", scrollBtn = "Scroll to Bottom",
    }
    local fc = d.friendsCount
    for _, key in ipairs({ "friendsBtn", "copyBtn", "portalBtn", "voiceBtn", "settingsBtn", "scrollBtn" }) do
        local btn = CFD(cf1)[key]
        if btn and btn._icon then
            btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
            local label = ICON_LABELS[key]
            if key == "friendsBtn" and fc then
                fc:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    fc:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                        EUI.ShowWidgetTooltip(self, label)
                    end
                end)
                btn:SetScript("OnLeave", function()
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    fc:SetTextColor(r, g, b, 0.5)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                end)
            else
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                        EUI.ShowWidgetTooltip(self, label)
                    end
                end)
                btn:SetScript("OnLeave", function()
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
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
    local show = not cfg.hideSidebarBg
    local sbBg = sb:GetRegions()
    if sbBg and sbBg.SetShown then
        sbBg:SetShown(show)
    end
    if PP.GetBorders(sb) then
        PP.GetBorders(sb):SetShown(show)
    end
end

-- Scale sidebar icon buttons and friends count text
function ECHAT.ApplySidebarIconScale()
    local cfg = ECHAT.DB()
    local scale = cfg.sidebarIconScale or 1.0
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end

    local BASE_FRIEND = 26
    local BASE_ICON = 22
    local BASE_FONT = 9

    for _, key in ipairs({ "copyBtn", "portalBtn", "voiceBtn", "settingsBtn", "scrollBtn" }) do
        local btn = CFD(cf1)[key]
        if btn then btn:SetSize(BASE_ICON * scale, BASE_ICON * scale) end
    end
    if CFD(cf1).friendsBtn then
        CFD(cf1).friendsBtn:SetSize(BASE_FRIEND * scale, BASE_FRIEND * scale)
    end
    if CFD(cf1).friendsCount then
        CFD(cf1).friendsCount:SetFont(GetFont(), max(7, BASE_FONT * scale), "")
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

local function ApplyIconOffset(btn, sb)
    if not btn or not sb or not btn:IsShown() then return end
    local key = btn._freeMoveKey
    if not key then return end
    local ox, oy = GetIconOffset(key)
    -- Break the chain for ALL icons: re-anchor directly to sidebar
    -- using current center position so moving one doesn't drag the rest.
    local bx, by = btn:GetCenter()
    local sx, sy = sb:GetCenter()
    if not bx or not sx then return end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", sb, "CENTER", (bx - sx) + ox, (by - sy) + oy)
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

    local isDragging = false
    local startX, startY, origOffX, origOffY
    local origPoint, origRel, origRelPoint, origX, origY

    local function FreeMoveOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then
            isDragging = false
            self:SetScript("OnUpdate", nil)
            C_Timer.After(0, function() self._freeMoveJustDragged = nil end)
            local es = self:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / es, cy / es
            local dx, dy = cx - startX, cy - startY
            SaveIconOffset(key, origOffX + dx, origOffY + dy)
            return
        end
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        if origPoint then
            self:ClearAllPoints()
            self:SetPoint(origPoint, origRel, origRelPoint, origX + origOffX + dx, origY + origOffY + dy)
        end
    end

    btn:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if not IsShiftKeyDown() then return end
        local cfg = ECHAT.DB()
        if not cfg.freeMoveIcons then return end
        isDragging = true
        self._freeMoveJustDragged = true
        local es = self:GetEffectiveScale()
        startX, startY = GetCursorPosition()
        startX, startY = startX / es, startY / es
        origOffX, origOffY = GetIconOffset(key)
        origPoint, origRel, origRelPoint, origX, origY = self:GetPoint(1)
        origX = (origX or 0) - origOffX
        origY = (origY or 0) - origOffY
        self:SetScript("OnUpdate", FreeMoveOnUpdate)
    end)

    btn:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not isDragging then return end
        isDragging = false
        self:SetScript("OnUpdate", nil)
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        SaveIconOffset(key, origOffX + dx, origOffY + dy)
        C_Timer.After(0, function() self._freeMoveJustDragged = nil end)
    end)
end

function ECHAT.ApplyIconFreeMove()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end

    local btns = {
        { ref = "friendsBtn", key = "friends" },
        { ref = "copyBtn",    key = "copy" },
        { ref = "portalBtn",  key = "portals" },
        { ref = "voiceBtn",   key = "voice" },
        { ref = "settingsBtn", key = "settings" },
        { ref = "scrollBtn",  key = "scroll" },
    }

    for _, info in ipairs(btns) do
        local btn = CFD(cf1)[info.ref]
        if btn then
            btn._freeMoveKey = info.key
            EnableIconFreeMove(btn)
            if cfg.freeMoveIcons then
                ApplyIconOffset(btn, sb)
            end
        end
    end
end

-- Portal flyout: dungeon portal spell buttons
local PORTAL_SPELLS = {
    1254400, 1254572, 1254563, 1254559,
    159898,  1254555, 1254551, 393273,
}
local PORTAL_SHORT = {
    [1254400] = "WRS", [1254572] = "MT",  [1254563] = "NPX", [1254559] = "MC",
    [159898]  = "SR",  [1254555] = "PoS", [1254551] = "SoT", [393273]  = "AA",
}

local _portalFlyout, _portalBtns

local function RefreshPortalButtons()
    if not _portalBtns then return end
    for _, btn in ipairs(_portalBtns) do
        local spellID = btn.spellID
        local known = IsPlayerSpell(spellID)
        if btn._lastKnown ~= known then
            btn._lastKnown = known
            btn.icon:SetDesaturated(not known)
            btn.icon:SetAlpha(known and 1 or 0.4)
        end
        if known then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
            else
                btn.cooldown:Clear()
            end
        else
            btn.cooldown:Clear()
        end
    end
end

local function CreatePortalFlyout()
    if _portalFlyout then return _portalFlyout end

    local BTN_SIZE = 32
    local SPACING = 1
    local PADDING = 2
    local COLS = 4
    local ROWS = ceil(#PORTAL_SPELLS / COLS)

    local portalW = PADDING * 2 + BTN_SIZE * COLS + SPACING * (COLS - 1)
    local flyH = PADDING * 2 + BTN_SIZE * ROWS + SPACING * (ROWS - 1)
    local HS_COUNT = 3
    local HS_H = floor((flyH - PADDING * 2 - SPACING * (HS_COUNT - 1)) / HS_COUNT)
    local hsX = PADDING + COLS * BTN_SIZE + (COLS - 1) * SPACING + SPACING
    local flyW = hsX + HS_H + PADDING

    local flyout = CreateFrame("Frame", "EUIChatPortalFlyout", UIParent)
    flyout:SetSize(flyW, flyH)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(100)
    flyout:Hide()

    local bg = flyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(BG_R, BG_G, BG_B, 0.95)

    if PP and PP.CreateBorder then
        PP.CreateBorder(flyout, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
    end

    -- Close in combat
    local guard = CreateFrame("Frame")
    guard:RegisterEvent("PLAYER_REGEN_DISABLED")
    guard:SetScript("OnEvent", function()
        flyout:Hide()
    end)

    -- Spell buttons
    _portalBtns = {}
    for i, spellID in ipairs(PORTAL_SPELLS) do
        local col = (i - 1) % COLS
        local row = floor((i - 1) / COLS)

        local btn = CreateFrame("Button", "EUIChatPortal" .. i, flyout, "SecureActionButtonTemplate")
        btn:SetSize(BTN_SIZE, BTN_SIZE)
        btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            PADDING + col * (BTN_SIZE + SPACING),
            -(PADDING + row * (BTN_SIZE + SPACING)))

        btn.spellID = spellID

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo then icon:SetTexture(spellInfo.iconID) end
        btn.icon = icon

        -- 1px black border
        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(true)
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        btn.cooldown = cd

        local short = PORTAL_SHORT[spellID]
        if short then
            local labelFrame = CreateFrame("Frame", nil, btn)
            labelFrame:SetAllPoints()
            labelFrame:SetFrameLevel(cd:GetFrameLevel() + 2)
            local label = labelFrame:CreateFontString(nil, "OVERLAY", nil)
            label:SetFont(GetFont(), 8, "OUTLINE")
            label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
            label:SetTextColor(1, 1, 1, 0.9)
            label:SetText(short)
            label:SetShadowOffset(1, -1)
            label:SetShadowColor(0, 0, 0, 1)
        end

        -- Hover highlight (HIGHLIGHT layer auto-shows on mouseover)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)

        -- Casting highlight overlay
        local castHL = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        btn._castHL = castHL

        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spellID)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        _portalBtns[i] = btn
    end

    -- Hearthstone column: 3 icons stacked vertically as a 5th column
    -- on the right side, separated by a thin vertical divider.
    local _hearthBtns = {}
    for i = 1, HS_COUNT do
        local btn = CreateFrame("Button", "EUIChatHearth" .. i, flyout, "SecureActionButtonTemplate")
        btn:SetSize(HS_H, HS_H)
        btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            hsX,
            -(PADDING + (i - 1) * (HS_H + SPACING)))

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
        btn.icon = icon

        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(true)
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        btn.cooldown = cd

        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)

        btn:RegisterForClicks("AnyUp", "AnyDown")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._hsType == "spell" then
                GameTooltip:SetSpellByID(self._hsID)
            elseif self._hsType == "item" then
                if self._hsID ~= 6948 and PlayerHasToy and PlayerHasToy(self._hsID) then
                    GameTooltip:SetToyByItemID(self._hsID)
                else
                    GameTooltip:SetItemByID(self._hsID)
                end
            elseif self._hsType == "housing" then
                GameTooltip:AddLine("Housing Dashboard")
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Casting highlight overlay (same as portal buttons)
        local castHL = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        btn._castHL = castHL

        btn:HookScript("PostClick", function(self)
            if self._hsType == "housing" then
                if HousingFramesUtil and HousingFramesUtil.ToggleHousingDashboard then
                    HousingFramesUtil.ToggleHousingDashboard()
                end
                if _portalFlyout then _portalFlyout:Hide() end
            else
                -- Show cast highlight immediately on click
                self._castHL:Show()
            end
        end)

        _hearthBtns[i] = btn
    end


    -- Cooldown-only refresh: updates swipes without re-resolving toys.
    -- Called on SPELL_UPDATE_COOLDOWN events.
    local function RefreshHearthCooldowns()
        for _, btn in ipairs(_hearthBtns) do
            local aType, id = btn._hsType, btn._hsID
            if aType == "spell" and C_Spell and C_Spell.GetSpellCooldown then
                local cdInfo = C_Spell.GetSpellCooldown(id)
                if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                    btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
                else
                    btn.cooldown:Clear()
                end
            elseif aType == "item" and GetItemCooldown then
                local ok, start, dur = pcall(GetItemCooldown, id)
                if ok and start and dur and dur > 0 then
                    btn.cooldown:SetCooldown(start, dur)
                else
                    btn.cooldown:Clear()
                end
            else
                btn.cooldown:Clear()
            end
        end
    end

    -- Full resolve: picks random toy, sets icon/macro/attributes.
    -- Called once on Show only (not on cooldown events).
    local function ResolveHearthButtons()
        if InCombatLockdown() then return end
        local EUI = EllesmereUI
        local resolvers = {
            EUI.ResolveHearthSlot,
            EUI.ResolveDalaranSlot,
            EUI.ResolveHousingSlot,
        }
        for i, btn in ipairs(_hearthBtns) do
            local aType, id, iconTex = resolvers[i]()
            btn._hsType = aType
            btn._hsID = id
            btn.icon:SetTexture(iconTex)
            btn.icon:SetTexCoord(aType == "housing" and 0 or 6/64,
                                 aType == "housing" and 1 or 58/64,
                                 aType == "housing" and 0 or 6/64,
                                 aType == "housing" and 1 or 58/64)
            if aType == "housing" then
                btn:SetAttribute("type", nil)
                btn:SetAttribute("macrotext", nil)
            elseif aType == "spell" then
                btn:SetAttribute("type", "macro")
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                local name = info and info.name or ""
                btn:SetAttribute("macrotext", "/cast " .. name)
            else
                btn:SetAttribute("type", "macro")
                if id == 6948 then
                    btn:SetAttribute("macrotext", "/use item:" .. id)
                else
                    local toyName
                    if C_ToyBox and C_ToyBox.GetToyInfo then
                        local _, tn = C_ToyBox.GetToyInfo(id)
                        toyName = tn
                    end
                    btn:SetAttribute("macrotext", toyName and ("/use " .. toyName) or ("/use item:" .. id))
                end
            end
        end
        RefreshHearthCooldowns()
    end

    -- Cooldown + casting highlight refresh while visible
    flyout:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self:RegisterEvent("UNIT_SPELLCAST_START")
        self:RegisterEvent("UNIT_SPELLCAST_STOP")
        self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        self:RegisterEvent("UNIT_SPELLCAST_FAILED")
        self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        RefreshPortalButtons()
        ResolveHearthButtons()
    end)
    flyout:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        for _, btn in ipairs(_portalBtns) do
            if btn._castHL then btn._castHL:Hide() end
        end
        for _, btn in ipairs(_hearthBtns) do
            if btn._castHL then btn._castHL:Hide() end
        end
    end)
    flyout:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
        if event == "SPELL_UPDATE_COOLDOWN" then
            RefreshPortalButtons()
            RefreshHearthCooldowns()
        elseif unit == "player" then
            local casting = (event == "UNIT_SPELLCAST_START") and spellID or nil
            for _, btn in ipairs(_portalBtns) do
                if btn._castHL then
                    btn._castHL:SetShown(casting and casting == btn.spellID)
                end
            end
            -- Clear hearthstone cast highlights on cast end
            if not casting then
                for _, btn in ipairs(_hearthBtns) do
                    if btn._castHL then btn._castHL:Hide() end
                end
            end
        end
    end)

    -- Escape to close
    EllesmereUI.RegisterEscapeClose(flyout)

    _portalFlyout = flyout
    return flyout
end

function ECHAT.TogglePortalFlyout(anchorBtn)
    if InCombatLockdown() then return end
    local flyout = CreatePortalFlyout()
    if flyout:IsShown() then
        flyout:Hide()
    else
        -- Compute absolute screen position (protected frame can't anchor to non-secure region)
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
        flyout:Show()
    end
end

-- Flip edit box between bottom (default) and top of chat panel
function ECHAT.ApplyInputPosition()
    local cfg = ECHAT.DB()
    local onTop = cfg.inputOnTop

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and CFD(cf).bg then
            local name = cf:GetName()
            if not name then break end
            local eb = _G[name .. "EditBox"]
            local bg = CFD(cf).bg
            local div = CFD(cf).inputDiv
            local fsc = cf.FontStringContainer
            local track = CFD(cf).scrollTrack

            if eb then
                eb:ClearAllPoints()
                if onTop then
                    eb:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, 3)
                    eb:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, 3)
                else
                    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -10, -8)
                    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -8)
                end
            end

            if div then
                div:ClearAllPoints()
                if onTop then
                    div:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, -20)
                    div:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 10, -20)
                else
                    div:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", -10, -8)
                    div:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 10, -8)
                end
            end

            if bg then
                bg:ClearAllPoints()
                bg:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, 3)
                if onTop then
                    bg:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 10, -6)
                else
                    bg:SetPoint("BOTTOMRIGHT", eb or cf, "BOTTOMRIGHT", 5, eb and -4 or -6)
                end
            end

            if fsc then
                fsc:ClearAllPoints()
                if onTop then
                    fsc:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -22)
                else
                    fsc:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -6)
                end
                fsc:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
            end

            if track then
                track:ClearAllPoints()
                if onTop then
                    track:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -22)
                else
                    track:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -2)
                end
                track:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 5, 2)
            end
        end
    end
end

-- Internal: immediately apply alpha to all chat elements
-- Cache frames for _ApplyAlpha to avoid repeated _G lookups
local _alphaFrames
local function _BuildAlphaCache()
    _alphaFrames = {}
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        local cfd = cf and CFD(cf)
        if cf and cfd.bg then
            _alphaFrames[#_alphaFrames + 1] = {
                cf = cf,
                eb = _G["ChatFrame" .. i .. "EditBox"],
                bg = cfd.bg,
                scrollTrack = cfd.scrollTrack,
                resizeGrip = cfd.resizeGrip,
            }
        end
    end
    -- Cache sidebar + its frame + mode for the fade loop
    local cf1 = _G.ChatFrame1
    _alphaFrames._sidebar = cf1 and CFD(cf1).sidebar
    local cfg = ECHAT.DB()
    _alphaFrames._sidebarMode = cfg and cfg.sidebarVisibility or "always"
end


local function _ApplyAlpha(alpha)
    _chatAlphaCurrent = alpha
    if not _alphaFrames then _BuildAlphaCache() end
    -- Dock manager: once, outside the loop
    if _euiDockStyled and _G.GeneralDockManager then
        _G.GeneralDockManager:SetAlpha(alpha)
    end
    for i = 1, #_alphaFrames do
        local af = _alphaFrames[i]
        local cf = af.cf
        if cf:IsShown() or af.bg:IsShown() then
            cf:SetAlpha(alpha)
            local eb = af.eb
            if eb then
                local focused = eb:HasFocus()
                if issecretvalue and issecretvalue(focused) then focused = false end
                if cf.isTemporary or not focused then
                    eb:SetAlpha(alpha)
                end
            end
            if af.resizeGrip then af.resizeGrip:SetAlpha(alpha * 0.2) end
        end
    end
    -- Active underline: single tracked ref instead of 20-tab loop
    local ul = ns._activeUnderline
    if ul and ul:IsShown() then ul:SetAlpha(alpha) end
    -- Sidebar (mode cached at build time)
    local sb = _alphaFrames._sidebar
    if sb then
        local sbMode = _alphaFrames._sidebarMode
        if sbMode == "mouseover" then
            sb:SetAlpha(min(alpha, _sidebarFadeAlpha))
        elseif sbMode ~= "never" then
            sb:SetAlpha(alpha)
        end
    end
end

-- Animate alpha toward target over FADE_DURATION
local function _SetAlphaTarget(target)
    _chatAlphaTarget = target
    _chatFadeFrame:Show()
end

local _fadeApplyAccum = 0
_chatFadeFrame:SetScript("OnUpdate", function(self, dt)
    if _chatAlphaCurrent == _chatAlphaTarget then
        self:Hide()
        _fadeApplyAccum = 0
        return
    end
    local fadingIn = _chatAlphaTarget > _chatAlphaCurrent
    local duration = fadingIn and FADE_IN_DURATION
        or (_idleFadeActive and IDLE_FADE_OUT_DURATION or FADE_OUT_DURATION)
    local speed = dt / duration
    if fadingIn then
        _chatAlphaCurrent = min(_chatAlphaTarget, _chatAlphaCurrent + speed)
    else
        _chatAlphaCurrent = max(_chatAlphaTarget, _chatAlphaCurrent - speed)
    end
    -- Throttle widget updates to ~30Hz. The alpha step accumulates every
    -- frame but we only push it to widgets every 33ms. Fade is still
    -- smooth; saves 75% of SetAlpha calls at 120fps.
    _fadeApplyAccum = _fadeApplyAccum + dt
    if _fadeApplyAccum < 0.016 then return end
    _fadeApplyAccum = 0
    _ApplyAlpha(_chatAlphaCurrent)
    if _chatAlphaCurrent == _chatAlphaTarget then
        self:Hide()
    end
end)

-- Set alpha for the visibility/mouseover system (animated)
-- This is the top-level authority; idle fade cannot exceed this.
local _visAlpha = 1
function ECHAT.SetChatAlpha(alpha)
    _visAlpha = alpha
    _visChatVisible = (alpha >= 1)
    _SetAlphaTarget(alpha)
end

-- Set alpha for idle fade (animated), clamped to visibility alpha
function ECHAT.SetIdleFadeAlpha(alpha)
    _SetAlphaTarget(min(alpha, _visAlpha))
end

-- Refresh visibility based on DB settings (combat, mouseover, always, etc.)
function ECHAT.RefreshVisibility()
    local cfg = ECHAT.DB()

    local vis = true
    if EUI and EUI.EvalVisibility then
        vis = EUI.EvalVisibility(cfg)
    end

    local alpha
    if vis == false then
        alpha = 0
    else
        alpha = 1
    end

    if alpha == 1 and _idleFadeActive then
        ECHAT.SetIdleFadeAlpha(GetIdleFadeAlpha())
    else
        ECHAT.SetChatAlpha(alpha)
    end
end

-------------------------------------------------------------------------------
--  Chat text helpers
-------------------------------------------------------------------------------
local function StripUIEscapes(text)
    if not text then return "" end
    text = text:gsub("|H.-|h(.-)|h", "%1")   -- hyperlinks -> display text
    text = text:gsub("|T.-|t", "")            -- textures
    text = text:gsub("|A.-|a", "")            -- atlas
    text = text:gsub("|K.-|k", "")            -- secret value placeholders
    text = text:gsub("|n", "\n")              -- newlines
    text = text:gsub("||", "|")               -- escaped pipes
    -- Keep |cXXXXXXXX and |r color codes so the copy popup preserves colors
    return text
end

-- Read all messages directly from the active chat frame on demand.
-- No hooks needed: ScrollingMessageFrame:GetMessageInfo(i) returns
-- the rendered text for each line.
local function ReadActiveChatText()
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local cf = selected or ChatFrame1
    if not cf or not cf.GetNumMessages then return "" end
    local n = cf:GetNumMessages()
    if n == 0 then return "(No chat history)" end
    local lines = {}
    for i = 1, n do
        local ok, text = pcall(cf.GetMessageInfo, cf, i)
        if ok and text and not (issecretvalue and issecretvalue(text)) then
            local sok, stripped = pcall(StripUIEscapes, text)
            if sok and stripped then
                lines[#lines + 1] = stripped
            end
        end
    end
    return table.concat(lines, "\n")
end



-------------------------------------------------------------------------------
--  Copy popup (used by sidebar copy-chat button)
-------------------------------------------------------------------------------

local copyDimmer

local function ShowCopyPopup(text)
    if not EUI.EnsureLoaded then return end
    EUI:EnsureLoaded()

    if not copyDimmer then
        local POPUP_W, POPUP_H = 520, 340

        -- Dimmer
        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)
        dimmer:Hide()
        local dimTex = EUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
        dimTex:SetAllPoints()

        -- Popup frame
        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)

        local bg = EUI.SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
        bg:SetAllPoints()
        EUI.MakeBorder(popup, 1, 1, 1, 0.15, EUI.PanelPP)

        -- ScrollingEditBox (Blizzard template: scrolling + selection built-in)
        local textBox = CreateFrame("Frame", nil, popup, "ScrollingEditBoxTemplate")
        textBox:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -20)
        textBox:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 60)

        local editBox = textBox:GetEditBox()
        editBox:SetFont(GetFont(), 12, EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("chat") or "")
        editBox:SetTextColor(1, 1, 1, 0.75)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dimmer:Hide()
        end)
        editBox:SetScript("OnChar", function(self)
            if self._readOnlyText then
                self:SetText(self._readOnlyText)
                self:HighlightText()
            end
        end)

        -- Thin interactive scrollbar reading from the template's ScrollBox
        local scrollBox = textBox:GetScrollBox()
        local track = CreateFrame("Button", nil, popup)
        track:SetWidth(8)
        track:SetPoint("TOPRIGHT", textBox, "TOPRIGHT", 2, -2)
        track:SetPoint("BOTTOMRIGHT", textBox, "BOTTOMRIGHT", 2, 2)
        track:SetFrameLevel(popup:GetFrameLevel() + 5)
        track:EnableMouse(true)
        track:RegisterForClicks("AnyUp")

        local thumb = track:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(1, 1, 1, 0.27)
        thumb:SetWidth(4)
        thumb:SetHeight(40)
        thumb:SetPoint("TOP", track, "TOP", 0, 0)

        local _sbDragging = false
        local _sbDragOffsetY = 0

        local function UpdateThumb()
            if not scrollBox then thumb:Hide(); return end
            local ext = scrollBox:GetVisibleExtentPercentage()
            if not ext or ext >= 1 then thumb:Hide(); return end
            thumb:Show()
            local trackH = track:GetHeight()
            local thumbH = max(20, trackH * ext)
            thumb:SetHeight(thumbH)
            local pct = scrollBox:GetScrollPercentage() or 0
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(pct * (trackH - thumbH)))
        end

        local function SetScrollFromY(cursorY)
            local trackH = track:GetHeight()
            local ext = scrollBox:GetVisibleExtentPercentage() or 1
            local thumbH = max(20, trackH * ext)
            local maxTravel = trackH - thumbH
            if maxTravel <= 0 then return end
            local trackTop = track:GetTop()
            if not trackTop then return end
            local scale = track:GetEffectiveScale()
            local localY = trackTop - (cursorY / scale) - _sbDragOffsetY
            local pct = max(0, min(1, localY / maxTravel))
            scrollBox:SetScrollPercentage(pct)
        end

        track:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local trackTop = self:GetTop()
            if not trackTop then return end
            -- Check if click is on the thumb
            local thumbTop = thumb:GetTop()
            local thumbBot = thumb:GetBottom()
            if thumbTop and thumbBot then
                local localCursor = cursorY / scale
                if localCursor <= thumbTop and localCursor >= thumbBot then
                    _sbDragOffsetY = thumbTop - localCursor
                    _sbDragging = true
                    return
                end
            end
            -- Click on track: jump to position
            _sbDragOffsetY = (thumb:GetHeight() or 20) / 2
            _sbDragging = true
            SetScrollFromY(cursorY)
        end)
        track:SetScript("OnMouseUp", function() _sbDragging = false end)

        -- Poll only while popup is open
        local pollFrame = CreateFrame("Frame")
        pollFrame:Hide()
        local _lastPct, _lastExt = -1, -1
        pollFrame:SetScript("OnUpdate", function()
            if _sbDragging then
                local _, cursorY = GetCursorPosition()
                SetScrollFromY(cursorY)
            end
            local ext = scrollBox:GetVisibleExtentPercentage() or 1
            local pct = scrollBox:GetScrollPercentage() or 0
            if ext == _lastExt and pct == _lastPct then return end
            _lastExt, _lastPct = ext, pct
            UpdateThumb()
        end)
        dimmer:HookScript("OnShow", function() _lastPct, _lastExt = -1, -1; pollFrame:Show() end)
        dimmer:HookScript("OnHide", function() _sbDragging = false; pollFrame:Hide() end)

        popup._textBox = textBox
        popup._editBox = editBox

        -- Close button
        local closeBtn = CreateFrame("Button", nil, popup)
        closeBtn:SetSize(90, 24)
        closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EUI.MakeStyledButton(closeBtn, "Close", 10,
            EUI.RB_COLOURS, function() dimmer:Hide() end)

        -- Click dimmer to close
        dimmer:SetScript("OnMouseDown", function()
            if not popup:IsMouseOver() then dimmer:Hide() end
        end)

        -- Escape to close (combat-safe: use pcall for SetPropagateKeyboardInput)
        popup:EnableKeyboard(true)
        popup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                pcall(self.SetPropagateKeyboardInput, self, false)
                dimmer:Hide()
            else
                pcall(self.SetPropagateKeyboardInput, self, true)
            end
        end)

        popup._dimmer = dimmer
        copyDimmer = dimmer
        copyDimmer._popup = popup
    end

    -- Populate
    local popup = copyDimmer._popup
    popup._textBox:SetText(text)
    popup._editBox._readOnlyText = text
    copyDimmer:Show()
    C_Timer.After(0.05, function()
        popup._editBox:SetFocus()
        popup._editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
--  URL detection + inline copy popup
-------------------------------------------------------------------------------
local URL_PATTERNS = {
    "%f[%S](%a[%w+.-]+://%S+)",
    "^(%a[%w+.-]+://%S+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+/%S+)",
    "^(www%.[-%w_%%]+%.%a%a+/%S+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",
    "^(www%.[-%w_%%]+%.%a%a+)",
}

-- Cheap literal pre-check: skip all regex if message has no URL-like
-- substring. 99% of chat messages hit this fast path and return false.
local function ContainsURL(text)
    if not text then return false end
    return text:find("://", 1, true) or text:find("www.", 1, true)
end

-- Pre-compute substitution string once (color hex is constant)
local _urlSubstitution
local function _GetUrlSubstitution()
    if not _urlSubstitution then
        local eg = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
        local hex = string.format("|cff%02x%02x%02x", eg.r * 255, eg.g * 255, eg.b * 255)
        _urlSubstitution = hex .. "|H" .. addonName .. "url:%1|h[%1]|h|r"
    end
    return _urlSubstitution
end

local function WrapURLs(text)
    if not text then return text end
    local sub = _GetUrlSubstitution()
    for _, p in ipairs(URL_PATTERNS) do
        text = text:gsub(p, sub)
    end
    return text
end

local urlBackdrop, urlPopup

local function HideUrlPopup()
    if urlPopup then urlPopup:Hide() end
    if urlBackdrop then urlBackdrop:Hide() end
end

local function ShowUrlPopup(url)
    if not urlPopup then
        urlBackdrop = CreateFrame("Button", nil, UIParent)
        urlBackdrop:SetFrameStrata("DIALOG")
        urlBackdrop:SetFrameLevel(499)
        urlBackdrop:SetAllPoints(UIParent)
        local bdTex = urlBackdrop:CreateTexture(nil, "BACKGROUND")
        bdTex:SetAllPoints()
        bdTex:SetColorTexture(0, 0, 0, 0.10)
        local fadeIn = urlBackdrop:CreateAnimationGroup()
        fadeIn:SetToFinalAlpha(true)
        local a = fadeIn:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.2)
        urlBackdrop._fadeIn = fadeIn
        urlBackdrop:RegisterForClicks("AnyUp")
        urlBackdrop:SetScript("OnClick", HideUrlPopup)
        urlBackdrop:Hide()

        urlPopup = CreateFrame("Frame", nil, UIParent)
        urlPopup:SetFrameStrata("DIALOG")
        urlPopup:SetFrameLevel(500)
        urlPopup:SetSize(340, 52)
        urlPopup:EnableMouse(true)
        local popFade = urlPopup:CreateAnimationGroup()
        popFade:SetToFinalAlpha(true)
        local pa = popFade:CreateAnimation("Alpha")
        pa:SetFromAlpha(0); pa:SetToAlpha(1); pa:SetDuration(0.2)
        urlPopup._fadeIn = popFade

        local bg = urlPopup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
        if PP and PP.CreateBorder then
            PP.CreateBorder(urlPopup, 1, 1, 1, 0.15, 1, "OVERLAY", 7)
        end

        local hint = urlPopup:CreateFontString(nil, "OVERLAY")
        hint:SetFont(GetFont(), 8, "")
        hint:SetTextColor(1, 1, 1, 0.5)
        hint:SetPoint("TOP", urlPopup, "TOP", 0, -6)
        hint:SetText("Ctrl+C to copy, Escape to close")

        local eb = CreateFrame("EditBox", nil, urlPopup)
        eb:SetSize(300, 16)
        eb:SetPoint("TOP", hint, "BOTTOM", 0, -4)
        eb:SetFont(GetFont(), 11, "")
        eb:SetAutoFocus(false)
        eb:SetJustifyH("CENTER")
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetColorTexture(0.10, 0.12, 0.16, 1)
        ebBg:SetPoint("TOPLEFT", -6, 4); ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
        if PP and PP.CreateBorder then
            PP.CreateBorder(eb, 1, 1, 1, 0.02, 1, "OVERLAY", 7)
        end
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); HideUrlPopup() end)
        eb:SetScript("OnKeyDown", function(self, key)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0.05, HideUrlPopup)
            end
        end)
        eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        urlPopup:SetScript("OnMouseDown", function() urlPopup._eb:SetFocus(); urlPopup._eb:HighlightText() end)
        urlPopup._eb = eb
    end
    urlPopup._eb:SetText(url)
    urlPopup:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    urlPopup:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx / scale, cy / scale + 10)
    urlBackdrop:SetAlpha(0); urlBackdrop:Show(); urlBackdrop._fadeIn:Play()
    urlPopup:SetAlpha(0); urlPopup:Show(); urlPopup._fadeIn:Play()
    urlPopup._eb:SetFocus(); urlPopup._eb:HighlightText()
end

-------------------------------------------------------------------------------
--  Hyperlink tooltip on hover + click-to-toggle item detail popup
-------------------------------------------------------------------------------
local TOOLTIP_LINK_TYPES = {
    achievement = true, apower = true, currency = true, enchant = true,
    glyph = true, instancelock = true, item = true, keystone = true,
    quest = true, spell = true, talent = true, unit = true,
}

local _hyperlinkEntered = nil

local function OnHyperlinkEnter(self, hyperlink)
    local cfg = ECHAT.DB()
    if cfg.hideTooltipOnHover then return end
    local linkType = hyperlink:match("^([^:]+)")
    if TOOLTIP_LINK_TYPES[linkType] then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(hyperlink)
        GameTooltip:Show()
        _hyperlinkEntered = self
    end
end

local function OnHyperlinkLeave(self)
    if _hyperlinkEntered then
        _hyperlinkEntered = nil
        GameTooltip:Hide()
    end
end

-- URL click handler: open copy popup when user clicks a wrapped URL link.
hooksecurefunc("SetItemRef", function(link)
    if not link then return end
    local url = link:match("^" .. addonName .. "url:(.+)$")
    if url then
        ShowUrlPopup(url)
    end
end)

-------------------------------------------------------------------------------
--  Chat frame reskin
-------------------------------------------------------------------------------
local _skinned = {}

-- Chat message events that indicate real player/NPC chat (not system).
local CHAT_MSG_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_MONSTER_SAY = true, CHAT_MSG_MONSTER_YELL = true,
}

-------------------------------------------------------------------------------
--  Tab reskin: in-place reskin of Blizzard tabs.
--  We work WITH Blizzard's tab system instead of replacing it.
--  Blizzard tabs are stripped of textures and restyled with our visuals.
--  hooksecurefunc on SetAlpha/FCFTab_UpdateColors/FCFDock_SelectWindow
--  keeps our styling applied after Blizzard updates.
-------------------------------------------------------------------------------

-- Texture name suffixes to strip from each tab
local TAB_TEX_SUFFIXES = {
    "Left", "Middle", "Right",
    "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
}

-- Clip frame for underlines: masks them to the dock manager bounds so
-- they don't extend past the visible tab row.  Our frame on UIParent,
-- anchored to gdm -- zero writes to Blizzard frames.
local _ulClipFrame
local function GetULClipFrame()
    if _ulClipFrame then return _ulClipFrame end
    local gdm = _G.GeneralDockManager
    if not gdm then return nil end
    _ulClipFrame = CreateFrame("Frame", nil, UIParent)
    _ulClipFrame:SetPoint("TOPLEFT", gdm, "TOPLEFT", 0, 0)
    _ulClipFrame:SetPoint("BOTTOMRIGHT", gdm, "BOTTOMRIGHT", 0, 0)
    _ulClipFrame:SetClipsChildren(true)
    _ulClipFrame:SetFrameStrata("MEDIUM")
    _ulClipFrame:SetFrameLevel(5)
    return _ulClipFrame
end

-- Update visual state of one skinned tab (colors, underline, pulse)
local function UpdateTabStyle(tab)
    if not tab or not CFD(tab).skinned then return end
    local chatFrame = _G["ChatFrame" .. tab:GetID()]
    if not chatFrame then return end
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local isActive = (chatFrame == selected)

    -- Reparent whisper conversation icon to hidden container
    if tab.conversationIcon and tab.conversationIcon:GetParent() ~= _hiddenParent then
        tab.conversationIcon:SetParent(_hiddenParent)
    end

    -- Use cached tab.Text ref from SkinTab (avoids GetFontString() on
    -- Blizzard tab). Safe here: UpdateTabStyle only runs from deferred
    -- contexts (FCFDock_SelectWindow C_Timer, SkinPass), never inside
    -- FCF_OpenTemporaryWindow's secure chain. If taint resurfaces, rip SetFont first.
    local fs = CFD(tab).tabText
    if fs then
        fs:SetFont(GetFont(), 11, "")
        fs:SetJustifyH("CENTER")
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tab, 0, 0)
        if not chatFrame.isTemporary then
            fs:SetTextColor(1, 1, 1)
        end
    end

    -- Background shade
    if CFD(tab).bg then
        CFD(tab).bg:SetColorTexture(BG_R, BG_G, BG_B, isActive and BG_A or (BG_A * 0.67))
    end

    -- Accent underline -- track the active one for fast ApplyAlpha
    if CFD(tab).underline then
        CFD(tab).underline:SetShown(isActive)
        if isActive then ns._activeUnderline = CFD(tab).underline end
    end

end

-- One-time reskin of a Blizzard chat tab (strip textures, add our visuals)
local function SkinTab(cf)
    local name = cf:GetName()
    if not name then return end
    local tab = _G[name .. "Tab"]
    if not tab or CFD(tab).skinned then return end
    CFD(tab).skinned = true
    -- Strip Blizzard tab textures, but preserve the glow frame
    -- so FCF_StartAlertFlash can animate it for new message alerts.
    for _, suffix in ipairs(TAB_TEX_SUFFIXES) do
        local tex = _G[name .. "Tab" .. suffix] or tab[suffix]
        if tex and tex.SetTexture then tex:SetTexture() end
    end

    -- Dark background
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg._euiOwned = true
    bg:SetAllPoints()
    bg:SetColorTexture(BG_R, BG_G, BG_B, BG_A * 0.67)
    CFD(tab).bg = bg

    -- Accent underline: deferred to avoid pixel snap hooks firing during
    -- chat init's secure window.
    C_Timer.After(0, function()
        local ulHost = CreateFrame("Frame", nil, GetULClipFrame() or UIParent)
        ulHost:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        ulHost:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        ulHost:SetHeight((PP and PP.mult) or 1)
        ulHost:SetFrameStrata("MEDIUM")
        ulHost:SetFrameLevel(5)
        local eg = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
        local underline = ulHost:CreateTexture(nil, "OVERLAY", nil, 6)
        underline:SetAllPoints()
        underline:SetColorTexture(eg.r, eg.g, eg.b, 1)
        ulHost:Hide()
        if EUI.RegAccent then EUI.RegAccent({ type = "solid", obj = underline, a = 1 }) end
        CFD(tab).underline = ulHost
        UpdateTabStyle(tab)
    end)

    -- Hover highlight
    local hover = tab:CreateTexture(nil, "HIGHLIGHT")
    hover._euiOwned = true
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.05)

    -- Cache the tab's text FontString for UpdateTabStyle (avoids
    -- repeated GetFontString() calls on the Blizzard tab).
    -- Some tab implementations use _G[name.."TabText"] instead of tab.Text.
    CFD(tab).tabText = tab.Text or _G[name .. "TabText"]
    tab:SetPushedTextOffset(0, 0)
    tab:SetHeight(24)

    -- Reparent the whisper conversation icon to hidden container
    if tab.conversationIcon then
        tab.conversationIcon:SetParent(_hiddenParent)
    end

    -- Hook SetAlpha: enforce our alpha after Blizzard sets it.
    -- Second arg acts as skip flag to prevent recursion.
    -- Cache chat frame reference to avoid string concat per SetAlpha call
    local _tabCF = _G["ChatFrame" .. tab:GetID()]
    hooksecurefunc(tab, "SetAlpha", function(self, alpha, skip)
        if skip then return end
        if not _tabCF then return end
        local sel = _G.GeneralDockManager and _G.GeneralDockManager.selected
        local isActive = (not _tabCF.isDocked or _tabCF == sel)
        if self.alerting then return end
        self:SetAlpha(isActive and 1 or 0.5, true)
    end)

    -- Hook SetPoint: zero out Blizzard's y=-1 on LEFT/LEFT anchors
    -- (tabs anchored to ScrollFrameChild). Skip tabs 1-2.
    if tab:GetID() >= 3 then
        local _spIgnore = false
        hooksecurefunc(tab, "SetPoint", function(self, point, rel, relPoint, x, y)
            if _spIgnore then return end
            if point == "LEFT" and relPoint == "LEFT" and y and y ~= 0 then
                _spIgnore = true
                local es = self:GetEffectiveScale()
                local onePx = PP and PP.SnapForES and PP.SnapForES(1, es) or 1
                self:SetPoint(point, rel, relPoint, (x or 0) + onePx, 0)
                _spIgnore = false
            end
        end)
    end

    UpdateTabStyle(tab)
end

-- Position and style GeneralDockManager as our tab bar (one-time)
local function StyleDockManager()
    local gdm = _G.GeneralDockManager
    if not gdm or _euiDockStyled then return end
    local cf1 = _G.ChatFrame1
    if not cf1 or not CFD(cf1).bg then return end
    _euiDockStyled = true

    -- Position above our chat bg (matches old EUI_ChatTabBar position)
    gdm:ClearAllPoints()
    gdm:SetPoint("BOTTOMLEFT", CFD(cf1).bg, "TOPLEFT", 0, 0)
    gdm:SetPoint("BOTTOMRIGHT", CFD(cf1).bg, "TOPRIGHT", 0, 0)
    local dockH = 24
    gdm:SetHeight(dockH)
    if _G.GeneralDockManagerScrollFrame then
        _G.GeneralDockManagerScrollFrame:SetHeight(dockH)
    end
    if _G.GeneralDockManagerScrollFrameChild then
        _G.GeneralDockManagerScrollFrameChild:SetHeight(dockH)
    end



    -- Style the overflow button if it exists
    local overflow = _G.GeneralDockManagerOverflowButton
    if overflow then
        overflow:SetAlpha(0.5)
    end

end

-------------------------------------------------------------------------------
--  SkinEditBox: ALL edit box modifications in one place.
--  Chrome/position/font applied to ALL frames (including temp 11+).
--  Header font only on frames 1-10 (touching header on 11+ taints UpdateHeader).
--  History hooks only on frames 1-10 (user-initiated, safe).
-------------------------------------------------------------------------------
local function SkinEditBox(cf)
    local name = cf:GetName()
    if not name then return end
    local eb = _G[name .. "EditBox"]
    local idx = tonumber(name:match("ChatFrame(%d+)"))
    if not eb or not idx or CFD(eb).skinned then return end
    CFD(eb).skinned = true

    -- Hide Blizzard chrome textures
    for _, texName in ipairs({
        name .. "EditBoxLeft", name .. "EditBoxMid", name .. "EditBoxRight",
        name .. "EditBoxFocusLeft", name .. "EditBoxFocusMid", name .. "EditBoxFocusRight",
    }) do
        local tex = _G[texName]
        if tex then tex:SetAlpha(0) end
    end
    if eb.focusLeft then eb.focusLeft:SetAlpha(0) end
    if eb.focusMid then eb.focusMid:SetAlpha(0) end
    if eb.focusRight then eb.focusRight:SetAlpha(0) end

    -- Position flush below chat frame
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -10, -8)
    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -8)
    eb:SetHeight(23)

    -- Font
    local ebSize = GetFrameFontSize(cf:GetID())
    eb:SetFont(GetFont(), ebSize, "")
    eb:SetTextInsets(8, 8, 0, 0)

    -- Apply custom font to the header ("Say:", "Party:", etc.) and suffix.
    -- Called once at skin time and again on focus-gained (covers chat type
    -- switches). Never from inside UpdateHeader -- calling SetFont in that
    -- secure chain taints the execution context and blocks SendChatMessage.
    local function ApplyEditBoxHeaderFont(editBox)
        local sz = GetFrameFontSize(editBox:GetParent():GetID())
        if editBox.header then
            editBox.header:SetFont(GetFont(), sz, "")
        end
        if editBox.headerSuffix then
            editBox.headerSuffix:SetFont(GetFont(), sz, "")
        end
    end
    ApplyEditBoxHeaderFont(eb)
    eb:HookScript("OnEditFocusGained", function(self) ApplyEditBoxHeaderFont(self) end)

    eb:SetAltArrowKeyMode(false)
    if not CFD(eb).history then
            CFD(eb).history = {}
            CFD(eb).histIdx = 0
            hooksecurefunc(eb, "AddHistoryLine", function(self, text)
                if issecretvalue and (issecretvalue(text)) then return end
                local h = CFD(self).history
                local last = h[#h]
                if issecretvalue and last and issecretvalue(last) then
                    h[#h] = nil
                end
                if h[#h] ~= text then
                    h[#h + 1] = text
                    if #h > 50 then table.remove(h, 1) end
                end
            end)
            eb:HookScript("OnKeyDown", function(self, key)
                if key ~= "UP" and key ~= "DOWN" then return end
                -- In M+ keys and boss encounters, Blizzard restricts addon
                -- chat operations. Calling SetText here taints the edit box
                -- execution context, blocking SendChatMessage on next Enter.
                -- Fall back to Blizzard's built-in history in restricted contexts.
                local restricted = GetCVarBool("addonChatRestrictionsForced")
                    or (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
                        and C_ChallengeMode.IsChallengeModeActive())
                if restricted then return end
                local h = CFD(self).history
                if #h == 0 then return end
                if key == "UP" then
                    CFD(self).histIdx = CFD(self).histIdx + 1
                    if CFD(self).histIdx > #h then CFD(self).histIdx = #h end
                elseif key == "DOWN" then
                    CFD(self).histIdx = CFD(self).histIdx - 1
                    if CFD(self).histIdx < 0 then CFD(self).histIdx = 0 end
                end
                if CFD(self).histIdx == 0 then
                    self:SetText("")
                else
                    local entry = h[#h - CFD(self).histIdx + 1]
                    if not entry or (issecretvalue and issecretvalue(entry)) then
                        self:SetText("")
                    else
                        self:SetText(entry)
                    end
                end
            end)
            eb:HookScript("OnEditFocusLost", function(self)
                CFD(self).histIdx = 0
            end)
        end
end

local function SkinChatFrame(cf)
    if not cf or _skinned[cf] then return end
    _skinned[cf] = true
    _alphaFrames = nil
    local name = cf:GetName()
    if not name then return end

    -- No HookScript("OnEvent") on chat frames -- even post-hooks taint
    -- the C-level event dispatcher. Idle reset + pulse detection are
    -- handled by standalone event frames (see sections 5/6 below).

    -- Unified dark background (covers chat + edit box as one panel)
    if not CFD(cf).bg then
        local bg = CreateFrame("Frame", nil, cf)
        local eb = _G[name .. "EditBox"]
        bg:SetPoint("TOPLEFT", cf, "TOPLEFT", -10, 3)
        bg:SetPoint("BOTTOMRIGHT", eb or cf, "BOTTOMRIGHT", 5, eb and -4 or -6)
        bg:SetFrameLevel(max(0, cf:GetFrameLevel() - 1))

        local bgTex = bg:CreateTexture(nil, "BACKGROUND")
        bgTex._euiOwned = true
        bgTex:SetAllPoints()
        bgTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)

        if not cf:IsShown() then
            bg:Hide()
            cf:HookScript("OnShow", function() bg:Show() end)
        end
        CFD(cf).bg = bg
    end

    -- Sidebar: 40px panel to the left of the main chat frame for icons.
    -- Parented to UIParent so it stays visible regardless of active tab.
    if name == "ChatFrame1" and not CFD(cf).sidebar then
        local sidebar = CreateFrame("Frame", nil, UIParent)
        sidebar:SetWidth(40)
        sidebar:SetPoint("TOPRIGHT", CFD(cf).bg, "TOPLEFT", 0, 0)
        sidebar:SetPoint("BOTTOMRIGHT", CFD(cf).bg, "BOTTOMLEFT", 0, 0)
        sidebar:SetFrameStrata(cf:GetFrameStrata())
        sidebar:SetFrameLevel(cf:GetFrameLevel() + 1)

        local sbBg = sidebar:CreateTexture(nil, "BACKGROUND")
        sbBg:SetAllPoints()
        sbBg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)

        -- Sidebar mouseover hover (for "mouseover" visibility mode)
        sidebar:EnableMouse(true)
        sidebar:SetScript("OnEnter", function()
            local cfg = ECHAT.DB()
            if cfg.sidebarVisibility == "mouseover" then
                _sidebarFadeTarget = 1
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
                        _sidebarFadeTarget = 0
                        if _sidebarFadeFrame then _sidebarFadeFrame:Show() end
                    end
                end)
            end
        end)

        -- 1px vertical divider between sidebar and chat bg
        local onePx = (PP and PP.mult) or 1
        local sbDiv = sidebar:CreateTexture(nil, "OVERLAY", nil, 7)
        sbDiv._euiOwned = true
        sbDiv:SetWidth(onePx)
        sbDiv:SetColorTexture(1, 1, 1, 0.06)
        sbDiv:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
        sbDiv:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
        if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(sbDiv) end
        CFD(cf).sidebarDiv = sbDiv

        local MEDIA = "Interface\\AddOns\\EllesmereUIChat\\Media\\"
        local ICON_SIZE = 22
        local ICON_SPACING = 10
        local ICON_ALPHA = 0.4
        local ICON_HOVER_ALPHA = 0.9

        local function MakeSidebarIcon(parent, texPath, anchorTo, anchorPoint, yOff)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(ICON_SIZE, ICON_SIZE)
            if anchorTo then
                btn:SetPoint("TOP", anchorTo, "BOTTOM", 0, -ICON_SPACING)
            else
                btn:SetPoint(anchorPoint or "TOP", parent, anchorPoint or "TOP", 0, yOff or -ICON_SPACING)
            end
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture(texPath)
            icon:SetDesaturated(true)
            icon:SetVertexColor(1, 1, 1, ICON_ALPHA)
            btn:HookScript("OnEnter", function() icon:SetVertexColor(1, 1, 1, ICON_HOVER_ALPHA) end)
            btn:HookScript("OnLeave", function() icon:SetVertexColor(1, 1, 1, ICON_ALPHA) end)
            btn._icon = icon
            return btn
        end

        -- Read visibility + ordering config at creation time
        local icfg = ECHAT.DB()
        local showFriends  = icfg.showFriends ~= false
        local showCopy     = icfg.showCopy ~= false
        local showPortals  = icfg.showPortals ~= false
        local showVoice    = icfg.showVoice ~= false
        local showSettings = icfg.showSettings ~= false
        local iconOrder    = icfg.sidebarIconOrder or {}

        -- Friends + count (always first when enabled)
        local anchor = nil
        local friendsBtn, friendsCount, copyBtn, portalBtn, voiceBtn, settingsBtn

        if showFriends then
            friendsBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_friends.png", nil, "TOP", -ICON_SPACING)
            friendsBtn:SetSize(26, 26)

            friendsCount = sidebar:CreateFontString(nil, "OVERLAY")
            friendsCount:SetFont(GetFont(), 9, "")
            friendsCount:SetTextColor(1, 1, 1, 0.5)
            friendsCount:SetPoint("TOP", friendsBtn, "BOTTOM", 0, 7)
            friendsCount:SetText("0")

            friendsBtn:HookScript("OnEnter", function(self)
                friendsCount:SetTextColor(1, 1, 1, 0.9)
                if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                    EUI.ShowWidgetTooltip(self, "Friends")
                end
            end)
            friendsBtn:HookScript("OnLeave", function()
                friendsCount:SetTextColor(1, 1, 1, 0.5)
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)

            local function UpdateFriendsCount()
                local _, numOnline = BNGetNumFriends()
                local wowOnline = C_FriendList.GetNumOnlineFriends()
                friendsCount:SetText(numOnline + wowOnline)
            end

            local fcEvents = CreateFrame("Frame")
            fcEvents:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
            fcEvents:RegisterEvent("BN_FRIEND_INFO_CHANGED")
            fcEvents:RegisterEvent("FRIENDLIST_UPDATE")
            fcEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            fcEvents:SetScript("OnEvent", UpdateFriendsCount)

            CFD(cf).friendsCount = friendsCount
            anchor = friendsCount
        end

        -- Middle group: ordered by sidebarIconOrder config
        local middleIcons = {
            { key = "showCopy",     show = showCopy,     tex = "chat_copy.png" },
            { key = "showPortals",  show = showPortals,  tex = "chat_portal.png", size = 26 },
            { key = "showVoice",    show = showVoice,    tex = "chat_voice.png" },
            { key = "showSettings", show = showSettings,  tex = "chat_settings.png" },
        }
        table.sort(middleIcons, function(a, b)
            local oa = iconOrder[a.key]; if type(oa) ~= "number" then oa = 999 end
            local ob = iconOrder[b.key]; if type(ob) ~= "number" then ob = 999 end
            return oa < ob
        end)

        local middleBtns = {}
        for _, info in ipairs(middleIcons) do
            if info.show then
                local btn = MakeSidebarIcon(sidebar, MEDIA .. info.tex)
                if info.size then btn:SetSize(info.size, info.size) end
                btn:ClearAllPoints()
                if anchor then
                    btn:SetPoint("TOP", anchor, "BOTTOM", 0, -ICON_SPACING)
                else
                    btn:SetPoint("TOP", sidebar, "TOP", 0, -ICON_SPACING)
                end
                anchor = btn
                middleBtns[info.key] = btn
            end
        end
        copyBtn     = middleBtns["showCopy"]
        portalBtn   = middleBtns["showPortals"]
        voiceBtn    = middleBtns["showVoice"]
        settingsBtn = middleBtns["showSettings"]

        -- Bottom: Scroll (anchored to bottom with gap)
        local scrollBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_scroll2.png")
        scrollBtn:SetSize(22, 22)
        scrollBtn:ClearAllPoints()
        scrollBtn:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, ICON_SPACING)

        -- Sidebar icon tooltips
        local function HookIconTooltip(btn, label)
            btn:HookScript("OnEnter", function(self)
                if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                    EUI.ShowWidgetTooltip(self, label)
                end
            end)
            btn:HookScript("OnLeave", function()
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)
        end
        if copyBtn then HookIconTooltip(copyBtn, "Copy Chat") end
        if voiceBtn then HookIconTooltip(voiceBtn, "Voice/Channels") end
        if settingsBtn then HookIconTooltip(settingsBtn, "Settings") end
        HookIconTooltip(scrollBtn, "Scroll to Bottom")

        -- Scroll to bottom
        scrollBtn:SetScript("OnClick", function()
            local cf1 = ChatFrame1
            if cf1 and cf1.ScrollBar and cf1.ScrollBar.SetScrollPercentage then
                cf1.ScrollBar:SetScrollPercentage(1)
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

        -- Friends button toggles FriendsFrame
        if friendsBtn then
        friendsBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
                return
            end
            ToggleFriendsFrame()
        end)
        end

        -- Portals button click handler

        if portalBtn then
        portalBtn:SetScript("OnClick", function(self)
            if InCombatLockdown() then return end
            ECHAT.TogglePortalFlyout(self)
        end)
        HookIconTooltip(portalBtn, "M+ Portals")
        end

        -- Voice button toggles ChannelFrame
        if voiceBtn then
        voiceBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            ToggleChannelFrame()
        end)
        end

        -- Settings button toggles EUI options on Chat module
        if settingsBtn then
        settingsBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            local mf = EUI._mainFrame
            if mf and mf:IsShown() and EUI:GetActiveModule() == "EllesmereUIChat" then
                mf:Hide()
            else
                EUI:ShowModule("EllesmereUIChat")
                -- Scroll sidebar to bottom so Chat (in the reskin group) is visible
                C_Timer.After(0, function()
                    local sf = EUI._addonScrollFrame
                    if sf then
                        local max = sf:GetVerticalScrollRange() or 0
                        sf:SetVerticalScroll(max)
                        -- Poke scroll child to trigger OnScrollRangeChanged (updates thumb)
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
        sbd.copyBtn = copyBtn
        sbd.portalBtn = portalBtn
        sbd.voiceBtn = voiceBtn
        sbd.settingsBtn = settingsBtn
        sbd.scrollBtn = scrollBtn

        CFD(cf).sidebar = sidebar
    end

    -- Top clip: prevent text bleeding into the tab area.
    -- Left/right padding is not possible without a custom renderer --
    -- Blizzard's font strings are positioned absolutely by the layout
    -- engine and ignore FSC container bounds.
    local fsc = cf.FontStringContainer
    if fsc and not CFD(cf).topClipped then
        CFD(cf).topClipped = true
        fsc:ClearAllPoints()
        fsc:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -6)
        fsc:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
    end

    -- Horizontal divider above input field
    if not CFD(cf).inputDiv then
        local onePx = (PP and PP.mult) or 1
        local div = CFD(cf).bg:CreateTexture(nil, "OVERLAY", nil, 7)
        div._euiOwned = true
        div:SetHeight(onePx)
        div:SetColorTexture(1, 1, 1, 0.06)
        div:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", -10, -8)
        div:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 10, -8)
        if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(div) end
        CFD(cf).inputDiv = div
    end

    -- Chat frame font/shadow/fade (one-time, at login)
    local cfId = cf:GetID()
    cf:SetFont(GetFont(), GetFrameFontSize(cfId), GetOutlineFlag())
    if cf.SetShadowOffset then cf:SetShadowOffset(1, -1) end
    if cf.SetShadowColor then cf:SetShadowColor(0, 0, 0, 0.8) end
    cf:SetFading(false)

    -- 3. Hyperlink handlers (per-frame, on our bg frame -- not on Blizzard's cf)
    --    OnHyperlinkEnter/Leave for tooltip, OnHyperlinkClick for item toggle
    if not CFD(cf).hyperlinkHooked then
        CFD(cf).hyperlinkHooked = true
        cf:HookScript("OnHyperlinkEnter", OnHyperlinkEnter)
        cf:HookScript("OnHyperlinkLeave", OnHyperlinkLeave)
        -- Item tooltip toggle + URL click handled by global SetItemRef hook
    end

    -- 4. Edit box
    SkinEditBox(cf)


    -- 5. Tab (consolidated in SkinTab -- strips textures, sets height,
    --    creates bg/pulse/underline, click hook)
    SkinTab(cf)

    -- 6. Hide Blizzard button frame
    local btnFrame = _G[name .. "ButtonFrame"]
    if btnFrame then
        btnFrame:SetParent(_hiddenParent)
    end

    -- Restyle Blizzard's resize button to align with our bg (all chat frames).
    local resizeBtn = _G[name .. "ResizeButton"]
    if resizeBtn and CFD(cf).bg then
        resizeBtn:SetSize(18, 18)
        resizeBtn:ClearAllPoints()
        resizeBtn:SetPoint("BOTTOMRIGHT", CFD(cf).bg, "BOTTOMRIGHT", -2, 2)
        resizeBtn:SetFrameStrata("HIGH")
        if resizeBtn.GetRegions then
            for ri = 1, select("#", resizeBtn:GetRegions()) do
                local region = select(ri, resizeBtn:GetRegions())
                if region and region:IsObjectType("Texture") then
                    region:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png")
                    region:SetDesaturated(true)
                    region:SetVertexColor(1, 1, 1)
                    region:SetAllPoints()
                end
            end
        end
        resizeBtn:SetAlpha(0.2)
        resizeBtn:HookScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        resizeBtn:HookScript("OnLeave", function(self) self:SetAlpha(0.2) end)
    end

    -- Custom resize grip removed: Blizzard is sole authority for chat sizing.
    -- Blizzard's resize button (restyled above) handles all resizing natively.

    -- Hide scroll buttons + scroll-to-bottom
    for _, suffix in ipairs({"BottomButton", "DownButton", "UpButton"}) do
        local btn = _G[name .. suffix]
        if btn then btn:SetAlpha(0); btn:EnableMouse(false) end
    end
    if cf.ScrollToBottomButton then
        cf.ScrollToBottomButton:SetParent(_hiddenParent)
    end

    -- Minimize button
    local minBtn = _G[name .. "MinimizeButton"]
    if minBtn then minBtn:SetAlpha(0); minBtn:EnableMouse(false) end

    -- Strip ALL Blizzard textures from the chat frame by walking every
    -- region. Only targets Texture objects and skips anything we created
    -- (our textures have _eui prefix fields).
    if cf.GetRegions then
        for i = 1, select("#", cf:GetRegions()) do
            local region = select(i, cf:GetRegions())
            if region and region:IsObjectType("Texture") and not region._euiOwned then
                region:SetTexture("")
                region:SetAtlas("")
                region:SetAlpha(0)
            end
        end
    end
    -- Also strip the Background child frame and its regions
    if cf.Background then
        cf.Background:SetAlpha(0)
        if cf.Background.GetRegions then
            for i = 1, select("#", cf.Background:GetRegions()) do
                local region = select(i, cf.Background:GetRegions())
                if region and region:IsObjectType("Texture") then
                    region:SetAlpha(0)
                end
            end
        end
    end

    -- Let clicks pass through to the game world
    cf:SetHyperlinksEnabled(true)

    -- Combat Log: replace Blizzard's filter tab bar with our own dark bar
    -- that matches the chat panel's width and style.
    if name == "ChatFrame2" then
        local qbf = _G.CombatLogQuickButtonFrame_Custom
        if qbf and not CFD(qbf).skinned then
            CFD(qbf).skinned = true

            -- Strip all default textures
            if qbf.GetRegions then
                for i = 1, select("#", qbf:GetRegions()) do
                    local region = select(i, qbf:GetRegions())
                    if region and region:IsObjectType("Texture") then
                        region:SetAlpha(0)
                    end
                end
            end

            -- Anchor flush: bottom of filter bar meets top of bg (cf top + 3),
            -- width matches bg (-10 left, +5 right)
            qbf:ClearAllPoints()
            qbf:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -10, 3)
            qbf:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 10, 3)
            qbf:SetHeight(24)

            -- Dark background matching our panel
            local qbfBg = qbf:CreateTexture(nil, "BACKGROUND")
            qbfBg:SetAllPoints()
            qbfBg:SetColorTexture(BG_R, BG_G, BG_B, 1)


            -- Bottom divider (separates filter tabs from messages)
            local onePx = (PP and PP.mult) or 1
            local qbfDiv = qbf:CreateTexture(nil, "OVERLAY", nil, 7)
            qbfDiv._euiOwned = true
            qbfDiv:SetHeight(onePx)
            qbfDiv:SetColorTexture(1, 1, 1, 0.06)
            qbfDiv:SetPoint("BOTTOMLEFT", qbf, "BOTTOMLEFT", 0, 0)
            qbfDiv:SetPoint("BOTTOMRIGHT", qbf, "BOTTOMRIGHT", 0, 0)
            if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(qbfDiv) end

            -- Restyle the filter buttons and accent-color the active one
            local EG = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
            local clFilterBtns = {}
            local function UpdateCLFilterColors()
                for _, btn in ipairs(clFilterBtns) do
                    local fs = btn:GetFontString()
                    if not fs then return end
                    local isActive = btn.GetChecked and btn:GetChecked()
                    if isActive then
                        local eg = EUI.ELLESMERE_GREEN or EG
                        fs:SetTextColor(eg.r, eg.g, eg.b, 1)
                    else
                        fs:SetTextColor(1, 1, 1, 0.5)
                    end
                end
            end
            if qbf.GetChildren then
                for i = 1, select("#", qbf:GetChildren()) do
                    local btn = select(i, qbf:GetChildren())
                    if btn and btn:IsObjectType("CheckButton") or (btn and btn:IsObjectType("Button")) then
                        clFilterBtns[#clFilterBtns + 1] = btn
                        -- Strip button textures
                        if btn.GetRegions then
                            for j = 1, select("#", btn:GetRegions()) do
                                local rgn = select(j, btn:GetRegions())
                                if rgn and rgn:IsObjectType("Texture") then
                                    rgn:SetAlpha(0)
                                end
                            end
                        end
                        -- Restyle the text
                        local fs = btn:GetFontString()
                        if fs then
                            fs:SetFont(GetFont(), 12, "")
                        end
                        -- Update colors on click
                        btn:HookScript("OnClick", UpdateCLFilterColors)
                    end
                end
            end
            UpdateCLFilterColors()
            if EUI.RegAccent then
                EUI.RegAccent({ type = "callback", fn = UpdateCLFilterColors })
            end

            -- One-time alpha set. No reactive hook -- hooksecurefunc on
            -- SetAlpha taints execution during whisper/tab processing.
            qbf:SetAlpha(1)

            -- Don't extend bg upward -- the filter bar has its own bg (qbfBg).
            -- Keeping both chat frame bgs the same size prevents visual
            -- jumping when switching between General and Combat Log tabs.
        end
    end

    -- Skip scrollbar entirely for undocked temporary frames in M+ / raid / PvP combat
    if cf.isTemporary and not cf.isDocked then
        local _, instanceType = IsInInstance()
        local inMPlus = instanceType == "party" and C_ChallengeMode
            and C_ChallengeMode.IsChallengeModeActive
            and C_ChallengeMode.IsChallengeModeActive()
        local inRaidCombat = instanceType == "raid" and InCombatLockdown()
        local inPvP = (instanceType == "pvp" or instanceType == "arena") and InCombatLockdown()
        if inMPlus or inRaidCombat or inPvP then return end
    end

    -- Kill Blizzard's ScrollBar
    if cf.ScrollBar then
        cf.ScrollBar:UnregisterAllEvents()
        cf.ScrollBar:SetParent(_hiddenParent)
        cf.ScrollBar:Hide()
    end

    -- Thin scrollbar: reads scroll state from Blizzard's own ScrollBar.
    -- Clickable + draggable. Parented to our bg frame.
    if not CFD(cf).scrollTrack and cf.ScrollBar then
        local blizSB = cf.ScrollBar
        local track = CreateFrame("Button", nil, CFD(cf).bg)
        track:SetFrameLevel(CFD(cf).bg:GetFrameLevel() + 10)
        track:SetWidth(8)
        track:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -2)
        track:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 5, 2)
        track:SetClipsChildren(true)
        track:EnableMouse(true)
        track:RegisterForClicks("AnyUp")

        local thumb = track:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(1, 1, 1, 0.25)
        thumb:SetWidth(3)
        thumb:Hide()

        -- Only show scrollbar when hovering the chat area.
        -- Scrollbar fade in/out with hover + drag awareness.
        -- Track stays visible (for OnUpdate) but alpha controls visibility.
        local _hovered = false
        local _dragging = false
        local _dragOffsetY = 0
        local _trackAlpha = 0
        local _trackTarget = 0
        local _lastPct, _lastExt = -1, -1
        local FADE_SPEED = 1 / 0.25  -- full fade in 0.25s

        local function ShowTrack() _trackTarget = 1; _lastPct = -1; _lastExt = -1; track:Show() end
        local function HideTrack() _trackTarget = 0 end

        local function CheckHover()
            local ok, over = pcall(function()
                return _dragging or CFD(cf).bg:IsMouseOver() or track:IsMouseOver()
            end)
            if ok and over then
                _hovered = true; ShowTrack()
            else
                _hovered = false; HideTrack()
            end
        end

        CFD(cf).bg:EnableMouse(false)
        -- bg OnEnter/OnLeave removed -- hover detection is in the polling ticker
        track._showTrack = ShowTrack
        track._hideTrack = HideTrack
        track._isHovered = function() return _hovered end
        track._isDragging = function() return _dragging end
        track._setHovered = function(v) _hovered = v end
        track:HookScript("OnEnter", function() _hovered = true; ShowTrack() end)
        track:HookScript("OnLeave", function()
            if not _dragging then
                _hovered = false; HideTrack()
            end
        end)
        track:SetAlpha(0)
        track:Hide()

        local function GetThumbState()
            local pct = blizSB.GetScrollPercentage and blizSB:GetScrollPercentage()
            local ext = blizSB.GetVisibleExtentPercentage and blizSB:GetVisibleExtentPercentage()
            if not pct or not ext or ext >= 1 then return nil end
            local trackH = track:GetHeight()
            if trackH <= 0 then return nil end
            local thumbH = max(20, trackH * ext)
            return pct, ext, trackH, thumbH
        end

        local function UpdateThumb()
            local pct, ext, trackH, thumbH = GetThumbState()
            if not pct or (not _hovered and not _dragging) then thumb:Hide(); return end
            local yOff = (trackH - thumbH) * pct
            thumb:SetHeight(thumbH)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -yOff)
            thumb:Show()
        end

        local function SetScrollFromY(cursorY)
            local pct, ext, trackH, thumbH = GetThumbState()
            if not pct then return end
            local _, trackTop = track:GetCenter()
            trackTop = select(2, track:GetRect()) + trackH
            local localY = trackTop - cursorY - _dragOffsetY
            local scrollRange = trackH - thumbH
            if scrollRange <= 0 then return end
            local newPct = max(0, min(1, localY / scrollRange))
            if blizSB.SetScrollPercentage then
                blizSB:SetScrollPercentage(newPct)
            end
        end

        -- Click on track: jump to that position
        track:SetScript("OnClick", function(self, button)
            local pct, ext, trackH, thumbH = GetThumbState()
            if not pct then return end
            local _, cursorY = GetCursorPosition()
            cursorY = cursorY / self:GetEffectiveScale()
            local trackBottom = select(2, track:GetRect())
            local localY = cursorY - trackBottom
            local scrollRange = trackH - thumbH
            if scrollRange <= 0 then return end
            local newPct = max(0, min(1, 1 - (localY - thumbH / 2) / scrollRange))
            if blizSB.SetScrollPercentage then
                blizSB:SetScrollPercentage(newPct)
            end
            UpdateThumb()
        end)

        -- Drag: mousedown on track starts drag, mouseup ends
        track:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local pct, ext, trackH, thumbH = GetThumbState()
            if not pct then return end
            local _, cursorY = GetCursorPosition()
            cursorY = cursorY / self:GetEffectiveScale()
            -- Calculate offset from thumb top so dragging feels anchored
            local trackBottom = select(2, track:GetRect())
            local thumbTop = trackBottom + trackH - (trackH - thumbH) * pct
            _dragOffsetY = cursorY - thumbTop + thumbH
            _dragging = true
        end)

        track:SetScript("OnMouseUp", function()
            _dragging = false
            C_Timer.After(0, CheckHover)
        end)

        track:SetScript("OnUpdate", function(self, dt)
            -- Fade alpha toward target
            if _trackAlpha ~= _trackTarget then
                local step = FADE_SPEED * dt
                if _trackTarget > _trackAlpha then
                    _trackAlpha = min(_trackTarget, _trackAlpha + step)
                else
                    _trackAlpha = max(_trackTarget, _trackAlpha - step)
                end
                self:SetAlpha(_trackAlpha)
                if _trackAlpha <= 0 and _trackTarget <= 0 then
                    self:Hide()
                    return
                end
            end

            if _dragging then
                if not IsMouseButtonDown("LeftButton") then
                    _dragging = false
                    CheckHover()
                    return
                end
                local _, cursorY = GetCursorPosition()
                cursorY = cursorY / self:GetEffectiveScale()
                local pct, ext, trackH, thumbH = GetThumbState()
                if pct then
                    local trackBottom = select(2, track:GetRect())
                    local localY = cursorY - trackBottom - _dragOffsetY
                    local scrollRange = trackH - thumbH
                    if scrollRange > 0 then
                        local visualPct = max(0, min(1, 1 - localY / scrollRange))
                        local yOff = (trackH - thumbH) * visualPct
                        thumb:ClearAllPoints()
                        thumb:SetHeight(thumbH)
                        thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -yOff)
                        thumb:Show()
                        if blizSB.SetScrollPercentage then
                            blizSB:SetScrollPercentage(visualPct)
                        end
                    end
                end
            else
                self._elapsed = (self._elapsed or 0) + dt
                if self._elapsed < 0.15 then return end
                self._elapsed = 0
                local pct = blizSB.GetScrollPercentage and blizSB:GetScrollPercentage()
                local ext = blizSB.GetVisibleExtentPercentage and blizSB:GetVisibleExtentPercentage()
                if pct == _lastPct and ext == _lastExt then
                    return
                end
                _lastPct, _lastExt = pct, ext
                UpdateThumb()
            end
        end)

        CFD(cf).scrollTrack = track
    end
end

-------------------------------------------------------------------------------
--  Tab color updater -- refreshes all skinned Blizzard tabs
-------------------------------------------------------------------------------
local function UpdateTabColors()
    StyleDockManager()

    for i = 1, 20 do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and CFD(tab).skinned then
            UpdateTabStyle(tab)
        end
    end

    -- Re-chain docked tab anchors with consistent 1px physical gap
    if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then
        local onePx = PP and PP.mult or 1
        local prev = nil
        for _, cf in ipairs(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) do
            local n = cf and cf:GetName()
            local tab = n and _G[n .. "Tab"]
            if tab and tab:IsShown() then
                if prev then
                    tab:SetPoint("LEFT", prev, "RIGHT", onePx, 0)
                end
                prev = tab
            end
        end
    end
    -- Only show resize grip when General (ChatFrame1) is the active tab
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local cf1 = _G.ChatFrame1
    if cf1 and CFD(cf1).resizeGrip then
        local cfg = ECHAT.DB()
        local locked = cfg and cfg.lockChatSize
        CFD(cf1).resizeGrip:SetShown(not locked and selected == cf1)
    end
end


-------------------------------------------------------------------------------
--  Initialization (PLAYER_LOGIN)
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    EnsureDB()

    ---------------------------------------------------------------------------
    --  1. Load saved background color/opacity before skinning any frames
    ---------------------------------------------------------------------------
    local p = ECHAT.DB()
    BG_R = p.bgR or BG_R
    BG_G = p.bgG or BG_G
    BG_B = p.bgB or BG_B
    BG_A = p.bgAlpha or BG_A

    ---------------------------------------------------------------------------
    --  2. Skin all 20 chat frames (bg, tabs, scrollbar, edit box, etc.)
    ---------------------------------------------------------------------------
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf then SkinChatFrame(cf) end
    end
    ---------------------------------------------------------------------------
    --  2b. Expanded font size options. Font is applied at skin time only.
    --      The global hooksecurefunc("FCF_SetChatWindowFontSize") was removed
    --      because it tainted FCFDock_UpdateTabs -> PanelTemplates_TabResize.
    ---------------------------------------------------------------------------
    CHAT_FONT_HEIGHTS = { 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }


    ---------------------------------------------------------------------------
    --  2c. Clickable URLs via message event filters
    ---------------------------------------------------------------------------
    local URL_EVENTS = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER",
        "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
    }
    local function UrlFilter(self, event, msg, ...)
        if not msg or not ContainsURL(msg) then return false end
        return false, WrapURLs(msg), ...
    end
    for _, ev in ipairs(URL_EVENTS) do
        ChatFrame_AddMessageEventFilter(ev, UrlFilter)
    end

    ---------------------------------------------------------------------------
    --  3. Temporary window detection (whisper windows)
    --     1s ticker checks for unskinned frames. Replaces the global
    --     hooksecurefunc("FCF_OpenTemporaryWindow") which tainted edit box
    --     header arithmetic during window creation.
    ---------------------------------------------------------------------------
    -- Shared skin pass: skins unskinned frames, re-strips tabs,
    -- re-applies font, hides Blizzard chrome. Called from whisper
    -- events and protected state watcher -- no timers.
    local function SkinPass()
        local wantFont = GetFont()
        local wantOutline = GetOutlineFlag()
        for i = 1, 20 do
            local cf = _G["ChatFrame" .. i]
            -- Skin new frames (calls SkinEditBox + SkinTab internally)
            if cf and not _skinned[cf] then
                SkinChatFrame(cf)
            end
            -- Ensure tab is skinned (new temp windows, pool reuse)
            if cf then
                SkinTab(cf)
                -- Re-enforce height (Blizzard resets it on temp window creation)
                local tab = _G["ChatFrame" .. i .. "Tab"]
                if tab and CFD(tab).skinned then
                    tab:SetHeight(24)
                end
            end
            -- Re-apply font if Blizzard reset it (e.g. font size change)
            if cf and _skinned[cf] then
                local curFont = cf:GetFont()
                if curFont and curFont ~= wantFont then
                    local _, sz = cf:GetFont()
                    cf:SetFont(wantFont, sz, wantOutline)
                end
            end
        end
        UpdateTabColors()
        if ECHAT.ApplyInputPosition then ECHAT.ApplyInputPosition() end
    end

    ---------------------------------------------------------------------------
    --  4. Global tab hooks (hooksecurefunc on globals).
    ---------------------------------------------------------------------------
    if FCFDock_SelectWindow then
        hooksecurefunc("FCFDock_SelectWindow", function()
            C_Timer.After(0, UpdateTabColors)
        end)
    end
    -- DO NOT hook FCFTab_UpdateColors -- it fires INSIDE
    -- FCF_OpenTemporaryWindow's secure chain and taints even safe
    -- operations like SetTextColor (session 46 root cause #1).
    -- Tab text coloring is handled in UpdateTabStyle instead, which
    -- runs from FCFDock_SelectWindow (deferred, outside secure chain).
    -- Tab close: Blizzard resets all tab colors via FCFTab_UpdateColors
    -- but FCFDock_SelectWindow only fires if the ACTIVE tab was closed.
    -- Closing a non-active tab skips our color refresh. FCF_Close is a
    -- top-level user action, safe to hook (not inside a secure chain).
    if FCF_Close then
        hooksecurefunc("FCF_Close", function()
            C_Timer.After(0, UpdateTabColors)
        end)
    end
    -- Temp window creation: re-run SkinPass to catch new frames.
    if FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            C_Timer.After(0, SkinPass)
        end)
    end

    -- Pin scroll frame flush to dock manager after Blizzard's dock is
    -- fully set up. Can't do this in StyleDockManager (too early, breaks
    -- tab chain). PLAYER_ENTERING_WORLD fires after the dock is ready.
    local function PinScrollFrame()
        local gdm2 = _G.GeneralDockManager
        local sf = _G.GeneralDockManagerScrollFrame
        local sfc = _G.GeneralDockManagerScrollFrameChild
        -- Don't override sf anchoring -- Blizzard's default stops at the
        -- overflow button, which is what hides overflow tabs natively.
        -- sf is a child of gdm, so it follows our dock repositioning.
        -- Height is already set in StyleDockManager.
        if sfc then
            sfc:ClearAllPoints()
            sfc:SetPoint("BOTTOMLEFT", sf, "BOTTOMLEFT", 0, 0)
            local dockH2 = 24
            sfc:SetHeight(dockH2)
        end
        UpdateTabColors()
    end
    do
        local pinFrame = CreateFrame("Frame")
        pinFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
        pinFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            PinScrollFrame()
            -- Re-chain docked tab anchors: Blizzard positions tabs BEFORE
            -- our SetPoint hooks are installed (dock setup < PLAYER_LOGIN).
            -- Re-anchor each docked tab to its predecessor so the chain
            -- is correct and our hooks fire on subsequent updates.
            -- Fix only the first docked tab after the main two (General/Combat).
            -- Its anchor to ScrollFrameChild is wrong because Blizzard set it
            -- before our SetPoint hook was installed.
            -- Re-chain all docked tabs with consistent 1px physical gap.
            -- Blizzard positions tabs before our SetPoint hooks exist,
            -- so tabs 3+ have wrong anchors on initial load.
            if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then
                local onePx = PP and PP.mult or 1
                local prev = nil
                for _, cf in ipairs(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) do
                    local n = cf and cf:GetName()
                    local tab = n and _G[n .. "Tab"]
                    if tab and tab:IsShown() then
                        if prev then
                            tab:ClearAllPoints()
                            tab:SetPoint("LEFT", prev, "RIGHT", onePx, 0)
                        end
                        prev = tab
                    end
                end
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  5. Tab color management
    --     Deferred update batches multiple tab changes into one pass.
    ---------------------------------------------------------------------------
    C_Timer.After(0, UpdateTabColors)
    local _tabColorTimer
    local function DeferredTabColorUpdate()
        if _tabColorTimer then return end
        _tabColorTimer = true
        C_Timer.After(0, function()
            _tabColorTimer = nil
            UpdateTabColors()
        end)
    end
    ECHAT._deferredTabColorUpdate = DeferredTabColorUpdate


    ---------------------------------------------------------------------------
    --  6. Idle fade system
    --     Dims chat after N seconds of inactivity. Resets on: new message
    --     on active tab, whisper window, edit box focus/typing, or cursor
    --     entering the chat area (event-driven via OnEnter/OnLeave).
    ---------------------------------------------------------------------------
    do
        local idleTimer = nil

        local function IsIdleApplicable()
            local cfg = ECHAT.DB()
            local vis = cfg.visibility or "always"
            return vis ~= "never"
        end

        local function StartIdleFade()

            if _idleFadeActive then return end
            _idleFadeActive = true
            ECHAT.SetIdleFadeAlpha(GetIdleFadeAlpha())
        end

        local function CancelIdleFade()
            _idleFadeActive = false
            if idleTimer then
                idleTimer:Cancel()
                idleTimer = nil
            end
            if _visChatVisible then
                ECHAT.SetIdleFadeAlpha(1)
            end
        end

        function ECHAT.ResetIdleTimer()

            if not IsIdleApplicable() then return end
            CancelIdleFade()
            local cfg = ECHAT.DB()
            local delay = cfg.idleFadeDelay or 15
            idleTimer = C_Timer.NewTimer(delay, StartIdleFade)
        end

        -- Idle reset throttle: max once per second.
        local _lastIdleReset = 0
        local function OnActiveMessage()
            if not IsIdleApplicable() then return end
            local now = GetTime()
            if now - _lastIdleReset < 1 then return end
            _lastIdleReset = now
            if _idleMouseOver then
                CancelIdleFade()
            else
                ECHAT.ResetIdleTimer()
            end
        end

        -- Idle reset via standalone event frame (no hooks on chat frames).
        local idleEventFrame = CreateFrame("Frame")
        for ev in pairs(CHAT_MSG_EVENTS) do
            idleEventFrame:RegisterEvent(ev)
        end
        idleEventFrame:SetScript("OnEvent", OnActiveMessage)

        for i = 1, 20 do
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if eb then
                eb:HookScript("OnEditFocusGained", OnActiveMessage)
                eb:HookScript("OnTextChanged", OnActiveMessage)
            end
        end

        ---------------------------------------------------------------------------
        --  7. Whisper sound alert
        --     Plays a configurable sound on incoming whispers. Uses a standalone
        --     event frame (not a message filter) for zero taint risk.
        ---------------------------------------------------------------------------
        do
            local _SOUNDS_DIR = "Interface\\AddOns\\EllesmereUI\\media\\sounds\\"
            local WHISPER_SOUND_PATHS = {
                ["none"]     = nil,
                ["airhorn"]  = _SOUNDS_DIR .. "AirHorn.ogg",
                ["banana"]   = _SOUNDS_DIR .. "BananaPeelSlip.ogg",
                ["bikehorn"] = _SOUNDS_DIR .. "BikeHorn.ogg",
                ["boxing"]   = _SOUNDS_DIR .. "BoxingArenaSound.ogg",
                ["water"]    = _SOUNDS_DIR .. "WaterDrop.ogg",
            }
            local WHISPER_SOUND_NAMES = {
                ["none"]     = "None",
                ["airhorn"]  = "Air Horn",
                ["banana"]   = "Banana Peel Slip",
                ["bikehorn"] = "Bike Horn",
                ["boxing"]   = "Boxing Arena",
                ["water"]    = "Water Drop",
            }
            local WHISPER_SOUND_ORDER = {
                "none", "airhorn", "banana", "bikehorn", "boxing", "water",
            }
            ECHAT.WHISPER_SOUND_PATHS = WHISPER_SOUND_PATHS
            ECHAT.WHISPER_SOUND_NAMES = WHISPER_SOUND_NAMES
            ECHAT.WHISPER_SOUND_ORDER = WHISPER_SOUND_ORDER

            -- Append SharedMedia sounds
            if EllesmereUI.AppendSharedMediaSounds then
                EllesmereUI.AppendSharedMediaSounds(
                    WHISPER_SOUND_PATHS,
                    WHISPER_SOUND_NAMES,
                    WHISPER_SOUND_ORDER
                )
            end

            local _whisperThrottle = 0
            local whisperFrame = CreateFrame("Frame")
            whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
            whisperFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
            whisperFrame:SetScript("OnEvent", function()
                local cfg = ECHAT.DB()
                local key = cfg and cfg.whisperSoundKey
                if not key or key == "none" then return end
                local now = GetTime()
                if now - _whisperThrottle < 5 then return end
                _whisperThrottle = now
                local path = WHISPER_SOUND_PATHS[key]
                if path then PlaySoundFile(path, "Master") end
            end)
        end

        -- Event-driven hover detection: zero CPU when idle.
        -- Uses EnableMouseMotion on our bg frames + HookScript on tabs.
        -- EnableMouseMotion captures hover without blocking clicks, but
        -- does block camera turning. We accept this trade-off for zero-poll.
        local _idleMouseOver = false
        local _hoverCount = 0
        local _editFocusCount = 0

        local function UpdateHoverState()
            local over = (_hoverCount > 0) or (_editFocusCount > 0)
            if not IsIdleApplicable() then return end
            if over and not _idleMouseOver then
                _idleMouseOver = true
                CancelIdleFade()
            elseif not over and _idleMouseOver then
                _idleMouseOver = false
                ECHAT.ResetIdleTimer()
            end
        end

        local function OnChatEnter(cf)
            _hoverCount = _hoverCount + 1
            UpdateHoverState()
            local track = CFD(cf).scrollTrack
            if track and track._setHovered then
                track._setHovered(true)
                track._showTrack()
            end
        end
        local function OnChatLeave(cf)
            _hoverCount = max(0, _hoverCount - 1)
            UpdateHoverState()
            local track = CFD(cf).scrollTrack
            if track and track._setHovered and not track._isDragging() then
                track._setHovered(false)
                track._hideTrack()
            end
        end

        -- Single invisible overlay covering tabs + bg + sidebar.
        -- EnableMouseMotion detects hover without blocking clicks.
        -- Placed at BACKGROUND strata so it never intercepts anything.
        do
            local cf1 = _G.ChatFrame1
            local gdm = _G.GeneralDockManager
            local bg1 = CFD(cf1).bg
            local sb = CFD(cf1).sidebar
            if bg1 and gdm then
                local overlay = CreateFrame("Frame", nil, UIParent)
                overlay:SetPoint("TOPLEFT", gdm, "TOPLEFT", sb and -40 or 0, 0)
                overlay:SetPoint("BOTTOMRIGHT", bg1, "BOTTOMRIGHT", 0, 0)
                overlay:SetFrameStrata("BACKGROUND")
                overlay:EnableMouseMotion(true)
                overlay:SetScript("OnEnter", function()
                    _hoverCount = _hoverCount + 1
                    UpdateHoverState()
                    local sel = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
                        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
                    if sel then
                        local track = CFD(sel).scrollTrack
                        if track and track._setHovered then
                            track._setHovered(true)
                            track._showTrack()
                        end
                    end
                end)
                overlay:SetScript("OnLeave", function()
                    _hoverCount = max(0, _hoverCount - 1)
                    UpdateHoverState()
                    local sel = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
                        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
                    if sel then
                        local track = CFD(sel).scrollTrack
                        if track and track._setHovered and not track._isDragging() then
                            track._setHovered(false)
                            track._hideTrack()
                        end
                    end
                end)
            end
        end

        -- Sidebar has EnableMouse(true) which blocks the overlay beneath it.
        -- HookScript on our own frame -- safe, no taint.
        local sidebar = CFD(ChatFrame1).sidebar
        if sidebar then
            sidebar:HookScript("OnEnter", function()
                _hoverCount = _hoverCount + 1; UpdateHoverState()
            end)
            sidebar:HookScript("OnLeave", function()
                _hoverCount = max(0, _hoverCount - 1); UpdateHoverState()
            end)
        end

        -- Edit box focus tracking -- only ChatFrame1 (permanent, no secret
        -- values). Hooking temp whisper edit boxes (11+) taints their
        -- execution context, causing secret value errors on BN_WHISPER tellTarget.
        local eb1 = _G["ChatFrame1EditBox"]
        if eb1 then
            eb1:HookScript("OnEditFocusGained", function()
                _editFocusCount = _editFocusCount + 1; UpdateHoverState()
            end)
            eb1:HookScript("OnEditFocusLost", function()
                _editFocusCount = max(0, _editFocusCount - 1); UpdateHoverState()
            end)
        end

        -- Start the initial timer
        ECHAT.ResetIdleTimer()
    end

    ---------------------------------------------------------------------------
    --  7. Accent color + timestamps
    ---------------------------------------------------------------------------
    if EUI.RegAccent then
        EUI.RegAccent({ type = "callback", fn = UpdateTabColors })
    end

    -- Enable scroll-to-scroll chat (Blizzard disables by default)
    if SetCVar then SetCVar("chatMouseScroll", 1) end

    local function ApplyTimestampCVar()
        if not SetCVar then return end
        local cfg = ECHAT.DB()
        local fmt = cfg.timestampFormat or "%I:%M "
        if fmt == "__blizzard" then return end
        SetCVar("showTimestamps", fmt)
    end
    ApplyTimestampCVar()
    C_Timer.After(2, ApplyTimestampCVar)
    ECHAT.ApplyTimestampCVar = ApplyTimestampCVar

    ---------------------------------------------------------------------------
    --  8. Apply all visual settings from DB
    ---------------------------------------------------------------------------
    ECHAT.ApplySidebarVisibility()
    ECHAT.ApplyBorders()
    -- ECHAT.ApplySidebarIcons() -- causes taint (full layout chain)
    -- Apply individual icon visibility from DB without the layout chain.
    do
        local _cfg = ECHAT.DB()
        local _cf1 = _G.ChatFrame1
        if _cfg and _cf1 then
            local _sbd = CFD(_cf1)
            if _sbd.scrollBtn then _sbd.scrollBtn:SetShown(_cfg.showScroll ~= false) end
            if _sbd.friendsBtn then _sbd.friendsBtn:SetShown(_cfg.showFriends ~= false) end
            if _sbd.copyBtn then _sbd.copyBtn:SetShown(_cfg.showCopy ~= false) end
            if _sbd.portalBtn then _sbd.portalBtn:SetShown(_cfg.showPortals ~= false) end
            if _sbd.voiceBtn then _sbd.voiceBtn:SetShown(_cfg.showVoice ~= false) end
            if _sbd.settingsBtn then _sbd.settingsBtn:SetShown(_cfg.showSettings ~= false) end
        end
    end
    ECHAT.ApplySidebarPosition()
    ECHAT.ApplyIconColor()
    ECHAT.ApplyInputPosition()
    ECHAT.ApplySidebarBackground()
    ECHAT.ApplySidebarIconScale()
    ECHAT.ApplyIconFreeMove()
    ECHAT.ApplyLockChatSize()

    -- Profile-swap refresh: re-read DB and refresh all chat visuals.
    -- TODO: re-enable after taint audit is complete
    -- _G._ECHAT_RefreshAll = function()
    --     ECHAT.ApplySidebarVisibility()
    --     ECHAT.ApplyBorders()
    --     ECHAT.ApplySidebarIcons()
    --     ECHAT.ApplySidebarPosition()
    --     ECHAT.ApplyIconColor()
    --     ECHAT.ApplyInputPosition()
    --     ECHAT.ApplySidebarBackground()
    --     ECHAT.ApplySidebarIconScale()
    --     ECHAT.ApplyIconFreeMove()
    --     ECHAT.ApplyLockChatSize()
    --     ECHAT.ApplyBackground()
    --     ECHAT.ApplyFonts()
    --     if ECHAT.RefreshVisibility then ECHAT.RefreshVisibility() end
    -- end

    ---------------------------------------------------------------------------
    --  9-12. Chat positioning: Blizzard / Edit Mode owns position+size.
    --        No reparenting, no hooks, no unlock registration.
    ---------------------------------------------------------------------------
    ChatFrame1:SetClampedToScreen(false)

    -- One-time overlay informing user that chat is now Edit Mode controlled
    do
        local cfg = ECHAT.DB()
        if cfg and not cfg._editModeNoticeDismissed and cfg.chatPosition then
            local cf1bg = CFD(ChatFrame1).bg
            if cf1bg then
                local overlay = CreateFrame("Frame", nil, cf1bg)
                overlay:SetAllPoints(cf1bg)
                overlay:SetFrameLevel(cf1bg:GetFrameLevel() + 50)
                overlay:EnableMouse(true)

                local bg = overlay:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0.04, 0.06, 0.07, 0.95)

                local msg = overlay:CreateFontString(nil, "OVERLAY")
                msg:SetFont(GetFont(), 12, "")
                msg:SetTextColor(1, 1, 1, 0.85)
                msg:SetPoint("CENTER", overlay, "CENTER", 0, 16)
                msg:SetWidth(overlay:GetWidth() - 40)
                msg:SetJustifyH("CENTER")
                msg:SetText("Your chat position is now controlled by Blizzard Edit Mode.\nPlease adjust its position there.")

                local btn = CreateFrame("Button", nil, overlay)
                btn:SetSize(90, 24)
                btn:SetPoint("TOP", msg, "BOTTOM", 0, -12)
                btn:SetFrameLevel(overlay:GetFrameLevel() + 1)

                local btnBg = btn:CreateTexture(nil, "BACKGROUND")
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0.12, 0.14, 0.18, 1)

                local btnHL = btn:CreateTexture(nil, "HIGHLIGHT")
                btnHL:SetAllPoints()
                btnHL:SetColorTexture(1, 1, 1, 0.06)

                local btnText = btn:CreateFontString(nil, "OVERLAY")
                btnText:SetFont(GetFont(), 11, "")
                btnText:SetTextColor(1, 1, 1, 0.8)
                btnText:SetPoint("CENTER")
                btnText:SetText("Okay")

                if PP and PP.CreateBorder then
                    PP.CreateBorder(btn, 1, 1, 1, 0.08, 1, "OVERLAY", 7)
                end

                btn:SetScript("OnClick", function()
                    cfg._editModeNoticeDismissed = true
                    overlay:Hide()
                end)
            end
        end
    end

    --[[ REMOVED: sections 9-12 (position capture, reparent, enforcement, unlock)
    ---------------------------------------------------------------------------
    do
        local captureFrame = CreateFrame("Frame")
        captureFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        captureFrame:SetScript("OnEvent", function()
            local cfg = ECHAT.DB()
            if not cfg then return end
            if not cfg.chatPosition then
                local pt, _, relPt, x, y = ChatFrame1:GetPoint(1)
                if pt and x and y then
                    cfg.chatPosition = { point = pt, relPoint = relPt or pt, x = x, y = y }
                end
            end
            if not cfg.chatWidth then
                cfg.chatWidth = ChatFrame1:GetWidth()
            end
            if not cfg.chatHeight then
                cfg.chatHeight = ChatFrame1:GetHeight()
            end
            ApplyChatPosition()
            ApplyChatSize()
        end)
    end
    ---------------------------------------------------------------------------
    --  10. Reparent ChatFrame1 to our own container
    --      Breaks it out of Blizzard's Edit Mode hierarchy so we can call
    --      SetSize without tainting. Hides Edit Mode overlay + resize button.
    ---------------------------------------------------------------------------
    local chatContainer = CreateFrame("Frame", nil, UIParent)
    chatContainer:SetAllPoints(UIParent)
    chatContainer:EnableMouse(false)
    ChatFrame1:SetParent(chatContainer)
    if ChatFrame1.Selection then ChatFrame1.Selection:SetParent(_hiddenParent) end
    if ChatFrame1.EditModeResizeButton then ChatFrame1.EditModeResizeButton:SetParent(_hiddenParent) end

    -- SetParent called once above. No reactive hook -- hooksecurefunc on
    -- SetParent taints HistoryKeeper during whisper event processing.
    ChatFrame1:SetClampedToScreen(false)

    ---------------------------------------------------------------------------
    --  11. Position enforcement hook
    --      Blocks Blizzard/Edit Mode from overriding our saved position.
    --      Allows unlock mode dragging and resize grip repositioning.
    ---------------------------------------------------------------------------
    pcall(ApplyChatPosition)
    -- SetPoint called once above via ApplyChatPosition. No reactive hook.
    -- hooksecurefunc on SetPoint taints HistoryKeeper during whisper
    -- event processing. Position may drift if Blizzard overrides it, but
    -- taint-free chat is more important.

    ---------------------------------------------------------------------------
    --  12. Unlock mode registration (position + resize via EUI unlock mode)
    ---------------------------------------------------------------------------
    if EUI.RegisterUnlockElements then
        local MK = EUI.MakeUnlockElement
        EUI:RegisterUnlockElements({
            MK({
                key   = "ECHAT_ChatFrame",
                label = "Chat",
                group = "Chat",
                order = 600,
                noAnchorTo = true,
                noInitHook = true,
                getFrame = function() return ChatFrame1 end,
                getSize  = function()
                    local cfg = ECHAT.DB()
                    if cfg then
                        return cfg.chatWidth or 400, cfg.chatHeight or 200
                    end
                    return 400, 200
                end,
                setWidth = function(_, newW)
                    if InCombatLockdown() then return end
                    local cf1 = _G.ChatFrame1
                    if not cf1 then return end
                    local PPc = EllesmereUI and EllesmereUI.PP
                    local snapW = PPc and PPc.Snap(max(200, newW)) or math.floor(max(200, newW) + 0.5)
                    cf1:SetWidth(snapW)
                    if EllesmereUI._unlockActive then
                        local cfg = ECHAT.DB()
                        if cfg then cfg.chatWidth = snapW end
                    end
                end,
                setHeight = function(_, newH)
                    if InCombatLockdown() then return end
                    local cf1 = _G.ChatFrame1
                    if not cf1 then return end
                    local PPc = EllesmereUI and EllesmereUI.PP
                    local snapH = PPc and PPc.Snap(max(100, newH)) or math.floor(max(100, newH) + 0.5)
                    cf1:SetHeight(snapH)
                    if EllesmereUI._unlockActive then
                        local cfg = ECHAT.DB()
                        if cfg then cfg.chatHeight = snapH end
                    end
                end,
                isHidden = function()
                    local cfg = ECHAT.DB()
                    return cfg.visibility == "never"
                end,
                savePos = function(_, point, relPoint, x, y)
                    local cfg = ECHAT.DB()
                    if not cfg then return end
                    cfg.chatPosition = { point = point, relPoint = relPoint or point, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ApplyChatPosition()
                    end
                end,
                loadPos = function()
                    local cfg = ECHAT.DB()
                    if not cfg then return nil end
                    return cfg.chatPosition
                end,
                clearPos = function()
                    local cfg = ECHAT.DB()
                    if not cfg then return end
                    cfg.chatPosition = nil
                end,
                applyPos = function()
                    ApplyChatPosition()
                end,
            }),
        })
    end
    --]]

    ---------------------------------------------------------------------------
    --  12b. BNet Toast notification -- position via unlock mode
    ---------------------------------------------------------------------------
    do
        local toast = _G.BNToastFrame
        if toast then
            -- Apply saved position or default to bottom-right of chat bg
            local function ApplyToastPosition()
                local cfg = ECHAT.DB()
                if not cfg or not cfg.toastPosition then return end
                local pos = cfg.toastPosition
                if not pos.point then return end
                local px, py = pos.x or 0, pos.y or 0
                local PPa = EUI and EUI.PP
                if PPa and PPa.SnapForES then
                    local es = toast:GetEffectiveScale()
                    px = PPa.SnapForES(px, es)
                    py = PPa.SnapForES(py, es)
                end
                toast:ClearAllPoints()
                toast:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
            end

            -- Enforce saved position when Blizzard tries to reposition.
            -- Skip during unlock mode so the user can drag freely.
            local _toastIgnoreSP = false
            hooksecurefunc(toast, "SetPoint", function()
                if _toastIgnoreSP or EUI._unlockActive then return end
                local cfg = ECHAT.DB()
                if cfg and cfg.toastPosition then
                    _toastIgnoreSP = true
                    ApplyToastPosition()
                    _toastIgnoreSP = false
                end
            end)

            -- Apply saved position or set default (above chat frame)
            C_Timer.After(0, function()
                local cfg = ECHAT.DB()
                if cfg and not cfg.toastPosition then
                    -- Default: anchor to top of chat bg
                    local cf1bg = _G.ChatFrame1 and CFD(_G.ChatFrame1).bg
                    if cf1bg then
                        toast:ClearAllPoints()
                        toast:SetPoint("BOTTOMLEFT", cf1bg, "TOPLEFT", 0, 30)
                        -- Snapshot the absolute position
                        local es = toast:GetEffectiveScale()
                        local uiS = UIParent:GetEffectiveScale()
                        local cx, cy = toast:GetCenter()
                        local uCX, uCY = UIParent:GetCenter()
                        if cx and uCX then
                            cfg.toastPosition = {
                                point = "CENTER", relPoint = "CENTER",
                                x = (cx * es - uCX * uiS) / uiS,
                                y = (cy * es - uCY * uiS) / uiS,
                            }
                        end
                    end
                end
                ApplyToastPosition()
            end)

            -- Register with unlock mode
            if EUI.RegisterUnlockElements then
                local MK = EUI.MakeUnlockElement
                EUI:RegisterUnlockElements({
                    MK({
                        key   = "ECHAT_BNToast",
                        label = "BNet Toast",
                        group = "Chat",
                        order = 601,
                        noAnchorTo = true,
                        noResize   = true,
                        getFrame = function() return toast end,
                        getSize  = function()
                            return toast:GetWidth(), toast:GetHeight()
                        end,
                        isHidden = function() return false end,
                        savePos = function(_, point, relPoint, x, y)
                            local cfg = ECHAT.DB()
                            if not cfg then return end
                            cfg.toastPosition = { point = point, relPoint = relPoint or point, x = x, y = y }
                            if not EUI._unlockActive then
                                ApplyToastPosition()
                            end
                        end,
                        loadPos = function()
                            local cfg = ECHAT.DB()
                            if not cfg then return nil end
                            return cfg.toastPosition
                        end,
                        clearPos = function()
                            local cfg = ECHAT.DB()
                            if not cfg then return end
                            cfg.toastPosition = nil
                        end,
                        applyPos = function()
                            ApplyToastPosition()
                        end,
                    }),
                })
            end
        end
    end

    ---------------------------------------------------------------------------
    --  13. Visibility system registration
    ---------------------------------------------------------------------------
    ECHAT.RefreshVisibility()
    if EUI.RegisterVisibilityUpdater then
        EUI.RegisterVisibilityUpdater(ECHAT.RefreshVisibility)
    end

    ---------------------------------------------------------------------------
    --  14. Hide Blizzard social buttons (quick join, menu, channel, voice)
    ---------------------------------------------------------------------------
    for _, frameName in ipairs({
        "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    }) do
        local f = _G[frameName]
        if f then f:SetAlpha(0); f:EnableMouse(false) end
    end
end)
