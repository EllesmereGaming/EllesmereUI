if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Options.lua
--  Registers the Resource Bars module with EllesmereUI
--  Pages: Class, Power and Health Bars | Cast Bar | Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIResourceBars"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page
local abs = math.abs

local PAGE_DISPLAY   = "Class, Power and Health Bars"
local PAGE_CASTBAR   = "Cast Bar"
local PAGE_GCD       = "GCD Bar"
local PAGE_SWING     = "Swing Timer"   -- WoW Forever only (C_SwingTimer)
local PAGE_TOTEM     = "Totem Bar"
local PAGE_UNLOCK    = "Unlock Mode"

-- WoW Forever shows the first tab as "Main Resources" and the totem tab as
-- "Totem Bars" (it holds the Call Totem Bar too). Display only: the page
-- identity above stays the same for nav targets, unlock and saved state.
if EllesmereUI.IS_FOREVER then
    EllesmereUI.TAB_LABEL_OVERRIDES[PAGE_DISPLAY] = "Main Resources"
    EllesmereUI.TAB_LABEL_OVERRIDES[PAGE_TOTEM] = "Totem Bars"
end

-- Classic WoW UI: each bar's Border Size slot sizes the vanilla frame round
-- the bar (stockBorderScale, a percentage of the frame's full size; nil =
-- the shared default) in place of the gated EUI border size. The border
-- row's colour swatch, offset cog and style sync stand down under it; this
-- sync copies the size. The cast bar row does the same on its own style key.
function ns.ERB_ClassicBorderRow()
    return EllesmereUI.BlizzStyle.Active("resourcebars") == "classic"
end
-- "Border Around All" is offered under either stock style (the classic
-- frame, or the Blizzard Style panel, round the group).
function ns.ERB_BorderAllRow()
    return EllesmereUI.BlizzStyle.Active("resourcebars") ~= "eui"
end
local CLASSIC_SYNC_KEYS = { "health", "primary", "secondary" }
local CLASSIC_MATCH_KEYS = { "ERB_Health", "ERB_Power", "ERB_ClassResource" }
-- matchKey: the bar's unlock element, whose size matches read the frame's
-- reach (getMatchPad) and are re-applied when it changes. While "Border
-- Around All" is on, the three bars share one frame and so one size: every
-- bar's slider writes all three.
function ns.ERB_ClassicBorderSizeCfg(cfgFn, offFn, offTip, rebuild, matchKey)
    return EllesmereUI.BlizzStyle.ClassicBorderSizeCfg(
        function() local c = cfgFn(); return c and c.stockBorderScale end,
        function(v)
            local c = cfgFn(); if not c then return end
            c.stockBorderScale = v
            local d = _G._ERB_AceDB
            local p = d and d.profile
            local all = p and ns.ERB_GroupSettingOn and ns.ERB_GroupSettingOn(p)
            if all then
                for i = 1, #CLASSIC_SYNC_KEYS do p[CLASSIC_SYNC_KEYS[i]].stockBorderScale = v end
            end
            rebuild()
            if all then
                for i = 1, #CLASSIC_MATCH_KEYS do EllesmereUI.ReapplyMatchPads(CLASSIC_MATCH_KEYS[i]) end
            else
                EllesmereUI.ReapplyMatchPads(matchKey)
            end
            EllesmereUI:RefreshPage()
        end,
        { disabled = offFn, disabledTooltip = offTip })
end
-- Exact border size companion (borderSizePx, see EllesmereUI.BorderPx): the
-- "apply to all" syncs copy it beside borderSize. A value the target held is
-- cleared with false, never nil (nil does not travel through mirror sync).
function ns.ERB_CopyBorderPx(t, s)
    local v = s.borderSizePx
    if v == nil and t.borderSizePx ~= nil then v = false end
    t.borderSizePx = v
end
-- Two bars agree when both are unset (nil or false) or hold the same value.
function ns.ERB_SameBorderPx(a, b)
    return (a.borderSizePx or false) == (b.borderSizePx or false)
