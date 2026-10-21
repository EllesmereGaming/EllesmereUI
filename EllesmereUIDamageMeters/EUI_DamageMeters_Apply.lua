if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_DamageMeters_Apply.lua
--
--  The ns functions that push a changed setting to every window.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._dmInternals
-- EllesmereUIDamageMeters.lua or an earlier EUI_DamageMeters_*.lua file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI
local ForeverShortName = EUI.ForeverShortName

local DB, GetHeaderH, ICON_ALPHA, MIN_H = I.DB, I.GetHeaderH, I.ICON_ALPHA, I.MIN_H
local MIN_W, _windows = I.MIN_W, I._windows
local ApplyHeaderButtonsHoverVisibility = I.ApplyHeaderButtonsHoverVisibility
local LayoutHeaderButtons, WinDB, GetAccentRGB = I.LayoutHeaderButtons, I.WinDB, I.GetAccentRGB
local PhysicalPixels, SetDMFont = I.PhysicalPixels, I.SetDMFont

-- ns exports (loop over all windows)
ns.RefreshMeter = function()
    ns.DMInvalidateAppearance()
    local cfg = DB()
    for _, w in ipairs(_windows) do
        if cfg.barSeparators or cfg.iconSeparator or w._decorSync then ns.DMSetWindowBorderLayer(w, cfg) end
        w.Refresh()
    end
end

-- Re-lay out every row after a UI scale change. The row stride is derived from
-- the frame's effective scale, so a new scale invalidates the cached row
-- anchors; busting _barCacheKey makes the next refresh re-anchor them. Rows are
-- otherwise only re-anchored on a settings change or from the in-combat ticker,
-- so out of combat the old grid would survive until the next fight. Deliberately
-- not _EDM_Apply (a full re-apply of every window): the core scale slider calls
-- this on every drag step.
ns.Rescale = function()
    ns.DMInvalidateAppearance()
    for _, w in ipairs(_windows) do
        w._barCacheKey = nil
        w.Refresh()
        if w.sourceOpen and w.RefreshBreakdown then w.RefreshBreakdown() end
    end
    if ns.ApplySpellHistory then ns.ApplySpellHistory() end
end
-- Called by the core right after PP.SetUIScale, alongside the other modules' re-apply hooks
_G._EDM_Rescale = ns.Rescale

