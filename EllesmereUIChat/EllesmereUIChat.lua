-------------------------------------------------------------------------------
--  EllesmereUIChat.lua
--
--  Visual reskin + utility features:
--    - Dark unified background (chat + input as one panel)
--    - Tab restyling (custom fonts, colors, spacing, and borders)
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

-- BISECT LADDER (whisper-creation taint). The gate-7 configuration below
-- (every flag true) is the last field-CLEAN state. Gates are cleared ONE
-- per tester cycle -- multiple taint sources are possible, so a returning
-- error attributes to the single flag flipped that cycle. The clip-homed
-- tab hosts (GetTabHostClip) are the root-cause fix for gate 7A and are
-- ACTIVE; this build's only new variable vs the clean state.
local BISECT_TAB_GEOMETRY_OFF = false   -- 1: CLEARED (this cycle)
local BISECT_TAB_PADDING_OFF = false    -- 3: CLEARED (this cycle)
local BISECT_TAB_BORDERS_OFF = false    -- 4: RETEST -- dirty on first clear;
                                        --    tab getters removed since
-- 4b: gate-4 stayed dirty with all tab getters gone. This flag skips ONLY
-- the border-engine call (EllesmereUI.ApplyBorderStyle + PP solid border)
-- on the tab hosts; host management, FCF_IsDocked, and separators all
-- still run. The engine's scale walk + PP pixel-snap machinery have never
-- executed on a gdm-chained frame in any clean build.
local BISECT_EXT_BG_OFF = false         -- 5: CLEARED (this cycle)
local BISECT_DEFERRED_PASSES_OFF = false -- 6: CLEARED (this cycle)
local BISECT_EB_ANCHORS_OFF = false     -- 7: CLEARED (this cycle)
local BISECT_TEX_SHIFT_OFF = false      -- 8: CLEARED (this cycle) -- textures
                                        --    re-anchored to their OWN parent
                                        --    add no dependency edge; anchor +
                                        --    unsnap both have clean alibis
-- FINAL HOST DESIGN (gate 9 confirmed CLEAN in field): an insecure frame
-- ANCHORED to a Blizzard chat tab is the taint injector -- parenting,
-- existence, and strata were all exonerated; the anchor dependency alone
-- poisons the secure dock pass into UpdateHeader's secret whisper math.
-- Hosts therefore carry ZERO tab anchors: clip-parented and positioned
-- NUMERICALLY (PositionTabHosts) from coordinates resolved in our own
-- deferred passes. Geometry READS of tabs from our execution are safe;
-- anchor TIES are not.

