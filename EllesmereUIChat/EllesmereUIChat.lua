if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIChat.lua
--
--  Chat module root: panels, sidebar, fade/visibility, edit box skin, tabs.
--  Message DISPLAY is owned by our own engine (EllesmereUIChat_Engine.lua):
--  Blizzard's chat frames keep running as the secure formatting/data plane
--  (their visual children are parked in a hidden container), and every
--  formatted line is bridged into a ScrollingMessageFrame we own. Features:
--    - Dark unified background (chat + input as one panel)
--    - Tab restyling (custom fonts, colors, spacing, and borders)
--    - Blizzard chrome removal
--    - Timestamps (showTimestamps CVar, rides Blizzard's secure formatter)
--    - Thin EUI scrollbar on our message frames
--    - Copy Chat button + session history (own message store)
-------------------------------------------------------------------------------
local addonName, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[addonName] = ns  -- LOD options files read this module ns via the registry
local EUI = _G.EllesmereUI
if not EUI then return end

ns.ECHAT = ns.ECHAT or {}
local ECHAT = ns.ECHAT

-- The chat panel hangs off UIParent, placed numerically from the chat frame's rect
-- (PositionChatPanel) so nothing of ours sits in Blizzard's anchor chain. The
-- interaction follower (do-block after SyncChatFrameState) drives repositioning, armed
-- only while chat is interacted with -- NO recurring work at idle.

-- The tab strip is fully owned now (EllesmereUIChat_Tabs.lua): our buttons on
-- our own container, drawn from the same settings. The old in-place reskin of
-- Blizzard's tabs (host clip, per-tab host trios, seat normalizes) is gone.

-- Chat uses the same tuned Blizzard-border offsets as other rectangular EUI
-- panels. Without this registration the shared engine's lookup resolves to
-- zero, clipping the border texture into the panel.
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

-- Per-frame state lives here, never as properties on Blizzard's chat frame
-- tables (that taints them -> HistoryKeeper errors in protected instances).
local _cfd = {}
local function CFD(cf)
    local d = _cfd[cf]
    if not d then
        d = {}
        _cfd[cf] = d
    end
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
            timestampAll = false,
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
            tabOffsetX = 0,
            scrollButtonOnChat = false,
            tabBackgroundColor = { r=0.03, g=0.045, b=0.05, a=0.44 },
            tabBackgroundColorActive = { r=0.03, g=0.045, b=0.05, a=0.65 },
            activeUnderline = true,
            activeUnderlineColorMode = "accent",
            activeUnderlineColor = { r=0.05, g=0.82, b=0.61, a=1 },
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
            abbreviateChannels = true,  -- same key as live: saved settings carry over
            classColorNames = true,
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

-- Unified fade system: all alpha changes go through a target + lerp.
local _visChatVisible = true
-- Strength 100 is a true full hide: alpha 0 plus mouse passthrough
-- (SetChatMousePassthrough).
local function GetIdleFadeAlpha()
    local cfg = ECHAT.DB()
    local strength = min(cfg.idleFadeStrength or 40, 100)
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
-- Tab fade rides the strip: our tab buttons are children of our own strip
-- container, which _ApplyAlpha fades directly. The old constraints on
-- Blizzard's tabs still stand for anyone tempted to touch the HIDDEN strip:
-- NEVER write the six CHAT_FRAME_TAB_*_ALPHA globals (an addon-written global
-- taints, Blizzard reads those constants inside its dock-update/temp-window
-- chains, and the tainted execution hits secret whisper values -- no
-- timing/deferral fix exists) and never fight FCFTab_UpdateAlpha.

-- Tab strip height (the owned strip in EllesmereUIChat_Tabs.lua). Used by
-- "Extend Background Behind Tabs" to size the strip behind the tabs and shift
-- the sidebar icon chain up by the same amount.
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

-- Batch cursor check: read cursor position once per frame, test against the
-- cached raw coords instead of calling GetCursorPosition repeatedly.
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

-- Chat frame text size is Blizzard's per-frame setting (right-click tab ->
-- Font Size); the EUI profile mirrors the latest user-selected value.
local function GetFrameFontSize(id)
    if FCF_GetChatWindowInfo then
        local _, fontSize = FCF_GetChatWindowInfo(id)
        if fontSize and fontSize > 0 then return fontSize end
    end
    return 12
end

local function GetEditBoxHeight()
    return min(60, max(10, ECHAT.DB().editBoxHeight or 23))
end
local function GetEditBoxFont()
    local key = ECHAT.DB().editBoxFont
    if not key or key == "__chat" then return GetFont() end
    if key == "__global" then
        return (EUI.GetFontPath and EUI.GetFontPath("chat")) or STANDARD_TEXT_FONT
    end
    return (EUI.ResolveFontName and EUI.ResolveFontName(key)) or GetFont()
end
local function GetEditBoxFontSize(id)
    return ECHAT.DB().editBoxFontSize or GetFrameFontSize(id)
end
-- Tab font size is hardcoded to 11 (no getter).

-- Chat background texture catalogue: same set as the Unit Frames bar texture
-- dropdown (same shared media files), with SharedMedia statusbar textures
-- appended through the shared EllesmereUI helper.
ns.chatBgTextures, ns.chatBgTextureNames, ns.chatBgTextureOrder =
    EllesmereUI.BuildBarTextureTables(true)

-- Refresh from SharedMedia (idempotent; registers the late-registration
-- callback on first call, same as the other modules).
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

    -- "none" = solid color instead of a texture
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
            local bgTex = CFD(cf).bg:GetRegions()
            if bgTex then
                if texPath and bgTex.SetTexture then
                    bgTex:SetTexture(texPath)
                    bgTex:SetVertexColor(BG_R, BG_G, BG_B, BG_A)
                elseif bgTex.SetColorTexture then
                    -- Clear the texture-mode tint before returning to solid, or
                    -- the color double-tints through the vertex color.
                    if bgTex.SetVertexColor then bgTex:SetVertexColor(1, 1, 1, 1) end
                    bgTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
                end
            end
        end
    end
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

-- Mouseover sidebars only participate in panel geometry while visible; kept
-- separate from alpha so the border expands on hover and contracts only once
-- the fade-out has completed.
local _sidebarMouseoverLayoutVisible = false
local function SidebarParticipatesInLayout(cfg)
    local mode = cfg.sidebarVisibility or "always"
    return mode == "always"
        or (mode == "mouseover" and _sidebarMouseoverLayoutVisible)
end

-- Extend the chat background up behind the tab strip (and the sidebar by the same
-- amount) so the tabs sit on one continuous panel. Opt-in via cfg.extendBgBehindTabs
-- (default off, reload on toggle). Creates OUR OWN frames only -- never touches a
-- Blizzard tab or GeneralDockManager -- so it is taint free; strip height matches the
-- dock height for pixel alignment. The strip is ONE frame parented to UIParent (not a
-- chat frame), pinned to ChatFrame1's bg top: UIParent parenting keeps it visible when
-- switching docked tabs (a per-frame child would vanish with its hidden frame), and
-- BACKGROUND strata keeps it behind the tabs. It does not inherit a chat frame's alpha,
-- so _ApplyAlpha fades it directly.
function ECHAT.ApplyExtendedBackground()
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
        -- BACKGROUND strata (still above the 3D world) puts tabs in front;
        -- the strip never overlaps chat text or the sidebar.
        ext:SetFrameStrata("BACKGROUND")
        -- Level 1 leaves level 0 free for the panel border's "Show Behind"
        -- mode, whose outward half stays visible around the strip.
        ext:SetFrameLevel(1)
        if _chatAlphaCurrent then ext:SetAlpha(_chatAlphaCurrent) end
        ext:SetShown(extend)
    end

    -- Sidebar (ChatFrame1 only): matching strip plus a 1px divider so the
    -- sidebar/chat hairline runs full height. Can be the sidebar's own child
    -- (rendered behind icons via its own frame level) since the sidebar is
    -- always visible and fades on its own.
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
            and SidebarParticipatesInLayout(cfg)
            -- A separate sidebar is its own island: excluded here, wrapped
            -- by its own border below.
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
        -- Chat tabs/edit box can live on a higher strata than the chat frame,
        -- so a frame-level bump alone is not enough. "Show Behind" drops the
        -- border to the very back instead, so the chat fill covers its inward
        -- half and only the outward half frames the panel.
        local showBehind = cfg.panelBorderBehind == true
        border:SetFrameStrata(showBehind and "BACKGROUND" or "MEDIUM")
        -- Solid borders use a child at host+1; textured borders render at host
        -- level. Behind mode keeps both at 0, under the extended strip (level 1)
        -- and chat bg. Capped below 100: per-tab border hosts sit at level 100
        -- and must draw over the chat border.
        local borderLevel = showBehind and 0 or max(96, min(98, cf1:GetFrameLevel() + 20))
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

            -- Separate Sidebar: its own border, same style and construction class as
            -- the panel border (our UIParent frame anchored to our sidebar frame).
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
                    sbBorder:SetFrameStrata(showBehind and "BACKGROUND" or "MEDIUM")
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

-- Re-apply font to all chat text surfaces. Chat text size is Blizzard's
-- per-frame setting (right-click tab -> Font Size; we only set family +
-- outline). The Blizzard frames keep receiving the font too: the hosted
-- combat log renders through ChatFrame2, and their buffers should wrap
-- identically to ours for backfill copies.
function ECHAT.ApplyFonts()
    local font = GetFont()
    local editFont = GetEditBoxFont()
    local outline = GetOutlineFlag()
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.SetFont then
            local size = GetFrameFontSize(i)
            -- Same per-window font FAMILY as our display view (CJK members):
            -- the invisible Blizzard frame owns hyperlink hit-zones, so its
            -- glyph metrics must match ours on lines carrying CJK text.
            local fam = ECHAT.EngineFontFamily and ECHAT.EngineFontFamily(i, font, size, outline)
            if fam then
                cf:SetFontObject(fam)
            else
                cf:SetFont(font, size, outline)
            end
        end
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            local size = GetEditBoxFontSize(i)
            eb:SetFont(editFont, size, outline)
            if i <= 10 then
                if eb.header then eb.header:SetFont(editFont, size, outline) end
                if eb.headerSuffix then eb.headerSuffix:SetFont(editFont, size, outline) end
            end
        end
    end
    -- Our message frames (family/outline ours, size per window from Blizzard).
    if ECHAT.EngineApplyFonts then ECHAT.EngineApplyFonts() end
end

-- One size for every chat window (the options slider). Persistence rides
-- Blizzard's own per-window storage -- SetChatWindowSize is a plain C write.
-- The EUI profile mirrors the latest size selected either here or through a
-- chat tab's right-click menu, so the native menu choice survives reload.
-- NEVER route
-- this through FCF_SetChatWindowFontSize: the old in-place skin's size
-- control rippled through Blizzard's tab-resize/dock machinery measuring
-- secret label widths under our taint (the v7.15-era removal). Under the
-- engine, size only touches storage, SetFont, and OUR frames.
function ECHAT.ApplyChatFontSize(size)
    if type(size) ~= "number" or size <= 0 then return end
    for i = 1, 10 do
        if _G["ChatFrame" .. i] then SetChatWindowSize(i, size) end
    end
    -- Temp whisper frames carry no numbered storage; their live font is the
    -- state FCF_GetChatWindowInfo reads back, so set it directly.
    local frames = _G.CHAT_FRAMES
    if type(frames) == "table" then
        for i = 11, #frames do
            local cf = _G[frames[i]]
            if cf and cf.isTemporary and cf.inUse and cf.SetFont then
                local font, _, flags = cf:GetFont()
                if font then cf:SetFont(font, size, flags or "") end
            end
        end
    end
    ECHAT.ApplyFonts()
end

-- Profile-wide font size: cfg.chatFontSize (NO static default -- absence
-- means "not yet captured") is the source of truth; Blizzard's per-window
-- storage stays the delivery vehicle via ApplyChatFontSize, so the taint
-- posture is unchanged. Genesis: seeded from the FIRST character's live
-- size at the first settled sight (pixel-invisible on that character); every
-- later login re-asserts the profile value across windows. The interaction
-- follower mirrors native tab-menu changes because that menu writes the
-- frame font directly without emitting UPDATE_CHAT_WINDOWS.
function ECHAT.SyncChatFontSize()
    local cfg = ECHAT.DB()
    if not cfg then return end
    if cfg.chatFontSize == nil then
        local cf = _G.ChatFrame1
        if cf and cf.GetFont then
            local _, fh = cf:GetFont()
            if type(fh) == "number" and fh > 0 then
                cfg.chatFontSize = math.floor(fh + 0.5)
            end
        end
        return -- live sizes already match what was just captured
    end
    ECHAT.ApplyChatFontSize(cfg.chatFontSize)
end

-- Class-colored names in message BODIES only: the engine's display
-- transform colors group/raid member names found in the text of Say/Yell/
-- Party/Raid lines, on our display copy. SENDER prefixes are deliberately
-- untouched -- their class coloring is Blizzard default behavior and this
-- module never writes the per-type storage (SetChatColorNameByClass) in
-- either direction.
function ECHAT.ApplyClassColorNames(on)
    if ECHAT.EngineSetClassColorNames then
        ECHAT.EngineSetClassColorNames(on == true)
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
        _sidebarMouseoverLayoutVisible = false
        _sidebarFadeTarget = 0
        _sidebarFadeAlpha = 0
        sidebar:SetAlpha(0)
        sidebar:EnableMouse(false)
    elseif mode == "mouseover" then
        _sidebarMouseoverLayoutVisible = false
        _sidebarFadeTarget = 0
        _sidebarFadeAlpha = 0
        sidebar:SetAlpha(0)
        sidebar:EnableMouse(true)
    else
        _sidebarMouseoverLayoutVisible = true
        _sidebarFadeTarget = 1
        _sidebarFadeAlpha = 1
        sidebar:SetAlpha(1)
        sidebar:EnableMouse(true)
    end
    -- Separate-mode border mirrors the sidebar's alpha.
    if ns._sidebarSeparateBorder then
        ns._sidebarSeparateBorder:SetAlpha(_sidebarFadeAlpha)
    end

    -- Re-anchor the extended panel border as the sidebar enters/leaves layout.
    if ECHAT.ApplyTabPadding then
        ECHAT.ApplyTabPadding()
    elseif ECHAT.ApplyExtendedBackground then
        ECHAT.ApplyExtendedBackground()
    end

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
            if _sidebarFadeAlpha == _sidebarFadeTarget then
                self:Hide()
                if _sidebarFadeTarget == 0 and _sidebarMouseoverLayoutVisible then
                    _sidebarMouseoverLayoutVisible = false
                    if ECHAT.ApplyTabPadding then
                        ECHAT.ApplyTabPadding()
                    elseif ECHAT.ApplyExtendedBackground then
                        ECHAT.ApplyExtendedBackground()
                    end
                end
            end
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
            -- Input-on-top: the divider marks the overlaid input's edge, so it
            -- shares that input's shown state (ECHAT.ApplyInputTopStrip) --
            -- otherwise it cuts across a message once the strip is released.
            CFD(cf).inputDiv:SetShown(not hide
                and (not cfg.inputOnTop or ECHAT.InputTopStripActive(cf)))
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

-- Sidebar hints use the fully skinned GameTooltip when the BlizzardSkin
-- module's tooltip reskin is active; otherwise the lightweight EUI widget
-- tooltip, so Chat has no hard dependency on that module.
local function ShowSidebarIconTooltip(owner, label)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")
    local useGameTooltip = isLoaded
        and (not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false)
        and GameTooltip
    owner._euiSidebarUsesGameTooltip = useGameTooltip and true or false
    if useGameTooltip then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(EUI.L(label), 1, 1, 1)
        GameTooltip:Show()
    elseif EUI.ShowWidgetTooltip then
        EUI.ShowWidgetTooltip(owner, label)
    end
end

local function HideSidebarIconTooltip(owner)
    if owner and owner._euiSidebarUsesGameTooltip then
        GameTooltip:Hide()
        owner._euiSidebarUsesGameTooltip = false
    elseif EUI.HideWidgetTooltip then
        EUI.HideWidgetTooltip()
    end
end

-- Numeric placement of the chat panel background. NEVER anchor the panel to the chat
-- frame/edit box: that puts an insecure frame inside ChatFrame1's rect chain, so any
-- layout write of ours (SetPoint, SetShown, even Hide) dirties it, and Blizzard's next
-- temp-window dock resolves geometry THROUGH our anchors, runs tainted, and its
-- FCF_SetLocked write poisons ChatFrame.isLocked. Reading the rect is safe, anchoring
-- is not -- position numerically against UIParent instead.
--
-- The whole pass, reads included, is DEFERRED ONE FRAME: a fresh temp window skins
-- mid-open, and if our first SetPoint lands while the dock is still dirty, that
-- insecure write gets resolved inside Blizzard's own deferred dock pass and taints
-- its isLocked/dock-selected writes. Deferring one tick moves us outside that pass.
-- Do NOT "optimise" by testing the rect synchronously and deferring only writes:
-- GetLeft/Top/ Right/Bottom, GetEffectiveScale, and IsShown all force the layout
-- engine to RESOLVE the frame, which taints exactly like writing does. Dedupe caps
-- this to one queued placement per chat frame per frame; the closure is built once
-- and reused, so repeats cost only the timer.
function ECHAT.PositionChatPanel(cf)
    local d = CFD(cf)
    if d._posQueued then return end
    d._posQueued = true
    local fn = d._posDefer
    if not fn then
        fn = function()
            d._posQueued = nil
            ECHAT._PositionChatPanelNow(cf)
        end
        d._posDefer = fn
    end
    C_Timer.After(0, fn)