-- Bust per-class color caches and repaint when global custom class colors change, so bars/text
-- recolor live without a /reload (color is cached keyed only on classFile, which the palette edit doesn't change).
ns.RefreshColors = function()
    for _, w in ipairs(_windows) do
        w._stickyClassCache = false; w._stickySpecCache = nil
        -- The key bust re-seeds every populated row's colour memo (the full-rebuild pass).
        w._barCacheKey = nil
        w.Refresh()
    end
end
-- Exposed on the shared table so the parent addon's ApplyColorsToOUF can repaint damage meters when global custom class colors change
EllesmereUI._DM_RefreshColors = ns.RefreshColors

-- WoW Forever: a Name Format change (the Left Text cog, Forever Essentials).
-- The row and pinned-row name memos are keyed on the raw name, so they are
-- dropped before the repaint; the breakdown rows and hover headers are rebuilt
-- on every refresh and show. A hidden window catches up when it shows.
if ForeverShortName then
    ns.RefreshNames = function()
        for _, w in ipairs(_windows) do
            local pool = w.rowPool
            if pool then
                for i = 1, #pool do pool[i]._cachedSrcName = nil end
            end
            w._stickyNameCache = nil
            w.Refresh()
        end
    end
end

ns.ApplyBorder = function()
    ns.DMInvalidateAppearance()
    for _, w in ipairs(_windows) do
        if w.rowPool then
            for _, bar in ipairs(w.rowPool) do
                if bar.ApplyBorder then bar.ApplyBorder() end
            end
        end
        if w.stickyPlayer and w.stickyPlayer.ApplyBorder then
            w.stickyPlayer.ApplyBorder()
        end
        ns.DMRefreshRowDecor(w)
    end
end

ns.ApplyBarBg = function()
    for _, w in ipairs(_windows) do
        if w.rowPool then
            for _, bar in ipairs(w.rowPool) do
                if bar.ApplyBg then bar.ApplyBg() end
            end
        end
        if w.stickyPlayer and w.stickyPlayer.ApplyBg then
            w.stickyPlayer.ApplyBg()
        end
    end
end

ns.ApplyBarTextOffsets = function()
    for _, w in ipairs(_windows) do
        if w.rowPool then
            for _, bar in ipairs(w.rowPool) do
                if bar.ApplyTextOffsets then bar.ApplyTextOffsets() end
            end
        end
        if w.stickyPlayer and w.stickyPlayer.ApplyTextOffsets then
            w.stickyPlayer.ApplyTextOffsets()
        end
    end
end

ns.ApplyBackground = function()
    local cfg = DB()
    local r, g, b, a = cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgAlpha or 0.75
    for _, w in ipairs(_windows) do
        if w.frame and w.frame._bg then ns.DMPaintWindowBg(w.frame._bg, r, g, b, a, true) end
        if w.sourceFrame and w.sourceFrame._bg then ns.DMPaintWindowBg(w.sourceFrame._bg, r, g, b, a) end
    end
    -- Under Classic WoW UI the header tint is shaded from the window colour.
    if ns.DMClassic() then ns.ApplyHeader() end
end

ns.ApplyWindowBorder = function()
    ns.DMInvalidateAppearance()
    local cfg = DB()
    -- Stock-style windows carry their own frame art (the stock panel, the
    -- classic tooltip edge), no EUI border.
    local size = ns.DMBlizz() and 0 or (tonumber(cfg.windowBorderSize) or 0)
    local texture = cfg.windowBorderTexture or "solid"
    -- Exact size (nil = the legacy step path); a stock style forces size 0, no px.
    local px = size > 0 and EUI.BorderPx(cfg.windowBorderSizePx, size, texture) or nil
    local color = cfg.windowBorderColor or {}
    local r, g, b, a = color.r or 0, color.g or 0, color.b or 0, color.a or 1
    local includeHeader = cfg.windowBorderIncludeHeader ~= false
    local offsetX = texture ~= "solid" and (tonumber(cfg.windowBorderOffsetX) or 0) or 0
    local offsetY = texture ~= "solid" and (tonumber(cfg.windowBorderOffsetY) or 0) or 0

    for _, w in ipairs(_windows) do
        local target = w.windowBorderTarget
        if target and w.frame and w.header then
            ns.DMSetWindowBorderLayer(w, cfg)
            target:ClearAllPoints()
            if includeHeader then
                target:SetPoint("TOPLEFT", w.frame, "TOPLEFT", -offsetX, offsetY)
            else
                target:SetPoint("TOPLEFT", w.header, "BOTTOMLEFT", -offsetX, offsetY)
            end
            target:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", offsetX, -offsetY)
            -- Offsets are represented by the target geometry itself, which also makes them work for the solid four-strip border implementation
            EUI.ApplyBorderStyle(target, size, r, g, b, a, texture, nil, nil, nil, nil, nil, nil, nil, px)
            if cfg.hdrBottomSeparator or w._headerSeparator then ns.DMApplyHeaderSeparator(w) end
            ns.DMRefreshRowDecor(w)
        end
    end
    -- Border reach counts in size matching (each window's getMatchPad reads
    -- these settings): re-push a window's matches when it moved (deferred).
    if EUI.MatchPadChanged then
        for i = 1, #_windows do EUI.MatchPadChanged("EDM_Win" .. i) end
    end
end

ns.ApplyHeader = function()
    local cfg = DB()
    local hc = cfg.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
    local hA = cfg.hdrBgAlpha or 1
    local tR, tG, tB
    if cfg.hdrTextUseAccent ~= false then tR, tG, tB = ns.DMTitleRGB()
    else local c = cfg.hdrTextColor; tR = c and c.r or 1; tG = c and c.g or 1; tB = c and c.b or 1 end
    local hdrFS = cfg.hdrFontSize or 11
    local hdrH = GetHeaderH()
    local iconSz = ns.DMHdrIconSize(cfg)
    for _, w in ipairs(_windows) do
        if w.header then
            w.header:SetHeight(hdrH)
            if w.header._hdrBg then ns.DMPaintHeaderBg(w.header._hdrBg, hR, hG, hB, hA) end
            if w.header._bottomBorder and not ns.DMClassicSeparator(w.header._bottomBorder, PhysicalPixels(1)) then
                local size = cfg.hdrBottomBorderSize or 0
                local color = cfg.hdrBottomBorderColor or {}
                w.header._bottomBorder:SetHeight(PhysicalPixels(size))
                w.header._bottomBorder:SetColorTexture(color.r or 0, color.g or 0, color.b or 0, color.a or 1)
                w.header._bottomBorder:SetShown(size > 0 and not ns.DMBlizz())
            end
        end
        if w.frame and w.frame._bg then
            w.frame._bg:ClearAllPoints()
            w.frame._bg:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 0, -hdrH)
            w.frame._bg:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", 0, 0)
        end
        if w.titleText then
            SetDMFont(w.titleText, hdrFS)
            w.titleText:SetTextColor(tR, tG, tB, 1)
            local txOX, txOY = cfg.hdrTextOffX or 0, cfg.hdrTextOffY or 0
            w.titleText:ClearAllPoints()
            w.titleText:SetPoint("LEFT", w.header, "LEFT", 6 + txOX, txOY + ns.DMHdrLift(cfg.hdrHeight))
        end
        if w.timerText then
            SetDMFont(w.timerText, hdrFS)
        end
        LayoutHeaderButtons(w, cfg, iconSz)
        -- Close icon is 2px larger than other icons
        if w._closeIconTex then
            w._closeIconTex:ClearAllPoints()
            w._closeIconTex:SetSize(iconSz + 2, iconSz + 2)
            w._closeIconTex:SetPoint("CENTER", w.winActionBtn, "CENTER", 0, 0)
        end

        ApplyHeaderButtonsHoverVisibility(w, cfg)
        w._fitFull = nil
        if w.FitTitle then w.FitTitle() end
    end
    ns.ApplyWindowBorder()