-- WHISPER-CREATION TAINT: ROOT CAUSE (field-bisected 2026-07-22 over a
-- 7-gate ladder against the clean 8.5.2 baseline). Creating child FRAMES
-- on Blizzard chat tabs (841's panelBorder/separatorHost/underlineHost)
-- taints the temp-whisper creation chain: FCF_OpenTemporaryWindow ->
-- FCF_DockUpdate walks the tabs with our frames in their child lists, and
-- the chain then runs UpdateHeader's SECRET whisper-name width math
-- tainted ("arithmetic on a secret value blocked... EllesmereUIChat",
-- ChatFrameEditBox.lua:677) and the whisper fails to route. The pre-841
-- module avoided exactly this ("zero writes to Blizzard frames" -- its
-- underline lived on a UIParent clip frame). FIX: all per-tab host frames
-- are parented to the shared UIParent clip container below and only
-- ANCHORED to their tab. NEVER CreateFrame with a Blizzard chat tab (or
-- chat frame) as parent. Textures created directly on tabs (bg/hover)
-- are fine -- they existed in 8.5.2, field-clean.
local _tabHostClip
local function GetTabHostClip()
    if _tabHostClip then return _tabHostClip end
    local clip = CreateFrame("Frame", nil, UIParent)
    clip:SetFrameStrata("DIALOG")
    clip:EnableMouse(false)
    clip:SetClipsChildren(true)
    local gdm = _G.GeneralDockManager
    if gdm then
        -- Slack past the dock bounds so the 1px separators/underline and
        -- the dynamic-tab visual shift are not clipped at the edges.
        clip:SetPoint("TOPLEFT", gdm, "TOPLEFT", -4, 8)
        clip:SetPoint("BOTTOMRIGHT", gdm, "BOTTOMRIGHT", 4, -8)
    else
        clip:SetAllPoints(UIParent)
    end
    ns._tabHostClip = clip
    _tabHostClip = clip
    return clip
end

-- Chat uses the same tuned Blizzard-border offsets as the other rectangular
-- EUI panels. Without a chat registration the shared engine resolves the
-- addon-specific lookup to zero, which clips this texture into the panel.
if EUI.RegisterBorderDefaults then
    EUI.RegisterBorderDefaults("chat", {
        ["blizz"] = {
            defaultSize = "heavy",
            sizes = {
                none   = { offsetX=0, offsetY=0, shiftX=0, shiftY=0 },
                thin   = { offsetX=2, offsetY=1, shiftX=0, shiftY=0 },
                normal = { offsetX=3, offsetY=2, shiftX=0, shiftY=0 },
                heavy  = { offsetX=4, offsetY=2, shiftX=1, shiftY=0 },
                strong = { offsetX=4, offsetY=2, shiftX=2, shiftY=0 },
            },
        },
    })
end

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
            bgTexture  = "none",  -- chat background texture key (Unit Frames bar texture catalogue)
            timestampFormat = "%I:%M ",
            font = "__global",
            outlineMode = "__global",
            fontSize = 12,
            tabFont = "__global",
            tabFontSize = 11,
            tabFontColor = { r=1, g=1, b=1, a=0.65 },
            tabFontColorActive = { r=1, g=1, b=1, a=1 },
            sidebarVisibility = "always",
            hideBorders = false,
            innerBorderColor = { r=1, g=1, b=1, a=0.06 },
            innerBorderColorMode = "custom",
            panelBorderBehind = false,
            tabBackgroundTexture = "none",
            activeTabBorder = true,
            tabBorderColorActive = { r=1, g=1, b=1, a=0.18 },
            extendBgBehindTabs = false,
            panelBorderTexture = "solid",
            panelBorderThickness = "none",
            panelBorderColorMode = "custom",
            panelBorderColor = { r=1, g=1, b=1 },
            panelBorderOpacity = 0.18,
            tabSpacing = 1,
            tabPadding = 0,
            syncTabBorder = true,
            tabBorderTexture = "solid",
            tabBorderThickness = "none",
            tabBorderColorMode = "custom",
            tabBorderColor = { r=1, g=1, b=1 },
            tabBorderOpacity = 0.18,
            alignTabsToPanel = false,
            tabHeight = 24,
            tabInnerPaddingX = 12,
            tabBackgroundColor = { r=0.03, g=0.045, b=0.05, a=0.44 },
            tabBackgroundColorActive = { r=0.03, g=0.045, b=0.05, a=0.65 },
            activeUnderline = true,
            activeUnderlineColorMode = "accent",
            activeUnderlineColor = { r=0.05, g=0.82, b=0.61, a=1 },
            forceOnScreen = false,
            showFriends = true,
            showGuild = false,
            showDurability = false,
            showCopy = true,
            showPortals = true,
            showVoice = false,
            showSettings = true,
            showScroll = true,
            hideTooltipOnHover = true,
            sidebarRight = false,
            sidebarSeparate = false,
            sidebarSeparateSpacing = 8,
            iconR = 1,
            iconG = 1,
            iconB = 1,
            iconUseAccent = false,
            idleFadeDelay = 15,
            idleFadeStrength = 40,
            idleFadeEnabled = true,
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
            -- Session chat history (EllesmereUIChat_SessionHistory.lua, SavedVariablesPerCharacter)
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
    -- Chat-specific outline override; still slug-gated by "Never Show Slug".
    if mode == "outline" then return (EUI.SlugFlag and EUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG" end
    if mode == "thick" then return (EUI.SlugFlag and EUI.SlugFlag("THICKOUTLINE, SLUG")) or "THICKOUTLINE, SLUG" end
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
local _visAlpha = 1
local _euiDockStyled
-- Tab alpha is NOT managed here. The per-tab fade layer (own driver frame,
-- fadeBaseAlpha capture, tab:SetAlpha writes) shipped 2026-07-20 and was
-- removed same day: Blizzard's own tab alpha machinery (FCFTab_UpdateAlpha,
-- mouseover alphas) rewrites tab alpha constantly and always won, so the
-- feature visibly did nothing. Tabs fade with the chat panel the original
-- way instead -- the dock-level GeneralDockManager:SetAlpha in _ApplyAlpha,
-- which the tabs inherit as children. Do not reintroduce per-tab SetAlpha
-- (and NEVER hook tab SetAlpha -- the pre-2026 attempt was a constant
-- hot-path perf hit).

-- Height of the tab strip (GeneralDockManager dockH, set in StyleDockManager).
-- Used by the "Extend Background Behind Tabs" feature to size the strip behind
-- the tabs and to shift the sidebar icon chain up by the same amount.
local TAB_STRIP_H = 24
local function GetTabHeight()
    local cfg = ECHAT.DB()
    return cfg.tabHeight or TAB_STRIP_H
end

local function GetTabFont()
    local cfg = ECHAT.DB()
    local fontKey = cfg.tabFont or "__global"
    if fontKey == "__global" then
        return (EUI.GetFontPath and EUI.GetFontPath("chat")) or STANDARD_TEXT_FONT
    end
    return (EUI.ResolveFontName and EUI.ResolveFontName(fontKey)) or STANDARD_TEXT_FONT
end
local function GetTabPadding()
    local cfg = ECHAT.DB()
    if cfg.extendBgBehindTabs then return 0 end
    return cfg.tabPadding or 0
end
local function GetTabAreaHeight()
    return GetTabHeight() + GetTabPadding()
end

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

local function GetInnerBorderColor(cfg)
    if cfg.innerBorderColorMode == "accent" and EllesmereUI.GetAccentColor then
        local r, g, b = EllesmereUI.GetAccentColor()
        local c = cfg.innerBorderColor
        return r, g, b, (c and c.a) or 0.06
    end
    local c = cfg.innerBorderColor or { r=1, g=1, b=1, a=0.06 }
    return c.r or 1, c.g or 1, c.b or 1, c.a == nil and 0.06 or c.a
end

-- Set true once GeneralDockManager has been positioned and styled as our tab bar
_euiDockStyled = false
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

-- Chat background texture catalogue: the same set as the Unit Frames bar
-- texture dropdown (same shared media files), with SharedMedia statusbar
-- textures appended through the shared EllesmereUI helper.
local CHAT_TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
ns.chatBgTextures = {
    ["none"]          = nil,
    ["melli"]         = CHAT_TEX_BASE .. "melli.tga",
    ["beautiful"]     = CHAT_TEX_BASE .. "beautiful.tga",
    ["plating"]       = CHAT_TEX_BASE .. "plating.tga",
    ["atrocity"]      = CHAT_TEX_BASE .. "atrocity.tga",
    ["divide"]        = CHAT_TEX_BASE .. "divide.tga",
    ["glass"]         = CHAT_TEX_BASE .. "glass.tga",
    ["fade-right"]    = CHAT_TEX_BASE .. "fade-right.tga",
    ["thin-line-top"]    = CHAT_TEX_BASE .. "thin-line-top.tga",
    ["thin-line-bottom"] = CHAT_TEX_BASE .. "thin-line-bottom.tga",
    ["fade"]          = CHAT_TEX_BASE .. "fade.tga",
    ["gradient-lr"]   = CHAT_TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = CHAT_TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = CHAT_TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = CHAT_TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = CHAT_TEX_BASE .. "matte.tga",
    ["sheer"]         = CHAT_TEX_BASE .. "sheer.tga",
    ["blinkii-diamonds"] = CHAT_TEX_BASE .. "blinkii-diamonds.tga",
    ["kringel-window"]   = CHAT_TEX_BASE .. "kringel-window.tga",
}
ns.chatBgTextureOrder = {
    "none", "melli", "atrocity",
    "fade", "fade-right",
    "thin-line-top", "thin-line-bottom",
    "beautiful", "plating",
    "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
    "blinkii-diamonds", "kringel-window",
}
ns.chatBgTextureNames = {
    ["none"]        = "None",
    ["melli"]       = "Melli (ElvUI)",
    ["beautiful"]   = "Beautiful",
    ["plating"]     = "Plating",
    ["atrocity"]    = "Atrocity",
    ["divide"]      = "Divide",
    ["glass"]       = "Glass",
    ["fade-right"]  = "Fade Right",
    ["thin-line-top"]    = "Thin Line Top",
    ["thin-line-bottom"] = "Thin Line Bottom",
    ["fade"]        = "Fade",
    ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left",
    ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down",
    ["matte"]       = "Matte",
    ["sheer"]       = "Sheer",
    ["blinkii-diamonds"] = "Blinkii Diamonds",
    ["kringel-window"]   = "Kringel Window",
}

-- Refresh the catalogue from SharedMedia (idempotent; registers the
-- late-registration callback on first call, same as the other modules).
function ECHAT.RefreshBgTextureCatalogue()
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(
            ns.chatBgTextureNames, ns.chatBgTextureOrder, nil, ns.chatBgTextures)
    end
end

-- Apply background settings from DB to all skinned chat frames
function ECHAT.ApplyBackground()
    local p = ECHAT.DB()
    BG_R = p.bgR or 0.03
    BG_G = p.bgG or 0.045
    BG_B = p.bgB or 0.05
    BG_A = p.bgAlpha or 0.65

    -- Resolve the background texture ("none" = legacy solid color)
    local texKey = p.bgTexture or "none"
    local texPath
    if texKey ~= "none" then
        ECHAT.RefreshBgTextureCatalogue()
        if EllesmereUI.ResolveTexturePath then
            texPath = EllesmereUI.ResolveTexturePath(ns.chatBgTextures, texKey, nil)
        else
            texPath = ns.chatBgTextures[texKey]
        end
    end

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and CFD(cf).bg then
            -- Update main bg texture
            local bgTex = CFD(cf).bg:GetRegions()
            if bgTex then
                if texPath and bgTex.SetTexture then
                    bgTex:SetTexture(texPath)
                    bgTex:SetVertexColor(BG_R, BG_G, BG_B, BG_A)
                elseif bgTex.SetColorTexture then
                    -- Clear any texture-mode tint before returning to solid,
                    -- or the color would double-tint through the vertex color.
                    if bgTex.SetVertexColor then bgTex:SetVertexColor(1, 1, 1, 1) end
                    bgTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
                end
            end
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
    -- Keep the behind-tabs extension in sync with the new color/opacity.
    if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
    if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
end

-- Extend the chat background up behind the tab strip (and the sidebar by the
-- same amount) so the tabs sit on one continuous panel instead of floating over
-- empty space. Opt-in via cfg.extendBgBehindTabs (default off, reload on toggle).
--
-- This only ever creates OUR OWN frames -- it never touches a Blizzard tab or
-- the GeneralDockManager -- so it stays completely taint free. The strip height
-- matches the dock height so it lines up pixel-for-pixel with the tab bar.
--
-- The chat strip is ONE frame parented to UIParent (not to a chat frame) and
-- pinned to ChatFrame1's bg top. UIParent parenting keeps it visible when you
-- switch docked tabs (a per-frame child would vanish with its hidden frame), and
-- a BACKGROUND strata keeps it BEHIND the tabs. Because it does not inherit a
-- chat frame's alpha, _ApplyAlpha fades it directly.
function ECHAT.ApplyExtendedBackground()
    if BISECT_EXT_BG_OFF then
        if ns._chatBgExt then ns._chatBgExt:Hide() end
        if ns._chatPanelBorder then ns._chatPanelBorder:Hide() end
        if ns._tabPanelBottomSeparatorTex then ns._tabPanelBottomSeparatorTex:Hide() end
        return
    end
    local cfg = ECHAT.DB()
    local extend = cfg.extendBgBehindTabs == true
    local cf1 = _G.ChatFrame1
    local d1 = cf1 and CFD(cf1)
    local bg1 = d1 and d1.bg
    if not bg1 then return end

    local ext = ns._chatBgExt
    if extend and not ext then
        ext = CreateFrame("Frame", nil, UIParent)
        ext:SetPoint("BOTTOMLEFT", bg1, "TOPLEFT", 0, 0)
        ext:SetPoint("BOTTOMRIGHT", bg1, "TOPRIGHT", 0, 0)
        ext:SetHeight(GetTabAreaHeight())
        local t = ext:CreateTexture(nil, "BACKGROUND")
        t._euiOwned = true
        t:SetAllPoints()
        ns._chatBgExt = ext
        ns._chatBgExtTex = t
    end
    if ext then
        ext:SetHeight(GetTabAreaHeight())
        if ns._chatBgExtTex then ns._chatBgExtTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A) end
        -- Sit at the very bottom of the UI so the tabs (and their own dark
        -- backgrounds) always render in front of this strip. BACKGROUND is still
        -- above the 3D world, and the strip never overlaps the chat text or the
        -- sidebar, so dropping this low has no other visual side effects.
        ext:SetFrameStrata("BACKGROUND")
        -- Level 1 leaves level 0 free for the panel border's "Show Behind"
        -- mode, whose outward half stays visible around the strip.
        ext:SetFrameLevel(1)
        if _chatAlphaCurrent then ext:SetAlpha(_chatAlphaCurrent) end
        ext:SetShown(extend)
    end

    -- Sidebar (ChatFrame1 only): a matching strip above the sidebar, plus a 1px
    -- divider continuation so the sidebar/chat hairline runs the full height. The
    -- sidebar is always visible and fades on its own, so this can stay a child of
    -- it (rendered behind the icons via the sidebar's own frame level).
    local sb = d1.sidebar
    if sb then
        local showSb = extend and not cfg.hideSidebarBg
        local sext = d1.sidebarExt
        if showSb and not sext then
            sext = CreateFrame("Frame", nil, sb)
            sext:SetPoint("BOTTOMLEFT", sb, "TOPLEFT", 0, 0)
            sext:SetPoint("BOTTOMRIGHT", sb, "TOPRIGHT", 0, 0)
            sext:SetHeight(GetTabAreaHeight())
            sext:SetFrameLevel(sb:GetFrameLevel())
            local t = sext:CreateTexture(nil, "BACKGROUND")
            t._euiOwned = true
            t:SetAllPoints()
            local div = sext:CreateTexture(nil, "OVERLAY", nil, 7)
            div._euiOwned = true
            div:SetWidth((PP and PP.mult) or 1)
            div:SetColorTexture(GetInnerBorderColor(cfg))
            if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(div) end
            d1.sidebarExt = sext
            d1.sidebarExtTex = t
            d1.sidebarExtDiv = div
        end
        if sext then
            sext:SetHeight(GetTabAreaHeight())
            if d1.sidebarExtTex then d1.sidebarExtTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A) end
            local div = d1.sidebarExtDiv
            if div then
                div:SetColorTexture(GetInnerBorderColor(cfg))
                div:ClearAllPoints()
                if cfg.sidebarRight then
                    div:SetPoint("TOPLEFT", sext, "TOPLEFT", 0, 0)
                    div:SetPoint("BOTTOMLEFT", sext, "BOTTOMLEFT", 0, 0)
                else
                    div:SetPoint("TOPRIGHT", sext, "TOPRIGHT", 0, 0)
                    div:SetPoint("BOTTOMRIGHT", sext, "BOTTOMRIGHT", 0, 0)
                end
                div:SetShown(not cfg.hideBorders)
            end
            sext:SetShown(showSb)
        end
    end

    -- One border around the complete extended panel: tab strip, chat
    -- background, and the sidebar on whichever side it currently occupies.
    local border = ns._chatPanelBorder
    if not border then
        border = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        border:EnableMouse(false)
        ns._chatPanelBorder = border
    end
    if border then
        border:ClearAllPoints()
        local includeSidebar = sb
            and not cfg.hideSidebarBg
            and (cfg.sidebarVisibility or "always") ~= "never"
            -- A separate sidebar is its own island: excluded from the
            -- panel border, wrapped by its own border below.
            and cfg.sidebarSeparate ~= true
        local topExtension = extend and GetTabAreaHeight() or 0
        if includeSidebar and not cfg.sidebarRight then
            border:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, topExtension)
            border:SetPoint("BOTTOMRIGHT", bg1, "BOTTOMRIGHT", 0, 0)
        elseif includeSidebar and cfg.sidebarRight then
            border:SetPoint("TOPLEFT", bg1, "TOPLEFT", 0, topExtension)
            border:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
        else
            border:SetPoint("TOPLEFT", bg1, "TOPLEFT", 0, topExtension)
            border:SetPoint("BOTTOMRIGHT", bg1, "BOTTOMRIGHT", 0, 0)
        end
        -- Chat tabs and the edit box can live on a higher strata than the chat
        -- frame itself, so a frame-level bump on the chat strata is not enough.
        -- "Show Behind" instead drops the border to the very back so the chat
        -- fill covers its inward half and only the outward half frames the
        -- panel.
        local showBehind = cfg.panelBorderBehind == true
        border:SetFrameStrata(showBehind and "BACKGROUND" or "DIALOG")
        -- Solid borders use a child at host + 1, while textured borders render
        -- directly at host level. In behind mode both stay at 0, under the
        -- extended strip (level 1) and the chat bg.
        local borderLevel = showBehind and 0 or max(100, cf1:GetFrameLevel() + 20)
        border:SetFrameLevel(borderLevel)

        if EllesmereUI.ApplyBorderStyle then
            local sizes = { none=0, thin=1, normal=2, heavy=3, strong=4 }
            local thicknessKey = cfg.panelBorderThickness or "none"
            local mode = cfg.panelBorderColorMode or "custom"
            local color
            if mode == "accent" then
                local r, g, b = EllesmereUI.GetAccentColor()
                color = { r=r, g=g, b=b }
            elseif mode == "class" then
                local _, class = UnitClass("player")
                color = class and RAID_CLASS_COLORS[class] or { r=1, g=1, b=1 }
            else
                color = cfg.panelBorderColor or { r=1, g=1, b=1 }
            end
            local alpha = cfg.panelBorderOpacity
            if alpha == nil then alpha = mode == "custom" and 0.18 or 0.5 end
            EllesmereUI.ApplyBorderStyle(border, sizes[thicknessKey] or 1,
                color.r, color.g, color.b, alpha, cfg.panelBorderTexture or "solid",
                cfg.panelBorderOffsetX, cfg.panelBorderOffsetY,
                cfg.panelBorderShiftX, cfg.panelBorderShiftY, "chat", thicknessKey)
            local solidBorder = PP and PP.GetBorders and PP.GetBorders(border)
            if solidBorder then solidBorder:SetFrameLevel(borderLevel + (showBehind and 0 or 1)) end
            border:Show()

            -- Separate Sidebar: its own border, same style as the panel.
            -- Same construction class as the panel border (our UIParent
            -- frame anchored to our sidebar frame).
            local wantSbBorder = cfg.sidebarSeparate == true and sb
                and not cfg.hideSidebarBg
                and (cfg.sidebarVisibility or "always") ~= "never"
            local sbBorder = ns._sidebarSeparateBorder
            if wantSbBorder and not sbBorder then
                sbBorder = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                sbBorder:EnableMouse(false)
                ns._sidebarSeparateBorder = sbBorder
            end
            if sbBorder then
                if wantSbBorder then
                    local sbTop = (extend and not cfg.hideSidebarBg)
                        and GetTabAreaHeight() or 0
                    sbBorder:ClearAllPoints()
                    sbBorder:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, sbTop)
                    sbBorder:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
                    sbBorder:SetFrameStrata(showBehind and "BACKGROUND" or "DIALOG")
                    sbBorder:SetFrameLevel(borderLevel)
                    EllesmereUI.ApplyBorderStyle(sbBorder, sizes[thicknessKey] or 1,
                        color.r, color.g, color.b, alpha, cfg.panelBorderTexture or "solid",
                        cfg.panelBorderOffsetX, cfg.panelBorderOffsetY,
                        cfg.panelBorderShiftX, cfg.panelBorderShiftY, "chat", thicknessKey)
                    local sbSolid = PP and PP.GetBorders and PP.GetBorders(sbBorder)
                    if sbSolid then sbSolid:SetFrameLevel(borderLevel + (showBehind and 0 or 1)) end
                    sbBorder:Show()
                else
                    sbBorder:Hide()
                end
            end
        else
            if EllesmereUI.ApplyBorderStyle then
                EllesmereUI.ApplyBorderStyle(border, 0, 1, 1, 1, 0, cfg.panelBorderTexture or "solid")
            end
            border:Hide()
        end
    end
    if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
    if ECHAT.ApplyTabSeparators then ECHAT.ApplyTabSeparators() end
    if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
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
    -- Separate-mode border mirrors the sidebar's alpha.
    if ns._sidebarSeparateBorder then
        ns._sidebarSeparateBorder:SetAlpha(_sidebarFadeAlpha)
    end

    -- Re-anchor the extended panel border when the sidebar enters or leaves
    -- the visible layout.
    if ECHAT.ApplyTabPadding then
        ECHAT.ApplyTabPadding()
    elseif ECHAT.ApplyExtendedBackground then
        ECHAT.ApplyExtendedBackground()
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
            if ns._sidebarSeparateBorder then
                ns._sidebarSeparateBorder:SetAlpha(min(_sidebarFadeAlpha, _chatAlphaCurrent))
            end
            if _sidebarFadeAlpha == _sidebarFadeTarget then self:Hide() end
        end)
    end