end

function ECHAT._PositionChatPanelNow(cf)
    local d = CFD(cf)
    local bg = d and d.bg
    if not bg then return end
    -- ChatFrame1's panel keeps tracking even while the frame is dock-hidden
    -- (a selected temp window hides it): the sidebar, the extended tab band,
    -- and the strip visuals all anchor to THIS panel, and skipping it while
    -- hidden strands them when chat is moved. Hidden frames keep live rects.
    if not cf:IsShown() and cf ~= _G.ChatFrame1 then return end
    local l, t, r, cb = cf:GetLeft(), cf:GetTop(), cf:GetRight(), cf:GetBottom()
    if not (l and t and r and cb) then
        -- Undock rescue: dragging a tab off the dock can end with Blizzard's
        -- StopMovingOrSizing clearing the frame's anchors and never baking the
        -- drop position back on (12.1). The point-less frame then crashes
        -- FCF_SavePositionAndDimensions every frame (GetLeft nil) and renders
        -- nowhere. A shown, undocked chat frame with zero points is only ever
        -- that broken state: re-anchor it at the cursor (the drop spot) so the
        -- next drag-stop iteration saves cleanly and the window stays where
        -- the user dropped it. Costs nothing when healthy -- this branch is
        -- the existing nil-rect early-out.
        if cf ~= _G.ChatFrame1 and not cf.isDocked and cf:IsShown()
            and cf:GetNumPoints() == 0 then
            local cx, cy = GetCursorPosition()
            local es = cf:GetEffectiveScale()
            local issec = _G.issecretvalue
            if cx and cy and es and es > 0
                and not (issec and (issec(cx) or issec(cy))) then
                pcall(function()
                    cf:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / es, cy / es)
                end)
            else
                pcall(function()
                    cf:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                end)
            end
        end
        return
    end
    -- Secret-gated like every other per-tick rect read (grip doctrine): a
    -- mid-drag or restricted-content rect must never reach the arithmetic
    -- below at follower cadence. A frame riding StartMoving's hardware
    -- capture reads secret for its whole drag (12.1), so instead of freezing
    -- the panel until the drop, follow by cursor delta from the last healthy
    -- corners -- no secret value is ever read, and the panel+text ride the
    -- drag like the Blizzard-owned art does.
    local issecret = _G.issecretvalue
    if issecret and (issecret(l) or issecret(t) or issecret(r) or issecret(cb)) then
        if _G.MOVING_CHATFRAME == cf and d._bgL then
            local mx, my = GetCursorPosition()
            if mx and my and not (issecret(mx) or issecret(my)) then
                local ui2 = UIParent:GetEffectiveScale()
                if ui2 and ui2 > 0 then
                    mx, my = mx / ui2, my / ui2
                    local base = d._dragCursorBase
                    if not base then
                        base = { x = mx, y = my,
                                 l = d._bgL, t = d._bgT, r = d._bgR, b = d._bgB }
                        d._dragCursorBase = base
                    end
                    local dx, dy = mx - base.x, my - base.y
                    d._bgL, d._bgT = base.l + dx, base.t + dy
                    d._bgR, d._bgB = base.r + dx, base.b + dy
                    bg:ClearAllPoints()
                    bg:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d._bgL, d._bgT)
                    bg:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", d._bgR, d._bgB)
                end
            end
        end
        return
    end
    d._dragCursorBase = nil
    -- Rest-rect cache (frame-local space) for the tab-drag ownership lane:
    -- the broken StartMoving capture scrambles the rect before any post-hook
    -- can read it, so drag-start grab offsets come from here instead.
    d._cfL, d._cfT = l, t
    d._cfWasDocked = cf.isDocked and true or nil
    -- Rects come back in each frame's own space; convert to UIParent's.
    local ui = UIParent:GetEffectiveScale()
    if not ui or ui == 0 then return end
    local cs = cf:GetEffectiveScale() / ui
    -- Insets from ApplyInputPosition (input above/below, its height); falls
    -- back to creation-time geometry before that has ever run.
    local ins = d._bgIns
    local il, ir, it, ib
    if ins then
        il, ir, it, ib = ins.l, ins.r, ins.t, ins.b
    else
        il, ir, it, ib = -10, 5, 3, -6
    end
    local left, top = (l * cs) + il, (t * cs) + it
    local right, bottom = (r * cs) + ir, (cb * cs) + ib
    if right - left < 1 or top - bottom < 1 then return end
    local pl, pt, pr, pb = d._bgL, d._bgT, d._bgR, d._bgB
    -- Write only when it moved: this runs every frame and a redundant SetPoint
    -- is still a layout write.
    if pl and math.abs(pl - left) < 0.05 and math.abs(pt - top) < 0.05
       and math.abs(pr - right) < 0.05 and math.abs(pb - bottom) < 0.05 then
        return
    end
    d._bgL, d._bgT, d._bgR, d._bgB = left, top, right, bottom
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    bg:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right, bottom)
end

-- Direct (no-timer) placement of every panel plus the dock manager. Callable
-- ONLY from OUR OWN execution (interaction follower's OnUpdate, deferred
-- event passes -- both timer-equivalent contexts). Skin-pass call sites keep
-- using the queued PositionChatPanel above.
function ECHAT.PositionChatPanelsNow()
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        -- Gate on the panel existing, NOT on _skinned: this function sits
        -- above that local, so referencing it here reads a nil GLOBAL.
        if cf and CFD(cf).bg then ECHAT._PositionChatPanelNow(cf) end
    end
    -- The owned tab strip is anchored to the panel and follows for free.
end

-- Panel hosting. Blizzard's house editor is a full-screen UI panel: it hides
-- UIParent and FCF_SetFullScreenFrame reparents the chat frames onto itself so
-- chat stays readable while decorating. That helper only moves widgets whose
-- parent is still UIParent, and our panel frames are UIParent children by design
-- (see the bg creation note), so they stay behind on the hidden UIParent and the
-- entire visible chat -- background, our message frames, tabs, sidebar -- goes
-- with them. Follow the chat frames onto whichever host Blizzard picked, and
-- back to UIParent when the editor closes. Every frame moved here is ours.
local _panelHost = UIParent
local function PanelHost()
    return FCF_GetCurrentFullScreenFrame and FCF_GetCurrentFullScreenFrame() or UIParent
end

local function ReseatPanel(f, host)
    if not f then return end
    local p = f:GetParent()
    if p ~= host and (p == UIParent or p == _panelHost) then
        FrameUtil.SetParentMaintainRenderLayering(f, host)
    end
end

function ECHAT.ApplyPanelHost()
    local host = PanelHost()
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf then
            local d = CFD(cf)
            ReseatPanel(d.bg, host)
            ReseatPanel(d.sidebar, host)
            -- Moves only while it is seated on the chat panel; on the sidebar
            -- seat it is a child of a frame this pass already moved.
            ReseatPanel(d.scrollBtn, host)
        end
    end
    ReseatPanel(ns._chatTabStrip, host)
    ReseatPanel(ns._chatBgExt, host)
    ReseatPanel(ns._chatPanelBorder, host)
    ReseatPanel(ns._sidebarSeparateBorder, host)
    ReseatPanel(ns._chatHoverOverlay, host)
    _panelHost = host
end

-- The on-demand popups are built the first time they are used and can be built
-- on either side of an editor session, so they seat themselves on show instead
-- of riding the pass above.
function ECHAT.HostPopup(f)
    local host = PanelHost()
    if f:GetParent() ~= host then
        FrameUtil.SetParentMaintainRenderLayering(f, host)
    end
end

-- The main window ships with clamp-rect insets that extend its clamp box
-- ~25-60px past every edge (phantom room reserved for the stock tab strip
-- and edit box). Our panel draws its own tabs and input INSIDE the window,
-- so the reservation only blocks corner placement: the screen clamp pins
-- the frame that far from every edge, which also silently eats unlock-mode
-- drags and arrow nudges toward a corner (the anchor moves, the resolved
-- rect stays pinned). Zero the insets so the clamp lands exactly at the
-- screen edges; clamped-to-screen itself stays on as the cannot-lose-the-
-- window safety net. Compare-gated (write-free when settled) because dock
-- passes can rewrite the insets; asserted from the state sync and the
-- position chokepoint.
local function EnsureChatClampInsets()
    local cf1 = _G.ChatFrame1
    if not (cf1 and cf1.GetClampRectInsets) then return end
    local l, r, t, b = cf1:GetClampRectInsets()
    if l ~= 0 or r ~= 0 or t ~= 0 or b ~= 0 then
        cf1:SetClampRectInsets(0, 0, 0, 0)
    end
end

-- State sync for what the panels lost by no longer being chat frame children,
-- plus two Blizzard buttons hidden by alpha: Blizzard fades ButtonFrame /
-- ScrollToBottomButton back in on hover (UIFrameFadeIn drives only their
-- alpha) and re-levels chat frames on dock passes. Runs from the interaction
-- follower and the deferred event passes. The stack-hidden gate keeps the
-- shown-follow from re-showing panels the full-hide put away.
function ECHAT.SyncChatFrameState()
    if ECHAT.SuppressChatEditModeSelection then ECHAT.SuppressChatEditModeSelection() end
    EnsureChatClampInsets()
    -- Size drift self-heal: Edit Mode's late layout passes can re-rect the
    -- main window through paths the ApplySystemAnchor guard never sees,
    -- leaving the frame on its stale explicit size while the panel still
    -- shows ours. Verify the saved size holds and re-assert on drift.
    -- Compare-gated (two reads when settled); suspended during the grip
    -- drag and unlock sessions, whose live geometry rules.
    local cfgSz = ECHAT.DB()
    local pos = cfgSz and cfgSz.chatPosition
    local sz = pos and cfgSz.chatSize
    if sz and sz.w and sz.h and not ns._chatSizingActive
        and not (_G.EllesmereUI and _G.EllesmereUI._unlockActive) then
        local cf1s = _G.ChatFrame1
        -- Armed only after the settled-sight apply (the anchor guard is
        -- installed there): position ownership must never begin early, or
        -- this heal re-rects chat mid-login while Blizzard's dock passes are
        -- still resolving (ghost tab strip built against half-resolved
        -- geometry = invisible tabs until the next pass).
        local d1 = cf1s and CFD(cf1s)
        if d1 and d1.anchorGuarded then
            local w = cf1s:GetWidth()
            local h = cf1s:GetHeight()
            local isec = _G.issecretvalue
            local drift = false
            if w and h and not (isec and (isec(w) or isec(h)))
                and (math.abs(w - sz.w) > 1.5 or math.abs(h - sz.h) > 1.5) then
                drift = true
            end
            -- Position drift too (canonical BOTTOMLEFT saves): Edit Mode's
            -- late writes move the rect as well as resizing it.
            if not drift and pos.point == "BOTTOMLEFT" and pos.x and pos.y then
                local l, b = cf1s:GetLeft(), cf1s:GetBottom()
                if l and b and not (isec and (isec(l) or isec(b)))
                    and (math.abs(l - pos.x) > 1.5 or math.abs(b - pos.y) > 1.5) then
                    drift = true
                end
            end
            if drift and ECHAT.ApplyChatPosition then ECHAT.ApplyChatPosition() end
        end
    end
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf then
            local shown = cf:IsShown()
            if shown then
                local bf = _G["ChatFrame" .. i .. "ButtonFrame"]
                if bf and bf:GetAlpha() ~= 0 then bf:SetAlpha(0) end
                local sb = cf.ScrollToBottomButton
                if sb and sb:GetAlpha() ~= 0 then sb:SetAlpha(0) end
            end
            local bg = CFD(cf).bg
            if bg and not ns._chatStackHidden then
                if bg:IsShown() ~= shown then bg:SetShown(shown) end
                if shown then
                    local lvl = max(0, cf:GetFrameLevel() - 1)
                    if bg:GetFrameLevel() ~= lvl then bg:SetFrameLevel(lvl) end
                    local st = cf:GetFrameStrata()
                    if bg:GetFrameStrata() ~= st then bg:SetFrameStrata(st) end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Interaction follower: the ONLY recurring driver in this module, HIDDEN
--  whenever chat is not being interacted with. A chat frame's rect / the
--  dock's state can only change via an event the deferred passes already
--  catch (login, dock config, scale, Edit Mode commits, whisper windows) or a
--  mouse/Edit Mode interaction on a widget we hook (tab/resize/sidebar hover,
--  Edit Mode show/hide). The follower arms on those edges, follows per-frame
--  while armed, then disarms to hidden -- zero recurring work or allocations
--  while idle. Accepted gap: a frame moved by another addon or a /run with no
--  event and no nearby mouse only heals on the next event/interaction.
-------------------------------------------------------------------------------
do
    local follower = CreateFrame("Frame")
    follower:Hide()
    local hoverCount = 0
    local lingerUntil = 0
    local editMode = false
    local unlockHold = false
    local accum = 0
    local lastSelected
    local lastShown = {}
    local lastFontSize = {}
    local lastDockCount

    -- Seed before the first interaction so a fast tab-menu change is still
    -- recognized as a change from the settled Blizzard value.
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.GetFont then
            local size = GetFrameFontSize(i)
            if size and size > 0 then lastFontSize[i] = size end
        end
    end

    follower:SetScript("OnUpdate", function(_, elapsed)
        -- Geometry every frame while armed: drags need per-frame follow.
        ECHAT.PositionChatPanelsNow()
        -- Dock membership, every frame (one table-length read): closing a
        -- NON-selected docked window flips nothing else we watch -- its
        -- frame was already hidden by the dock and selection stays put.
        if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then
            local n = #GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
            if n ~= lastDockCount then
                lastDockCount = n
                -- Ghosts correct SYNCHRONOUSLY: this tick is our own
                -- execution, after the click that changed the dock but
                -- before this frame renders. A queued pass would paint one
                -- frame of a ghost stretched on the dying tab.
                if ECHAT.TabsRefreshNow then ECHAT.TabsRefreshNow() end
                if ECHAT.QueueTabPass then ECHAT.QueueTabPass() end
            end
        end
        -- State compares are cheaper at a coarse cadence.
        accum = accum + elapsed
        if accum < 0.1 then return end
        accum = 0
        -- Edit Mode self-heal: OnHide is the normal disarm; this covers a missed
        -- one (reload inside Edit Mode etc.).
        if editMode and EditModeManagerFrame and not EditModeManagerFrame:IsShown() then
            editMode = false
        end
        -- Selected dock window changed (tab click, tab menu action).
        if GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow then
            local sel = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
            if sel ~= lastSelected then
                lastSelected = sel
                if ECHAT.QueueTabPass then ECHAT.QueueTabPass() end
            end
        end
        -- Blizzard's tab menu writes the frame font directly and does not emit
        -- UPDATE_CHAT_WINDOWS. Mirror the changed stored size into the EUI
        -- profile while this existing interaction-only watcher is armed, then
        -- refresh our visible copy from Blizzard's storage.
        for i = 1, 20 do
            local cf = _G["ChatFrame" .. i]
            if cf and cf.GetFont then
                local size = GetFrameFontSize(i)
                if size and size ~= lastFontSize[i] then
                    if lastFontSize[i] then
                        local cfg = ECHAT.DB()
                        if cfg and cfg.chatFontSize ~= size then
                            cfg.chatFontSize = size
                        end
                    end
                    if lastFontSize[i] and ECHAT.EngineApplyFontTo then
                        ECHAT.EngineApplyFontTo(cf)
                    end
                    lastFontSize[i] = size
                end
            end
        end
        -- A frame appeared or closed (tab menu close, window created).
        local shownChanged = false
        for i = 1, 20 do
            local cf = _G["ChatFrame" .. i]
            local shown = cf and cf:IsShown() or false
            if shown ~= lastShown[i] then
                lastShown[i] = shown
                shownChanged = true
            end
        end
        if shownChanged and ECHAT.QueueFullPass then ECHAT.QueueFullPass() end
        ECHAT.SyncChatFrameState()
        -- Disarm: nothing hovered, Edit Mode closed, linger expired, no open
        -- context menu. The linger covers quick menu clicks; the menu check
        -- covers long browses -- tab menu actions (close, rename, new window)
        -- land while the mouse has been in the menu far past the linger, and
        -- the shown/selection watches above must see their results.
        local menuOpen = Menu and Menu.GetManager and Menu.GetManager():IsAnyMenuOpen()
        if hoverCount == 0 and not editMode and not unlockHold and not menuOpen and GetTime() >= lingerUntil then
            ECHAT.PositionChatPanelsNow()
            follower:Hide()
        end
    end)

    -- Hover refcount from widget OnEnter/OnLeave hooks (tabs, resize buttons,
    -- sidebar). OnLeave fires when a hovered frame hides, so the count cannot
    -- leak across dock rebuilds.
    function ECHAT.FollowArm()
        hoverCount = hoverCount + 1
        follower:Show()
    end
    function ECHAT.FollowRelease()
        hoverCount = max(0, hoverCount - 1)
        if hoverCount == 0 then lingerUntil = GetTime() + 4 end
    end
    -- Edit Mode session: chat can be dragged/resized with the mouse far from
    -- any of our hover widgets (the Selection overlay occludes them).
    function ECHAT.FollowArmEditMode(on)
        editMode = on and true or false
        if editMode then follower:Show() end
    end
    -- Unlock-mode session hold: the Chat mover drags ChatFrame1 with the
    -- cursor over OUR mover proxy, not over any arming widget -- without
    -- this hold the panel and text freeze mid-drag until the next pass.
    -- Separate from the Edit Mode flag: its self-heal would clear a shared
    -- flag whenever the Edit Mode manager is closed (always, in unlock).
    function ECHAT.FollowArmUnlock(on)
        unlockHold = on and true or false
        if unlockHold then follower:Show() end
    end