end
-- Separator Art dropdown values / order (fresh tables, page build only):
-- "match" (the bar's own style, see ns.ERB_SeparatorArt) first, then every
-- built-in border style with a horizontal companion strip, named from the
-- catalogue, so a later style with separator art joins with no change here.
-- withNone puts a "none" entry first for a dropdown whose None turns it off.
function ns.ERB_SeparatorArtValues(withNone)
    local values, order = {}, {}
    if withNone then values.none = "None"; order[1] = "none" end
    values.match = "Match Border"; order[#order + 1] = "match"
    for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
        if EllesmereUI.GetBorderCompanion(entry.key, "sepH") then
            values[entry.key] = entry.name
            order[#order + 1] = entry.key
        end
    end
    return values, order
end
-- Which of the three bars carry a textured border, as one string. A cross-bar
-- border sync that changes it rebuilds the page (each section's Width Offset |
-- Height Offset row exists only while its style is textured); otherwise the
-- fast refresh keeps the sync icon's flash.
function ns.ERB_TexturedBars(p)
    local function one(t)
        local x = t and t.borderTexture or "solid"
        return (x ~= "solid" and x ~= "") and "1" or "0"
    end
    return one(p.health) .. one(p.primary) .. one(p.secondary)
end
function ns.ERB_ClassicBorderSync(region, dbFn, key, refresh, flashFn)
    EllesmereUI.BuildSyncIcon({
        region  = region,
        tooltip = "Apply Border Size to all Bars",
        onClick = function()
            local p = dbFn(); if not p then return end
            local v = p[key].stockBorderScale
            for i = 1, #CLASSIC_SYNC_KEYS do p[CLASSIC_SYNC_KEYS[i]].stockBorderScale = v end
            refresh()
            for i = 1, #CLASSIC_MATCH_KEYS do EllesmereUI.ReapplyMatchPads(CLASSIC_MATCH_KEYS[i]) end
            EllesmereUI:RefreshPage()
        end,
        isSynced = function()
            local p = dbFn(); if not p then return false end
            local v = p[key].stockBorderScale
            for i = 1, #CLASSIC_SYNC_KEYS do
                if p[CLASSIC_SYNC_KEYS[i]].stockBorderScale ~= v then return false end
            end
            return true
        end,
        flashTargets = flashFn,
    })
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    -- Options page pool (EllesmereUI_FramePool.lua): frames made here on a pool
    -- host are reset and dressed again by the next build instead of made anew;
    -- elsewhere this is CreateFrame. Captured once, never read through the
    -- public slot later.
    local CreateFrame = EllesmereUI._Pool.CreateFrame
    local PoolGen, PoolKeep = EllesmereUI._Pool.Gen, EllesmereUI._Pool.Keep
    local PP = EllesmereUI.PanelPP
    local THR_BORDER_WHITE = { 1, 1, 1 }  -- Threshold & Hash Lines buttons: default (unconfigured) border tint

    local db
    C_Timer.After(0, function() db = _G._ERB_AceDB end)

    local function DB()
        if not db then db = _G._ERB_AceDB end
        return db and db.profile
    end

    local function Refresh()
        if _G._ERB_Apply then _G._ERB_Apply() end
    end

    ---------------------------------------------------------------------------
    --  Lerps current -> target, calling applyFn(v) each frame; key cancels a
    --  prior anim on the same property.
    ---------------------------------------------------------------------------
    local _animTimers = {}  -- [frame][key] = ticker
    local ANIM_DURATION = 0.18

    local function SmoothAnimate(frame, key, targetVal, applyFn)
        if not frame then return end
        if not _animTimers[frame] then _animTimers[frame] = {} end
        if _animTimers[frame][key] then
            _animTimers[frame][key]:Cancel()
            _animTimers[frame][key] = nil
        end
        local startVal = frame["_anim_" .. key] or targetVal
        frame["_anim_" .. key] = targetVal
        if math.abs(startVal - targetVal) < 0.001 then
            applyFn(targetVal)
            return
        end
        local elapsed = 0
        local ticker
        -- A frame of the options page pool dressed again mid-animation belongs
        -- to its new build: the animation stops and leaves it alone.
        local gen = PoolGen(frame)
        ticker = C_Timer.NewTicker(0.016, function()
            if PoolGen(frame) ~= gen then
                ticker:Cancel()
                local slots = _animTimers[frame]
                if slots and slots[key] == ticker then slots[key] = nil end
                return
            end
            elapsed = elapsed + 0.016
            local t = math.min(elapsed / ANIM_DURATION, 1)
            t = 1 - (1 - t) * (1 - t)  -- ease-out quad
            local v = startVal + (targetVal - startVal) * t
            applyFn(v)
            if t >= 1 then
                ticker:Cancel()
                if _animTimers[frame] then _animTimers[frame][key] = nil end
            end
        end)
        _animTimers[frame][key] = ticker
    end

    -- Preview Header
    local _previewHeaderBuilder
    local _previewFrames = {}
    local _previewHintFS
    local _previewScale = 1
    local _previewBuilding = false  -- true while _previewHeaderBuilder is executing
    local HasClassResource     -- forward decl

    HasClassResource = function()
        local gsr = _G._ERB_GetSecondaryResource
        return gsr and gsr() ~= nil
    end

    local HasPrimaryPower = function()
        local gpp = _G._ERB_GetPrimaryPowerType
        return gpp and gpp() ~= nil
    end

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    -- The preview hint is one font string the Class, Power and Health Bars and
    -- Cast Bar headers share, each build moving it onto its own header. Under
    -- page reuse each page keeps a header frame of its own (a frame of the
    -- options page pool): a build starts with the hint off its own header, as
    -- the shared header's clear dropped it, and a header shown again from the
    -- cache takes the hint back from the other page's header (with one shared
    -- header frame its cache restore already did).
    local _hintHdr = {}  -- [page] = the header frame that page's preview last built on
    local _classHdrEmpty -- the Class, Power and Health Bars header last built into its kept frame with nothing to show
    local function HintBuildStart(page, hdr)
        _hintHdr[page] = hdr
        local host = PoolGen(hdr) and _previewHintFS and _previewHintFS:GetParent()
        if host and host:GetParent() == hdr then host:Hide() end
    end
    local function RehomeHint(page)
        local host = _previewHintFS and _previewHintFS:GetParent()
        local hdr = _hintHdr[page]
        if not (host and hdr) then return end
        -- The hint may sit on any other preview page's header.
        local cur, away = host:GetParent(), nil
        for other, oh in pairs(_hintHdr) do
            if other ~= page then
                if oh == hdr then return end
                if oh == cur then away = oh end
            end
        end
        if not away and cur ~= hdr then return end
        if away then
            host:SetParent(hdr)
            host:SetFrameLevel(hdr:GetFrameLevel() + 1)
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 20)
        end
        if host:GetParent() == hdr then host:Show() end
    end

    local FONT_PATH = (EllesmereUI.GetFontPath("resourceBars"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    local SetPVFont = EllesmereUI.ApplyModuleFont
    local CONTENT_PAD = 45
    local SIDE_PAD = 20

    local CLASS_COLORS = {
        WARRIOR     = { 0.78, 0.61, 0.43 },
        PALADIN     = { 0.96, 0.55, 0.73 },
        HUNTER      = { 0.67, 0.83, 0.45 },
        ROGUE       = { 1.00, 0.96, 0.41 },
        PRIEST      = { 1.00, 1.00, 1.00 },
        DEATHKNIGHT = { 0.77, 0.12, 0.23 },
        SHAMAN      = { 0.00, 0.44, 0.87 },
        MAGE        = { 0.25, 0.78, 0.92 },
        WARLOCK     = { 0.53, 0.53, 0.93 },
        MONK        = { 0.00, 1.00, 0.60 },
        DRUID       = { 1.00, 0.49, 0.04 },
        DEMONHUNTER = { 0.64, 0.19, 0.79 },
        EVOKER      = { 0.20, 0.58, 0.50 },
    }

    -- Dark Mode preview colors come from the global per-profile palette (GetDarkModeFill/GetDarkModeBg); like the live bars, opacity sliders are ignored (background stays at alpha 1).

    -- Snap() uses the preview container's own effective scale, not PixelUtil (which snaps to screen pixels and can disagree with the preview grid).
    local UnsnapTex = EllesmereUI.PP.DisablePixelSnap

    local _previewSnap  -- rebuilt per preview build in _previewHeaderBuilder

    local _borderRefreshers = {}  -- re-snap sizes when scale changes
    -- Pixel-perfect preview border via the unified PP border system (raw integer sizes, never scaled).
    local function MakePreviewBorder(parent, r, g, b, a, size)
        local alpha = a or 1
        local sz = size or 1

        local bf = CreateFrame("Frame", nil, parent)
        bf:SetAllPoints(parent)
        bf:SetFrameLevel(parent:GetFrameLevel() + 2)

        local PP = EllesmereUI and EllesmereUI.PP
        if PP then
            PP.CreateBorder(bf, r, g, b, alpha, sz, "BORDER", 7)
        end

        return {
            _frame = bf, edges = (PP and PP.GetBorders(bf)) or {},
            SetColor = function(self, cr, cg, cb, ca)
                if PP then PP.SetBorderColor(bf, cr, cg, cb, ca or 1) end
            end,
            SetSize = function(self, newSz)
                if PP then PP.SetBorderSize(bf, newSz) end
            end,
            SetShown = function(self, shown)
                if PP then
                    if shown then PP.ShowBorder(bf) else PP.HideBorder(bf) end
                end
            end,
        }
    end

    local _previewPipCount = 3  -- randomized each page visit
    local _previewBarFillPct = 65 -- randomized each page visit (30-80)
    local _headerBaseH = 0  -- preview area height without the hint line (set by every preview build)

    -- Power and Health Bar previews: the live bar's shape (an outer frame with
    -- the border and text over a StatusBar holding the fill and background),
    -- built through the options pool and styled from the same settings the
    -- live build reads. Always horizontal: the stack shows size and look, not
    -- the on-screen placement or orientation.
    local PreviewBar = {}
    function PreviewBar.Build(parent)
        local bar = CreateFrame("Frame", nil, parent)
        local sb = CreateFrame("StatusBar", nil, bar)
        sb:SetAllPoints()
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        sb:SetMinMaxValues(0, 100)
        bar._sb = sb
        -- ns.ERB_SeatBlizzMask reads the fill through the host, as on a live bar.
        bar.GetStatusBarTexture = function() return sb:GetStatusBarTexture() end
        local bg = sb:CreateTexture(nil, "BACKGROUND")
        UnsnapTex(bg)
        bar._bg = bg
        bar._border = { _frame = CreateFrame("Frame", nil, bar) }
        -- Hash lines sit above the fill, as the live tick overlay does.
        local th = CreateFrame("Frame", nil, bar)
        th:SetAllPoints(sb)
        th:SetFrameLevel(sb:GetFrameLevel() + 1)
        bar._tickHost, bar._ticks = th, {}
        local tf = CreateFrame("Frame", nil, bar)
        tf:SetAllPoints(bar)
        tf:SetFrameLevel(bar:GetFrameLevel() + 10)
        bar._text = tf:CreateFontString(nil, "OVERLAY")
        return bar
    end

    -- A preview whose bar is off: dimmed like the page's greyed controls, and
    -- its hit overlays hidden so no click leads to those rows. hits: optional.
    function PreviewBar.Lock(frame, on, hits)
        frame:SetAlpha(on and 1 or 0.3)
        if hits then
            for _, hit in ipairs(hits) do hit:SetShown(on) end
        end
    end

    -- The click hint of the preview showing now: only while it has something to click.
    -- hdr: that preview's header; the hint shows only once it sits there.
    function PreviewBar.HintFor(on, hdr)
        -- A dismissed hint is left to its fade (DismissPreviewHint).
        if not _previewHintFS or IsPreviewHintDismissed() then return end
        local host = _previewHintFS:GetParent()
        _previewHintFS:SetShown(on and host and host:GetParent() == hdr or false)
    end

    -- Size the shown header for its preview (baseH) and the hint, only on a
    -- change of at least one physical pixel (the header snaps to them).
    -- Silent: a resize here must move the page down, not scroll it under the header.
    function PreviewBar.SizeHeader(hdr, baseH)
        -- The hint's dismiss fade sizes the header to this: never another page's.
        _headerBaseH = baseH
        local want = baseH + ((_previewHintFS and _previewHintFS:IsShown()) and 35 or 0)
        local es = hdr:GetEffectiveScale()
        local px = (es > 0) and (EllesmereUI.PP.perfect / es) or 1
        if math.abs(hdr:GetHeight() - want) < px * 0.5 then return end
        EllesmereUI:SetContentHeaderHeightSilent(want)
    end

    -- nil while the bar can show in the preview, else the eye's tooltip
    -- (the house "This option requires X to be enabled" sentence).
    function PreviewBar.Avail(p, key)
        local sp = p.secondary
        if key == "classResource" then
            if not sp.enabled then return EllesmereUI.DisabledTooltip("Class Resource") end
            if not HasClassResource() then return EllesmereUI.L("This option needs a specialization with a class resource") end
        elseif key == "power" then
            if p.primary.enabled == false then return EllesmereUI.DisabledTooltip("Power Bar") end
            if not HasPrimaryPower() then return EllesmereUI.L("This option needs a specialization with a power bar") end
            -- Druid per-form disable, as the live IsPowerBarHidden.
            if _G._ERB_BarHiddenByForm and _G._ERB_BarHiddenByForm(p.primary) then
                return EllesmereUI.L("This option is turned off for the current form")
            end
            -- Power hides while the class resource replaces it, as live.
            if sp.hidePowerIfResource and sp.enabled ~= false and HasClassResource() then
                return EllesmereUI.DisabledTooltip("Hide Power Bar if Resource", "disabled")
            end
        elseif key == "health" then
            if not p.health.enabled then return EllesmereUI.DisabledTooltip("Health Bar") end
        elseif key == "arcaneSoul" then
            if not (p.arcaneSoul and p.arcaneSoul.enabled) then return EllesmereUI.DisabledTooltip("Arcane Soul Helper") end
        end
        return nil
    end

    -- kind: "power" or "health"; c: p.primary or p.health.
    function PreviewBar.Style(bar, p, c, kind)
        local g = p.general
        local isHealth = kind == "health"
        local w = _previewSnap(c.width or 214)
        local h = _previewSnap(c.height or (isHealth and 16 or 14))
        bar:SetSize(w, h)

        local bf = bar._border._frame
        if ns.ERB_BarsBlizz() then
            bf:Hide()
            ns.ERB_ApplyBlizzBarChrome(bar, bar._sb, w, h, false, ns.ERB_BarFrameK(c))
        else
            bf:SetFrameLevel(c.borderBehind and math.max(0, bar:GetFrameLevel() - 1) or (bar:GetFrameLevel() + 1))
            -- Extend Top / Extend Bottom are power bar only, as live.
            if isHealth then ns.ERB_AnchorBorderHost(bf, bar) else ns.ERB_AnchorBorderHost(bf, bar, ns.ERB_BorderExtents(c)) end
            EllesmereUI.ApplyBorderStyle(bf, c.borderSize or 0,
                c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1,
                c.borderTexture or "solid", c.borderTextureOffset, c.borderTextureOffsetY,
                c.borderTextureShiftX, c.borderTextureShiftY, "resourcebars", c.borderSize or 0,
                nil, EllesmereUI.BorderPx(c.borderSizePx, c.borderSize or 0, c.borderTexture or "solid"))
            bf:Show()
        end

        -- The bar's own texture counts only while splitTex is on, as live.
        local texKey = (p.splitTex == true and c.barTexture) or g.barTexture
        local sb = bar._sb
        sb:SetStatusBarTexture(EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, texKey or "none", "Interface\\Buttons\\WHITE8x8"))
        if bar._blizzBarMask then ns.ERB_SeatBlizzMask(bar) end
        local ft = sb:GetStatusBarTexture()
        UnsnapTex(ft)

        -- Fill colour: custom > class colour (health) or power type colour (power).
        local ptype = (not isHealth) and _G._ERB_GetPrimaryPowerType and _G._ERB_GetPrimaryPowerType()
        local typeCol
        if isHealth then
            local _, cf = UnitClass("player")
            typeCol = CLASS_COLORS[cf]
        else
            typeCol = ptype and _G._ERB_PowerColors and _G._ERB_PowerColors[ptype]
        end
        local fR, fG, fB
        if c.customColored then
            fR, fG, fB = c.fillR, c.fillG, c.fillB
        elseif typeCol then
            fR, fG, fB = typeCol[1], typeCol[2], typeCol[3]
        elseif isHealth then
            fR, fG, fB = 0.15, 0.75, 0.30
        else
            fR, fG, fB = 1, 1, 1
        end

        -- Threshold, bands and hash lines from the same per-spec entry the live
        -- update resolves, against the player's real maximum (value-mode hash
        -- lines and bands); 500K health / 100 power when it reads secret or 0.
        local mx = isHealth and UnitHealthMax("player") or (ptype and UnitPowerMax("player", ptype))
        if not mx or (issecretvalue and issecretvalue(mx)) or mx <= 0 then mx = isHealth and 500000 or 100 end
        local tsEntry = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(c) or nil
        local bandOn, bands, bandMode, bandRev
        if _G._ERB_ResolveBandConfig then bandOn, bands, bandMode, bandRev = _G._ERB_ResolveBandConfig(c, tsEntry) end
        local thEntry = (tsEntry and tsEntry.thresholdEnabled ~= false) and tsEntry or nil
        -- Health colours at or below the threshold; power above it, or below with Partial Only.
        local below = isHealth
        if not isHealth and thEntry then
            below = thEntry.thresholdPartialOnly
            if below == nil then below = c.thresholdPartialOnly end
        end
        local tPct = thEntry and (thEntry.thresholdPct or c.thresholdPct or 30)

        -- The random fill only: a threshold or band colours it when the value reaches it, as live.
        local pct = isHealth and (100 - math.floor(_previewBarFillPct / 3)) or _previewBarFillPct

        local aR, aG, aB, aA  -- threshold or band colour in force, nil = base colour
        if bandOn and _G._ERB_FindCountBand then
            local band = _G._ERB_FindCountBand(bands, (bandMode == "value") and (mx * pct / 100) or pct, bandRev)
            if band then aR, aG, aB, aA = band.r or 1, band.g or 1, band.b or 1, band.a or 1 end
        elseif thEntry then
            if (below and pct <= tPct) or (not below and pct > tPct) then
                aR, aG, aB, aA = thEntry.thresholdR or c.thresholdR or 1, thEntry.thresholdG or c.thresholdG or 0.2,
                    thEntry.thresholdB or c.thresholdB or 0.2, 1
            end
        end
        local fmt = c.textFormat or "none"
        local textInstead = thEntry and thEntry.thresholdTextInstead and fmt ~= "none"

        -- Plain texture calls, not the live change-gated helpers: their memo
        -- would outlive a pool reset of this texture.
        if aR and not textInstead then
            ft:SetVertexColor(aR, aG, aB, aA)
        elseif c.gradientEnabled then
            ft:SetVertexColor(1, 1, 1, 1)
            ft:SetGradient(c.gradientDir or "HORIZONTAL", CreateColor(fR, fG, fB, 1),
                CreateColor(c.gradientR or 1, c.gradientG or 1, c.gradientB or 1, c.gradientA or 1))
        else
            ft:SetVertexColor(fR, fG, fB, 1)
        end

        local bg = bar._bg
        bg:SetColorTexture(c.bgR or 0, c.bgG or 0, c.bgB or 0, c.bgA or 0.75)
        UnsnapTex(bg)
        if g.barTextureBg or bg._erbBgTex then
            ns.ERB_BgTexture(bg, g.barTextureBg and (c.fillOpacity or 100) >= 100
                and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, texKey, nil), c.bgR, c.bgG, c.bgB, c.bgA)
        end

        sb:SetValue(pct)
        -- Fill Opacity: translucent fill, background over the empty part only (as the class resource preview).
        local op = (c.fillOpacity or 100) / 100
        ft:SetAlpha(op)
        bg:ClearAllPoints()
        if op < 1 then
            bg:SetPoint("TOPLEFT", ft, "TOPRIGHT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
        else
            bg:SetAllPoints(sb)
        end

        -- Hash lines: the entry's own, else the bar-wide ones (ns.ApplyHashLines' source rule).
        do
            local ticks = bar._ticks
            for i = 1, #ticks do ticks[i]:Hide() end
            local hEnt = (tsEntry and tsEntry.hashValues and tsEntry.hashValues ~= "") and tsEntry
                or (c.hashEnabled and c) or nil
            local hashStr = hEnt and hEnt.hashValues or ""
            local isPercent = hEnt and (hEnt.hashMode or "percent") == "percent"
            local P = EllesmereUI.PP
            local pxW = (hEnt and hEnt.hashWidth or 1) * P.mult  -- physical pixels, as live
            -- Inside the border, as live: a solid border's exact size is the inset.
            local hbs = c.borderSize or 0
            local htex = c.borderTexture
            if not htex or htex == "" or htex == "solid" then
                hbs = EllesmereUI.BorderPx(c.borderSizePx, hbs, htex) or hbs
            end
            local vI = math.min(hbs * P.mult, math.max(0, (h - 1) / 2))
            local n = 0
            for s in hashStr:gmatch("[^,]+") do
                local v = tonumber(s:match("^%s*(.-)%s*$"))
                local frac = v and v > 0 and v / (isPercent and 100 or mx)
                if frac and frac <= 1 then
                    n = n + 1
                    local t = ticks[n]
                    if not t then
                        t = bar._tickHost:CreateTexture(nil, "OVERLAY", nil, 7)
                        UnsnapTex(t)
                        ticks[n] = t
                    end
                    t:SetColorTexture(hEnt.hashColorR or 1, hEnt.hashColorG or 1, hEnt.hashColorB or 1, hEnt.hashColorA or 0.7)
                    t:ClearAllPoints()
                    t:SetSize(pxW, h - vI * 2)
                    t:SetPoint("TOPLEFT", sb, "TOPLEFT", math.min(P.Scale(w * frac), w - pxW), -vI)
                    t:Show()
                end
            end
        end

        ns.ERB_RoundBar(bar, c)

        -- Text in the live formats, from the made-up values.
        local text = bar._text
        if fmt == "none" then
            text:Hide()
            return
        end
        local txt
        if isHealth then
            local curStr = ns.AbbreviateNumbers(math.floor(mx * pct / 100))
            local pctStr = tostring(pct)
            if fmt == "both" then txt = curStr .. " | " .. pctStr .. "%"
            elseif fmt == "curhpshort" then txt = curStr
            elseif fmt == "curmaxhp" then txt = curStr .. " / " .. ns.AbbreviateNumbers(mx)
            elseif fmt == "perhpnosign" then txt = pctStr
            elseif fmt == "perhpnum" then txt = pctStr .. "% | " .. curStr
            else txt = pctStr .. "%" end
        else
            local percentText = tostring(pct) .. ((c.showPercent == false) and "" or "%")
            local curStr = ns.AbbreviateNumbers(math.floor(mx * pct / 100))
            if fmt == "smart" then
                local isPercent = EllesmereUI.IsSmartPowerPercent and EllesmereUI.IsSmartPowerPercent(ptype)
                txt = isPercent and percentText or curStr
            elseif fmt == "both" then txt = curStr .. " | " .. percentText
            elseif fmt == "curpp" then txt = curStr
            elseif fmt == "curmaxpp" then txt = curStr .. " / " .. ns.AbbreviateNumbers(mx)
            elseif fmt == "perpp" then txt = percentText
            else txt = curStr end
        end
        SetPVFont(text, FONT_PATH, c.textSize or 11)
        text:ClearAllPoints()
        local ta = c.textAnchor or "CENTER"
        text:SetPoint(ta, bar, ta, c.textXOffset or 0, c.textYOffset or 0)
        if aR and textInstead then
            text:SetTextColor(aR, aG, aB, aA)
        elseif c.textCustomColored == false and typeCol then
            text:SetTextColor(typeCol[1], typeCol[2], typeCol[3], 1)
        elseif c.textCustomColored == false then
            text:SetTextColor(1, 1, 1, 1)
        else
            text:SetTextColor(c.textFillR or 1, c.textFillG or 1, c.textFillB or 1, c.textFillA or 1)
        end
        text:SetText(txt)
        text:Show()
    end

    -- Discrete pip count for the current spec: the real resource max (Fury
    -- Whirlwind 4, Arms Sweeping Strikes 18, DK runes 6, Maelstrom Weapon
    -- 5/10, ...) so the preview matches the live bar; 5 when none exists.
    local function PreviewPipCount()
        local gsr = _G._ERB_GetSecondaryResource
        local info = gsr and gsr()
        if not info or info.type == "bar" then return 5 end
        local m = info.max
        -- Talent-dependent maxes come from the live sources
        if info.power == "SWEEPING_STRIKES" or info.power == "WHIRLWIND_STACKS" then
            local realMax = _G._EWC and _G._EWC.MaxApps(info.power)
            if realMax and realMax > 0 then m = realMax end
        elseif info.power == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
            local _, realMax = EllesmereUI.GetMaelstromWeapon()
            if realMax and realMax > 0 then m = realMax end
        end
        if type(m) == "number" and m >= 2 and m <= 20 then return m end
        return 5
    end

    local function UpdatePreviewHeader()
        local p = DB()
        if not p then return end

        -- Session-only eye state of the section headers (BarDisplayPage_Options.lua), shown by default.
        local pvHidden = ns._erbPvHidden or {}
        local hasCR = HasClassResource()
        if not hasCR and _previewFrames.pipContainer then _previewFrames.pipContainer:Hide() end

        local container = _previewFrames.container
        local sp = p.secondary
        local isBar = ns.IsBarTypeSecondary()

        local pc = hasCR and _previewFrames.pipContainer
        if pc then
            local pipH = sp.pipHeight

            local _, cf = UnitClass("player")
            local cc = CLASS_COLORS[cf]
            local pr, pg, pb
            if sp.darkTheme then
                pr, pg, pb = EllesmereUI.GetDarkModeFill()
            elseif sp.resourceColored then
                -- Per-spec resource/power color, falls back to class color
                local gsr = _G._ERB_GetSecondaryResource
                local rslv = _G._ERB_ResolveSecondaryResourceColor
                local rr, rg, rb
                if gsr and rslv then
                    local info = gsr()
                    if info and info.power ~= nil then rr, rg, rb = rslv(info.power) end
                end
                if rr then pr, pg, pb = rr, rg, rb
                else pr, pg, pb = cc and cc[1] or 0.95, cc and cc[2] or 0.90, cc and cc[3] or 0.60 end
            elseif sp.classColored ~= false then
                pr, pg, pb = cc and cc[1] or 0.95, cc and cc[2] or 0.90, cc and cc[3] or 0.60
            else
                -- classColored explicitly false: custom fill color
                pr, pg, pb = sp.fillR, sp.fillG, sp.fillB
            end

            local pScale = 1.0  -- static center, no y-offset interaction with preview
            local function ApplyPipTransform()
                local s = pc["_anim_scale"] or pScale
                pc:SetScale(s)
                pc:ClearAllPoints()
                pc:SetPoint("CENTER", container, "CENTER", 0, pc._pvY or 0)  -- _pvY: its slot in the stack below
            end
            SmoothAnimate(pc, "scale", pScale, function() ApplyPipTransform() end)

            if isBar then
                local totalW = p.primary.width or 214
                pc:SetSize(totalW, pipH)

                if pc._barBg then
                    if sp.darkTheme then
                        local _dbr, _dbg, _dbb = EllesmereUI.GetDarkModeBg()
                        pc._barBg:SetColorTexture(_dbr, _dbg, _dbb, 1)
                    elseif sp.classColored then
                        pc._barBg:SetColorTexture(pr * 0.3, pg * 0.3, pb * 0.3, 0.5)
                    else
                        pc._barBg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                    end
                    UnsnapTex(pc._barBg)
                    -- Textured Background on the preview's one background, in the colour above.
                    if p.general.barTextureBg or pc._barBg._erbBgTex then
                        local br, bgg, bb, ba = sp.bgR, sp.bgG, sp.bgB, sp.bgA
                        if sp.darkTheme then
                            br, bgg, bb = EllesmereUI.GetDarkModeBg()
                            ba = 1
                        elseif sp.classColored then
                            br, bgg, bb, ba = pr * 0.3, pg * 0.3, pb * 0.3, 0.5
                        end
                        ns.ERB_BgTexture(pc._barBg, p.general.barTextureBg and (sp.fillOpacity or 100) >= 100
                            and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, p.general.barTexture, nil), br, bgg, bb, ba)
                    end
                end

                if pc._barFill then
                    local fillFrac = _previewBarFillPct / 100
                    pc._barFill:SetWidth(totalW * fillFrac)
                    pc._barFill:SetHeight(pipH)
                    local texKey = p.general.barTexture or "none"
                    local texLookup = _G._ERB_BarTextures or {}
                    local texPath = texLookup[texKey]
                    if texPath then
                        pc._barFill:SetTexture(texPath)
                    else
                        pc._barFill:SetTexture("Interface\\Buttons\\WHITE8x8")
                    end
                    pc._barFill:SetVertexColor(pr, pg, pb, 1)
                    UnsnapTex(pc._barFill)
                    pc._barFill:Show()
                    -- Fill Opacity: translucent fill + bg over the empty portion only (mirrors the live bar)
                    local _pvOp = (sp.fillOpacity or 100) / 100
                    pc._barFill:SetAlpha(_pvOp)
                    if pc._barBg then
                        pc._barBg:ClearAllPoints()
                        if _pvOp < 1 then
                            pc._barBg:SetPoint("TOPLEFT", pc._barFill, "TOPRIGHT", 0, 0)
                            pc._barBg:SetPoint("BOTTOMRIGHT", pc, "BOTTOMRIGHT", 0, 0)
                        else
                            pc._barBg:SetAllPoints(pc)
                        end
                    end
                end

                -- Tick marks on bar preview
                if not pc._previewTicks then pc._previewTicks = {} end
                do
                    -- Hash lines come from the thresholdSpecs entry; tickValues is the fallback
                    local _pvTsEntry = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(sp) or nil
                    local tickStr = (_pvTsEntry and _pvTsEntry.hashValues ~= "") and _pvTsEntry.hashValues or (sp.tickValues or "")
                    local ticks = pc._previewTicks
                    for i = 1, #ticks do ticks[i]:Hide() end
                    local vals = {}
                    for s in tickStr:gmatch("[^,]+") do
                        local n = tonumber(s:match("^%s*(.-)%s*$"))
                        if n and n > 0 then vals[#vals + 1] = n end
                    end
                    -- Tick positions use the actual resource max
                    local gsr = _G._ERB_GetSecondaryResource
                    local secInfo = gsr and gsr()
                    local previewMax = (secInfo and secInfo.max) or 100
                    local _pvHashPct = _pvTsEntry and _pvTsEntry.hashMode == "percent"
                    local PP = EllesmereUI and EllesmereUI.PP
                    local onePx = PP and PP.Scale(1) or 1
                    for i, v in ipairs(vals) do
                        local _pvFrac, _pvOk
                        if _pvHashPct then
                            _pvOk = (v <= 100); _pvFrac = v / 100
                        else
                            _pvOk = (v <= previewMax); _pvFrac = v / previewMax
                        end
                        if _pvOk then
                            if not ticks[i] then
                                local t = pc:CreateTexture(nil, "OVERLAY", nil, 7)
                                t:SetColorTexture(1, 1, 1, 1)
                                t:SetSnapToPixelGrid(false)
                                t:SetTexelSnappingBias(0)
                                ticks[i] = t
                            end
                            local t = ticks[i]
                            t:ClearAllPoints()
                            local frac = _pvFrac
                            local off = PP and PP.Scale(totalW * frac) or (totalW * frac)
                            t:SetSize(onePx, pipH)
                            t:SetPoint("TOPLEFT", pc, "TOPLEFT", off, 0)
                            t:Show()
                        end
                    end
                end

                -- Separators: the bottom-edge line (bar types have no gaps), as live.
                ns.ERB_Separators(pc, sp, (sp.edgeSep and sp.edgeSepH ~= false and ns.ERB_Textured(sp)
                    and not EllesmereUI.BlizzStyle.Get("resourcebars")) and true or false, pc:GetFrameLevel() + 5)
                -- Bar-type has no pips: hide pips and gap fills from a prior build
                for _, pip in ipairs(_previewFrames.pips) do pip:Hide() end
                if pc._gapFills then for i = 1, #pc._gapFills do pc._gapFills[i]:Hide() end end
            else
                -- Pips preview: same pixel-perfect geometry as the live resource bar
                local CalcPG = _G._ERB_CalcPipGeometry
                local pcScale = pc:GetEffectiveScale()
                if pcScale <= 0 then pcScale = 1 end
                -- One physical pixel in this frame's units, as CalcPipGeometry.
                local onePx = EllesmereUI.PP.perfect / pcScale
                local function PipSnap(val)
                    return math.floor(val / onePx + 0.5) * onePx
                end
                local totalW = PipSnap(sp.pipWidth)
                local snappedPipH = PipSnap(sp.pipHeight)
                local numPips = PreviewPipCount()
                local isVertical = false
                local isReversed = false

                local slots
                if CalcPG then
                    slots = CalcPG(totalW, numPips, sp.pipSpacing or 1, pc)
                end

                local pipX = {}
                local pipW = {}
                if slots then
                    for i = 1, numPips do
                        pipX[i] = slots[i].x0
                        pipW[i] = slots[i].x1 - slots[i].x0
                    end
                else
                    -- Fallback while CalcPipGeometry is not loaded yet
                    local pipSp = (sp.pipSpacing > 0) and math.max(onePx, PipSnap(sp.pipSpacing)) or 0
                    local availW = totalW - (numPips - 1) * pipSp
                    local baseW = math.floor(availW / onePx / numPips) * onePx
                    local leftover = availW - baseW * numPips
                    local extraCount = math.floor(leftover / onePx + 0.5)
                    local x0 = 0
                    for i = 1, numPips do
                        pipX[i] = x0
                        pipW[i] = baseW + (i <= extraCount and onePx or 0)
                        x0 = x0 + pipW[i] + pipSp
                    end
                end
                if isVertical then
                    pc:SetSize(snappedPipH, totalW)
                else
                    pc:SetSize(totalW, snappedPipH)
                end

                -- Threshold and bands as the live pips resolve them (Update.lua):
                -- "From" (>=) or "Up to" (<=, thresholdReverse), Partial Only
                -- ("From" only), multi-band, and Recolor Text Instead.
                local _pvTsEntry2 = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(sp) or nil
                local FindCountBand = _G._ERB_FindCountBand
                local _pvBandOn, _pvBands, _pvBandRev
                if _G._ERB_ResolveBandConfig and FindCountBand then
                    local on, bands, _, rev = _G._ERB_ResolveBandConfig(sp, _pvTsEntry2)
                    _pvBandOn, _pvBands, _pvBandRev = on, bands, rev
                end
                local _pvTsEnabled = _pvTsEntry2 and (_pvTsEntry2.thresholdEnabled ~= false) or false
                local _pvThreshCount = _pvTsEntry2 and _pvTsEntry2.thresholdCount or sp.thresholdCount or 3
                -- Enhance Five Bar needs at least 7 (5 pips + overflow), as live clamps it.
                if _pvTsEnabled and sp.enhanceFiveBar and _pvThreshCount < 7 then
                    local info = _G._ERB_GetSecondaryResource and _G._ERB_GetSecondaryResource()
                    if info and info.power == "MAELSTROM_WEAPON" then _pvThreshCount = 7 end
                end
                local _pvPartialOnly = _pvTsEntry2 and _pvTsEntry2.thresholdPartialOnly
                if _pvPartialOnly == nil then _pvPartialOnly = sp.thresholdPartialOnly end
                local _pvReverse = _pvTsEntry2 and _pvTsEntry2.thresholdReverse
                if _pvReverse == nil then _pvReverse = sp.thresholdReverse end
                if _pvReverse then _pvPartialOnly = false end
                -- The random fill only: a threshold or band colours it when the value reaches it, as live.
                local filledCount = _previewPipCount
                -- _previewPipCount is randomized against a generic 5-pip preview; rescale for other counts (e.g. 18 Sweeping Strikes)
                if numPips ~= 5 then
                    filledCount = math.max(1, math.min(numPips,
                        math.floor(_previewPipCount / 5 * numPips + 0.5)))
                end
                -- Read by the count-text block so the number matches the lit segments
                pc._pvShownCount = filledCount
                local pvPipBg = ns.ERB_PipBgOn(sp, false)  -- Background on individual pips, as live
                -- current spec threshold color if configured
                local tr = _pvTsEntry2 and _pvTsEntry2.thresholdR or sp.thresholdR
                local tg = _pvTsEntry2 and _pvTsEntry2.thresholdG or sp.thresholdG
                local tb = _pvTsEntry2 and _pvTsEntry2.thresholdB or sp.thresholdB
                local useThresh = _pvTsEnabled and ((_pvReverse and filledCount <= _pvThreshCount)
                    or ((not _pvReverse) and filledCount >= _pvThreshCount))
                if _pvBandOn then
                    local band = FindCountBand(_pvBands, filledCount, _pvBandRev)
                    useThresh = band ~= nil
                    if band then tr, tg, tb = band.r or 1, band.g or 1, band.b or 1 end
                end
                -- Recolor Text Instead: the count text takes the colour, the pips stay at base.
                pc._pvTextCol = nil
                if _pvTsEntry2 and _pvTsEntry2.thresholdTextInstead and sp.showText then
                    if useThresh then pc._pvTextCol = { tr, tg, tb } end
                    useThresh = false
                end

                -- Top up pip frames when this spec needs more than were built (counts run 3-18); the loop below styles them, so bare bg+fill suffice here.
                for i = #_previewFrames.pips + 1, numPips do
                    local pip = CreateFrame("Frame", nil, pc)
                    local bg = pip:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    pip._bg = bg
                    local fill = pip:CreateTexture(nil, "ARTWORK")
                    fill:SetAllPoints()
                    pip._fill = fill
                    _previewFrames.pips[i] = pip
                end
                for i = 1, math.min(numPips, #_previewFrames.pips) do
                    local pip = _previewFrames.pips[i]
                    if isVertical then
                        pip:SetSize(snappedPipH, pipW[i])
                        pip:ClearAllPoints()
                        if isReversed then
                            pip:SetPoint("BOTTOM", pc, "BOTTOM", 0, pipX[i])
                        else
                            pip:SetPoint("TOP", pc, "TOP", 0, -pipX[i])
                        end
                    else
                        pip:SetSize(pipW[i], snappedPipH)
                        pip:ClearAllPoints()
                        pip:SetPoint("LEFT", pc, "LEFT", pipX[i], 0)
                    end
                    if pvPipBg then
                        pip._bg:SetColorTexture(ns.ERB.PipBgColor(sp, true))
                    elseif sp.darkTheme then
                        local _dbr, _dbg, _dbb = EllesmereUI.GetDarkModeBg()
                        pip._bg:SetColorTexture(_dbr, _dbg, _dbb, 1)
                    elseif sp.classColored then
                        pip._bg:SetColorTexture(pr * 0.5, pg * 0.5, pb * 0.5, 0.5)
                    else
                        pip._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                    end
                    UnsnapTex(pip._bg)
                    -- Textured Background, as live, in the colour above.
                    if p.general.barTextureBg or pip._bg._erbBgTex then
                        local br, bgg, bb, ba = sp.bgR, sp.bgG, sp.bgB, sp.bgA
                        if sp.darkTheme then
                            br, bgg, bb = EllesmereUI.GetDarkModeBg()
                            ba = 1
                        elseif sp.classColored then
                            br, bgg, bb, ba = pr * 0.5, pg * 0.5, pb * 0.5, 0.5
                        end
                        ns.ERB_BgTexture(pip._bg, p.general.barTextureBg and not pvPipBg
                            and (sp.fillOpacity or 100) >= 100 and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, p.general.barTexture, nil), br, bgg, bb, ba)
                    end

                    local texKey = p.general.barTexture or "none"
                    local texLookup = _G._ERB_BarTextures or {}
                    local texPath = texLookup[texKey]
                    if texPath then
                        pip._fill:SetTexture(texPath)
                    else
                        pip._fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                    end
                    UnsnapTex(pip._fill)

                    if pip._border then pip._border:SetShown(false) end

                    if sp.borderOnPips then
                        if not pip._borderFrame then
                            local bf = CreateFrame("Frame", nil, pip)
                            bf:SetAllPoints(pip)
                            pip._borderFrame = bf
                        end
                        pip._borderFrame:SetFrameLevel(sp.borderBehind and math.max(0, pip:GetFrameLevel() - 1) or (pip:GetFrameLevel() + 2))
                        EllesmereUI.ApplyBorderStyle(pip._borderFrame, sp.borderSize or 1,
                            sp.borderR or 0, sp.borderG or 0, sp.borderB or 0, sp.borderA or 1,
                            sp.borderTexture or "solid", sp.borderTextureOffset, sp.borderTextureOffsetY,
                            sp.borderTextureShiftX, sp.borderTextureShiftY, "resourcebars", sp.borderSize or 1,
                            nil, EllesmereUI.BorderPx(sp.borderSizePx, sp.borderSize or 1, sp.borderTexture or "solid"))
                        pip._borderFrame:Show()
                    else
                        if pip._borderFrame then pip._borderFrame:Hide() end
                    end
                    local active = i <= filledCount
                    if active and useThresh then
                        if not _pvBandOn and _pvPartialOnly and i < _pvThreshCount then
                            pip._fill:SetVertexColor(pr, pg, pb, 1)
                        else
                            pip._fill:SetVertexColor(tr, tg, tb, 1)
                        end
                        pip._fill:Show()
                    elseif active then
                        pip._fill:SetVertexColor(pr, pg, pb, 1)
                        pip._fill:Show()
                    else
                        pip._fill:Hide()
                    end
                    -- Fill Opacity: translucent fill; active pips hide their bg so the fill reveals what's behind (mirrors live pips)
                    local _pvPipOp = (sp.fillOpacity or 100) / 100
                    pip._fill:SetAlpha(_pvPipOp)
                    pip._bg:SetAlpha((active and (_pvPipOp < 1 or pvPipBg)) and 0 or 1)

                    -- DK rune durations: fake cooldown numbers on unfilled pips
                    if cf == "DEATHKNIGHT" and sp.showText then
                        if not pip._pvCdText then
                            local overlay = CreateFrame("Frame", nil, pip)
                            overlay:SetAllPoints(pip)
                            overlay:SetFrameLevel(pip:GetFrameLevel() + 3)
                            local fs = overlay:CreateFontString(nil, "OVERLAY")
                            fs:SetTextColor(1, 1, 1, 0.9)
                            pip._pvCdText = fs
                        end
                        SetPVFont(pip._pvCdText, FONT_PATH, sp.textSize)
                        pip._pvCdText:ClearAllPoints()
                        pip._pvCdText:SetPoint("CENTER", pip, "CENTER",
                            sp.textXOffset or 0, sp.textYOffset or 0)
                        if not active then
                            -- Higher fake durations for pips further right
                            local fakeDurations = { 2, 4, 6, 7, 9, 10 }
                            pip._pvCdText:SetText(tostring(fakeDurations[i] or ""))
                            pip._pvCdText:Show()
                        else
                            pip._pvCdText:SetText("")
                            pip._pvCdText:Hide()
                        end
                    elseif pip._pvCdText then
                        pip._pvCdText:Hide()
                    end

                    pip:Show()
                end
                for i = numPips + 1, #_previewFrames.pips do
                    _previewFrames.pips[i]:Hide()
                end

                -- Optional gap-color fill layer (mirrors the live bar)
                if not pc._gapFills then pc._gapFills = {} end
                do
                    local pvFills = pc._gapFills
                    if sp.gapColorEnabled and numPips > 1 then
                        local gr, gg, gb, ga = sp.gapR or 0, sp.gapG or 0, sp.gapB or 0, sp.gapA or 1
                        local gn = 0
                        for i = 1, numPips - 1 do
                            local gx = pipX[i] + pipW[i]
                            local gw = pipX[i + 1] - gx
                            if gw and gw > 0 then
                                gn = gn + 1
                                local tex = pvFills[gn]
                                if not tex then
                                    tex = pc:CreateTexture(nil, "BACKGROUND", nil, 0)
                                    UnsnapTex(tex)
                                    pvFills[gn] = tex
                                end
                                tex:SetColorTexture(gr, gg, gb, ga)
                                tex:ClearAllPoints()
                                tex:SetPoint("TOPLEFT", pc, "TOPLEFT", gx, 0)
                                tex:SetPoint("BOTTOMLEFT", pc, "BOTTOMLEFT", gx, 0)
                                tex:SetWidth(gw)
                                tex:Show()
                            end
                        end
                        for i = gn + 1, #pvFills do pvFills[i]:Hide() end
                    else
                        for i = 1, #pvFills do pvFills[i]:Hide() end
                    end
                end

                -- Separators: the bottom-edge line and one line per gap, as live.
                do
                    local on = sp.edgeSep and ns.ERB_Textured(sp) and not EllesmereUI.BlizzStyle.Get("resourcebars")
                    ns.ERB_Separators(pc, sp, (on and sp.edgeSepH ~= false) and true or false, pc:GetFrameLevel() + 5,
                        (on and sp.edgeSepV ~= false) and slots or nil, numPips, false, false)
                end

                -- Hide bar fill / ticks left from a previous build
                if pc._barFill then pc._barFill:Hide() end
                if pc._previewTicks then
                    for i = 1, #pc._previewTicks do pc._previewTicks[i]:Hide() end
                end
            end

            -- Full-bar border on container (PP or textured, via ApplyBorderStyle)
            if not pc._barBorderFrame then
                local bf = CreateFrame("Frame", nil, pc)
                bf:SetAllPoints(pc)
                pc._barBorderFrame = bf
            end
            pc._barBorderFrame:SetFrameLevel(sp.borderBehind and math.max(0, pc:GetFrameLevel() - 1) or (pc:GetFrameLevel() + 2))

            if EllesmereUI.BlizzStyle.Get("resourcebars") then
                -- Blizzard Style / Classic WoW UI: the stock bar frame (the
                -- same art and overhang the live bars use) instead of the
                -- full-bar border.
                pc._barBorderFrame:Hide()
                if ns.ERB_BarsClassic() then
                    -- Classic WoW UI: the vanilla frame round the row (the
                    -- live seat on this mock); no mask, no bevel.
                    ns.ERB_ApplyClassicBarChrome(pc, nil, nil, nil, nil, ns.ERB_BarFrameK(sp))
                else -- Blizzard Style kit (indentation kept)
                local bbg = pc._blizzBarBg
                if not bbg then
                    bbg = pc:CreateTexture(nil, "BACKGROUND", nil, -2)
                    if C_Texture.GetAtlasInfo("UI-HUD-CoolDownManager-Bar-BG") then bbg:SetAtlas("UI-HUD-CoolDownManager-Bar-BG") end
                    UnsnapTex(bbg)
                    pc._blizzBarBg = bbg
                end
                bbg:ClearAllPoints()
                bbg:SetPoint("TOPLEFT", pc, "TOPLEFT", -2, 3)
                bbg:SetPoint("BOTTOMRIGHT", pc, "BOTTOMRIGHT", 6, -7)
                bbg:Show()
                -- The stock fill art's footprint masks a bar-type fill and
                -- backing inside the frame's rim, as on the live bars.
                local bm = pc._blizzBarMask
                if not bm and C_Texture.GetAtlasInfo("UI-HUD-CoolDownManager-Bar") then
                    bm = pc:CreateMaskTexture()
                    bm:SetAtlas("UI-HUD-CoolDownManager-Bar")
                    bm:SetAllPoints(pc)
                    pc._blizzBarMask = bm
                end
                if pc._barFill and pc._blizzMaskedFill ~= pc._barFill then
                    pc._barFill:AddMaskTexture(bm); pc._blizzMaskedFill = pc._barFill
                end
                if pc._barBg and pc._blizzMaskedBg ~= pc._barBg then
                    pc._barBg:AddMaskTexture(bm); pc._blizzMaskedBg = pc._barBg
                end
                -- The inner bevel the live rows carry: on the container itself
                -- for a bar-type (its fill is a texture here), on an overlay
                -- above the pips otherwise; pip textures take the mask so the
                -- end pips round off with the frame (the preview is horizontal).
                local shade = pc._blizzShadeFrame
                if isBar then
                    ns.ERB_BlizzBarShadow(pc, bm)
                    if shade then shade:Hide() end
                else
                    if pc._blizzShadow then for i = 1, 4 do pc._blizzShadow[i]:Hide() end end
                    if not shade then
                        shade = CreateFrame("Frame", nil, pc)
                        shade:SetAllPoints(pc)
                        pc._blizzShadeFrame = shade
                    end
                    shade:SetFrameLevel(pc:GetFrameLevel() + 8)
                    shade:Show()
                    ns.ERB_BlizzBarShadow(shade, bm)
                    local pvPips = _previewFrames.pips
                    if pvPips then
                        for i = 1, #pvPips do
                            ns.ERB_MaskTex(pvPips[i]._bg, bm); ns.ERB_MaskTex(pvPips[i]._fill, bm)
                        end
                    end
                end
                end -- Blizzard Style kit
            elseif sp.borderOnPips and not isBar then
                pc._barBorderFrame:Hide()
            else
                -- Extend Top / Extend Bottom, as the live full-bar border draws them.
                ns.ERB_AnchorBorderHost(pc._barBorderFrame, pc, ns.ERB_BorderExtents(sp))
                EllesmereUI.ApplyBorderStyle(pc._barBorderFrame, sp.borderSize or 1,
                    sp.borderR or 0, sp.borderG or 0, sp.borderB or 0, sp.borderA or 1,
                    sp.borderTexture or "solid", sp.borderTextureOffset, sp.borderTextureOffsetY,
                    sp.borderTextureShiftX, sp.borderTextureShiftY, "resourcebars", sp.borderSize or 1,
                    nil, EllesmereUI.BorderPx(sp.borderSizePx, sp.borderSize or 1, sp.borderTexture or "solid"))
                pc._barBorderFrame:Show()
            end

            -- Rounded corners, as on the live class resource (ns.ERB_RoundSecondary).
            do
                local radius = (not ns.ERB_BarsBlizz() and sp.cornerRadius) or 0
                local style = sp.borderTexture or "solid"
                local onPips = sp.borderOnPips and not isBar
                if radius > 0 then
                    EllesmereUI.RoundCorners(pc, radius, {
                        style = style, border = not onPips and pc._barBorderFrame or nil,
                        corners = sp.cornerMask,
                    })
                else
                    EllesmereUI.RoundCorners(pc, 0)
                end
                local pipRadius = onPips and radius or 0
                for i = 1, #_previewFrames.pips do
                    local pip = _previewFrames.pips[i]
                    if pipRadius > 0 then
                        EllesmereUI.RoundCorners(pip, pipRadius, { style = style, border = pip._borderFrame, corners = sp.cornerMask })
                    else
                        EllesmereUI.RoundCorners(pip, 0)
                    end
                end
            end

            -- Full-bar background for pips only; bar-type uses _barBg. Background on
            -- individual pips drops it, as on the live bar.
            if not isBar and not ns.ERB_PipBgOn(sp, false) then
                if not pc._pipBarBg then
                    pc._pipBarBg = pc:CreateTexture(nil, "BACKGROUND", nil, -1)
                    UnsnapTex(pc._pipBarBg)
                end
                pc._pipBarBg:ClearAllPoints()
                pc._pipBarBg:SetAllPoints(pc)
                pc._pipBarBg:SetColorTexture(sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5)
                pc._pipBarBg:Show()
                -- Blizzard Style: the backdrop takes the row's bar-shape mask.
                if pc._blizzBarMask then ns.ERB_MaskTex(pc._pipBarBg, pc._blizzBarMask) end
            elseif pc._pipBarBg then
                pc._pipBarBg:Hide()
            end

            -- Count text (centered on bar); DK uses per-pip durations instead
            local isDK = cf == "DEATHKNIGHT"
            if sp.showText and pc._countText and not isDK then
                SetPVFont(pc._countText, FONT_PATH, sp.textSize)
                pc._countText:ClearAllPoints()
                local _pvTA = sp.textAnchor or "CENTER"
                pc._countText:SetPoint(_pvTA, pc, _pvTA, sp.textXOffset or 0, sp.textYOffset or 0)
                if isBar then
                    local percentSuffix = (sp.showPercent == false) and "" or "%"
                    pc._countText:SetText(tostring(_previewBarFillPct) .. percentSuffix)
                else
                    -- Mirrors the pip loop's filled count so the number matches the lit segments. Pip resources show the bare count only; "cur / max" is exclusive to bar-type stack bars (Show Max Stacks), previewed by the isBar branch.
                    local shown = pc._pvShownCount or _previewPipCount
                    pc._countText:SetText(tostring(shown))
                end
                local tc = (not isBar) and pc._pvTextCol
                if tc then
                    pc._countText:SetTextColor(tc[1], tc[2], tc[3], 1)
                else
                    pc._countText:SetTextColor(sp.textR or 1, sp.textG or 1, sp.textB or 1, 0.9)  -- live base text colour
                end
                pc._countText:Show()
            elseif pc._countText then
                pc._countText:Hide()
            end

            pc:SetShown((not pvHidden.classResource and not PreviewBar.Avail(p, "classResource")) and true or false)
        end

        -- The stack, top to bottom: Class Resource, Power, Health (the live
        -- default order), then Arcane Soul (Mage only, below a divider), each
        -- shown while its bar is on and its eye is open.
        do
            local pb, hb = _previewFrames.powerBar, _previewFrames.healthBar
            local showPower = pb and not pvHidden.power and not PreviewBar.Avail(p, "power")
            local showHealth = hb and not pvHidden.health and not PreviewBar.Avail(p, "health")
            if showPower then PreviewBar.Style(pb, p, p.primary, "power") end
            if showHealth then PreviewBar.Style(hb, p, p.health, "health") end
            if pb then pb:SetShown(showPower and true or false) end
            if hb then hb:SetShown(showHealth and true or false) end

            local asf = _previewFrames.arcaneSoul
            local styleAS = _G._ERB_StyleArcaneSoulSample
            local showAS = asf and styleAS and not pvHidden.arcaneSoul and not PreviewBar.Avail(p, "arcaneSoul")
            if showAS then
                -- Sized from the static sample when its font changed (a font not
                -- loaded yet measures 0: the text size stands in, and deferred
                -- updates measure again, 0.2s doubling up to about 6s in all),
                -- then straight back to the replay.
                local size, changed = styleAS(asf._fs)
                if changed then asf._asTries = 0 end
                if changed or asf._asEstimated then
                    local w, h = asf._fs:GetStringWidth(), asf._fs:GetStringHeight()
                    asf._asEstimated = not (w > 0 and h > 0) or nil
                    asf:SetSize(math.ceil(w > 0 and w or size * 5), math.ceil(h > 0 and h or size))
                    local tries = asf._asTries or 0
                    if asf._asEstimated and tries < 5 then
                        asf._asTries = tries + 1
                        local gen = PoolGen(asf)
                        C_Timer.After(0.2 * 2 ^ tries, function()
                            if PoolGen(asf) == gen and asf:IsVisible() then UpdatePreviewHeader() end
                        end)
                    end
                end
                local tick = _G._ERB_ArcaneSoulDemoTick
                if tick then tick(asf) end
            end
            if asf then asf:SetShown(showAS and true or false) end

            local labels = _previewFrames.labels or {}
            local stack, stackLbl = {}, {}
            if pc and pc:IsShown() then stack[#stack + 1] = pc; stackLbl[#stack] = labels.classResource end
            if showPower then stack[#stack + 1] = pb; stackLbl[#stack] = labels.power end
            if showHealth then stack[#stack + 1] = hb; stackLbl[#stack] = labels.health end
            if showAS then stack[#stack + 1] = asf; stackLbl[#stack] = labels.arcaneSoul end
            for _, fs in pairs(labels) do fs:Hide() end

            -- Each element: its title (a header-scale font string, so its
            -- line and gap convert into the bars' units), then the bar.
            local snap = _previewSnap or function(v) return v end
            local scale = (_previewScale and _previewScale > 0) and _previewScale or 1
            local titleH = (12 + 3) / scale
            local gap = snap(8)
            local total = 0
            for i = 1, #stack do total = total + titleH + stack[i]:GetHeight() end
            total = total + gap * math.max(0, #stack - 1)
            -- A one-pixel divider between the bars and Arcane Soul, as wide as the widest bar.
            local div = _previewFrames.asDivider
            local divAt = (div and container and showAS and #stack > 1) and #stack or nil
            local divH, divW = 0, 0
            if divAt then
                divH = 1 / container:GetEffectiveScale()
                total = total + divH + gap
                for i = 1, divAt - 1 do divW = math.max(divW, stack[i]:GetWidth()) end
            end
            if div then div:SetShown(divAt and true or false) end
            -- Offsets from the container centre, bar edges on the preview's pixel grid.
            local top = snap(total / 2)
            for i = 1, #stack do
                if i == divAt then
                    div:ClearAllPoints()
                    div:SetSize(divW, divH)
                    div:SetPoint("TOP", container, "CENTER", 0, top)
                    top = snap(top - divH - gap)
                end
                local f = stack[i]
                local fh = f:GetHeight()
                local barTop = snap(top - titleH)
                f._pvY = barTop - fh / 2
                f:ClearAllPoints()
                f:SetPoint("CENTER", container, "CENTER", 0, f._pvY)
                local fs = stackLbl[i]
                if fs then
                    fs:ClearAllPoints()
                    fs:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 3)
                    fs:Show()
                end
                top = barTop - fh - gap
            end

            -- At least the former fixed 80px; 20px above and below a taller stack.
            local TOTAL_H = 0
            if #stack > 0 then
                TOTAL_H = math.max(80, math.ceil((total + 40) * _previewScale))
            end
            _headerBaseH = TOTAL_H
            if container then container:SetHeight(math.max(1, TOTAL_H) / _previewScale) end
            if _previewHintFS then
                if TOTAL_H == 0 then
                    _previewHintFS:Hide()
                elseif not _previewBuilding and not IsPreviewHintDismissed() and not _previewHintFS:IsShown()
                    and _previewHintFS:GetParent() and _previewHintFS:GetParent():GetParent() == _hintHdr[PAGE_DISPLAY] then
                    _previewHintFS:Show()
                end
            end
            if not _previewBuilding then
                local hintH = (TOTAL_H > 0 and _previewHintFS and _previewHintFS:IsShown()) and 35 or 0
                EllesmereUI:UpdateContentHeaderHeight(TOTAL_H + hintH)
            end
        end
        -- The section eyes follow (BarDisplayPage_Options.lua).
        if ns._erbPvEyes then
            for _, refresh in pairs(ns._erbPvEyes) do refresh() end
        end
    end

    -- Forward decls for preview click-to-scroll
    local CreateHitOverlay
    local _hitOverlays = {}

    -- Preview Header Builder
    _previewHeaderBuilder = function(hdr, hdrW)
        HintBuildStart(PAGE_DISPLAY, hdr)
        _classHdrEmpty = PoolGen(hdr) ~= nil
        local p = DB()
        if not p then return 0 end
        _previewBuilding = true
        local _, classFile = UnitClass("player")

        local container = CreateFrame("Frame", nil, hdr)
        container:SetSize(hdrW, 100)
        container:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        _previewFrames.container = container

        -- Scale the preview so pixel sizes match real bars on screen: compensate the panel's effective scale against UIParent's.
        local previewScale = UIParent:GetEffectiveScale() / hdr:GetEffectiveScale()
        _previewScale = previewScale
        container:SetScale(previewScale)

        _previewSnap = function(val)
            local s = container:GetEffectiveScale()
            return math.floor(val * s + 0.5) / s
        end

        local sp = p.secondary
        local pipH = sp.pipHeight
        local isBar = ns.IsBarTypeSecondary()

        local pipC = CreateFrame("Frame", nil, container)  -- hosts either pips or the bar preview
        _previewFrames.pipContainer = pipC
        _previewFrames.pips = {}

        if isBar then
            -- Bar-type preview (Devourer, Elemental Shaman)
            local totalW = p.primary.width or 214
            pipC:SetSize(totalW, pipH)
            pipC:SetPoint("CENTER", container, "CENTER", 0, 0)

            local bg = pipC:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            UnsnapTex(bg)
            pipC._barBg = bg

            -- Fill: status-bar style via texture + width clipping
            local fill = pipC:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("LEFT")
            fill:SetHeight(pipH)
            local texKey = p.general.barTexture or "none"
            local texLookup = _G._ERB_BarTextures or {}
            local texPath = texLookup[texKey]
            if texPath then
                fill:SetTexture(texPath)
            else
                fill:SetTexture("Interface\\Buttons\\WHITE8x8")
            end
            UnsnapTex(fill)
            pipC._barFill = fill
        else
            -- pipWidth is the TOTAL bar width, divided evenly across pips; remainder pixels go into pip widths, never spacing.
            local numPips = PreviewPipCount()
            local totalW = sp.pipWidth
            local pipSp = sp.pipSpacing
            local baseW = math.floor((totalW - (numPips - 1) * pipSp) / numPips)
            local remainder = totalW - (numPips - 1) * pipSp - baseW * numPips

            local pipX = {}
            local cursor = 0
            for i = 1, numPips do
                pipX[i] = cursor
                cursor = cursor + baseW + (i <= remainder and 1 or 0) + pipSp
            end
            pipC:SetSize(totalW, pipH)
            pipC:SetPoint("CENTER", container, "CENTER", 0, 0)

            for i = 1, numPips do
                local pip = CreateFrame("Frame", nil, pipC)
                local thisPipW = baseW + (i <= remainder and 1 or 0)
                pip:SetSize(thisPipW, pipH)
                pip:SetPoint("LEFT", pipC, "LEFT", pipX[i], 0)
                local bg = pip:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                if sp.darkTheme then
                    local _dbr, _dbg, _dbb = EllesmereUI.GetDarkModeBg()
                    bg:SetColorTexture(_dbr, _dbg, _dbb, 1)
                elseif sp.classColored then
                    local cc = CLASS_COLORS[classFile]
                    local cr, cg, cb = cc and cc[1] or 0.95, cc and cc[2] or 0.90, cc and cc[3] or 0.60
                    bg:SetColorTexture(cr * 0.5, cg * 0.5, cb * 0.5, 0.5)
                else
                    bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                end
                UnsnapTex(bg)
                pip._bg = bg
                local fill = pip:CreateTexture(nil, "ARTWORK")
                fill:SetAllPoints()
                local texKey = p.general.barTexture or "none"
                local texLookup = _G._ERB_BarTextures or {}
                local texPath = texLookup[texKey]
                if texPath then
                    fill:SetTexture(texPath)
                else
                    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                end
                fill:SetVertexColor(1, 1, 1, 1)
                UnsnapTex(fill)
                pip._fill = fill
                pip._border = MakePreviewBorder(pip, 0, 0, 0, 0, 0)
                pip._border:SetShown(false)
                _previewFrames.pips[i] = pip
            end
        end

        local countTextOverlay = CreateFrame("Frame", nil, pipC)
        countTextOverlay:SetAllPoints(pipC)
        countTextOverlay:SetFrameLevel(pipC:GetFrameLevel() + 10)
        local countText = countTextOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(countText, FONT_PATH, sp.textSize)
        countText:SetTextColor(1, 1, 1, 0.9)
        do local _pvTA = sp.textAnchor or "CENTER"; countText:SetPoint(_pvTA, pipC, _pvTA, sp.textXOffset or 0, sp.textYOffset or 0) end
        pipC._countText = countText

        -- Built for every spec (cheap, pooled); UpdatePreviewHeader shows what applies.
        _previewFrames.powerBar = PreviewBar.Build(container)
        _previewFrames.healthBar = PreviewBar.Build(container)
        -- Arcane Soul: its section exists for retail Mages only, so does its
        -- element. The element replays the live sequence (the eye hides only
        -- it); the watcher keeps the on-screen sample running while this
        -- header shows.
        _previewFrames.arcaneSoul, _previewFrames.asDivider = nil, nil
        if classFile == "MAGE" and not EllesmereUI.IS_FOREVER then
            local asf = CreateFrame("Frame", nil, container)
            asf._fs = asf:CreateFontString(nil, "OVERLAY")
            asf._fs:SetPoint("CENTER", asf, "CENTER", 0, 0)
            asf._fs._asStamp = nil  -- a reused font string is reset: style it again
            asf:SetSize(1, 1)
            if _G._ERB_ArcaneSoulDemoOnUpdate then asf:SetScript("OnUpdate", _G._ERB_ArcaneSoulDemoOnUpdate) end
            _previewFrames.arcaneSoul = asf

            local div = container:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(1, 1, 1, 0.10)
            UnsnapTex(div)
            div:Hide()
            _previewFrames.asDivider = div

            local screenDemo = _G._ERB_ArcaneSoulScreenDemo
            if screenDemo then
                local watch = CreateFrame("Frame", nil, container)
                watch:SetSize(1, 1)
                watch:SetPoint("CENTER")
                watch:SetScript("OnShow", function(self) screenDemo(self, true) end)
                watch:SetScript("OnHide", function(self) screenDemo(self, false) end)
                if watch:IsVisible() then screenDemo(watch, true) end
            end
        end
        -- Element titles at header scale (the hint's size), on a child frame so
        -- the header cache stashes them with the rest.
        do
            local lblHost = CreateFrame("Frame", nil, hdr)
            lblHost:SetAllPoints(hdr)
            lblHost:SetFrameLevel(container:GetFrameLevel() + 1)
            local function Title(text)
                local fs = EllesmereUI.MakeFont(lblHost, 11, nil, 1, 1, 1)
                fs:SetAlpha(0.6)
                fs:SetText(text)
                fs:Hide()
                return fs
            end
            _previewFrames.labels = {
                classResource = Title(EllesmereUI.L("Class Resource")),
                power = Title(EllesmereUI.L("Power Bar")),
                health = Title(EllesmereUI.L("Health Bar")),
                arcaneSoul = _previewFrames.arcaneSoul and Title(EllesmereUI.L("Arcane Soul")) or nil,
            }
        end

        UpdatePreviewHeader()

        -- Hit overlays for preview click-to-scroll
        wipe(_hitOverlays)
        local overlayLevel = container:GetFrameLevel() + 20
        if pipC then CreateHitOverlay(pipC, "classResource", overlayLevel) end
        CreateHitOverlay(_previewFrames.powerBar, "power", overlayLevel)
        CreateHitOverlay(_previewFrames.healthBar, "health", overlayLevel)
        if _previewFrames.arcaneSoul then CreateHitOverlay(_previewFrames.arcaneSoul, "arcaneSoul", overlayLevel) end
        if pipC and pipC._countText then
            -- Padded frame around the text for easier clicking
            local ctHit = CreateFrame("Frame", nil, pipC)
            ctHit:SetPoint("TOPLEFT", pipC._countText, "TOPLEFT", -2, 2)
            ctHit:SetPoint("BOTTOMRIGHT", pipC._countText, "BOTTOMRIGHT", 2, -2)
            CreateHitOverlay(ctHit, "countText", overlayLevel + 5)
        end

        if _previewHintFS and not _previewHintFS:GetParent() then
            _previewHintFS = nil
        end

        -- Preview area height from the stack UpdatePreviewHeader laid out (0: nothing to show)
        local TOTAL_H = _headerBaseH
        local hintShown = TOTAL_H > 0 and not IsPreviewHintDismissed()
        -- Built with nothing to show, or without a class resource (its row was
        -- built for none, so a later spec or form with one needs a new build).
        _classHdrEmpty = ((TOTAL_H == 0 or not HasClassResource()) and PoolGen(hdr) ~= nil) or nil
        if hintShown then
            if not _previewHintFS then
                -- Thin non-clipping child frame so the cache system stashes/restores it properly on page switch.
                -- Held across builds and pages (module state): out of its header's pool.
                local hintHost = PoolKeep(CreateFrame("Frame", nil, hdr))
                hintHost:SetAllPoints(hdr)
                _previewHintFS = EllesmereUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
            end
            -- The host is kept across builds: one level above the header, as a new one sits.
            local host = _previewHintFS:GetParent()
            host:SetParent(hdr)
            host:SetFrameLevel(hdr:GetFrameLevel() + 1)
            host:Show()
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 20)
            _previewHintFS:Show()
            TOTAL_H = TOTAL_H + 35
        elseif _previewHintFS then
            _previewHintFS:Hide()
        end

        _previewBuilding = false
        return TOTAL_H
    end

    local _refreshTimer
    local function DebouncedRefresh()
        if _refreshTimer then _refreshTimer:Cancel() end
        _refreshTimer = C_Timer.NewTimer(0.05, function()
            _refreshTimer = nil
            Refresh()
        end)
    end

    -- Preview click-to-scroll infrastructure
    local PlaySettingGlow   -- made on first click: Widgets helpers load with the panel
    local _clickMappings = {}   -- populated in BuildBarDisplayPage

    local function NavigateToSetting(key)
        local m = _clickMappings[key]
        if not m or not m.section or not m.target then return end

        EllesmereUI.DismissPreviewHint(_previewHintFS, _headerBaseH, 35, 5)

        local sf = EllesmereUI._scrollFrame
        if not sf then return end
        local _, _, _, _, headerY = m.section:GetPoint(1)
        if not headerY then return end
        local scrollPos = math.max(0, math.abs(headerY) - 40)
        EllesmereUI.SmoothScrollTo(scrollPos)
        local glowTarget = m.target
        if m.slotSide and m.target then
            local region = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
            if region then glowTarget = region end
        end
        PlaySettingGlow = PlaySettingGlow or EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN, thickness = function() return PP.Scale(2) end, noSnap = true })
        -- A row the page dressed again meanwhile (a rebuild) shows another setting now: no glow.
        local gen = PoolGen(glowTarget)
        C_Timer.After(0.15, function()
            if PoolGen(glowTarget) ~= gen then return end
            PlaySettingGlow(glowTarget)
        end)
    end

    CreateHitOverlay = function(element, mappingKey, frameLevelOverride)
        local btn = EllesmereUI.CreatePreviewHitOverlay(element, NavigateToSetting, mappingKey, false, frameLevelOverride)
        _hitOverlays[#_hitOverlays + 1] = btn
        return btn
    end

    -- Non-debounced: smooth animation of scale/offset changes
    local function SmoothRefresh()
        Refresh(); UpdatePreviewHeader()
    end

    local function RefreshClass()
        DebouncedRefresh(); UpdatePreviewHeader()
    end
    local function RefreshHealth()
        DebouncedRefresh(); UpdatePreviewHeader()
    end
    local function RefreshPower()
        DebouncedRefresh(); UpdatePreviewHeader()
    end
    local function RebuildClass()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local function RebuildHealth()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local function RebuildPower()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end

    -- Hash line positions as typed: keeps the numeric tokens (0 and up), comma-joined. Shared by
    -- the bar-wide hash cog and the Threshold & Hash Lines editor's entry field. exact: each token
    -- is read trimmed, as the bar parses it ("25 50" is no position), instead of with its spaces
    -- dropped ("50 000" = 50000).
    local function SanitizePositions(str, exact)
        if not str or str == "" then return "" end
        local out = {}
        for token in tostring(str):gmatch("[^,]+") do
            local n = tonumber(exact and token:match("^%s*(.-)%s*$") or (token:gsub("%s", "")))
            if n and n >= 0 then out[#out + 1] = tostring(n) end
        end
        return table.concat(out, ", ")
    end

    -- Cog + popup for simple per-bar hash lines (Health/Power). cfg = { parentRgn, getBarData, refreshFn, popupTitle, anchorTo }; returns cogBtn.
    local function BuildHashCog(cfg)
        local getBarData = cfg.getBarData
        local refreshFn  = cfg.refreshFn or function() end

        local function HashOff()
            local c = getBarData()
            return not (c and c.hashEnabled)
        end

        local DIS_TIP = EllesmereUI.L("Enable hash lines first")
        local rows = {
            { type = "toggle", label = EllesmereUI.L("Show Hash Lines"),
              tooltip = EllesmereUI.L("Draw tick lines across the bar at positions you choose."),
              get = function() local c = getBarData(); return c and c.hashEnabled or false end,
              set = function(v) local c = getBarData(); if not c then return end
                  c.hashEnabled = v and true or false; refreshFn() end },
            { type = "input", label = EllesmereUI.L("Positions"), inputWidth = 130,
              commitOnBlur = true,
              disabled = HashOff,
              disabledTooltip = DIS_TIP,
              get = function() local c = getBarData(); return c and c.hashValues or "" end,
              set = function(v) local c = getBarData(); if not c then return end
                  c.hashValues = SanitizePositions(v); refreshFn() end },
            { type = "segmented", label = EllesmereUI.L("Mode"),
              disabled = HashOff,
              disabledTooltip = DIS_TIP,
              keys = { "percent", "value" }, labels = { percent = "%", value = "Value" },
              get = function() local c = getBarData(); return (c and c.hashMode) or "percent" end,
              set = function(k) local c = getBarData(); if not c then return end
                  c.hashMode = k; refreshFn() end },
            { type = "slider", label = EllesmereUI.L("Thickness"), min = 1, max = 5, step = 1,
              disabled = HashOff,
              disabledTooltip = DIS_TIP,
              get = function() local c = getBarData(); return c and c.hashWidth or 1 end,
              set = function(v) local c = getBarData(); if not c then return end
                  c.hashWidth = v; refreshFn() end },
            { type = "colorpicker", label = EllesmereUI.L("Color"), hasAlpha = true,
              disabled = HashOff,
              disabledTooltip = DIS_TIP,
              get = function()
                  local c = getBarData()
                  if not c then return 1, 1, 1, 0.7 end
                  return c.hashColorR or 1, c.hashColorG or 1, c.hashColorB or 1, c.hashColorA or 0.7
              end,
              set = function(r, g, b, a)
                  local c = getBarData(); if not c then return end
                  c.hashColorR, c.hashColorG, c.hashColorB, c.hashColorA = r, g, b, a
                  refreshFn()
              end },
        }

        return EllesmereUI.BuildInlineCog(cfg.parentRgn, {
            anchorTo = cfg.anchorTo, tip = EllesmereUI.L("Hash Lines"),
            title = cfg.popupTitle or EllesmereUI.L("Hash Lines"), bgAlpha = 1,
            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
            rows = rows,
        })
    end

    -- Druid-only per-form popup button. `field` picks the map the toggles write: "textDisabledForms" (text rows) or "barDisabledForms" (whole-bar rows).
    local function AddFormDisableBtn(rgn, leftOf, cfgFn, refreshFn, field, title, tooltip)
        local _, classFile = UnitClass("player")
        if classFile ~= "DRUID" then return end
        field = field or "textDisabledForms"
        title = title or "Enable/Disable per Form"
        tooltip = tooltip or EllesmereUI.L(title)
        local FORMS = { { key = "mana", label = "Caster" },
                        { key = "rage", label = "Bear" },
                        { key = "energy", label = "Cat" },
                        { key = "moonkin", label = "Moonkin" } }
        local rows = {}
        for _, f in ipairs(FORMS) do
            local key = f.key
            rows[#rows + 1] = { type = "toggle", label = f.label,
                get = function()
                    local c = cfgFn()
                    return not (c and c[field] and c[field][key])
                end,
                set = function(v)
                    local c = cfgFn(); if not c then return end
                    if v then
                        if c[field] then c[field][key] = nil end
                    else
                        c[field] = c[field] or {}
                        c[field][key] = true
                    end
                    refreshFn()
                end }
        end
        local btn = EllesmereUI.BuildInlineCog(rgn, {
            anchorTo = leftOf, tip = tooltip,
            icon = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\glyph.tga",
            title = title, bgAlpha = 1,
            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
            rows = rows,
        })
        if not btn then return end
        -- Crop the DRUID cell out of the class glyph sheet.
        btn._icon:SetDesaturated(true)
        btn._icon:SetTexCoord(0.375, 0.5, 0, 0.125)
        return btn
    end
    -- The L() literals keep both popup titles in the static locale key list: .tools/extract-locale-keys.sh only sees literal string arguments.
    local function AddFormTextBtn(rgn, leftOf, cfgFn, refreshFn)
        return AddFormDisableBtn(rgn, leftOf, cfgFn, refreshFn, "textDisabledForms",
            "Enable/Disable per Form", EllesmereUI.L("Enable/Disable per Form"))
    end
    local function AddFormBarBtn(rgn, cfgFn, refreshFn)
        return AddFormDisableBtn(rgn, nil, cfgFn, refreshFn, "barDisabledForms",
            "Enable/Disable Bar per Form", EllesmereUI.L("Enable/Disable Bar per Form"))
    end

    -- Multi-band threshold editor (opt-in): popup opened per threshold-spec entry from
    -- its "Bands" button, editing entry.bands -- an ordered list of { to=<boundary>, r,g,b,a }
    -- color stops. `to` is a resource count for pip resources, or a percent/value for bars.
    -- ShowBandEditor() rebinds it to the calling bar each time it opens.
    local _bandCloseIcon = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
    local bandPopup
    local _bandRows = {}
    local _bandEntryIdx
    local _bandGetBarData, _bandRefreshFn, _bandCountBased
    local _bandLockPercent, _bandPercentMax   -- Brewmaster stagger: force percent, cap 500
    local _bandDefR, _bandDefG, _bandDefB, _bandDefA = 1, 0.2, 0.2, 1
    local _bandModeRow, _bandModeSeg, _bandModeSegRefresh, _bandModeHint, _bandAddBtn, _bandTitleFS
    local _bandReverseRow, _bandReverseSeg, _bandReverseSegRefresh
    local BAND_POPUP_W = 300
    local BAND_ROW_H = 26
    local BAND_PAD = 14
    local BAND_GAP = 10
    local RefreshBandEditor  -- forward decl

    -- Shared explainer tooltip: Multi toggle + Bands button
    local BAND_HELP_TIP =
        "Color the bar by ranges instead of a single threshold.\n"
        .. "Up to (<=) / From (>=)\n"
		.. "Any remaning values outside the bands will use fill color.\n"
        .. "|cff888888Bars can use % or actual value; pip resources use counts.|r"

    local BAND_REPLACES_TIP =
        "Single threshold is off while Multi-band is on.\n"

    -- Shown on the greyed percent/value control for Brewmaster stagger
    local STAGGER_PCT_TIP =
        "Stagger value can only be percent based"

    local function CurrentBandEntry()
        if not _bandEntryIdx or not _bandGetBarData then return nil end
        local bd = _bandGetBarData(); if not bd or not bd.thresholdSpecs then return nil end
        return bd.thresholdSpecs[_bandEntryIdx]
    end

    local function SortBands(bands)
        table.sort(bands, function(a, b) return (a.to or 0) < (b.to or 0) end)
    end

    local function BuildBandPopup()
        bandPopup = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
        bandPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        bandPopup:SetFrameLevel(260)
        bandPopup:SetClampedToScreen(true)
        bandPopup:EnableMouse(true)
        bandPopup:SetScale(EllesmereUI.GetPopupScale())
        bandPopup:Hide()
        PP.Size(bandPopup, BAND_POPUP_W, 200)

        local bg = bandPopup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.97)
        PP.CreateBorder(bandPopup, 1, 1, 1, 0.18, 1, "BORDER", 7)

        local clickCatcher = CreateFrame("Button", nil, bandPopup)
        clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        clickCatcher:SetFrameLevel(bandPopup:GetFrameLevel() - 1)
        clickCatcher:SetAllPoints((EllesmereUI:GetMainFrame()) or UIParent)
        clickCatcher:SetScript("OnClick", function() bandPopup:Hide() end)
        clickCatcher:Hide()
        -- Close on entering combat
        bandPopup:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_DISABLED" then self:Hide() end
        end)
        bandPopup:SetScript("OnShow", function(self)
            clickCatcher:Show()
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", function(p)
                if IsMouseButtonDown("LeftButton") then
                    local mf = EllesmereUI._mainFrame
                    local dm = EllesmereUI._openDropdownMenu
                        if not p:IsMouseOver() and not (mf and mf:IsMouseOver()) and not (dm and dm:IsShown() and dm:IsMouseOver()) then p:Hide() end
                end
            end)
        end)
        bandPopup:SetScript("OnHide", function(self)
            clickCatcher:Hide()
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", nil)
        end)
        EllesmereUI.TrackOverlay(bandPopup)
        EllesmereUI.PadHint(bandPopup, "nodepass")
        EllesmereUI.PadHint(clickCatcher, "nodepass")
        EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = bandPopup }
        EllesmereUI:RegisterOnHide(function() bandPopup:Hide() end)
        EllesmereUI:RegisterOnCollapse(function(on) if on then bandPopup:Hide() end end)

        _bandTitleFS = EllesmereUI.MakeFont(bandPopup, 13, nil, 1, 1, 1)
        _bandTitleFS:SetAlpha(0.6)
        _bandTitleFS:SetPoint("TOP", bandPopup, "TOP", 0, -BAND_PAD)
        _bandTitleFS:SetText(EllesmereUI.L("Color Bands"))

        -- Labeled row (label left, control right), matching the detail-pane rows
        local function HeaderRow(labelText)
            local rf = CreateFrame("Frame", nil, bandPopup)
            rf:SetFrameLevel(bandPopup:GetFrameLevel() + 3)
            PP.Height(rf, BAND_ROW_H)
            local lbl = EllesmereUI.MakeFont(rf, 12, nil, 1, 1, 1)
            lbl:SetAlpha(0.6)
            lbl:SetPoint("LEFT", rf, "LEFT", 0, 0)
            lbl:SetText(EllesmereUI.L(labelText))
            rf._lbl = lbl
            return rf
        end

        local _  -- the switches' unused second return (never the global)
        -- Value units segmented switch (Amount / Percent), bar-type only; count-based shows a hint instead.
        _bandModeRow = HeaderRow("Values as")
        _bandModeSeg, _, _bandModeSegRefresh = EllesmereUI.BuildSegmentedControl({
            parent    = _bandModeRow,
            keys      = { "amount", "percent" },
            labels    = { amount = "Amount", percent = "Percent" },
            autoWidth = true,
            square    = true,
            height    = 22,
            getChecked = function(key)
                local ent = CurrentBandEntry()
                local isPercent = _bandLockPercent or not (ent and ent.bandMode == "value")
                if key == "percent" then return isPercent else return not isPercent end
            end,
            isDisabled = function() return _bandLockPercent and true or false end,
            onToggle = function(key)
                if _bandLockPercent then return end
                local ent = CurrentBandEntry(); if not ent then return end
                ent.bandMode = (key == "percent") and "percent" or "value"
                if _bandRefreshFn then _bandRefreshFn() end
                RefreshBandEditor()
            end,
        })
        _bandModeSeg:SetPoint("RIGHT", _bandModeRow, "RIGHT", 0, 0)
        -- Disabled-state tooltip: Brewmaster stagger is percent-only
        local _bandModeDis = CreateFrame("Frame", nil, _bandModeRow)
        _bandModeDis:SetAllPoints(_bandModeSeg)
        _bandModeDis:SetFrameLevel(_bandModeSeg:GetFrameLevel() + 5)
        _bandModeDis:EnableMouse(true)
        _bandModeDis:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L(STAGGER_PCT_TIP)) end)
        _bandModeDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        _bandModeDis:Hide()
        _bandModeRow._staggerDis = _bandModeDis
        _bandModeHint = EllesmereUI.MakeFont(bandPopup, 10, nil, 1, 1, 1)
        _bandModeHint:SetAlpha(0.4)

        -- Direction segmented switch (always one of two values)
        _bandReverseRow = HeaderRow("Direction")
        _bandReverseSeg, _, _bandReverseSegRefresh = EllesmereUI.BuildSegmentedControl({
            parent    = _bandReverseRow,
            keys      = { "upto", "from" },
            labels    = { upto = "Up to", from = "From" },
            autoWidth = true,
            square    = true,
            height    = 22,
            getChecked = function(key)
                local ent = CurrentBandEntry()
                local reverse = ent and ent.bandReverse and true or false
                if key == "from" then return reverse else return not reverse end
            end,
            onToggle = function(key)
                local ent = CurrentBandEntry(); if not ent then return end
                ent.bandReverse = (key == "from")
                if _bandRefreshFn then _bandRefreshFn() end
                RefreshBandEditor()
            end,
        })
        _bandReverseSeg:SetPoint("RIGHT", _bandReverseRow, "RIGHT", 0, 0)

        -- Add Band button
        _bandAddBtn = CreateFrame("Button", nil, bandPopup)
        PP.Size(_bandAddBtn, BAND_POPUP_W - BAND_PAD * 2, 26)
        _bandAddBtn:SetFrameLevel(bandPopup:GetFrameLevel() + 3)
        local abg = EllesmereUI.SolidTex(_bandAddBtn, "BACKGROUND", 0.069, 0.058, 0.047, 0.92)
        abg:SetAllPoints()
        _bandAddBtn._border = EllesmereUI.MakeBorder(_bandAddBtn, 1, 1, 1, 0.4, PP)
        local albl = EllesmereUI.MakeFont(_bandAddBtn, 12, nil, 1, 1, 1)
        albl:SetAlpha(0.5)
        albl:SetPoint("CENTER")
        albl:SetText(EllesmereUI.L("+ Add Band"))
        _bandAddBtn:SetScript("OnEnter", function()
            albl:SetAlpha(0.7)
            if _bandAddBtn._border and _bandAddBtn._border.SetColor then _bandAddBtn._border:SetColor(1, 1, 1, 0.6) end
        end)
        _bandAddBtn:SetScript("OnLeave", function()
            albl:SetAlpha(0.5)
            if _bandAddBtn._border and _bandAddBtn._border.SetColor then _bandAddBtn._border:SetColor(1, 1, 1, 0.4) end
        end)
        _bandAddBtn:SetScript("OnClick", function()
            local ent = CurrentBandEntry(); if not ent then return end
            if not ent.bands then ent.bands = {} end
            local last = ent.bands[#ent.bands]
            local nextTo = last and ((last.to or 0) + 1) or 1
            ent.bands[#ent.bands + 1] = { to = nextTo, r = _bandDefR, g = _bandDefG, b = _bandDefB, a = _bandDefA }
            SortBands(ent.bands)
            if _bandRefreshFn then _bandRefreshFn() end
            RefreshBandEditor()
        end)
    end

    -- Lazily create the widgets for band row k; returns the row table
    local function EnsureBandRow(k)
        local row = _bandRows[k]
        if row then return row end
        row = {}
        local rf = CreateFrame("Frame", nil, bandPopup)
        rf:SetSize(BAND_POPUP_W - BAND_PAD * 2, BAND_ROW_H)
        rf:SetFrameLevel(bandPopup:GetFrameLevel() + 2)
        row.frame = rf

        local lbl = EllesmereUI.MakeFont(rf, 12, nil, 1, 1, 1)
        lbl:SetAlpha(0.6)
        lbl:SetPoint("LEFT", rf, "LEFT", 2, 0)
        lbl:SetText(EllesmereUI.L("Up to"))  -- band colors values up to `to`
        row.lbl = lbl

        local input = CreateFrame("EditBox", nil, rf)
        input:SetSize(54, 22)
        input:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
        input:SetFrameLevel(rf:GetFrameLevel() + 2)
        input:SetAutoFocus(false)
        input:SetFontObject(GameFontHighlightSmall)
        local inFont = EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
        input:SetFont(inFont, 12, "")
        input:SetTextColor(1, 1, 1, 0.75)
        input:SetJustifyH("CENTER")
        input:SetNumeric(true)
        local inBg = input:CreateTexture(nil, "BACKGROUND")
        inBg:SetAllPoints()
        inBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
        EllesmereUI.MakeBorder(input, 1, 1, 1, 0.08, PP)
        row.input = input

        -- Commit on focus loss. Enter clears focus -> triggers this; Escape sets _cancelCommit so leaving the field discards the typed text.
        local function CommitInput(self)
            if self._cancelCommit then self._cancelCommit = nil; return end
            local ent = CurrentBandEntry()
            local band = ent and ent.bands and ent.bands[row._idx]
            if not band then return end
            local val = tonumber(self:GetText())
            if val then
                local pctMax = _bandPercentMax or 100
                local hi = _bandCountBased and 100 or ((not _bandLockPercent and ent.bandMode == "value") and 1000000 or pctMax)
                val = math.max(1, math.min(hi, math.floor(val + 0.5)))
                band.to = val
                SortBands(ent.bands)
                if _bandRefreshFn then _bandRefreshFn() end
            end
            RefreshBandEditor()
        end
        input:SetScript("OnEditFocusLost", CommitInput)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self._cancelCommit = true; self:ClearFocus(); RefreshBandEditor() end)

        local swatch, swatchSnap = EllesmereUI.BuildColorSwatch(rf, rf:GetFrameLevel() + 3,
            function()
                local ent = CurrentBandEntry()
                local band = ent and ent.bands and ent.bands[row._idx]
                if not band then return _bandDefR, _bandDefG, _bandDefB, _bandDefA end
                return band.r or _bandDefR, band.g or _bandDefG, band.b or _bandDefB, band.a or _bandDefA
            end,
            function(r, g, b, a)
                local ent = CurrentBandEntry()
                local band = ent and ent.bands and ent.bands[row._idx]
                if band then
                    band.r, band.g, band.b, band.a = r, g, b, a
                    if _bandRefreshFn then _bandRefreshFn() end
                end
            end, true, 19)
        swatch:SetPoint("LEFT", input, "RIGHT", 10, 0)
        row.swatch = swatch
        row.swatchSnap = swatchSnap

        local delBtn = CreateFrame("Button", nil, rf)
        delBtn:SetSize(14, 14)
        delBtn:SetPoint("RIGHT", rf, "RIGHT", -2, 0)
        delBtn:SetFrameLevel(rf:GetFrameLevel() + 3)
        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
        delIcon:SetAllPoints()
        delIcon:SetTexture(_bandCloseIcon)
        delIcon:SetAlpha(0.4)
        delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
        delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
        delBtn:SetScript("OnClick", function()
            local ent = CurrentBandEntry()
            if ent and ent.bands and ent.bands[row._idx] then
                table.remove(ent.bands, row._idx)
                if _bandRefreshFn then _bandRefreshFn() end
                RefreshBandEditor()
            end
        end)
        row.delBtn = delBtn

        _bandRows[k] = row
        return row
    end

    RefreshBandEditor = function()
        if not bandPopup then return end
        local ent = CurrentBandEntry()
        if not ent then bandPopup:Hide(); return end
        if not ent.bands then ent.bands = {} end

        local curY = -(BAND_PAD + 24)  -- below the title

        local function placeRow(rf)
            rf:ClearAllPoints()
            PP.Point(rf, "TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY)
            PP.Point(rf, "TOPRIGHT", bandPopup, "TOPRIGHT", -BAND_PAD, curY)
            rf:Show()
            curY = curY - BAND_ROW_H - BAND_GAP
        end

        -- Mode row (bar-type) or a hint (count-based: boundaries are counts)
        if _bandCountBased then
            _bandModeRow:Hide()
            _bandModeHint:ClearAllPoints()
            _bandModeHint:SetPoint("TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY - 4)
            _bandModeHint:SetText(EllesmereUI.L("Boundaries are resource counts"))
            _bandModeHint:Show()
            curY = curY - 18 - BAND_GAP
        else
            _bandModeHint:Hide()
            if _bandModeSegRefresh then _bandModeSegRefresh() end
            -- Brewmaster stagger: percent locked, so grey the control + tooltip
            if _bandModeRow._staggerDis then _bandModeRow._staggerDis:SetShown(_bandLockPercent and true or false) end
            if _bandModeRow._lbl then _bandModeRow._lbl:SetAlpha(_bandLockPercent and 0.3 or 0.6) end
            placeRow(_bandModeRow)
        end

        -- Row label follows direction: "From" (>=) when reverse, else "Up to"
        local reverse = ent.bandReverse and true or false

        if _bandReverseSegRefresh then _bandReverseSegRefresh() end
        placeRow(_bandReverseRow)
        local rowLabel = reverse and EllesmereUI.L("From") or EllesmereUI.L("Up to")
        local n = #ent.bands
        for k = 1, n do
            local row = EnsureBandRow(k)
            row._idx = k
            row.lbl:SetText(rowLabel)
            row.frame:ClearAllPoints()
            PP.Point(row.frame, "TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY)
            row.input:SetText(tostring(ent.bands[k].to or 1))
            if row.swatchSnap then row.swatchSnap() end
            row.frame:Show()
            curY = curY - BAND_ROW_H - 4
        end
        for k = n + 1, #_bandRows do
            if _bandRows[k] then _bandRows[k].frame:Hide() end
        end

        curY = curY - 4
        _bandAddBtn:ClearAllPoints()
        PP.Point(_bandAddBtn, "TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY)
        curY = curY - 26

        local totalH = math.abs(curY) + BAND_PAD
        PP.Size(bandPopup, BAND_POPUP_W, totalH)
    end

    -- params = { getBarData, refreshFn, entryIdx, anchor, countBased, defR/G/B/A }
    local function ShowBandEditor(params)
        if not bandPopup then BuildBandPopup() end
        _bandGetBarData = params.getBarData
        _bandRefreshFn  = params.refreshFn
        _bandEntryIdx   = params.entryIdx
        _bandCountBased = params.countBased and true or false
        _bandLockPercent = params.lockPercent and true or false
        _bandPercentMax = params.percentMax
        _bandDefR = params.defR or 1
        _bandDefG = params.defG or 0.2
        _bandDefB = params.defB or 0.2
        _bandDefA = params.defA or 1
        local ent = CurrentBandEntry()
        if ent then
            if _bandLockPercent then ent.bandMode = "percent" end  -- stagger: percent-only
            if not ent.bands then ent.bands = {} end
            -- First open seeds a starter band from the single threshold
            if #ent.bands == 0 then
                local seedTo = _bandCountBased and (ent.thresholdCount or 3) or (ent.thresholdPct or 30)
                ent.bands[1] = {
                    to = seedTo,
                    r = ent.thresholdR or _bandDefR, g = ent.thresholdG or _bandDefG,
                    b = ent.thresholdB or _bandDefB, a = ent.thresholdA or _bandDefA,
                }
            end
        end
        RefreshBandEditor()
        bandPopup:ClearAllPoints()
        bandPopup:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
        bandPopup:Show()
    end

    -- Colour list editor: a per-threshold-entry list of { spellID, r,g,b,a } stored in
    -- entry[o.field] (per-spec via the entry's specIDs). List order = priority: the first
    -- matching spell wins, and rows drag to reorder like BuildCogPopup's 'reorder' row.
    -- Buff Colors and Spender Colors each build one. o = { field, title, addLabel }
    -- (title/addLabel already localized). Returns Show(params), params =
    -- { getBarData, refreshFn, entryIdx, anchor }; the popup is built on first Show.
    local function MakeColorListEditor(o)
        local field = o.field
        local POPUP_W, ROW_H = 320, 26
        local STEP = ROW_H + 4
        local popup, addBtn, insLine
        local rows = {}
        local entryIdx, getBarData, refreshFn
        local drag = { row = nil, startY = nil, active = false }
        local Refresh, DragTick  -- forward decls

        local function CurrentEntry()
            if not entryIdx or not getBarData then return nil end
            local bd = getBarData(); if not bd or not bd.thresholdSpecs then return nil end
            return bd.thresholdSpecs[entryIdx]
        end

        -- The list item a row edits, or nil
        local function RowItem(row)
            local ent = CurrentEntry()
            local list = ent and ent[field]
            return list and list[row._idx]
        end

        local function OnPopupUpdate(pp)
            if drag.row then DragTick(); return end  -- dragging: move/reorder, never dismiss
            if IsMouseButtonDown("LeftButton") then
                local mf = EllesmereUI._mainFrame
                if not pp:IsMouseOver() and not (mf and mf:IsMouseOver()) then pp:Hide() end
            end
        end

        local function Build()
            popup = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(260)
            popup:SetClampedToScreen(true)
            popup:EnableMouse(true)
            popup:SetScale(EllesmereUI.GetPopupScale())
            popup:Hide()
            PP.Size(popup, POPUP_W, 200)
            local bg = popup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(0.077, 0.068, 0.058, 0.97)
            PP.CreateBorder(popup, 1, 1, 1, 0.18, 1, "BORDER", 7)

            -- Insertion line shown while dragging a row; theme accent, matches the raid "Sort By" reorder line
            insLine = popup:CreateTexture(nil, "OVERLAY", nil, 7)
            insLine:SetHeight(2)
            local eg = EllesmereUI.ELLESMERE_GREEN
            insLine:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
            insLine:Hide()

            local clickCatcher = CreateFrame("Button", nil, popup)
            clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            clickCatcher:SetFrameLevel(popup:GetFrameLevel() - 1)
            clickCatcher:SetAllPoints((EllesmereUI:GetMainFrame()) or UIParent)
            clickCatcher:SetScript("OnClick", function() if drag.active then return end popup:Hide() end)
            clickCatcher:Hide()
            -- Close on entering combat (the event is registered only while shown)
            popup:SetScript("OnEvent", function(self) self:Hide() end)
            popup:SetScript("OnShow", function(self)
                clickCatcher:Show()
                self:RegisterEvent("PLAYER_REGEN_DISABLED")
                self:SetScript("OnUpdate", OnPopupUpdate)
            end)
            popup:SetScript("OnHide", function(self)
                clickCatcher:Hide()
                self:UnregisterEvent("PLAYER_REGEN_DISABLED")
                self:SetScript("OnUpdate", nil)
                -- A combat or panel close can land mid-drag: drop it (Show re-lays the rows)
                drag.row = nil; drag.active = false
                insLine:Hide()
            end)
            EllesmereUI.TrackOverlay(popup)
            EllesmereUI.PadHint(popup, "nodepass")
            EllesmereUI.PadHint(clickCatcher, "nodepass")
            EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = popup }
            EllesmereUI:RegisterOnHide(function() popup:Hide() end)
            EllesmereUI:RegisterOnCollapse(function(on) if on then popup:Hide() end end)

            local titleFS = EllesmereUI.MakeFont(popup, 13, nil, 1, 1, 1)
            titleFS:SetAlpha(0.7)
            titleFS:SetPoint("TOP", popup, "TOP", 0, -BAND_PAD)
            titleFS:SetText(o.title)
            local hintFS = EllesmereUI.MakeFont(popup, 10, nil, 1, 1, 1, 0.25)
            hintFS:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -BAND_PAD - 4)
            hintFS:SetText(EllesmereUI.L("Drag to Reorder"))

            addBtn = CreateFrame("Button", nil, popup)
            PP.Size(addBtn, POPUP_W - BAND_PAD * 2, 26)
            addBtn:SetFrameLevel(popup:GetFrameLevel() + 3)
            local abg = EllesmereUI.SolidTex(addBtn, "BACKGROUND", 0.069, 0.058, 0.047, 0.92)
            abg:SetAllPoints()
            addBtn._border = EllesmereUI.MakeBorder(addBtn, 1, 1, 1, 0.4, PP)
            local albl = EllesmereUI.MakeFont(addBtn, 12, nil, 1, 1, 1)
            albl:SetAlpha(0.5); albl:SetPoint("CENTER"); albl:SetText(o.addLabel)
            addBtn:SetScript("OnEnter", function() albl:SetAlpha(0.7); addBtn._border:SetColor(1, 1, 1, 0.6) end)
            addBtn:SetScript("OnLeave", function() albl:SetAlpha(0.5); addBtn._border:SetColor(1, 1, 1, 0.4) end)
            addBtn:SetScript("OnClick", function()
                local ent = CurrentEntry(); if not ent then return end
                if not ent[field] then ent[field] = {} end
                ent[field][#ent[field] + 1] = { spellID = nil, r = 0.2, g = 0.6, b = 1.0, a = 1 }
                if refreshFn then refreshFn() end
                Refresh()
            end)
        end

        local function EnsureRow(k)
            local row = rows[k]
            if row then return row end
            row = {}
            local rf = CreateFrame("Frame", nil, popup)
            rf:SetSize(POPUP_W - BAND_PAD * 2, ROW_H)
            rf:SetFrameLevel(popup:GetFrameLevel() + 2)
            row.frame = rf

            local input = CreateFrame("EditBox", nil, rf)
            input:SetSize(58, 22)
            input:SetPoint("LEFT", rf, "LEFT", 16, 0)
            input:SetFrameLevel(rf:GetFrameLevel() + 2)
            input:SetAutoFocus(false)
            input:SetFont(EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF", 12, "")
            input:SetTextColor(1, 1, 1, 0.75)
            input:SetJustifyH("CENTER")
            input:SetNumeric(true)
            input:SetMaxLetters(7)
            local inBg = input:CreateTexture(nil, "BACKGROUND"); inBg:SetAllPoints()
            inBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
            EllesmereUI.MakeBorder(input, 1, 1, 1, 0.08, PP)
            row.input = input

            -- Drag grip: list order = priority, so rows are draggable
            local grip = CreateFrame("Button", nil, rf)
            grip:SetSize(14, ROW_H)
            grip:SetPoint("LEFT", rf, "LEFT", 0, 0)
            grip:SetFrameLevel(rf:GetFrameLevel() + 4)
            local gripFS = EllesmereUI.MakeFont(grip, 13, nil, 1, 1, 1, 0.25)
            gripFS:SetPoint("CENTER")
            gripFS:SetText("=")
            grip:SetScript("OnEnter", function() gripFS:SetTextColor(1, 1, 1, 0.6) end)
            grip:SetScript("OnLeave", function() gripFS:SetTextColor(1, 1, 1, 0.25) end)
            grip:SetScript("OnMouseDown", function(self, b)
                if b ~= "LeftButton" then return end
                local _, cy = GetCursorPosition()
                drag.row = row; drag.startY = cy; drag.active = false
            end)
            row.grip = grip

            local nameFS = EllesmereUI.MakeFont(rf, 11, nil, 1, 1, 1)
            nameFS:SetAlpha(0.6)
            nameFS:SetPoint("LEFT", input, "RIGHT", 8, 0)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWidth(150)
            nameFS:SetWordWrap(false)
            row.nameFS = nameFS

            local function RefreshName()
                local e = RowItem(row)
                local id = e and e.spellID
                if id then
                    nameFS:SetText(C_Spell.GetSpellName(id) or (EllesmereUI.COLOR_CODES.BAD .. EllesmereUI.L("Unknown ID") .. "|r"))
                else
                    nameFS:SetText(EllesmereUI.COLOR_CODES.DIM .. EllesmereUI.L("(enter Spell ID)") .. "|r")
                end
            end
            row.RefreshName = RefreshName

            local function CommitInput(self)
                if self._cancelCommit then self._cancelCommit = nil; return end
                local e = RowItem(row)
                if not e then return end
                local val = tonumber(self:GetText())
                e.spellID = (val and val > 0) and val or nil
                RefreshName()
                if refreshFn then refreshFn() end
            end
            input:SetScript("OnEditFocusLost", CommitInput)
            input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            input:SetScript("OnEscapePressed", function(self) self._cancelCommit = true; self:ClearFocus(); Refresh() end)

            local swatch, swatchSnap = EllesmereUI.BuildColorSwatch(rf, rf:GetFrameLevel() + 3,
                function()
                    local e = RowItem(row)
                    if not e then return 0.2, 0.6, 1.0, 1 end
                    return e.r or 0.2, e.g or 0.6, e.b or 1.0, e.a or 1
                end,
                function(r, g, b, a)
                    local e = RowItem(row)
                    if e then e.r, e.g, e.b, e.a = r, g, b, a; if refreshFn then refreshFn() end end
                end, true, 19)
            swatch:SetPoint("RIGHT", rf, "RIGHT", -24, 0)
            row.swatch = swatch
            row.swatchSnap = swatchSnap

            local delBtn = CreateFrame("Button", nil, rf)
            delBtn:SetSize(14, 14)
            delBtn:SetPoint("RIGHT", rf, "RIGHT", -2, 0)
            delBtn:SetFrameLevel(rf:GetFrameLevel() + 3)
            local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
            delIcon:SetAllPoints(); delIcon:SetTexture(_bandCloseIcon); delIcon:SetAlpha(0.4)
            delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
            delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
            delBtn:SetScript("OnClick", function()
                local ent = CurrentEntry()
                if ent and ent[field] and ent[field][row._idx] then
                    table.remove(ent[field], row._idx)
                    if refreshFn then refreshFn() end
                    Refresh()
                end
            end)
            row.delBtn = delBtn

            rows[k] = row
            return row
        end

        Refresh = function()
            if not popup then return end
            local ent = CurrentEntry()
            if not ent then popup:Hide(); return end
            if not ent[field] then ent[field] = {} end
            local list = ent[field]
            local curY = -(BAND_PAD + 24)
            local n = #list
            for k = 1, n do
                local row = EnsureRow(k)
                row._idx = k
                row.frame:ClearAllPoints()
                PP.Point(row.frame, "TOPLEFT", popup, "TOPLEFT", BAND_PAD, curY)
                row._baseY = curY  -- for the drag-reorder hit test
                row.frame:SetFrameLevel(popup:GetFrameLevel() + 2)  -- reset after a drag raised it
                row.frame:SetAlpha(1)
                row.input:SetText(list[k].spellID and tostring(list[k].spellID) or "")
                row.RefreshName()
                row.swatchSnap()
                row.frame:Show()
                curY = curY - ROW_H - 4
            end
            for k = n + 1, #rows do if rows[k] then rows[k].frame:Hide() end end
            curY = curY - 4
            addBtn:ClearAllPoints()
            PP.Point(addBtn, "TOPLEFT", popup, "TOPLEFT", BAND_PAD, curY)
            curY = curY - 26
            PP.Size(popup, POPUP_W, math.abs(curY) + BAND_PAD)
        end

        -- Runs each frame from the popup's OnUpdate while a grip is held: separates click from
        -- drag, moves the row under the cursor with an insertion line, and on release reorders
        -- the list (order = priority) and re-renders.
        DragTick = function()
            local d = drag
            local row = d.row
            if not row then return end
            local down = IsMouseButtonDown("LeftButton")
            local _, cy = GetCursorPosition()
            if not d.active then
                if not down then d.row = nil; return end          -- released before threshold = a click
                if math.abs(cy - (d.startY or cy)) < 3 then return end
                d.active = true
                row.frame:SetFrameLevel(popup:GetFrameLevel() + 20)
                row.frame:SetAlpha(0.85)
            end
            local ent = CurrentEntry()
            local list = ent and ent[field]
            local n = list and #list or 0
            local sc = popup:GetEffectiveScale()
            local cY = cy / sc
            local mT = popup:GetTop() or 0
            -- Insertion index among the STATIC (non-dragged) rows
            local iI = n
            for ri = 1, n do
                local r2 = rows[ri]
                if r2 ~= row and r2._baseY then
                    local rm = mT + r2._baseY - ROW_H / 2
                    if cY > rm then iI = ri; break end
                    iI = ri + 1
                end
            end
            iI = math.max(1, math.min(iI, n + 1))
            if down then
                local firstY = -(BAND_PAD + 24)
                local lnY = (iI <= 1) and (firstY + 2) or (firstY - (iI - 1) * STEP + 2)
                insLine:ClearAllPoints()
                insLine:SetPoint("TOPLEFT", popup, "TOPLEFT", BAND_PAD, lnY)
                insLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -BAND_PAD, lnY)
                insLine:Show()
                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOPLEFT", popup, "TOPLEFT", BAND_PAD, cY - mT)
            else
                -- Dropped: reorder the list + re-render
                local from = row._idx
                if from and from < iI then iI = iI - 1 end
                local to = math.max(1, math.min(iI, n))
                insLine:Hide()
                d.row = nil; d.active = false
                if list and from and from ~= to then
                    local mv = table.remove(list, from)
                    table.insert(list, to, mv)
                    if refreshFn then refreshFn() end
                end
                Refresh()
            end
        end

        return function(params)
            if not popup then Build() end
            getBarData = params.getBarData
            refreshFn  = params.refreshFn
            entryIdx   = params.entryIdx
            local ent = CurrentEntry()
            if ent and not ent[field] then ent[field] = {} end
            Refresh()
            popup:ClearAllPoints()
            popup:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
            popup:Show()
        end
    end

    local ShowBuffEditor = MakeColorListEditor({
        field = "buffColors", title = EllesmereUI.L("Buff Colors"), addLabel = EllesmereUI.L("+ Add Buff"),
    })
    local BUFF_HELP_TIP =
        "Recolor the bar while you have a buff. The first active buff in the list wins, so order = priority. Overrides threshold coloring while active.\n"
        .. "You must be tracking the buff in Blizzard CDM, added to EUI CDM, and this only works with CDM trackable buffs."

    local ShowSpenderEditor = MakeColorListEditor({
        field = "spenderColors", title = EllesmereUI.L("Spender Colors"), addLabel = EllesmereUI.L("+ Add Spender"),
    })
    local SPENDER_HELP_TIP =
        "Recolor the bar while a spell is castable (usable and off cooldown). The first castable spell in the list wins, so order = priority. Overrides threshold coloring while active; an active tracked buff from Buff Colors takes priority.\n"
        .. "For an ability that turns into another spell while active, enter the original spell's ID: its current form is checked."

    -- Skins a small text button of the threshold settings (Bands, Buffs, Spenders):
    -- a dark fill that lightens on hover, tip on hover. label comes localized.
    local function SkinCardButton(btn, label, tip)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
        btn._border = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.08, PP)
        local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
        lbl:SetAlpha(0.8)
        lbl:SetPoint("CENTER")
        lbl:SetText(label)
        btn:SetScript("OnEnter", function(self)
            bg:SetColorTexture(0.16, 0.16, 0.16, 0.9)
            EllesmereUI.ShowWidgetTooltip(self, tip)
        end)
        btn:SetScript("OnLeave", function()
            bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
            EllesmereUI.HideWidgetTooltip()
        end)
    end

    -- Threshold notice badge: an info bubble in the Settings button's top-left corner
    -- naming every spec that has a threshold configured, so a spec's setup stays visible
    -- from a page that doesn't list it. Green while none of them applies to the spec being
    -- played, orange while one does. Motion-only and click-through (same recipe as the
    -- Spec Overrides badge) so the button keeps its own hover and click.
    local THR_NOTE_IDLE   = { 0x0c/255, 0xd2/255, 0x9d/255, "0cd29d" }
    local THR_NOTE_ACTIVE = { 1, 0x8c/255, 0x26/255, "ff8c26" }
    -- getBarData: fn() -> bar table. Returns the updater so callers can re-run it after an edit.
    local function AttachThresholdNotice(anchorBtn, getBarData)
        if not anchorBtn then return end
        local badge = CreateFrame("Frame", nil, anchorBtn)
        badge:SetSize(14, 14)
        badge:SetPoint("TOPLEFT", anchorBtn, "TOPLEFT", 2, -2)
        -- Below the button's disabled overlay (level + 5), so a disabled bar dims and
        -- covers the badge along with everything else on the button.
        badge:SetFrameLevel(anchorBtn:GetFrameLevel() + 3)
        badge:SetMouseClickEnabled(false)
        local ico = badge:CreateTexture(nil, "OVERLAY")
        ico:SetAllPoints()
        if ico.SetSnapToPixelGrid then ico:SetSnapToPixelGrid(false); ico:SetTexelSnappingBias(0) end
        ico:SetTexture([[Interface\AddOns\EllesmereUI\media\icons\eui-info.png]])
        badge._color = THR_NOTE_IDLE
        badge:SetScript("OnEnter", function(self)
            local c = self._color
            ico:SetVertexColor(c[1], c[2], c[3], 1)
            if self._tip and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, self._tip)
            end
        end)
        badge:SetScript("OnLeave", function(self)
            local c = self._color
            ico:SetVertexColor(c[1], c[2], c[3], 0.85)
            EllesmereUI.HideWidgetTooltip()
        end)
        badge:Hide()

        -- Recolors the button's own border to match (white when nothing is configured); its
        -- OnEnter/OnLeave read anchorBtn._borderTint instead of hardcoding white, so the tint
        -- survives hover. Alpha still follows the existing hover/idle levels.
        local function ApplyBorderTint(rgb)
            anchorBtn._borderTint = rgb
            if anchorBtn._border and anchorBtn._border.SetColor then
                local a = anchorBtn:IsMouseOver() and 0.3 or EllesmereUI.DD_BRD_A
                anchorBtn._border:SetColor(rgb[1], rgb[2], rgb[3], a)
            end
        end

        local function Update()
            local list, active = ns.ThresholdNoticeInfo(getBarData())
            if not list then
                if EllesmereUI.HideWidgetTooltip and badge:IsMouseOver() then EllesmereUI.HideWidgetTooltip() end
                badge:Hide()
                ApplyBorderTint(THR_BORDER_WHITE)
                return
            end
            local c = active and THR_NOTE_ACTIVE or THR_NOTE_IDLE
            badge._color = c
            ico:SetVertexColor(c[1], c[2], c[3], badge:IsMouseOver() and 1 or 0.85)
            local tip = "|cff" .. c[4] .. EllesmereUI.L("Thresholds or hash lines configured for:") .. "|r " .. list
            local lead = active and EllesmereUI.L("Current Spec is affected by Threshold & Hash Lines.")
                or EllesmereUI.L("Current Spec is not affected by Threshold & Hash Lines.")
            badge._tip = "|cff" .. c[4] .. lead .. "|r\n\n" .. tip
            badge:Show()
            ApplyBorderTint(c)
        end
        anchorBtn:HookScript("OnShow", Update)
        EllesmereUI.RegisterWidgetRefresh(Update)
        Update()
        return Update
    end

    -- Spec / talent watcher for the Threshold & Hash Lines editors. A spec or talent change
    -- moves which entry the resolver picks and changes the loadout talents, so every open
    -- editor refreshes in place and keeps its selection. A spec swap with no editor open
    -- redraws the Display page instead; with one open, that redraw waits until the last
    -- editor closes (a redraw would close it); an editor closed by leaving the page or
    -- closing the panel leaves the rebuild to the page's next visit. One event frame and
    -- one accent entry per session, made by the first editor build; the talent events are
    -- registered only while an editor is open.
    local ThrWatchBuild, ThrEditorShown, ThrEditorHidden
    do
        local shown = {}  -- [editor page] = { refresh, repaint }, while that page is shown
        local watch, stale, redraw, refreshQueued
        local function OnDisplayPage()
            return EllesmereUI:IsShown() and EllesmereUI:GetActivePage() == PAGE_DISPLAY
        end
        local function RedrawNow()
            if not redraw then return end
            redraw = nil
            if OnDisplayPage() then EllesmereUI:RefreshPage(true) end
        end
        -- One redraw per burst (a spec swap fires both spec events); a page build in between cancels it
        local function RedrawDisplay()
            if redraw or not OnDisplayPage() then return end
            redraw = true
            C_Timer.After(0, RedrawNow)
        end
        -- One in-place refresh per burst, a frame later, once the bars have seen the change.
        -- An editor whose page the options page pool dressed again since is over: it
        -- leaves the watcher instead of painting widgets that now show something else.
        local function FlushRefresh()
            refreshQueued = nil
            for page, ed in pairs(shown) do
                if PoolGen(page) == ed.gen then ed.refresh() else ThrEditorHidden(page) end
            end
        end
        local function OnEvent(_, event)
            local specSwap = event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED"
            if next(shown) then
                if specSwap then stale = true end
                if not refreshQueued then
                    refreshQueued = true
                    C_Timer.After(0, FlushRefresh)
                end
            elseif specSwap then
                if OnDisplayPage() then
                    RedrawDisplay()
                else
                    -- Away from the page (another page or module, or the panel
                    -- closed): its next visit builds it for the new spec.
                    EllesmereUI:InvalidateModulePageCache("EllesmereUIResourceBars")
                end
            end
        end
        -- Every editor build: makes the watcher once; the page being built is current again
        ThrWatchBuild = function()
            stale, redraw = nil, nil
            if watch then return end
            watch = CreateFrame("Frame")
            watch:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
            watch:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
            watch:SetScript("OnEvent", OnEvent)
            -- The selection highlight follows the live theme accent
            EllesmereUI.RegAccent({ type = "callback", fn = function()
                for page, ed in pairs(shown) do
                    if PoolGen(page) == ed.gen then ed.repaint() else ThrEditorHidden(page) end
                end
            end })
        end
        ThrEditorShown = function(page, ed)
            if not next(shown) then
                watch:RegisterEvent("TRAIT_CONFIG_UPDATED")
                watch:RegisterEvent("PLAYER_TALENT_UPDATE")
            end
            shown[page] = ed
        end
        ThrEditorHidden = function(page)
            if not shown[page] then return end
            shown[page] = nil
            if next(shown) then return end
            watch:UnregisterEvent("TRAIT_CONFIG_UPDATED")
            watch:UnregisterEvent("PLAYER_TALENT_UPDATE")
            if stale then
                stale = nil
                if OnDisplayPage() then
                    RedrawDisplay()
                elseif EllesmereUI:GetActivePage() == PAGE_DISPLAY then
                    -- Closed with the panel: RefreshPage only flags a hidden panel, so its next open rebuilds the page
                    EllesmereUI:RefreshPage(true)
                else
                    -- Left for another page or module (the panel is open): drop the page's build so the next visit rebuilds it
                    EllesmereUI:InvalidateModulePageCache("EllesmereUIResourceBars")
                end
            end
        end
    end

    -- Threshold & Hash Lines editor, shared by the class resource, power and health bar
    -- sections. The Settings button opens an in-page editor over the section: the bar's
    -- threshold entries in a list on the left, the selected entry's settings on the right.
    -- cfg fields (optional unless marked):
    --    parentRgn       -- (required) the DualRow right region that hosts the button
    --    getBarData      -- (required) fn() returns the bar table (p.secondary, p.primary, p.health)
    --    refreshFn       -- (required) fn() called after a setting change
    --    rebuildFn       -- (required) fn() called after a structural change (hash lines, talent gate, variants)
    --    swatchRefreshFn -- fn() called after a threshold color change (default refreshFn)
    --    disabledFn      -- fn() returns true while the bar is off; disabledTip names the bar for its tooltip
    --    pageParent / pageTopY / pageBotY -- (required) the section's page frame and its Y range (pageBotY is
    --                       a fn, read when the editor first opens); the editor covers that range
    --    pageBotExtra    -- px the editor also covers below pageBotY (a row the page appends after the section)
    --    defaultR/G/B/A  -- default threshold color (new entries, the swatch and the band editor)
    --    roleShortcuts   -- bool: the spec picker offers All Healers / All Tanks / All DPS
    --    newEntry        -- fn(ids, barData) returns a new entry (default: thresholdPct 30 at the default color)
    --    partialDefault  -- bool: a default new entry covering a spender power (mana, energy, focus) colors below value
    --    thresholdField  -- the entry key the threshold input edits (default "thresholdPct")
    --    thresholdLabel  -- threshold row label (default "Threshold"); threshMin / threshMax its bounds (1 / 99)
    --    thresholdCog    -- { title, minWidth, rows = fn(CurEntry, RedrawDetail) }: a cog beside the threshold
    --    hashModeDefault -- what a missing entry.hashMode means (default "percent")
    --    hashWidthMax    -- Hash Width slider max (default 5)
    --    hashValueHint   -- localized hash input hint while lines sit by value (default "(Ex: 50000)")
    --    showBuffs       -- bool: Buff Colors row
    --    showSpenders    -- bool: Spender Colors row; spenderTip / spenderToggleTip its button / toggle tooltips
    --    textInsteadTip  -- tooltip of the Recolor Text Instead Of Bar toggle
    --    barInput        -- { label, field, min, max, default, letters }: a bar-wide number row, shown for
    --                       the entries whose rules set barInput
    --    entryRules      -- fn(ent, rules, barData) adjusts the selected entry's rules (see RefreshDetail)
    -- Returns settingsBtn (the button frame).
    local function BuildThresholdSettingsButton(cfg)
        local parentRgn = cfg.parentRgn
        local THR_FIELD = cfg.thresholdField or "thresholdPct"
        local HASH_NIL  = cfg.hashModeDefault or "percent"
        local ROW_GAP = 6

        local defR = cfg.defaultR or 1
        local defG = cfg.defaultG or 0.2
        local defB = cfg.defaultB or 0.2
        local defA = cfg.defaultA or 1
        local _playerClassFile = select(2, UnitClass("player"))

        local BTN_W, BTN_H = 140, 30
        local settingsBtn = CreateFrame("Button", nil, parentRgn)
        PP.Size(settingsBtn, BTN_W, BTN_H)
        PP.Point(settingsBtn, "RIGHT", parentRgn, "RIGHT", -20, 0)
        settingsBtn:SetFrameLevel(parentRgn:GetFrameLevel() + 2)
        local btnBg = EllesmereUI.SolidTex(settingsBtn, "BACKGROUND",
            EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
        btnBg:SetAllPoints()
        settingsBtn._border = EllesmereUI.MakeBorder(settingsBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        local btnLbl = EllesmereUI.MakeFont(settingsBtn, 13, nil, 1, 1, 1)
        btnLbl:SetAlpha(EllesmereUI.DD_TXT_A)
        btnLbl:SetPoint("CENTER")
        btnLbl:SetText(EllesmereUI.L("Settings"))
        settingsBtn:SetScript("OnEnter", function(self)
            btnBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
            if self._border and self._border.SetColor then
                local t = self._borderTint or THR_BORDER_WHITE
                self._border:SetColor(t[1], t[2], t[3], 0.3)
            end
        end)
        settingsBtn:SetScript("OnLeave", function(self)
            btnBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            if self._border and self._border.SetColor then
                local t = self._borderTint or THR_BORDER_WHITE
                self._border:SetColor(t[1], t[2], t[3], EllesmereUI.DD_BRD_A)
            end
        end)
        -- disabled overlay
        local btnDis = CreateFrame("Frame", nil, parentRgn)
        btnDis:SetAllPoints(settingsBtn)
        btnDis:SetFrameLevel(settingsBtn:GetFrameLevel() + 5)
        btnDis:EnableMouse(true)
        btnDis:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(settingsBtn, EllesmereUI.DisabledTooltip(cfg.disabledTip or "this bar"))
        end)
        btnDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateBtnDis()
            local off = cfg.disabledFn and cfg.disabledFn()
            if off then
                btnDis:Show()
                settingsBtn:SetAlpha(0.3)
                if parentRgn._label then parentRgn._label:SetAlpha(0.3) end
            else
                btnDis:Hide()
                settingsBtn:SetAlpha(1)
                if parentRgn._label then parentRgn._label:SetAlpha(1) end
            end
        end
        settingsBtn:HookScript("OnShow", UpdateBtnDis)
        EllesmereUI.RegisterWidgetRefresh(UpdateBtnDis)
        UpdateBtnDis()

        -- Threshold notice badge; re-run by both refreshers below (every entry edit, add,
        -- delete and spec change) and after a hash commit
        local UpdateNotice = AttachThresholdNotice(settingsBtn, cfg.getBarData)

        ThrWatchBuild()

        -- Editor page (lazy)
        local thrPage
        local specContainer
        local contentHalfSize
        local scrollTo  -- the entry list's ScrollTo (AttachSmoothScrollbar)
        local _entryFrames = {}
        local _tempSpecSel = {}  -- transient dropdown selection
        local _specDDRefresh
        local _selectedIdx       -- selected entry; drives the right pane
        local _roleSpecs         -- [role shortcut key] = its spec IDs
        local rules = {}         -- the selected entry's rules, filled by RefreshDetail
        local RefreshDetail, RefreshSpecEntries
        local function RedrawDetail() if RefreshDetail then RefreshDetail() end end

        -- True when an existing entry already claims specID
        local function IsSpecClaimed(specID)
            local bd = cfg.getBarData()
            if not bd or not bd.thresholdSpecs then return false end
            for _, entry in ipairs(bd.thresholdSpecs) do
                if entry.specIDs then
                    for _, sid in ipairs(entry.specIDs) do
                        if sid == 0 then return true end  -- All Specs claims everything
                        if sid == specID then return true end
                    end
                end
            end
            return false
        end
        local function HasAllSpecsEntry()
            local bd = cfg.getBarData()
            if not bd or not bd.thresholdSpecs then return false end
            for _, entry in ipairs(bd.thresholdSpecs) do
                if entry.specIDs then
                    for _, sid in ipairs(entry.specIDs) do
                        if sid == 0 then return true end
                    end
                end
            end
            return false
        end

        -- The shared spec list (WoW Forever: one row per class, no role
        -- shortcuts), locked by what the existing entries claim.
        local function BuildSpecItems()
            local items
            items, _roleSpecs = EllesmereUI.SpecPickItems({
                roles = cfg.roleShortcuts, lockedFn = IsSpecClaimed, allLockedFn = HasAllSpecsEntry })
            return items
        end

        -- A fresh entry: hash row empty, threshold on at its defaults
        local function NewEntry(ids, bd)
            if cfg.newEntry then return cfg.newEntry(ids, bd) end
            local newEntry = {
                specIDs = ids,
                thresholdEnabled = true,
                thresholdPct = 30,
                thresholdPartialOnly = false,
                thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA,
                hashValues = "", hashMode = "percent", hashWidth = 1,
                hashColorR = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
            }
            -- Default for the power bar's "Threshold color below value": spenders (mana/energy/focus)
            -- start ON (warn when low), builders (rage/runic/fury) OFF (warn when high). Only when
            -- the entry covers the current spec, the one whose power type we can read.
            if cfg.partialDefault then
                local curIdx = C_SpecializationInfo.GetSpecialization()
                local curSpecID = curIdx and C_SpecializationInfo.GetSpecializationInfo(curIdx)
                -- WoW Forever: the entry covers the player when it names a spec of the class.
                if curSpecID or EllesmereUI.IS_FOREVER then
                    for _, sid in ipairs(ids) do
                        if sid == 0 or sid == curSpecID or (EllesmereUI.IS_FOREVER and EllesmereUI.IsPlayerSpec(sid)) then
                            local _, token = UnitPowerType("player")
                            if token == "MANA" or token == "FOCUS" or token == "ENERGY" then
                                newEntry.thresholdPartialOnly = true
                            end
                            break
                        end
                    end
                end
            end
            return newEntry
        end

        -- Paints one row's bg/accent for the current selection state
        local function PaintRow(f)
            local sel = (f._entryIdx ~= nil) and (_selectedIdx == f._entryIdx)
            local eg = EllesmereUI.ELLESMERE_GREEN
            f._selected = sel
            f._accent:SetShown(sel)
            -- Re-apply the live theme accent each paint; the creation-time color goes stale after a theme change
            f._accent:SetColorTexture(eg.r, eg.g, eg.b, 1)
            if sel then
                f._bg:SetColorTexture(eg.r, eg.g, eg.b, 0.10)
            else
                f._bg:SetColorTexture(1, 1, 1, 0.02)
            end
        end
        local function RepaintRows()
            for i = 1, #_entryFrames do
                local f = _entryFrames[i]
                if f and f:IsShown() then PaintRow(f) end
            end
        end

        local function BuildFrame()
            local parent   = cfg.pageParent
            local INNERPAD = 10
            local ROW_H    = 50
            local botY     = cfg.pageBotY() - (cfg.pageBotExtra or 0)

            thrPage = CreateFrame("Frame", nil, parent)
            PP.Point(thrPage, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, cfg.pageTopY)
            PP.Point(thrPage, "TOPRIGHT", parent, "TOPRIGHT", -CONTENT_PAD, cfg.pageTopY)
            PP.Point(thrPage, "BOTTOMLEFT", parent, "TOPLEFT", CONTENT_PAD, botY)
            -- The unlock-mode cycle can leave this lazily-built frame with an undefined rect, so capture the resolved anchors: ToggleFrame re-asserts them before every Show to force a rect recompute.
            local _thrPts = {}
            for p = 1, thrPage:GetNumPoints() do _thrPts[p] = { thrPage:GetPoint(p) } end
            thrPage._reanchor = function()
                thrPage:ClearAllPoints()
                for p = 1, #_thrPts do thrPage:SetPoint(unpack(_thrPts[p])) end
            end
            thrPage:SetFrameLevel(parent:GetFrameLevel() + 50)
            thrPage:EnableMouse(true)
            -- Joins the spec / talent watcher while shown. A value being typed in the pane commits
            -- first, so the refresh never writes the saved value over it.
            local paneBoxes = {}  -- [edit box] = true, filled by MakeInput
            local ed = { refresh = function()
                local f = GetCurrentKeyBoardFocus()
                if f and paneBoxes[f] then f:ClearFocus() end
                RefreshSpecEntries(); RefreshDetail()
            end, repaint = RepaintRows, gen = PoolGen(thrPage) }
            thrPage:SetScript("OnShow", function(self) ThrEditorShown(self, ed) end)
            thrPage:SetScript("OnHide", ThrEditorHidden)
            local obg = thrPage:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints()
            obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 1)
            -- 1px center divider in the global BORDER style
            local div = thrPage:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(EllesmereUI.BORDER_R, EllesmereUI.BORDER_G, EllesmereUI.BORDER_B, 0.05)
            div:SetWidth(1)
            div:SetPoint("TOP", thrPage, "TOP", 0, 0)
            div:SetPoint("BOTTOM", thrPage, "BOTTOM", 0, 0)

            local totalH = thrPage:GetHeight()
            contentHalfSize = math.floor(thrPage:GetWidth() / 2 - (SIDE_PAD * 2))
            local BUTTON_W, BUTTON_H = 80, 29
            local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
            local eg = EllesmereUI.ELLESMERE_GREEN

            -- Back: the styled button (bg / border / label hover), the arrow leading its label
            local backBtn = CreateFrame("Button", nil, thrPage)
            PP.Size(backBtn, BUTTON_W, BUTTON_H)
            PP.Point(backBtn, "TOPLEFT", thrPage, "TOPLEFT", SIDE_PAD, -INNERPAD)
            backBtn:SetFrameLevel(thrPage:GetFrameLevel() + 2)
            local _, _, backLbl = EllesmereUI.MakeStyledButton(backBtn, "", 12, {
                0.077, 0.068, 0.058, 0.50,  0.119, 0.111, 0.104, 0.50,
                1, 1, 1, 0.12,  1, 1, 1, 0.22,
                1, 1, 1, 0.55,  1, 1, 1, 0.85,
            }, function() thrPage:Hide() end)
            local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
            backIcon:SetSize(14, 14)
            PP.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
            backIcon:SetTexture(MEDIA .. "icons\\eui-arrow-left.png")
            backIcon:SetVertexColor(eg.r, eg.g, eg.b)
            backIcon:SetAlpha(0.6)
            if backIcon.SetSnapToPixelGrid then
                backIcon:SetSnapToPixelGrid(false); backIcon:SetTexelSnappingBias(0)
            end
            backLbl:ClearAllPoints()
            PP.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
            backLbl:SetText(EllesmereUI.L("Back"))
            backBtn:HookScript("OnEnter", function() backIcon:SetAlpha(0.85) end)
            backBtn:HookScript("OnLeave", function() backIcon:SetAlpha(0.6) end)

            -- Spec-assignment chrome: the spec dropdown + Add Specs, right of Back
            do
                local ADD_W, GAP_L = 90, 10
                local DD_W = contentHalfSize - (INNERPAD * 2) - BUTTON_W - ADD_W
                local ddRow = CreateFrame("Frame", nil, backBtn)
                ddRow:SetSize(DD_W, BUTTON_H)
                ddRow:SetPoint("TOPLEFT", backBtn, "TOPRIGHT", 10, 0)
                ddRow:SetFrameLevel(thrPage:GetFrameLevel() + 2)

                -- Spec dropdown (checkbox multi-select with search)
                local specItems = BuildSpecItems()
                local specDDHost = CreateFrame("Frame", nil, ddRow)
                specDDHost:SetSize(DD_W, BUTTON_H)
                specDDHost:SetPoint("LEFT", ddRow, "LEFT", 0, 0)
                specDDHost:SetFrameLevel(ddRow:GetFrameLevel())

                local cbDD, cbDDRefresh  -- forward decl for closure access
                cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    specDDHost, DD_W, specDDHost:GetFrameLevel() + 2,
                    specItems,
                    function(key)
                        -- Role shortcuts never show as "checked"
                        if _roleSpecs[key] then return false end
                        -- WoW Forever class row: checked while every spec of the class is selected
                        local fvIDs = EllesmereUI.IS_FOREVER and EllesmereUI.ForeverClassSpecIDs(key)
                        if fvIDs then
                            for i = 1, #fvIDs do
                                if not _tempSpecSel[fvIDs[i]] then return false end
                            end
                            return true
                        end
                        return _tempSpecSel[key] or false
                    end,
                    function(key, val)
                        -- Role shortcuts + All Specs: select, then close the dropdown
                        local roleSpecs = _roleSpecs[key]
                        if roleSpecs then
                            wipe(_tempSpecSel)
                            for _, sid in ipairs(roleSpecs) do _tempSpecSel[sid] = true end
                            cbDD:Click()
                            if cbDDRefresh then cbDDRefresh() end
                            return
                        end
                        if key == 0 then
                            wipe(_tempSpecSel)
                            _tempSpecSel[0] = true
                            cbDD:Click()
                            if cbDDRefresh then cbDDRefresh() end
                            return
                        end
                        -- WoW Forever class row: selects or clears every spec of the class
                        local fvIDs = EllesmereUI.IS_FOREVER and EllesmereUI.ForeverClassSpecIDs(key)
                        if fvIDs then
                            if val then _tempSpecSel[0] = nil end
                            for i = 1, #fvIDs do _tempSpecSel[fvIDs[i]] = val and true or nil end
                            if cbDDRefresh then cbDDRefresh() end
                            return
                        end
                        if val then
                            _tempSpecSel[0] = nil
                            _tempSpecSel[key] = true
                        else
                            _tempSpecSel[key] = nil
                        end
                        if cbDDRefresh then cbDDRefresh() end
                    end,
                    nil, 10, true
                )
                PP.Point(cbDD, "LEFT", specDDHost, "LEFT", 0, 0)
                -- Dropdown label font 11px instead of the default 13
                for _, rgn2 in ipairs({ cbDD:GetRegions() }) do
                    if rgn2.SetFont and rgn2.GetText then
                        local f, _, fl = rgn2:GetFont(); if f then rgn2:SetFont(f, 11, fl or "") end; break
                    end
                end

                -- Replace "None" with placeholder text on the dropdown label
                local _origRefresh = cbDDRefresh
                local function WrappedRefresh()
                    _origRefresh()
                    for _, rgn2 in ipairs({ cbDD:GetRegions() }) do
                        if rgn2.GetText and EllesmereUI.EnKey(rgn2:GetText()) == "None" then
                            rgn2:SetText(EllesmereUI.L("Select a Spec...")); break
                        end
                    end
                end
                _specDDRefresh = WrappedRefresh
                WrappedRefresh()

                local addBtn = CreateFrame("Button", nil, ddRow)
                PP.Size(addBtn, ADD_W, BUTTON_H)
                addBtn:SetPoint("LEFT", specDDHost, "RIGHT", GAP_L, 0)
                addBtn:SetFrameLevel(ddRow:GetFrameLevel() + 2)
                local _, _, addLbl = EllesmereUI.MakeStyledButton(addBtn, "", 11, {
                    0.069, 0.058, 0.047, 0.92,  0.069, 0.058, 0.047, 0.92,
                    1, 1, 1, 0.4,  1, 1, 1, 0.6,
                    1, 1, 1, 0.5,  1, 1, 1, 0.7,
                }, function()
                    local bd = cfg.getBarData(); if not bd then return end
                    local ids = {}
                    if _tempSpecSel[0] then
                        ids[1] = 0
                    else
                        for sid in pairs(_tempSpecSel) do
                            if sid ~= 0 then ids[#ids + 1] = sid end
                        end
                    end
                    if #ids == 0 then return end
                    if not bd.thresholdSpecs then bd.thresholdSpecs = {} end
                    bd.thresholdSpecs[#bd.thresholdSpecs + 1] = NewEntry(ids, bd)
                    _selectedIdx = #bd.thresholdSpecs
                    wipe(_tempSpecSel)
                    WrappedRefresh()
                    RefreshSpecEntries(true)
                    RedrawDetail()
                    cfg.refreshFn()
                end)
                addLbl:SetText(EllesmereUI.L("Add Specs"))
            end

            -- Scrollable entry container
            local specContainerH = totalH - (INNERPAD * 3) - BUTTON_H
            specContainer = CreateFrame("Frame", nil, backBtn)
            specContainer:SetFrameStrata("DIALOG")
            specContainer:SetFrameLevel(200)
            PP.Point(specContainer, "TOPLEFT", thrPage, "TOPLEFT", SIDE_PAD, -ROW_H)
            PP.Size(specContainer, contentHalfSize, specContainerH)

            local bg = specContainer:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.077, 0.068, 0.058, 0.95)
            PP.CreateBorder(specContainer, 1, 1, 1, 0.15, 1, "BORDER", 7)

            local scrollFrame = CreateFrame("ScrollFrame", nil, specContainer)
            scrollFrame:SetPoint("TOPLEFT", specContainer, "TOPLEFT", 1, -2)
            scrollFrame:SetPoint("TOPRIGHT", specContainer, "TOPRIGHT", -1, -2)
            scrollFrame:SetPoint("BOTTOMRIGHT", specContainer, "BOTTOMRIGHT", -1, 1)
            scrollFrame:SetFrameLevel(specContainer:GetFrameLevel() + 1)

            local scrollChild = CreateFrame("Frame", nil, scrollFrame)
            scrollChild:SetWidth(contentHalfSize)
            scrollFrame:SetScrollChild(scrollChild)
            specContainer._scrollChild = scrollChild
            specContainer._scrollFrame = scrollFrame

            -- Thin scrollbar on the container edge, shown on overflow; while the list fits, the wheel
            -- scrolls the page, and Shift + wheel scales the panel as everywhere in it
            scrollTo = select(2, EllesmereUI.AttachSmoothScrollbar(scrollFrame, {
                child = scrollChild, trackParent = specContainer, panelWheel = true, passWheel = true,
                step = 30, width = 4, thumbMin = 20, rightInset = 3, topInset = 4, level = 10,
                trackAlpha = 0.04, thumbAlpha = 0.15,
            }))

            -- Right detail pane: config for the selected entry
            local detailC = CreateFrame("Frame", nil, thrPage)
            detailC:SetFrameStrata("DIALOG")
            detailC:SetFrameLevel(200)
            -- The right side has no header row, so it starts at the top
            PP.Point(detailC, "TOPRIGHT", thrPage, "TOPRIGHT", -SIDE_PAD, -INNERPAD)
            PP.Size(detailC, contentHalfSize, specContainerH + (ROW_H - INNERPAD))
            local dBg = detailC:CreateTexture(nil, "BACKGROUND")
            dBg:SetAllPoints()
            dBg:SetColorTexture(0.077, 0.068, 0.058, 0.95)
            PP.CreateBorder(detailC, 1, 1, 1, 0.15, 1, "BORDER", 7)
            detailC:EnableMouse(true)

            local DPAD   = 16
            local DLVL   = detailC:GetFrameLevel() + 2
            local ROWH   = 26
            local ROWGAP = 12
            local MEDIAF = EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"

            -- Shown when nothing is selected
            local dPlaceholder = EllesmereUI.MakeFont(detailC, 13, nil, 1, 1, 1)
            dPlaceholder:SetAlpha(0.4)
            dPlaceholder:SetPoint("CENTER")
            dPlaceholder:SetText(EllesmereUI.L("Select or add an entry"))

            -- The live currently-selected entry, or nil
            local function CurEntry()
                local bd = cfg.getBarData()
                if not bd or not bd.thresholdSpecs then return nil end
                return _selectedIdx and bd.thresholdSpecs[_selectedIdx] or nil
            end

            local _allRows = {}
            -- Labeled row frame, registered for the layout pass
            local function DRow(labelText, h)
                local rf = CreateFrame("Frame", nil, detailC)
                rf:SetFrameLevel(DLVL)
                rf._rawH = h or ROWH
                PP.Height(rf, rf._rawH)
                if labelText then
                    local lbl = EllesmereUI.MakeFont(rf, 13, nil, 1, 1, 1)
                    lbl:SetAlpha(0.6)
                    lbl:SetPoint("LEFT", rf, "LEFT", 0, 0)
                    lbl:SetText(EllesmereUI.L(labelText))
                    rf._lbl = lbl
                end
                _allRows[#_allRows + 1] = rf
                return rf
            end

            -- Value edit boxes (hash / threshold)
            local function MakeInput(rowParent, w, numeric)
                local ib = CreateFrame("EditBox", nil, rowParent)
                paneBoxes[ib] = true
                PP.Size(ib, w, 22)
                ib:SetFrameLevel(rowParent:GetFrameLevel() + 3)
                ib:SetAutoFocus(false)
                ib:SetFont(MEDIAF, 12, "")
                ib:SetTextColor(1, 1, 1, 0.75)
                ib:SetJustifyH("CENTER")
                if numeric then ib:SetNumeric(true) end
                local ibg = ib:CreateTexture(nil, "BACKGROUND")
                ibg:SetAllPoints()
                ibg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                EllesmereUI.MakeBorder(ib, 1, 1, 1, 0.08, PP)
                return ib
            end

            -- Greys a row's controls and explains why (tooltip in blocker._tip), shown by RefreshDetail
            local function MakeBlocker(row, fromRgn, toRgn, inset, lvl)
                local blocker = CreateFrame("Frame", nil, row)
                blocker:SetPoint("TOPLEFT", fromRgn, "TOPLEFT", -inset, 3)
                blocker:SetPoint("BOTTOMRIGHT", toRgn, "BOTTOMRIGHT", 3, -3)
                blocker:SetFrameLevel(row:GetFrameLevel() + lvl)
                blocker:EnableMouse(true)
                local tex = blocker:CreateTexture(nil, "OVERLAY")
                tex:SetAllPoints()
                tex:SetColorTexture(0.077, 0.068, 0.058, 0.7)
                blocker:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, self._tip) end)
                blocker:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                blocker:Hide()
                return blocker
            end

            -- Row: Talent gate (single-spec entries only)
            local talentRow = DRow("Talent", ROWH)
            talentRow._talentValues = { _menuOpts = { searchable = true, parent = thrPage } }
            talentRow._talentOrder = {}
            local talentDD = EllesmereUI.BuildDropdownControl(
                talentRow, 170, talentRow:GetFrameLevel() + 2,
                talentRow._talentValues, talentRow._talentOrder,
                function()
                    local ent = CurEntry(); if not ent then return 0 end
                    return ent.talentSpellID or 0
                end,
                function(key)
                    local ent = CurEntry(); if not ent then return end
                    if key == 0 then
                        ent.talentSpellID = nil; ent.talentName = nil
                    else
                        ent.talentSpellID = key
                        ent.talentName = talentRow._talentValues[key]
                    end
                    cfg.rebuildFn()
                    if talentRow._talentDD and talentRow._talentDD._refreshLabel then
                        talentRow._talentDD._refreshLabel()
                    end
                    -- Relabel + re-dim duplicate entries live
                    RefreshSpecEntries()
                end,
                function(key)
                    local ent = CurEntry(); if not ent then return false end
                    local bd = cfg.getBarData(); if not bd or not bd.thresholdSpecs then return false end
                    local wantGate = (key ~= 0) and key or nil
                    for i, other in ipairs(bd.thresholdSpecs) do
                        if i ~= _selectedIdx then
                            local og = other.talentSpellID
                            local sameGate = (wantGate == nil and og == nil)
                                or (wantGate ~= nil and og == wantGate)
                            if sameGate and ns.SpecsConflict(ent.specIDs, other.specIDs) then
                                return EllesmereUI.L("Already used by another card for this spec")
                            end
                        end
                    end
                    return false
                end
            )
            talentDD:SetHeight(22)
            talentDD:SetPoint("RIGHT", talentRow, "RIGHT", 0, 0)
            talentRow._talentDD = talentDD
            -- Keep the menu above the cog popups
            talentDD:HookScript("OnClick", function()
                local m = talentDD._ddMenu
                if m then m:SetFrameStrata("TOOLTIP") end
            end)
            talentDD:HookScript("OnHide", function() talentDD._invalidateMenu() end)
            -- Greys the picker for a spec of a class the player is not playing (its talents are not in the loadout)
            local talentDis = CreateFrame("Frame", nil, talentRow)
            talentDis:SetPoint("TOPLEFT", talentDD, "TOPLEFT", 0, 0)
            talentDis:SetPoint("BOTTOMRIGHT", talentDD, "BOTTOMRIGHT", 0, 0)
            talentDis:SetFrameLevel(talentDD:GetFrameLevel() + 10)
            talentDis:EnableMouse(true)
            local talentDisTex = talentDis:CreateTexture(nil, "OVERLAY")
            talentDisTex:SetAllPoints()
            talentDisTex:SetColorTexture(0.077, 0.068, 0.058, 0.6)
            talentDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(talentDis, EllesmereUI.L("Talent gating is only available while playing this spec's class"))
            end)
            talentDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            talentDis:Hide()
            talentRow._dis = talentDis

            -- Row: Hash values ("Hash at X" + hint + input + swatch + style cog)
            local hashRow = DRow(nil, ROWH)
            local hashLbl = EllesmereUI.MakeFont(hashRow, 13, nil, 1, 1, 1)
            hashLbl:SetAlpha(0.6)
            hashLbl:SetPoint("LEFT", hashRow, "LEFT", 0, 0)
            hashRow._lbl2 = hashLbl
            local hashModeRow = { type = "toggle", label = "Position by percent",
                get = function() local ent = CurEntry(); return ((ent and ent.hashMode) or HASH_NIL) == "percent" end,
                set = function(v)
                    local ent = CurEntry(); if not ent then return end
                    ent.hashMode = v and "percent" or "value"
                    cfg.rebuildFn()
                    RedrawDetail()
                end }
            if cfg.entryRules then
                -- Pip resources place their lines by stack count
                hashModeRow.disabled = function() return rules.pips end
                hashModeRow.disabledTooltip = "Bar-type resources only (pips use stack counts)"
            end
            -- Style cog, pinned inside the row's right edge
            local hashCogBtn = EllesmereUI.BuildInlineCog(hashRow, {
                title = "Hash Line Style", bgAlpha = 1, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
                rows = {
                    hashModeRow,
                    { type = "slider", label = "Hash Width", min = 1, max = cfg.hashWidthMax or 5, step = 1,
                      get = function() local ent = CurEntry(); return ent and ent.hashWidth or 1 end,
                      set = function(v) local ent = CurEntry(); if ent then ent.hashWidth = v; cfg.rebuildFn() end end },
                },
                size = 20, anchorTo = hashRow, relPoint = "RIGHT", gap = 0,
            })
            local hashSwatch, hashSwatchSnap = EllesmereUI.BuildColorSwatch(
                hashRow, hashRow:GetFrameLevel() + 4,
                function()
                    local ent = CurEntry(); if not ent then return 1, 1, 1, 0.7 end
                    return ent.hashColorR or 1, ent.hashColorG or 1, ent.hashColorB or 1, ent.hashColorA or 0.7
                end,
                function(r, g, b, a)
                    local ent = CurEntry(); if not ent then return end
                    ent.hashColorR, ent.hashColorG, ent.hashColorB, ent.hashColorA = r, g, b, a
                    cfg.rebuildFn()
                end, true, 19)
            hashSwatch:SetPoint("RIGHT", hashCogBtn, "LEFT", -8, 0)
            local hashInput = MakeInput(hashRow, 120, false)
            hashInput:SetPoint("RIGHT", hashSwatch, "LEFT", -8, 0)
            local hashHint = EllesmereUI.MakeFont(hashRow, 10, nil, 1, 1, 1)
            hashHint:SetAlpha(0.35)
            hashHint:SetPoint("RIGHT", hashInput, "LEFT", -8, 0)
            hashRow._hint = hashHint
            hashInput:SetScript("OnEditFocusLost", function(self)
                if self._cancelCommit then self._cancelCommit = nil; return end
                local ent = CurEntry(); if not ent then return end
                -- Only the numeric positions are kept, so text that draws no line never counts as configured
                ent.hashValues = SanitizePositions(self:GetText(), true)
                self:SetText(ent.hashValues)
                cfg.rebuildFn()
                UpdateNotice()
            end)
            hashInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            hashInput:SetScript("OnEscapePressed", function(self)
                self._cancelCommit = true
                local ent = CurEntry()
                self:SetText(ent and ent.hashValues or "")
                self:ClearFocus()
            end)

            -- Row: Threshold (enable toggle + input + swatch [+ cog])
            local threshRow = DRow(cfg.thresholdLabel or "Threshold", ROWH)
            local threshCogBtn
            local tc = cfg.thresholdCog
            if tc then
                threshCogBtn = EllesmereUI.BuildInlineCog(threshRow, {
                    title = tc.title, bgAlpha = 1, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
                    minWidth = tc.minWidth, rows = tc.rows(CurEntry, RedrawDetail),
                    size = 20, anchorTo = threshRow, relPoint = "RIGHT", gap = 0,
                })
            end
            local threshEnable, _, threshEnableSnap = EllesmereUI.BuildToggleControl(
                threshRow, DLVL + 4,
                function()
                    local ent = CurEntry(); if not ent then return false end
                    if ent.thresholdEnabled == nil then return true end
                    return ent.thresholdEnabled
                end,
                function(v)
                    local ent = CurEntry(); if not ent then return end
                    ent.thresholdEnabled = v
                    cfg.refreshFn()
                    RedrawDetail()
                end,
                { sizeRatio = 0.95 }
            )
            -- The entry's own color, else the bar-wide one the bar falls back to
            local threshSwatch, threshSwatchSnap = EllesmereUI.BuildColorSwatch(
                threshRow, threshRow:GetFrameLevel() + 4,
                function()
                    local ent = CurEntry(); if not ent then return defR, defG, defB, defA end
                    local bd = cfg.getBarData()
                    return ent.thresholdR or bd.thresholdR or defR, ent.thresholdG or bd.thresholdG or defG,
                        ent.thresholdB or bd.thresholdB or defB, ent.thresholdA or bd.thresholdA or defA
                end,
                function(r, g, b, a)
                    local ent = CurEntry(); if not ent then return end
                    ent.thresholdR, ent.thresholdG, ent.thresholdB, ent.thresholdA = r, g, b, a
                    if cfg.swatchRefreshFn then cfg.swatchRefreshFn() else cfg.refreshFn() end
                end, true, 19)
            if threshCogBtn then
                threshSwatch:SetPoint("RIGHT", threshCogBtn, "LEFT", -8, 0)
            else
                threshSwatch:SetPoint("RIGHT", threshRow, "RIGHT", 0, 0)
            end
            local threshInput = MakeInput(threshRow, 50, true)
            threshInput:SetPoint("RIGHT", threshSwatch, "LEFT", -8, 0)
            threshEnable:SetPoint("RIGHT", threshInput, "LEFT", -8, 0)
            -- Bounds and default come from the selected entry's rules
            threshInput:SetScript("OnEditFocusLost", function(self)
                if self._cancelCommit then self._cancelCommit = nil; return end
                local ent = CurEntry(); if not ent then return end
                local val = tonumber(self:GetText())
                if not val then self:SetText(tostring(ent[THR_FIELD] or rules.thrDef)); return end
                val = math.max(rules.thrMin, math.min(rules.thrMax, math.floor(val + 0.5)))
                self:SetText(tostring(val))
                ent[THR_FIELD] = val
                cfg.refreshFn()
            end)
            threshInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            threshInput:SetScript("OnEscapePressed", function(self)
                self._cancelCommit = true
                local ent = CurEntry()
                self:SetText(tostring((ent and ent[THR_FIELD]) or rules.thrDef))
                self:ClearFocus()
            end)
            -- The entry's note on its bounds (rules.thrTip), if any
            threshInput:SetScript("OnEnter", function(self)
                if self._tip then EllesmereUI.ShowWidgetTooltip(self, self._tip) end
            end)
            threshInput:SetScript("OnLeave", function(self)
                if self._tip then EllesmereUI.HideWidgetTooltip() end
            end)
            -- Greys the threshold input + swatch (label kept) while the threshold is off or replaced by multi-band
            local threshDis = CreateFrame("Frame", nil, threshRow)
            threshDis:SetPoint("TOPLEFT", threshInput, "TOPLEFT", -2, 3)
            threshDis:SetPoint("BOTTOMRIGHT", threshSwatch, "BOTTOMRIGHT", 3, -3)
            threshDis:SetFrameLevel(threshRow:GetFrameLevel() + 6)
            threshDis:EnableMouse(true)
            local threshDisTex = threshDis:CreateTexture(nil, "OVERLAY")
            threshDisTex:SetAllPoints()
            threshDisTex:SetColorTexture(0.077, 0.068, 0.058, 0.7)
            threshDis:SetScript("OnEnter", function()
                local tip = (threshRow._disTip == "MULTI") and BAND_REPLACES_TIP
                    or EllesmereUI.DisabledTooltip("Threshold Color")
                EllesmereUI.ShowWidgetTooltip(threshDis, tip)
            end)
            threshDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Row: Multi-band (toggle + Bands editor button)
            local multiRow = DRow("Multi-band Coloring", ROWH)
            local bandsBtn = CreateFrame("Button", nil, multiRow)
            PP.Size(bandsBtn, 60, 22)
            bandsBtn:SetPoint("RIGHT", multiRow, "RIGHT", 0, 0)
            bandsBtn:SetFrameLevel(multiRow:GetFrameLevel() + 4)
            SkinCardButton(bandsBtn, EllesmereUI.L("Bands"), BAND_HELP_TIP)
            bandsBtn:SetScript("OnClick", function(self)
                if not CurEntry() then return end
                ShowBandEditor({
                    getBarData = cfg.getBarData, refreshFn = cfg.refreshFn,
                    entryIdx = _selectedIdx, anchor = self, countBased = rules.pips,
                    lockPercent = rules.bandPctCap ~= nil, percentMax = rules.bandPctCap,
                    defR = defR, defG = defG, defB = defB, defA = defA,
                })
            end)
            local multiToggle, _, multiSnap = EllesmereUI.BuildToggleControl(
                multiRow, DLVL + 4,
                function() local ent = CurEntry(); return ent and ent.multiBandEnabled or false end,
                function(v)
                    local ent = CurEntry(); if not ent then return end
                    ent.multiBandEnabled = v
                    cfg.refreshFn()
                    RedrawDetail()
                end,
                { sizeRatio = 0.95 }
            )
            multiToggle:SetPoint("RIGHT", bandsBtn, "LEFT", -10, 0)
            multiToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, BAND_HELP_TIP) end)
            multiToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            -- Covers the toggle + Bands button when multi-band cannot apply (rules.multiBlock)
            local multiDis = MakeBlocker(multiRow, multiToggle, bandsBtn, 3, 8)

            -- Row: Buff colors (toggle + Buffs editor button). First active buff wins and overrides threshold coloring.
            local buffRow, buffSnap
            if cfg.showBuffs then
                buffRow = DRow("Buff Colors", ROWH)
                local buffsBtn = CreateFrame("Button", nil, buffRow)
                PP.Size(buffsBtn, 60, 22)
                buffsBtn:SetPoint("RIGHT", buffRow, "RIGHT", 0, 0)
                buffsBtn:SetFrameLevel(buffRow:GetFrameLevel() + 4)
                SkinCardButton(buffsBtn, EllesmereUI.L("Buffs"), BUFF_HELP_TIP)
                buffsBtn:SetScript("OnClick", function(self)
                    if not CurEntry() then return end
                    ShowBuffEditor({
                        getBarData = cfg.getBarData, refreshFn = cfg.refreshFn,
                        entryIdx = _selectedIdx, anchor = self,
                    })
                end)
                local buffToggle
                buffToggle, _, buffSnap = EllesmereUI.BuildToggleControl(
                    buffRow, DLVL + 4,
                    function() local ent = CurEntry(); return ent and ent.buffColorEnabled or false end,
                    function(v)
                        local ent = CurEntry(); if not ent then return end
                        ent.buffColorEnabled = v
                        cfg.refreshFn()
                    end,
                    { sizeRatio = 0.95 }
                )
                buffToggle:SetPoint("RIGHT", buffsBtn, "LEFT", -10, 0)
                buffToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, BUFF_HELP_TIP) end)
                buffToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end

            -- Row: Spender colors (toggle + Spenders editor button). First castable spell wins.
            local spenderRow, spenderSnap
            if cfg.showSpenders then
                local spTip = cfg.spenderTip or SPENDER_HELP_TIP
                local spToggleTip = cfg.spenderToggleTip or spTip
                spenderRow = DRow("Spender Colors", ROWH)
                local spBtn = CreateFrame("Button", nil, spenderRow)
                PP.Size(spBtn, 60, 22)
                spBtn:SetPoint("RIGHT", spenderRow, "RIGHT", 0, 0)
                spBtn:SetFrameLevel(spenderRow:GetFrameLevel() + 4)
                SkinCardButton(spBtn, EllesmereUI.L("Spenders"), spTip)
                spBtn:SetScript("OnClick", function(self)
                    if not CurEntry() then return end
                    ShowSpenderEditor({
                        getBarData = cfg.getBarData, refreshFn = cfg.refreshFn,
                        entryIdx = _selectedIdx, anchor = self,
                    })
                end)
                local spToggle
                spToggle, _, spenderSnap = EllesmereUI.BuildToggleControl(
                    spenderRow, DLVL + 4,
                    function() local ent = CurEntry(); return ent and ent.spenderColorEnabled or false end,
                    function(v)
                        local ent = CurEntry(); if not ent then return end
                        ent.spenderColorEnabled = v
                        cfg.refreshFn()
                    end,
                    { sizeRatio = 0.95 }
                )
                spToggle:SetPoint("RIGHT", spBtn, "LEFT", -10, 0)
                spToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, spToggleTip) end)
                spToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end

            -- Row: Recolor text instead of bar (per entry)
            local textInsteadRow = DRow("Recolor Text Instead Of Bar", ROWH)
            local textInsteadToggle, _, textInsteadSnap = EllesmereUI.BuildToggleControl(
                textInsteadRow, DLVL + 4,
                function() local ent = CurEntry(); return ent and ent.thresholdTextInstead or false end,
                function(v) local ent = CurEntry(); if ent then ent.thresholdTextInstead = v; cfg.refreshFn() end end,
                { sizeRatio = 0.95 }
            )
            textInsteadToggle:SetPoint("RIGHT", textInsteadRow, "RIGHT", 0, 0)
            if cfg.textInsteadTip then
                textInsteadToggle:HookScript("OnEnter", function(self)
                    EllesmereUI.ShowWidgetTooltip(self, cfg.textInsteadTip)
                end)
                textInsteadToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
            -- Covers the row when recoloring the text can have no effect (rules.textBlock)
            local textInsteadDis = MakeBlocker(textInsteadRow, textInsteadRow, textInsteadToggle, 2, 6)

            -- Row: a bar-wide number (cfg.barInput), placed only for the entries whose rules ask for it
            local barRow, barSnap
            local bi = cfg.barInput
            if bi then
                barRow = DRow(bi.label, ROWH)
                local barInput = MakeInput(barRow, 50, true)
                barInput:SetPoint("RIGHT", barRow, "RIGHT", 0, 0)
                if bi.letters then barInput:SetMaxLetters(bi.letters) end
                barSnap = function()
                    local bd = cfg.getBarData()
                    barInput:SetText(tostring((bd and bd[bi.field]) or bi.default))
                end
                barInput:SetScript("OnEditFocusLost", function(self)
                    if self._cancelCommit then self._cancelCommit = nil; return end
                    local bd = cfg.getBarData(); if not bd then return end
                    local v = tonumber(self:GetText())
                    if v then
                        bd[bi.field] = math.max(bi.min, math.min(bi.max, math.floor(v + 0.5)))
                        cfg.refreshFn()
                    end
                    barSnap()
                end)
                barInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                barInput:SetScript("OnEscapePressed", function(self) self._cancelCommit = true; self:ClearFocus(); barSnap() end)
                -- Covers the row when another setting owns the value (rules.barBlock)
                barRow._dis = MakeBlocker(barRow, barRow, barInput, 2, 6)
            end

            -- RefreshDetail: repaint the pane for the selected entry
            RefreshDetail = function()
                UpdateNotice()
                local ent = CurEntry()
                if not ent then
                    for _, rf in ipairs(_allRows) do rf:Hide() end
                    dPlaceholder:Show()
                    return
                end
                dPlaceholder:Hide()

                -- The entry's rules: the bar's defaults, then cfg.entryRules adjusts them per entry.
                --   thrMin / thrMax / thrDef -- threshold bounds and the default value
                --   thrLabel / thrTip -- threshold row label (nil keeps the static one) and input note
                --   pips       -- entry counts stacks: hash lines by stack, band boundaries as counts
                --   hideHash   -- no hash row for this entry
                --   bandPctCap -- the band editor is percent only, up to this value
                --   multiBlock / textBlock -- why multi-band / text recoloring cannot apply (nil = it can)
                --   barInput   -- show the cfg.barInput row; barBlock -- why it cannot apply (nil = it can)
                local r = rules
                r.thrMin, r.thrMax, r.thrDef = cfg.threshMin or 1, cfg.threshMax or 99, 30
                r.thrLabel, r.thrTip, r.pips, r.hideHash = nil, nil, false, false
                r.bandPctCap, r.multiBlock, r.textBlock, r.barInput, r.barBlock = nil, nil, nil, false, nil
                if cfg.entryRules then cfg.entryRules(ent, r, cfg.getBarData()) end

                -- Talent gate is single-spec only
                local ids = ent.specIDs
                local allowTalent = (ids and #ids == 1 and ids[1] ~= 0) and true or false

                -- Refill talent options from the active loadout plus the entry's saved gate, even if off-spec/off-loadout
                if allowTalent then
                    local loadoutTalents = (ns.GetLoadoutTalents()) or {}
                    local vals, ord = talentRow._talentValues, talentRow._talentOrder
                    wipe(ord)
                    for k in pairs(vals) do if k ~= "_menuOpts" then vals[k] = nil end end
                    vals[0] = EllesmereUI.L("No talent"); ord[#ord + 1] = 0
                    for _, t in ipairs(loadoutTalents) do
                        if vals[t.spellID] == nil then ord[#ord + 1] = t.spellID end
                        vals[t.spellID] = t.name
                    end
                    if ent.talentSpellID and vals[ent.talentSpellID] == nil then
                        vals[ent.talentSpellID] = ent.talentName
                            or C_Spell.GetSpellName(ent.talentSpellID)
                            or ("Spell " .. ent.talentSpellID)
                        ord[#ord + 1] = ent.talentSpellID
                    end
                    if talentDD._invalidateMenu then talentDD._invalidateMenu() end
                    if talentDD._refreshLabel then talentDD._refreshLabel() end

                    -- Talents come from the player's own loadout, so block the picker for other classes' specs
                    local talentClassOK = true
                    if GetSpecializationInfoByID then
                        local _, _, _, _, _, classFile = GetSpecializationInfoByID(ids[1])
                        talentClassOK = (classFile == _playerClassFile)
                    elseif EllesmereUI.IS_FOREVER then
                        talentClassOK = (EllesmereUI.SpecClassOf(ids[1]) == _playerClassFile)
                    end
                    talentRow._dis:SetShown(not talentClassOK)
                end

                -- Hash row text: pip resources place lines by stack count
                local hashWord, hintText
                if r.pips then
                    hashWord, hintText = EllesmereUI.L("Stack"), EllesmereUI.L("(Ex: 2,4)")
                else
                    local isPct = (ent.hashMode or HASH_NIL) == "percent"
                    hashWord = isPct and EllesmereUI.L("Percent") or EllesmereUI.L("Value")
                    hintText = isPct and EllesmereUI.L("(Ex: 25,50,75)") or cfg.hashValueHint or EllesmereUI.L("(Ex: 50000)")
                end
                hashRow._lbl2:SetText(EllesmereUI.Lf("Hash at %1$s", hashWord))
                hashRow._hint:SetText(hintText)
                hashInput:SetText(ent.hashValues or "")

                threshInput:SetText(tostring(ent[THR_FIELD] or r.thrDef))
                threshInput._tip = r.thrTip
                if r.thrLabel then threshRow._lbl:SetText(r.thrLabel) end

                hashSwatchSnap(); threshEnableSnap(); threshSwatchSnap(); multiSnap(); textInsteadSnap()
                if buffSnap then buffSnap() end
                if spenderSnap then spenderSnap() end
                if barSnap then barSnap() end

                -- Single threshold and multi-band are independent toggles; multi wins over single when both are on.
                local entEnabled = ent.thresholdEnabled
                if entEnabled == nil then entEnabled = true end
                local multiOn = (ent.multiBandEnabled and not r.multiBlock) and true or false
                if r.multiBlock then
                    multiToggle:SetAlpha(0.35); multiToggle:SetEnabled(false)
                    bandsBtn:SetAlpha(0.35); bandsBtn:SetEnabled(false)
                    multiRow._lbl:SetAlpha(0.3)
                    multiDis._tip = r.multiBlock; multiDis:Show()
                else
                    multiToggle:SetAlpha(1); multiToggle:SetEnabled(true)
                    bandsBtn:SetAlpha(multiOn and 1 or 0.35); bandsBtn:SetEnabled(multiOn)
                    multiRow._lbl:SetAlpha(0.6)
                    multiDis:Hide()
                end
                if multiOn then
                    threshRow._disTip = "MULTI"; threshDis:Show()
                elseif not entEnabled then
                    threshRow._disTip = nil; threshDis:Show()
                else
                    threshDis:Hide()
                end
                textInsteadDis._tip = r.textBlock
                textInsteadDis:SetShown(r.textBlock ~= nil)
                textInsteadRow._lbl:SetAlpha(r.textBlock and 0.3 or 0.6)

                -- Layout pass: place visible rows top-to-bottom
                for _, rf in ipairs(_allRows) do rf:Hide() end
                local yy = -DPAD
                local function place(rf)
                    rf:ClearAllPoints()
                    PP.Point(rf, "TOPLEFT", detailC, "TOPLEFT", DPAD, yy)
                    PP.Point(rf, "TOPRIGHT", detailC, "TOPRIGHT", -DPAD, yy)
                    rf:Show()
                    yy = yy - (rf._rawH or ROWH) - ROWGAP
                end
                if allowTalent then place(talentRow) end
                if not r.hideHash then place(hashRow) end
                place(threshRow)
                place(multiRow)
                if buffRow then place(buffRow) end
                if spenderRow then place(spenderRow) end
                place(textInsteadRow)
                if barRow and r.barInput then
                    barRow._dis._tip = r.barBlock
                    barRow._dis:SetShown(r.barBlock ~= nil)
                    barRow._lbl:SetAlpha(r.barBlock and 0.3 or 0.6)
                    place(barRow)
                end
            end
            thrPage:Hide()
        end -- BuildFrame

        -- BuildFrame runs lazily on the first ToggleFrame open, not here

        -- Build/Refresh dynamic entry frames
        RefreshSpecEntries = function(scrollToSel)
            UpdateNotice()
            if not specContainer then return end
            local bd = cfg.getBarData(); if not bd then return end
            if not bd.thresholdSpecs then bd.thresholdSpecs = {} end
            local entries = bd.thresholdSpecs

            -- The entry the resolver actually picks in-game right now; seeds the default selection so it opens pre-selected
            local activeIdx
            do
                local resolved = _G._ERB_ResolveThresholdSpecEntry(bd)
                if resolved then
                    for i = 1, #entries do
                        if entries[i] == resolved then activeIdx = i; break end
                    end
                end
            end

            -- Resolve/clamp the selection: active entry, else the first
            if #entries == 0 then
                _selectedIdx = nil
            else
                if _selectedIdx and _selectedIdx > #entries then _selectedIdx = #entries end
                if not _selectedIdx or _selectedIdx < 1 then _selectedIdx = activeIdx or 1 end
            end

            local scrollChild = specContainer._scrollChild
            local curY = 0
            local ENTRY_W = contentHalfSize - 6
            local ENTRY_H = 32

            for i = 1, #_entryFrames do
                if _entryFrames[i] then _entryFrames[i]:Hide() end
            end

            for idx, entry in ipairs(entries) do
                local ef = _entryFrames[idx]
                if not ef then
                    ef = CreateFrame("Button", nil, scrollChild)
                    ef:SetFrameLevel(thrPage:GetFrameLevel() + 2)
                    ef:RegisterForClicks("LeftButtonUp")
                    _entryFrames[idx] = ef

                    local entBg = ef:CreateTexture(nil, "BACKGROUND")
                    entBg:SetAllPoints()
                    entBg:SetColorTexture(1, 1, 1, 0.02)
                    ef._bg = entBg

                    -- Selection accent: left theme-accent bar
                    local accent = ef:CreateTexture(nil, "ARTWORK")
                    accent:SetPoint("TOPLEFT", ef, "TOPLEFT", 0, 0)
                    accent:SetPoint("BOTTOMLEFT", ef, "BOTTOMLEFT", 0, 0)
                    accent:SetWidth(3)
                    accent:Hide()
                    ef._accent = accent

                    local delBtn = CreateFrame("Button", nil, ef)
                    delBtn:SetSize(14, 14)
                    delBtn:SetPoint("RIGHT", ef, "RIGHT", -8, 0)
                    delBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                    local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                    delIcon:SetAllPoints()
                    delIcon:SetTexture(_bandCloseIcon)
                    delIcon:SetAlpha(0.4)
                    delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
                    delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
                    delBtn:SetScript("OnClick", function()
                        local bd2 = cfg.getBarData(); if not (bd2 and ef._entryIdx) then return end
                        table.remove(bd2.thresholdSpecs, ef._entryIdx)
                        local n = #bd2.thresholdSpecs
                        if n == 0 then _selectedIdx = nil
                        elseif _selectedIdx and _selectedIdx > n then _selectedIdx = n end
                        _specDDRefresh()
                        RefreshSpecEntries()
                        RedrawDetail()
                        cfg.refreshFn()
                    end)
                    ef._delBtn = delBtn

                    -- Add-variant duplicates this entry as a talent-gated sibling for the same spec; sits left of the delete X
                    local varBtn = CreateFrame("Button", nil, ef)
                    PP.Size(varBtn, 84, 20)
                    varBtn:SetPoint("RIGHT", delBtn, "LEFT", -10, 0)
                    varBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                    local varBg = varBtn:CreateTexture(nil, "BACKGROUND")
                    varBg:SetAllPoints()
                    varBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                    varBtn._border = EllesmereUI.MakeBorder(varBtn, 1, 1, 1, 0.08, PP)
                    local varLbl = EllesmereUI.MakeFont(varBtn, 11, nil, 1, 1, 1)
                    varLbl:SetText(EllesmereUI.L("Add Variant"))
                    varLbl:SetAlpha(0.65)
                    varLbl:SetPoint("CENTER")
                    varBtn:SetScript("OnEnter", function(self)
                        varBg:SetColorTexture(0.16, 0.16, 0.16, 0.9)
                        varLbl:SetAlpha(0.9)
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Add a talent variant of this entry"))
                    end)
                    varBtn:SetScript("OnLeave", function()
                        varBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        varLbl:SetAlpha(0.65)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    varBtn:SetScript("OnClick", function()
                        if not ef._entryIdx then return end
                        local bd2 = cfg.getBarData(); if not bd2 then return end
                        local specs = bd2.thresholdSpecs
                        local src = specs and specs[ef._entryIdx]; if not src then return end
                        local copy = EllesmereUI.Lite.DeepCopy(src)
                        copy.talentSpellID = nil
                        copy.talentName = nil
                        table.insert(specs, ef._entryIdx + 1, copy)
                        _selectedIdx = ef._entryIdx + 1
                        RefreshSpecEntries()
                        RedrawDetail()
                        cfg.rebuildFn()
                    end)
                    ef._varBtn = varBtn

                    -- Spec/talent group label (class-colored)
                    local specLbl = EllesmereUI.MakeFont(ef, 14, nil, 1, 1, 1)
                    specLbl:SetAlpha(0.85)
                    specLbl:SetPoint("LEFT", ef, "LEFT", 12, 0)
                    specLbl:SetPoint("RIGHT", varBtn, "LEFT", -8, 0)
                    specLbl:SetJustifyH("LEFT")
                    specLbl:SetWordWrap(false)
                    ef._specLbl = specLbl

                    -- Whole row selects this entry: repaint + refresh the detail pane with no list rebuild, so the scroll never jumps
                    ef:SetScript("OnClick", function(self)
                        if not self._entryIdx then return end
                        _selectedIdx = self._entryIdx
                        RepaintRows()
                        RedrawDetail()
                    end)
                    ef:SetScript("OnEnter", function(self)
                        if not self._selected then self._bg:SetColorTexture(1, 1, 1, 0.06) end
                    end)
                    ef:SetScript("OnLeave", function(self)
                        if not self._selected then self._bg:SetColorTexture(1, 1, 1, 0.02) end
                    end)
                end -- end entry frame creation

                ef._entryIdx = idx
                ef:SetSize(ENTRY_W, ENTRY_H)
                ef:ClearAllPoints()
                ef:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, curY)
                ef._yOffset = -curY

                -- Class-color the label from the first specID (entries with no specIDs read "Unknown", in white)
                ef._specLbl:SetText(ns.EntryLabel(entry))
                local classFile
                local firstSID = entry.specIDs and entry.specIDs[1]
                if firstSID == 0 then
                    classFile = _playerClassFile
                elseif firstSID and GetSpecializationInfoByID then
                    local _, _, _, _, _, cf = GetSpecializationInfoByID(firstSID)
                    classFile = cf
                elseif firstSID and EllesmereUI.IS_FOREVER then
                    classFile = EllesmereUI.SpecClassOf(firstSID)
                end
                local cc = classFile and CLASS_COLORS[classFile]
                if cc then ef._specLbl:SetTextColor(cc[1], cc[2], cc[3], 1)
                else ef._specLbl:SetTextColor(1, 1, 1, 1) end

                -- Talent variants are single-spec only: "All Specs"/multi-spec entries span specs, so a talent gate is meaningless. Hide "Add Variant" there and strip any stale gate.
                local ids = entry.specIDs
                local allowTalent = (ids and #ids == 1 and ids[1] ~= 0) and true or false
                ef._varBtn:SetShown(allowTalent)
                if not allowTalent and entry.talentSpellID then
                    entry.talentSpellID = nil
                    entry.talentName = nil
                    cfg.rebuildFn()
                end

                -- Selection highlight; duplicates the resolver can never reach are shadow-dimmed
                PaintRow(ef)
                ef:SetAlpha(ns._ERB_IsThresholdCardShadowed(entries, idx) and 0.45 or 1)

                ef:Show()
                curY = curY - ENTRY_H - ROW_GAP
            end

            local contentH = math.abs(curY) + SIDE_PAD
            scrollChild:SetSize(contentHalfSize, math.max(1, contentH))

            -- Scroll the list to the selected row (on open / add); else keep the offset, pulled back in when a shorter list leaves it past the end (the thumb follows)
            if scrollToSel and _selectedIdx and _entryFrames[_selectedIdx] then
                scrollTo((_entryFrames[_selectedIdx]._yOffset or 0) - 8)
            else
                scrollTo(specContainer._scrollFrame:GetVerticalScroll())
            end
        end

        local function ToggleFrame()
            if not cfg.getBarData() then return end
            if not thrPage then BuildFrame() end
            if thrPage:IsShown() then
                -- Unlock cycle: forces a correct redraw
                if thrPage:GetLeft() ~= nil then
                    thrPage:Hide()
                    return
                end
                thrPage:Hide()
            end
            wipe(_tempSpecSel)
            _specDDRefresh()
            -- Re-pick the resolver's active entry each open, then scroll to it
            _selectedIdx = nil
            RefreshSpecEntries(true)
            RefreshDetail()
            thrPage._reanchor()
            thrPage:Show()
        end

        settingsBtn:SetScript("OnClick", function() ToggleFrame() end)
        -- Close on page switch or main panel close. Hidden inside its page's own
        -- hide, the editor may get no OnHide of its own (the engine's cascade
        -- order decides), so it also leaves the spec / talent watcher here (a
        -- second call does nothing).
        settingsBtn:HookScript("OnHide", function()
            if thrPage and thrPage:IsShown() then thrPage:Hide() end
            if thrPage then ThrEditorHidden(thrPage) end
        end)

        return settingsBtn
    end -- BuildThresholdSettingsButton

    -- Unlock Mode page
    local function BuildUnlockPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "POSITIONING", y);  y = y - h

        _, h = W:Toggle(parent, "Unlock Elements", y,
            function() return EllesmereUI._unlockModeActive or false end,
            function(v)
                if EllesmereUI and EllesmereUI.ToggleUnlockMode then
                    EllesmereUI:ToggleUnlockMode()
                end
            end,
            nil,
            "Opens the shared Unlock Mode to reposition and scale elements"
        );  y = y - h

        _, h = W:Spacer(parent, y, 12);  y = y - h

        _, h = W:SectionHeader(parent, "RESET", y);  y = y - h

        _, h = W:Toggle(parent, "Reset Positions", y,
            function() return false end,
            function()
                local p = DB(); if not p then return end
                p.health.offsetX = 0;   p.health.offsetY = -64;   p.health.unlockPos = nil
                p.primary.offsetX = 0;  p.primary.offsetY = -52; p.primary.unlockPos = nil
                p.secondary.offsetX = 0; p.secondary.offsetY = -38; p.secondary.unlockPos = nil
                p.secondary.countTextUnlockPos = nil
                p.castBar.unlockPos = nil; p.castBar.anchorX = 0; p.castBar.anchorY = -50
                p.gcdBar.unlockPos = nil; p.gcdBar.anchorX = 0; p.gcdBar.anchorY = -78
                Refresh()
            end,
            nil,
            "Click to reset all element positions to defaults"
        );  y = y - h

        return math.abs(y)
    end

    -- Cast Bar preview state
    local _castBarPreviewFill = 0.65
    local _castBarPreviewFrames = {}
    local _castBarPreviewScale = 1

    -- Shuffled spell icon pool for cast bar preview (same spells as nameplates)
    local _castBarIconPool = { 136197, 236802, 135808, 136116, 135735, 136048, 135812, 136075 }
    local _castBarIconIdx = 0
    local function ShuffleCastBarIcons()
        _castBarIconIdx = 0
        for i = #_castBarIconPool, 2, -1 do
            local j = math.random(i)
            _castBarIconPool[i], _castBarIconPool[j] = _castBarIconPool[j], _castBarIconPool[i]
        end
    end
    local function NextCastBarIcon()
        _castBarIconIdx = _castBarIconIdx + 1
        if _castBarIconIdx > #_castBarIconPool then _castBarIconIdx = 1 end
        return _castBarIconPool[_castBarIconIdx]
    end

    -- Rows the Blizzard kit replaces but the classic cast bar leaves to the
    -- user (its background colour and opacity): gated only while Blizzard
    -- Style renders, live under Classic WoW UI. Returns cfg for inline use.
    function ns.ERB_CastBlizzOnlyGate(cfg)
        if EllesmereUI.BlizzStyle.Active("castbar") == "blizzard" then
            return EllesmereUI.BlizzStyle.Gate("castbar", cfg)
        end
        return cfg
    end
    -- Blizzard Style chrome on the preview mock, mirroring the live bar's
    -- ns.ERB_ApplyBlizzCastChrome: the stock frame art round the bar and,
    -- with Spell Text on, the stock text box under it with the spell name
    -- inside; Classic WoW UI seats the vanilla frame instead (no text box).
    -- Regions are created once; off the style both hide. On ns (no new
    -- upvalue for the updater below).
    function ns.ERB_CastPreviewBlizzChrome(pf, cb, barW, blizz)
        if not blizz then
            if pf.blizzFrame then pf.blizzFrame:Hide() end
            if pf.blizzTextBox then pf.blizzTextBox:Hide() end
            return
        end
        if not pf.blizzFrame then
            local af = CreateFrame("Frame", nil, pf.container)
            af:SetAllPoints(pf.container)
            af:SetFrameLevel(pf.container:GetFrameLevel() + 6)
            pf.blizzArt = af
            local fr = af:CreateTexture(nil, "OVERLAY", nil, 2)
            if fr.SetSnapToPixelGrid then fr:SetSnapToPixelGrid(false); fr:SetTexelSnappingBias(0) end
            pf.blizzFrame = fr
            local tb = pf.barFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
            if tb.SetSnapToPixelGrid then tb:SetSnapToPixelGrid(false); tb:SetTexelSnappingBias(0) end
            pf.blizzTextBox = tb
        end
        local fr, tb = pf.blizzFrame, pf.blizzTextBox
        if ns.ERB_CastClassic() then
            -- Classic WoW UI: the vanilla frame round the whole container
            -- (bar plus icon, the live seat); the spell name stays on the bar.
            ns.ERB_SeatClassicChrome(fr, pf.container, cb.height, false, ns.ERB_ClassicFrameK(cb))
            tb:Hide()
            return
        end
        local frameAtlas = ns.ERB_BlizzAtlas("frame")
        if frameAtlas then
            ns.ERB_StockAtlas(fr, frameAtlas)
            fr:ClearAllPoints()
            fr:SetPoint("TOPLEFT", pf.barFrame, "TOPLEFT", -2, 2)
            fr:SetPoint("BOTTOMRIGHT", pf.barFrame, "BOTTOMRIGHT", 2, -2)
            fr:Show()
        else
            fr:Hide()
        end
        local boxAtlas = cb.showSpellText and ns.ERB_BlizzAtlas("textbox")
        if boxAtlas then
            ns.ERB_StockAtlas(tb, boxAtlas)
            tb:ClearAllPoints()
            tb:SetPoint("TOPLEFT", pf.barFrame, "BOTTOMLEFT", 0, 3)
            tb:SetPoint("BOTTOMRIGHT", pf.barFrame, "BOTTOMRIGHT", 0, -13)
            tb:Show()
            local nameText = pf.spellText
            local side = cb.spellTextSide or "left"
            local x, y = cb.spellTextX or 0, cb.spellTextY or 0
            nameText:ClearAllPoints()
            if side == "right" then
                nameText:SetJustifyH("RIGHT")
                nameText:SetPoint("RIGHT", tb, "RIGHT", -8 + x, y)
            elseif side == "center" then
                nameText:SetJustifyH("CENTER")
                nameText:SetPoint("CENTER", tb, "CENTER", x, y)
            else
                nameText:SetJustifyH("LEFT")
                nameText:SetPoint("LEFT", tb, "LEFT", 8 + x, y)
            end
            nameText:SetWidth(math.max(10, (barW or cb.width or 220) - 16))
        else
            tb:Hide()
        end
    end

    local function UpdateCastBarPreview()
        local p = DB()
        if not p then return end
        local cb = p.castBar
        local pf = _castBarPreviewFrames

        if not pf.bar then return end
        -- Blizzard Style (latched per session, like the live bar): the stock
        -- art on the same mock -- the icon spanning the text box, no EUI
        -- border, stock background, fill and pip, frame art and the spell
        -- name inside the text box. Everything else stays the EUI mock.
        local blizz = (ns.ERB_CastBlizz and ns.ERB_CastBlizz()) or false
        -- classic = Classic WoW UI (the vanilla frame and spark round the
        -- user's fill); blizzKit = the 12.1 kit (stock background, fill, pip
        -- and text box). Shared stock-mode geometry stays on blizz.
        local classic = (ns.ERB_CastClassic and ns.ERB_CastClassic()) or false
        local blizzKit = blizz and not classic

        -- Snap helper: round to the preview container's physical pixel grid
        local cScale = pf.container:GetEffectiveScale()
        if cScale <= 0 then cScale = 1 end
        local onePx = EllesmereUI.PP.perfect / cScale
        local function Snap(val)
            return math.floor(val / onePx + 0.5) * onePx
        end

        local w, h = Snap(cb.width), Snap(cb.height)
        local bs = cb.borderSize

        -- Container size: icon (hxh) + bar (only when icon shown)
        local hasIcon = cb.showIcon ~= false and not ns.ERB_CastIconPortrait(cb)
        local iconFree = ns.ERB_CastIconFree(cb)
        local iconW = (hasIcon and not iconFree) and Snap(blizz and ns.ERB_CastIconW(cb) or h) or 0
        pf.container:SetSize(w + iconW, h)

        -- Scale down to fit when the cast bar is wider than the panel
        local PAD = EllesmereUI.CONTENT_PAD
        local hdr = pf.container:GetParent()
        local availW = (hdr:GetWidth() - PAD * 2) / _castBarPreviewScale
        local fitScale = 1
        if (w + iconW) > availW and (w + iconW) > 0 and availW > 0 then
            fitScale = availW / (w + iconW)
        end
        pf.container:SetScale(_castBarPreviewScale * fitScale)

        pf.container:ClearAllPoints(); pf.container:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        -- Dimmed while the bar is off, like the page's greyed controls; no
        -- click then leads to those rows.
        local cbOn = cb.enabled and true or false
        PreviewBar.Lock(pf.container, cbOn, pf.hits)
        PreviewBar.HintFor(cbOn, hdr)
        -- Bar frame (sits beside the icon; iconOnRight puts the icon on the right)
        local iconOnRight = hasIcon and cb.iconOnRight
        pf.barFrame:SetSize(w, h)
        pf.barFrame:ClearAllPoints()
        pf.barFrame:SetPoint("LEFT", pf.container, "LEFT", iconOnRight and 0 or iconW, 0)

        -- Background
        local texKey = cb.texture
        -- Textured Background: back to the plain background before a branch repaints it.
        if pf.bg._erbBgTex then ns.ERB_BgTexture(pf.bg, nil) end
        if blizzKit then
            -- The retail background under WoW Forever too, as live.
            local bgAtlas = ns.ERB_BlizzAtlas("bg")
            if bgAtlas then
                EllesmereUI.StockAtlas(pf.bg, bgAtlas)
            else
                pf.bg:SetTexture(nil)
                pf.bg:SetColorTexture(0, 0, 0, 0.7)
            end
            pf.bg:ClearAllPoints()
            pf.bg:SetPoint("TOPLEFT", pf.barFrame, "TOPLEFT", -1, 1)
            pf.bg:SetPoint("BOTTOMRIGHT", pf.barFrame, "BOTTOMRIGHT", 1, -1)
        elseif texKey == "blizzard" then
            -- As live: Classic WoW UI takes the retail background on WoW Forever.
            if classic then
                ns.ERB_StockAtlas(pf.bg, "UI-CastingBar-Background", true)
            else
                pf.bg:SetAtlas("UI-CastingBar-Background", true)
            end
            pf.bg:ClearAllPoints()
            pf.bg:SetAllPoints(pf.barFrame)
        else
            pf.bg:SetTexture(nil)
            pf.bg:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
            -- Textured Background: flat while Fill Color is below 100, as live.
            if cb.textureBg and (cb.fillOpacity or 100) >= 100 then
                ns.ERB_BgTexture(pf.bg, EllesmereUI.ResolveTexturePath(_G._ERB_CastBarTextures, texKey, nil), cb.bgR, cb.bgG, cb.bgB, cb.bgA)
            end
            pf.bg:ClearAllPoints()
            pf.bg:SetAllPoints(pf.barFrame)
        end

        -- Border wraps container (bar + icon) - PP or textured via ApplyBorderStyle
        if pf.container._border then
            pf.container._border:SetFrameLevel(cb.borderBehind and math.max(0, pf.container:GetFrameLevel() - 1) or (pf.container:GetFrameLevel() + 5))
            local pbs = blizz and 0 or (cb.borderSize or 0)
            local pbpx = (not blizz) and EllesmereUI.BorderPx(cb.borderSizePx, pbs, cb.borderTexture or "solid") or nil
            -- Extend Top / Extend Bottom, as the live bar draws them (none under a stock style).
            ns.ERB_AnchorBorderHost(pf.container._border, pf.container, ns.ERB_BorderExtents((not blizz) and cb or nil))
            EllesmereUI.ApplyBorderStyle(pf.container._border, pbs,
                cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1,
                cb.borderTexture or "solid", cb.borderTextureOffset, cb.borderTextureOffsetY,
                cb.borderTextureShiftX, cb.borderTextureShiftY, "resourcebars", pbs, nil, pbpx)
        end
        -- Bottom Separator, as the live bar draws it (none under a stock style or a Solid border).
        ns.ERB_Separators(pf.container, cb, (cb.edgeSep and not blizz and ns.ERB_Textured(cb)) and true or false,
            pf.container:GetFrameLevel() + 7)

        -- Status bar: full bar frame, no inset
        pf.bar:ClearAllPoints()
        pf.bar:SetAllPoints(pf.barFrame)
        pf.bar:SetValue(_castBarPreviewFill)

        -- Bar texture
        local texLookup = _G._ERB_CastBarTextures or {}
        local texPath = texLookup[texKey]
        if blizzKit then
            pf.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            pf.bar:GetStatusBarTexture():SetAtlas(ns.ERB_BlizzAtlas("cast") or "UI-CastingBar-Fill")
        elseif texKey == "blizzard" then
            pf.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            pf.bar:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        elseif texPath then
            pf.bar:SetStatusBarTexture(texPath)
        else
            pf.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end

        -- Bar color / gradient
        local fillTex = pf.bar:GetStatusBarTexture()
        local fR, fG, fB, fA = cb.fillR, cb.fillG, cb.fillB, 1
        if cb.classColored == true then
            local _, cf = UnitClass("player")
            local cc = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
            if cc then fR, fG, fB = cc.r, cc.g, cc.b end
        end
        local fillOp = (cb.fillOpacity or 100) / 100
        if blizzKit then
            -- The stock fill art is pre-coloured; the live bar skips its colour pass too.
            fillTex:SetVertexColor(1, 1, 1, 1)
        elseif cb.gradientEnabled then
            local dir = cb.gradientDir or "HORIZONTAL"
            fillTex:SetGradient(dir, CreateColor(fR, fG, fB, fA * fillOp), CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA * fillOp))
        else
            fillTex:SetVertexColor(fR, fG, fB, fA * fillOp)
        end
        -- Mirror the live bar's Fill Opacity bg behavior: below 100 the bg covers only the empty portion so the translucent fill shows what's behind the bar; at 100 it spans the whole bar frame.
        if texKey ~= "blizzard" and not blizzKit then
            pf.bg:ClearAllPoints()
            if (cb.fillOpacity or 100) < 100 then
                pf.bg:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
                pf.bg:SetPoint("BOTTOMRIGHT", pf.barFrame, "BOTTOMRIGHT", 0, 0)
            else
                pf.bg:SetAllPoints(pf.barFrame)
            end
        end

        -- Spark: under the style the stock pip replaces the spark art (once,
        -- drawn plain; the EUI spark art is additive).
        if blizzKit and not pf.blizzSpark then
            local pip = ns.ERB_BlizzAtlas("spark")
            if pip then
                pf.blizzSpark = true
                pf.spark:SetAtlas(pip)
                pf.spark:SetBlendMode("BLEND")
            end
        end
        -- Classic WoW UI: the vanilla spark file (additive, like the EUI art) once.
        -- It stands taller than the bar and draws over the frame art
        -- (container +6) as live does, so it moves to its own host above it.
        if classic and not pf.classicSpark then
            pf.classicSpark = true
            pf.spark:SetTexture(ns.ERB_CLASSIC.spark)
            local host = CreateFrame("Frame", nil, pf.barFrame)
            host:SetAllPoints(pf.bar)
            host:SetFrameLevel(pf.container:GetFrameLevel() + 8)
            pf.spark:SetParent(host)
        end
        if cb.showSpark then
            -- The vanilla spark is a square scaled with the bar, centred a
            -- little above the bar's centre line (the live bar's numbers).
            local sparkY = 0
            if classic then
                local C = ns.ERB_CLASSIC
                local ss = C.sparkSize * h / C.barH
                pf.spark:SetSize(ss, ss)
                sparkY = C.sparkY * h / C.barH
            else
                pf.spark:SetSize(8, h)
            end
            pf.spark:ClearAllPoints()
            pf.spark:SetPoint("CENTER", fillTex, "RIGHT", 0, sparkY)
            pf.spark:Show()
        else
            pf.spark:Hide()
        end

        -- Icon: left or right side of container, full size
        do
            -- Under the style the icon also spans the text box (the live
            -- bar's ns.ERB_CastIconW) and shows the full spell art.
            local iSize = Snap(blizz and ns.ERB_CastIconW(cb) or h)
            pf.iconFrame:SetSize(iSize, iSize)
            if pf.icon then
                if blizz then pf.icon:SetTexCoord(0, 1, 0, 1) else pf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            end
            -- Classic WoW UI keeps the icon under the frame art (container
            -- +6), inside the frame's window beside the bar, as live does.
            if classic then pf.iconFrame:SetFrameLevel(pf.container:GetFrameLevel() + 1) end
            pf.iconFrame:ClearAllPoints()
            if iconOnRight then
                pf.iconFrame:SetPoint("TOPRIGHT", pf.container, "TOPRIGHT", 0, 0)
            else
                pf.iconFrame:SetPoint("TOPLEFT", pf.container, "TOPLEFT", 0, 0)
            end
            ns.ERB_LayoutFreeCastIcon(pf.iconFrame, pf.container, cb, iconFree)
            if hasIcon then pf.iconFrame:Show() else pf.iconFrame:Hide() end
        end

        -- Icon/bar seam divider preview: mirrors the live cast bar's onePixel
        -- math (PP.perfect / effective scale), NOT the widget-local Snap()
        -- helper above -- the border itself already renders through that same
        -- shared PP system (ApplyBorderStyle -> SnapBorderTextures), so the
        -- divider has to match it, not the panel's own pixel grid.
        if pf.iconDivider then
            -- Border Art Divider, as the live bar draws it.
            local showDivider = hasIcon and not iconFree and cb.showIconDivider
            if ns.ERB_CastDividerArt(pf.iconDivider, showDivider, pf.iconFrame, iconOnRight, cb, blizz) then
                pf.iconDivider:Show()
            elseif showDivider then
                local PPp = EllesmereUI.PP
                local des = pf.container:GetEffectiveScale()
                local onePixel = (PPp and des > 0) and (PPp.perfect / des) or 1
                local dbs = cb.borderSize or 1
                -- Same rule as the live divider: an exact SOLID size drives it, textured keeps the step.
                local dtex = cb.borderTexture
                if not blizz and (not dtex or dtex == "" or dtex == "solid") then
                    dbs = EllesmereUI.BorderPx(cb.borderSizePx, cb.borderSize or 0, dtex) or dbs
                end
                pf.iconDivider:ClearAllPoints()
                pf.iconDivider:SetWidth(math.max(onePixel, math.floor(dbs + 0.5) * onePixel))
                if iconOnRight then
                    pf.iconDivider:SetPoint("TOPRIGHT", pf.iconFrame, "TOPLEFT", 0, 0)
                    pf.iconDivider:SetPoint("BOTTOMRIGHT", pf.iconFrame, "BOTTOMLEFT", 0, 0)
                else
                    pf.iconDivider:SetPoint("TOPLEFT", pf.iconFrame, "TOPRIGHT", 0, 0)
                    pf.iconDivider:SetPoint("BOTTOMLEFT", pf.iconFrame, "BOTTOMRIGHT", 0, 0)
                end
                pf.iconDivider:SetColorTexture(cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1)
                pf.iconDivider:Show()
            else
                pf.iconDivider:Hide()
            end
        end

        -- Cast text side-aware layout (mirrors the live cast bar)
        local cbTimerW   = (cb.timerSize or 11) * 2.2
        local cbDurSide   = cb.timerSide or "right"
        local cbSpellSide = cb.spellTextSide or "left"
        local cbBarW = pf.bar:GetWidth() or 0
        -- Timer / duration text
        if cb.showTimer then
            SetPVFont(pf.timerText, FONT_PATH, cb.timerSize or 11)
            local pt, xb, jh = ns.GetCastTextAnchor(cbDurSide, false, cbTimerW)
            pf.timerText:ClearAllPoints()
            pf.timerText:SetJustifyH(jh)
            pf.timerText:SetPoint(pt, pf.bar, pt, xb + (cb.timerX or 0), cb.timerY or 0)
            -- Preview total cast time is 3.0s; mirror the live "elapsed / total" mode.
            if cb.showTotalDuration then
                pf.timerText:SetText(string.format("%.1f / %.1f", 3.0 * _castBarPreviewFill, 3.0))
            else
                pf.timerText:SetText(string.format("%.1f", 3.0 * (1 - _castBarPreviewFill)))
            end
            pf.timerText:Show()
            ns.ERB_CastTextColor(pf.timerText, cb.timerR, cb.timerG, cb.timerB, cb.timerA)
        else
            pf.timerText:Hide()
        end

        -- Spell name text
        if cb.showSpellText then
            SetPVFont(pf.spellText, FONT_PATH, cb.spellTextSize or 11)
            if blizzKit and ns.ERB_BlizzAtlas("textbox") then
                -- Placed inside the stock text box by the chrome pass below.
            else
                local pt, xb, jh = ns.GetCastTextAnchor(cbSpellSide, cb.showTimer and cbDurSide == cbSpellSide, cbTimerW)
                pf.spellText:ClearAllPoints()
                pf.spellText:SetJustifyH(jh)
                pf.spellText:SetPoint(pt, pf.bar, pt, xb + (cb.spellTextX or 0), cb.spellTextY or 0)
                if cbSpellSide == "center" then
                    pf.spellText:SetWidth(cbBarW - 8 - (cb.showTimer and 2 * cbTimerW or 0))
                elseif cbBarW > 0 then
                    pf.spellText:SetWidth(cbBarW - 8 - (cb.showTimer and cbTimerW or 0))
                end
            end
            pf.spellText:SetText(EllesmereUI.L("Spell Name"))
            pf.spellText:Show()
            ns.ERB_CastTextColor(pf.spellText, cb.spellTextR, cb.spellTextG, cb.spellTextB, cb.spellTextA)
        else
            pf.spellText:Hide()
        end
        -- Blizzard Style chrome: frame art, and the text box with the spell name in it.
        ns.ERB_CastPreviewBlizzChrome(pf, cb, cbBarW, blizz)
        -- Re-flow so a live JustifyH change takes effect on already-rendered text.
        ns.ReflowFontString(pf.timerText)
        ns.ReflowFontString(pf.spellText)

        -- Update header height: 80px preview + optional hint text
        PreviewBar.SizeHeader(hdr, 80)
    end

    local _castBarPreviewBuilder = function(hdr, hdrW)
        HintBuildStart(PAGE_CASTBAR, hdr)
        local p = DB()
        if not p then return 0 end
        local cb = p.castBar

        local previewScale = UIParent:GetEffectiveScale() / hdr:GetEffectiveScale()
        _castBarPreviewScale = previewScale

        local container = CreateFrame("Frame", nil, hdr)
        container:SetPoint("CENTER", hdr, "CENTER", 0, 0)

        -- Snap helper: round to the preview container's physical pixel grid (use previewScale for initial snap; adjusted below if we scale-to-fit)
        local cScale = UIParent:GetEffectiveScale()
        if cScale <= 0 then cScale = 1 end
        local onePx = EllesmereUI.PP.perfect / cScale
        local function Snap(val)
            return math.floor(val / onePx + 0.5) * onePx
        end

        local w, h = Snap(cb.width), Snap(cb.height)
        local hasIcon = cb.showIcon ~= false and not ns.ERB_CastIconPortrait(cb)
        local iconW = hasIcon and Snap(h) or 0

        -- Scale down to fit when the cast bar is wider than the panel
        local PAD = EllesmereUI.CONTENT_PAD
        local availW = (hdrW - PAD * 2) / previewScale
        local fitScale = 1
        if (w + iconW) > availW and (w + iconW) > 0 and availW > 0 then
            fitScale = availW / (w + iconW)
        end
        container:SetScale(previewScale * fitScale)

        container:SetSize(w + iconW, h)

        -- Bar frame (holds bg, status bar)
        local barFrame = CreateFrame("Frame", nil, container)
        barFrame:SetSize(w, h)
        barFrame:SetPoint("LEFT", container, "LEFT", iconW, 0)
        -- Fresh mocks: the style chrome memos (frame art, text box and the
        -- spark swaps) belong to the previous build's frames; drop them so
        -- the next update re-creates the chrome on these.
        local pf = _castBarPreviewFrames
        if pf.blizzArt then pf.blizzArt:Hide() end
        if pf.blizzTextBox then pf.blizzTextBox:Hide() end
        pf.blizzArt, pf.blizzFrame, pf.blizzTextBox, pf.blizzSpark, pf.classicSpark = nil, nil, nil, nil, nil
        pf.barFrame = barFrame
        pf.container = container

        -- Border: dedicated child frame covering bar + icon (PP or textured)
        local bdrFrame = CreateFrame("Frame", nil, container)
        bdrFrame:SetAllPoints(container)
        bdrFrame:SetFrameLevel(container:GetFrameLevel() + 5)
        container._border = bdrFrame
        ns.ERB_AnchorBorderHost(bdrFrame, container, ns.ERB_BorderExtents((not ns.ERB_CastBlizz()) and cb or nil))
        EllesmereUI.ApplyBorderStyle(bdrFrame, cb.borderSize or 0,
            cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1,
            cb.borderTexture or "solid", cb.borderTextureOffset, cb.borderTextureOffsetY,
            cb.borderTextureShiftX, cb.borderTextureShiftY, "resourcebars", cb.borderSize or 0,
            nil, EllesmereUI.BorderPx(cb.borderSizePx, cb.borderSize or 0, cb.borderTexture or "solid"))
        -- Bottom Separator, as the live bar draws it.
        ns.ERB_Separators(container, cb, (cb.edgeSep and not ns.ERB_CastBlizz() and ns.ERB_Textured(cb)) and true or false,
            container:GetFrameLevel() + 7)

        -- Background (full bar area, no inset)
        local bg = barFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local texKey = cb.texture
        if texKey == "blizzard" then
            if ns.ERB_CastClassic() then
                ns.ERB_StockAtlas(bg, "UI-CastingBar-Background", true)
            else
                bg:SetAtlas("UI-CastingBar-Background", true)
            end
        else
            bg:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
            -- Textured Background, as live (never under the Blizzard Style kit).
            if cb.textureBg and (cb.fillOpacity or 100) >= 100 and not (ns.ERB_CastBlizz() and not ns.ERB_CastClassic()) then
                ns.ERB_BgTexture(bg, EllesmereUI.ResolveTexturePath(_G._ERB_CastBarTextures, texKey, nil), cb.bgR, cb.bgG, cb.bgB, cb.bgA)
            end
        end
        _castBarPreviewFrames.bg = bg

        -- Status bar (full bar area, no inset)
        local bar = CreateFrame("StatusBar", nil, barFrame)
        bar:SetAllPoints()
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(_castBarPreviewFill)

        local texLookup = _G._ERB_CastBarTextures or {}
        local texPath = texLookup[texKey]
        if texKey == "blizzard" then
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            bar:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        elseif texPath then
            bar:SetStatusBarTexture(texPath)
        else
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end

        local fillTex = bar:GetStatusBarTexture()
        if cb.gradientEnabled then
            local dir = cb.gradientDir or "HORIZONTAL"
            fillTex:SetGradient(dir, CreateColor(cb.fillR, cb.fillG, cb.fillB, 1), CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA))
        else
            fillTex:SetVertexColor(cb.fillR, cb.fillG, cb.fillB, 1)
        end
        _castBarPreviewFrames.bar = bar

        -- Spark
        local spark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
        spark:SetBlendMode("ADD")
        spark:SetSize(8, h)
        spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
        if not cb.showSpark then spark:Hide() end
        _castBarPreviewFrames.spark = spark

        -- Icon: left side of container, full size
        local iconFrame = CreateFrame("Frame", nil, container)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(NextCastBarIcon())
        local iSize = Snap(h)
        iconFrame:SetSize(iSize, iSize)
        iconFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        if not hasIcon then iconFrame:Hide() end
        _castBarPreviewFrames.iconFrame = iconFrame
        _castBarPreviewFrames.icon = icon

        -- Icon/bar seam divider (mirrors the live cast bar's "Show Icon
        -- Divider"): parented to bdrFrame, same reasoning as the live one --
        -- a texture on container itself would sit below the icon/bar child
        -- frames regardless of draw layer.
        local iconDivider = bdrFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        iconDivider:Hide()
        _castBarPreviewFrames.iconDivider = iconDivider

        -- Texts ride an overlay above everything the mock draws (border +5,
        -- style frame art +6, icon +7, spark host +8), as the live bar keeps
        -- its texts; their anchors stay on the bar.
        local textFrame = CreateFrame("Frame", nil, barFrame)
        textFrame:SetAllPoints(bar)
        textFrame:SetFrameLevel(container:GetFrameLevel() + 9)

        -- Timer text
        local timerText = textFrame:CreateFontString(nil, "OVERLAY")
        SetPVFont(timerText, FONT_PATH, cb.timerSize or 11)
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4 + (cb.timerX or 0), cb.timerY or 0)
        timerText:SetJustifyH("RIGHT")
        if cb.showTimer then
            if cb.showTotalDuration then
                timerText:SetText(string.format("%.1f / %.1f", 3.0 * _castBarPreviewFill, 3.0))
            else
                timerText:SetText(string.format("%.1f", 3.0 * (1 - _castBarPreviewFill)))
            end
        else
            timerText:Hide()
        end
        ns.ERB_CastTextColor(timerText, cb.timerR, cb.timerG, cb.timerB, cb.timerA)
        _castBarPreviewFrames.timerText = timerText

        -- Spell name text
        local spellText = textFrame:CreateFontString(nil, "OVERLAY")
        SetPVFont(spellText, FONT_PATH, cb.spellTextSize or 11)
        spellText:SetPoint("LEFT", bar, "LEFT", 4 + (cb.spellTextX or 0), cb.spellTextY or 0)
        spellText:SetJustifyH("LEFT")
        if cb.showSpellText then
            spellText:SetText(EllesmereUI.L("Spell Name"))
        else
            spellText:Hide()
        end
        ns.ERB_CastTextColor(spellText, cb.spellTextR, cb.spellTextG, cb.spellTextB, cb.spellTextA)
        _castBarPreviewFrames.spellText = spellText

        -- Create hit overlays for preview click-to-scroll (kept for the
        -- bar-off state: dimmed, no clicks)
        wipe(_hitOverlays)
        local hits = {}
        pf.hits = hits
        local overlayLevel = container:GetFrameLevel() + 20
        hits[#hits + 1] = CreateHitOverlay(barFrame, "castBar", overlayLevel)
        hits[#hits + 1] = CreateHitOverlay(iconFrame, "castIcon", overlayLevel + 5)
        if cb.showTimer then
            local ttHit = CreateFrame("Frame", nil, bar)
            ttHit:SetPoint("TOPLEFT", timerText, "TOPLEFT", -2, 2)
            ttHit:SetPoint("BOTTOMRIGHT", timerText, "BOTTOMRIGHT", 2, -2)
            hits[#hits + 1] = CreateHitOverlay(ttHit, "castTimer", overlayLevel + 5)
        end
        if cb.showSpellText then
            local stHit = CreateFrame("Frame", nil, bar)
            stHit:SetPoint("TOPLEFT", spellText, "TOPLEFT", -2, 2)
            stHit:SetPoint("BOTTOMRIGHT", spellText, "BOTTOMRIGHT", 2, -2)
            hits[#hits + 1] = CreateHitOverlay(stHit, "castSpellText", overlayLevel + 5)
        end
        PreviewBar.Lock(container, cb.enabled and true or false, hits)

        -- Hint text: made even while the bar is off, shown only while it is on
        -- (nothing to click otherwise), so switching the bar on can show it.
        local TOTAL_H = 80
        _headerBaseH = TOTAL_H
        local hintShown = not IsPreviewHintDismissed()
        if hintShown then
            if not _previewHintFS then
                -- Held across builds and pages (module state): out of its header's pool.
                local hintHost = PoolKeep(CreateFrame("Frame", nil, hdr))
                hintHost:SetAllPoints(hdr)
                _previewHintFS = EllesmereUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
            end
            -- The host is kept across builds: one level above the header, as a new one sits.
            local host = _previewHintFS:GetParent()
            host:SetParent(hdr)
            host:SetFrameLevel(hdr:GetFrameLevel() + 1)
            host:Show()
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 20)
            _previewHintFS:SetShown(cb.enabled and true or false)
            if cb.enabled then TOTAL_H = TOTAL_H + 35 end
        elseif _previewHintFS then
            _previewHintFS:Hide()
        end

        return TOTAL_H
    end

    -- Textured Background: the Texture Settings cog row, one per bar kind, shared
    -- by the module pages and Global Settings > Textures. apply: the page's own
    -- refresh after a write.
    local TEXBG_KINDS = {
        bars = { tbl = "general", key = "barTextureBg", tex = "barTexture",
                 need = "This option requires a Texture other than None." },
        cast = { tbl = "castBar", key = "textureBg", tex = "texture", blizz = true,
                 need = "This option requires a Bar Texture other than None or Blizzard." },
        gcd  = { tbl = "gcdBar", key = "textureBg", tex = "texture",
                 need = "This option requires a Bar Texture other than None." },
    }
    local function TexBgRowCfg(kind, apply)
        local k = TEXBG_KINDS[kind]
        return { type = "toggle", label = "Textured Background",
            tooltip = "Draws the bar texture on the background too.",
            disabled = function()
                local p = DB(); local t = p and p[k.tbl]
                if not t then return true end
                -- Split textures: the health and power bars may carry their own.
                if kind == "bars" and p.splitTex == true then return false end
                local tx = t[k.tex] or "none"
                return tx == "none" or (k.blizz == true and tx == "blizzard")
            end,
            disabledTooltip = k.need,
            get = function() local p = DB(); local t = p and p[k.tbl]; return (t and t[k.key]) or false end,
            set = function(v)
                local p = DB(); local t = p and p[k.tbl]; if not t then return end
                t[k.key] = v and true or false
                apply()
            end }
    end

    -- Shared helpers for the section and page builders under ResourceBars_Options\
    -- (loaded before this file, read when a page builds). Preview state stays
    -- here; the pages write it through the two setters.
    ns._ERB_OptEnv = {
        TexBgRowCfg = TexBgRowCfg,
        DB = DB, PP = PP, Refresh = Refresh,
        SmoothRefresh = SmoothRefresh, RefreshHealth = RefreshHealth, RebuildHealth = RebuildHealth,
        AddFormBarBtn = AddFormBarBtn, AddFormTextBtn = AddFormTextBtn,
        BuildHashCog = BuildHashCog, BuildThresholdSettingsButton = BuildThresholdSettingsButton, RefreshPower = RefreshPower,
        RebuildPower = RebuildPower, RefreshClass = RefreshClass, RebuildClass = RebuildClass,
        BAND_REPLACES_TIP = BAND_REPLACES_TIP, STAGGER_PCT_TIP = STAGGER_PCT_TIP, CLASS_COLORS = CLASS_COLORS,
        _clickMappings = _clickMappings, _previewHeaderBuilder = _previewHeaderBuilder, CLASSIC_SYNC_KEYS = CLASSIC_SYNC_KEYS,
        CLASSIC_MATCH_KEYS = CLASSIC_MATCH_KEYS, ShuffleCastBarIcons = ShuffleCastBarIcons, UpdateCastBarPreview = UpdateCastBarPreview,
        _castBarPreviewBuilder = _castBarPreviewBuilder, UpdatePreviewHeader = UpdatePreviewHeader, PreviewAvail = PreviewBar.Avail,
        SetDisplayPreviewValues = function(pipCount, fillPct)
            _previewPipCount = pipCount
            _previewBarFillPct = fillPct
        end,
        SetCastBarPreviewFill = function(v) _castBarPreviewFill = v end,
    }

    -- GCD Bar preview: one static mock of the bar at a random fill, styled
    -- from p.gcdBar the way BuildGCDBar paints the live bar. Always
    -- horizontal like the bar stack preview (Horizontal (Left) keeps its
    -- fill direction); a vertical bar shows at its configured size laid flat.
    do
        local env = ns._ERB_OptEnv
        local GCD_PREVIEW_H = 80

        -- The shared preview hint on a GCD or Totem Bar header build, as the
        -- Cast Bar header places it. Returns the height it adds.
        -- Made even while the preview is off (shown only while on), so
        -- switching the bar on can show it.
        local function PlaceHint(hdr, on)
            if IsPreviewHintDismissed() then
                if _previewHintFS then _previewHintFS:Hide() end
                return 0
            end
            if not _previewHintFS then
                -- Held across builds and pages (module state): out of its header's pool.
                local hintHost = PoolKeep(CreateFrame("Frame", nil, hdr))
                hintHost:SetAllPoints(hdr)
                _previewHintFS = EllesmereUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
            end
            local host = _previewHintFS:GetParent()
            host:SetParent(hdr)
            host:SetFrameLevel(hdr:GetFrameLevel() + 1)
            host:Show()
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 20)
            _previewHintFS:SetShown(on and true or false)
            return on and 35 or 0
        end

        local gcdFill = 0.6
        local pf = {}

        -- building: the header build itself (it returns the height); any
        -- other update resizes the shown header for the hint.
        local function UpdateGCDPreview(building)
            local p = DB()
            if not (p and pf.bar) then return end
            local g = p.gcdBar
            local container = pf.container
            local hdr = container:GetParent()

            -- Scale down to fit when the bar is wider than the panel; snap on
            -- the grid of that final scale.
            local rawW = g.width or 220
            local PAD = EllesmereUI.CONTENT_PAD
            local availW = ((pf.hdrW or hdr:GetWidth()) - PAD * 2) / pf.scale
            local fitScale = 1
            if rawW > availW and rawW > 0 and availW > 0 then fitScale = availW / rawW end
            container:SetScale(pf.scale * fitScale)
            local cScale = container:GetEffectiveScale()
            if cScale <= 0 then cScale = 1 end
            local onePx = EllesmereUI.PP.perfect / cScale
            local function Snap(val)
                return math.floor(val / onePx + 0.5) * onePx
            end
            local w, h = Snap(rawW), Snap(g.height or 12)
            container:SetSize(w, h)
            container:ClearAllPoints(); container:SetPoint("CENTER", hdr, "CENTER", 0, 0)
            local on = g.enabled and true or false
            PreviewBar.Lock(container, on, pf.hits)
            if not building then
                PreviewBar.HintFor(on, hdr)
                PreviewBar.SizeHeader(hdr, GCD_PREVIEW_H)
            end

            -- Border + Bottom Separator, as BuildGCDBar
            local bdr = pf.border
            local bs = g.borderSize or 0
            bdr:SetFrameLevel(g.borderBehind and math.max(0, container:GetFrameLevel() - 1) or (container:GetFrameLevel() + 5))
            ns.ERB_AnchorBorderHost(bdr, container, ns.ERB_BorderExtents(g))
            EllesmereUI.ApplyBorderStyle(bdr, bs,
                g.borderR or 0, g.borderG or 0, g.borderB or 0, g.borderA or 1,
                g.borderTexture or "solid", g.borderTextureOffset, g.borderTextureOffsetY,
                g.borderTextureShiftX, g.borderTextureShiftY, "resourcebars", bs,
                nil, EllesmereUI.BorderPx(g.borderSizePx, bs, g.borderTexture or "solid"))
            ns.ERB_Separators(container, g, (g.edgeSep and ns.ERB_Textured(g)) and true or false,
                container:GetFrameLevel() + 7)

            -- Texture + background (Textured Background included)
            local bar, bg = pf.bar, pf.bg
            -- The live fill inset inside a border: one physical pixel, on this grid.
            local inset = bs > 0 and onePx or 0
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -inset)
            bar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -inset, inset)
            bar:SetStatusBarTexture(EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, g.texture, "Interface\\Buttons\\WHITE8x8"))
            bg:SetTexture(nil)
            bg:SetColorTexture(g.bgR, g.bgG, g.bgB, g.bgA)
            if g.textureBg or bg._erbBgTex then
                ns.ERB_BgTexture(bg, g.textureBg and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, g.texture, nil),
                    g.bgR, g.bgG, g.bgB, g.bgA)
            end

            local leftward = g.orientation == "HORIZONTAL_LEFT"
            bar:SetReverseFill(leftward)
            bar:SetValue(gcdFill)

            -- Fill color / gradient
            local fillTex = bar:GetStatusBarTexture()
            local fR, fG, fB, fA = g.fillR, g.fillG, g.fillB, g.fillA or 1
            if g.classColored then
                local _, cf = UnitClass("player")
                local cc = cf and CLASS_COLORS[cf]
                if cc then fR, fG, fB = cc[1], cc[2], cc[3] end
            end
            if g.gradientEnabled then
                fillTex:SetGradient(g.gradientDir or "HORIZONTAL", CreateColor(fR, fG, fB, fA),
                    CreateColor(g.gradientR, g.gradientG, g.gradientB, g.gradientA or 1))
            else
                fillTex:SetVertexColor(fR, fG, fB, fA)
            end

            -- Spark on the fill's leading edge
            local spark = pf.spark
            if g.showSpark then
                spark:SetSize(8, h)
                spark:ClearAllPoints()
                spark:SetPoint("CENTER", fillTex, leftward and "LEFT" or "RIGHT", 0, 0)
                spark:Show()
            else
                spark:Hide()
            end
        end

        env.UpdateGCDPreview = UpdateGCDPreview
        env.SetGCDPreviewFill = function(v) gcdFill = v end

        env._gcdPreviewBuilder = function(hdr, hdrW)
            HintBuildStart(PAGE_GCD, hdr)
            local p = DB()
            if not p then return 0 end

            -- Pixel sizes match the live bar: the panel's scale against UIParent's.
            pf.scale = UIParent:GetEffectiveScale() / hdr:GetEffectiveScale()

            local container = CreateFrame("Frame", nil, hdr)
            container:SetPoint("CENTER", hdr, "CENTER", 0, 0)
            container:SetScale(pf.scale)
            pf.container = container

            local bg = container:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            pf.bg = bg

            local bar = CreateFrame("StatusBar", nil, container)
            bar:SetMinMaxValues(0, 1)
            bar:SetOrientation("HORIZONTAL")
            bar:SetRotatesTexture(false)
            bar:SetFrameLevel(container:GetFrameLevel() + 1)
            pf.bar = bar

            local spark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
            spark:SetTexture(ns.SPARK_TEX or "Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
            spark:SetBlendMode("ADD")
            pf.spark = spark

            local bdrFrame = CreateFrame("Frame", nil, container)
            bdrFrame:SetAllPoints(container)
            pf.border = bdrFrame

            wipe(_hitOverlays)
            pf.hits = { CreateHitOverlay(container, "gcdBar", container:GetFrameLevel() + 20) }

            -- Width is known only once hdr is laid out: fit against hdrW for this pass.
            pf.hdrW = hdrW
            UpdateGCDPreview(true)
            pf.hdrW = nil

            _headerBaseH = GCD_PREVIEW_H
            return GCD_PREVIEW_H + PlaceHint(hdr, p.gcdBar.enabled)
        end

        env.RestoreGCDPreview = function()
            gcdFill = math.random(30, 85) / 100
            -- Header shown again from the cache: take the hint back before the update sizes it.
            if not IsPreviewHintDismissed() then RehomeHint(PAGE_GCD) end
            UpdateGCDPreview()
        end

        -- Totem Bar preview: sample icons in the Totem Bar layout (Icon Size,
        -- Spacing, Orientation, border, timer), static like the Cast Bar's.
        -- WoW Forever shamans with the Call Totem Bar on get its six buttons
        -- as a second group below. No swipe: the timers stand still.
        -- Header height: at least TOTEM_PREVIEW_H, the stack plus TOTEM_PREVIEW_VPAD, at most TOTEM_PREVIEW_MAXH.
        local TOTEM_PREVIEW_H, TOTEM_PREVIEW_VPAD, TOTEM_PREVIEW_MAXH = 80, 40, 260
        local TOTEM_ICONS = {
            { tex = "Interface\\Icons\\Spell_Nature_StoneSkinTotem", timer = "24" },
            { tex = "Interface\\Icons\\Spell_Fire_SearingTotem", timer = "11" },
            { tex = "Interface\\Icons\\Spell_Nature_ManaRegenTotem", timer = "52" },
            { tex = "Interface\\Icons\\Spell_Nature_Windfury", timer = "7" },
        }
        local CALL_ICONS = {
            { tex = "Interface\\Icons\\Spell_Shaman_DropAll_01" },
            { tex = "Interface\\Icons\\Spell_Nature_StoneSkinTotem" },
            { tex = "Interface\\Icons\\Spell_Fire_SearingTotem", timer = "5" },
            { tex = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
            { tex = "Interface\\Icons\\Spell_Nature_Windfury", timer = "18" },
            { tex = "Interface\\Icons\\Spell_Shaman_TotemRecall" },
        }
        -- Each group: key (profile table), icons, zoom (the live crop), map
        -- keys for the hit overlays.
        local TOTEM_GROUPS = {
            { key = "totemBar", icons = TOTEM_ICONS, zoom = 0.055, mapIcon = "totemIcon", mapTimer = "totemTimer" },
            { key = "callTotemBar", icons = CALL_ICONS, zoom = 0.08, mapIcon = "callTotemIcon", mapTimer = "callTotemTimer" },
        }
        local tp = { groups = {} }

        -- The Call Totem Bar group shows where its section does, while it is on.
        local function CallTotemShown(p)
            local c = p and p.callTotemBar
            return ns.ERB_HasCallTotemSection() and c and c.enabled == true
        end

        -- building: the header build itself (it returns the height); any
        -- other update resizes the shown header.
        -- Something in the Totem preview takes a click (a group that is on).
        local function TotemPreviewClickable()
            for _, grp in ipairs(tp.groups) do
                if grp.on then return true end
            end
            return false
        end

        local function UpdateTotemPreview(building)
            local p = DB()
            local container = tp.container
            if not (p and container) then return end
            local hdr = container:GetParent()

            -- Group sizes in live units first: the fit scale (and with it the
            -- pixel grid) is known only once the whole stack is measured.
            -- The Call Totem Bar group, built wherever its section is, shows
            -- while that bar is on.
            local GAP = 10
            local totalW, totalH, shown = 0, 0, 0
            for gi, grp in ipairs(tp.groups) do
                local t = p[TOTEM_GROUPS[gi].key]
                if gi == 2 and not CallTotemShown(p) then t = nil end
                grp.t = nil
                if t then
                    local n = #grp.icons
                    local len = n * (t.iconSize or 30) + (n - 1) * (t.spacing or 2)
                    local across = t.iconSize or 30
                    local vertical = t.orientation == "VERTICAL"
                    totalW = math.max(totalW, vertical and across or len)
                    totalH = totalH + (vertical and len or across) + (shown > 0 and GAP or 0)
                    shown = shown + 1
                    grp.t = t
                end
            end

            -- The header grows with the stack (a column, two groups) up to
            -- TOTEM_PREVIEW_MAXH; past that, or past the panel width, it scales down.
            local PAD = EllesmereUI.CONTENT_PAD
            local availW = ((tp.hdrW or hdr:GetWidth()) - PAD * 2) / tp.scale
            local availH = (TOTEM_PREVIEW_MAXH - TOTEM_PREVIEW_VPAD) / tp.scale
            local fit = 1
            if totalW > availW and availW > 0 then fit = availW / totalW end
            if totalH * fit > availH and availH > 0 then fit = availH / totalH end
            container:SetScale(tp.scale * fit)
            tp.baseH = math.max(TOTEM_PREVIEW_H, math.ceil(totalH * tp.scale * fit) + TOTEM_PREVIEW_VPAD)

            local cScale = container:GetEffectiveScale()
            if cScale <= 0 then cScale = 1 end
            local onePx = EllesmereUI.PP.perfect / cScale
            local function Snap(val)
                return math.floor(val / onePx + 0.5) * onePx
            end

            local snapW, top = 0, 0
            for gi, grp in ipairs(tp.groups) do
                local t = grp.t
                grp.frame:SetShown(t ~= nil)
                if not t then
                    grp.on = false
                    for _, hit in ipairs(grp.iconHits) do hit:Hide() end
                    for _, hit in ipairs(grp.timerHits) do hit:Hide() end
                else
                    local size = Snap(t.iconSize or 30)
                    -- A set gap keeps at least one physical pixel when the stack is fitted down.
                    local spacing = (t.spacing or 2) > 0 and math.max(onePx, Snap(t.spacing or 2)) or 0
                    local vertical = t.orientation == "VERTICAL"
                    local n = #grp.icons
                    local len = n * size + (n - 1) * spacing
                    local gw, gh = len, size
                    if vertical then gw, gh = size, len end
                    grp.frame:SetSize(gw, gh)
                    grp.frame:ClearAllPoints()
                    grp.frame:SetPoint("TOP", container, "TOP", 0, -top)
                    top = top + gh + GAP
                    snapW = math.max(snapW, gw)
                    local bs = t.borderSize or 0
                    local texKey = t.borderTexture or "solid"
                    local showTimer = t.showTimer ~= false
                    -- The active totem bar shows only for the player's own class, as live.
                    local on = true
                    if gi == 1 then
                        local ec = t.enabledClasses
                        local _, cf = UnitClass("player")
                        on = (ec and cf and ec[cf]) and true or false
                    end
                    grp.on = on
                    for i, ic in ipairs(grp.icons) do
                        ic:SetSize(size, size)
                        ic:ClearAllPoints()
                        local off = (i - 1) * (size + spacing)
                        if vertical then
                            ic:SetPoint("TOP", grp.frame, "TOP", 0, -off)
                        else
                            ic:SetPoint("LEFT", grp.frame, "LEFT", off, 0)
                        end
                        -- "Show Behind": +3 in front of the icon, level-1 behind it, as live.
                        local bdr = ic._border
                        bdr:SetFrameLevel(t.borderBehind and math.max(0, ic:GetFrameLevel() - 1) or (ic:GetFrameLevel() + 3))
                        EllesmereUI.ApplyBorderStyle(bdr, bs,
                            t.borderR or 0, t.borderG or 0, t.borderB or 0, t.borderA or 1,
                            texKey, t.borderTextureOffset, t.borderTextureOffsetY,
                            t.borderTextureShiftX, t.borderTextureShiftY, "resourcebars", bs,
                            nil, EllesmereUI.BorderPx(t.borderSizePx, bs, texKey))
                        local fs = ic._timer
                        if fs then
                            if showTimer then
                                SetPVFont(fs, FONT_PATH, t.timerSize or 11, "resourceBars")
                                fs:Show()
                            else
                                fs:Hide()
                            end
                        end
                    end
                    PreviewBar.Lock(grp.frame, on, grp.iconHits)
                    for _, hit in ipairs(grp.timerHits) do hit:SetShown(on and showTimer) end
                end
            end
            container:SetSize(math.max(1, snapW), math.max(1, top - GAP))
            container:ClearAllPoints(); container:SetPoint("CENTER", hdr, "CENTER", 0, 0)

            _headerBaseH = tp.baseH
            if not building then
                PreviewBar.HintFor(TotemPreviewClickable(), hdr)
                PreviewBar.SizeHeader(hdr, tp.baseH)
            end
        end

        env.UpdateTotemPreview = UpdateTotemPreview

        env._totemPreviewBuilder = function(hdr, hdrW)
            HintBuildStart(PAGE_TOTEM, hdr)
            local p = DB()
            if not p then return 0 end

            -- Pixel sizes match the live bar: the panel's scale against UIParent's.
            tp.scale = UIParent:GetEffectiveScale() / hdr:GetEffectiveScale()

            local container = CreateFrame("Frame", nil, hdr)
            container:SetPoint("CENTER", hdr, "CENTER", 0, 0)
            container:SetScale(tp.scale)
            tp.container = container

            wipe(_hitOverlays)
            wipe(tp.groups)
            local overlayLevel = container:GetFrameLevel() + 20
            -- The Call Totem Bar group is built wherever its section is
            -- (UpdateTotemPreview shows it while that bar is on).
            local nGroups = ns.ERB_HasCallTotemSection() and 2 or 1
            for gi = 1, nGroups do
                local def = TOTEM_GROUPS[gi]
                local frame = CreateFrame("Frame", nil, container)
                frame:Show()
                local grp = { frame = frame, icons = {}, timerHits = {} }
                tp.groups[gi] = grp
                grp.iconHits = { CreateHitOverlay(frame, def.mapIcon, overlayLevel) }
                for i, d in ipairs(def.icons) do
                    local ic = CreateFrame("Frame", nil, frame)
                    local tex = ic:CreateTexture(nil, "ARTWORK")
                    tex:SetAllPoints()
                    tex:SetTexture(d.tex)
                    tex:SetTexCoord(def.zoom, 1 - def.zoom, def.zoom, 1 - def.zoom)
                    ic._border = CreateFrame("Frame", nil, ic)
                    ic._border:SetAllPoints(ic)
                    if d.timer then
                        -- The live timer is the cooldown's countdown number: white, centred.
                        local tf = CreateFrame("Frame", nil, ic)
                        tf:SetAllPoints(ic)
                        tf:SetFrameLevel(ic:GetFrameLevel() + 5)
                        local fs = tf:CreateFontString(nil, "OVERLAY")
                        SetPVFont(fs, FONT_PATH, 11, "resourceBars")
                        fs:SetPoint("CENTER", ic, "CENTER", 0, 0)
                        fs:SetTextColor(1, 1, 1, 1)
                        fs:SetText(d.timer)
                        ic._timer = fs
                        -- Every timer leads to the timer settings, above the icon overlay.
                        local hit = CreateFrame("Frame", nil, frame)
                        hit:SetPoint("TOPLEFT", fs, "TOPLEFT", -2, 2)
                        hit:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 2, -2)
                        CreateHitOverlay(hit, def.mapTimer, overlayLevel + 5)
                        grp.timerHits[#grp.timerHits + 1] = hit
                    end
                    grp.icons[i] = ic
                end
            end

            -- Width is known only once hdr is laid out: fit against hdrW for this pass.
            tp.hdrW = hdrW
            UpdateTotemPreview(true)
            tp.hdrW = nil

            return tp.baseH + PlaceHint(hdr, TotemPreviewClickable())
        end

        env.RestoreTotemPreview = function()
            -- Header shown again from the cache: take the hint back before the update sizes it.
            if not IsPreviewHintDismissed() then RehomeHint(PAGE_TOTEM) end
            UpdateTotemPreview()
        end
    end

    -- Register the module
    EllesmereUI:RegisterModule("EllesmereUIResourceBars", {
        title       = "Resource Bars",
        description = "Custom class resource, health, and mana bar display.",
        pages       = C_SwingTimer
            and { PAGE_DISPLAY, PAGE_CASTBAR, PAGE_GCD, PAGE_SWING, PAGE_TOTEM }
            or  { PAGE_DISPLAY, PAGE_CASTBAR, PAGE_GCD, PAGE_TOTEM },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_DISPLAY then
                return ns.ERB_BuildBarDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_CASTBAR then
                return ns.ERB_BuildCastBarPage(pageName, parent, yOffset)
            elseif pageName == PAGE_GCD then
                return ns.ERB_BuildGCDBarPage(pageName, parent, yOffset)
            elseif pageName == PAGE_SWING then
                return ns.ERB_BuildSwingTimerPage(pageName, parent, yOffset)
            elseif pageName == PAGE_TOTEM then
                return ns.ERB_BuildTotemBarPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _previewHeaderBuilder
            elseif pageName == PAGE_CASTBAR then
                return _castBarPreviewBuilder
            elseif pageName == PAGE_GCD then
                return ns._ERB_OptEnv._gcdPreviewBuilder
            elseif pageName == PAGE_TOTEM then
                return ns._ERB_OptEnv._totemPreviewBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
                -- A kept header that built with nothing to show (no class
                -- resource) is built again on every visit, as an empty header
                -- is never cached without page reuse (its spec rows included;
                -- the build draws its own preview values).
                if _classHdrEmpty then
                    EllesmereUI:RefreshPage(true)
                    return
                end
                -- Randomize preview values when switching TO this tab
                local minPips = math.floor(5 * 0.50 + 0.5)
                local maxPips = math.floor(5 * 0.75 + 0.5)
                _previewPipCount = math.random(minPips, maxPips)
                _previewBarFillPct = math.random(30, 80)
                UpdatePreviewHeader()
                -- Refresh hint visibility never recreate here, just show/hide
                local dismissed = IsPreviewHintDismissed()
                if _previewHintFS then
                    if dismissed then
                        _previewHintFS:Hide()
                    else
                        RehomeHint(PAGE_DISPLAY)
                        _previewHintFS:SetAlpha(0.45)
                        _previewHintFS:Show()
                        if _previewHintFS:GetParent() then _previewHintFS:GetParent():Show() end
                    end
                end
                -- Set correct header height based on current hint state
                if _headerBaseH > 0 then
                    EllesmereUI:SetContentHeaderHeightSilent(_headerBaseH + (dismissed and 0 or 35))
                end
            elseif pageName == PAGE_CASTBAR then
                -- Randomize cast bar preview fill each time the tab is opened
                _castBarPreviewFill = math.random(30, 85) / 100
                -- Before the preview update: it sizes the header for the hint.
                if not IsPreviewHintDismissed() then RehomeHint(PAGE_CASTBAR) end
                UpdateCastBarPreview()
            elseif pageName == PAGE_GCD then
                ns._ERB_OptEnv.RestoreGCDPreview()
            elseif pageName == PAGE_TOTEM then
                ns._ERB_OptEnv.RestoreTotemPreview()
            end
        end,
        onReset = function()
            if _G._ERB_AceDB then
                _G._ERB_AceDB:ResetProfile()
            end
            Refresh()
        end,
    })

    SLASH_ERBOPT1 = "/erbopt"
    SlashCmdList.ERBOPT = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIResourceBars")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
