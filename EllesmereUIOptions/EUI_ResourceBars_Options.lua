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
            if EllesmereUI.ReapplyMatchPads then
                if all then
                    for i = 1, #CLASSIC_MATCH_KEYS do EllesmereUI.ReapplyMatchPads(CLASSIC_MATCH_KEYS[i]) end
                else
                    EllesmereUI.ReapplyMatchPads(matchKey)
                end
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
            if EllesmereUI.ReapplyMatchPads then
                for i = 1, #CLASSIC_MATCH_KEYS do EllesmereUI.ReapplyMatchPads(CLASSIC_MATCH_KEYS[i]) end
            end
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
    local PP = EllesmereUI.PanelPP
    local THR_BORDER_WHITE = { 1, 1, 1 }  -- Threshold Settings buttons: default (unconfigured) border tint

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
        ticker = C_Timer.NewTicker(0.016, function()
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

        if not HasClassResource() then
            local pc = _previewFrames.pipContainer
            if pc then pc:Hide() end
            if _previewHintFS then _previewHintFS:Hide() end
            EllesmereUI:UpdateContentHeaderHeight(0)
            return
        end

        local container = _previewFrames.pipContainer and _previewFrames.pipContainer:GetParent()
        local sp = p.secondary
        local isBar = ns.IsBarTypeSecondary()

        local pc = _previewFrames.pipContainer
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
                pc:SetPoint("CENTER", container, "CENTER", 0, 0)
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
                local onePx = 1 / pcScale
                local function PipSnap(val)
                    return math.floor(val * pcScale + 0.5) / pcScale
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
                    local baseW = math.floor(availW * pcScale / numPips) / pcScale
                    local leftover = availW - baseW * numPips
                    local extraCount = math.floor(leftover * pcScale + 0.5)
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

                local _pvTsEntry2 = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(sp) or nil
                local _pvThreshCount = _pvTsEntry2 and _pvTsEntry2.thresholdCount or sp.thresholdCount
                local _pvPartialOnly = _pvTsEntry2 and _pvTsEntry2.thresholdPartialOnly or sp.thresholdPartialOnly
                local filledCount
                local _pvTsEnabled = _pvTsEntry2 and (_pvTsEntry2.thresholdEnabled ~= false) or false
                if _pvTsEnabled then
                    filledCount = _pvThreshCount
                else
                    filledCount = _previewPipCount
                    -- _previewPipCount is randomized against a generic 5-pip preview; rescale for other counts (e.g. 18 Sweeping Strikes)
                    if numPips ~= 5 then
                        filledCount = math.max(1, math.min(numPips,
                            math.floor(_previewPipCount / 5 * numPips + 0.5)))
                    end
                end
                -- Read by the count-text block so the number matches the lit segments
                pc._pvShownCount = filledCount
                local useThresh = _pvTsEnabled
                local pvPipBg = ns.ERB_PipBgOn(sp, false)  -- Background on individual pips, as live
				-- current spec threshold color if configured
				local tr = _pvTsEntry2 and _pvTsEntry2.thresholdR or sp.thresholdR
				local tg = _pvTsEntry2 and _pvTsEntry2.thresholdG or sp.thresholdG
				local tb = _pvTsEntry2 and _pvTsEntry2.thresholdB or sp.thresholdB

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
                        if _pvPartialOnly and i < _pvThreshCount then
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
                EllesmereUI.RoundCorners(pc, radius, {
                    roots = { pc }, style = style,
                    border = not onPips and pc._barBorderFrame or nil,
                })
                for i = 1, #_previewFrames.pips do
                    local pip = _previewFrames.pips[i]
                    EllesmereUI.RoundCorners(pip, onPips and radius or 0, {
                        roots = { pip }, style = style, border = pip._borderFrame,
                    })
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
                pc._countText:Show()
            elseif pc._countText then
                pc._countText:Hide()
            end

            if sp.enabled then
                pc:Show()
            else
                pc:Hide()
            end
        end

        do
            local TOTAL_H = 80
            _headerBaseH = TOTAL_H
            if container then container:SetHeight(80) end
            if not _previewBuilding then
                local hintH = (_previewHintFS and _previewHintFS:IsShown()) and 35 or 0
                EllesmereUI:UpdateContentHeaderHeight(TOTAL_H + hintH)
            end
        end
    end

    -- Forward decls for preview click-to-scroll
    local CreateHitOverlay
    local _hitOverlays = {}

    -- Preview Header Builder
    _previewHeaderBuilder = function(hdr, hdrW)
        local p = DB()
        if not p then return 0 end
        if not HasClassResource() then return 0 end
        _previewBuilding = true
        local _, classFile = UnitClass("player")

        local container = CreateFrame("Frame", nil, hdr)
        container:SetSize(hdrW, 100)
        container:SetPoint("CENTER", hdr, "CENTER", 0, 0)

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

        UpdatePreviewHeader()

        -- Hit overlays for preview click-to-scroll (pips only)
        wipe(_hitOverlays)
        local overlayLevel = container:GetFrameLevel() + 20
        if pipC then CreateHitOverlay(pipC, "classResource", overlayLevel) end
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
        local hintShown = not IsPreviewHintDismissed()

        -- Fixed 80px preview area
        local TOTAL_H = 80
        _headerBaseH = TOTAL_H
        if hintShown then
            if not _previewHintFS then
                -- Thin non-clipping child frame so the cache system stashes/restores it properly on page switch
                local hintHost = CreateFrame("Frame", nil, hdr)
                hintHost:SetAllPoints(hdr)
                _previewHintFS = EllesmereUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
            end
            _previewHintFS:GetParent():SetParent(hdr)
            _previewHintFS:GetParent():Show()
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 20)
            _previewHintFS:Show()
            TOTAL_H = TOTAL_H + 35
        elseif _previewHintFS then
            _previewHintFS:Hide()
        end

        container:SetHeight(80)
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
        C_Timer.After(0.15, function() PlaySettingGlow(glowTarget) end)
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

    -- Cog + popup for simple per-bar hash lines (Health/Power). cfg = { parentRgn, getBarData, refreshFn, popupTitle, anchorTo }; returns cogBtn.
    local function BuildHashCog(cfg)
        local getBarData = cfg.getBarData
        local refreshFn  = cfg.refreshFn or function() end

        local function SanitizePositions(str)
            if not str or str == "" then return "" end
            local out = {}
            for token in tostring(str):gmatch("[^,]+") do
                local n = tonumber((token:gsub("%s", "")))
                if n and n >= 0 then out[#out + 1] = tostring(n) end
            end
            return table.concat(out, ", ")
        end

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
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
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
        local abg = EllesmereUI.SolidTex(_bandAddBtn, "BACKGROUND", 0.05, 0.07, 0.09, 0.92)
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
            bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
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
            local abg = EllesmereUI.SolidTex(addBtn, "BACKGROUND", 0.05, 0.07, 0.09, 0.92)
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

    -- Shared per-spec threshold popup builder, used by power and health bar sections.
    -- cfg fields:
    --    parentRgn      -- the DualRow right region to host the button
    --    getBarData     -- fn() returns the bar sub-table (p.secondary, p.primary, p.health)
    --    refreshFn      -- fn() called after any setting change
    --    rebuildFn      -- fn() called for structural changes (hash lines)
    --    disabledFn     -- fn() returns true when the parent bar is disabled
    --    disabledTip    -- string for disabled tooltip
    --    showHash       -- bool: include hash line row + hash cog
    --    showPartialCog -- bool: include "Only Color At/Above Threshold" cog
    --    isBarTypeFn    -- fn(specID) returns true for bar-type specs (only for showHash)
    --    thresholdLabel -- string: threshold input label ("Threshold" / "Threshold %")
    --    threshMin/Max  -- slider bounds (default 1/99)
    --    popupTitle     -- string: popup title
    --    defaultR/G/B/A -- default threshold color
	--    settingsPage   -- frame for settings
    --  }
    -- Returns settingsBtn (the button frame).
    local function BuildThresholdSettingsButton(cfg)
        local parentRgn = cfg.parentRgn
        local CLOSE_ICON_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
        local POPUP_W = 410
        local POPUP_PAD = 14
        local ROW_GAP = 6
        local EG = EllesmereUI.ELLESMERE_GREEN
        local CLASS_COLORS_L = CLASS_COLORS

        local barTypeSpecs = _G._ERB_BAR_TYPE_SPECS or {}
        local function IsSpecBarType_L(specID)
            if not cfg.isBarTypeFn then return false end
            if specID == 0 then return cfg.isBarTypeFn() end
            return barTypeSpecs[specID] or false
        end
        local function IsEntryBarType_L(entry)
            if not cfg.showHash then return false end
            if not entry or not entry.specIDs or #entry.specIDs == 0 then return false end
            return IsSpecBarType_L(entry.specIDs[1])
        end
        local function SpecName_L(specID)
            if specID == 0 then return "All Specs" end
            -- The by-id lookup has no namespaced form and is absent on WoW Forever.
            local _, name, className
            if GetSpecializationInfoByID then
                _, name, _, _, _, _, className = GetSpecializationInfoByID(specID)
            end
            if name and className then return name .. " " .. className end
            return name or ("Spec " .. specID)
        end
        local function EntryLabel_L(entry)
            -- WoW Forever: the shared card label (a class held whole reads as the class).
            if EllesmereUI.IS_FOREVER then return ns.EntryLabel(entry) end
            if not entry or not entry.specIDs or #entry.specIDs == 0 then return "Unknown" end
            if entry.specIDs[1] == 0 then return "All Specs" end
            local names = {}
            for _, sid in ipairs(entry.specIDs) do names[#names + 1] = SpecName_L(sid) end
            return table.concat(names, ", ")
        end

        local defR = cfg.defaultR or 1
        local defG = cfg.defaultG or 0.2
        local defB = cfg.defaultB or 0.2
        local defA = cfg.defaultA or 1

        -- Druid "form specific" (Advanced mode only): a threshold per resource type, keyed by form
        local _playerClassFile = select(2, UnitClass("player"))
        local hasFormToggle = cfg.formCapable and cfg.singleSpec and _playerClassFile == "DRUID"
        local FORM_LABEL = { mana = "Caster", rage = "Bear", energy = "Cat", moonkin = "Moonkin" }
        local function DefaultFormEntries()
            return {
                { formKey = "mana",    thresholdEnabled = true, thresholdPct = 30, thresholdPartialOnly = true,
                  thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA },
                { formKey = "rage",    thresholdEnabled = true, thresholdPct = 30, thresholdPartialOnly = false,
                  thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA },
                { formKey = "energy",  thresholdEnabled = true, thresholdPct = 30, thresholdPartialOnly = true,
                  thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA },
                { formKey = "moonkin", thresholdEnabled = true, thresholdPct = 30, thresholdPartialOnly = true,
                  thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA },
            }
        end
        local function IsFormMode()
            local bd = cfg.getBarData()
            return (bd and bd.thresholdFormMode) and true or false
        end

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

        -- Popup (lazy)
        local popup
        local _entryFrames = {}
        local _tempSpecSel = {}
        local _specDDRefresh

        -- Role shortcut sentinels: negative so they cannot collide with specIDs
        local ROLE_ALL_HEALERS = -1
        local ROLE_ALL_TANKS   = -2
        local ROLE_ALL_DPS     = -3
        local _roleSpecCache = {}  -- [ROLE_KEY] = { specID, specID, ... }

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

        local function BuildSpecItems_L()
            local items = {}
            items[#items + 1] = { key = 0, label = "All Specs", isAction = true, lockedFn = HasAllSpecsEntry }
            -- WoW Forever: one row per class, keyed by its class token, standing for
            -- every retail spec of the class (the getter and setter expand it); no
            -- role shortcuts. A row locks while any spec of its class is claimed.
            if EllesmereUI.IS_FOREVER then
                local classes = EllesmereUI.ForeverClasses()
                for n = 1, #classes do
                    local token = classes[n]
                    local ids = EllesmereUI.ForeverClassSpecIDs(token)
                    items[#items + 1] = { key = token, label = EllesmereUI.ForeverClassName(token), lockedFn = function()
                        for i = 1, #ids do
                            if IsSpecClaimed(ids[i]) then return true end
                        end
                        return false
                    end }
                end
                return items
            end
            items[#items + 1] = { key = ROLE_ALL_HEALERS, label = "All Healers", isAction = true, lockedFn = HasAllSpecsEntry }
            items[#items + 1] = { key = ROLE_ALL_TANKS, label = "All Tanks", isAction = true, lockedFn = HasAllSpecsEntry }
            items[#items + 1] = { key = ROLE_ALL_DPS, label = "All DPS", isAction = true, lockedFn = HasAllSpecsEntry }

            -- Class list, sorted alphabetically by class name
            local classList = {}
            for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
                local className, classFile = GetClassInfo(classID)
                if className then
                    classList[#classList + 1] = { classID = classID, className = className, classFile = classFile }
                end
            end
            table.sort(classList, function(a, b) return a.className < b.className end)

            -- Spec rows per class, filling the role caches as we go
            local healers, tanks, dps = {}, {}, {}
            for _, cls in ipairs(classList) do
                items[#items + 1] = { isHeader = true, label = cls.className }
                local numSpecs = GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(cls.classID) or 0
                for specIndex = 1, numSpecs do
                    local specID, specName, _, _, role = GetSpecializationInfoForClassID(cls.classID, specIndex)
                    if specID and specName then
                        local sid = specID
                        items[#items + 1] = { key = specID, label = specName, lockedFn = function() return IsSpecClaimed(sid) end }
                        if role == "HEALER" then healers[#healers + 1] = specID
                        elseif role == "TANK" then tanks[#tanks + 1] = specID
                        else dps[#dps + 1] = specID end
                    end
                end
            end
            _roleSpecCache[ROLE_ALL_HEALERS] = healers
            _roleSpecCache[ROLE_ALL_TANKS] = tanks
            _roleSpecCache[ROLE_ALL_DPS] = dps
            return items
        end

        local RefreshPopupEntries_L
        local SetFormMode, LayoutHeaderForMode

        local function BuildPopup_L()
            popup = CreateFrame("Frame", nil, UIParent)
            popup:SetFrameStrata("DIALOG")
            popup:SetFrameLevel(200)
            popup:SetClampedToScreen(true)
            popup:EnableMouse(true)
            popup:SetScale(0.9)
            popup:Hide()
            PP.Size(popup, POPUP_W, 300)

            local bg = popup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.08, 0.10, 0.95)
            PP.CreateBorder(popup, 1, 1, 1, 0.15, 1, "BORDER", 7)

            local clickCatcher = CreateFrame("Button", nil, popup)
            clickCatcher:SetFrameStrata("DIALOG")
            clickCatcher:SetFrameLevel(popup:GetFrameLevel() - 1)
            clickCatcher:SetAllPoints((EllesmereUI:GetMainFrame()) or UIParent)
            clickCatcher:SetScript("OnClick", function() popup:Hide() end)
            clickCatcher:Hide()
            popup:SetScript("OnShow", function(self)
                clickCatcher:Show()
                self:SetScript("OnUpdate", function(p)
                    if IsMouseButtonDown("LeftButton") then
                        local mf = EllesmereUI._mainFrame
                        local dm = EllesmereUI._openDropdownMenu
                        if not p:IsMouseOver() and not (mf and mf:IsMouseOver()) and not (dm and dm:IsShown() and dm:IsMouseOver()) then p:Hide() end
                    end
                end)
            end)
            popup:SetScript("OnHide", function(self)
                clickCatcher:Hide()
                self:SetScript("OnUpdate", nil)
            end)

            if EllesmereUI._popupFrames then
                EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = popup }
            end

            local curY = -POPUP_PAD

            local titleFS = EllesmereUI.MakeFont(popup, 13, nil, 1, 1, 1)
            titleFS:SetAlpha(0.55)
            titleFS:SetPoint("TOP", popup, "TOP", 0, curY)
            titleFS:SetText(EllesmereUI.L(cfg.popupTitle or "Threshold Settings"))
            curY = curY - 25

            -- Mode switch (druid power bar): single per-spec vs three per-form entries; sits between the title and the spec chrome
            if hasFormToggle then
                local pillRow = CreateFrame("Frame", nil, popup)
                pillRow:SetSize(POPUP_W, 26)
                pillRow:SetPoint("TOP", popup, "TOP", 0, curY)
                pillRow:SetFrameLevel(popup:GetFrameLevel() + 6)
                local modeSeg, _, modeSegRefresh = EllesmereUI.BuildSegmentedControl({
                    parent    = pillRow,
                    keys      = { "single", "form" },
                    labels    = { single = "Single", form = "Form specific" },
                    autoWidth = true,
                    square    = true,
                    height    = 22,
                    getChecked = function(key)
                        if key == "form" then return IsFormMode() else return not IsFormMode() end
                    end,
                    onToggle = function(key)
                        if SetFormMode then SetFormMode(key == "form") end
                    end,
                })
                modeSeg:SetPoint("CENTER", pillRow, "CENTER", 0, 0)
                popup._modeSeg = modeSeg
                popup._modeSegRefresh = modeSegRefresh
                curY = curY - 30
            end
            -- Header bottom when the spec chrome is hidden (form mode)
            popup._afterPillY = curY

            -- Centered spec dropdown + Add button. Skipped in singleSpec mode (Advanced per-spec: the spec is implied, one config only)
            if not cfg.singleSpec then
            local DD_W, ADD_W, GAP_L = 220, 90, 10
            local rowW = DD_W + GAP_L + ADD_W
            local ddRow = CreateFrame("Frame", nil, popup)
            ddRow:SetSize(rowW, 30)
            ddRow:SetPoint("TOP", popup, "TOP", 0, curY)
            ddRow:SetFrameLevel(popup:GetFrameLevel() + 5)
            popup._ddRow = ddRow

            local specItems = BuildSpecItems_L()
            local specDDHost = CreateFrame("Frame", nil, ddRow)
            specDDHost:SetSize(DD_W, 30)
            specDDHost:SetPoint("LEFT", ddRow, "LEFT", 0, 0)
            specDDHost:SetFrameLevel(ddRow:GetFrameLevel())

            local cbDD, cbDDRefresh  -- forward decl for closure access
            cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                specDDHost, DD_W, specDDHost:GetFrameLevel() + 2,
                specItems,
                function(key)
                    -- Role shortcuts never show as "checked"
                    if key == ROLE_ALL_HEALERS or key == ROLE_ALL_TANKS or key == ROLE_ALL_DPS then return false end
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
                    local roleSpecs = _roleSpecCache[key]
                    if roleSpecs then
                        wipe(_tempSpecSel)
                        for _, sid in ipairs(roleSpecs) do _tempSpecSel[sid] = true end
                        cbDD:Click()  -- close the dropdown
                        if cbDDRefresh then cbDDRefresh() end
                        return
                    end
                    if key == 0 then
                        wipe(_tempSpecSel)
                        _tempSpecSel[0] = true
                        cbDD:Click()  -- close the dropdown
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

            local _origRefresh = cbDDRefresh
            local function WrappedRefresh()
                _origRefresh()
                local regions = { cbDD:GetRegions() }
                for _, rgn2 in ipairs(regions) do
                    if rgn2.GetText and EllesmereUI.EnKey(rgn2:GetText()) == "None" then
                        rgn2:SetText(EllesmereUI.L("Select a Spec...")); break
                    end
                end
            end
            _specDDRefresh = WrappedRefresh
            WrappedRefresh()

            local addBtn = CreateFrame("Button", nil, ddRow)
            PP.Size(addBtn, ADD_W, 30)
            addBtn:SetPoint("LEFT", specDDHost, "RIGHT", GAP_L, 0)
            addBtn:SetFrameLevel(ddRow:GetFrameLevel() + 2)
            local addBg = EllesmereUI.SolidTex(addBtn, "BACKGROUND", 0.05, 0.07, 0.09, 0.92)
            addBg:SetAllPoints()
            addBtn._border = EllesmereUI.MakeBorder(addBtn, 1, 1, 1, 0.4, PP)
            local addLbl = EllesmereUI.MakeFont(addBtn, 11, nil, 1, 1, 1)
            addLbl:SetAlpha(0.5)
            addLbl:SetPoint("CENTER")
            addLbl:SetText(EllesmereUI.L("Add Specs"))
            addBtn:SetScript("OnEnter", function()
                addLbl:SetAlpha(0.7)
                if addBtn._border and addBtn._border.SetColor then addBtn._border:SetColor(1, 1, 1, 0.6) end
            end)
            addBtn:SetScript("OnLeave", function()
                addLbl:SetAlpha(0.5)
                if addBtn._border and addBtn._border.SetColor then addBtn._border:SetColor(1, 1, 1, 0.4) end
            end)
            addBtn:SetScript("OnClick", function()
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
                local newEntry = {
                    specIDs = ids,
                    thresholdEnabled = true,
                    thresholdPct = cfg.threshMin == 1 and 30 or 30,
                    thresholdPartialOnly = false,
                    thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA,
                }
                if cfg.showHash then
                    local isBar = IsSpecBarType_L(ids[1])
                    newEntry.hashValues = ""
                    newEntry.hashWidth = 1
                    newEntry.hashColorR = 1; newEntry.hashColorG = 1; newEntry.hashColorB = 1; newEntry.hashColorA = 0.7
                    newEntry.thresholdCount = isBar and 30 or 3
                else
                    newEntry.thresholdPct = 30
                end
                -- Default for the power bar's "Threshold color below value": spenders (mana/energy/focus)
                -- start ON (warn when low), builders (rage/runic/fury) OFF (warn when high). Only when
                -- the entry covers the current spec, the one whose power type we can read.
                if cfg.showPartialCog then
                    local curIdx = C_SpecializationInfo.GetSpecialization()
                    local curSpecID = curIdx and C_SpecializationInfo.GetSpecializationInfo(curIdx)
                    -- WoW Forever: the entry covers the player when it names a spec of the class.
                    if curSpecID or EllesmereUI.IS_FOREVER then
                        for _, sid in ipairs(ids) do
                            if sid == curSpecID or (EllesmereUI.IS_FOREVER and EllesmereUI.IsPlayerSpec(sid)) then
                                local _, token = UnitPowerType("player")
                                if token == "MANA" or token == "FOCUS" or token == "ENERGY" then
                                    newEntry.thresholdPartialOnly = true
                                end
                                break
                            end
                        end
                    end
                end
                bd.thresholdSpecs[#bd.thresholdSpecs + 1] = newEntry
                wipe(_tempSpecSel)
                WrappedRefresh()
                RefreshPopupEntries_L()
                cfg.refreshFn()
            end)

            curY = curY - 36
            end -- not singleSpec
            popup._afterDDY = curY

            -- Scrollable entry container
            local POPUP_MAX_H = 375
            local headerH = math.abs(curY)

            local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
            scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, curY)
            scrollFrame:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, curY)
            scrollFrame:SetFrameLevel(popup:GetFrameLevel() + 1)

            local scrollChild = CreateFrame("Frame", nil, scrollFrame)
            scrollChild:SetWidth(POPUP_W)
            scrollFrame:SetScrollChild(scrollChild)

            local scrollBar = CreateFrame("Frame", nil, popup)
            scrollBar:SetWidth(4)
            scrollBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -3, curY)
            scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -3, 4)
            scrollBar:SetFrameLevel(popup:GetFrameLevel() + 10)
            scrollBar:Hide()
            local scrollTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
            scrollTrack:SetAllPoints()
            scrollTrack:SetColorTexture(1, 1, 1, 0.04)
            local scrollThumb = scrollBar:CreateTexture(nil, "OVERLAY")
            scrollThumb:SetWidth(4)
            scrollThumb:SetColorTexture(1, 1, 1, 0.15)
            scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, 0)
            scrollThumb:SetHeight(30)

            scrollFrame:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = self:GetVerticalScrollRange()
                if maxScroll <= 0 then return end
                local cur = self:GetVerticalScroll()
                self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 30)))
            end)
            scrollFrame:SetScript("OnScrollRangeChanged", function(self, _, yRange)
                if not yRange or yRange <= 0 then scrollBar:Hide(); return end
                scrollBar:Show()
                local barH = scrollBar:GetHeight()
                if barH <= 0 then return end
                scrollThumb:SetHeight(math.max(20, barH * (self:GetHeight() / (self:GetHeight() + yRange))))
            end)
            scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
                local maxScroll = self:GetVerticalScrollRange()
                if maxScroll <= 0 then return end
                local barH = scrollBar:GetHeight()
                local thumbH = scrollThumb:GetHeight()
                local travel = barH - thumbH
                scrollThumb:ClearAllPoints()
                scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, -travel * (offset / maxScroll))
            end)

            popup._scrollFrame = scrollFrame
            popup._scrollChild = scrollChild
            popup._scrollBar = scrollBar
            popup._headerH = headerH
            popup._maxH = POPUP_MAX_H

            -- Re-anchor the scroll region for the current mode: form mode hides
            -- the spec chrome, so the list starts right below the mode pill.
            -- The data swap is SetFormMode's job.
            LayoutHeaderForMode = function(on)
                if not hasFormToggle then return end
                local topY = on and popup._afterPillY or popup._afterDDY
                if popup._ddRow then popup._ddRow:SetShown(not on) end
                scrollFrame:ClearAllPoints()
                scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, topY)
                scrollFrame:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, topY)
                scrollBar:ClearAllPoints()
                scrollBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -3, topY)
                scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -3, 4)
                popup._headerH = math.abs(topY)
            end

            -- Swap live thresholdSpecs between the single per-spec list and the
            -- three per-form entries, stashing the inactive set so switching
            -- back restores the user's config.
            SetFormMode = function(on)
                local bd = cfg.getBarData(); if not bd then return end
                on = on and true or false
                if (bd.thresholdFormMode and true or false) ~= on then
                    if on then
                        bd._singleSpecsBackup = bd.thresholdSpecs
                        bd.thresholdSpecs = bd._formSpecsBackup or DefaultFormEntries()
                        bd._formSpecsBackup = nil
                        bd.thresholdFormMode = true
                    else
                        bd._formSpecsBackup = bd.thresholdSpecs
                        bd.thresholdSpecs = bd._singleSpecsBackup or {}
                        bd._singleSpecsBackup = nil
                        bd.thresholdFormMode = nil
                    end
                end
                LayoutHeaderForMode(on)
                if popup._modeSegRefresh then popup._modeSegRefresh() end
                RefreshPopupEntries_L()
                if popup._scrollFrame then popup._scrollFrame:SetVerticalScroll(0) end
                cfg.refreshFn()
                if cfg.rebuildFn then cfg.rebuildFn() end
            end

            -- Initial layout for whatever mode was persisted
            if hasFormToggle then LayoutHeaderForMode(IsFormMode()) end
        end -- BuildPopup_L

        RefreshPopupEntries_L = function()
            if not popup then return end
            local bd = cfg.getBarData(); if not bd then return end
            local formMode = (bd.thresholdFormMode and hasFormToggle) and true or false
            -- Form mode guarantees the three per-form entries exist
            if formMode and (not bd.thresholdSpecs or #bd.thresholdSpecs == 0) then
                bd.thresholdSpecs = DefaultFormEntries()
            end
            if not bd.thresholdSpecs then bd.thresholdSpecs = {} end
            local entries = bd.thresholdSpecs

            -- singleSpec (Advanced): exactly one config, no spec chrome
            if cfg.singleSpec and #entries == 0 then
                entries[1] = { specIDs = { 0 }, thresholdEnabled = false,
                    thresholdPct = 30, thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA }
            end

            local scrollChild = popup._scrollChild
            local curY = 0
            local ENTRY_W = POPUP_W - POPUP_PAD * 2
            local ENTRY_H = (cfg.singleSpec and not formMode) and 40 or (cfg.showHash and 89 or 60)
            local effThreshY = (cfg.singleSpec and not formMode) and -8 or (cfg.showHash and -61 or -33)

            for i = 1, #_entryFrames do
                if _entryFrames[i] then _entryFrames[i]:Hide() end
            end

            for idx, entry in ipairs(entries) do
                local ef = _entryFrames[idx]
                if not ef then
                    ef = CreateFrame("Frame", nil, scrollChild)
                    ef:SetFrameLevel(popup:GetFrameLevel() + 2)
                    _entryFrames[idx] = ef

                    local entBg = ef:CreateTexture(nil, "BACKGROUND")
                    entBg:SetAllPoints()
                    entBg:SetColorTexture(1, 1, 1, 0.02)

                    local delBtn = CreateFrame("Button", nil, ef)
                    delBtn:SetSize(14, 14)
                    delBtn:SetPoint("TOPRIGHT", ef, "TOPRIGHT", -6, -9)
                    delBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                    local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                    delIcon:SetAllPoints()
                    delIcon:SetTexture(CLOSE_ICON_PATH)
                    delIcon:SetAlpha(0.4)
                    delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
                    delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
                    ef._delBtn = delBtn

                    local specLbl = EllesmereUI.MakeFont(ef, 14, nil, 1, 1, 1)
                    specLbl:SetAlpha(0.85)
                    specLbl:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, -9)
                    specLbl:SetPoint("RIGHT", ef, "RIGHT", -26, 0)
                    specLbl:SetJustifyH("LEFT")
                    specLbl:SetWordWrap(false)
                    ef._specLbl = specLbl

                    -- Threshold row Y depends on whether a hash row exists; singleSpec has no spec-label row so it sits at the top
                    local threshY = cfg.singleSpec and -8 or (cfg.showHash and -61 or -33)

                    -- Hash row: class resource only
                    if cfg.showHash then
                        local hashLbl = EllesmereUI.MakeFont(ef, 13, nil, 1, 1, 1)
                        hashLbl:SetAlpha(0.6)
                        hashLbl:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, -33)
                        ef._hashLbl = hashLbl

                        local hashHint = EllesmereUI.MakeFont(ef, 10, nil, 1, 1, 1)
                        hashHint:SetAlpha(0.35)
                        hashHint:SetPoint("LEFT", hashLbl, "RIGHT", 4, 0)
                        ef._hashHint = hashHint

                        local hashInput = CreateFrame("EditBox", nil, ef)
                        hashInput:SetSize(100, 22)
                        hashInput:SetPoint("LEFT", hashHint, "RIGHT", 8, 0)
                        hashInput:SetFrameLevel(ef:GetFrameLevel() + 3)
                        hashInput:SetAutoFocus(false)
                        hashInput:SetFontObject(GameFontHighlightSmall)
                        local hiFont = EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
                        hashInput:SetFont(hiFont, 12, "")
                        hashInput:SetTextColor(1, 1, 1, 0.75)
                        hashInput:SetJustifyH("CENTER")
                        local hiBg = hashInput:CreateTexture(nil, "BACKGROUND")
                        hiBg:SetAllPoints()
                        hiBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        EllesmereUI.MakeBorder(hashInput, 1, 1, 1, 0.08, PP)
                        ef._hashInput = hashInput

                        local _, hashCogShow = EllesmereUI.BuildCogPopup({
                            title = "Hash Line Style", bgAlpha = 1,
                            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
                            rows = {
                                { type = "slider", label = "Hash Width", min = 1, max = 4, step = 1,
                                  get = function()
                                      if not ef._entryIdx then return 1 end
                                      local bd2 = cfg.getBarData(); if not bd2 then return 1 end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      return ent and ent.hashWidth or 1
                                  end,
                                  set = function(v)
                                      if not ef._entryIdx then return end
                                      local bd2 = cfg.getBarData(); if not bd2 then return end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      if ent then ent.hashWidth = v; cfg.rebuildFn() end
                                  end },
                                { type = "colorpicker", label = "Hash Color", hasAlpha = true,
                                  get = function()
                                      if not ef._entryIdx then return 1, 1, 1, 0.7 end
                                      local bd2 = cfg.getBarData(); if not bd2 then return 1, 1, 1, 0.7 end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      if not ent then return 1, 1, 1, 0.7 end
                                      return ent.hashColorR or 1, ent.hashColorG or 1, ent.hashColorB or 1, ent.hashColorA or 0.7
                                  end,
                                  set = function(r, g, b, a)
                                      if not ef._entryIdx then return end
                                      local bd2 = cfg.getBarData(); if not bd2 then return end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      if ent then
                                          ent.hashColorR, ent.hashColorG, ent.hashColorB, ent.hashColorA = r, g, b, a
                                          cfg.rebuildFn()
                                      end
                                  end },
                            },
                        })
                        local hashCogBtn = CreateFrame("Button", nil, ef)
                        hashCogBtn:SetSize(20, 20)
                        hashCogBtn:SetPoint("LEFT", hashInput, "RIGHT", 6, 0)
                        hashCogBtn:SetFrameLevel(ef:GetFrameLevel() + 5)
                        hashCogBtn:SetAlpha(0.4)
                        local hashCogTex = hashCogBtn:CreateTexture(nil, "OVERLAY")
                        hashCogTex:SetAllPoints()
                        hashCogTex:SetTexture(EllesmereUI.COGS_ICON)
                        hashCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                        hashCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                        hashCogBtn:SetScript("OnClick", function(self) hashCogShow(self) end)
                        ef._hashCogBtn = hashCogBtn
                    end

                    -- Threshold row
                    local threshLbl2 = EllesmereUI.MakeFont(ef, 13, nil, 1, 1, 1)
                    threshLbl2:SetAlpha(0.6)
                    threshLbl2:SetPoint("LEFT", ef, "TOPLEFT", 8, threshY - 11)
                    threshLbl2:SetText(cfg.thresholdLabel or EllesmereUI.L("Threshold"))
                    ef._threshLbl = threshLbl2

                    local threshInput = CreateFrame("EditBox", nil, ef)
                    threshInput:SetSize(40, 22)
                    threshInput:SetPoint("LEFT", threshLbl2, "RIGHT", 8, 0)
                    threshInput:SetFrameLevel(ef:GetFrameLevel() + 3)
                    threshInput:SetAutoFocus(false)
                    threshInput:SetFontObject(GameFontHighlightSmall)
                    local tiFont = EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
                    threshInput:SetFont(tiFont, 12, "")
                    threshInput:SetTextColor(1, 1, 1, 0.75)
                    threshInput:SetJustifyH("CENTER")
                    threshInput:SetNumeric(true)
                    local tiBg = threshInput:CreateTexture(nil, "BACKGROUND")
                    tiBg:SetAllPoints()
                    tiBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                    EllesmereUI.MakeBorder(threshInput, 1, 1, 1, 0.08, PP)
                    ef._threshInput = threshInput

                    local entrySwatch, entrySwatchSnap = EllesmereUI.BuildColorSwatch(ef, ef:GetFrameLevel() + 4,
                        function()
                            if not ef._entryIdx then return defR, defG, defB, defA end
                            local bd2 = cfg.getBarData(); if not bd2 then return defR, defG, defB, defA end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if not ent then return defR, defG, defB, defA end
                            return ent.thresholdR or defR, ent.thresholdG or defG, ent.thresholdB or defB, ent.thresholdA or defA
                        end,
                        function(r, g, b, a)
                            if not ef._entryIdx then return end
                            local bd2 = cfg.getBarData(); if not bd2 then return end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if ent then ent.thresholdR, ent.thresholdG, ent.thresholdB, ent.thresholdA = r, g, b, a; cfg.refreshFn() end
                        end, true, 19)
                    entrySwatch:SetPoint("LEFT", threshInput, "RIGHT", 8, 0)
                    ef._entrySwatch = entrySwatch
                    ef._entrySwatchSnap = entrySwatchSnap

                    local entryToggle, _, entrySnap = EllesmereUI.BuildToggleControl(
                        ef, ef:GetFrameLevel() + 4,
                        function()
                            if not ef._entryIdx then return false end
                            local bd2 = cfg.getBarData(); if not bd2 then return false end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if not ent then return false end
                            if ent.thresholdEnabled == nil then return true end
                            return ent.thresholdEnabled
                        end,
                        function(v)
                            if not ef._entryIdx then return end
                            local bd2 = cfg.getBarData(); if not bd2 then return end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if ent then ent.thresholdEnabled = v; cfg.refreshFn() end
                            if RefreshPopupEntries_L then RefreshPopupEntries_L() end
                        end,
                        { sizeRatio = 0.95 }
                    )
                    entryToggle:SetPoint("LEFT", entrySwatch, "RIGHT", 6, 0)
                    ef._entryToggle = entryToggle
                    ef._entrySnap = entrySnap

					-- Cog (only if showPartialCog)
                    do
                        local cogRows = {}
                        if cfg.showPartialCog then
                            cogRows[#cogRows + 1] = { type = "toggle", label = "Threshold color below value",
                                rawTooltip = true,
                                disabled = function()
                                    if not ef._entryIdx then return false end
                                    local bd2 = cfg.getBarData(); if not bd2 then return false end
                                    local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                    return (ent and ent.multiBandEnabled) and true or false
                                end,
                                disabledTooltip = "Single-threshold options don't apply while Multi-band coloring is on.",
                                get = function()
                                    if not ef._entryIdx then return false end
                                    local bd2 = cfg.getBarData(); if not bd2 then return false end
                                    local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                    return ent and ent.thresholdPartialOnly
                                end,
                                set = function(v)
                                    if not ef._entryIdx then return end
                                    local bd2 = cfg.getBarData(); if not bd2 then return end
                                    local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                    if ent then ent.thresholdPartialOnly = v; cfg.refreshFn() end
                                end }
                        end
                        cogRows[#cogRows + 1] = { type = "toggle", label = "Recolor Text Instead Of Bar",
                            get = function()
                                if not ef._entryIdx then return false end
                                local bd2 = cfg.getBarData(); if not bd2 then return false end
                                local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                return ent and ent.thresholdTextInstead
                            end,
                            set = function(v)
                                if not ef._entryIdx then return end
                                local bd2 = cfg.getBarData(); if not bd2 then return end
                                local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                if ent then ent.thresholdTextInstead = v; cfg.refreshFn() end
                            end }
                        local _, entryCogShow = EllesmereUI.BuildCogPopup({
                            title = "Threshold Coloring", bgAlpha = 1, minWidth = 280,
                            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
                            rows = cogRows,
                        })
                        local cogBtn2 = CreateFrame("Button", nil, ef)
                        cogBtn2:SetSize(20, 20)
                        cogBtn2:SetPoint("LEFT", entryToggle, "RIGHT", 6, 0)
                        cogBtn2:SetFrameLevel(ef:GetFrameLevel() + 5)
                        cogBtn2:SetAlpha(0.4)
                        local cogTex2 = cogBtn2:CreateTexture(nil, "OVERLAY")
                        cogTex2:SetAllPoints()
                        cogTex2:SetTexture(EllesmereUI.COGS_ICON)
                        cogBtn2:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                        cogBtn2:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                        cogBtn2:SetScript("OnClick", function(self) entryCogShow(self) end)
                        ef._cogBtn = cogBtn2
                    end

                    -- Multi-band per-entry toggle + "Bands" editor button (right)
                    local bandsBtn = CreateFrame("Button", nil, ef)
                    bandsBtn:SetSize(58, 22)
                    bandsBtn:SetPoint("RIGHT", ef, "TOPRIGHT", -8, threshY - 11)
                    bandsBtn:SetFrameLevel(ef:GetFrameLevel() + 4)
                    local bbBg = bandsBtn:CreateTexture(nil, "BACKGROUND")
                    bbBg:SetAllPoints()
                    bbBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                    bandsBtn._border = EllesmereUI.MakeBorder(bandsBtn, 1, 1, 1, 0.08, PP)
                    local bbLbl = EllesmereUI.MakeFont(bandsBtn, 12, nil, 1, 1, 1)
                    bbLbl:SetAlpha(0.8)
                    bbLbl:SetPoint("CENTER")
                    bbLbl:SetText(EllesmereUI.L("Bands"))
                    bandsBtn:SetScript("OnEnter", function(self)
                        bbBg:SetColorTexture(0.16, 0.16, 0.16, 0.9)
                        EllesmereUI.ShowWidgetTooltip(self, BAND_HELP_TIP)
                    end)
                    bandsBtn:SetScript("OnLeave", function(self)
                        bbBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    bandsBtn:SetScript("OnClick", function(self)
                        if not ef._entryIdx then return end
                        ShowBandEditor({
                            getBarData = cfg.getBarData, refreshFn = cfg.refreshFn,
                            entryIdx = ef._entryIdx, anchor = self, countBased = false,
                            defR = defR, defG = defG, defB = defB, defA = defA,
                        })
                    end)
                    ef._bandsBtn = bandsBtn

                    local multiToggle, _, multiSnap = EllesmereUI.BuildToggleControl(
                        ef, ef:GetFrameLevel() + 4,
                        function()
                            if not ef._entryIdx then return false end
                            local bd2 = cfg.getBarData(); if not bd2 then return false end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            return ent and ent.multiBandEnabled or false
                        end,
                        function(v)
                            if not ef._entryIdx then return end
                            local bd2 = cfg.getBarData(); if not bd2 then return end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if ent then ent.multiBandEnabled = v; cfg.refreshFn() end
                            if RefreshPopupEntries_L then RefreshPopupEntries_L() end
                        end,
                        { sizeRatio = 0.95 }
                    )
                    multiToggle:SetPoint("RIGHT", bandsBtn, "LEFT", -8, 0)
                    ef._multiToggle = multiToggle
                    ef._multiSnap = multiSnap
                    multiToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, BAND_HELP_TIP) end)
                    multiToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                    local multiLbl = EllesmereUI.MakeFont(ef, 11, nil, 1, 1, 1)
                    multiLbl:SetAlpha(0.55)
                    multiLbl:SetText(EllesmereUI.L("Multi"))
                    multiLbl:SetPoint("RIGHT", multiToggle, "LEFT", -4, 0)
                    ef._multiLbl = multiLbl

                    -- Disabled overlay (excludes toggle)
                    local threshDis = CreateFrame("Frame", nil, ef)
                    threshDis:SetPoint("TOPLEFT", threshLbl2, "TOPLEFT", -2, 4)
                    threshDis:SetPoint("BOTTOMRIGHT", entryToggle, "BOTTOMLEFT", -4, -4)
                    threshDis:SetFrameLevel(ef:GetFrameLevel() + 6)
                    threshDis:EnableMouse(true)
                    local threshDisTex = threshDis:CreateTexture(nil, "OVERLAY")
                    threshDisTex:SetAllPoints()
                    threshDisTex:SetColorTexture(0.06, 0.08, 0.10, 0.7)
                    threshDis:SetScript("OnEnter", function()
                        local tip = (ef._threshDisTip == "MULTI") and BAND_REPLACES_TIP
                            or EllesmereUI.DisabledTooltip("Threshold Color")
                        EllesmereUI.ShowWidgetTooltip(threshDis, tip)
                    end)
                    threshDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    ef._threshDis = threshDis
                end -- end entry frame creation

                ef:SetSize(ENTRY_W, ENTRY_H)
                ef:ClearAllPoints()
                ef:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", POPUP_PAD, curY)
                ef._entryIdx = idx

                if ef._threshLbl then
                    ef._threshLbl:ClearAllPoints()
                    ef._threshLbl:SetPoint("LEFT", ef, "TOPLEFT", 8, effThreshY - 11)
                end
                if ef._bandsBtn then
                    ef._bandsBtn:ClearAllPoints()
                    ef._bandsBtn:SetPoint("RIGHT", ef, "TOPRIGHT", -8, effThreshY - 11)
                end

                if formMode then
                    -- Form mode: fixed per-form entries, form name label, no delete
                    ef._specLbl:Show()
                    ef._delBtn:Hide()
                    ef._specLbl:SetText(EllesmereUI.L(FORM_LABEL[entry.formKey] or "Unknown"))
                    local cc = CLASS_COLORS_L["DRUID"]
                    if cc then ef._specLbl:SetTextColor(cc[1], cc[2], cc[3], 1)
                    else ef._specLbl:SetTextColor(1, 1, 1, 1) end
                elseif cfg.singleSpec then
                    -- Advanced: spec is implied, so no spec label, no delete
                    ef._specLbl:Hide()
                    ef._delBtn:Hide()
                else
                    ef._specLbl:Show()
                    ef._delBtn:Show()
                    ef._specLbl:SetText(EntryLabel_L(entry))
                    do
                        local firstSID = entry.specIDs and entry.specIDs[1]
                        local classFile
                        if firstSID == 0 then
                            local _, cf = UnitClass("player"); classFile = cf
                        elseif firstSID and GetSpecializationInfoByID then
                            local _, _, _, _, _, cf = GetSpecializationInfoByID(firstSID); classFile = cf
                        elseif firstSID and EllesmereUI.IS_FOREVER then
                            classFile = EllesmereUI.SpecClassOf(firstSID)
                        end
                        local cc = classFile and CLASS_COLORS_L[classFile]
                        if cc then ef._specLbl:SetTextColor(cc[1], cc[2], cc[3], 1)
                        else ef._specLbl:SetTextColor(1, 1, 1, 1) end
                    end

                    ef._delBtn:SetScript("OnClick", function()
                        local bd2 = cfg.getBarData(); if not bd2 then return end
                        table.remove(bd2.thresholdSpecs, idx)
                        wipe(_tempSpecSel)
                        if _specDDRefresh then _specDDRefresh() end
                        RefreshPopupEntries_L()
                        cfg.refreshFn()
                    end)
                end

                if cfg.showHash and ef._hashLbl then
                    local isBar = IsEntryBarType_L(entry)
                    local hashWord = isBar and "Percent" or "Stack"
                    ef._hashLbl:SetText(EllesmereUI.Lf("Hash at %1$s", hashWord))
                    ef._hashHint:SetText(isBar and EllesmereUI.L("(Ex: 25,50,75)") or EllesmereUI.L("(Ex: 2,4)"))
                    ef._hashInput:SetText(entry.hashValues or "")
                    -- Commit on focus loss; Enter clears focus, Escape discards
                    ef._hashInput:SetScript("OnEditFocusLost", function(self)
                        if self._cancelCommit then self._cancelCommit = nil; return end
                        local bd2 = cfg.getBarData(); if not bd2 then return end
                        local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[idx]
                        if ent then ent.hashValues = self:GetText(); cfg.rebuildFn() end
                    end)
                    ef._hashInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                    ef._hashInput:SetScript("OnEscapePressed", function(self)
                        self._cancelCommit = true
                        local bd2 = cfg.getBarData(); if not bd2 then return end
                        local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[idx]
                        self:SetText(ent and ent.hashValues or ""); self:ClearFocus()
                    end)
                end

                local threshKey = cfg.showHash and "thresholdCount" or "thresholdPct"
                local threshDef = cfg.showHash and (IsEntryBarType_L(entry) and 30 or 3) or 30
                local threshMaxVal = cfg.threshMax or 99
                if cfg.showHash then
                    threshMaxVal = IsEntryBarType_L(entry) and 100 or 10
                end
                ef._threshInput:SetText(tostring(entry[threshKey] or threshDef))
                -- Commit on focus loss; Enter clears focus, Escape discards
                ef._threshInput:SetScript("OnEditFocusLost", function(self)
                    if self._cancelCommit then self._cancelCommit = nil; return end
                    local val = tonumber(self:GetText())
                    if not val then self:SetText(tostring(entry[threshKey] or threshDef)); return end
                    val = math.max(cfg.threshMin or 1, math.min(threshMaxVal, math.floor(val + 0.5)))
                    self:SetText(tostring(val))
                    local bd2 = cfg.getBarData(); if not bd2 then return end
                    local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[idx]
                    if ent then ent[threshKey] = val; cfg.refreshFn() end
                end)
                ef._threshInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                ef._threshInput:SetScript("OnEscapePressed", function(self)
                    self._cancelCommit = true
                    self:SetText(tostring(entry[threshKey] or threshDef)); self:ClearFocus()
                end)

                if ef._entrySnap then ef._entrySnap() end
                if ef._entrySwatchSnap then ef._entrySwatchSnap() end
                if ef._multiSnap then ef._multiSnap() end

                -- Multi-band on: bands replace the single-threshold input + swatch
                local entEnabled = entry.thresholdEnabled
                if entEnabled == nil then entEnabled = true end
                local multiOn = entry.multiBandEnabled and true or false
                -- Single threshold and multi-band are independent toggles; multi wins over single when both are on.
                if ef._multiToggle then
                    ef._multiToggle:SetAlpha(1)
                    ef._multiToggle:SetEnabled(true)
                end
                if ef._bandsBtn then
                    ef._bandsBtn:SetAlpha(multiOn and 1 or 0.35)
                    ef._bandsBtn:SetEnabled(multiOn)
                end
                if ef._cogBtn then ef._cogBtn:Show() end

                if multiOn then
                    ef._threshDisTip = "MULTI"
                    ef._threshDis:Show()
                elseif not entEnabled then
                    ef._threshDisTip = nil
                    ef._threshDis:Show()
                else
                    ef._threshDis:Hide()
                end

                -- Dim ONLY duplicates the resolver can never reach; per-spec/inactive-talent cards stay fully visible, and form entries (one per form) are never dimmed.
                ef:SetAlpha((not formMode) and ns._ERB_IsThresholdCardShadowed(entries, idx) and 0.45 or 1)

                ef:Show()
                curY = curY - ENTRY_H - ROW_GAP
            end

            local contentH = math.abs(curY) + POPUP_PAD
            scrollChild:SetSize(POPUP_W, math.max(1, contentH))
            local headerH = popup._headerH or 0
            local scrollH = math.min(contentH, popup._maxH - headerH)
            scrollH = math.max(scrollH, POPUP_PAD)
            popup._scrollFrame:SetHeight(scrollH)
            PP.Size(popup, POPUP_W, headerH + scrollH + POPUP_PAD)

            -- Entry list just changed: refresh the button's threshold notice badge.
            if cfg.noticeFn then cfg.noticeFn() end
        end

        local function TogglePopup_L(anchor)
            if not popup then BuildPopup_L() end
            if popup:IsShown() then popup:Hide(); return end
            wipe(_tempSpecSel)
            if _specDDRefresh then _specDDRefresh() end
            if hasFormToggle then
                if LayoutHeaderForMode then LayoutHeaderForMode(IsFormMode()) end
                if popup._modeSegRefresh then popup._modeSegRefresh() end
            end
            RefreshPopupEntries_L()
            if popup._scrollFrame then popup._scrollFrame:SetVerticalScroll(0) end
            popup:ClearAllPoints()
            popup:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
            popup:Show()
        end

        settingsBtn:SetScript("OnClick", function(self) TogglePopup_L(self) end)
        settingsBtn:HookScript("OnHide", function()
            if popup and popup:IsShown() then popup:Hide() end
        end)

        return settingsBtn
    end -- BuildThresholdSettingsButton

    -- Threshold notice badge: an info bubble in the Settings button's top-left corner
    -- naming every spec that has a threshold configured, so a spec's setup stays visible
    -- from a page that doesn't list it. Green while none of them applies to the spec being
    -- played, orange while one does. Motion-only and click-through (same recipe as the
    -- Spec Overrides badge) so the button keeps its own hover and click.
    local THR_NOTE_IDLE   = { 0x0c/255, 0xd2/255, 0x9d/255, "0cd29d" }
    local THR_NOTE_ACTIVE = { 1, 0x8c/255, 0x26/255, "ff8c26" }
    -- getBarData: fn() -> bar table. pageSpecID: the Advanced page's spec, else nil.
    -- Returns the updater so callers can re-run it after an edit.
    local function AttachThresholdNotice(anchorBtn, getBarData, pageSpecID)
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
            local list, active = ns.ThresholdNoticeInfo(getBarData(), pageSpecID)
            if not list then
                if EllesmereUI.HideWidgetTooltip and badge:IsMouseOver() then EllesmereUI.HideWidgetTooltip() end
                badge:Hide()
                ApplyBorderTint(THR_BORDER_WHITE)
                return
            end
            local c = active and THR_NOTE_ACTIVE or THR_NOTE_IDLE
            badge._color = c
            ico:SetVertexColor(c[1], c[2], c[3], badge:IsMouseOver() and 1 or 0.85)
            local tip = "|cff" .. c[4] .. EllesmereUI.L("Thresholds configured for:") .. "|r " .. list
            local lead = active and EllesmereUI.L("Current Spec is affected by Threshold Settings.")
                or EllesmereUI.L("Current Spec is not affected by Threshold Settings.")
            badge._tip = "|cff" .. c[4] .. lead .. "|r\n\n" .. tip
            badge:Show()
            ApplyBorderTint(c)
        end
        anchorBtn:HookScript("OnShow", Update)
        EllesmereUI.RegisterWidgetRefresh(Update)
        Update()
        return Update
    end

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
        local function Snap(val)
            return math.floor(val * cScale + 0.5) / cScale
        end

        local w, h = Snap(cb.width), Snap(cb.height)
        local bs = cb.borderSize

        -- Container size: icon (hxh) + bar (only when icon shown)
        local hasIcon = cb.showIcon ~= false
        local iconFree = ns.ERB_CastIconFree(cb)
        local iconW = (hasIcon and not iconFree) and Snap(blizz and ns.ERB_CastIconW(cb) or h) or 0
        pf.container:SetSize(w + iconW, h)

        -- Scale down to fit when the cast bar is wider than the panel
        local PAD = EllesmereUI.CONTENT_PAD or 10
        local hdr = pf.container:GetParent()
        local availW = (hdr:GetWidth() - PAD * 2) / _castBarPreviewScale
        local fitScale = 1
        if (w + iconW) > availW and (w + iconW) > 0 and availW > 0 then
            fitScale = availW / (w + iconW)
        end
        pf.container:SetScale(_castBarPreviewScale * fitScale)

        pf.container:ClearAllPoints(); pf.container:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        -- Bar frame (sits beside the icon; iconOnRight puts the icon on the right)
        local iconOnRight = hasIcon and cb.iconOnRight
        pf.barFrame:SetSize(w, h)
        pf.barFrame:ClearAllPoints()
        pf.barFrame:SetPoint("LEFT", pf.container, "LEFT", iconOnRight and 0 or iconW, 0)

        -- Background
        local texKey = cb.texture
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
        local hintH = (_previewHintFS and _previewHintFS:IsShown()) and 35 or 0
        EllesmereUI:UpdateContentHeaderHeight(80 + hintH)
    end

    local _castBarPreviewBuilder = function(hdr, hdrW)
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
        local function Snap(val)
            return math.floor(val * cScale + 0.5) / cScale
        end

        local w, h = Snap(cb.width), Snap(cb.height)
        local hasIcon = cb.showIcon ~= false
        local iconW = hasIcon and Snap(h) or 0

        -- Scale down to fit when the cast bar is wider than the panel
        local PAD = EllesmereUI.CONTENT_PAD or 10
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

        -- Create hit overlays for preview click-to-scroll
        wipe(_hitOverlays)
        local overlayLevel = container:GetFrameLevel() + 20
        CreateHitOverlay(barFrame, "castBar", overlayLevel)
        CreateHitOverlay(iconFrame, "castIcon", overlayLevel + 5)
        if cb.showTimer then
            local ttHit = CreateFrame("Frame", nil, bar)
            ttHit:SetPoint("TOPLEFT", timerText, "TOPLEFT", -2, 2)
            ttHit:SetPoint("BOTTOMRIGHT", timerText, "BOTTOMRIGHT", 2, -2)
            CreateHitOverlay(ttHit, "castTimer", overlayLevel + 5)
        end
        if cb.showSpellText then
            local stHit = CreateFrame("Frame", nil, bar)
            stHit:SetPoint("TOPLEFT", spellText, "TOPLEFT", -2, 2)
            stHit:SetPoint("BOTTOMRIGHT", spellText, "BOTTOMRIGHT", 2, -2)
            CreateHitOverlay(stHit, "castSpellText", overlayLevel + 5)
        end

        -- Hint text
        local TOTAL_H = 80
        _headerBaseH = TOTAL_H
        local hintShown = not IsPreviewHintDismissed()
        if hintShown then
            if not _previewHintFS then
                local hintHost = CreateFrame("Frame", nil, hdr)
                hintHost:SetAllPoints(hdr)
                _previewHintFS = EllesmereUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
            end
            _previewHintFS:GetParent():SetParent(hdr)
            _previewHintFS:GetParent():Show()
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 20)
            _previewHintFS:Show()
            TOTAL_H = TOTAL_H + 35
        elseif _previewHintFS then
            _previewHintFS:Hide()
        end

        return TOTAL_H
    end

    -- Shared helpers for the section and page builders under ResourceBars_Options\
    -- (loaded before this file, read when a page builds). Preview state stays
    -- here; the pages write it through the two setters.
    ns._ERB_OptEnv = {
        DB = DB, PP = PP, Refresh = Refresh,
        SmoothRefresh = SmoothRefresh, RefreshHealth = RefreshHealth, RebuildHealth = RebuildHealth,
        AddFormBarBtn = AddFormBarBtn, AddFormTextBtn = AddFormTextBtn, AttachThresholdNotice = AttachThresholdNotice,
        BuildHashCog = BuildHashCog, BuildThresholdSettingsButton = BuildThresholdSettingsButton, RefreshPower = RefreshPower,
        RebuildPower = RebuildPower, RefreshClass = RefreshClass, RebuildClass = RebuildClass,
        ShowBandEditor = ShowBandEditor, ShowBuffEditor = ShowBuffEditor, ShowSpenderEditor = ShowSpenderEditor,
        BAND_HELP_TIP = BAND_HELP_TIP, BAND_REPLACES_TIP = BAND_REPLACES_TIP, BUFF_HELP_TIP = BUFF_HELP_TIP,
        SPENDER_HELP_TIP = SPENDER_HELP_TIP, STAGGER_PCT_TIP = STAGGER_PCT_TIP, CLASS_COLORS = CLASS_COLORS,
        SIDE_PAD = SIDE_PAD, THR_BORDER_WHITE = THR_BORDER_WHITE, PAGE_DISPLAY = PAGE_DISPLAY,
        _clickMappings = _clickMappings, _previewHeaderBuilder = _previewHeaderBuilder, CLASSIC_SYNC_KEYS = CLASSIC_SYNC_KEYS,
        CLASSIC_MATCH_KEYS = CLASSIC_MATCH_KEYS, ShuffleCastBarIcons = ShuffleCastBarIcons, UpdateCastBarPreview = UpdateCastBarPreview,
        _castBarPreviewBuilder = _castBarPreviewBuilder,
        SetDisplayPreviewValues = function(pipCount, fillPct)
            _previewPipCount = pipCount
            _previewBarFillPct = fillPct
        end,
        SetCastBarPreviewFill = function(v) _castBarPreviewFill = v end,
    }

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
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
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
                UpdateCastBarPreview()
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