end

-- Visibility ONLY: the SetShown half of ApplySidebarIcons, without its
-- ClearAllPoints/SetPoint chain. Re-anchoring here is taint-risky (also skipped at init
-- and in _ECHAT_RefreshAll): tab passes fire right after a whisper opens a temp window,
-- and re-anchoring then would land while Blizzard's dock pass is still resolving -- the
-- collision that poisons ChatFrame.isLocked. Fade only needs shown/hidden; re-anchoring
-- stays on paths that actually change the chain (icon order, spacing, free-move).
function ECHAT.ApplySidebarIconVisibility()
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    local sbd = cf1 and CFD(cf1)
    if not (cfg and sbd and sbd.sidebar) then return end
    local sbMode = cfg.sidebarVisibility or "always"
    local sbHidden = sbMode == "never"
        or (sbMode == "mouseover" and _sidebarFadeTarget == 0 and _sidebarFadeAlpha == 0)
        or ns._chatPassthrough == true
    local PAIRS = {
        { "showFriends", "friendsBtn", "friendsCount" },
        { "showGuild", "guildBtn", "guildCount" },
        { "showDurability", "durabilityBtn", "durabilityPct" },
        { "showCopy", "copyBtn" },
        { "showPortals", "portalBtn" },
        { "showVoice", "voiceBtn" },
        { "showSettings", "settingsBtn" },
    }
    for i = 1, #PAIRS do
        local key, btnKey, tailKey = PAIRS[i][1], PAIRS[i][2], PAIRS[i][3]
        local btn = sbd[btnKey]
        if btn then
            local shown = cfg[key] ~= false and not sbHidden
            if btn:IsShown() ~= shown then btn:SetShown(shown) end
            local tail = tailKey and sbd[tailKey]
            if tail and tail:IsShown() ~= shown then tail:SetShown(shown) end
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
    -- Shift the chain up by the tab-strip height when the background is extended
    -- and free-move is off. Matches the offset applied at icon creation.
    local iconTopShift = (cfg.extendBgBehindTabs and not cfg.freeMoveIcons) and GetTabAreaHeight() or 0
    local sbd = CFD(cf1)

    -- Re-anchor the chain in the creation-time order snapshot. Options-dropdown
    -- order edits intentionally do NOT apply live -- rebuilt on next reload.
    -- Icons never created (enabled after login) are skipped so the chain hangs
    -- off the last icon that actually exists.
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

    -- An alpha-0 sidebar still leaves child Buttons hoverable/clickable (motion is a
    -- separate channel from EnableMouse), so invisible icons must be HIDDEN: always in
    -- "never" mode, and in "mouseover" while fully faded out (shown children would eat
    -- the hover meant to reveal the sidebar). Both fade edges re-run this via
    -- ApplyTabPadding, so shown state tracks the fade with no extra wiring.
    local sbMode = cfg.sidebarVisibility or "always"
    local sbHidden = sbMode == "never"
        or (sbMode == "mouseover" and _sidebarFadeTarget == 0 and _sidebarFadeAlpha == 0)
        or ns._chatPassthrough == true

    local anchor = nil
    for _, key in ipairs(chainOrder) do
        local refs = CHAIN_REFS[key]
        local btn = refs and sbd[refs.btn]
        if btn then
            local shown = cfg[key] ~= false and not sbHidden
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
    showSettings   = "settingsBtn",
    showScroll     = "scrollBtn",
}

-- Canonical chain-icon keys and fallback order values. Explicit numbers in
-- cfg.sidebarIconOrder win; unlisted keys fall back here. Friends/Durability
-- sit below zero so profiles whose saved map only holds the four middle keys
-- still order Friends, Durability, then the middle group. Scroll is not part
-- of the chain -- it stays pinned at the sidebar bottom.
local SIDEBAR_CHAIN_KEYS = {
    "showFriends", "showGuild", "showDurability", "showCopy", "showPortals", "showVoice", "showSettings",
}
local SIDEBAR_FALLBACK_ORDER = {
    showFriends = -20, showGuild = -15, showDurability = -10,
    showCopy = 1, showPortals = 2, showVoice = 3, showSettings = 4,
}

-- Chain-icon keys sorted into the user's saved order. Used by the sidebar
-- creation pass (reload-time source of truth), by ApplySidebarIcons when no
-- creation snapshot exists, and by the options dropdown to list its rows.
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

-- Chat frame position: owned by EUI unlock mode when a saved position exists
-- (genesis-captured otherwise); enforcement is the ApplySystemAnchor guard.
local function ApplyChatPosition()
    -- A grip resize is an engine-driven op on ChatFrame1; the op re-anchors
    -- the frame, Edit Mode's machinery reacts with ApplySystemAnchor, and
    -- the guard below would then re-apply the SAVED anchors every tick --
    -- a revert war that freezes the resize. Held off until release.
    if ns._chatSizingActive then return end
    local cfg = ECHAT.DB()
    if not cfg or not cfg.chatPosition then return end
    local pos = cfg.chatPosition
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    -- Corner positions only resolve with the clamp insets zeroed; assert
    -- before anchoring so the enforcement itself can never land clamped.
    EnsureChatClampInsets()
    local px, py = pos.x, pos.y
    -- Saved size rides as a SECOND corner anchor: a two-point rect is
    -- anchor-determined, so no code path ever calls SetSize on ChatFrame1
    -- (a synchronous SetSize dispatch would run the dock relayout tainted),
    -- the engine layout pass dispatches its OnSizeChanged SECURE, and any
    -- Blizzard SetSize is overridden by the anchors.
    -- Second-corner enforcement serves only while the Edit Mode store
    -- disagrees with the saved size (pre-migration, fresh imports, declined
    -- reloads); once the store carries it, Blizzard's own apply owns the
    -- size and this stands down. Late-bound ns field: the EM helpers are
    -- defined below this function.
    local size = cfg.chatSize
    local sizeLane = size and size.w and size.h
        and (not ns._EMChatSizeDelta or ns._EMChatSizeDelta())
    local isCenterAnchor = (pos.point == "CENTER")
        and (pos.relPoint == "CENTER" or pos.relPoint == nil)
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa and px and py then
        local es = cf1:GetEffectiveScale()
        if isCenterAnchor and PPa.SnapCenterForDim then
            -- Snap against the dimensions the rect is about to carry: the
            -- composed lane below sizes it from the saved size, which the
            -- frame's explicit size (Edit Mode's last apply) can differ from.
            local dimW = sizeLane and size.w or (cf1:GetWidth() or 0)
            local dimH = sizeLane and size.h or (cf1:GetHeight() or 0)
            px = PPa.SnapCenterForDim(px, dimW, es)
            py = PPa.SnapCenterForDim(py, dimH, es)
        elseif PPa.SnapForES then
            px = PPa.SnapForES(px, es)
            py = PPa.SnapForES(py, es)
        end
    end
    if not pos.point or not (px and py) then return end
    cf1:ClearAllPoints()
    local composed = false
    if sizeLane and isCenterAnchor then
        -- CENTER-form saves (unlock mode Save & Exit) compose the rect around
        -- the centre outright. A lone CENTER anchor would resolve on the
        -- frame's explicit size for a tick, and the canonicalize below would
        -- read the corner of THAT rect -- landing the chat half the size delta
        -- away from where it was dropped.
        cf1:SetPoint("TOPLEFT", UIParent, "CENTER", px - size.w / 2, py + size.h / 2)
        cf1:SetPoint("BOTTOMRIGHT", UIParent, "CENTER", px + size.w / 2, py - size.h / 2)
        composed = true
    else
        cf1:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px or 0, py or 0)
    end
    if sizeLane then
        if pos.point == "BOTTOMLEFT" and (pos.relPoint or "BOTTOMLEFT") == "BOTTOMLEFT" then
            cf1:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT",
                (px or 0) + size.w, (py or 0) + size.h)
            composed = true
        elseif pos.point == "TOPLEFT" and (pos.relPoint or "TOPLEFT") == "TOPLEFT" then
            -- TOPLEFT-form positions compose the size anchor directly. A
            -- single-anchor apply would leave the rect on the frame's
            -- explicit (Edit Mode, stale) size until the deferred normalize
            -- below lands -- a window where a late Edit Mode pass baked the
            -- old size in.
            cf1:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT",
                (px or 0) + size.w, (py or 0) - size.h)
            composed = true
        end
        if not composed or pos.point ~= "BOTTOMLEFT" then
            -- Canonicalize foreign forms to BOTTOMLEFT once the rect
            -- resolves, so every later apply composes on the fast path.
            C_Timer.After(0, function()
                local cfg2 = ECHAT.DB()
                if not cfg2 or not cfg2.chatPosition or ns._chatSizingActive then return end
                local l, b = cf1:GetLeft(), cf1:GetBottom()
                local issecret = _G.issecretvalue
                if not (l and b) or (issecret and (issecret(l) or issecret(b))) then return end
                cfg2.chatPosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = l, y = b }
                ApplyChatPosition()
            end)
        end
    end
    -- The visible stack follows numerically; sync it now rather than at the
    -- next event so drags and guard re-applies land in one motion.
    if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
    -- The sync above reads the rect the SetPoints just changed, and same-tick
    -- reads can lag the engine layout pass (the grip-save rule) -- the panel,
    -- the tab band anchored to it, and the strip's clip then disagree for a
    -- tick (ghost tabs clipped to slivers). One coalesced deferred re-sync
    -- lands panels-then-strip on the resolved rect for EVERY apply path.
    if not ns._chatPosResync then
        ns._chatPosResync = true
        C_Timer.After(0, function()
            ns._chatPosResync = nil
            if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
            if ECHAT.TabsRefreshNow then ECHAT.TabsRefreshNow() end
        end)
    end
end
ECHAT.ApplyChatPosition = ApplyChatPosition

-------------------------------------------------------------------------------
--  Edit Mode size ownership. Blizzard's saved-dimensions restore skips the
--  main window ("controlled via edit mode"), so the EM layout is the native
--  store for ChatFrame1's size -- and every loading screen re-applies it.
--  Writing the user's size INTO the active layout makes that apply land the
--  RIGHT size (no default-size flash on load screens, no post-load heal),
--  after which the second-corner anchor enforcement in ApplyChatPosition
--  goes dormant (EMChatSizeDelta reads false). All access goes through the
--  C_EditMode data API only -- never EditModeManagerFrame methods (secure
--  manager chains) -- and only ever saves a blob that came out of
--  GetLayouts with integer setting edits, so a malformed save cannot be
--  constructed here. Field-confirmed shape: the blob carries user layouts
--  only, while activeLayout counts the two presets first (see the resolver
--  comment); preset-active users skip cleanly to the legacy anchor lane,
--  and any unexpected shape aborts the write the same way, exactly as
--  before this system.
-------------------------------------------------------------------------------
local function EMChatEnums()
    local sysEnum = Enum and Enum.EditModeSystem
    local setEnum = Enum and Enum.EditModeChatFrameSetting
    local layEnum = Enum and Enum.EditModeLayoutType
    if not (sysEnum and sysEnum.ChatFrame and setEnum
        and setEnum.WidthHundreds and setEnum.WidthTensAndOnes
        and setEnum.HeightHundreds and setEnum.HeightTensAndOnes
        and layEnum and layEnum.Preset ~= nil) then
        return nil
    end
    return sysEnum.ChatFrame, setEnum, layEnum
end

local function EMChatFindSystem(layout, sysChat)
    local systems = layout and layout.systems
    if type(systems) ~= "table" then return nil end
    for i = 1, #systems do
        local s = systems[i]
        if type(s) == "table" and s.system == sysChat then return s end
    end
end

local function EMChatSettingRow(sys, settingID)
    local st = sys and sys.settings
    if type(st) ~= "table" then return nil end
    for i = 1, #st do
        local row = st[i]
        if type(row) == "table" and row.setting == settingID then return row end
    end
end

-- Resolve the blob and the ACTIVE layout entry under the proof rule.
-- Returns blob, entry, sysChat, setEnum (nil on any unexpected shape).
local function EMChatResolve()
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then return nil end
    local sysChat, setEnum, layEnum = EMChatEnums()
    if not sysChat then return nil end
    -- Never touch the store while Blizzard's Edit Mode is live: the manager
    -- keeps its OWN session copy of layoutInfo and pushes it WHOLE on Save,
    -- so a write from here is either discarded by the next Save or discards
    -- the edit in progress.
    local emf = _G.EditModeManagerFrame
    if emf and (emf.editModeActive or (emf.IsShown and emf:IsShown())) then return nil end
    local ok, blob = pcall(C_EditMode.GetLayouts)
    if not ok or type(blob) ~= "table" or type(blob.layouts) ~= "table" then return nil end
    local active = blob.activeLayout
    if type(active) ~= "number" then return nil end
    -- SaveLayouts replaces the character's ENTIRE layout set and expects the
    -- shape Blizzard always passes it: PRESET layouts first, then the saved
    -- ones, with activeLayout indexing that merged list. GetLayouts returns
    -- only the saved half (field-dumped: 3 saved entries riding
    -- activeLayout 5), so the merged list is rebuilt here the way
    -- EditModeManagerFrame:UpdateLayoutInfo builds it; when the presets
    -- cannot be resolved this fails CLOSED rather than ever handing
    -- SaveLayouts the short list. Preset entries are read-only and are
    -- carried through untouched purely for index alignment.
    if not (EditModePresetLayoutManager
        and EditModePresetLayoutManager.GetCopyOfPresetLayouts) then return nil end
    local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    if type(presets) ~= "table" or #presets == 0 then return nil end
    local numPresets = #presets
    if tAppendAll then
        tAppendAll(presets, blob.layouts)
    else
        for i = 1, #blob.layouts do presets[numPresets + i] = blob.layouts[i] end
    end
    blob.layouts = presets
    -- A preset is active: read-only, nothing safe to write (the preset-copy
    -- flow stays the open follow-up; the legacy anchor lane serves).
    if active <= numPresets then return nil end
    local entry = blob.layouts[active]
    if type(entry) ~= "table" or entry.layoutType == layEnum.Preset then return nil end
    return blob, entry, sysChat, setEnum
end

-- Stored chat size of a layout entry (EM encodes each dimension as
-- hundreds + tens-and-ones setting pairs). nil when unreadable.
local function EMChatReadSize(entry, sysChat, setEnum)
    local sys = EMChatFindSystem(entry, sysChat)
    if not sys then return nil end
    local wH = EMChatSettingRow(sys, setEnum.WidthHundreds)
    local wT = EMChatSettingRow(sys, setEnum.WidthTensAndOnes)
    local hH = EMChatSettingRow(sys, setEnum.HeightHundreds)
    local hT = EMChatSettingRow(sys, setEnum.HeightTensAndOnes)
    if not (wH and wT and hH and hT
        and type(wH.value) == "number" and type(wT.value) == "number"
        and type(hH.value) == "number" and type(hT.value) == "number") then
        return nil
    end
    return wH.value * 100 + wT.value, hH.value * 100 + hT.value
end

-- True while the saved size still needs the legacy second-corner anchor:
-- cfg.chatSize exists and the EM store disagrees (or cannot be read). Once
-- the store carries the size, this reads false and enforcement stands down.
local function EMChatSizeDelta()
    local cfg = ECHAT.DB()
    local size = cfg and cfg.chatSize
    if not (size and size.w and size.h) then return false end
    -- Belt: after a store write this session, keep the anchor enforcement
    -- standing anyway. Field-tested that SaveLayouts coheres EM's cached
    -- tables immediately, so this should never matter -- it guards the
    -- untested edges (event timing on other clients) at the cost of one
    -- boolean.
    if ns._emChatWrote then return true end
    local blob, entry, sysChat, setEnum = EMChatResolve()
    if not blob then return true end
    local w, h = EMChatReadSize(entry, sysChat, setEnum)
    if not w then return true end
    return math.abs(w - size.w) > 1 or math.abs(h - size.h) > 1
end

-- Write w/h into the active layout (copying a preset to a new account
-- layout first when needed). Returns true only when the save landed.
local function EMChatWriteSize(w, h)
    if InCombatLockdown() then return false end
    local blob, entry, sysChat, setEnum = EMChatResolve()
    if not blob then return false end
    local sys = EMChatFindSystem(entry, sysChat)
    if not sys then return false end
    local wH = EMChatSettingRow(sys, setEnum.WidthHundreds)
    local wT = EMChatSettingRow(sys, setEnum.WidthTensAndOnes)
    local hH = EMChatSettingRow(sys, setEnum.HeightHundreds)
    local hT = EMChatSettingRow(sys, setEnum.HeightTensAndOnes)
    if not (wH and wT and hH and hT) then return false end
    w = math.max(0, math.floor(w + 0.5))
    h = math.max(0, math.floor(h + 0.5))
    wH.value = math.floor(w / 100)
    wT.value = w % 100
    hH.value = math.floor(h / 100)
    hT.value = h % 100
    local okSave = pcall(C_EditMode.SaveLayouts, blob)
    if not okSave then return false end
    ns._emChatWrote = true
    return true
end

-- Grip release and login migration both land here: write the store when it
-- disagrees. Fully silent -- field-tested that SaveLayouts coheres Edit
-- Mode's cached tables immediately (opening EM after an un-reloaded write
-- shows the new size and does not revert it), so no reload is needed and
-- no prompt exists. Quiet no-op for everyone whose store already agrees.
function ns.EMChatSyncSize()
    if InCombatLockdown() then return end
    local cfg = ECHAT.DB()
    local size = cfg and cfg.chatSize
    if not (size and size.w and size.h) then return end
    if not EMChatSizeDelta() then return end
    EMChatWriteSize(size.w, size.h)
