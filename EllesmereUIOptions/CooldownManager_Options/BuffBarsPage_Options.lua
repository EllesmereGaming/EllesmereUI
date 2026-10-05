if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\BuffBarsPage_Options.lua
--  Cooldown Manager options: the Tracking Bars page with its state, preview
--  popout, placeholders, pickers and stack threshold editor. One init
--  function, called by EUI_CooldownManager_Options.lua where this code used to
--  run, so its hooks and frames are created at the same point and in the same
--  order as before.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
if not ns then return end  -- module disabled: no options page

local function InitBuffBarsPage(PP, DB, Refresh, FONT_PATH, GetCDMOptOutline, GateBlizzardOnly, PAGE_BUFF_BARS)
    ---------------------------------------------------------------------------
    --  Buff Bars page: per-bar tracked buff bars with individual settings
    ---------------------------------------------------------------------------
    local _tbbSelectedBar = 1
    local _tbbSelectedGroup      -- nil = editing a bar; gid = editing that group
    -- Deep-link helper (Global Settings > Glows): select a tracking bar by index.
    function ns._TBBSelectBar(idx)
        _tbbSelectedBar = idx
        _tbbSelectedGroup = nil
    end
    local _tbbDDBtn              -- live management-dropdown button (picker anchor)
    local _tbbNavigateFn         -- set per page build: click-to-scroll handler

    ---------------------------------------------------------------------------
    --  Popout preview docked to the options panel's left edge (raid-frame overlay
    --  preview pattern). Bars are built/skinned by the SAME runtime functions as live
    --  bars (CreateTBBBarFrame/ApplyTBBBarSettings), then dressed with sample fill/timer/
    --  stacks. Bar mode: selected bar with click-to-scroll overlays. Group mode: every
    --  bar of the group chained with its grow/spacing, each clickable to edit.
    ---------------------------------------------------------------------------
    local _tbbPopout
    local _tbbPopoutBars = {}     -- pooled preview wraps (runtime-built)

    local function GetTBBPopout()
        if _tbbPopout then return _tbbPopout end
        local oc = CreateFrame("Frame", nil, UIParent)
        oc:SetFrameStrata("FULLSCREEN_DIALOG")
        oc:SetFrameLevel(10)
        oc:SetClampedToScreen(true)
        oc:Hide()
        local bg = oc:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.9)
        local title = oc:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        title:SetPoint("TOP", oc, "TOP", 0, -7)
        title:SetTextColor(1, 1, 1, 0.9)
        oc._title = title
        local hint = oc:CreateFontString(nil, "OVERLAY")
        hint:SetFont(FONT_PATH, 10, GetCDMOptOutline())
        hint:SetPoint("BOTTOM", oc, "BOTTOM", 0, 7)
        hint:SetTextColor(1, 1, 1, 0.4)
        oc._hint = hint
        _tbbPopout = oc
        return oc
    end

    local function HideTBBPopout()
        if _tbbPopout then _tbbPopout:Hide() end
    end

    -- Pooled hover/click overlay on a preview element (green border, like unit frame
    -- preview overlays); retargeted every refresh.
    local function TBBPvNavButton(wrap, key)
        wrap._pvNav = wrap._pvNav or {}
        local btn = wrap._pvNav[key]
        if not btn then
            btn = CreateFrame("Button", nil, wrap)
            local c = EllesmereUI.ELLESMERE_GREEN
            btn._brd = PP.CreateBorder(btn, c.r, c.g, c.b, 1, 2, "OVERLAY", 7)
            btn._brd:Hide()
            btn:SetScript("OnEnter", function(self)
                self._brd:Show()
                if self._tip then EllesmereUI.ShowWidgetTooltip(self, self._tip) end
            end)
            btn:SetScript("OnLeave", function(self)
                self._brd:Hide()
                EllesmereUI.HideWidgetTooltip()
            end)
            btn:SetScript("OnMouseDown", function(self)
                if self._onNav then self._onNav() end
            end)
            wrap._pvNav[key] = btn
        end
        return btn
    end

    local function HideTBBPvNav(wrap)
        if not wrap._pvNav then return end
        for _, b in pairs(wrap._pvNav) do b:Hide() end
    end

    -- Attach nav overlays for one preview bar. Bar mode: element overlays scroll to and
    -- flash their option rows; group mode: one whole-bar overlay selects the bar for editing.
    local function UpdateTBBPvNav(wrap, mode, barIdx)
        HideTBBPvNav(wrap)
        if mode == "group" then
            local btn = TBBPvNavButton(wrap, "select")
            btn:ClearAllPoints()
            btn:SetAllPoints(wrap)
            btn:SetFrameLevel(wrap:GetFrameLevel() + 30)
            btn._tip = EllesmereUI.L("Click to edit this bar")
            btn._onNav = function()
                _tbbSelectedBar = barIdx
                _tbbSelectedGroup = nil
                EllesmereUI:RefreshPage(true)
            end
            btn:Show()
            return
        end
        local sb = wrap._bar
        local function ElemBtn(key, elem, isText)
            if not elem or not elem.IsShown or not elem:IsShown() then return end
            if isText and (elem:GetText() or "") == "" then return end
            local btn = TBBPvNavButton(wrap, key)
            btn:ClearAllPoints()
            if isText then
                local tw = (elem:GetStringWidth() or 0) + 6
                local th = (elem:GetStringHeight() or 0) + 6
                if tw < 14 then tw = 14 end
                if th < 14 then th = 14 end
                btn:SetSize(tw, th)
                -- Anchor by justification: FontString width > string width, so CENTER isn't where glyphs render.
                local justify = elem.GetJustifyH and elem:GetJustifyH() or "LEFT"
                if justify == "RIGHT" then
                    btn:SetPoint("RIGHT", elem, "RIGHT", 2, 0)
                elseif justify == "CENTER" then
                    btn:SetPoint("CENTER", elem, "CENTER", 0, 0)
                else
                    btn:SetPoint("LEFT", elem, "LEFT", -2, 0)
                end
            else
                btn:SetAllPoints(elem)
            end
            btn:SetFrameLevel(wrap:GetFrameLevel() + (isText and 32 or 30))
            btn._tip = nil
            btn._onNav = function()
                if _tbbNavigateFn then _tbbNavigateFn(key) end
            end
            btn:Show()
        end
        ElemBtn("barFill", sb, false)
        ElemBtn("icon", wrap._icon, false)
        ElemBtn("nameText", wrap._nameText, true)
        ElemBtn("timerText", wrap._timerText, true)
        ElemBtn("stacksText", wrap._stacksText, true)
    end

    -- Preview-only dressing over live skinning: sample fill, sample timer/stacks text,
    -- resolved name/icon, and the unassigned overlay.
    local function DressTBBPopoutBar(wrap, cfg)
        local sb = wrap._bar
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(0.65)
        if wrap._timerText and wrap._timerText:IsShown() then
            wrap._timerText:SetText("3.2")
        end
        -- Stacks visibility is tick-driven on live bars; drive it from cfg here
        if wrap._stacksText then
            if (cfg.stacksPosition or "center") ~= "none" then
                wrap._stacksText:SetText("3")
                wrap._stacksText:Show()
            else
                wrap._stacksText:Hide()
            end
        end
        local unassigned = (not cfg.spellID or cfg.spellID == 0) and not cfg.glowBased
        -- Name (same resolution as the live build)
        if wrap._nameText and wrap._nameText:IsShown() then
            local displayName = cfg.name
            if (not displayName or displayName == "" or displayName == "New Bar")
               and cfg.spellID and cfg.spellID > 0 then
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                displayName = (info and info.name) or displayName
            end
            if unassigned then displayName = "" end
            wrap._nameText:SetText(EllesmereUI.L(displayName or ""))
        end
        -- Icon texture (same resolution as the live build; question mark when no buff assigned yet)
        if wrap._icon and wrap._icon:IsShown() and wrap._icon._tex then
            local iconID
            if cfg.popularKey and ns.TBB_POPULAR_BUFFS then
                for _, pe in ipairs(ns.TBB_POPULAR_BUFFS) do
                    if pe.key == cfg.popularKey then iconID = pe.icon; break end
                end
            end
            if not iconID and cfg.spellID and cfg.spellID > 0 then
                local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                iconID = spInfo and spInfo.iconID
            end
            wrap._icon._tex:SetTexture(iconID or 134400)
        end
        -- Unassigned: dim ALL bar content (fill/texts/icon/border) under a black overlay
        -- frame with a centered hint, above the bar's own layers so it draws over the fill/gradient stack.
        if not wrap._pvDarkFrame then
            local df = CreateFrame("Frame", nil, wrap)
            df:SetAllPoints(wrap)
            local tex = df:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetColorTexture(0, 0, 0, 0.6)
            local hintFS = df:CreateFontString(nil, "OVERLAY")
            hintFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            hintFS:SetTextColor(1, 1, 1, 1)
            hintFS:SetJustifyH("CENTER")
            hintFS:SetText(EllesmereUI.L("Choose a buff from the bar menu"))
            wrap._pvDarkFrame = df
            wrap._pvHint = hintFS
        end
        -- Frame level: above text overlay (+6) and border (+5), below click overlays (+30).
        wrap._pvDarkFrame:SetFrameLevel(wrap:GetFrameLevel() + 20)
        wrap._pvHint:ClearAllPoints()
        wrap._pvHint:SetPoint("CENTER", sb, "CENTER", 0, 0)
        wrap._pvDarkFrame:SetShown(unassigned)
    end

    -- Vertical headroom for texts anchored above/below the bar (outside its bounds).
    local function TBBPvTextPad(cfg, side)
        local tp = cfg.timerPosition or (cfg.showTimer and "right" or "none")
        local sp = cfg.stacksPosition or "center"
        local np = cfg.verticalOrientation and "none"
            or (cfg.namePosition or ((cfg.showName ~= false) and "left" or "none"))
        local p = 0
        if tp == side then p = math.max(p, cfg.timerSize or 11) end
        if sp == side then p = math.max(p, cfg.stacksSize or 11) end
        if np == side then p = math.max(p, cfg.nameSize or 11) end
        return p > 0 and (p + 8) or 0
    end

    -- HARD gate for BOTH Tracking Bars preview systems (popout + unlock-style
    -- placeholders): never visible unless the panel is actually OPEN on the Tracking
    -- Bars page. activeModule/activePage alone is NOT enough -- both persist after close,
    -- and event-driven refreshes (saved positions, spec/instance events) rebuild this page with the panel hidden. Every show path funnels through this check.
    local function TBBPreviewAllowed()
        -- Folded to the mini window counts as closed (the page is off screen).
        if not (EllesmereUI:IsShown()) or EllesmereUI._panelCollapsed then return false end
        -- nil = mid-build (page state not stamped); builders only run for the page shown, so only a definite mismatch blocks.
        local am = EllesmereUI:GetActiveModule()
        local ap = EllesmereUI:GetActivePage()
        if am and ap and (am ~= "EllesmereUICooldownManager" or ap ~= PAGE_BUFF_BARS) then
            return false
        end
        return true
    end

    local function RefreshTBBPopout()
        if not TBBPreviewAllowed() then
            HideTBBPopout()
            return
        end
        local t = ns.GetTrackedBuffBars()
        local bars = t and t.bars or {}

        -- Configs to render: the selected group's members, or the selected bar
        local list = {}
        local mode = "bar"
        if _tbbSelectedGroup then
            mode = "group"
            for i, c in ipairs(bars) do
                if ns.TBBBarGroupID(c) == _tbbSelectedGroup then
                    list[#list + 1] = { idx = i, cfg = c }
                end
            end
        else
            local c = bars[_tbbSelectedBar]
            if c then list[1] = { idx = _tbbSelectedBar, cfg = c } end
        end
        if #list == 0 then HideTBBPopout(); return end

        local oc = GetTBBPopout()

        -- Build/refresh each preview bar with the LIVE bar code
        for n, e in ipairs(list) do
            local wrap = _tbbPopoutBars[n]
            if not wrap then
                wrap = ns.CreateTBBBarFrame(oc, "Pv" .. n)
                _tbbPopoutBars[n] = wrap
                -- Width-gated geometry (charge hash lines, threshold ticks) silently skips
                -- while a fresh pool bar's fill size is 0; live bars re-drive from the timer
                -- tick, previews have none, so re-drive when size resolves.
                if wrap._bar then
                    wrap._bar:SetScript("OnSizeChanged", function(sbSelf)
                        local cfg = wrap._pvCfg
                        if not cfg then return end
                        if ns.ApplyTBBChargeHashLines then
                            local mc = ns.GetTBBMaxCharges and ns.GetTBBMaxCharges(cfg)
                            ns.ApplyTBBChargeHashLines(wrap, cfg, mc)
                        end
                        if ns.ApplyTBBTickMarks then
                            ns.ApplyTBBTickMarks(sbSelf, cfg, wrap._threshTicks,
                                cfg.verticalOrientation, wrap._tickOverlay)
                            wrap._ticksDirty = nil
                        end
                    end)
                end
            end
            wrap._pvCfg = e.cfg
            ns.ApplyTBBBarSettings(wrap, e.cfg)
            -- The apply path pins the wrap to the bar's own strata (cfg.strata,
            -- MEDIUM default); lift into the popout's strata AFTER each apply
            -- and re-assert the constructor's child levels (a parent strata
            -- change resets child frame levels). Guarded so refreshes that
            -- didn't touch strata skip the re-stack; level checked too, else a
            -- bar whose OWN strata is the popout's would dodge the lift.
            local base = oc:GetFrameLevel() + 20
            if wrap:GetFrameStrata() ~= "FULLSCREEN_DIALOG" or wrap:GetFrameLevel() ~= base then
                wrap:SetFrameStrata("FULLSCREEN_DIALOG")
                wrap:SetFrameLevel(base)
                local sb = wrap._bar
                if sb then sb:SetFrameLevel(base + 1) end
                if wrap._gradClip and sb then wrap._gradClip:SetFrameLevel(sb:GetFrameLevel() + 1) end
                if wrap._chargeHashFillClip and sb then wrap._chargeHashFillClip:SetFrameLevel(sb:GetFrameLevel() + 1) end
                if wrap._threshOverlays and sb then
                    for i = 1, #wrap._threshOverlays do
                        local ov = wrap._threshOverlays[i]
                        if ov then ov:SetFrameLevel(sb:GetFrameLevel() + 2) end
                    end
                end
                if wrap._sparkOverlay and sb then wrap._sparkOverlay:SetFrameLevel(sb:GetFrameLevel() + 3) end
                -- Tick overlay reassert; matches the live-bar block.
                if wrap._tickOverlay and sb then wrap._tickOverlay:SetFrameLevel(sb:GetFrameLevel() + 4) end
                if wrap._chargeHashOverlay and sb then wrap._chargeHashOverlay:SetFrameLevel(sb:GetFrameLevel() + 5) end
                -- base+6 matches the live-bar reassert: keeps the border above
                -- the tick overlay (sb+4 = base+5), which wins ties via lazy
                -- creation.
                if wrap._barBorder then wrap._barBorder:SetFrameLevel(base + 6) end
                if wrap._pandemicGlowOverlay then wrap._pandemicGlowOverlay:SetFrameLevel(base + 7) end
                if wrap._textOverlay and sb then wrap._textOverlay:SetFrameLevel(sb:GetFrameLevel() + 7) end
            end
            DressTBBPopoutBar(wrap, e.cfg)
            -- Reused pool bars already have a resolved size, so OnSizeChanged may never
            -- fire here: consume the deferred tick-mark pass (apply path drew hash lines itself when sized).
            local psb = wrap._bar
            if wrap._ticksDirty and psb and psb:GetWidth() > 0 and ns.ApplyTBBTickMarks then
                ns.ApplyTBBTickMarks(psb, e.cfg, wrap._threshTicks,
                    e.cfg.verticalOrientation, wrap._tickOverlay)
                wrap._ticksDirty = nil
            end
            wrap:Show()
        end
        for n = #list + 1, #_tbbPopoutBars do
            if _tbbPopoutBars[n] then
                HideTBBPvNav(_tbbPopoutBars[n])
                _tbbPopoutBars[n]:Hide()
            end
        end

        -- Chain layout: single bar centered; group members chained with the
        -- group's grow/spacing, exactly like the live BuildTrackedBuffBars
        local PAD_IN, TITLE_H = 20, 25
        local growDir, spacing = "DOWN", 2
        if mode == "group" then
            growDir = (ns.TBBGroupGrow(_tbbSelectedGroup) or "DOWN"):upper()
            spacing = ns.TBBGroupSpacing(_tbbSelectedGroup) or 2
        end
        local horizontalChain = mode == "group" and (growDir == "LEFT" or growDir == "RIGHT")

        local totalW, totalH = 0, 0
        for n = 1, #list do
            local wrap = _tbbPopoutBars[n]
            local w2, h2 = wrap:GetWidth(), wrap:GetHeight()
            if mode ~= "group" then
                totalW, totalH = w2, h2
            elseif horizontalChain then
                totalW = totalW + w2 + (n > 1 and spacing or 0)
                if h2 > totalH then totalH = h2 end
            else
                totalH = totalH + h2 + (n > 1 and spacing or 0)
                if w2 > totalW then totalW = w2 end
            end
        end
        local topPad, botPad = 0, 0
        for _, e in ipairs(list) do
            topPad = math.max(topPad, TBBPvTextPad(e.cfg, "top"))
            botPad = math.max(botPad, TBBPvTextPad(e.cfg, "bottom"))
        end

        -- Footer hint
        local hintH = 0
        if mode == "bar" then
            if not (EllesmereUIDB and EllesmereUIDB.previewHintDismissed) then
                oc._hint:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
                oc._hint:Show()
                hintH = 18
            else
                oc._hint:Hide()
            end
        else
            oc._hint:SetText(EllesmereUI.L("Click a bar to edit it"))
            oc._hint:Show()
            hintH = 18
        end

        oc:SetSize(math.max(totalW + PAD_IN * 2, 240),
            totalH + topPad + botPad + PAD_IN * 2 + TITLE_H + hintH)

        local firstY = -(PAD_IN + TITLE_H + topPad)
        local prev
        for n = 1, #list do
            local wrap = _tbbPopoutBars[n]
            wrap:ClearAllPoints()
            if n == 1 then
                if mode == "group" and growDir == "UP" then
                    wrap:SetPoint("BOTTOM", oc, "BOTTOM", 0, PAD_IN + botPad + hintH)
                elseif mode == "group" and growDir == "RIGHT" then
                    wrap:SetPoint("TOPLEFT", oc, "TOPLEFT", PAD_IN, firstY)
                elseif mode == "group" and growDir == "LEFT" then
                    wrap:SetPoint("TOPRIGHT", oc, "TOPRIGHT", -PAD_IN, firstY)
                else
                    wrap:SetPoint("TOP", oc, "TOP", 0, firstY)
                end
            else
                -- Same relative chain the live bars use
                if growDir == "UP" then
                    wrap:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
                elseif growDir == "RIGHT" then
                    wrap:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                elseif growDir == "LEFT" then
                    wrap:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
                else
                    wrap:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
                end
            end
            prev = wrap
            UpdateTBBPvNav(wrap, mode, list[n].idx)
        end

        if mode == "group" then
            local gname = (ns.TBBGroupName and ns.TBBGroupName(_tbbSelectedGroup))
                or (EllesmereUI.L("Group") .. " " .. _tbbSelectedGroup)
            oc._title:SetText(gname .. " " .. EllesmereUI.L("Preview"))
        else
            oc._title:SetText(EllesmereUI.L("Preview"))
        end

        -- Dock to the left edge of the options panel, vertically centered
        oc:ClearAllPoints()
        local sf = EllesmereUI._scrollFrame
        if sf then
            oc:SetPoint("RIGHT", sf, "LEFT", 0, 0)
        else
            oc:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        oc:Show()
    end

    -- Pool of unlock placeholders, one per bar (module-scope for cross-page access)
    local _tbbPlaceholders = {}
    local function UpdateTBBPlaceholder()
        -- Same hard gate as the popout: never show (or set placeholder mode) with the
        -- panel closed or another page in front. HideTBBPlaceholder is declared below.
        if not TBBPreviewAllowed() then
            ns._tbbPlaceholderMode = false
            for _, ph in ipairs(_tbbPlaceholders) do
                if ph then ph:Hide() end
            end
            HideTBBPopout()
            return
        end
        ns._tbbPlaceholderMode = true
        -- The TBB tick may be idle-asleep; placeholders render from the tick.
        if ns.WakeTBBTick then ns.WakeTBBTick() end
        local tbb = ns.GetTrackedBuffBars()
        local bars = tbb and tbb.bars
        if not bars then return end
        for i, _ in ipairs(bars) do
            local liveBar = ns.GetTBBFrame and ns.GetTBBFrame(i)
            if liveBar then
                if not _tbbPlaceholders[i] then
                    _tbbPlaceholders[i] = EllesmereUI.BuildUnlockPlaceholder({
                        parent = liveBar,
                        onClick = function()
                            if EllesmereUI._openUnlockMode then
                                EllesmereUI._unlockReturnModule = EllesmereUI:GetActiveModule()
                                EllesmereUI._unlockReturnPage   = EllesmereUI:GetActivePage()
                                C_Timer.After(0, EllesmereUI._openUnlockMode)
                            end
                        end,
                    })
                else
                    local ph = _tbbPlaceholders[i]
                    ph:SetParent(liveBar)
                    ph:SetAllPoints(liveBar)
                    ph:SetFrameLevel(liveBar:GetFrameLevel() + 10)
                end
                _tbbPlaceholders[i]:Show()
                liveBar:Show()
            end
        end
        -- Hide any leftover placeholders from deleted bars
        for i = (#bars + 1), #_tbbPlaceholders do
            if _tbbPlaceholders[i] then _tbbPlaceholders[i]:Hide() end
        end
    end
    local function HideTBBPlaceholder()
        ns._tbbPlaceholderMode = false
        for _, ph in ipairs(_tbbPlaceholders) do
            if ph then ph:Hide() end
        end
        -- The popout preview lives and dies with the page, same as placeholders
        -- (runs on every page-leave/panel-close path).
        HideTBBPopout()
    end
    ns.HideTBBPlaceholders = HideTBBPlaceholder
    ns.ShowTBBPlaceholders = UpdateTBBPlaceholder
    EllesmereUI:RegisterOnHide(HideTBBPlaceholder)
    -- Re-show placeholders when the panel re-opens on Tracking Bars. Exiting unlock mode
    -- to the SAME page skips SelectPage (currentPage == restorePage), so the page-restore
    -- hook that calls ShowTBBPlaceholders never fires; this OnShow re-asserts them.
    local function ReassertTBBPreviews()
        local am = EllesmereUI:GetActiveModule()
        local ap = EllesmereUI:GetActivePage()
        if am == "EllesmereUICooldownManager" and ap == PAGE_BUFF_BARS then
            UpdateTBBPlaceholder()
            RefreshTBBPopout()
        end
    end
    EllesmereUI:RegisterOnShow(ReassertTBBPreviews)
    -- The popout sits on UIParent beside the panel: it folds away with the panel
    -- and comes back with it (the live-bar placeholders stay up as the preview).
    EllesmereUI:RegisterOnCollapse(function(on)
        if on then HideTBBPopout() else ReassertTBBPreviews() end
    end)

    -- Every CDM page + its selected-bar index are per-spec, but the options panel caches
    -- built pages, so after a swap the cache holds the PREVIOUS spec's wrappers. A shared-
    -- profile spec swap never runs RefreshAllAddons (the cache clear), so without explicit
    -- invalidation reopening serves stale content: drop the CDM page cache, RefreshPage in place if open.
    local _tbbRefreshFn
    local function HandleTBBSpecChange()
        _tbbSelectedBar = 1
        _tbbSelectedGroup = nil
        EllesmereUI:InvalidateModulePageCache("EllesmereUICooldownManager")
        if EllesmereUI:IsShown()
            and EllesmereUI:GetActiveModule() == "EllesmereUICooldownManager"
            and EllesmereUI.RefreshPage then
            -- Panel open on a CDM page: rebuild now (content-header dropdown + body).
            EllesmereUI:RefreshPage(true)
        else
            -- Panel closed (or another module): reopening takes the fast RefreshPage path
            -- (dropdown not rebuilt) and SelectPage early-returns on the same page, so the
            -- dropdown would keep the previous spec's bar. Flag a cold rebuild for next show.
            ns._cdmColdRebuildOnShow = true
        end
    end

    -- Authoritative trigger: CDM's ProcessSpecChange calls this AFTER swapping the
    -- spec-key cache (_cachedSpecKey), so the rebuild reads the NEW spec. The
    -- PLAYER_SPECIALIZATION_CHANGED watcher below is a backup (covers panel-closed cache
    -- drop too); it can fire early and read the old spec, but ProcessSpecChange corrects it after.
    ns.OnTBBSpecChanged = HandleTBBSpecChange

    local _tbbSpecWatcher = CreateFrame("Frame")
    _tbbSpecWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _tbbSpecWatcher:SetScript("OnEvent", HandleTBBSpecChange)

    -- Bars auto-added while the panel sits on Tracking Bars (e.g. user drags a new spell
    -- into Blizzard's Tracked Bars and returns): rebuild the open page immediately.
    ns.OnTBBBarsAutoAdded = function()
        if EllesmereUI:IsShown()
            and EllesmereUI:GetActiveModule() == "EllesmereUICooldownManager"
            and EllesmereUI:GetActivePage() == PAGE_BUFF_BARS
            and EllesmereUI.RefreshPage then
            EllesmereUI:RefreshPage(true)
        end
    end

    -- A spec swap while the panel is CLOSED can't rebuild (nothing shown); honor the
    -- pending cold rebuild here so reopening directly onto a CDM page rebuilds fresh.
    EllesmereUI:RegisterOnShow(function()
        if not ns._cdmColdRebuildOnShow then return end
        if EllesmereUI:GetActiveModule() == "EllesmereUICooldownManager"
            and EllesmereUI.RefreshPage then
            ns._cdmColdRebuildOnShow = false
            EllesmereUI:RefreshPage(true)
        end
    end)

    -- Buff spell picker for tracked buff bars (reuses CDM buff spell list)
    local _tbbSpellPickerMenu

    EllesmereUI:RegisterOnHide(function()
        if _tbbSpellPickerMenu then _tbbSpellPickerMenu:Hide() end
    end)

    -- Show the "Custom Buff ID" popup with Spell ID + Duration fields
    local function ShowCustomBuffIDPopup(anchorFrame, barCfg, onChanged)
        local popupName = "EUI_TBB_CustomBuffPopup"
        local popup = _G[popupName]
        if not popup then
            local POPUP_W, POPUP_H = 320, 210
            local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:Hide()
            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)

            popup = CreateFrame("Frame", popupName, dimmer)
            popup:SetSize(POPUP_W, POPUP_H)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            popup:EnableMouse(true)
            local popBg = popup:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints(); popBg:SetColorTexture(0.077, 0.068, 0.058, 1)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)

            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
            title:SetPoint("TOP", popup, "TOP", 0, -18)
            title:SetTextColor(1, 1, 1, 1)
            title:SetText(EllesmereUI.L("Custom Buff ID"))

            local sidLbl = popup:CreateFontString(nil, "OVERLAY")
            sidLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            sidLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", 24, -52)
            sidLbl:SetTextColor(0.7, 0.7, 0.7, 1)
            sidLbl:SetText(EllesmereUI.L("Spell ID"))

            local sidBox = CreateFrame("EditBox", nil, popup)
            sidBox:SetSize(180, 28)
            sidBox:SetPoint("TOPLEFT", sidLbl, "BOTTOMLEFT", 0, -4)
            sidBox:SetAutoFocus(false)
            sidBox:SetNumeric(true)
            sidBox:SetMaxLetters(7)
            sidBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            sidBox:SetTextColor(1, 1, 1, 0.9)
            sidBox:SetJustifyH("LEFT")
            local sidBg = sidBox:CreateTexture(nil, "BACKGROUND")
            sidBg:SetAllPoints(); sidBg:SetColorTexture(0.060, 0.049, 0.037, 1)
            EllesmereUI.MakeBorder(sidBox, 1, 1, 1, 0.12, EllesmereUI.PP)
            local sidPh = sidBox:CreateFontString(nil, "ARTWORK")
            sidPh:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            sidPh:SetPoint("LEFT", sidBox, "LEFT", 4, 0)
            sidPh:SetTextColor(0.5, 0.5, 0.5, 0.5)
            sidPh:SetText(EllesmereUI.L("e.g. 12345"))
            sidBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then sidPh:Show() else sidPh:Hide() end
            end)
            popup._sidBox = sidBox

            local durLbl = popup:CreateFontString(nil, "OVERLAY")
            durLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            durLbl:SetPoint("TOPLEFT", sidBox, "BOTTOMLEFT", 0, -12)
            durLbl:SetTextColor(0.7, 0.7, 0.7, 1)
            durLbl:SetText(EllesmereUI.L("Duration (seconds)"))

            local durBox = CreateFrame("EditBox", nil, popup)
            durBox:SetSize(180, 28)
            durBox:SetPoint("TOPLEFT", durLbl, "BOTTOMLEFT", 0, -4)
            durBox:SetAutoFocus(false)
            durBox:SetNumeric(true)
            durBox:SetMaxLetters(5)
            durBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            durBox:SetTextColor(1, 1, 1, 0.9)
            durBox:SetJustifyH("LEFT")
            local durBg = durBox:CreateTexture(nil, "BACKGROUND")
            durBg:SetAllPoints(); durBg:SetColorTexture(0.060, 0.049, 0.037, 1)
            EllesmereUI.MakeBorder(durBox, 1, 1, 1, 0.12, EllesmereUI.PP)
            local durPh = durBox:CreateFontString(nil, "ARTWORK")
            durPh:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            durPh:SetPoint("LEFT", durBox, "LEFT", 4, 0)
            durPh:SetTextColor(0.5, 0.5, 0.5, 0.5)
            durPh:SetText(EllesmereUI.L("e.g. 30"))
            durBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then durPh:Show() else durPh:Hide() end
            end)
            popup._durBox = durBox

            local status = popup:CreateFontString(nil, "OVERLAY")
            status:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            status:SetPoint("TOP", durBox, "BOTTOM", 0, -6)
            status:SetTextColor(1, 0.3, 0.3, 1)
            status:SetText("")
            popup._status = status
            popup._statusTimer = nil

            local ar, ag, ab = EllesmereUI.GetAccentColor()
            local addBtn = CreateFrame("Button", nil, popup)
            addBtn:SetSize(80, 28)
            addBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
            local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
            addBg:SetAllPoints(); addBg:SetColorTexture(ar, ag, ab, 0.15)
            EllesmereUI.MakeBorder(addBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
            local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
            addLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            addLbl:SetPoint("CENTER"); addLbl:SetText(EllesmereUI.L("Add"))
            addLbl:SetTextColor(ar, ag, ab, 0.9)
            addBtn:SetScript("OnEnter", function() addLbl:SetTextColor(1, 1, 1, 1) end)
            addBtn:SetScript("OnLeave", function() addLbl:SetTextColor(ar, ag, ab, 0.9) end)
            popup._addBtn = addBtn

            local cancelBtn = CreateFrame("Button", nil, popup)
            cancelBtn:SetSize(80, 28)
            cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)
            local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
            cBg:SetAllPoints(); cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
            EllesmereUI.MakeBorder(cancelBtn, 1, 1, 1, 0.10, EllesmereUI.PP)
            local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
            cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            cLbl:SetPoint("CENTER"); cLbl:SetText(EllesmereUI.L("Cancel"))
            cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
            cancelBtn:SetScript("OnEnter", function() cLbl:SetTextColor(1, 1, 1, 1) end)
            cancelBtn:SetScript("OnLeave", function() cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8) end)
            cancelBtn:SetScript("OnClick", function() dimmer:Hide() end)
            popup._cancelBtn = cancelBtn

            sidBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)
            durBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)

            popup._dimmer = dimmer
            _G[popupName] = popup
        end

        local curSID = (barCfg.spellID and barCfg.spellID > 0 and not barCfg.popularKey) and barCfg.spellID or nil
        local curDur = barCfg.customDuration or nil
        popup._sidBox:SetText(curSID and tostring(curSID) or "")
        popup._durBox:SetText(curDur and tostring(curDur) or "")
        popup._status:SetText("")

        local function SetStatus(text, r, g, b)
            popup._status:SetText(text)
            popup._status:SetTextColor(r or 1, g or 0.3, b or 0.3, 1)
            if popup._statusTimer then popup._statusTimer:Cancel() end
            if text ~= "" then
                popup._statusTimer = C_Timer.NewTimer(2.5, function()
                    popup._status:SetText("")
                end)
            end
        end

        popup._addBtn:SetScript("OnClick", function()
            local sid = tonumber(popup._sidBox:GetText())
            local dur = tonumber(popup._durBox:GetText())
            if not sid or sid <= 0 then SetStatus("Enter a valid spell ID"); return end
            sid = math.floor(sid)
            if not C_Spell.GetSpellName(sid) then SetStatus("Unknown spell ID"); return end
            if not dur or dur <= 0 then SetStatus("Enter a duration in seconds"); return end
            dur = math.floor(dur)
            popup._dimmer:Hide()
            barCfg.spellID        = sid
            barCfg.spellIDs       = nil
            barCfg.popularKey     = nil
            barCfg.glowBased      = nil
            barCfg.trackType      = nil
            barCfg.customDuration = dur
            -- Manually-entered id has no live frame to read the base from: clear stale
            -- base; MatchFrameToConfig self-heals it once talented.
            barCfg.baseSpellID    = nil
            barCfg.name           = C_Spell.GetSpellName(sid)
            Refresh()
            ns.BuildTrackedBuffBars()
            if onChanged then onChanged() end
        end)

        ns.PadPopupOpen(popup._dimmer, popup, popup._cancelBtn)  -- controller cursor
        popup._dimmer:Show()
        popup._sidBox:SetFocus()
    end

    local function ShowTBBSpellPicker(anchorFrame, barCfg, onChanged)
        if _tbbSpellPickerMenu then _tbbSpellPickerMenu:Hide() end

        local trackedBars = ns.GetTrackedBarSpells and ns.GetTrackedBarSpells(true) or {}
        local popular = ns.TBB_POPULAR_BUFFS or {}

        -- No early bail on empty trackedBars -- the picker still shows popular presets and the custom spell ID input.

        local mBgR  = EllesmereUI.DD_BG_R  or 0.075
        local mBgG  = EllesmereUI.DD_BG_G  or 0.113
        local mBgB  = EllesmereUI.DD_BG_B  or 0.141
        local mBgA  = EllesmereUI.DD_BG_HA or 0.98
        local mBrdA = EllesmereUI.DD_BRD_A or 0.20
        local hlA   = EllesmereUI.DD_ITEM_HL_A or 0.08
        local tDimR = EllesmereUI.TEXT_DIM_R or 0.7
        local tDimG = EllesmereUI.TEXT_DIM_G or 0.7
        local tDimB = EllesmereUI.TEXT_DIM_B or 0.7
        local tDimA = EllesmereUI.TEXT_DIM_A or 0.85
        local ACCENT = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }

        local menuW = 240
        local ITEM_H = 26
        local MAX_H = 340

        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetClampedToScreen(true)
        menu:SetSize(menuW, 10)

        local mbg = menu:CreateTexture(nil, "BACKGROUND")
        mbg:SetAllPoints(); mbg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

        local inner = CreateFrame("Frame", nil, menu)
        inner:SetWidth(menuW)
        inner:SetPoint("TOPLEFT")

        local mH = 4

        -- "Custom Buff ID" entry at the top
        local isCustomSelected = barCfg.spellID and barCfg.spellID > 0 and not barCfg.popularKey and not barCfg.spellIDs and barCfg.trackType ~= "cooldown"
        local csItem = CreateFrame("Button", nil, inner)
        csItem:SetHeight(ITEM_H)
        csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        csItem:SetFrameLevel(menu:GetFrameLevel() + 2)
        local csHl = csItem:CreateTexture(nil, "ARTWORK", nil, -1)
        csHl:SetAllPoints(); csHl:SetColorTexture(1, 1, 1, 0)
        local csLbl = csItem:CreateFontString(nil, "OVERLAY")
        csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        csLbl:SetPoint("LEFT", 10, 0)
        csLbl:SetJustifyH("LEFT")
        csLbl:SetText(EllesmereUI.L("Custom Buff ID"))
        csLbl:SetTextColor(isCustomSelected and 1 or tDimR, isCustomSelected and 1 or tDimG, isCustomSelected and 1 or tDimB, isCustomSelected and 1 or tDimA)
        csItem:SetScript("OnEnter", function() csLbl:SetTextColor(1,1,1,1); csHl:SetColorTexture(1,1,1,hlA) end)
        csItem:SetScript("OnLeave", function()
            csLbl:SetTextColor(isCustomSelected and 1 or tDimR, isCustomSelected and 1 or tDimG, isCustomSelected and 1 or tDimB, isCustomSelected and 1 or tDimA)
            csHl:SetColorTexture(1,1,1,0)
        end)
        csItem:SetScript("OnClick", function()
            menu:Hide()
            ShowCustomBuffIDPopup(anchorFrame, barCfg, onChanged)
        end)
        mH = mH + ITEM_H

        local div1 = inner:CreateTexture(nil, "ARTWORK")
        div1:SetHeight(1); div1:SetColorTexture(1, 1, 1, 0.10)
        div1:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        div1:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9

        -- Popular buff entries
        local function MakePopularItem(entry)
            local isSelected = barCfg.popularKey == entry.key
            local item = CreateFrame("Button", nil, inner)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(menu:GetFrameLevel() + 2)

            local ico = item:CreateTexture(nil, "ARTWORK")
            local icoSz = ITEM_H - 4
            ico:SetSize(icoSz, icoSz)
            ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            ico:SetTexture(entry.icon)
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local baseR = isSelected and 1 or tDimR
            local baseG = isSelected and 1 or tDimG
            local baseB = isSelected and 1 or tDimB
            local baseA = isSelected and 1 or tDimA

            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            lbl:SetPoint("LEFT", 8, 0)
            lbl:SetPoint("RIGHT", ico, "LEFT", -4, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false); lbl:SetMaxLines(1)
            lbl:SetText(EllesmereUI.L(entry.name))
            lbl:SetTextColor(baseR, baseG, baseB, baseA)

            local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)

            item:SetScript("OnEnter", function() lbl:SetTextColor(1,1,1,1); hl:SetColorTexture(1,1,1,hlA) end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(baseR, baseG, baseB, baseA)
                hl:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)
            end)
            item:SetScript("OnClick", function()
                menu:Hide()
                barCfg.popularKey     = entry.key
                barCfg.spellIDs       = entry.spellIDs
                barCfg.glowBased      = entry.glowBased or nil
                barCfg.customDuration = entry.customDuration
                barCfg.spellID        = entry.spellIDs and entry.spellIDs[1] or 0
                barCfg.baseSpellID    = nil
                barCfg.trackType      = nil
                barCfg.name           = entry.name
                Refresh()
                ns.BuildTrackedBuffBars()
                if onChanged then onChanged() end
            end)
            mH = mH + ITEM_H
        end

        local _, _tbbPClass = UnitClass("player")
        local nPopular = 0
        for _, entry in ipairs(popular) do
            -- tbbOnly presets (e.g. debuff-driven Bloodlust) carry a sentinel class to hide
            -- from the cooldown/utility item picker; the TBB picker overrides that and always shows them.
            if entry.tbbOnly or not entry.class or entry.class == _tbbPClass then
                MakePopularItem(entry)
                nPopular = nPopular + 1
            end
        end

        -- "Buffs" section always renders (even with no tracked bars) so the Missing Spells prompt below stays visible.
        -- Its divider closes the preset rows, so it is skipped when none were built
        -- (WoW Forever has no presets): the one above already separates Custom Buff ID.
        do
            if nPopular > 0 then
                local div2 = inner:CreateTexture(nil, "ARTWORK")
                div2:SetHeight(1); div2:SetColorTexture(1, 1, 1, 0.10)
                div2:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                div2:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9
            end

            local buffHdr = inner:CreateFontString(nil, "OVERLAY")
            buffHdr:SetFont(FONT_PATH, 10, GetCDMOptOutline())
            buffHdr:SetTextColor(1, 1, 1, 0.5)
            buffHdr:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -mH - 5)
            buffHdr:SetText(EllesmereUI.L("Buffs"))
            mH = mH + 20
        end

        local function MakeSpellItem(sp)
            -- Every spell here came from BuffBarCooldownViewer enumeration, so it's by definition tracked -- no popup needed.
            local usedOnBar = ns.SpellUsedOnAnyOtherTBB and ns.SpellUsedOnAnyOtherTBB(sp.spellID, nil)
            -- A family bar (Roll the Bones) is selected by its base id OR any member,
            -- since the row resolves to the active outcome while one is up.
            local isSelected = not barCfg.popularKey
                             and barCfg.trackType ~= "cooldown"
                             and barCfg.spellID and barCfg.spellID > 0 and barCfg.spellID == sp.spellID
            if not isSelected and barCfg.spellIDs and not barCfg.popularKey
               and barCfg.trackType ~= "cooldown" then
                for _, sid in ipairs(barCfg.spellIDs) do
                    if sid == sp.spellID then isSelected = true; break end
                end
            end
            local item = CreateFrame("Button", nil, inner)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(menu:GetFrameLevel() + 2)

            local ico = item:CreateTexture(nil, "ARTWORK")
            local icoSz = ITEM_H - 4
            ico:SetSize(icoSz, icoSz)
            ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            if sp.icon then ico:SetTexture(sp.icon) end
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local baseR = isSelected and 1 or tDimR
            local baseG = isSelected and 1 or tDimG
            local baseB = isSelected and 1 or tDimB
            local baseA = isSelected and 1 or tDimA

            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            lbl:SetPoint("LEFT", 8, 0)
            lbl:SetPoint("RIGHT", ico, "LEFT", -4, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false); lbl:SetMaxLines(1)
            lbl:SetText(EllesmereUI.L(sp.name))
            lbl:SetTextColor(baseR, baseG, baseB, baseA)

            local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)

            -- Gray out if already used on another bar
            if usedOnBar and not isSelected then
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                ico:SetDesaturated(true); ico:SetAlpha(0.4)
                item:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.Lf("Already assigned to %s", EllesmereUI.L(usedOnBar)))
                    hl:SetColorTexture(1, 1, 1, hlA * 0.3); hl:SetAlpha(1)
                end)
                item:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                    hl:SetAlpha(0)
                end)
                mH = mH + ITEM_H
                return
            end

            -- Tracked-but-untalented bar spells (no live BuffBar frame) stay clickable but
            -- render desaturated with a hint (matches CD/utility pickers), so bars can be set without swapping talents.
            local notLearned = (sp.isKnown == false)
            if notLearned then ico:SetDesaturated(true); ico:SetAlpha(0.5) end
            item:SetScript("OnEnter", function()
                lbl:SetTextColor(1,1,1,1); hl:SetColorTexture(1,1,1,hlA)
                if notLearned then EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.L("Not currently talented")) end
            end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(baseR, baseG, baseB, baseA)
                hl:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)
                if notLearned then EllesmereUI.HideWidgetTooltip() end
            end)
            item:SetScript("OnClick", function()
                if notLearned then EllesmereUI.HideWidgetTooltip() end
                menu:Hide()
                barCfg.spellID        = sp.spellID
                barCfg.spellIDs       = nil
                barCfg.popularKey     = nil
                barCfg.glowBased      = nil
                barCfg.customDuration = nil
                barCfg.trackType      = nil
                barCfg.name           = sp.name
                -- Capture the BASE spell id for hero-talent override spells so the bar keeps
                -- tracking after the talent is removed (active override's cooldownInfo
                -- reports base in info.spellID); store only when it differs from the picked id.
                barCfg.baseSpellID = nil
                if sp.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(sp.cdID)
                    local RTB_BASE_SPELL_ID = 1214909
                    local isSec = issecretvalue
                    local baseSID = info and info.spellID
                    if baseSID and (isSec and isSec(baseSID)) then baseSID = nil end
                    if baseSID and baseSID > 0 and baseSID ~= sp.spellID then
                        barCfg.baseSpellID = baseSID
                    end
                    -- Roll the Bones: ONE tracked-bar slot cycles through mutually
                    -- exclusive outcome buffs, listed only in the raw linkedSpellIDs.
                    -- The row resolves to whichever outcome is up at pick time, so a
                    -- single id matches nothing else after a re-roll: store the whole
                    -- family as the want-set and key the config on the stable base.
                    if baseSID == RTB_BASE_SPELL_ID and type(info.linkedSpellIDs) == "table" then
                        local ids = {}
                        for i = 1, #info.linkedSpellIDs do
                            local lid = info.linkedSpellIDs[i]
                            if type(lid) == "number" and not (isSec and isSec(lid)) and lid > 0 then
                                ids[#ids + 1] = lid
                            end
                        end
                        if #ids >= 2 then
                            barCfg.spellIDs    = ids
                            barCfg.spellID     = baseSID
                            barCfg.baseSpellID = nil
                            local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(baseSID)
                            if nm and nm ~= "" then barCfg.name = nm end
                        end
                    end
                end
                Refresh()
                ns.BuildTrackedBuffBars()
                if onChanged then onChanged() end
            end)
            mH = mH + ITEM_H
        end

        for _, sp in ipairs(trackedBars) do MakeSpellItem(sp) end

        -- "Missing Spells?" prompt (centered, accent-colored) closes EUI options and opens
        -- Blizzard's CDM; sits at the end of Buffs so it reads as the way to add more.
        do
            local FOOTER_H = 38
            local mbItem = CreateFrame("Button", nil, inner)
            mbItem:SetHeight(FOOTER_H)
            mbItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            mbItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            mbItem:SetFrameLevel(menu:GetFrameLevel() + 2)

            local mbFS = mbItem:CreateFontString(nil, "OVERLAY")
            mbFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            mbFS:SetAllPoints()
            mbFS:SetJustifyH("CENTER")
            mbFS:SetJustifyV("MIDDLE")
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            mbFS:SetTextColor(ar, ag, ab, 1)
            mbFS:SetText(EllesmereUI.L("Missing Spells? Add as") .. "\n" .. EllesmereUI.L("Tracking Bar in Blizz CDM"))

            mbItem:SetScript("OnEnter", function() mbFS:SetTextColor(1, 1, 1, 1) end)
            mbItem:SetScript("OnLeave", function()
                local r, g, b = EllesmereUI.GetAccentColor()
                mbFS:SetTextColor(r, g, b, 1)
            end)
            mbItem:SetScript("OnClick", function()
                menu:Hide()
                if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
            end)
            mH = mH + FOOTER_H
        end

        -- "Cooldowns" section: pick a spell COOLDOWN to track instead of a buff
        -- (cfg.trackType="cooldown"), sourced from Essential+Utility pools + settings catalog; skipped when empty.
        local cdSpells = ns.GetCDMSpellsForBar and ns.GetCDMSpellsForBar("cooldowns") or {}
        if #cdSpells > 0 then
            local cdDiv = inner:CreateTexture(nil, "ARTWORK")
            cdDiv:SetHeight(1); cdDiv:SetColorTexture(1, 1, 1, 0.10)
            cdDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            cdDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9

            local cdHdr = inner:CreateFontString(nil, "OVERLAY")
            cdHdr:SetFont(FONT_PATH, 10, GetCDMOptOutline())
            cdHdr:SetTextColor(1, 1, 1, 0.5)
            cdHdr:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -mH - 5)
            cdHdr:SetText(EllesmereUI.L("Cooldowns"))
            mH = mH + 20

            local function MakeCooldownItem(sp)
                -- Gray-out check is scoped to OTHER cooldown-tracking bars -- a buff bar for the same spell never blocks this pick.
                local usedOnBar = ns.SpellUsedOnAnyOtherTBB and ns.SpellUsedOnAnyOtherTBB(sp.spellID, nil, "cooldown")
                local isSelected = barCfg.trackType == "cooldown"
                                 and not barCfg.popularKey and not barCfg.spellIDs
                                 and barCfg.spellID and barCfg.spellID > 0 and barCfg.spellID == sp.spellID
                local item = CreateFrame("Button", nil, inner)
                item:SetHeight(ITEM_H)
                item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                item:SetFrameLevel(menu:GetFrameLevel() + 2)

                local ico = item:CreateTexture(nil, "ARTWORK")
                local icoSz = ITEM_H - 4
                ico:SetSize(icoSz, icoSz)
                ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
                if sp.icon then ico:SetTexture(sp.icon) end
                ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                local baseR = isSelected and 1 or tDimR
                local baseG = isSelected and 1 or tDimG
                local baseB = isSelected and 1 or tDimB
                local baseA = isSelected and 1 or tDimA

                local lbl = item:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                lbl:SetPoint("LEFT", 8, 0)
                lbl:SetPoint("RIGHT", ico, "LEFT", -4, 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetWordWrap(false); lbl:SetMaxLines(1)
                lbl:SetText(EllesmereUI.L(sp.name))
                lbl:SetTextColor(baseR, baseG, baseB, baseA)

                local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)

                -- Gray out if already used on another cooldown-tracking bar
                if usedOnBar and not isSelected then
                    lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                    ico:SetDesaturated(true); ico:SetAlpha(0.4)
                    item:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.Lf("Already assigned to %s", EllesmereUI.L(usedOnBar)))
                        hl:SetColorTexture(1, 1, 1, hlA * 0.3); hl:SetAlpha(1)
                    end)
                    item:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                        hl:SetAlpha(0)
                    end)
                    mH = mH + ITEM_H
                    return
                end

                -- Untalented catalog spells stay clickable but render desaturated with a hint, matching the buff rows above.
                local notLearned = (sp.isKnown == false)
                if notLearned then ico:SetDesaturated(true); ico:SetAlpha(0.5) end
                item:SetScript("OnEnter", function()
                    lbl:SetTextColor(1,1,1,1); hl:SetColorTexture(1,1,1,hlA)
                    if notLearned then EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.L("Not currently talented")) end
                end)
                item:SetScript("OnLeave", function()
                    lbl:SetTextColor(baseR, baseG, baseB, baseA)
                    hl:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)
                    if notLearned then EllesmereUI.HideWidgetTooltip() end
                end)
                item:SetScript("OnClick", function()
                    if notLearned then EllesmereUI.HideWidgetTooltip() end
                    menu:Hide()
                    barCfg.spellID        = sp.spellID
                    barCfg.spellIDs       = nil
                    barCfg.popularKey     = nil
                    barCfg.glowBased      = nil
                    barCfg.customDuration = nil
                    barCfg.trackType      = "cooldown"
                    barCfg.name           = sp.name
                    -- Capture the BASE spell id for hero-talent override spells so the bar keeps tracking after the talent is removed.
                    barCfg.baseSpellID = nil
                    if sp.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(sp.cdID)
                        if info and info.spellID and info.spellID > 0 and info.spellID ~= sp.spellID then
                            barCfg.baseSpellID = info.spellID
                        end
                    end
                    Refresh()
                    ns.BuildTrackedBuffBars()
                    if onChanged then onChanged() end
                end)
                mH = mH + ITEM_H
            end

            for _, sp in ipairs(cdSpells) do MakeCooldownItem(sp) end
        end

        local totalH = mH + 4
        inner:SetHeight(totalH)
        if totalH > MAX_H then
            menu:SetHeight(MAX_H)
            local sf = CreateFrame("ScrollFrame", nil, menu)
            sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
            sf:SetFrameLevel(menu:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            sf:SetScrollChild(inner)
            inner:SetWidth(menuW)
            local scrollPos = 0
            local maxScroll = totalH - MAX_H
            sf:SetScript("OnMouseWheel", function(_, delta)
                scrollPos = math.max(0, math.min(maxScroll, scrollPos - delta * 30))
                sf:SetVerticalScroll(scrollPos)
            end)
        else
            menu:SetHeight(totalH)
            inner:SetParent(menu)
            inner:SetPoint("TOPLEFT")
        end

        menu:ClearAllPoints()
        menu:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -2)
        menu:SetScript("OnUpdate", function(m)
            if not m:IsMouseOver() and not anchorFrame:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                m:Hide()
            end
        end)
        menu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)
        menu:Show()
        _tbbSpellPickerMenu = menu
    end

    -- Select a bar and open its buff picker anchored to the management dropdown (used by
    -- the dropdown's bar rows); page refresh runs first so the picker anchors to the fresh button.
    local function OpenBuffPickerForBar(idx)
        _tbbSelectedBar = idx
        _tbbSelectedGroup = nil
        EllesmereUI:RefreshPage(true)
        C_Timer.After(0, function()
            local t = ns.GetTrackedBuffBars()
            local cfg = t.bars and t.bars[idx]
            if cfg and _tbbDDBtn and _tbbDDBtn:IsShown() then
                ShowTBBSpellPicker(_tbbDDBtn, cfg, function()
                    EllesmereUI:RefreshPage(true)
                end)
            end
        end)
    end

    -- Smallest unused "Preset N" default name for the save popup.
    local function UniqueTBBPresetName()
        local presets = ns.GetTBBStylePresets and ns.GetTBBStylePresets() or {}
        local function taken(nm)
            for _, pr in ipairs(presets) do
                if pr.name == nm then return true end
            end
            return false
        end
        local n = 1
        while taken("Preset " .. n) do n = n + 1 end
        return "Preset " .. n
    end

    ---------------------------------------------------------------------------
    --  Stack threshold editor (opt-in) popup, opened from the cog on "Enable Stack
    --  Threshold"; edits cfg.stackThresholds -- an ordered list of {value=<stack count>,
    --  r,g,b,a} color stops capped at STACK_THRESH_MAX. Only drives rendering while
    --  cfg.stackThresholdMulti is on (else legacy single-threshold keys own the bar).
    --  ShowStackThreshEditor() rebinds per calling bar.
    ---------------------------------------------------------------------------
    local STACK_THRESH_MAX = 5
    local _stCloseIcon = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
    local stPopup
    local _stRows = {}
    local _stGetCfg, _stRefreshFn
    local _stMultiRow, _stMultiSnap, _stAddBtn, _stAddLbl
    local ST_POPUP_W = 260
    local ST_ROW_H = 26
    local ST_PAD = 14
    local ST_GAP = 10
    local ST_DEF_R, ST_DEF_G, ST_DEF_B, ST_DEF_A = 0.8, 0.1, 0.1, 1
    local RefreshStackThreshEditor  -- forward decl

    -- Shared explainers; literals live inside the L() calls so extract-locale-keys.sh can
    -- see them (it only reads string literals passed directly to L/Lf, never variables).
    local function StackThreshHelpTip()
        return EllesmereUI.L("Color the bar differently at several stack counts. The highest count you have reached wins.")
    end
    local function StackThreshReplacesTip()
        return EllesmereUI.L("The single stack threshold is off while Multiple Thresholds is on.")
    end
    local function StackThreshAtCapTip()
        return EllesmereUI.L("Maximum of 5 thresholds.")
    end

    local function CurrentStackThreshCfg()
        if not _stGetCfg then return nil end
        return _stGetCfg()
    end

    local function SortStackThresholds(list)
        table.sort(list, function(a, b) return (a.value or 0) < (b.value or 0) end)
    end

    local function BuildStackThreshPopup()
        stPopup = CreateFrame("Frame", nil, UIParent)
        stPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        stPopup:SetFrameLevel(260)
        stPopup:SetClampedToScreen(true)
        stPopup:EnableMouse(true)
        stPopup:SetScale(0.9)
        stPopup:Hide()
        PP.Size(stPopup, ST_POPUP_W, 200)

        local bg = stPopup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.97)
        PP.CreateBorder(stPopup, 1, 1, 1, 0.18, 1, "BORDER", 7)

        local clickCatcher = CreateFrame("Button", nil, stPopup)
        clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        clickCatcher:SetFrameLevel(stPopup:GetFrameLevel() - 1)
        clickCatcher:SetAllPoints((EllesmereUI:GetMainFrame()) or UIParent)
        clickCatcher:SetScript("OnClick", function() stPopup:Hide() end)
        clickCatcher:Hide()
        -- Close on entering combat
        stPopup:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_DISABLED" then self:Hide() end
        end)
        stPopup:SetScript("OnShow", function(self)
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
        stPopup:SetScript("OnHide", function(self)
            clickCatcher:Hide()
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", nil)
        end)

        local titleFS = EllesmereUI.MakeFont(stPopup, 13, nil, 1, 1, 1)
        titleFS:SetAlpha(0.6)
        titleFS:SetPoint("TOP", stPopup, "TOP", 0, -ST_PAD)
        titleFS:SetText(EllesmereUI.L("Stack Thresholds"))

        -- Row: multi opt-in (label left, toggle right) -- matches the band editor.
        _stMultiRow = CreateFrame("Frame", nil, stPopup)
        _stMultiRow:SetFrameLevel(stPopup:GetFrameLevel() + 3)
        PP.Height(_stMultiRow, ST_ROW_H)
        local mlbl = EllesmereUI.MakeFont(_stMultiRow, 12, nil, 1, 1, 1)
        mlbl:SetAlpha(0.6)
        mlbl:SetPoint("LEFT", _stMultiRow, "LEFT", 0, 0)
        mlbl:SetText(EllesmereUI.L("Use Multiple Thresholds"))
        local multiToggle
        multiToggle, _, _stMultiSnap = EllesmereUI.BuildToggleControl(
            _stMultiRow, _stMultiRow:GetFrameLevel() + 3,
            function()
                local cfg = CurrentStackThreshCfg()
                return cfg and cfg.stackThresholdMulti
            end,
            function(v)
                local cfg = CurrentStackThreshCfg(); if not cfg then return end
                cfg.stackThresholdMulti = v and true or false
                if _stRefreshFn then _stRefreshFn() end
                RefreshStackThreshEditor()
                EllesmereUI:RefreshPage()
            end,
            { sizeRatio = 0.95 })
        multiToggle:SetPoint("RIGHT", _stMultiRow, "RIGHT", 0, 0)
        local multiHit = CreateFrame("Frame", nil, _stMultiRow)
        multiHit:SetAllPoints(mlbl)
        multiHit:EnableMouse(true)
        multiHit:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, StackThreshHelpTip()) end)
        multiHit:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        -- Add Threshold button
        _stAddBtn = CreateFrame("Button", nil, stPopup)
        PP.Size(_stAddBtn, ST_POPUP_W - ST_PAD * 2, 26)
        _stAddBtn:SetFrameLevel(stPopup:GetFrameLevel() + 3)
        local abg = EllesmereUI.SolidTex(_stAddBtn, "BACKGROUND", 0.069, 0.058, 0.047, 0.92)
        abg:SetAllPoints()
        _stAddBtn._border = EllesmereUI.MakeBorder(_stAddBtn, 1, 1, 1, 0.4, PP)
        _stAddLbl = EllesmereUI.MakeFont(_stAddBtn, 12, nil, 1, 1, 1)
        _stAddLbl:SetAlpha(0.5)
        _stAddLbl:SetPoint("CENTER")
        _stAddLbl:SetText(EllesmereUI.L("+ Add Threshold"))
        _stAddBtn:SetScript("OnEnter", function(self)
            local cfg = CurrentStackThreshCfg()
            local list = cfg and cfg.stackThresholds
            if list and #list >= STACK_THRESH_MAX then
                EllesmereUI.ShowWidgetTooltip(self, StackThreshAtCapTip())
                return
            end
            _stAddLbl:SetAlpha(0.7)
            if self._border and self._border.SetColor then self._border:SetColor(1, 1, 1, 0.6) end
        end)
        _stAddBtn:SetScript("OnLeave", function(self)
            EllesmereUI.HideWidgetTooltip()
            _stAddLbl:SetAlpha(0.5)
            if self._border and self._border.SetColor then self._border:SetColor(1, 1, 1, 0.4) end
        end)
        _stAddBtn:SetScript("OnClick", function()
            local cfg = CurrentStackThreshCfg(); if not cfg then return end
            if not cfg.stackThresholds then cfg.stackThresholds = {} end
            local list = cfg.stackThresholds
            if #list >= STACK_THRESH_MAX then return end
            local last = list[#list]
            local nextVal = last and math.min(100, (last.value or 0) + 1) or 5
            list[#list + 1] = { value = nextVal, r = ST_DEF_R, g = ST_DEF_G, b = ST_DEF_B, a = ST_DEF_A }
            SortStackThresholds(list)
            if _stRefreshFn then _stRefreshFn() end
            RefreshStackThreshEditor()
        end)
    end

    -- Lazily create the widgets for threshold row k; returns the row table.
    local function EnsureStackThreshRow(k)
        local row = _stRows[k]
        if row then return row end
        row = {}
        local rf = CreateFrame("Frame", nil, stPopup)
        rf:SetSize(ST_POPUP_W - ST_PAD * 2, ST_ROW_H)
        rf:SetFrameLevel(stPopup:GetFrameLevel() + 2)
        row.frame = rf

        local lbl = EllesmereUI.MakeFont(rf, 12, nil, 1, 1, 1)
        lbl:SetAlpha(0.6)
        lbl:SetPoint("LEFT", rf, "LEFT", 2, 0)
        lbl:SetText(EllesmereUI.L("At"))
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

        -- Commit on focus loss (Enter clears focus -> triggers this; Escape sets
        -- _cancelCommit to discard the typed text).
        local function CommitInput(self)
            if self._cancelCommit then self._cancelCommit = nil; return end
            local cfg = CurrentStackThreshCfg()
            local list = cfg and cfg.stackThresholds
            local ent = list and list[row._idx]
            if not ent then return end
            local val = tonumber(self:GetText())
            if val then
                -- Same range as the single-threshold slider on the Extras row.
                ent.value = math.max(0, math.min(100, math.floor(val + 0.5)))
                SortStackThresholds(list)
                if _stRefreshFn then _stRefreshFn() end
            end
            RefreshStackThreshEditor()
        end
        input:SetScript("OnEditFocusLost", CommitInput)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self._cancelCommit = true; self:ClearFocus(); RefreshStackThreshEditor() end)

        local swatch, swatchSnap = EllesmereUI.BuildColorSwatch(rf, rf:GetFrameLevel() + 3,
            function()
                local cfg = CurrentStackThreshCfg()
                local list = cfg and cfg.stackThresholds
                local ent = list and list[row._idx]
                if not ent then return ST_DEF_R, ST_DEF_G, ST_DEF_B, ST_DEF_A end
                return ent.r or ST_DEF_R, ent.g or ST_DEF_G, ent.b or ST_DEF_B, ent.a or ST_DEF_A
            end,
            function(r, g, b, a)
                local cfg = CurrentStackThreshCfg()
                local list = cfg and cfg.stackThresholds
                local ent = list and list[row._idx]
                if ent then
                    ent.r, ent.g, ent.b, ent.a = r, g, b, a
                    if _stRefreshFn then _stRefreshFn() end
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
        delIcon:SetTexture(_stCloseIcon)
        delIcon:SetAlpha(0.4)
        delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
        delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
        delBtn:SetScript("OnClick", function()
            local cfg = CurrentStackThreshCfg()
            local list = cfg and cfg.stackThresholds
            if list and list[row._idx] then
                table.remove(list, row._idx)
                -- An empty list would silently fall back to the single threshold while the
                -- toggle still reads "on"; turn it off so the popup matches the bar.
                if #list == 0 and cfg.stackThresholdMulti then
                    cfg.stackThresholdMulti = false
                    EllesmereUI:RefreshPage()
                end
                if _stRefreshFn then _stRefreshFn() end
                RefreshStackThreshEditor()
            end
        end)
        row.delBtn = delBtn

        _stRows[k] = row
        return row
    end

    RefreshStackThreshEditor = function()
        if not stPopup then return end
        local cfg = CurrentStackThreshCfg()
        if not cfg then stPopup:Hide(); return end
        if not cfg.stackThresholds then cfg.stackThresholds = {} end
        local list = cfg.stackThresholds

        local curY = -(ST_PAD + 24)  -- below the title

        _stMultiRow:ClearAllPoints()
        PP.Point(_stMultiRow, "TOPLEFT", stPopup, "TOPLEFT", ST_PAD, curY)
        PP.Point(_stMultiRow, "TOPRIGHT", stPopup, "TOPRIGHT", -ST_PAD, curY)
        _stMultiRow:Show()
        if _stMultiSnap then _stMultiSnap() end
        curY = curY - ST_ROW_H - ST_GAP

        local n = #list
        for k = 1, n do
            local row = EnsureStackThreshRow(k)
            row._idx = k
            row.frame:ClearAllPoints()
            PP.Point(row.frame, "TOPLEFT", stPopup, "TOPLEFT", ST_PAD, curY)
            row.input:SetText(tostring(list[k].value or 5))
            if row.swatchSnap then row.swatchSnap() end
            row.frame:Show()
            curY = curY - ST_ROW_H - 4
        end
        for k = n + 1, #_stRows do
            if _stRows[k] then _stRows[k].frame:Hide() end
        end

        curY = curY - 4
        _stAddBtn:ClearAllPoints()
        PP.Point(_stAddBtn, "TOPLEFT", stPopup, "TOPLEFT", ST_PAD, curY)
        local atCap = (n >= STACK_THRESH_MAX)
        _stAddBtn:SetEnabled(not atCap)
        _stAddBtn:SetAlpha(atCap and 0.35 or 1)
        curY = curY - 26

        local totalH = math.abs(curY) + ST_PAD
        PP.Size(stPopup, ST_POPUP_W, totalH)
    end

    -- params = { getCfg, refreshFn, anchor }
    local function ShowStackThreshEditor(params)
        if not stPopup then BuildStackThreshPopup() end
        _stGetCfg   = params.getCfg
        _stRefreshFn = params.refreshFn
        local cfg = CurrentStackThreshCfg()
        if cfg then
            if not cfg.stackThresholds then cfg.stackThresholds = {} end
            -- Seed the first entry from the single threshold the first time; inert until
            -- stackThresholdMulti is on, so opening/closing this popup changes nothing on the bar.
            if #cfg.stackThresholds == 0 then
                cfg.stackThresholds[1] = {
                    value = cfg.stackThreshold or 5,
                    r = cfg.stackThresholdR or ST_DEF_R, g = cfg.stackThresholdG or ST_DEF_G,
                    b = cfg.stackThresholdB or ST_DEF_B, a = cfg.stackThresholdA or ST_DEF_A,
                }
            end
        end
        RefreshStackThreshEditor()
        stPopup:ClearAllPoints()
        stPopup:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
        stPopup:Show()
    end

    local function BuildBuffBarsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -- If user chose Blizzard bars, show re-enable button and bail
        local usingBlizz = DB() and DB().cdmBars and DB().cdmBars.useBlizzardBuffBars
        if usingBlizz then
            _, h = W:WideDualButton(parent,
                "Enable Tracking Bars", "Open Blizzard CDM", y,
                function()
                    local p = DB()
                    if p and p.cdmBars then
                        p.cdmBars.useBlizzardBuffBars = false
                    end
                    EllesmereUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "Switching to EllesmereUI Tracking Bars requires a reload.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload    = true,
                    })
                end,
                function()
                    if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
                end, 310);  y = y - h
            return math.abs(y)
        end

        -- Pre-populate bars for spells newly added to Blizzard's Tracked Bars before
        -- reading the bar list, so the page always shows them.
        if ns.EnsureTBBAutoBars and ns.EnsureTBBAutoBars() > 0 then
            ns.BuildTrackedBuffBars()
        end

        local tbb = ns.GetTrackedBuffBars()
        -- Hold the per-group orientation invariant before any widget reads the configs
        -- (the page-tail rebuild runs after).
        if ns.EnforceTBBGroupOrientation then ns.EnforceTBBGroupOrientation(tbb) end
        local bars = tbb.bars
        if _tbbSelectedBar > #bars then _tbbSelectedBar = math.max(1, #bars) end

        local function SelectedTBB()
            local t = ns.GetTrackedBuffBars()
            if _tbbSelectedBar < 1 or _tbbSelectedBar > #t.bars then return nil end
            return t.bars[_tbbSelectedBar]
        end

        local function SelectedTBBSupportsChargeHash()
            local bd = SelectedTBB()
            return bd and ns.GetTBBMaxCharges
                and ns.GetTBBMaxCharges(bd) ~= nil
        end

        -- Validate the group selection against the live group list (groups dissolve when
        -- their last bar is deleted). Bar-less GLOBAL groups are legal selections: the
        -- Currently Editing menu lists them on every spec precisely so their shared
        -- settings stay editable, and their local gid persists through its globalKey
        -- link with no member bars (every GROUP MODE section is group-keyed and the
        -- previews hide/guard on an empty member list).
        if _tbbSelectedGroup then
            local ok = false
            for _, g in ipairs(ns.TBBGroupIDsInUse()) do
                if g == _tbbSelectedGroup then ok = true; break end
            end
            if not ok and ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(_tbbSelectedGroup) then
                ok = true
            end
            if not ok then _tbbSelectedGroup = nil end
        end

        -- The preview mirrors whatever is being edited: the selected bar, or the selected
        -- group's style source (its anchor bar).
        local function PreviewCfg()
            if _tbbSelectedGroup then
                return ns.TBBGroupStyleSource(_tbbSelectedGroup)
            end
            return SelectedTBB()
        end

        local function GroupLabel(gid)
            return (ns.TBBGroupName and ns.TBBGroupName(gid))
                or (EllesmereUI.L("Group") .. " " .. gid)
        end

        -------------------------------------------------------------------
        --  CLICK NAVIGATION (preview elements -> option rows). Map lives on
        --  parent._tbbClickTargets (populated by the bar-mode section build below);
        --  overlays resolve it at click time so a header rebuild never holds stale refs.
        -------------------------------------------------------------------
        local PlaySettingGlow = EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN })

        local function NavigateToSetting(key)
            local targets = parent._tbbClickTargets
            if not targets then return end
            local m = targets[key]
            if not m or not m.section or not m.target then return end
            EllesmereUIDB = EllesmereUIDB or {}
            EllesmereUIDB.previewHintDismissed = true
            if _tbbPopout and _tbbPopout._hint then _tbbPopout._hint:Hide() end
            local _, _, _, _, headerY = m.section:GetPoint(1)
            if not headerY then return end
            EllesmereUI.SmoothScrollTo(math.max(0, math.abs(headerY) - 40))
            local glowTarget = m.target
            if m.slotSide then
                local region = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
                if region then glowTarget = region end
            end
            C_Timer.After(0.15, function() PlaySettingGlow(glowTarget) end)
        end

        local _tbbRefreshTimer

        local function RefreshTBB()
            if _tbbRefreshTimer then _tbbRefreshTimer:Cancel() end
            _tbbRefreshTimer = C_Timer.NewTimer(0.05, function()
                _tbbRefreshTimer = nil
                Refresh()
                ns.BuildTrackedBuffBars()
                RefreshTBBPopout()
                UpdateTBBPlaceholder()
            end)
        end
        -- Expose this build's RefreshTBB to the outer spec-change watcher so a spec swap
        -- while this page is open rebuilds the dropdown/preview.
        _tbbRefreshFn = RefreshTBB

        -- Drag-and-drop move: put a bar into another group (or make it independent).
        -- Joining a group adopts its current look, same as a freshly added bar; selects the moved bar.
        local function MoveBarToGroup(idx, gid)
            local t = ns.GetTrackedBuffBars()
            local cfg = t.bars and t.bars[idx]
            if not cfg then return end
            if ns.TBBBarGroupID(cfg) == gid then return end
            ns.TBBSetBarGroup(cfg, gid)
            if gid ~= 0 then
                local src = ns.TBBGroupStyleSource(gid)
                if src and src ~= cfg then ns.CopyTBBStyle(src, cfg) end
            end
            _tbbSelectedBar = idx
            _tbbSelectedGroup = nil
            ns.BuildTrackedBuffBars()
            EllesmereUI:RefreshPage(true)
        end

        -------------------------------------------------------------------
        --  MANAGEMENT DROPDOWN builder ("Currently Editing:"). Creates the bar/group
        --  selector inside `parentFrame` (Preset Style panel), returns the dropdown
        --  button; caller positions it.
        -------------------------------------------------------------------
        local function BuildManagementDropdown(parentFrame)
            local DD_H = 34
            local ddW = 350

            local DDS = EllesmereUI.DD_STYLE
            local mBgR  = DDS.BG_R
            local mBgG  = DDS.BG_G
            local mBgB  = DDS.BG_B
            local mBgA  = DDS.BG_A
            local mBgHA = DDS.BG_HA
            local mBrdA = DDS.BRD_A
            local mBrdHA = DDS.BRD_HA or 0.30
            local mTxtA = DDS.TXT_A
            local mTxtHA = DDS.TXT_HA or 1
            local hlA   = DDS.ITEM_HL_A
            local selA  = DDS.ITEM_SEL_A
            local tDimR = EllesmereUI.TEXT_DIM_R or 0.7
            local tDimG = EllesmereUI.TEXT_DIM_G or 0.7
            local tDimB = EllesmereUI.TEXT_DIM_B or 0.7
            local tDimA = EllesmereUI.TEXT_DIM_A or 0.85
            local ITEM_H = 26
            local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
            local ICON_SZ = 14

            local ddBtn = CreateFrame("Button", nil, parentFrame)
            PP.Size(ddBtn, ddW, DD_H)
            ddBtn:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
            local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
            ddBg:SetAllPoints(); ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
            local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, mBrdA, EllesmereUI.PanelPP)
            local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
            ddLbl:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            ddLbl:SetAlpha(mTxtA)
            ddLbl:SetJustifyH("LEFT")
            ddLbl:SetWordWrap(false); ddLbl:SetMaxLines(1)
            ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
            local arrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, EllesmereUI.PanelPP)
            ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

            local function UpdateDDLabel()
                if _tbbSelectedGroup then
                    local n = ns.TBBGroupedCount(_tbbSelectedGroup)
                    ddLbl:SetText(GroupLabel(_tbbSelectedGroup)
                        .. "  -  " .. n .. " " .. EllesmereUI.L(n == 1 and "Bar" or "Bars"))
                    return
                end
                local bd = SelectedTBB()
                if bd then
                    local label = (bd.name and EllesmereUI.L(bd.name)) or "Bar"
                    if not bd.popularKey and bd.spellID and bd.spellID > 0 then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(bd.spellID)
                        if info and info.name then label = info.name end
                    end
                    local gid = ns.TBBBarGroupID and ns.TBBBarGroupID(bd) or 0
                    if gid ~= 0 then
                        label = label .. "  (" .. GroupLabel(gid) .. ")"
                    end
                    ddLbl:SetText(label)
                else
                    -- Re-fetch the live (per-spec) bar count instead of the build-time `bars`
                    -- upvalue: this header builder is reused across SetContentHeader refreshes
                    -- (e.g. spec change) without a page rebuild, so captured `bars` can be stale.
                    local liveBars = ns.GetTrackedBuffBars().bars
                    if not liveBars or #liveBars == 0 then
                        ddLbl:SetText(EllesmereUI.L("No Bars - Click to Add"))
                    else
                        ddLbl:SetText(EllesmereUI.L("Select a bar"))
                    end
                end
            end
            UpdateDDLabel()

            -- Can this bar play Audio on Buff Gain / Loss? The one check behind the
            -- row right-click, the speaker mark and the menu hint. A sound follows a
            -- buff edge: the bar needs a buff assigned and tracked as a buff (never a
            -- cooldown-tracking bar), and the runtime needs an edge source for it (a
            -- Blizzard buff viewer frame, or a self-timed preset).
            local function BarTakesSound(b)
                if not b or b.trackType == "cooldown" then return false end
                if not ((b.spellID and b.spellID > 0) or b.glowBased) then return false end
                return ns.TBB_BarCanCue(b) and true or false
            end

            -- Right-click a bar row: Audio on Buff Gain / Loss for that bar, the
            -- tracking-bar twin of the CDM icon menu's two audio rows. Opens beside the
            -- clicked row; each row flies out the shared sound list (search, scroll,
            -- preview speaker) from BuildSoundDropdownValues. Same keys and sound
            -- catalogue as the icon menu; playback lives in EllesmereUICdmBuffBars.
            local function OpenBarSoundMenu(idx, anchorRow)
                local t = ns.GetTrackedBuffBars()
                local cfg = t.bars and t.bars[idx]
                if not cfg then return end
                if ddBtn._tbbSndMenu then ddBtn._tbbSndMenu:Hide() end
                local W = 240
                local sm = CreateFrame("Frame", nil, UIParent)
                sm:SetFrameStrata("FULLSCREEN_DIALOG")
                -- Above the bar menu it opens from (300), which stays open underneath.
                sm:SetFrameLevel(320)
                sm:SetClampedToScreen(true)
                sm:EnableMouse(true)
                sm:SetSize(W, 8 + ITEM_H * 2)
                local smBg = sm:CreateTexture(nil, "BACKGROUND")
                smBg:SetAllPoints(); smBg:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
                EllesmereUI.MakeBorder(sm, 1, 1, 1, mBrdA, EllesmereUI.PP)
                -- A fixed spot, as the CDM icon menu sits under its icon: beside the clicked
                -- row, just outside the bar menu, so it covers no other bar.
                sm:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 4, 0)
                local ar, ag, ab = EllesmereUI.GetAccentColor()
                local names = ns.FOCUSKICK_SOUND_NAMES or {}
                local flyouts = {}

                local function MakeSoundRow(i, label, field)
                    local row = CreateFrame("Button", nil, sm)
                    row:SetHeight(ITEM_H)
                    row:SetPoint("TOPLEFT", sm, "TOPLEFT", 1, -4 - (i - 1) * ITEM_H)
                    row:SetPoint("TOPRIGHT", sm, "TOPRIGHT", -1, -4 - (i - 1) * ITEM_H)
                    row:SetFrameLevel(sm:GetFrameLevel() + 2)
                    local lbl = row:CreateFontString(nil, "OVERLAY")
                    lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    lbl:SetPoint("LEFT", row, "LEFT", 10, 0)
                    lbl:SetText(EllesmereUI.L(label))
                    local arrow = row:CreateTexture(nil, "ARTWORK")
                    arrow:SetSize(10, 10)
                    arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    arrow:SetTexture(MEDIA .. "icons\\right-arrow.png")
                    arrow:SetAlpha(0.7)
                    local val = row:CreateFontString(nil, "OVERLAY")
                    val:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    val:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                    val:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
                    val:SetJustifyH("RIGHT")
                    val:SetWordWrap(false); val:SetMaxLines(1)
                    val:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    local hl = row:CreateTexture(nil, "ARTWORK")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)

                    local function Get() return cfg[field] or "none" end
                    -- Accent label while a sound is chosen, like the icon menu's rows.
                    local function Paint()
                        local k = cfg[field]
                        if k and k ~= "none" then
                            lbl:SetTextColor(ar, ag, ab, 1)
                        else
                            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        end
                        val:SetText(names[Get()] or Get())
                    end
                    Paint()
                    local function Set(v)
                        cfg[field] = (v ~= "none" and v) or nil
                        if cfg[field] then
                            -- Flip the 0-cost gate live and hook the bar frames already
                            -- out of the pool, so the next edge plays without a reload.
                            ns._cdmAnyBuffSound = true
                            if ns.EnsureTBBSoundHooks then ns.EnsureTBBSoundHooks() end
                        end
                        Paint()
                        -- The bar row's speaker button follows (dimmed with no sound).
                        if anchorRow._sndPaint then anchorRow._sndPaint() end
                    end
                    local function ShowFlyout()
                        hl:SetAlpha(hlA)
                        for f, fly in pairs(flyouts) do
                            if f ~= field then fly:Hide() end
                        end
                        local fly = flyouts[field]
                        if not fly then
                            local values, order = EllesmereUI.BuildSoundDropdownValues(
                                ns.FOCUSKICK_SOUND_PATHS, names, ns.FOCUSKICK_SOUND_ORDER)
                            values._menuOpts.anchor = "RIGHT"
                            -- Match the CDM icon menu's flyouts: the CDM options font at 11 and
                            -- the speaker atlas in its own colour.
                            values._menuOpts.labelFont = { FONT_PATH, 11, GetCDMOptOutline() }
                            values._menuOpts.iconNativeColor = true
                            local refresh
                            fly, _, refresh = EllesmereUI.BuildDropdownMenu(row, 200, order, values, Get, Set, val, "regular")
                            -- BuildDropdownMenu creates it at FULLSCREEN_DIALOG 200, under both menus.
                            fly:SetFrameStrata(sm:GetFrameStrata())
                            fly:SetFrameLevel(sm:GetFrameLevel() + 30)
                            fly._refresh = refresh
                            flyouts[field] = fly
                        end
                        if not fly:IsShown() then
                            if fly._refresh then fly._refresh() end
                            fly:Show()
                        end
                    end
                    row:SetScript("OnEnter", ShowFlyout)
                    row:SetScript("OnClick", ShowFlyout)
                    row:SetScript("OnLeave", function() hl:SetAlpha(0) end)
                end
                MakeSoundRow(1, "Audio on Buff Gain", "buffActiveSoundKey")
                MakeSoundRow(2, "Audio on Buff Loss", "buffLostSoundKey")

                local function OverAny()
                    if sm:IsMouseOver() then return true end
                    for _, fly in pairs(flyouts) do
                        if fly:IsShown() and fly:IsMouseOver() then return true end
                    end
                    return false
                end
                sm:SetScript("OnUpdate", function(m)
                    if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
                       and not OverAny() then
                        m:Hide()
                    end
                end)
                sm:HookScript("OnHide", function(m)
                    m:SetScript("OnUpdate", nil)
                    for _, fly in pairs(flyouts) do fly:Hide() end
                end)
                -- The bar menu underneath asks this before dismissing itself on a click.
                sm._overAny = OverAny
                ddBtn._tbbSndMenu = sm
                sm:Show()
            end

            -- Custom dropdown menu: bars organized by group with quick-add actions inside
            -- each, an independent section, and new-group/independent-bar creation at the bottom.
            local ddMenu
            local function BuildDDMenu()
                if ddMenu then ddMenu:Hide(); ddMenu = nil end
                local t = ns.GetTrackedBuffBars()
                -- Screen-level overlay: created hidden, tracked once its scripts are set.
                local menu = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
                menu:Hide()
                menu:SetFrameStrata("FULLSCREEN_DIALOG")
                menu:SetFrameLevel(300)
                menu:SetClampedToScreen(true)
                menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
                menu:SetPoint("TOPRIGHT", ddBtn, "BOTTOMRIGHT", 0, -2)
                local bg = menu:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(); bg:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
                EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

                -- Rows build on an inner frame so tall menus can scroll.
                local inner = CreateFrame("Frame", nil, menu)
                -- The options panel can run at a different effective scale than this
                -- screen-level menu; normalize button width into menu space so rows end exactly at the menu's edges.
                inner:SetWidth(ddBtn:GetWidth() * ddBtn:GetEffectiveScale() / menu:GetEffectiveScale())
                inner:SetPoint("TOPLEFT")
                local MENU_MAX_H = 420
                local ar, ag, ab = EllesmereUI.GetAccentColor()

                local mH = 4

                -- Drag-and-drop: bar rows can be dragged onto another group's section (or
                -- independent) to move them; zones collect every row of a group so the whole
                -- section is a drop target. Drag flag declared before any OnUpdate reads it.
                local dropZones = {}   -- { gid, label, frames = {rows...} }
                local dragState = { idx = nil, name = nil }
                menu._dragActive = false

                local function HoveredZone()
                    for _, z in ipairs(dropZones) do
                        for _, f in ipairs(z.frames) do
                            if f and f:IsMouseOver() then return z end
                        end
                    end
                    return nil
                end

                local dragGhost
                local function GhostUpdate()
                    local cx, cy = GetCursorPosition()
                    local sc = UIParent:GetEffectiveScale()
                    dragGhost:ClearAllPoints()
                    dragGhost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / sc + 14, cy / sc - 22)
                    local z = HoveredZone()
                    if z and dragState.idx then
                        local t2 = ns.GetTrackedBuffBars()
                        local c2 = t2.bars and t2.bars[dragState.idx]
                        if c2 and ns.TBBBarGroupID(c2) ~= z.gid then
                            dragGhost._lbl:SetText(dragState.name .. "  >  " .. z.label)
                            dragGhost._lbl:SetTextColor(ar, ag, ab, 1)
                            return
                        end
                    end
                    dragGhost._lbl:SetText(dragState.name or "")
                    dragGhost._lbl:SetTextColor(1, 1, 1, 0.8)
                end
                local function EnsureGhost()
                    if dragGhost then return dragGhost end
                    dragGhost = CreateFrame("Frame", nil, UIParent)
                    dragGhost:SetFrameStrata("TOOLTIP")
                    dragGhost:SetFrameLevel(500)
                    dragGhost:SetSize(10, 20)
                    local gl = dragGhost:CreateFontString(nil, "OVERLAY")
                    gl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    gl:SetPoint("BOTTOMLEFT", dragGhost, "BOTTOMLEFT", 0, 0)
                    dragGhost._lbl = gl
                    dragGhost:Hide()
                    return dragGhost
                end
                local function StopDrag()
                    menu._dragActive = false
                    dragState.idx = nil
                    if dragGhost then
                        dragGhost:Hide()
                        dragGhost:SetScript("OnUpdate", nil)
                    end
                end
                menu:HookScript("OnHide", StopDrag)

                local function BarIconID(b)
                    if b.popularKey and ns.TBB_POPULAR_BUFFS then
                        for _, pe in ipairs(ns.TBB_POPULAR_BUFFS) do
                            if pe.key == b.popularKey then return pe.icon end
                        end
                    end
                    if b.spellID and b.spellID > 0 then
                        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spellID)
                        if tex then return tex end
                    end
                    return 134400
                end

                local function AddHeaderRow(text)
                    if mH > 4 then mH = mH + 4 end
                    local hLbl = inner:CreateFontString(nil, "OVERLAY")
                    hLbl:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    hLbl:SetTextColor(1, 1, 1, 0.9)
                    hLbl:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -mH - 5)
                    hLbl:SetText(text)
                    mH = mH + 20
                end

                -- Group header: clickable, selects the GROUP as editing context (group
                -- settings replace per-bar sections). gkey (optional) = group's globalKey,
                -- adds the GLOBAL tag + a delete button that removes it for every spec (with confirmation).
                local function AddGroupHeaderRow(gid, gkey)
                    if mH > 4 then mH = mH + 4 end
                    local item = CreateFrame("Button", nil, inner)
                    item:SetHeight(22)
                    item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(menu:GetFrameLevel() + 2)
                    local hLbl = item:CreateFontString(nil, "OVERLAY")
                    hLbl:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    hLbl:SetTextColor(1, 1, 1, 0.9)
                    hLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                    local groupDisplayName = (ns.TBBGroupName and ns.TBBGroupName(gid))
                        or (EllesmereUI.L("GROUP") .. " " .. gid)
                    hLbl:SetText(groupDisplayName)
                    if gkey then
                        local gTag = item:CreateFontString(nil, "OVERLAY")
                        gTag:SetFont(FONT_PATH, 9, GetCDMOptOutline())
                        gTag:SetTextColor(ar, ag, ab, 0.9)
                        gTag:SetPoint("LEFT", hLbl, "RIGHT", 6, 0)
                        gTag:SetText(EllesmereUI.L("GLOBAL"))
                    end
                    local eLbl = item:CreateFontString(nil, "OVERLAY")
                    eLbl:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    eLbl:SetTextColor(ar, ag, ab, 0.85)
                    eLbl:SetText(EllesmereUI.L("Edit Group"))
                    local delBtn
                    if gkey then
                        delBtn = CreateFrame("Button", nil, item)
                        delBtn:SetSize(ICON_SZ, ICON_SZ)
                        delBtn:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                        delBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                        delIcon:SetSize(ICON_SZ, ICON_SZ)
                        delIcon:SetPoint("CENTER")
                        if delIcon.SetSnapToPixelGrid then delIcon:SetSnapToPixelGrid(false); delIcon:SetTexelSnappingBias(0) end
                        delIcon:SetTexture(MEDIA .. "icons\\eui-close.png")
                        delBtn:SetAlpha(0.6)
                        delBtn:SetScript("OnEnter", function()
                            delBtn:SetAlpha(1)
                            EllesmereUI.ShowWidgetTooltip(delBtn, EllesmereUI.L("Delete this global group for all specs"))
                        end)
                        delBtn:SetScript("OnLeave", function()
                            delBtn:SetAlpha(0.6)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        delBtn:SetScript("OnClick", function()
                            menu:Hide()
                            EllesmereUI:ShowConfirmPopup({
                                title = "Delete Global Group",
                                message = EllesmereUI.Lf("Delete \"%1$s\" for ALL specs? Bars keep their current positions.", groupDisplayName),
                                confirmText = "Delete", cancelText = "Cancel",
                                onConfirm = function()
                                    if ns.TBBDeleteGlobalGroup then ns.TBBDeleteGlobalGroup(gkey) end
                                    if _tbbSelectedGroup == gid then _tbbSelectedGroup = nil end
                                    ns.BuildTrackedBuffBars()
                                    EllesmereUI:RefreshPage(true)
                                end,
                            })
                        end)
                        eLbl:SetPoint("RIGHT", delBtn, "LEFT", -8, 0)
                    else
                        eLbl:SetPoint("RIGHT", item, "RIGHT", -10, 0)
                    end
                    local hl = item:CreateTexture(nil, "ARTWORK")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1)
                    local isSel = _tbbSelectedGroup == gid
                    hl:SetAlpha(isSel and selA or 0)
                    item:SetScript("OnEnter", function()
                        hLbl:SetTextColor(1, 1, 1, 1); eLbl:SetTextColor(1, 1, 1, 0.9); hl:SetAlpha(hlA)
                    end)
                    item:SetScript("OnLeave", function()
                        hLbl:SetTextColor(1, 1, 1, 0.9); eLbl:SetTextColor(ar, ag, ab, 0.85)
                        hl:SetAlpha(isSel and selA or 0)
                    end)
                    item:SetScript("OnClick", function()
                        menu:Hide()
                        _tbbSelectedGroup = gid
                        EllesmereUI:RefreshPage(true)
                    end)
                    mH = mH + 22
                    return item
                end

                local function AddBarItem(idx, b, indent)
                    local item = CreateFrame("Button", nil, inner)
                    item:SetHeight(ITEM_H)
                    item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(menu:GetFrameLevel() + 2)

                    local spIco = item:CreateTexture(nil, "OVERLAY")
                    spIco:SetSize(ITEM_H - 8, ITEM_H - 8)
                    spIco:SetPoint("LEFT", item, "LEFT", 10 + (indent or 0), 0)
                    spIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local unassigned = (not b.spellID or b.spellID == 0) and not b.glowBased
                    spIco:SetTexture(BarIconID(b))
                    if unassigned then spIco:SetDesaturated(true); spIco:SetAlpha(0.35) end

                    -- Icon = change this bar's buff (green border affordance)
                    local icoBtn = CreateFrame("Button", nil, item)
                    icoBtn:SetAllPoints(spIco)
                    icoBtn:SetFrameLevel(item:GetFrameLevel() + 3)
                    local egc = EllesmereUI.ELLESMERE_GREEN
                    local icoBrd = PP.CreateBorder(icoBtn, egc.r, egc.g, egc.b, 1, 1, "OVERLAY", 7)
                    if icoBrd then icoBrd:Hide() end
                    icoBtn:SetScript("OnEnter", function()
                        if icoBrd then icoBrd:Show() end
                        EllesmereUI.ShowWidgetTooltip(icoBtn, EllesmereUI.L("Change buff"))
                    end)
                    icoBtn:SetScript("OnLeave", function()
                        if icoBrd then icoBrd:Hide() end
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    icoBtn:SetScript("OnClick", function()
                        menu:Hide()
                        OpenBuffPickerForBar(idx)
                    end)

                    local iLbl = item:CreateFontString(nil, "OVERLAY")
                    iLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    iLbl:SetJustifyH("LEFT")
                    iLbl:SetWordWrap(false); iLbl:SetMaxLines(1)
                    iLbl:SetPoint("LEFT", spIco, "RIGHT", 6, 0)
                    local displayName = (b.name and EllesmereUI.L(b.name)) or EllesmereUI.Lf("Bar %d", idx)
                    if not b.popularKey and b.spellID and b.spellID > 0 then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(b.spellID)
                        if info and info.name then displayName = info.name end
                    end
                    if unassigned then
                        displayName = displayName .. "  (" .. EllesmereUI.L("no buff assigned") .. ")"
                    end
                    iLbl:SetText(displayName)

                    local iHl = item:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints(); iHl:SetColorTexture(1, 1, 1, 1)
                    iHl:SetAlpha(idx == _tbbSelectedBar and selA or 0)

                    local delBtn = CreateFrame("Button", nil, item)
                    delBtn:SetSize(ICON_SZ, ICON_SZ)
                    delBtn:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                    delBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                    local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                    delIcon:SetSize(ICON_SZ, ICON_SZ)
                    delIcon:SetPoint("CENTER")
                    if delIcon.SetSnapToPixelGrid then delIcon:SetSnapToPixelGrid(false); delIcon:SetTexelSnappingBias(0) end
                    delIcon:SetTexture(MEDIA .. "icons\\eui-close.png")
                    delBtn:SetAlpha(0.75)
                    iLbl:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)

                    -- Only a bar that can cue gets the sound menu: on a row right-click and
                    -- on the speaker button, dimmed ("Add Audio Effect") while the bar has
                    -- no Audio on Buff Gain/Loss sound and full ("Edit Audio Effect") once
                    -- it has one. The sound menu repaints it through item._sndPaint.
                    local soundable = BarTakesSound(b)
                    if soundable then
                        local sndBtn = CreateFrame("Button", nil, item)
                        sndBtn:SetSize(ICON_SZ, ICON_SZ)
                        sndBtn:SetPoint("RIGHT", delBtn, "LEFT", -6, 0)
                        sndBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                        local sndIcon = sndBtn:CreateTexture(nil, "OVERLAY")
                        sndIcon:SetAllPoints()
                        sndIcon:SetAtlas(EllesmereUI.SOUND_ICON_ATLAS)
                        local function HasSound()
                            local g, l = b.buffActiveSoundKey, b.buffLostSoundKey
                            return (g and g ~= "none") or (l and l ~= "none")
                        end
                        local function RestAlpha() return HasSound() and 0.8 or 0.3 end
                        item._sndPaint = function()
                            if not sndBtn:IsMouseOver() then sndBtn:SetAlpha(RestAlpha()) end
                        end
                        sndBtn:SetAlpha(RestAlpha())
                        sndBtn:SetScript("OnEnter", function(self)
                            self:SetAlpha(1); iLbl:SetTextColor(1,1,1,1); iHl:SetAlpha(hlA)
                            EllesmereUI.ShowWidgetTooltip(self, HasSound() and EllesmereUI.L("Edit Audio Effect") or EllesmereUI.L("Add Audio Effect"))
                        end)
                        sndBtn:SetScript("OnLeave", function(self)
                            EllesmereUI.HideWidgetTooltip()
                            self:SetAlpha(RestAlpha())
                            if item:IsMouseOver() then return end
                            iLbl:SetTextColor(tDimR,tDimG,tDimB,tDimA); iHl:SetAlpha(idx == _tbbSelectedBar and selA or 0)
                        end)
                        -- The bar menu stays open underneath, as with the row right-click.
                        sndBtn:SetScript("OnClick", function() OpenBarSoundMenu(idx, item) end)
                        iLbl:SetPoint("RIGHT", sndBtn, "LEFT", -4, 0)
                    end

                    delBtn:SetScript("OnEnter", function() delBtn:SetAlpha(1); iLbl:SetTextColor(1,1,1,1); iHl:SetAlpha(hlA) end)
                    delBtn:SetScript("OnLeave", function()
                        if item:IsMouseOver() then return end
                        delBtn:SetAlpha(0.75); iLbl:SetTextColor(tDimR,tDimG,tDimB,tDimA); iHl:SetAlpha(idx == _tbbSelectedBar and selA or 0)
                    end)
                    delBtn:SetScript("OnClick", function()
                        menu:Hide()
                        EllesmereUI:ShowConfirmPopup({
                            title = "Delete Bar",
                            message = EllesmereUI.Lf("Delete \"%1$s\"?", displayName),
                            confirmText = "Delete", cancelText = "Cancel",
                            onConfirm = function()
                                ns.RemoveTrackedBuffBar(idx)
                                EllesmereUI:RefreshPage(true)
                            end,
                        })
                    end)

                    item:SetScript("OnEnter", function() iLbl:SetTextColor(1,1,1,1); iHl:SetAlpha(hlA); delBtn:SetAlpha(1) end)
                    item:SetScript("OnLeave", function() iLbl:SetTextColor(tDimR,tDimG,tDimB,tDimA); iHl:SetAlpha(idx == _tbbSelectedBar and selA or 0); delBtn:SetAlpha(0.75) end)
                    item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    item:SetScript("OnClick", function(_, mouseButton)
                        if mouseButton == "RightButton" then
                            if not soundable then return end
                            -- The bar menu stays open underneath, like the CDM icon menu.
                            OpenBarSoundMenu(idx, item)
                            return
                        end
                        menu:Hide()
                        if unassigned then
                            -- No buff yet: go straight to the buff picker.
                            OpenBuffPickerForBar(idx)
                        else
                            _tbbSelectedBar = idx
                            _tbbSelectedGroup = nil
                            EllesmereUI:RefreshPage(true)
                        end
                    end)

                    -- Drag to move between groups (drop handled by zone under the cursor at release).
                    item:RegisterForDrag("LeftButton")
                    item:SetScript("OnDragStart", function()
                        menu._dragActive = true
                        dragState.idx = idx
                        dragState.name = displayName
                        local g = EnsureGhost()
                        g._lbl:SetText(displayName)
                        g._lbl:SetTextColor(1, 1, 1, 0.8)
                        g:Show()
                        g:SetScript("OnUpdate", GhostUpdate)
                    end)
                    item:SetScript("OnDragStop", function()
                        local moveIdx = dragState.idx
                        local z = HoveredZone()
                        StopDrag()
                        if moveIdx and z then
                            MoveBarToGroup(moveIdx, z.gid)
                        end
                    end)
                    mH = mH + ITEM_H
                    return item
                end

                local function AddActionItem(text, indent, onClick)
                    local item = CreateFrame("Button", nil, inner)
                    item:SetHeight(ITEM_H)
                    item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(menu:GetFrameLevel() + 2)
                    local lbl = item:CreateFontString(nil, "OVERLAY")
                    lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    lbl:SetPoint("LEFT", item, "LEFT", 10 + (indent or 0), 0)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetText(text)
                    lbl:SetTextColor(ar, ag, ab, 0.85)
                    local hl = item:CreateTexture(nil, "ARTWORK")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                    item:SetScript("OnEnter", function() lbl:SetTextColor(1,1,1,1); hl:SetAlpha(hlA) end)
                    item:SetScript("OnLeave", function() lbl:SetTextColor(ar, ag, ab, 0.85); hl:SetAlpha(0) end)
                    item:SetScript("OnClick", onClick)
                    mH = mH + ITEM_H
                    return item
                end

                -- A freshly created bar has no buff yet: select it and open the buff picker right away so add-and-assign is one flow.
                local function SelectNewBar(newIdx)
                    menu:Hide()
                    OpenBuffPickerForBar(newIdx)
                end

                -- Grouped bars, one section per group (each section doubles as a drop zone for bar drags).
                local gids = ns.TBBGroupIDsInUse and ns.TBBGroupIDsInUse() or {}
                local renderedGlobal = {}
                for _, gid in ipairs(gids) do
                    local gkey = ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid) or nil
                    if gkey then renderedGlobal[gkey] = true end
                    local zone = {
                        gid = gid,
                        label = (ns.TBBGroupName and ns.TBBGroupName(gid))
                            or (EllesmereUI.L("Group") .. " " .. gid),
                        frames = {},
                    }
                    dropZones[#dropZones + 1] = zone
                    zone.frames[#zone.frames + 1] = AddGroupHeaderRow(gid, gkey)
                    for idx, b in ipairs(t.bars) do
                        if ns.TBBBarGroupID(b) == gid then
                            zone.frames[#zone.frames + 1] = AddBarItem(idx, b, 8)
                        end
                    end
                    zone.frames[#zone.frames + 1] = AddActionItem(EllesmereUI.L("+ Add Bar to Group"), 8, function()
                        SelectNewBar(ns.AddTrackedBuffBar(gid))
                    end)
                end

                -- Global groups with no bars on this spec are always listed so any spec can
                -- assign/drag bars into them; selecting one edits its shared settings (a normal drop zone).
                if ns.TBBGlobalGroupKeys then
                    for _, gkey in ipairs(ns.TBBGlobalGroupKeys()) do
                        if not renderedGlobal[gkey] then
                            local lgid = ns.TBBEnsureLocalGroupForGlobal(gkey)
                            if lgid then
                                local zone = {
                                    gid = lgid,
                                    label = (ns.TBBGroupName and ns.TBBGroupName(lgid))
                                        or (EllesmereUI.L("Group") .. " " .. lgid),
                                    frames = {},
                                }
                                dropZones[#dropZones + 1] = zone
                                zone.frames[#zone.frames + 1] = AddGroupHeaderRow(lgid, gkey)
                                zone.frames[#zone.frames + 1] = AddActionItem(EllesmereUI.L("+ Add Bar to Group"), 8, function()
                                    SelectNewBar(ns.AddTrackedBuffBar(lgid))
                                end)
                            end
                        end
                    end
                end

                -- Independent bars (the section is the "make independent" zone)
                local indepZone = { gid = 0, label = EllesmereUI.L("Independent"), frames = {} }
                dropZones[#dropZones + 1] = indepZone
                local anyIndependent = false
                for _, b in ipairs(t.bars) do
                    if ns.TBBBarGroupID(b) == 0 then anyIndependent = true; break end
                end
                if anyIndependent then
                    AddHeaderRow(EllesmereUI.L("INDEPENDENT BARS"))
                    for idx, b in ipairs(t.bars) do
                        if ns.TBBBarGroupID(b) == 0 then
                            indepZone.frames[#indepZone.frames + 1] = AddBarItem(idx, b, 8)
                        end
                    end
                end

                -- Divider + creation actions
                local div = inner:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1); div:SetColorTexture(1, 1, 1, 0.10)
                div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9

                AddActionItem(EllesmereUI.L("+ Add New Group"), 0, function()
                    local gid = ns.TBBNextGroupID()
                    if ns.TBBResetGroupSettings then ns.TBBResetGroupSettings(gid) end
                    SelectNewBar(ns.AddTrackedBuffBar(gid))
                end)
                indepZone.frames[#indepZone.frames + 1] = AddActionItem(EllesmereUI.L("+ Add Independent Bar"), 0, function()
                    SelectNewBar(ns.AddTrackedBuffBar(0))
                end)

                if #t.bars > 1 then
                    local dragHint = inner:CreateFontString(nil, "OVERLAY")
                    dragHint:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    dragHint:SetTextColor(1, 1, 1, 0.35)
                    dragHint:SetPoint("TOP", inner, "TOP", 0, -mH - 4)
                    dragHint:SetText(EllesmereUI.L("Drag a bar to move it into another group"))
                    mH = mH + 20
                end
                -- Discoverability for the row right-click (Audio on Buff Gain/Loss): shown
                -- while any bar can take a sound.
                local anySoundable = false
                for _, b in ipairs(t.bars) do
                    if BarTakesSound(b) then anySoundable = true; break end
                end
                if anySoundable then
                    local soundHint = inner:CreateFontString(nil, "OVERLAY")
                    soundHint:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    soundHint:SetTextColor(1, 1, 1, 0.35)
                    soundHint:SetPoint("TOP", inner, "TOP", 0, -mH - 4)
                    soundHint:SetText(EllesmereUI.L("Right-click a bar to set its sounds"))
                    mH = mH + 20
                end

                local totalH = mH + 4
                inner:SetHeight(totalH)
                if totalH > MENU_MAX_H then
                    menu:SetHeight(MENU_MAX_H)
                    local sf = CreateFrame("ScrollFrame", nil, menu)
                    sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
                    sf:SetFrameLevel(menu:GetFrameLevel() + 1)
                    sf:EnableMouseWheel(true)
                    sf:SetScrollChild(inner)
                    local scrollPos = 0
                    local maxScroll = totalH - MENU_MAX_H
                    sf:SetScript("OnMouseWheel", function(_, delta)
                        scrollPos = math.max(0, math.min(maxScroll, scrollPos - delta * 30))
                        sf:SetVerticalScroll(scrollPos)
                    end)
                else
                    menu:SetHeight(totalH)
                end
                menu:SetScript("OnUpdate", function(m)
                    -- Never dismiss mid-drag: dragging naturally leaves the menu bounds with the button held down.
                    if m._dragActive then return end
                    -- A click in the row's sound menu or its flyouts is not a click outside.
                    local snd = ddBtn._tbbSndMenu
                    if snd and snd:IsShown() and snd._overAny and snd._overAny() then return end
                    if not m:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                        m:Hide()
                    end
                end)
                menu:HookScript("OnHide", function(m)
                    m:SetScript("OnUpdate", nil)
                    if ddBtn._tbbSndMenu then ddBtn._tbbSndMenu:Hide() end
                end)
                -- A no-op unless the menu sits on the controller-cursor overlay layer.
                EllesmereUI.TrackOverlay(menu)
                menu:Show()
                ddMenu = menu
            end

            ddBtn:SetScript("OnEnter", function() ddLbl:SetAlpha(mTxtHA); ddBrd:SetColor(1,1,1,mBrdHA); ddBg:SetColorTexture(mBgR,mBgG,mBgB,mBgHA) end)
            ddBtn:SetScript("OnLeave", function()
                if ddMenu and ddMenu:IsShown() then return end
                ddLbl:SetAlpha(mTxtA); ddBrd:SetColor(1,1,1,mBrdA); ddBg:SetColorTexture(mBgR,mBgG,mBgB,mBgA)
            end)
            ddBtn:SetScript("OnClick", function()
                -- An open buff picker (e.g. from "+ Add Bar to Group") yields to the management menu.
                if _tbbSpellPickerMenu and _tbbSpellPickerMenu:IsShown() then
                    _tbbSpellPickerMenu:Hide()
                end
                if ddMenu and ddMenu:IsShown() then ddMenu:Hide() else BuildDDMenu() end
            end)
            ddBtn:HookScript("OnHide", function()
                if ddMenu then ddMenu:Hide() end
                if ddBtn._tbbSndMenu then ddBtn._tbbSndMenu:Hide() end
            end)

            -- Keep the label current when settings refresh in place (e.g. a group rename commits without a full page rebuild).
            EllesmereUI.RegisterWidgetRefresh(UpdateDDLabel)

            _tbbDDBtn = ddBtn
            return ddBtn
        end

        -- No content header: preview lives in the popout panel docked to the left of the
        -- options window (RefreshTBBPopout); wire its click-to-scroll overlays to this build's rows.
        EllesmereUI:ClearContentHeader()
        _tbbNavigateFn = NavigateToSetting

        -------------------------------------------------------------------
        --  ACTION CARDS + PRESET STYLE (top of scrollable settings; shown in both bar and group mode)
        -------------------------------------------------------------------
        do
            -- The third card broadcasts the selected bar to every other spec, then flips to
            -- "Remove Bar from All Specs" (the inverse); dimmed unless a preset/custom-buff bar is selected.
            local _selForBroadcast = (not _tbbSelectedGroup) and SelectedTBB() or nil
            local _canBroadcast = ns.IsTrackedBuffBarBroadcastable
                and ns.IsTrackedBuffBarBroadcastable(_selForBroadcast) or false
            -- WoW Forever: the class runs on one spec, so there is nowhere to copy to.
            if EllesmereUI.IS_FOREVER then _canBroadcast = false end
            local _isBroadcast = _canBroadcast
                and ns.IsTrackedBuffBarBroadcast
                and ns.IsTrackedBuffBarBroadcast(_selForBroadcast) or false
            local _broadcastLabel = _isBroadcast and "Remove Bar from All Specs"
                                                  or "Add Bar to All Specs"
            local EGc = EllesmereUI.ELLESMERE_GREEN
            local PADc = EllesmereUI.CONTENT_PAD or 10
            local CARD_H, CARD_GAP, CARD_ICON = 60, 12, 24
            local cardTotalW = parent:GetWidth() - PADc * 2
            local CARD_W = math.floor((cardTotalW - CARD_GAP * 2) / 3)
            y = y - 10
            local cardRow = CreateFrame("Frame", nil, parent)
            PP.Size(cardRow, cardTotalW, CARD_H)
            PP.Point(cardRow, "TOPLEFT", parent, "TOPLEFT", PADc, y)

            local function MakeActionCard(xOff, iconPath, cardTitle, cardDesc, onClick, disabledTip)
                local card = CreateFrame("Button", nil, cardRow)
                PP.Size(card, CARD_W, CARD_H)
                PP.Point(card, "TOPLEFT", cardRow, "TOPLEFT", xOff, 0)
                card:SetFrameLevel(cardRow:GetFrameLevel() + 2)

                local cbg = card:CreateTexture(nil, "BACKGROUND")
                cbg:SetAllPoints()
                cbg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
                local cbrd = EllesmereUI.MakeBorder(card, 1, 1, 1, 0.12, PP)

                -- Accent top edge
                local accentLine = card:CreateTexture(nil, "ARTWORK", nil, 7)
                accentLine:SetColorTexture(EGc.r, EGc.g, EGc.b, 0.6)
                PP.Point(accentLine, "TOPLEFT", card, "TOPLEFT", 1, -1)
                PP.Point(accentLine, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
                accentLine:SetHeight(2)
                if accentLine.SetSnapToPixelGrid then accentLine:SetSnapToPixelGrid(false); accentLine:SetTexelSnappingBias(0) end

                local cIcon = card:CreateTexture(nil, "ARTWORK")
                cIcon:SetSize(CARD_ICON, CARD_ICON)
                PP.Point(cIcon, "LEFT", card, "LEFT", 18, 0)
                cIcon:SetTexture(iconPath)
                cIcon:SetVertexColor(EGc.r, EGc.g, EGc.b)
                cIcon:SetAlpha(0.6)
                if cIcon.SetSnapToPixelGrid then cIcon:SetSnapToPixelGrid(false); cIcon:SetTexelSnappingBias(0) end

                local titleFs = EllesmereUI.MakeFont(card, 12, nil, 1, 1, 1, 0.9)
                PP.Point(titleFs, "TOPLEFT", cIcon, "TOPRIGHT", 14, 1)
                PP.Point(titleFs, "RIGHT", card, "RIGHT", -10, 0)
                titleFs:SetJustifyH("LEFT")
                titleFs:SetWordWrap(false)
                titleFs:SetText(EllesmereUI.L(cardTitle))

                local descFs = EllesmereUI.MakeFont(card, 10, nil, 1, 1, 1, 0.35)
                PP.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
                PP.Point(descFs, "RIGHT", card, "RIGHT", -10, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetText(EllesmereUI.L(cardDesc))

                if disabledTip then
                    card:SetAlpha(0.45)
                    card:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(card, disabledTip)
                    end)
                    card:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                else
                    card:SetScript("OnEnter", function()
                        cbg:SetColorTexture(0.119, 0.111, 0.104, 0.50)
                        cbrd:SetColor(1, 1, 1, 0.22)
                        titleFs:SetAlpha(1)
                        cIcon:SetAlpha(0.85)
                    end)
                    card:SetScript("OnLeave", function()
                        cbg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
                        cbrd:SetColor(1, 1, 1, 0.12)
                        titleFs:SetAlpha(0.9)
                        cIcon:SetAlpha(0.6)
                    end)
                    card:SetScript("OnClick", onClick)
                end
                return card
            end

            local MEDIA_ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
            MakeActionCard(0, MEDIA_ICONS .. "power.png",
                "Use Blizzard CDM Bars", "Switch back to Blizzard's bars.", function()
                    EllesmereUI:ShowConfirmPopup({
                        title = "Use Blizzard Bars",
                        message = "This will disable EllesmereUI Tracking Bars and show Blizzard's default Tracked Bars display instead.",
                        confirmText = "Switch & Reload",
                        cancelText = "Cancel",
                        reload = true,
                        onConfirm = function()
                            local p = DB()
                            if p and p.cdmBars then
                                p.cdmBars.useBlizzardBuffBars = true
                            end
                        end,
                    })
                end)
            MakeActionCard(CARD_W + CARD_GAP, MEDIA_ICONS .. "eui-open.png",
                "Open Blizzard CDM", "Manage your tracked bars.", function()
                    if ns.OpenBlizzardCDMTab then
                        ns.OpenBlizzardCDMTab(true)
                    end
                end)
            MakeActionCard((CARD_W + CARD_GAP) * 2, MEDIA_ICONS .. "sync.png",
                _broadcastLabel, "Copy this bar to every spec.", function()
                    local sel = SelectedTBB()
                    if _tbbSelectedGroup or not ns.IsTrackedBuffBarBroadcastable(sel) then return end
                    local nm = sel.name or "Bar"
                    if (not sel.popularKey or sel.popularKey == "") and sel.spellID and sel.spellID > 0 then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sel.spellID)
                        if info and info.name then nm = info.name end
                    end
                    if ns.IsTrackedBuffBarBroadcast and ns.IsTrackedBuffBarBroadcast(sel) then
                        EllesmereUI:ShowConfirmPopup({
                            title = "Remove Bar from All Specs",
                            message = EllesmereUI.Lf("Remove \"%1$s\" from every other spec? The bar in this spec is kept.", nm),
                            confirmText = "Remove from All",
                            cancelText = "Cancel",
                            onConfirm = function()
                                if ns.RemoveBarFromAllSpecs then ns.RemoveBarFromAllSpecs(_tbbSelectedBar) end
                                EllesmereUI:RefreshPage(true)
                            end,
                        })
                    else
                        EllesmereUI:ShowConfirmPopup({
                            title = "Add Bar to All Specs",
                            message = EllesmereUI.Lf("Add \"%1$s\" to every spec? It will be copied to each of your specs that doesn't already have it.", nm),
                            confirmText = "Add to All Specs",
                            cancelText = "Cancel",
                            onConfirm = function()
                                if ns.AddBarToAllSpecs then ns.AddBarToAllSpecs(_tbbSelectedBar) end
                                EllesmereUI:RefreshPage(true)
                            end,
                        })
                    end
                end,
                (not _canBroadcast) and ((EllesmereUI.IS_FOREVER
                    and "WoW Forever has no other specs to copy this bar to")
                    or (_tbbSelectedGroup
                    and "Select a bar to broadcast it to other specs"
                    or "Only preset or custom buff bars can be added to all specs")) or nil)
            y = y - CARD_H - 12

            -- Preset Style panel (styled like Profiles & Presets "Active Profile"): pick a
            -- saved style preset and apply it to the selected bar/group, or save the current
            -- style as one. Presets are profile-wide; new bars resolve one by association at creation.
            local _wc = EllesmereUI.WB_COLOURS
            local PROF_BTN_COLOURS = {
                _wc[1],  _wc[2],  _wc[3],  _wc[4],   _wc[5],  _wc[6],  _wc[7],  _wc[8],
                1, 1, 1, EllesmereUI.DD_BRD_A,   1, 1, 1, EllesmereUI.DD_BRD_HA or 0.30,
                _wc[17], _wc[18], _wc[19], _wc[20],  _wc[21], _wc[22], _wc[23], _wc[24],
            }
            local LABEL_H  = 16
            local CTRL_H   = 30
            local PAD_X    = 24
            local PAD_Y    = 20
            local GAP_DD   = 30
            local GAP_BTN  = 14
            local PR_ROW_H = PAD_Y + LABEL_H + 4 + CTRL_H + PAD_Y

            local innerW = cardTotalW - PAD_X * 2
            local DD_W   = math.floor(innerW * 0.30)
            local BTN_W  = math.floor((innerW - DD_W - GAP_DD - GAP_BTN * 2) / 3)

            local prRow = CreateFrame("Frame", nil, parent)
            PP.Size(prRow, cardTotalW, PR_ROW_H)
            PP.Point(prRow, "TOPLEFT", parent, "TOPLEFT", PADc, y)

            local prBg = prRow:CreateTexture(nil, "BACKGROUND")
            prBg:SetAllPoints()
            prBg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
            EllesmereUI.MakeBorder(prRow, 1, 1, 1, 0.10, PP)

            -- "Preset Style" label (accent, matching "Active Profile")
            local prLbl = EllesmereUI.MakeFont(prRow, 12, nil, EGc.r, EGc.g, EGc.b, 0.7)
            PP.Point(prLbl, "TOPLEFT", prRow, "TOPLEFT", PAD_X, -PAD_Y)
            prLbl:SetText(EllesmereUI.L("Preset Style"))
            prLbl:SetJustifyH("LEFT")

            -- Live reads: label/menu/apply buttons all pull from the current preset list so saves/renames/deletes never go stale.
            local function SelectedPresetName()
                local p = DB()
                local sel = p and p.tbbSelectedStylePreset
                if sel and ns.FindTBBStylePreset and ns.FindTBBStylePreset(sel) then
                    return sel
                end
                local presets = ns.GetTBBStylePresets and ns.GetTBBStylePresets()
                return presets and presets[1] and presets[1].name or nil
            end
            local function SelectedPreset()
                local nm = SelectedPresetName()
                if not nm then return nil end
                return ns.FindTBBStylePreset and ns.FindTBBStylePreset(nm)
            end

            -- Preset dropdown: bespoke button + menu (same look as the standard control) so
            -- each row carries inline rename/delete buttons, matching the "Active Profile" dropdown.
            local aS = EllesmereUI.RD_DD_COLOURS
            local prDD = CreateFrame("Button", nil, prRow)
            PP.Size(prDD, DD_W, CTRL_H)
            prDD:SetFrameLevel(prRow:GetFrameLevel() + 2)
            local prDDBg = prDD:CreateTexture(nil, "BACKGROUND")
            prDDBg:SetAllPoints()
            prDDBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            local prDDBrd = EllesmereUI.MakeBorder(prDD, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
            local prDDLbl = EllesmereUI.MakeFont(prDD, 13, nil, 1, 1, 1)
            prDDLbl:SetAlpha(EllesmereUI.DD_TXT_A)
            prDDLbl:SetJustifyH("LEFT")
            prDDLbl:SetWordWrap(false)
            prDDLbl:SetMaxLines(1)
            prDDLbl:SetPoint("LEFT", prDD, "LEFT", 12, 0)
            local prArrow = EllesmereUI.MakeDropdownArrow(prDD, 12, PP)
            prDDLbl:SetPoint("RIGHT", prArrow, "LEFT", -5, 0)
            PP.Point(prDD, "TOPLEFT", prLbl, "BOTTOMLEFT", 0, -6)
            local function UpdatePrDDLabel()
                prDDLbl:SetText(SelectedPresetName() or EllesmereUI.L("No Saved Presets"))
            end
            UpdatePrDDLabel()

            local prMenu = CreateFrame("Frame", nil, UIParent)
            prMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            prMenu:SetFrameLevel(200)
            prMenu:SetClampedToScreen(true)
            prMenu:SetSize(DD_W, 4)
            prMenu:SetPoint("TOPLEFT", prDD, "BOTTOMLEFT", 0, -2)
            prMenu:Hide()
            local prMenuBg = prMenu:CreateTexture(nil, "BACKGROUND")
            prMenuBg:SetAllPoints()
            prMenuBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, 0.98)
            EllesmereUI.MakeBorder(prMenu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
            prMenu:SetScript("OnShow", function(self)
                local sc = prDD:GetEffectiveScale() / UIParent:GetEffectiveScale()
                self:SetScale(sc)
                self:SetScript("OnUpdate", function(m)
                    if not prDD:IsMouseOver() and not m:IsMouseOver() then
                        if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide() end
                    end
                end)
            end)

            local X_SZ = 14
            local MEDIA_PR = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
            local prItems = {}

            local function RebuildPresetMenu()
                for _, itm in ipairs(prItems) do itm:Hide() end
                local presets = (ns.GetTBBStylePresets and ns.GetTBBStylePresets()) or {}
                local selName = SelectedPresetName()
                local mH = 4
                for i = 1, math.max(#presets, 1) do
                    local itm = prItems[i]
                    if not itm then
                        itm = CreateFrame("Button", nil, prMenu)
                        itm:SetHeight(26)
                        itm:SetFrameLevel(prMenu:GetFrameLevel() + 1)

                        local lbl = itm:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT_PATH, 13, GetCDMOptOutline())
                        lbl:SetPoint("LEFT",  itm, "LEFT",  10, 0)
                        lbl:SetPoint("RIGHT", itm, "RIGHT", -(X_SZ * 2 + 26), 0)
                        lbl:SetJustifyH("LEFT")
                        lbl:SetWordWrap(false)
                        lbl:SetMaxLines(1)
                        lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                        itm._lbl = lbl

                        local hl = itm:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                        itm._hl = hl

                        local xBtn = CreateFrame("Button", nil, itm)
                        xBtn:SetSize(X_SZ, X_SZ)
                        xBtn:SetPoint("RIGHT", itm, "RIGHT", -8, 0)
                        xBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                        local xIcon = xBtn:CreateTexture(nil, "OVERLAY")
                        xIcon:SetAllPoints()
                        if xIcon.SetSnapToPixelGrid then xIcon:SetSnapToPixelGrid(false); xIcon:SetTexelSnappingBias(0) end
                        xIcon:SetTexture(MEDIA_PR .. "eui-close.png")
                        xBtn:SetAlpha(0.4)
                        itm._xBtn = xBtn

                        local editBtn = CreateFrame("Button", nil, itm)
                        editBtn:SetSize(X_SZ, X_SZ)
                        editBtn:SetPoint("RIGHT", xBtn, "LEFT", -4, 0)
                        editBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                        local editIcon = editBtn:CreateTexture(nil, "OVERLAY")
                        editIcon:SetAllPoints()
                        if editIcon.SetSnapToPixelGrid then editIcon:SetSnapToPixelGrid(false); editIcon:SetTexelSnappingBias(0) end
                        editIcon:SetTexture(MEDIA_PR .. "eui-edit.png")
                        editBtn:SetAlpha(0.4)
                        itm._editBtn = editBtn

                        local function IsOverInlineBtn()
                            return xBtn:IsMouseOver() or editBtn:IsMouseOver()
                        end
                        local function SetAllInlineAlpha(a)
                            xBtn:SetAlpha(a); editBtn:SetAlpha(a)
                        end

                        itm:SetScript("OnEnter", function()
                            if itm._isEmpty then return end
                            lbl:SetTextColor(1, 1, 1, 1)
                            hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                            SetAllInlineAlpha(0.8)
                        end)
                        itm:SetScript("OnLeave", function()
                            if itm._isEmpty then return end
                            if IsOverInlineBtn() then return end
                            lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                            hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                            SetAllInlineAlpha(0.4)
                        end)

                        local function InlineBtnEnter(self)
                            lbl:SetTextColor(1, 1, 1, 1)
                            hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                            SetAllInlineAlpha(0.8)
                            self:SetAlpha(1)
                        end
                        local function InlineBtnLeave(hoveredSelf)
                            if itm:IsMouseOver() or IsOverInlineBtn() then
                                hoveredSelf:SetAlpha(0.8)
                                return
                            end
                            lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                            hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                            SetAllInlineAlpha(0.4)
                        end

                        xBtn:SetScript("OnEnter", function(self)
                            InlineBtnEnter(self)
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Delete"))
                        end)
                        xBtn:SetScript("OnLeave", function(self)
                            InlineBtnLeave(self)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        editBtn:SetScript("OnEnter", function(self)
                            InlineBtnEnter(self)
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Rename"))
                        end)
                        editBtn:SetScript("OnLeave", function(self)
                            InlineBtnLeave(self)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        prItems[i] = itm
                    end

                    itm:SetPoint("TOPLEFT",  prMenu, "TOPLEFT",  1, -mH)
                    itm:SetPoint("TOPRIGHT", prMenu, "TOPRIGHT", -1, -mH)

                    local pr = presets[i]
                    if not pr then
                        -- Empty state: a single dim, non-interactive row
                        itm._isEmpty = true
                        itm._isSel = false
                        itm._lbl:SetText(EllesmereUI.L("No Saved Presets"))
                        itm._lbl:SetTextColor(1, 1, 1, 0.35)
                        itm._hl:SetAlpha(0)
                        itm._xBtn:Hide()
                        itm._editBtn:Hide()
                        itm:SetScript("OnClick", function() prMenu:Hide() end)
                    else
                        local capName = pr.name
                        itm._isEmpty = false
                        itm._lbl:SetText(capName)
                        itm._lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                        itm._isSel = (capName == selName)
                        itm._hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                        itm._xBtn:Show()
                        itm._xBtn:SetAlpha(0.4)
                        itm._editBtn:Show()
                        itm._editBtn:SetAlpha(0.4)
                        itm:SetScript("OnClick", function()
                            prMenu:Hide()
                            local p = DB()
                            if p then p.tbbSelectedStylePreset = capName end
                            UpdatePrDDLabel()
                        end)
                        itm._xBtn:SetScript("OnClick", function()
                            prMenu:Hide()
                            EllesmereUI:ShowConfirmPopup({
                                title       = EllesmereUI.L("Delete Preset"),
                                message     = EllesmereUI.Lf("Delete \"%1$s\"?", capName),
                                confirmText = EllesmereUI.L("Delete"),
                                cancelText  = EllesmereUI.L("Cancel"),
                                onConfirm   = function()
                                    if ns.DeleteTBBStylePreset then ns.DeleteTBBStylePreset(capName) end
                                    EllesmereUI:RefreshPage(true)
                                end,
                            })
                        end)
                        itm._editBtn:SetScript("OnClick", function()
                            prMenu:Hide()
                            EllesmereUI:ShowInputPopup({
                                title       = EllesmereUI.L("Rename Preset"),
                                message     = EllesmereUI.Lf("Enter a new name for \"%1$s\":", capName),
                                placeholder = capName,
                                confirmText = EllesmereUI.L("Rename"),
                                cancelText  = EllesmereUI.L("Cancel"),
                                onConfirm   = function(newName)
                                    newName = newName and strtrim(newName) or ""
                                    if newName == "" or newName == capName then return end
                                    if ns.FindTBBStylePreset and ns.FindTBBStylePreset(newName) then
                                        EllesmereUI.PrintError(EllesmereUI.Lf("A preset named \"%1$s\" already exists.", newName))
                                        return
                                    end
                                    if ns.RenameTBBStylePreset then ns.RenameTBBStylePreset(capName, newName) end
                                    EllesmereUI:RefreshPage(true)
                                end,
                            })
                        end)
                    end

                    itm:Show()
                    mH = mH + 26
                end
                prMenu:SetHeight(mH + 4)
            end

            local function PrApplyNormal()
                prDDLbl:SetTextColor(aS[17], aS[18], aS[19], aS[20])
                prDDBrd:SetColor(aS[9], aS[10], aS[11], aS[12])
                prDDBg:SetColorTexture(aS[1], aS[2], aS[3], aS[4])
            end
            local function PrApplyHover()
                prDDLbl:SetTextColor(aS[21], aS[22], aS[23], aS[24])
                prDDBrd:SetColor(aS[13], aS[14], aS[15], aS[16])
                prDDBg:SetColorTexture(aS[5], aS[6], aS[7], aS[8])
            end
            prDD:SetScript("OnClick", function()
                if prMenu:IsShown() then prMenu:Hide()
                else RebuildPresetMenu(); prMenu:Show() end
            end)
            prDD:SetScript("OnEnter", function() PrApplyHover() end)
            prDD:SetScript("OnLeave", function()
                if not prMenu:IsShown() then PrApplyNormal() end
            end)
            prDD:HookScript("OnHide", function() prMenu:Hide() end)
            prMenu:HookScript("OnShow", function() PrApplyHover() end)
            prMenu:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                if prDD:IsMouseOver() then PrApplyHover()
                else PrApplyNormal() end
            end)

            -- Buttons with dim labels above, matching the profile row's "Assign to Spec" / "New Profile" columns.
            local function PresetBtn(labelText, btnText, xOff, tooltip, onClick)
                local lab = EllesmereUI.MakeFont(prRow, 12, nil, 1, 1, 1, 0.45)
                PP.Point(lab, "LEFT", prLbl, "LEFT", xOff, 0)
                lab:SetText(EllesmereUI.L(labelText))
                lab:SetJustifyH("LEFT")
                local b = CreateFrame("Button", nil, prRow)
                PP.Size(b, BTN_W, CTRL_H)
                PP.Point(b, "TOPLEFT", lab, "BOTTOMLEFT", 0, -6)
                b:SetFrameLevel(prRow:GetFrameLevel() + 2)
                EllesmereUI.MakeStyledButton(b, btnText, 11, PROF_BTN_COLOURS, onClick)
                b:HookScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(b, tooltip)
                end)
                b:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                return b
            end
            local bx = DD_W + GAP_DD
            PresetBtn("Apply to Bar", "Apply to Bar", bx,
                "Apply the selected preset's style to this bar.", function()
                    local pr = SelectedPreset(); if not pr then return end
                    local sel = (not _tbbSelectedGroup) and SelectedTBB() or nil
                    if not sel then return end
                    ns.ApplyTBBStylePresetToCfg(pr, sel)
                    RefreshTBB(); EllesmereUI:RefreshPage()
                end)
            PresetBtn("Apply to Group", "Apply to Group", bx + BTN_W + GAP_BTN,
                "Apply the selected preset's style to every bar in this group.", function()
                    local pr = SelectedPreset(); if not pr then return end
                    local gid = _tbbSelectedGroup
                    if not gid then
                        local sel = SelectedTBB()
                        gid = sel and ns.TBBBarGroupID(sel) or 0
                    end
                    if not gid or gid == 0 then return end
                    local t = ns.GetTrackedBuffBars()
                    for _, c in ipairs(t.bars or {}) do
                        if ns.TBBBarGroupID(c) == gid then
                            ns.ApplyTBBStylePresetToCfg(pr, c)
                        end
                    end
                    RefreshTBB(); EllesmereUI:RefreshPage()
                end)
            PresetBtn("New Preset", "Save New Preset", bx + (BTN_W + GAP_BTN) * 2,
                "Save this bar's current style as a new preset.", function()
                    local src = PreviewCfg()
                    if not src then return end
                    EllesmereUI:ShowInputPopup({
                        title       = EllesmereUI.L("Save Style Preset"),
                        message     = EllesmereUI.L("Enter a name for the new preset:"),
                        placeholder = UniqueTBBPresetName(),
                        confirmText = EllesmereUI.L("Save"),
                        cancelText  = EllesmereUI.L("Cancel"),
                        onConfirm   = function(nm)
                            if not nm or nm == "" then nm = UniqueTBBPresetName() end
                            if ns.SaveTBBStylePreset and ns.SaveTBBStylePreset(nm, src) then
                                local p = DB()
                                if p then p.tbbSelectedStylePreset = nm end
                            end
                            EllesmereUI:RefreshPage(true)
                        end,
                    })
                end)

            y = y - PR_ROW_H - 14

            -- Currently Editing: centered label + the bar/group management dropdown, between the preset panel and the settings sections.
            local ceLbl = EllesmereUI.MakeFont(parent, 12, nil, 1, 1, 1, 0.85)
            PP.Point(ceLbl, "TOP", parent, "TOP", 0, y)
            ceLbl:SetText(EllesmereUI.L("Currently Editing:"))
            ceLbl:SetJustifyH("CENTER")
            y = y - 16 - 6

            local mgmtDD = BuildManagementDropdown(parent)
            PP.Point(mgmtDD, "TOP", parent, "TOP", 0, y)
            y = y - 34 - 14
        end

        -------------------------------------------------------------------
        --  GROUP MODE: only this group's settings, no per-bar sections
        -------------------------------------------------------------------
        if _tbbSelectedGroup then
            local gid = _tbbSelectedGroup
            parent._showRowDivider = true
            parent._tbbClickTargets = nil

            _, h = W:SectionHeader(parent, "GROUP SETTINGS", y);  y = y - h

            -- Grow Direction | Bar Spacing
            _, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Grow Direction",
                  values = { DOWN = "Down", UP = "Up", LEFT = "Left", RIGHT = "Right" },
                  order = { "DOWN", "UP", "LEFT", "RIGHT" },
                  getValue = function() return ns.TBBGroupGrow(gid) end,
                  setValue = function(v)
                      ns.TBBSetGroupGrow(gid, v)
                      ns.BuildTrackedBuffBars()
                      -- Preview popout: RefreshPage() takes the fast path, repaint it here.
                      RefreshTBBPopout()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "slider", pixel = true, text = "Bar Spacing", min = -2, max = 20, step = 1,
                  getValue = function() return ns.TBBGroupSpacing(gid) end,
                  setValue = function(v)
                      ns.TBBSetGroupSpacing(gid, v)
                      ns.BuildTrackedBuffBars()
                      -- Preview popout: RefreshPage() takes the fast path, repaint it here.
                      RefreshTBBPopout()
                      EllesmereUI:RefreshPage()
                  end }
            );  y = y - h

            -- Group Name (blank = the default "Group N" label) | Auto-Add
            _, h = W:DualRow(parent, y,
                { type = "input", text = "Group Name", inputWidth = 160,
                  inputStyle = "popup",
                  placeholder = EllesmereUI.L("Group") .. " " .. gid,
                  tooltip = "Rename this group; leave blank for the default name.",
                  getValue = function()
                      return (ns.TBBGroupName and ns.TBBGroupName(gid)) or ""
                  end,
                  setValue = function(text)
                      if ns.TBBSetGroupName then ns.TBBSetGroupName(gid, text) end
                      RefreshTBB()
                      -- Soft refresh so the "Currently Editing:" dropdown label picks up the new name right away.
                      EllesmereUI:RefreshPage()
                  end },
                { type = "toggle", text = "Auto-Add New to This Group",
                  tooltip = "Automatically add a bar to this group for every spell in Blizzard's Tracked Bars section, now and whenever a new one appears.",
                  getValue = function() return ns.TBBGroupAutoAdd and ns.TBBGroupAutoAdd(gid) or false end,
                  setValue = function(v)
                      if not ns.TBBSetGroupAutoAdd then return end
                      ns.TBBSetGroupAutoAdd(gid, v)
                      if v and ns.PopulateTBBAutoAddGroup then
                          ns.PopulateTBBAutoAddGroup(gid)
                      end
                      ns.BuildTrackedBuffBars()
                      EllesmereUI:RefreshPage(true)
                  end }
            );  y = y - h

            -- Global Group | Shift Elements If No Bars
            local function GlobalEntry()
                local gk = ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid)
                return gk and ns.TBBGlobalGroup and ns.TBBGlobalGroup(gk) or nil
            end
            local shiftRow
            shiftRow, h = W:DualRow(parent, y,
                { type = "toggle", text = "Global Group",
                  tooltip = "Share this group's name, layout, and position across all specs.",
                  getValue = function()
                      return (ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid) ~= nil) or false
                  end,
                  setValue = function(v)
                      if not ns.TBBSetGroupGlobal then return end
                      ns.TBBSetGroupGlobal(gid, v)
                      ns.BuildTrackedBuffBars()
                      EllesmereUI:RefreshPage(true)
                  end },
                { type = "dropdown", text = "Shift Elements If No Bars",
                  tooltip = "When the current spec has no bars in this group, keeps elements anchored to the group in place and shifts them up or down by one bar height (tune with the cog's Extra Y Offset) to cover its empty slot.",
                  disabled = function() return GlobalEntry() == nil end,
                  disabledTooltip = "Global Group",
                  values = { None = "None", Up = "Up", Down = "Down" },
                  order = { "None", "Up", "Down" },
                  getValue = function()
                      local e = GlobalEntry()
                      return (e and e.shiftNoBar) or "None"
                  end,
                  setValue = function(v)
                      local e = GlobalEntry()
                      if not e then return end
                      if v == "Up" or v == "Down" then
                          e.shiftNoBar = v
                      else
                          e.shiftNoBar = nil
                      end
                      ns.BuildTrackedBuffBars()
                      EllesmereUI:RefreshPage()
                  end }
            );  y = y - h
            -- Inline reposition cog on the shift dropdown: Extra Y Offset
            -- (ResourceBars "Shift Elements if No Resource" parity).
            if not EllesmereUI._prebuilding then
                local rgn = shiftRow._rightRegion
                EllesmereUI.BuildInlineCog(rgn, {
                    title = "Shift Offset",
                    icon = EllesmereUI.DIRECTIONS_ICON,
                    rows = {
                        { type = "slider", pixel = true, label = "Extra Y Offset", min = -50, max = 50, step = 1,
                          get = function()
                              local e = GlobalEntry()
                              return (e and e.shiftNoBarExtraY) or 0
                          end,
                          set = function(v)
                              local e = GlobalEntry()
                              if not e then return end
                              e.shiftNoBarExtraY = (v ~= 0) and v or nil
                              ns.BuildTrackedBuffBars()
                              -- The build tail's cascade is EDGE-gated on the
                              -- shift direction, which a magnitude edit never
                              -- flips -- re-cascade explicitly so the slider
                              -- applies live (deferred batch coalesces drags).
                              local gk = ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid)
                              if gk and EllesmereUI.PropagateAnchorChain then
                                  EllesmereUI.PropagateAnchorChain("TBBG_" .. gk)
                              end
                          end },
                    },
                })
            end

            -- Ensure bar frames exist before showing placeholders
            ns.BuildTrackedBuffBars()
            UpdateTBBPlaceholder()
            RefreshTBBPopout()
            return math.abs(y)
        end

        -------------------------------------------------------------------
        --  Scrollable settings (bar mode)
        -------------------------------------------------------------------
        if not SelectedTBB() then
            HideTBBPlaceholder()
            return math.abs(y)
        end

        -- Append SharedMedia textures to runtime ns tables (for bar rendering)
        EllesmereUI.AppendSharedMediaTextures(
            ns.TBB_TEXTURE_NAMES or {},
            ns.TBB_TEXTURE_ORDER or {},
            nil,
            ns.TBB_TEXTURES
        )

        -- Texture dropdown values (built from ns tables, now including SM entries)
        local texValues = {}
        local texOrder = {}
        do
            local names = ns.TBB_TEXTURE_NAMES or {}
            local order = ns.TBB_TEXTURE_ORDER or {}
            local lookup = ns.TBB_TEXTURES or {}
            for _, key in ipairs(order) do
                if key ~= "---" then
                    texValues[key] = names[key] or key
                end
                texOrder[#texOrder + 1] = key
            end
            texValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    return lookup[key]
                end,
            }
        end

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  BAR LAYOUT
        -------------------------------------------------------------------
        local layoutHeader
        layoutHeader, h = W:SectionHeader(parent, "BAR LAYOUT", y);  y = y - h

        -- Height | Width. The whole group shares one width/height, so a grouped member
        -- inherits the group ANCHOR's match-lock: if size-matched, every member's slider
        -- is disabled (match wins) instead of silently fighting it.
        local tbbKey = "TBB_" .. _tbbSelectedBar
        do
            local selBd = SelectedTBB()
            local selGid = selBd and ns.TBBBarGroupID(selBd) or 0
            if selGid ~= 0 then
                local ai = ns.TBBGroupAnchorIndex(selGid)
                if ai then tbbKey = "TBB_" .. ai end
            end
        end
        local thDis, thTip, thRaw = EllesmereUI.MatchGuard(tbbKey, "Height")
        local twDis, twTip, twRaw = EllesmereUI.MatchGuard(tbbKey, "Width")
        -- Width is the THICKNESS of a vertical bar (toggle swaps stored dimensions), so its
        -- floor drops to 1 there -- a 50px floor would clamp a slim vertical bar the moment the slider is touched.
        local selIsVert
        do
            local sb0 = SelectedTBB()
            selIsVert = sb0 and sb0.verticalOrientation and true or false
        end
        local hwRow
        hwRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 800, step = 1,
              disabled = thDis, disabledTooltip = thTip, rawTooltip = thRaw,
              getValue = function() local bd = SelectedTBB(); return bd and bd.height or 24 end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.height = v
                  -- Grouped bars share height: write the rest of the group too.
                  local gid = ns.TBBBarGroupID(bd)
                  if gid ~= 0 then
                      local t = ns.GetTrackedBuffBars()
                      for _, b in ipairs(t.bars or {}) do
                          if b ~= bd and ns.TBBBarGroupID(b) == gid then b.height = v end
                      end
                  end
                  ns.BuildTrackedBuffBars()
                  -- BuildTrackedBuffBars() only rebuilds the LIVE bar pool; the
                  -- preview wraps in the popout are separate frames. RefreshPage()
                  -- takes the fast widget-refresh path here, so the page builder
                  -- tail that repaints the popout never re-runs. Repaint it
                  -- directly or the preview keeps the old geometry.
                  RefreshTBBPopout()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 1, max = 800, step = 1,
              disabled = twDis, disabledTooltip = twTip, rawTooltip = twRaw,
              getValue = function() local bd = SelectedTBB(); return bd and bd.width or 270 end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.width = v
                  -- Grouped bars share width: write the rest of the group too.
                  local gid = ns.TBBBarGroupID(bd)
                  if gid ~= 0 then
                      local t = ns.GetTrackedBuffBars()
                      for _, b in ipairs(t.bars or {}) do
                          if b ~= bd and ns.TBBBarGroupID(b) == gid then b.width = v end
                      end
                  end
                  ns.BuildTrackedBuffBars()
                  -- Preview popout: RefreshPage() takes the fast path, repaint it here.
                  RefreshTBBPopout()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Sync icons: Apply Height/Width to all bars of the SAME orientation -- "height" is
        -- the short side of a horizontal bar but the LONG side of a vertical one, so cross-orientation copies would be nonsense.
        if EllesmereUI.BuildSyncIcon then
            local function SameOrientation(a, b)
                return (a.verticalOrientation and true or false) == (b.verticalOrientation and true or false)
            end
            local orientWord = selIsVert and "Vertical" or "Horizontal"
            EllesmereUI.BuildSyncIcon({
                region = hwRow._leftRegion,
                tooltip = "Apply Height to all " .. orientWord .. " Bars",
                isSynced = function()
                    local bd = SelectedTBB(); if not bd then return false end
                    local val = bd.height or 24
                    local t = ns.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if SameOrientation(bd, b) and (b.height or 24) ~= val then return false end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB(); if not bd then return end
                    local val = bd.height or 24
                    local t = ns.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if SameOrientation(bd, b) then b.height = val end
                    end
                    RefreshTBB(); EllesmereUI:RefreshPage()
                end,
            })
            EllesmereUI.BuildSyncIcon({
                region = hwRow._rightRegion,
                tooltip = "Apply Width to all " .. orientWord .. " Bars",
                isSynced = function()
                    local bd = SelectedTBB(); if not bd then return false end
                    local val = bd.width or 270
                    local t = ns.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if SameOrientation(bd, b) and (b.width or 270) ~= val then return false end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB(); if not bd then return end
                    local val = bd.width or 270
                    local t = ns.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if SameOrientation(bd, b) then b.width = val end
                    end
                    RefreshTBB(); EllesmereUI:RefreshPage()
                end,
            })
        end

        -- Vertical Orientation | Bar Texture
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Vertical Orientation",
              tooltip = "Vertical bars fill upward; flipping a grouped bar flips its whole group.",
              getValue = function() local bd = SelectedTBB(); return bd and bd.verticalOrientation end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  -- Swap width/height so visual dimensions stay correct
                  local function flip(c)
                      c.width, c.height = (c.height or 24), (c.width or 270)
                      c.verticalOrientation = v
                  end
                  flip(bd)
                  -- Groups stay orientation-uniform: shared width/height only makes sense
                  -- when every member reads dimensions the same way, so the whole group flips together.
                  local gid = ns.TBBBarGroupID(bd)
                  if gid ~= 0 then
                      local t = ns.GetTrackedBuffBars()
                      for _, b in ipairs(t.bars or {}) do
                          if b ~= bd and ns.TBBBarGroupID(b) == gid
                             and (b.verticalOrientation and true or false) ~= (v and true or false) then
                              flip(b)
                          end
                      end
                      -- Rotate the grow direction so side-by-side stays side-by-side across the flip (DOWN<->RIGHT, UP<->LEFT).
                      local rot = v and { DOWN = "RIGHT", UP = "LEFT" }
                                    or { RIGHT = "DOWN", LEFT = "UP" }
                      local grow = ns.TBBGroupGrow(gid)
                      if rot[grow] then ns.TBBSetGroupGrow(gid, rot[grow]) end
                  end
                  RefreshTBB()
                  -- Full rebuild: the Width slider's floor and sync tooltips are orientation-dependent.
                  EllesmereUI:RefreshPage(true)
              end },
            GateBlizzardOnly("cdmbars", { type = "dropdown", text = "Bar Texture",
              values = texValues, order = texOrder,
              getValue = function() local bd = SelectedTBB(); return bd and bd.texture or "none" end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.texture = v; RefreshTBB()
              end })
        );  y = y - h

        -- Name Text (dropdown + cog) | Duration Text (dropdown + cog)
        local TBB_POS_VALUES = { none = "None", center = "Center", top = "Top", bottom = "Bottom", left = "Left", right = "Right" }
        local TBB_POS_ORDER = { "none", "center", "top", "bottom", "left", "right" }

        -- When a text element claims a position, evict any other text already there so
        -- labels never overlap. Compares EFFECTIVE (rendered) positions: name text never
        -- renders on vertical bars, so its stored slot must not evict anything there.
        local function EvictTBBTextConflicts(bd, changedKey, newPos)
            if newPos == "none" then return end
            local function resolvePos(key)
                if key == "namePosition" and bd.verticalOrientation then return "none" end
                local v = bd[key]
                if v then return v end
                if key == "namePosition" then return (bd.showName ~= false) and "left" or "none" end
                if key == "timerPosition" then return bd.showTimer and "right" or "none" end
                if key == "stacksPosition" then return "center" end
                return "none"
            end
            local TEXT_KEYS = { "namePosition", "timerPosition", "stacksPosition" }
            for _, k in ipairs(TEXT_KEYS) do
                if k ~= changedKey and resolvePos(k) == newPos then
                    bd[k] = "none"
                    if k == "namePosition" then bd.showName = false
                    elseif k == "timerPosition" then bd.showTimer = false end
                end
            end
        end

        local function AddTBBTextSwatch(row, region, prefix)
            local ctrl = region._control
            local function GetColor()
                local bd = SelectedTBB()
                if not bd then return 1, 1, 1, 0.9 end
                local r = bd[prefix .. "TextR"]
                local g = bd[prefix .. "TextG"]
                local b = bd[prefix .. "TextB"]
                local a = bd[prefix .. "TextA"]
                if r == nil then r = 1 end
                if g == nil then g = 1 end
                if b == nil then b = 1 end
                if a == nil then a = 0.9 end
                return r, g, b, a
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                region, row:GetFrameLevel() + 3, GetColor,
                function(r, g, b, a)
                    local bd = SelectedTBB(); if not bd then return end
                    bd[prefix .. "TextR"] = r
                    bd[prefix .. "TextG"] = g
                    bd[prefix .. "TextB"] = b
                    bd[prefix .. "TextA"] = a
                    RefreshTBB()
                end,
                true, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -12, 0)
            region._lastInline = swatch

            local block = CreateFrame("Frame", nil, swatch)
            block:SetAllPoints()
            block:SetFrameLevel(swatch:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                local bd = SelectedTBB()
                local tip
                if prefix == "name" and bd and bd.verticalOrientation then
                    tip = "Horizontal Orientation (name text is not shown on vertical bars)"
                else
                    local label = prefix == "timer" and "Duration Text"
                        or (prefix == "stacks" and "Stacks Text" or "Name Text")
                    tip = "This option requires a " .. label .. " position other than None"
                end
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip(tip))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function UpdateSwatchState()
                local bd = SelectedTBB()
                local position
                if bd then
                    position = bd[prefix .. "Position"]
                    if not position then
                        if prefix == "name" then
                            position = (bd.showName ~= false) and "left" or "none"
                        elseif prefix == "timer" then
                            position = bd.showTimer and "right" or "none"
                        else
                            position = "center"
                        end
                    end
                end
                local enabled = position ~= nil and position ~= "none"
                if prefix == "name" and bd and bd.verticalOrientation then enabled = false end
                swatch:SetAlpha(enabled and 1 or 0.3)
                if enabled then block:Hide() else block:Show() end
            end

            EllesmereUI.RegisterWidgetRefresh(function()
                updateSwatch()
                UpdateSwatchState()
            end)
            UpdateSwatchState()
        end

        local nameRow
        nameRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Name Text",
              values = TBB_POS_VALUES, order = TBB_POS_ORDER,
              disabled = function()
                  local bd = SelectedTBB()
                  return bd and bd.verticalOrientation and true or false
              end,
              disabledTooltip = "Horizontal Orientation (name text is not shown on vertical bars)",
              getValue = function()
                  local bd = SelectedTBB(); if not bd then return "left" end
                  if bd.namePosition then return bd.namePosition end
                  return (bd.showName ~= false) and "left" or "none"
              end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  EvictTBBTextConflicts(bd, "namePosition", v)
                  bd.namePosition = v
                  bd.showName = (v ~= "none")
                  RefreshTBB(); EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Duration Text",
              values = TBB_POS_VALUES, order = TBB_POS_ORDER,
              getValue = function()
                  local bd = SelectedTBB(); if not bd then return "right" end
                  if bd.timerPosition then return bd.timerPosition end
                  return bd.showTimer and "right" or "none"
              end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  EvictTBBTextConflicts(bd, "timerPosition", v)
                  bd.timerPosition = v
                  bd.showTimer = (v ~= "none")
                  RefreshTBB(); EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        AddTBBTextSwatch(nameRow, nameRow._leftRegion, "name")
        AddTBBTextSwatch(nameRow, nameRow._rightRegion, "timer")
        -- Cog on Name Text: text size + x/y
        do
            local rgn = nameRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Name Text Settings",
                icon = EllesmereUI.DIRECTIONS_ICON,
                disabled = function()
                    local bd = SelectedTBB()
                    if bd and bd.verticalOrientation then return true end
                    local pos = bd and bd.namePosition
                    if not pos then pos = (bd and bd.showName ~= false) and "left" or "none" end
                    return pos == "none"
                end,
                disabledTooltip = function()
                    local bd = SelectedTBB()
                    if bd and bd.verticalOrientation then return "Horizontal Orientation (name text is not shown on vertical bars)" end
                    return "This option requires a Name Text position other than None"
                end,
                rows = {
                    { type = "slider", label = "Text Size", min = 8, max = 24, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.nameSize or 11 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.nameSize = v; RefreshTBB()
                      end },
                    { type = "toggle", label = "Text Wrap",
                      get = function() local bd = SelectedTBB(); return bd and bd.nameWrap == true end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.nameWrap = v or nil; RefreshTBB()
                      end },
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.nameX or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.nameX = v; RefreshTBB()
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.nameY or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.nameY = v; RefreshTBB()
                      end },
                },
            })
        end
        -- Sync icon on Name Text
        do
            local rgn = nameRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Name Text to all Bars",
                isSynced = function()
                    local bd = SelectedTBB(); if not bd then return false end
                    local pos = bd.namePosition or ((bd.showName ~= false) and "left" or "none")
                    local tbb = ns.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        local bp = b.namePosition or ((b.showName ~= false) and "left" or "none")
                        if bp ~= pos then return false end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB(); if not bd then return end
                    local pos = bd.namePosition or ((bd.showName ~= false) and "left" or "none")
                    local tbb = ns.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        b.namePosition = pos
                        b.showName = (pos ~= "none")
                    end
                    RefreshTBB(); EllesmereUI:RefreshPage()
                end,
            })
        end
        -- Cog on Duration Text: timer size + x/y
        do
            local rgn = nameRow._rightRegion
            local durationRows = {
                    { type = "slider", label = "Timer Size", min = 8, max = 24, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.timerSize or 11 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.timerSize = v; RefreshTBB()
                      end },
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.timerX or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.timerX = v; RefreshTBB()
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.timerY or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.timerY = v; RefreshTBB()
                      end },
            }
            -- Engine-rendered tenths below the threshold (see EllesmereUICdmTbbDecimals.lua).
                table.insert(durationRows, 2,
                    { type = "toggle", label = "Decimals",
                      tooltip = "Cannot work for pet/totem summon bars (Call Dreadstalkers, etc.) -- they expose no readable timer.",
                      get = function() local bd = SelectedTBB(); return bd and bd.timerDecimals == true end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.timerDecimals = v or nil; RefreshTBB()
                      end })
                table.insert(durationRows, 3,
                    { type = "slider", label = "Decimal Threshold", min = 1, max = 120, step = 1,
                      disabled = function()
                          local bd = SelectedTBB()
                          return not (bd and bd.timerDecimals)
                      end,
                      disabledTooltip = "Decimals enabled",
                      get = function() local bd = SelectedTBB(); return bd and bd.timerDecimalThreshold or 5 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.timerDecimalThreshold = v; RefreshTBB()
                      end })
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Duration Text Settings",
                rows = durationRows,
                icon = EllesmereUI.DIRECTIONS_ICON,
                disabled = function()
                    local bd = SelectedTBB()
                    local pos = bd and bd.timerPosition
                    if not pos then pos = (bd and bd.showTimer) and "right" or "none" end
                    return pos == "none"
                end,
                disabledTooltip = "This option requires a Duration Text position other than None",
            })
        end
        -- Sync icon on Duration Text
        do
            local rgn = nameRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Duration Text to all Bars",
                isSynced = function()
                    local bd = SelectedTBB(); if not bd then return false end
                    local pos = bd.timerPosition or (bd.showTimer and "right" or "none")
                    local tbb = ns.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        local bp = b.timerPosition or (b.showTimer and "right" or "none")
                        if bp ~= pos then return false end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB(); if not bd then return end
                    local pos = bd.timerPosition or (bd.showTimer and "right" or "none")
                    local tbb = ns.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        b.timerPosition = pos
                        b.showTimer = (pos ~= "none")
                    end
                    RefreshTBB(); EllesmereUI:RefreshPage()
                end,
            })
        end

        -- Stacks Text (dropdown + resize cog: size, x, y) | Bar Strata
        local stacksRow
        stacksRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Stacks Text",
              values = TBB_POS_VALUES, order = TBB_POS_ORDER,
              getValue = function() local bd = SelectedTBB(); return bd and bd.stacksPosition or "center" end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  EvictTBBTextConflicts(bd, "stacksPosition", v)
                  bd.stacksPosition = v; RefreshTBB(); EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Bar Strata",
              tooltip = "Screen layer the bar renders on; changing a grouped bar changes its whole group.",
              values = EllesmereUI.FRAME_STRATA_LABELS,
              order = EllesmereUI.FRAME_STRATA_ORDER_FULL,
              getValue = function() local bd = SelectedTBB(); return bd and bd.strata or "MEDIUM" end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.strata = v
                  -- Grouped bars share one strata: write the rest of the group too.
                  local gid = ns.TBBBarGroupID(bd)
                  if gid ~= 0 then
                      local t = ns.GetTrackedBuffBars()
                      for _, b in ipairs(t.bars or {}) do
                          if b ~= bd and ns.TBBBarGroupID(b) == gid then b.strata = v end
                      end
                  end
                  RefreshTBB()
              end }
        );  y = y - h
        AddTBBTextSwatch(stacksRow, stacksRow._leftRegion, "stacks")
        do
            local rgn = stacksRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Stacks Text Settings",
                icon = EllesmereUI.DIRECTIONS_ICON,
                disabled = function()
                    local bd = SelectedTBB()
                    return bd and (bd.stacksPosition or "center") == "none"
                end,
                disabledTooltip = "This option requires a Stacks Text position other than None",
                rows = {
                    { type = "slider", label = "Size", min = 6, max = 24, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.stacksSize or 11 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.stacksSize = v; RefreshTBB()
                      end },
                    { type = "slider", label = "X Offset", min = -250, max = 250, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.stacksX or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.stacksX = v; RefreshTBB()
                      end },
                    { type = "slider", label = "Y Offset", min = -250, max = 250, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.stacksY or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.stacksY = v; RefreshTBB()
                      end },
                },
            })
        end
        -- Sync icon on Stacks Text
        do
            local rgn = stacksRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Stacks Text to all Bars",
                isSynced = function()
                    local bd = SelectedTBB(); if not bd then return false end
                    local pos = bd.stacksPosition or "center"
                    local tbb = ns.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        if (b.stacksPosition or "center") ~= pos then return false end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB(); if not bd then return end
                    local pos = bd.stacksPosition or "center"
                    local tbb = ns.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do b.stacksPosition = pos end
                    RefreshTBB(); EllesmereUI:RefreshPage()
                end,
            })
        end

        -- Reverse Fill | Fill Up. Deliberately paired on one row: they are the
        -- two options a user reaches for when the bar is not moving the way
        -- they expect, and they do different things. Reverse Fill mirrors the
        -- geometry, Fill Up flips the direction the value travels. Splitting
        -- them across the page is what makes people try the wrong one.
        -- Named distinctly: `fillRow` is already taken further down by the
        -- Fill Color row, which preview click-nav targets by reference.
        local fillDirRow
        fillDirRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Reverse Fill",
              tooltip = "Mirrors which end of the bar the fill is anchored to. It does not change the direction the bar travels: use Fill Up for that.",
              getValue = function() local bd = SelectedTBB(); return bd and bd.reverseFill end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.reverseFill = v; RefreshTBB()
              end },
            { type = "toggle", text = "Fill Up",
              tooltip = "Fills the bar as the cooldown recovers instead of draining it as the cooldown runs down.",
              disabled = function()
                  local bd = SelectedTBB()
                  -- Charge Hash Lines drives its own recovery bar, which
                  -- already fills upward, so fillUp cannot do anything there.
                  -- Leaving the toggle live would promise behaviour it has no
                  -- way to deliver. Test the same way the Charge Hash Lines
                  -- toggle does: the stored flag alone is not enough, because
                  -- chargeHashLines rides in TBB_STYLE_KEYS and a style copy
                  -- or preset can set it on a single-charge spell, where the
                  -- hash fill never actually runs.
                  return not bd or bd.trackType ~= "cooldown"
                      or (bd.chargeHashLines == true
                          and SelectedTBBSupportsChargeHash())
              end,
              -- rawTooltip: these are whole sentences. Without it they get
              -- wrapped into "This option requires <text> to be enabled".
              rawTooltip = true,
              disabledTooltip = function()
                  local bd = SelectedTBB()
                  if not bd or bd.trackType ~= "cooldown" then
                      return "This option requires a cooldown-tracking bar"
                  end
                  return "Charge Hash Lines already fills as charges recover"
              end,
              getValue = function()
                  local bd = SelectedTBB(); return bd and bd.fillUp == true
              end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.fillUp = v and true or nil
                  RefreshTBB()
              end }
        );  y = y - h

        -- Charge Hash Lines | Smooth Bars. Hash separator count/orientation resolve
        -- automatically from the spell's max charges; Smooth Bars is profile-wide, not per bar/spec.
        local SMOOTH_ITEMS = {
            { key = "buffs",     label = "Buffs" },
            { key = "cooldowns", label = "Cooldowns" },
        }
        local SMOOTH_DEFAULT = { buffs = true, cooldowns = false }
        local chargeHashRow
        chargeHashRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Charge Hash Lines",
              tooltip = "Divides a cooldown-tracking bar into one recovery section per ability charge. The timer shows the next charge's cooldown.",
              disabled = function()
                  local bd = SelectedTBB()
                  return not bd or bd.trackType ~= "cooldown"
                      or not SelectedTBBSupportsChargeHash()
              end,
              disabledTooltip = function()
                  local bd = SelectedTBB()
                  if not bd or bd.trackType ~= "cooldown" then
                      return "This option requires a cooldown-tracking bar"
                  end
                  return "This option is only available for abilities with multiple charges"
              end,
              getValue = function()
                  local bd = SelectedTBB()
                  return bd and bd.chargeHashLines == true
                      and SelectedTBBSupportsChargeHash()
              end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  if v and not SelectedTBBSupportsChargeHash() then return end
                  bd.chargeHashLines = v and true or nil
                  RefreshTBB(); EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Smooth Bars",
              tooltip = "Eases bar movement instead of snapping. Affects all Tracking Bars of that type, in every spec of this profile.",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end });  y = y - h
        do
            local rgn = chargeHashRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Charge Hash Line Settings",
                disabled = function()
                    local bd = SelectedTBB()
                    return not bd or bd.trackType ~= "cooldown"
                        or not SelectedTBBSupportsChargeHash()
                        or bd.chargeHashLines ~= true
                end,
                disabledTooltip = function()
                    local bd = SelectedTBB()
                    if not bd or bd.trackType ~= "cooldown" then return "This option requires a cooldown-tracking bar" end
                    if not SelectedTBBSupportsChargeHash() then return "This option is only available for abilities with multiple charges" end
                    return "Enable Charge Hash Lines first"
                end,
                rawTooltip = true,
                rows = {
                    { type = "slider", label = "Line Width", min = 1, max = 10, step = 1,
                      get = function()
                          local bd = SelectedTBB()
                          return bd and bd.chargeHashLineWidth or 2
                      end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.chargeHashLineWidth = v
                          RefreshTBB()
                      end },
                    { type = "colorpicker", label = "Line Color", hasAlpha = true,
                      get = function()
                          local bd = SelectedTBB()
                          if not bd then return 0, 0, 0, 1 end
                          local a = bd.chargeHashLineA
                          if a == nil then a = 1 end
                          return bd.chargeHashLineR or 0, bd.chargeHashLineG or 0,
                              bd.chargeHashLineB or 0, a
                      end,
                      set = function(r, g, b, a)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.chargeHashLineR, bd.chargeHashLineG = r, g
                          bd.chargeHashLineB, bd.chargeHashLineA = b, a
                          RefreshTBB()
                      end },
                    { type = "toggle", label = "Partial Charge Shade",
                      tooltip = "Darkens the section of the bar that is still recharging the next charge.",
                      get = function()
                          local bd = SelectedTBB()
                          return bd and bd.chargeHashShade == true
                      end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.chargeHashShade = v and true or nil
                          RefreshTBB()
                      end },
                    { type = "slider", label = "Shade Darkness", min = 5, max = 95, step = 5,
                      disabled = function()
                          local bd = SelectedTBB()
                          return not bd or bd.chargeHashShade ~= true
                      end,
                      get = function()
                          local bd = SelectedTBB()
                          return bd and math.floor(((bd.chargeHashShadeAlpha or 0.5) * 100) + 0.5) or 50
                      end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.chargeHashShadeAlpha = (v or 50) / 100
                          RefreshTBB()
                      end },
                },
            })
        end

        do
            local rgn = chargeHashRow._rightRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2,
                SMOOTH_ITEMS,
                function(k)
                    local s = ns.GetTBBSmoothSettings and ns.GetTBBSmoothSettings()
                    if not s or s[k] == nil then return SMOOTH_DEFAULT[k] end
                    return s[k] == true
                end,
                function(k, v)
                    local s = ns.GetTBBSmoothSettings and ns.GetTBBSmoothSettings()
                    if s then s[k] = v and true or false end
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        local displayHeader
        displayHeader, h = W:SectionHeader(parent, "Display", y);  y = y - h
        y = EllesmereUI.BlizzStyle.Note(parent, y, "cdmbars")

        -- Visibility: one control, the shared axis list plus the TBB-only Hide When
        -- Inactive row (single-lane, so it rides in as an extraItem). No mouseover for
        -- CDM-family bars; "Only In Combat" is the In Combat axis.
        local _, tbbVisH = EllesmereUI.BuildVisibilityRow(W, parent, y,
            { getStore = SelectedTBB, legacyKey = "barVisibility",
              caps = { partyIncludesRaid = false, noMouseover = true, luaDragonriding = true },
              onChanged = function() RefreshTBB() end,
              onOptionChanged = function() RefreshTBB() end,
              extraItems = {
                  { key = "hideWhenInactive", label = "Hide When Inactive",
                    tooltip = "Only show this bar while the tracked buff/cooldown is active. Unchecked keeps an empty bar on screen at all times.",
                    -- nil means ON everywhere this is read, so it cannot go through a
                    -- plain truthiness path.
                    get = function()
                        local bd = SelectedTBB()
                        return bd and bd.hideWhenInactive ~= false
                    end,
                    -- No refresh here: the row fires onOptionChanged after every write.
                    set = function(v)
                        local bd = SelectedTBB(); if not bd then return end
                        bd.hideWhenInactive = v
                    end },
              } },
            -- Show Icon moved up into the slot the Visibility Options dropdown left behind.
            { type = "dropdown", text = "Show Icon",
              values = { none = "None", left = "Left (Top)", right = "Right (Bottom)" },
              order = { "none", "left", "right" },
              getValue = function() local bd = SelectedTBB(); return bd and bd.iconDisplay or "none" end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.iconDisplay = v; RefreshTBB()
              end });  y = y - tbbVisH

        -- Opacity | Background Color (moved up from its old trailing half-row below)
        local iconRow
        iconRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 1,
              getValue = function()
                  local bd = SelectedTBB()
                  return bd and math.floor((bd.opacity or 1.0) * 100 + 0.5) or 100
              end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.opacity = v / 100; RefreshTBB()
              end },
            { type = "multiSwatch", text = "Background Color",
              swatches = {
                  GateBlizzardOnly("cdmbars", { tooltip = "Background Color", hasAlpha = true,
                    getValue = function()
                        local bd = SelectedTBB()
                        return (bd and bd.bgR or 0), (bd and bd.bgG or 0), (bd and bd.bgB or 0), (bd and bd.bgA or 0.4)
                    end,
                    setValue = function(r, g, b, a)
                        local bd = SelectedTBB(); if not bd then return end
                        bd.bgR, bd.bgG, bd.bgB, bd.bgA = r, g, b, a; RefreshTBB()
                    end }),
              } }
        );  y = y - h

        -- Fill Color (dropdown: auto/custom + gradient mode + 2 inline swatches) | Show Spark
        local fillRow
        fillRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("cdmbars", { type = "dropdown", text = "Fill Color",
              values = {
                  none = "Custom Color",
                  VERTICAL = "Vertical Gradient",
                  HORIZONTAL = "Horizontal Gradient",
              },
              order = { "none", "HORIZONTAL", "VERTICAL" },
              getValue = function()
                  local bd = SelectedTBB(); if not bd then return "none" end
                  -- Treat legacy "auto" as "custom" (no migration needed)
                  if not bd.gradientEnabled then return "none" end
                  return bd.gradientDir or "HORIZONTAL"
              end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.fillColorMode = "custom"
                  if v == "none" then
                      bd.gradientEnabled = false
                  else
                      bd.gradientEnabled = true
                      bd.gradientDir = v
                  end
                  RefreshTBB(); EllesmereUI:RefreshPage()
              end }),
            { type = "toggle", text = "Show Spark",
              getValue = function() local bd = SelectedTBB(); return bd and bd.showSpark end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.showSpark = v; RefreshTBB()
              end }
        );  y = y - h
        -- Inline swatches on Fill Color dropdown: fill color + gradient end color
        do
            local rgn = fillRow._leftRegion
            local ctrl = rgn._control

            -- Swatch 1 (rightmost, closer to dropdown): Fill Color
            local fillSwatch, updateFillSwatch = EllesmereUI.BuildColorSwatch(
                rgn, fillRow:GetFrameLevel() + 3,
                function()
                    local bd = SelectedTBB()
                    if not bd then
                        local _, cf = UnitClass("player")
                        local cc = RAID_CLASS_COLORS[cf]
                        return cc and cc.r or 1, cc and cc.g or 0.70, cc and cc.b or 0, 1
                    end
                    return bd.fillR, bd.fillG, bd.fillB, bd.fillA
                end,
                function(r, g, b, a)
                    local bd = SelectedTBB(); if not bd then return end
                    bd.fillColorMode = "custom"
                    bd.fillR, bd.fillG, bd.fillB, bd.fillA = r, g, b, a; RefreshTBB()
                end,
                true, 20)
            PP.Point(fillSwatch, "RIGHT", ctrl, "LEFT", -8, 0)

            -- Swatch 2 (left of swatch 1): Gradient End Color
            local gradSwatch, updateGradSwatch = EllesmereUI.BuildColorSwatch(
                rgn, fillRow:GetFrameLevel() + 3,
                function()
                    local bd = SelectedTBB()
                    if not bd then return 0.20, 0.20, 0.80, 1 end
                    return bd.gradientR, bd.gradientG, bd.gradientB, bd.gradientA
                end,
                function(r, g, b, a)
                    local bd = SelectedTBB(); if not bd then return end
                    bd.gradientR, bd.gradientG, bd.gradientB, bd.gradientA = r, g, b, a; RefreshTBB()
                end,
                true, 20)
            PP.Point(gradSwatch, "RIGHT", fillSwatch, "LEFT", -4, 0)

            -- Disable block on fill swatch when Auto mode
            local fillBlock = CreateFrame("Frame", nil, fillSwatch)
            fillBlock:SetAllPoints(); fillBlock:SetFrameLevel(fillSwatch:GetFrameLevel() + 10)
            fillBlock:EnableMouse(true)
            fillBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(fillSwatch, EllesmereUI.DisabledTooltip("This option requires Fill Color to be set to Custom"))
            end)
            fillBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Disable block on gradient swatch when gradient is off or auto mode
            local gradBlock = CreateFrame("Frame", nil, gradSwatch)
            gradBlock:SetAllPoints(); gradBlock:SetFrameLevel(gradSwatch:GetFrameLevel() + 10)
            gradBlock:EnableMouse(true)
            gradBlock:SetScript("OnEnter", function()
                local bd = SelectedTBB()
                local isAuto = false
                local msg = isAuto and "Set Fill Color to a Custom option" or "This option requires a gradient to be set"
                EllesmereUI.ShowWidgetTooltip(gradSwatch, EllesmereUI.DisabledTooltip(msg))
            end)
            gradBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function UpdateSwatchStates()
                local bd = SelectedTBB()
                local isAuto = false
                -- Blizzard Style keeps the flat atlas fill, so the gradient end colour is inert there.
                local noGrad = not bd or not bd.gradientEnabled or EllesmereUI.BlizzStyle.Get("cdmbars")
                -- Fill swatch: disabled in auto mode
                if isAuto then fillSwatch:SetAlpha(0.3); fillBlock:Show()
                else fillSwatch:SetAlpha(1); fillBlock:Hide() end
                -- Grad swatch: disabled in auto mode OR when no gradient
                if isAuto or noGrad then gradSwatch:SetAlpha(0.3); gradBlock:Show()
                else gradSwatch:SetAlpha(1); gradBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateFillSwatch(); updateGradSwatch(); UpdateSwatchStates() end)
            UpdateSwatchStates()
        end

        -- Border Texture dropdown (+ inline offset cog) | empty
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local tbbBsRow
            tbbBsRow, h = W:DualRow(parent, y,
                EllesmereUI.BlizzStyle.Gate("cdmbars", { type="dropdown", text="Border Texture",
                  values=texValues, order=texOrder,
                  getValue=function() local bd = SelectedTBB(); return bd and bd.borderTexture or "solid" end,
                  setValue=function(v)
                      local bd = SelectedTBB(); if not bd then return end
                      bd.borderTexture = v; bd.borderTextureOffset = nil; bd.borderTextureOffsetY = nil; bd.borderTextureShiftX = nil; bd.borderTextureShiftY = nil
                      local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      bd.borderR = _bcol.r; bd.borderG = _bcol.g; bd.borderB = _bcol.b
                      bd.borderBehind = _bbehind
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then bd.borderSize = defSz end
                      if bd.borderSizePx then bd.borderSizePx = false end
                      RefreshTBB(); EllesmereUI:RefreshPage(true)
                  end }),
                -- Classic WoW UI: the slot sizes the vanilla frame instead.
                (EllesmereUI.BlizzStyle.Active("cdmbars") == "classic") and EllesmereUI.BlizzStyle.ClassicBorderSizeCfg(
                    function() local bd = SelectedTBB(); return bd and bd.stockBorderScale end,
                    function(v)
                        local bd = SelectedTBB(); if not bd then return end
                        bd.stockBorderScale = v; RefreshTBB()
                    end) or
                EllesmereUI.BlizzStyle.Gate("cdmbars", EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
                  getStep = function() local bd = SelectedTBB(); return bd and bd.borderSize or 0 end,
                  setStep = function(step) local bd = SelectedTBB(); if bd then bd.borderSize = step end end,
                  getTex = function() local bd = SelectedTBB(); return bd and bd.borderTexture or "solid" end,
                  getPx = function() local bd = SelectedTBB(); return bd and bd.borderSizePx end,
                  setPx = function(v) local bd = SelectedTBB(); if bd then bd.borderSizePx = v end end,
                  apply = function() RefreshTBB() end,
                })));  y = y - h
            -- Width Offset | Height Offset: the textured border's outward offsets,
            -- present only while a textured style is selected (built on the
            -- prebuild pass too, so the y advance is identical).
            do
                local bd0 = SelectedTBB()
                local tex0 = bd0 and bd0.borderTexture or "solid"
                if tex0 ~= "" and tex0 ~= "solid" then
                    local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                        addonKey = "resourcebars",
                        getTex = function() local bd = SelectedTBB(); return bd and bd.borderTexture or "solid" end,
                        getStep = function() local bd = SelectedTBB(); return bd and bd.borderSize or 0 end,
                        getSizeKey = function() local bd = SelectedTBB(); return bd and bd.borderSize or 0 end,
                        getPx = function() local bd = SelectedTBB(); return bd and bd.borderSizePx end,
                        getX = function() local bd = SelectedTBB(); return bd and bd.borderTextureOffset end,
                        setX = function(v) local bd = SelectedTBB(); if bd then bd.borderTextureOffset = v end end,
                        getY = function() local bd = SelectedTBB(); return bd and bd.borderTextureOffsetY end,
                        setY = function(v) local bd = SelectedTBB(); if bd then bd.borderTextureOffsetY = v end end,
                        apply = function() RefreshTBB() end,
                    })
                    _, h = W:DualRow(parent, y,
                        EllesmereUI.BlizzStyle.Gate("cdmbars", ocfgL),
                        EllesmereUI.BlizzStyle.Gate("cdmbars", ocfgR));  y = y - h
                end
            end
            -- Inline border color swatch on Border Size (right region); none
            -- under Classic WoW UI, whose slider sizes the vanilla frame.
            if EllesmereUI.BlizzStyle.Active("cdmbars") ~= "classic" then
                local rgn = tbbBsRow._rightRegion
                local ctrl = rgn._control
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, tbbBsRow:GetFrameLevel() + 3,
                    function()
                        local bd = SelectedTBB()
                        return (bd and bd.borderR or 0), (bd and bd.borderG or 0), (bd and bd.borderB or 0)
                    end,
                    function(r, g, b)
                        local bd = SelectedTBB(); if not bd then return end
                        bd.borderR, bd.borderG, bd.borderB = r, g, b; RefreshTBB()
                    end,
                    false, 20)
                PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
                EllesmereUI.BlizzStyle.BlockInline("cdmbars", borderSwatch)
            end
            do
                local rgn = tbbBsRow._leftRegion
                local cogBtn = EllesmereUI.BuildInlineCog(rgn, {
                    icon = EllesmereUI.DIRECTIONS_ICON,
                    title = "Border Options",
                    rows = {
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local bd = SelectedTBB(); if not bd then return 0 end
                              local v = bd.borderTextureShiftX
                              if v then return v end
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", bd.borderTexture or "solid", bd.borderSize or 0)
                              return dsx
                          end,
                          set = function(v)
                              local bd = SelectedTBB(); if not bd then return end
                              bd.borderTextureShiftX = v == 0 and nil or v; RefreshTBB()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local bd = SelectedTBB(); if not bd then return 0 end
                              local v = bd.borderTextureShiftY
                              if v then return v end
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", bd.borderTexture or "solid", bd.borderSize or 0)
                              return dsy
                          end,
                          set = function(v)
                              local bd = SelectedTBB(); if not bd then return end
                              bd.borderTextureShiftY = v == 0 and nil or v; RefreshTBB()
                          end },
                        { type = "toggle", label = "Show Behind",
                          get = function()
                              local bd = SelectedTBB(); return bd and bd.borderBehind or false
                          end,
                          set = function(v)
                              local bd = SelectedTBB(); if not bd then return end
                              bd.borderBehind = v == false and nil or v; RefreshTBB()
                          end },
                    },
                })
                if cogBtn then
                    local function UpdateCogVis()
                        local bd = SelectedTBB()
                        local tex = bd and bd.borderTexture or "solid"
                        cogBtn:SetShown(tex ~= "solid" and not EllesmereUI.BlizzStyle.Get("cdmbars"))
                    end
                    EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                    UpdateCogVis()
                end
            end
        end

        -----------------------------------------------------------------------
        --  EXTRAS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h

        -- Row 1: Pandemic Glow (dropdown + swatch + cog + sync) | Stack Based
        -- Bar (buff bars only; page rebuilds on selection change, so cd/utility
        -- bars get a blank slot). Stack Based Bar is inert until Max Stacks is
        -- enabled below.
        do
            -- Shared glow controls over the bar's pandemic keys (the Glows page's
            -- Tracked Buff Bar descriptor, resolving the selected bar).
            local GO = EllesmereUI.GlowOptions
            local tbbDesc = ns._CDM_TbbGlowDesc(SelectedTBB, function() RefreshTBB() end)

            local bd0 = SelectedTBB()
            local rightSlot
            if bd0 and bd0.trackType ~= "cooldown" then
                rightSlot = { type = "toggle", text = "Stack Based Bar",
                    tooltip = "Fill this bar from current stacks out of Max Stacks instead of remaining time (requires Enable Max Stacks below).",
                    getValue = function() local bd = SelectedTBB(); return bd and bd.stackBasedBar end,
                    setValue = function(v)
                        local bd = SelectedTBB(); if not bd then return end
                        bd.stackBasedBar = v and true or false; RefreshTBB()
                    end }
            else
                rightSlot = { type = "label", text = "" }
            end

            local tbbPanRow
            tbbPanRow, h = W:DualRow(parent, y, GO.DropdownSpec(tbbDesc, "Pandemic Glow",
                "Show a glow on the bar when the remaining duration is in the pandemic window (last 30%)"), rightSlot);  y = y - h
            GO.AttachInline(tbbPanRow._leftRegion, tbbDesc)

            -- Apply All
            if EllesmereUI.BuildSyncIcon and EllesmereUI.ApplyPandemicGlowToAll then
                EllesmereUI.BuildSyncIcon({
                    region = tbbPanRow._leftRegion,
                    tooltip = "Apply this pandemic glow to Nameplates, all CDM bars, and other tracking bars. A surface that can't show a style uses its closest match.",
                    isSynced = function()
                        local src = SelectedTBB(); if not src then return true end
                        return EllesmereUI.IsPandemicGlowSyncedToAll(EllesmereUI.PandemicPayloadFromRectBar(src), { skipTbbBar = src })
                    end,
                    onClick = function()
                        local src = SelectedTBB(); if not src then return end
                        EllesmereUI.ApplyPandemicGlowToAll(EllesmereUI.PandemicPayloadFromRectBar(src), { skipTbbBar = src })
                        RefreshTBB()
                    end,
                })
            end
        end

        -- Row 2: Enable Max Stacks (toggle + inline slider) | Ticks at Stacks (label + inline input)
        local function maxStacksOff()
            local bd = SelectedTBB()
            return not bd or not bd.stackThresholdMaxEnabled
        end
        local maxStacksRow
        maxStacksRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Max Stacks",
              getValue = function() local bd = SelectedTBB(); return bd and bd.stackThresholdMaxEnabled end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.stackThresholdMaxEnabled = v; RefreshTBB(); EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "Ticks at Stacks",
              tooltip = "Comma separated stack counts to put a tick mark at. Type all to mark every stack." }
        );  y = y - h
        -- Inline slider on Enable Max Stacks toggle (same as inline swatch positioning)
        do
            local rgn = maxStacksRow._leftRegion
            local ctrl = rgn._control
            local SL = EllesmereUI.SL or {}
            local trackFrame, valBox, _, slThumb = EllesmereUI.BuildSliderCore(
                rgn, 90, 4, 14, 36, 26, 13, SL.INPUT_A or 0.6,
                1, 100, 1,
                function() local bd = SelectedTBB(); return bd and bd.stackThresholdMax or 10 end,
                function(v) local bd = SelectedTBB(); if bd then bd.stackThresholdMax = v; RefreshTBB() end end,
                true)
            PP.Point(valBox, "RIGHT", ctrl, "LEFT", -6, 0)
            PP.Point(trackFrame, "RIGHT", valBox, "LEFT", -8, 0)
            -- Disable block
            local block = CreateFrame("Frame", nil, trackFrame)
            block:SetPoint("TOPLEFT", trackFrame, "TOPLEFT", -4, 4)
            block:SetPoint("BOTTOMRIGHT", valBox, "BOTTOMRIGHT", 4, -4)
            block:SetFrameLevel(trackFrame:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(trackFrame, EllesmereUI.DisabledTooltip("Max Stacks"))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateMaxSliderState()
                local off = maxStacksOff()
                trackFrame:SetAlpha(off and 0.3 or 1)
                valBox:SetAlpha(off and 0.3 or 1)
                valBox:EnableMouse(not off)
                if slThumb then slThumb._sliderDisabled = off end
                if off then block:Show() else block:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateMaxSliderState)
            UpdateMaxSliderState()
        end
        -- Add "(Ex: 1,5,8)" suffix in smaller, dimmer text
        do
            local ticksLabel = maxStacksRow._rightRegion and maxStacksRow._rightRegion._label
            if ticksLabel then
                local suffix = maxStacksRow._rightRegion:CreateFontString(nil, "OVERLAY")
                suffix:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                suffix:SetTextColor(1, 1, 1, 0.35)
                suffix:SetPoint("LEFT", ticksLabel, "RIGHT", 5, 0)
                suffix:SetText(EllesmereUI.L("(Ex: 1,5,8)"))
            end
        end
        -- Inline input on Ticks at Stacks (matches slider value box style)
        do
            local rgn = maxStacksRow._rightRegion
            local SIDE_PAD = 20
            local FONT = EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
            local INPUT_W = 70
            local INPUT_H = 26

            local box = CreateFrame("EditBox", nil, rgn)
            PP.Size(box, INPUT_W, INPUT_H)
            PP.Point(box, "RIGHT", rgn, "RIGHT", -SIDE_PAD, 0)
            box:SetFrameLevel(rgn:GetFrameLevel() + 2)
            box:SetAutoFocus(false)
            box:SetJustifyH("CENTER")
            box:SetFont(FONT, 13, "")
            box:SetTextColor(
                EllesmereUI.TEXT_DIM_R or 0.75,
                EllesmereUI.TEXT_DIM_G or 0.75,
                EllesmereUI.TEXT_DIM_B or 0.75,
                EllesmereUI.TEXT_DIM_A or 1)
            -- Background matching slider input box
            local bg = box:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(
                EllesmereUI.SL_INPUT_R or 0.08,
                EllesmereUI.SL_INPUT_G or 0.08,
                EllesmereUI.SL_INPUT_B or 0.08,
                (EllesmereUI.SL_INPUT_A or 0.5) + (EllesmereUI.MW_INPUT_ALPHA_BOOST or 0.15))
            -- Border matching slider input box
            if PP.CreateBorder then
                PP.CreateBorder(box,
                    EllesmereUI.BORDER_R or 0.15,
                    EllesmereUI.BORDER_G or 0.15,
                    EllesmereUI.BORDER_B or 0.15,
                    EllesmereUI.SL_INPUT_BRD_A or 0.4, 1)
            end

            box:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                local bd = SelectedTBB(); if bd then
                    bd.stackThresholdTicks = self:GetText(); RefreshTBB()
                end
            end)
            box:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                local bd = SelectedTBB()
                self:SetText(bd and bd.stackThresholdTicks or "")
            end)

            -- Inline swatch for tick mark color (left of the input box)
            local tickSwatch, updateTickSwatch = EllesmereUI.BuildColorSwatch(
                rgn, box:GetFrameLevel() + 1,
                function()
                    local bd = SelectedTBB()
                    if not bd then return 1, 1, 1, 1 end
                    local a = bd.stackThresholdTickA
                    if a == nil then a = 1 end
                    return bd.stackThresholdTickR or 1, bd.stackThresholdTickG or 1,
                           bd.stackThresholdTickB or 1, a
                end,
                function(r, g, b, a)
                    local bd = SelectedTBB(); if not bd then return end
                    bd.stackThresholdTickR, bd.stackThresholdTickG = r, g
                    bd.stackThresholdTickB, bd.stackThresholdTickA = b, a; RefreshTBB()
                end,
                true, 20)
            PP.Point(tickSwatch, "RIGHT", box, "LEFT", -8, 0)
            local tickBlock = CreateFrame("Frame", nil, tickSwatch)
            tickBlock:SetAllPoints(); tickBlock:SetFrameLevel(tickSwatch:GetFrameLevel() + 10)
            tickBlock:EnableMouse(true)
            tickBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(tickSwatch, EllesmereUI.DisabledTooltip("Max Stacks"))
            end)
            tickBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function UpdateTicksInput()
                local bd = SelectedTBB()
                box:SetText(bd and bd.stackThresholdTicks or "")
                local off = maxStacksOff()
                box:SetAlpha(off and 0.3 or 1)
                box:EnableMouse(not off)
                if off then tickSwatch:SetAlpha(0.3); tickBlock:Show()
                else tickSwatch:SetAlpha(1); tickBlock:Hide() end
                if updateTickSwatch then updateTickSwatch() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateTicksInput)
            UpdateTicksInput()
        end

        -- Row 3: Enable Stack Threshold (toggle + inline swatch) | Stack Threshold (slider)
        local threshRow
        threshRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Stack Threshold",
              tooltip = "This will change the color of your bar if you have more than your chosen number of stacks",
              getValue = function() local bd = SelectedTBB(); return bd and bd.stackThresholdEnabled end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.stackThresholdEnabled = v; RefreshTBB(); EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Stack Threshold",
              min = 0, max = 100, step = 1,
              disabled = function()
                  local bd = SelectedTBB()
                  if not bd or not bd.stackThresholdEnabled then return true end
                  return bd.stackThresholdMulti and true or false
              end,
              disabledTooltip = function()
                  local bd = SelectedTBB()
                  if bd and bd.stackThresholdEnabled and bd.stackThresholdMulti then
                      return StackThreshReplacesTip()
                  end
                  return EllesmereUI.DisabledTooltip("Stack Threshold")
              end,
              rawTooltip = true,
              getValue = function() local bd = SelectedTBB(); return bd and bd.stackThreshold or 5 end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.stackThreshold = v; RefreshTBB()
              end }
        );  y = y - h
        -- Inline swatch on Enable Stack Threshold toggle
        do
            local rgn = threshRow._leftRegion
            local ctrl = rgn._control
            local threshSwatch, updateThreshSwatch = EllesmereUI.BuildColorSwatch(
                rgn, threshRow:GetFrameLevel() + 3,
                function()
                    local bd = SelectedTBB()
                    if not bd then return 0.8, 0.1, 0.1, 1 end
                    return bd.stackThresholdR or 0.8, bd.stackThresholdG or 0.1, bd.stackThresholdB or 0.1, bd.stackThresholdA or 1
                end,
                function(r, g, b, a)
                    local bd = SelectedTBB(); if not bd then return end
                    bd.stackThresholdR, bd.stackThresholdG, bd.stackThresholdB, bd.stackThresholdA = r, g, b, a; RefreshTBB()
                end,
                true, 20)
            PP.Point(threshSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local threshBlock = CreateFrame("Frame", nil, threshSwatch)
            threshBlock:SetAllPoints(); threshBlock:SetFrameLevel(threshSwatch:GetFrameLevel() + 10)
            threshBlock:EnableMouse(true)
            threshBlock:SetScript("OnEnter", function()
                local bd = SelectedTBB()
                if bd and bd.stackThresholdEnabled and bd.stackThresholdMulti then
                    EllesmereUI.ShowWidgetTooltip(threshSwatch, StackThreshReplacesTip())
                    return
                end
                EllesmereUI.ShowWidgetTooltip(threshSwatch, EllesmereUI.DisabledTooltip("Stack Threshold"))
            end)
            threshBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Cog: opens the multi-threshold editor. Stays usable while multi is
            -- on, since it is the only way back out of it.
            EllesmereUI.BuildInlineCog(rgn, {
                anchorTo = threshSwatch,
                show = function(self)
                    ShowStackThreshEditor({
                        getCfg    = SelectedTBB,
                        refreshFn = RefreshTBB,
                        anchor    = self,
                    })
                end,
                tip = StackThreshHelpTip(),
                disabled = function() local bd = SelectedTBB(); return not (bd and bd.stackThresholdEnabled) end,
                disabledTooltip = "Stack Threshold",
            })

            local function UpdateThreshSwatchState()
                local bd = SelectedTBB()
                local enabled = bd and bd.stackThresholdEnabled
                -- The swatch edits the single threshold color, so multi masks it
                -- the same way it masks the slider.
                local off = not enabled or (bd.stackThresholdMulti and true or false)
                if off then threshSwatch:SetAlpha(0.3); threshBlock:Show()
                else threshSwatch:SetAlpha(1); threshBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateThreshSwatch(); UpdateThreshSwatchState() end)
            UpdateThreshSwatchState()
        end

        -- Preview click-navigation map: preview element -> section + row.
        -- Resolved at click time by NavigateToSetting.
        parent._tbbClickTargets = {
            barFill    = { section = displayHeader, target = fillRow,   slotSide = "left" },
            icon       = { section = displayHeader, target = iconRow,   slotSide = "left" },
            nameText   = { section = layoutHeader,  target = nameRow,   slotSide = "left" },
            timerText  = { section = layoutHeader,  target = nameRow,   slotSide = "right" },
            stacksText = { section = layoutHeader,  target = stacksRow, slotSide = "left" },
        }

        -- Ensure bar frames exist before showing placeholders
        ns.BuildTrackedBuffBars()
        UpdateTBBPlaceholder()
        RefreshTBBPopout()
        return math.abs(y)
    end

    return BuildBuffBarsPage, RefreshTBBPopout
end

-- Used by EUI_CooldownManager_Options.lua
ns.CDMO_InitBuffBarsPage = InitBuffBarsPage