end

-- Show/hide all borders and dividers
function ECHAT.ApplyBorders()
    local cfg = ECHAT.DB()
    local hide = cfg.hideBorders
    local r, g, b, a = GetInnerBorderColor(cfg)

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and CFD(cf).bg and PP.GetBorders(CFD(cf).bg) then
            PP.SetBorderColor(CFD(cf).bg, r, g, b, a)
            PP.GetBorders(CFD(cf).bg):SetShown(not hide)
        end
        if cf and CFD(cf).inputDiv then
            CFD(cf).inputDiv:SetColorTexture(r, g, b, a)
            CFD(cf).inputDiv:SetShown(not hide)
        end
    end
    local cf1 = _G.ChatFrame1
    if cf1 and CFD(cf1).sidebar then
        local sbBgHidden = cfg.hideSidebarBg
        if PP.GetBorders(CFD(cf1).sidebar) then
            PP.SetBorderColor(CFD(cf1).sidebar, r, g, b, a)
            PP.GetBorders(CFD(cf1).sidebar):SetShown(not hide and not sbBgHidden)
        end
        if CFD(cf1).sidebarDiv then
            CFD(cf1).sidebarDiv:SetColorTexture(r, g, b, a)
            CFD(cf1).sidebarDiv:SetShown(not hide)
        end
    end
    -- Mirror border visibility onto the behind-tabs divider continuation.
    if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
    if ECHAT.ApplyTabSeparators then ECHAT.ApplyTabSeparators() end
end

-- Show/hide individual sidebar icons and re-anchor visible ones to close gaps
function ECHAT.ApplySidebarIcons()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sb = cf1 and CFD(cf1).sidebar
    if not sb then return end

    local ICON_GAP = cfg.sidebarIconSpacing or 10
    -- Shift the chain up by the tab-strip height when the background is extended
    -- (and free-move is off). Matches the offset applied at icon creation time.
    local iconTopShift = (cfg.extendBgBehindTabs and not cfg.freeMoveIcons) and GetTabAreaHeight() or 0
    local sbd = CFD(cf1)

    -- Re-anchor the chain icons in the creation-time order snapshot. Order
    -- edits from the options dropdown intentionally do NOT apply live -- the
    -- sidebar is rebuilt in the saved order on the next reload. Icons whose
    -- button was never created (enabled after login, pending reload) are
    -- skipped so the chain hangs off the last icon that actually exists.
    local CHAIN_REFS = {
        showFriends    = { btn = "friendsBtn",    tail = "friendsCount" },
        showGuild      = { btn = "guildBtn",      tail = "guildCount" },
        showDurability = { btn = "durabilityBtn", tail = "durabilityPct" },
        showCopy       = { btn = "copyBtn" },
        showPortals    = { btn = "portalBtn" },
        showVoice      = { btn = "voiceBtn" },
        showSettings   = { btn = "settingsBtn" },
    }
    local chainOrder = sbd._iconChainOrder or ECHAT.ResolveSidebarIconOrder()

    local anchor = nil
    for _, key in ipairs(chainOrder) do
        local refs = CHAIN_REFS[key]
        local btn = refs and sbd[refs.btn]
        if btn then
            local shown = cfg[key] ~= false
            btn:SetShown(shown)
            local tail = refs.tail and sbd[refs.tail]
            if tail then tail:SetShown(shown) end
            if shown then
                btn:ClearAllPoints()
                if anchor then
                    btn:SetPoint("TOP", anchor, "BOTTOM", 0, -ICON_GAP)
                else
                    btn:SetPoint("TOP", sb, "TOP", 0, -ICON_GAP + iconTopShift)
                end
                anchor = tail or btn
            end
        end
    end

    -- Scroll is independent
    if sbd.scrollBtn then sbd.scrollBtn:SetShown(cfg.showScroll ~= false) end

    -- Re-apply free move offsets after chain layout
    if ECHAT.ApplyIconFreeMove then ECHAT.ApplyIconFreeMove() end
end

-- Map of sidebar-icon visibility key -> its CFD button reference. The button is
-- only created at login for icons that were enabled at that time, so enabling a
-- previously-disabled icon has no frame to show until the sidebar is rebuilt on
-- reload. The options panel uses this to fire a reload prompt only when adding a
-- brand-new icon (scrollBtn is always created, so it never needs one).
local SIDEBAR_ICON_REFS = {
    showFriends    = "friendsBtn",
    showGuild      = "guildBtn",
    showDurability = "durabilityBtn",
    showCopy       = "copyBtn",
    showPortals    = "portalBtn",
    showVoice      = "voiceBtn",
    showSettings   = "settingsBtn",
    showScroll     = "scrollBtn",
}

-- Canonical chain-icon keys and their fallback order values. Explicit numbers
-- in cfg.sidebarIconOrder win; keys without one fall back here. Friends and
-- Durability sit below zero so profiles saved before full reordering existed
-- (their maps only ever held the four middle keys) keep today's layout:
-- Friends, Durability, then the middle group. Scroll is not part of the
-- chain -- it stays pinned at the sidebar bottom.
local SIDEBAR_CHAIN_KEYS = {
    "showFriends", "showGuild", "showDurability", "showCopy", "showPortals", "showVoice", "showSettings",
}
local SIDEBAR_FALLBACK_ORDER = {
    showFriends = -20, showGuild = -15, showDurability = -10,
    showCopy = 1, showPortals = 2, showVoice = 3, showSettings = 4,
}

-- Returns the chain-icon keys sorted into the user's saved order. Used by the
-- sidebar creation pass (reload-time source of truth), by ApplySidebarIcons as
-- a fallback when no creation snapshot exists, and by the options dropdown to
-- list its rows.
function ECHAT.ResolveSidebarIconOrder()
    local cfg = ECHAT.DB()
    local map = (cfg and cfg.sidebarIconOrder) or {}
    local keyIndex = {}
    local keys = {}
    for i = 1, #SIDEBAR_CHAIN_KEYS do
        keys[i] = SIDEBAR_CHAIN_KEYS[i]
        keyIndex[SIDEBAR_CHAIN_KEYS[i]] = i
    end
    local function OrderOf(key)
        local o = map[key]
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

-- Force Chat on Screen: when the saved preference is on, keep ChatFrame1 clamped to
-- the screen; otherwise allow it to be dragged off-screen (the default). Applied at
-- load and whenever the Chat options toggle changes. Persists via the chat DB.
function ECHAT.ApplyForceOnScreen()
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    local cfg = ECHAT.DB()
    local force = cfg and cfg.forceOnScreen == true or false
    cf1:SetClampedToScreen(force)
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
    -- Separate Sidebar: detach from the panel by the configured gap; the
    -- sidebar keeps its own bg and (via ApplyExtendedBackground) gets its
    -- own panel-style border.
    local gap = (cfg.sidebarSeparate == true) and (cfg.sidebarSeparateSpacing or 8) or 0
    sb:ClearAllPoints()
    if cfg.sidebarRight then
        sb:SetPoint("TOPLEFT", CFD(cf1).bg, "TOPRIGHT", gap, 0)
        sb:SetPoint("BOTTOMLEFT", CFD(cf1).bg, "BOTTOMRIGHT", gap, 0)
    else
        sb:SetPoint("TOPRIGHT", CFD(cf1).bg, "TOPLEFT", -gap, 0)
        sb:SetPoint("BOTTOMRIGHT", CFD(cf1).bg, "BOTTOMLEFT", -gap, 0)
    end
    -- Move the divider to the correct edge; hidden entirely in separate
    -- mode (it is the joint line between sidebar and panel).
    if CFD(cf1).sidebarDiv then
        CFD(cf1).sidebarDiv:ClearAllPoints()
        if cfg.sidebarRight then
            CFD(cf1).sidebarDiv:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
            CFD(cf1).sidebarDiv:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0)
        else
            CFD(cf1).sidebarDiv:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
            CFD(cf1).sidebarDiv:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
        end
        CFD(cf1).sidebarDiv:SetShown(cfg.sidebarSeparate ~= true)
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
        portalBtn = "M+ Portals", voiceBtn = "Voice/Channels", settingsBtn = "Settings",
        scrollBtn = "Scroll to Bottom",
    }
    local fc = d.friendsCount
    local gc = d.guildCount
    local dp = d.durabilityPct
    for _, key in ipairs({ "friendsBtn", "guildBtn", "durabilityBtn", "copyBtn", "portalBtn", "voiceBtn", "settingsBtn", "scrollBtn" }) do
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
            elseif key == "guildBtn" and gc then
                gc:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    gc:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                        EUI.ShowWidgetTooltip(self, label)
                    end
                end)
                btn:SetScript("OnLeave", function()
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    gc:SetTextColor(r, g, b, 0.5)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                end)
            elseif key == "durabilityBtn" and dp then
                dp:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    dp:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                        EUI.ShowWidgetTooltip(self, label)
                    end
                end)
                btn:SetScript("OnLeave", function()
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    dp:SetTextColor(r, g, b, 0.5)
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

    local BASE_FRIEND = 26
    local BASE_ICON = 22
    local BASE_FONT = 9

    -- _freeMoveH mirrors each icon's height from these known size constants so
    -- the free-move natural-position walk (TopYFromSidebarTop) never has to call
    -- GetHeight() -- a geometry resolve that can taint the Edit-Mode ChatFrame1.
    -- These are our own frames, so writing the field is safe.
    for _, key in ipairs({ "durabilityBtn", "copyBtn", "portalBtn", "voiceBtn", "settingsBtn", "scrollBtn" }) do
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

-- Y offset of `frame`'s TOP edge below the SIDEBAR's TOP edge, computed from
-- GetPoint (stored anchor data, no geometry resolve) plus each frame's STORED
-- height (_freeMoveH, written from known size constants in ApplySidebarIconScale).
--
-- CRITICAL: this deliberately never calls GetHeight()/GetWidth()/GetCenter() or
-- any geometry-RESOLVING getter. Those resolve a frame's rect by walking its
-- anchor chain, which for our icons runs icon -> sidebar -> chat bg -> ChatFrame1.
-- ChatFrame1 is Edit-Mode-secured; forcing its layout to resolve from our
-- insecure code TAINTS it, and the next BN whisper then errors in HistoryKeeper /
-- FCFManager. GetHeight here used to taint ChatFrame1 whenever its geometry was
-- still unresolved at the moment of the walk (login timing / saved chat layout) --
-- which is why it only hit some users. Reading the pre-stored _freeMoveH removes
-- the resolve entirely while keeping the math identical.
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

-- Capture each icon's natural position as an offset from a sidebar EDGE (TOP for
-- the top-stacked icons, BOTTOM for the scroll button), computed taint-safely.
-- Stored once; re-applying never reads live geometry, so offsets never compound.
local function CaptureNatural(btn, sb)
    if btn._freeMoveNat then return end
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
    -- the anchor chain to ChatFrame1, so it is taint-safe. GetParent() == sidebar.
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

    -- Free move is opt-in. When it is OFF (the common case) we do NOTHING here:
    -- no anchor-chain capture, no drag-hook install, no offsets. This guard is
    -- the actual fix for the on-some-profiles taint -- CaptureNatural walks the
    -- icon anchor chain, and running that walk while the feature is disabled was
    -- pure cost that, for users whose chat geometry was still unresolved at
    -- login, resolved up to and tainted the Edit-Mode ChatFrame1. The setting
    -- previously gated only the offset APPLY; the capture ran unconditionally.
    -- Enabling the toggle re-runs ApplySidebarIcons -> ApplyIconFreeMove, so the
    -- hooks install the moment the feature is turned on. Icons left untouched
    -- here simply keep their natural chain layout, which is exactly what we want.
    if not cfg.freeMoveIcons then return end

    local btns = {
        { ref = "friendsBtn",    key = "friends" },
        { ref = "guildBtn",      key = "guild" },
        { ref = "durabilityBtn", key = "durability" },
        { ref = "copyBtn",       key = "copy" },
        { ref = "portalBtn",     key = "portals" },
        { ref = "voiceBtn",      key = "voice" },
        { ref = "settingsBtn",   key = "settings" },
        { ref = "scrollBtn",     key = "scroll" },
    }

    -- PHASE 1 -- capture every icon's natural anchor (GetPoint anchor data +
    -- stored heights, never a geometry-resolving getter; see TopYFromSidebarTop)
    -- and install the drag hooks. This MUST complete for ALL icons before any
    -- icon is re-anchored in Phase 2. The capture walks each icon's anchor chain,
    -- so if Phase 2 ran interleaved, a later icon's walk would read an earlier
    -- icon's already-applied offset and bake it into its "natural" position --
    -- making icons drift on every reload. Two phases keep the chain pristine
    -- throughout capture.
    for _, info in ipairs(btns) do
        local btn = CFD(cf1)[info.ref]
        if btn then
            btn._freeMoveKey = info.key
            CaptureNatural(btn, sb)
            EnableIconFreeMove(btn)
        end
    end

    -- PHASE 2 -- re-anchor each icon to its sidebar edge at natural + saved
    -- offset, so the icons move independently of one another.
    for _, info in ipairs(btns) do
        local btn = CFD(cf1)[info.ref]
        if btn then ApplyIconOffset(btn, sb) end
    end