end
ns._EMChatSizeDelta = EMChatSizeDelta

-- Edit Mode's layout apply (login server-data arrival, layout switches) can
-- re-rect the main window through paths the ApplySystemAnchor guard never
-- sees, taking the last word over the settled-sight apply -- the frame sits
-- at Edit Mode's rect while the panel stack holds ours until an interaction
-- re-arms enforcement. Its own event is the precise edge: re-assert there,
-- deferred out of Edit Mode's execution, gated on ownership having begun
-- (anchor guard installed) so it can never fire early.
do
    local emWatch = CreateFrame("Frame")
    emWatch:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    emWatch:SetScript("OnEvent", function()
        local cfg = ECHAT.DB()
        if not (cfg and cfg.chatPosition) then return end
        local cf1 = _G.ChatFrame1
        local d1 = cf1 and CFD(cf1)
        if not (d1 and d1.anchorGuarded) then return end
        C_Timer.After(0, function()
            if ns._chatSizingActive then return end
            if _G.EllesmereUI and _G.EllesmereUI._unlockActive then return end
            local c2 = ECHAT.DB()
            if c2 and c2.chatPosition then ApplyChatPosition() end
        end)
    end)
end

-- Genesis capture: on the first settled sight with no saved position,
-- ChatFrame1's current (Edit-Mode-placed) rect becomes OUR saved position.
-- Pixel-identical takeover -- users see no change on update; from then on
-- chat position is an EUI unlock element.
local function CaptureChatPositionGenesis()
    local cfg = ECHAT.DB()
    if not cfg then return end
    -- One-time ownership migration: positions saved before the Edit Mode
    -- era are stale (users repositioned via Edit Mode since; re-applying
    -- an ancient spot would visibly move their chat on update). Discard
    -- once so genesis captures the CURRENT placement.
    if cfg._chatPosOwnership ~= 1 then
        cfg._chatPosOwnership = 1
        cfg.chatPosition = nil
    end
    if cfg.chatPosition then return end
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    local left, bottom = cf1:GetLeft(), cf1:GetBottom()
    if not (left and bottom) then return end
    cfg.chatPosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = left, y = bottom }
end

-- Edit Mode override, the suite's action-bar anchor-guard pattern: post-hook
-- the system anchor apply, re-apply OURS deferred so no addon code runs
-- inside Edit Mode's secure chain. One hook covers the login layout apply,
-- layout switches, and Edit Mode exit. ChatFrame1 is NEVER reparented and
-- its SetPoint is NEVER hooked -- both are recorded failure classes (Edit
-- Mode's UpdateSystemAnchorInfo assumes a UIParent child; a reparented
-- chat came back with no anchors at all).
local function InstallChatAnchorGuard()
    local cf1 = _G.ChatFrame1
    if not cf1 or not cf1.ApplySystemAnchor then return end
    local d = CFD(cf1)
    if d.anchorGuarded then return end
    d.anchorGuarded = true
    hooksecurefunc(cf1, "ApplySystemAnchor", function()
        local cfg = ECHAT.DB()
        if cfg and cfg.chatPosition then
            C_Timer.After(0, ApplyChatPosition)
        end
    end)
end

-- Kill Edit Mode's selection overlay for chat: the unit-frame treatment
-- adapted. Their Blizzard frames die by hidden reparent; cf1 must stay
-- live, and Edit Mode still drives its Selection child -- so the Selection
-- goes alpha-0 and mouse-dead IN PLACE (never reparented: a region its
-- owner still writes must stay in its tree). Chat can be neither
-- highlighted nor dragged in Edit Mode; asserted from the state sync since
-- Edit Mode rewrites the overlay across its sessions.
-- Edit Mode's resize handle on the main window (EditModeResizeButton, a
-- Button child Edit Mode shows on enter and hides on exit) gets the same
-- in-place treatment: sizing belongs to our grip, and a live handle here
-- would write Edit Mode's size store behind the size lane's back.
local function SuppressEditModeChild(f)
    if not f then return end
    if f:GetAlpha() ~= 0 then f:SetAlpha(0) end
    if f.SetMouseClickEnabled then
        if f:IsMouseClickEnabled() then f:SetMouseClickEnabled(false) end
        if f:IsMouseMotionEnabled() then f:SetMouseMotionEnabled(false) end
    end
end
function ECHAT.SuppressChatEditModeSelection()
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    SuppressEditModeChild(cf1.Selection)
    SuppressEditModeChild(cf1.EditModeResizeButton)
end
ns._CaptureChatPositionGenesis = CaptureChatPositionGenesis
ns._InstallChatAnchorGuard = InstallChatAnchorGuard

-- Main chat size is applied as a second corner anchor inside
-- ApplyChatPosition (cfg.chatSize; anchor-determined rect, never SetSize).
-- Undocked windows stay Blizzard-sized. This stub remains for callers.
local function ApplyChatSize()
end
ECHAT.ApplyChatSize = ApplyChatSize

-- Main chat resize grip: our button, ANCHOR-driven sizing. Blizzard never
-- shows ChatFrame1's own resize button (Edit Mode owned main chat sizing,
-- and our position takeover suppressed Edit Mode), so this grip is the sole
-- resize surface. HARD CONSTRAINTS, both field-proven:
--   - Never SetSize ChatFrame1 in any form: its OnSizeChanged is wired to
--     FCFDock_OnPrimarySizeChanged, which writes dock.isDirty/leftTab AND
--     installs the dock OnUpdate script; a synchronous insecure dispatch
--     taints the dock slots the secure whisper temp-window chain reads
--     (the recorded UpdateHeader secret-rect detonation class).
--   - StartSizing is engine-VETOED on the Edit-Mode-managed main window
--     (probed: rect identical before/after with the op "running"); the
--     docked branch in Blizzard's ResizeButton XML is legacy-dead.
-- The lane that satisfies both: pin TOPLEFT and drive the BOTTOMRIGHT
-- corner anchor from the cursor. A two-point rect is anchor-determined;
-- the engine layout pass recomputes it and dispatches OnSizeChanged as a
-- fresh SECURE execution (Blizzard's own dock relayout defers its work one
-- frame for exactly this timing). Persistence: cfg.chatSize, applied as
-- the second corner anchor by ApplyChatPosition -- Blizzard's saved-
-- dimensions restore explicitly skips the main window.
local function BuildMainChatResizeGrip(cf)
    local d = CFD(cf)
    if d.resizeGrip or not d.bg then return end
    local grip = CreateFrame("Button", nil, d.bg)
    d.resizeGrip = grip
    grip:SetSize(18, 18)
    -- Anchored to the chat frame like the undocked buttons, so the icon
    -- hugs the true resize corner regardless of panel insets; nudged out
    -- past the frame edge so it sits in the panel's corner, not the text's.
    grip:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 4, -3)
    grip:SetFrameStrata("HIGH")
    local tex = grip:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png")
    tex:SetDesaturated(true)
    tex:SetVertexColor(1, 1, 1)
    grip:SetAlpha(0.4)

    -- Damage-meters drag mechanics, anchor-driven: per tick the TOPLEFT stays
    -- pinned and the BOTTOMRIGHT corner anchor follows the cursor (shift =
    -- axis lock, min sizes, screen-edge caps). The rect is anchor-determined,
    -- so the engine layout pass recomputes it and ChatFrame1's OnSizeChanged
    -- (the dock relayout) dispatches SECURE. StartSizing is NOT usable here
    -- (engine-vetoed on the Edit-Mode-managed main window; field-probed) and
    -- SetSize is BANNED (synchronous tainted dispatch). No InProtectedInstance
    -- gate: /euidev makes it return true and would dead-stop the grip; all
    -- rect reads below are secret-gated instead.
    local MIN_W, MIN_H = 220, 100
    local sizing = false
    local startX, startY, startW, startH, anchorLeft, anchorTop
    local curW, curH, axis, shiftWas
    local ticker = CreateFrame("Frame")
    ticker:Hide()
    ticker:SetScript("OnUpdate", function()
        if not sizing then return end
        local cx, cy = GetCursorPosition()
        local es = cf:GetEffectiveScale()
        local dx = cx / es - startX
        local dy = startY - cy / es
        local shiftDown = IsShiftKeyDown()
        local newW, newH
        if shiftDown then
            if not shiftWas then
                axis = (math.abs(dx) >= math.abs(dy)) and "w" or "h"
            end
            if axis == "w" then
                newW, newH = math.max(MIN_W, startW + dx), startH
            else
                newW, newH = startW, math.max(MIN_H, startH + dy)
            end
        else
            axis = nil
            newW = math.max(MIN_W, startW + dx)
            newH = math.max(MIN_H, startH + dy)
        end
        -- Cap so the frame can't extend past screen edges from the pinned corner.
        local screenR = UIParent:GetRight() or 0
        local screenB = UIParent:GetBottom() or 0
        if screenR - anchorLeft > MIN_W then newW = math.min(newW, screenR - anchorLeft) end
        if anchorTop - screenB > MIN_H then newH = math.min(newH, anchorTop - screenB) end
        curW, curH = newW, newH
        -- Full re-anchor per tick: a mid-drag Edit Mode anchor write would
        -- otherwise leave a third point and overconstrain the rect.
        cf:ClearAllPoints()
        cf:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchorLeft, anchorTop)
        cf:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", anchorLeft + newW, anchorTop - newH)
        shiftWas = shiftDown
        -- The visible stack is positioned numerically; sync per tick so the
        -- panels ride the drag with zero lag.
        if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
    end)

    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        -- Belt behind the combat hide: no drag may start in lockdown even
        -- if a hide edge races the click.
        if InCombatLockdown() then return end
        local issecret = _G.issecretvalue
        local left, top = cf:GetLeft(), cf:GetTop()
        local w, h = cf:GetWidth(), cf:GetHeight()
        if not (left and top and w and h) then return end
        if issecret and (issecret(left) or issecret(top)
            or issecret(w) or issecret(h)) then return end
        -- Hold the position enforcement for the whole drag: our per-tick
        -- corner anchors rule until release.
        ns._chatSizingActive = true
        cf:ClearAllPoints()
        cf:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        cf:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", left + w, top - h)
        anchorLeft, anchorTop = left, top
        local cx, cy = GetCursorPosition()
        local es = cf:GetEffectiveScale()
        startX, startY = cx / es, cy / es
        startW, startH = w, h
        curW, curH = w, h
        shiftWas = false
        sizing = true
        ticker:Show()
        -- Held for the whole drag: the cursor can slide off the grip mid-
        -- drag, and its OnLeave alone would disarm the geometry follower
        -- while the frame is still resizing.
        if ECHAT.FollowArm then ECHAT.FollowArm() end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not sizing then return end
        sizing = false
        ticker:Hide()
        ns._chatSizingActive = nil
        if ECHAT.FollowRelease then ECHAT.FollowRelease() end
        -- Save from the drag's own numbers (never frame reads: the rect
        -- resolves in the engine layout pass and can lag the final tick).
        -- Persistence is OUR DB key -- Blizzard's saved-dimensions restore
        -- explicitly skips the main window ("controlled via edit mode").
        local cfg = ECHAT.DB()
        if cfg and curW and curH then
            local w = math.floor(curW + 0.5)
            local h = math.floor(curH + 0.5)
            cfg.chatSize = { w = w, h = h }
            cfg.chatPosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
                x = anchorLeft, y = anchorTop - h }
        end
        if ECHAT.ApplyChatPosition then ECHAT.ApplyChatPosition() end
        if ECHAT.TabsRefreshNow then ECHAT.TabsRefreshNow() end
        -- Hand the size to the Edit Mode store (the native owner) and offer
        -- the finalizing reload; quiet no-op when the store already agrees.
        if ns.EMChatSyncSize then ns.EMChatSyncSize() end
    end)
    -- Lock toggled or panel hidden mid-drag: end the drag and release the
    -- position hold, or the guard would stay suspended forever.
    grip:SetScript("OnHide", function()
        if sizing then
            sizing = false
            ticker:Hide()
            ns._chatSizingActive = nil
            if ECHAT.FollowRelease then ECHAT.FollowRelease() end
        end
    end)
    -- Undocked-button hover parity; a resize drag starts and stays on this
    -- grip, so the geometry follower arms while the mouse is here and the
    -- panels ride the drag live.
    grip:SetScript("OnEnter", function(self)
        self:SetAlpha(0.75)
        if ECHAT.FollowArm then ECHAT.FollowArm() end
    end)
    grip:SetScript("OnLeave", function(self)
        self:SetAlpha(0.4)
        if ECHAT.FollowRelease then ECHAT.FollowRelease() end
    end)
    -- Combat gate: resizing is disabled in combat, matching Edit Mode's own
    -- posture. Both edges recompute through the lock applier (the single
    -- shown-state authority), so the combat hide can never fight the lock
    -- setting; built once with the grip (idempotency guard above).
    local combatGate = CreateFrame("Frame")
    combatGate:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatGate:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatGate:SetScript("OnEvent", function()
        if ECHAT.ApplyLockChatSize then ECHAT.ApplyLockChatSize() end
    end)
end
ns._BuildMainChatResizeGrip = BuildMainChatResizeGrip

-- Unlock-mode placements of ChatFrame1 (the Chat mover's drag start, every
-- drag tick, arrow/cog nudges) collapse it to ONE anchor point: the mover
-- treats every element as explicitly sized. The main window's size rides a
-- second corner anchor instead (SetSize on ChatFrame1 is banned -- see the
-- grip above), so a one-point frame falls back to its explicit size, which
-- is whatever Edit Mode's last apply set, not ours. Called from the
-- element's onLiveMove after each placement: re-add the opposite corner
-- from the anchor DEFINITION (GetPoint returns the SetPoint arguments, never
-- a lagging rect) so the frame keeps its size through the whole session.
-- Idempotent -- a frame already carrying two points is left alone.
local function KeepMainChatSizeCorner()
    local cfg = ECHAT.DB()
    local size = cfg and cfg.chatSize
    if not (size and size.w and size.h) then return end
    local cf1 = _G.ChatFrame1
    if not cf1 or cf1:GetNumPoints() ~= 1 then return end
    local point, rel, relPoint, x, y = cf1:GetPoint(1)
    if rel ~= UIParent then return end
    local issecret = _G.issecretvalue
    if issecret and (issecret(x) or issecret(y)) then return end
    if type(x) ~= "number" or type(y) ~= "number" then return end
    relPoint = relPoint or point
    local w, h = size.w, size.h
    if point == "TOPLEFT" then
        cf1:SetPoint("BOTTOMRIGHT", UIParent, relPoint, x + w, y - h)
    elseif point == "BOTTOMLEFT" then
        cf1:SetPoint("TOPRIGHT", UIParent, relPoint, x + w, y + h)
    elseif point == "TOPRIGHT" then
        cf1:SetPoint("BOTTOMLEFT", UIParent, relPoint, x - w, y + h)
    elseif point == "BOTTOMRIGHT" then
        cf1:SetPoint("TOPLEFT", UIParent, relPoint, x - w, y - h)
    elseif point == "CENTER" then
        cf1:ClearAllPoints()
        cf1:SetPoint("TOPLEFT", UIParent, relPoint, x - w / 2, y + h / 2)
        cf1:SetPoint("BOTTOMRIGHT", UIParent, relPoint, x + w / 2, y - h / 2)
    end
end
ns._KeepMainChatSizeCorner = KeepMainChatSizeCorner

-- Lock Main Chat Size: hides OUR grip (main chat's sole resize surface).
-- Blizzard's ChatFrame1ResizeButton stays permanently dead -- alpha + mouse
-- only, never isLocked/FCF_SetLocked (the dock-list/isLocked poison class).
function ECHAT.ApplyLockChatSize()
    local cfg = ECHAT.DB()
    local locked = cfg and cfg.lockChatSize == true
    local btn = _G.ChatFrame1ResizeButton
    if btn then
        btn:SetAlpha(0)
        btn:EnableMouse(false)
    end
    local cf1 = _G.ChatFrame1
    local grip = cf1 and CFD(cf1).resizeGrip
    if grip then
        -- Hidden in combat too: Edit Mode itself is combat-disabled, and a
        -- mid-combat resize could hit protected chat frames (the whisper-
        -- window lockdown class). The grip's OnHide ends any drag that was
        -- live when combat started; the regen listener in the grip build
        -- recomputes this on both combat edges.
        grip:SetShown(not locked and not InCombatLockdown())
    end
end

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
    if cfg.sidebarRight then
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

    -- _freeMoveH mirrors each icon's height from these constants so
    -- TopYFromSidebarTop never calls GetHeight() -- a geometry resolve that
    -- can taint the Edit-Mode ChatFrame1. Our own frames, so writing is safe.
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

    -- Hearthstone column: 3 icons stacked vertically as a 5th column on the
    -- right side, separated by a thin vertical divider.
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
                self._castHL:Show()
            end
        end)

        _hearthBtns[i] = btn
    end


    -- Swipe-only refresh (SPELL_UPDATE_COOLDOWN); never re-resolves toys.
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

    -- Full resolve (random toy, icon/macro/attributes). Show only, never on
    -- cooldown events; attribute writes are combat-illegal, hence the gate.
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

    -- Events live only while shown: cooldown + cast highlight refresh.
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
            -- Cast end clears hearthstone highlights
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
    if not ECHAT.DB().inputOnTop then return false end
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
        d.inputDiv:SetShown(not cfg.hideBorders and (not cfg.inputOnTop or active))
    end
    if changed and ECHAT.EngineLayoutWindow then ECHAT.EngineLayoutWindow(cf) end
end

