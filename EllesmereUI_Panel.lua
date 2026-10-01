if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Panel.lua
--  The options panel shell: main frame, sidebar, header, tabs, content
--  area, inline search, module registration, page selection, show/hide
--  and the sidebar unlock tip. Loads right after EllesmereUI.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
-- Private namespace shared with EllesmereUI.lua (module registry, sidebar model).
local _, EUI_NS = ...

local PP                  = EllesmereUI.PP
local PanelPP             = EllesmereUI.PanelPP
local MakeFont            = EllesmereUI.MakeFont
local MakeBorder          = EllesmereUI.MakeBorder
local SolidTex            = EllesmereUI.SolidTex
local lerp                = EllesmereUI.lerp
local RegAccent           = EllesmereUI.RegAccent
local ResetRowCounters    = EllesmereUI.ResetRowCounters
local ResolveFactionTheme = EllesmereUI._ResolveFactionTheme
local ELLESMERE_GREEN     = EllesmereUI.ELLESMERE_GREEN
local BORDER_COLOR        = EllesmereUI.BORDER_COLOR
local DARK_BG             = EllesmereUI.DARK_BG
local TEXT_DIM            = EllesmereUI.TEXT_DIM
local TEXT_SECTION        = EllesmereUI.TEXT_SECTION
local CONTENT_PAD         = EllesmereUI.CONTENT_PAD
local STYLE               = EllesmereUI._STYLE
local THEME_BG_FILES      = EllesmereUI._THEME_BG_FILES
local IS_STANDALONE       = EllesmereUI._IS_STANDALONE
local MEDIA_PATH          = EllesmereUI.MEDIA_PATH
local ICONS_PATH          = EllesmereUI.ICONS_PATH
local ADDON_ROSTER        = EllesmereUI.ADDON_ROSTER
local CLASS_ART_MAP       = EllesmereUI.CLASS_ART_MAP
local playerClass         = EllesmereUI._playerClass
local modules             = EUI_NS.modules
local _widgetRefreshList  = EllesmereUI._widgetRefreshList
local IsAddonLoaded       = C_AddOns.IsAddOnLoaded

-- Sidebar nav states
local NAV_SELECTED_TEXT   = { r = STYLE.TEXT_WHITE_R, g = STYLE.TEXT_WHITE_G, b = STYLE.TEXT_WHITE_B, a = 1 }
local NAV_SELECTED_ICON_A = 1
local NAV_ENABLED_TEXT    = { r = STYLE.TEXT_WHITE_R, g = STYLE.TEXT_WHITE_G, b = STYLE.TEXT_WHITE_B, a = 0.6 }
local NAV_ENABLED_ICON_A  = 0.60
local NAV_DISABLED_TEXT   = { r = 1, g = 1, b = 1, a = 0.11 }
local NAV_DISABLED_ICON_A = 0.20
local NAV_HOVER_ENABLED_TEXT  = { r = 1, g = 1, b = 1, a = 0.86 }
local NAV_HOVER_DISABLED_TEXT = { r = 1, g = 1, b = 1, a = 0.39 }

local BG_WIDTH, BG_HEIGHT = 1500, 1154
local CLICK_W, CLICK_H    = 1300, 946
local SIDEBAR_W  = 295
local HEADER_H   = 138      -- title + desc + banner glow + dark band for tabs
local TAB_BAR_H  = 40
local FOOTER_H   = 82

local mainFrame, bgFrame, clickArea, sidebar, contentFrame
local headerFrame, tabBar, scrollFrame, scrollChild, footerFrame, contentHeaderFrame
local sidebarButtons = {}
EUI_NS.sidebarButtons = sidebarButtons
local activeModule, activePage
local _lastPagePerModule = {}
local scrollTarget = 0
local isSmoothing = false
local smoothFrame
local UpdateScrollThumb
local suppressScrollRangeChanged = false
local lastHeaderPadded = false
local skipScrollChildReanchor = false

local function ClearWidgetRefreshList()
    for i = 1, #_widgetRefreshList do _widgetRefreshList[i] = nil end
end

-- Snapshot/restore the refresh registry around off-screen widget builds (search-index
-- pre-build) so an unviewed page never leaks refresh closures into the displayed list.
function EllesmereUI._SnapshotAndClearWidgetRefreshList()
    local snap = {}
    for i = 1, #_widgetRefreshList do snap[i] = _widgetRefreshList[i] end
    ClearWidgetRefreshList()
    return snap
end
function EllesmereUI._RestoreWidgetRefreshList(snap)
    ClearWidgetRefreshList()
    for i = 1, #snap do _widgetRefreshList[i] = snap[i] end
end

-- Hide all children/regions of a frame without orphaning them
local HideAllChildren
do
    local _hideAllScratch = {}
    local function _packIntoScratch(...)
        local n = select("#", ...)
        for i = 1, n do _hideAllScratch[i] = select(i, ...) end
        return n
    end
    HideAllChildren = function(parent, keepSet)
        -- Pack children into reusable scratch table (one GetChildren call)
        local n = _packIntoScratch(parent:GetChildren())
        for i = 1, n do
            if not (keepSet and keepSet[_hideAllScratch[i]]) then _hideAllScratch[i]:Hide() end
            _hideAllScratch[i] = nil
        end
        n = _packIntoScratch(parent:GetRegions())
        for i = 1, n do
            if not (keepSet and keepSet[_hideAllScratch[i]]) then _hideAllScratch[i]:Hide() end
            _hideAllScratch[i] = nil
        end
        -- Also hide custom root frames parented to scrollFrame (bypass scroll child)
        if EllesmereUI._hideScrollFrameRoots then
            EllesmereUI._hideScrollFrameRoots()
        end
    end
end

