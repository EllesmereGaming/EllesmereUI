if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\BarsPage_Options.lua
--  Cooldown Manager options: the CDM Bars page (BuildCDMBarsPage). Definitions
--  only; the shared helpers come from ns._CDMO_OptEnv (filled by
--  EUI_CooldownManager_Options.lua), the preview from LivePreview_Options.lua.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
if not ns then return end  -- module disabled: no options page

local function BuildCDMBarsPage(pageName, parent, yOffset)
    local env = ns._CDMO_OptEnv
    local AnyIconAlwaysShowOn, BuildKeybindStyleControls, DB, durationPositionOrder = env.AnyIconAlwaysShowOn, env.BuildKeybindStyleControls, env.DB, env.durationPositionOrder
    local durationPositionValues, FONT_PATH, GetCDMOptOutline, optState = env.durationPositionValues, env.FONT_PATH, env.GetCDMOptOutline, env.optState
    local PP, Refresh, SelectedCDMBar, UpdateCDMPreview = env.PP, env.Refresh, env.SelectedCDMBar, env.UpdateCDMPreview
    local UpdateCDMPreviewAndResize = env.UpdateCDMPreviewAndResize
    local BuildCDMLivePreview = ns.CDMO_BuildCDMLivePreview
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    local p = DB()
    if not p or not p.cdmBars then return math.abs(yOffset) end

    local bars = p.cdmBars.bars
    if not bars or #bars == 0 then return math.abs(yOffset) end


    -- Clamp selection
    if optState.selectedCDMBarIndex < 1 then optState.selectedCDMBarIndex = 1 end
    if optState.selectedCDMBarIndex > #bars then optState.selectedCDMBarIndex = #bars end

    local barData = bars[optState.selectedCDMBarIndex]
    if not barData then return math.abs(yOffset) end

    -- Tag every option registered by this build with the selected bar, so a global-search
    -- jump to a bar-specific setting (e.g. HoverCast/FocusKick-only rows) restores this exact
    -- bar first via EllesmereUI._setCDMBar -- otherwise the matched row wouldn't exist under whatever bar is selected when the player jumps there.
    EllesmereUI._buildingSelector = { setter = EllesmereUI._setCDMBar, key = barData.key }

    -- Capture the key so closures always look up the CURRENT bar data from the profile (no
    -- stale references across reorders/rebuilds). Searchable single-select "Sync From"
    -- source-spec dropdown; defaults to the current spec. Reuses one frame on ns so repeated opens don't leak.
    local function ShowRPTSourcePicker(defaultKey, onSelect)
        -- All-classes source list (current class always + other classes that have data), so the source isn't limited to the player's class.
        local info = ns.GetAllCDMSpecInfo and ns.GetAllCDMSpecInfo()
            or (ns.GetCDMSpecInfo and ns.GetCDMSpecInfo()) or {}
        local DDW = 280
        local ROW_H = 30
        local MAX_VISIBLE = 10               -- rows shown before the list scrolls
        local MAX_LIST_H = MAX_VISIBLE * ROW_H
        local P = ns._rptSrcPopup
        if not P then
            P = { rows = {} }
            ns._rptSrcPopup = P
            local scale = (EllesmereUI.GetPopupScale()) or 1
            local dimmer = CreateFrame("Frame", nil, UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:Hide()
            local dt = dimmer:CreateTexture(nil, "BACKGROUND"); dt:SetAllPoints(); dt:SetColorTexture(0, 0, 0, 0.25)
            local popup = CreateFrame("Frame", nil, dimmer)
            popup:SetScale(scale)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            PP.Size(popup, DDW + 24, 320)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:EnableMouse(true)
            local bg = popup:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.08, 0.10, 1)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, PP)
            local titleFs = EllesmereUI.MakeFont(popup, 15, nil, 1, 1, 1, 1)
            titleFs:SetPoint("TOP", popup, "TOP", 0, -14); titleFs:SetText("Sync From")
            local subFs = EllesmereUI.MakeFont(popup, 11, nil, 1, 1, 1, 0.45)
            subFs:SetPoint("TOP", titleFs, "BOTTOM", 0, -4)
            subFs:SetWidth(DDW); subFs:SetJustifyH("CENTER")
            subFs:SetText("Choose the spec to copy trinkets, pots, racials & buff presets from")
            local search = CreateFrame("EditBox", nil, popup)
            PP.Size(search, DDW, 26)
            search:SetPoint("TOP", subFs, "BOTTOM", 0, -10)
            search:SetFont(FONT_PATH, 12, "")
            search:SetTextColor(1, 1, 1, 0.9); search:SetJustifyH("LEFT")
            search:SetAutoFocus(false); search:SetMaxLetters(30); search:SetTextInsets(6, 6, 0, 0)
            local sbg = search:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints(); sbg:SetColorTexture(0, 0, 0, 0.4)
            EllesmereUI.MakeBorder(search, 1, 1, 1, 0.10, PP)
            local ph = search:CreateFontString(nil, "OVERLAY"); ph:SetFont(FONT_PATH, 11, "")
            ph:SetTextColor(0.5, 0.5, 0.5, 0.6); ph:SetPoint("LEFT", search, "LEFT", 6, 0); ph:SetText("Search...")
            search:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            -- Scrollable, capped list: a long cross-class spec list scrolls
            -- (mousewheel) inside a fixed max height instead of running off the
            -- screen. A thin thumb on the right shows when there is more to see.
            local scrollF = CreateFrame("ScrollFrame", nil, popup)
            scrollF:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
            scrollF:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
            scrollF:EnableMouseWheel(true)
            local listF = CreateFrame("Frame", nil, scrollF)
            listF:SetWidth(DDW)
            scrollF:SetScrollChild(listF)
            local track = scrollF:CreateTexture(nil, "ARTWORK")
            track:SetWidth(3); track:SetColorTexture(1, 1, 1, 0.06)
            track:SetPoint("TOPRIGHT", scrollF, "TOPRIGHT", -1, 0)
            track:SetPoint("BOTTOMRIGHT", scrollF, "BOTTOMRIGHT", -1, 0)
            track:Hide()
            local thumb = scrollF:CreateTexture(nil, "OVERLAY")
            thumb:SetWidth(3); thumb:SetColorTexture(1, 1, 1, 0.25); thumb:Hide()
            local function UpdateThumb()
                local visH, fullH = scrollF:GetHeight(), listF:GetHeight()
                local maxScroll = math.max(0, fullH - visH)
                if maxScroll <= 0 then track:Hide(); thumb:Hide(); return end
                track:Show(); thumb:Show()
                local thumbH = math.max(20, visH * visH / fullH)
                thumb:SetHeight(thumbH)
                local frac = (scrollF:GetVerticalScroll() or 0) / maxScroll
                thumb:ClearAllPoints()
                thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -frac * (visH - thumbH))
            end
            scrollF:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = math.max(0, listF:GetHeight() - self:GetHeight())
                if maxScroll <= 0 then return end
                local new = math.max(0, math.min(maxScroll, (self:GetVerticalScroll() or 0) - delta * ROW_H * 2))
                self:SetVerticalScroll(new); UpdateThumb()
            end)
            dimmer:SetScript("OnMouseDown", function() dimmer:Hide() end)
            popup:SetScript("OnMouseDown", function() end)
            P.dimmer, P.popup, P.search, P.ph, P.list, P.DDW = dimmer, popup, search, ph, listF, DDW
            P.scroll, P.updateThumb = scrollF, UpdateThumb
        end

        local function Rebuild()
            local filter = (P.search:GetText() or ""):lower()
            local shown = 0
            for _, r in ipairs(P.rows) do r:Hide() end
            for _, s in ipairs(info) do
                local nm = s.name or ""
                if filter == "" or nm:lower():find(filter, 1, true) then
                    shown = shown + 1
                    local r = P.rows[shown]
                    if not r then
                        r = CreateFrame("Button", nil, P.list)
                        PP.Size(r, P.DDW, ROW_H)
                        r:SetFrameLevel(P.list:GetFrameLevel() + 1)
                        local hl = r:CreateTexture(nil, "ARTWORK"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06); hl:Hide(); r._hl = hl
                        local ic = r:CreateTexture(nil, "ARTWORK"); ic:SetSize(20, 20); ic:SetPoint("LEFT", r, "LEFT", 8, 0); r._ic = ic
                        local tx = EllesmereUI.MakeFont(r, 13, nil, 1, 1, 1, 0.85); tx:SetPoint("LEFT", ic, "RIGHT", 8, 0); r._tx = tx
                        r:SetScript("OnEnter", function(self) self._hl:Show() end)
                        r:SetScript("OnLeave", function(self) if not self._isDefault then self._hl:Hide() end end)
                        P.rows[shown] = r
                    end
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", P.list, "TOPLEFT", 0, -((shown - 1) * ROW_H))
                    if s.icon then r._ic:SetTexture(s.icon); r._ic:Show() else r._ic:Hide() end
                    r._tx:SetText(nm)
                    r._isDefault = (s.key == defaultKey)
                    r._hl:SetShown(r._isDefault)
                    local key = s.key
                    r:SetScript("OnClick", function()
                        P.dimmer:Hide()
                        if onSelect then onSelect(key) end
                    end)
                    r:Show()
                end
            end
            local listH = math.max(ROW_H, shown * ROW_H)
            P.list:SetHeight(listH)
            local visH = math.min(listH, MAX_LIST_H)
            P.scroll:SetHeight(visH)
            P.popup:SetHeight(110 + visH)
            P.scroll:SetVerticalScroll(0)
            if P.updateThumb then P.updateThumb() end
        end
        P.search:SetScript("OnTextChanged", function(self)
            P.ph:SetShown((self:GetText() or "") == "")
            Rebuild()
        end)
        P.search:SetText("")
        P.ph:Show()
        Rebuild()
        P.dimmer:Show()
        C_Timer.After(0.05, function() P.search:SetFocus() end)
    end

    -- Sync Generic CDs/Buffs across specs (per profile): trinkets, pots, racials
    -- and buff-bar presets (Bloodlust, etc.). First-time setup picks a SOURCE spec
    -- (searchable dropdown, default current spec), then a spec picker with the
    -- source locked ON (auto-checked, can't be deselected).
    local function DoRPTSyncSetup()
        local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
        ShowRPTSourcePicker(curKey, function(sourceKey)
            local srcName = sourceKey
            local srcID = tonumber(sourceKey)
            if srcID then
                -- WoW Forever has no by-ID spec global; its spec-ID name
                -- lookups name the source there instead of the raw key.
                local n
                if GetSpecializationInfoByID then
                    n = select(2, GetSpecializationInfoByID(srcID))
                elseif GetSpecializationNameForSpecID then
                    n = GetSpecializationNameForSpecID(srcID)
                elseif GetSpecializationInfoForSpecID then
                    n = select(2, GetSpecializationInfoForSpecID(srcID))
                end
                if n and n ~= "" then srcName = n end
            end
            -- WoW Forever: a key names a whole class there.
            if EllesmereUI.IS_FOREVER then
                local t = EllesmereUI.SpecClassOf(tonumber(sourceKey))
                if t then srcName = EllesmereUI.ForeverClassName(t) end
            end
            local specs = ns.GetCDMSpecInfo and ns.GetCDMSpecInfo() or {}
            for _, s in ipairs(specs) do
                s.checked = (s.key == sourceKey)
            end
            EllesmereUI:ShowCDMSpecPickerPopup({
                title       = "Sync Generic CDs/Buffs",
                -- The grid lists every class (a profile is shared across
                -- characters), so an alt's specs are ticked from here; say
                -- so, or it reads as "this character's specs" only. Keep the
                -- subtitle to one line so it clears Check All / Uncheck All.
                subtitle    = EllesmereUI.Lf("Choose which specs sync with %1$s, including your alts' specs (the source is always included)", srcName),
                confirmText = "Sync",
                specs       = specs,
                lockedSpecs = { [sourceKey] = "This is the spec you're syncing from -- it's always included." },
                foreverActiveKey = curKey,
                onConfirm   = function(selectedSpecs)
                    selectedSpecs[sourceKey] = true
                    local cnt = 0
                    for _, v in pairs(selectedSpecs) do if v then cnt = cnt + 1 end end
                    if cnt <= 1 then
                        -- Only the source picked -> nothing to sync; clear any
                        -- existing sync and SAY so (one ticked spec is the
                        -- natural first guess at "sync FROM this spec").
                        if ns.ClearRPTSync then ns.ClearRPTSync() end
                        EllesmereUI.Print("|cff0cd29fEllesmereUI CDM:|r " .. EllesmereUI.L("Sync cleared -- only one spec was selected. Tick at least two specs (including other characters' specs) to sync between them."))
                        EllesmereUI:RefreshPage(true)
                        return
                    end
                    if ns.SetupRPTSync then ns.SetupRPTSync(selectedSpecs, sourceKey) end
                    if ns.FullCDMRebuild then ns.FullCDMRebuild("profile_import") end
                    -- Which bar each entry sits on is synced; its SLOT is not
                    -- (every spec keeps its own ordering) -- easily read as a
                    -- bug, so the print states it explicitly.
                    EllesmereUI.Print("|cff0cd29fEllesmereUI CDM:|r " .. EllesmereUI.Lf("Syncing generic CDs/buffs across %d specs. Icon order is not synced -- each spec keeps its own arrangement.", cnt))
                    EllesmereUI:RefreshPage(true)
                end,
            })
        end)
    end

    -- Edit an existing sync: open the spec picker directly (no source step),
    -- with the currently-synced specs pre-checked. Unchecking a spec drops it
    -- from the sync (its trinkets/pots/racials/buff presets are left as-is);
    -- checking a new spec folds it in. Falling to one-or-zero specs clears it.
    local function EditRPTSync()
        -- Pre-check EVERY synced spec, not just the current class's: a sync
        -- can span other classes (one profile across characters), and the
        -- grid shows all classes -- seed from the STORED sync set, not from
        -- GetCDMSpecInfo (which only returns the current class's specs).
        local existing = ns.GetRPTSyncSpecs and ns.GetRPTSyncSpecs()
        local specs = {}
        if existing then
            for key in pairs(existing) do
                specs[#specs + 1] = { key = key, checked = true }
            end
        end
        EllesmereUI:ShowCDMSpecPickerPopup({
            title       = "Sync Generic CDs/Buffs",
            subtitle    = "Uncheck a spec to remove it from the sync. Removed specs keep their current trinkets, pots, racials & buff presets.",
            confirmText = "Save",
            specs       = specs,
            foreverActiveKey = EllesmereUI.IS_FOREVER and ns.GetActiveSpecKey and ns.GetActiveSpecKey() or nil,
            onConfirm   = function(selectedSpecs)
                local cnt = 0
                for _, v in pairs(selectedSpecs) do if v then cnt = cnt + 1 end end
                if cnt <= 1 then
                    -- One or zero specs left -> nothing to sync; clear it.
                    -- Announced for the same reason as the setup path: the
                    -- sync is discarded here, not merely left unchanged.
                    if ns.ClearRPTSync then ns.ClearRPTSync() end
                    EllesmereUI.Print("|cff0cd29fEllesmereUI CDM:|r " .. EllesmereUI.L("Sync cleared -- fewer than two specs remained selected."))
                    EllesmereUI:RefreshPage(true)
                    return
                end
                if ns.UpdateRPTSyncSpecs then ns.UpdateRPTSyncSpecs(selectedSpecs) end
                if ns.FullCDMRebuild then ns.FullCDMRebuild("profile_import") end
                EllesmereUI:RefreshPage(true)
            end,
        })
    end

    -- Route the third action button: edit the live sync, or set up a new one.
    local function DoRPTSync()
        if ns.HasRPTSync and ns.HasRPTSync() then
            EditRPTSync()
        else
            DoRPTSyncSetup()
        end
    end

    -- Action buttons: repopulate + open Blizzard CDM + sync generic CDs/buffs
    -- (trinkets, pots, racials & buff presets across specs).
    -- The third button keeps the same label whether or not a sync exists;
    -- DoRPTSync routes to setup vs edit based on ns.HasRPTSync().
    _, h = W:WideTripleButton(parent,
        "Repopulate from Blizzard CDM", "Open Blizzard CDM", "Sync Generic CDs/Buffs", y,
        function()
            EllesmereUI:ShowConfirmPopup({
                title = "Repopulate Bars",
                message = "This will reset all default bar spell assignments for the current spec to match Blizzard's CDM layout. Spells you added yourself (presets, custom IDs and racials) are kept. Continue?",
                confirmText = "Repopulate",
                cancelText = "Cancel",
                onConfirm = function()
                    if ns.RepopulateFromBlizzard then
                        ns.RepopulateFromBlizzard()
                    end
                    C_Timer.After(0.15, function()
                        if optState._cdmPreview and optState._cdmPreview.Update then
                            optState._cdmPreview:Update()
                        end
                        UpdateCDMPreviewAndResize()
                    end)
                end,
            })
        end,
        function()
            local bd = SelectedCDMBar()
            local barType = bd and (bd.barType or bd.key) or "cooldowns"
            local isBuff = (barType == "buffs")
            if ns.OpenBlizzardCDMTab then
                ns.OpenBlizzardCDMTab(isBuff)
            end
        end,
        DoRPTSync, 225);  y = y - h

    local barKey = barData.key
    local function BD()
        local pp = DB()
        if not pp or not pp.cdmBars or not pp.cdmBars.bars then return barData end
        for _, b in ipairs(pp.cdmBars.bars) do
            if b.key == barKey then return b end
        end
        return barData
    end

    local isDefault = (barData.key == "cooldowns" or barData.key == "utility" or barData.key == "buffs")
    local isBuffBar = ns.IsBarBuffFamily(barData)
    -- FocusKick is the special nameplate-anchored bar. Most options panel
    -- sections are hidden for it; only Icon Display + a custom Nameplate
    -- Anchor row are shown.
    local isFocusKick = (barData.key == "focuskick")

    -------------------------------------------------------------------
    --  CONTENT HEADER  (dropdown + live preview)
    -------------------------------------------------------------------
    EllesmereUI:ClearContentHeader()
    optState._cdmPreview = nil

    optState._cdmHeaderBuilder = function(hdr, hdrW)
        local PAD = EllesmereUI.CONTENT_PAD or 10
        local PV_PAD = 10
        local fy = -20

        -- Bar selector dropdown (custom-built to support delete buttons)
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

        -- Dropdown button
        local ddBtn = CreateFrame("Button", nil, hdr)
        PP.Size(ddBtn, ddW, DD_H)
        ddBtn:SetFrameLevel(hdr:GetFrameLevel() + 5)
        local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints(); ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, mBrdA, EllesmereUI.PanelPP)
        local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
        ddLbl:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        ddLbl:SetAlpha(mTxtA)
        ddLbl:SetJustifyH("LEFT")
        ddLbl:SetWordWrap(false); ddLbl:SetMaxLines(1)
        ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
        -- Arrow (standard EllesmereUI dropdown arrow)
        local arrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, EllesmereUI.PanelPP)
        ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

        local function UpdateDDLabel()
            local bd = bars[optState.selectedCDMBarIndex]
            local label = bd and EllesmereUI.L(bd.name or bd.key) or ""
            ddLbl:SetText(label)
        end
        UpdateDDLabel()

        -- Custom-bar display order for THIS dropdown only: a pure VIEW over
        -- p.cdmBars.bars. The bars array is NEVER reordered -- stored
        -- numeric bar paths (unlock/override data) and selectedCDMBarIndex
        -- depend on array positions. Saved key list first (keys whose bar
        -- no longer exists are dropped), then any custom bars not yet
        -- listed, in array order (new bars append). Same self-healing
        -- contract as the RF party Class Order list. Built-ins (cooldowns/
        -- utility/buffs/focuskick) are never part of the order list.
        local function CustomBarDisplayOrder()
            local order, seen, byKey = {}, {}, {}
            for _, b in ipairs(bars) do
                if b.key and not b.isGhostBar and b.key ~= "cooldowns"
                   and b.key ~= "utility" and b.key ~= "buffs" and b.key ~= "focuskick" then
                    byKey[b.key] = b
                end
            end
            local saved = p.cdmBars.customBarMenuOrder
            if type(saved) == "table" then
                for _, k in ipairs(saved) do
                    if byKey[k] and not seen[k] then order[#order + 1] = k; seen[k] = true end
                end
            end
            for _, b in ipairs(bars) do
                local k = b.key
                if k and byKey[k] and not seen[k] then order[#order + 1] = k; seen[k] = true end
            end
            return order, byKey
        end

        -- Custom dropdown menu
        local ddMenu
        local function BuildDDMenu()
            if ddMenu then ddMenu:Hide(); ddMenu = nil end
            local menu = CreateFrame("Frame", nil, UIParent)
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(300)
            menu:SetClampedToScreen(true)
            menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
            menu:SetPoint("TOPRIGHT", ddBtn, "BOTTOMRIGHT", 0, -2)
            local bg = menu:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
            EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

            local mH = 4
            local customCount = 0
            for _, b in ipairs(bars) do
                if b.key ~= "cooldowns" and b.key ~= "utility" and b.key ~= "buffs" and not b.isGhostBar then
                    customCount = customCount + 1
                end
            end

            -- Display list: array order, except CUSTOM bars render in the saved
            -- dropdown order (CustomBarDisplayOrder). All customs emit as one block
            -- at the first custom bar's array position, so an empty/absent saved
            -- order reproduces the old listing byte-identically. Every entry
            -- carries its REAL array index (realIdx) -- selection and all other
            -- consumers keep using array positions; only this listing is reordered.
            local ordKeys, ordByKey = CustomBarDisplayOrder()
            local reorderable = #ordKeys >= 2
            local displayList, realIdx = {}, {}
            do
                local customsEmitted = false
                for bIdx, b in ipairs(bars) do
                    realIdx[b] = bIdx
                    if not b.isGhostBar then
                        if ordByKey[b.key] then
                            if not customsEmitted then
                                customsEmitted = true
                                for _, k in ipairs(ordKeys) do
                                    displayList[#displayList + 1] = ordByKey[k]
                                end
                            end
                        else
                            displayList[#displayList + 1] = b
                        end
                    end
                end
            end

            -- In-menu drag-to-reorder for the custom-bar band: each custom
            -- row gets a grip ("=") that drags the row; a green insertion
            -- line previews the drop slot; releasing writes ONLY the display
            -- key list (p.cdmBars.customBarMenuOrder) and re-renders the
            -- menu in place. Same drag mechanics as the shared reorder
            -- widget (RF Class Order). Row clicks / delete / rename are
            -- untouched -- only the grip starts a drag.
            local dragState = {}
            local customRows = {}
            local hintShown = false
            local insLine
            if reorderable then
                insLine = menu:CreateTexture(nil, "OVERLAY", nil, 7)
                insLine:SetHeight(2)
                local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
                insLine:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
                insLine:Hide()
            end

            for _, b in ipairs(displayList) do
                local idx = realIdx[b]
                if b.isGhostBar then
                    -- skip ghost bar in dropdown
                else
                -- FocusKick is treated as a built-in: cannot be deleted
                -- or renamed even though its barType is "cooldowns".
                local isFocusKick = (b.key == "focuskick")
                local isCustom = (b.key ~= "cooldowns" and b.key ~= "utility" and b.key ~= "buffs" and not isFocusKick)

                -- Hint above the custom-bar band (only when reorderable).
                if reorderable and not hintShown and ordByKey[b.key] then
                    hintShown = true
                    local ht = menu:CreateFontString(nil, "OVERLAY")
                    ht:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    ht:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -mH - 4)
                    ht:SetTextColor(1, 1, 1, 0.25)
                    ht:SetText(EllesmereUI.L("Drag to Reorder Bars"))
                    mH = mH + 18
                end

                local item = CreateFrame("Button", nil, menu)
                item:SetHeight(ITEM_H)
                item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
                item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                item:SetFrameLevel(menu:GetFrameLevel() + 2)
                if reorderable and ordByKey[b.key] then
                    customRows[#customRows + 1] = { item = item, key = b.key, topY = -mH }
                end

                local iLbl = item:CreateFontString(nil, "OVERLAY")
                iLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                iLbl:SetJustifyH("LEFT")
                iLbl:SetWordWrap(false); iLbl:SetMaxLines(1)
                iLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                local displayName = EllesmereUI.L(b.name or b.key)
                iLbl:SetText(displayName)

                local iHl = item:CreateTexture(nil, "ARTWORK")
                iHl:SetAllPoints(); iHl:SetColorTexture(1, 1, 1, 1)
                iHl:SetAlpha(idx == optState.selectedCDMBarIndex and selA or 0)

                -- Delete + Rename buttons for custom bars
                local delBtn, editBtn
                if isCustom then
                    delBtn = CreateFrame("Button", nil, item)
                    delBtn:SetSize(ICON_SZ, ICON_SZ)
                    delBtn:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                    delBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                    local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                    delIcon:SetSize(ICON_SZ, ICON_SZ)
                    delIcon:SetPoint("CENTER", delBtn, "CENTER", 0, 0)
                    if delIcon.SetSnapToPixelGrid then delIcon:SetSnapToPixelGrid(false); delIcon:SetTexelSnappingBias(0) end
                    delIcon:SetTexture(MEDIA .. "icons\\eui-close.png")
                    delBtn:SetAlpha(0.75)

                    editBtn = CreateFrame("Button", nil, item)
                    editBtn:SetSize(ICON_SZ, ICON_SZ)
                    editBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
                    editBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                    local edIcon = editBtn:CreateTexture(nil, "OVERLAY")
                    edIcon:SetSize(ICON_SZ, ICON_SZ)
                    edIcon:SetPoint("CENTER", editBtn, "CENTER", 0, 0)
                    if edIcon.SetSnapToPixelGrid then edIcon:SetSnapToPixelGrid(false); edIcon:SetTexelSnappingBias(0) end
                    edIcon:SetTexture(MEDIA .. "icons\\eui-edit.png")
                    editBtn:SetAlpha(0.75)

                    iLbl:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)

                    -- Drag grip: the ONLY drag affordance (row click still
                    -- selects, delete/rename untouched). Same grip glyph +
                    -- 3px threshold + insertion-line mechanics as the
                    -- shared reorder widget. Drop writes the display key
                    -- list and re-renders this menu in place.
                    if reorderable and ordByKey[b.key] then
                        iLbl:SetPoint("LEFT", item, "LEFT", 24, 0)
                        local gripBtn = CreateFrame("Button", nil, item)
                        gripBtn:SetSize(16, ITEM_H)
                        gripBtn:SetPoint("LEFT", item, "LEFT", 4, 0)
                        gripBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                        local grip = gripBtn:CreateFontString(nil, "OVERLAY")
                        grip:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                        grip:SetPoint("CENTER", gripBtn, "CENTER", 0, 0)
                        grip:SetText("=")
                        grip:SetTextColor(1, 1, 1, 0.2)
                        gripBtn:SetScript("OnEnter", function()
                            grip:SetTextColor(1, 1, 1, 0.6)
                        end)
                        gripBtn:SetScript("OnLeave", function()
                            if not (dragState.row == item and dragState.active) then
                                grip:SetTextColor(1, 1, 1, 0.2)
                            end
                        end)
                        gripBtn:SetScript("OnMouseDown", function(_, mb)
                            if mb ~= "LeftButton" then return end
                            local _, cy = GetCursorPosition()
                            dragState.row = item
                            dragState.startY = cy
                            dragState.active = false
                            dragState.slot = nil
                        end)
                        gripBtn:SetScript("OnUpdate", function()
                            if dragState.row ~= item or not dragState.startY then return end
                            local _, cy = GetCursorPosition()
                            if not dragState.active then
                                if math.abs(cy - dragState.startY) < 3 then return end
                                dragState.active = true
                                item:SetFrameLevel(menu:GetFrameLevel() + 10)
                                item:SetAlpha(0.8)
                                grip:SetTextColor(1, 1, 1, 0.6)
                            end
                            local sc = menu:GetEffectiveScale()
                            local cY = cy / sc
                            local mT = menu:GetTop() or 0
                            -- Insertion slot among the custom rows (skip self).
                            local iI = #customRows
                            for ri, r2 in ipairs(customRows) do
                                if r2.item ~= item then
                                    local rm = mT + r2.topY - ITEM_H / 2
                                    if cY > rm then iI = ri; break end
                                    iI = ri + 1
                                end
                            end
                            iI = math.max(1, math.min(iI, #customRows + 1))
                            dragState.slot = iI
                            local bandTop = customRows[1] and customRows[1].topY or 0
                            local lnY = (iI <= 1) and (bandTop + 1) or (bandTop - (iI - 1) * ITEM_H + 1)
                            insLine:ClearAllPoints()
                            insLine:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, lnY)
                            insLine:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -8, lnY)
                            insLine:Show()
                            item:ClearAllPoints()
                            item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, cY - mT)
                            item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, cY - mT)
                        end)
                        gripBtn:SetScript("OnMouseUp", function(_, mb)
                            if mb ~= "LeftButton" or dragState.row ~= item then return end
                            local wasActive = dragState.active
                            local slot = dragState.slot
                            dragState.row = nil
                            dragState.startY = nil
                            dragState.active = false
                            dragState.slot = nil
                            if insLine then insLine:Hide() end
                            if not wasActive then return end
                            local from
                            local keys = {}
                            for ri, r2 in ipairs(customRows) do
                                keys[ri] = r2.key
                                if r2.item == item then from = ri end
                            end
                            local to = slot or from
                            if from and to then
                                if from < to then to = to - 1 end
                                to = math.max(1, math.min(to, #keys))
                                if from ~= to then
                                    local mv = table.remove(keys, from)
                                    table.insert(keys, to, mv)
                                    local pp = DB()
                                    if pp and pp.cdmBars then
                                        pp.cdmBars.customBarMenuOrder = keys
                                    end
                                end
                            end
                            -- Re-render in the new order (also re-anchors the
                            -- dragged row); the rebuilt menu stays open.
                            BuildDDMenu()
                        end)
                    end

                    local function InlineBtnEnter(self)
                        self:SetAlpha(1)
                        iLbl:SetTextColor(1, 1, 1, 1)
                        iHl:SetAlpha(hlA)
                        delBtn:SetAlpha(0.85); editBtn:SetAlpha(0.85)
                    end
                    local function InlineBtnLeave(self)
                        if item:IsMouseOver() or delBtn:IsMouseOver() or editBtn:IsMouseOver() then
                            self:SetAlpha(0.85); return
                        end
                        delBtn:SetAlpha(0.75); editBtn:SetAlpha(0.75)
                        iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        iHl:SetAlpha(idx == optState.selectedCDMBarIndex and selA or 0)
                    end

                    delBtn:SetScript("OnEnter", function(self)
                        InlineBtnEnter(self)
                        EllesmereUI.ShowWidgetTooltip(self, "Delete")
                    end)
                    delBtn:SetScript("OnLeave", function(self)
                        InlineBtnLeave(self)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    editBtn:SetScript("OnEnter", function(self)
                        InlineBtnEnter(self)
                        EllesmereUI.ShowWidgetTooltip(self, "Rename")
                    end)
                    editBtn:SetScript("OnLeave", function(self)
                        InlineBtnLeave(self)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    delBtn:SetScript("OnClick", function()
                        menu:Hide()
                        local delName = b.name or b.key
                        local delKey = b.key
                        EllesmereUI:ShowConfirmPopup({
                            title = "Delete Bar",
                            message = EllesmereUI.Lf("Are you sure you want to delete \"%1$s\"?", delName),
                            confirmText = "Delete",
                            cancelText = "Cancel",
                            onConfirm = function()
                                ns.RemoveCDMBar(delKey)
                                -- Select the cooldowns bar after deletion
                                optState.selectedCDMBarIndex = 1
                                for bi, bb in ipairs(bars) do
                                    if bb.key == "cooldowns" then optState.selectedCDMBarIndex = bi; break end
                                end
                                Refresh()
                                EllesmereUI:InvalidateContentHeaderCache()
                                EllesmereUI:SetContentHeader(optState._cdmHeaderBuilder)
                                EllesmereUI:RefreshPage(true)
                            end,
                        })
                    end)
                    editBtn:SetScript("OnClick", function()
                        menu:Hide()
                        local oldName = b.name or b.key
                        EllesmereUI:ShowInputPopup({
                            title = "Rename Bar",
                            message = EllesmereUI.Lf("Enter a new name for \"%1$s\":", oldName),
                            placeholder = oldName,
                            confirmText = "Rename",
                            cancelText = "Cancel",
                            onConfirm = function(newName)
                                newName = newName and strtrim(newName) or ""
                                if newName == "" or newName == oldName then return end
                                b.name = newName
                                EllesmereUI:InvalidateContentHeaderCache()
                                EllesmereUI:SetContentHeader(optState._cdmHeaderBuilder)
                                EllesmereUI:RefreshPage(true)
                                if ns.RegisterCDMUnlockElements then
                                    ns.RegisterCDMUnlockElements()
                                end
                            end,
                        })
                    end)
                end

                item:SetScript("OnEnter", function()
                    iLbl:SetTextColor(1, 1, 1, 1)
                    iHl:SetAlpha(hlA)
                    if delBtn then delBtn:SetAlpha(1) end
                    if editBtn then editBtn:SetAlpha(1) end
                end)
                item:SetScript("OnLeave", function()
                    if delBtn and delBtn:IsMouseOver() then return end
                    if editBtn and editBtn:IsMouseOver() then return end
                    iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    iHl:SetAlpha(idx == optState.selectedCDMBarIndex and selA or 0)
                    if delBtn then delBtn:SetAlpha(0.75) end
                    if editBtn then editBtn:SetAlpha(0.75) end
                end)
                item:SetScript("OnClick", function()
                    menu:Hide()
                    optState.selectedCDMBarIndex = idx
                    EllesmereUI:InvalidateContentHeaderCache()
                    EllesmereUI:SetContentHeader(optState._cdmHeaderBuilder)
                    EllesmereUI:RefreshPage(true)
                end)

                mH = mH + ITEM_H
            end -- else (not ghost bar)
            end -- for displayList

            -- Divider before add-bar options
            local div = menu:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH - 4)
            div:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9

            -- "Add New ..." items (disabled if at cap)
            local atCap = customCount >= (ns.MAX_CUSTOM_BARS or 6)
            -- Custom Aura ("custom_buff") bars were merged into Buff bars: a
            -- Buff bar now hosts Blizzard-tracked buffs AND injected preset/
            -- custom buffs, so there's no separate Aura bar type to create.
            local addBarTypes = {
                { type = "cooldowns",   label = EllesmereUI.L("+ Add New Cooldowns Bar") },
                { type = "utility",     label = EllesmereUI.L("+ Add New Utility Bar") },
                { type = "buffs",       label = EllesmereUI.L("+ Add New Buff Bar") },
            }
            for _, entry in ipairs(addBarTypes) do
                local addItem = CreateFrame("Button", nil, menu)
                addItem:SetHeight(ITEM_H)
                addItem:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
                addItem:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                addItem:SetFrameLevel(menu:GetFrameLevel() + 2)
                local addLbl = addItem:CreateFontString(nil, "OVERLAY")
                addLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                addLbl:SetPoint("LEFT", addItem, "LEFT", 10, 0)
                addLbl:SetJustifyH("LEFT")
                if atCap then
                    addLbl:SetText(EllesmereUI.Lf("%1$s (max %2$s)", entry.label, ns.MAX_CUSTOM_BARS or 6))
                    addLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                else
                    addLbl:SetText(entry.label)
                    addLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    local addHl = addItem:CreateTexture(nil, "ARTWORK")
                    addHl:SetAllPoints(); addHl:SetColorTexture(1, 1, 1, 1); addHl:SetAlpha(0)
                    local bType = entry.type
                    addItem:SetScript("OnEnter", function()
                        addLbl:SetTextColor(1, 1, 1, 1); addHl:SetAlpha(hlA)
                    end)
                    addItem:SetScript("OnLeave", function()
                        addLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); addHl:SetAlpha(0)
                    end)
                    addItem:SetScript("OnClick", function()
                        menu:Hide()
                        ns.AddCDMBar(bType)
                        optState.selectedCDMBarIndex = #p.cdmBars.bars
                        Refresh()
                        EllesmereUI:InvalidateContentHeaderCache()
                        EllesmereUI:SetContentHeader(optState._cdmHeaderBuilder)
                        EllesmereUI:RefreshPage(true)
                    end)
                end
                mH = mH + ITEM_H
            end

            menu:SetHeight(mH + 4)

            -- Close on left-click outside (non-blocking). Never dismiss while a custom-bar row is being dragged -- a fast drag can momentarily leave the menu bounds.
            menu:SetScript("OnUpdate", function(m)
                if dragState.active then return end
                if not m:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                    m:Hide()
                end
            end)
            menu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)

            menu:Show()
            ddMenu = menu
        end

        -- Dropdown button hover/click
        ddBtn:SetScript("OnEnter", function()
            ddLbl:SetAlpha(mTxtHA)
            ddBrd:SetColor(1, 1, 1, mBrdHA)
            ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
        end)
        ddBtn:SetScript("OnLeave", function()
            if ddMenu and ddMenu:IsShown() then return end
            ddLbl:SetAlpha(mTxtA)
            ddBrd:SetColor(1, 1, 1, mBrdA)
            ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        end)
        ddBtn:SetScript("OnClick", function()
            if ddMenu and ddMenu:IsShown() then ddMenu:Hide() else BuildDDMenu() end
        end)
        ddBtn:HookScript("OnHide", function() if ddMenu then ddMenu:Hide() end end)

        PP.Point(ddBtn, "TOP", hdr, "TOP", 0, fy)
        fy = fy - DD_H - PV_PAD

        -- Live CDM bar preview
        local previewH = BuildCDMLivePreview(hdr, fy)
        fy = fy - previewH - PV_PAD

        optState._cdmHeaderFixedH = 20 + DD_H + PV_PAD + PV_PAD

        return math.abs(fy)
    end
    EllesmereUI:SetContentHeader(optState._cdmHeaderBuilder)

    -- Refresh preview icons on mount/dismount (skyriding swaps action bar icons). Skipped
    -- during a hidden search pre-build for the same reason as the pageListener in BuildBarGlowsPage: OnHide cleanup may never fire for a never-visible wrapper, leaking the listener all session.
    if not EllesmereUI._prebuilding then
        local mountListener = CreateFrame("Frame")
        mountListener:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        mountListener:SetScript("OnEvent", function()
            EllesmereUI:RefreshPage(true)
        end)
        parent:HookScript("OnHide", function()
            mountListener:UnregisterAllEvents()
        end)
    end

    -------------------------------------------------------------------
    --  Scrollable options
    -------------------------------------------------------------------

    -------------------------------------------------------------------
    --  BAR LAYOUT / ICON DISPLAY
    -------------------------------------------------------------------
    parent._showRowDivider = true

    if barData.key == "buffs" then
        -- ("Use Blizzard Buff Bar" toggle temporarily removed.)
    end

    -------------------------------------------------------------------
    --  BAR LAYOUT
    -------------------------------------------------------------------
    -- Sync helper: all bars except ghost/focuskick. FocusKick is a nameplate-anchored
    -- identity and never receives global syncs.
    local function ForEachSyncBar(fn)
        local pp = DB(); if not pp or not pp.cdmBars then return end
        for _, b in ipairs(pp.cdmBars.bars) do
            if not b.isGhostBar and b.key ~= "focuskick" then fn(b) end
        end
    end

    if not isFocusKick then
    _, h = W:SectionHeader(parent, "BAR LAYOUT", y);  y = y - h

    -- Row 1: (Sync) Visibility. Mouseover stays structurally absent for CDM bars
    -- (noMouseover), matching the old VIS_VALUES_CDM list.
    local visRow, visH = EllesmereUI.BuildVisibilityRow(W, parent, y,
        { getStore = BD, legacyKey = "barVisibility",
          caps = { partyIncludesRaid = false, noMouseover = true, luaDragonriding = true },
          -- The three built-in bars ship visHideHousing = true in DEFAULTS, so an
          -- explicit uncheck must persist false or DeepMergeDefaults re-fills it to
          -- true on next login. Harmless for other bars: they never go through that
          -- merge, so the checkbox reads store[k] == true either way.
          trueDefaultOpts = { visHideHousing = true },
          onChanged = function()
              ns.CDMApplyVisibility()
          end,
          onOptionChanged = function()
              ns.CDMApplyVisibility()
          end },
        -- Number of Rows moved up into the slot the Visibility Options dropdown
        -- left behind; its Row Icons cog moved with it.
        { type="slider", text="Number of Rows",
          min=1, max=6, step=1,
          getValue=function() return BD().numRows or 1 end,
          setValue=function(v)
              local bd = BD()
              bd.numRows = v
              if v ~= 2 then
                  bd.topRowCount = nil; bd.customTopRowEnabled = nil
                  bd.bottomRowCount = nil; bd.customBottomRowEnabled = nil
                  bd.topRowSizeOffset = nil; bd.customTopRowSizeEnabled = nil
                  bd.bottomRowSizeOffset = nil; bd.customBottomRowSizeEnabled = nil
                  if bd.rowGrowDirection then
                      -- The row growth pin rides on the 2-row custom split (the
                      -- only layout whose row count changes at runtime). Clear it
                      -- with the rest of the split settings and re-store the
                      -- position in plain edge format from the bar's current spot.
                      bd.rowGrowDirection = nil
                      if ns.RecaptureBarAnchor then ns.RecaptureBarAnchor(bd.key) end
                  end
              end
              -- numRows change invalidates cached match dims (rows is one
              -- of the inputs to the matched-axis dim calculation).
              bd._matchIconPhys = nil
              bd._matchExtraPixels = nil
              bd._matchStride = nil
              bd._matchExtraPixelsH = nil
              bd._matchStrideH = nil
              ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              EllesmereUI:RefreshPage()
          end });  y = y - visH

    -- ONE sync icon now that both halves share a control: VisFullCopy / VisFullEquals
    -- carry the mode selection and every option boolean together.
    if not EllesmereUI._prebuilding then
        local rgn = visRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Visibility to all Bars",
            isSynced = function()
                local src = BD()
                local synced = true
                ForEachSyncBar(function(b)
                    if not EllesmereUI.VisFullEquals(src, "barVisibility", b, "barVisibility") then synced = false end
                end)
                return synced
            end,
            onClick = function()
                local src = BD()
                ForEachSyncBar(function(b)
                    if b ~= src then EllesmereUI.VisFullCopy(b, src, "barVisibility") end
                end)
                ns.CDMApplyVisibility(); EllesmereUI:RefreshPage()
            end,
        })
    end

    -- Row 2: Anchor to Cursor | Cursor Position (cog: X + Y)
    do
        local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
            W = W, parent = parent, y = y,
            getData = BD,
            onApply = function()
                ns.BuildAllCDMBars(); ns.RegisterCDMUnlockElements()
                Refresh()
            end,
        })
        y = y - cursorH
    end

    -- Bar Opacity is offered for cooldown/utility/buff bars only (excl. focuskick);
    -- other bar types leave the slot blank, as before.
    local isCDOrUtilityRow3 = (barData.barType == "cooldowns" or barData.barType == "utility" or barData.barType == "buffs") and not isFocusKick
    local row3Right
    if isCDOrUtilityRow3 then
        row3Right = { type="slider", text="Bar Opacity",
            min=0, max=100, step=1,
            getValue=function() return math.floor((BD().barOpacity or 1) * 100 + 0.5) end,
            setValue=function(v)
                BD().barOpacity = v / 100
                if ns.ApplyBarOpacity then ns.ApplyBarOpacity(BD().key) end
                UpdateCDMPreview()
            end }
    else
        row3Right = { type="label", text="" }
    end
    local opacityRow
    opacityRow, h = W:DualRow(parent, y,
        { type="toggle", text="Bar Background",
          getValue=function() return BD().barBgEnabled == true end,
          setValue=function(v)
              BD().barBgEnabled = v
              ns.BuildAllCDMBars(); Refresh()
              UpdateCDMPreview(); EllesmereUI:RefreshPage()
          end },
        row3Right);  y = y - h

    -- Inline color swatch on Bar Background (left)
    if not EllesmereUI._prebuilding then
        local rgn = opacityRow._leftRegion
        local ctrl = rgn and rgn._control
        if ctrl and EllesmereUI.BuildColorSwatch then
            local bgSwatch, updateBgSwatch = EllesmereUI.BuildColorSwatch(
                rgn, opacityRow:GetFrameLevel() + 3,
                function() return BD().barBgR or 0, BD().barBgG or 0, BD().barBgB or 0, BD().barBgA or 0.5 end,
                function(r, g, b, a)
                    BD().barBgR = r; BD().barBgG = g; BD().barBgB = b; BD().barBgA = a
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                end,
                true, 20)
            PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local block = CreateFrame("Frame", nil, bgSwatch)
            block:SetAllPoints(); block:SetFrameLevel(bgSwatch:GetFrameLevel() + 10); block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(bgSwatch, EllesmereUI.DisabledTooltip("Bar Background"))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                if updateBgSwatch then updateBgSwatch() end
                local on = BD().barBgEnabled == true
                bgSwatch:SetAlpha(on and 1 or 0.3)
                if on then block:Hide() else block:Show() end
            end)
            local on = BD().barBgEnabled == true
            bgSwatch:SetAlpha(on and 1 or 0.3)
            if on then block:Hide() else block:Show() end
        end
    end

    -- Inline cog on Number of Rows (now in the Visibility row's right slot):
    -- Row Icons settings (only relevant when numRows == 2)
    if not EllesmereUI._prebuilding then
        local leftRgn = visRow._rightRegion
        local ctrl = leftRgn._control
        local function customTopOff()
            local bd = BD()
            return not bd or not bd.customTopRowEnabled
        end
        local function rowsNotTwo()
            return (BD().numRows or 1) ~= 2
        end
        -- Row-size options are locked while the bar is width/height matched,
        -- exactly like Icon Scale (a per-row size offset can't honor a match).
        local rsMatchKey = "CDM_" .. BD().key
        local rsWDis, rsWTip = EllesmereUI.MatchGuard(rsMatchKey, "Width")
        local rsHDis, rsHTip = EllesmereUI.MatchGuard(rsMatchKey, "Height")
        local function rowSizeMatched() return rsWDis() or rsHDis() end
        local function rowSizeMatchTip()
            if rsWDis() then return rsWTip() end
            return rsHTip()
        end
        -- Row Growth dropdown: labels track the bar's orientation (rows
        -- stack vertically on horizontal bars, horizontally on vertical
        -- bars). The page rebuilds on orientation flips and bar switches,
        -- so build-time resolution is safe.
        local rowGrowValues, rowGrowOrder, rowGrowTip
        if BD().verticalOrientation then
            rowGrowValues = { CENTER = "Grow Centered", RIGHT = "Grow Right", LEFT = "Grow Left" }
            rowGrowOrder = { "CENTER", "RIGHT", "LEFT" }
            rowGrowTip = "How extra columns grow when the second column appears or disappears. Grow Right keeps the left column in place, Grow Left keeps the right column in place, Grow Centered keeps the bar centered."
        else
            rowGrowValues = { CENTER = "Grow Centered", DOWN = "Grow Down", UP = "Grow Up" }
            rowGrowOrder = { "CENTER", "DOWN", "UP" }
            rowGrowTip = "How extra rows grow when the second row appears or disappears. Grow Down keeps the top row in place, Grow Up keeps the bottom row in place, Grow Centered keeps the bar centered."
        end
        EllesmereUI.BuildInlineCog(leftRgn, { anchorTo = ctrl, icon = EllesmereUI.COGS_ICON,
            title = "Row Icons",
            rows = {
                { type="dropdown", label="Row Growth",
                  values=rowGrowValues, order=rowGrowOrder,
                  tooltip=rowGrowTip,
                  -- Only meaningful with the 2-row custom split (the only
                  -- layout whose row count changes at runtime). Anchored
                  -- bars are positioned by their anchor system, which
                  -- ignores the pin entirely.
                  disabled=function()
                      if rowsNotTwo() then return true end
                      local b = BD()
                      if b.anchorTo and b.anchorTo ~= "none" then return true end
                      if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("CDM_" .. b.key) then return true end
                      return false
                  end,
                  disabledTooltip=function()
                      if rowsNotTwo() then return "This option requires exactly 2 rows" end
                      return "Not available while this bar is anchored to another element"
                  end,
                  rawTooltip=true,
                  get=function() return BD().rowGrowDirection or "CENTER" end,
                  set=function(v)
                      local bd = BD()
                      bd.rowGrowDirection = (v ~= "CENTER") and v or nil
                      -- Recapture the corner from the bar's current spot BEFORE
                      -- rebuilding, so the new anchor pins where the bar sits now.
                      if ns.RecaptureBarAnchor then ns.RecaptureBarAnchor(bd.key) end
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  end },
                { type="toggle", label="Custom Base Row Count",
                  -- The base row is the FIRST DATA row: it fills first and it is
                  -- the row Row Growth keeps in place (visual top normally, visual
                  -- bottom/right when reversed). Stored in the legacy topRowCount
                  -- keys; the legacy bottom-count fields are still honored at
                  -- runtime for old profiles but no longer have UI. Enabling this
                  -- clears the legacy bottom flag so the base count takes effect.
                  disabled=rowsNotTwo,
                  disabledTooltip="This option requires exactly 2 rows",
                  rawTooltip=true,
                  get=function() return BD().customTopRowEnabled end,
                  set=function(v)
                      BD().customTopRowEnabled = v
                      if v then BD().customBottomRowEnabled = nil end
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  end },
                { type="slider", label="Base Row Icons",
                  min=1, max=15, step=1,
                  tooltip="How many icons to show on the base row (the row that fills first and that Row Growth keeps in place). The rest go on the second row.",
                  disabled=function() return rowsNotTwo() or customTopOff() end,
                  disabledTooltip=function()
                      if rowsNotTwo() then return "This option requires exactly 2 rows" end
                      return "Custom Base Row Count"
                  end,
                  get=function()
                      local bd = BD()
                      if bd.topRowCount and bd.topRowCount > 0 then return bd.topRowCount end
                      local count = 0
                      local sdTR = ns.GetBarSpellData(bd.key)
                      if sdTR and sdTR.assignedSpells then
                          for _, sid in ipairs(sdTR.assignedSpells) do if sid and sid ~= 0 then count = count + 1 end end
                      end
                      if count == 0 then return 1 end
                      return math.ceil(count / 2)
                  end,
                  set=function(v)
                      if v == 0 then v = nil end
                      BD().topRowCount = v
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  end },
                { type="toggle", label="Custom Base Row Size",
                  -- Mutually exclusive with Custom Second Row Size (stored
                  -- in the legacy customBottomRowSize* keys); also locked
                  -- while the bar is width/height matched (same as Icon Scale).
                  disabled=function() return rowsNotTwo() or rowSizeMatched() or BD().customBottomRowSizeEnabled == true end,
                  disabledTooltip=function()
                      if rowsNotTwo() then return "This option requires exactly 2 rows" end
                      if rowSizeMatched() then return rowSizeMatchTip() end
                      return "Disabled while Custom Second Row Size is enabled"
                  end,
                  rawTooltip=true,
                  get=function() return BD().customTopRowSizeEnabled end,
                  set=function(v)
                      BD().customTopRowSizeEnabled = v
                      if v then BD().customBottomRowSizeEnabled = nil end
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  end },
                { type="slider", label="Base Icon Size",
                  min=-20, max=20, step=1,
                  tooltip="Offsets the base row's icon size in pixels from Icon Scale. The second row keeps the base size.",
                  disabled=function() return rowsNotTwo() or rowSizeMatched() or not BD().customTopRowSizeEnabled end,
                  disabledTooltip=function()
                      if rowsNotTwo() then return "This option requires exactly 2 rows" end
                      if rowSizeMatched() then return rowSizeMatchTip() end
                      return "Custom Base Row Size"
                  end,
                  rawTooltip=function() return rowSizeMatched() end,
                  get=function() return BD().topRowSizeOffset or 0 end,
                  set=function(v)
                      if v == 0 then v = nil end
                      BD().topRowSizeOffset = v
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  end },
                { type="toggle", label="Custom Second Row Size",
                  -- Flip of Custom Base Row Size; mutually exclusive with it.
                  disabled=function() return rowsNotTwo() or rowSizeMatched() or BD().customTopRowSizeEnabled == true end,
                  disabledTooltip=function()
                      if rowsNotTwo() then return "This option requires exactly 2 rows" end
                      if rowSizeMatched() then return rowSizeMatchTip() end
                      return "Disabled while Custom Base Row Size is enabled"
                  end,
                  rawTooltip=true,
                  get=function() return BD().customBottomRowSizeEnabled end,
                  set=function(v)
                      BD().customBottomRowSizeEnabled = v
                      if v then BD().customTopRowSizeEnabled = nil end
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  end },
                { type="slider", label="Second Row Icon Size",
                  min=-20, max=20, step=1,
                  tooltip="Offsets the second row's icon size in pixels from Icon Scale. The base row keeps the base size.",
                  disabled=function() return rowsNotTwo() or rowSizeMatched() or not BD().customBottomRowSizeEnabled end,
                  disabledTooltip=function()
                      if rowsNotTwo() then return "This option requires exactly 2 rows" end
                      if rowSizeMatched() then return rowSizeMatchTip() end
                      return "Custom Second Row Size"
                  end,
                  rawTooltip=function() return rowSizeMatched() end,
                  get=function() return BD().bottomRowSizeOffset or 0 end,
                  set=function(v)
                      if v == 0 then v = nil end
                      BD().bottomRowSizeOffset = v
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  end },
            },
        })
        -- Cog stays clickable at any row count; the rows inside gate
        -- themselves on the 2-row requirement individually.
    end

    -- Inline cog on Bar Opacity (now in the Bar Background row): fade the bar to a
    -- chosen alpha while out of combat. Off by default.
    if isCDOrUtilityRow3 then
        local rgn = opacityRow._rightRegion
        local ctrl = rgn and rgn._control
        EllesmereUI.BuildInlineCog(rgn, {
            anchorTo = ctrl,
            title = "Out of Combat Alpha",
            rows = {
                { type="toggle", label="Fade Out of Combat",
                  tooltip="Dims this bar while out of combat.",
                  rawTooltip=true,
                  get=function() return BD().oocFadeEnabled == true end,
                  set=function(v)
                      BD().oocFadeEnabled = v
                      if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
                      UpdateCDMPreview()
                  end },
                { type="slider", label="Out of Combat Alpha",
                  min=0, max=100, step=1,
                  disabled=function() return not BD().oocFadeEnabled end,
                  disabledTooltip="Enable Fade Out of Combat first",
                  rawTooltip=true,
                  get=function() return math.floor((BD().oocFadeAlpha or 0.5) * 100 + 0.5) end,
                  set=function(v)
                      BD().oocFadeAlpha = v / 100
                      if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
                      UpdateCDMPreview()
                  end },
            },
        })
    end

    -- Max Icons + Overflow To: excess icons (beyond Max, the tail of this bar's order)
    -- render on the target bar for the session. Identity, per-spell settings and the options
    -- preview stay on this bar. Legacy profiles carry nil barType on default bars -- resolve the family via the shared helper, never the raw field.
    local ofBarType = ns.GetBarType and ns.GetBarType(barData) or barData.barType
    local isOverflowBar = (ofBarType == "cooldowns" or ofBarType == "utility")
        and not barData.isGhostBar
        and barData.key ~= (ns.FOCUSKICK_BAR_KEY or "focuskick")
    if isOverflowBar then
        local function OverflowShiftBlocked()
            return (ns.CdmBarHasShiftCdState and ns.CdmBarHasShiftCdState(BD().key)) or false
        end
        -- A bar may not BOTH receive overflow and have its own overflow config: incoming
        -- icons ignore the recipient's cap and never chain onward, so a cap on a recipient
        -- would promise behavior that does not exist. Recipient = ANY bar (enabled or not -- re-enabling must not create the forbidden state) with an active cap+target pair pointing here.
        local function BarIsOverflowRecipient(key)
            local pp = DB()
            if not (pp and pp.cdmBars) then return false end
            for _, b in ipairs(pp.cdmBars.bars) do
                if b.key ~= key and b.maxIcons and b.maxIcons > 0
                   and b.overflowTarget == key then
                    return true
                end
            end
            return false
        end
        local ofVals, ofOrder = { [""] = "None" }, { "" }
        do
            local pp = DB()
            if pp and pp.cdmBars then
                for _, b in ipairs(pp.cdmBars.bars) do
                    local bt = ns.GetBarType and ns.GetBarType(b) or b.barType
                    -- Bars with their own active overflow config are not offered as targets (the recipient rule, other door).
                    local hasOwnOverflow = b.maxIcons and b.maxIcons > 0 and b.overflowTarget ~= nil
                    if b.key ~= barData.key and not b.isGhostBar
                       and b.key ~= (ns.FOCUSKICK_BAR_KEY or "focuskick")
                       and b.key ~= "buffs"
                       and bt ~= "buffs" and bt ~= "custom_buff"
                       and not hasOwnOverflow then
                        ofVals[b.key] = EllesmereUI.L(b.name or b.key)
                        ofOrder[#ofOrder + 1] = b.key
                    end
                end
                -- A stored target that the filter (or a bar delete) now excludes still
                -- displays -- and can be cleared -- rather than masquerading as "None" while active at runtime (pre-rule configs keep working under no-chaining).
                local cur = barData.overflowTarget
                if cur and not ofVals[cur] then
                    local curName = cur
                    for _, b in ipairs(pp.cdmBars.bars) do
                        if b.key == cur then curName = b.name or cur; break end
                    end
                    ofVals[cur] = EllesmereUI.L(curName)
                    ofOrder[#ofOrder + 1] = cur
                end
            end
        end
        _, h = W:DualRow(parent, y,
            { type="slider", text="Max Icons (0 = Off)",
              min=0, max=20, step=1,
              -- A blocked bar with a value already set can still lower/clear it -- a disabled control must never trap an existing value on.
              disabled=function()
                  local b = BD()
                  return (OverflowShiftBlocked() or BarIsOverflowRecipient(b.key))
                      and not (b.maxIcons and b.maxIcons > 0)
              end,
              disabledTooltip=function()
                  if BarIsOverflowRecipient(BD().key) then
                      return "Not available while another bar overflows into this bar"
                  end
                  return "Not available while a spell on this bar uses a Cooldown State Shift Icons setting"
              end,
              rawTooltip=true,
              getValue=function() return BD().maxIcons or 0 end,
              setValue=function(v)
                  if v == 0 then v = nil end
                  BD().maxIcons = v
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
              end },
            { type="dropdown", text="Overflow To",
              values=ofVals, order=ofOrder,
              -- Recipient bars cannot pick a fresh target (third door); one with a stale target set stays enabled so it can be cleared back to None.
              disabled=function()
                  local b = BD()
                  return OverflowShiftBlocked()
                      or (BarIsOverflowRecipient(b.key) and not b.overflowTarget)
                      or not (b.maxIcons and b.maxIcons > 0)
              end,
              -- Tooltip priority: recipient block, then the plain Max Icons requirement. The
              -- Shift Icons message only shows when it is the ACTUAL blocker (Max Icons
              -- already above 0 but a spell carries a shift cooldown-state setting) -- most users never touch that setting, so the default tooltip stays basic.
              disabledTooltip=function()
                  local b = BD()
                  if BarIsOverflowRecipient(b.key) then
                      return "Not available while another bar overflows into this bar"
                  end
                  if not (b.maxIcons and b.maxIcons > 0) then
                      return "Requires Max Icons to be above 0"
                  end
                  return "Not available while a spell on this bar uses a Cooldown State Shift Icons setting"
              end,
              rawTooltip=true,
              getValue=function()
                  local t = BD().overflowTarget
                  if t and ofVals[t] then return t end
                  return ""
              end,
              setValue=function(v)
                  if v == "" then v = nil end
                  BD().overflowTarget = v
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end });  y = y - h
    end

    -- Vertical Orientation shares a row with Keep Buffs in Same Place on buff bars
    -- (both apply there), and stands alone -- last row of the section -- otherwise.
    -- Moved down here, after Max Icons/Overflow To; shown for every non-focuskick bar
    -- regardless of overflow capability, same as before the move (this section's outer
    -- gate is `not isFocusKick`, not isOverflowBar).
    local vertOrientCfg = { type="toggle", text="Vertical Orientation",
        getValue=function() return BD().verticalOrientation end,
        setValue=function(v)
            local bd = BD()
            bd.verticalOrientation = v
            bd.growDirection = v and "DOWN" or "RIGHT"
            -- Orientation flip invalidates the row growth direction too (UP/DOWN are
            -- horizontal-bar values, LEFT/RIGHT vertical).
            bd.rowGrowDirection = nil
            -- Orientation flip swaps the meaning of width-axis vs height-axis, so width/height match caches no longer apply.
            bd._matchIconPhys = nil
            bd._matchExtraPixels = nil
            bd._matchStride = nil
            bd._matchExtraPixelsH = nil
            bd._matchStrideH = nil
            ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
        end }

    if ns.IsBarBuffFamily(barData) then
        local prof = ns.ECME and ns.ECME.db and ns.ECME.db.profile
        -- (Hide Buffs When Inactive toggle removed: always forced ON.)
    end

    -- Keep Buffs in Same Place (native buff bars): reserves every tracked buff's slot so
    -- active buffs never reposition; inactive slots are invisible. Reuses the Always-Show
    -- placeholder path internally (placeholders injected, then rendered alpha 0). Mutually exclusive with Always Show Buffs -- disabled while that is on.
    -- (Minimum Bar Size moved to the Icon Scale inline cog, user-directed.)
    if isBuffBar then
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Keep Buffs in Same Place",
              disabled=function()
                  local b = BD()
                  return b.showInactiveBuffIcons == true or AnyIconAlwaysShowOn(b.key)
              end,
              disabledTooltip="Disabled while Always Show Buffs is enabled (on the bar, or on any individual buff)", rawTooltip=true,
              getValue=function() return BD().hidePlaceholderIcon == true end,
              setValue=function(v)
                  BD().hidePlaceholderIcon = v
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  EllesmereUI:RefreshPage()
              end },
            vertOrientCfg); y = y - h
    else
        _, h = W:DualRow(parent, y, vertOrientCfg, { type="label", text="" });  y = y - h
    end

    end -- not isFocusKick (Bar Layout section)

    -------------------------------------------------------------------
    --  FOCUSKICK OPTIONS (FocusKick only)
    -------------------------------------------------------------------
    if isFocusKick then
        _, h = W:SectionHeader(parent, "FocusKick Options", y);  y = y - h

        local NP_SIDE_VALUES = { LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" }
        local NP_SIDE_ORDER  = { "LEFT", "RIGHT", "TOP", "BOTTOM" }

        -- Row 1: Nameplate Anchor (left) | Focus Text Reminders (right)
        local npRow
        npRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Nameplate Anchor",
              values = NP_SIDE_VALUES, order = NP_SIDE_ORDER,
              getValue = function() return BD().nameplateAnchorSide or "LEFT" end,
              setValue = function(v)
                  BD().nameplateAnchorSide = v
                  if ns.ApplyFocusKickAnchor then ns.ApplyFocusKickAnchor() end
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Focus Text Reminders",
              tooltip = "This will display the word \"FOCUS\" below caster/miniboss mobs in M+ if you have not set your focus. Disabled for specs with no kick.",
              getValue = function()
                  local bd = BD()
                  return bd.focusReminderEnabled == true
              end,
              setValue = function(v)
                  BD().focusReminderEnabled = v
                  if ns.RefreshFocusReminders then ns.RefreshFocusReminders() end
                  EllesmereUI:RefreshPage()
              end });  y = y - h

        -- Inline cog for Nameplate Offset (left)
        if not EllesmereUI._prebuilding then
            local rgn = npRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.RESIZE_ICON, anchorTo = rgn._control,
                title = "Nameplate Offset",
                rows = {
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() return BD().nameplateOffsetX or 0 end,
                      set = function(v)
                          BD().nameplateOffsetX = v
                          if ns.ApplyFocusKickAnchor then ns.ApplyFocusKickAnchor() end
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() return BD().nameplateOffsetY or 0 end,
                      set = function(v)
                          BD().nameplateOffsetY = v
                          if ns.ApplyFocusKickAnchor then ns.ApplyFocusKickAnchor() end
                      end },
                },
            })
        end

        -- Inline dual swatch + cog for Focus Reminders (right region). Layout right-to-left
        -- along the row's right region: [control] [accent swatch] [custom swatch] [cog].
        -- Accent swatch (closest to control) is the active mode by default; custom swatch dims and blocks while accent is on.
        if not EllesmereUI._prebuilding then
            local rgn = npRow._rightRegion
            local ctrl = rgn and rgn._control

            -- Right (accent) swatch: one-click activation, displays live ELLESMERE_GREEN
            local accentSwatch, updateAccentSwatch = EllesmereUI.BuildColorSwatch(
                rgn, npRow:GetFrameLevel() + 3,
                function()
                    local eg = EllesmereUI.ELLESMERE_GREEN
                    if eg then return eg.r, eg.g, eg.b end
                    return 0.047, 0.824, 0.624
                end,
                function() end,  -- read-only display, no picker
                false, 20)
            PP.Point(accentSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            accentSwatch:SetScript("OnClick", function()
                BD().focusReminderUseAccent = true
                if ns.RefreshFocusReminders then ns.RefreshFocusReminders() end
                EllesmereUI:RefreshPage()
            end)
            accentSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
            end)
            accentSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Left (custom) swatch: color picker when accent mode is off
            local customSwatch, updateCustomSwatch = EllesmereUI.BuildColorSwatch(
                rgn, npRow:GetFrameLevel() + 3,
                function()
                    local bd = BD()
                    return bd.focusReminderR or 1, bd.focusReminderG or 1, bd.focusReminderB or 1
                end,
                function(r, g, b)
                    BD().focusReminderR, BD().focusReminderG, BD().focusReminderB = r, g, b
                    BD().focusReminderUseAccent = false
                    if ns.RefreshFocusReminders then ns.RefreshFocusReminders() end
                end,
                false, 20)
            PP.Point(customSwatch, "RIGHT", accentSwatch, "LEFT", -8, 0)
            customSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Block overlay: while accent mode is active, clicking the custom swatch flips accent mode off instead of opening the color picker.
            local customBlock = CreateFrame("Button", nil, customSwatch)
            customBlock:SetAllPoints()
            customBlock:SetFrameLevel(customSwatch:GetFrameLevel() + 10)
            customBlock:EnableMouse(true)
            customBlock:SetScript("OnClick", function()
                if BD().focusReminderUseAccent then
                    BD().focusReminderUseAccent = false
                    if ns.RefreshFocusReminders then ns.RefreshFocusReminders() end
                    EllesmereUI:RefreshPage()
                end
            end)
            customBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.BuildInlineCog(rgn, { anchorTo = customSwatch, icon = EllesmereUI.RESIZE_ICON,
                title = "Focus Reminder Settings",
                rows = {
                    { type = "slider", label = "Text Size", min = 8, max = 50, step = 1,
                      get = function() return BD().focusReminderSize or 26 end,
                      set = function(v)
                          BD().focusReminderSize = v
                          if ns.RefreshFocusReminders then ns.RefreshFocusReminders() end
                      end },
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() return BD().focusReminderOffsetX or 0 end,
                      set = function(v)
                          BD().focusReminderOffsetX = v
                          if ns.RefreshFocusReminders then ns.RefreshFocusReminders() end
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() return BD().focusReminderOffsetY or 0 end,
                      set = function(v)
                          BD().focusReminderOffsetY = v
                          if ns.RefreshFocusReminders then ns.RefreshFocusReminders() end
                      end },
                },
            })

            -- Disable both swatches + cog when Focus Text Reminders toggle is off
            local enableBlock = CreateFrame("Frame", nil, customSwatch)
            enableBlock:SetAllPoints()
            enableBlock:SetFrameLevel(customSwatch:GetFrameLevel() + 20)
            enableBlock:EnableMouse(true)
            enableBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(customSwatch, EllesmereUI.DisabledTooltip("Focus Text Reminders"))
            end)
            enableBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function UpdateFRSwatchState()
                local bd = BD()
                local on = bd.focusReminderEnabled == true
                if not on then
                    accentSwatch:SetAlpha(0.3); customSwatch:SetAlpha(0.3)
                    customBlock:Hide(); enableBlock:Show()
                else
                    enableBlock:Hide()
                    local useAccent = bd.focusReminderUseAccent
                    if useAccent then
                        accentSwatch:SetAlpha(1)
                        customSwatch:SetAlpha(0.3); customBlock:Show()
                    else
                        accentSwatch:SetAlpha(0.3)
                        customSwatch:SetAlpha(1); customBlock:Hide()
                    end
                end
            end
            EllesmereUI.RegisterWidgetRefresh(function()
                updateAccentSwatch(); updateCustomSwatch(); UpdateFRSwatchState()
            end)
            UpdateFRSwatchState()
        end

        -- Row 2: Focus Cast Sound (left) | Interrupt Spell picker (right). Sound values come
        -- from the runtime sound table (built-in sounds + LSM appended at init); the spell
        -- picker rebuilds every render so it reflects the bar's current spell list. Shallow-copy the names table to attach per-row menu options (preview icon) without polluting the shared ns.FOCUSKICK_SOUND_NAMES other code reads.
        local soundValues = {}
        if ns.FOCUSKICK_SOUND_NAMES then
            for k, v in pairs(ns.FOCUSKICK_SOUND_NAMES) do soundValues[k] = v end
        else
            soundValues.none = "None"
        end
        local soundOrder = ns.FOCUSKICK_SOUND_ORDER or { "none" }
        soundValues._menuOpts = {
            itemHeight = 26,
            maxTextWidthPct = 0.8,
            searchable = true,
            iconAtlas = function(key)
                if key == "none" then return nil end
                local paths = ns.FOCUSKICK_SOUND_PATHS
                if not paths or not paths[key] then return nil end
                return EllesmereUI.SOUND_ICON_ATLAS
            end,
            iconPressedAtlas = function(key)
                if key == "none" then return nil end
                return EllesmereUI.SOUND_ICON_PRESSED_ATLAS
            end,
            iconOnClick = function(key)
                local paths = ns.FOCUSKICK_SOUND_PATHS
                local path = paths and paths[key]
                if path then PlaySoundFile(path, "Master") end
            end,
            iconTooltip = function() return "Preview Sound" end,
        }

        -- Spell dropdown values/order -- rebuilt live on every dropdown
        -- click (see OnClick hook below) so the list always reflects what
        -- is currently on the focuskick bar, even if the user added or
        -- removed spells via the spell picker without closing options.
        local spellValues = {}
        local spellOrder  = {}
        local function RebuildSpellOptions()
            wipe(spellValues)
            for i = #spellOrder, 1, -1 do spellOrder[i] = nil end
            local sd = ns.GetBarSpellData and ns.GetBarSpellData("focuskick")
            local list = sd and sd.assignedSpells
            if list then
                for _, sid in ipairs(list) do
                    -- Only positive spell IDs (Blizzard cooldownable spells).
                    -- Skip negative preset markers (trinkets / items).
                    if type(sid) == "number" and sid > 0 then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                        local label = (info and info.name) or ("Spell " .. sid)
                        local key = tostring(sid)
                        if not spellValues[key] then
                            spellValues[key] = label
                            spellOrder[#spellOrder + 1] = key
                        end
                    end
                end
            end
            if #spellOrder == 0 then
                spellValues["__none"] = "(no spells on bar)"
                spellOrder[#spellOrder + 1] = "__none"
            end
            -- The stored selection can outlive its spell (removing the kick empties
            -- assignedSpells, focusKickInterruptSpellID keeps pointing at it) and the
            -- dropdown would render the raw spell id. Give it a NAME but do NOT add it
            -- to spellOrder: it must not be selectable on a bar that no longer holds it.
            -- Label it ONLY when this character can cast it: the id is profile-level but
            -- the spellbook is per-spec, so a spec sharing the profile can inherit a pick
            -- it can never use; unlabelled makes getValue below fall back to the bar's
            -- own contents.
            local selSid = BD and BD() and BD().focusKickInterruptSpellID
            if selSid and (not ns.ResolveCastableInterrupt
                or ns.ResolveCastableInterrupt(selSid)) then
                local selKey = tostring(selSid)
                if not spellValues[selKey] then
                    local selInfo = C_Spell and C_Spell.GetSpellInfo
                        and C_Spell.GetSpellInfo(selSid)
                    spellValues[selKey] = (selInfo and selInfo.name)
                        or ("Spell " .. selKey)
                end
            end
        end
        RebuildSpellOptions()

        local focusKickRow
        focusKickRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Focus Cast Sound",
              values = soundValues, order = soundOrder,
              getValue = function() return BD().focusCastSoundKey or "none" end,
              setValue = function(v) BD().focusCastSoundKey = v end },
            { type = "dropdown", text = "Interrupt Spell",
              values = spellValues, order = spellOrder,
              getValue = function()
                  local sid = BD().focusKickInterruptSpellID
                  if not sid then return spellOrder[1] end
                  -- No label means RebuildSpellOptions rejected it: either
                  -- this character cannot cast it, or it is not on the bar
                  -- and not castable. Show what the bar actually holds
                  -- rather than a selection the player never made.
                  local key = tostring(sid)
                  if not spellValues[key] then return spellOrder[1] end
                  return key
              end,
              setValue = function(v)
                  if v == "__none" then
                      BD().focusKickInterruptSpellID = nil
                  else
                      BD().focusKickInterruptSpellID = tonumber(v)
                  end
              end });  y = y - h

        -- Live refresh: every click on the Interrupt Spell dropdown
        -- rebuilds the option list from the bar's current spells and
        -- invalidates the cached menu so the new options appear.
        do
            local rightRgn = focusKickRow and focusKickRow._rightRegion
            local ddBtn = rightRgn and rightRgn._control
            if ddBtn then
                local origOnClick = ddBtn:GetScript("OnClick")
                ddBtn:SetScript("OnClick", function(self, ...)
                    RebuildSpellOptions()
                    if ddBtn._invalidateMenu then ddBtn._invalidateMenu() end
                    if origOnClick then origOnClick(self, ...) end
                end)
            end
        end

        -- Row: Show on Target
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show on Target",
              tooltip = "Show the FocusKick bar on your current target's nameplate instead of your focus target's nameplate.",
              getValue = function() return BD().focusKickUseTarget == true end,
              setValue = function(v)
                  BD().focusKickUseTarget = v
                  if ns.ApplyFocusKickAnchor then ns.ApplyFocusKickAnchor() end
                  if ns.RefreshFocusCastProxyUnit then ns.RefreshFocusCastProxyUnit() end
                  EllesmereUI:RefreshPage()
              end },
            { type="label", text="" });  y = y - h

        _, h = W:Spacer(parent, y, 8);  y = y - h
    else
        _, h = W:Spacer(parent, y, 8);  y = y - h
    end

    -------------------------------------------------------------------
    --  ICON DISPLAY
    -------------------------------------------------------------------
    -- (The per-icon hint now lives directly below the preview icons -- see
    -- the reorder hint in BuildCDMLivePreview's pf.Update.)
    _, h = W:SectionHeader(parent, "ICON DISPLAY", y);  y = y - h
    y = EllesmereUI.BlizzStyle.Note(parent, y, "cdmicons")

    -- Active State Animation dropdown values
    local ACTIVE_ANIM_VALUES = {
        blizzard    = "Blizzard",
        ["1"]       = "Pixel Glow",
        ["3"]       = "Action Button Glow",
        ["4"]       = "Auto-Cast Shine",
        ["5"]       = "GCD",
        ["7"]       = "Classic WoW Glow",
        hideActive  = "Hide Active State",
    }
    local ACTIVE_ANIM_ORDER = { "blizzard", "hideActive", "1", "---", "3", "4", "5", "7" }

    local function IsCustomShape()
        local s = BD().iconShape or "none"
        return s ~= "none" and s ~= "cropped"
    end

    -- Adjust Crop cog on Custom Icon Shape (both shape rows below). Writes the per-bar
    -- iconCropPercent that ns.CdmCropFactor / ns.CdmCropTrim read; unset = 10 = the classic
    -- crop. Disabled unless the shape is Cropped. Under a stock style both shape rows are
    -- fully gated, so the row (and this cog with it) is hidden by the widget factory.
    local function AttachCropCog(rgn)
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() return (BD().iconShape or "none") ~= "cropped" end,
            disabledTooltip = "This option requires Custom Icon Shape to be set to Cropped",
            title = "Custom Icon Shape",
            rows = {
                { type="slider", label="Adjust Crop", min=5, max=25, step=1,
                  tooltip="How much is trimmed from the icon's top and bottom, as a percentage per side. 10% is the classic cropped look.",
                  get=function() return ns.CdmCropPercent(BD()) end,
                  set=function(v)
                      local bd = BD()
                      bd.iconCropPercent = v
                      -- Icon height changes: drop the same match caches the shape setter drops.
                      bd._matchIconPhys = nil
                      bd._matchExtraPixels = nil
                      bd._matchStride = nil
                      bd._matchExtraPixelsH = nil
                      bd._matchStrideH = nil
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  end },
            },
        })
    end

    -- Shape dropdown values
    local SHAPE_VALUES = {
        none     = "None",
        cropped  = "Cropped",
        square   = "Square",
        circle   = "Circle",
        csquare  = "Curved Square",
        diamond  = "Diamond",
        hexagon  = "Hexagon",
        portrait = "Portrait",
        shield   = "Shield",
    }
    local SHAPE_ORDER = { "none", "cropped", "---", "square", "circle", "csquare", "diamond", "hexagon", "portrait", "shield" }

    -- Border thickness dropdown
    local BORDER_LABELS = { none="None", thin="Thin", normal="Normal", heavy="Heavy", strong="Strong" }
    local BORDER_ORDER  = { "none", "thin", "normal", "heavy", "strong" }
    local BORDER_SIZES  = { none=0, thin=1, normal=2, heavy=3, strong=4 }

    local isBuffGlowBar = isBuffBar or (barData.barType == "custom_buff")
    local scaleAnimRow
    if isBuffGlowBar then
        -- Row 1: Always Show Buffs (native buff bars only) | Icon Scale.
        -- Per-bar now: shows a greyed placeholder icon for each inactive
        -- tracked buff. No edit-mode change, no reload. custom_buff bars
        -- draw their own always-on icons, so the toggle is hidden there.
        local row1Left
        if isBuffBar then
            row1Left = { type="toggle", text="Always Show Buffs",
                -- Mutually exclusive with "Keep Buffs in Same Place" (Bar Layout).
                -- Disabled while that is the active choice. The extra
                -- "and showInactiveBuffIcons ~= true" keeps a legacy both-on profile
                -- unlockable: this toggle stays enabled so it can be turned off.
                disabled=function() local b=BD(); return b.hidePlaceholderIcon == true and b.showInactiveBuffIcons ~= true end,
                disabledTooltip="Disabled while Keep Buffs in Same Place is enabled", rawTooltip=true,
                getValue=function() return BD().showInactiveBuffIcons == true end,
                setValue=function(v)
                    BD().showInactiveBuffIcons = v
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                    EllesmereUI:RefreshPage()
                end }
        else
            row1Left = { type="label", text="" }
        end
        local icsWDis, icsWTip, icsWRaw = EllesmereUI.MatchGuard("CDM_" .. barKey, "Width")
        local icsHDis, icsHTip = EllesmereUI.MatchGuard("CDM_" .. barKey, "Height")
        local icsDis = function() return icsWDis() or icsHDis() end
        local icsTip = function() if icsWDis() then return icsWTip() end if icsHDis() then return icsHTip() end return false end
        scaleAnimRow, h = W:DualRow(parent, y,
            row1Left,
            { type="slider", text="Icon Scale",
              min=16, max=100, step=1,
              disabled=icsDis, disabledTooltip=icsTip, rawTooltip=true,
              getValue=function() return BD().iconSize or 36 end,
              setValue=function(v)
                  local bd = BD()
                  bd.iconSize = v
                  bd._matchPhysWidth = nil
                  bd._matchPhysHeight = nil
                  bd._matchIconPhys = nil
                  bd._matchExtraPixels = nil
                  bd._matchStride = nil
                  bd._matchExtraPixelsH = nil
                  bd._matchStrideH = nil
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end });  y = y - h

        -- Inline cog on Always Show Buffs toggle (per-bar; native buff bars)
        if isBuffBar then
            local leftRgn = scaleAnimRow._leftRegion
            EllesmereUI.BuildInlineCog(leftRgn, {
                anchorTo = leftRgn._control,
                disabled = function() return not BD().showInactiveBuffIcons end,
                disabledTooltip = "Always Show Buffs",
                title = "Always Show Buffs",
                rows = {
                    { type="toggle", label="Desaturate Off CD",
                      get=function() return BD().desaturateInactiveBuffs ~= false end,
                      set=function(v)
                          BD().desaturateInactiveBuffs = v
                      end },
                },
            })
        end

        -- Row 2: Buff Glow + swatches | Icon Spacing. The Glows page's Buff Glow
        -- descriptor over this bar: a custom icon shape locks it (shown as None),
        -- and its Pixel Glow parameters keep their own row below (per-icon Buff
        -- Glows read them too), so this row takes the swatches only.
        local GO = EllesmereUI.GlowOptions
        local buffGlowDesc = ns._CDM_BuffGlowDesc(BD, function() ns.BuildAllCDMBars(); Refresh() end)
        buffGlowDesc.caps = { mode = true }
        buffGlowDesc.isOff, buffGlowDesc.disabled = IsCustomShape, IsCustomShape
        buffGlowDesc.disabledTooltip = "This option requires a non-custom button shape"
        local buffGlowRow
        buffGlowRow, h = W:DualRow(parent, y,
            GO.DropdownSpec(buffGlowDesc, "Buff Glow"),
            { type="slider", pixel=true, text="Icon Spacing",
              min=-10, max=20, step=1,
              getValue=function() return BD().spacing or 2 end,
              setValue=function(v)
                  local bd = BD()
                  bd.spacing = v
                  bd._matchIconPhys = nil
                  bd._matchExtraPixels = nil
                  bd._matchStride = nil
                  bd._matchExtraPixelsH = nil
                  bd._matchStrideH = nil
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end });  y = y - h
        GO.AttachInline(buffGlowRow._leftRegion, buffGlowDesc)

        -- (Pixel Glow Thickness / Lines / Speed moved to a dedicated row at the
        -- bottom of this section -- see "Pixel Glow Thickness (buff bars)" below.
        -- Same buffGlow* variables, so user settings are unchanged.)

        -- Row 3: Custom Icon Shape | Icon Zoom
        local buffShapeZoomRow
        buffShapeZoomRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("cdmicons", { type="dropdown", text="Custom Icon Shape",
              values=SHAPE_VALUES, order=SHAPE_ORDER,
              itemDisabled=function(val)
                  if val ~= "none" and val ~= "cropped" and (BD().borderTexture or "solid") ~= "solid" then return true end
                  return false
              end,
              itemDisabledTooltip=function(val)
                  if val ~= "none" and val ~= "cropped" and (BD().borderTexture or "solid") ~= "solid" then
                      return "This option requires the Border Style to be set to Solid"
                  end
              end,
              getValue=function() return BD().iconShape or "none" end,
              setValue=function(v)
                  local bd = BD()
                  bd.iconShape = v
                  bd.iconZoom = ns.CDM_SHAPE_ZOOM_DEFAULTS[v] or 0.08
                  local isCS = (v ~= "none" and v ~= "cropped")
                  if isCS then
                      bd.borderThickness = "strong"; bd.borderSize = BORDER_SIZES["strong"]
                      bd.activeStateAnim = "blizzard"
                  else
                      bd.borderThickness = "thin"; bd.borderSize = BORDER_SIZES["thin"]
                  end
                  bd._matchIconPhys = nil
                  bd._matchExtraPixels = nil
                  bd._matchStride = nil
                  bd._matchExtraPixelsH = nil
                  bd._matchStrideH = nil
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  -- The Border Size slot is a different control under a custom shape: rebuild the page.
                  EllesmereUI:RefreshPage(true)
              end }),
            EllesmereUI.BlizzStyle.Gate("cdmicons", { type="slider", text="Icon Zoom",
              min=0, max=0.20, step=0.01,
              getValue=function() return BD().iconZoom or 0.08 end,
              setValue=function(v)
                  BD().iconZoom = v
                  ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
              end }));  y = y - h

        AttachCropCog(buffShapeZoomRow._leftRegion)

        -- Sync icon on Custom Icon Shape (left of row 3)
        if not EllesmereUI._prebuilding then
        EllesmereUI.BuildSyncIcon({
            region  = buffShapeZoomRow._leftRegion,
            tooltip = "Apply Icon Shape to all Bars",
            isSynced = function()
                local bd = BD()
                local v = bd.iconShape or "none"
                local zoom = bd.iconZoom or 0.08
                local crop = ns.CdmCropPercent(bd)
                local synced = true
                ForEachSyncBar(function(b) if (b.iconShape or "none") ~= v or (b.iconZoom or 0.08) ~= zoom or ns.CdmCropPercent(b) ~= crop then synced = false end end)
                return synced
            end,
            onClick = function()
                local bd = BD()
                local v = bd.iconShape or "none"
                local zoom = bd.iconZoom or 0.08
                local crop = bd.iconCropPercent
                ForEachSyncBar(function(b)
                    b.iconShape = v; b.iconZoom = zoom; b.iconCropPercent = crop
                    local isCS = (v ~= "none" and v ~= "cropped")
                    if isCS then b.borderThickness = "strong"; b.borderSize = BORDER_SIZES["strong"]
                    else b.borderThickness = "thin"; b.borderSize = BORDER_SIZES["thin"] end
                    b._matchIconPhys = nil
                    b._matchExtraPixels = nil
                    b._matchStride = nil
                    b._matchExtraPixelsH = nil
                    b._matchStrideH = nil
                end)
                ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize(); EllesmereUI:RefreshPage()
            end,
        })
        end
        -- Sync icon on Icon Zoom (right of row 3)
        if not EllesmereUI._prebuilding then
        EllesmereUI.BuildSyncIcon({
            region  = buffShapeZoomRow._rightRegion,
            tooltip = "Apply Icon Zoom to all Bars",
            isSynced = function()
                local v = BD().iconZoom or 0.08
                local synced = true
                ForEachSyncBar(function(b) if (b.iconZoom or 0.08) ~= v then synced = false end end)
                return synced
            end,
            onClick = function()
                local v = BD().iconZoom or 0.08
                ForEachSyncBar(function(b) b.iconZoom = v end)
                ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
            end,
        })
        end

        -- Row 4: Border Size + swatches | Border Style dropdown + offset cog
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local buffBsRow
            -- Border Size: the exact-size slider, except under a custom shape, whose
            -- ring is on (Strong) or off (None): that keeps the None..Strong dropdown.
            local buffSizeCfg
            if IsCustomShape() then
                buffSizeCfg = { type="dropdown", text="Border Size",
                  values=BORDER_LABELS, order=BORDER_ORDER,
                  itemDisabled=function(val)
                      if IsCustomShape() and (val == "thin" or val == "normal" or val == "heavy") then return true end
                      return false
                  end,
                  itemDisabledTooltip=function(val)
                      if IsCustomShape() and (val == "thin" or val == "normal" or val == "heavy") then
                          return "This option requires a non-custom shape to be selected"
                      end
                  end,
                  getValue=function() return BD().borderThickness or "thin" end,
                  setValue=function(v)
                      BD().borderThickness = v; BD().borderSize = BORDER_SIZES[v] or 1
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                  end }
            else
                buffSizeCfg = EllesmereUI.BorderPxSliderCfg({ text="Border Size",
                  getStep=function() return BD().borderSize or 1 end,
                  setStep=function(step)
                      local bd = BD()
                      bd.borderThickness = EllesmereUI.BORDER_LABEL_OF_STEP[step] or "thin"; bd.borderSize = step
                  end,
                  getTex=function() return BD().borderTexture or "solid" end,
                  getPx=function() return BD().borderSizePx end,
                  setPx=function(v) BD().borderSizePx = v end,
                  apply=function() ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview() end,
                })
            end
            buffBsRow, h = W:DualRow(parent, y,
                EllesmereUI.BlizzStyle.Gate("cdmicons", buffSizeCfg),
                EllesmereUI.BlizzStyle.Gate("cdmicons", { type="dropdown", text="Border Style",
                  disabled=function() return IsCustomShape() end,
                  disabledTooltip="This option requires a non-custom button shape",
                  values=texValues, order=texOrder,
                  getValue=function() return BD().borderTexture or "solid" end,
                  setValue=function(v)
                      local bd = BD()
                      bd.borderTexture = v; bd.borderTextureOffset = nil; bd.borderTextureOffsetY = nil; bd.borderTextureShiftX = nil; bd.borderTextureShiftY = nil
                      local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      bd.borderR = _bcol.r; bd.borderG = _bcol.g; bd.borderB = _bcol.b; bd.borderA = 1
                      bd.borderClassColor = false
                      bd.borderBehind = _bbehind
                      local defTh = EllesmereUI.GetBorderDefaultSize("cdm", v)
                      -- An unregistered SharedMedia border defaults to the NUMBER 1: store its label.
                      if type(defTh) == "number" then defTh = EllesmereUI.BORDER_LABEL_OF_STEP[defTh] or "thin" end
                      if defTh then
                          bd.borderThickness = defTh; bd.borderSize = BORDER_SIZES[defTh] or 1
                      end
                      if bd.borderSizePx then bd.borderSizePx = false end
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                      EllesmereUI:RefreshPage(true)
                  end }));  y = y - h
            -- Width Offset | Height Offset: the textured border's outward offsets,
            -- present only while a textured style is selected (built on the
            -- prebuild pass too, so the y advance is identical). Disabled under a
            -- custom shape exactly like the Border Style dropdown it belongs to.
            do
                local tex0 = BD().borderTexture or "solid"
                if tex0 ~= "" and tex0 ~= "solid" then
                    local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                        addonKey = "cdm",
                        disabled = function() return IsCustomShape() end,
                        disabledTooltip = "This option requires a non-custom button shape",
                        getTex = function() return BD().borderTexture or "solid" end,
                        getStep = function() return BD().borderSize or 1 end,
                        getSizeKey = function() return BD().borderThickness or "thin" end,
                        getPx = function() return BD().borderSizePx end,
                        getX = function() return BD().borderTextureOffset end,
                        setX = function(v) BD().borderTextureOffset = v end,
                        getY = function() return BD().borderTextureOffsetY end,
                        setY = function(v) BD().borderTextureOffsetY = v end,
                        apply = function() ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview() end,
                    })
                    _, h = W:DualRow(parent, y,
                        EllesmereUI.BlizzStyle.Gate("cdmicons", ocfgL),
                        EllesmereUI.BlizzStyle.Gate("cdmicons", ocfgR));  y = y - h
                end
            end
            -- Inline cog for border offset
            if not EllesmereUI._prebuilding then
                local rgn = buffBsRow._rightRegion
                local cogBtn = EllesmereUI.BuildInlineCog(rgn, {
                    icon = EllesmereUI.DIRECTIONS_ICON,
                    title = "Border Options",
                    rows = {
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local v = BD().borderTextureShiftX
                              if v then return v end
                              local bd = BD()
                              local tex = bd.borderTexture or "solid"
                              local th = bd.borderThickness or "thin"
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("cdm", tex, th)
                              return dsx
                          end,
                          set = function(v)
                              BD().borderTextureShiftX = v == 0 and nil or v
                              ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local v = BD().borderTextureShiftY
                              if v then return v end
                              local bd = BD()
                              local tex = bd.borderTexture or "solid"
                              local th = bd.borderThickness or "thin"
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("cdm", tex, th)
                              return dsy
                          end,
                          set = function(v)
                              BD().borderTextureShiftY = v == 0 and nil or v
                              ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                          end },
                        { type = "toggle", label = "Show Behind",
                          get = function() return BD().borderBehind or false end,
                          set = function(v)
                              BD().borderBehind = v == false and nil or v
                              ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                          end },
                    },
                })
                local function UpdateCogVis()
                    local tex = BD().borderTexture or "solid"
                    if tex == "solid" or EllesmereUI.BlizzStyle.Get("cdmicons") then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Inline border color swatches on Border Size (left region of row 4)
            if not EllesmereUI._prebuilding then
                local leftRgn = buffBsRow._leftRegion
                local ctrl = leftRgn._control

                local classBorderSwatch, updateClassBorderSwatch = EllesmereUI.BuildColorSwatch(
                    leftRgn, buffBsRow:GetFrameLevel() + 3,
                    function()
                        local _, classFile = UnitClass("player")
                        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                        if cc then return cc.r, cc.g, cc.b end
                        return 1, 1, 1
                    end,
                    function() end,
                    false, 20)
                PP.Point(classBorderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                classBorderSwatch:SetScript("OnClick", function()
                    if EllesmereUI.BlizzStyle.Get("cdmicons") then return end
                    BD().borderClassColor = true
                    ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                    EllesmereUI:RefreshPage()
                end)
                classBorderSwatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(classBorderSwatch, "Class Colored")
                end)
                classBorderSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                local UpdateBorderState
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    leftRgn, buffBsRow:GetFrameLevel() + 3,
                    function() return BD().borderR or 0, BD().borderG or 0, BD().borderB or 0 end,
                    function(r, g, b)
                        -- Picking a color always switches off class color so the chosen custom color actually applies.
                        BD().borderClassColor = false
                        BD().borderR, BD().borderG, BD().borderB = r, g, b
                        ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                    end,
                    false, 20)
                PP.Point(swatch, "RIGHT", classBorderSwatch, "LEFT", -8, 0)
                swatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, "Custom Colored")
                end)
                swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Clicking the custom swatch switches class color off AND opens
                -- the color picker in the same click (a toggle-only first click
                -- leaves the border black and the swatch looking stuck).
                local origClick = swatch:GetScript("OnClick")
                swatch:SetScript("OnClick", function(self, ...)
                    -- No border selected (or Blizzard Style): don't open the color picker
                    if (BD().borderThickness or "thin") == "none" or EllesmereUI.BlizzStyle.Get("cdmicons") then return end
                    if BD().borderClassColor then
                        BD().borderClassColor = false
                        ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                        updateSwatch(); UpdateBorderState()
                    end
                    if origClick then origClick(self, ...) end
                end)

                function UpdateBorderState()
                    local isClassColored = BD().borderClassColor
                    local isNone = (BD().borderThickness or "thin") == "none" or EllesmereUI.BlizzStyle.Get("cdmicons")
                    swatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
                    classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); updateClassBorderSwatch(); UpdateBorderState() end)
                UpdateBorderState()
            end
            -- Sync icon: Border Size (left region)
            if not EllesmereUI._prebuilding then
            EllesmereUI.BuildSyncIcon({
                region  = buffBsRow._leftRegion,
                tooltip = "Apply Border Size to all Bars",
                isSynced = function()
                    local bd = BD()
                    local v = bd.borderThickness or "thin"
                    local px = bd.borderSizePx or false
                    local cc = bd.borderClassColor
                    local synced = true
                    ForEachSyncBar(function(b) if (b.borderThickness or "thin") ~= v or (b.borderSizePx or false) ~= px or b.borderClassColor ~= cc then synced = false end end)
                    return synced
                end,
                onClick = function()
                    local bd = BD()
                    local v = bd.borderThickness or "thin"
                    local sz = bd.borderSize or 1
                    local px = bd.borderSizePx
                    local cc = bd.borderClassColor
                    ForEachSyncBar(function(b)
                        b.borderThickness = v; b.borderSize = sz
                        local pxv = px
                        if pxv == nil and b.borderSizePx ~= nil then pxv = false end
                        b.borderSizePx = pxv
                        b.borderClassColor = cc
                    end)
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                end,
            })
            end
            -- Sync icon: Border Style (right region)
            if not EllesmereUI._prebuilding then
            EllesmereUI.BuildSyncIcon({
                region  = buffBsRow._rightRegion,
                tooltip = "Apply Border Style to all Bars",
                onClick = function()
                    local bd = BD()
                    local bt = bd.borderTexture or "solid"
                    local ox = bd.borderTextureOffset
                    local oy = bd.borderTextureOffsetY
                    local sx = bd.borderTextureShiftX
                    local sy = bd.borderTextureShiftY
                    local th = bd.borderThickness or "thin"
                    local sz = bd.borderSize or 1
                    local px = bd.borderSizePx
                    local bh = bd.borderBehind
                    local br, bg, bb, ba = bd.borderR, bd.borderG, bd.borderB, bd.borderA
                    local cc = bd.borderClassColor
                    ForEachSyncBar(function(b)
                        b.borderTexture = bt
                        b.borderTextureOffset = ox
                        b.borderTextureOffsetY = oy
                        b.borderTextureShiftX = sx
                        b.borderTextureShiftY = sy
                        b.borderThickness = th; b.borderSize = sz
                        local pxv = px
                        if pxv == nil and b.borderSizePx ~= nil then pxv = false end
                        b.borderSizePx = pxv
                        b.borderBehind = bh
                        b.borderR = br; b.borderG = bg; b.borderB = bb; b.borderA = ba
                        b.borderClassColor = cc
                    end)
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local bd = BD()
                    local bt = bd.borderTexture or "solid"
                    local ox = bd.borderTextureOffset
                    local oy = bd.borderTextureOffsetY
                    local sx = bd.borderTextureShiftX
                    local sy = bd.borderTextureShiftY
                    local bh = bd.borderBehind or false
                    local synced = true
                    ForEachSyncBar(function(b)
                        if (b.borderTexture or "solid") ~= bt then synced = false end
                        if b.borderTextureOffset ~= ox or b.borderTextureOffsetY ~= oy then synced = false end
                        if b.borderTextureShiftX ~= sx or b.borderTextureShiftY ~= sy then synced = false end
                        if (b.borderBehind or false) ~= bh then synced = false end
                    end)
                    return synced
                end,
            })
            end
        end

    else
    local icsWDis2, icsWTip2 = EllesmereUI.MatchGuard("CDM_" .. barKey, "Width")
    local icsHDis2, icsHTip2 = EllesmereUI.MatchGuard("CDM_" .. barKey, "Height")
    local icsDis2 = function() return icsWDis2() or icsHDis2() end
    local icsTip2 = function() if icsWDis2() then return icsWTip2() end if icsHDis2() then return icsHTip2() end return false end
    scaleAnimRow, h = W:DualRow(parent, y,
        { type="slider", text="Icon Scale",
          min=16, max=100, step=1,
          disabled=icsDis2, disabledTooltip=icsTip2, rawTooltip=true,
          getValue=function() return BD().iconSize or 36 end,
          setValue=function(v)
              local bd = BD()
              bd.iconSize = v
              -- Manual iconSize override -- clear ALL match cache so the
              -- new value wins over any stored target width/height.
              bd._matchPhysWidth = nil
              bd._matchPhysHeight = nil
              bd._matchIconPhys = nil
              bd._matchExtraPixels = nil
              bd._matchStride = nil
              bd._matchExtraPixelsH = nil
              bd._matchStrideH = nil
              ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
          end },
        { type="slider", pixel=true, text="Icon Spacing",
          min=-10, max=20, step=1,
          getValue=function() return BD().spacing or 2 end,
          setValue=function(v)
              local bd = BD()
              bd.spacing = v
              -- Spacing change invalidates the width/height match cache because the
              -- cached _matchIconPhys was computed against the old spacing -- new
              -- spacing means the icons no longer fit the matched bar dimension.
              bd._matchIconPhys = nil
              bd._matchExtraPixels = nil
              bd._matchStride = nil
              bd._matchExtraPixelsH = nil
              bd._matchStrideH = nil
              ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
          end });  y = y - h

    -- Sync icon on Icon Spacing (right of row 1)
    if not EllesmereUI._prebuilding then
    EllesmereUI.BuildSyncIcon({
        region  = scaleAnimRow._rightRegion,
        tooltip = "Apply Icon Spacing to all Bars",
        isSynced = function()
            local v = BD().spacing or 2
            local synced = true
            ForEachSyncBar(function(b) if (b.spacing or 2) ~= v then synced = false end end)
            return synced
        end,
        onClick = function()
            local v = BD().spacing or 2
            ForEachSyncBar(function(b)
                b.spacing = v
                -- Spacing change invalidates each bar's match cache.
                b._matchIconPhys = nil
                b._matchExtraPixels = nil
                b._matchStride = nil
                b._matchExtraPixelsH = nil
                b._matchStrideH = nil
            end)
            ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize(); EllesmereUI:RefreshPage()
        end,
    })
    end
    end -- isBuffBar else

    -- Inline cog on Icon Scale: Minimum Bar Size (growth-axis icon-slot
    -- reservation, user-directed to live here, not as a Bar Layout row). Placed
    -- AFTER the isBuffGlowBar branch: each side builds its own scaleAnimRow with
    -- Icon Scale in a different slot (right on buff-family rows, left elsewhere).
    -- The slider stays editable: the runtime skips the reservation while the
    -- growth axis is width/height matched, so no MatchGuard lock is needed.
    -- Orientation resolves at build time; the page rebuilds on flips. FocusKick is
    -- excluded: it is nameplate-anchored, nothing matches or anchors to its edges.
    if not isFocusKick then
        local minVert = BD().verticalOrientation == true
        local rgn = isBuffGlowBar and scaleAnimRow._rightRegion or scaleAnimRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.RESIZE_ICON,
            title = minVert and "Minimum Height" or "Minimum Width",
            rows = {
                { type="slider",
                  label=minVert and "Icon Slots Tall (0 = Off)" or "Icon Slots Wide (0 = Off)",
                  min=0, max=20, step=1,
                  get=function() return BD().minSizeIcons or 0 end,
                  set=function(v)
                      if v == 0 then v = nil end
                      local bd = BD()
                      bd.minSizeIcons = v
                      -- Growth-axis extent changed: cached match dims stale.
                      bd._matchIconPhys = nil
                      bd._matchExtraPixels = nil
                      bd._matchStride = nil
                      bd._matchExtraPixelsH = nil
                      bd._matchStrideH = nil
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                  end },
            },
        })
    end

    -- Border Style dropdown (CD/utility and non-buff bars only)
    if not isBuffGlowBar then
    do
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local bsRow
        -- Border Size: the exact-size slider, except under a custom shape, whose
        -- ring is on (Strong) or off (None): that keeps the None..Strong dropdown.
        local sizeCfg
        if IsCustomShape() then
            sizeCfg = { type="dropdown", text="Border Size",
              values=BORDER_LABELS, order=BORDER_ORDER,
              itemDisabled=function(val)
                  if IsCustomShape() and (val == "thin" or val == "normal" or val == "heavy") then return true end
                  return false
              end,
              itemDisabledTooltip=function(val)
                  if IsCustomShape() and (val == "thin" or val == "normal" or val == "heavy") then
                      return "This option requires a non-custom shape to be selected"
                  end
              end,
              getValue=function() return BD().borderThickness or "thin" end,
              setValue=function(v)
                  BD().borderThickness = v; BD().borderSize = BORDER_SIZES[v] or 1
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
              end }
        else
            sizeCfg = EllesmereUI.BorderPxSliderCfg({ text="Border Size",
              getStep=function() return BD().borderSize or 1 end,
              setStep=function(step)
                  local bd = BD()
                  bd.borderThickness = EllesmereUI.BORDER_LABEL_OF_STEP[step] or "thin"; bd.borderSize = step
              end,
              getTex=function() return BD().borderTexture or "solid" end,
              getPx=function() return BD().borderSizePx end,
              setPx=function(v) BD().borderSizePx = v end,
              apply=function() ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview() end,
            })
        end
        bsRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("cdmicons", { type="dropdown", text="Border Style",
              disabled=function() return IsCustomShape() end,
              disabledTooltip="This option requires a non-custom button shape",
              values=texValues, order=texOrder,
              getValue=function() return BD().borderTexture or "solid" end,
              setValue=function(v)
                  local bd = BD()
                  bd.borderTexture = v; bd.borderTextureOffset = nil; bd.borderTextureOffsetY = nil; bd.borderTextureShiftX = nil; bd.borderTextureShiftY = nil
                  local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  bd.borderR = _bcol.r; bd.borderG = _bcol.g; bd.borderB = _bcol.b; bd.borderA = 1
                  bd.borderClassColor = false
                  bd.borderBehind = _bbehind
                  local defTh = EllesmereUI.GetBorderDefaultSize("cdm", v)
                  -- An unregistered SharedMedia border defaults to the NUMBER 1: store its label.
                  if type(defTh) == "number" then defTh = EllesmereUI.BORDER_LABEL_OF_STEP[defTh] or "thin" end
                  if defTh then
                      bd.borderThickness = defTh; bd.borderSize = BORDER_SIZES[defTh] or 1
                  end
                  if bd.borderSizePx then bd.borderSizePx = false end
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                  EllesmereUI:RefreshPage(true)
              end }),
            EllesmereUI.BlizzStyle.Gate("cdmicons", sizeCfg));  y = y - h
        -- Width Offset | Height Offset: the textured border's outward offsets,
        -- present only while a textured style is selected (built on the
        -- prebuild pass too, so the y advance is identical). Disabled under a
        -- custom shape exactly like the Border Style dropdown it belongs to.
        do
            local tex0 = BD().borderTexture or "solid"
            if tex0 ~= "" and tex0 ~= "solid" then
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "cdm",
                    disabled = function() return IsCustomShape() end,
                    disabledTooltip = "This option requires a non-custom button shape",
                    getTex = function() return BD().borderTexture or "solid" end,
                    getStep = function() return BD().borderSize or 1 end,
                    getSizeKey = function() return BD().borderThickness or "thin" end,
                    getPx = function() return BD().borderSizePx end,
                    getX = function() return BD().borderTextureOffset end,
                    setX = function(v) BD().borderTextureOffset = v end,
                    getY = function() return BD().borderTextureOffsetY end,
                    setY = function(v) BD().borderTextureOffsetY = v end,
                    apply = function() ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview() end,
                })
                _, h = W:DualRow(parent, y,
                    EllesmereUI.BlizzStyle.Gate("cdmicons", ocfgL),
                    EllesmereUI.BlizzStyle.Gate("cdmicons", ocfgR));  y = y - h
            end
        end
        -- Inline cog for border offset
        if not EllesmereUI._prebuilding then
            local rgn = bsRow._leftRegion
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Border Options",
                rows = {
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = BD().borderTextureShiftX
                          if v then return v end
                          local bd = BD()
                          local tex = bd.borderTexture or "solid"
                          local th = bd.borderThickness or "thin"
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("cdm", tex, th)
                          return dsx
                      end,
                      set = function(v)
                          BD().borderTextureShiftX = v == 0 and nil or v
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                      end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = BD().borderTextureShiftY
                          if v then return v end
                          local bd = BD()
                          local tex = bd.borderTexture or "solid"
                          local th = bd.borderThickness or "thin"
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("cdm", tex, th)
                          return dsy
                      end,
                      set = function(v)
                          BD().borderTextureShiftY = v == 0 and nil or v
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                      end },
                    { type = "toggle", label = "Show Behind",
                      get = function() return BD().borderBehind or false end,
                      set = function(v)
                          BD().borderBehind = v == false and nil or v
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                      end },
                },
            })
            local function UpdateCogVis()
                local tex = BD().borderTexture or "solid"
                if tex == "solid" or EllesmereUI.BlizzStyle.Get("cdmicons") then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
        -- Sync icon: Border Style (left region of bsRow)
        if not EllesmereUI._prebuilding then
        EllesmereUI.BuildSyncIcon({
            region  = bsRow._leftRegion,
            tooltip = "Apply Border Style to all Bars",
            onClick = function()
                local bd = BD()
                local bt = bd.borderTexture or "solid"
                local ox = bd.borderTextureOffset
                local oy = bd.borderTextureOffsetY
                local sx = bd.borderTextureShiftX
                local sy = bd.borderTextureShiftY
                local th = bd.borderThickness or "thin"
                local sz = bd.borderSize or 1
                local px = bd.borderSizePx
                local bh = bd.borderBehind
                local br, bg, bb, ba = bd.borderR, bd.borderG, bd.borderB, bd.borderA
                local cc = bd.borderClassColor
                ForEachSyncBar(function(b)
                    b.borderTexture = bt
                    b.borderTextureOffset = ox; b.borderTextureOffsetY = oy
                    b.borderTextureShiftX = sx; b.borderTextureShiftY = sy
                    b.borderThickness = th; b.borderSize = sz
                        local pxv = px
                        if pxv == nil and b.borderSizePx ~= nil then pxv = false end
                        b.borderSizePx = pxv
                    b.borderBehind = bh
                    b.borderR = br; b.borderG = bg; b.borderB = bb; b.borderA = ba
                    b.borderClassColor = cc
                end)
                ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local bd = BD()
                local bt = bd.borderTexture or "solid"
                local ox = bd.borderTextureOffset
                local oy = bd.borderTextureOffsetY
                local sx = bd.borderTextureShiftX
                local sy = bd.borderTextureShiftY
                local bh = bd.borderBehind or false
                local synced = true
                ForEachSyncBar(function(b)
                    if (b.borderTexture or "solid") ~= bt then synced = false end
                    if b.borderTextureOffset ~= ox or b.borderTextureOffsetY ~= oy then synced = false end
                    if b.borderTextureShiftX ~= sx or b.borderTextureShiftY ~= sy then synced = false end
                    if (b.borderBehind or false) ~= bh then synced = false end
                end)
                return synced
            end,
        })
        end
        -- Inline color swatches on Border Size (right region)
        if not EllesmereUI._prebuilding then
            local rightRgn = bsRow._rightRegion
            local ctrl = rightRgn._control

            -- Class color swatch (rightmost)
            local classBorderSwatch, updateClassBorderSwatch = EllesmereUI.BuildColorSwatch(
                rightRgn, bsRow:GetFrameLevel() + 3,
                function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end,
                false, 20)
            PP.Point(classBorderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            classBorderSwatch:SetScript("OnClick", function()
                if EllesmereUI.BlizzStyle.Get("cdmicons") then return end
                BD().borderClassColor = true
                ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                EllesmereUI:RefreshPage()
            end)
            classBorderSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(classBorderSwatch, "Class Colored")
            end)
            classBorderSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Custom color swatch (left of class swatch)
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rightRgn, bsRow:GetFrameLevel() + 3,
                function() return BD().borderR or 0, BD().borderG or 0, BD().borderB or 0 end,
                function(r, g, b)
                    BD().borderR, BD().borderG, BD().borderB = r, g, b
                    ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                end,
                false, 20)
            PP.Point(swatch, "RIGHT", classBorderSwatch, "LEFT", -8, 0)
            swatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, "Custom Color")
            end)
            swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Click the dimmed custom swatch to switch back from class color (no block overlay)
            local origClick = swatch:GetScript("OnClick")
            swatch:SetScript("OnClick", function(self, ...)
                if EllesmereUI.BlizzStyle.Get("cdmicons") then return end
                if BD().borderClassColor then
                    BD().borderClassColor = false
                    ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                    EllesmereUI:RefreshPage()
                    return
                end
                -- No border selected: allow swapping boxes but do not open the color picker
                if (BD().borderThickness or "thin") == "none" then return end
                if origClick then origClick(self, ...) end
            end)

            local function UpdateBorderSwatchState()
                local isClassColored = BD().borderClassColor
                local isNone = (BD().borderThickness or "thin") == "none" or EllesmereUI.BlizzStyle.Get("cdmicons")
                swatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
                classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); updateClassBorderSwatch(); UpdateBorderSwatchState() end)
            UpdateBorderSwatchState()
        end
        -- Sync icon on Border Size (right region)
        if not EllesmereUI._prebuilding then
        EllesmereUI.BuildSyncIcon({
            region  = bsRow._rightRegion,
            tooltip = "Apply Border Size to all Bars",
            isSynced = function()
                local bd = BD()
                local v = bd.borderThickness or "thin"
                local px = bd.borderSizePx or false
                local cc = bd.borderClassColor
                local bt = bd.borderTexture or "solid"
                local sx = bd.borderTextureShiftX
                local sy = bd.borderTextureShiftY
                local br, bg, bb, ba = bd.borderR or 0, bd.borderG or 0, bd.borderB or 0, bd.borderA or 1
                local synced = true
                ForEachSyncBar(function(b)
                    if (b.borderThickness or "thin") ~= v or (b.borderSizePx or false) ~= px or b.borderClassColor ~= cc or (b.borderTexture or "solid") ~= bt then synced = false end
                    if b.borderTextureShiftX ~= sx or b.borderTextureShiftY ~= sy then synced = false end
                    if (b.borderR or 0) ~= br or (b.borderG or 0) ~= bg or (b.borderB or 0) ~= bb or (b.borderA or 1) ~= ba then synced = false end
                end)
                return synced
            end,
            onClick = function()
                local bd = BD()
                local v = bd.borderThickness or "thin"
                local sz = bd.borderSize or 1
                local px = bd.borderSizePx
                local cc = bd.borderClassColor
                local bt = bd.borderTexture or "solid"
                local sx = bd.borderTextureShiftX
                local sy = bd.borderTextureShiftY
                local br, bg, bb, ba = bd.borderR, bd.borderG, bd.borderB, bd.borderA
                ForEachSyncBar(function(b)
                    b.borderThickness = v; b.borderSize = sz
                        local pxv = px
                        if pxv == nil and b.borderSizePx ~= nil then pxv = false end
                        b.borderSizePx = pxv
                    b.borderClassColor = cc; b.borderTexture = bt
                    b.borderTextureShiftX = sx; b.borderTextureShiftY = sy
                    b.borderR = br; b.borderG = bg; b.borderB = bb; b.borderA = ba
                end)
                ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
            end,
        })
        end
    end
    end -- not isBuffGlowBar

    -- (Active Animation UI removed -- active state is now per-icon via spell picker dropdown)

    -- (Sync) Custom Icon Shape | (Sync) Icon Zoom (CD/utility bars only;
    -- buff bars have both in their own Row 3 above)
    if not isBuffGlowBar then
    local shapeRow
    shapeRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("cdmicons", { type="dropdown", text="Custom Icon Shape",
            values=SHAPE_VALUES, order=SHAPE_ORDER,
            itemDisabled=function(val)
                if val ~= "none" and val ~= "cropped" and (BD().borderTexture or "solid") ~= "solid" then return true end
                return false
            end,
            itemDisabledTooltip=function(val)
                if val ~= "none" and val ~= "cropped" and (BD().borderTexture or "solid") ~= "solid" then
                    return "This option requires the Border Style to be set to Solid"
                end
            end,
            getValue=function() return BD().iconShape or "none" end,
            setValue=function(v)
                local bd = BD()
                bd.iconShape = v
                bd.iconZoom = ns.CDM_SHAPE_ZOOM_DEFAULTS[v] or 0.08
                local isCS = (v ~= "none" and v ~= "cropped")
                if isCS then
                    bd.borderThickness = "strong"; bd.borderSize = BORDER_SIZES["strong"]
                    bd.activeStateAnim = "blizzard"
                else
                    bd.borderThickness = "thin"; bd.borderSize = BORDER_SIZES["thin"]
                end
                bd._matchIconPhys = nil
                bd._matchExtraPixels = nil
                bd._matchStride = nil
                bd._matchExtraPixelsH = nil
                bd._matchStrideH = nil
                ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                -- The Border Size slot is a different control under a custom shape: rebuild the page.
                EllesmereUI:RefreshPage(true)
            end }),
        EllesmereUI.BlizzStyle.Gate("cdmicons", { type="slider", text="Icon Zoom",
            min=0, max=0.20, step=0.01,
            getValue=function() return BD().iconZoom or 0.08 end,
            setValue=function(v)
                BD().iconZoom = v
                ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
            end }));  y = y - h

    AttachCropCog(shapeRow._leftRegion)

    if not EllesmereUI._prebuilding then
    EllesmereUI.BuildSyncIcon({
        region  = shapeRow._leftRegion,
        tooltip = "Apply Icon Shape to all Bars",
        isSynced = function()
            local bd = BD()
            local v = bd.iconShape or "none"
            local zoom = bd.iconZoom or 0.08
            local crop = ns.CdmCropPercent(bd)
            local synced = true
            ForEachSyncBar(function(b) if (b.iconShape or "none") ~= v or (b.iconZoom or 0.08) ~= zoom or ns.CdmCropPercent(b) ~= crop then synced = false end end)
            return synced
        end,
        onClick = function()
            local bd = BD()
            local v = bd.iconShape or "none"
            local zoom = bd.iconZoom or 0.08
            local crop = bd.iconCropPercent
            ForEachSyncBar(function(b)
                b.iconShape = v; b.iconZoom = zoom; b.iconCropPercent = crop
                local isCS = (v ~= "none" and v ~= "cropped")
                if isCS then b.borderThickness = "strong"; b.borderSize = BORDER_SIZES["strong"]
                else b.borderThickness = "thin"; b.borderSize = BORDER_SIZES["thin"] end
                b._matchIconPhys = nil
                b._matchExtraPixels = nil
                b._matchStride = nil
                b._matchExtraPixelsH = nil
                b._matchStrideH = nil
            end)
            ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize(); EllesmereUI:RefreshPage()
        end,
    })
    end
    if not EllesmereUI._prebuilding then
    EllesmereUI.BuildSyncIcon({
        region  = shapeRow._rightRegion,
        tooltip = "Apply Icon Zoom to all Bars",
        isSynced = function()
            local v = BD().iconZoom or 0.08
            local synced = true
            ForEachSyncBar(function(b) if (b.iconZoom or 0.08) ~= v then synced = false end end)
            return synced
        end,
        onClick = function()
            local v = BD().iconZoom or 0.08
            ForEachSyncBar(function(b) b.iconZoom = v end)
            ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
        end,
    })
    end
    end -- not isBuffGlowBar

    -- Row 4: Duration Size (swatch + cog) | Stack Size (swatch + cog)
    local durationRow
    durationRow, h = W:DualRow(parent, y,
        { type="slider", text="Duration Size",
          min=6, max=30, step=1, trackWidth=120,
          getValue=function() return BD().cooldownFontSize or 12 end,
          setValue=function(v)
              BD().cooldownFontSize = v
              ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
          end },
        { type="slider", text="Charge/Stack Size",
          min=6, max=30, step=1, trackWidth=120,
          getValue=function() return BD().stackCountSize or 11 end,
          setValue=function(v)
              BD().stackCountSize = v
              ns.RefreshCDMIconAppearance(BD().key); ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
          end }
    );  y = y - h

    -- Duration Size: inline color swatch + cog
    if not EllesmereUI._prebuilding then
        local leftRgn = durationRow._leftRegion
        local ctrl = leftRgn._control
        local durSwatch, updateDurSwatch = EllesmereUI.BuildColorSwatch(
            leftRgn, durationRow:GetFrameLevel() + 3,
            function() return BD().cooldownTextR or 1, BD().cooldownTextG or 1, BD().cooldownTextB or 1 end,
            function(r, g, b)
                BD().cooldownTextR = r; BD().cooldownTextG = g; BD().cooldownTextB = b
                ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
            end,
            false, 20)
        PP.Point(durSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
        leftRgn._lastInline = durSwatch

        local durBlock = CreateFrame("Frame", nil, durSwatch)
        durBlock:SetAllPoints(); durBlock:SetFrameLevel(durSwatch:GetFrameLevel() + 10); durBlock:EnableMouse(true)
        durBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(durSwatch, EllesmereUI.DisabledTooltip("Duration Text"))
        end)
        durBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            if updateDurSwatch then updateDurSwatch() end
            local on = BD().showCooldownText ~= false
            durSwatch:SetAlpha(on and 1 or 0.3)
            if on then durBlock:Hide() else durBlock:Show() end
        end)
        local on = BD().showCooldownText ~= false
        durSwatch:SetAlpha(on and 1 or 0.3)
        if on then durBlock:Hide() else durBlock:Show() end

        EllesmereUI.BuildInlineCog(leftRgn, { anchorTo = durSwatch, icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Duration Text",
            rows = {
                { type="toggle", label="Show Duration",
                  get=function() return BD().showCooldownText ~= false end,
                  set=function(v)
                      BD().showCooldownText = v
                      ns.RefreshCDMIconAppearance(BD().key); Refresh(); EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", label="Position",
                  values=durationPositionValues, order=durationPositionOrder,
                  get=function() return BD().cooldownTextPosition or "center" end,
                  set=function(v)
                      BD().cooldownTextPosition = v
                      ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                  end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return BD().cooldownTextX or 0 end,
                  set=function(v)
                      BD().cooldownTextX = v
                      ns.RefreshCDMIconAppearance(BD().key); Refresh()
                  end },
                { type="slider", label="Y Offset", min=-50, max=50, step=1,
                  get=function() return BD().cooldownTextY or 0 end,
                  set=function(v)
                      BD().cooldownTextY = v
                      ns.RefreshCDMIconAppearance(BD().key); Refresh()
                  end },
            },
        })
    end

    -- Stack Size: inline color swatch + cog
    if not EllesmereUI._prebuilding then
        local rightRgn = durationRow._rightRegion
        local ctrl = rightRgn._control
        local scSwatch, updateScSwatch = EllesmereUI.BuildColorSwatch(
            rightRgn, durationRow:GetFrameLevel() + 3,
            function() return BD().stackCountR or 1, BD().stackCountG or 1, BD().stackCountB or 1 end,
            function(r, g, b)
                BD().stackCountR = r; BD().stackCountG = g; BD().stackCountB = b
                ns.RefreshCDMIconAppearance(BD().key); ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
            end,
            false, 20)
        PP.Point(scSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
        rightRgn._lastInline = scSwatch

        local scBlock = CreateFrame("Frame", nil, scSwatch)
        scBlock:SetAllPoints(); scBlock:SetFrameLevel(scSwatch:GetFrameLevel() + 10); scBlock:EnableMouse(true)
        scBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(scSwatch, EllesmereUI.DisabledTooltip("Item Count"))
        end)
        scBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            if updateScSwatch then updateScSwatch() end
            local on = BD().showItemCount ~= false
            scSwatch:SetAlpha(on and 1 or 0.3)
            if on then scBlock:Hide() else scBlock:Show() end
        end)
        local on = BD().showItemCount ~= false
        scSwatch:SetAlpha(on and 1 or 0.3)
        if on then scBlock:Hide() else scBlock:Show() end

        local scPopupSpec = {
            title = "Charges/Stacks",
            rows = {
                -- View over the legacy showItemCount boolean (Never = false,
                -- Always = true/nil) plus the itemCountOOC flag for the new
                -- Out of Combat mode. OOC keeps showItemCount = true so every
                -- legacy reader treats it as "on"; the combat gate lives in
                -- the icon restyle. Zero migration.
                { type="dropdown", label="Show Item Count",
                  values={ never="Never", always="Always", ooc="Out of Combat" },
                  order={ "never", "always", "ooc" },
                  get=function()
                      if BD().itemCountOOC then return "ooc" end
                      return (BD().showItemCount ~= false) and "always" or "never"
                  end,
                  set=function(v)
                      local bd = BD()
                      bd.itemCountOOC = (v == "ooc") or nil
                      bd.showItemCount = (v ~= "never")
                      ns.RefreshCDMIconAppearance(bd.key); ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                  end },
                -- Crafted-rank pip on tracked items (ranks share icon art, so
                -- two ranks are otherwise indistinguishable). Off by default.
                { type="toggle", label="Show Item Quality",
                  tooltip="Show the crafted quality rank on tracked items, matching the rank icon on the action bars. Items with no crafted quality are unaffected.",
                  get=function() return BD().showItemQuality == true end,
                  set=function(v)
                      BD().showItemQuality = v
                      if ns.FullCDMRebuild then ns.FullCDMRebuild("item_quality_toggle") end
                  end },
                -- Buff-family only (stripped below for cd/utility): those
                -- bars hide counters via the per-spell Hide Charge Text
                -- lane, which owns their counter alpha channel.
                { type="toggle", label="Show Charge/Stack Text",
                  tooltip="Show the charge and stack counters on this bar's icons.",
                  get=function() return BD().showChargeStackText ~= false end,
                  -- if/else, NOT `v and nil or false`: that expression is
                  -- ALWAYS false (the nil arm falls through the or).
                  set=function(v)
                      if v then BD().showChargeStackText = nil
                      else BD().showChargeStackText = false end
                      ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                  end },
                { type="dropdown", label="Position",
                  values={ bottomright="Bottom Right", bottom="Bottom", bottomleft="Bottom Left", left="Left", topleft="Top Left", top="Top", topright="Top Right", right="Right", center="Center" },
                  order={ "bottomright", "bottom", "bottomleft", "left", "topleft", "top", "topright", "right", "center" },
                  get=function() return BD().stackCountPosition or "bottomright" end,
                  set=function(v)
                      BD().stackCountPosition = v
                      ns.RefreshCDMIconAppearance(BD().key); ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                  end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return BD().stackCountX or 0 end,
                  set=function(v)
                      BD().stackCountX = v
                      ns.RefreshCDMIconAppearance(BD().key); ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                  end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return BD().stackCountY or 0 end,
                  set=function(v)
                      BD().stackCountY = v
                      ns.RefreshCDMIconAppearance(BD().key); ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                  end },
            },
        }
        -- Show Charge/Stack Text (row 3) is buff-family only -- see its comment.
        if not isBuffGlowBar then table.remove(scPopupSpec.rows, 3) end
        scPopupSpec.icon, scPopupSpec.anchorTo = EllesmereUI.DIRECTIONS_ICON, scSwatch
        EllesmereUI.BuildInlineCog(rightRgn, scPopupSpec)
    end

    -- Suppress GCD (CD/utility bars only) | Pixel Glow Thickness (+ cog: Lines/Speed)
    if not isBuffGlowBar then
    if ns.CDM_BarHasPixelRow(barData) then
        local sgcdRow
        sgcdRow, h = W:DualRow(parent, y,
            { type="toggle", text="Suppress GCD",
              tooltip="Hide the brief GCD swipe that flashes when you cast any spell. The actual ability cooldown swipe still shows.",
              getValue=function() return BD().suppressGCD == true end,
              setValue=function(v) BD().suppressGCD = v and true or false; Refresh() end },
            { type="slider", text="Pixel Glow Thickness", min=1, max=4, step=1, trackWidth=120,
              tooltip="Thickness of any Pixel Glow assigned to this bar's buttons. Assign glows by right-clicking an icon in the preview.",
              getValue=function() return BD().pixelGlowThickness or 2 end,
              setValue=function(v)
                  BD().pixelGlowThickness = v
                  ns.BuildAllCDMBars(); if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end; Refresh()
              end });  y = y - h
        -- Inline cog on Pixel Glow Thickness: Lines + Speed
        if not EllesmereUI._prebuilding then
            local rightRgn = sgcdRow._rightRegion
            EllesmereUI.BuildInlineCog(rightRgn, { icon = EllesmereUI.RESIZE_ICON,
                title = "Pixel Glow",
                rows = {
                    { type="slider", label="Lines", min=2, max=16, step=1,
                      get=function() return BD().pixelGlowLines or 8 end,
                      set=function(v)
                          BD().pixelGlowLines = v
                          ns.BuildAllCDMBars(); if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end
                      end },
                    { type="slider", label="Speed", min=1, max=8, step=1,
                      get=function() return 9 - (BD().pixelGlowSpeed or 4) end,
                      set=function(v)
                          BD().pixelGlowSpeed = 9 - v
                          ns.BuildAllCDMBars(); if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end
                      end },
                    { type="toggle", label="Background",
                      get=function() return BD().pixelGlowBackground == true end,
                      set=function(v)
                          BD().pixelGlowBackground = v and true or nil
                          ns.BuildAllCDMBars(); if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end
                      end },
                    { type="colorpicker", label="Background Color",
                      get=function() return BD().pixelGlowBackgroundR or 0, BD().pixelGlowBackgroundG or 0, BD().pixelGlowBackgroundB or 0 end,
                      set=function(r, g, b)
                          BD().pixelGlowBackgroundR = r; BD().pixelGlowBackgroundG = g; BD().pixelGlowBackgroundB = b
                          ns.BuildAllCDMBars(); if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end
                      end,
                      disabled=function() return BD().pixelGlowBackground ~= true end,
                      disabledTooltip="Pixel Glow Background" },
                },
            })
        end
    end
    end

    -- Pixel Glow Thickness (buff bars) -- mirrors the CD/utility row above.
    -- Reuses the same buffGlow* variables so user settings are unchanged.
    -- Always enabled (no disabled state).
    if isBuffGlowBar then
        local pgRow
        pgRow, h = W:DualRow(parent, y,
            { type="slider", text="Pixel Glow Thickness", min=1, max=4, step=1, trackWidth=120,
              tooltip="Thickness of the Pixel Glow applied to this bar's buff icons.",
              getValue=function() return BD().buffGlowThickness or 2 end,
              setValue=function(v)
                  BD().buffGlowThickness = v
                  ns.BuildAllCDMBars(); if ns.RefreshBuffGlows then ns.RefreshBuffGlows() end; Refresh()
              end },
            { type="toggle", text="Only Show Numbers",
              tooltip="Hide this bar's icons and show only the duration text.",
              getValue=function() return BD().onlyShowNumbers == true end,
              setValue=function(v)
                  BD().onlyShowNumbers = v and true or nil
                  ns.BuildAllCDMBars(); Refresh()
              end });  y = y - h
        -- Inline cog on Pixel Glow Thickness: Lines + Speed (buffGlow* vars)
        if not EllesmereUI._prebuilding then
            local leftRgn = pgRow._leftRegion
            EllesmereUI.BuildInlineCog(leftRgn, { icon = EllesmereUI.RESIZE_ICON,
                title = "Pixel Glow",
                rows = {
                    { type="slider", label="Lines", min=2, max=16, step=1,
                      get=function() return BD().buffGlowLines or 8 end,
                      set=function(v)
                          BD().buffGlowLines = v
                          ns.BuildAllCDMBars(); if ns.RefreshBuffGlows then ns.RefreshBuffGlows() end
                      end },
                    { type="slider", label="Speed", min=1, max=8, step=1,
                      get=function() return 9 - (BD().buffGlowSpeed or 4) end,
                      set=function(v)
                          BD().buffGlowSpeed = 9 - v
                          ns.BuildAllCDMBars(); if ns.RefreshBuffGlows then ns.RefreshBuffGlows() end
                      end },
                    { type="toggle", label="Background",
                      get=function() return BD().buffGlowBackground == true end,
                      set=function(v)
                          BD().buffGlowBackground = v and true or nil
                          ns.BuildAllCDMBars(); if ns.RefreshBuffGlows then ns.RefreshBuffGlows() end
                      end },
                    { type="colorpicker", label="Background Color",
                      get=function() return BD().buffGlowBackgroundR or 0, BD().buffGlowBackgroundG or 0, BD().buffGlowBackgroundB or 0 end,
                      set=function(r, g, b)
                          BD().buffGlowBackgroundR = r; BD().buffGlowBackgroundG = g; BD().buffGlowBackgroundB = b
                          ns.BuildAllCDMBars(); if ns.RefreshBuffGlows then ns.RefreshBuffGlows() end
                      end,
                      disabled=function() return BD().buffGlowBackground ~= true end,
                      disabledTooltip="Pixel Glow Background" },
                },
            })
        end
    end

    -- Charges/Stacks Only (cd/utility bars) -- the counterpart to the buff
    -- bars' "Only Show Numbers" above. Strips the icon down to its charge /
    -- stack counter: art, swipe, recharge edge and cooldown text all go.
    if not isBuffGlowBar
       and (barData.barType == "cooldowns" or barData.barType == "utility") then
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Charges/Stacks Only (No Icon)",
              tooltip="Hide this bar's icon art, cooldown swipe, recharge edge and cooldown text, leaving only the charge or stack count.",
              getValue=function() return BD().chargesOnly == true end,
              setValue=function(v)
                  BD().chargesOnly = v and true or nil
                  ns.BuildAllCDMBars(); Refresh()
              end },
            { type="toggle", text="Hide Charge Count at 0",
              tooltip="Hide the charge number while a spell has no charges left, instead of showing a 0. The number returns as soon as a charge comes back.",
              getValue=function() return BD().hideZeroChargeText == true end,
              setValue=function(v)
                  BD().hideZeroChargeText = v and true or nil
                  ns.BuildAllCDMBars(); Refresh()
              end });  y = y - h
    end

    _, h = W:Spacer(parent, y, 8);  y = y - h

    -------------------------------------------------------------------
    --  EXTRAS (not shown for custom aura bars or FocusKick)
    -------------------------------------------------------------------
    local isCustomBuffBar = (barData.barType == "custom_buff")
    local isAnyBuffBar = isBuffGlowBar  -- buffs or custom_buff
    if ns.CDM_BarHasExtras(barData) then
    _, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h

    -- Hide Items if Missing: one config, hosted in a different row per bar
    -- family. Buff bars carry it in the tooltip row's right slot; CD and
    -- utility bars keep it beside Mirror Key Presses further down.
    local hideMissingCfg = { type="toggle", text="Hide Items if Missing",
          tooltip = "Hide consumable items (potions, healthstone) from the bar when you have none in your bags, instead of showing them dimmed. They reappear automatically once you have the item again.",
          getValue=function() return BD().hideItemsIfMissing == true end,
          setValue=function(v)
              BD().hideItemsIfMissing = v
              if ns.FullCDMRebuild then ns.FullCDMRebuild("hide_missing_toggle") end
          end }
    -- Buffs get "Show Tooltip on Hover" only (auras aren't cast -> no keybind);
    -- cooldown/utility icon bars get the Tooltip | Keybind pair below.
    if isAnyBuffBar then
    local _, tth = W:DualRow(parent, y,
        { type="toggle", text="Show Tooltip on Hover",
          getValue=function() return BD().showTooltip == true end,
          setValue=function(v)
              BD().showTooltip = v
              ns.ApplyCDMTooltipState(BD().key)
              Refresh()
          end },
        hideMissingCfg
    );  y = y - tth
    else
    local kbRow
    kbRow, h = W:DualRow(parent, y,
        { type="toggle", text="Show Tooltip on Hover",
          getValue=function() return BD().showTooltip == true end,
          setValue=function(v)
              BD().showTooltip = v
              ns.ApplyCDMTooltipState(BD().key)
              Refresh()
          end },
        { type="toggle", text="Show Keybind",
          getValue=function() return BD().showKeybind == true end,
          setValue=function(v)
              local b = BD()
              b.showKeybind = v
              ns.RefreshCDMIconAppearance(b.key); ns.ApplyCachedKeybinds(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
          end }
    );  y = y - h

    BuildKeybindStyleControls(kbRow, BD, function()
        ns.RefreshCDMIconAppearance(BD().key); ns.ApplyCachedKeybinds()
        UpdateCDMPreview(); EllesmereUI:RefreshPage()
    end)
    end -- if isAnyBuffBar (tooltip only) / else (tooltip + keybind)

    -- Pandemic Glow: the Glows page's descriptor over this bar, with the
    -- preview and the Pixel Glow cog inline and the swatches in the right half.
    do
        local GO = EllesmereUI.GlowOptions
        local panDesc = ns._CDM_PandemicGlowDesc(BD, function() ns.BuildAllCDMBars(); Refresh() end)
        local panGlowRow
        panGlowRow, h = W:DualRow(parent, y,
            GO.DropdownSpec(panDesc, "Pandemic Glow",
                "Show a glow on icons when the remaining duration is in the pandemic window (last 30%)"),
            { type="label", text="Pandemic Glow Color" });  y = y - h

        if not EllesmereUI._prebuilding then
            local leftRgn = panGlowRow._leftRegion
            leftRgn._lastInline = GO.BuildPreview(leftRgn, panDesc, { anchor = leftRgn._control, x = -8 })
            GO.AttachInline(leftRgn, panDesc, panGlowRow._rightRegion)

            if EllesmereUI.BuildSyncIcon and EllesmereUI.ApplyPandemicGlowToAll then
                EllesmereUI.BuildSyncIcon({
                    region = panGlowRow._leftRegion,
                    tooltip = "Apply this pandemic glow to Nameplates, all CDM bars, and tracking bars. A surface that can't show a style uses its closest match.",
                    isSynced = function()
                        return EllesmereUI.IsPandemicGlowSyncedToAll(EllesmereUI.PandemicPayloadFromCdmBar(BD()), { skipCdmKey = barKey })
                    end,
                    onClick = function()
                        EllesmereUI.ApplyPandemicGlowToAll(EllesmereUI.PandemicPayloadFromCdmBar(BD()), { skipCdmKey = barKey })
                        Refresh()
                    end,
                })
            end
        end
    end

    -- Show Non-On Use Trinkets | Show Rotation Helper. Forever has no
    -- Assisted Highlight: there the trinket toggle closes the section
    -- instead (beside Show Glows Only in Combat, or as the odd last slot).
    local trinketCfg = { type="toggle", text="Show Non-On Use Trinkets",
          tooltip = "Show equipped trinkets even if they don't have an on-use effect.",
          getValue=function() return BD().showPassiveTrinkets == true end,
          setValue=function(v)
              BD().showPassiveTrinkets = v
              if ns.FullCDMRebuild then ns.FullCDMRebuild("trinket_toggle") end
          end }
    if not EllesmereUI.IS_FOREVER then
    _, h = W:DualRow(parent, y,
        trinketCfg,
        { type="toggle", text="Show Rotation Helper",
          tooltip = "Highlight Blizzard's next recommended ability on all CDM bars. Requires Assisted Highlight to be enabled in Blizzard's options. Disabling this hides only the CDM highlight.\n\nPress the normal ability's keybind yourself. This does not cast spells or use the Single-Button Assistant, so it does not add that assistant's global cooldown penalty. Only abilities present on your CDM bars can be highlighted.",
          disabled=function() return not ns.RotationAssistAvailable() end,
          disabledTooltip="This option requires Blizzard's Assisted Highlight to be enabled",
          rawTooltip=true,
          getValue=function()
              local p = DB()
              return p and p.cdmBars and not p.cdmBars.hideRotationHelper and ns.RotationAssistAvailable()
          end,
          setValue=function(v)
              local p = DB()
              if p and p.cdmBars then
                  p.cdmBars.hideRotationHelper = not v
                  if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end
                  -- The Style and Thickness rows below exist only while this
                  -- is on (the Glows page rebuilds its listing on every return).
                  EllesmereUI:RefreshPage(true)
              end
          end });  y = y - h
    end -- not IS_FOREVER

    -- Rotation Assist styling is profile-wide (not tied to the selected
    -- bar). Keeping it on this override-eligible page lets the existing
    -- spec/conditional override system capture every scalar below.
    -- Read and write the runtime addon's authoritative profile. The options
    -- DB reference can lag behind a profile/override proxy swap, which made
    -- the swatches display Class while the renderer still read Custom.
    local function RotationBars()
        local runtime = ns.ECME and ns.ECME.db and ns.ECME.db.profile
        local fallback = DB()
        return (runtime and runtime.cdmBars) or (fallback and fallback.cdmBars)
    end
    -- Which of the Thickness / Outset rows the current style reads (the renderer
    -- uses thickness for Solid Border and Pixel Glow, outset for every style but
    -- Blizzard Default): 0 = neither, 1 = outset only, 3 = both. The rows below
    -- exist only for the styles that read them, so the Style dropdown forces a
    -- rebuild when this key flips.
    local function RotRowsKey()
        local c = RotationBars()
        local s = (c and c.rotationAssistStyle) or "blizzard"
        local key = 0
        if s ~= "blizzard" then key = 1 end
        if s == "solid" or s == "pixel" then key = key + 2 end
        return key
    end

    -- Style | Color and Thickness | Outset: built only while the CDM highlight
    -- can show (Show Rotation Helper on, Blizzard's Assisted Highlight on).
    if not ns._CDM_RotationHelperOff() then
    local rotStyleRow
    rotStyleRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Rotation Assist Style",
          values={
              blizzard="Blizzard Default", solid="Solid Border",
              pixel="Pixel Glow", shape="Shape Glow",
              button="Action Button Glow", autocast="Auto-Cast Shine",
              gcd="GCD", modern="Modern WoW Glow", classic="Classic WoW Glow",
          },
          order={ "blizzard", "solid", "pixel", "shape", "button", "autocast", "gcd", "modern", "classic" },
          tooltip="Choose the profile-wide border or glow used for Blizzard's Assisted Combat suggestion.",
          getValue=function()
              local c = RotationBars(); return (c and c.rotationAssistStyle) or "blizzard"
          end,
          setValue=function(v)
              local c = RotationBars()
              if c then
                  local before = RotRowsKey()
                  c.rotationAssistStyle = v
                  if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end
                  -- Full rebuild only when the Thickness / Outset row set changes;
                  -- the in-place refresh otherwise.
                  EllesmereUI:RefreshPage(RotRowsKey() ~= before)
              end
          end },
        { type="label", text="Rotation Assist Color" });  y = y - h

    do
        local colorRgn = rotStyleRow._rightRegion
        if colorRgn and EllesmereUI.BuildTrioColorSwatch then
            -- Same trio as the Pandemic Glow row above. The helper opens the
            -- picker only while custom mode is already active, so a picker
            -- cancel can never flip the mode. Dimmed while Blizzard Default
            -- owns the highlight; clicks are ignored there.
            local function rotColorOff()
                local c = RotationBars()
                return not c or c.rotationAssistStyle == "blizzard"
            end
            local swatch, defaultSwatch, classSwatch = EllesmereUI.BuildTrioColorSwatch(
                colorRgn, rotStyleRow:GetFrameLevel() + 3,
                {
                    getMode = function()
                        local c = RotationBars()
                        return (c and c.rotationAssistColorMode) or "default"
                    end,
                    setMode = function(mode)
                        local c = RotationBars()
                        if not c or c.rotationAssistStyle == "blizzard" then return end
                        c.rotationAssistColorMode = mode
                        if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end
                        EllesmereUI._NotifySettingWrite(colorRgn)
                    end,
                    getCustomRGB = function()
                        local c = RotationBars()
                        return (c and c.rotationAssistColorR) or 1,
                               (c and c.rotationAssistColorG) or 0,
                               (c and c.rotationAssistColorB) or 0
                    end,
                    setCustomRGB = function(r, g, b)
                        local c = RotationBars()
                        if c then
                            c.rotationAssistColorR = r
                            c.rotationAssistColorG = g
                            c.rotationAssistColorB = b
                        end
                        if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end
                    end,
                    hasClassColor = true,
                    onChange = function() EllesmereUI:RefreshPage() end,
                    disabled = rotColorOff,
                    disabledAlpha = 0.15,
                })
            PP.Point(classSwatch, "RIGHT", colorRgn, "RIGHT", -20, 0)
            PP.Point(swatch, "RIGHT", classSwatch, "LEFT", -8, 0)
            PP.Point(defaultSwatch, "RIGHT", swatch, "LEFT", -8, 0)

            local function UpdateRotSwatchMouse()
                local off = rotColorOff()
                swatch:EnableMouse(not off)
                defaultSwatch:EnableMouse(not off)
                classSwatch:EnableMouse(not off)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateRotSwatchMouse)
            UpdateRotSwatchMouse()
            colorRgn._captureCfg = {
                type = "multi", text = "Rotation Assist Color",
                accessors = {
                    {
                        type = "dropdown", text = "Rotation Assist Color Mode",
                        values = { default = "Default", custom = "Custom", class = "Class Color" },
                        order = { "default", "custom", "class" },
                        getValue = function()
                            local c = RotationBars()
                            return (c and c.rotationAssistColorMode) or "default"
                        end,
                        setValue = function(mode)
                            local c = RotationBars()
                            if c then c.rotationAssistColorMode = mode end
                            if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end
                        end,
                    },
                    {
                        type = "colorpicker", text = "Rotation Assist Custom Color",
                        getValue = function()
                            local c = RotationBars()
                            return (c and c.rotationAssistColorR) or 1,
                                   (c and c.rotationAssistColorG) or 0,
                                   (c and c.rotationAssistColorB) or 0, 1
                        end,
                        setValue = function(r, g, b)
                            local c = RotationBars()
                            if c then
                                c.rotationAssistColorR = r
                                c.rotationAssistColorG = g
                                c.rotationAssistColorB = b
                            end
                            if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end
                        end,
                    },
                },
            }
        end
    end

    -- Thickness | Outset: built only for the styles that read them (see
    -- RotRowsKey). Outset alone takes the left slot with a blank right slot.
    local rotRows = RotRowsKey()
    if rotRows > 0 then
        local thicknessCfg = { type="slider", text="Rotation Assist Thickness", min=1, max=8, step=1, trackWidth=120,
          tooltip="Thickness in physical pixels for Solid Border and Pixel Glow.",
          getValue=function()
              local c = RotationBars(); return (c and c.rotationAssistThickness) or 3
          end,
          setValue=function(v)
              local c = RotationBars()
              if c then c.rotationAssistThickness = v end
              if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end
          end }
        local outsetCfg = { type="slider", text="Rotation Assist Outset", min=0, max=12, step=1, trackWidth=120,
          tooltip="How many pixels the custom effect extends beyond the icon.",
          getValue=function()
              local c = RotationBars(); return (c and c.rotationAssistOutset) or 1
          end,
          setValue=function(v)
              local c = RotationBars()
              if c then c.rotationAssistOutset = v end
              if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end
          end }
        if rotRows >= 2 then
            local rotThRow
            rotThRow, h = W:DualRow(parent, y, thicknessCfg, outsetCfg);  y = y - h
            -- Pixel Glow's remaining parameters (Solid Border reads thickness only).
            if not EllesmereUI._prebuilding then
                local function notPixel()
                    local c = RotationBars(); return not c or c.rotationAssistStyle ~= "pixel"
                end
                -- The shared Pixel Glow rows over the rotationAssist* keys, minus
                -- Thickness (it sits on this row itself).
                local rotCogRows = {}
                for _, r in ipairs(EllesmereUI.GlowOptions.CogRows(ns._CDM_RotationGlowDesc())) do
                    if r.label ~= "Thickness" then rotCogRows[#rotCogRows + 1] = r end
                end
                EllesmereUI.BuildInlineCog(rotThRow._leftRegion, {
                    title = "Pixel Glow Settings",
                    captureRegion = rotThRow._leftRegion,
                    disabled = notPixel,
                    disabledTooltip = "This option requires Pixel Glow to be the selected glow type",
                    rows = rotCogRows,
                })
            end
        else
            _, h = W:DualRow(parent, y, outsetCfg, EllesmereUI.BlankRowCfg());  y = y - h
        end
    end
    end -- not RotationHelperOff

    -- Hide Items if Missing | Mirror Key Presses -- CD/utility bars only.
    -- Buff bars host Hide Items if Missing in the tooltip row above (their
    -- copy of this row would be empty), and Mirror Key Presses is not for
    -- buff-family bars (buffs are auto-tracked auras, not keybind-pressed
    -- abilities, so a "pressed" look has no meaning). (Per-spell threshold
    -- decimals/color moved to the per-icon dropdown: Threshold Text.)
    if not isAnyBuffBar then
    _, h = W:DualRow(parent, y,
        hideMissingCfg,
        { type="toggle", text="Mirror Key Presses",
          tooltip = "When you press an ability's keybind, show the action button's \"pushed down\" look on its icon on this bar -- even while the ability is on cooldown.",
          getValue=function() return BD().pressMirror == true end,
          setValue=function(v)
              BD().pressMirror = v
              if ns.ClearCdmPressPush then ns.ClearCdmPressPush() end
          end });  y = y - h
    end

    -- Bar Strata: per-bar screen render layer for the bar container and its
    -- icons (MEDIUM default = the engine's baseline, so unset bars are
    -- unchanged). Cursor-anchored bars keep their deliberate TOOLTIP raise
    -- while riding the cursor; this applies only when not cursor-anchored.
    -- Same values/labels as the Tracking Bars "Bar Strata" dropdown.
    local strataCfg = { type = "dropdown", text = "Bar Strata",
          tooltip = "Screen layer this bar and its icons render on.",
          values = EllesmereUI.FRAME_STRATA_LABELS,
          order = EllesmereUI.FRAME_STRATA_ORDER_FULL,
          getValue = function() return BD().barStrata or "MEDIUM" end,
          setValue = function(v)
              BD().barStrata = v
              ns.BuildAllCDMBars(); Refresh()
          end }
    -- WoW Forever has no combat potion presets, so the swap toggle is not
    -- built there and Bar Strata opens the glow rows below instead.
    if not EllesmereUI.IS_FOREVER then
    _, h = W:DualRow(parent, y,
        strataCfg,
        -- Profile-wide (one switch covers the Light's Potential, Recklessness
        -- and Liquid Luster presets on every CD/utility bar): a pot preset
        -- whose own family is fully out of bags swaps its icon/count/cooldown
        -- to the best pot of the partner families instead of sitting greyed
        -- (Liquid Luster is the final fallback for the other two).
        { type = "toggle", text = "Swap Combat Potions When Missing",
          tooltip = "When your bags have none of one combat potion type, its icon swaps to track the next type you own.",
          getValue = function()
              local p = DB(); return p and p.cdmBars and p.cdmBars.swapPotionsWhenMissing == true
          end,
          setValue = function(v)
              local p = DB()
              if p and p.cdmBars then
                  p.cdmBars.swapPotionsWhenMissing = v
                  if ns._BumpPotResolveGen then ns._BumpPotResolveGen() end
                  if ns.FullCDMRebuild then ns.FullCDMRebuild("pot_swap_toggle") end
              end
          end });  y = y - h
    end -- not IS_FOREVER

    -- Global, not per-bar: one gate for every glow the Cooldown Manager
    -- draws, hence the label. Same hosting trick as Hide Items if Missing
    -- above -- it takes the cooldown edge row's free slot where that row
    -- exists, and closes the section on its own for buff-family bars.
    local glowCombatCfg = { type="toggle", text="Show Glows Only in Combat (global)",
          tooltip = "Hide every Cooldown Manager glow out of combat and bring them all back the moment you enter combat.",
          getValue=function()
              local p = DB()
              return (p and p.cdmBars and p.cdmBars.glowsOnlyInCombat) == true
          end,
          setValue=function(v)
              local p = DB()
              if not p or not p.cdmBars then return end
              p.cdmBars.glowsOnlyInCombat = v and true or false
              -- Re-read the cached gate, then let the sweep take the running
              -- glows down (or bring the suppressed ones back) right away
              -- instead of waiting for the next combat edge.
              local first = v and ns._cdmGlowGateEverOn ~= true
              if ns.RefreshGlowCombatGate then ns.RefreshGlowCombatGate() end
              if ns.CDMGlowCombatSync then ns.CDMGlowCombatSync() end
              -- First enable of the session: glows lit before this point carry
              -- no record (StartNativeGlow records only once the gate has been
              -- on), so re-issue the bar and buff glows now -- they restart
              -- suppressed. Proc, CD-ready and preset glows already lit follow
              -- on their own next edge; every later login is exact from the start.
              if first then
                  if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end
                  if ns.RefreshBuffGlows then ns.RefreshBuffGlows() end
              end
              EllesmereUI:RefreshPage()
          end }

    -- Cooldown/utility bars only: buff bars have no cooldown edge.
    -- WoW Forever: Bar Strata takes the first slot here and every later
    -- toggle moves up one, closing with Show Non-On Use Trinkets.
    if barData.barType == "cooldowns" or barData.barType == "utility" then
    local edgeCfg = { type="toggle", text="Always Show Cooldown Edge",
          tooltip="Show the rotating cooldown edge on every cooldown in this bar, not just while a charge is recharging. Hide Recharge Edge still overrides this for individual charge spells.",
          getValue=function() return BD().showCooldownEdge == true end,
          setValue=function(v)
              BD().showCooldownEdge = v and true or nil
              ns.BuildAllCDMBars(); Refresh()
          end }
    if EllesmereUI.IS_FOREVER then
        _, h = W:DualRow(parent, y, strataCfg, edgeCfg);  y = y - h
        _, h = W:DualRow(parent, y, glowCombatCfg, trinketCfg);  y = y - h
    else
        _, h = W:DualRow(parent, y, edgeCfg, glowCombatCfg);  y = y - h
    end
    else
    if EllesmereUI.IS_FOREVER then
        _, h = W:DualRow(parent, y, strataCfg, glowCombatCfg);  y = y - h
        _, h = W:DualRow(parent, y, trinketCfg, EllesmereUI.BlankRowCfg());  y = y - h
    else
        _, h = W:DualRow(parent, y, glowCombatCfg, EllesmereUI.BlankRowCfg());  y = y - h
    end
    end

    end -- custom_buff extras guard

    -----------------------------------------------------------------
    --  ADDITIONAL BAR OFFSET -- render-only X/Y displacement stacked on
    --  top of the bar's normal position (saved, module-anchored, or
    --  unlock-anchored). Unlock mode always shows the BASE position (the
    --  bar's mover gets a distinct tint + tooltip while an offset is set);
    --  the offset re-applies on exit. 0/0 = the feature is fully inert.
    --  FocusKick is nameplate-pinned (no free position, no mover): dead controls there.
    -----------------------------------------------------------------
    if not isFocusKick then
    _, h = W:SectionHeader(parent, "ADDITIONAL BAR OFFSET", y);  y = y - h
    do
        local function SetAddOffset(axisKey, v)
            local b = BD(); if not b then return end
            b[axisKey] = (v ~= 0) and v or nil
            -- The anchor extra-offset registry getter (registered for every eligible bar
            -- by the unlock registration pass below) reads the live value, so no per-edit
            -- set/clear is needed. Re-register unlock elements so the mover's offset
            -- marker (tint + tooltip) reflects the new state at the next unlock entry,
            -- then re-apply positions: the build covers saved and module-anchored
            -- placement, the cascade covers an unlock-anchored bar (the build leaves
            -- those positions to the anchor system).
            if ns.RegisterCDMUnlockElements then ns.RegisterCDMUnlockElements() end
            ns.BuildAllCDMBars()
            if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("CDM_" .. b.key)
                and EllesmereUI.PropagateAnchorChain then
                EllesmereUI.PropagateAnchorChain("CDM_" .. b.key)
            end
            Refresh()
        end
        _, h = W:DualRow(parent, y,
            { type = "slider", pixel = true, text = "Offset X", min = -500, max = 500, step = 1, trackWidth = 120,
              tooltip = "Extra horizontal shift stacked on top of this bar's normal position. Unlock mode shows the base position; the offset re-applies when you exit.",
              getValue = function() local b = BD(); return (b and b.addOffsetX) or 0 end,
              setValue = function(v) SetAddOffset("addOffsetX", v) end },
            { type = "slider", pixel = true, text = "Offset Y", min = -500, max = 500, step = 1, trackWidth = 120,
              tooltip = "Extra vertical shift stacked on top of this bar's normal position. Unlock mode shows the base position; the offset re-applies when you exit.",
              getValue = function() local b = BD(); return (b and b.addOffsetY) or 0 end,
              setValue = function(v) SetAddOffset("addOffsetY", v) end }
        );  y = y - h
    end
    end -- not isFocusKick

    return math.abs(y)
end

-- Used by EUI_CooldownManager_Options.lua
ns.CDMO_BuildCDMBarsPage = BuildCDMBarsPage