-- Flip edit box between bottom (default) and top of chat panel
function ECHAT.ApplyInputPosition()
    local cfg = ECHAT.DB()
    local onTop = cfg.inputOnTop
    local inputHeight = GetEditBoxHeight()

    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and CFD(cf).bg then
            local name = cf:GetName()
            if not name then break end
            local eb = _G[name .. "EditBox"]
            local bg = CFD(cf).bg
            local div = CFD(cf).inputDiv

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

        end
    end
    -- Our message frames derive their text area from the recorded insets.
    if ECHAT.EngineLayoutWindows then ECHAT.EngineLayoutWindows() end
end

function ECHAT.ApplySidebarWidth()
    local cf1 = _G.ChatFrame1
    local sidebar = cf1 and CFD(cf1).sidebar
    if not sidebar then return end
    sidebar:SetWidth(min(100, max(30, ECHAT.DB().sidebarWidth or 40)))
    if ECHAT.ApplySidebarPosition then ECHAT.ApplySidebarPosition() end
end

-- Frame cache for _ApplyAlpha, so the fade loop does no repeated _G lookups.
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
    local cf1 = _G.ChatFrame1
    _alphaFrames._sidebar = cf1 and CFD(cf1).sidebar
    local cfg = ECHAT.DB()
    _alphaFrames._sidebarMode = cfg and cfg.sidebarVisibility or "always"
    -- A chat-anchored scroll button does not inherit the sidebar alpha.
    if cfg and cfg.scrollButtonOnChat and cf1 then
        _alphaFrames._chatScrollBtn = CFD(cf1).scrollBtn
    end
end


-- Full-hide mouse passthrough. At effective alpha 0 every mouse surface over the panel
-- is released so clicks and camera drags reach the world. Two regimes: idle fade at
-- strength 100 keeps frames shown (a fade must render) and disables both mouse channels
-- on chat frames 1-10 plus their edit boxes, scroll bars, static tabs,
-- FontStringContainers and line-pool children (temp windows/dynamic tabs untouched),
-- plus our grips/sidebar/overlay -- hover- wake comes from the geometric poll below.
-- Visibility-hidden (never/combat rules) also Hide()s the stack via SetChatStackShown,
-- the only state the engine cannot route input to. Original states are captured in the
-- CFD side table and restored exactly the moment any fade-in begins (new message,
-- Enter, visibility change).
local _chatPassthrough = false

-- Capture-then-disable / exact-restore for BOTH mouse channels: clicks (EnableMouse)
-- and motion (EnableMouseMotion -- blocks camera right-drag). States live in the CFD
-- side table under `key` and `key .. "M"`, so we only ever re-enable what we ourselves
-- disabled. Channels are read/written SEPARATELY: EnableMouse/IsMouseEnabled are
-- COMBINED-channel APIs, chat widgets run split states (click-only line frames,
-- motion-only containers), and a combined restore flips the wrong channel -- e.g.
-- re-arming clicks on a natively motion-only frame after one passthrough cycle.
local function GetMouseChannels(f)
    local click
    if f.IsMouseClickEnabled then click = f:IsMouseClickEnabled()
    else click = f:IsMouseEnabled() end
    if issecretvalue and issecretvalue(click) then click = false end
    local motion = f.IsMouseMotionEnabled and f:IsMouseMotionEnabled()
    if issecretvalue and issecretvalue(motion) then motion = false end
    return click and true or false, motion and true or false
end
-- Forward declaration: the write helpers below arm it when a lockdown-
-- blocked write is skipped; defined after SetChatStackShown.
local ArmChatPMRegen

-- Delta-gated and lockdown-contained. Reads first and writes only real
-- changes, so the assert-every-sweep passes cost no protected calls while
-- the state already matches (a REAL drift -- Blizzard re-arming click on
-- its widgets -- is still a delta and still writes). Chat frames turn
-- PROTECTED while a temporary whisper window exists, and a blocked mouse
-- write used to throw out of the middle of a passthrough transition,
-- stranding the state machine half-engaged (field: chat frozen / tabs dead
-- after combat with Out of Combat visibility). Protection is not reliably
-- queryable up front, so under lockdown each remaining write runs through
-- pcall -- the refusal itself is the detection -- and the function returns
-- false so the caller arms the regen re-apply. Out of combat every write
-- is direct, exactly as before.
local function SetMouseChannels(f, click, motion)
    click = click and true or false
    motion = motion and true or false
    local curClick, curMotion = GetMouseChannels(f)
    local ok = true
    if curClick ~= click then
        local fn = f.SetMouseClickEnabled or f.EnableMouse
        if InCombatLockdown() then
            if not pcall(fn, f, click) then ok = false end
        else
            fn(f, click)
        end
    end
    if curMotion ~= motion then
        local fn = f.SetMouseMotionEnabled or f.EnableMouseMotion
        if fn then
            if InCombatLockdown() then
                if not pcall(fn, f, motion) then ok = false end
            else
                fn(f, motion)
            end
        end
    end
    return ok
end

local function PMOff(d, key, f)
    if not f then return end
    -- Capture on first sight only, but ASSERT the disable every sweep:
    -- Blizzard's message pipeline re-enables click on chat widgets while we
    -- are engaged, and a skipped re-disable leaves an invisible click zombie.
    if d[key] == nil then
        local click, motion = GetMouseChannels(f)
        d[key] = click
        d[key .. "M"] = motion
    end
    if not SetMouseChannels(f, false, false) then ArmChatPMRegen() end
end
local function PMOn(d, key, f)
    if f and d[key] ~= nil then
        if not SetMouseChannels(f, d[key], d[key .. "M"]) then
            -- Keep the capture: the regen re-apply restores from it.
            ArmChatPMRegen()
            return
        end
    end
    d[key] = nil
    d[key .. "M"] = nil
end

-- The SMF's per-line hit-test frames are children of FontStringContainer
-- (Blizzard's line pool) and each carries its own mouse state, so toggling
-- the container alone does not release them. ONE bounded generation -- direct
-- children only, NEVER recursive -- with per-child state captured on first
-- sight in a weak side store and restored exactly from it.
local function PMOffChildren(d, key, parent)
    if not parent then return end
    local store = d[key]
    if not store then store = setmetatable({}, { __mode = "k" }); d[key] = store end
    local kids = { parent:GetChildren() }
    for i = 1, #kids do
        local c = kids[i]
        -- Capture first sight only; assert the disable every sweep -- the SMF
        -- re-enables click on its line frames as messages render, and these
        -- shape the dead zone.
        if not store[c] then
            local click, motion = GetMouseChannels(c)
            store[c] = { click, motion }
        end
        if not SetMouseChannels(c, false, false) then ArmChatPMRegen() end
    end
end
local function PMOnChildren(d, key, parent)
    local store = d[key]
    if not store or not parent then return end
    local kids = { parent:GetChildren() }
    for i = 1, #kids do
        local c = kids[i]
        local st = store[c]
        if st then
            if SetMouseChannels(c, st[1], st[2]) then
                store[c] = nil
            else
                -- Keep the capture for the regen re-apply.
                ArmChatPMRegen()
            end
        end
    end
end

-- Frame-level portion of the full-hide passthrough. OUR message frames are
-- simply hidden for the duration (a hidden frame cannot receive input); the
-- live Blizzard mouse surfaces over the panel -- the edit boxes, the skinned
-- permanent tabs, the dock overflow button, the invisible hyperlink
-- hit-zones in each FontStringContainer, and the chat frame itself -- get
-- the capture-exact PMOff/PMOn treatment.
local function PassthroughFrames(on)
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        local d = cf and CFD(cf)
        if d and d.bg then
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if on then
                PMOff(d, "pmCf", cf)
                -- FontStringContainer is a separate mouse surface (hyperlink
                -- hit-testing) not covered by the chat frame's own state; its
                -- line-pool children each carry their own too.
                PMOff(d, "pmFsc", cf.FontStringContainer)
                PMOffChildren(d, "pmFscKids", cf.FontStringContainer)
                PMOff(d, "pmEb", eb)
                PMOff(d, "pmGrip", d.resizeGrip)
            else
                PMOn(d, "pmCf", cf)
                PMOn(d, "pmFsc", cf.FontStringContainer)
                PMOnChildren(d, "pmFscKids", cf.FontStringContainer)
                PMOn(d, "pmEb", eb)
                PMOn(d, "pmGrip", d.resizeGrip)
            end
        end
    end
    -- Blizzard's tabs and dock overflow are hidden wholesale now (owned tab
    -- strip); hidden frames cannot receive input, so no mouse work for them.
    -- Our own surfaces hide outright while passthrough is engaged.
    if ECHAT.EngineSetPassthrough then ECHAT.EngineSetPassthrough(on) end
    if ECHAT.TabsSetPassthrough then ECHAT.TabsSetPassthrough(on) end
end

-- Hover-wake while fully hidden: a passthrough panel cannot receive mouse
-- events, so mouseover reveal at fade strength 100 needs a geometric poll --
-- IsMouseOver() is a pure rect test needing no mouse state. Runs ONLY while
-- idle-fade passthrough is engaged (never for the "never" hard hide, never
-- while visible): one rect test 5x/sec, cancelled the moment chat reveals.
local _ptWakeTicker
local function StopPTWake()
    if _ptWakeTicker then _ptWakeTicker:Cancel(); _ptWakeTicker = nil end
end
local function StartPTWake()
    StopPTWake()
    _ptWakeTicker = C_Timer.NewTicker(0.2, function()
        if not _chatPassthrough or not _idleFadeActive or not _visChatVisible then
            StopPTWake()
            return
        end
        local ov = ns._chatHoverOverlay
        if ov and ov:IsMouseOver() then
            StopPTWake()
            if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
        end
    end)
end

-- Hard-hidden visibility states (visibility "never", combat-only modes while
-- out of combat) hide the chat stack OUTRIGHT. Blizzard's chat frames are
-- never touched here: their shown state belongs to FCF (OnShow/OnHide write
-- SetChatWindowShown into config storage), and their visuals are parked in
-- the engine's hidden container regardless. What hides is OUR stack: the
-- panels (our message frames and scrollbars are their children), the dock
-- manager (single remember; nothing of Blizzard's re-shows it), and the
-- module chrome. Shown-state is captured per frame and restored exactly on
-- reveal. Idle fade still uses alpha (a fade must render); this applies only
-- when visibility says hidden.
local _chromeWasShown = setmetatable({}, { __mode = "k" })
local _chromeList = {}

local function SetChatStackShown(shown)
    -- Gate for SyncChatFrameState: the panels' shown-follow must not undo
    -- this hide (the Blizzard frames stay shown, so the follow would).
    ns._chatStackHidden = not shown
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        local d = cf and CFD(cf)
        if d and d.bg then
            if not shown then
                if d.bg:IsShown() then d.pmWasShown = true; d.bg:Hide() end
            elseif d.pmWasShown then
                d.pmWasShown = nil
                d.bg:Show()
            end
        end
    end
    local gdm = _G.GeneralDockManager
    if gdm then
        -- Show/Hide of an ancestor of a PROTECTED child (a docked temporary
        -- whisper tab in lockdown) is blocked: contain the write and let the
        -- regen re-apply land it. The remember records only what actually
        -- happened.
        if not shown then
            if gdm:IsShown() then
                if not InCombatLockdown() then
                    ns._gdmWasShown = true
                    gdm:Hide()
                elseif pcall(gdm.Hide, gdm) then
                    ns._gdmWasShown = true
                else
                    ArmChatPMRegen()
                end
            end
        elseif ns._gdmWasShown then
            if not InCombatLockdown() then
                ns._gdmWasShown = nil
                gdm:Show()
            elseif pcall(gdm.Show, gdm) then
                ns._gdmWasShown = nil
            else
                ArmChatPMRegen()
            end
        end
    end
    -- Our own chrome hides outright too; the per-frame remember preserves each
    -- applier's shown/hidden decision for the reveal.
    local cf1 = _G.ChatFrame1
    _chromeList[1] = ns._chatPanelBorder
    _chromeList[2] = ns._sidebarSeparateBorder
    _chromeList[3] = ns._chatBgExt
    _chromeList[4] = ns._chatTabStrip
    _chromeList[5] = ns._chatHoverOverlay
    _chromeList[6] = cf1 and CFD(cf1).sidebar or nil
    for i = 1, 6 do
        local f = _chromeList[i]
        if f then
            if not shown then
                if f:IsShown() then _chromeWasShown[f] = true; f:Hide() end
            elseif _chromeWasShown[f] then
                _chromeWasShown[f] = nil
                f:Show()
            end
        end
        _chromeList[i] = nil
    end
end

-- One-shot regen re-apply for lockdown-blocked writes. Re-asserts the
-- CURRENT intended passthrough state whole; the delta gate makes the pass
-- idempotent (everything that already landed is skipped, only the refused
-- writes replay). Fires before the visibility dispatcher's deferred
-- refresh, so a post-combat reveal starts from a clean slate. The event is
-- registered only while armed: zero idle cost.
local _chatPMRegenFrame
ArmChatPMRegen = function()
    if not _chatPMRegenFrame then
        _chatPMRegenFrame = CreateFrame("Frame")
        _chatPMRegenFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            PassthroughFrames(_chatPassthrough)
            if _chatPassthrough and not _visChatVisible then
                SetChatStackShown(false)
            end
        end)
    end
    _chatPMRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function SetChatMousePassthrough(on)
    if _chatPassthrough == on then return end
    _chatPassthrough = on
    ns._chatPassthrough = on
    -- Reveal BEFORE the restore pass: TabsSweepBlizzard (run by the tab
    -- restore inside PassthroughFrames) derives its click state from
    -- ns._chatPassthrough OR ns._chatStackHidden. With the stack still
    -- remembered hidden, the restore sweep re-disables the very tabs it is
    -- meant to re-enable, and nothing later re-runs it (field: tabs dead
    -- after combat with in-combat hide once the engage completes cleanly).
    -- The engage direction keeps the reverse order: sweep first (its
    -- passthrough flag alone forces click-off), stack-hide after.
    if not on then SetChatStackShown(true) end
    PassthroughFrames(on)
    if on then
        if not _visChatVisible then SetChatStackShown(false) end
        local cf1 = _G.ChatFrame1
        local sb = cf1 and CFD(cf1).sidebar
        if sb then
            sb:EnableMouse(false)
            if sb.EnableMouseMotion then sb:EnableMouseMotion(false) end
        end
        if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
        -- _visChatVisible excludes the visibility-hidden regimes, where
        -- hover-wake must not exist.
        if _idleFadeActive and _visChatVisible
            and ECHAT.DB().idleFadeEnabled ~= false then
            StartPTWake()
        end
    else
        StopPTWake()
        -- Our sidebar always runs with motion on (hover fade/reveal); the
        -- mode-specific click state is re-derived by ApplySidebarVisibility.
        local cf1 = _G.ChatFrame1
        local sb = cf1 and CFD(cf1).sidebar
        if sb and sb.EnableMouseMotion then sb:EnableMouseMotion(true) end
        if ECHAT.ApplySidebarVisibility then ECHAT.ApplySidebarVisibility() end
    end
    if ECHAT.ApplyIdleFadeHoverMotion then ECHAT.ApplyIdleFadeHoverMotion() end
end

-- Late joiners while engaged: a frame skinned or integrated during a
-- full-hide (temp whisper window opening mid-hide) must join the passthrough
-- set. One deferred catch-up covers it; nothing re-arms already-treated
-- widgets, so no recurring sweeps exist.
local _ptSweepQueued = false
local function RequestPassthroughSweep()
    if not _chatPassthrough or _ptSweepQueued then return end
    _ptSweepQueued = true
    C_Timer.After(0, function()
        _ptSweepQueued = false
        if not _chatPassthrough then return end
        PassthroughFrames(true)
        if not _visChatVisible then SetChatStackShown(false) end
    end)
end

local function _ApplyAlpha(alpha)
    _chatAlphaCurrent = alpha
    SetChatMousePassthrough(alpha <= 0)
    if not _alphaFrames then _BuildAlphaCache() end
    -- Our tab strip (UIParent-parented) fades directly; its buttons inherit.
    if ns._chatTabStrip then ns._chatTabStrip:SetAlpha(alpha) end
    for i = 1, #_alphaFrames do
        local af = _alphaFrames[i]
        local cf = af.cf
        if cf:IsShown() or af.bg:IsShown() then
            cf:SetAlpha(alpha)
            -- The panel is a UIParent child (taint fix) and does not inherit
            -- the chat frame's alpha -- fade it directly.
            af.bg:SetAlpha(alpha)
            local eb = af.eb
            if eb then
                local focused = eb:HasFocus()
                if issecretvalue and issecretvalue(focused) then focused = false end
                if cf.isTemporary or not focused then
                    eb:SetAlpha(alpha)
                end
            end
            if af.resizeGrip then af.resizeGrip:SetAlpha(alpha * 0.4) end
        end
    end
    -- Behind-tabs extension is UIParent-parented: fade it directly.
    if ns._chatBgExt then ns._chatBgExt:SetAlpha(alpha) end
    if ns._chatPanelBorder then ns._chatPanelBorder:SetAlpha(alpha) end
    if ns._sidebarSeparateBorder then
        ns._sidebarSeparateBorder:SetAlpha(min(alpha, _sidebarFadeAlpha))
    end
    -- The panel bottom separator is a texture on bg and inherits the chat frame's alpha
    -- automatically -- no explicit write needed. Sidebar (mode cached at build time)
    local sb = _alphaFrames._sidebar
    if sb then
        local sbMode = _alphaFrames._sidebarMode
        if sbMode == "mouseover" then
            sb:SetAlpha(min(alpha, _sidebarFadeAlpha))
        elseif sbMode ~= "never" then
            sb:SetAlpha(alpha)
        end
    end
    -- Chat-anchored scroll button (UIParent-parented, fades with the panel)
    if _alphaFrames._chatScrollBtn then
        _alphaFrames._chatScrollBtn:SetAlpha(alpha)
    end