end

ns.ApplyIconColor = function()
    local cfg = DB()
    local r, g, b
    if cfg.iconColorUseAccent then r, g, b = GetAccentRGB()
    else local c = cfg.iconColor; r = c and c.r or 1; g = c and c.g or 1; b = c and c.b or 1 end
    for _, w in ipairs(_windows) do
        for _, icon in ipairs(w.hdrIcons) do
            -- Stock-style art carries its own colours.
            if not icon._hdrArt then icon:SetVertexColor(r, g, b, ICON_ALPHA) end
        end
    end
end

ns.ApplyIconBorder = function()
    for _, w in ipairs(_windows) do
        if w.rowPool then
            for _, bar in ipairs(w.rowPool) do
                if bar.ApplyIconBorder then bar.ApplyIconBorder() end
            end
        end
        if w.stickyPlayer and w.stickyPlayer.ApplyIconBorder then
            w.stickyPlayer.ApplyIconBorder()
        end
    end
end

ns.ApplyDMPosition = function()
    for _, w in ipairs(_windows) do
        if w.ApplyPosition then w.ApplyPosition() end
    end
end

ns.ApplyDMSize = function()
    for _, w in ipairs(_windows) do
        local wdb = WinDB(w.idx)
        if w.frame then
            if wdb.width then w.frame:SetWidth(math.max(MIN_W, wdb.width)) end
            if wdb.height then w.frame:SetHeight(math.max(MIN_H, wdb.height)) end
        end
    end
end

I.broken = false