-- OnShow callbacks -- available immediately; mainFrame hooks in when created
local _onShowCallbacks = {}
function EllesmereUI:RegisterOnShow(fn)
    _onShowCallbacks[#_onShowCallbacks + 1] = fn
end

-- OnHide callbacks -- fired when the settings panel closes
local _onHideCallbacks = {}
function EllesmereUI:RegisterOnHide(fn)
    _onHideCallbacks[#_onHideCallbacks + 1] = fn
end

-------------------------------------------------------------------------------
--  Tab helpers  (forward-declared, defined before CreateMainFrame uses them)
-------------------------------------------------------------------------------
local ClearTabs, CreateTabButton, BuildTabs, UpdateTabHighlight
local UpdateSidebarHighlight, ClearContent

-------------------------------------------------------------------------------
--  Build Main Frame
-------------------------------------------------------------------------------
local function CreateMainFrame()
    if mainFrame then return mainFrame end

    -----------------------------------------------------------------------
    --  Root frame + scaling
    -----------------------------------------------------------------------
    mainFrame = CreateFrame("Frame", "EllesmereUIFrame", UIParent)
    EllesmereUI._mainFrame = mainFrame
    mainFrame:SetSize(BG_WIDTH, BG_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetFrameLevel(100)
    mainFrame:Hide()
    mainFrame:EnableMouse(false)
    mainFrame:SetMovable(true)
    mainFrame:SetScript("OnShow", function()
        -- Recalculate pixel-perfect base scale on every open so resolution / UIParent scale changes apply
        local physW2 = (GetPhysicalScreenSize())
        local baseScale2 = GetScreenWidth() / physW2
        local userScale2 = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
        mainFrame:SetScale(baseScale2 * userScale2)
        -- Re-sync PanelPP mult for the (possibly new) scale
        if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end
        -- The mini window was dragged and then closed: open with the panel on screen.
        if EllesmereUI._panelNudge then EllesmereUI._KeepPanelOnScreen() end
        -- Panel borders are resnapped by the tab-switch ResnapBordersUnder (active page only, ~2ms);
        -- a global ResnapAllBorders here costs ~74ms and is unnecessary, since non-panel borders have their own scale and resnap triggers.
        for _, fn in ipairs(_onShowCallbacks) do fn() end
        -- Controller cursor: every open is one the player asked for (slash, button,
        -- binding, pause menu), so bring the gamepad pointer up.
        if EllesmereUI.PadNative() then EllesmereUI.RaiseGamePadCursor() end
    end)
    mainFrame:SetScript("OnHide", function()
        -- Every close path (Escape, combat, the mini window's X) unfolds a collapsed
        -- window, so the next open is always the full panel. A parent hiding it
        -- (Alt-Z, a cinematic) leaves it shown: it stays folded and comes back as it was.
        if EllesmereUI._panelCollapsed and not mainFrame:IsShown() then
            EllesmereUI._SetPanelCollapsed(false)
        end
        -- Close the sidebar sync popup so it never lingers after the window is dismissed.
        EllesmereUI.CloseSyncPopup()
        if _onHideCallbacks then
            for _, fn in ipairs(_onHideCallbacks) do fn() end
        end
        -- Built pages stay cached for the session: frames can never be freed, so
        -- dropping them on close would only turn every revisit into a rebuild.
    end)

    -- Pixel-perfect scale: make 1 WoW unit = 1 screen pixel
    local physW = (GetPhysicalScreenSize())
    local baseScale = GetScreenWidth() / physW
    local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
    mainFrame:SetScale(baseScale * userScale)
    -- Initialize PanelPP mult for the saved user scale
    if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end

    EllesmereUI.RegisterEscapeClose(mainFrame)

    -- Panel body: every surface of the window hangs under it (parent panel-owned
    -- frames to EllesmereUI._panelBody, not to mainFrame), so collapsing hides the
    -- whole window while mainFrame -- the open options session -- stays shown.
    local body = CreateFrame("Frame", nil, mainFrame)
    body:SetAllPoints(mainFrame)
    body:SetFrameLevel(mainFrame:GetFrameLevel())
    EllesmereUI._panelBody = body

    -----------------------------------------------------------------------
    --  Background texture  (dual-layer crossfade for smooth transitions)
    -----------------------------------------------------------------------
    bgFrame = CreateFrame("Frame", nil, body)
    bgFrame:SetAllPoints(mainFrame)
    bgFrame:SetFrameLevel(mainFrame:GetFrameLevel())
    bgFrame:EnableMouse(false)
    bgFrame:SetAlpha(1)  -- mainFrame controls overall window opacity

    -- Permanent base background: backdrop shadow (always visible behind everything)
    local bgBase = bgFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgBase:SetTexture(MEDIA_PATH .. "backgrounds\\eui-bg.png")
    bgBase:SetAllPoints()
    bgBase:SetAlpha(1)

    -- Two crossfade layers (A = current, B = incoming). Only the active layer holds a
    -- texture; the idle one is cleared after each transition to free GPU memory.
    local bgA = bgFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
    bgA:SetAllPoints()
    bgA:SetAlpha(1)

    local bgB = bgFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgB:SetAllPoints()
    bgB:SetAlpha(0)

    -- Track which layer is "front" (the one fading in)
    local bgFront, bgBack = bgA, bgB
    local bgFadeProgress = 1  -- 1 = fully transitioned (front is fully visible)
    local BG_FADE_DURATION = 0.5

    -- Title-bar theme boxes (the collapse button's box and the collapsed mini
    -- window): one table, so they cost this function a single local. See tbox.Paint.
    local tbox = {}

    -- Accent hue via desaturate + vertex tint: base images are teal, so desaturating
    -- removes the hue and vertex color re-tints to the chosen accent. Horde/Alliance
    -- have dedicated background images and are used as-is (never desaturated/tinted).
    -- TintColor returns nil for those, else the vertex colour of the desaturated art.
    function tbox.TintColor(theme, r, g, b)
        if theme == "EllesmereUI" or theme == "EllesmereUI Original" or theme == "EllesmereUI Forever"
           or theme == "Horde" or theme == "Alliance" or theme == "Midnight" or theme == "Dark"
           or theme == "Pixels" then
            -- These themes use their native bg as-is (or no bg for Dark)
            return nil
        end
        local minBright = 1.10
        local maxBright = 1.60
        local floor     = 0.08
        local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        local darkFactor = 1 - lum
        local bright = minBright + darkFactor * (maxBright - minBright)
        return math.min(floor + r * bright, 1), math.min(floor + g * bright, 1), math.min(floor + b * bright, 1)
    end
    local function ApplyBgTintToLayer(layer, theme, r, g, b)
        local fr, fg, fb = tbox.TintColor(theme, r, g, b)
        if fr then
            layer:SetDesaturated(true)
            layer:SetVertexColor(fr, fg, fb, 1)
        else
            layer:SetDesaturated(false)
            layer:SetVertexColor(1, 1, 1, 1)
        end
    end

    -- A colour picked off the art (r, g, b), as the art shows it under the theme's tint.
    function tbox.Tinted(theme, tr, tg, tb, r, g, b)
        local fr, fg, fb = tbox.TintColor(theme, tr, tg, tb)
        if not fr then return r, g, b end
        local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return lum * fr, lum * fg, lum * fb
    end

    -- Active theme and its colour (the tint input), for painting outside a theme change.
    function tbox.Theme()
        local theme = ResolveFactionTheme(EllesmereUIDB and EllesmereUIDB.activeTheme or EllesmereUI.DEFAULT_THEME)
        return theme, EllesmereUI.ResolveThemeColor(theme)
    end

    -- Glyph cuts of EllesmereUI.RESIZE_ICON (texcoords), plus an optical nudge
    -- (x, y canvas units; y down): the expand arrow 1 toward its tail, the
    -- collapse arrow 1 right and 1 down. Field 7: size change from the art's
    -- glyph size (the collapse arrow 1 smaller).
    tbox.GLYPH = {
        collapse = { 5 / 30, 15 / 30, 16 / 30, 26 / 30, 1, 1, -1 }, -- down-left
        expand   = { 17 / 30, 27 / 30, 4 / 30, 14 / 30, -1, 1 },   -- up-right
    }

    -- Canvas distance from the painted close box to its copy (the collapse box).
    -- A multiple of 4 keeps the copy on the art's pixel grid at the 75% and 125%
    -- panel scales as well as at 100/150/200%, so its border matches the original.
    tbox.DX = 48

    -- A theme box is a copy of the close box painted into the theme art
    -- (EllesmereUI.THEME_CLOSE_BOX), cut from the same art: its border as four
    -- strips (top and bottom carry the corners; the open centre shows the art
    -- below), dx canvas units left of the painted box, plus an arrow glyph in the
    -- X's colours. owner holds the textures; canvas point (ox, oy) sits on
    -- anchor's TOPLEFT. With no glyph it is a hover glow instead: the border
    -- ring alone, additive, in owner's highlight layer.
    function tbox.New(owner, anchor, ox, oy, dx, glyph)
        local set = { anchor = anchor, ox = ox, oy = oy, dx = dx, glyph = glyph, alpha = 1, s = {} }
        for i = 1, 4 do
            local t = owner:CreateTexture(nil, glyph and "BACKGROUND" or "HIGHLIGHT")
            if not glyph then t:SetBlendMode("ADD") end
            set.s[i] = t
        end
        if glyph then
            local tc = tbox.GLYPH[glyph]
            local icon = EllesmereUI.RESIZE_ICON
            set.shadow = owner:CreateTexture(nil, "BORDER")
            set.base = owner:CreateTexture(nil, "BORDER")
            set.acc = owner:CreateTexture(nil, "BORDER")
            set.shadow:SetTexture(icon)
            set.base:SetTexture(icon)
            set.acc:SetTexture(icon)
            set.shadow:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            set.base:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            set.acc:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            set.shadow:SetVertexColor(0, 0, 0, 1)
            local acc = set.acc
            RegAccent({ type = "callback", fn = function(r, g, b)
                acc:SetVertexColor(r, g, b, acc:GetAlpha())
            end })
        end
        return set
    end

    -- Draw order of a glyph set: strips at BACKGROUND stripSub, glyph pieces
    -- (rim, colour, accent) at BORDER glyphSub, +2, +4.
    function tbox.Layer(set, stripSub, glyphSub)
        for i = 1, 4 do set.s[i]:SetDrawLayer("BACKGROUND", stripSub) end
        set.shadow:SetDrawLayer("BORDER", glyphSub)
        set.base:SetDrawLayer("BORDER", glyphSub + 2)
        set.acc:SetDrawLayer("BORDER", glyphSub + 4)
    end

    -- Show a set at alpha a (0 hides it). Texture alpha and vertex alpha are one
    -- channel, so every repaint ends here to put the set's alpha back.
    function tbox.Alpha(set, a)
        set.alpha = a
        local spec = set.spec
        local shown = a > 0 and spec ~= nil
        for i = 1, 4 do
            local t = set.s[i]
            t:SetShown(shown)
            t:SetAlpha(a)
        end
        if set.base then
            set.base:SetShown(shown)
            set.base:SetAlpha(a)
            local sh = shown and spec.sh or 0
            set.shadow:SetShown(sh > 0)
            set.shadow:SetAlpha(sh * a)
            local acc = shown and spec.acc or 0
            set.acc:SetShown(acc > 0)
            set.acc:SetAlpha(acc * a)
        end
    end

    -- Paint a set from the theme's art (tr, tg, tb = the theme colour, the tint input).
    function tbox.Paint(set, theme, tr, tg, tb)
        local file = THEME_BG_FILES[theme] or THEME_BG_FILES["EllesmereUI"]
        local spec = EllesmereUI.THEME_CLOSE_BOX[file]
        set.spec = spec
        if spec then
            local path = MEDIA_PATH .. file
            -- A copy takes the whole tight rect at a 6 unit depth (halo, border and
            -- inner line, clear of the X); a glow takes just the border line, so the
            -- flat fill and the corners outside the rounded border never light up.
            local x, y, w, h, S = spec.x, spec.y, spec.w, spec.h, 6
            if not set.base then x, y, w, h, S = spec.bx, spec.by, spec.bw, spec.bh, spec.bd end
            local px, py = x - set.dx - set.ox, y - set.oy
            for i = 1, 4 do
                local sx, sy, sw, sh = 0, 0, w, S                          -- top
                if i == 2 then sy = h - S                                   -- bottom
                elseif i == 3 then sy, sw, sh = S, S, h - 2 * S             -- left
                elseif i == 4 then sx, sy, sw, sh = w - S, S, S, h - 2 * S  -- right
                end
                local t = set.s[i]
                t:SetTexture(path)
                t:SetTexCoord((x + sx) / BG_WIDTH, (x + sx + sw) / BG_WIDTH, (y + sy) / BG_HEIGHT, (y + sy + sh) / BG_HEIGHT)
                t:SetSize(sw, sh)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", set.anchor, "TOPLEFT", px + sx, -(py + sy))
                ApplyBgTintToLayer(t, theme, tr, tg, tb)
            end
            if set.base then
                local tc = tbox.GLYPH[set.glyph]
                local cx, cy = spec.gx - set.dx + tc[5] - set.ox, spec.gy + tc[6] - set.oy
                local gs = (spec.gs or 16) + (tc[7] or 0)   -- the rim is 2 units wider than the glyph
                set.shadow:SetSize(gs + 2, gs + 2)
                set.base:SetSize(gs, gs)
                set.acc:SetSize(gs, gs)
                set.shadow:ClearAllPoints()
                set.shadow:SetPoint("CENTER", set.anchor, "TOPLEFT", cx, -cy)
                set.base:ClearAllPoints()
                set.base:SetPoint("CENTER", set.anchor, "TOPLEFT", cx, -cy)
                set.acc:ClearAllPoints()
                set.acc:SetPoint("CENTER", set.anchor, "TOPLEFT", cx, -cy)
                local r, g, b = tbox.Tinted(theme, tr, tg, tb, spec.r, spec.g, spec.b)
                set.base:SetVertexColor(r, g, b, 1)
                set.acc:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
            end
        end
        tbox.Alpha(set, set.alpha)
    end

    -- Hover glow and tooltip for a title-bar box's hit area: the box border again,
    -- additive, shown by the button's highlight layer and brighter while pressed.
    -- Painted on enter from the art in use, so it costs nothing until hovered.
    function tbox.Hover(btn, anchor, ox, oy, dx, tip)
        local glow = tbox.New(btn, anchor, ox, oy, dx)
        btn:SetScript("OnEnter", function(self)
            glow.alpha = 0.5
            tbox.Paint(glow, tbox.Theme())
            if tip then EllesmereUI.ShowWidgetTooltip(self, tip) end
        end)
        btn:SetScript("OnLeave", function()
            if tip then EllesmereUI.HideWidgetTooltip() end
        end)
        btn:SetScript("OnMouseDown", function() tbox.Alpha(glow, 0.85) end)
        btn:SetScript("OnMouseUp", function() tbox.Alpha(glow, 0.5) end)
    end

    -- The collapse box: a front/back pair on bgFrame that swaps and crossfades
    -- with the theme art it is cut from (ApplyThemeBG, bgFadeTicker).
    tbox.front = tbox.New(bgFrame, bgFrame, 0, 0, tbox.DX, "collapse")
    tbox.back = tbox.New(bgFrame, bgFrame, 0, 0, tbox.DX, "collapse")
    tbox.Layer(tbox.front, 4, 1)
    tbox.Layer(tbox.back, 3, 0)

    -- Background crossfade ticker: old stays solid, new fades in on top with the same
    -- ease-in-out curve as the accent transition, so both animations track visually.
    local bgFadeTicker = CreateFrame("Frame", nil, bgFrame)
    bgFadeTicker:Hide()
    bgFadeTicker:SetScript("OnUpdate", function(self, elapsed)
        bgFadeProgress = bgFadeProgress + elapsed / BG_FADE_DURATION
        -- The accent overlay sits above both layers, so it is driven here only while
        -- a theme that has one is entering (dir 1) or leaving (dir -1).
        local ov = bgFrame._accentOverlayDir and bgFrame._accentOverlay
        if bgFadeProgress >= 1 then
            bgFadeProgress = 1
            bgFront:SetAlpha(1)
            -- The collapse box pair is not occluded (its rect differs per art), so
            -- the outgoing one hides.
            tbox.Alpha(tbox.front, 1)
            tbox.Alpha(tbox.back, 0)
            -- bgBack stays solid behind bgFront (occluded, zero cost). NEVER clear it
            -- here (single-frame flash); the next ApplyThemeBG replaces its texture.
            if ov then
                if bgFrame._accentOverlayDir > 0 then
                    ov:SetAlpha(1)
                else
                    -- Faded out over the new theme: empty it so it holds no texture.
                    ov:Hide()
                    ov:SetTexture(nil)
                    bgFrame._accentOverlayPath = nil
                end
                bgFrame._accentOverlayDir = nil
            end
            self:Hide()
        else
            -- Ease-in-out: slow start, fast middle, slow end
            local t = bgFadeProgress
            t = t < 0.5 and (2 * t * t) or (1 - (-2 * t + 2) * (-2 * t + 2) / 2)
            bgBack:SetAlpha(1)
            bgFront:SetAlpha(t)
            tbox.Alpha(tbox.front, t)
            -- The outgoing box stays near solid until late, like bgBack: a plain
            -- 1 - t leaves both boxes part-transparent mid-fade and they dim.
            tbox.Alpha(tbox.back, 1 - t * t * t)
            if ov then
                local from = bgFrame._accentOverlayFrom
                if bgFrame._accentOverlayDir > 0 then
                    ov:SetAlpha(from + (1 - from) * t)
                else
                    ov:SetAlpha(from * (1 - t))
                end
            end
        end
    end)

    -- Accent overlay (EllesmereUI.THEME_ACCENT_OVERLAYS): one texture above the
    -- crossfade pair (BACKGROUND 2), on our own bgFrame, tinted with the live UI
    -- accent through a single RegAccent entry made when it is created. It is built
    -- on the first apply of a theme that has one; a theme without one fades it out
    -- and empties it, so it costs nothing while unused. faded = false (the panel's
    -- first build) shows it at once instead of fading it in.
    local function ApplyThemeAccentOverlay(theme, faded)
        local spec = EllesmereUI.THEME_ACCENT_OVERLAYS[theme]
        local ov = bgFrame._accentOverlay
        if not spec then
            if ov and ov:IsShown() then
                bgFrame._accentOverlayFrom = ov:GetAlpha()
                bgFrame._accentOverlayDir = -1
            end
            return
        end
        if not ov then
            ov = bgFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
            bgFrame._accentOverlay = ov
            ov:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
            -- A callback, not a "vertex" entry: on a texture the vertex alpha IS its
            -- alpha, and the vertex entry writes 1, which would stomp the crossfade
            -- (every theme pick re-applies the accent right after starting it).
            RegAccent({ type = "callback", fn = function(r, g, b)
                ov:SetVertexColor(r, g, b, ov:GetAlpha())
            end })
        end
        local path = MEDIA_PATH .. spec.file
        -- A re-pick (or a return mid fade-out) keeps the art and fades on from its alpha.
        if not (ov:IsShown() and bgFrame._accentOverlayPath == path) then
            ov:ClearAllPoints()
            ov:SetPoint("TOPLEFT", bgFrame, "TOPLEFT", spec.x, -spec.y)
            ov:SetSize(spec.w, spec.h)
            ov:SetTexture(path)
            bgFrame._accentOverlayPath = path
            ov:SetAlpha(0)
            ov:Show()
        end
        if faded then
            bgFrame._accentOverlayFrom = ov:GetAlpha()
            bgFrame._accentOverlayDir = 1
        else
            ov:SetAlpha(1)
            bgFrame._accentOverlayDir = nil
        end
    end

    --- Apply the full theme: crossfade to new background image + tint
    local function ApplyThemeBG(theme, r, g, b)
        theme = ResolveFactionTheme(theme)
        local file = THEME_BG_FILES[theme] or THEME_BG_FILES["EllesmereUI"]
        local newPath = MEDIA_PATH .. file

        -- Swap roles: old front becomes back, new incoming becomes front
        bgBack, bgFront = bgFront, bgBack

        -- New front layer gets the target texture + tint on top; this SetTexture is also
        -- the lazy cleanup of the previous transition's idle layer.
        bgFront:SetTexture(newPath)
        ApplyBgTintToLayer(bgFront, theme, r, g, b)
        bgFront:SetDrawLayer("BACKGROUND", 1)
        bgFront:SetAlpha(0)

        -- Old layer stays fully solid underneath
        bgBack:SetDrawLayer("BACKGROUND", 0)
        bgBack:SetAlpha(1)

        -- The collapse box is cut from the same art: its pair swaps the same way.
        tbox.front, tbox.back = tbox.back, tbox.front
        tbox.Layer(tbox.front, 4, 1)
        tbox.Layer(tbox.back, 3, 0)
        tbox.front.alpha = 0
        tbox.Paint(tbox.front, theme, r, g, b)
        tbox.Alpha(tbox.back, 1)
        -- A collapsed window shows the mini instead: it takes the new art at once.
        if EllesmereUI._panelCollapsed then tbox.SkinMini(theme, r, g, b) end

        -- Start crossfade (the accent overlay, if either theme has one, rides it)
        bgFadeProgress = 0
        ApplyThemeAccentOverlay(theme, true)
        bgFadeTicker:Show()

        -- The sidebar opacity slider's orientation follows the theme.
        if EllesmereUI._layoutOpacitySlider then EllesmereUI._layoutOpacitySlider() end
    end

    -- For tint-only updates (Custom Color picker dragging), update the front layer directly
    local function ApplyBgTint(r, g, b)
        local theme = ResolveFactionTheme((EllesmereUIDB or {}).activeTheme or EllesmereUI.DEFAULT_THEME)
        ApplyBgTintToLayer(bgFront, theme, r, g, b)
        tbox.Paint(tbox.front, theme, r, g, b)
        if EllesmereUI._panelCollapsed then tbox.SkinMini(theme, r, g, b) end
    end

    -- Apply initial theme at creation (no crossfade, just set correct texture + tint)
    -- Resolve theme color directly -- ELLESMERE_GREEN is the UI accent which may differ
    local _initTheme = ResolveFactionTheme((EllesmereUIDB or {}).activeTheme or EllesmereUI.DEFAULT_THEME)
    local _initFile = THEME_BG_FILES[_initTheme] or THEME_BG_FILES["EllesmereUI"]
    local _initR, _initG, _initB = EllesmereUI.ResolveThemeColor(_initTheme)
    bgA:SetTexture(MEDIA_PATH .. _initFile)
    ApplyBgTintToLayer(bgA, _initTheme, _initR, _initG, _initB)
    tbox.Paint(tbox.front, _initTheme, _initR, _initG, _initB)
    ApplyThemeAccentOverlay(_initTheme, false)
    EllesmereUI._bgTexture = bgA
    EllesmereUI._applyBgTint = ApplyBgTint
    EllesmereUI._applyThemeBG = ApplyThemeBG

    -----------------------------------------------------------------------
    --  Click area  (1300x946, centred)
    -----------------------------------------------------------------------
    clickArea = CreateFrame("Frame", "EllesmereUIClickArea", body)
    EllesmereUI._clickArea = clickArea
    clickArea:SetSize(CLICK_W, CLICK_H)
    clickArea:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    clickArea:SetFrameLevel(mainFrame:GetFrameLevel() + 1)
    clickArea:EnableMouse(true)
    clickArea:SetMovable(true)
    clickArea:RegisterForDrag("LeftButton")
    -- No SetClampedToScreen: the whole window moves as one and drags freely off any edge.
    clickArea:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
    clickArea:SetScript("OnDragStop",  function() mainFrame:StopMovingOrSizing() end)
    -- Controller cursor: the drag surface is not a stop; its children are.
    EllesmereUI.PadHint(clickArea, "nodepass")

    -----------------------------------------------------------------------
    --  Close button  (invisible hit area over background X graphic)
    -----------------------------------------------------------------------
    local closeBtn = CreateFrame("Button", nil, clickArea)
    closeBtn:SetSize(40, 40)
    closeBtn:SetPoint("TOPRIGHT", clickArea, "TOPRIGHT", -14, -11)
    closeBtn:SetFrameLevel(clickArea:GetFrameLevel() + 20)
    closeBtn:SetScript("OnClick", function() EllesmereUI:Hide() end)
    tbox.Hover(closeBtn, bgFrame, 0, 0, 0)
    -- Controller cursor: its cancel press closes the window through this button.
    if EllesmereUI.PadCP() then mainFrame.CloseButton = closeBtn end

    -----------------------------------------------------------------------
    --  Collapse button  (hit area over tbox.front/back, left of the close X)
    --  and the mini window it folds the panel to
    -----------------------------------------------------------------------
    do
        local collapseBtn = CreateFrame("Button", nil, clickArea)
        collapseBtn:SetSize(40, 40)
        collapseBtn:SetPoint("TOPRIGHT", clickArea, "TOPRIGHT", -(tbox.DX + 14), -11)
        collapseBtn:SetFrameLevel(clickArea:GetFrameLevel() + 20)
        collapseBtn:SetScript("OnClick", function() EllesmereUI._SetPanelCollapsed(true) end)
        tbox.Hover(collapseBtn, bgFrame, 0, 0, tbox.DX, EllesmereUI.L("Collapse"))
    end

    -- Built on the first collapse. Every piece is a rect of art the panel already
    -- has loaded, drawn exactly where it sits on the panel, so nothing moves under
    -- the cursor: the bar is the panel's own top-right corner (its painted close
    -- box included) with its top rows flipped under it as the bottom edge, the
    -- expand box lands on the collapse box, and the badge is the painted logo
    -- emblem cut to a circle. No events and no OnUpdate.
    function tbox.BuildMini()
        local MX, MY = 1206, 98   -- canvas point of the mini window's top-left
        local W, H = 197, 76
        local MASK = MEDIA_PATH .. "portraits\\circle_mask.tga"
        local mini = CreateFrame("Frame", nil, mainFrame)
        mini:Hide()
        mini:SetSize(W, H)
        mini:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", MX, -MY)
        mini:SetFrameLevel(mainFrame:GetFrameLevel() + 2)
        -- Composed as one image before the panel opacity applies, so at reduced
        -- opacity the stacked pieces (bar, ring, badge) never show through each other.
        mini:SetFlattensRenderLayers(true)
        mini:EnableMouse(true)
        mini:RegisterForDrag("LeftButton")
        mini:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
        mini:SetScript("OnDragStop", function()
            mainFrame:StopMovingOrSizing()
            EllesmereUI._panelNudge = true
        end)
        EllesmereUI._panelMini = mini

        -- Shadow: the panel shadow around the same corner (rows 24-135) and those
        -- rows flipped below, symmetric about the bar's middle; the cut end fades.
        local shadowFile = MEDIA_PATH .. "backgrounds\\eui-bg.png"
        local fadeFrom, fadeTo = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1)
        for half = 0, 1 do
            for piece = 0, 1 do
                local x0 = (piece == 0) and 1244 or 1314
                local x1 = (piece == 0) and 1314 or 1480
                local top, bot = 24 / BG_HEIGHT, 136 / BG_HEIGHT
                if half == 1 then top, bot = bot, top end
                local t = mini:CreateTexture(nil, "BACKGROUND", nil, -8)
                t:SetTexture(shadowFile)
                t:SetTexCoord(x0 / BG_WIDTH, x1 / BG_WIDTH, top, bot)
                t:SetSize(x1 - x0, 112)
                t:SetPoint("TOPLEFT", mini, "TOPLEFT", x0 - MX, (half == 0) and 74 or -38)
                if piece == 0 then t:SetGradient("HORIZONTAL", fadeFrom, fadeTo) end
            end
        end

        -- Bar: canvas 1244-1403 x 101-157, then rows 101-113 flipped as its bottom edge.
        local barTop = mini:CreateTexture(nil, "BACKGROUND", nil, 0)
        barTop:SetSize(159, 57)
        barTop:SetPoint("TOPLEFT", mini, "TOPLEFT", 1244 - MX, -(101 - MY))
        barTop:SetTexCoord(1244 / BG_WIDTH, 1403 / BG_WIDTH, 101 / BG_HEIGHT, 158 / BG_HEIGHT)
        local barCap = mini:CreateTexture(nil, "BACKGROUND", nil, 0)
        barCap:SetSize(159, 13)
        barCap:SetPoint("TOPLEFT", mini, "TOPLEFT", 1244 - MX, -(158 - MY))
        barCap:SetTexCoord(1244 / BG_WIDTH, 1403 / BG_WIDTH, 114 / BG_HEIGHT, 101 / BG_HEIGHT)
        local barOv = mini:CreateTexture(nil, "BACKGROUND", nil, 1)

        -- Expand box and its hit areas (the close X is the painted one in the bar).
        local expandBox = tbox.New(mini, mini, MX, MY, tbox.DX, "expand")
        tbox.Layer(expandBox, 2, 0)
        local expandBtn = CreateFrame("Button", nil, mini)
        expandBtn:SetSize(40, 40)
        expandBtn:SetPoint("TOPLEFT", mini, "TOPLEFT", (1346 - tbox.DX) - MX, -(115 - MY))
        expandBtn:SetFrameLevel(mini:GetFrameLevel() + 5)
        expandBtn:SetScript("OnClick", function() EllesmereUI._SetPanelCollapsed(false) end)
        tbox.Hover(expandBtn, mini, MX, MY, tbox.DX, EllesmereUI.L("Expand"))
        local miniClose = CreateFrame("Button", nil, mini)
        miniClose:SetSize(40, 40)
        miniClose:SetPoint("TOPLEFT", mini, "TOPLEFT", 1346 - MX, -(115 - MY))
        miniClose:SetFrameLevel(mini:GetFrameLevel() + 5)
        miniClose:SetScript("OnClick", function() EllesmereUI:Hide() end)
        tbox.Hover(miniClose, mini, MX, MY, 0)

        -- Badge: a thin ring (a disc 2 units wider behind it) and the emblem square.
        local ring = mini:CreateTexture(nil, "ARTWORK", nil, 0)
        ring:SetSize(H + 4, H + 4)
        ring:SetPoint("CENTER", mini, "TOPLEFT", H / 2, -H / 2)
        local ringMask = mini:CreateMaskTexture()
        ringMask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ringMask:SetSize((H + 4) * 128 / 104, (H + 4) * 128 / 104)   -- mask circle = 104/128
        ringMask:SetPoint("CENTER", ring, "CENTER")
        ring:AddMaskTexture(ringMask)
        local badge = mini:CreateTexture(nil, "ARTWORK", nil, 1)
        badge:SetSize(H, H)
        badge:SetPoint("TOPLEFT", mini, "TOPLEFT", 0, 0)
        local badgeOv = mini:CreateTexture(nil, "ARTWORK", nil, 2)
        local badgeMask = mini:CreateMaskTexture()
        badgeMask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        badgeMask:SetSize(H * 128 / 104, H * 128 / 104)
        badgeMask:SetPoint("CENTER", badge, "CENTER")
        badge:AddMaskTexture(badgeMask)
        badgeOv:AddMaskTexture(badgeMask)

        -- A theme's accent overlay (EllesmereUI.THEME_ACCENT_OVERLAYS) cut to the
        -- canvas rect x0,y0 - x1,y1 with canvas point (ax, ay) on the mini's
        -- TOPLEFT; hidden when the theme has none or the rect misses it.
        local function CutOverlay(tex, ov, x0, y0, x1, y1, ax, ay)
            if ov then
                x0, y0 = math.max(x0, ov.x), math.max(y0, ov.y)
                x1, y1 = math.min(x1, ov.x + ov.w), math.min(y1, ov.y + ov.h)
            end
            if not ov or x1 <= x0 or y1 <= y0 then tex:Hide(); return end
            tex:SetTexture(MEDIA_PATH .. ov.file)
            tex:SetTexCoord((x0 - ov.x) / ov.w, (x1 - ov.x) / ov.w, (y0 - ov.y) / ov.h, (y1 - ov.y) / ov.h)
            tex:SetSize(x1 - x0, y1 - y0)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", mini, "TOPLEFT", x0 - ax, -(y0 - ay))
            tex:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
            tex:Show()
        end
        RegAccent({ type = "callback", fn = function(r, g, b)
            barOv:SetVertexColor(r, g, b, 1)
            badgeOv:SetVertexColor(r, g, b, 1)
        end })

        -- Re-skinned on each collapse (and on a theme change while collapsed).
        function tbox.SkinMini(theme, tr, tg, tb)
            local file = THEME_BG_FILES[theme] or THEME_BG_FILES["EllesmereUI"]
            local spec = EllesmereUI.THEME_CLOSE_BOX[file] or EllesmereUI.THEME_CLOSE_BOX[THEME_BG_FILES["EllesmereUI"]]
            local path = MEDIA_PATH .. file
            barTop:SetTexture(path)
            ApplyBgTintToLayer(barTop, theme, tr, tg, tb)
            barCap:SetTexture(path)
            ApplyBgTintToLayer(barCap, theme, tr, tg, tb)
            local ex, ey = spec.ex, spec.ey
            badge:SetTexture(path)
            badge:SetTexCoord(ex / BG_WIDTH, (ex + H) / BG_WIDTH, ey / BG_HEIGHT, (ey + H) / BG_HEIGHT)
            ApplyBgTintToLayer(badge, theme, tr, tg, tb)
            local rr, rg, rb = tbox.Tinted(theme, tr, tg, tb, spec.rr, spec.rg, spec.rb)
            ring:SetColorTexture(rr, rg, rb, 1)
            local ov = EllesmereUI.THEME_ACCENT_OVERLAYS[theme]
            CutOverlay(barOv, ov, 1244, 101, 1403, 158, MX, MY)
            CutOverlay(badgeOv, ov, ex, ey, ex + H, ey + H, ex, ey)
            tbox.Paint(expandBox, theme, tr, tg, tb)
        end
        return mini
    end

    -- Fold the window to the mini window (on) or back. mainFrame stays shown, so
    -- the options session goes on: no show/hide callback runs, and previews and
    -- editing sessions keep going. Popups that close on an outside click are
    -- closed by the click itself; the rest close here, and panel-owned surfaces
    -- parented outside the body follow through EllesmereUI:RegisterOnCollapse.
    function EllesmereUI._SetPanelCollapsed(on)
        local mini = EllesmereUI._panelMini
        local hooks = EllesmereUI._onCollapseCallbacks
        EllesmereUI.HideWidgetTooltip(true)
        if on then
            if EllesmereUI._panelCollapsed or not mainFrame:IsShown() then return end
            EllesmereUI._panelCollapsed = true
            EllesmereUI.CloseSyncPopup()
            -- Name/icon popups sit on UIParent with no click-off (the panel's own
            -- OnHide closes them for the same reason).
            if EllesmereUI._specOvNamePopup then EllesmereUI._specOvNamePopup:Hide() end
            local cond = EllesmereUI._CondOv
            if cond and cond._namePopup then cond._namePopup:Hide() end
            body:Hide()
            mini = mini or tbox.BuildMini()
            tbox.SkinMini(tbox.Theme())
            mini:Show()
            for i = 1, #hooks do hooks[i](true) end
        elseif EllesmereUI._panelCollapsed then
            EllesmereUI._panelCollapsed = nil
            mini:Hide()
            body:Show()
            -- Unfolded by a close (mainFrame's OnHide): the OnHide callbacks take it
            -- from here, and a deferred page rebuild waits for the next open.
            if not mainFrame:IsShown() then return end
            -- Dropped somewhere else: keep the unfolded panel on screen.
            if EllesmereUI._panelNudge then EllesmereUI._KeepPanelOnScreen() end
            -- Pages are only ever built on screen (RefreshPage defers while folded).
            if EllesmereUI._pendingForceRefresh then
                EllesmereUI._pendingForceRefresh = nil
                EllesmereUI:RefreshPage(true)
            end
            for i = 1, #hooks do hooks[i](false) end
        end
    end

    -- Shift the window so the panel itself (the click area, not the art's shadow
    -- margin) is on screen; a panel taller or wider than the screen keeps its top
    -- left corner. Runs once after the mini window was dragged.
    function EllesmereUI._KeepPanelOnScreen()
        EllesmereUI._panelNudge = nil
        local l, r, t, b = clickArea:GetLeft(), clickArea:GetRight(), clickArea:GetTop(), clickArea:GetBottom()
        local ml, mb = mainFrame:GetLeft(), mainFrame:GetBottom()
        if not (l and r and t and b and ml and mb) then return end
        local isv = issecretvalue
        if isv and (isv(l) or isv(r) or isv(t) or isv(b) or isv(ml) or isv(mb)) then return end
        local s = UIParent:GetEffectiveScale() / mainFrame:GetEffectiveScale()
        local sw, sh = UIParent:GetWidth() * s, UIParent:GetHeight() * s
        local dx, dy = 0, 0
        if r > sw then dx = sw - r end
        if l + dx < 0 then dx = -l end
        if b < 0 then dy = -b end
        if t + dy > sh then dy = sh - t end
        if dx ~= 0 or dy ~= 0 then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", ml + dx, mb + dy)
        end
    end

    -----------------------------------------------------------------------
    --  Sidebar
    -----------------------------------------------------------------------
    sidebar = CreateFrame("Frame", nil, clickArea)
    sidebar:SetSize(SIDEBAR_W, CLICK_H)
    sidebar:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 0, 0)
    sidebar:SetFrameLevel(clickArea:GetFrameLevel() + 2)
    EllesmereUI._sidebar = sidebar

    -- Nav buttons -- start below the logo area with proper spacing
    local NAV_TOP     = -114   -- distance from sidebar top to first nav item
    local NAV_ROW_H   = 40    -- height per nav row (Unlock / Global / Patch Notes / Profiles)
    local NAV_ICON_W  = 46    -- exact pixel width
    local NAV_ICON_H  = 31    -- exact pixel height
    local NAV_LEFT    = 20    -- left padding for icon
    local NAV_TXT_GAP = 10    -- gap between icon and label

    -- Helper: create a 1px horizontal glow line on a sidebar button (TOP or BOTTOM edge)
    local function MakeNavEdgeLine(btn, edge)
        local g = btn:CreateTexture(nil, "BORDER")
        g:SetHeight(1)
        PanelPP.Point(g, edge .. "LEFT", btn, edge .. "LEFT", 0, 0)
        PanelPP.Point(g, edge .. "RIGHT", btn, edge .. "RIGHT", 0, 0)
        g:SetColorTexture(0.7, 0.7, 0.7, 1)
        g:SetGradient("HORIZONTAL", CreateColor(0.7, 0.7, 0.7, 0.5), CreateColor(0.7, 0.7, 0.7, 0))
        g:Hide()
        return g
    end

    -- Horizontal gradient glow on a sidebar button, anchored top+bottom so it scales
    -- with the row height (group headers and child rows differ).
    local function MakeNavGradient(btn, r, g, b, startA)
        local tex = btn:CreateTexture(nil, "BACKGROUND")
        tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        tex:SetColorTexture(r, g, b, 1)
        tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, startA), CreateColor(r, g, b, 0))
        tex:Hide()
        return tex
    end

    -- Helper: attach the shared decoration set to a sidebar nav button
    -- (active indicator, selection glow, top/bottom edge lines, hover glow, hover indicator)
    local function DecorateSidebarButton(btn)
        local EG = ELLESMERE_GREEN
        btn._indicator = SolidTex(btn, "ARTWORK", EG.r, EG.g, EG.b, 1)
        btn._indicator:SetWidth(3)
        btn._indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 0)
        btn._indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -1, 0)
        btn._indicator:Hide()
        RegAccent({ type="solid", obj=btn._indicator, a=1 })

        btn._glow    = MakeNavGradient(btn, EG.r, EG.g, EG.b, 0.15)
        RegAccent({ type="gradient", obj=btn._glow, startA=0.15 })
        btn._glowTop = MakeNavEdgeLine(btn, "TOP")
        btn._glowBot = MakeNavEdgeLine(btn, "BOTTOM")

        local hR, hG, hB = 0.85, 0.95, 0.90
        btn._hoverGlow = MakeNavGradient(btn, hR, hG, hB, 0.03)
        btn._hoverIndicator = SolidTex(btn, "ARTWORK", hR, hG, hB, 0.25)
        btn._hoverIndicator:SetWidth(3)
        btn._hoverIndicator:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 0)
        btn._hoverIndicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -1, 0)
        btn._hoverIndicator:Hide()
    end

    -------------------------------------------------------------------
    --  Unlock Mode button  (always top, not a module -- just triggers unlock)
    -------------------------------------------------------------------
    do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, NAV_ROW_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, NAV_TOP)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        -- Glow layer (behind icon): tinted version of the -on texture
        local iconGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        iconGlow:SetTexture(ICONS_PATH .. "sidebar\\unlockmode-ig-on.png")
        iconGlow:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconGlow:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        iconGlow:SetDesaturated(true)
        iconGlow:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
        iconGlow:Hide()
        btn._iconGlow = iconGlow
        RegAccent({ type="vertex", obj=iconGlow })

        -- Icon layer (on top of glow): always the white off texture
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICONS_PATH .. "sidebar\\unlockmode-ig.png")
        icon:SetSize(NAV_ICON_W, NAV_ICON_H)
        icon:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        btn._icon    = icon
        btn._iconOn  = ICONS_PATH .. "sidebar\\unlockmode-ig-on.png"
        btn._iconOff = ICONS_PATH .. "sidebar\\unlockmode-ig.png"

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText(EllesmereUI.L("Unlock Mode"))
        btn._label = label

        -- Always "loaded" appearance
        label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        icon:SetDesaturated(false)
        icon:SetAlpha(NAV_ENABLED_ICON_A)

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            hlTex:SetAlpha(0.06)
            self._hoverGlow:Show()
            self._hoverIndicator:Show()
            self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
        end)
        btn:SetScript("OnLeave", function(self)
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        end)
        btn:SetScript("OnClick", function()
            if EllesmereUI._openUnlockMode then
                EllesmereUI._unlockReturnModule = activeModule
                EllesmereUI._unlockReturnPage   = activePage
                C_Timer.After(0, EllesmereUI._openUnlockMode)
            end
        end)

        EllesmereUI._unlockSidebarBtn = btn

        -- One-time tutorial tip: play badge opening the Unlock Mode video guide, retired
        -- once clicked. VideoGuides owns all gating (per-account seen map + the Enable
        -- Tutorial Tips setting); nil-guarded for standalone builds.
        if EllesmereUI.VideoGuides and EllesmereUI.VideoGuides.AttachTip then
            EllesmereUI.VideoGuides.AttachTip(btn, "unlock_mode", {
                tooltip = "Video Guide: Unlock Mode",
                x = -12,
            })
        end
    end

    -------------------------------------------------------------------
    --  Global Settings button  (always second, not an addon)
    -------------------------------------------------------------------
    local GLOBAL_KEY = "_EUIGlobal"
    do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, NAV_ROW_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, NAV_TOP - NAV_ROW_H)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        -- Glow layer (behind icon): tinted version of the -on texture
        local iconGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        iconGlow:SetTexture(ICONS_PATH .. "sidebar\\settings-ig-on-2.png")
        iconGlow:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconGlow:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        iconGlow:SetDesaturated(true)
        iconGlow:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
        iconGlow:Hide()
        btn._iconGlow = iconGlow
        RegAccent({ type="vertex", obj=iconGlow })

        -- Icon layer (on top of glow): always the white off texture
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICONS_PATH .. "sidebar\\settings-ig-2.png")
        icon:SetSize(NAV_ICON_W, NAV_ICON_H)
        icon:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        btn._icon    = icon
        btn._iconOn  = ICONS_PATH .. "sidebar\\settings-ig-on-2.png"
        btn._iconOff = ICONS_PATH .. "sidebar\\settings-ig-2.png"

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText(EllesmereUI.L("Global Settings"))
        btn._label = label

        -- No download icon for global settings
        local dlIcon = btn:CreateTexture(nil, "ARTWORK")
        dlIcon:SetSize(18, 18)
        dlIcon:SetPoint("RIGHT", btn, "RIGHT", -14, 0)
        dlIcon:Hide()
        btn._dlIcon = dlIcon

        -- Always "loaded" -- global settings is built-in
        label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        icon:SetDesaturated(false)
        icon:SetAlpha(NAV_ENABLED_ICON_A)
        btn._folder = GLOBAL_KEY
        btn._loaded = true

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            if self._ovLocked then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "This module can't be overridden. Exit the override editing session to open it.")
                end
                return
            end
            hlTex:SetAlpha(0.06)
            if activeModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            if self._ovLocked then return end
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if activeModule ~= self._folder then
                self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnClick", function(self)
            if self._ovLocked then return end
            if modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        sidebarButtons[GLOBAL_KEY] = btn
    end

    -------------------------------------------------------------------
    --  Patch Notes button  (own page -- selects the _EUIPatchNotes module)
    -------------------------------------------------------------------
    do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, NAV_ROW_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, NAV_TOP - NAV_ROW_H * 2)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        -- Glow layer (behind icon): tinted version of the -on texture
        local iconGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        iconGlow:SetTexture(ICONS_PATH .. "sidebar\\notes-on.png")
        iconGlow:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconGlow:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        iconGlow:SetDesaturated(true)
        iconGlow:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
        iconGlow:Hide()
        btn._iconGlow = iconGlow
        RegAccent({ type="vertex", obj=iconGlow })

        -- Icon layer (on top of glow): always the white off texture
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICONS_PATH .. "sidebar\\notes-off.png")
        icon:SetSize(NAV_ICON_W, NAV_ICON_H)
        icon:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        btn._icon    = icon
        btn._iconOn  = ICONS_PATH .. "sidebar\\notes-on.png"
        btn._iconOff = ICONS_PATH .. "sidebar\\notes-off.png"

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText(EllesmereUI.L("Patch Notes"))
        btn._label = label

        label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        icon:SetDesaturated(false)
        icon:SetAlpha(NAV_ENABLED_ICON_A)

        btn._folder = "_EUIPatchNotes"
        btn._loaded = true

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            if self._ovLocked then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "This module can't be overridden. Exit the override editing session to open it.")
                end
                return
            end
            hlTex:SetAlpha(0.06)
            if activeModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            if self._ovLocked then return end
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if activeModule ~= self._folder then
                self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnClick", function(self)
            if self._ovLocked then return end
            -- Opening Patch Notes consumes the new-patch reminder dot; it
            -- re-arms only on the next version increase.
            if EllesmereUIDB and EllesmereUIDB.patchDotPending then
                EllesmereUIDB.patchDotPending = nil
                if EllesmereUI._UpdatePatchDot then EllesmereUI._UpdatePatchDot() end
            end
            if modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        -- Pulsing "new patch" dot: shown while patchDotPending is raised (version-increase
        -- stamp near EllesmereUI.VERSION) and patchDotDisabled is unset. Built lazily.
        local dot
        EllesmereUI._UpdatePatchDot = function()
            local show = EllesmereUIDB and EllesmereUIDB.patchDotPending
                and not EllesmereUIDB.patchDotDisabled and true or false
            if not dot then
                if not show then return end
                dot = CreateFrame("Frame", nil, btn)
                dot:SetFrameLevel(btn:GetFrameLevel() + 5)
                dot:SetSize(9, 9)
                dot:SetPoint("RIGHT", btn, "RIGHT", -14, 0)
                local t = dot:CreateTexture(nil, "OVERLAY")
                t:SetAllPoints()
                t:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
                -- Round: run the solid color through the portrait circle mask.
                local mask = dot:CreateMaskTexture()
                mask:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga",
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(t)
                t:AddMaskTexture(mask)
                local ag = dot:CreateAnimationGroup()
                ag:SetLooping("REPEAT")
                local a1 = ag:CreateAnimation("Alpha")
                a1:SetFromAlpha(1); a1:SetToAlpha(0.35)
                a1:SetDuration(0.7); a1:SetOrder(1); a1:SetSmoothing("IN_OUT")
                local a2 = ag:CreateAnimation("Alpha")
                a2:SetFromAlpha(0.35); a2:SetToAlpha(1)
                a2:SetDuration(0.7); a2:SetOrder(2); a2:SetSmoothing("IN_OUT")
                dot._ag = ag
            end
            dot:SetShown(show)
            if show then dot._ag:Play() else dot._ag:Stop() end
        end
        EllesmereUI._UpdatePatchDot()

        sidebarButtons["_EUIPatchNotes"] = btn
        EllesmereUI._patchNotesSidebarBtn = btn
    end

    -------------------------------------------------------------------
    --  Profiles & Presets button  (own page -- selects the _EUIProfiles module)
    -------------------------------------------------------------------
    do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, NAV_ROW_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, NAV_TOP - NAV_ROW_H * 3)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        -- Glow layer (behind icon): tinted version of the -on texture
        local iconGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        iconGlow:SetTexture(ICONS_PATH .. "sidebar\\profiles-on.png")
        iconGlow:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconGlow:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        iconGlow:SetDesaturated(true)
        iconGlow:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
        iconGlow:Hide()
        btn._iconGlow = iconGlow
        RegAccent({ type="vertex", obj=iconGlow })

        -- Icon layer (on top of glow): always the white off texture
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICONS_PATH .. "sidebar\\profiles-off.png")
        icon:SetSize(NAV_ICON_W, NAV_ICON_H)
        icon:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        btn._icon    = icon
        btn._iconOn  = ICONS_PATH .. "sidebar\\profiles-on.png"
        btn._iconOff = ICONS_PATH .. "sidebar\\profiles-off.png"

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText(EllesmereUI.L("Profiles & Presets"))
        btn._label = label

        label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        icon:SetDesaturated(false)
        icon:SetAlpha(NAV_ENABLED_ICON_A)

        btn._folder = "_EUIProfiles"
        btn._loaded = true

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            if self._ovLocked then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "This module can't be overridden. Exit the override editing session to open it.")
                end
                return
            end
            hlTex:SetAlpha(0.06)
            if activeModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            if self._ovLocked then return end
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if activeModule ~= self._folder then
                self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnClick", function(self)
            if self._ovLocked then return end
            if modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        sidebarButtons["_EUIProfiles"] = btn
        EllesmereUI._profilesSidebarBtn = btn
    end

    -- First addon starts four rows down (Unlock, Global, Patch Notes, Profiles & Presets)
    local ORIG_ADDON_NAV_TOP = NAV_TOP - NAV_ROW_H * 4

    -----------------------------------------------------------------------
    --  Sidebar search bar (filters addon list by display name or page name)
    -----------------------------------------------------------------------
    local SB_TOP_PAD     = 13   -- gap between Profiles & Presets and the search bar
    local SB_H           = 28
    local SB_BOT_PAD     = 6
    local SB_SIDE_INSET  = 20
    local SB_TOTAL       = SB_TOP_PAD + SB_H + SB_BOT_PAD

    local sidebarSearchFrame = CreateFrame("Frame", nil, sidebar)
    sidebarSearchFrame:SetSize(SIDEBAR_W - SB_SIDE_INSET * 2, SB_H)
    sidebarSearchFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", SB_SIDE_INSET + 2, ORIG_ADDON_NAV_TOP - SB_TOP_PAD)
    sidebarSearchFrame:SetFrameLevel(sidebar:GetFrameLevel() + 3)

    local sbBg = SolidTex(sidebarSearchFrame, "BACKGROUND",
        EllesmereUI.SL_INPUT_R, EllesmereUI.SL_INPUT_G, EllesmereUI.SL_INPUT_B, EllesmereUI.SL_INPUT_A + 0.10)
    sbBg:SetAllPoints()
    local sbBrd = MakeBorder(sidebarSearchFrame,
        EllesmereUI.BORDER_R, EllesmereUI.BORDER_G, EllesmereUI.BORDER_B, 0.10)

    local sbEdit = CreateFrame("EditBox", nil, sidebarSearchFrame)
    sbEdit:SetAllPoints()
    sbEdit:SetAutoFocus(false)
    sbEdit:SetFont(EllesmereUI.EXPRESSWAY, 13, "")
    sbEdit:SetTextColor(1, 1, 1, 1)
    sbEdit:SetTextInsets(10, 24, 0, 0)
    sbEdit:SetMaxLetters(40)

    local sbPlaceholder = MakeFont(sidebarSearchFrame, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.3)
    sbPlaceholder:SetPoint("LEFT", sidebarSearchFrame, "LEFT", 10, 0)
    sbPlaceholder:SetText(EllesmereUI.L("Search Features..."))

    local sbClearBtn = CreateFrame("Button", nil, sidebarSearchFrame)
    sbClearBtn:SetSize(20, 20)
    sbClearBtn:SetPoint("RIGHT", sidebarSearchFrame, "RIGHT", -4, 0)
    sbClearBtn:SetFrameLevel(sbEdit:GetFrameLevel() + 2)
    sbClearBtn:Hide()
    local sbClearLabel = MakeFont(sbClearBtn, 15, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.35)
    sbClearLabel:SetPoint("CENTER")
    sbClearLabel:SetText("x")
    sbClearBtn:SetScript("OnEnter", function() sbClearLabel:SetTextColor(1, 1, 1, 1) end)
    sbClearBtn:SetScript("OnLeave", function() sbClearLabel:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.35) end)
    sbClearBtn:SetScript("OnClick", function()
        sbEdit:SetText("")
        sbEdit:ClearFocus()
    end)

    local function _sbBorderHover(a) sbBrd:SetColor(EllesmereUI.BORDER_R, EllesmereUI.BORDER_G, EllesmereUI.BORDER_B, a) end
    sidebarSearchFrame:SetScript("OnEnter", function() _sbBorderHover(0.15) end)
    sidebarSearchFrame:SetScript("OnLeave", function() _sbBorderHover(0.10) end)
    sbEdit:SetScript("OnEditFocusGained", function() _sbBorderHover(0.15) end)
    sbEdit:SetScript("OnEditFocusLost", function() _sbBorderHover(0.10) end)
    sbEdit:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sbEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    EllesmereUI._sidebarSearchBox = sbEdit
    EllesmereUI._sidebarSearchText = ""

    sbEdit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text == "" then
            sbPlaceholder:Show()
            sbClearBtn:Hide()
        else
            sbPlaceholder:Hide()
            sbClearBtn:Show()
        end
        EllesmereUI._sidebarSearchText = text
        -- Deliberately NO sidebar filtering here: the global search results popup
        -- (EllesmereUI_GlobalSearch.lua) lists matches without reshuffling the nav.
    end)

    -- Addon scroll area sits below the search bar
    local ADDON_NAV_TOP = ORIG_ADDON_NAV_TOP - SB_TOTAL

    -----------------------------------------------------------------------
    --  Scrollable addon nav container
    --  The roster exceeds the space between ADDON_NAV_TOP and the class art, so addon
    --  buttons live in a ScrollFrame with smooth wheel scrolling and a thin right thumb.
    -----------------------------------------------------------------------
    local ADDON_VISIBLE_ROWS    = 12   -- nav rows shrank to 40px; bump count so the addon viewport still fills to the bottom
    -- +30 = 20px viewport bonus plus 10px offsetting the SB_TOP_PAD bump, so growing the
    -- search-bar padding cannot shrink the viewport. ARROW_RESERVE = strip for the arrow.
    local ADDON_ARROW_RESERVE   = 24
    local ADDON_SCROLL_H        = ADDON_VISIBLE_ROWS * NAV_ROW_H - SB_TOTAL + 30 - ADDON_ARROW_RESERVE
    local ADDON_SCROLL_STEP     = 60   -- match the main content scroll
    local ADDON_SMOOTH_SPEED    = 12   -- match the main content scroll

    local addonScrollFrame = CreateFrame("ScrollFrame", nil, sidebar)
    addonScrollFrame:SetWidth(SIDEBAR_W)
    addonScrollFrame:SetHeight(ADDON_SCROLL_H)
    addonScrollFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, ADDON_NAV_TOP)
    addonScrollFrame:SetFrameLevel(sidebar:GetFrameLevel() + 1)
    addonScrollFrame:EnableMouseWheel(true)
    addonScrollFrame:SetClipsChildren(true)

    local addonScrollChild = CreateFrame("Frame", nil, addonScrollFrame)
    addonScrollChild:SetWidth(SIDEBAR_W)
    -- Placeholder height; the button-build loop below sets the real value from
    -- cumulative GROUP_ROW_H / CHILD_ROW_H offsets.
    addonScrollChild:SetHeight(1)
    addonScrollFrame:SetScrollChild(addonScrollChild)

    EllesmereUI._addonScrollFrame = addonScrollFrame
    EllesmereUI._addonScrollChild = addonScrollChild

    -- Thin scrollbar thumb on the right edge of the scroll area
    local addonTrack = CreateFrame("Frame", nil, addonScrollFrame)
    addonTrack:SetWidth(3)
    addonTrack:SetPoint("TOPRIGHT", addonScrollFrame, "TOPRIGHT", -2, -2)
    addonTrack:SetPoint("BOTTOMRIGHT", addonScrollFrame, "BOTTOMRIGHT", -2, 2)
    addonTrack:SetFrameLevel(addonScrollFrame:GetFrameLevel() + 3)
    local addonTrackBg = SolidTex(addonTrack, "BACKGROUND", 1, 1, 1, 0.03)
    addonTrackBg:SetAllPoints()

    local addonThumb = SolidTex(addonTrack, "ARTWORK", 1, 1, 1, 0.25)
    addonThumb:SetPoint("TOP", addonTrack, "TOP", 0, 0)
    addonThumb:SetWidth(3)
    addonThumb:SetHeight(40)

    -- Scroll-to-bottom arrow below the viewport: dims at the bottom (or when the list
    -- does not scroll), click animates down. OnClick is wired below, once the
    -- smooth-scroll state locals exist. Alpha tiers live on the frame (ours to write).
    local arrowBtn = CreateFrame("Button", nil, sidebar)
    arrowBtn:SetSize(22, 19)
    arrowBtn:SetPoint("TOP", addonScrollFrame, "BOTTOM", 0, -5)
    arrowBtn:SetFrameLevel(sidebar:GetFrameLevel() + 5)
    arrowBtn:SetHitRectInsets(-12, -12, -6, -8)
    arrowBtn._aEnabled, arrowBtn._aDisabled, arrowBtn._aHover = 0.7, 0.2, 1.0
    arrowBtn._atBottom = false
    do
        local t = arrowBtn:CreateTexture(nil, "ARTWORK")
        t:SetTexture(ICONS_PATH .. "eui-arrow-down3.png")
        t:SetAllPoints()
    end
    arrowBtn:SetAlpha(arrowBtn._aEnabled)
    arrowBtn:SetScript("OnEnter", function(self)
        if not self._atBottom then self:SetAlpha(self._aHover) end
    end)
    arrowBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(self._atBottom and self._aDisabled or self._aEnabled)
    end)
    EllesmereUI._addonScrollArrow = arrowBtn

    local function UpdateAddonThumb()
        local maxScroll = EllesmereUI.SafeScrollRange(addonScrollFrame) or 0
        -- Arrow state: dimmed when nothing is below. Runs before the no-scroll return.
        do
            local cur = tonumber(addonScrollFrame:GetVerticalScroll()) or 0
            local atBottom = (maxScroll <= 0.5) or (cur >= maxScroll - 0.5)
            arrowBtn._atBottom = atBottom
            if atBottom then
                arrowBtn:SetAlpha(arrowBtn._aDisabled)
            elseif arrowBtn:IsMouseOver() then
                arrowBtn:SetAlpha(arrowBtn._aHover)
            else
                arrowBtn:SetAlpha(arrowBtn._aEnabled)
            end
        end
        if maxScroll <= 0 then
            addonTrack:Hide()
            return
        end
        addonTrack:Show()
        local trackH = addonTrack:GetHeight()
        local visH = addonScrollFrame:GetHeight()
        local ratio = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * ratio)
        addonThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(addonScrollFrame:GetVerticalScroll()) or 0) / maxScroll
        addonThumb:ClearAllPoints()
        addonThumb:SetPoint("TOP", addonTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
    end

    -- Smooth mouse-wheel scroll (lerp towards target)
    local addonScrollTarget = 0
    local addonIsSmoothing  = false
    local addonSmoothFrame  = CreateFrame("Frame")
    addonSmoothFrame:Hide()
    -- Pixel-snap the scroll offset in EFFECTIVE-PIXEL space (not raw WoW units), like the
    -- main content scroll. Rounding in the direction of travel keeps the lerp monotonic
    -- so it never bounces at settlement. Fractional offsets leave glyphs on sub-pixel
    -- positions and the rasterizer picks different pixels per frame: 1px scroll jitter.
    addonSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = addonScrollFrame:GetVerticalScroll()
        local maxScroll = EllesmereUI.SafeScrollRange(addonScrollFrame) or 0
        local scale = addonScrollFrame:GetEffectiveScale()
        -- Snap max down to a pixel boundary so target can't exceed it.
        maxScroll = math.floor(maxScroll * scale) / scale
        addonScrollTarget = math.max(0, math.min(maxScroll, addonScrollTarget))
        local diff = addonScrollTarget - cur
        if math.abs(diff) < 0.3 then
            addonScrollFrame:SetVerticalScroll(addonScrollTarget)
            UpdateAddonThumb()
            addonIsSmoothing = false
            addonSmoothFrame:Hide()
            return
        end
        local newScroll = cur + diff * math.min(1, ADDON_SMOOTH_SPEED * elapsed)
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        if diff > 0 then
            newScroll = math.ceil(newScroll * scale) / scale
        else
            newScroll = math.floor(newScroll * scale) / scale
        end
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        addonScrollFrame:SetVerticalScroll(newScroll)
        UpdateAddonThumb()
    end)

    addonScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = EllesmereUI.SafeScrollRange(self) or 0
        if maxScroll <= 0 then return end
        local scale = self:GetEffectiveScale()
        maxScroll = math.floor(maxScroll * scale) / scale
        local base = addonIsSmoothing and addonScrollTarget or self:GetVerticalScroll()
        local target = math.max(0, math.min(maxScroll, base - delta * ADDON_SCROLL_STEP))
        -- Snap the resting target to a pixel boundary so settlement lands on an integer row offset.
        target = math.floor(target * scale + 0.5) / scale
        addonScrollTarget = math.min(target, maxScroll)
        if not addonIsSmoothing then
            addonIsSmoothing = true
            addonSmoothFrame:Show()
        end
    end)
    addonScrollFrame:SetScript("OnScrollRangeChanged", UpdateAddonThumb)
    addonScrollFrame:HookScript("OnSizeChanged", UpdateAddonThumb)
    -- Controller cursor: it scrolls the list itself to reach a row, so the thumb
    -- follows (the lerp already paints its own frames).
    if EllesmereUI.PadCP() then
        addonScrollFrame:HookScript("OnVerticalScroll", function()
            if not addonIsSmoothing and not addonTrack:GetScript("OnUpdate") then UpdateAddonThumb() end
        end)
    end

    -- Arrow click: smooth-animate to the bottom, reusing the wheel's scroll state.
    arrowBtn:SetScript("OnClick", function()
        local maxScroll = EllesmereUI.SafeScrollRange(addonScrollFrame) or 0
        if maxScroll <= 0 then return end
        local scale = addonScrollFrame:GetEffectiveScale()
        maxScroll = math.floor(maxScroll * scale) / scale
        addonScrollTarget = maxScroll
        if not addonIsSmoothing then
            addonIsSmoothing = true
            addonSmoothFrame:Show()
        end
    end)

    -- Click/drag the scrollbar track: a click jumps to that position, holding drags.
    -- The visible track is 3px, so a wider invisible hit rect is added.
    addonTrack:EnableMouse(true)
    addonTrack:SetHitRectInsets(-8, -2, 0, 0)
    local function _scrollToCursor()
        local maxScroll = EllesmereUI.SafeScrollRange(addonScrollFrame) or 0
        if maxScroll <= 0 then return end
        local trackH = addonTrack:GetHeight()
        local thumbH = addonThumb:GetHeight()
        local travel = math.max(1, trackH - thumbH)
        local _, cy = GetCursorPosition()
        local scale = addonTrack:GetEffectiveScale()
        local trackTop = addonTrack:GetTop() or 0
        -- Center the thumb on the cursor, then clamp to travel range.
        local offset = (trackTop - cy / scale) - thumbH / 2
        offset = math.max(0, math.min(travel, offset))
        local rawScroll = (offset / travel) * maxScroll
        -- Snap to an effective-pixel boundary so labels land on exact pixels.
        local s = addonScrollFrame:GetEffectiveScale()
        local newScroll = math.floor(rawScroll * s + 0.5) / s
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        addonScrollTarget = newScroll
        addonScrollFrame:SetVerticalScroll(newScroll)
        UpdateAddonThumb()
    end
    addonTrack:SetScript("OnMouseDown", function(self)
        _scrollToCursor()
        addonIsSmoothing = false
        addonSmoothFrame:Hide()
        self:SetScript("OnUpdate", _scrollToCursor)
    end)
    addonTrack:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    addonTrack:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    -- Controller cursor: a pointer-position control, never a stop.
    EllesmereUI.PadHint(addonTrack, "nodeignore")

    -- Grouped-sidebar row heights (groups = text-only headers, children = indented rows
    -- with label + power), sized to fit all addons without scrolling. On EllesmereUI so
    -- RefreshSidebarStates / _applySidebarSearch read the same values.
    EllesmereUI.SIDEBAR_GROUP_ROW_H = 28
    EllesmereUI.SIDEBAR_CHILD_ROW_H = 28   -- includes 6px air gap between addons
    EllesmereUI.SIDEBAR_GROUP_GAP   = 10   -- extra vertical space between groups
    local GROUP_ROW_H    = EllesmereUI.SIDEBAR_GROUP_ROW_H
    local CHILD_ROW_H    = EllesmereUI.SIDEBAR_CHILD_ROW_H
    local CHILD_INDENT_X = NAV_LEFT + 16   -- label indent past the group label

    -- Register the addon-enable helper once (on EllesmereUI to avoid new upvalues).
    if not EllesmereUI._addonToggleInit then
        EllesmereUI._addonToggleInit = true
        EllesmereUI.IsAddonEnabled = function(name)
            if C_AddOns and C_AddOns.GetAddOnEnableState then
                return C_AddOns.GetAddOnEnableState(name) > 0
            end
            return true
        end
    end

    -- Create a group header row (accent-colored label only, no icon, no power,
    -- not clickable). Acts as a visual category divider above its children.
    local function CreateGroupHeader(group)
        local row = CreateFrame("Frame", nil, addonScrollChild)
        row:SetSize(SIDEBAR_W, GROUP_ROW_H)
        row:SetFrameLevel(addonScrollChild:GetFrameLevel() + 1)

        local EG = ELLESMERE_GREEN
        local label = MakeFont(row, 15, nil, EG.r, EG.g, EG.b, 1)
        label:SetPoint("LEFT", row, "LEFT", NAV_LEFT, 0)
        label:SetText(EllesmereUI.L(group.label))
        RegAccent({ type="callback", fn = function(r, g, b)
            label:SetTextColor(r, g, b, 1)
        end })

        row._isGroup = true
        row._group   = group
        row._label   = label
        return row
    end

    -- Create a child (addon) row: indented label + power on the right, no left icon.
    local function CreateAddonChildRow(info)
        local btn = CreateFrame("Button", nil, addonScrollChild)
        btn:SetSize(SIDEBAR_W, CHILD_ROW_H)
        btn:SetFrameLevel(addonScrollChild:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", btn, "LEFT", CHILD_INDENT_X, 0)
        label:SetText(EllesmereUI.L(info.display))
        btn._label = label

        -- One-time tutorial tip on the Cooldown Manager row: play badge in the indent
        -- gutter opening the CDM video guide, retired once clicked. VideoGuides owns all
        -- gating (seen map + Enable Tutorial Tips); nil-guarded for standalone builds.
        if info.folder == "EllesmereUICooldownManager"
            and EllesmereUI.VideoGuides and EllesmereUI.VideoGuides.AttachTip then
            EllesmereUI.VideoGuides.AttachTip(btn, "cooldown_manager", {
                tooltip = "Video Guide: Cooldown Manager",
                point = "RIGHT", relPoint = "LEFT",
                x = CHILD_INDENT_X - 6,
            })
        end

        -- Download icon (shown for uninstalled addons)
        local dlIcon = btn:CreateTexture(nil, "ARTWORK")
        dlIcon:SetSize(18, 18)
        dlIcon:SetPoint("RIGHT", btn, "RIGHT", -14, 0)
        dlIcon:SetTexture(ICONS_PATH .. "eui-download.png")
        dlIcon:SetDesaturated(true)
        dlIcon:SetAlpha(0.6)
        dlIcon:Hide()
        btn._dlIcon = dlIcon

        -- Power toggle (hidden for comingSoon/maintenance/alwaysLoaded, and entirely in
        -- standalone builds: one module, which cannot toggle itself off).
        if not IS_STANDALONE and not info.comingSoon and not info.maintenance and not info.alwaysLoaded then
            local pwrBtn = CreateFrame("Button", nil, btn)
            pwrBtn:SetSize(13, 13)
            pwrBtn:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
            pwrBtn:SetFrameLevel(btn:GetFrameLevel() + 5)
            local pwrTex = pwrBtn:CreateTexture(nil, "ARTWORK")
            pwrTex:SetAllPoints()
            pwrTex:SetTexture(ICONS_PATH .. "power.png")
            pwrTex:SetAlpha(0.75)
            pwrBtn._tex = pwrTex
            pwrBtn._folder = info.folder
            pwrBtn._display = info.display
            pwrBtn:SetScript("OnEnter", function(self)
                local enabled = IsAddonLoaded(self._folder)
                if enabled then
                    self._tex:SetVertexColor(0.824, 0.212, 0.212, 1)
                else
                    self._tex:SetVertexColor(0.212, 0.824, 0.325, 1)
                end
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, enabled and "Disable " .. self._display or "Enable " .. self._display)
                end
            end)
            pwrBtn:SetScript("OnLeave", function(self)
                local enabled = IsAddonLoaded(self._folder)
                self._tex:SetVertexColor(1, 1, 1, enabled and 1 or 0.5)
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            pwrBtn:SetScript("OnClick", function(self)
                local enabled = IsAddonLoaded(self._folder)
                local action = enabled and "disable" or "enable"
                local folder = self._folder
                EllesmereUI:ShowConfirmPopup({
                    title       = EllesmereUI.Lf("%1$s Module", enabled and EllesmereUI.L("Disable") or EllesmereUI.L("Enable")),
                    message     = EllesmereUI.Lf("Are you sure you want to %1$s %2$s?", EllesmereUI.L(action), EllesmereUI.L(self._display)),
                    confirmText = enabled and "Disable & Reload" or "Enable & Reload",
                    cancelText  = "Cancel",
                    reload      = true,
                    onConfirm   = function()
                        if folder == "EllesmereUIBags" and EllesmereUIDB then
                            EllesmereUIDB.bagsUserChosen = true
                        end
                        if enabled then
                            C_AddOns.DisableAddOn(folder)
                        else
                            C_AddOns.EnableAddOn(folder)
                        end
                    end,
                })
            end)
            btn._pwrBtn = pwrBtn
        end

        -- Sync icon (to the left of power button, hidden for exempt/single-profile).
        -- Also hidden entirely in standalone builds (no cross-module sync surface).
        if not IS_STANDALONE and not info.comingSoon and not info.maintenance and not EllesmereUI._syncExempt[info.folder] then
            local syncBtn = CreateFrame("Button", nil, btn)
            syncBtn:SetSize(15, 15)
            if btn._pwrBtn then
                syncBtn:SetPoint("RIGHT", btn._pwrBtn, "LEFT", -8, 0)
            else
                syncBtn:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
            end
            syncBtn:SetFrameLevel(btn:GetFrameLevel() + 5)
            local syncTex = syncBtn:CreateTexture(nil, "ARTWORK")
            syncTex:SetAllPoints()
            syncTex:SetTexture(EllesmereUI.SYNC_ICON)
            syncTex:SetVertexColor(1, 1, 1, 1)
            syncBtn._tex = syncTex
            -- syncFolder/syncDisplay let an entry drive the sync of a DIFFERENT profile
            -- folder (Dragon Riding lives in the BlizzardSkin entry); the loaded check
            -- still uses info.folder, only the sync state/group target is redirected.
            local syncFolder = info.syncFolder or info.folder
            syncBtn._folder = syncFolder
            syncBtn._display = info.syncDisplay or info.display
            local SYNC_ON_R, SYNC_ON_G, SYNC_ON_B = 0x32/255, 0xbc/255, 0x53/255
            local SYNC_HOVER_R = math.min(1, SYNC_ON_R * 1.25)
            local SYNC_HOVER_G = math.min(1, SYNC_ON_G * 1.25)
            local SYNC_HOVER_B = math.min(1, SYNC_ON_B * 1.25)
            local isGlobalOnly = EllesmereUI._syncGlobalOnly and EllesmereUI._syncGlobalOnly[info.folder]
            local function RefreshSyncState()
                -- Hide the sync icon for disabled modules (no live settings to sync);
                -- same loaded check as the power button so the two stay consistent.
                if not IsAddonLoaded(info.folder) then syncBtn:Hide(); return end
                -- Hide if only one profile exists
                local profCount = 0
                if EllesmereUIDB and EllesmereUIDB.profiles then
                    for _ in pairs(EllesmereUIDB.profiles) do
                        profCount = profCount + 1
                        if profCount > 1 then break end
                    end
                end
                if profCount <= 1 then syncBtn:Hide(); return end
                -- Green when the ACTIVE profile is a member of this module's sync group;
                -- dim white otherwise, including when a group exists without it.
                local activeProf = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
                local activeSynced = isGlobalOnly or EllesmereUI.IsProfileSynced(syncFolder, activeProf)
                -- Check global hide settings
                if EllesmereUIDB then
                    if EllesmereUIDB.hideSyncIcons then
                        if EllesmereUIDB.hideSyncIconsOnlyFull then
                            if activeSynced then syncBtn:Hide(); return end
                        else
                            syncBtn:Hide(); return
                        end
                    end
                end
                syncBtn:Show()
                if activeSynced then
                    syncTex:SetVertexColor(SYNC_ON_R, SYNC_ON_G, SYNC_ON_B, 1)
                else
                    syncTex:SetVertexColor(1, 1, 1, 0.5)
                end
            end
            RefreshSyncState()
            syncBtn._refreshAlpha = RefreshSyncState
            -- Bulk-refresh registry (e.g. after profile deletion), keyed by folder so a
            -- sidebar rebuild overwrites the old closure instead of accumulating stale ones.
            if not EllesmereUI._syncRefreshFns then EllesmereUI._syncRefreshFns = {} end
            EllesmereUI._syncRefreshFns[info.folder] = RefreshSyncState
            syncBtn:SetScript("OnEnter", function(self)
                if isGlobalOnly then
                    self._tex:SetVertexColor(SYNC_HOVER_R, SYNC_HOVER_G, SYNC_HOVER_B, 1)
                    if EllesmereUI.ShowWidgetTooltip then
                        EllesmereUI.ShowWidgetTooltip(self, "No Profile Level Customizations")
                    end
                    return
                end
                local activeProf = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
                local activeSynced = EllesmereUI.IsProfileSynced(self._folder, activeProf)
                if activeSynced then
                    self._tex:SetVertexColor(SYNC_HOVER_R, SYNC_HOVER_G, SYNC_HOVER_B, 1)
                else
                    self._tex:SetVertexColor(1, 1, 1, 1)
                end
                if EllesmereUI.ShowWidgetTooltip then
                    local tip = activeSynced and "Profile Synced" or "Sync " .. self._display
                    EllesmereUI.ShowWidgetTooltip(self, tip)
                end
            end)
            syncBtn:SetScript("OnLeave", function(self)
                RefreshSyncState()
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            syncBtn:SetScript("OnClick", function(self)
                if isGlobalOnly then return end
                EllesmereUI.OpenSyncPopup(self._folder, self._display, self)
            end)
            btn._syncBtn = syncBtn
        end

        -- Bound the label to the leftmost right-side icon so long translated names
        -- ellipsize instead of overlapping the sync/power icons. The download icon always
        -- exists, so there is always a right anchor reserving the cluster's space.
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        local rightEdge = btn._syncBtn or btn._pwrBtn or btn._dlIcon
        if rightEdge then
            label:SetPoint("RIGHT", rightEdge, "LEFT", -6, 0)
        end

        -- Default to unloaded appearance (refreshed each time panel opens)
        label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
        btn._folder = info.folder
        btn._loaded = false
        btn._alwaysLoaded = info.alwaysLoaded or false
        btn._comingSoon = info.comingSoon or false
        btn._maintenance = info.maintenance or false

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            if self._comingSoon then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Coming soon")
                end
                return
            end
            if self._maintenance then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "In Maintenance")
                end
                return
            end
            if self._ovLocked then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "This module can't be overridden. Exit the override editing session to open it.")
                end
                return
            end
            if self._notEnabled then return end
            hlTex:SetAlpha(0.06)
            if activeModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                if self._loaded then
                    self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
                else
                    self._label:SetTextColor(NAV_HOVER_DISABLED_TEXT.r, NAV_HOVER_DISABLED_TEXT.g, NAV_HOVER_DISABLED_TEXT.b, NAV_HOVER_DISABLED_TEXT.a)
                end
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            if self._comingSoon then return end
            if self._maintenance then return end
            if self._ovLocked then return end
            if self._notEnabled then return end
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if activeModule ~= self._folder then
                if self._loaded then
                    self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
                else
                    self._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
                end
            end
        end)
        btn:SetScript("OnClick", function(self)
            if self._comingSoon then return end
            if self._maintenance then return end
            if self._ovLocked then return end
            if self._notEnabled then return end
            if self._loaded and modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        return btn
    end

    -- Build the sidebar in group order; positions are assigned once and re-stacked by
    -- RefreshSidebarStates / _applySidebarSearch. Group/roster references go through
    -- the private EUI_NS model (one upvalue, CreateMainFrame is at the 60-upvalue cap);
    -- cumulative `_y` walks each row so group and child heights can differ.
    local _y = 0
    local _groupHeaders = EUI_NS.sidebarGroupButtons
    local _infoByFolder = EUI_NS.navInfo
    local GROUP_GAP = EllesmereUI.SIDEBAR_GROUP_GAP
    for i, group in ipairs(EUI_NS.navGroups) do
        if i > 1 then _y = _y + GROUP_GAP end
        local header = CreateGroupHeader(group)
        header:SetPoint("TOPLEFT", addonScrollChild, "TOPLEFT", 0, -_y)
        _groupHeaders[group.key] = header
        _y = _y + GROUP_ROW_H
        for _, folder in ipairs(group.members) do
            local info = _infoByFolder[folder]
            if info then
                local btn = CreateAddonChildRow(info)
                btn:SetPoint("TOPLEFT", addonScrollChild, "TOPLEFT", 0, -_y)
                sidebarButtons[info.folder] = btn
                _y = _y + CHILD_ROW_H
            end
        end
    end
    -- Row factories for plugin sections registered after the panel is built
    -- (the plugin registry creates their header and rows on the fly; positions
    -- come from the next RefreshSidebarStates).
    EUI_NS.CreateSidebarGroupHeader = CreateGroupHeader
    EUI_NS.CreateSidebarChildRow    = CreateAddonChildRow
    -- Lock/unlock excluded modules during an override editing session: their settings cannot be
    -- captured, so the row grays out and blocks clicks. Called from the session enter/exit paths in EllesmereUI_SpecOverrides.
    EllesmereUI.RefreshSidebarOverrideLocks = function()
        local active = EllesmereUI.SpecOverrides_EditSessionActive
            and EllesmereUI.SpecOverrides_EditSessionActive() or false
        for folder, btn in pairs(sidebarButtons) do
            local lock = (active and EllesmereUI.SpecOverrides_ModuleExcluded
                and EllesmereUI.SpecOverrides_ModuleExcluded(folder)) or false
            if lock then
                -- Re-assert UNCONDITIONALLY: RefreshSidebarStates recolors every row by
                -- loaded state on module switches and would otherwise wash the lock out.
                btn._ovLocked = true
                btn._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
                if btn._icon then
                    btn._icon:SetDesaturated(true)
                    btn._icon:SetAlpha(0.35)
                end
            elseif btn._ovLocked then
                btn._ovLocked = nil
                if btn._loaded then
                    btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
                    if btn._icon then
                        btn._icon:SetDesaturated(false)
                        btn._icon:SetAlpha(NAV_ENABLED_ICON_A)
                    end
                end
            end
        end
    end
    -- Refresh all sync icons (called from global settings toggle)
    EllesmereUI._refreshAllSyncIcons = function()
        for _, btn in pairs(sidebarButtons) do
            if btn._syncBtn and btn._syncBtn._refreshAlpha then
                btn._syncBtn._refreshAlpha()
            end
        end
    end
    addonScrollChild:SetHeight(_y)

    -- Class art (decorative, purely visual -- does not affect layout of any other element)
    do
        local artFile = CLASS_ART_MAP[playerClass] or "warrior.png"
        local classArt = sidebar:CreateTexture(nil, "BACKGROUND", nil, -1)
        classArt:SetTexture(ICONS_PATH .. "sidebar\\class-accent\\" .. artFile)
        classArt:SetSize(156, 145)
        classArt:SetPoint("BOTTOM", sidebar, "BOTTOM", 10, 200)
        classArt:SetAlpha(1)
    end

    -- Version text
    local versionText = MakeFont(sidebar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    versionText:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 18, 18)
    versionText:SetText("v" .. (EllesmereUI.VERSION or "1.0"))
    versionText:SetAlpha(0.5)

    ---------------------------------------------------------------------------
    --  Build deferred opacity slider: vertical above versionText in the
    --  sidebar, or horizontal beside it under the EllesmereUI and EllesmereUI
    --  Forever themes (their art shares one frame layout).
    --  The orientation follows the theme live (ApplyThemeBG re-lays it out).
    ---------------------------------------------------------------------------
    do
        local SLIDER_H    = 60      -- vertical: track height
        local SLIDER_W    = 90      -- horizontal: track length
        local THUMB_W     = 14      -- thumb size across the track
        local THUMB_H     = 8       -- thumb size along the track (thin bar)
        local TRACK_W     = 2       -- thin track line
        local MIN_ALPHA   = 0.50
        local MAX_ALPHA   = 0.99
        local DEFAULT_A   = 0.99
        local horizontal  = false
        local currentAlpha = DEFAULT_A

        local opacityFrame = CreateFrame("Frame", nil, sidebar)
        opacityFrame:SetFrameLevel(sidebar:GetFrameLevel() + 5)

        -- Track background (thin line)
        local track = opacityFrame:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(1, 1, 1, 0.10)

        -- Thumb (sits on top of track, hides the line behind it)
        local thumb = CreateFrame("Frame", nil, opacityFrame)
        thumb:SetFrameLevel(opacityFrame:GetFrameLevel() + 2)

        -- Thumb texture (ARTWORK layer, above track's BACKGROUND)
        local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
        thumbTex:SetAllPoints()
        thumbTex:SetColorTexture(1, 1, 1, 0.25)

        -- Solid blocker behind thumb to hide the track line
        local thumbBlocker = thumb:CreateTexture(nil, "BORDER")
        thumbBlocker:SetPoint("TOPLEFT", thumbTex, "TOPLEFT", 0, 0)
        thumbBlocker:SetPoint("BOTTOMRIGHT", thumbTex, "BOTTOMRIGHT", 0, 0)
        thumbBlocker:SetColorTexture(DARK_BG.r, DARK_BG.g, DARK_BG.b, 1)

        -- Click on track to jump AND begin dragging immediately
        local trackFrame = CreateFrame("Button", nil, opacityFrame)
        trackFrame:SetFrameLevel(opacityFrame:GetFrameLevel())

        -- Track length along the slider axis (falls back before the first layout pass)
        local function TrackLength()
            local len = horizontal and track:GetWidth() or track:GetHeight()
            if not len or len < 1 then len = horizontal and SLIDER_W or SLIDER_H end
            return len
        end

        local function SetOpacity(alpha)
            alpha = math.max(MIN_ALPHA, math.min(MAX_ALPHA, alpha))
            currentAlpha = alpha
            mainFrame:SetAlpha(alpha)
            -- Thumb position: MIN at the bottom / left end, MAX at the top / right end
            local frac = (alpha - MIN_ALPHA) / (MAX_ALPHA - MIN_ALPHA)
            local pos = frac * (TrackLength() - THUMB_H)
            thumb:ClearAllPoints()
            if horizontal then
                thumb:SetPoint("LEFT", track, "LEFT", pos, 0)
            else
                thumb:SetPoint("BOTTOM", track, "BOTTOM", 0, pos)
            end
        end

        -- Cursor position along the track as a 0..1 fraction (nil until the track has a size)
        local function CursorFrac()
            local cx, cy = GetCursorPosition()
            local len = horizontal and track:GetWidth() or track:GetHeight()
            if not len or len < 1 then return nil end
            local origin = horizontal and track:GetLeft() or track:GetBottom()
            if not origin then return nil end
            local cur = (horizontal and cx or cy) / opacityFrame:GetEffectiveScale()
            local frac = (cur - origin - THUMB_H / 2) / (len - THUMB_H)
            return math.max(0, math.min(1, frac))
        end

        -- Dragging (OnUpdate only while active); a click on the track jumps, then drags too
        local dragging = false
        local function StartDrag()
            dragging = true
            thumb:SetScript("OnUpdate", function()
                if not dragging then return end
                local frac = CursorFrac()
                if frac then SetOpacity(MIN_ALPHA + frac * (MAX_ALPHA - MIN_ALPHA)) end
            end)
        end
        local function StopDrag()
            dragging = false
            thumb:SetScript("OnUpdate", nil)
        end
        thumb:EnableMouse(true)
        thumb:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then StartDrag() end
        end)
        thumb:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then StopDrag() end
        end)
        trackFrame:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local frac = CursorFrac()
            if frac then SetOpacity(MIN_ALPHA + frac * (MAX_ALPHA - MIN_ALPHA)) end
            StartDrag()
        end)
        trackFrame:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then StopDrag() end
        end)

        -- Mouse wheel on the whole area
        opacityFrame:EnableMouseWheel(true)
        opacityFrame:SetScript("OnMouseWheel", function(self, delta)
            local cur = mainFrame:GetAlpha()
            SetOpacity(cur + delta * 0.05)
        end)

        -- Orientation from the active theme. Sizes resolve a frame after the
        -- anchors change, so the thumb is re-placed on the next frame.
        local function Layout()
            local theme = EllesmereUI.GetActiveTheme()
            horizontal = (theme == "EllesmereUI" or theme == "EllesmereUI Forever")
            opacityFrame:ClearAllPoints()
            track:ClearAllPoints()
            trackFrame:ClearAllPoints()
            if horizontal then
                opacityFrame:SetSize(SLIDER_W, THUMB_W + 4)
                opacityFrame:SetPoint("LEFT", versionText, "RIGHT", 10, 0)
                track:SetSize(SLIDER_W, TRACK_W)
                track:SetPoint("LEFT", opacityFrame, "LEFT", 0, 0)
                track:SetPoint("RIGHT", opacityFrame, "RIGHT", 0, 0)
                thumb:SetSize(THUMB_H, THUMB_W)
                trackFrame:SetPoint("TOPLEFT", track, "TOPLEFT", 0, THUMB_W / 2)
                trackFrame:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -(THUMB_W / 2))
            else
                opacityFrame:SetSize(THUMB_W + 12, SLIDER_H + 26)
                opacityFrame:SetPoint("BOTTOM", versionText, "TOP", 0, 16)
                track:SetSize(TRACK_W, SLIDER_H)
                track:SetPoint("TOP", opacityFrame, "TOP", 0, -16)
                track:SetPoint("BOTTOM", opacityFrame, "BOTTOM", 0, 0)
                thumb:SetSize(THUMB_W, THUMB_H)
                trackFrame:SetPoint("TOPLEFT", track, "TOPLEFT", -(THUMB_W / 2), 0)
                trackFrame:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", (THUMB_W / 2), 0)
            end
            C_Timer.After(0, function() SetOpacity(currentAlpha) end)
        end
        EllesmereUI._layoutOpacitySlider = Layout

        -- First layout; its deferred re-place applies DEFAULT_A once the track has a size.
        Layout()
    end

    -- CPU metric keys for the sidebar performance tracker
    local CPU_METRICS = {}
    if Enum and Enum.AddOnProfilerMetric then
        CPU_METRICS = {
            { key = "SessionAvg",   enum = Enum.AddOnProfilerMetric.SessionAverageTime,   label = "Session Avg"   },
            { key = "RecentAvg",    enum = Enum.AddOnProfilerMetric.RecentAverageTime,    label = "Recent Avg"    },
            { key = "EncounterAvg", enum = Enum.AddOnProfilerMetric.EncounterAverageTime, label = "Encounter Avg" },
            { key = "Last",         enum = Enum.AddOnProfilerMetric.LastTime,             label = "Last"          },
            { key = "Peak",         enum = Enum.AddOnProfilerMetric.PeakTime,             label = "Peak"          },
        }
    end

    local function GatherEUICPU()
        local cpuByKey = {}
        for _, m in ipairs(CPU_METRICS) do cpuByKey[m.key] = 0 end
        for _, info in ipairs(ADDON_ROSTER) do
            if IsAddonLoaded(info.folder) then
                if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric then
                    for _, m in ipairs(CPU_METRICS) do
                        cpuByKey[m.key] = cpuByKey[m.key] + (C_AddOnProfiler.GetAddOnMetric(info.folder, m.enum) or 0)
                    end
                end
            end
        end
        return cpuByKey
    end

    -- Resource usage tracker (CPU for all EUI addons). Only ticks while the panel is
    -- visible: parented to sidebar, a descendant of mainFrame (hidden frames never tick).

    local resCpuText = MakeFont(sidebar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    resCpuText:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -20, 18)
    resCpuText:SetJustifyH("RIGHT")
    resCpuText:SetAlpha(0.5)

    local resCpuLabel = MakeFont(sidebar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    resCpuLabel:SetPoint("BOTTOMRIGHT", resCpuText, "TOPRIGHT", 0, 3)
    resCpuLabel:SetJustifyH("RIGHT")
    resCpuLabel:SetAlpha(0.5)
    resCpuLabel:SetText("CPU Usage:")

    local resPerfLabel = MakeFont(sidebar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    resPerfLabel:SetPoint("BOTTOMRIGHT", resCpuLabel, "TOPRIGHT", 0, 11)
    resPerfLabel:SetJustifyH("RIGHT")
    resPerfLabel:SetAlpha(0.5)
    resPerfLabel:SetText("All EUI Addons")

    local resDivider = sidebar:CreateTexture(nil, "ARTWORK")
    resDivider:SetColorTexture(1, 1, 1, 0.15)
    resDivider:SetHeight(1)
    resDivider:SetPoint("BOTTOMRIGHT", resPerfLabel, "BOTTOMRIGHT", 0, -5)
    resDivider:SetPoint("BOTTOMLEFT", resPerfLabel, "BOTTOMLEFT", 0, -5)

    local RES_UPDATE_INTERVAL = 5
    local UpdateResourceText

    UpdateResourceText = function()
        local cpuByKey = GatherEUICPU()
        local cpuVal = cpuByKey["RecentAvg"] or 0
        if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric then
            local fps = GetFramerate() or 0
            local pct = 0
            if fps > 0 then
                pct = cpuVal / (1000 / fps) * 100
            end
            resCpuText:SetText(EllesmereUI.COLOR_CODES.WHITE .. string.format("%.3f MS (%.1f%%)", cpuVal, pct) .. "|r")
        else
            resCpuText:SetText("|cffffffffN/A|r")
        end
    end

    local resUpdateFrame = CreateFrame("Frame", nil, sidebar)
    local resTicker
    resUpdateFrame:SetScript("OnShow", function()
        UpdateResourceText()
        if not resTicker then
            resTicker = C_Timer.NewTicker(RES_UPDATE_INTERVAL, UpdateResourceText)
        end
    end)
    resUpdateFrame:SetScript("OnHide", function()
        if resTicker then resTicker:Cancel(); resTicker = nil end
    end)

    -----------------------------------------------------------------------
    --  Right-side content region
    -----------------------------------------------------------------------
    local rightX = SIDEBAR_W
    local rightW = CLICK_W - SIDEBAR_W   -- 1030

    -- Header  (module title + description, sits over the banner artwork)
    headerFrame = CreateFrame("Frame", nil, clickArea)
    headerFrame:SetSize(rightW, HEADER_H)
    headerFrame:SetPoint("TOPLEFT", clickArea, "TOPLEFT", rightX, 0)
    headerFrame:SetFrameLevel(clickArea:GetFrameLevel() + 3)

    local headerTitle = MakeFont(headerFrame, 36, "", 1, 1, 1)
    headerTitle:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", CONTENT_PAD, -35)
    headerFrame._title = headerTitle

    local headerDesc = MakeFont(headerFrame, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    headerDesc:SetPoint("TOPLEFT", headerTitle, "BOTTOMLEFT", 2, -12)
    headerDesc:SetWidth(rightW - CONTENT_PAD * 2)
    headerDesc:SetJustifyH("LEFT")
    headerFrame._desc = headerDesc

    -----------------------------------------------------------------------
    --  Tab bar  (sits below the header, above scrollable content)
    -----------------------------------------------------------------------
    tabBar = CreateFrame("Frame", nil, clickArea)
    tabBar:SetSize(rightW, TAB_BAR_H)
    tabBar:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", -9, 0)
    tabBar:SetFrameLevel(clickArea:GetFrameLevel() + 4)

    tabBar._tabButtons = {}
    EllesmereUI._tabBar = tabBar

    -----------------------------------------------------------------------
    --  Content header  (optional non-scrolling region above the scroll area)
    --  Modules call EllesmereUI:SetContentHeader(buildFunc) to populate it.
    --  buildFunc(frame, width) should build UI into frame and return height.
    -----------------------------------------------------------------------
    local contentBaseTop = HEADER_H + TAB_BAR_H
    local contentMaxH    = CLICK_H - contentBaseTop - FOOTER_H

    contentHeaderFrame = CreateFrame("Frame", nil, clickArea)
    PanelPP.Size(contentHeaderFrame, rightW, 1)
    PanelPP.Point(contentHeaderFrame, "TOPLEFT", clickArea, "TOPLEFT", rightX, -contentBaseTop)
    contentHeaderFrame:SetFrameLevel(clickArea:GetFrameLevel() + 4)
    contentHeaderFrame:EnableMouseWheel(true)
    contentHeaderFrame:SetScript("OnMouseWheel", function(_, delta)
        if scrollFrame then scrollFrame:GetScript("OnMouseWheel")(scrollFrame, delta) end
    end)
    contentHeaderFrame:SetClipsChildren(true)
    contentHeaderFrame:Hide()
    EllesmereUI._contentHeader = contentHeaderFrame
    local contentHeaderH = 0   -- current header height

    -- Subtle background tint (only visible when header is active)
    local contentHeaderBg = contentHeaderFrame:CreateTexture(nil, "BACKGROUND")
    contentHeaderBg:SetColorTexture(0, 0, 0, 0.1)
    PanelPP.DisablePixelSnap(contentHeaderBg)
    contentHeaderBg:SetAllPoints()

    -- 1px divider at the bottom edge of the content header
    local contentHeaderDiv = contentHeaderFrame:CreateTexture(nil, "OVERLAY")
    contentHeaderDiv:SetColorTexture(1, 1, 1, 0.06)
    PanelPP.DisablePixelSnap(contentHeaderDiv)
    PanelPP.Point(contentHeaderDiv, "BOTTOMLEFT", contentHeaderFrame, "BOTTOMLEFT", 0, 0)
    PanelPP.Point(contentHeaderDiv, "BOTTOMRIGHT", contentHeaderFrame, "BOTTOMRIGHT", 0, 0)
    contentHeaderDiv:SetHeight(1)

    local function ApplyContentLayout()
        local wasSuppressed = suppressScrollRangeChanged
        suppressScrollRangeChanged = true

        scrollFrame:ClearAllPoints()
        PanelPP.Point(scrollFrame, "TOPLEFT", clickArea, "TOPLEFT", rightX, -(contentBaseTop + contentHeaderH))
        -- Anchor bottom to footer top so WoW resolves height from both edges, avoiding
        -- the PanelPP.Point vs PanelPP.Height rounding mismatch (1px flicker at the
        -- scroll area's bottom edge when the content header height changes).
        if footerFrame then
            PanelPP.Point(scrollFrame, "BOTTOMRIGHT", footerFrame, "TOPRIGHT", 0, 0)
        else
            local newH = contentMaxH - contentHeaderH
            PanelPP.Height(scrollFrame, newH)
        end

        suppressScrollRangeChanged = wasSuppressed
        UpdateScrollThumb()
    end

    -----------------------------------------------------------------------
    --  Scrollable content area
    -----------------------------------------------------------------------
    scrollFrame = CreateFrame("ScrollFrame", "EllesmereUIScrollFrame", clickArea)
    EllesmereUI._scrollFrame = scrollFrame
    PanelPP.Size(scrollFrame, rightW, contentMaxH)
    PanelPP.Point(scrollFrame, "TOPLEFT", clickArea, "TOPLEFT", rightX, -contentBaseTop)
    scrollFrame:SetFrameLevel(clickArea:GetFrameLevel() + 3)
    scrollFrame:EnableMouseWheel(true)
    -- Clip children to the viewport so off-screen widgets are skipped; without it every
    -- widget on the page renders each frame regardless of scroll position.
    scrollFrame:SetClipsChildren(true)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    PanelPP.Size(scrollChild, rightW, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Thin scrollbar  (hidden when content fits)
    local scrollTrack = CreateFrame("Frame", nil, scrollFrame)
    scrollTrack:SetWidth(4)
    scrollTrack:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -12, -4)
    scrollTrack:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -12, 4)
    scrollTrack:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)
    scrollTrack:Hide()

    local trackBg = SolidTex(scrollTrack, "BACKGROUND", 1, 1, 1, 0.02)
    trackBg:SetAllPoints()

    local scrollThumb = CreateFrame("Button", nil, scrollTrack)
    scrollThumb:SetWidth(4)
    scrollThumb:SetHeight(60)
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
    scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
    scrollThumb:EnableMouse(true)
    -- Register for drag so the thumb captures drag events before clickArea
    scrollThumb:RegisterForDrag("LeftButton")
    scrollThumb:SetScript("OnDragStart", function() end)
    scrollThumb:SetScript("OnDragStop", function() end)

    -- Invisible wider hit area so the scrollbar is easier to grab
    local scrollHitArea = CreateFrame("Button", nil, scrollFrame)
    scrollHitArea:SetWidth(16)
    scrollHitArea:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -6, -4)
    scrollHitArea:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -6, 4)
    scrollHitArea:SetFrameLevel(scrollTrack:GetFrameLevel() + 2)
    scrollHitArea:EnableMouse(true)
    scrollHitArea:RegisterForDrag("LeftButton")
    scrollHitArea:SetScript("OnDragStart", function() end)
    scrollHitArea:SetScript("OnDragStop", function() end)

    local thumbTex = SolidTex(scrollThumb, "ARTWORK", 1, 1, 1, 0.27)
    thumbTex:SetAllPoints()

    local SCROLL_STEP = 60
    local SMOOTH_SPEED = 12   -- lerp speed (higher = snappier, 10-15 feels good)
    local isDragging = false
    local dragStartY, dragStartScroll

    -- Smooth scroll state
    scrollTarget = 0
    isSmoothing = false

    local function StopScrollDrag()
        if not isDragging then return end
        isDragging = false
        scrollThumb:SetScript("OnUpdate", nil)
    end

    UpdateScrollThumb = function()
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
        if maxScroll <= 0 then
            scrollTrack:Hide()
            return
        end
        scrollTrack:Show()
        local trackH = scrollTrack:GetHeight()
        local visH   = scrollFrame:GetHeight()
        local visibleRatio = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * visibleRatio)
        scrollThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(scrollFrame:GetVerticalScroll()) or 0) / maxScroll
        local maxThumbTravel = trackH - thumbH
        scrollThumb:ClearAllPoints()
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * maxThumbTravel))
    end

    -- Smooth scroll OnUpdate: lerp toward scrollTarget then stop
    smoothFrame = CreateFrame("Frame")
    smoothFrame:Hide()
    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = scrollFrame:GetVerticalScroll()
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
        -- Snap max downward so we never try to scroll past a pixel-aligned boundary
        local scale = scrollFrame:GetEffectiveScale()
        maxScroll = math.floor(maxScroll * scale) / scale
        -- Re-clamp target in case scroll range changed
        scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            -- Close enough -- snap to target and stop
            scrollFrame:SetVerticalScroll(scrollTarget)
            UpdateScrollThumb()
            isSmoothing = false
            smoothFrame:Hide()
            return
        end
        local newScroll = cur + diff * math.min(1, SMOOTH_SPEED * elapsed)
        -- Clamp to valid range
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        -- Round toward the target so the last frames approach monotonically, never bouncing
        if diff > 0 then
            newScroll = math.ceil(newScroll * scale) / scale
        else
            newScroll = math.floor(newScroll * scale) / scale
        end
        -- Re-clamp after rounding (ceil could push past max)
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        scrollFrame:SetVerticalScroll(newScroll)
        UpdateScrollThumb()
    end)

    local function SmoothScrollTo(target)
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
        local scale = scrollFrame:GetEffectiveScale()
        -- Snap max downward so target never exceeds a pixel-aligned boundary
        maxScroll = math.floor(maxScroll * scale) / scale
        scrollTarget = math.max(0, math.min(maxScroll, target))
        -- Snap target to pixel boundary so content is pixel-perfect at rest
        scrollTarget = math.floor(scrollTarget * scale + 0.5) / scale
        -- Re-clamp after snapping (rounding could push above max)
        scrollTarget = math.min(scrollTarget, maxScroll)
        if not isSmoothing then
            isSmoothing = true
            smoothFrame:Show()
        end
    end
    EllesmereUI.SmoothScrollTo = SmoothScrollTo

    -- Current content scroll offset: the in-flight target while animating, else the
    -- settled position. Lets callers capture and restore scroll across a page rebuild.
    function EllesmereUI.GetContentScroll()
        if isSmoothing then return scrollTarget or 0 end
        return (scrollFrame and tonumber(scrollFrame:GetVerticalScroll())) or 0
    end

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = EllesmereUI.SafeScrollRange(self)
        if maxScroll <= 0 then return end
        -- Accumulate on top of the current target (not current position) for responsive chained scrolls
        local base = isSmoothing and scrollTarget or self:GetVerticalScroll()
        SmoothScrollTo(base - delta * SCROLL_STEP)
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(self)
        if suppressScrollRangeChanged then return end
        -- An offset past the new range would strand the view: the thumb hides
        -- and the wheel ignores a zero range, so pull it back in.
        local maxScroll = EllesmereUI.SafeScrollRange(self)
        if (tonumber(self:GetVerticalScroll()) or 0) > maxScroll then
            self:SetVerticalScroll(maxScroll)
            if scrollTarget > maxScroll then scrollTarget = maxScroll end
        end
        UpdateScrollThumb()
    end)

    local function ScrollThumbOnUpdate(self)
        -- Auto-release when mouse button is no longer held
        if not IsMouseButtonDown("LeftButton") then
            StopScrollDrag()
            return
        end
        -- Cancel any smooth animation during drag
        isSmoothing = false
        smoothFrame:Hide()
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local deltaY = dragStartY - cursorY
        local trackH = scrollTrack:GetHeight()
        local maxThumbTravel = trackH - self:GetHeight()
        if maxThumbTravel <= 0 then return end
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
        local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + (deltaY / maxThumbTravel) * maxScroll))
        -- Snap to whole pixels to prevent sub-pixel widget jitter
        local scale = scrollFrame:GetEffectiveScale()
        newScroll = math.floor(newScroll * scale + 0.5) / scale
        scrollTarget = newScroll
        scrollFrame:SetVerticalScroll(newScroll)
        UpdateScrollThumb()
    end

    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isSmoothing = false
        smoothFrame:Hide()
        isDragging = true
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / self:GetEffectiveScale()
        dragStartScroll = scrollFrame:GetVerticalScroll()
        self:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    scrollThumb:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    -- Hit area: click to jump + drag (same as track click but with wider target)
    scrollHitArea:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        -- Cancel any smooth animation
        isSmoothing = false
        smoothFrame:Hide()
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
        if maxScroll <= 0 then return end
        -- Jump to cursor position
        local _, cy = GetCursorPosition()
        cy = cy / scrollTrack:GetEffectiveScale()
        local top = scrollTrack:GetTop() or 0
        local trackH = scrollTrack:GetHeight()
        local thumbH = scrollThumb:GetHeight()
        if trackH <= thumbH then return end
        local frac = (top - cy - thumbH / 2) / (trackH - thumbH)
        frac = math.max(0, math.min(1, frac))
        local newScroll = frac * maxScroll
        local scale = scrollFrame:GetEffectiveScale()
        newScroll = math.floor(newScroll * scale + 0.5) / scale
        scrollTarget = newScroll
        scrollFrame:SetVerticalScroll(newScroll)
        UpdateScrollThumb()
        -- Begin dragging via thumb
        isDragging = true
        dragStartY = cy
        dragStartScroll = newScroll
        scrollThumb:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    scrollHitArea:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)
    -- Controller cursor: pointer-position controls are never stops, and its own
    -- scrolling of the content moves the thumb (the lerp and drag paint their own).
    EllesmereUI.PadHint(scrollThumb, "nodeignore")
    EllesmereUI.PadHint(scrollHitArea, "nodeignore")
    if EllesmereUI.PadCP() then
        scrollFrame:HookScript("OnVerticalScroll", function()
            if not isSmoothing and not isDragging then UpdateScrollThumb() end
        end)
    end

    contentFrame = scrollChild

    -----------------------------------------------------------------------
    --  Content header API  (non-scrolling region above scroll area)
    -----------------------------------------------------------------------
    local _contentHeaderCache = {}   -- keyed by "module::page"
    local _chStash = CreateFrame("Frame")  -- hidden off-screen stash for cached header children
    _chStash:Hide()

    local function ClearContentHeaderInner()
        local ch = { contentHeaderFrame:GetChildren() }
        for _, c in ipairs(ch) do c:Hide(); c:SetParent(nil) end
        local rg = { contentHeaderFrame:GetRegions() }
        for _, r in ipairs(rg) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then r:Hide(); r:SetParent(nil) end
        end
        contentHeaderFrame:Hide()
        contentHeaderFrame:SetHeight(1)
        contentHeaderH = 0
        ApplyContentLayout()
    end

    -- Cache the content header's children/regions, reparented to a hidden stash so
    -- ClearContentHeaderInner cannot destroy them while clearing for other pages.
    local function SaveContentHeaderToCache(cacheKey)
        if not contentHeaderFrame:IsShown() then return false end
        local children = { contentHeaderFrame:GetChildren() }
        local regions = {}
        for _, r in ipairs({ contentHeaderFrame:GetRegions() }) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then regions[#regions + 1] = r end
        end
        if #children == 0 and #regions == 0 then return false end
        -- Move children and regions to stash so ClearContentHeaderInner can't touch them
        for _, c in ipairs(children) do c:Hide(); c:SetParent(_chStash) end
        for _, r in ipairs(regions) do r:Hide(); r:SetParent(_chStash) end
        _contentHeaderCache[cacheKey] = {
            children = children,
            regions  = regions,
            height   = contentHeaderH,
        }
        contentHeaderFrame:Hide()
        contentHeaderFrame:SetHeight(1)
        contentHeaderH = 0
        ApplyContentLayout()
        return true
    end

    -- Restore a previously saved content header from cache.
    local function RestoreContentHeaderFromCache(cacheKey)
        local entry = _contentHeaderCache[cacheKey]
        if not entry then return false end
        -- Hide any current header children first (without orphaning)
        local ch = { contentHeaderFrame:GetChildren() }
        for _, c in ipairs(ch) do c:Hide() end
        local rg = { contentHeaderFrame:GetRegions() }
        for _, r in ipairs(rg) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then r:Hide() end
        end
        -- Reparent cached children and regions back to contentHeaderFrame and show
        for _, c in ipairs(entry.children) do c:SetParent(contentHeaderFrame); c:Show() end
        for _, r in ipairs(entry.regions) do r:SetParent(contentHeaderFrame); r:Show() end
        contentHeaderFrame:Show()
        contentHeaderH = entry.height
        PanelPP.Height(contentHeaderFrame, entry.height)
        ApplyContentLayout()
        return true
    end

    local function InvalidateContentHeaderCache()
        for key, entry in pairs(_contentHeaderCache) do
            for _, c in ipairs(entry.children) do c:Hide(); c:SetParent(nil) end
            for _, r in ipairs(entry.regions) do r:Hide(); r:SetParent(nil) end
            _contentHeaderCache[key] = nil
        end
    end

    function EllesmereUI:SetContentHeader(buildFunc)
        ClearContentHeaderInner()
        contentHeaderFrame:Show()
        local h = buildFunc(contentHeaderFrame, rightW) or 0
        contentHeaderH = h
        PanelPP.Height(contentHeaderFrame, h)
        ApplyContentLayout()
    end

    function EllesmereUI:UpdateContentHeaderHeight(h)
        if not contentHeaderFrame:IsShown() then return end
        local oldActualH = contentHeaderFrame:GetHeight()
        -- Save scroll state BEFORE ApplyContentLayout, which may clobber it
        -- if WoW returns a stale scroll range after the resize.
        local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll() or 0
        local savedTarget = scrollTarget
        contentHeaderH = h
        PanelPP.Height(contentHeaderFrame, h)
        -- Use the ACTUAL height change after PixelUtil snapping, not the requested
        -- delta: rounding to physical pixels at the frame's effective scale makes the
        -- real change differ from h-oldH by a sub-pixel amount (1px content shift).
        local newActualH = contentHeaderFrame:GetHeight()
        local delta = newActualH - oldActualH
        ApplyContentLayout()
        -- The scroll frame moved by |delta| px; scroll content the same to hold the viewport.
        if delta ~= 0 and scrollFrame then
            local adjusted = math.max(0, savedScroll + delta)
            scrollFrame:SetVerticalScroll(adjusted)
            if isSmoothing then
                scrollTarget = math.max(0, savedTarget + delta)
            else
                scrollTarget = adjusted
            end
            UpdateScrollThumb()
        end
    end

    -- Silent variant: resizes the header with no scroll compensation, for cosmetic
    -- height changes (buff icons toggled) that must not jump the scroll.
    function EllesmereUI:SetContentHeaderHeightSilent(h)
        if not contentHeaderFrame:IsShown() then return end
        contentHeaderH = h
        PanelPP.Height(contentHeaderFrame, h)
        ApplyContentLayout()
    end

    function EllesmereUI:ClearContentHeader()
        ClearContentHeaderInner()
    end

    -- Lightweight hide (no orphaning), for when the header is already cached.
    function EllesmereUI:HideContentHeader()
        local ch = { contentHeaderFrame:GetChildren() }
        for _, c in ipairs(ch) do c:Hide() end
        local rg = { contentHeaderFrame:GetRegions() }
        for _, r in ipairs(rg) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then r:Hide() end
        end
        contentHeaderFrame:Hide()
        contentHeaderFrame:SetHeight(1)
        contentHeaderH = 0
        ApplyContentLayout()
    end

    -- Expose cache functions for SelectPage (outside CreateMainFrame scope)
    function EllesmereUI:SaveContentHeaderToCache(cacheKey)
        return SaveContentHeaderToCache(cacheKey)
    end
    function EllesmereUI:RestoreContentHeaderFromCache(cacheKey)
        return RestoreContentHeaderFromCache(cacheKey)
    end
    function EllesmereUI:InvalidateContentHeaderCache()
        InvalidateContentHeaderCache()
    end

    -----------------------------------------------------------------------
    --  Footer  (Reset to Defaults + Reload UI | Done)
    -----------------------------------------------------------------------
    footerFrame = CreateFrame("Frame", nil, clickArea)
    PanelPP.Size(footerFrame, rightW, FOOTER_H)
    PanelPP.Point(footerFrame, "BOTTOMLEFT", clickArea, "BOTTOMLEFT", rightX, 0)
    footerFrame:SetFrameLevel(clickArea:GetFrameLevel() + 5)

    -----------------------------------------------------------------------
    --  Footer button hover colours  (tweak these to adjust fade targets)
    -----------------------------------------------------------------------
    -- Reset to Defaults / Reload UI  (white, muted)
    local RS_TEXT_R,   RS_TEXT_G,   RS_TEXT_B,   RS_TEXT_A   = 1, 1, 1, .5
    local RS_TEXT_HR,  RS_TEXT_HG,  RS_TEXT_HB,  RS_TEXT_HA  = 1, 1, 1, .7
    local RS_BRD_R,   RS_BRD_G,   RS_BRD_B,   RS_BRD_A     = 1, 1, 1, .4
    local RS_BRD_HR,  RS_BRD_HG,  RS_BRD_HB,  RS_BRD_HA   = 1, 1, 1, .6

    -- Helper: build a footer button with fade hover
    local function MakeFooterBtn(parent, w, h, anchorPoint, anchorTo, anchorRel, ax, ay,
                                  textR, textG, textB, textA, textHR, textHG, textHB, textHA,
                                  brdR, brdG, brdB, brdA, brdHR, brdHG, brdHB, brdHA,
                                  label, onClick)
        local btn = CreateFrame("Button", nil, parent)
        PanelPP.Size(btn, w, h)
        PanelPP.Point(btn, anchorPoint, anchorTo, anchorRel, ax, ay)
        btn:SetFrameLevel(parent:GetFrameLevel() + 1)
        local brd = MakeBorder(btn, brdR, brdG, brdB, brdA, PanelPP)
        local bg = SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, .92)
        bg:SetAllPoints()
        local lbl = MakeFont(btn, 13, nil, textR, textG, textB)
        lbl:SetAlpha(textA); lbl:SetPoint("CENTER"); lbl:SetText(EllesmereUI.L(label))
        btn._label = lbl
        do
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                lbl:SetTextColor(lerp(textR, textHR, t), lerp(textG, textHG, t), lerp(textB, textHB, t), lerp(textA, textHA, t))
                brd:SetColor(lerp(brdR, brdHR, t), lerp(brdG, brdHG, t), lerp(brdB, brdHB, t), lerp(brdA, brdHA, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target; self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
            btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
        end
        btn:SetScript("OnClick", function() if onClick then onClick() end end)
        return btn
    end

    local FOOTER_BTN_W, FOOTER_BTN_H = 180, 36
    local FOOTER_BTN_GAP = 20   -- gap between Reset and Reload
    local DONE_BTN_W = 160      -- Done button width
    local FOOTER_PAD = 24       -- symmetric inset from left/right edges
    local FOOTER_Y   = 24       -- vertical offset from bottom

    -- Reset button  (left side, FOOTER_PAD from left edge)
    local resetBtn = MakeFooterBtn(footerFrame, FOOTER_BTN_W, FOOTER_BTN_H,
        "BOTTOMLEFT", footerFrame, "BOTTOMLEFT", FOOTER_PAD, FOOTER_Y,
        RS_TEXT_R, RS_TEXT_G, RS_TEXT_B, RS_TEXT_A, RS_TEXT_HR, RS_TEXT_HG, RS_TEXT_HB, RS_TEXT_HA,
        RS_BRD_R, RS_BRD_G, RS_BRD_B, RS_BRD_A, RS_BRD_HR, RS_BRD_HG, RS_BRD_HB, RS_BRD_HA,
        "Reset", function()
            if not activeModule or not modules[activeModule] or not modules[activeModule].onReset then return end
            local config = modules[activeModule]
            local addonTitle = config.title or activeModule
            local msg = EllesmereUI.Lf("Are you sure you want to reset all %1$s settings to their defaults? This will reload your UI.", EllesmereUI.L(addonTitle))
            local disclaimer
            if activeModule == (EllesmereUI.GLOBAL_KEY or "_EUIGlobal") then
                disclaimer = "This will not reset addon-specific Quick Setup."
            end
            EllesmereUI:ShowConfirmPopup({
                title       = EllesmereUI.Lf("Reset %1$s", EllesmereUI.L(addonTitle)),
                message     = msg,
                disclaimer  = disclaimer,
                confirmText = "Reset & Reload",
                cancelText  = "Cancel",
                reload      = true,
                onConfirm   = function()
                    config.onReset()
                end,
            })
        end)
    footerFrame._resetBtn = resetBtn

    -- Reload UI  (next to Reset, 40px gap, same white/muted style)
    local reloadBtn = MakeFooterBtn(footerFrame, FOOTER_BTN_W, FOOTER_BTN_H,
        "BOTTOMLEFT", resetBtn, "BOTTOMRIGHT", FOOTER_BTN_GAP, 0,
        RS_TEXT_R, RS_TEXT_G, RS_TEXT_B, RS_TEXT_A, RS_TEXT_HR, RS_TEXT_HG, RS_TEXT_HB, RS_TEXT_HA,
        RS_BRD_R, RS_BRD_G, RS_BRD_B, RS_BRD_A, RS_BRD_HR, RS_BRD_HG, RS_BRD_HB, RS_BRD_HA,
        "Reload UI", function() EllesmereUI.RequestReload(EllesmereUI.L("Reload UI"), EllesmereUI.L("Reload the UI now?")) end)
    footerFrame._reloadBtn = reloadBtn
    -- WoW Forever: the click itself is the reload, no popup.
    EllesmereUI.AttachReloadClick(reloadBtn)

    -- Per-module Reset visibility: modules with no onReset (Patch Notes, Profiles) hide
    -- Reset and slide Reload UI left into its slot. Called from SelectModule.
    EllesmereUI._UpdateResetButtonVisible = function(hasReset)
        local rb, rl = footerFrame._resetBtn, footerFrame._reloadBtn
        if not rb or not rl then return end
        rl:ClearAllPoints()
        if hasReset then
            rb:Show()
            rl:SetPoint("BOTTOMLEFT", rb, "BOTTOMRIGHT", FOOTER_BTN_GAP, 0)
        else
            rb:Hide()
            rl:SetPoint("BOTTOMLEFT", footerFrame, "BOTTOMLEFT", FOOTER_PAD, FOOTER_Y)
        end
    end

    -- Social icons  (to the left of Done button)
    do
        local SOCIAL_SIZE = 40
        local SOCIAL_GAP  = 12
        local SOCIAL_ALPHA = 0.35
        local SOCIAL_HOVER = 0.70
        local SOCIAL_FADE  = 0.1

        -- Reusable link popup (created once, shared by all social icons)
        local linkPopup, linkBackdrop
        local function HideLinkPopup()
            if linkPopup then linkPopup:Hide() end
            if linkBackdrop then linkBackdrop:Hide() end
        end
        local function ShowLinkPopup(url, anchorBtn)
            if not linkPopup then
                -- Controller cursor: overlay parent (UIParent unless a controller cursor is loaded).
                local overlayParent = EllesmereUI.OverlayParent()
                linkBackdrop = CreateFrame("Button", nil, overlayParent)
                linkBackdrop:SetFrameStrata("DIALOG")
                linkBackdrop:SetFrameLevel(499)
                linkBackdrop:SetAllPoints(UIParent)
                local bdTex = linkBackdrop:CreateTexture(nil, "BACKGROUND")
                bdTex:SetAllPoints()
                bdTex:SetColorTexture(0, 0, 0, 0.20)
                local fadeIn = linkBackdrop:CreateAnimationGroup()
                fadeIn:SetToFinalAlpha(true)
                local a = fadeIn:CreateAnimation("Alpha")
                a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.2)
                linkBackdrop._fadeIn = fadeIn
                linkBackdrop:RegisterForClicks("AnyUp")
                linkBackdrop:SetScript("OnClick", HideLinkPopup)
                linkBackdrop:Hide()

                linkPopup = CreateFrame("Frame", nil, overlayParent)
                linkPopup:SetFrameStrata("DIALOG")
                linkPopup:SetFrameLevel(500)
                linkPopup:SetSize(380, 72)
                local popFade = linkPopup:CreateAnimationGroup()
                popFade:SetToFinalAlpha(true)
                local pa = popFade:CreateAnimation("Alpha")
                pa:SetFromAlpha(0); pa:SetToAlpha(1); pa:SetDuration(0.2)
                linkPopup._fadeIn = popFade

                local bg = SolidTex(linkPopup, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.97)
                bg:SetAllPoints()
                MakeBorder(linkPopup, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

                local hint = MakeFont(linkPopup, 11, nil, TEXT_SECTION.r, TEXT_SECTION.g, TEXT_SECTION.b, TEXT_SECTION.a)
                hint:SetPoint("TOP", linkPopup, "TOP", 0, -10)
                hint:SetText("Press Ctrl+C to copy, then Escape to close")

                local eb = CreateFrame("EditBox", nil, linkPopup)
                eb:SetSize(340, 26)
                eb:SetPoint("TOP", hint, "BOTTOM", 0, -8)
                eb:SetFontObject(GameFontHighlight)
                eb:SetAutoFocus(false)
                eb:SetJustifyH("CENTER")
                local ebBg = SolidTex(eb, "BACKGROUND", 0.10, 0.12, 0.16, 1)
                ebBg:SetPoint("TOPLEFT", -6, 4); ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
                MakeBorder(eb, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.02)
                eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); HideLinkPopup() end)
                eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
                linkPopup:EnableMouse(true)
                linkPopup:SetScript("OnMouseDown", function() linkPopup._eb:SetFocus(); linkPopup._eb:HighlightText() end)
                linkPopup._eb = eb
                -- Controller cursor: the backdrop blocks what is under it without being a stop.
                EllesmereUI.TrackOverlay(linkBackdrop)
                EllesmereUI.TrackOverlay(linkPopup)
                EllesmereUI.PadHint(linkBackdrop, "nodepass")
                -- Controller cursor: its cancel press clicks the backdrop, which closes.
                if EllesmereUI.PadCP() then linkPopup.CloseButton = linkBackdrop end
            end
            linkPopup._eb:SetText(url)
            linkPopup:ClearAllPoints()
            linkPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 8)
            linkBackdrop:SetAlpha(0); linkBackdrop:Show(); linkBackdrop._fadeIn:Play()
            linkPopup:SetAlpha(0); linkPopup:Show(); linkPopup._fadeIn:Play()
            linkPopup._eb:SetFocus(); linkPopup._eb:HighlightText()
        end

        local socialDefs = {
            { icon = ICONS_PATH .. "twitch-2.png",  url = "https://www.twitch.tv/ellesmere_gaming", tooltip = "Twitch" },
            { icon = ICONS_PATH .. "discord-2.png", url = "https://discord.gg/FtCsUSC",             tooltip = "Discord" },
            { icon = ICONS_PATH .. "donate-3.png",  url = "https://www.patreon.com/ellesmere",       tooltip = "Patreon" },
            { icon = ICONS_PATH .. "paypal.png",    url = "https://www.paypal.biz/ellesmeregaming",  tooltip = "PayPal" },
        }

        -- Anchor: rightmost icon sits SOCIAL_GAP to the left of where Done starts
        -- Done is at BOTTOMRIGHT -FOOTER_PAD, so first icon anchor = Done left edge - gap
        local prevAnchor = nil
        for i = #socialDefs, 1, -1 do
            local def = socialDefs[i]
            local btn = CreateFrame("Button", nil, footerFrame)
            PanelPP.Size(btn, SOCIAL_SIZE, SOCIAL_SIZE)
            btn:SetFrameLevel(footerFrame:GetFrameLevel() + 1)
            if not prevAnchor then
                -- Rightmost icon: anchor relative to Done button position
                PanelPP.Point(btn, "BOTTOMRIGHT", footerFrame, "BOTTOMRIGHT",
                    -(FOOTER_PAD + DONE_BTN_W + SOCIAL_GAP + 15), FOOTER_Y + (FOOTER_BTN_H - SOCIAL_SIZE) / 2)
            else
                PanelPP.Point(btn, "RIGHT", prevAnchor, "LEFT", -SOCIAL_GAP, 0)
            end
            prevAnchor = btn

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture(def.icon)
            tex:SetAlpha(SOCIAL_ALPHA)
            PanelPP.DisablePixelSnap(tex)

            local progress, target = 0, 0
            local function Apply(t)
                tex:SetAlpha(lerp(SOCIAL_ALPHA, SOCIAL_HOVER, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / SOCIAL_FADE)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target; self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            btn:SetScript("OnEnter", function(self)
                target = 1; self:SetScript("OnUpdate", OnUpdate)
                if def.tooltip and EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, def.tooltip)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                target = 0; self:SetScript("OnUpdate", OnUpdate)
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            btn:SetScript("OnClick", function() ShowLinkPopup(def.url, btn) end)
        end
    end

    -- Close  (right side, FOOTER_PAD from right edge, green, closes window)
    do
        local btn = CreateFrame("Button", nil, footerFrame)
        PanelPP.Size(btn, DONE_BTN_W, FOOTER_BTN_H)
        PanelPP.Point(btn, "BOTTOMRIGHT", footerFrame, "BOTTOMRIGHT", -FOOTER_PAD, FOOTER_Y)
        btn:SetFrameLevel(footerFrame:GetFrameLevel() + 1)
        local brd = MakeBorder(btn, ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 0.7, PanelPP)
        local bg = SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, .92)
        bg:SetAllPoints()
        local lbl = MakeFont(btn, 13, nil, ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b)
        lbl:SetAlpha(0.7); lbl:SetPoint("CENTER"); lbl:SetText(EllesmereUI.L("Close"))
        -- Hover animation reads from ELLESMERE_GREEN live
        local FADE_DUR = 0.1
        local progress, target = 0, 0
        local function Apply(t)
            local EG = ELLESMERE_GREEN
            lbl:SetTextColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
            brd:SetColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
        end
        local function OnUpdate(self, elapsed)
            local dir = (target == 1) and 1 or -1
            progress = progress + dir * (elapsed / FADE_DUR)
            if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                progress = target; self:SetScript("OnUpdate", nil)
            end
            Apply(progress)
        end
        btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
        btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
        btn:SetScript("OnClick", function() if mainFrame then mainFrame:Hide() end end)
        -- Register for accent updates
        RegAccent({ type="callback", fn=function(r, g, b)
            lbl:SetTextColor(r, g, b, lerp(0.7, 1, progress))
            brd:SetColor(r, g, b, lerp(0.7, 1, progress))
        end })
    end

    return mainFrame