end

-- Portal flyout: dungeon portal spell buttons, built from the shared season
-- list (EllesmereUI.SEASON_PORTALS) -- one place to update per season.
local PORTAL_SPELLS, PORTAL_SHORT = {}, {}
for _, e in ipairs(EllesmereUI.SEASON_PORTALS) do
    PORTAL_SPELLS[#PORTAL_SPELLS + 1] = e.spellID
    PORTAL_SHORT[e.spellID] = e.short
end

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
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(label, true) end
            label:SetFont(GetFont(), 8, (EUI.SlugFlag and EUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
            label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
            label:SetTextColor(1, 1, 1, 0.9)
            label:SetText((EllesmereUI and EllesmereUI.L and EllesmereUI.L(short)) or short)
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
                GameTooltip:AddLine(EUI.L("Housing Dashboard"))
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
            local bar = cf.ScrollBar

            if eb and (i <= 10 or not BISECT_EB_ANCHORS_OFF) then
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

            if bar and (i <= 10 or not BISECT_EB_ANCHORS_OFF) then
                bar:ClearAllPoints()
                if onTop then
                    bar:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -22)
                else
                    bar:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, -2)
                end
                bar:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 5, 2)
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
    -- Dock manager: once, outside the loop. The tabs are its children and
    -- inherit this alpha -- the original (and only working) way the tab strip
    -- fades with the panel; see the tab-alpha note at the fade locals.
    if _euiDockStyled and _G.GeneralDockManager then
        _G.GeneralDockManager:SetAlpha(alpha)
    end
    -- Tab host clip container (UIParent-parented): carries the dock fade
    -- for the border/separator/underline hosts.
    if ns._tabHostClip then ns._tabHostClip:SetAlpha(alpha) end
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
    -- Behind-tabs background extension (UIParent-parented, so it does not inherit
    -- the chat frame alpha -- fade it directly alongside the chat).
    if ns._chatBgExt then ns._chatBgExt:SetAlpha(alpha) end
    if ns._chatPanelBorder then ns._chatPanelBorder:SetAlpha(alpha) end
    if ns._sidebarSeparateBorder then
        ns._sidebarSeparateBorder:SetAlpha(min(alpha, _sidebarFadeAlpha))
    end
    -- Tab-strip bottom separator is UIParent-parented like the extension.
    -- Panel bottom separator is now a texture on bg -- inherits the chat
    -- frame's alpha automatically, no explicit write needed.
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
        ECHAT.SetChatAlpha(1)
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

-- Chat events that count as real PLAYER chat activity (used ONLY to reset the
-- idle-fade timer). MONSTER_SAY / MONSTER_YELL are deliberately EXCLUDED: in a
-- party their sender (chanSender) is a SECRET value, and registering this
-- insecure frame for those events taints Blizzard's HistoryKeeper when it
-- string-converts the secret sender -> "tainted by EllesmereUIChat" spam on every
-- monster line. Ambient NPC chat is not user activity, so excluding it is also
-- correct for the feature. All sender names below are plain visible player names.
local CHAT_MSG_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_CHANNEL = true,
}

-------------------------------------------------------------------------------
--  Tab reskin: in-place reskin of Blizzard tabs.
--  We work WITH Blizzard's tab system instead of replacing it.
--  Blizzard tabs are stripped of textures and restyled with our visuals.
--  ALL styling re-assert is DEFERRED (QueueTabPass + the deferred
--  FCFDock_SelectWindow/FCF_Close hooks). No synchronous hooks on
--  FCFTab_UpdateColors, FCFDock_UpdateTabs, or tab methods -- their bodies
--  executed inside the secure temp-whisper creation chain and blocked
--  UpdateHeader's secret width math (2026-07-21 taintlog).
-------------------------------------------------------------------------------

-- Texture name suffixes to strip from each tab
local TAB_TEX_SUFFIXES = {
    "Left", "Middle", "Right",
    "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
}

-- Update visual state of one skinned tab.
local function UpdateTabStyle(tab)
    if not tab or not CFD(tab).skinned then return end
    local chatFrame = CFD(tab).chatFrame
    if not chatFrame then return end
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local isActive = chatFrame.isDocked == false and chatFrame:IsShown()
        or (chatFrame == selected)

    -- Dynamic (temp whisper) tabs sit at Blizzard's native seat: flush
    -- against the static strip and 1px low. The tab FRAME must never be
    -- moved (three field failures; see the note above ApplyTabLayout), so
    -- correct it visually: shift OUR drawn layers one PHYSICAL pixel right
    -- and up on dynamic tabs (PP.perfect / UIParent effective scale -- the
    -- chat module never SetScales, so every tab shares UIParent's effective
    -- scale, and reading it touches nothing chat-owned). State-guarded so
    -- the re-anchor runs only when the shift value actually changes
    -- (dock-state transitions, UI-scale/resolution changes).
    local d = CFD(tab)
    local onePhysPx = 1
    if PP and PP.perfect then
        onePhysPx = PP.perfect / UIParent:GetEffectiveScale()
    end
    -- Per-axis shift, tuned empirically against the rendered result (the
    -- tab's fractional physical position makes the axes round differently):
    -- 0 right / 2 up lands the visuals level and gapped at the tested scale.
    local isDyn = chatFrame.isDocked and not chatFrame.isStaticDocked
    local visShiftX = isDyn and 0 or 0
    local visShiftY = isDyn and (2 * onePhysPx) or 0
    local visShift = visShiftX + visShiftY * 1000  -- change-detection key
    if not BISECT_TEX_SHIFT_OFF and d.visShift ~= visShift then
        d.visShift = visShift
        -- Pixel-snap defeats a sub-unit offset: the tab sits at fractional
        -- physical coords, so a snapped texture rounds the shift
        -- asymmetrically. Disable snapping on the shifted layers so they
        -- render the exact offset. Dynamic tabs only -- static tab layers
        -- keep default snapping (crisp edges, and SetAllPoints alignment
        -- never exposes the fraction there).
        local unsnap = isDyn and PP and PP.DisablePixelSnap
        local function ShiftRect(r)
            if not r then return end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", tab, "TOPLEFT", visShiftX, visShiftY)
            r:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", visShiftX, visShiftY)
            if unsnap and r.SetSnapToPixelGrid then PP.DisablePixelSnap(r) end
        end
        -- Tab-parented TEXTURES only (field-safe class). Host FRAMES get
        -- their shift inside PositionTabHosts -- never anchor writes that
        -- tie a frame to the tab.
        ShiftRect(d.bg)
        ShiftRect(d.hover)
    end

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
        fs:SetFont(GetTabFont(), ECHAT.DB().tabFontSize or 11, "")
        fs:SetJustifyH("CENTER")
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tab, visShiftX, visShiftY)
        local cfg = ECHAT.DB()
        local tc = isActive
            and (cfg.tabFontColorActive or { r=1, g=1, b=1, a=1 })
            or (cfg.tabFontColor or { r=1, g=1, b=1, a=.65 })
        -- PERMANENT (user decision 2026-07-22): temp whisper tabs keep
        -- Blizzard's own text color -- zero writes to the secret-name
        -- fontstring, and the whisper color doubles as a visual marker for
        -- conversation tabs. Same gate the pre-841 module shipped.
        if not chatFrame.isTemporary then
            fs:SetTextColor(tc.r or 1, tc.g or 1, tc.b or 1, tc.a == nil and 1 or tc.a)
        end
    end

    local cfg = ECHAT.DB()
    if CFD(tab).bg then
        local c = isActive
            and (cfg.tabBackgroundColorActive or {r=.03,g=.045,b=.05,a=.65})
            or (cfg.tabBackgroundColor or {r=.03,g=.045,b=.05,a=.44})
        local bgRegion = CFD(tab).bg
        -- Optional tab background texture (un-synced style only); "none"
        -- keeps the flat color. Same catalogue + tint mechanism as the
        -- chat panel background.
        local texKey = (cfg.syncTabBorder == false)
            and (cfg.tabBackgroundTexture or "none") or "none"
        local texPath
        if texKey ~= "none" then
            if ECHAT.RefreshBgTextureCatalogue then ECHAT.RefreshBgTextureCatalogue() end
            if EllesmereUI.ResolveTexturePath then
                texPath = EllesmereUI.ResolveTexturePath(ns.chatBgTextures, texKey, nil)
            else
                texPath = ns.chatBgTextures and ns.chatBgTextures[texKey]
            end
        end
        if texPath then
            bgRegion:SetTexture(texPath)
            bgRegion:SetVertexColor(c.r or .03, c.g or .045, c.b or .05, c.a == nil and 1 or c.a)
        else
            -- Clear texture-mode tint before returning to solid color.
            bgRegion:SetVertexColor(1, 1, 1, 1)
            bgRegion:SetColorTexture(c.r or .03, c.g or .045, c.b or .05, c.a == nil and 1 or c.a)
        end
    end

    local underline = CFD(tab).activeUnderline
    if underline then
        local mode = cfg.activeUnderlineColorMode or "accent"
        local r, g, b, a
        if mode == "accent" then
            r, g, b = EllesmereUI.GetAccentColor(); a = 1
        elseif mode == "border" then
            local borderMode = cfg.panelBorderColorMode or "custom"
            if borderMode == "accent" then
                r, g, b = EllesmereUI.GetAccentColor()
            elseif borderMode == "class" then
                local _, class = UnitClass("player")
                local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                r, g, b = c and c.r or 1, c and c.g or 1, c and c.b or 1
            else
                local c = cfg.panelBorderColor or {r=1,g=1,b=1}
                r, g, b = c.r, c.g, c.b
            end
            a = cfg.panelBorderOpacity or 0.18
        else
            local c = cfg.activeUnderlineColor or {r=.05,g=.82,b=.61,a=1}
            r, g, b, a = c.r, c.g, c.b, c.a == nil and 1 or c.a
        end
        underline:SetColorTexture(r, g, b, a)
        underline:SetShown(cfg.activeUnderline ~= false and isActive)
    end