end

-- Scroll-to-bottom button seat: sidebar bottom (default) or the chat panel's
-- bottom-right corner. The button is ours, so reparenting is safe.
function ECHAT.ApplyScrollButtonPosition()
    local cf1 = _G.ChatFrame1
    local d = cf1 and CFD(cf1)
    local btn = d and d.scrollBtn
    if not btn then return end
    local cfg = ECHAT.DB()
    -- Seat memo: this runs on every icon-layout pass (including sidebar hover
    -- edges); an unchanged seat needs no re-anchor and no alpha invalidation.
    local seat = cfg.scrollButtonOnChat and "chat" or "sidebar"
    if d.scrollSeat == seat then return end
    d.scrollSeat = seat
    local sb = d.sidebar
    btn:ClearAllPoints()
    if cfg.scrollButtonOnChat and d.bg then
        btn:SetParent(UIParent)
        btn:SetFrameStrata(cf1:GetFrameStrata())
        btn:SetFrameLevel(cf1:GetFrameLevel() + 5)
        -- Anchor to the message frame, not bg: the unified bg panel includes the
        -- edit box, so bg's corner sits in the input row.
        btn:SetPoint("BOTTOMRIGHT", cf1, "BOTTOMRIGHT", 8, -6)
    elseif sb then
        btn:SetParent(sb)
        btn:SetFrameStrata(sb:GetFrameStrata())
        btn:SetFrameLevel(sb:GetFrameLevel() + 1)
        btn:SetPoint("BOTTOM", sb, "BOTTOM", 0, 10)
    end
    -- Parent changed: the alpha cache decides whether to fade it directly.
    _alphaFrames = nil
end

-- Animate alpha toward target
local function _SetAlphaTarget(target)
    _chatAlphaTarget = target
    _chatFadeFrame:Show()
end

local _fadeApplyAccum = 0
_chatFadeFrame:SetScript("OnUpdate", function(self, dt)
    if _chatAlphaCurrent == _chatAlphaTarget then
        self:Hide()
        _fadeApplyAccum = 0
        -- The throttle below can swallow the last step of a fade; push the
        -- final value so completion states (especially 0) always land.
        _ApplyAlpha(_chatAlphaCurrent)
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
    -- The alpha step accumulates every frame but is only pushed to widgets on a
    -- throttle. Still smooth; saves ~75% of SetAlpha calls at 120fps.
    _fadeApplyAccum = _fadeApplyAccum + dt
    if _fadeApplyAccum < 0.016 then return end
    _fadeApplyAccum = 0
    _ApplyAlpha(_chatAlphaCurrent)
    if _chatAlphaCurrent == _chatAlphaTarget then
        self:Hide()
    end
end)

-- Animated alpha for the visibility/mouseover system. Top-level authority:
-- idle fade cannot exceed this.
function ECHAT.SetChatAlpha(alpha)
    _visAlpha = alpha
    _visChatVisible = (alpha >= 1)
    _SetAlphaTarget(alpha)
end

-- Animated idle-fade alpha, clamped to the visibility alpha
function ECHAT.SetIdleFadeAlpha(alpha)
    _SetAlphaTarget(min(alpha, _visAlpha))
end

-- Re-derive visibility from DB settings (combat, mouseover, always, ...)
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

-- Read all messages from the active window on demand. The primary source is
-- OUR message frame for the selected window; the hosted combat log (still
-- Blizzard-rendered) and any window the engine has not integrated fall back
-- to the Blizzard buffer read. Secret lines are skipped either way.
local function ReadActiveChatText()
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local cf = selected or ChatFrame1
    if not cf then return "" end
    local raw = {}
    local usedEngine = false
    if ECHAT.EngineGetMessageLines and ns._chatWins and ns._chatWins[cf]
        and not (ns._clHosted and cf == _G.ChatFrame2) then
        ECHAT.EngineGetMessageLines(cf, raw)
        usedEngine = true
    end
    if not usedEngine then
        if not cf.GetNumMessages then return "" end
        local n = cf:GetNumMessages()
        for i = 1, n do
            local ok, text = pcall(cf.GetMessageInfo, cf, i)
            if ok then raw[#raw + 1] = text end
        end
    end
    if #raw == 0 then return "(No chat history)" end
    local lines = {}
    for i = 1, #raw do
        local text = raw[i]
        if text and not (issecretvalue and issecretvalue(text)) then
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
    if not copyDimmer then
        local POPUP_W, POPUP_H = 520, 340

        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)
        dimmer:Hide()
        local dimTex = EUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
        dimTex:SetAllPoints()

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)

        local bg = EUI.SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
        bg:SetAllPoints()
        EUI.MakeBorder(popup, 1, 1, 1, 0.15, EUI.PanelPP)

        -- Blizzard template: scrolling + selection built in
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
            -- Not on the thumb: jump to the clicked position
            _sbDragOffsetY = (thumb:GetHeight() or 20) / 2
            _sbDragging = true
            SetScrollFromY(cursorY)
        end)
        track:SetScript("OnMouseUp", function() _sbDragging = false end)

        -- Polls only while the popup is open (hidden frame otherwise)
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

        local closeBtn = CreateFrame("Button", nil, popup)
        closeBtn:SetSize(90, 24)
        closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EUI.MakeStyledButton(closeBtn, "Close", 10,
            EUI.RB_COLOURS, function() dimmer:Hide() end)

        dimmer:SetScript("OnMouseDown", function()
            if not popup:IsMouseOver() then dimmer:Hide() end
        end)

        -- SetPropagateKeyboardInput is protected in combat: always pcall it.
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

    local popup = copyDimmer._popup
    popup._textBox:SetText(text)
    popup._editBox._readOnlyText = text
    ECHAT.HostPopup(copyDimmer)
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

-- Literal pre-check so the regex pass is skipped entirely for messages with no
-- URL-like substring (the overwhelming majority).
local function ContainsURL(text)
    if not text then return false end
    return text:find("://", 1, true) or text:find("www.", 1, true)
end

-- Substitution string built once (the color hex is constant)
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
    ECHAT.HostPopup(urlBackdrop)
    ECHAT.HostPopup(urlPopup)
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
    -- Secret link (lockdown line): match would error; no tooltip either way.
    if _G.issecretvalue and _G.issecretvalue(hyperlink) then return end
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

-- Open the copy popup when a wrapped URL link is clicked. Also the mirror
-- for the censored-message links ("[Show Message]" and its send/rewrite
-- siblings): their handlers rewrite or remove the stored line IN PLACE on
-- every chat frame (TransformMessages / RemoveMessagesByPredicate -- no
-- AddMessage, no event), so the engine window would keep showing the
-- placeholder; this post-hook runs after the handler and queues the same
-- deferred rebuild the CAUTIONARY_CHAT_MESSAGE mirror uses.
hooksecurefunc("SetItemRef", function(link)
    if not link then return end
    if _G.issecretvalue and _G.issecretvalue(link) then return end
    if link:find("^censoredmessage") then
        if ECHAT.EngineQueueRebuildAll then ECHAT.EngineQueueRebuildAll() end
        return
    end
    local url = link:match("^" .. addonName .. "url:(.+)$")
    if url then
        ShowUrlPopup(url)
    end
end)

-------------------------------------------------------------------------------
--  Chat frame reskin
-------------------------------------------------------------------------------
local _skinned = {}

-- Chat events counted as real PLAYER activity (used ONLY to reset the
-- idle-fade timer). NEVER add MONSTER_SAY/MONSTER_YELL: in a party their
-- chanSender is SECRET, and registering this insecure frame for them taints
-- HistoryKeeper when it string-converts the sender -> taint spam per monster
-- line. All senders below are plain visible player names.
local CHAT_MSG_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_CHANNEL = true,
    -- WHISPER/BN_WHISPER stay off this frame: the whisper-sound event frame
    -- (init section 7) receives them, keeping secret-sender events on ONE
    -- frame. Outgoing _INFORM variants need no registration -- the edit-box
    -- OnEditFocusGained/OnTextChanged hooks already reset the fade.
}

-------------------------------------------------------------------------------
--  Tabs are fully owned (EllesmereUIChat_Tabs.lua): our buttons over our own
--  strip, styled from the same settings, with Blizzard's strip hidden. The
--  ECHAT.ApplyTab* entry points the options page calls are defined there.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  SkinEditBox: ALL edit box modifications in one place. Chrome/position/font
--  apply to ALL frames (including temp 11+); HOOKS only on frames 1-10.
-------------------------------------------------------------------------------
local function SkinEditBox(cf)
    local name = cf:GetName()
    if not name then return end
    local eb = _G[name .. "EditBox"]
    local idx = tonumber(name:match("ChatFrame(%d+)"))
    if not eb or not idx or CFD(eb).skinned then return end
    CFD(eb).skinned = true

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

    -- Flush below the chat frame, for ALL frames including temp 11+.
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -10, -8)
    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -8)
    eb:SetHeight(GetEditBoxHeight())

    -- Same outline as the chat frames and ECHAT.ApplyFonts (both read
    -- GetOutlineFlag), so the input box always matches the rest of chat --
    -- hardcoding "" here leaves it un-outlined with the drop shadow showing.
    local ebSize = GetEditBoxFontSize(cf:GetID())
    eb:SetFont(GetEditBoxFont(), ebSize, GetOutlineFlag())
    eb:SetTextInsets(8, 8, 0, 0)

    -- Custom font for the header ("Say:", "Party:", ...) and suffix. Called at
    -- skin time and on focus-gained (covers chat-type switches). NEVER call
    -- from inside UpdateHeader -- SetFont in that secure chain taints the
    -- execution context and blocks SendChatMessage.
    local function ApplyEditBoxHeaderFont(editBox)
        local sz = GetEditBoxFontSize(editBox:GetParent():GetID())
        local ol = GetOutlineFlag()
        if editBox.header then
            editBox.header:SetFont(GetEditBoxFont(), sz, ol)
        end
        if editBox.headerSuffix then
            editBox.headerSuffix:SetFont(GetEditBoxFont(), sz, ol)
        end
    end
    ApplyEditBoxHeaderFont(eb)

    -- Edit box HOOKS (not the plain setters above) taint a temp whisper
    -- window's execution context: when its secure code later touches its
    -- secret tellTarget (e.g. a BN_WHISPER presence ID), it poisons the
    -- shared ChatHistory access tables and EVERY chat message errors in
    -- HistoryKeeper for the rest of the session. Only permanent docked frames
    -- (1-10) may be hooked; temp windows (11+) get visuals only.
    if idx <= 10 then
        eb:HookScript("OnEditFocusGained", function(self)
            ApplyEditBoxHeaderFont(self)
        end)

        -- Input-on-top: reclaim/release the reserved top strip of the text
        -- area as the input comes and goes, so an idle chat uses its full
        -- height. OnShow/OnHide are C-side script hooks -- no field write onto
        -- the edit box, the hazard the block comment above describes.
        eb:HookScript("OnShow", function()
            ECHAT.RefreshInputTopStrips()
        end)
        eb:HookScript("OnHide", function()
            ECHAT.RefreshInputTopStrips()
        end)

        -- Plain Up/Down input recall. The Midnight edit box performs no native recall
        -- on plain arrows regardless of alt-arrow mode, so recall is Lua-side over an
        -- external history. Two rules keep it taint-safe (breaking them blocks /ping
        -- with ADDON_ACTION_FORBIDDEN): (1) SECURE commands (IsSecureCmd: /ping,
        -- /cast, ...) NEVER enter this history -- SetText plants addon-tainted text,
        -- fatal for a protected re-send; (2) Alt chords pass through untouched --
        -- Alt+Up/Down stays the engine's own untainted recall, our SetText must never
        -- overwrite it. Alt-arrow mode must be OFF or the widget never hands plain
        -- Up/Down to the OnKeyDown hook.
        eb:SetAltArrowKeyMode(false)
        if not CFD(eb).history then
            CFD(eb).history = {}
            CFD(eb).histIdx = 0
            -- Sent-line capture for the recall history above. NEVER use
            -- hooksecurefunc(eb, "AddHistoryLine", ...): it reads as
            -- a function hook but is a FIELD WRITE onto the Blizzard edit box
            -- (hooksecurefunc(object, "method", fn) assigns object.method =
            -- wrapper), which taints ChatFrame1EditBox. Blizzard calls
            -- self:AddHistoryLine(text) from inside its send path, so that tainted
            -- field read lands in the chat machinery and blocks
            -- ChatFrameEditBoxMixin:OnUpdate's SetText on a secret whisper target.
            -- Script hooks carry no field write and are verified clean. OnEnterPressed
            -- alone is not enough: Blizzard's handler runs first and clears the box, so
            -- text is shadowed on change and committed on send.
            eb:HookScript("OnTextChanged", function(self, userInput)
                local t = self:GetText()
                if issecretvalue and issecretvalue(t) then
                    CFD(self).pendingLine = nil
                    return
                end
                -- A PROGRAMMATIC empty write must not consume the shadow:
                -- Blizzard's OnEnterPressed clears the box (SetText("")) before our
                -- commit hook runs, so honoring it would erase the line the commit is
                -- about to read. User-typed emptiness (select-all + delete) still
                -- records "" so an empty send commits nothing; programmatic non-empty
                -- writes (arrow recall, reply prefill) shadow normally.
                if t == "" and not userInput then return end
                CFD(self).pendingLine = t
            end)
            eb:HookScript("OnEnterPressed", function(self)
                local d = CFD(self)
                local text = d.pendingLine
                d.pendingLine = nil
                if not text or text == "" then return end
                if issecretvalue and issecretvalue(text) then return end
                local cmd = text:match("^%s*(/%S+)")
                if cmd and IsSecureCmd and IsSecureCmd(cmd) then return end
                local h = d.history
                if h[#h] ~= text then
                    h[#h + 1] = text
                    if #h > 50 then table.remove(h, 1) end
                end
            end)
            eb:HookScript("OnKeyDown", function(self, key)
                if key ~= "UP" and key ~= "DOWN" then return end
                if IsAltKeyDown() then return end
                -- Narrow, field-proven restriction guards.
                -- C_ChatInfo.InChatMessagingLockdown exists but its breadth on
                -- Midnight is unverified -- do not swap it in blind.
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
    -- event frames (sections 5/6 below).

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
        bg:SetFrameStrata(cf:GetFrameStrata())
        bg:SetFrameLevel(max(0, cf:GetFrameLevel() - 1))
        bg:SetShown(cf:IsShown())

        local bgTex = bg:CreateTexture(nil, "BACKGROUND")
        bgTex._euiOwned = true
        bgTex:SetAllPoints()
        bgTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)

        -- NO cf:HookScript("OnShow") to mirror visibility: FCF_OpenTemporary- Window
        -- shows the pooled frame partway through (via SetShown), so on any frame
        -- skinned while hidden (pooled temp window between conversations, or restored
        -- by reload with a whisper open) that closure would run INSIDE the open and
        -- taint the rest of it. The state watcher carries shown-state instead.
        CFD(cf).bg = bg
    end

    -- Sidebar: icon panel beside the main chat frame. Parented to UIParent so it
    -- stays visible regardless of the active tab.
    if name == "ChatFrame1" and not CFD(cf).sidebar then
        local sidebar = CreateFrame("Frame", nil, UIParent)
        sidebar:SetWidth(min(100, max(30, ECHAT.DB().sidebarWidth or 40)))
        sidebar:SetPoint("TOPRIGHT", CFD(cf).bg, "TOPLEFT", 0, 0)
        sidebar:SetPoint("BOTTOMRIGHT", CFD(cf).bg, "BOTTOMLEFT", 0, 0)
        sidebar:SetFrameStrata(cf:GetFrameStrata())
        sidebar:SetFrameLevel(cf:GetFrameLevel() + 1)

        local sbBg = sidebar:CreateTexture(nil, "BACKGROUND")
        sbBg:SetAllPoints()
        sbBg:SetColorTexture(BG_R, BG_G, BG_B, BG_A)

        sidebar:EnableMouse(true)
        sidebar:SetScript("OnEnter", function()
            local cfg = ECHAT.DB()
            if cfg.sidebarVisibility == "mouseover" then
                -- Fade target MUST be set before the layout pass: the icon
                -- shown-state in ApplySidebarIcons reads it to decide whether
                -- the faded-out cutoff still applies.
                _sidebarFadeTarget = 1
                if not _sidebarMouseoverLayoutVisible then
                    _sidebarMouseoverLayoutVisible = true
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
                        _sidebarFadeTarget = 0
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

        -- Visibility + ordering config is read once, at creation time.
        local icfg = ECHAT.DB()
        local showFriends    = icfg.showFriends ~= false
        local showGuild      = icfg.showGuild ~= false
        local showDurability = icfg.showDurability ~= false

        -- Extended background grows the sidebar upward by the tab-strip height,
        -- so chain-anchored icons shift up the same amount to keep the top gap.
        -- Skipped under free-move: those icons are user-positioned, not chained.
        local iconTopShift = (icfg.extendBgBehindTabs and not icfg.freeMoveIcons) and GetTabAreaHeight() or 0

        -- Chain icons are created in the saved order (drag-to-reorder in the
        -- options dropdown; a new order takes effect on the next reload).
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
                if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, "Friends") end
            end)
            friendsBtn:HookScript("OnLeave", function(self)
                friendsCount:SetTextColor(1, 1, 1, 0.5)
                HideSidebarIconTooltip(self)
            end)

            local fcLast, fcDirty
            local function UpdateFriendsCount()
                if InCombatLockdown() then
                    fcDirty = true
                    return
                end
                fcDirty = nil
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
            fcEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
            -- Recount inline on the exact edges -- the narrow account
            -- online/offline pair (the same field-proven set the DataBars
            -- micromenu count uses), NOT the BN_FRIEND_INFO_CHANGED presence
            -- firehose, so nothing fires between real login/logout edges.
            -- Two cached count reads plus one compare, no timers, and the
            -- label only rewrites when the number changed. In combat nothing
            -- recounts at all -- events mark the count dirty and the regen
            -- edge settles it once.
            fcEvents:SetScript("OnEvent", function(_, event)
                if event == "PLAYER_REGEN_ENABLED" then
                    if fcDirty then UpdateFriendsCount() end
                    return
                end
                UpdateFriendsCount()
            end)

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
                if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, "Guild") end
            end)
            guildBtn:HookScript("OnLeave", function(self)
                guildCount:SetTextColor(1, 1, 1, 0.5)
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
            durabilityBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_durability.png")
            ChainAnchor(durabilityBtn)

            durabilityPct = sidebar:CreateFontString(nil, "OVERLAY")
            durabilityPct:SetFont(GetFont(), 9, "")
            durabilityPct:SetTextColor(1, 1, 1, 0.5)
            durabilityPct:SetPoint("TOP", durabilityBtn, "BOTTOM", 0, 0)
            durabilityPct:SetText("100%")

            durabilityBtn:HookScript("OnEnter", function(self)
                durabilityPct:SetTextColor(1, 1, 1, 0.9)
                if not self._freeMoveJustDragged then
                    ShowSidebarIconTooltip(self, "Equipment Durability")
                end
            end)
            durabilityBtn:HookScript("OnLeave", function(self)
                durabilityPct:SetTextColor(1, 1, 1, 0.5)
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
            anchor = durabilityPct
        end

        -- Friends/Guild/Durability have bespoke creators (count or percent text
        -- plus events); the rest are plain sidebar icons.
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

        -- Scroll is pinned to the sidebar bottom, outside the chain.
        local scrollBtn = MakeSidebarIcon(sidebar, MEDIA .. "chat_scroll2.png")
        scrollBtn:SetSize(22, 22)
        scrollBtn:ClearAllPoints()
        scrollBtn:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, ICON_SPACING)

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
        end

        if settingsBtn then
        settingsBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            local mf = EUI._mainFrame
            if mf and mf:IsShown() and EUI:GetActiveModule() == "EllesmereUIChat" then
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
        sbd.settingsBtn = settingsBtn
        sbd.scrollBtn = scrollBtn
        -- Order snapshot for ApplySidebarIcons: live visibility toggles keep this
        -- session's layout; a changed saved order applies on reload.
        sbd._iconChainOrder = chainOrder

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
    -- (temp-window open) both read it. Blizzard drives this frame's alpha on hover
    -- (UIFrameFadeIn/Out), so the zero is re-asserted by the state watcher rather than
    -- set once -- same idiom as the scroll buttons and minimize button below.
    local btnFrame = _G[name .. "ButtonFrame"]
    if btnFrame then
        btnFrame:SetAlpha(0)
        btnFrame:EnableMouse(false)
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
            resizeBtn:SetAlpha(0.4)
            -- Arms the interaction follower: a resize drag starts and stays on
            -- this button, and the panel must follow it live.
            resizeBtn:HookScript("OnEnter", function(self)
                self:SetAlpha(0.75)
                if ECHAT.FollowArm then ECHAT.FollowArm() end
            end)
            resizeBtn:HookScript("OnLeave", function(self)
                self:SetAlpha(0.4)
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

    local minBtn = _G[name .. "MinimizeButton"]
    if minBtn then minBtn:SetAlpha(0); minBtn:EnableMouse(false) end

    -- Strip ALL Blizzard textures from the chat frame. Texture objects only, and
    -- skips anything we created (marked with _euiOwned).
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

    cf:SetHyperlinksEnabled(true)

    -- Combat Log: replace Blizzard's filter tab bar with a dark bar matching
    -- the chat panel's width and style.
    if name == "ChatFrame2" then
        local qbf = _G.CombatLogQuickButtonFrame_Custom
        if qbf and not CFD(qbf).skinned then
            CFD(qbf).skinned = true

            if qbf.GetRegions then
                for i = 1, select("#", qbf:GetRegions()) do
                    local region = select(i, qbf:GetRegions())
                    if region and region:IsObjectType("Texture") then
                        region:SetAlpha(0)
                    end
                end
            end

            -- Flush: filter bar bottom meets bg top (cf top + 3), width matches
            -- the panel.
            qbf:ClearAllPoints()
            qbf:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -10, 3)
            qbf:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 10, 3)
            qbf:SetHeight(24)

            local qbfBg = qbf:CreateTexture(nil, "BACKGROUND")
            qbfBg:SetAllPoints()
            qbfBg:SetColorTexture(BG_R, BG_G, BG_B, 1)


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
                        if btn.GetRegions then
                            for j = 1, select("#", btn:GetRegions()) do
                                local rgn = select(j, btn:GetRegions())
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
            if EUI.RegAccent then
                EUI.RegAccent({ type = "callback", fn = UpdateCLFilterColors })
            end

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