end

-------------------------------------------------------------------------------
--  Tab Bar helpers
-------------------------------------------------------------------------------
-- Display-only tab label overrides ([page identity] = shown label), registered by module options
-- files. Page IDENTITY stays the original string everywhere else (SelectPage, nav targets, unlock elements, spec overrides, saved state); only the tab text changes.
EllesmereUI.TAB_LABEL_OVERRIDES = EllesmereUI.TAB_LABEL_OVERRIDES or {}

ClearTabs = function()
    for _, btn in ipairs(tabBar._tabButtons) do btn:Hide(); btn:SetParent(nil) end
    wipe(tabBar._tabButtons)
end

CreateTabButton = function(index, name)
    local btn = CreateFrame("Button", nil, tabBar)
    btn:SetHeight(TAB_BAR_H)
    btn:SetFrameLevel(tabBar:GetFrameLevel() + 1)

    local label = MakeFont(btn, 16, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    label:SetPoint("CENTER", 0, 0)
    label:SetText(EllesmereUI.L(EllesmereUI.TAB_LABEL_OVERRIDES[name] or name))
    btn._label = label
    btn._name  = name

    local textW = label:GetStringWidth() or 60
    btn:SetWidth(textW + 30)

    -- Teal underline for active tab
    local underline = SolidTex(btn, "ARTWORK", ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
    underline:SetSize(textW + 14, 2)
    underline:SetPoint("BOTTOM", btn, "BOTTOM", 0, 0)
    underline:Hide()
    btn._underline = underline
    RegAccent({ type="solid", obj=underline, a=1 })

    btn:SetScript("OnEnter", function(self)
        if activePage ~= self._name then self._label:SetTextColor(1, 1, 1, 0.86) end
    end)
    btn:SetScript("OnLeave", function(self)
        if activePage ~= self._name then self._label:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a) end
    end)
    btn:SetScript("OnClick", function(self) EllesmereUI:SelectPage(self._name) end)

    return btn
end

BuildTabs = function(pageNames, disabledPages, disabledTooltips)
    ClearTabs()
    if not pageNames or #pageNames == 0 then tabBar:SetHeight(0.001); return end
    tabBar:SetHeight(TAB_BAR_H)
    local disabledSet = {}
    if disabledPages then
        for _, name in ipairs(disabledPages) do disabledSet[name] = true end
    end
    local xOff = CONTENT_PAD
    for i, name in ipairs(pageNames) do
        local btn = CreateTabButton(i, name)
        btn:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", xOff, 0)
        xOff = xOff + btn:GetWidth() + 6
        tabBar._tabButtons[i] = btn
        -- Disable tab if in disabledPages list
        if disabledSet[name] then
            btn:EnableMouse(true)  -- keep mouse enabled for tooltip
            btn._label:SetAlpha(0.30)
            btn._disabled = true
            local tip = disabledTooltips and disabledTooltips[name]
            if tip then
                btn:SetScript("OnEnter", function(self)
                    if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(self, tip) end
                end)
                btn:SetScript("OnLeave", function()
                    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                end)
            end
            -- Swallow clicks on disabled tabs
            btn:SetScript("OnClick", function() end)
        end
    end

    ---------------------------------------------------------------------------
    --  Inline search EditBox  (right-aligned in tab bar, always visible)
    ---------------------------------------------------------------------------
    if not tabBar._searchBox then
        local SEARCH_W, SEARCH_H = 210, 28
        local searchFrame = CreateFrame("Frame", nil, tabBar)
        searchFrame:SetSize(SEARCH_W, SEARCH_H)
        searchFrame:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", -10, (TAB_BAR_H - SEARCH_H) / 2 + 2)
        searchFrame:SetFrameLevel(tabBar:GetFrameLevel() + 2)

        local searchBg = SolidTex(searchFrame, "BACKGROUND", STYLE.SL_INPUT_R, STYLE.SL_INPUT_G, STYLE.SL_INPUT_B, STYLE.SL_INPUT_A + 0.10)
        searchBg:SetAllPoints()
        local searchBrd = MakeBorder(searchFrame, STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.10)

        local editBox = CreateFrame("EditBox", nil, searchFrame)
        editBox:SetAllPoints()
        editBox:SetAutoFocus(false)
        editBox:SetFont(EllesmereUI.EXPRESSWAY, 13, "")
        editBox:SetTextColor(STYLE.TEXT_WHITE_R, STYLE.TEXT_WHITE_G, STYLE.TEXT_WHITE_B, 1)
        editBox:SetTextInsets(10, 24, 0, 0)
        editBox:SetMaxLetters(40)

        local placeholder = MakeFont(searchFrame, 12, nil, STYLE.TEXT_DIM_R, STYLE.TEXT_DIM_G, STYLE.TEXT_DIM_B, 0.3)
        placeholder:SetPoint("LEFT", searchFrame, "LEFT", 10, 0)
        placeholder:SetText(EllesmereUI.L("Search Module Settings..."))

        -- Clear button (X) on right side -- frame level above editBox so clicks register
        local clearBtn = CreateFrame("Button", nil, searchFrame)
        clearBtn:SetSize(20, 20)
        clearBtn:SetPoint("RIGHT", searchFrame, "RIGHT", -4, 0)
        clearBtn:SetFrameLevel(editBox:GetFrameLevel() + 2)
        clearBtn:Hide()
        local clearLabel = MakeFont(clearBtn, 15, nil, STYLE.TEXT_DIM_R, STYLE.TEXT_DIM_G, STYLE.TEXT_DIM_B, 0.35)
        clearLabel:SetPoint("CENTER")
        clearLabel:SetText("x")
        clearBtn:SetScript("OnEnter", function() clearLabel:SetTextColor(1, 1, 1, 1) end)
        clearBtn:SetScript("OnLeave", function() clearLabel:SetTextColor(STYLE.TEXT_DIM_R, STYLE.TEXT_DIM_G, STYLE.TEXT_DIM_B, 0.35) end)
        clearBtn:SetScript("OnClick", function()
            editBox:SetText("")
            editBox:ClearFocus()
        end)

        -- Border hover effect
        searchFrame:SetScript("OnEnter", function() searchBrd:SetColor(STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.15) end)
        searchFrame:SetScript("OnLeave", function() searchBrd:SetColor(STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.10) end)
        editBox:SetScript("OnEditFocusGained", function() searchBrd:SetColor(STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.15) end)
        editBox:SetScript("OnEditFocusLost", function() searchBrd:SetColor(STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.10) end)

        local searchDebounceTimer
        editBox:SetScript("OnTextChanged", function(self, userInput)
            local text = self:GetText() or ""
            if text == "" then
                placeholder:Show()
                clearBtn:Hide()
            else
                placeholder:Hide()
                clearBtn:Show()
            end
            if searchDebounceTimer then searchDebounceTimer:Cancel(); searchDebounceTimer = nil end
            EllesmereUI:ApplyInlineSearch(text, true)
            if text ~= "" then
                searchDebounceTimer = C_Timer.NewTimer(0.5, function()
                    searchDebounceTimer = nil
                    EllesmereUI:ApplyInlineSearch(text)
                end)
            end
        end)

        editBox:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
        end)

        editBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)

        tabBar._searchBox = editBox
        tabBar._searchFrame = searchFrame

        -- Spec Override capture toggle (left of the search box). All look
        -- and behavior live in EllesmereUI_SpecOverrides.lua.
        if EllesmereUI.SpecOverrides_SetupButton then
            local soBtn = CreateFrame("Button", nil, tabBar)
            soBtn:SetSize(26, 26)
            soBtn:SetPoint("RIGHT", searchFrame, "LEFT", -10, 0)
            soBtn:SetFrameLevel(tabBar:GetFrameLevel() + 2)
            EllesmereUI.SpecOverrides_SetupButton(soBtn)
            tabBar._specOvBtn = soBtn
        end
        -- Conditional Overrides has no toolbar button: its cards render as a second section in the spec popup.
    end
    tabBar._searchFrame:Show()
    -- Clear search text when tabs are rebuilt (module switch)
    if tabBar._searchBox:GetText() ~= "" then
        tabBar._searchBox:SetText("")
    end

    -- Defer a relayout so GetStringWidth returns correct values after render
    tabBar:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local x = CONTENT_PAD
        for _, b in ipairs(self._tabButtons) do
            local tw = b._label:GetStringWidth() or 60
            b:SetWidth(tw + 30)
            if b._underline then b._underline:SetWidth(tw + 14) end
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
            x = x + b:GetWidth() + 6
        end
    end)