end

function ECHAT.ApplyTabAppearance()
    for i = 1, 20 do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and CFD(tab).skinned then UpdateTabStyle(tab) end
    end
end

-- Numeric host placement with ZERO getter calls into the chat/dock chain.
-- Two field-proven taint injectors rule this design: (1) anchoring an
-- insecure frame to a Blizzard tab, and (2) geometry resolves (GetLeft
-- etc.) on tab/dock regions from insecure code -- both poison the secure
-- dock pass into UpdateHeader's secret whisper math. Positions therefore
-- accumulate purely from OUR OWN layout numbers: the widths ApplyTabLayout
-- stamps (CFD hostW), the configured spacing, and the clip's fixed slack
-- constants (clip TOPLEFT = gdm TOPLEFT -4,+8; first static tab sits at
-- gdm BOTTOMLEFT, i.e. clip-local x=4, y=8). STATIC docked tabs only --
-- dynamic whisper tabs get no host visuals (their bg/hover textures
-- remain); until the tab-geometry gate clears, no hostW exists and hosts
-- simply stay hidden.
function ECHAT.PositionTabHosts()
    local clip = ns._tabHostClip
    if not clip then return end
    local cfg = ECHAT.DB()
    local configured = cfg.tabSpacing == nil and 1 or cfg.tabSpacing
    local spacing = (cfg.extendBgBehindTabs and 1 or configured) * ((PP and PP.mult) or 1)
    local height = GetTabHeight()
    local positioned = {}
    local x = 4
    if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then
        for _, cf in ipairs(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) do
            local n = cf and cf:GetName()
            local tab = n and _G[n .. "Tab"]
            local d = tab and CFD(tab)
            if d and d.skinned and cf.isStaticDocked and d.hostW then
                local function Place(host)
                    if not host then return end
                    host:ClearAllPoints()
                    host:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", x, 8)
                    host:SetSize(d.hostW, height)
                    host:Show()
                    positioned[host] = true
                end
                Place(d.panelBorder)
                Place(d.tabSeparatorHost)
                Place(d.activeUnderlineHost)
                x = x + d.hostW + spacing
            end
        end
    end
    -- Anything not placed this pass (dynamic whisper tabs, hidden or
    -- unmeasured tabs) stays hidden.
    for i = 1, 20 do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        local d = tab and CFD(tab)
        if d and d.skinned then
            for _, host in ipairs({ d.panelBorder, d.tabSeparatorHost, d.activeUnderlineHost }) do
                if host and not positioned[host] and host:GetParent() ~= UIParent then
                    host:Hide()
                end
            end
        end
    end
end

-- Without the extended tab-strip background, each visible tab is its own
-- visual island. Give those tabs the same configurable border as the chat
-- panel; the unified layout uses only the single outer panel border instead.
function ECHAT.ApplyTabBorders()
    if BISECT_TAB_BORDERS_OFF then return end
    local cfg = ECHAT.DB()
    local sync = cfg.syncTabBorder ~= false
    local prefix = sync and "panelBorder" or "tabBorder"
    local function B(suffix, fallback)
        local value = cfg[prefix .. suffix]
        if value == nil then return fallback end
        return value
    end
    local show = cfg.extendBgBehindTabs ~= true
    local sizes = { none=0, thin=1, normal=2, heavy=3, strong=4 }
    local thicknessKey = B("Thickness", "none")
    local size = sizes[thicknessKey] or 1
    local mode = B("ColorMode", "custom")
    local r, g, b
    if mode == "accent" then
        r, g, b = EllesmereUI.GetAccentColor()
    elseif mode == "class" then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        r, g, b = c and c.r or 1, c and c.g or 1, c and c.b or 1
    else
        local c = B("Color", { r=1, g=1, b=1 })
        r, g, b = c.r, c.g, c.b
    end
    local alpha = B("Opacity", nil)
    if alpha == nil then alpha = mode == "custom" and 0.18 or 0.5 end
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)

    for i = 1, 20 do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        local host = tab and CFD(tab).panelBorder
        if host then
            local chatFrame = CFD(tab).chatFrame
            local undocked = chatFrame and chatFrame.isDocked == false
            if chatFrame and FCF_IsDocked then
                local ok, docked = pcall(FCF_IsDocked, chatFrame)
                if ok then undocked = not docked end
            end
            -- Active tab may carry its own border color.
            local br, bgr, bb, ba = r, g, b, alpha
            if cfg.activeTabBorder ~= false then
                local isActive = (chatFrame and chatFrame == selected)
                    or (chatFrame and undocked and chatFrame:IsShown())
                local ac = isActive and cfg.tabBorderColorActive
                if ac then
                    br, bgr, bb = ac.r or r, ac.g or g, ac.b or b
                    ba = ac.a == nil and alpha or ac.a
                end
            end
            -- Docked hosts live on the shared clip container (never on the
            -- tab -- taint root cause); undocked ones on UIParent, unclipped.
            -- Anchors are owned by PositionTabHosts (numeric, no tab ties).
            local wantedParent = undocked and UIParent or GetTabHostClip()
            if host:GetParent() ~= wantedParent then
                host:SetParent(wantedParent)
            end
            host:SetFrameStrata("DIALOG")
            -- Constant level: hosts render on our clip at DIALOG strata,
            -- so a tab-derived level is meaningless -- and tab:GetFrameLevel
            -- was an un-exonerated tab getter in this (dirty-tested) pass.
            local level = 100
            host:SetFrameLevel(level)
            -- No alpha writes here at all: hosts default to 1, docked hosts
            -- inherit the dock fade from the clip container's alpha
            -- (_ApplyAlpha), and visibility is handled by SetShown below.
            -- Tab alpha is entirely Blizzard's -- never read or written.
            EllesmereUI.ApplyBorderStyle(host, show and size or 0,
                br, bgr, bb, ba, B("Texture", "solid"),
                B("OffsetX", nil), B("OffsetY", nil),
                B("ShiftX", nil), B("ShiftY", nil), "chat", thicknessKey)
            local solidBorder = PP and PP.GetBorders and PP.GetBorders(host)
            if solidBorder then solidBorder:SetFrameLevel(level + 1) end
            host:SetShown(show and size > 0 and tab:IsShown())
        end
    end
end

function ECHAT.ApplyTabSeparators()
    if BISECT_TAB_BORDERS_OFF then return end
    local cfg = ECHAT.DB()
    local show = cfg.extendBgBehindTabs == true and not cfg.hideBorders
    local r, g, b, a = GetInnerBorderColor(cfg)
    local dockedTabs = {}
    if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then
        for _, cf in ipairs(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) do
            local name = cf and cf:GetName()
            local tab = name and _G[name .. "Tab"]
            if tab and tab:IsShown() then dockedTabs[tab] = true end
        end
    end

    -- One continuous separator below the chat panel. The sidebar is a separate
    -- visual column and must never be crossed by the tab separator.
    -- FIELD-CONVICTED (2026-07-22): the old implementation was a UIParent
    -- frame ANCHORED to bg -- an insecure frame in ChatFrame1's rect
    -- dependency web (bg is cf1-parented), which taints the temp-whisper
    -- creation chain exactly like tab-anchored hosts did. Safe form: a
    -- TEXTURE on our bg frame (textures on our own frames are the
    -- 8.5.2-proven class); it inherits the chat fade for free.
    -- FIELD-CONVICTED HOME (2026-07-22, three texture variants dirty): the
    -- separator may NOT live anywhere in ChatFrame1's rect web -- not as
    -- an anchored frame, not as a texture on bg, in-bounds or out,
    -- snapped or not. Tab bg/hover textures on the tabs themselves stay
    -- clean, so the exact hazard boundary inside the cf1 web is unmapped;
    -- the clip container (gdm-chained, fully exonerated with textures +
    -- per-pass writes) is the proven-safe home. Position is numeric:
    -- clip bottom slack is 8, gdm sits GetTabPadding() above bg's top, so
    -- bg's top edge lies at y = 8 - padding in clip space; x slack 4.
    -- Separator: EXACT copy of the proven-clean per-tab separator pattern
    -- (a host FRAME child of the clip, anchored once at creation, with a
    -- SetAllPoints texture; per pass only color + shown). A direct
    -- clip-region texture -- the only shape without a clean twin -- tested
    -- dirty in every variant; do not put regions directly on the clip.
    local clip = GetTabHostClip()
    if clip then
        local y = 8 - (GetTabPadding() or 0)
        if ns._tabPanelSepHost and ns._tabPanelSepY ~= y then
            ns._tabPanelSepHost:Hide()
            ns._tabPanelSepHost = nil
            ns._tabPanelBottomSeparatorTex = nil
        end
        if not ns._tabPanelSepHost then
            local host = CreateFrame("Frame", nil, clip)
            host:SetFrameStrata("DIALOG")
            host:SetFrameLevel(90)
            host:EnableMouse(false)
            host:SetHeight((PP and PP.mult) or 1)
            host:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 4, y)
            host:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", -4, y)
            local tex = host:CreateTexture(nil, "OVERLAY", nil, 7)
            tex._euiOwned = true
            tex:SetAllPoints()
            ns._tabPanelSepHost = host
            ns._tabPanelBottomSeparatorTex = tex
            ns._tabPanelSepY = y
        end
        ns._tabPanelBottomSeparatorTex:SetColorTexture(r, g, b, a)
        ns._tabPanelSepHost:SetShown(show)
    end

    for i = 1, 20 do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        local d = tab and CFD(tab)
        if d and d.tabSeparatorHost then
            d.tabSeparatorBottom:SetColorTexture(r, g, b, a)
            d.tabSeparatorLeft:SetColorTexture(r, g, b, a)
            d.tabSeparatorBottom:Hide()
            -- A right edge on every docked tab creates all between-tab lines
            -- and gives the final tab the same clean outer edge.
            d.tabSeparatorLeft:SetShown(show and dockedTabs[tab] == true)
            -- Clip-parented host no longer auto-hides with its tab; couple
            -- visibility explicitly.
            d.tabSeparatorHost:SetShown(show and tab:IsShown())
        end
    end
end