-------------------------------------------------------------------------------
--  Tab refresh shim: the owned strip (EllesmereUIChat_Tabs.lua) redraws from
--  a coalesced deferred pass; this also re-hides anything of Blizzard's tab
--  plane that its own event passes re-showed.
-------------------------------------------------------------------------------
local function UpdateTabColors()
    if ECHAT.TabsSweepBlizzard then ECHAT.TabsSweepBlizzard() end
    if ECHAT.TabsRefresh then ECHAT.TabsRefresh() end
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
    --  2. Skin all 20 chat frames (bg, tabs, edit box, etc.), then bring them
    --     under the display engine: font providers first, then integration
    --     (Blizzard text suppressed, AddMessage bridge installed, our windows
    --     built and backfilled with everything already in Blizzard's buffers).
    ---------------------------------------------------------------------------
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf then SkinChatFrame(cf) end
    end
    ECHAT.EngineFontProvider = GetFont
    ECHAT.EngineFontSizeProvider = GetFrameFontSize
    ECHAT.EngineOutlineProvider = GetOutlineFlag
    -- Seed the display-transform switches BEFORE integration: the install
    -- backfill renders through the same transforms as live lines.
    if ECHAT.EngineSetChannelAbbrev then
        ECHAT.EngineSetChannelAbbrev(p.abbreviateChannels == true)
    end
    if p.classColorNames == true then
        ECHAT.ApplyClassColorNames(true)
    end
    if ECHAT.EngineIntegrateAll then ECHAT.EngineIntegrateAll() end
    -- Owned tab strip: hides Blizzard's strip, builds ours from the same
    -- window storage, and starts mirroring selection/flash from the engine.
    if ECHAT.TabsInit then ECHAT.TabsInit() end
    -- Re-run the background pass so a saved Background Texture applies at login
    -- (the skin loop creates the bg textures with the solid color).
    ECHAT.ApplyBackground()
    ---------------------------------------------------------------------------
    --  2b. NEVER replace the global CHAT_FONT_HEIGHTS to expand font sizes:
    --      every read becomes tainted, and Blizzard's tab context menu
    --      iterates it mid-build, so the whole menu -- every click handler
    --      wired after that read -- runs tainted, and any item touching a
    --      whisper window's secret-keyed tables errors
    --      (FCF_RestoreChatsToFrame forbidden-table iteration). EUI font size
    --      is applied at skin time instead.
    ---------------------------------------------------------------------------


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
    --  3. Temporary window (whisper) detection.
    ---------------------------------------------------------------------------
    -- Shared skin pass: skins unskinned frames, re-strips tabs, re-applies font,
    -- hides Blizzard chrome. Driven by whisper events and the state watcher --
    -- never by a hooksecurefunc on FCF_OpenTemporaryWindow, which taints edit
    -- box header arithmetic during window creation.
    local function SkinPass()
        local wantFont = GetFont()
        local wantOutline = GetOutlineFlag()
        for i = 1, 20 do
            local cf = _G["ChatFrame" .. i]
            -- New frames (SkinChatFrame handles the panel + edit box)
            if cf and not _skinned[cf] then
                SkinChatFrame(cf)
            end
            -- Re-apply font if Blizzard reset it (e.g. font size change).
            -- Family form, not raw SetFont: a raw write here would detach
            -- the CJK font family the skin pass attached.
            if cf and _skinned[cf] then
                local curFont = cf:GetFont()
                if curFont and curFont ~= wantFont then
                    -- Size from Blizzard's stored per-window setting, NEVER read
                    -- back off the widget: under a font family cf:GetFont()
                    -- answers for the ACTIVE alphabet, so on a CJK client it
                    -- returns the CJK member -- a file that never equals
                    -- wantFont, at that member's own height. Feeding it back in
                    -- re-seeded the family from its own output, and this pass
                    -- runs on UPDATE_(FLOATING_)CHAT_WINDOWS, so chat text grew
                    -- on every login, reload and tab switch.
                    local sz = GetFrameFontSize(cf:GetID())
                    local fam = ECHAT.EngineFontFamily
                        and ECHAT.EngineFontFamily(cf:GetID(), wantFont, sz, wantOutline)
                    if fam then
                        cf:SetFontObject(fam)
                    else
                        cf:SetFont(wantFont, sz, wantOutline)
                    end
                end
                -- Blizzard resets this alongside the font/dock passes above;
                -- re-assert every pass rather than gating on a changed-check
                -- (a plain boolean set costs nothing). See SkinChatFrame for
                -- why this must stay congruent with win.smf's own setting.
                cf:SetIndentedWordWrap(true)
            end
        end
        UpdateTabColors()
        ECHAT.ApplyTabLayout()
        if ECHAT.ApplyInputPosition then ECHAT.ApplyInputPosition() end
    end

    ---------------------------------------------------------------------------
    --  4. Chat-frame state watcher, in place of FCF_* hooksecurefunc hooks.
    --  NEVER hooksecurefunc FCFDock_SelectWindow / FCF_Close /
    --  FCF_OpenNewWindow -- deferring the body to C_Timer.After(0) does not
    --  help, since the hook WRAPPER still executes inside the caller's own
    --  execution and taints the rest of that caller. Measured chain: an
    --  FCF_Close hook taints the caller -> a later FCF_DockFrame (or
    --  FCF_CopyChatSettings) reaches FCF_SetLocked, whose `chatFrame.isLocked
    --  = isLocked` write lands under that taint -> the FIELD stays tainted
    --  through every later secure pass (so watching only GLOBALS reads
    --  clean) -> FCF_Tab_SetupMenu reads tabChatFrame.isLocked building the
    --  tab menu, so its closures (incl. "Close Whisper Window") die
    --  iterating the forbidden privateMessageList -> the same field is read
    --  by FCF_UpdateResizeButton during the temp-window OPEN, tainting its
    --  secret whisper-name math too. One field, both error classes. These
    --  hooks only did cosmetic re-assertion, so the same state is watched
    --  instead -- from the interaction follower (armed only while chat is
    --  hovered or Edit Mode is open) and the deferred event passes below:
    --  outside Blizzard's dispatch, zero idle cost, up to one tick latency.
    ---------------------------------------------------------------------------
    -- Likewise NEVER hook FCFTab_UpdateColors or FCFDock_UpdateTabs synchronously:
    -- FCF_OpenTemporaryWindow -> FCF_SetTemporaryWindowType calls FCFTab_UpdateColors
    -- directly and ends with a synchronous FCFDock_UpdateTabs call, so both hook bodies
    -- would execute inside the temp-whisper creation chain, deactivating the new
    -- editBox and running UpdateHeader's width math on the SECRET whisper-name geometry
    -- -- no body shape is safe here. Recolor + layout run DEFERRED from our own
    -- triggers below; the cost is a possible 1-frame Blizzard-styled flash.
    local _tabPassQueued = false
    local function QueueTabPass()
        if _tabPassQueued then return end
        _tabPassQueued = true
        C_Timer.After(0, function()
            _tabPassQueued = false
            UpdateTabColors()
            ECHAT.ApplyTabLayout()
            -- Every restyle trigger is also a moment panel geometry can
            -- shift or the dock selection can have changed; all calls
            -- early-out on clean state, and this deferred body is our own
            -- execution.
            if ECHAT.SyncChatFrameState then ECHAT.SyncChatFrameState() end
            if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
            if ECHAT.EngineUpdateCombatLogHost then ECHAT.EngineUpdateCombatLogHost() end
        end)
    end
    ECHAT.QueueTabPass = QueueTabPass
    -- Full pass: skin new frames, then restyle + state sync. SkinPass ends with
    -- UpdateTabColors/ApplyTabLayout/ApplyInputPosition, so this is the one-stop
    -- deferred handler for anything that can create a chat frame.
    local _fullPassQueued = false
    local function QueueFullPass()
        if _fullPassQueued then return end
        _fullPassQueued = true
        C_Timer.After(0, function()
            _fullPassQueued = false
            SkinPass()
            -- New frames (temp whisper windows, user-created windows) join
            -- the engine here: visual children parked, bridge installed, our
            -- window built and backfilled. Idempotent for known frames.
            if ECHAT.EngineIntegrateAll then ECHAT.EngineIntegrateAll() end
            if ECHAT.SyncChatFrameState then ECHAT.SyncChatFrameState() end
            if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
            -- A re-skin resets the resize button's base alpha; re-assert the
            -- lock state over it.
            if ECHAT.ApplyLockChatSize then ECHAT.ApplyLockChatSize() end
            -- A frame integrated while the panel is fully hidden must join
            -- the passthrough set.
            RequestPassthroughSweep()
            -- A window created while the house editor is open is born on the
            -- hidden UIParent; seat it with the rest of the panel.
            ECHAT.ApplyPanelHost()
        end)
    end
    ECHAT.QueueFullPass = QueueFullPass
    -- Every moment Blizzard resets our styling (login passes, zone transitions, dock
    -- config loads) coincides with these events on our own frame -- outside Blizzard's
    -- dispatch, deferred one tick. Also covers user-created permanent windows
    -- (UPDATE_CHAT_WINDOWS) and repositions panels after scale changes.
    local tabPassFrame = CreateFrame("Frame")
    tabPassFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    tabPassFrame:RegisterEvent("UPDATE_CHAT_WINDOWS")
    tabPassFrame:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
    tabPassFrame:RegisterEvent("UI_SCALE_CHANGED")
    tabPassFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    tabPassFrame:SetScript("OnEvent", QueueFullPass)
    -- Edit Mode can rebuild the chat dock and tab geometry after a panel resize.
    -- Re-assert tab appearance only once that update has left Blizzard's
    -- event/script stack; the short second pass covers the final size commit
    -- performed while Edit Mode closes.
    do
        local editModeStyleGeneration = 0
        local function QueueEditModeTabStyle()
            editModeStyleGeneration = editModeStyleGeneration + 1
            local generation = editModeStyleGeneration
            QueueTabPass()
            C_Timer.After(0.10, function()
                if generation == editModeStyleGeneration then QueueTabPass() end
            end)
        end
        local editModeStyleFrame = CreateFrame("Frame")
        editModeStyleFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        editModeStyleFrame:SetScript("OnEvent", function()
            C_Timer.After(0, QueueEditModeTabStyle)
        end)
        if EditModeManagerFrame then
            -- Arm the follower for the whole Edit Mode session: chat can be
            -- dragged/resized with the mouse nowhere near our hover widgets
            -- (the Selection overlay occludes them).
            EditModeManagerFrame:HookScript("OnShow", function()
                if ECHAT.FollowArmEditMode then ECHAT.FollowArmEditMode(true) end
            end)
            EditModeManagerFrame:HookScript("OnHide", function()
                if ECHAT.FollowArmEditMode then ECHAT.FollowArmEditMode(false) end
                C_Timer.After(0, QueueEditModeTabStyle)
            end)
        end
    end

    -- House editor open/close: reseat the panel onto Blizzard's full-screen host
    -- (see ApplyPanelHost). Our own event frame, deferred a tick so the reseat
    -- runs after HouseEditorFrame's show/hide has set the full-screen frame --
    -- never an EventRegistry callback or a hook, both of which would run our
    -- body inside Blizzard's own execution.
    if C_HouseEditor and C_HouseEditor.IsHouseEditorActive then
        local houseEditorFrame = CreateFrame("Frame")
        houseEditorFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
        houseEditorFrame:SetScript("OnEvent", function()
            C_Timer.After(0, ECHAT.ApplyPanelHost)
        end)
    end
    -- Tab close is covered by the state watcher above. NEVER hook FCF_Close:
    -- "top-level user action" is the wrong test -- it is also reached from
    -- FCF_PopInWindow (the tab menu's own Close button) and dock teardown, and even
    -- a genuine top-level click's hook taints the REST of the caller, which is what
    -- poisons ChatFrame*.isLocked. Temp window creation: NEVER
    -- hooksecurefunc("FCF_OpenTemporaryWindow") either -- the secure whisper router
    -- calls it mid-function and continues to DeactivateChat -> UpdateHeader, whose
    -- width math runs on the SECRET whisper name geometry; our hook in the chain
    -- taints the remainder of the caller and blocks that arithmetic. Instead the
    -- same whisper events are registered on our own frame (standalone C-side
    -- dispatch, outside Blizzard's execution, taint-free) and the skin is deferred.
    -- That covers every temp-window trigger: incoming whisper and outgoing /w in
    -- popout mode (WHISPER_INFORM).
    do
        local tempWinFrame = CreateFrame("Frame")
        tempWinFrame:RegisterEvent("CHAT_MSG_WHISPER")
        tempWinFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
        tempWinFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
        tempWinFrame:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
        tempWinFrame:SetScript("OnEvent", QueueFullPass)
    end
    -- User-created permanent chat windows are covered by the full pass on
    -- UPDATE_CHAT_WINDOWS -- NO hooksecurefunc on FCF_OpenNewWindow: it is
    -- created from the same tab menu whose closures must stay untainted.

    -- One extra strip pass once the loading screen drops: Blizzard's final
    -- login dock update can re-show pieces of its (hidden) tab plane.
    do
        local pinFrame = CreateFrame("Frame")
        pinFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
        pinFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            UpdateTabColors()
            ECHAT.ApplyTabLayout()
            -- Chat position ownership begins at the first settled sight:
            -- capture Edit Mode's placement as ours if unsaved, arm the
            -- anchor guard, kill the Edit Mode selection overlay, apply.
            if ns._CaptureChatPositionGenesis then ns._CaptureChatPositionGenesis() end
            if ns._InstallChatAnchorGuard then ns._InstallChatAnchorGuard() end
            if ECHAT.SuppressChatEditModeSelection then ECHAT.SuppressChatEditModeSelection() end
            if ECHAT.ApplyChatPosition then ECHAT.ApplyChatPosition() end
            -- Font size follows the profile: capture on first sight,
            -- re-assert on every later login.
            if ECHAT.SyncChatFontSize then ECHAT.SyncChatFontSize() end
            -- (ApplyChatPosition self-resyncs panels+strip one tick later,
            -- and the EDIT_MODE_LAYOUTS_UPDATED watcher re-asserts if Edit
            -- Mode's late layout apply lands after this.)
            -- Post-login heal window: Edit Mode's last write can land through
            -- paths none of the event answers see, leaving chat at EM's rect
            -- (short by the tab area) until the first hover armed the
            -- follower's drift heal. Run the state sync -- which carries that
            -- heal -- on a short bounded cadence instead, then self-destruct.
            local healTicks = 0
            local healFrame = CreateFrame("Frame")
            local healAccum = 0
            healFrame:SetScript("OnUpdate", function(w, dt)
                healAccum = healAccum + dt
                if healAccum < 0.1 then return end
                healAccum = 0
                healTicks = healTicks + 1
                if ECHAT.SyncChatFrameState then ECHAT.SyncChatFrameState() end
                if healTicks >= 40 then w:SetScript("OnUpdate", nil) end
            end)
        end)
    end

    ---------------------------------------------------------------------------
    --  5. Tab color management. The deferred update batches multiple tab
    --     changes into one pass.
    ---------------------------------------------------------------------------
    -- Blizzard performs additional dock sizing after the initial chat setup, so
    -- text-derived widths are re-applied across a few deferred passes and saved
    -- Inner Padding X is correct without requiring a tab click.
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
    --  6. Idle fade: dims chat after N seconds of inactivity. Resets on a new
    --     message on the active tab, a whisper window, edit box focus/typing,
    --     or the cursor entering the chat area (event-driven, no polling).
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
            -- Faded: arm the hover-reveal motion overlay.

            if ECHAT.ApplyIdleFadeHoverMotion then ECHAT.ApplyIdleFadeHoverMotion() end
        end

        local function CancelIdleFade()
            local wasActive = _idleFadeActive
            _idleFadeActive = false
            if idleTimer then
                idleTimer:Cancel()
                idleTimer = nil
            end
            if _visChatVisible then
                ECHAT.SetIdleFadeAlpha(1)
            end
            -- Visible again: the overlay goes inert so the panel area is
            -- click- and camera-transparent like the default UI.
            if wasActive and ECHAT.ApplyIdleFadeHoverMotion then
                ECHAT.ApplyIdleFadeHoverMotion()
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
            -- (No passthrough sweep needed on messages anymore: Blizzard's
            -- line pool is parked in the engine's hidden container, and OUR
            -- message frames are hidden outright while passthrough is
            -- engaged -- a hidden frame arms nothing.)
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

        -- Permanent docked frames only (1-10): hooking a temp whisper edit
        -- box (11+) taints its execution context and poisons HistoryKeeper on
        -- BN_WHISPER. A /reload with a conversation window open could expose
        -- one here, hence the gate.
        for i = 1, 10 do
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if eb then
                eb:HookScript("OnEditFocusGained", function(...)
                    OnActiveMessage(...)
                end)
                eb:HookScript("OnTextChanged", function(...)
                    OnActiveMessage(...)
                end)
            end
        end

        ---------------------------------------------------------------------------
        --  7. Whisper sound alert (also resets idle fade for incoming
        --     whispers). Driven by a standalone EVENT FRAME, not a message
        --     filter: Blizzard wraps every filter in
        --     `if canaccessvalue(...) then callback(...) end`
        --     (ChatFrameFilters.lua), so a message carrying ANY value the
        --     addon cannot access -- the secret sender on every BN whisper --
        --     skips the filter entirely, even one that reads no arguments.
        --     Event registration on our own frame is outside Blizzard's
        --     dispatch and carries no taint.
        ---------------------------------------------------------------------------
        do
            local WHISPER_SOUND_PATHS, WHISPER_SOUND_NAMES, WHISPER_SOUND_ORDER =
                EllesmereUI.BuildAlertSoundTables()
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
                OnActiveMessage()
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

        -- Event-driven hover detection: zero CPU when idle. Uses
        -- EnableMouseMotion on our bg frames + HookScript on tabs.
        -- EnableMouseMotion captures hover without blocking clicks but does
        -- block camera turning -- accepted trade-off for zero-poll.
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

        -- Single invisible overlay covering tabs + bg + sidebar, at BACKGROUND strata.
        -- Its mouse motion is conditional -- see ApplyIdleFadeHoverMotion below.
        do
            local cf1 = _G.ChatFrame1
            local gdm = _G.GeneralDockManager
            local bg1 = CFD(cf1).bg
            local sb = CFD(cf1).sidebar
            if bg1 and gdm then
                local overlay = CreateFrame("Frame", nil, UIParent)
                ns._chatHoverOverlay = overlay
                overlay:SetPoint("TOPLEFT", gdm, "TOPLEFT", sb and -40 or 0, 0)
                overlay:SetPoint("BOTTOMRIGHT", bg1, "BOTTOMRIGHT", 0, 0)
                overlay:SetFrameStrata("BACKGROUND")
                overlay:EnableMouse(false)
                -- Peek reveal: motion is live ONLY while idle-faded (see
                -- ApplyIdleFadeHoverMotion), so an enter here can only mean
                -- the user moused over the faded chat. No OnLeave needed --
                -- the reveal itself turns motion back off.
                overlay:SetScript("OnEnter", function()
                    if _idleFadeActive and ECHAT.ResetIdleTimer then
                        ECHAT.ResetIdleTimer()
                    end
                end)
                -- Motion capture is needed ONLY while the chat is idle-faded (to catch
                -- the reveal hover). While visible the overlay must be inert so clicks
                -- AND camera drags over the panel reach the world exactly like the
                -- default UI (EnableMouseMotion intercepts right-drag camera input even
                -- though it passes clicks). Passthrough (full hide) keeps it inert too.
                function ECHAT.ApplyIdleFadeHoverMotion()
                    local cfg = ECHAT.DB()
                    local on = cfg.idleFadeEnabled ~= false
                        and (cfg.visibility or "always") ~= "never"
                        and ns._chatPassthrough ~= true
                        and _idleFadeActive
                    -- Per-channel setters, and click pinned OFF every pass:
                    -- EnableMouseMotion toggling alone leaves the click
                    -- channel armed, which made this overlay an invisible
                    -- click-catcher over the VISIBLE chat -- clicks and
                    -- camera dead, undetectable by motion-based probes.
                    if overlay.SetMouseClickEnabled then
                        overlay:SetMouseClickEnabled(false)
                    end
                    if overlay.SetMouseMotionEnabled then
                        overlay:SetMouseMotionEnabled(on)
                    else
                        overlay:EnableMouseMotion(on)
                    end
                    if not on then
                        _hoverCount = 0
                        _idleMouseOver = false
                    end
                end
                ECHAT.ApplyIdleFadeHoverMotion()
            end
        end

        -- Sidebar has EnableMouse(true) which blocks the overlay beneath it.
        -- HookScript on our own frame -- safe, no taint.
        local sidebar = CFD(ChatFrame1).sidebar
        if sidebar then
            sidebar:HookScript("OnEnter", function()
                _hoverCount = _hoverCount + 1; UpdateHoverState()
                if ECHAT.FollowArm then ECHAT.FollowArm() end
            end)
            sidebar:HookScript("OnLeave", function()
                _hoverCount = max(0, _hoverCount - 1); UpdateHoverState()
                if ECHAT.FollowRelease then ECHAT.FollowRelease() end
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

    -- Seed the engine's stamp-all transform with the RESOLVED format:
    -- explicit formats pass through, "__blizzard" resolves to Blizzard's own
    -- setting, "none" (either source) disarms it.
    local function ApplyStampAll()
        if not ECHAT.EngineSetStampAll then return end
        local cfg = ECHAT.DB()
        local fmt = cfg.timestampFormat or "%I:%M "
        if fmt == "none" then
            fmt = nil
        elseif fmt == "__blizzard" then
            local ok, f = pcall(function()
                return ChatFrameUtil and ChatFrameUtil.GetTimestampFormat and ChatFrameUtil.GetTimestampFormat()
            end)
            fmt = (ok and type(f) == "string" and f ~= "" and f ~= "none") and f or nil
        end
        ECHAT.EngineSetStampAll(cfg.timestampAll == true and fmt ~= nil, fmt)
    end
    ECHAT.ApplyStampAll = ApplyStampAll

    local function ApplyTimestampCVar()
        ApplyStampAll()
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
    -- ApplyBorders is DEFERRED out of the PLAYER_LOGIN execution: running it
    -- synchronously here chains into ApplyExtendedBackground, which plants the panel
    -- border's anchors in ChatFrame1's rect web WHILE Blizzard's login dock pass is
    -- still resolving layout -- that pass then reads our insecure anchors, runs
    -- tainted, and its persistent dock state poisons every later temp-whisper open
    -- (FCFManager_GetChatTarget/ GetDecoratedSenderName secret errors). The deferred
    -- tab passes (PEW + C_Timer) are the proven-clean home for this work instead.
    do
        local bordersDefer = CreateFrame("Frame")
        bordersDefer:RegisterEvent("PLAYER_ENTERING_WORLD")
        bordersDefer:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            C_Timer.After(0, function() ECHAT.ApplyBorders() end)
        end)
    end
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
    ECHAT.ApplySidebarWidth()
    ECHAT.ApplySidebarPosition()
    ECHAT.ApplyIconColor()
    ECHAT.ApplyInputPosition()
    ECHAT.ApplySidebarBackground()
    ECHAT.ApplySidebarIconScale()
    ECHAT.ApplyIconFreeMove()
    ECHAT.ApplyLockChatSize()

    -- Profile-swap refresh: re-apply all chat visuals from the (already- swapped) DB --
    -- ECHAT.DB() reads the live profile dynamically, so re-running the Apply functions
    -- pulls the new profile's settings. ApplySidebarIcons() is deliberately NOT called
    -- here -- its full ClearAllPoints/SetPoint layout chain is taint-risky (skipped at
    -- init too); icon visibility uses the same minimal SetShown block as init, and
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
        ECHAT.ApplySidebarWidth()
        ECHAT.ApplySidebarPosition()
        ECHAT.ApplyIconColor()
        ECHAT.ApplyInputPosition()
        ECHAT.ApplySidebarBackground()
        ECHAT.ApplySidebarIconScale()
        ECHAT.ApplyIconFreeMove()
        ECHAT.ApplyLockChatSize()
        ECHAT.ApplyBackground()
        ECHAT.ApplyFonts()
        if ECHAT.RefreshVisibility then ECHAT.RefreshVisibility() end
        -- The passes above can build panel chrome (borders, the tab-band
        -- extension) that did not exist when the house editor opened.
        ECHAT.ApplyPanelHost()
    end

    ---------------------------------------------------------------------------
    --  9-12. Chat positioning: OURS via the unlock element.
    ---------------------------------------------------------------------------
    --[[ Chat position is OURS (unlock element + genesis capture + anchor
    -- guard). HARD CONSTRAINTS from the failed first attempt, still binding:
    -- ChatFrame1 is NEVER reparented (Edit Mode's UpdateSystemAnchorInfo
    -- assumes a UIParent child; a reparented chat came back with NO anchors
    -- -- unmovable, unresizable) and its SetPoint is NEVER hooked. Position
    -- enforcement is ONLY the deferred ApplySystemAnchor post-hook; the Edit
    -- Mode Selection overlay is suppressed IN PLACE (alpha + mouse), never
    -- reparented -- Edit Mode still drives that region. Chat SIZE stays
    -- Blizzard's (the resize grip). ]]

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

            -- Enforce saved position when Blizzard tries to reposition; skip
            -- during unlock mode so the user can drag freely. NOT
            -- hooksecurefunc(toast, "SetPoint", ...): that form assigns
            -- toast.SetPoint = wrapper, a FIELD WRITE onto BNToastFrame's
            -- table (same hazard as the edit box in SkinEditBox). Blizzard reads that
            -- field whenever it anchors the toast, so the tainted read lands inside the
            -- Battle.net toast chain -- the same chain that opens a BN whisper and puts
            -- a SECRET target name into ChatFrame1EditBox.text. OnShow is a script hook
            -- (C-side, no field write) and fires on every toast, the only moment the
            -- position matters; the deferred call lets Blizzard finish its own
            -- anchoring first. Same shape as the FCFDock_SelectWindow hook this module
            -- already replaced for taint reasons.
            toast:HookScript("OnShow", function()
                if EUI._unlockActive then return end
                local cfg = ECHAT.DB()
                if not (cfg and cfg.toastPosition) then return end
                C_Timer.After(0, function()
                    if EUI._unlockActive then return end
                    local c = ECHAT.DB()
                    if c and c.toastPosition then ApplyToastPosition() end
                end)
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
    --  12c. Main chat: a REAL unlock element. Drag saves cfg.chatPosition;
    --       everything downstream (panels, our text, the ghost tab strip)
    --       follows ChatFrame1 through the existing numeric machinery.
    ---------------------------------------------------------------------------
    if EUI.RegisterUnlockElements then
        local MK = EUI.MakeUnlockElement
        EUI:RegisterUnlockElements({
            MK({
                key   = "ECHAT_MainChat",
                label = "Chat",
                group = "Chat",
                order = 600,
                noResize = true,
                getFrame = function() return _G.ChatFrame1 end,
                getSize  = function()
                    local cf1 = _G.ChatFrame1
                    return cf1:GetWidth(), cf1:GetHeight()
                end,
                isHidden = function() return false end,
                -- The mover places ChatFrame1 with one anchor per drag tick /
                -- nudge; our size rides a second corner (SetSize is banned on
                -- the main window), so restore it after every placement.
                onLiveMove = function()
                    if ns._KeepMainChatSizeCorner then ns._KeepMainChatSizeCorner() end
                end,
                savePos = function(_, point, relPoint, x, y)
                    local cfg = ECHAT.DB()
                    if not cfg then return end
                    cfg.chatPosition = { point = point, relPoint = relPoint or point, x = x, y = y }
                    if not EUI._unlockActive then
                        ECHAT.ApplyChatPosition()
                    end
                end,
                loadPos = function()
                    local cfg = ECHAT.DB()
                    return cfg and cfg.chatPosition or nil
                end,
                clearPos = function()
                    -- Back to wherever Blizzard's layout puts it; the next
                    -- settled sight re-captures that as the new genesis.
                    -- Saved size clears with it (back to Blizzard's size).
                    local cfg = ECHAT.DB()
                    if cfg then
                        cfg.chatPosition = nil
                        cfg.chatSize = nil
                    end
                end,
                applyPos = function() ECHAT.ApplyChatPosition() end,
            }),
        })
    end
    -- The geometry follower runs for the whole unlock session so the panel
    -- and text track the Chat mover per-frame instead of snapping after.
    -- Both session edges re-assert the saved rect from the DB: on open, so
    -- the mover measures the true (size-composed) rect even if a one-anchor
    -- placement elsewhere left the frame on its explicit size; on close, so
    -- the committed or reverted position lands composed in the same
    -- execution (the drift heal is suspended for the session and would
    -- otherwise be the first thing to notice, one tick later).
    if EUI.RegisterUnlockModeListener then
        EUI:RegisterUnlockModeListener("EllesmereUIChat", function(active)
            if ECHAT.FollowArmUnlock then ECHAT.FollowArmUnlock(active) end
            if ECHAT.ApplyChatPosition then ECHAT.ApplyChatPosition() end
        end)
    end

    ---------------------------------------------------------------------------
    --  13. Visibility system registration
    ---------------------------------------------------------------------------
    ECHAT.RefreshVisibility()
    if EUI.RegisterVisibilityUpdater then
        EUI.RegisterVisibilityUpdater(ECHAT.RefreshVisibility)
    end

    ---------------------------------------------------------------------------
    --  13b. Edit Mode chat-size migration: one-shot after login. On-delta
    --  only -- users who never resized (no cfg.chatSize) or whose store
    --  already matches see nothing. A too-early pass (layouts not yet pushed
    --  from the server) fails the writer's proof rule harmlessly and simply
    --  retries next login.
    ---------------------------------------------------------------------------
    do
        local mig = CreateFrame("Frame")
        mig:RegisterEvent("PLAYER_ENTERING_WORLD")
        mig:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
            C_Timer.After(2, function()
                if ns.EMChatSyncSize then ns.EMChatSyncSize() end
            end)
        end)
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