end

UpdateTabHighlight = function(selectedName)
    for _, btn in ipairs(tabBar._tabButtons) do
        if btn._disabled then
            -- disabled tab: keep dimmed, no underline
        elseif btn._name == selectedName then
            btn._label:SetTextColor(1, 1, 1, 1)
            btn._underline:Show()
        else
            btn._label:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            btn._underline:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Inline Search  (filter sections on the current page)
-------------------------------------------------------------------------------
local _pageCache  -- forward declaration; initialized below in page-cache section
-- Pool of reusable highlight border frames (accent-colored, fade-in only)
local _searchHighlightPool = {}
local _searchHighlightsActive = {}

local function GetSearchHighlight()
    local hl = table.remove(_searchHighlightPool)
    if not hl then
        hl = CreateFrame("Frame")
        local c = ELLESMERE_GREEN
        local function MkEdge()
            local t = hl:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(c.r, c.g, c.b, 1)
            return t
        end
        hl._top = MkEdge()
        hl._bot = MkEdge()
        hl._lft = MkEdge()
        hl._rgt = MkEdge()
        hl._top:SetHeight(1)
        hl._top:SetPoint("TOPLEFT"); hl._top:SetPoint("TOPRIGHT")
        hl._bot:SetHeight(1)
        hl._bot:SetPoint("BOTTOMLEFT"); hl._bot:SetPoint("BOTTOMRIGHT")
        hl._lft:SetWidth(1)
        hl._lft:SetPoint("TOPLEFT", hl._top, "BOTTOMLEFT")
        hl._lft:SetPoint("BOTTOMLEFT", hl._bot, "TOPLEFT")
        hl._rgt:SetWidth(1)
        hl._rgt:SetPoint("TOPRIGHT", hl._top, "BOTTOMRIGHT")
        hl._rgt:SetPoint("BOTTOMRIGHT", hl._bot, "TOPRIGHT")
    end
    _searchHighlightsActive[#_searchHighlightsActive + 1] = hl
    return hl
end

local function RecycleAllSearchHighlights()
    for i = #_searchHighlightsActive, 1, -1 do
        local hl = _searchHighlightsActive[i]
        hl:Hide()
        hl:SetScript("OnUpdate", nil)
        hl:ClearAllPoints()
        _searchHighlightPool[#_searchHighlightPool + 1] = hl
        _searchHighlightsActive[i] = nil
    end
end

local function PlaySearchHighlight(hl, targetFrame)
    hl:SetParent(targetFrame)
    hl:SetAllPoints(targetFrame)
    hl:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
    hl:SetAlpha(0)
    hl:Show()
    local elapsed = 0
    hl:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.3 then
            self:SetAlpha(0.5)
            self:SetScript("OnUpdate", nil)
            return
        end
        self:SetAlpha(0.5 * (elapsed / 0.3))
    end)
end

EllesmereUI.PlaySearchHighlight = PlaySearchHighlight
EllesmereUI.GetSearchHighlight = GetSearchHighlight

-- Collect a wrapper's direct children sorted by original Y (top to bottom) into sections
-- { header=frame, members={frame,...} }: each child belongs to the nearest section header above
-- it, children before any header become leading orphans. Split column containers (_leftCol/_rightCol) are single blocks -- searched inside, never re-anchored per child.
local function CollectAllChildren(wrapper)
    local children = { wrapper:GetChildren() }
    -- Save original anchor info on first encounter so we can restore later.
    for _, child in ipairs(children) do
        if not child._origAnchor then
            local point, rel, relPoint, x, y = child:GetPoint(1)
            if point then
                child._origAnchor = { point, rel, relPoint, x, y }
            end
        end
        -- For split containers, build a searchable label from all children inside
        if child._leftCol or child._rightCol then
            if not child._splitSearchLabels then
                local labels = {}
                local labelsLoc = {}
                local function GatherLabels(col)
                    if not col then return end
                    local subs = { col:GetChildren() }
                    for _, sub in ipairs(subs) do
                        if sub._sectionName then labels[#labels + 1] = sub._sectionName; labelsLoc[#labelsLoc + 1] = sub._sectionNameLoc or sub._sectionName end
                        if sub._labelText then labels[#labels + 1] = sub._labelText; labelsLoc[#labelsLoc + 1] = sub._labelTextLoc or sub._labelText end
                    end
                end
                GatherLabels(child._leftCol)
                GatherLabels(child._rightCol)
                child._splitSearchLabels = table.concat(labels, " ")
                -- Bilingual search: localized variant, only stored when it differs (nil on English).
                local _loc = table.concat(labelsLoc, " ")
                if _loc ~= child._splitSearchLabels then child._splitSearchLabelsLoc = _loc end
            end
        end
    end
    table.sort(children, function(a, b)
        local ay = a._origAnchor and a._origAnchor[5] or 0
        local by = b._origAnchor and b._origAnchor[5] or 0
        return ay > by  -- y offsets are negative, so higher (less negative) = higher on page
    end)

    local sections = {}       -- { { header=frame, members={frame,...} }, ... }
    local orphans  = {}       -- children before any section header
    local current  = nil      -- current section entry

    for _, child in ipairs(children) do
        if child._searchIgnore then
            -- Managed outside the inline search (e.g. party sync overlays); never
            -- collect it so the search can't re-anchor or hide/show it.
        elseif child._isSectionHeader then
            current = { header = child, members = {} }
            sections[#sections + 1] = current
        elseif current then
            current.members[#current.members + 1] = child
        else
            orphans[#orphans + 1] = child
        end
    end
    return sections, orphans
end

function EllesmereUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
    -- For split rows (DualRow etc.), narrow a deep-link highlight to the half/slot whose own
    -- label matches instead of pulsing the whole row; returns that child region, or nil to fall
    -- back to the full row. Inline, not a file-scope local: the main chunk is at the 200-local cap.
    local function ResolveHighlightSlot(row, text)
        if not text or not row.GetChildren then return nil end
        local locText = EllesmereUI.L(text) or text
        for _, region in ipairs({ row:GetChildren() }) do
            local lbl = region._label
            if lbl and lbl.GetText then
                local t = lbl:GetText()
                if t and t ~= "" and (t:find(text, 1, true) or (locText ~= text and t:find(locText, 1, true))) then
                    return region
                end
            end
        end
        return nil
    end

    -- First-open split (see _SplitFirstOpen): Show() below returns without
    -- building the panel on the session's first open, so run the whole deep
    -- link next frame rather than navigating a panel that does not exist yet.
    if self:_SplitFirstOpen(function()
        EllesmereUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
    end) then return end

    self:Show()
    self:SelectModule(moduleName)
    self:SelectPage(pageName)

    -- Switch dropdown AFTER the page is loaded, then force a full rebuild.
    -- This mirrors exactly what the dropdown's own onChange handler does.
    if preSelectFn then
        preSelectFn()
        self:InvalidateContentHeaderCache()
        local config = modules[moduleName]
        if config and config.getHeaderBuilder then
            local hb = config.getHeaderBuilder(pageName)
            if hb then self:SetContentHeader(hb) end
        end
        self:RefreshPage(true)
    end

    C_Timer.After(0.05, function()
        local cacheKey = moduleName .. "::" .. pageName
        local cached = _pageCache[cacheKey]
        if not cached or not cached.wrapper then return end

        local sections = CollectAllChildren(cached.wrapper)
        for _, sec in ipairs(sections) do
            if sec.header._sectionName == sectionName then
                -- Find the row to scroll to; narrow the highlight to the matching
                -- slot (DualRow half) when possible, otherwise pulse the whole row.
                local target = sec.header
                local hlTarget = sec.header
                if highlightText then
                    for _, m in ipairs(sec.members) do
                        if (m._labelText and m._labelText:find(highlightText, 1, true))
                           or (m._labelTextLoc and m._labelTextLoc:find(highlightText, 1, true)) then
                            target = m
                            hlTarget = ResolveHighlightSlot(m, highlightText) or m
                            break
                        end
                    end
                end

                local a = target._origAnchor
                if a then
                    local scrollPos = math.abs(a[5]) - 40
                    EllesmereUI.SmoothScrollTo(scrollPos)
                    C_Timer.After(0.15, function()
                        local hl = GetSearchHighlight()
                        PlaySearchHighlight(hl, hlTarget)
                    end)
                end
                return
            end
        end
    end)
end

-- Searchable label for any child frame. On translated clients the localized variant is
-- appended so search matches either language; on English the *Loc fields are nil.
local function GetSearchLabel(child)
    local en = child._labelText or child._sectionName or child._splitSearchLabels
    if not en then return "" end
    local loc = child._labelTextLoc or child._sectionNameLoc or child._splitSearchLabelsLoc
    if loc then return en .. " " .. loc end
    return en
end

-- Resolve the current display text of a dropdown on a region (if any)
local function GetDropdownValueText(region)
    if not region._ddGetValue or not region._ddValues then return nil end
    local key = region._ddGetValue()
    if key == nil then return nil end
    local val = region._ddValues[key]
    if val == nil then return nil end
    if type(val) == "table" then return val.text end
    return tostring(val)
end

function EllesmereUI:ApplyInlineSearch(query, skipHighlights)
    if not activeModule or not activePage then return end
    -- Active search force-expands every "Show Less Common" section (links hidden);
    -- clearing collapses back to session state. MUST run before the cache lookup below:
    -- a state transition rebuilds and replaces this page's cache entry.
    if EllesmereUI.SetLessCommonSearchActive then
        EllesmereUI.SetLessCommonSearchActive(query ~= nil and query ~= "")
    end
    local cacheKey = activeModule .. "::" .. activePage
    local cached = _pageCache[cacheKey]
    if not cached or not cached.wrapper then return end

    -- Per-page search-state hook (e.g. the party tab hides its sync overlays
    -- while a search is active). Fires for both filtering and restore.
    if EllesmereUI._onInlineSearch then EllesmereUI._onInlineSearch(query or "") end

    RecycleAllSearchHighlights()

    local sections, orphans = CollectAllChildren(cached.wrapper)

    -- Empty query: restore everything
    if not query or query == "" then
        for _, sec in ipairs(sections) do
            sec.header:Show()
            if sec.header._origAnchor then
                sec.header:ClearAllPoints()
                local a = sec.header._origAnchor
                PanelPP.Point(sec.header, a[1], a[2], a[3], a[4], a[5])
            end
            for _, m in ipairs(sec.members) do
                m:Show()
                if m._origAnchor then
                    m:ClearAllPoints()
                    local a = m._origAnchor
                    PanelPP.Point(m, a[1], a[2], a[3], a[4], a[5])
                end
            end
        end
        for _, o in ipairs(orphans) do
            o:Show()
            if o._origAnchor then
                o:ClearAllPoints()
                local a = o._origAnchor
                PanelPP.Point(o, a[1], a[2], a[3], a[4], a[5])
            end
        end
        -- Restore original scroll height
        contentFrame:SetHeight(cached.totalH + 30)
        if scrollFrame and scrollFrame.SetVerticalScroll then
            scrollTarget = 0
            isSmoothing = false
            if smoothFrame then smoothFrame:Hide() end
            scrollFrame:SetVerticalScroll(0)
            UpdateScrollThumb()
        end
        cached._searchFiltered = nil
        return
    end

    local queryLower = query:lower()

    -- Determine which sections are visible and which rows/slots match
    local visibleSections = {}
    for _, sec in ipairs(sections) do
        local sectionName = sec.header._sectionName or ""
        local sectionMatch = sectionName:lower():find(queryLower, 1, true)
        -- Bilingual: also match the localized section name on translated clients.
        if not sectionMatch and sec.header._sectionNameLoc then
            sectionMatch = sec.header._sectionNameLoc:lower():find(queryLower, 1, true)
        end
        -- Per-page section exclusion hook (e.g. the party tab hides sections that
        -- are synced with raid settings). Only consulted during a live search.
        local excluded = EllesmereUI._searchExcludeSection
            and EllesmereUI._searchExcludeSection(sectionName)

        local anyMemberMatch = false
        local matchingMembers = {}
        for _, m in ipairs(sec.members) do
            local label = GetSearchLabel(m)
            local matched = label ~= "" and label:lower():find(queryLower, 1, true)
            if not matched then
                -- Also check current dropdown selected values on this row's regions
                for _, rgn in ipairs({ m._leftRegion, m._midRegion, m._rightRegion }) do
                    if rgn then
                        local ddText = GetDropdownValueText(rgn)
                        if ddText and ddText:lower():find(queryLower, 1, true) then
                            matched = true; break
                        end
                    end
                end
            end
            if matched then
                anyMemberMatch = true
                matchingMembers[m] = true
            end
        end

        if (sectionMatch or anyMemberMatch) and not excluded then
            visibleSections[#visibleSections + 1] = {
                sec = sec,
                sectionMatch = sectionMatch,
                matchingMembers = matchingMembers,
            }
        else
            sec.header:Hide()
            for _, m in ipairs(sec.members) do m:Hide() end
        end
    end

    -- Orphans are by construction the LEADING widgets on a page: created before its first
    -- SectionHeader call, so _currentSection is nil when TagOptionRow tags them. Match them like
    -- section members instead of hiding them unconditionally, or a query matching only an orphan (a lead "Activate X" button) leaves the page empty.
    local visibleOrphans = {}
    for _, o in ipairs(orphans) do
        local label = GetSearchLabel(o)
        local matched = label ~= "" and label:lower():find(queryLower, 1, true)
        if not matched then
            for _, rgn in ipairs({ o._leftRegion, o._midRegion, o._rightRegion }) do
                if rgn then
                    local ddText = GetDropdownValueText(rgn)
                    if ddText and ddText:lower():find(queryLower, 1, true) then
                        matched = true; break
                    end
                end
            end
        end
        if matched then
            visibleOrphans[#visibleOrphans + 1] = o
        else
            o:Hide()
        end
    end

    -- Build per-slot highlight targets and count totals to decide if we suppress
    -- highlights (when every visible slot is highlighted, none should glow).
    local highlightTargets = {}  -- list of { frame = region_or_member }
    local totalSlots = 0
    local highlightedSlots = 0

    for _, vs in ipairs(visibleSections) do
        for _, m in ipairs(vs.sec.members) do
            -- Skip spacer frames -- they have no content to highlight
            if m._isSpacer then
                -- still counts as nothing
            else
            -- Collect the slots this member exposes
            local slots = {}
            if m._leftRegion then
                slots[#slots + 1] = { region = m._leftRegion,  label = m._leftRegion._slotLabel  or "" }
            end
            if m._midRegion then
                slots[#slots + 1] = { region = m._midRegion,   label = m._midRegion._slotLabel   or "" }
            end
            if m._rightRegion then
                slots[#slots + 1] = { region = m._rightRegion, label = m._rightRegion._slotLabel or "" }
            end

            if #slots > 0 then
                -- Split row: check each slot individually
                for _, s in ipairs(slots) do
                    if s.label ~= "" then
                        totalSlots = totalSlots + 1
                        local slotMatch = s.label:lower():find(queryLower, 1, true)
                        if not slotMatch then
                            local ddText = GetDropdownValueText(s.region)
                            if ddText then slotMatch = ddText:lower():find(queryLower, 1, true) end
                        end
                        if vs.sectionMatch or slotMatch then
                            highlightedSlots = highlightedSlots + 1
                            highlightTargets[#highlightTargets + 1] = s.region
                        end
                    end
                end
            else
                -- Non-split row: whole member is one slot
                totalSlots = totalSlots + 1
                local label = GetSearchLabel(m)
                local memberMatch = label ~= "" and label:lower():find(queryLower, 1, true)
                if vs.sectionMatch or memberMatch then
                    highlightedSlots = highlightedSlots + 1
                    highlightTargets[#highlightTargets + 1] = m
                end
            end
            end -- _isSpacer else
        end
    end

    -- Same slot/highlight accounting for visible orphans: they already passed the match check, so unlike section members there is no "section matched" bypass to OR in.
    for _, o in ipairs(visibleOrphans) do
        if not o._isSpacer then
            local slots = {}
            if o._leftRegion then slots[#slots + 1] = { region = o._leftRegion,  label = o._leftRegion._slotLabel  or "" } end
            if o._midRegion  then slots[#slots + 1] = { region = o._midRegion,   label = o._midRegion._slotLabel   or "" } end
            if o._rightRegion then slots[#slots + 1] = { region = o._rightRegion, label = o._rightRegion._slotLabel or "" } end

            if #slots > 0 then
                for _, s in ipairs(slots) do
                    if s.label ~= "" then
                        totalSlots = totalSlots + 1
                        local slotMatch = s.label:lower():find(queryLower, 1, true)
                        if not slotMatch then
                            local ddText = GetDropdownValueText(s.region)
                            if ddText then slotMatch = ddText:lower():find(queryLower, 1, true) end
                        end
                        if slotMatch then
                            highlightedSlots = highlightedSlots + 1
                            highlightTargets[#highlightTargets + 1] = s.region
                        end
                    end
                end
            else
                totalSlots = totalSlots + 1
                highlightedSlots = highlightedSlots + 1
                highlightTargets[#highlightTargets + 1] = o
            end
        end
    end

    -- If every visible slot is highlighted, suppress all highlights
    local suppressHighlights = (highlightedSlots >= totalSlots)

    -- Build a fast lookup for highlight targets
    local hlSet = {}
    if not suppressHighlights then
        for _, target in ipairs(highlightTargets) do
            hlSet[target] = true
        end
    end

    -- Re-anchor visible items sequentially from top
    local startY = -6
    local y = startY

    -- Matching orphans lead the page (always before the first section in the source
    -- layout), so place and highlight them first; the sections loop continues from y.
    for _, o in ipairs(visibleOrphans) do
        if o._isSpacer then
            o:Hide()
        else
            local ox = o._origAnchor and o._origAnchor[4] or CONTENT_PAD
            o:ClearAllPoints()
            PanelPP.Point(o, "TOPLEFT", cached.wrapper, "TOPLEFT", ox, y)
            o:Show()

            if not suppressHighlights and not skipHighlights then
                if o._leftRegion and hlSet[o._leftRegion] then
                    local hl = GetSearchHighlight(); PlaySearchHighlight(hl, o._leftRegion)
                end
                if o._midRegion and hlSet[o._midRegion] then
                    local hl = GetSearchHighlight(); PlaySearchHighlight(hl, o._midRegion)
                end
                if o._rightRegion and hlSet[o._rightRegion] then
                    local hl = GetSearchHighlight(); PlaySearchHighlight(hl, o._rightRegion)
                end
                if not o._leftRegion and hlSet[o] then
                    local hl = GetSearchHighlight(); PlaySearchHighlight(hl, o)
                end
            end

            y = y - o:GetHeight()
        end
    end

    for _, vs in ipairs(visibleSections) do
        local sec = vs.sec
        local hdrX = sec.header._origAnchor and sec.header._origAnchor[4] or CONTENT_PAD
        sec.header:ClearAllPoints()
        PanelPP.Point(sec.header, "TOPLEFT", cached.wrapper, "TOPLEFT", hdrX, y)
        sec.header:Show()
        y = y - sec.header:GetHeight()

        for _, m in ipairs(sec.members) do
            -- Hide spacers during search -- they're just empty gaps
            if m._isSpacer then
                m:Hide()
            else
            local mx = m._origAnchor and m._origAnchor[4] or CONTENT_PAD
            m:ClearAllPoints()
            PanelPP.Point(m, "TOPLEFT", cached.wrapper, "TOPLEFT", mx, y)
            m:Show()

            if not suppressHighlights and not skipHighlights then
                -- Check slot-level highlights for split rows
                if m._leftRegion and hlSet[m._leftRegion] then
                    local hl = GetSearchHighlight()
                    PlaySearchHighlight(hl, m._leftRegion)
                end
                if m._midRegion and hlSet[m._midRegion] then
                    local hl = GetSearchHighlight()
                    PlaySearchHighlight(hl, m._midRegion)
                end
                if m._rightRegion and hlSet[m._rightRegion] then
                    local hl = GetSearchHighlight()
                    PlaySearchHighlight(hl, m._rightRegion)
                end
                -- Non-split row highlight
                if not m._leftRegion and hlSet[m] then
                    local hl = GetSearchHighlight()
                    PlaySearchHighlight(hl, m)
                end
            end

            y = y - m:GetHeight()
            end -- _isSpacer else
        end
    end

    -- Resize content to fit visible items only
    local visibleH = math.abs(y - startY)
    contentFrame:SetHeight(visibleH + 30)

    if scrollFrame and scrollFrame.SetVerticalScroll then
        scrollTarget = 0
        isSmoothing = false
        if smoothFrame then smoothFrame:Hide() end
        scrollFrame:SetVerticalScroll(0)
        UpdateScrollThumb()
    end
    -- Mark this page as currently search-filtered so it is reliably restored when
    -- shown again, even if the search box was cleared on a tab/module switch.
    cached._searchFiltered = true
end

-------------------------------------------------------------------------------
--  Sidebar highlight  (icon on/off swap)
-------------------------------------------------------------------------------
UpdateSidebarHighlight = function(selectedFolder)
    for folder, btn in pairs(sidebarButtons) do
        btn._hoverGlow:Hide()
        btn._hoverIndicator:Hide()
        if folder == selectedFolder then
            btn._indicator:Show()
            btn._glow:Show()
            btn._glowTop:Show()
            btn._glowBot:Show()
            btn._label:SetTextColor(NAV_SELECTED_TEXT.r, NAV_SELECTED_TEXT.g, NAV_SELECTED_TEXT.b, NAV_SELECTED_TEXT.a)
            if btn._icon then
                btn._icon:SetTexture(btn._iconOff)
                btn._icon:SetDesaturated(false)
                btn._icon:SetAlpha(NAV_SELECTED_ICON_A)
            end
            if btn._iconGlow then btn._iconGlow:Show() end
        else
            btn._indicator:Hide()
            btn._glow:Hide()
            btn._glowTop:Hide()
            btn._glowBot:Hide()
            if btn._iconGlow then btn._iconGlow:Hide() end
            if btn._loaded then
                btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
                if btn._icon then
                    btn._icon:SetTexture(btn._iconOff)
                    btn._icon:SetDesaturated(false)
                    btn._icon:SetAlpha(NAV_ENABLED_ICON_A)
                end
            else
                btn._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
                if btn._icon then
                    btn._icon:SetDesaturated(true)
                    btn._icon:SetAlpha(NAV_DISABLED_ICON_A)
                end
            end
        end
    end
    -- Controller cursor: the selected row is its first stop when the window opens.
    if EllesmereUI.PadCP() then
        for folder, btn in pairs(sidebarButtons) do
            EllesmereUI.PadHint(btn, "nodepriority", folder == selectedFolder and 1 or false)
        end
    end
end

-------------------------------------------------------------------------------
--  Content clearing
-------------------------------------------------------------------------------
-- WoW frames are permanent C objects that can never be freed, so orphaning with
-- SetParent(nil) leaks the same memory: Hide() everything in place instead. buildPage
-- creates new frames on top and hidden ones cost nothing to render.
ClearContent = function()
    if not scrollChild then return end
    -- Clear widget refresh registry
    ClearWidgetRefreshList()
    -- Clear content header (non-scrolling region) if active
    if EllesmereUI.ClearContentHeader then
        EllesmereUI:ClearContentHeader()
    end
    -- Reset alternating row counters
    ResetRowCounters()
    -- Clear per-page layout flags so they don't bleed into the next page
    if scrollChild then scrollChild._showRowDivider = nil end
    -- Hide copy popup if visible
    if EllesmereUI._copyPopup then EllesmereUI._copyPopup:Hide() end
    if EllesmereUI._copyBackdrop then EllesmereUI._copyBackdrop:Hide() end
    -- Disconnect children: frames can never be freed, but SetParent(nil) removes them
    -- from the render/layout hierarchy so they stop accumulating under scrollChild.
    local children = { scrollChild:GetChildren() }
    for _, child in ipairs(children) do child:Hide(); child:SetParent(nil) end
    local regions = { scrollChild:GetRegions() }
    for _, region in ipairs(regions) do region:Hide(); region:SetParent(nil) end
end

-------------------------------------------------------------------------------
--  SPLIT COLUMN LAYOUT
--  Creates two side-by-side scrollable column frames with a 1px divider.
--  Usage:  local left, right, splitFrame = EllesmereUI:CreateSplitColumns(parent, yOffset)
--  Widgets anchor to left/right using the same TOPLEFT + yOffset pattern.
--  Call splitFrame:SetHeight(maxH) after populating both columns.
-------------------------------------------------------------------------------
function EllesmereUI:CreateSplitColumns(parent, yOffset)
    local PAD = 20        -- space between column edge and divider
    local DIV_W = 1       -- divider width
    local totalW = parent:GetWidth()
    local colW = math.floor((totalW - PAD * 2 - DIV_W) / 2)

    local splitFrame = CreateFrame("Frame", nil, parent)
    splitFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset or 0)
    splitFrame:SetWidth(totalW)
    splitFrame:SetHeight(1)  -- caller sets final height

    local leftCol = CreateFrame("Frame", nil, splitFrame)
    leftCol:SetPoint("TOPLEFT", splitFrame, "TOPLEFT", 0, 0)
    leftCol:SetSize(colW, 1)

    local divider = splitFrame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.08)
    divider:SetWidth(DIV_W)
    divider:SetPoint("TOP", splitFrame, "TOP", 0, 0)
    divider:SetPoint("BOTTOM", splitFrame, "BOTTOM", 0, 0)

    local rightCol = CreateFrame("Frame", nil, splitFrame)
    rightCol:SetPoint("TOPRIGHT", splitFrame, "TOPRIGHT", 0, 0)
    rightCol:SetSize(colW, 1)

    splitFrame._leftCol  = leftCol
    splitFrame._rightCol = rightCol
    splitFrame._divider  = divider
    splitFrame._colW     = colW

    -- Mark columns with split parent so RowBg can extend backgrounds full width
    leftCol._splitParent  = splitFrame
    rightCol._splitParent = splitFrame

    return leftCol, rightCol, splitFrame
end

-------------------------------------------------------------------------------
--  Module Registration (suite only)
--  RegisterModule is the suite's own entry point. Third-party addons use
--  EllesmereUI.RegisterPlugin (see the Plugin API section), which can only create
--  new sidebar sections. RegisterModule stays closed to them:
--   * the caller's file must resolve to a trusted folder; a caller without a file
--     path (loadstring chunks, calls routed through C functions) is rejected;
--   * outside standalone builds the only trusted caller is the options addon, and
--     only while the core itself is loading it (EUI_NS.CoreRegistrationOpen), so a
--     suite key cannot be claimed ahead of the real registration;
--   * only suite keys are accepted (roster folders + the fixed panel pages), and
--     each one is sealed on first registration: it cannot be registered again.
-------------------------------------------------------------------------------
do
    -- Non-roster suite pages that register through RegisterModule.
    local CORE_PAGE_KEYS = {
        [EllesmereUI.GLOBAL_KEY] = true,
        _EUIProfiles   = true,
        _EUIPatchNotes = true,
    }
    local sealed = {}

    -- Shared tail of every accepted registration. Only reachable from the
    -- trusted paths below and from the plugin registry.
    function EUI_NS.StoreModule(folderName, config)
        sealed[folderName] = true
        modules[folderName] = config
        -- If the UI is built, update the sidebar button now; else RefreshSidebarStates does it on first open
        local btn = sidebarButtons[folderName]
        if btn then
            btn._loaded = true
            btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            if btn._icon then
                btn._icon:SetDesaturated(false)
                btn._icon:SetAlpha(NAV_ENABLED_ICON_A)
            end
        end
        -- Don't auto-select here; RefreshSidebarStates handles default selection in roster order
    end

    function EUI_NS.IsModuleKeyTaken(folderName)
        return sealed[folderName] == true
    end

    -- Internal registration for pages the core file builds itself (no caller check).
    function EUI_NS.RegisterCoreModule(folderName, config, isCore)
        if type(folderName) ~= "string" or type(config) ~= "table" then return false end
        if sealed[folderName] or EUI_NS.IsPluginKey(folderName) then return false end
        config._euiCore = isCore == true
        config._plugin = nil
        EUI_NS.StoreModule(folderName, config)
        return true
    end

    function EllesmereUI:RegisterModule(folderName, config)
        if type(folderName) ~= "string" or type(config) ~= "table" then return end
        -- Only allow registration from EllesmereUI addon files.
        -- Extract the addon folder name from the caller's file path.
        local caller = debugstack(2, 1, 0) or ""
        local callerFolder = caller:match("AddOns/([^/]+)/")
        -- NaowhUI_EUI registers its own page, from its files or from a loadstring chunk.
        if folderName == "NaowhUI_EUI" and (callerFolder == nil or callerFolder == folderName)
           and EUI_NS.navInfo[folderName] and C_AddOns.IsAddOnLoaded(folderName) then
            EUI_NS.RegisterCoreModule(folderName, config, false)
            return
        end
        if not callerFolder then return end
        local ALLOWED = {
            EllesmereUI = true,
            EllesmereUIOptions = true,  -- the LoadOnDemand options surface: every module's options file registers from here
            EllesmereUIActionBars = true,
            EllesmereUIAuraBuffReminders = true,
            EllesmereUICooldownManager = true,
            EllesmereUINameplates = true,
            EllesmereUIPartyMode = true,
            EllesmereUIRaidFrames = true,
            EllesmereUIResourceBars = true,
            EllesmereUIUnitFrames = true,
            EllesmereUIMythicTimer = true,
            -- v6.6 split
            EllesmereUIQoL = true,
            EllesmereUIBlizzardSkin = true,
            EllesmereUIQuestTracker = true,
            EllesmereUIMinimap = true,
            EllesmereUIFriends = true,
            EllesmereUIChat = true,
            EllesmereUIDamageMeters = true,
            EllesmereUIBags = true,
            EllesmereUIDataBars = true,
            EllesmereUIQuickdraw = true,
            EllesmereUIForeverEssentials = true,
        }
        if IS_STANDALONE then
            -- Options files are bundled flat into the one standalone addon.
            if not ALLOWED[callerFolder] then return end
        else
            if callerFolder ~= "EllesmereUIOptions" or not EUI_NS.CoreRegistrationOpen() then return end
        end
        if not (EUI_NS.navInfo[folderName] or CORE_PAGE_KEYS[folderName]) then return end
        if sealed[folderName] then return end
        -- Suite-core marker (module key is a suite folder), gating the toolbar whitelists:
        -- the overrides icon renders for core modules only, the inline search for core
        -- modules + Global Settings. Companion/external pages stay unmarked, so neither
        -- control renders for them (see SelectModule).
        config._euiCore = ALLOWED[folderName] == true
        config._plugin = nil
        EUI_NS.StoreModule(folderName, config)
    end
end

-------------------------------------------------------------------------------
--  Page / Module Selection
-------------------------------------------------------------------------------
-- Page cache: maps "moduleName::pageName" -> { wrapper, totalH, headerBuilder }
-- On revisit, we show the cached wrapper and refresh widget values instead of rebuilding.
_pageCache = {}
-- Private: an entry's headerBuilder / wrapper is live page content, so the
-- cache is shared with the core files only (global search reads it).
EUI_NS.pageCache = _pageCache
local _activePageWrapper  -- the currently-visible wrapper frame

-- Invalidate all cached pages (called on profile reset, module reload, etc.)
function EllesmereUI:InvalidatePageCache()
    for key, entry in pairs(_pageCache) do
        if entry.wrapper then
            entry.wrapper:Hide()
            entry.wrapper:SetParent(nil)
        end
        _pageCache[key] = nil
    end
    _activePageWrapper = nil
    if EllesmereUI.InvalidateContentHeaderCache then
        EllesmereUI:InvalidateContentHeaderCache()
    end
end

-- Invalidate cached pages for a SINGLE module (key prefix "Module::"), e.g. on spec change
-- where only the per-spec module's pages go stale. Panel OPEN: the shown page's wrapper is kept
-- so the screen is not blanked (the caller rebuilds it in place via RefreshPage(true)). Panel
-- CLOSED: every cached page is dropped for a fresh build. Teardown matches RefreshPage: Hide + SetParent(nil) the wrapper, then drop the entry.
function EllesmereUI:InvalidateModulePageCache(moduleName)
    if not moduleName then return end
    local prefix = moduleName .. "::"
    local keepKey
    if self.IsShown and self:IsShown() and activeModule and activePage then
        keepKey = activeModule .. "::" .. activePage
    end
    for key, entry in pairs(_pageCache) do
        if key:sub(1, #prefix) == prefix and key ~= keepKey then
            if entry.wrapper then
                entry.wrapper:Hide()
                entry.wrapper:SetParent(nil)
            end
            _pageCache[key] = nil
        end
    end
end

function EllesmereUI:SelectPage(pageName)
    -- Excluded pages (CDM Bar Glows / Tracking Bars) lock during an override editing
    -- session: their systems keep their own per-spec storage, outside the capture.
    if EllesmereUI.SpecOverrides_EditSessionActive
       and EllesmereUI.SpecOverrides_EditSessionActive()
       and EllesmereUI.SpecOverrides_PageExcluded
       and EllesmereUI.SpecOverrides_PageExcluded(activeModule, pageName) then
        return
    end
    if not activeModule or not modules[activeModule] then return end
    if pageName == activePage then return end

    -- "Unlock Mode" is a fake nav item -- fire unlock mode without changing page state.
    -- Capture the current module + page so DoClose can restore them exactly.
    if pageName == "Unlock Mode" then
        if EllesmereUI._openUnlockMode then
            EllesmereUI._unlockReturnModule = activeModule
            EllesmereUI._unlockReturnPage   = activePage
            C_Timer.After(0, EllesmereUI._openUnlockMode)
        end
        return
    end

    -- "Disable Addons" is a fake nav item -- close EUI and open the Blizzard addon list.
    if pageName == "Disable Addons" then
        if EllesmereUI._mainFrame then EllesmereUI._mainFrame:Hide() end
        C_Timer.After(0, function()
            if not AddonList then
                C_AddOns.LoadAddOn("Blizzard_AddonList")
            end
            if AddonList then ShowUIPanel(AddonList) end
        end)
        return
    end

    -- Restore the page's inline-search filter and clear the box BEFORE switching activePage:
    -- SetText("") fires ApplyInlineSearch("") via OnTextChanged, which keys off activePage, so it
    -- must still point at the filtered page or it stays stuck in its filtered layout (looks "searched" with an empty box) until re-search.
    if tabBar and tabBar._searchBox and tabBar._searchBox:GetText() ~= "" then
        tabBar._searchBox:SetText("")
    end

    -- Save current page's refresh list before switching
    if activePage then
        local oldKey = activeModule .. "::" .. activePage
        if _pageCache[oldKey] then
            local rl = _pageCache[oldKey].refreshList
            if not rl then rl = {}; _pageCache[oldKey].refreshList = rl end
            -- Wipe and repopulate in-place
            for i = #rl, 1, -1 do rl[i] = nil end
            for i = 1, #_widgetRefreshList do
                rl[i] = _widgetRefreshList[i]
            end
        end
        -- Save current content header to cache before leaving this page
        EllesmereUI:SaveContentHeaderToCache(oldKey)
    end

    activePage = pageName
    _lastPagePerModule[activeModule] = pageName
    UpdateTabHighlight(pageName)

    local cacheKey = activeModule .. "::" .. pageName
    local cached = _pageCache[cacheKey]

    -- Reconcile the two independent caches before the fast path. The page wrapper (_pageCache)
    -- and the content-header PREVIEW (_contentHeaderCache) cache separately, but the preview's
    -- interactive hit overlays are created ONLY by buildPage. If InvalidateContentHeaderCache ran
    -- while this page's wrapper stayed cached, a header-only SetContentHeader rebuild recreates
    -- the preview with NO overlays -- visible but dead to hover/click until /reload. So a page
    -- that HAS a preview but misses its header cache discards the stale wrapper (RefreshPage teardown) and falls through to a cold rebuild; pages without a headerBuilder stay on the fast path.
    if cached and cached.wrapper then
        HideAllChildren(scrollChild)
        if not EllesmereUI:RestoreContentHeaderFromCache(cacheKey) then
            if cached.headerBuilder then
                cached.wrapper:Hide()
                cached.wrapper:SetParent(nil)
                _pageCache[cacheKey] = nil
                cached = nil
            elseif EllesmereUI.ClearContentHeader then
                EllesmereUI:ClearContentHeader()
            end
        end
    end

    if cached and cached.wrapper then
        -- Fast path (both caches in sync): show the cached wrapper, set child height
        cached.wrapper:Show()
        _activePageWrapper = cached.wrapper
        contentFrame:SetHeight(cached.totalH + 30)

        -- Restore elements hidden by a previous inline search, keyed off the page's own filtered
        -- flag and NOT the search box: clearing the box on a tab/module switch does not reliably
        -- restore the page being left, so a cached page can stay filtered while the box reads empty. The flag tracks the real state.
        if cached._searchFiltered then
            EllesmereUI:ApplyInlineSearch("")
        end

        -- Restore this page's refresh list
        ClearWidgetRefreshList()
        if cached.refreshList then
            for i = 1, #cached.refreshList do
                _widgetRefreshList[i] = cached.refreshList[i]
            end
        end

        -- Refresh all widget values in-place
        for i = 1, #_widgetRefreshList do _widgetRefreshList[i]() end

        -- Fire module-level refresh hooks (preview update, etc.)
        local config = modules[activeModule]
        if config.onPageCacheRestore then config.onPageCacheRestore(pageName) end
    else
        -- Cold path: build page for the first time
        HideAllChildren(scrollChild)

        -- Clear content header
        lastHeaderPadded = false
        ClearWidgetRefreshList()
        ResetRowCounters()
        if EllesmereUI._copyPopup then EllesmereUI._copyPopup:Hide() end
        if EllesmereUI._copyBackdrop then EllesmereUI._copyBackdrop:Hide() end
        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end

        -- Create a wrapper frame for this page
        local wrapper = CreateFrame("Frame", nil, scrollChild)
        wrapper:SetAllPoints(scrollChild)
        _activePageWrapper = wrapper

        local config = modules[activeModule]
        local totalH = 0
        if config.buildPage then
            local startY = -6

            EllesmereUI._buildingModule = activeModule
            EllesmereUI._buildingPage = pageName
            totalH = config.buildPage(pageName, wrapper, startY) or 600
            EllesmereUI._buildingModule = nil
            EllesmereUI._buildingPage = nil
            EllesmereUI._buildingSelector = nil
            contentFrame:SetHeight(totalH + 30)
        end

        -- Capture the content header builder for this page (if one was set)
        local headerBuilder = nil
        if config.getHeaderBuilder then
            headerBuilder = config.getHeaderBuilder(pageName)
        end

        -- Cache this page's refresh list
        local cachedRefreshList = {}
        for i = 1, #_widgetRefreshList do
            cachedRefreshList[i] = _widgetRefreshList[i]
        end

        _pageCache[cacheKey] = {
            wrapper = wrapper,
            totalH = totalH,
            headerBuilder = headerBuilder,
            refreshList = cachedRefreshList,
        }
    end

    -- Reset scroll to top on tab switch
    if scrollFrame and scrollFrame.SetVerticalScroll then
        scrollTarget = 0
        isSmoothing = false
        if smoothFrame then smoothFrame:Hide() end
        scrollFrame:SetVerticalScroll(0)
        UpdateScrollThumb()
    end

    -- Re-snap PP borders after a tab switch: cached frames re-show without
    -- CreateBorder's built-in 2-frame re-snap, so borders misalign until reopen. Wait
    -- 1 frame so the hierarchy has finished layout before recalculating effective scales.
    C_Timer.After(0, function()
        if PP and PP.ResnapBordersUnder and _activePageWrapper then
            PP.ResnapBordersUnder(_activePageWrapper)
        elseif PP and PP.ResnapAllBorders then
            PP.ResnapAllBorders()
        end
    end)
end

-- Rebuild the current page content without resetting scroll position
-- Pass force=true to bypass the fast refresh path (e.g. when widget layout changes).
function EllesmereUI:RefreshPage(force)
    if not activeModule or not activePage then return end
    -- Fast path: if widgets registered refresh callbacks, just re-read
    -- DB values in-place.  No frame teardown, no allocations.
    if not force and #_widgetRefreshList > 0 then
        for i = 1, #_widgetRefreshList do _widgetRefreshList[i]() end
        return
    end
    -- Panel hidden: a rebuild here would run buildPage with nothing on screen, firing page-open
    -- side effects (preview flags, placeholder shows) AFTER the OnHide cleanup already cleared
    -- them -- they then stick until the next open (e.g. CDM buff previews staying visible when
    -- an override edit session tears down on panel close). Defer the rebuild to the next show instead; the on-show callback below consumes the flag before module OnShow handlers run.
    -- Folded to the mini window counts as hidden: a page built under the hidden body
    -- never shows, so its OnHide teardown (page-scoped event listeners) never runs.
    -- The unfold consumes the flag (EllesmereUI._SetPanelCollapsed).
    if not (mainFrame and mainFrame:IsShown()) or EllesmereUI._panelCollapsed then
        EllesmereUI._pendingForceRefresh = true
        return
    end
    -- Slow path: full teardown + rebuild
    local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll() or 0
    local savedTarget = scrollTarget

    -- Invalidate the current page's cache entry and destroy ONLY its wrapper. CRITICAL: do NOT
    -- call ClearContent() here -- it calls SetParent(nil) on ALL scrollChild children, which
    -- orphans other cached pages' wrappers. Those wrappers are still referenced by _pageCache and
    -- will be restored when the user switches back to that tab; if orphaned, Show() makes them appear detached and the layout breaks ("settings fly all over the screen" bug).
    local cacheKey = activeModule .. "::" .. activePage
    local oldEntry = _pageCache[cacheKey]
    if oldEntry and oldEntry.wrapper then
        oldEntry.wrapper:Hide()
        oldEntry.wrapper:SetParent(nil)
    end
    _pageCache[cacheKey] = nil

    -- Clear widget refresh registry and header (safe -- these are per-page)
    ClearWidgetRefreshList()
    if EllesmereUI.ClearContentHeader then
        EllesmereUI:ClearContentHeader()
    end
    ResetRowCounters()
    if scrollChild then scrollChild._showRowDivider = nil end
    if EllesmereUI._copyPopup then EllesmereUI._copyPopup:Hide() end
    if EllesmereUI._copyBackdrop then EllesmereUI._copyBackdrop:Hide() end

    skipScrollChildReanchor = true
    suppressScrollRangeChanged = true

    -- Create a fresh wrapper for the rebuilt page
    local wrapper = CreateFrame("Frame", nil, scrollChild)
    wrapper:SetAllPoints(scrollChild)

    local config = modules[activeModule]
    local totalH = 0
    if config.buildPage then
        local startY = -6
        EllesmereUI._buildingModule = activeModule
        EllesmereUI._buildingPage = activePage
        totalH = config.buildPage(activePage, wrapper, startY) or 600
        EllesmereUI._buildingModule = nil
        EllesmereUI._buildingPage = nil
        EllesmereUI._buildingSelector = nil
        contentFrame:SetHeight(totalH + 30)
    end

    -- Re-cache
    local headerBuilder = nil
    if config.getHeaderBuilder then
        headerBuilder = config.getHeaderBuilder(activePage)
    end
    local cachedRefreshList = {}
    for i = 1, #_widgetRefreshList do
        cachedRefreshList[i] = _widgetRefreshList[i]
    end
    _pageCache[cacheKey] = {
        wrapper = wrapper,
        totalH = totalH,
        headerBuilder = headerBuilder,
        refreshList = cachedRefreshList,
    }

    skipScrollChildReanchor = false
    suppressScrollRangeChanged = false
    isSmoothing = false
    if smoothFrame then smoothFrame:Hide() end
    if scrollFrame then
        -- The range is stale right after the height change; recompute it so a
        -- shrunken page (card collapsed) clamps instead of keeping the old offset.
        scrollFrame:UpdateScrollChildRect()
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
        local restored = math.min(savedScroll, maxScroll)
        scrollTarget = math.min(savedTarget, maxScroll)
        scrollFrame:SetVerticalScroll(restored)
        UpdateScrollThumb()
    end
    -- The rebuilt wrapper is unfiltered while the search box still holds its text (a
    -- section-gate toggle clicked under a live search): re-apply the query so the page
    -- stays filtered. Highlights are skipped, like the box's own immediate pass.
    local sbox = tabBar and tabBar._searchBox
    local sq = sbox and sbox:GetText() or ""
    if sq ~= "" then
        EllesmereUI:ApplyInlineSearch(sq, true)
        -- The filter pass scrolls to the top (its keystroke behaviour); put the user
        -- back where the click happened, clamped to the filtered range.
        if scrollFrame then
            local maxFiltered = EllesmereUI.SafeScrollRange(scrollFrame)
            local back = math.min(savedScroll, maxFiltered)
            scrollTarget = back
            scrollFrame:SetVerticalScroll(back)
            UpdateScrollThumb()
        end
    end
end

-- Consume a rebuild that was requested while the panel was hidden (see the deferral
-- inside RefreshPage). Registered here, before any module files load, so it runs ahead
-- of module OnShow callbacks -- they then observe the freshly rebuilt page.
EllesmereUI:RegisterOnShow(function()
    if EllesmereUI._pendingForceRefresh then
        EllesmereUI._pendingForceRefresh = nil
        EllesmereUI:RefreshPage(true)
    end
end)

-- Public: snap the settings scroll back to the top (e.g. in resource bars clicking on a
-- simple section to the Advanced page)
function EllesmereUI:ScrollToTop()
    if scrollFrame and scrollFrame.SetVerticalScroll then
        scrollTarget = 0
        isSmoothing = false
        if smoothFrame then smoothFrame:Hide() end
        scrollFrame:SetVerticalScroll(0)
        UpdateScrollThumb()
    end
end

function EllesmereUI:GetActiveModule()
    return activeModule
end

function EllesmereUI:GetModuleTitle(folderName)
    local m = folderName and modules[folderName]
    return m and m.title
end

function EllesmereUI:SelectModule(folderName)
    if not modules[folderName] then return end
    -- The panel is not always built when we get here: on the session's first
    -- open the first-open split (see _SplitFirstOpen) makes Show()/Toggle()
    -- return BEFORE CreateMainFrame, so a caller that opens the panel and
    -- selects a module in the same execution arrives with headerFrame nil.
    -- Bail before activeModule is written -- a half-applied selection also
    -- suppresses CreateMainFrame's default-module pick, leaving a blank panel.
    if not headerFrame then return end
    if folderName == activeModule then return end
    -- Excluded modules are locked while an override editing session is
    -- active; blocking at the choke point covers every navigation path
    -- (sidebar, list rows, links), not just the grayed buttons.
    if EllesmereUI.SpecOverrides_EditSessionActive
       and EllesmereUI.SpecOverrides_EditSessionActive()
       and EllesmereUI.SpecOverrides_ModuleExcluded
       and EllesmereUI.SpecOverrides_ModuleExcluded(folderName) then
        return
    end

    -- Re-sync pixel perfect mult on every addon switch
    if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end

    -- Save current page's content header under the CORRECT old key
    -- before we overwrite activeModule.
    if activePage and activeModule then
        local oldKey = activeModule .. "::" .. activePage
        if _pageCache[oldKey] then
            local rl = _pageCache[oldKey].refreshList
            if not rl then rl = {}; _pageCache[oldKey].refreshList = rl end
            for i = #rl, 1, -1 do rl[i] = nil end
            for i = 1, #_widgetRefreshList do
                rl[i] = _widgetRefreshList[i]
            end
        end
        EllesmereUI:SaveContentHeaderToCache(oldKey)
    end

    -- Notify the module being left (mirrors onReset). No-op if unset.
    if activeModule and modules[activeModule] and modules[activeModule].onModuleLeave then
        modules[activeModule].onModuleLeave()
    end

    -- Restore the old module page's inline-search filter and clear the search box BEFORE
    -- switching modules, while activeModule/activePage still point to the filtered page.
    -- SetText("") fires ApplyInlineSearch("") via OnTextChanged; doing this after the switch would target the new module and leave the old page stuck in its filtered layout.
    if tabBar and tabBar._searchBox and tabBar._searchBox:GetText() ~= "" then
        tabBar._searchBox:SetText("")
    end

    activeModule = folderName
    local config = modules[folderName]
    UpdateSidebarHighlight(folderName)
    headerFrame._title:SetText(EllesmereUI.L(config.title or folderName))
    local rb = footerFrame and footerFrame._resetBtn
    if rb and rb._label then
        local navEntry = EUI_NS.navInfo[folderName]
        local displayName = (navEntry and navEntry.display) or config.title or folderName
        rb._label:SetText(EllesmereUI.Lf("Reset %1$s", EllesmereUI.L(displayName)))
        rb._label:SetWidth(rb:GetWidth() * 0.85)
        rb._label:SetWordWrap(false)
        rb._label:SetMaxLines(1)
    end
    if EllesmereUI._UpdateResetButtonVisible then
        EllesmereUI._UpdateResetButtonVisible(config.onReset ~= nil)
    end
    headerFrame._desc:SetText(EllesmereUI.L(config.description or ""))
    BuildTabs(config.pages, config.disabledPages, config.disabledPageTooltips)
    -- Toolbar whitelists: the overrides icon and the inline search operate on suite data only
    -- (override capture, search index), so they render solely for whitelisted pages -- overrides:
    -- core modules; search: core modules + Global Settings. Foreign/companion pages get neither. (BuildTabs unconditionally shows the search frame; gate it here.)
    if tabBar then
        local core = config._euiCore == true
        if tabBar._searchFrame then
            tabBar._searchFrame:SetShown(core or folderName == EllesmereUI.GLOBAL_KEY)
        end
        if tabBar._specOvBtn then
            tabBar._specOvBtn:SetShown(core)
        end
    end
    local savedPage = _lastPagePerModule[folderName]
    -- Validate saved page still exists in this module's page list
    local validPage = nil
    if savedPage and config.pages then
        for _, p in ipairs(config.pages) do
            if p == savedPage then validPage = savedPage; break end
        end
    end
    local targetPage = validPage or (config.pages and config.pages[1])
    -- Clear activePage so SelectPage doesn't bail when the target page
    -- has the same name as the previous module's page (e.g. both have "General").
    activePage = nil
    if targetPage then
        self:SelectPage(targetPage)
    else
        activePage = nil
        ClearContent()
    end
end

-------------------------------------------------------------------------------
--  Sidebar search filter -- iterates the last order captured by RefreshSidebarStates, hides
--  any button whose addon display name and registered page names don't contain the query, and re-stacks the remaining ones at the top of the scroll area.
-------------------------------------------------------------------------------
function EllesmereUI._applySidebarSearch(text)
    text = text and text:lower() or ""
    local scrollChild = EllesmereUI._addonScrollChild
    if not scrollChild then return end

    -- Split the query into whitespace-delimited words. An entry matches only
    -- if EVERY word is found somewhere in its combined searchable text
    -- (display name + registered page names + module searchTerms).
    local queryWords = {}
    if text ~= "" then
        for word in text:gmatch("%S+") do
            queryWords[#queryWords + 1] = word
        end
    end

    -- Bilingual: index the localized form too, only when it differs from the
    -- original, so the English haystack stays byte-identical on English clients.
    local function addLocalized(parts, s)
        s = tostring(s)
        parts[#parts + 1] = s:lower()
        local loc = tostring(EllesmereUI.L(s))
        if loc ~= s then parts[#parts + 1] = loc:lower() end
    end

    local function childMatches(info)
        if #queryWords == 0 then return true end
        local parts = {}
        addLocalized(parts, info.display or "")
        local mod = modules[info.folder]
        if mod and mod.pages then
            for _, p in ipairs(mod.pages) do
                addLocalized(parts, p)
            end
        end
        if mod and mod.searchTerms then
            if type(mod.searchTerms) == "table" then
                for _, t in ipairs(mod.searchTerms) do
                    addLocalized(parts, t)
                end
            else
                addLocalized(parts, mod.searchTerms)
            end
        end
        local haystack = table.concat(parts, " ")
        for _, word in ipairs(queryWords) do
            if not haystack:find(word, 1, true) then return false end
        end
        return true
    end

    local y = 0
    local groupHeaders = EUI_NS.sidebarGroupButtons
    local infoByFolder = EUI_NS.navInfo
    local GROUP_H  = EllesmereUI.SIDEBAR_GROUP_ROW_H
    local CHILD_H  = EllesmereUI.SIDEBAR_CHILD_ROW_H
    local GROUP_GAP = EllesmereUI.SIDEBAR_GROUP_GAP
    local firstVisibleGroup = true
    for _, group in ipairs(EUI_NS.navGroups) do
        local header = groupHeaders[group.key]
        local visibleChildren = {}
        for _, folder in ipairs(group.members) do
            local info = infoByFolder[folder]
            local btn = info and sidebarButtons[folder]
            if btn and info then
                if childMatches(info) then
                    visibleChildren[#visibleChildren + 1] = btn
                else
                    btn:Hide()
                end
            end
        end
        if header then
            if #visibleChildren == 0 then
                header:Hide()
            else
                if not firstVisibleGroup then y = y + GROUP_GAP end
                firstVisibleGroup = false
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                header:Show()
                y = y + GROUP_H
            end
        end
        for _, btn in ipairs(visibleChildren) do
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            btn:Show()
            y = y + CHILD_H
        end
    end

    scrollChild:SetHeight(math.max(CHILD_H, y))
    if text ~= "" and EllesmereUI._addonScrollFrame then
        EllesmereUI._addonScrollFrame:SetVerticalScroll(0)
    end
end

-------------------------------------------------------------------------------
--  Show / Hide / Toggle
-------------------------------------------------------------------------------
local function RefreshSidebarStates()
    -- Refresh global settings button state (unchanged -- still a dedicated
    -- always-visible row above the grouped scroll area).
    local globalBtn = sidebarButtons["_EUIGlobal"]
    if globalBtn then
        if "_EUIGlobal" == activeModule then
            globalBtn._label:SetTextColor(NAV_SELECTED_TEXT.r, NAV_SELECTED_TEXT.g, NAV_SELECTED_TEXT.b, NAV_SELECTED_TEXT.a)
            globalBtn._icon:SetTexture(globalBtn._iconOff)
            globalBtn._icon:SetDesaturated(false)
            globalBtn._icon:SetAlpha(NAV_SELECTED_ICON_A)
            globalBtn._iconGlow:Show()
        else
            globalBtn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            globalBtn._icon:SetTexture(globalBtn._iconOff)
            globalBtn._icon:SetDesaturated(false)
            globalBtn._icon:SetAlpha(NAV_ENABLED_ICON_A)
            globalBtn._iconGlow:Hide()
        end
    end

    local scrollChild = EllesmereUI._addonScrollChild
    if not scrollChild then return end

    local firstLoaded = nil
    local groupHeaders = EUI_NS.sidebarGroupButtons
    local infoByFolder = EUI_NS.navInfo

    local GROUP_H   = EllesmereUI.SIDEBAR_GROUP_ROW_H
    local CHILD_H   = EllesmereUI.SIDEBAR_CHILD_ROW_H
    local GROUP_GAP = EllesmereUI.SIDEBAR_GROUP_GAP
    local y = 0
    for i, group in ipairs(EUI_NS.navGroups) do
        if i > 1 then y = y + GROUP_GAP end
        local header = groupHeaders[group.key]
        if header then
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            header:Show()
            y = y + GROUP_H
        end
        for _, folder in ipairs(group.members) do
            local info = infoByFolder[folder]
            local btn = info and sidebarButtons[folder]
            if btn then
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                btn:Show()
                y = y + CHILD_H

                local loaded = info.alwaysLoaded or IsAddonLoaded(info.folder)
                local isSpecial = info.comingSoon or info.maintenance
                -- Coming-soon / maintenance rows render as disabled regardless
                -- of whether their placeholder folder happens to be loaded.
                local effectiveLoaded = loaded and not isSpecial
                btn._loaded = effectiveLoaded
                btn._notEnabled = (not loaded) and (not isSpecial)
                btn._dlIcon:Hide()

                -- Refresh sync icon state
                if btn._syncBtn and btn._syncBtn._refreshAlpha then
                    btn._syncBtn._refreshAlpha()
                end

                if effectiveLoaded and folder == activeModule then
                    btn._label:SetTextColor(NAV_SELECTED_TEXT.r, NAV_SELECTED_TEXT.g, NAV_SELECTED_TEXT.b, NAV_SELECTED_TEXT.a)
                    if btn._pwrBtn then btn._pwrBtn._tex:SetAlpha(1) end
                elseif effectiveLoaded then
                    btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
                    if btn._pwrBtn then btn._pwrBtn._tex:SetAlpha(1) end
                    if not firstLoaded then firstLoaded = folder end
                else
                    btn._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
                    if btn._pwrBtn then btn._pwrBtn._tex:SetAlpha(0.5) end
                    btn._indicator:Hide()
                    btn._glow:Hide()
                    btn._glowTop:Hide()
                    btn._glowBot:Hide()
                end
            end
        end
    end

    if scrollChild.SetHeight then
        scrollChild:SetHeight(math.max(CHILD_H, y))
    end

    -- Default to Global Settings if no module is active
    if not activeModule then
        activeModule = nil
        if modules["_EUIGlobal"] then
            EllesmereUI:SelectModule("_EUIGlobal")
        elseif firstLoaded and modules[firstLoaded] then
            EllesmereUI:SelectModule(firstLoaded)
        end
    end

    -- (Sidebar search no longer filters the addon rows -- the global search
    -- results popup replaced that behavior -- so there is no filter state to
    -- re-apply across refreshes anymore.)

    -- Re-assert override-session locks LAST: the recolor loop above paints by loaded
    -- state and would otherwise wash out locked rows on every module/page switch.
    if EllesmereUI.RefreshSidebarOverrideLocks then
        EllesmereUI.RefreshSidebarOverrideLocks()
    end
end

-----------------------------------------------------------------------
--  Sidebar Unlock Mode tip  (one-time, shown on first panel open)
-----------------------------------------------------------------------
local _sidebarUnlockTip
local function ShowSidebarUnlockTip()
    if EllesmereUIDB and EllesmereUIDB.sidebarUnlockTipSeen then return end
    if _sidebarUnlockTip and _sidebarUnlockTip:IsShown() then return end
    local anchor = EllesmereUI._unlockSidebarBtn
    if not anchor then return end

    if not _sidebarUnlockTip then
        local TIP_W, TIP_H = 320, 100
        local EG = ELLESMERE_GREEN
        local ar, ag, ab = EG.r, EG.g, EG.b

        local tip = CreateFrame("Frame", nil, EllesmereUI._panelBody)
        tip:SetFrameStrata("FULLSCREEN_DIALOG")
        tip:SetFrameLevel(200)
        PanelPP.Size(tip, TIP_W, TIP_H)
        tip:EnableMouse(true)

        -- Center horizontally on the Unlock Mode label text
        local lbl = anchor._label
        if lbl then
            tip:SetPoint("TOP", lbl, "BOTTOM", 0, -12)
        else
            tip:SetPoint("TOP", anchor, "BOTTOM", 60, -12)
        end

        -- Background
        local bg = SolidTex(tip, "BACKGROUND", 0.06, 0.08, 0.10, 1)
        bg:SetAllPoints()

        -- Border (pixel-perfect via PanelPP)
        MakeBorder(tip, ar, ag, ab, 0.25, PanelPP)

        -- Arrow pointing up (clipped diamond)
        local ARROW_SZ = 16
        local arrowClip = CreateFrame("Frame", nil, tip)
        arrowClip:SetFrameStrata("FULLSCREEN_DIALOG")
        arrowClip:SetFrameLevel(tip:GetFrameLevel() + 10)
        arrowClip:SetClipsChildren(true)
        local clipH = ARROW_SZ
        arrowClip:SetSize(ARROW_SZ * 2, clipH)
        arrowClip:SetPoint("BOTTOM", tip, "TOP", 0, -1)

        local arrowFrame = CreateFrame("Frame", nil, arrowClip)
        arrowFrame:SetFrameLevel(arrowClip:GetFrameLevel() + 1)
        arrowFrame:SetSize(ARROW_SZ + 4, ARROW_SZ + 4)
        arrowFrame:SetPoint("CENTER", arrowClip, "BOTTOM", 0, 0)

        local arrowBorder = arrowFrame:CreateTexture(nil, "ARTWORK", nil, 7)
        arrowBorder:SetSize(ARROW_SZ + 2, ARROW_SZ + 2)
        arrowBorder:SetPoint("CENTER")
        arrowBorder:SetColorTexture(ar, ag, ab, 0.18)
        arrowBorder:SetRotation(math.rad(45))
        if arrowBorder.SetSnapToPixelGrid then arrowBorder:SetSnapToPixelGrid(false); arrowBorder:SetTexelSnappingBias(0) end

        local arrowFill = arrowFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        arrowFill:SetSize(ARROW_SZ, ARROW_SZ)
        arrowFill:SetPoint("CENTER")
        arrowFill:SetColorTexture(0.06, 0.08, 0.10, 1)
        arrowFill:SetRotation(math.rad(45))
        if arrowFill.SetSnapToPixelGrid then arrowFill:SetSnapToPixelGrid(false); arrowFill:SetTexelSnappingBias(0) end

        -- Message
        local msg = MakeFont(tip, 12, nil, 1, 1, 1, 0.85)
        msg:SetPoint("TOP", tip, "TOP", 0, -17)
        msg:SetWidth(TIP_W - 30)
        msg:SetJustifyH("CENTER")
        msg:SetSpacing(6)
        msg:SetText(EllesmereUI.L("Unlock Mode is where you can adjust\npositioning for all the elements of EllesmereUI"))

        -- Okay button
        local okBtn = CreateFrame("Button", nil, tip)
        okBtn:SetSize(86, 26)
        okBtn:SetPoint("BOTTOM", tip, "BOTTOM", 0, 13)
        EllesmereUI.MakeStyledButton(okBtn, "Okay", 11,
            EllesmereUI.RB_COLOURS, function()
                tip:Hide()
                if EllesmereUIDB then EllesmereUIDB.sidebarUnlockTipSeen = true end
            end)

        _sidebarUnlockTip = tip
    end

    _sidebarUnlockTip:SetAlpha(0)
    _sidebarUnlockTip:Show()

    local fadeIn = 0
    _sidebarUnlockTip:SetScript("OnUpdate", function(self, dt)
        fadeIn = fadeIn + dt
        if fadeIn >= 0.3 then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
            return
        end
        self:SetAlpha(fadeIn / 0.3)
    end)
end

-- FIRST-OPEN SPLIT: the session's first open pays two heavy bills --
-- EnsureLoaded (LoadAddOn parsing the whole LoD options addon + every deferred
-- init) and the full panel build -- and the per-execution watchdog meters them
-- TOGETHER when both run in one hardware-event handler (field: "script ran too
-- long" aborting mid-sidebar on the very first open). Split them: the
-- triggering execution only LOADS; afterFn (the caller re-invoking itself)
-- runs next frame with its own fresh budget. Later opens (already loaded) stay
-- fully synchronous -- returns false and the caller proceeds as before.
-- EnsureLoaded itself stays synchronous: direct callers (DataBars' block
-- settings path) use the deferred inits' results in the same execution. A
-- failed load (options addon disabled) also returns false so the caller runs
-- the exact legacy failure path; _openPending swallows re-clicks during the
-- one-frame gap so a Toggle can't double-fire.
function EllesmereUI:_SplitFirstOpen(afterFn)
    if self._deferredLoaded then return false end
    self:EnsureLoaded()
    if not self._deferredLoaded then return false end
    self._openPending = true
    C_Timer.After(0, function()
        EllesmereUI._openPending = nil
        afterFn()
    end)
    return true
end

function EllesmereUI:Show()
    if self._openPending then return end
    if self:_SplitFirstOpen(function() EllesmereUI:Show() end) then return end
    CreateMainFrame()
    RefreshSidebarStates()
    mainFrame:Show()
    -- An open request while folded to the mini window unfolds it.
    if self._panelCollapsed then self._SetPanelCollapsed(false) end
    ShowSidebarUnlockTip()
end
function EllesmereUI:Hide()   if mainFrame then mainFrame:Hide() end end
function EllesmereUI:Toggle()
    if self._openPending then return end
    if self:_SplitFirstOpen(function() EllesmereUI:Toggle() end) then return end
    CreateMainFrame()
    if self._panelCollapsed then
        -- Folded to the mini window: the toggle asks for the options back.
        self._SetPanelCollapsed(false)
    elseif mainFrame:IsShown() then
        mainFrame:Hide()
    else
        RefreshSidebarStates()
        mainFrame:Show()
        ShowSidebarUnlockTip()
        -- Refresh widget disabled states (e.g. width-match may have
        -- changed in unlock mode since the page was last shown).
        if self.RefreshPage then self:RefreshPage() end
    end
end
function EllesmereUI:IsShown() return mainFrame and mainFrame:IsShown() end
-- The main settings window frame. Used e.g. to scope popup click-catchers to the
-- panel instead of UIParent, so an open popup doesn't block world mouse/mouselook.
function EllesmereUI:GetMainFrame() return mainFrame end
function EllesmereUI:GetActivePage() return activePage end

--- Apply a user-defined panel scale on top of the pixel-perfect base scale.
--- @param userScale number  multiplier (1.0 = default, 0.5-1.5 range)
do
    local scaleAnimFrame = CreateFrame("Frame")
    local scaleFrom, scaleTo, scaleElapsed
    local SCALE_DUR = 0.10
    local isAnimating = false

    local function OnScaleUpdate(self, dt)
        scaleElapsed = scaleElapsed + dt
        local t = math.min(1, scaleElapsed / SCALE_DUR)
        local ease = t * (2 - t)  -- ease-out quad
        local cur = scaleFrom + (scaleTo - scaleFrom) * ease
        if mainFrame then mainFrame:SetScale(cur) end
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            isAnimating = false
            if mainFrame then mainFrame:SetScale(scaleTo) end
            if EllesmereUI._onScaleChanged then
                for _, fn in ipairs(EllesmereUI._onScaleChanged) do fn() end
            end
        end
    end

    function EllesmereUI:SetPanelScale(userScale)
        if not mainFrame then return end
        local physW = (GetPhysicalScreenSize())
        local baseScale = GetScreenWidth() / physW
        local targetScale = baseScale * (userScale or 1.0)
        if EllesmereUIDB then EllesmereUIDB.panelScale = userScale end
        -- Recalculate PanelPP mult for the new scale
        if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end
        if isAnimating then
            -- Already animating: just redirect the target without restarting.
            scaleTo = targetScale
        else
            scaleFrom = mainFrame:GetScale()
            scaleTo = targetScale
            scaleElapsed = 0
            isAnimating = true
            scaleAnimFrame:SetScript("OnUpdate", OnScaleUpdate)
        end
    end
end

-- Open the panel with a specific addon's tab selected
function EllesmereUI:ShowModule(folderName)
    if InCombatLockdown() then
        EllesmereUI.PrintError("Cannot open options during combat.")
        return
    end
    if self._openPending then return end
    -- First-open split (see _SplitFirstOpen): the combat check above stays in
    -- the click execution; the deferred re-invoke re-checks it harmlessly.
    if self:_SplitFirstOpen(function() EllesmereUI:ShowModule(folderName) end) then return end
    CreateMainFrame()
    RefreshSidebarStates()
    mainFrame:Show()
    if self._panelCollapsed then self._SetPanelCollapsed(false) end
    ShowSidebarUnlockTip()
    if modules[folderName] then
        self:SelectModule(folderName)
    end
end

-------------------------------------------------------------------------------
--  Plugin API
--  Third-party addons add their own settings pages through RegisterPlugin. A
--  plugin always gets a NEW sidebar section of its own; it can never add a row
--  to one of the suite's sections, add a tab to a suite module, or replace a
--  suite page:
--   * plugin module keys live in the "plugin:<id>:<module>" namespace, which
--     RegisterModule refuses, so they never collide with a suite key;
--   * the section and its rows go to private lists that the sidebar renders
--     only above or below the suite's block of groups (EUI_NS.RebuildNavGroups);
--   * the registry keeps its own copy of every field it uses, so editing the
--     spec table after registration has no effect;
--   * every plugin callback runs through xpcall: a plugin error is reported
--     through the error handler and never breaks the panel.
--  Plugin pages take part in the global search like suite pages: widget rows
--  are indexed on live navigation and by the search's hidden pre-build pass
--  (a module can opt out of the latter with searchPrebuild = false).
--  Developer guide: PLUGINS_API.md.
-------------------------------------------------------------------------------
EllesmereUI.PLUGIN_API_VERSION = 1

do
    local PREFIX          = EUI_NS.PLUGIN_PREFIX
    local MAX_MODULES     = 20
    local MAX_PAGES       = 20
    local MAX_ID_LEN      = 40
    local MAX_LABEL_CHARS = 32
    local MAX_TITLE_CHARS = 48
    local MAX_DESC_CHARS  = 300

    -- id -> { label, position, keys = { [moduleKey] = fullKey }, firstKey }
    local plugins = {}

    local function ReportError(err) return geterrorhandler()(err) end

    local function Reject(id, msg)
        ReportError(("EllesmereUI.RegisterPlugin(%s): %s"):format(tostring(id), msg))
        return false
    end

    -- Caps s at maxChars UTF-8 characters.
    local function CapChars(s, maxChars)
        local n, cut = 0, nil
        for pos in s:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
            n = n + 1
            if n > maxChars then cut = pos; break end
        end
        if cut then s = s:sub(1, cut - 1):gsub("%s+$", "") end
        return s
    end

    -- Plain single-line text: drops every UI escape sequence (colors, textures,
    -- atlases, hyperlinks, line breaks) so a label cannot borrow suite styling.
    local function PlainText(s, maxChars)
        if type(s) ~= "string" then return nil end
        s = s:gsub("|[Tt].-|[Tt]", "")
             :gsub("|[Aa].-|[Aa]", "")
             :gsub("|[Kk].-|[Kk]", "")
             :gsub("|H.-|h(.-)|h", "%1")
             :gsub("|c%x%x%x%x%x%x%x%x", "")
             :gsub("|cn[^:]*:", "")
             :gsub("|r", "")
             :gsub("|n", " ")
             :gsub("|", "")
             :gsub("%c", " ")
             :gsub("%s+", " ")
             :gsub("^ ", ""):gsub(" $", "")
        if s == "" then return nil end
        return CapChars(s, maxChars)
    end

    -- Section labels a plugin may not use: the suite's own group labels (English
    -- and localized), the fixed panel entries, and the suite name itself.
    local function IsReservedLabel(label)
        local lower = label:lower()
        if lower:find("^ellesmere") or lower:find("^eui") then return true end
        local reserved = { "Global Settings", "Profiles", "Patch Notes" }
        for _, g in ipairs(EUI_NS.coreGroups) do reserved[#reserved + 1] = g.label end
        for _, r in ipairs(reserved) do
            if lower == r:lower() or lower == tostring(EllesmereUI.L(r)):lower() then
                return true
            end
        end
        return false
    end

    local function ValidId(s)
        return type(s) == "string" and #s <= MAX_ID_LEN and s:find("^%a[%w_%-]*$") ~= nil
    end

    local function Guard(fn)
        if fn == nil then return nil end
        return function(...)
            local ok, a = xpcall(fn, ReportError, ...)
            if ok then return a end
        end
    end

    -- Guarded header builders, cached so a page keeps one builder identity.
    local guardedHeaders = setmetatable({}, { __mode = "k" })
    local function GuardHeaderSource(getHeaderBuilder)
        if getHeaderBuilder == nil then return nil end
        local get = Guard(getHeaderBuilder)
        return function(pageName)
            local hb = get(pageName)
            if type(hb) ~= "function" then return nil end
            local g = guardedHeaders[hb]
            if not g then
                g = Guard(hb)
                guardedHeaders[hb] = g
            end
            return g
        end
    end

    local CALLBACKS = { "buildPage", "getHeaderBuilder", "onPageCacheRestore", "onReset", "onModuleLeave" }

    -- Validates one module spec and returns the registry's private config copy.
    local function BuildModuleConfig(id, label, m, index, seenKeys)
        if type(m) ~= "table" then return nil, ("modules[%d] must be a table"):format(index) end
        if not ValidId(m.key) then
            return nil, ("modules[%d].key must match ^%%a[%%w_%%-]*$ (max %d chars)"):format(index, MAX_ID_LEN)
        end
        if seenKeys[m.key] then return nil, ("duplicate module key %q"):format(m.key) end
        local title = PlainText(m.title, MAX_TITLE_CHARS)
        if not title then return nil, ("modules[%d].title must be a non-empty string"):format(index) end
        if m.description ~= nil and type(m.description) ~= "string" then
            return nil, ("modules[%d].description must be a string"):format(index)
        end
        if type(m.pages) ~= "table" or #m.pages == 0 or #m.pages > MAX_PAGES then
            return nil, ("modules[%d].pages must be a list of 1-%d page names"):format(index, MAX_PAGES)
        end
        local pages, seenPages = {}, {}
        for i, p in ipairs(m.pages) do
            -- Page names are handed back to buildPage verbatim, so they are
            -- validated rather than cleaned: plain text only.
            if type(p) ~= "string" or p == "" or p:find("[|%c]") or seenPages[p] then
                return nil, ("modules[%d].pages[%d] must be a unique plain-text string"):format(index, i)
            end
            seenPages[p] = true
            pages[i] = p
        end
        for _, cb in ipairs(CALLBACKS) do
            if m[cb] ~= nil and type(m[cb]) ~= "function" then
                return nil, ("modules[%d].%s must be a function"):format(index, cb)
            end
        end
        if type(m.buildPage) ~= "function" then
            return nil, ("modules[%d].buildPage is required"):format(index)
        end
        if m.searchPrebuild ~= nil and type(m.searchPrebuild) ~= "boolean" then
            return nil, ("modules[%d].searchPrebuild must be a boolean"):format(index)
        end
        seenKeys[m.key] = true
        return {
            title              = title,
            description        = m.description and CapChars(m.description, MAX_DESC_CHARS) or nil,
            pages              = pages,
            buildPage          = Guard(m.buildPage),
            getHeaderBuilder   = GuardHeaderSource(m.getHeaderBuilder),
            onPageCacheRestore = Guard(m.onPageCacheRestore),
            onReset            = Guard(m.onReset),
            onModuleLeave      = Guard(m.onModuleLeave),
            _euiCore           = false,
            _plugin            = id,
            _pluginLabel       = label,
            _searchPrebuild    = m.searchPrebuild ~= false,
        }
    end

    -- Builds the header and rows of a section registered after the panel exists.
    local function BuildLateSection(group)
        local createHeader = EUI_NS.CreateSidebarGroupHeader
        local createRow    = EUI_NS.CreateSidebarChildRow
        if not (createHeader and createRow) then return end
        EUI_NS.sidebarGroupButtons[group.key] = createHeader(group)
        for _, key in ipairs(group.members) do
            sidebarButtons[key] = createRow(EUI_NS.navInfo[key])
        end
        if EllesmereUI.RefreshSidebarOverrideLocks then EllesmereUI.RefreshSidebarOverrideLocks() end
        if mainFrame and mainFrame:IsShown() then RefreshSidebarStates() end
    end

    --- Registers a plugin and its sidebar section.
    --- @param id string   unique plugin id (letters, digits, "_" and "-")
    --- @param spec table  { label, position = "bottom"|"top", modules = { ... } }
    --- @return boolean    true when the plugin was registered
    function EllesmereUI.RegisterPlugin(id, spec)
        if not ValidId(id) then
            return Reject(id, ("id must match ^%%a[%%w_%%-]*$ (max %d chars)"):format(MAX_ID_LEN))
        end
        if plugins[id] then return Reject(id, "a plugin with this id is already registered") end
        if type(spec) ~= "table" then return Reject(id, "spec must be a table") end

        local label = PlainText(spec.label, MAX_LABEL_CHARS)
        if not label then return Reject(id, "label must be a non-empty string") end
        if IsReservedLabel(label) then return Reject(id, ("label %q is reserved"):format(label)) end

        local position = spec.position
        if position == nil then position = "bottom" end
        if position ~= "bottom" and position ~= "top" then
            return Reject(id, 'position must be "bottom" or "top"')
        end

        if type(spec.modules) ~= "table" or #spec.modules == 0 or #spec.modules > MAX_MODULES then
            return Reject(id, ("modules must be a list of 1-%d module specs"):format(MAX_MODULES))
        end

        -- Validate everything before touching any shared state.
        local configs, seenKeys = {}, {}
        for i, m in ipairs(spec.modules) do
            local config, err = BuildModuleConfig(id, label, m, i, seenKeys)
            if not config then return Reject(id, err) end
            local fullKey = PREFIX .. id .. ":" .. m.key
            if EUI_NS.IsModuleKeyTaken(fullKey) then
                return Reject(id, ("module key %q is already registered"):format(fullKey))
            end
            configs[i] = { key = m.key, fullKey = fullKey, config = config }
        end

        local record = { label = label, position = position, keys = {} }
        local group = { key = PREFIX .. id, label = label, members = {}, plugin = id }
        for i, c in ipairs(configs) do
            EUI_NS.navInfo[c.fullKey] = {
                folder       = c.fullKey,
                display      = c.config.title,
                search_name  = label .. " " .. c.config.title,
                alwaysLoaded = true,
                plugin       = id,
            }
            group.members[i] = c.fullKey
            record.keys[c.key] = c.fullKey
            EUI_NS.StoreModule(c.fullKey, c.config)
        end
        record.firstKey = configs[1].fullKey
        plugins[id] = record

        local list = (position == "top") and EUI_NS.pluginGroupsTop or EUI_NS.pluginGroupsBottom
        list[#list + 1] = group
        EUI_NS.RebuildNavGroups()
        BuildLateSection(group)
        return true
    end

    function EllesmereUI.IsPluginRegistered(id)
        return plugins[id] ~= nil
    end

    --- True while the global search's hidden pre-build pass is running a page
    --- builder. The builder then gets a stub widget factory; skip side effects
    --- (event registration, hooks, previews) while this is true.
    function EllesmereUI.IsSearchPrebuild()
        return EllesmereUI._prebuilding == true
    end

    --- Full module key of a plugin module ("plugin:<id>:<moduleKey>"), for the
    --- panel calls that take one (GetActiveModule comparisons,
    --- InvalidateModulePageCache). Nil when not registered.
    function EllesmereUI.GetPluginModuleKey(id, moduleKey)
        local record = plugins[id]
        return record and record.keys[moduleKey] or nil
    end

    --- Opens the panel on a plugin module (its first module when moduleKey is
    --- nil), optionally on a given page. Returns false when nothing matches.
    function EllesmereUI.OpenPlugin(id, moduleKey, pageName)
        local record = plugins[id]
        if not record then return false end
        local key = (moduleKey == nil) and record.firstKey or record.keys[moduleKey]
        local config = key and modules[key]
        if not config then return false end
        if InCombatLockdown() then
            EllesmereUI.PrintError("Cannot open options during combat.")
            return false
        end
        if pageName ~= nil then
            local valid = false
            for _, p in ipairs(config.pages) do
                if p == pageName then valid = true; break end
            end
            if not valid then return false end
            -- SelectModule opens the module on its last page.
            _lastPagePerModule[key] = pageName
        end
        EllesmereUI:ShowModule(key)
        -- Already on this module: SelectModule was a no-op, switch the page here.
        if pageName and activeModule == key and activePage ~= pageName
           and mainFrame and mainFrame:IsShown() then
            EllesmereUI:SelectPage(pageName)
        end
        return true
    end
end