-- One-time reskin of a Blizzard chat tab (strip textures, add our visuals)
local function SkinTab(cf)
    local name = cf:GetName()
    if not name then return end
    local tab = _G[name .. "Tab"]
    if not tab or CFD(tab).skinned then return end
    CFD(tab).skinned = true
    CFD(tab).chatFrame = cf
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

    -- Hover highlight
    local hover = tab:CreateTexture(nil, "HIGHLIGHT")
    hover._euiOwned = true
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.05)
    CFD(tab).hover = hover

    -- Cache the tab's text FontString for UpdateTabStyle (avoids
    -- repeated GetFontString() calls on the Blizzard tab).
    -- Some tab implementations use _G[name.."TabText"] instead of tab.Text.
    CFD(tab).tabText = tab.Text or _G[name .. "TabText"]
    tab:SetPushedTextOffset(0, 0)
    if not BISECT_TAB_GEOMETRY_OFF then
        tab:SetHeight(GetTabHeight())
    end

    -- Host frames: parented to the shared UIParent clip container, only
    -- ANCHORED to the tab (see GetTabHostClip -- parenting frames to the
    -- tab itself was the whisper-creation taint root cause).
    local hostParent = GetTabHostClip()
    -- NO tab anchors on hosts, ever (see FINAL HOST DESIGN at the top).
    -- PositionTabHosts places them numerically; they start hidden.
    local panelBorder = CreateFrame("Frame", nil, hostParent)
    panelBorder:EnableMouse(false)
    panelBorder:Hide()
    CFD(tab).panelBorder = panelBorder

    local separatorHost = CreateFrame("Frame", nil, hostParent)
    separatorHost:Hide()
    separatorHost:SetFrameStrata("DIALOG")
    separatorHost:SetFrameLevel(90)
    separatorHost:EnableMouse(false)
    local onePx = (PP and PP.mult) or 1
    local separatorBottom = separatorHost:CreateTexture(nil, "OVERLAY", nil, 7)
    separatorBottom:SetHeight(onePx)
    separatorBottom:SetPoint("BOTTOMLEFT", separatorHost, "BOTTOMLEFT", 0, 0)
    separatorBottom:SetPoint("BOTTOMRIGHT", separatorHost, "BOTTOMRIGHT", 0, 0)
    local separatorLeft = separatorHost:CreateTexture(nil, "OVERLAY", nil, 7)
    separatorLeft:SetWidth(onePx)
    separatorLeft:SetPoint("TOPRIGHT", separatorHost, "TOPRIGHT", 0, 0)
    separatorLeft:SetPoint("BOTTOMRIGHT", separatorHost, "BOTTOMRIGHT", 0, 0)
    if PP and PP.DisablePixelSnap then
        PP.DisablePixelSnap(separatorBottom)
        PP.DisablePixelSnap(separatorLeft)
    end
    CFD(tab).tabSeparatorHost = separatorHost
    CFD(tab).tabSeparatorBottom = separatorBottom
    CFD(tab).tabSeparatorLeft = separatorLeft

    local underlineHost = CreateFrame("Frame", nil, hostParent)
    underlineHost:Hide()
    underlineHost:SetFrameStrata("DIALOG")
    underlineHost:SetFrameLevel(95)
    underlineHost:EnableMouse(false)
    local activeUnderline = underlineHost:CreateTexture(nil, "OVERLAY", nil, 7)
    activeUnderline:SetHeight(onePx)
    activeUnderline:SetPoint("BOTTOMLEFT", underlineHost, "BOTTOMLEFT", 0, 0)
    activeUnderline:SetPoint("BOTTOMRIGHT", underlineHost, "BOTTOMRIGHT", 0, 0)
    if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(activeUnderline) end
    activeUnderline:Hide()
    CFD(tab).activeUnderlineHost = underlineHost
    CFD(tab).activeUnderline = activeUnderline

    -- Reparent the whisper conversation icon to hidden container
    if tab.conversationIcon then
        tab.conversationIcon:SetParent(_hiddenParent)
    end

    -- NO hooksecurefunc(tab, "SetPoint") -- removed 2026-07-21 with the
    -- other synchronous tab hooks: its body executed inside the secure
    -- temp-whisper creation chain (FCF_DockUpdate re-anchors the tabs
    -- mid-creation), the same injection that blocked UpdateHeader's secret
    -- width math. The y=-1 seat normalize now lives in ApplyTabLayout
    -- (deferred passes only), which is safe again precisely because the
    -- synchronous FCFDock_UpdateTabs hook is gone -- the deferred-once
    -- rewrite was stable for months pre-841 under these same conditions.

    UpdateTabStyle(tab)
    ECHAT.ApplyTabBorders()
    ECHAT.ApplyTabSeparators()
    if ECHAT.ApplyTabSpacing then ECHAT.ApplyTabSpacing() end
    if ECHAT.PositionTabHosts then ECHAT.PositionTabHosts() end
end

function ECHAT.ApplyTabSpacing()
    if BISECT_TAB_GEOMETRY_OFF then return end
    if not GENERAL_CHAT_DOCK or not GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then return end
    local cfg = ECHAT.DB()
    local configured = cfg.tabSpacing == nil and 1 or cfg.tabSpacing
    -- Extended mode has no user-configurable spacing, but reserves one physical
    -- pixel after each right-edge separator so the next tab starts beside the
    -- line instead of rendering on top of it.
    local spacing = (cfg.extendBgBehindTabs and 1 or configured) * ((PP and PP.mult) or 1)
    -- STATIC tabs only (frames docked with isStaticDocked). Dynamic temp
    -- whisper tabs are parented to the dock's SCROLL CHILD and their anchors
    -- and widths feed FCFDock_ScrollToSelectedTab/JumpToTab's math -- when we
    -- re-chained them here, the jump never converged, the dock's OnUpdate
    -- stayed armed, and Blizzard and our pass alternated layouts every frame
    -- (field report: whisper tabs blinking and unclickable). Blizzard owns
    -- them entirely; their chain keeps its native 1px gap.
    local prev
    for _, cf in ipairs(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) do
        local n = cf and cf:GetName()
        local tab = n and _G[n .. "Tab"]
        if tab and tab:IsShown() and cf.isStaticDocked then
            if prev then
                tab:ClearAllPoints()
                tab:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
            end
            prev = tab
        end
    end
    if ECHAT.ApplyTabSeparators then ECHAT.ApplyTabSeparators() end
end

-- NO dynamic-tab anchor writes, in ANY timing regime. Field-proven three
-- times on 2026-07-20: synchronous re-chain (blink + unclickable), sync
-- Y-only rewrite (permanent scroll drift), and finally the pre-841 style
-- DEFERRED-once bridge -- which was stable for months pre-841 but now
-- fights the dock too (841's environment keeps the scroll/jump loop alive
-- in ways the old module never did). The whisper strip's 1px-left/1px-low
-- native seat is corrected VISUALLY instead: UpdateTabStyle shifts OUR
-- drawn elements (bg/hover/text/hosts) on dynamic tabs; the Blizzard tab
-- frame itself is never moved.
function ECHAT.ApplyTabLayout()
    if BISECT_TAB_GEOMETRY_OFF then
        if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
        if ECHAT.ApplyTabPadding then ECHAT.ApplyTabPadding() end
        if ECHAT.PositionTabHosts then ECHAT.PositionTabHosts() end
        return
    end
    local cfg = ECHAT.DB()
    local height = GetTabHeight()
    local paddingX = cfg.tabInnerPaddingX or 12
    for i = 1, 20 do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and CFD(tab).skinned then
            tab:SetHeight(height)
            local fs = CFD(tab).tabText
            local cfOwner = CFD(tab).chatFrame
            -- Text-derived widths apply to STATIC docked tabs only. Dynamic
            -- temp whisper tabs are scroll-managed: FCFDock_CalculateTabSize
            -- caps their width and the scroll/jump math depends on it, so
            -- Blizzard owns their sizing. Their labels are also SECRET target
            -- names on Midnight (rendered width of secret text is a secret
            -- number; arithmetic on it is a hard error -- field report:
            -- ChatFrame11Tab), so the issecretvalue guard stays as the belt.
            if fs and fs.GetStringWidth and cfOwner and cfOwner.isStaticDocked then
                local w = fs:GetStringWidth()
                if w and not (issecretvalue and issecretvalue(w)) then
                    local tabW = max(40, ceil(w + paddingX * 2))
                    tab:SetWidth(tabW)
                    -- Width record for PositionTabHosts (numeric host
                    -- placement without geometry resolves).
                    CFD(tab).hostW = tabW
                end
            end
            -- Dynamic (docked, non-static) whisper tab seat normalize:
            -- Blizzard anchors the first dynamic tab LEFT/LEFT y=-1 on the
            -- scroll child; rewrite once to (+1physpx, 0). Idempotent (the
            -- rewritten anchor has y=0, so repeat passes skip), DEFERRED
            -- passes only -- this replaced the per-tab SetPoint hook, whose
            -- body ran inside the secure temp-window creation chain and
            -- tainted UpdateHeader's secret width math (2026-07-21).
            if cfOwner and cfOwner.isDocked and not cfOwner.isStaticDocked then
                local pt, rel, relPt, x, y = tab:GetPoint(1)
                if pt == "LEFT" and relPt == "LEFT" and y and y ~= 0 then
                    local es = tab:GetEffectiveScale()
                    local onePhys = PP and PP.SnapForES and PP.SnapForES(1, es) or 1
                    tab:SetPoint(pt, rel, relPt, (x or 0) + onePhys, 0)
                end
            end
        end
    end
    local gdm = _G.GeneralDockManager
    local sf = _G.GeneralDockManagerScrollFrame
    local sfc = _G.GeneralDockManagerScrollFrameChild
    if gdm then gdm:SetHeight(height) end
    if sf then sf:SetHeight(height) end
    if sfc then sfc:SetHeight(height) end
    if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
    if ECHAT.ApplyTabPadding then ECHAT.ApplyTabPadding() end
    if ECHAT.ApplyTabSpacing then ECHAT.ApplyTabSpacing() end
    if ECHAT.PositionTabHosts then ECHAT.PositionTabHosts() end
end

function ECHAT.ApplyTabPadding()
    if BISECT_TAB_PADDING_OFF then return end
    local gdm = _G.GeneralDockManager
    local cf1 = _G.ChatFrame1
    local bg = cf1 and CFD(cf1).bg
    if gdm and bg then
        local padding = GetTabPadding()
        local cfg = ECHAT.DB()
        local sidebar = cf1 and CFD(cf1).sidebar
        local sidebarActive = sidebar and (cfg.sidebarVisibility or "always") ~= "never"
        local alignFull = cfg.alignTabsToPanel and not cfg.extendBgBehindTabs and sidebarActive
        gdm:ClearAllPoints()
        if alignFull and not cfg.sidebarRight then
            gdm:SetPoint("BOTTOMLEFT", sidebar, "TOPLEFT", 0, padding)
            gdm:SetPoint("BOTTOMRIGHT", bg, "TOPRIGHT", 0, padding)
        elseif alignFull and cfg.sidebarRight then
            gdm:SetPoint("BOTTOMLEFT", bg, "TOPLEFT", 0, padding)
            gdm:SetPoint("BOTTOMRIGHT", sidebar, "TOPRIGHT", 0, padding)
        else
            gdm:SetPoint("BOTTOMLEFT", bg, "TOPLEFT", 0, padding)
            gdm:SetPoint("BOTTOMRIGHT", bg, "TOPRIGHT", 0, padding)
        end
    end
    if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
    if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
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
    local tabPadding = GetTabPadding()
    gdm:SetPoint("BOTTOMLEFT", CFD(cf1).bg, "TOPLEFT", 0, tabPadding)
    gdm:SetPoint("BOTTOMRIGHT", CFD(cf1).bg, "TOPRIGHT", 0, tabPadding)
    local dockH = GetTabHeight()
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
--  Edit box hooks only on frames 1-10 (temp windows 11+ get visuals only).
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

    -- Position flush below chat frame (8.5.2 did this for ALL frames
    -- incl. temp 11+; gate 7 of the bisect ladder holds 11+ untouched
    -- until its clearing cycle).
    if idx <= 10 or not BISECT_EB_ANCHORS_OFF then
        eb:ClearAllPoints()
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -10, -8)
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -8)
        eb:SetHeight(23)
    end

    -- Font: use the SAME outline as the chat frames + ECHAT.ApplyFonts (which
    -- reads GetOutlineFlag too), so the input box always matches the rest of
    -- chat. Hardcoding "" here left it un-outlined (drop shadow showed through)
    -- whenever the user picked an outline for chat.
    local ebSize = GetFrameFontSize(cf:GetID())
    eb:SetFont(GetFont(), ebSize, GetOutlineFlag())
    eb:SetTextInsets(8, 8, 0, 0)

    -- Apply custom font to the header ("Say:", "Party:", etc.) and suffix.
    -- Called once at skin time and again on focus-gained (covers chat type
    -- switches). Never from inside UpdateHeader -- calling SetFont in that
    -- secure chain taints the execution context and blocks SendChatMessage.
    local function ApplyEditBoxHeaderFont(editBox)
        local sz = GetFrameFontSize(editBox:GetParent():GetID())
        local ol = GetOutlineFlag()
        if editBox.header then
            editBox.header:SetFont(GetFont(), sz, ol)
        end
        if editBox.headerSuffix then
            editBox.headerSuffix:SetFont(GetFont(), sz, ol)
        end
    end
    if idx <= 10 or not BISECT_EB_ANCHORS_OFF then
        ApplyEditBoxHeaderFont(eb)
    end

    -- Edit box HOOKS (not the plain setters above) taint a temp whisper
    -- window's execution context. When that conversation's secure code later
    -- touches its secret tellTarget (e.g. a BN_WHISPER presence ID) it poisons
    -- the shared ChatHistory access tables, after which EVERY chat message
    -- errors in HistoryKeeper for the rest of the session. Only the permanent
    -- docked frames (1-10) are safe to hook; temp windows (11+) get visual
    -- skinning only. (This matches the function header's stated intent and the
    -- 1-10 header-font gate in ECHAT.ApplyFonts.)
    if idx <= 10 then
        eb:HookScript("OnEditFocusGained", function(self) ApplyEditBoxHeaderFont(self) end)

        -- Plain Up/Down input recall. The Midnight edit box performs no
        -- native recall on plain arrows regardless of alt-arrow mode, so the
        -- recall is Lua-side over an external history. Two rules keep it
        -- taint-safe (the previous implementation broke both and blocked
        -- /ping with ADDON_ACTION_FORBIDDEN):
        --   1. SECURE commands (IsSecureCmd: /ping, /cast, ...) never enter
        --      this history. SetText plants addon-tainted text -- harmless
        --      for ordinary sends, fatal for a protected re-send.
        --   2. Alt chords pass through untouched: Alt+Up/Down remains the
        --      engine's own untainted recall (it still holds secure
        --      commands), and our SetText must never overwrite it.
        -- Alt-arrow mode off: paired with the OnKeyDown hook in every working
        -- implementation -- without it the widget does not hand plain Up/Down
        -- to the hook. Midnight performs no native recall either way.
        eb:SetAltArrowKeyMode(false)
        if not CFD(eb).history then
            CFD(eb).history = {}
            CFD(eb).histIdx = 0
            hooksecurefunc(eb, "AddHistoryLine", function(self, text)
                if issecretvalue and issecretvalue(text) then return end
                local cmd = text and text:match("^%s*(/%S+)")
                if cmd and IsSecureCmd and IsSecureCmd(cmd) then return end
                local h = CFD(self).history
                if h[#h] ~= text then
                    h[#h + 1] = text
                    if #h > 50 then table.remove(h, 1) end
                end
            end)
            eb:HookScript("OnKeyDown", function(self, key)
                if key ~= "UP" and key ~= "DOWN" then return end
                if IsAltKeyDown() then return end
                -- Narrow, field-proven restriction guards kept from the
                -- long-shipped implementation. (C_ChatInfo.
                -- InChatMessagingLockdown exists but its breadth on Midnight
                -- is unverified -- do not swap it in blind.)
                local restricted = GetCVarBool("addonChatRestrictionsForced")
                    or (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
                        and C_ChallengeMode.IsChallengeModeActive())
                if restricted then return end
                local d = CFD(self)
                local h = d.history
                if #h == 0 then return end
                if key == "UP" then
                    d.histIdx = d.histIdx + 1
                    if d.histIdx > #h then d.histIdx = #h end
                else
                    d.histIdx = d.histIdx - 1
                    if d.histIdx < 0 then d.histIdx = 0 end
                end
                if d.histIdx == 0 then
                    self:SetText("")
                else
                    local entry = h[#h - d.histIdx + 1]
                    if entry then self:SetText(entry) else self:SetText("") end
                end
            end)
            eb:HookScript("OnEditFocusLost", function(self)
                CFD(self).histIdx = 0
            end)
        end
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
        sbDiv:SetColorTexture(GetInnerBorderColor(ECHAT.DB()))
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
        local showFriends    = icfg.showFriends ~= false
        local showGuild      = icfg.showGuild ~= false
        local showDurability = icfg.showDurability ~= false

        -- When the background is extended behind the tabs, the sidebar panel
        -- grows upward by the tab-strip height. Shift the (chain-anchored) icons
        -- up the same amount so the top icon keeps its gap from the new top edge.
        -- Skipped when free-move is on -- those icons are user-positioned, not
        -- chained, so they stay exactly where the user dropped them.
        local iconTopShift = (icfg.extendBgBehindTabs and not icfg.freeMoveIcons) and GetTabAreaHeight() or 0

        -- Chain icons are created below in the saved order (drag-to-reorder in
        -- the options dropdown; a new order takes effect on the next reload).
        local anchor = nil
        local friendsBtn, friendsCount, durabilityBtn, durabilityPct, copyBtn, portalBtn, voiceBtn, settingsBtn
        local guildBtn, guildCount

        local function ChainAnchor(btn)
            btn:ClearAllPoints()
            if anchor then
                btn:SetPoint("TOP", anchor, "BOTTOM", 0, -ICON_SPACING)
            else
                btn:SetPoint("TOP", sidebar, "TOP", 0, -ICON_SPACING + iconTopShift)
            end
        end

        local function CreateFriendsIcon()
            friendsBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_friends.png")
            friendsBtn:SetSize(26, 26)
            ChainAnchor(friendsBtn)

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

        local function CreateGuildIcon()
            guildBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_guild.png")
            guildBtn:SetSize(26, 26)
            ChainAnchor(guildBtn)

            guildCount = sidebar:CreateFontString(nil, "OVERLAY")
            guildCount:SetFont(GetFont(), 9, "")
            guildCount:SetTextColor(1, 1, 1, 0.5)
            guildCount:SetPoint("TOP", guildBtn, "BOTTOM", 0, 7)
            guildCount:SetText("0")

            guildBtn:HookScript("OnEnter", function(self)
                guildCount:SetTextColor(1, 1, 1, 0.9)
                if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                    EUI.ShowWidgetTooltip(self, "Guild")
                end
            end)
            guildBtn:HookScript("OnLeave", function()
                guildCount:SetTextColor(1, 1, 1, 0.5)
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)

            -- Online guildmate count (GetNumGuildMembers 2nd return), like
            -- Friends. Roster request is throttled: GuildRoster() itself fires
            -- GUILD_ROSTER_UPDATE, which re-enters this; unthrottled that loops.
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
            durabilityBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_durability.png")
            ChainAnchor(durabilityBtn)

            durabilityPct = sidebar:CreateFontString(nil, "OVERLAY")
            durabilityPct:SetFont(GetFont(), 9, "")
            durabilityPct:SetTextColor(1, 1, 1, 0.5)
            durabilityPct:SetPoint("TOP", durabilityBtn, "BOTTOM", 0, 0)
            durabilityPct:SetText("100%")

            durabilityBtn:HookScript("OnEnter", function(self)
                durabilityPct:SetTextColor(1, 1, 1, 0.9)
                if not self._freeMoveJustDragged and EUI.ShowWidgetTooltip then
                    EUI.ShowWidgetTooltip(self, "Equipment Durability")
                end
            end)
            durabilityBtn:HookScript("OnLeave", function()
                durabilityPct:SetTextColor(1, 1, 1, 0.5)
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)

            local function UpdateDurability()
                local lowest = 100
                for slot = 1, 18 do
                    local cur, mx = GetInventoryItemDurability(slot)
                    if cur and mx and mx > 0 then
                        local pct = (cur / mx) * 100
                        if pct < lowest then lowest = pct end
                    end
                end
                durabilityPct:SetText(math.floor(lowest) .. "%")
            end

            local durEvents = CreateFrame("Frame")
            durEvents:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
            durEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            durEvents:SetScript("OnEvent", UpdateDurability)

            CFD(cf).durabilityPct = durabilityPct
            anchor = durabilityPct
        end

        -- Create all chain icons in the saved order. Friends and Durability
        -- have bespoke creators (count/percent text + events); the rest are
        -- plain sidebar icons.
        local SPECIAL_CREATORS = {
            showFriends    = { show = showFriends,    create = CreateFriendsIcon },
            showGuild      = { show = showGuild,      create = CreateGuildIcon },
            showDurability = { show = showDurability, create = CreateDurabilityIcon },
        }
        local MIDDLE_DEFS = {
            showCopy     = { tex = "chat_copy.png" },
            showPortals  = { tex = "chat_portal.png", size = 26 },
            showVoice    = { tex = "chat_voice.png" },
            showSettings = { tex = "chat_settings.png" },
        }
        local middleBtns = {}
        local chainOrder = ECHAT.ResolveSidebarIconOrder()
        for _, key in ipairs(chainOrder) do
            local special = SPECIAL_CREATORS[key]
            if special then
                if special.show then special.create() end
            else
                local def = MIDDLE_DEFS[key]
                if def and icfg[key] ~= false then
                    local btn = MakeSidebarIcon(sidebar, MEDIA .. def.tex)
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

        -- Guild button click handler
        if guildBtn then
        guildBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
                return
            end
            ToggleGuildFrame()
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
        sbd.guildBtn = guildBtn
        sbd.durabilityBtn = durabilityBtn
        sbd.copyBtn = copyBtn
        sbd.portalBtn = portalBtn
        sbd.voiceBtn = voiceBtn
        sbd.settingsBtn = settingsBtn
        sbd.scrollBtn = scrollBtn
        -- Order snapshot for ApplySidebarIcons: live visibility toggles keep
        -- this session's layout; a changed saved order applies on reload.
        sbd._iconChainOrder = chainOrder

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
        div:SetColorTexture(GetInnerBorderColor(ECHAT.DB()))
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


    -- 5. Tab (consolidated in SkinTab -- strips textures and creates our
    --    background, border, separators, and layout hooks)
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
        -- While gate 7 leaves the temp (11+) edit box Blizzard-anchored, its
        -- native chain includes this button; anchoring to our bg (which
        -- wraps the eb) would be an anchor cycle there.
        local rbIdx = tonumber(name:match("ChatFrame(%d+)"))
        local rbAnchor = (BISECT_EB_ANCHORS_OFF and rbIdx and rbIdx > 10) and cf or CFD(cf).bg
        resizeBtn:SetPoint("BOTTOMRIGHT", rbAnchor, "BOTTOMRIGHT", -2, 2)
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

    -- Hide scrollbar arrow buttons by reparenting to hidden container.
    -- The scrollbar itself stays untouched in the frame hierarchy to
    -- avoid both trackExtent errors and HistoryKeeper taint.
    if cf.ScrollBar and not CFD(cf).scrollBarSkinned then
        local bar = cf.ScrollBar
        if bar.Back then bar.Back:SetParent(_hiddenParent) end
        if bar.Forward then bar.Forward:SetParent(_hiddenParent) end
        CFD(cf).scrollBarSkinned = true
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

    ECHAT.ApplyTabSpacing()
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
    -- Re-run the background pass so a saved Background Texture applies at
    -- login (the skin loop creates the bg textures with the solid color).
    ECHAT.ApplyBackground()
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
                if tab and CFD(tab).skinned and not BISECT_TAB_GEOMETRY_OFF then
                    tab:SetHeight(GetTabHeight())
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
        ECHAT.ApplyTabLayout()
        if ECHAT.ApplyInputPosition then ECHAT.ApplyInputPosition() end
    end

    ---------------------------------------------------------------------------
    --  4. Global tab hooks (hooksecurefunc on globals).
    ---------------------------------------------------------------------------
    if FCFDock_SelectWindow then
        hooksecurefunc("FCFDock_SelectWindow", function()
            -- Blizzard rebuilds the tab anchor chain while selecting a window.
            -- Re-apply spacing after that secure update has fully completed.
            C_Timer.After(0, function()
                UpdateTabColors()
                ECHAT.ApplyTabLayout()
            end)
        end)
    end
    -- NO synchronous hooks on FCFTab_UpdateColors or FCFDock_UpdateTabs.
    -- Both shipped briefly post-841 (recolor funnel + static-layout
    -- re-assert) and both were removed 2026-07-21: FCF_OpenTemporaryWindow
    -- -> FCF_SetTemporaryWindowType calls FCFTab_UpdateColors directly and
    -- ends with FCF_DockUpdate (a synchronous FCFDock_UpdateTabs call), so
    -- BOTH hook bodies executed inside the temp-whisper creation chain --
    -- which then Deactivates the new editBox and runs UpdateHeader's width
    -- math on the SECRET whisper-name geometry. Field taintlog (twice,
    -- after the FCF_OpenTemporaryWindow hook itself was already removed):
    -- "arithmetic on a secret value blocked because of taint from
    -- EllesmereUIChat" at ChatFrameEditBox.lua:677, and the whisper fails
    -- to route. The absence of any "while reading global" transfer line
    -- for us (DBM's hook shows one) fingers hook-body EXECUTION mid-chain
    -- as the injection, so no body shape is safe -- the funnel hooks are
    -- gone entirely. Recolor + layout now run DEFERRED from our own
    -- triggers below; the cost is a possible 1-frame Blizzard-styled
    -- flash on dock passes, accepted over the taint.
    local _tabPassQueued = false
    local function QueueTabPass()
        if BISECT_DEFERRED_PASSES_OFF then return end
        if _tabPassQueued then return end
        _tabPassQueued = true
        C_Timer.After(0, function()
            _tabPassQueued = false
            UpdateTabColors()
            ECHAT.ApplyTabLayout()
        end)
    end
    ECHAT.QueueTabPass = QueueTabPass
    if not BISECT_DEFERRED_PASSES_OFF then
        -- The yellow-reset moments (login passes, zone transitions, dock
        -- config loads) all coincide with these events on our own frame --
        -- outside Blizzard's dispatch, deferred one tick.
        local tabPassFrame = CreateFrame("Frame")
        tabPassFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        tabPassFrame:RegisterEvent("UPDATE_CHAT_WINDOWS")
        tabPassFrame:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
        tabPassFrame:SetScript("OnEvent", QueueTabPass)
    end
    -- Tab close: Blizzard resets all tab colors via FCFTab_UpdateColors
    -- but FCFDock_SelectWindow only fires if the ACTIVE tab was closed.
    -- Closing a non-active tab skips our color refresh. FCF_Close is a
    -- top-level user action, safe to hook (not inside a secure chain).
    if FCF_Close then
        hooksecurefunc("FCF_Close", function()
            C_Timer.After(0, function()
                UpdateTabColors()
                ECHAT.ApplyTabLayout()
            end)
        end)
    end
    -- Temp window creation: re-run SkinPass to catch new frames.
    -- NEVER hooksecurefunc("FCF_OpenTemporaryWindow") -- field-proven taint
    -- TWICE (pre-841 module history, and again in the 2026-07-21 tester
    -- taintlog): the secure whisper router calls it mid-function and then
    -- continues to DeactivateChat -> UpdateHeader, whose header width math
    -- runs on the SECRET whisper name geometry; with our hook in the chain
    -- the remainder of the caller executes tainted and the arithmetic is
    -- blocked. Instead, listen for the same whisper events on our own frame
    -- (standalone dispatch, outside Blizzard's) and defer the skin. This
    -- covers every temp-window trigger: incoming whisper, and outgoing
    -- /w-in-popout-mode (WHISPER_INFORM). A BACKGROUND open (window not
    -- selected) anchors the tab during the open itself, before this
    -- deferred pass installs the per-tab SetPoint hook -- SkinTab's
    -- one-shot anchor catch-up handles that missed first write.
    do
        local tempWinFrame = CreateFrame("Frame")
        tempWinFrame:RegisterEvent("CHAT_MSG_WHISPER")
        tempWinFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
        tempWinFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
        tempWinFrame:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
        tempWinFrame:SetScript("OnEvent", function()
            C_Timer.After(0, SkinPass)
            -- Recolor + layout (incl. the dynamic-tab seat normalize) after
            -- the skin lands; QueueTabPass coalesces with other triggers.
            C_Timer.After(0, QueueTabPass)
        end)
    end
    -- User-created permanent chat windows use a separate creation path from
    -- temporary whisper windows. Skin after Blizzard has assigned the frame,
    -- tab, ID, and dock state.
    if FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function()
            C_Timer.After(0, SkinPass)
            C_Timer.After(0.10, SkinPass)
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
            local dockH2 = GetTabHeight()
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
            ECHAT.ApplyTabLayout()
        end)
    end

    ---------------------------------------------------------------------------
    --  5. Tab color management
    --     Deferred update batches multiple tab changes into one pass.
    ---------------------------------------------------------------------------
    -- Blizzard performs additional dock sizing after the initial chat setup.
    -- Re-apply our text-derived widths across a few deferred passes so saved
    -- Inner Padding X is correct immediately, without requiring a tab click.
    local function ApplyInitialTabLayout()
        UpdateTabColors()
        ECHAT.ApplyTabLayout()
    end
    C_Timer.After(0, ApplyInitialTabLayout)
    C_Timer.After(0.10, ApplyInitialTabLayout)
    C_Timer.After(0.50, ApplyInitialTabLayout)
    local _tabColorTimer
    local function DeferredTabColorUpdate()
        if _tabColorTimer then return end
        _tabColorTimer = true
        C_Timer.After(0, function()
            _tabColorTimer = nil
            UpdateTabColors()
            ECHAT.ApplyTabLayout()
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
            if ECHAT.DB().idleFadeEnabled == false then return end
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
            CancelIdleFade()
            if not IsIdleApplicable() then return end
            local cfg = ECHAT.DB()
            if cfg.idleFadeEnabled ~= false then
                local delay = cfg.idleFadeDelay or 15
                idleTimer = C_Timer.NewTimer(delay, StartIdleFade)
            end
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

        -- Permanent docked frames only (1-10). Hooking a temp whisper edit box
        -- (11+) taints its execution context and poisons HistoryKeeper on
        -- BN_WHISPER. Temp windows do not exist at login, but a /reload with a
        -- conversation window open could expose them here, so gate it.
        for i = 1, 10 do
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
                ["none"]      = nil,
                ["airhorn"]   = _SOUNDS_DIR .. "AirHorn.ogg",
                ["banana"]    = _SOUNDS_DIR .. "BananaPeelSlip.ogg",
                ["bikehorn"]  = _SOUNDS_DIR .. "BikeHorn.ogg",
                ["bite"]      = _SOUNDS_DIR .. "Bite.ogg",
                ["boxing"]    = _SOUNDS_DIR .. "BoxingArenaSound.ogg",
                ["catmeow"]   = _SOUNDS_DIR .. "CatMeow.ogg",
                ["catmeow2"]  = _SOUNDS_DIR .. "CatMeow2.ogg",
                ["gunshot"]   = _SOUNDS_DIR .. "FrontalsGunshot.wav",
                ["glass"]     = _SOUNDS_DIR .. "Glass.mp3",
                ["kaching"]   = _SOUNDS_DIR .. "Kaching.ogg",
                ["phone"]     = _SOUNDS_DIR .. "Phone.ogg",
                ["robotblip"] = _SOUNDS_DIR .. "RobotBlip.ogg",
                ["sonar"]     = _SOUNDS_DIR .. "Sonar.ogg",
                ["siren"]     = _SOUNDS_DIR .. "WarningSiren.ogg",
                ["water"]     = _SOUNDS_DIR .. "WaterDrop.ogg",
                ["wilhelm"]   = _SOUNDS_DIR .. "Wilhelm.ogg",
            }
            local WHISPER_SOUND_NAMES = {
                ["none"]      = "None",
                ["airhorn"]   = "Air Horn",
                ["banana"]    = "Banana Peel Slip",
                ["bikehorn"]  = "Bike Horn",
                ["bite"]      = "Bite",
                ["boxing"]    = "Boxing Arena",
                ["catmeow"]   = "Cat Meow",
                ["catmeow2"]  = "Cat Meow 2",
                ["gunshot"]   = "Frontals Gunshot",
                ["glass"]     = "Glass",
                ["kaching"]   = "Kaching",
                ["phone"]     = "Phone",
                ["robotblip"] = "Robot Blip",
                ["sonar"]     = "Sonar",
                ["siren"]     = "Warning Siren",
                ["water"]     = "Water Drop",
                ["wilhelm"]   = "Wilhelm",
            }
            local WHISPER_SOUND_ORDER = {
                "none", "airhorn", "banana", "bikehorn", "bite", "boxing", "catmeow",
                "catmeow2", "gunshot", "glass", "kaching", "phone", "robotblip", "sonar",
                "siren", "water", "wilhelm",
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
        end
        local function OnChatLeave(cf)
            _hoverCount = max(0, _hoverCount - 1)
            UpdateHoverState()
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
                end)
                overlay:SetScript("OnLeave", function()
                    _hoverCount = max(0, _hoverCount - 1)
                    UpdateHoverState()
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
            if _sbd.durabilityBtn then _sbd.durabilityBtn:SetShown(_cfg.showDurability ~= false) end
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

    -- Profile-swap refresh: re-apply all chat visuals from the (already-swapped)
    -- DB. ECHAT.DB() reads the live profile dynamically, so re-running the Apply
    -- functions pulls the new profile's settings. ApplySidebarIcons() is
    -- deliberately NOT called here -- its full ClearAllPoints/SetPoint layout
    -- chain is taint-risky and is skipped at init too (see line ~2954); icon
    -- visibility is refreshed with the same minimal SetShown block init uses, and
    -- position/scale/free-move are covered by the Apply* calls below.
    _G._ECHAT_RefreshAll = function()
        ECHAT.ApplySidebarVisibility()
        ECHAT.ApplyBorders()
        do
            local _cfg = ECHAT.DB()
            local _cf1 = _G.ChatFrame1
            if _cfg and _cf1 then
                local _sbd = CFD(_cf1)
                if _sbd.scrollBtn then _sbd.scrollBtn:SetShown(_cfg.showScroll ~= false) end
                if _sbd.friendsBtn then _sbd.friendsBtn:SetShown(_cfg.showFriends ~= false) end
                if _sbd.durabilityBtn then _sbd.durabilityBtn:SetShown(_cfg.showDurability ~= false) end
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
        ECHAT.ApplyBackground()
        ECHAT.ApplyFonts()
        ECHAT.ApplyForceOnScreen()
        if ECHAT.RefreshVisibility then ECHAT.RefreshVisibility() end
    end

    ---------------------------------------------------------------------------
    --  9-12. Chat positioning: Blizzard / Edit Mode owns position+size.
    --        No reparenting, no hooks, no unlock registration.
    ---------------------------------------------------------------------------
    -- Clamp state follows the saved "Force Chat on Screen" preference (default off:
    -- chat may be dragged off-screen). Toggled from the Chat options panel.
    ECHAT.ApplyForceOnScreen()

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
