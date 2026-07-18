-------------------------------------------------------------------------------
--  EllesmereUICooldownManager_Options.lua
--  Registers CDM Effects module with EllesmereUI
--  Tab 1: CDM Bars  (Bar Glows + Tracking Bars disabled pending rewrite)
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_BAR_GLOWS    = "Bar Glows"
local PAGE_BUFF_BARS    = "Tracking Bars"
local PAGE_CDM_BARS     = "CDM Bars"

local PAGE_UNLOCK       = "Unlock Mode"

local SEC_MAPPINGS   = "GLOW MAPPINGS"
local SEC_LAYOUT     = "LAYOUT"
local SEC_APPEARANCE = "APPEARANCE"
local SEC_FILTER     = "FILTER"
local SEC_BEHAVIOR   = "BEHAVIOR"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    local db
    C_Timer.After(0, function() db = _G._ECME_AceDB end)

    local function DB()
        if not db then db = _G._ECME_AceDB end
        return db and db.profile
    end

    local function Refresh()
        if _G._ECME_Apply then _G._ECME_Apply() end
    end

    -- Post-spell-change for CD/utility bars. AddTrackedSpell /
    -- RemoveTrackedSpell already rebuild routes + queue reanchor.
    -- Force an immediate CollectAndReanchor so icons update NOW (not
    -- deferred via throttled queue). Then rebuild the options page with
    -- _skipNextApplyRebuild to prevent a redundant FullCDMRebuild.
    local function RefreshCDPreview()
        if ns.CollectAndReanchor then ns.CollectAndReanchor() end
        ns._skipNextApplyRebuild = true
        C_Timer.After(0.05, function()
            if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
            if ns.ApplyCachedKeybinds then ns.ApplyCachedKeybinds() end
            if EllesmereUI and EllesmereUI.RefreshPage then
                EllesmereUI:RefreshPage(true)
            end
        end)
    end

    -- Inline text input helper (no W:InputBox exists)
    local FONT_PATH = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("cdm"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

    local function GetCDMOptOutline()
        return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
    end
    local function GetCDMOptUseShadow()
        return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
    end
    local function SetPVFont(fs, font, size)
        if not (fs and fs.SetFont) then return end
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, GetCDMOptUseShadow()) end
        fs:SetFont(font, size, GetCDMOptOutline())
    end
    local function MakeTextInput(parent, label, yOffset, getValue, setValue)
        local ROW_H = 50
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(parent:GetWidth(), ROW_H)
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)

        local lbl = frame:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        lbl:SetTextColor(0.7, 0.7, 0.7, 1)
        lbl:SetPoint("TOPLEFT", 20, -6)
        lbl:SetText(label)

        local box = CreateFrame("EditBox", nil, frame)
        box:SetSize(parent:GetWidth() - 44, 22)
        box:SetPoint("TOPLEFT", 22, -22)
        box:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        box:SetTextColor(1, 1, 1, 1)
        box:SetAutoFocus(false)
        box:SetMaxLetters(200)

        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)

        box:SetText(getValue() or "")
        box:SetScript("OnEnterPressed", function(self)
            setValue(self:GetText())
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:SetText(getValue() or "")
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            setValue(self:GetText())
        end)

        return frame, ROW_H
    end

    ---------------------------------------------------------------------------
    --  Buff spell list from viewer pool
    ---------------------------------------------------------------------------
    --  Bar Glows page buff action button glow assignments)
    ---------------------------------------------------------------------------
    local BAR_BUTTON_PREFIXES = {
        [1] = "ActionButton",
        [2] = "MultiBarBottomLeftButton",
        [3] = "MultiBarBottomRightButton",
        [4] = "MultiBarRightButton",
        [5] = "MultiBarLeftButton",
        [6] = "MultiBar5Button",
        [7] = "MultiBar6Button",
        [8] = "MultiBar7Button",
    }

    -- Action bar shape masks/borders (for preview rendering)
    local AB_SHAPE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
    local AB_SHAPE_MASKS = {
        circle = AB_SHAPE_MEDIA .. "circle_mask.tga",
        csquare = AB_SHAPE_MEDIA .. "csquare_mask.tga",
        diamond = AB_SHAPE_MEDIA .. "diamond_mask.tga",
        hexagon = AB_SHAPE_MEDIA .. "hexagon_mask.tga",
        portrait = AB_SHAPE_MEDIA .. "portrait_mask.tga",
        shield = AB_SHAPE_MEDIA .. "shield_mask.tga",
        square = AB_SHAPE_MEDIA .. "square_mask.tga",
    }
    local AB_SHAPE_BORDERS = {
        circle = AB_SHAPE_MEDIA .. "circle_border.tga",
        csquare = AB_SHAPE_MEDIA .. "csquare_border.tga",
        diamond = AB_SHAPE_MEDIA .. "diamond_border.tga",
        hexagon = AB_SHAPE_MEDIA .. "hexagon_border.tga",
        portrait = AB_SHAPE_MEDIA .. "portrait_border.tga",
        shield = AB_SHAPE_MEDIA .. "shield_border.tga",
        square = AB_SHAPE_MEDIA .. "square_border.tga",
    }

    -- Action bar entries (1-8) are stable. CDM bar entries are built dynamically
    -- via BuildBGTargetList because the user can add extra cooldown/utility/buff
    -- bars beyond the defaults.
    local BG_ACTION_BAR_LABELS = {
        [1] = "Action Bar 1 (Main)", [2] = "Action Bar 2", [3] = "Action Bar 3", [4] = "Action Bar 4",
        [5] = "Action Bar 5", [6] = "Action Bar 6", [7] = "Action Bar 7", [8] = "Action Bar 8",
    }

    -- Backward-compat normalizer: legacy installs saved selectedBar as 101/102
    -- for the default cooldowns/utility CDM bars. Convert to the bar key string.
    -- New saves use the bar key directly.
    local function NormalizeSelectedBar(sel)
        if sel == 101 then return "cooldowns" end
        if sel == 102 then return "utility" end
        return sel
    end

    -- Build the live dropdown list. Returns an array of
    -- { value, label } entries in display order:
    --   1. CDM bars from p.cdmBars.bars (default + extras, skipping ghost/custom_buff)
    --   2. Action bars 1-8
    -- "value" is a string for CDM bars (the bar key) or an integer 1-8 for action bars.
    local function BuildBGTargetList()
        local list = {}
        local p = ns.ECME and ns.ECME.db and ns.ECME.db.profile
        if p and p.cdmBars and p.cdmBars.bars then
            for _, bd in ipairs(p.cdmBars.bars) do
                if bd.enabled and not bd.isGhostBar
                   and bd.barType ~= "custom_buff" then
                    list[#list + 1] = {
                        value = bd.key,
                        label = EllesmereUI.Lf("CDM Bar - %s", EllesmereUI.L(bd.name or bd.key)),
                    }
                end
            end
        end
        for i = 1, 8 do
            list[#list + 1] = { value = i, label = EllesmereUI.L(BG_ACTION_BAR_LABELS[i]) }
        end
        return list
    end

    local function GetBGTargetLabel(sel)
        sel = NormalizeSelectedBar(sel)
        if type(sel) == "number" then
            return EllesmereUI.L(BG_ACTION_BAR_LABELS[sel] or ("Action Bar " .. sel))
        end
        local p = ns.ECME and ns.ECME.db and ns.ECME.db.profile
        if p and p.cdmBars and p.cdmBars.bars then
            for _, bd in ipairs(p.cdmBars.bars) do
                if bd.key == sel then return EllesmereUI.Lf("CDM Bar - %s", EllesmereUI.L(bd.name or bd.key)) end
            end
        end
        return tostring(sel)
    end

    -- Presets, custom spell IDs, racials, trinkets and custom buffs are
    -- EllesmereUI-injected icons (not Blizzard cooldown-viewer cooldowns), so they
    -- have no stable cooldownID to key a glow assignment on. They are NOT
    -- glow-assignable: the Bar Glows preview leaves their buttons inert.
    local function IsNonGlowableCDMIcon(frame)
        if not frame then return false end
        -- Overflow-diverted icons render on this bar only for the session;
        -- their glow identity (and any slot-index fallback key) belongs to
        -- the source bar, so they are not listed/assignable while diverted.
        -- Existing cdm_-keyed glows still RENDER on them (the render pass is
        -- key-driven, not list-driven).
        if ns.CdmFrameOverflowBar and ns.CdmFrameOverflowBar(frame) then return true end
        return (frame._isRacialFrame or frame._isTrinketFrame
            or frame._isPresetFrame or frame._isItemPresetFrame
            or frame._isCustomSpellFrame or frame._isCustomBuffFrame) and true or false
    end

    -- True if any icon on a buff bar has its per-icon "Always Show Buff" override
    -- set to "on". A single per-icon "on" forces inactive placeholders the same way
    -- the bar-level "Always Show Buffs" toggle does, so it is mutually exclusive
    -- with "Keep Buffs in Same Place" -- treated identically to the bar toggle.
    local function AnyIconAlwaysShowOn(barKey)
        -- Per-spell entries live in the spec FAMILY store (own keys only --
        -- rawget skips bar-tier inheritance, checked separately below).
        local st = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore(barKey)
        if st then
            for _, ss in pairs(st) do
                if type(ss) == "table" and rawget(ss, "alwaysShow") == "on" then return true end
            end
        end
        local sd = ns.GetBarSpellData and ns.GetBarSpellData(barKey)
        local tier = ns.GetBarTierSettings and ns.GetBarTierSettings(sd, barKey)
        if tier and tier.alwaysShow == "on" then return true end
        return false
    end

    local BG_MODE_VALUES = { ACTIVE = "Buff Active", MISSING = "Buff Missing" }
    local BG_MODE_ORDER  = { "ACTIVE", "MISSING" }

    -- Build glow style dropdown values from ns.GLOW_STYLES
    local function GetGlowStyleValues()
        local labels, order = {}, {}
        if ns.GLOW_STYLES then
            for i, entry in ipairs(ns.GLOW_STYLES) do
                labels[i] = (entry.name and EllesmereUI.L(entry.name)) or ("Style " .. i)
                order[#order + 1] = i
            end
        end
        if #order == 0 then
            labels[1] = "Action Button Glow"
            order[1] = 1
        end
        return labels, order
    end

    ---------------------------------------------------------------------------
    --  Pandemic Glow shared helpers (used by CDM Bars options page)
    ---------------------------------------------------------------------------

    -- Pandemic glow style dropdown values (excludes ShapeGlow, adds "None")
    local PAN_GLOW_VALUES = { [0] = "None", [-1] = "Blizzard Default" }
    local PAN_GLOW_ORDER  = { 0, -1 }
    if ns.GLOW_STYLES then
        for i, entry in ipairs(ns.GLOW_STYLES) do
            if not entry.shapeGlow then
                PAN_GLOW_VALUES[i] = entry.name
                PAN_GLOW_ORDER[#PAN_GLOW_ORDER + 1] = i
            end
        end
    end

    -- Bar-only pandemic glow: only Pixel Glow and Auto-Cast Shine work on rectangles
    local PAN_GLOW_BAR_VALUES = { [0] = "None", [1] = "Pixel Glow", [4] = "Auto-Cast Shine" }
    local PAN_GLOW_BAR_ORDER  = { 0, 1, 4 }

    -- Pandemic-glow cross-surface sync (CDM bars + Nameplates) lives in the CDM
    -- core as EllesmereUI.ApplyPandemicGlowToAll / IsPandemicGlowSyncedToAll
    -- (best-effort, name-based so styles never shift across surfaces). Callers
    -- build a payload with EllesmereUI.PandemicPayloadFrom* and pass it.

    -- Create a pandemic glow preview icon in a DualRow right-half
    local function BuildPandemicPreview(row, isOffFn, getDataFn)
        local SIDE_PAD = 20
        local iconSize = 36
        local iconFrame = CreateFrame("Frame", nil, row)
        PP.Size(iconFrame, iconSize, iconSize)
        PP.Point(iconFrame, "RIGHT", row, "RIGHT", -SIDE_PAD, 0)

        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTex:SetTexture(136197)

        local onePx = PP.Scale(1)
        for _, info in ipairs({
            {"TOPLEFT", "TOPRIGHT", true}, {"BOTTOMLEFT", "BOTTOMRIGHT", true},
            {"TOPLEFT", "BOTTOMLEFT", false}, {"TOPRIGHT", "BOTTOMRIGHT", false},
        }) do
            local t = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(0, 0, 0, 1)
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
            PP.Point(t, info[1], iconFrame, info[1], 0, 0)
            PP.Point(t, info[2], iconFrame, info[2], 0, 0)
            if info[3] then t:SetHeight(onePx) else t:SetWidth(onePx) end
        end

        local glowOvr = CreateFrame("Frame", nil, iconFrame)
        glowOvr:SetAllPoints(iconFrame)
        glowOvr:SetFrameLevel(iconFrame:GetFrameLevel() + 2)
        glowOvr:EnableMouse(false)

        local function RefreshPreview()
            EllesmereUI.Glows.StopAllGlows(glowOvr)
            if isOffFn() then
                iconFrame:SetAlpha(0.3)
                return
            end
            iconFrame:SetAlpha(1)
            local bd = getDataFn()
            if not bd then return end
            local style = bd.pandemicGlowStyle or 1
            local c = bd.pandemicGlowColor or { r = 1, g = 1, b = 0 }
            local glowOpts = (style == 1) and {
                N = bd.pandemicGlowLines or 8,
                th = bd.pandemicGlowThickness or 2,
                period = bd.pandemicGlowSpeed or 4,
                bg = bd.pandemicGlowBackground and {
                    r = (bd.pandemicGlowBackgroundColor and bd.pandemicGlowBackgroundColor.r) or 0,
                    g = (bd.pandemicGlowBackgroundColor and bd.pandemicGlowBackgroundColor.g) or 0,
                    b = (bd.pandemicGlowBackgroundColor and bd.pandemicGlowBackgroundColor.b) or 0,
                } or nil,
            } or nil
            ns.StartNativeGlow(glowOvr, style, c.r or 1, c.g or 1, c.b or 0, glowOpts)
        end
        RefreshPreview()

        local previewLabel = ({ row._rightRegion:GetRegions() })[1]
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isOffFn()
            iconFrame:SetAlpha(off and 0.3 or 1)
            if previewLabel and previewLabel.SetAlpha then
                previewLabel:SetAlpha(off and 0.3 or 1)
            end
            RefreshPreview()
        end)

        row._refreshPreview = RefreshPreview
    end

    -- Create a pixel glow cog popup for pandemic settings
    -- getDataFn: returns the settings table; refreshFn: called after changes
    local _sharedPgPopup, _sharedPgPopupOwner
    -- Default key set: pandemic glow. Other callers (e.g. Buff Glow) pass their
    -- own keys so the shared popup reads/writes that feature's Lines/Thickness/Speed.
    local PG_DEFAULT_KEYS = { lines = "pandemicGlowLines", thickness = "pandemicGlowThickness", speed = "pandemicGlowSpeed", background = "pandemicGlowBackground", backgroundColor = "pandemicGlowBackgroundColor" }
    local function ShowPandemicPixelGlowPopup(anchorBtn, getDataFn, refreshFn, keys)
        -- Bind data source before popup creation so slider getValue callbacks work
        if _sharedPgPopup then
            _sharedPgPopup._getData = getDataFn
            _sharedPgPopup._refresh = refreshFn
            _sharedPgPopup._keys = keys or PG_DEFAULT_KEYS
        end
        if not _sharedPgPopup then
            local SolidTex   = EllesmereUI.SolidTex
            local MakeBorder = EllesmereUI.MakeBorder
            local MakeFont   = EllesmereUI.MakeFont
            local BuildSliderCore = EllesmereUI.BuildSliderCore
            local BuildToggleControl = EllesmereUI.BuildToggleControl
            local BuildColorSwatch = EllesmereUI.BuildColorSwatch
            local BORDER_COLOR   = EllesmereUI.BORDER_COLOR

            local SIDE_PAD = 14; local TOP_PAD = 14
            local TITLE_H = 11; local TITLE_GAP = 10; local GAP = 10
            local ROW_H = 24; local POPUP_INPUT_A = 0.55
            local INPUT_W = 34; local SLIDER_INPUT_GAP = 8; local LABEL_SLIDER_GAP = 12
            local MIN_POPUP_W = 180

            local totalH = TOP_PAD + TITLE_H + TITLE_GAP + (GAP * 5) + (ROW_H * 5) + TOP_PAD

            local pf = CreateFrame("Frame", nil, UIParent)
            pf:SetSize(260, totalH); pf:SetFrameStrata("DIALOG"); pf:SetFrameLevel(200)
            pf:EnableMouse(true); pf:Hide()
            -- Match panel/popup scale so this cog popup renders at the same size
            -- as the shared BuildCogPopup popups.
            pf:SetScale((EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1)
            if EllesmereUI._popupFrames then
                EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = pf }
            end
            -- Bind data source before sliders are built so getValue callbacks work
            pf._getData = getDataFn
            pf._refresh = refreshFn
            pf._keys = keys or PG_DEFAULT_KEYS

            local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, 0.95); bg:SetAllPoints()
            MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

            local titleFS = MakeFont(pf, 11, "", 1, 1, 1); titleFS:SetAlpha(0.7)
            titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD); titleFS:SetText(EllesmereUI.L("Pixel Glow Settings"))

            local tmpFS = pf:CreateFontString(nil, "OVERLAY")
            tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
            local maxLblW = 0
            for _, txt in ipairs({"Lines", "Thickness", "Speed", "Background", "Background Color"}) do
                tmpFS:SetText(txt); local w = tmpFS:GetStringWidth(); if w > maxLblW then maxLblW = w end
            end
            tmpFS:Hide(); if maxLblW < 10 then maxLblW = 60 end

            local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
            local SLIDER_W = math.max(80, 260 - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
            local POPUP_W = math.max(MIN_POPUP_W, SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD)
            pf:SetWidth(POPUP_W)

            local r1Y = -(TOP_PAD + TITLE_H + TITLE_GAP + GAP)
            local lbl1 = MakeFont(pf, 11, nil, 1, 1, 1); lbl1:SetAlpha(0.6)
            lbl1:SetText(EllesmereUI.L("Lines")); lbl1:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r1Y)
            local t1, v1 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                2, 16, 1,
                function() local d = pf._getData(); return d and d[pf._keys.lines] or 8 end,
                function(v) local d = pf._getData(); if d then d[pf._keys.lines] = v end; if pf._refresh then pf._refresh() end end, true)
            t1:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r1Y - 2)
            v1:ClearAllPoints(); v1:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r1Y)

            local r2Y = r1Y - ROW_H - GAP
            local lbl2 = MakeFont(pf, 11, nil, 1, 1, 1); lbl2:SetAlpha(0.6)
            lbl2:SetText(EllesmereUI.L("Thickness")); lbl2:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r2Y)
            local t2, v2 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                1, 4, 1,
                function() local d = pf._getData(); return d and d[pf._keys.thickness] or 2 end,
                function(v) local d = pf._getData(); if d then d[pf._keys.thickness] = v end; if pf._refresh then pf._refresh() end end, true)
            t2:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r2Y - 2)
            v2:ClearAllPoints(); v2:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r2Y)

            local r3Y = r2Y - ROW_H - GAP
            local lbl3 = MakeFont(pf, 11, nil, 1, 1, 1); lbl3:SetAlpha(0.6)
            lbl3:SetText(EllesmereUI.L("Speed")); lbl3:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r3Y)
            local t3, v3 = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                1, 8, 1,
                function() local d = pf._getData(); local p = d and d[pf._keys.speed] or 4; return 9 - p end,
                function(v) local d = pf._getData(); if d then d[pf._keys.speed] = 9 - v end; if pf._refresh then pf._refresh() end end, true)
            t3:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, r3Y - 2)
            v3:ClearAllPoints(); v3:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, r3Y)

            local r4Y = r3Y - ROW_H - GAP
            local lbl4 = MakeFont(pf, 11, nil, 1, 1, 1); lbl4:SetAlpha(0.6)
            lbl4:SetText(EllesmereUI.L("Background")); lbl4:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r4Y)
            local bgToggle, _, bgSnap = BuildToggleControl(pf, pf:GetFrameLevel() + 2,
                function()
                    local d = pf._getData(); local k = pf._keys.background
                    return d and k and d[k] == true
                end,
                function(v)
                    local d = pf._getData(); local k = pf._keys.background
                    if d and k then d[k] = v and true or nil end
                    if pf._refresh then pf._refresh() end
                end, { sizeRatio = 0.8, noAnim = true })
            bgToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, r4Y - ROW_H / 2)

            local r5Y = r4Y - ROW_H - GAP
            local lbl5 = MakeFont(pf, 11, nil, 1, 1, 1); lbl5:SetAlpha(0.6)
            lbl5:SetText(EllesmereUI.L("Background Color")); lbl5:SetPoint("TOPLEFT", pf, "TOPLEFT", SIDE_PAD, r5Y)
            local bgSwatch, bgUpdate = BuildColorSwatch(pf, pf:GetFrameLevel() + 2,
                function()
                    local d = pf._getData(); local k = pf._keys.backgroundColor
                    local c = d and k and d[k]
                    if c then return c.r or 0, c.g or 0, c.b or 0 end
                    return 0, 0, 0
                end,
                function(r, g, b)
                    local d = pf._getData(); local k = pf._keys.backgroundColor
                    if d and k then d[k] = { r = r, g = g, b = b } end
                    if pf._refresh then pf._refresh() end
                end, false, 20)
            bgSwatch:ClearAllPoints()
            bgSwatch:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, r5Y - ROW_H / 2)
            local bgBlock = CreateFrame("Frame", nil, bgSwatch)
            bgBlock:SetAllPoints(); bgBlock:SetFrameLevel(bgSwatch:GetFrameLevel() + 10); bgBlock:EnableMouse(true)
            bgBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(bgSwatch, EllesmereUI.DisabledTooltip("Pixel Glow Background"))
            end)
            bgBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function UpdateBgControls()
                if bgSnap then bgSnap() end
                if bgUpdate then bgUpdate() end
                local d = pf._getData()
                local k = pf._keys.background
                local on = d and k and d[k] == true
                bgSwatch:SetAlpha(on and 1 or 0.3)
                if on then bgBlock:Hide() else bgBlock:Show() end
            end
            bgToggle:HookScript("OnClick", UpdateBgControls)
            pf._refreshControls = UpdateBgControls
            UpdateBgControls()

            local wasDown = false
            pf:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                if _sharedPgPopupOwner then _sharedPgPopupOwner:SetAlpha(0.4) end
                _sharedPgPopupOwner = nil
            end)
            pf._clickOutside = function(self, _)
                local down = IsMouseButtonDown("LeftButton")
                if down and not wasDown then
                    if not self:IsMouseOver() and not (_sharedPgPopupOwner and _sharedPgPopupOwner:IsMouseOver()) then
                        self:Hide()
                    end
                end
                wasDown = down
            end
            if EllesmereUI._mainFrame then
                EllesmereUI._mainFrame:HookScript("OnHide", function()
                    if pf:IsShown() then pf:Hide() end
                end)
            end
            _sharedPgPopup = pf
        end

        if _sharedPgPopupOwner == anchorBtn and _sharedPgPopup:IsShown() then
            _sharedPgPopup:Hide(); return
        end
        -- Bind data source and refresh callback for this invocation
        _sharedPgPopup._getData = getDataFn
        _sharedPgPopup._refresh = refreshFn
        _sharedPgPopup._keys = keys or PG_DEFAULT_KEYS
        if _sharedPgPopup._refreshControls then _sharedPgPopup._refreshControls() end
        _sharedPgPopupOwner = anchorBtn

        _sharedPgPopup:ClearAllPoints()
        _sharedPgPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6)
        _sharedPgPopup:SetAlpha(0); _sharedPgPopup:Show()
        local elapsed = 0
        _sharedPgPopup:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt; local t = math.min(elapsed / 0.15, 1)
            self:SetAlpha(t); self:ClearAllPoints()
            self:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6 + (-8 * (1 - t)))
            if t >= 1 then self:SetScript("OnUpdate", self._clickOutside) end
        end)
    end

    -- Build a pandemic glow cog button that opens the shared pixel glow popup
    local function BuildPandemicCogButton(row, isAntsOffFn, getDataFn, refreshFn, keys)
        local leftRgn = row._leftRegion
        local btn = CreateFrame("Button", nil, leftRgn)
        btn:SetSize(26, 26)
        btn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
        btn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        btn:SetAlpha(0.4)
        local cogTex = btn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
        btn:SetScript("OnEnter", function(self)
            if isAntsOffFn() then
                EllesmereUI.ShowWidgetTooltip(self, "This option requires Pixel Glow to be the selected glow type")
            else self:SetAlpha(0.7) end
        end)
        btn:SetScript("OnLeave", function(self)
            EllesmereUI.HideWidgetTooltip()
            if _sharedPgPopupOwner ~= btn then self:SetAlpha(isAntsOffFn() and 0.15 or 0.4) end
        end)
        btn:SetScript("OnClick", function(self)
            if isAntsOffFn() then return end
            ShowPandemicPixelGlowPopup(self, getDataFn, refreshFn, keys)
        end)
        EllesmereUI.RegisterWidgetRefresh(function()
            if _sharedPgPopupOwner ~= btn then btn:SetAlpha(isAntsOffFn() and 0.15 or 0.4) end
        end)
    end

    -- Get the icon texture from a real Blizzard action button
    local function GetActionButtonIcon(barIdx, slot)
        local prefix = BAR_BUTTON_PREFIXES[barIdx]
        if not prefix then return nil end
        local btn = _G[prefix .. slot]
        if not btn then return nil end
        local icon = btn.icon or btn.Icon
        if icon and icon.GetTexture then return icon:GetTexture() end
        return nil
    end

    -- Check if a specific bar target uses a custom shape (not "none"/"cropped").
    -- barIdx can be a number 1-8 (action bar) or a string (CDM bar key).
    local function BarHasCustomShape(barIdx)
        barIdx = NormalizeSelectedBar(barIdx)
        if type(barIdx) == "string" then
            local cdmBd = ns.barDataByKey and ns.barDataByKey[barIdx]
            if cdmBd and cdmBd.iconShape and cdmBd.iconShape ~= "none" and cdmBd.iconShape ~= "cropped" then
                return true
            end
            return false
        end
        local barKeys = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8" }
        local barKey = barKeys[barIdx]
        if not barKey then return false end
        local ok, EAB = pcall(EllesmereUI.Lite.GetAddon, "EllesmereUIActionBars")
        if ok and EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars then
            local s = EAB.db.profile.bars[barKey]
            if s and s.buttonShape and s.buttonShape ~= "none" and s.buttonShape ~= "cropped" then
                return true
            end
        end
        return false
    end

    -- Preview glow state tracking
    local _bgPreviewGlowActive = {}
    local _bgPreviewGlowOverlays = {}
    local _bgSpellPickerMenu

    EllesmereUI:RegisterOnHide(function()
        if _bgSpellPickerMenu then _bgSpellPickerMenu:Hide() end
    end)

    local function ShowBarGlowSpellPicker(anchorFrame, barIdx, btnIdx, onChanged, overrideAssignKey)
        if _bgSpellPickerMenu then _bgSpellPickerMenu:Hide() end

        local bg = ns.GetBarGlows()
        local assignKey = overrideAssignKey or (barIdx .. "_" .. btnIdx)
        local buffList = bg.assignments[assignKey] or {}

        -- Build set of currently assigned spellIDs
        local assignedSet = {}
        for _, entry in ipairs(buffList) do
            if entry.spellID then assignedSet[entry.spellID] = true end
        end

        -- Track whether any change was made so we can fire onChanged when menu closes
        local dirty = false
        -- Immediate update: save picker position, rebuild, re-anchor
        local function ImmediateUpdate()
            dirty = false  -- already handled
            if not onChanged then return end
            local menuRef = _bgSpellPickerMenu
            if not menuRef then onChanged(); return end
            -- Save absolute screen position before rebuild
            local cx, cy = menuRef:GetCenter()
            local mScale = menuRef:GetEffectiveScale()
            local mW, mH = menuRef:GetSize()
            -- Fire the rebuild
            onChanged()
            -- Re-anchor to saved absolute position so page rebuild doesn't shift us
            menuRef = _bgSpellPickerMenu
            if menuRef and menuRef:IsShown() then
                menuRef:ClearAllPoints()
                local uiScale = UIParent:GetEffectiveScale()
                menuRef:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * mScale / uiScale, cy * mScale / uiScale)
            end
        end

        -- Get tracked and untracked buff spells (CDM buff icon bars)
        local tracked, untracked = ns.GetAllCDMBuffSpells()
        -- Tracked Bar spells are added later in the picker -- check them
        -- here too so the menu doesn't bail when only Tracked Bars exist.
        local hasTrackedBars = ns.GetTrackedBarSpells and #ns.GetTrackedBarSpells() > 0 or false
        if #tracked == 0 and #untracked == 0 and not hasTrackedBars then return end

        -- Standard dropdown colors
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
        local MAX_H = 300

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

        local function MakeCheckItem(sp)
            local item = CreateFrame("Button", nil, inner)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(menu:GetFrameLevel() + 2)

            -- Checkbox (AuraBuff style: Frame box + MakeBorder + inner fill)
            local cbSize = 14
            local cb = CreateFrame("Frame", nil, item)
            cb:SetSize(cbSize, cbSize)
            cb:SetPoint("LEFT", item, "LEFT", 8, 0)
            cb:SetFrameLevel(item:GetFrameLevel() + 1)
            local cbBg = cb:CreateTexture(nil, "BACKGROUND")
            cbBg:SetAllPoints(); cbBg:SetColorTexture(0.12, 0.12, 0.14, 1)
            local cbBrd = EllesmereUI.MakeBorder(cb, 0.25, 0.25, 0.28, 0.6, EllesmereUI.PanelPP)
            local cbFill = cb:CreateTexture(nil, "ARTWORK")
            if cbFill.SetSnapToPixelGrid then cbFill:SetSnapToPixelGrid(false); cbFill:SetTexelSnappingBias(0) end
            cbFill:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
            cbFill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
            cbFill:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1)
            local function UpdateCB()
                if assignedSet[sp.spellID] then
                    cbFill:Show()
                    cbBrd:SetColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.8)
                else
                    cbFill:Hide()
                    cbBrd:SetColor(0.25, 0.25, 0.28, 0.6)
                end
            end
            UpdateCB()

            -- Icon
            local ico = item:CreateTexture(nil, "ARTWORK")
            local icoSz = ITEM_H - 4
            ico:SetSize(icoSz, icoSz)
            ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            if sp.icon then ico:SetTexture(sp.icon) end
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Label
            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            lbl:SetPoint("RIGHT", ico, "LEFT", -4, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false); lbl:SetMaxLines(1)
            lbl:SetText(EllesmereUI.L(sp.name))
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)

            item:SetScript("OnEnter", function()
                lbl:SetTextColor(1, 1, 1, 1)
                hl:SetColorTexture(1, 1, 1, hlA)
            end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                hl:SetColorTexture(1, 1, 1, 0)
            end)
            item:SetScript("OnClick", function()
                -- Toggle assignment
                if assignedSet[sp.spellID] then
                    -- Remove
                    assignedSet[sp.spellID] = nil
                    for idx = #buffList, 1, -1 do
                        if buffList[idx].spellID == sp.spellID then
                            table.remove(buffList, idx)
                            break
                        end
                    end
                    UpdateCB()
                    bg.assignments[assignKey] = buffList
                    Refresh()
                    ImmediateUpdate()
                else
                    -- Add with defaults
                    assignedSet[sp.spellID] = true
                    local newEntry = {
                        spellID = sp.spellID,
                        glowStyle = 1,
                        glowColor = { r = 1, g = 0.82, b = 0.1 },
                        classColor = false,
                        mode = "ACTIVE",
                        onlyInCombat = false,
                    }
                    local prefix = BAR_BUTTON_PREFIXES[barIdx]
                    local realBtn = prefix and _G[prefix .. btnIdx]
                    if realBtn and realBtn.action then
                        local aType, aID = GetActionInfo(realBtn.action)
                        if aType == "spell" and aID then
                            newEntry.actionSpellID = aID
                        end
                    end
                    buffList[#buffList + 1] = newEntry
                    UpdateCB()
                    bg.assignments[assignKey] = buffList
                    Refresh()
                    ImmediateUpdate()
                end
            end)

            mH = mH + ITEM_H
        end

        -- Tracked buffs
        for _, sp in ipairs(tracked) do MakeCheckItem(sp) end

        -- Divider
        if #tracked > 0 and #untracked > 0 then
            local div = inner:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1); div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- Untracked buffs
        for _, sp in ipairs(untracked) do MakeCheckItem(sp) end

        -- Blizzard CDM "Tracked Bars" section (BuffBarCooldownViewer).
        -- Drag-and-drop in Blizzard CDM means a spell is in either the
        -- Tracked Buffs icon strip OR the Tracked Bars section, never
        -- both -- no dedup needed.
        local trackedBars = ns.GetTrackedBarSpells and ns.GetTrackedBarSpells() or {}
        if #trackedBars > 0 then
            if #tracked > 0 or #untracked > 0 then
                local div = inner:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1); div:SetColorTexture(1, 1, 1, 0.10)
                div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9
            end
            for _, sp in ipairs(trackedBars) do MakeCheckItem(sp) end
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
        menu:HookScript("OnHide", function(m)
            m:SetScript("OnUpdate", nil)
            if dirty and onChanged then onChanged() end
        end)

        menu:Show()
        menu._btnIdx = btnIdx
        _bgSpellPickerMenu = menu
    end

    ---------------------------------------------------------------------------
    --  Bar Glows: BuildBarGlowsPage
    ---------------------------------------------------------------------------
    local _glowHeaderBuilder  -- stored for cache restore via getHeaderBuilder
    local _glowSelectedButton = nil  -- UI-only selection state (not saved)
    local _glowBtnFrames = {}  -- button frames from last header build, indexed by button number

    local function BuildBarGlowsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        local bg = ns.GetBarGlows()
        local curBar = NormalizeSelectedBar(bg.selectedBar or "cooldowns")
        local curBtn = _glowSelectedButton  -- nil = no selection

        local ACCENT = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }

        -------------------------------------------------------------------
        --  Content Header: Live Action Bar Preview (replica of BuildLivePreview)
        -------------------------------------------------------------------
        EllesmereUI:ClearContentHeader()

        -- Stop any lingering preview glows
        for idx, ov in pairs(_bgPreviewGlowOverlays) do
            ns.StopNativeGlow(ov)
        end
        wipe(_bgPreviewGlowOverlays)
        wipe(_bgPreviewGlowActive)

        _glowHeaderBuilder = function(headerFrame, width)
            -- Re-read current state each build
            local bgData = ns.GetBarGlows()
            local sel = NormalizeSelectedBar(bgData.selectedBar or 1)
            local isCDMBar = (type(sel) == "string")
            -- For CDM bars: cdmBarKey is the bar key string. For action bars:
            -- barIdx is the integer 1-8 used for prefix lookup.
            local cdmBarKey = isCDMBar and sel or nil
            local barIdx = isCDMBar and nil or sel
            local ok, EAB_ADDON = pcall(EllesmereUI.Lite.GetAddon, "EllesmereUIActionBars")
            if not ok then EAB_ADDON = nil end
            local barKeyList = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8" }
            local barKeyStr = (not isCDMBar) and (barKeyList[barIdx] or "MainBar") or nil
            local barSettings = nil
            if barKeyStr and EAB_ADDON and EAB_ADDON.db and EAB_ADDON.db.profile then
                barSettings = EAB_ADDON.db.profile.bars[barKeyStr]
            end

            -- CDM bars: count icons dynamically; action bars: always 12.
            -- Overflow-diverted icons are tail-appended to the target's array
            -- and excluded here, so every native icon keeps its slot index
            -- (stable glow-assignment fallback keys).
            local NUM_BUTTONS = 12
            if isCDMBar and ns.cdmBarIcons and ns.cdmBarIcons[cdmBarKey] then
                NUM_BUTTONS = 0
                for _, ic in ipairs(ns.cdmBarIcons[cdmBarKey]) do
                    if not (ns.CdmFrameOverflowBar and ns.CdmFrameOverflowBar(ic)) then
                        NUM_BUTTONS = NUM_BUTTONS + 1
                    end
                end
                if NUM_BUTTONS == 0 then NUM_BUTTONS = 1 end
            end
            local prefix = (not isCDMBar) and (BAR_BUTTON_PREFIXES[barIdx] or "ActionButton") or nil

            -- Dropdown at top
            local DD_H = 34
            local ddW  = 350
            local DDS    = EllesmereUI.DD_STYLE
            local mBgR   = DDS.BG_R;  local mBgG  = DDS.BG_G;  local mBgB  = DDS.BG_B
            local mBgA   = DDS.BG_A;  local mBgHA = DDS.BG_HA
            local mBrdA  = DDS.BRD_A; local mBrdHA = DDS.BRD_HA or 0.30
            local mTxtA  = DDS.TXT_A; local mTxtHA = DDS.TXT_HA or 1
            local hlA    = DDS.ITEM_HL_A; local selA = DDS.ITEM_SEL_A
            local tDimR  = EllesmereUI.TEXT_DIM_R or 0.7
            local tDimG  = EllesmereUI.TEXT_DIM_G or 0.7
            local tDimB  = EllesmereUI.TEXT_DIM_B or 0.7
            local tDimA  = EllesmereUI.TEXT_DIM_A or 0.85
            local ITEM_H = 26

            local ddBtn = CreateFrame("Button", nil, headerFrame)
            PP.Size(ddBtn, ddW, DD_H)
            ddBtn:SetFrameLevel(headerFrame:GetFrameLevel() + 5)
            local ddBg  = ddBtn:CreateTexture(nil, "BACKGROUND")
            ddBg:SetAllPoints(); ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
            local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, mBrdA, EllesmereUI.PanelPP)
            local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
            ddLbl:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            ddLbl:SetAlpha(mTxtA); ddLbl:SetJustifyH("LEFT")
            ddLbl:SetWordWrap(false); ddLbl:SetMaxLines(1)
            ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
            local ddArrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, EllesmereUI.PanelPP)
            ddLbl:SetPoint("RIGHT", ddArrow, "LEFT", -5, 0)
            ddLbl:SetText(GetBGTargetLabel(sel))

            local ddMenu
            local function BuildDDMenu()
                if ddMenu then ddMenu:Hide(); ddMenu = nil end
                local menu = CreateFrame("Frame", nil, UIParent)
                menu:SetFrameStrata("FULLSCREEN_DIALOG")
                menu:SetFrameLevel(300)
                menu:SetClampedToScreen(true)
                menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
                menu:SetPoint("TOPRIGHT", ddBtn, "BOTTOMRIGHT", 0, -2)
                local bg2 = menu:CreateTexture(nil, "BACKGROUND")
                bg2:SetAllPoints(); bg2:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
                EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)
                local mH = 4
                local targets = BuildBGTargetList()
                for _, t in ipairs(targets) do
                    local entryVal = t.value
                    local item = CreateFrame("Button", nil, menu)
                    item:SetHeight(ITEM_H)
                    item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(menu:GetFrameLevel() + 2)
                    local iLbl = item:CreateFontString(nil, "OVERLAY")
                    iLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    iLbl:SetJustifyH("LEFT"); iLbl:SetWordWrap(false); iLbl:SetMaxLines(1)
                    iLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                    iLbl:SetText(t.label)
                    local iHl = item:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints(); iHl:SetColorTexture(1, 1, 1, 1)
                    local isCurrent = (entryVal == sel)
                    iHl:SetAlpha(isCurrent and selA or 0)
                    item:SetScript("OnEnter", function() iLbl:SetTextColor(1,1,1,1); iHl:SetAlpha(hlA) end)
                    item:SetScript("OnLeave", function() iLbl:SetTextColor(tDimR,tDimG,tDimB,tDimA); iHl:SetAlpha(isCurrent and selA or 0) end)
                    item:SetScript("OnClick", function()
                        menu:Hide()
                        bgData.selectedBar = entryVal
                        bgData.selectedButton = nil
                        _glowSelectedButton = nil
                        EllesmereUI:RefreshPage(true)
                    end)
                    mH = mH + ITEM_H
                end
                menu:SetHeight(mH + 4)
                menu:SetScript("OnUpdate", function(m)
                    if not m:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then m:Hide() end
                end)
                menu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)
                menu:Show()
                ddMenu = menu
            end

            ddBtn:SetScript("OnEnter", function() ddLbl:SetAlpha(mTxtHA); ddBrd:SetColor(1,1,1,mBrdHA); ddBg:SetColorTexture(mBgR,mBgG,mBgB,mBgHA) end)
            ddBtn:SetScript("OnLeave", function()
                if ddMenu and ddMenu:IsShown() then return end
                ddLbl:SetAlpha(mTxtA); ddBrd:SetColor(1,1,1,mBrdA); ddBg:SetColorTexture(mBgR,mBgG,mBgB,mBgA)
            end)
            ddBtn:SetScript("OnClick", function() if ddMenu and ddMenu:IsShown() then ddMenu:Hide() else BuildDDMenu() end end)
            ddBtn:HookScript("OnHide", function() if ddMenu then ddMenu:Hide() end end)
            PP.Point(ddBtn, "TOP", headerFrame, "TOP", 0, -20)

            -- Button grid below dropdown
            local gridTopY = -(20 + DD_H + 20)

            -- Read real button size
            local realBtnW, realBtnH = 36, 36
            if isCDMBar then
                -- CDM bar: read icon size from bar settings
                local cdmBd = ns.barDataByKey and ns.barDataByKey[cdmBarKey]
                if cdmBd then
                    realBtnW = cdmBd.iconSize or 36
                    realBtnH = realBtnW
                end
            else
                local btn1 = _G[prefix .. "1"]
                realBtnW = (btn1 and btn1:GetWidth() or 36)
                realBtnH = (btn1 and btn1:GetHeight() or 36)
            end
            if realBtnW < 1 then realBtnW = 36 end
            if realBtnH < 1 then realBtnH = 36 end

            -- Read bar size (no scale -- width/height based)
            local scaledBtnW = math.floor(realBtnW + 0.5)
            local scaledBtnH = math.floor(realBtnH + 0.5)

            -- CDM bar data reference (reused for shape, spacing, zoom, border)
            local cdmBd = isCDMBar and ns.barDataByKey and ns.barDataByKey[cdmBarKey] or nil

            -- Custom shape expansion
            local btnShape
            if isCDMBar then
                btnShape = (cdmBd and cdmBd.iconShape) or "none"
            else
                btnShape = (barSettings and barSettings.buttonShape) or "none"
            end
            if btnShape ~= "none" and btnShape ~= "cropped" then
                local shapeExp = 10
                scaledBtnW = scaledBtnW + shapeExp
                scaledBtnH = scaledBtnH + shapeExp
            end
            if btnShape == "cropped" then
                scaledBtnH = math.floor(scaledBtnH * 0.80 + 0.5)
            end

            local spacing = isCDMBar and ((cdmBd and cdmBd.spacing) or 2) or ((barSettings and barSettings.buttonPadding) or 2)
            local scaledPad = spacing

            -- How many buttons visible
            local numVisible = NUM_BUTTONS
            if not isCDMBar and barSettings then
                local ov = barSettings.overrideNumIcons
                if ov and ov > 0 and ov < numVisible then numVisible = ov end
            end

            -- Read zoom
            local zoom = isCDMBar and ((cdmBd and cdmBd.iconZoom) or 0.08) or (((barSettings and barSettings.iconZoom) or 5.5) / 100)
            local square = (not isCDMBar) and EAB_ADDON and EAB_ADDON.db and EAB_ADDON.db.profile.squareIcons

            -- Read border settings
            local brdSize = 0
            local brdColor, brdClassColor
            if isCDMBar and cdmBd then
                brdSize = cdmBd.borderSize or 1
                brdColor = { r = cdmBd.borderR or 0, g = cdmBd.borderG or 0, b = cdmBd.borderB or 0, a = cdmBd.borderA or 1 }
                brdClassColor = cdmBd.borderClassColor
            elseif not isCDMBar and barSettings then
                -- Read raw borderThickness setting
                local thickness = barSettings.borderThickness or "thin"
                if thickness == "none" then brdSize = 0
                elseif thickness == "thin" then brdSize = 1
                elseif thickness == "medium" then brdSize = 2
                elseif thickness == "thick" then brdSize = 3
                else brdSize = 1 end
                brdColor = barSettings.borderColor
                brdClassColor = barSettings.borderClassColor
            end
            if not brdColor then brdColor = { r = 0, g = 0, b = 0, a = 1 } end

            -- Layout
            local gridW = numVisible * scaledBtnW + (numVisible - 1) * scaledPad
            local startX = math.max(0, math.floor((width - gridW) / 2))
            local startY = gridTopY

            -- Disable WoW's automatic pixel snapping on a texture
            local function UnsnapTex(tex)
                if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0) end
            end

            -- Clear button frame refs from previous build
            wipe(_glowBtnFrames)

            for i = 1, NUM_BUTTONS do
                if i > numVisible then break end

                local xOff = startX + (i - 1) * (scaledBtnW + scaledPad)
                local isSelected = (_glowSelectedButton == i)

                local bf = CreateFrame("Button", nil, headerFrame)
                bf:SetSize(scaledBtnW, scaledBtnH)
                bf:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", xOff, startY)
                _glowBtnFrames[i] = bf
                bf:RegisterForClicks("LeftButtonUp", "RightButtonDown")

                -- Background
                local bgTex = bf:CreateTexture(nil, "BACKGROUND")
                bgTex:SetAllPoints()
                bgTex:SetColorTexture(0.06, 0.08, 0.10, 0.5)

                -- Icon from real action button or CDM bar icon
                local realBtn
                if isCDMBar then
                    local cdmIcons = ns.cdmBarIcons and ns.cdmBarIcons[cdmBarKey]
                    realBtn = cdmIcons and cdmIcons[i]
                else
                    realBtn = prefix and _G[prefix .. i]
                end
                -- Preset / custom / racial / trinket / custom-buff icons can't be
                -- glow-assigned; their button is left inert (no hover, clicks do nothing).
                local nonGlowable = isCDMBar and IsNonGlowableCDMIcon(realBtn)
                local _rbTex = realBtn and ((ns._hookFrameData[realBtn] and ns._hookFrameData[realBtn].tex) or realBtn._tex)
                local hasAction = realBtn and ((realBtn.icon and realBtn.icon:GetTexture()) or (_rbTex and _rbTex:GetTexture()))
                local iconTex = bf:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                UnsnapTex(iconTex)
                if hasAction then
                    local srcTex = (realBtn.icon and realBtn.icon:GetTexture()) or (_rbTex and _rbTex:GetTexture())
                    iconTex:SetTexture(srcTex)
                    -- Desaturate (preview only) icons that can't be glowed so it's
                    -- clear they're not assignable.
                    if nonGlowable then iconTex:SetDesaturated(true) end
                    local z = zoom
                    if btnShape == "cropped" then
                        iconTex:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
                    elseif z > 0 or square then
                        iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
                    else
                        iconTex:SetTexCoord(0, 1, 0, 1)
                    end
                else
                    iconTex:SetColorTexture(0, 0, 0, 0.5)
                end

                -- Shape mask
                local SHAPE_MASKS = isCDMBar and ns.CDM_SHAPE_MASKS or AB_SHAPE_MASKS
                local SHAPE_BORDERS = isCDMBar and ns.CDM_SHAPE_BORDERS or AB_SHAPE_BORDERS
                if btnShape ~= "none" and btnShape ~= "cropped" and SHAPE_MASKS and SHAPE_MASKS[btnShape] then
                    local mask = bf:CreateMaskTexture()
                    mask:SetAllPoints(bf)
                    mask:SetTexture(SHAPE_MASKS[btnShape], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    iconTex:AddMaskTexture(mask)
                    bgTex:AddMaskTexture(mask)
                    -- Store shape metadata for glow preview (StartNativeGlow reads these)
                    bf._shapeApplied = true
                    bf._shapeName = btnShape
                    bf._shapeMask = mask
                    -- Shape border (always created for hover/accent tinting; invisible when brdSize == 0)
                    if SHAPE_BORDERS and SHAPE_BORDERS[btnShape] then
                        local sbt = bf:CreateTexture(nil, "OVERLAY", nil, 6)
                        sbt:SetAllPoints(bf)
                        sbt:SetTexture(SHAPE_BORDERS[btnShape])
                        -- Direct ref for the accent/hover tint sites below. Never
                        -- locate this texture by scanning GetRegions: a freshly
                        -- tracked CD's icon region carries secret values, and
                        -- GetDrawLayer comparisons on it error out mid page-build.
                        bf._sbt = sbt
                        if brdSize > 0 then
                            local cr, cg, cb = brdColor.r, brdColor.g, brdColor.b
                            if brdClassColor then
                                local _, ct = UnitClass("player")
                                if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
                            end
                            sbt:SetVertexColor(cr, cg, cb, brdColor.a or 1)
                        else
                            sbt:SetVertexColor(0, 0, 0, 0)
                        end
                    end
                elseif brdSize > 0 then
                    -- Square borders via unified PP system
                    local cr, cg, cb, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
                    if brdClassColor then
                        local _, ct = UnitClass("player")
                        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
                    end
                    local PP = EllesmereUI and EllesmereUI.PP
                    if PP then PP.CreateBorder(bf, cr, cg, cb, ca, brdSize, "OVERLAY", 7) end
                end

                -- Accent border for buttons that have assignments
                local assignKey
                if isCDMBar and realBtn and realBtn.cooldownID then
                    assignKey = "cdm_" .. realBtn.cooldownID
                else
                    assignKey = barIdx .. "_" .. i
                end
                bf._assignKey = assignKey
                local assigns = bgData.assignments[assignKey]
                local hasAssign = assigns and #assigns > 0

                -- Pre-create accent border on every button (hidden unless needed)
                local accentCont = CreateFrame("Frame", nil, bf)
                accentCont:SetAllPoints()
                accentCont:SetFrameLevel(bf:GetFrameLevel() + 2)
                local PP2 = EllesmereUI and EllesmereUI.PP

                -- Active button gets accent border; assigned (non-active) buttons get white border
                -- For custom shapes, tint the shape border instead of showing square PP borders
                local isCustomShape = btnShape ~= "none" and btnShape ~= "cropped" and btnShape ~= "square" and btnShape ~= "csquare"
                    and SHAPE_MASKS and SHAPE_MASKS[btnShape]
                local accentBrd
                if not isCustomShape then
                    if isSelected then
                        accentBrd = PP2 and PP2.CreateBorder(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1, 2, "OVERLAY", 7)
                    else
                        accentBrd = PP2 and PP2.CreateBorder(accentCont, 1, 1, 1, 0.6, 2, "OVERLAY", 7)
                    end
                    if accentBrd then accentBrd:Hide() end
                end

                -- Show active state
                if isSelected then
                    if isCustomShape then
                        -- Tint shape border to accent color
                        if bf._sbt then
                            bf._sbt:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                        end
                    elseif accentBrd then
                        accentBrd:Show()
                    end
                end

                -- Show white border for assigned buttons (even if not active)
                if hasAssign and not isSelected then
                    if isCustomShape then
                        if bf._sbt then
                            bf._sbt:SetVertexColor(1, 1, 1, 0.6)
                        end
                    elseif accentBrd then
                        accentBrd:Show()
                    end
                end

                -- Store refs so click handler can activate inline
                bf._accentBrd = accentBrd
                bf._accentCont = accentCont

                -- Button alpha: unassigned = 50%, assigned/active = 100%
                if isSelected or hasAssign then
                    bf:SetAlpha(1)
                else
                    bf:SetAlpha(0.50)
                end

                -- Hover highlight: switch border to accent on hover
                -- Active button doesn't need hover (already accent)
                -- Store shape border ref for hover tinting
                bf._shapeBorderTex = isCustomShape and bf._sbt or nil
                local origBrdR, origBrdG, origBrdB, origBrdA = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
                if isCDMBar and cdmBd then
                    origBrdR = cdmBd.borderR or 0
                    origBrdG = cdmBd.borderG or 0
                    origBrdB = cdmBd.borderB or 0
                    origBrdA = (cdmBd.borderSize or 1) > 0 and (cdmBd.borderA or 1) or 0
                elseif brdSize == 0 then
                    origBrdA = 0
                end
                if not isSelected and not nonGlowable then
                    if hasAssign then
                        bf:SetScript("OnEnter", function()
                            if isCustomShape and bf._shapeBorderTex then
                                bf._shapeBorderTex:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            elseif PP2 and accentCont then
                                PP2.SetBorderColor(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            end
                        end)
                        bf:SetScript("OnLeave", function()
                            if isCustomShape and bf._shapeBorderTex then
                                bf._shapeBorderTex:SetVertexColor(1, 1, 1, 0.6)
                            elseif PP2 and accentCont then
                                PP2.SetBorderColor(accentCont, 1, 1, 1, 0.6)
                            end
                        end)
                    else
                        bf:SetScript("OnEnter", function()
                            bf:SetAlpha(0.55)
                            if isCustomShape and bf._shapeBorderTex then
                                bf._shapeBorderTex:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            else
                                if PP2 and accentCont then PP2.SetBorderColor(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1) end
                                if accentBrd then accentBrd:Show() end
                            end
                        end)
                        bf:SetScript("OnLeave", function()
                            bf:SetAlpha(0.50)
                            if isCustomShape and bf._shapeBorderTex then
                                bf._shapeBorderTex:SetVertexColor(origBrdR, origBrdG, origBrdB, origBrdA)
                            else
                                if accentBrd then accentBrd:Hide() end
                            end
                        end)
                    end
                end

                -- Helper: visually activate this button without a full rebuild
                local function ActivateInline()
                    local PP3 = EllesmereUI and EllesmereUI.PP
                    -- Clear previous active button visuals
                    if headerFrame._activeBtnRef and headerFrame._activeBtnRef ~= bf then
                        local prev = headerFrame._activeBtnRef
                        -- Revert border: if prev has assignments, switch to white; otherwise hide
                        local prevKey = prev._assignKey or (barIdx .. "_" .. (prev._btnIdx or 0))
                        local prevAssigns = bgData.assignments[prevKey]
                        local prevHasAssign = prevAssigns and #prevAssigns > 0
                        if prevHasAssign then
                            if PP3 and prev._accentCont then PP3.SetBorderColor(prev._accentCont, 1, 1, 1, 0.6) end
                        else
                            if prev._accentBrd then prev._accentBrd:Hide() end
                            prev:SetAlpha(0.50)
                            -- Restore hover scripts
                            prev:SetScript("OnEnter", function()
                                prev:SetAlpha(0.55)
                                if PP3 and prev._accentCont then PP3.SetBorderColor(prev._accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1) end
                                if prev._accentBrd then prev._accentBrd:Show() end
                            end)
                            prev:SetScript("OnLeave", function()
                                prev:SetAlpha(0.50)
                                if prev._accentBrd then prev._accentBrd:Hide() end
                            end)
                        end
                    end
                    -- Show this button as active with accent color + full alpha
                    bf:SetAlpha(1)
                    if PP3 and accentCont then PP3.SetBorderColor(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1) end
                    if accentBrd then accentBrd:Show() end
                    -- Remove hover toggle since border is now permanent
                    bf:SetScript("OnEnter", nil)
                    bf:SetScript("OnLeave", nil)
                    headerFrame._activeBtnRef = bf
                end
                bf._btnIdx = i

                -- Track the initially active button
                if isSelected then headerFrame._activeBtnRef = bf end

                -- Left click: always select this button; also open spell picker if no assignments
                -- Right click: always toggle spell picker
                bf:SetScript("OnClick", function(self, button)
                    -- Presets / custom IDs / racials / trinkets / custom buffs are not
                    -- glow-assignable: ignore both clicks so no glow can be added.
                    if nonGlowable then return end
                    local pickerOpen = _bgSpellPickerMenu and _bgSpellPickerMenu:IsShown()
                    local pickerOnThis = pickerOpen and _bgSpellPickerMenu._btnIdx == i

                    if button == "LeftButton" then
                        -- Close picker first if open (before rebuild destroys anchor)
                        if pickerOpen then _bgSpellPickerMenu:Hide() end
                        _glowSelectedButton = i
                        ActivateInline()
                        EllesmereUI:RefreshPage(true)
                    elseif button == "RightButton" then
                        if pickerOnThis then
                            -- Toggle off: just close the picker
                            _bgSpellPickerMenu:Hide()
                            return
                        end
                        -- Close any other picker first
                        if pickerOpen then _bgSpellPickerMenu:Hide() end
                        _glowSelectedButton = i
                        ActivateInline()
                        EllesmereUI:RefreshPage(true)
                        C_Timer.After(0, function()
                            local newBf = _glowBtnFrames[i]
                            if newBf then
                                ShowBarGlowSpellPicker(newBf, barIdx, i, function()
                                    _glowSelectedButton = i
                                    EllesmereUI:RefreshPage(true)
                                end, newBf._assignKey)
                            end
                        end)
                    end
                end)
            end

            -- Tip text below the button grid
            local tipFS = headerFrame:CreateFontString(nil, "OVERLAY")
            tipFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            tipFS:SetTextColor(1, 1, 1, 0.70)
            tipFS:SetPoint("TOP", headerFrame, "TOP", 0, -(20 + DD_H + 20 + scaledBtnH + 20))
            tipFS:SetText(EllesmereUI.L("Left click a button to edit its glow, right click to add a new glow"))

            return 20 + DD_H + 20 + scaledBtnH + 20 + 14 + 15
        end

        EllesmereUI:SetContentHeader(_glowHeaderBuilder)

        -- Live-update preview icons when the action bar pages (stance shift,
        -- dragonriding, mount/dismount, vehicle, etc.)
        --
        -- Skipped during a hidden search pre-build: this listener is cleaned
        -- up via parent:HookScript("OnHide", ...), which depends on the
        -- pre-build wrapper's OnHide actually firing when hidden -- not
        -- guaranteed, since the wrapper is parented under an already-hidden
        -- frame and never becomes effectively visible in between. If it
        -- doesn't fire, this listener (and the RefreshPage(true) it queues
        -- on every action-bar-page/mount change) would leak for the rest of
        -- the session. There's nothing to preview during indexing anyway.
        if not EllesmereUI._prebuilding then
            local pageListener = CreateFrame("Frame")
            local pagePending = false
            pageListener:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
            pageListener:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
            pageListener:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
            pageListener:SetScript("OnEvent", function()
                if pagePending then return end
                pagePending = true
                C_Timer.After(0.15, function()
                    pagePending = false
                    EllesmereUI:RefreshPage(true)
                end)
            end)
            parent:HookScript("OnHide", function()
                pageListener:UnregisterAllEvents()
            end)
        end

        -------------------------------------------------------------------
        --  Scrollable content area
        -------------------------------------------------------------------

        _, h = W:Spacer(parent, y, 8);  y = y - h

        -- A selected slot that is (now) a preset/custom/racial/trinket icon is not
        -- glow-assignable -- fall back to the hint instead of showing glow settings.
        if curBtn and type(curBar) == "string" then
            local cdmIcons = ns.cdmBarIcons and ns.cdmBarIcons[curBar]
            if IsNonGlowableCDMIcon(cdmIcons and cdmIcons[curBtn]) then
                curBtn = nil
            end
        end

        if not curBtn then
            -- No button selected: show centered hint text
            local hintFrame = CreateFrame("Frame", nil, parent)
            hintFrame:SetSize(parent:GetWidth(), 40)
            hintFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
            local hintText = hintFrame:CreateFontString(nil, "OVERLAY")
            hintText:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            hintText:SetTextColor(0.5, 0.5, 0.5, 1)
            hintText:SetPoint("CENTER")
            hintText:SetText(EllesmereUI.L("Left click a button to edit its glow, right click to add a new glow"))
            y = y - 40
        else
            -- Button selected: show per-buff sections
            local assignKey
            local isCurCDM = (type(curBar) == "string")
            if isCurCDM then
                local cdmIcons = ns.cdmBarIcons and ns.cdmBarIcons[curBar]
                local icon = cdmIcons and cdmIcons[curBtn]
                if icon and icon.cooldownID then
                    assignKey = "cdm_" .. icon.cooldownID
                end
            end
            if not assignKey then assignKey = curBar .. "_" .. curBtn end
            local buffList = bg.assignments[assignKey] or {}
            parent._showRowDivider = true

            if #buffList == 0 then
                _, h = W:Spacer(parent, y, 8);  y = y - h
                local emptyFrame = CreateFrame("Frame", nil, parent)
                emptyFrame:SetSize(parent:GetWidth(), 30)
                emptyFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
                local emptyText = emptyFrame:CreateFontString(nil, "OVERLAY")
                emptyText:SetFont(FONT_PATH, 12, GetCDMOptOutline())
                emptyText:SetTextColor(0.5, 0.5, 0.5, 1)
                emptyText:SetPoint("LEFT", 22, 0)
                emptyText:SetText(EllesmereUI.L("No buffs assigned. Right click a button in the preview to assign buffs."))
                y = y - 30
            else
                local glowLabels, glowOrder = GetGlowStyleValues()

                for aIdx, entry in ipairs(buffList) do
                    local buffName = "Unknown"
                    if entry.spellID and entry.spellID > 0 then
                        buffName = C_Spell.GetSpellName(entry.spellID) or ("Spell " .. entry.spellID)
                    end

                    -- Get the button's spell name for the header. cooldownID is a
                    -- CDM cooldown-viewer id, NOT a spell id -- feeding it straight to
                    -- GetSpellName returns an unrelated ("random") spell. Resolve the
                    -- icon's real spell id with the same canonical resolver the
                    -- CD/utility bars use, falling back to the cooldown viewer info.
                    local btnSpellName = "Button " .. curBtn
                    if isCurCDM then
                        local cdmIcons = ns.cdmBarIcons and ns.cdmBarIcons[curBar]
                        local icon = cdmIcons and cdmIcons[curBtn]
                        if icon then
                            local sid = ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(icon)
                            if (not sid) and icon.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(icon.cooldownID)
                                if info and info.spellID and info.spellID > 0 then sid = info.spellID end
                            end
                            if sid then btnSpellName = C_Spell.GetSpellName(sid) or btnSpellName end
                        end
                    else
                        local prefix = BAR_BUTTON_PREFIXES[curBar]
                        local realBtn = prefix and _G[prefix .. curBtn]
                        if realBtn and realBtn.action then
                            local aType, aID = GetActionInfo(realBtn.action)
                            if aType == "spell" and aID then
                                btnSpellName = C_Spell.GetSpellName(aID) or btnSpellName
                            elseif aType == "macro" then
                                local mName = GetMacroInfo(aID)
                                if mName then btnSpellName = mName end
                            end
                        end
                    end

                    -- Section header per buff
                    _, h = W:SectionHeader(parent, btnSpellName .. " x " .. buffName, y);  y = y - h

                    -- Row 1: Glow When | Only In Combat
                    local modeRow
                    local removeAIdx = aIdx
                    modeRow, h = W:DualRow(parent, y,
                        { type = "dropdown", text = "Glow When",
                          values = BG_MODE_VALUES, order = BG_MODE_ORDER,
                          getValue = function() return entry.mode or "ACTIVE" end,
                          setValue = function(v)
                              entry.mode = v
                              Refresh()
                          end,
                        },
                        { type = "toggle", text = "Only In Combat",
                          getValue = function() return entry.onlyInCombat == true end,
                          setValue = function(v)
                              entry.onlyInCombat = v or nil
                              Refresh()
                          end,
                        }
                    );  y = y - h

                    -- Helper: resolve current glow color and restart preview if active
                    local pvKey = assignKey .. "_" .. aIdx
                    local function RefreshPreviewGlow()
                        if not _bgPreviewGlowActive[pvKey] then return end
                        local ov = _bgPreviewGlowOverlays[pvKey]
                        if not ov then return end
                        local style = BarHasCustomShape(curBar) and 2 or (entry.glowStyle or 1)
                        local cr, cg, cb = 1, 0.82, 0.1
                        if entry.classColor then
                            local _, ct = UnitClass("player")
                            if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
                        elseif entry.glowColor then
                            cr, cg, cb = entry.glowColor.r, entry.glowColor.g, entry.glowColor.b
                        end
                        ns.StopNativeGlow(ov)
                        ns.StartNativeGlow(ov, style, cr, cg, cb)
                    end

                    -- Row 2: Glow Type (with eyeball) | Class Colored Glow (with swatch)
                    local glowRow
                    glowRow, h = W:DualRow(parent, y,
                        { type = "dropdown", text = "Glow Type",
                          values = glowLabels, order = glowOrder,
                          disabled = function() return BarHasCustomShape(curBar) end,
                          disabledTooltip = "This option is not available for custom shaped icons",
                          getValue = function()
                              if BarHasCustomShape(curBar) then return 2 end
                              return entry.glowStyle or 1
                          end,
                          setValue = function(v)
                              entry.glowStyle = tonumber(v) or 1
                              Refresh()
                              RefreshPreviewGlow()
                          end,
                        },
                        { type = "toggle", text = "Class Colored Glow",
                          getValue = function() return entry.classColor end,
                          setValue = function(v)
                              entry.classColor = v
                              Refresh()
                              RefreshPreviewGlow()
                              EllesmereUI:RefreshPage()
                          end,
                        }
                    );  y = y - h

                    -- Eyeball preview toggle (on left region of glow type row)
                    do
                        local EYE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
                        local EYE_VIS   = EYE_MEDIA .. "eui-visible.png"
                        local EYE_INVIS = EYE_MEDIA .. "eui-invisible.png"
                        local leftRgn = glowRow._leftRegion
                        if leftRgn and leftRgn._control then
                            local eyeBtn = CreateFrame("Button", nil, leftRgn)
                            eyeBtn:SetSize(26, 26)
                            eyeBtn:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
                            eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                            eyeBtn:SetAlpha(0.4)
                            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
                            eyeTex:SetAllPoints()
                            local function RefreshEye()
                                eyeTex:SetTexture(_bgPreviewGlowActive[pvKey] and EYE_INVIS or EYE_VIS)
                            end
                            RefreshEye()
                            eyeBtn:SetScript("OnClick", function()
                                local previewBtn = _glowBtnFrames[curBtn]
                                if not previewBtn then return end
                                if not _bgPreviewGlowOverlays[pvKey] then
                                    local ov = CreateFrame("Frame", nil, previewBtn)
                                    ov:SetAllPoints(previewBtn)
                                    ov:SetFrameLevel(previewBtn:GetFrameLevel() + 10)
                                    _bgPreviewGlowOverlays[pvKey] = ov
                                end
                                local ov = _bgPreviewGlowOverlays[pvKey]
                                if _bgPreviewGlowActive[pvKey] then
                                    ns.StopNativeGlow(ov)
                                    _bgPreviewGlowActive[pvKey] = false
                                    -- Restore accent border
                                    if previewBtn._accentBrd then previewBtn._accentBrd:Show() end
                                else
                                    local style = BarHasCustomShape(curBar) and 2 or (entry.glowStyle or 1)
                                    local cr, cg, cb = 1, 0.82, 0.1
                                    if entry.classColor then
                                        local _, ct = UnitClass("player")
                                        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
                                    elseif entry.glowColor then
                                        cr, cg, cb = entry.glowColor.r, entry.glowColor.g, entry.glowColor.b
                                    end
                                    ns.StartNativeGlow(ov, style, cr, cg, cb)
                                    _bgPreviewGlowActive[pvKey] = true
                                    -- Hide accent border so glow is visible
                                    if previewBtn._accentBrd then previewBtn._accentBrd:Hide() end
                                end
                                RefreshEye()
                            end)
                            eyeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                            eyeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                        end
                    end

                    -- Inline color swatch for glow color (on right region of row 2)
                    do
                        local rightRgn = glowRow._rightRegion
                        if rightRgn and rightRgn._control and EllesmereUI.BuildColorSwatch then
                            local toggle = rightRgn._control
                            local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(
                                rightRgn, glowRow:GetFrameLevel() + 3,
                                function()
                                    if entry.classColor then
                                        local _, ct = UnitClass("player")
                                        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then return cc.r, cc.g, cc.b end end
                                    end
                                    local c = entry.glowColor or { r = 1, g = 0.82, b = 0.1 }
                                    return c.r, c.g, c.b
                                end,
                                function(r, g, b)
                                    entry.glowColor = { r = r, g = g, b = b }
                                    entry.classColor = false
                                    Refresh()
                                    RefreshPreviewGlow()
                                    EllesmereUI:RefreshPage()
                                end,
                                false, 20)
                            PP.Point(glowSwatch, "RIGHT", toggle, "LEFT", -8, 0)
                        end
                    end

                    -- Row 3: Remove Glow on its own row (left slot), after the glow config.
                    local removeRow
                    removeRow, h = W:DualRow(parent, y,
                        { type = "labeledButton", text = "Remove Glow", buttonText = "Remove", width = 150,
                          onClick = function()
                              table.remove(buffList, removeAIdx)
                              if #buffList == 0 then
                                  bg.assignments[assignKey] = nil
                              end
                              Refresh()
                              EllesmereUI:RefreshPage(true)
                          end,
                        },
                        { type = "spacer" }
                    );  y = y - h

                    -- Buff icon to the LEFT of the Remove button
                    do
                        local leftRgn = removeRow._leftRegion
                        if leftRgn and leftRgn._control then
                            local btn = leftRgn._control
                            local btnH = btn:GetHeight()
                            local ico = leftRgn:CreateTexture(nil, "ARTWORK")
                            ico:SetSize(btnH, btnH)
                            PP.Point(ico, "RIGHT", btn, "LEFT", -8, 0)
                            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                            if entry.spellID and entry.spellID > 0 then
                                local info = C_Spell.GetSpellInfo(entry.spellID)
                                if info and info.iconID then
                                    ico:SetTexture(info.iconID)
                                end
                            end
                        end
                    end
                end
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Buff Bars page per-bar tracked buff bars with individual settings)
    ---------------------------------------------------------------------------
    local _tbbSelectedBar = 1
    local _tbbSelectedGroup      -- nil = editing a bar; gid = editing that group
    local _tbbDDBtn              -- live management-dropdown button (picker anchor)
    local _tbbNavigateFn         -- set per page build: click-to-scroll handler

    ---------------------------------------------------------------------------
    --  Popout preview: docked to the left edge of the options panel (same
    --  pattern as the raid frame overlay preview). Preview bars are built and
    --  skinned by the SAME runtime functions as the live bars
    --  (ns.CreateTBBBarFrame / ns.ApplyTBBBarSettings), then dressed with
    --  sample fill/timer/stacks values. Bar mode shows the selected bar with
    --  click-to-scroll element overlays; group mode shows every bar of the
    --  selected group chained with the group's grow/spacing, each clickable
    --  to jump into editing that bar.
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

    -- Pooled hover/click overlay on a preview element (green border, like the
    -- unit frame preview overlays). Retargeted every refresh.
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

    -- Attach nav overlays for one preview bar. Bar mode: element overlays
    -- scroll to and flash their option rows. Group mode: one whole-bar
    -- overlay that selects the bar for editing.
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
                -- Anchor by justification: the name FontString has an explicit
                -- width wider than its string, so its CENTER is not where the
                -- glyphs render.
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

    -- Preview-only dressing on top of the live skinning: sample fill, sample
    -- timer/stacks text, the resolved name/icon, and the unassigned overlay.
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
        -- Icon texture (same resolution as the live build; question mark when
        -- no buff is assigned yet)
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
        -- Unassigned: dim ALL bar content (fill, texts, icon, border) under a
        -- black overlay frame with the centered hint on top. A frame above
        -- the bar's own layers guarantees it draws over the fill/gradient
        -- stack, matching the old preview's darkening.
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
        -- Above the bar's text overlay (+6) and border (+5), below the click
        -- overlays (+30).
        wrap._pvDarkFrame:SetFrameLevel(wrap:GetFrameLevel() + 20)
        wrap._pvHint:ClearAllPoints()
        wrap._pvHint:SetPoint("CENTER", sb, "CENTER", 0, 0)
        wrap._pvDarkFrame:SetShown(unassigned)
    end

    -- Vertical headroom for texts positioned above/below the bar (they anchor
    -- outside the bar's bounds).
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

    -- HARD gate for BOTH Tracking Bars preview systems (popout preview and
    -- unlock-style placeholders): they must never be visible unless the
    -- options panel is actually OPEN on the Tracking Bars page. Checking
    -- activeModule/activePage alone is NOT enough -- both persist after the
    -- panel closes, and RefreshPage / event-driven refreshes (saved
    -- positions, spec or instance events) rebuild this page with the panel
    -- hidden. Every show path funnels through this check.
    local function TBBPreviewAllowed()
        if not (EllesmereUI.IsShown and EllesmereUI:IsShown()) then return false end
        -- nil = mid-build (page state not stamped yet); builders only run for
        -- the page being shown, so only a definite mismatch blocks.
        local am = EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
        local ap = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
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
                -- Width-gated geometry (charge hash lines, threshold ticks)
                -- silently skips while the fill's anchor-derived size is
                -- still 0 on a fresh pool bar. Live bars re-drive from the
                -- timer tick; previews have no tick, so re-drive when the
                -- size resolves.
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
            -- MEDIUM default); lift the preview into the popout's strata AFTER
            -- each apply and re-assert the child levels the constructor
            -- established (a parent strata change resets child frame levels).
            -- Guarded so refreshes that didn't touch strata skip the re-stack
            -- (level checked too: a bar whose OWN strata is the popout's would
            -- otherwise dodge the lift and keep the apply-path level).
            local base = oc:GetFrameLevel() + 20
            if wrap:GetFrameStrata() ~= "FULLSCREEN_DIALOG" or wrap:GetFrameLevel() ~= base then
                wrap:SetFrameStrata("FULLSCREEN_DIALOG")
                wrap:SetFrameLevel(base)
                local sb = wrap._bar
                if sb then sb:SetFrameLevel(base + 1) end
                if wrap._gradClip and sb then wrap._gradClip:SetFrameLevel(sb:GetFrameLevel() + 1) end
                if wrap._chargeHashFillClip and sb then wrap._chargeHashFillClip:SetFrameLevel(sb:GetFrameLevel() + 1) end
                if wrap._threshOverlay and sb then wrap._threshOverlay:SetFrameLevel(sb:GetFrameLevel() + 2) end
                if wrap._sparkOverlay and sb then wrap._sparkOverlay:SetFrameLevel(sb:GetFrameLevel() + 2) end
                if wrap._chargeHashOverlay and sb then wrap._chargeHashOverlay:SetFrameLevel(sb:GetFrameLevel() + 4) end
                if wrap._barBorder then wrap._barBorder:SetFrameLevel(base + 5) end
                if wrap._pandemicGlowOverlay then wrap._pandemicGlowOverlay:SetFrameLevel(base + 7) end
                if wrap._textOverlay and sb then wrap._textOverlay:SetFrameLevel(sb:GetFrameLevel() + 7) end
            end
            DressTBBPopoutBar(wrap, e.cfg)
            -- Reused pool bars already have a resolved size, so OnSizeChanged
            -- may never fire for this refresh: consume the deferred tick-mark
            -- pass here (the apply path drew hash lines itself when sized).
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

        -- Title
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
        -- Same hard gate as the popout: never show (and never set placeholder
        -- mode) with the panel closed or another page in front. Inline hide --
        -- HideTBBPlaceholder is declared below this function.
        if not TBBPreviewAllowed() then
            ns._tbbPlaceholderMode = false
            for _, ph in ipairs(_tbbPlaceholders) do
                if ph then ph:Hide() end
            end
            HideTBBPopout()
            return
        end
        ns._tbbPlaceholderMode = true
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
        -- The popout preview lives and dies with the page, same as the
        -- placeholders (this runs on every page-leave / panel-close path).
        HideTBBPopout()
    end
    ns.HideTBBPlaceholders = HideTBBPlaceholder
    ns.ShowTBBPlaceholders = UpdateTBBPlaceholder
    EllesmereUI:RegisterOnHide(HideTBBPlaceholder)
    -- Re-show placeholders when the panel re-opens onto the Tracking Bars page.
    -- Exiting unlock mode back to the SAME page it was opened from skips
    -- SelectPage (currentPage == restorePage in EUI_UnlockMode close), so the
    -- page-restore hook that normally calls ShowTBBPlaceholders never fires --
    -- the panel just re-Shows. This OnShow re-asserts the placeholders then.
    EllesmereUI:RegisterOnShow(function()
        local am = EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
        local ap = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
        if am == "EllesmereUICooldownManager" and ap == PAGE_BUFF_BARS then
            UpdateTBBPlaceholder()
            RefreshTBBPopout()
        end
    end)

    -- Refresh the CDM options pages on spec change. Every CDM page (Bars, Bar
    -- Glows, Tracking Bars) is per-spec, and so is the page-local selected-bar
    -- index. The options panel caches built pages, so after a spec swap the cache
    -- holds wrappers built for the PREVIOUS spec. A shared-profile spec swap never
    -- runs RefreshAllAddons (which is what clears the cache on a profile swap), so
    -- without an explicit invalidation, reopening the panel serves the stale page
    -- (the previous spec's selected bar -- e.g. Balance's "Eclipse (Solar)" still
    -- shown on Feral). Drop the CDM page cache so the next open rebuilds fresh; if
    -- a CDM page is open right now, rebuild it in place via RefreshPage.
    local _tbbRefreshFn
    local function HandleTBBSpecChange()
        _tbbSelectedBar = 1
        _tbbSelectedGroup = nil
        -- Every CDM page is per-spec; drop the cached wrappers so navigating to
        -- any of them rebuilds against the new spec.
        if EllesmereUI.InvalidateModulePageCache then
            EllesmereUI:InvalidateModulePageCache("EllesmereUICooldownManager")
        end
        if EllesmereUI.IsShown and EllesmereUI:IsShown()
            and EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule() == "EllesmereUICooldownManager"
            and EllesmereUI.RefreshPage then
            -- Panel open on a CDM page: rebuild now (content-header dropdown + body).
            EllesmereUI:RefreshPage(true)
        else
            -- Panel closed (or on another module). Reopening takes the fast
            -- RefreshPage path (re-reads body widgets but never rebuilds the
            -- content-header dropdown), and SelectPage early-returns when the last
            -- page is reselected -- so the dropdown would keep the previous spec's
            -- bar. Flag a cold rebuild for the next show so the page looks freshly
            -- built, matching a first open after reload.
            ns._cdmColdRebuildOnShow = true
        end
    end

    -- Authoritative trigger: CDM's ProcessSpecChange calls this AFTER it swaps the
    -- spec-key cache (_cachedSpecKey), so the rebuild reads the NEW spec. The
    -- PLAYER_SPECIALIZATION_CHANGED watcher below is a backup that also covers the
    -- panel-closed cache drop; that event can fire before SPELLS_CHANGED swaps the
    -- cache, so an in-place rebuild driven from it alone could read the old spec --
    -- but the ProcessSpecChange call always lands afterward and corrects it.
    ns.OnTBBSpecChanged = HandleTBBSpecChange

    local _tbbSpecWatcher = CreateFrame("Frame")
    _tbbSpecWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _tbbSpecWatcher:SetScript("OnEvent", HandleTBBSpecChange)

    -- Bars auto-added while the panel sits on the Tracking Bars page (e.g. the
    -- user drags a new spell into Blizzard's Tracked Bars section and comes
    -- back): rebuild the open page so the new bars appear immediately.
    ns.OnTBBBarsAutoAdded = function()
        if EllesmereUI.IsShown and EllesmereUI:IsShown()
            and EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule() == "EllesmereUICooldownManager"
            and EllesmereUI.GetActivePage and EllesmereUI:GetActivePage() == PAGE_BUFF_BARS
            and EllesmereUI.RefreshPage then
            EllesmereUI:RefreshPage(true)
        end
    end

    -- A spec swap while the panel is CLOSED can't rebuild the page (nothing is
    -- shown). Honor the pending cold rebuild here so reopening directly onto a CDM
    -- page rebuilds the dropdown + body against the new spec, like a fresh open.
    EllesmereUI:RegisterOnShow(function()
        if not ns._cdmColdRebuildOnShow then return end
        if EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule() == "EllesmereUICooldownManager"
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
            popBg:SetAllPoints(); popBg:SetColorTexture(0.06, 0.08, 0.10, 1)
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
            sidBg:SetAllPoints(); sidBg:SetColorTexture(0.04, 0.06, 0.08, 1)
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
            durBg:SetAllPoints(); durBg:SetColorTexture(0.04, 0.06, 0.08, 1)
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
            -- Manually-entered id: no live frame to read the base from. Clear any
            -- stale base; MatchFrameToConfig self-heals it if/when talented.
            barCfg.baseSpellID    = nil
            barCfg.name           = C_Spell.GetSpellName(sid)
            Refresh()
            ns.BuildTrackedBuffBars()
            if onChanged then onChanged() end
        end)

        popup._dimmer:Show()
        popup._sidBox:SetFocus()
    end

    local function ShowTBBSpellPicker(anchorFrame, barCfg, onChanged)
        if _tbbSpellPickerMenu then _tbbSpellPickerMenu:Hide() end

        local trackedBars = ns.GetTrackedBarSpells and ns.GetTrackedBarSpells(true) or {}
        local popular = ns.TBB_POPULAR_BUFFS or {}

        -- No early bail on empty trackedBars: the picker still shows
        -- popular presets and the custom spell ID input.

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

        -- Divider before popular buffs
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
        for _, entry in ipairs(popular) do
            -- tbbOnly presets (e.g. debuff-driven Bloodlust) carry a sentinel
            -- class to hide from the cooldown/utility item picker; the TBB
            -- picker overrides that and always shows them.
            if entry.tbbOnly or not entry.class or entry.class == _tbbPClass then
                MakePopularItem(entry)
            end
        end

        -- Divider before tracked-bar entries
        if #trackedBars > 0 then
            local div2 = inner:CreateTexture(nil, "ARTWORK")
            div2:SetHeight(1); div2:SetColorTexture(1, 1, 1, 0.10)
            div2:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div2:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        local function MakeSpellItem(sp)
            -- Every spell here came from BuffBarCooldownViewer enumeration,
            -- so it's by definition tracked. No popup needed.
            -- Check if spell is already on another Tracking Bar
            local usedOnBar = ns.SpellUsedOnAnyOtherTBB and ns.SpellUsedOnAnyOtherTBB(sp.spellID, nil)
            local isSelected = not barCfg.popularKey and not barCfg.spellIDs
                             and barCfg.trackType ~= "cooldown"
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

            -- Tracked-but-untalented bar spells (no live BuffBar frame) stay
            -- fully clickable but render desaturated with a hint, matching the
            -- CD/utility and buff pickers, so bars can be set without swapping
            -- talents.
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
                -- Capture the BASE spell id for hero-talent override spells so
                -- the bar keeps tracking after the talent is removed. When the
                -- picked spell is an active override (e.g. Death Charge), the
                -- live cooldownInfo reports the base (Death's Advance) in
                -- info.spellID; store it only when it differs from the picked id.
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

        for _, sp in ipairs(trackedBars) do MakeSpellItem(sp) end

        -- "Cooldowns" section: pick a spell COOLDOWN to track instead of a
        -- buff (cfg.trackType = "cooldown"). Sourced from the Essential +
        -- Utility pools plus the settings catalog. Skipped entirely when the
        -- list is empty so the picker stays identical to before.
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
                -- Gray-out check is scoped to OTHER cooldown-tracking bars:
                -- a buff bar for the same spell never blocks this pick.
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

                -- Untalented catalog spells stay clickable but render
                -- desaturated with a hint, matching the buff rows above.
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
                    -- Capture the BASE spell id for hero-talent override spells
                    -- so the bar keeps tracking after the talent is removed.
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

        -- "Missing Spells?" footer: centered, accent-colored prompt that opens
        -- Blizzard's CDM and closes EUI options, matching the CD/utility picker.
        do
            local fDiv = inner:CreateTexture(nil, "ARTWORK")
            fDiv:SetHeight(1); fDiv:SetColorTexture(1, 1, 1, 0.10)
            fDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            fDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9

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
            mbFS:SetText(EllesmereUI.L("Missing Spells?") .. "\n" .. EllesmereUI.L("Add in Blizzard CDM"))

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

    -- Select a bar and open the buff picker for it, anchored to the management
    -- dropdown. Used by the dropdown's bar rows (icon click / unassigned bar
    -- click) -- the page refresh runs first so the picker anchors to the
    -- freshly built dropdown button.
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
                        onConfirm = function() ReloadUI() end,
                    })
                end,
                function()
                    if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
                end, 310);  y = y - h
            return math.abs(y)
        end

        -- Pre-populate bars for spells newly added to Blizzard's Tracked Bars
        -- section before reading the bar list, so the page always shows them.
        if ns.EnsureTBBAutoBars and ns.EnsureTBBAutoBars() > 0 then
            ns.BuildTrackedBuffBars()
        end

        local tbb = ns.GetTrackedBuffBars()
        -- Hold the per-group orientation invariant before any widget reads
        -- the configs (the rebuild at the page tail runs after they do).
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

        -- Validate the group selection against the live group list (groups
        -- dissolve when their last bar is deleted).
        if _tbbSelectedGroup then
            local ok = false
            for _, g in ipairs(ns.TBBGroupIDsInUse()) do
                if g == _tbbSelectedGroup then ok = true; break end
            end
            if not ok then _tbbSelectedGroup = nil end
        end

        -- The preview mirrors whatever is being edited: the selected bar, or
        -- the selected group's style source (its anchor bar).
        local function PreviewCfg()
            if _tbbSelectedGroup then
                return ns.TBBGroupStyleSource(_tbbSelectedGroup)
            end
            return SelectedTBB()
        end

        -- Display name for a group: the user-given name, or "Group N".
        local function GroupLabel(gid)
            return (ns.TBBGroupName and ns.TBBGroupName(gid))
                or (EllesmereUI.L("Group") .. " " .. gid)
        end

        -------------------------------------------------------------------
        --  CLICK NAVIGATION (preview elements -> option rows)
        --  The map lives on parent._tbbClickTargets (populated by the bar-mode
        --  section build below); preview overlays resolve it at click time so
        --  a header rebuild never holds stale row references.
        -------------------------------------------------------------------
        local _navGlowFrame
        local function PlaySettingGlow(targetFrame)
            if not targetFrame then return end
            if not _navGlowFrame then
                _navGlowFrame = CreateFrame("Frame")
                local c = EllesmereUI.ELLESMERE_GREEN
                local function MkEdge()
                    local t = _navGlowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    t:SetColorTexture(c.r, c.g, c.b, 1)
                    return t
                end
                local top, bot, lft, rgt = MkEdge(), MkEdge(), MkEdge(), MkEdge()
                top:SetHeight(2); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
                bot:SetHeight(2); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
                lft:SetWidth(2)
                lft:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); lft:SetPoint("BOTTOMLEFT", bot, "TOPLEFT")
                rgt:SetWidth(2)
                rgt:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT"); rgt:SetPoint("BOTTOMRIGHT", bot, "TOPRIGHT")
            end
            _navGlowFrame:SetParent(targetFrame)
            _navGlowFrame:SetAllPoints(targetFrame)
            _navGlowFrame:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
            _navGlowFrame:SetAlpha(1)
            _navGlowFrame:Show()
            local elapsed = 0
            _navGlowFrame:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed >= 0.75 then
                    self:Hide(); self:SetScript("OnUpdate", nil); return
                end
                self:SetAlpha(1 - elapsed / 0.75)
            end)
        end

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
        -- Expose this build's RefreshTBB to the outer spec-change watcher so a
        -- spec swap while this page is open rebuilds the dropdown/preview.
        _tbbRefreshFn = RefreshTBB

        -- Drag-and-drop move: put a bar into another group (or make it
        -- independent). Joining a group adopts the group's current look, the
        -- same as a freshly added bar. Selects the moved bar.
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
        --  MANAGEMENT DROPDOWN builder ("Currently Editing:"). Creates the
        --  bar/group selector inside `parentFrame` (the Preset Style panel)
        --  and returns the dropdown button; the caller positions it.
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

            -- Dropdown button
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
                    -- Re-fetch the live (per-spec) bar count instead of the build-time
                    -- `bars` upvalue: this header builder is reused across SetContentHeader
                    -- refreshes (e.g. on spec change) without rebuilding the page, so the
                    -- captured `bars` can be the previous spec's stale list.
                    local liveBars = ns.GetTrackedBuffBars().bars
                    if not liveBars or #liveBars == 0 then
                        ddLbl:SetText(EllesmereUI.L("No Bars - Click to Add"))
                    else
                        ddLbl:SetText(EllesmereUI.L("Select a bar"))
                    end
                end
            end
            UpdateDDLabel()

            -- Custom dropdown menu: bars organized by group, with quick-add
            -- actions inside each group, an independent section, and
            -- new-group / independent-bar creation at the bottom.
            local ddMenu
            local function BuildDDMenu()
                if ddMenu then ddMenu:Hide(); ddMenu = nil end
                local t = ns.GetTrackedBuffBars()
                local menu = CreateFrame("Frame", nil, UIParent)
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
                -- The options panel can run at a different effective scale than
                -- this UIParent-level menu, so the button's local width is not
                -- the menu's width. Normalize it into menu space so the rows
                -- end exactly at the menu's edges.
                inner:SetWidth(ddBtn:GetWidth() * ddBtn:GetEffectiveScale() / menu:GetEffectiveScale())
                inner:SetPoint("TOPLEFT")
                local MENU_MAX_H = 420
                local ar, ag, ab = EllesmereUI.GetAccentColor()

                local mH = 4

                -- Drag-and-drop: bar rows can be dragged onto another group's
                -- section (or the independent section) to move them. Zones
                -- collect every row belonging to a group so the whole section
                -- is a drop target. The drag flag is declared before any
                -- OnUpdate that reads it.
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

                -- Group header: clickable -- selects the GROUP as the editing
                -- context (group settings replace the per-bar sections).
                -- gkey (optional): the group's globalKey -- adds the GLOBAL
                -- tag and a delete button that removes the global group for
                -- every spec (with confirmation).
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

                    -- Delete button
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
                    item:SetScript("OnClick", function()
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

                    -- Drag to move between groups (drop handled by zone under
                    -- the cursor at release)
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

                -- A freshly created bar has no buff yet: select it and open
                -- the buff picker right away so add-and-assign is one flow.
                local function SelectNewBar(newIdx)
                    menu:Hide()
                    OpenBuffPickerForBar(newIdx)
                end

                -- Grouped bars, one section per group (each section doubles as
                -- a drop zone for bar drags)
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

                -- Global groups with no bars on this spec: always listed so
                -- any spec can assign (or drag) bars into them -- that is the
                -- point of a global group. Selecting one edits its shared
                -- settings; the section is a normal drop zone.
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

                -- Drag hint
                if #t.bars > 1 then
                    local dragHint = inner:CreateFontString(nil, "OVERLAY")
                    dragHint:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    dragHint:SetTextColor(1, 1, 1, 0.35)
                    dragHint:SetPoint("TOP", inner, "TOP", 0, -mH - 4)
                    dragHint:SetText(EllesmereUI.L("Drag a bar to move it into another group"))
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
                    -- Never dismiss mid-drag: dragging naturally leaves the
                    -- menu bounds with the button held down.
                    if m._dragActive then return end
                    if not m:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                        m:Hide()
                    end
                end)
                menu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)
                menu:Show()
                ddMenu = menu
            end

            ddBtn:SetScript("OnEnter", function() ddLbl:SetAlpha(mTxtHA); ddBrd:SetColor(1,1,1,mBrdHA); ddBg:SetColorTexture(mBgR,mBgG,mBgB,mBgHA) end)
            ddBtn:SetScript("OnLeave", function()
                if ddMenu and ddMenu:IsShown() then return end
                ddLbl:SetAlpha(mTxtA); ddBrd:SetColor(1,1,1,mBrdA); ddBg:SetColorTexture(mBgR,mBgG,mBgB,mBgA)
            end)
            ddBtn:SetScript("OnClick", function()
                -- An open buff picker (e.g. from "+ Add Bar to Group") yields to
                -- the management menu.
                if _tbbSpellPickerMenu and _tbbSpellPickerMenu:IsShown() then
                    _tbbSpellPickerMenu:Hide()
                end
                if ddMenu and ddMenu:IsShown() then ddMenu:Hide() else BuildDDMenu() end
            end)
            ddBtn:HookScript("OnHide", function() if ddMenu then ddMenu:Hide() end end)

            -- Keep the label current when settings refresh in place (e.g. a
            -- group rename commits without a full page rebuild).
            EllesmereUI.RegisterWidgetRefresh(UpdateDDLabel)

            _tbbDDBtn = ddBtn
            return ddBtn
        end

        -- No content header: the preview lives in the popout panel docked to
        -- the left of the options window (RefreshTBBPopout). Wire its
        -- click-to-scroll overlays to this build's option rows.
        EllesmereUI:ClearContentHeader()
        _tbbNavigateFn = NavigateToSetting

        -------------------------------------------------------------------
        --  ACTION CARDS + PRESET STYLE (top of the scrollable settings;
        --  shown in both bar and group mode)
        -------------------------------------------------------------------
        do
            -- The third card broadcasts the selected bar to every other spec,
            -- then flips to "Remove Bar from All Specs" (the inverse). It is
            -- dimmed unless a preset or custom-buff bar is selected.
            local _selForBroadcast = (not _tbbSelectedGroup) and SelectedTBB() or nil
            local _canBroadcast = ns.IsTrackedBuffBarBroadcastable
                and ns.IsTrackedBuffBarBroadcastable(_selForBroadcast) or false
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
                cbg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
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
                        cbg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
                        cbrd:SetColor(1, 1, 1, 0.22)
                        titleFs:SetAlpha(1)
                        cIcon:SetAlpha(0.85)
                    end)
                    card:SetScript("OnLeave", function()
                        cbg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
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
                        onConfirm = function()
                            local p = DB()
                            if p and p.cdmBars then
                                p.cdmBars.useBlizzardBuffBars = true
                            end
                            ReloadUI()
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
                (not _canBroadcast) and (_tbbSelectedGroup
                    and "Select a bar to broadcast it to other specs"
                    or "Only preset or custom buff bars can be added to all specs") or nil)
            y = y - CARD_H - 12

            -- Preset Style panel: styled exactly like the Profiles & Presets
            -- "Active Profile" row (background panel, accent label above the
            -- dropdown, dim labels above the buttons). Pick a saved style
            -- preset and apply it to the selected bar / its group, or save the
            -- current style as a preset. Presets are profile-wide (shared
            -- across specs); outside these buttons the selection does nothing
            -- (new bars resolve a preset by association at creation).
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

            -- Background panel
            local prBg = prRow:CreateTexture(nil, "BACKGROUND")
            prBg:SetAllPoints()
            prBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            EllesmereUI.MakeBorder(prRow, 1, 1, 1, 0.10, PP)

            -- "Preset Style" label (accent, matching "Active Profile")
            local prLbl = EllesmereUI.MakeFont(prRow, 12, nil, EGc.r, EGc.g, EGc.b, 0.7)
            PP.Point(prLbl, "TOPLEFT", prRow, "TOPLEFT", PAD_X, -PAD_Y)
            prLbl:SetText(EllesmereUI.L("Preset Style"))
            prLbl:SetJustifyH("LEFT")

            -- Live reads: the label, menu and apply buttons all pull from the
            -- current preset list so saves, renames and deletes never go stale.
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

            -- Preset dropdown: bespoke button + menu (same look as the standard
            -- control) so each menu row carries inline rename/delete buttons,
            -- matching the Profiles & Presets "Active Profile" dropdown.
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
                                        print(EllesmereUI.Lf("|cffff6060[EllesmereUI]|r A preset named \"%1$s\" already exists.", newName))
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

            -- Buttons with dim labels above, matching the profile row's
            -- "Assign to Spec" / "New Profile" columns.
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

            -- Currently Editing: centered label + the bar/group management
            -- dropdown, between the preset panel and the settings sections.
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
                      EllesmereUI:RefreshPage()
                  end },
                { type = "slider", pixel = true, text = "Bar Spacing", min = -2, max = 20, step = 1,
                  getValue = function() return ns.TBBGroupSpacing(gid) end,
                  setValue = function(v)
                      ns.TBBSetGroupSpacing(gid, v)
                      ns.BuildTrackedBuffBars()
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
                      -- Soft refresh so the "Currently Editing:" dropdown label
                      -- picks up the new name right away.
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

            -- Global Group | (empty)
            _, h = W:DualRow(parent, y,
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
                { type = "label", text = "" }
            );  y = y - h

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
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(
                ns.TBB_TEXTURE_NAMES or {},
                ns.TBB_TEXTURE_ORDER or {},
                nil,
                ns.TBB_TEXTURES
            )
        end

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

        -- Helper: cog button builder (same as CDM Bars page)
        local function MakeCogBtn(rgn, showFn, anchorTo, iconPath)
            local anchor = anchorTo or (rgn and (rgn._lastInline or rgn._control)) or rgn
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(iconPath or EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) showFn(self) end)
            if rgn then rgn._lastInline = cogBtn end
            return cogBtn
        end

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  BAR LAYOUT
        -------------------------------------------------------------------
        local layoutHeader
        layoutHeader, h = W:SectionHeader(parent, "BAR LAYOUT", y);  y = y - h

        -- Height | Width
        -- The whole group shares one width/height, so a grouped member inherits
        -- the group ANCHOR's match-lock: if the anchor is size-matched, every
        -- member's slider is disabled (match wins) instead of silently fighting it.
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
        -- Width is the THICKNESS of a vertical bar (the toggle swaps the
        -- stored dimensions), so its floor drops to 1 there -- a 50px floor
        -- would clamp a slim vertical bar the moment the slider is touched.
        local selIsVert
        do
            local sb0 = SelectedTBB()
            selIsVert = sb0 and sb0.verticalOrientation and true or false
        end
        local hwRow
        hwRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 500, step = 1,
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
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = selIsVert and 1 or 50, max = 500, step = 1,
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
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Sync icons: Apply Height/Width to all bars of the SAME orientation.
        -- A "height" is the short side of a horizontal bar but the LONG side
        -- of a vertical one, so cross-orientation copies would be nonsense.
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
                  -- Groups stay orientation-uniform: shared width/height only
                  -- makes sense when every member reads the dimensions the
                  -- same way, so the whole group flips together.
                  local gid = ns.TBBBarGroupID(bd)
                  if gid ~= 0 then
                      local t = ns.GetTrackedBuffBars()
                      for _, b in ipairs(t.bars or {}) do
                          if b ~= bd and ns.TBBBarGroupID(b) == gid
                             and (b.verticalOrientation and true or false) ~= (v and true or false) then
                              flip(b)
                          end
                      end
                      -- Rotate the grow direction so side-by-side stays
                      -- side-by-side across the flip (DOWN<->RIGHT, UP<->LEFT).
                      local rot = v and { DOWN = "RIGHT", UP = "LEFT" }
                                    or { RIGHT = "DOWN", LEFT = "UP" }
                      local grow = ns.TBBGroupGrow(gid)
                      if rot[grow] then ns.TBBSetGroupGrow(gid, rot[grow]) end
                  end
                  RefreshTBB()
                  -- Full rebuild: the Width slider's floor and sync tooltips
                  -- are orientation-dependent.
                  EllesmereUI:RefreshPage(true)
              end },
            { type = "dropdown", text = "Bar Texture",
              values = texValues, order = texOrder,
              getValue = function() local bd = SelectedTBB(); return bd and bd.texture or "none" end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.texture = v; RefreshTBB()
              end }
        );  y = y - h

        -- Name Text (dropdown + cog) | Duration Text (dropdown + cog)
        local TBB_POS_VALUES = { none = "None", center = "Center", top = "Top", bottom = "Bottom", left = "Left", right = "Right" }
        local TBB_POS_ORDER = { "none", "center", "top", "bottom", "left", "right" }

        -- When a text element claims a position, evict any other text
        -- already sitting in that slot so two labels never overlap. Compares
        -- EFFECTIVE (rendered) positions: name text never renders on vertical
        -- bars, so its stored slot must not evict anything there.
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
        -- Cog on Name Text: text size + x/y
        do
            local rgn = nameRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Name Text Settings",
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn); cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                local bd = SelectedTBB()
                if bd and bd.verticalOrientation then
                    EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Horizontal Orientation (name text is not shown on vertical bars)"))
                else
                    EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("This option requires a Name Text position other than None"))
                end
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisName()
                local bd = SelectedTBB()
                if bd and bd.verticalOrientation then cogDis:Show(); return end
                local pos = bd and bd.namePosition
                if not pos then pos = (bd and bd.showName ~= false) and "left" or "none" end
                if pos == "none" then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisName)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisName)
            UpdateCogDisName()
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
            -- 12.1 only: engine-rendered tenths below the threshold (see
            -- EllesmereUICdmTbbDecimals.lua). No 12.0 equivalent exists --
            -- the rows are absent there rather than permanently disabled.
            if EllesmereUI.IS_121 then
                table.insert(durationRows, 2,
                    { type = "toggle", label = "Decimals",
                      tooltip = "Cannot work for pet/totem summon bars (Call Dreadstalkers, etc.) -- they expose no readable timer.",
                      get = function() local bd = SelectedTBB(); return bd and bd.timerDecimals == true end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.timerDecimals = v or nil; RefreshTBB()
                      end })
                table.insert(durationRows, 3,
                    { type = "slider", label = "Decimal Threshold", min = 3, max = 120, step = 1,
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
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text Settings",
                rows = durationRows,
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn); cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("This option requires a Duration Text position other than None"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisTimer()
                local bd = SelectedTBB()
                local pos = bd and bd.timerPosition
                if not pos then pos = (bd and bd.showTimer) and "right" or "none" end
                if pos == "none" then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisTimer)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisTimer)
            UpdateCogDisTimer()
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

        -- Stacks Text (dropdown + resize cog: size, x, y) | empty
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
            { type = "toggle", text = "Reverse Fill",
              getValue = function() local bd = SelectedTBB(); return bd and bd.reverseFill end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.reverseFill = v; RefreshTBB()
              end }
        );  y = y - h
        do
            local rgn = stacksRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Stacks Text Settings",
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn); cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("This option requires a Stacks Text position other than None"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisStacks()
                local bd = SelectedTBB()
                if bd and (bd.stacksPosition or "center") == "none" then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisStacks)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisStacks)
            UpdateCogDisStacks()
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

        -- Charge Hash Lines | Smooth Bars. The number and orientation of hash
        -- separators are resolved automatically from the tracked spell's max
        -- charges. Smooth Bars remains profile-wide rather than per bar/spec.
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
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Charge Hash Line Settings",
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
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.COGS_ICON)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints()
            cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
            cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function()
                local bd = SelectedTBB()
                local tip
                if not bd or bd.trackType ~= "cooldown" then
                    tip = "This option requires a cooldown-tracking bar"
                elseif not SelectedTBBSupportsChargeHash() then
                    tip = "This option is only available for abilities with multiple charges"
                else
                    tip = "Enable Charge Hash Lines first"
                end
                EllesmereUI.ShowWidgetTooltip(cogBtn, tip)
            end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateChargeHashCog()
                local bd = SelectedTBB()
                local disabled = not bd or bd.trackType ~= "cooldown"
                    or not SelectedTBBSupportsChargeHash()
                    or bd.chargeHashLines ~= true
                cogBtn:SetAlpha(disabled and 0.15 or 0.4)
                if disabled then cogBlock:Show() else cogBlock:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateChargeHashCog)
            EllesmereUI.RegisterWidgetRefresh(UpdateChargeHashCog)
            UpdateChargeHashCog()
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

        -- Bar Strata
        local barStrataRow
        barStrataRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Bar Strata",
              tooltip = "Screen layer the bar renders on; changing a grouped bar changes its whole group.",
              values = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium",
                         HIGH = "High", DIALOG = "Dialog", FULLSCREEN = "Fullscreen",
                         FULLSCREEN_DIALOG = "Fullscreen Dialog", TOOLTIP = "Tooltip" },
              order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG",
                        "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" },
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
              end },
            { type = "label", text = "" });  y = y - h

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        local displayHeader
        displayHeader, h = W:SectionHeader(parent, "Display", y);  y = y - h

        -- Show Icon | Opacity
        local iconRow
        iconRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Show Icon",
              values = { none = "None", left = "Left (Top)", right = "Right (Bottom)" },
              order = { "none", "left", "right" },
              getValue = function() local bd = SelectedTBB(); return bd and bd.iconDisplay or "none" end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.iconDisplay = v; RefreshTBB()
              end },
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 1,
              getValue = function()
                  local bd = SelectedTBB()
                  return bd and math.floor((bd.opacity or 1.0) * 100 + 0.5) or 100
              end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.opacity = v / 100; RefreshTBB()
              end }
        );  y = y - h

        -- Fill Color (dropdown: auto/custom + gradient mode + 2 inline swatches) | Show Spark
        local fillRow
        fillRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Fill Color",
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
              end },
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
                local noGrad = not bd or not bd.gradientEnabled
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
                { type="dropdown", text="Border Texture",
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
                      RefreshTBB(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 5, step = 1,
                  getValue = function() local bd = SelectedTBB(); return bd and bd.borderSize or 0 end,
                  setValue = function(v)
                      local bd = SelectedTBB(); if not bd then return end
                      bd.borderSize = v; RefreshTBB()
                  end });  y = y - h
            -- Inline border color swatch on Border Size (right region)
            do
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
            end
            do
                local rgn = tbbBsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local bd = SelectedTBB(); if not bd then return 0 end
                              local v = bd.borderTextureOffset
                              if v then return v end
                              local dox = EllesmereUI.GetBorderDefaults("resourcebars", bd.borderTexture or "solid", bd.borderSize or 0)
                              return dox
                          end,
                          set = function(v)
                              local bd = SelectedTBB(); if not bd then return end
                              bd.borderTextureOffset = v; RefreshTBB()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local bd = SelectedTBB(); if not bd then return 0 end
                              local v = bd.borderTextureOffsetY
                              if v then return v end
                              local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", bd.borderTexture or "solid", bd.borderSize or 0)
                              return doy
                          end,
                          set = function(v)
                              local bd = SelectedTBB(); if not bd then return end
                              bd.borderTextureOffsetY = v; RefreshTBB()
                          end },
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
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local bd = SelectedTBB()
                    local tex = bd and bd.borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
        end

        -- Background Color | empty
        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Background Color",
              swatches = {
                  { tooltip = "Background Color", hasAlpha = true,
                    getValue = function()
                        local bd = SelectedTBB()
                        return (bd and bd.bgR or 0), (bd and bd.bgG or 0), (bd and bd.bgB or 0), (bd and bd.bgA or 0.4)
                    end,
                    setValue = function(r, g, b, a)
                        local bd = SelectedTBB(); if not bd then return end
                        bd.bgR, bd.bgG, bd.bgB, bd.bgA = r, g, b, a; RefreshTBB()
                    end },
              } },
            { type = "toggle", text = "Hide When Inactive",
              getValue = function() local bd = SelectedTBB(); return bd and bd.hideWhenInactive ~= false end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.hideWhenInactive = v and true or false; RefreshTBB()
              end,
              tooltip = "Only show this bar while the tracked buff/cooldown is active. Turn off to keep an empty bar on screen at all times." }
        );  y = y - h

        -----------------------------------------------------------------------
        --  EXTRAS
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h

        -- Row 1: Pandemic Glow (dropdown + swatch + cog + sync) | Stack Based
        -- Bar (buff bars only; page rebuilds on selection change, so cd/utility
        -- bars get a blank slot). Stack Based Bar is inert until Max Stacks is
        -- enabled below.
        do
            local function tbbPandemicOff()
                local bd = SelectedTBB(); return not bd or bd.pandemicGlow ~= true
            end
            local function tbbAntsOff()
                if tbbPandemicOff() then return true end
                local bd = SelectedTBB()
                -- Pixel-glow "ants" settings apply for every bar style except
                -- Auto-Cast Shine (4). Any non-{1,4} stored value (e.g. the legacy
                -- -1 "Blizzard Default", which is meaningless on a rectangle)
                -- renders as Pixel Glow, so its ants settings stay editable.
                return not bd or bd.pandemicGlowStyle == 4
            end

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
            tbbPanRow, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Pandemic Glow",
                  values = PAN_GLOW_BAR_VALUES, order = PAN_GLOW_BAR_ORDER,
                  getValue = function()
                      local bd = SelectedTBB(); if not bd then return 0 end
                      if bd.pandemicGlow ~= true then return 0 end
                      -- Bars only render Pixel Glow (1) or Auto-Cast Shine (4).
                      -- Any other stored style (e.g. the -1 "Blizzard Default"
                      -- default, which has no meaning on a rectangle) renders as
                      -- Pixel Glow, so show it as Pixel Glow instead of a raw -1.
                      local style = bd.pandemicGlowStyle
                      if style ~= 4 then style = 1 end
                      return style
                  end,
                  setValue = function(v)
                      local bd = SelectedTBB(); if not bd then return end
                      if v == 0 then bd.pandemicGlow = false
                      else bd.pandemicGlow = true; bd.pandemicGlowStyle = v end
                      RefreshTBB()
                      C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                  end,
                  tooltip = "Show a glow on the bar when the remaining duration is in the pandemic window (last 30%)" },
                rightSlot);  y = y - h

            -- Inline color swatch
            do
                local tbbLR = tbbPanRow._leftRegion
                local tbbCtrl = tbbLR and tbbLR._control
                if tbbCtrl and EllesmereUI.BuildColorSwatch then
                    local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                        tbbLR, tbbPanRow:GetFrameLevel() + 3,
                        function()
                            local bd = SelectedTBB(); local c = bd and bd.pandemicGlowColor
                            if c then return c.r or 1, c.g or 1, c.b or 0 end; return 1, 1, 0
                        end,
                        function(r, g, b)
                            local bd = SelectedTBB(); if not bd then return end
                            bd.pandemicGlowColor = { r = r, g = g, b = b }; RefreshTBB()
                        end, nil, 20)
                    PP.Point(swatch, "RIGHT", tbbCtrl, "LEFT", -12, 0)
                    tbbLR._lastInline = swatch
                    EllesmereUI.RegisterWidgetRefresh(function()
                        local off = tbbPandemicOff()
                        swatch:SetAlpha(off and 0.15 or 1); swatch:EnableMouse(not off)
                        if updateSwatch then updateSwatch() end
                    end)
                    swatch:SetAlpha(tbbPandemicOff() and 0.15 or 1)
                    swatch:EnableMouse(not tbbPandemicOff())
                end
            end

            BuildPandemicCogButton(tbbPanRow, tbbAntsOff, SelectedTBB, function() RefreshTBB() end)

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
            { type = "label", text = "Ticks at Stacks" }
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

            local function UpdateTicksInput()
                local bd = SelectedTBB()
                box:SetText(bd and bd.stackThresholdTicks or "")
                local off = maxStacksOff()
                box:SetAlpha(off and 0.3 or 1)
                box:EnableMouse(not off)
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
              min = 0, max = 50, step = 1,
              disabled = function() local bd = SelectedTBB(); return not bd or not bd.stackThresholdEnabled end,
              disabledTooltip = "Stack Threshold",
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
                EllesmereUI.ShowWidgetTooltip(threshSwatch, EllesmereUI.DisabledTooltip("Stack Threshold"))
            end)
            threshBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateThreshSwatchState()
                local bd = SelectedTBB()
                local off = not bd or not bd.stackThresholdEnabled
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
    ---------------------------------------------------------------------------
    --  CDM Bars page
    ---------------------------------------------------------------------------
    local growValues = { RIGHT = "Right", LEFT = "Left", DOWN = "Down", UP = "Up" }
    local growOrder  = { "RIGHT", "LEFT", "DOWN", "UP" }

    -- Track which bar is selected in the CDM Bars tab
    local selectedCDMBarIndex = 1

    -- Deep-link helper: select a CDM bar by key or barType (used by the What's
    -- New "Always Show Buffs" card preSelect to land on the native buff bar,
    -- whose per-bar toggle only renders when a buff-family bar is selected).
    -- Sets the index immediately, like EllesmereUI._setUnitFrameUnit, so both the
    -- content header and the rebuilt page reflect the chosen bar.
    function EllesmereUI._setCDMBar(keyOrType)
        local p = DB()
        local bars = p and p.cdmBars and p.cdmBars.bars
        if not bars then return end
        for bi, bb in ipairs(bars) do
            if bb.key == keyOrType or bb.barType == keyOrType then
                selectedCDMBarIndex = bi
                return
            end
        end
    end

    -- CDM Bars preview state
    local _cdmPreview          -- reference to the preview frame
    local _cdmHeaderFixedH = 0
    local _cdmHeaderBuilder    -- forward ref for content header builder

    local function UpdateCDMPreview()
        if not _cdmPreview and EllesmereUI._contentHeaderPreview then
            _cdmPreview = EllesmereUI._contentHeaderPreview
        end
        if _cdmPreview and _cdmPreview.Update then
            _cdmPreview:Update()
        end
    end

    local function UpdateCDMPreviewAndResize()
        UpdateCDMPreview()
        if _cdmPreview and _cdmHeaderFixedH > 0 then
            -- Wrapper height is already capped by the Update function's resize logic
            local wrapperH = _cdmPreview._wrapper and _cdmPreview._wrapper:GetHeight()
                             or math.min(_cdmPreview:GetHeight() * (_cdmPreview:GetScale() or 1), 200)
            EllesmereUI:UpdateContentHeaderHeight(_cdmHeaderFixedH + wrapperH)
        end
    end

    EllesmereUI:RegisterOnShow(UpdateCDMPreview)

    -- Refresh our preview when user closes Blizzard's CDM settings panel
    -- (they may have added/removed spells from the viewer)
    if CooldownViewerSettings then
        CooldownViewerSettings:HookScript("OnHide", function()
            C_Timer.After(0.3, function()
                if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
                    EllesmereUI:RefreshPage(true)
                end
            end)
        end)
    end

    --- Get the currently selected CDM bar data
    local function SelectedCDMBar()
        local p = DB()
        if not p or not p.cdmBars or not p.cdmBars.bars then return nil end
        local bars = p.cdmBars.bars
        if selectedCDMBarIndex < 1 then selectedCDMBarIndex = 1 end
        if selectedCDMBarIndex > #bars then selectedCDMBarIndex = #bars end
        return bars[selectedCDMBarIndex]
    end

    -- Active state preview on first icon
    local _cdmActivePreviewOn = false
    local _cdmActivePreviewOverlay = nil  -- glow overlay frame on first preview slot
    local _cdmActivePreviewToken = 0     -- incremented each start to invalidate stale timers

    local function StopActiveStatePreview()
        if _cdmActivePreviewOverlay then
            ns.StopNativeGlow(_cdmActivePreviewOverlay)
        end
        -- Stop fake cooldown on preview slot
        if _cdmPreview and _cdmPreview._previewSlots then
            local slot = _cdmPreview._previewSlots[1]
            if slot and slot._previewCD then
                slot._previewCD:Clear()
                slot._previewCD:Hide()
            end
        end
    end

    local function StartActiveStatePreview()
        if not _cdmActivePreviewOn then return end
        _cdmActivePreviewToken = _cdmActivePreviewToken + 1
        local myToken = _cdmActivePreviewToken
        local bd = SelectedCDMBar()
        if not bd then return end
        local anim = bd.activeStateAnim or "blizzard"
        if not _cdmPreview or not _cdmPreview._previewSlots then return end
        local slot = _cdmPreview._previewSlots[1]
        if not slot or not slot:IsShown() then return end

        -- Ensure cooldown widget exists on preview slot
        if not slot._previewCD then
            local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
            cd:SetAllPoints()
            cd:SetDrawEdge(false)
            cd:SetDrawSwipe(true)
            cd:SetDrawBling(false)
            cd:SetReverse(false)
            cd:SetHideCountdownNumbers(false)
            cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
            if cd.SetSnapToPixelGrid then cd:SetSnapToPixelGrid(false); cd:SetTexelSnappingBias(0) end
            slot._previewCD = cd
        end

        -- Always refresh font (4px smaller than bar's cooldown font size, shadow style)
        C_Timer.After(0, function()
            if not slot._previewCD then return end
            local fSize = (bd.cooldownFontSize or 12) - 2
            if fSize < 6 then fSize = 6 end
            local fontPath = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("cdm")) or STANDARD_TEXT_FONT
            for _, region in ipairs({ slot._previewCD:GetRegions() }) do
                if region:GetObjectType() == "FontString" then
                    SetPVFont(region, fontPath, fSize)
                    break
                end
            end
        end)

        -- Ensure glow overlay exists
        if not slot._glowOverlay then
            local ov = CreateFrame("Frame", nil, slot)
            ov:SetAllPoints(slot)
            ov:SetFrameLevel(slot:GetFrameLevel() + 3)
            ov:SetAlpha(0)
            slot._glowOverlay = ov
        end
        _cdmActivePreviewOverlay = slot._glowOverlay

        -- Resolve active animation color
        local animR, animG, animB = 1.0, 0.85, 0.0
        if bd.activeAnimClassColor then
            local _, ct = UnitClass("player")
            if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then animR, animG, animB = cc.r, cc.g, cc.b end end
        elseif bd.activeAnimR then
            animR = bd.activeAnimR; animG = bd.activeAnimG or 0.85; animB = bd.activeAnimB or 0.0
        end

        local swAlpha = bd.swipeAlpha or 0.7
        local PREVIEW_DURATION = 5  -- seconds

        if anim == "none" then
            slot._previewCD:SetSwipeColor(0, 0, 0, swAlpha)
            slot._previewCD:SetCooldown(GetTime(), PREVIEW_DURATION)
            slot._previewCD:Show()
            ns.StopNativeGlow(_cdmActivePreviewOverlay)
        else
            slot._previewCD:SetSwipeColor(animR, animG, animB, swAlpha)
            slot._previewCD:SetCooldown(GetTime(), PREVIEW_DURATION)
            slot._previewCD:Show()

            if anim ~= "blizzard" then
                local glowIdx = tonumber(anim)
                if glowIdx then
                    ns.StartNativeGlow(_cdmActivePreviewOverlay, glowIdx, animR, animG, animB)
                end
            else
                ns.StopNativeGlow(_cdmActivePreviewOverlay)
            end
        end

        -- Auto-stop glow after preview duration ends
        C_Timer.After(PREVIEW_DURATION, function()
            if myToken ~= _cdmActivePreviewToken then return end
            if _cdmActivePreviewOverlay then
                ns.StopNativeGlow(_cdmActivePreviewOverlay)
            end
            if slot._previewCD then
                slot._previewCD:Clear()
                slot._previewCD:Hide()
            end
        end)
    end

    local function ShowWrongBarTypePopup(spellName, isSpellBuff)
        if not EllesmereUI or not EllesmereUI.ShowConfirmPopup then return end
        local correctBar = isSpellBuff and "a Buff bar" or "a Cooldown or Utility bar"
        EllesmereUI:ShowConfirmPopup({
            title = "Wrong Bar Type",
            message = (spellName or "This spell") .. " is tracked by Blizzard as " .. (isSpellBuff and "a buff/aura" or "a cooldown") .. " and should be added to " .. correctBar .. ".",
            confirmText = "Open Blizzard CDM",
            cancelText = "Close",
            onConfirm = function()
                if CooldownViewerSettings and CooldownViewerSettings.Show then
                    CooldownViewerSettings:Show()
                end
                if EllesmereUI._mainFrame then EllesmereUI._mainFrame:Hide() end
            end,
        })
    end

    ---------------------------------------------------------------------------
    --  Spell picker dropdown (right-click on icon or click "+" button)
    ---------------------------------------------------------------------------
    local _spellPickerMenu
    -- Close the spell picker when the main EUI options panel closes
    EllesmereUI:RegisterOnHide(function()
        if _spellPickerMenu and _spellPickerMenu:IsShown() then _spellPickerMenu:Hide() end
    end)
    -- Ensure assignedSpells is populated from live icons if nil.
    -- Shared by spell picker, preview, and all add/remove handlers.
    -- Normalize a spell ID to its base (undo talent overrides).
    -- E.g. Voltaic Blaze (470057) -> Flame Shock (188389).
    local function NormalizeToBase(sid)
        if not sid or sid <= 0 then return sid end
        if C_Spell and C_Spell.GetBaseSpell then
            local base = C_Spell.GetBaseSpell(sid)
            if base and base > 0 then return base end
        end
        return sid
    end

    -- Resolve a base spell ID to its current live version (talent overrides).
    -- E.g. Flame Shock (188389) -> Voltaic Blaze (470057) when talented.
    local function ResolveToLive(sid)
        if not sid or sid <= 0 then return sid end
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local ovr = C_SpellBook.FindSpellOverrideByID(sid)
            if ovr and ovr > 0 then return ovr end
        end
        return sid
    end

    local function EnsureAssignedSpells(barKeyE)
        local sd = ns.GetBarSpellData(barKeyE)
        if not sd then return sd end
        if sd.assignedSpells then
            -- Normalize overrides to base IDs and deduplicate in one pass.
            local seen = {}
            local writeIdx = 1
            for readIdx = 1, #sd.assignedSpells do
                local sid = NormalizeToBase(sd.assignedSpells[readIdx])
                if not seen[sid] then
                    seen[sid] = true
                    sd.assignedSpells[writeIdx] = sid
                    writeIdx = writeIdx + 1
                end
            end
            for i = writeIdx, #sd.assignedSpells do sd.assignedSpells[i] = nil end
        end
        -- Append any live-bar spells missing from assignedSpells so the
        -- preview always matches what the player sees on their CDM bars
        -- (e.g. after re-talenting a spell post-repopulate).
        --
        -- EXCEPTION: skip while an imported layout is still pending its first-load
        -- ghosting (_importGhostMode). The importer's tracked spells spill onto the
        -- default bars until the migration ghosts them; materializing those spills
        -- into assignedSpells here would mark them "assigned" and permanently defeat
        -- the import-authoritative ghosting (the spell then shows on cooldowns
        -- instead of being hidden). The import happens FROM this panel, so this
        -- rebuild fires before the migration can run -- the gate is essential.
        local importPending = false
        do
            local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
            local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
            local aprof = sp and sk and sp[sk]
            if aprof and aprof._importGhostMode then importPending = true end
        end
        -- Buff-family bars get their buffs ONLY through the picker
        -- (ShowBuffBarPicker -> AddTrackedSpell), so assignedSpells is already the
        -- complete, authoritative list and nothing legitimately spills onto them.
        -- Skipping the live-icon append below is what fixes the duplicate-slot bug:
        -- a buff's resolved spellID drifts between its ACTIVE state (GetSpellID/
        -- GetAuraSpellID return secret -> resolution falls back) and its INACTIVE
        -- state (clean GetAuraSpellID), so right after combat when buffs expire the
        -- live icon can resolve to a different ID than the stored one and the
        -- append re-adds the same buff a second time. CD/utility bars still need
        -- the append (re-talent re-population + transient-spillover reconciliation).
        local bdForFamily = ns.barDataByKey and ns.barDataByKey[barKeyE]
        local isBuffFamilyE = ns.IsBarBuffFamily and ns.IsBarBuffFamily(bdForFamily or barKeyE)
        local liveIcons = (not importPending) and (not isBuffFamilyE)
                          and ns.cdmBarIcons and ns.cdmBarIcons[barKeyE]
        if liveIcons then
            if not sd.assignedSpells then sd.assignedSpells = {} end
            local seen = {}
            for _, existing in ipairs(sd.assignedSpells) do
                seen[existing] = true
            end
            local removed = sd.removedSpells
            -- Never materialize a spell that's currently HIDDEN (in the ghost bar)
            -- onto a visible bar -- that recreates a both-state and the spell would
            -- reappear. Variant-aware against the active spec's ghost list. This
            -- closes the narrow window between the migration ghosting a spell and
            -- the reanchor refreshing cdmBarIcons.
            local ghostSd = ns.GetBarSpellData and ns.GetBarSpellData("__ghost_cd")
            local ghostList = ghostSd and ghostSd.assignedSpells
            local FindVar = ns.FindVariantIndexInList
            -- Also never materialize a spell the user has deliberately placed on
            -- ANOTHER bar (custom or default). A transient spillover during a profile
            -- swap can briefly render a custom-bar spell on cooldowns; without this it
            -- would be appended here and create a both-state (custom bar + cooldowns),
            -- which the route map then has to arbitrate. Build the claimed set from
            -- the active spec's stored bars (data), not the live route map (which may
            -- be momentarily stale during the swap).
            local claimedElsewhere
            do
                local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                local aprof = sp and sk and sp[sk]
                local bsAll = aprof and aprof.barSpells
                if bsAll and ns.StoreVariantValue then
                    for k, bsd in pairs(bsAll) do
                        if k ~= barKeyE and k ~= "__ghost_cd"
                           and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                            for _, sid in ipairs(bsd.assignedSpells) do
                                if type(sid) == "number" and sid > 0 then
                                    claimedElsewhere = claimedElsewhere or {}
                                    ns.StoreVariantValue(claimedElsewhere, sid, true, false)
                                end
                            end
                        end
                    end
                end
            end
            -- Walk the live icons in on-screen order (CollectAndReanchor already
            -- placed a spillover cooldown at its Blizzard-layout position). A new
            -- spell is inserted right after its left neighbour -- the previous live
            -- icon that already has a slot -- so it takes its true Blizzard-CDM
            -- position instead of being appended at the very end (which piled
            -- talent-swap spells after the trinket/racial slots and never survived
            -- a /reload cleanly).
            local insertAfterSid = nil
            for _, icon in ipairs(liveIcons) do
                -- Resolve the live icon's DISPLAYED spell the same way the picker
                -- does (canonical = GetSpellID-first, with the active-frame cache),
                -- so a spell whose cooldownInfo base differs from its live talent
                -- form (e.g. 137029 Holy Paladin vs 432496 Holy Bulwark) dedups
                -- against the stored canonical ID instead of appending a generic
                -- duplicate slot. Falls back to the raw FC spellID for our own
                -- custom frames (no GetSpellID/cooldownInfo to resolve).
                local _sid = (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(icon))
                             or (ns._ecmeFC[icon] and ns._ecmeFC[icon].spellID)
                -- Skip hosted-buff frames and their placeholders: their bar
                -- membership is the hosted MARKER entry. Materializing their
                -- canonical spellID here would fabricate a plain COOLDOWN entry
                -- for the same spell (the buff frame's id resolves positive).
                local _fdLI = ns._hookFrameData and ns._hookFrameData[icon]
                if icon._isPlaceholderFrame or (_fdLI and _fdLI._isBuffViewerFrame) then
                    _sid = nil
                end
                -- Skip overflow-diverted icons outright: they render on this
                -- bar only for the session but BELONG to their source bar's
                -- assignedSpells -- materializing (or advancing the insertion
                -- cursor on) them would write the diversion into this bar's
                -- saved list.
                if _sid and ns.CdmFrameOverflowBar and ns.CdmFrameOverflowBar(icon) then
                    _sid = nil
                end
                if _sid and _sid ~= 0 then
                    if _sid > 0 then _sid = NormalizeToBase(_sid) end
                    if seen[_sid] then
                        -- Already has a slot (Blizzard spell OR a custom trinket/item
                        -- marker): advance the cursor so the next NEW spell lands after
                        -- it, matching the on-screen order across custom entries too.
                        insertAfterSid = _sid
                    elseif _sid > 0
                       and not (removed and removed[_sid])
                       and not (ghostList and FindVar and FindVar(ghostList, _sid))
                       and not (claimedElsewhere and ns.ResolveVariantValue and ns.ResolveVariantValue(claimedElsewhere, _sid)) then
                        local pos
                        if insertAfterSid then
                            for i = 1, #sd.assignedSpells do
                                if sd.assignedSpells[i] == insertAfterSid then pos = i; break end
                            end
                        end
                        if pos then
                            table.insert(sd.assignedSpells, pos + 1, _sid)
                        else
                            -- No anchored predecessor yet: this new spell is the
                            -- left-most live icon, so it belongs at the front.
                            table.insert(sd.assignedSpells, 1, _sid)
                        end
                        seen[_sid] = true
                        insertAfterSid = _sid
                    end
                end
            end
        end
        -- Materialize tracked-but-UNLEARNED CD/utility spells onto the DEFAULT
        -- bar of their category. Blizzard creates no viewer frame for a spell
        -- the player hasn't talented, so the live-icon append above can never
        -- see them; without this they are invisible in the whole management
        -- UI. Sourced from the settings catalog (ns.EnumerateCDMSettingsCatalog),
        -- which respects the user's Blizzard arrangement: spells moved to Not
        -- Displayed never materialize, and each spell lands at its arranged
        -- position (insert after its nearest catalog predecessor already in
        -- the list). Guards, all load-bearing:
        --   * default cooldowns/utility bars only (custom bars get spells via
        --     the picker; spillover always belongs to the default bar)
        --   * LEARNED spells are exclusively the live-icon pass's job above,
        --     so behavior for them is byte-identical to before
        --   * skipped while an import's ghosting is pending (importPending)
        --     and until the spec's V6 ghost migration has stamped its flag --
        --     ghosting must classify spells BEFORE anything materializes
        --   * ghosted, explicitly-removed, and claimed-elsewhere spells skip
        --   * catalog nil (provider unavailable) = pass no-ops entirely
        if not importPending and (barKeyE == "cooldowns" or barKeyE == "utility")
           and ns.EnumerateCDMSettingsCatalog then
            local aprofM, migrated
            do
                local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                aprofM = sp and sk and sp[sk]
                migrated = aprofM and aprofM._barFilterModelV6 and true or false
            end
            local catalog = migrated and ns.EnumerateCDMSettingsCatalog() or nil
            if catalog and #catalog > 0 and IsPlayerSpell then
                local evc = Enum and Enum.CooldownViewerCategory
                local wantCat
                if evc then
                    if barKeyE == "cooldowns" then wantCat = evc.Essential
                    else wantCat = evc.Utility end
                end
                local FindVar = ns.FindVariantIndexInList
                if wantCat ~= nil and FindVar then
                    if not sd.assignedSpells then sd.assignedSpells = {} end
                    local list = sd.assignedSpells
                    local removed = sd.removedSpells
                    local ghostSdM = ns.GetBarSpellData and ns.GetBarSpellData("__ghost_cd")
                    local ghostListM = ghostSdM and ghostSdM.assignedSpells
                    -- Spells the user placed on ANY other bar keep their home.
                    local claimedM
                    do
                        local bsAll = aprofM and aprofM.barSpells
                        if bsAll and ns.StoreVariantValue then
                            for k, bsd in pairs(bsAll) do
                                if k ~= barKeyE and k ~= "__ghost_cd"
                                   and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                                    for _, sid in ipairs(bsd.assignedSpells) do
                                        if type(sid) == "number" and sid > 0 then
                                            claimedM = claimedM or {}
                                            ns.StoreVariantValue(claimedM, sid, true, false)
                                        end
                                    end
                                end
                            end
                        end
                    end
                    for ci = 1, #catalog do
                        local ce = catalog[ci]
                        if ce.category == wantCat then
                            local nsid = NormalizeToBase(ce.sid)
                            local isKnownM = true
                            if type(nsid) == "number" and nsid > 0 then
                                isKnownM = (IsPlayerSpell(nsid) or IsPlayerSpell(ce.sid)
                                    or IsPlayerSpell(ResolveToLive(nsid))) and true or false
                            end
                            if type(nsid) == "number" and nsid > 0
                               and not isKnownM
                               and not FindVar(list, nsid)
                               and not (removed and (removed[nsid] or removed[ce.sid]))
                               and not (ghostListM and FindVar(ghostListM, nsid))
                               and not (claimedM and ns.ResolveVariantValue and ns.ResolveVariantValue(claimedM, nsid)) then
                                local pos
                                for cj = ci - 1, 1, -1 do
                                    local prevSid = NormalizeToBase(catalog[cj].sid)
                                    local at = FindVar(list, prevSid)
                                    if at then pos = at; break end
                                end
                                if pos then
                                    table.insert(list, pos + 1, nsid)
                                else
                                    table.insert(list, 1, nsid)
                                end
                            end
                        end
                    end
                end
            end
        end
        -- Reconcile stale generic variants already saved before the canonical
        -- resolver was cache-backed. A buff whose cooldownInfo base spellID
        -- differs from its live talent form (e.g. 137029 Holy Paladin stored
        -- next to 432496 Holy Bulwark) leaves a generic duplicate that variant
        -- dedup cannot collapse -- there is no GetBaseSpell/override link
        -- between them. Map each pooled buff frame's base spellID -> its
        -- canonical live spellID (GetSpellID-first, cache-backed), then drop any
        -- stored base whose canonical live form is ALSO present, never stranding
        -- a lone entry.
        if sd.assignedSpells and #sd.assignedSpells > 1
           and ns.GetCanonicalSpellIDForFrame then
            local viewer = _G.BuffIconCooldownViewer
            local pool = viewer and viewer.itemFramePool
            if pool and pool.EnumerateActive then
                local canonOf
                for frame in pool:EnumerateActive() do
                    local info = frame.cooldownInfo
                    local baseSID = info and info.spellID
                    local canon = ns.GetCanonicalSpellIDForFrame(frame)
                    if type(baseSID) == "number" and baseSID > 0
                       and type(canon) == "number" and canon > 0 then
                        local nb, nc = NormalizeToBase(baseSID), NormalizeToBase(canon)
                        if nb ~= nc then
                            canonOf = canonOf or {}
                            canonOf[nb] = nc
                        end
                    end
                end
                if canonOf then
                    local present = {}
                    for _, sid in ipairs(sd.assignedSpells) do present[sid] = true end
                    local writeIdx = 1
                    for readIdx = 1, #sd.assignedSpells do
                        local sid = sd.assignedSpells[readIdx]
                        local canon = canonOf[sid]
                        if not (canon and present[canon]) then
                            sd.assignedSpells[writeIdx] = sid
                            writeIdx = writeIdx + 1
                        end
                    end
                    for i = writeIdx, #sd.assignedSpells do sd.assignedSpells[i] = nil end
                end
            end
        end
        -- Drop regular Blizzard spells the user has CLEARED from Blizzard's CDM
        -- (no longer in the live Essential/Utility viewer = the displayed set).
        -- The preview is built 1:1 from assignedSpells, so without this it keeps
        -- showing spells the live bar no longer renders. Preserve all user-added
        -- entries (trinkets/item presets = negatives, custom spell IDs, racials,
        -- and preset metadata). CD/utility bars only; skipped if the viewer set
        -- looks empty/unready so a transient gap never wipes assignments.
        do
            local bdE = ns.barDataByKey and ns.barDataByKey[barKeyE]
            local btE = bdE and bdE.barType
            if (btE == "cooldowns" or btE == "utility")
               and sd.assignedSpells and #sd.assignedSpells > 0
               and ns.EnumerateCDMViewerSpells then
                local displayed
                for _, e in ipairs(ns.EnumerateCDMViewerSpells(false)) do
                    local sid = e.sid
                    if type(sid) == "number" and sid > 0 then
                        displayed = displayed or {}
                        displayed[sid] = true
                        displayed[NormalizeToBase(sid)] = true
                        local ov = ResolveToLive(sid)
                        if ov then displayed[ov] = true end
                    end
                end
                if displayed and next(displayed) then
                    -- Blizzard's tracked-cooldown catalog (talent-independent,
                    -- arrangement-aware) -- the source untalented spells were
                    -- materialized from. Lets the keep test below also drop an
                    -- untalented spell the user removed from tracking (moved to Not
                    -- Displayed), which the `displayed` set alone cannot see because
                    -- untalented spells never get a live frame. nil when the provider
                    -- is unavailable -> untalented entries are kept (safe fallback).
                    local catalogSet
                    if ns.EnumerateCDMSettingsCatalog then
                        local cat = ns.EnumerateCDMSettingsCatalog()
                        if cat then
                            catalogSet = {}
                            for _, ce in ipairs(cat) do
                                local s = ce.sid
                                if type(s) == "number" and s > 0 then
                                    catalogSet[s] = true
                                    catalogSet[NormalizeToBase(s)] = true
                                    local ov = ResolveToLive(s)
                                    if ov then catalogSet[ov] = true end
                                end
                            end
                        end
                    end
                    local custom  = sd.customSpellIDs
                    local racials = ns._myRacialsSet
                    local cdurs   = sd.customSpellDurations
                    local sdurs   = sd.spellDurations
                    local groups  = sd.customSpellGroups
                    local hosted  = sd.hostedBuffSpellIDs
                    -- Marker-present set: when a hosted buff has its own MARKER
                    -- entry, a PLAIN entry of the same id is the spell's COOLDOWN
                    -- form and must not borrow the hosted exemption below --
                    -- untracking the cooldown in Blizzard's CDM should drop it
                    -- like any other cooldown while the hosted buff stays.
                    local hostedMarkerFor
                    if hosted then
                        for _, mid in ipairs(sd.assignedSpells) do
                            local mSid = ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(mid)
                            if mSid then
                                hostedMarkerFor = hostedMarkerFor or {}
                                hostedMarkerFor[mSid] = true
                            end
                        end
                    end
                    local writeIdx = 1
                    for readIdx = 1, #sd.assignedSpells do
                        local id = sd.assignedSpells[readIdx]
                        local keep = true
                        -- A HOSTED buff is a real buff (never in the Essential/Utility
                        -- viewer), so the "owned but not displayed -> drop" test below
                        -- would wrongly delete it. It is user-placed -- always keep,
                        -- exactly like a custom spell ID / racial.
                        if type(id) == "number" and id > 0
                           and not (custom and custom[id])
                           and not (racials and racials[id])
                           and not (cdurs and cdurs[id])
                           and not (sdurs and sdurs[id])
                           and not (groups and groups[id])
                           and not (hosted and hosted[id]
                                    and not (hostedMarkerFor and hostedMarkerFor[id])) then
                            -- Plain Blizzard cooldown. Keep it if still displayed OR if
                            -- the player no longer HAS the spell (talented out): a
                            -- talented-out cooldown must hold its rank in the ordered
                            -- list so it returns to the SAME slot when re-talented,
                            -- instead of being deleted here and re-appended at a
                            -- Blizzard-layout position later (the "jumps to a random
                            -- spot after a talent swap" bug). Only a spell the player
                            -- still OWNS but removed from Blizzard's CDM tracking
                            -- (known-but-not-displayed) is genuinely user-cleared -> drop.
                            local shown = displayed[id] or displayed[NormalizeToBase(id)]
                                          or displayed[ResolveToLive(id)]
                            -- IsPlayerSpell is guarded (nil in some contexts): if it is
                            -- unavailable, `have` is falsy so the spell is treated as
                            -- untalented (kept unless the catalog says otherwise).
                            local have = IsPlayerSpell and (IsPlayerSpell(id)
                                         or IsPlayerSpell(NormalizeToBase(id))
                                         or IsPlayerSpell(ResolveToLive(id)))
                            if shown then
                                keep = true
                            elseif have then
                                -- Owned but no longer in the displayed viewer: the user
                                -- cleared it from Blizzard's CDM tracking -> drop.
                                keep = false
                            elseif catalogSet and not importPending then
                                -- Untalented. It only reached the preview by being
                                -- materialized from the settings catalog, so it must
                                -- also LEAVE when removed from tracking: keep only while
                                -- it is still in the catalog. An untalented spell moved
                                -- to Not Displayed is gone from the catalog -> drop.
                                keep = (catalogSet[id] or catalogSet[NormalizeToBase(id)]
                                        or catalogSet[ResolveToLive(id)]) and true or false
                            else
                                -- Untalented with no catalog signal (provider down, or
                                -- mid-import): hold rank -- the safe fallback, so a
                                -- transient gap never wipes an untalented assignment and
                                -- import ghosting keeps ownership of its reconciliation.
                                keep = true
                            end
                        end
                        if keep then
                            sd.assignedSpells[writeIdx] = id
                            writeIdx = writeIdx + 1
                        end
                    end
                    for i = writeIdx, #sd.assignedSpells do sd.assignedSpells[i] = nil end
                    -- Normalize the hosted-buff representation. A hosted buff owns
                    -- a MARKER entry; a plain entry of the same id means the
                    -- COOLDOWN form. Pre-marker data stored the hosted buff as a
                    -- plain entry (flag only), which is ambiguous when the same
                    -- spell is also a cooldown -- resolve each flagged id here,
                    -- where the displayed/catalog sets can tell the forms apart.
                    if sd.hostedBuffSpellIDs and ns.HostedBuffMarker then
                        local list = sd.assignedSpells
                        local ghostSdN = ns.GetBarSpellData and ns.GetBarSpellData("__ghost_cd")
                        local ghostListN = ghostSdN and ghostSdN.assignedSpells
                        local FindVarN = ns.FindVariantIndexInList
                        -- Plain entries claimed by OTHER visible bars (variant-aware):
                        -- if the cooldown form lives elsewhere, a plain entry here is
                        -- a resurrected artifact of the old shared-id model.
                        local claimedN
                        do
                            local spN = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                            local skN = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                            local aprofN = spN and skN and spN[skN]
                            local bsAllN = aprofN and aprofN.barSpells
                            if bsAllN and ns.StoreVariantValue then
                                for kN, bsdN in pairs(bsAllN) do
                                    if kN ~= barKeyE and kN ~= "__ghost_cd"
                                       and type(bsdN) == "table" and type(bsdN.assignedSpells) == "table" then
                                        for _, sidN in ipairs(bsdN.assignedSpells) do
                                            if type(sidN) == "number" and sidN > 0 then
                                                claimedN = claimedN or {}
                                                ns.StoreVariantValue(claimedN, sidN, true, false)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        for hsid in pairs(sd.hostedBuffSpellIDs) do
                            if type(hsid) == "number" and hsid > 0 then
                                local markerN = ns.HostedBuffMarker(hsid)
                                local markerIdx, plainIdx
                                for i = 1, #list do
                                    local v = list[i]
                                    if v == markerN then markerIdx = i
                                    elseif v == hsid then plainIdx = i end
                                end
                                if plainIdx then
                                    -- Is there a real COOLDOWN form for this id --
                                    -- displayed or in the tracked catalog, not
                                    -- hidden on the ghost bar, not claimed by
                                    -- another bar? Then the plain entry is a
                                    -- legitimate cooldown member of this bar.
                                    local isCdForm = (displayed[hsid]
                                        or displayed[NormalizeToBase(hsid)]
                                        or displayed[ResolveToLive(hsid)]
                                        or (catalogSet and (catalogSet[hsid]
                                            or catalogSet[NormalizeToBase(hsid)]
                                            or catalogSet[ResolveToLive(hsid)]))) and true or false
                                    if isCdForm and ghostListN and FindVarN
                                       and FindVarN(ghostListN, hsid) then
                                        isCdForm = false
                                    end
                                    if isCdForm and claimedN and ns.ResolveVariantValue
                                       and ns.ResolveVariantValue(claimedN, hsid) then
                                        isCdForm = false
                                    end
                                    if markerIdx then
                                        -- Marker already present: a plain twin is
                                        -- only kept when it is a real cooldown
                                        -- member; otherwise it is an artifact.
                                        if not isCdForm then
                                            table.remove(list, plainIdx)
                                            ns._spellOrderDirty = true
                                        end
                                    elseif isCdForm then
                                        -- Legit dual form: keep the cooldown entry
                                        -- and give the hosted buff its own slot
                                        -- right next to it.
                                        table.insert(list, plainIdx + 1, markerN)
                                        ns._spellOrderDirty = true
                                    else
                                        -- Buff-only: the plain entry IS the hosted
                                        -- buff -- convert in place (keeps its slot).
                                        list[plainIdx] = markerN
                                        ns._spellOrderDirty = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        -- Self-heal HOSTED buffs. A hosted buff must live in assignedSpells (the
        -- Phase 3 sort keys off its MARKER entry). An earlier build's drop pass
        -- could have stranded one in hostedBuffSpellIDs alone (it never appears in
        -- the Essential/Utility viewer). Re-append the MARKER when neither it nor
        -- a legacy plain entry represents the buff -- never the plain id, which
        -- would resurrect the spell's COOLDOWN form onto this bar (the "removed
        -- cooldown comes back" bug).
        if sd.hostedBuffSpellIDs and sd.assignedSpells and ns.HostedBuffMarker then
            for hsid in pairs(sd.hostedBuffSpellIDs) do
                if type(hsid) == "number" and hsid > 0 then
                    local markerH = ns.HostedBuffMarker(hsid)
                    local present = false
                    for _, sid in ipairs(sd.assignedSpells) do
                        if sid == hsid or sid == markerH then present = true; break end
                    end
                    if not present then
                        sd.assignedSpells[#sd.assignedSpells + 1] = markerH
                        ns._spellOrderDirty = true
                    end
                end
            end
        end
        return sd
    end

    ---------------------------------------------------------------------------
    --  Custom Spell ID popup (shared by ShowSpellPicker + ShowBuffBarPicker)
    --  Lazily builds a single global popup; each call re-binds the Add handler
    --  to the given bar. withDuration adds the duration field (custom/preset
    --  buffs). onAdded(sid) runs after the spellDuration/customSpellID storage.
    ---------------------------------------------------------------------------
    local function ShowCustomSpellIDPopup(barKey, withDuration, onAdded)
        local popupName = "EUI_CDM_SpellIDPopup"
        local popup = _G[popupName]
        if not popup then
            local POPUP_W, POPUP_H = 320, 160
            local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:Hide()
            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
            dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

            popup = CreateFrame("Frame", popupName, dimmer)
            popup:SetSize(POPUP_W, POPUP_H)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            popup:EnableMouse(true)
            local popBg = popup:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints(); popBg:SetColorTexture(0.06, 0.08, 0.10, 1)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)

            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
            title:SetPoint("TOP", popup, "TOP", 0, -18)
            title:SetTextColor(1, 1, 1, 1)
            title:SetText(EllesmereUI.L("Add Custom Spell"))
            popup._title = title

            local editBox = CreateFrame("EditBox", nil, popup)
            editBox:SetSize(180, 28)
            editBox:SetPoint("TOP", title, "BOTTOM", 0, -16)
            editBox:SetAutoFocus(true)
            editBox:SetNumeric(true)
            editBox:SetMaxLetters(7)
            editBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            editBox:SetTextColor(1, 1, 1, 0.9)
            editBox:SetJustifyH("CENTER")
            local ebBg = editBox:CreateTexture(nil, "BACKGROUND")
            ebBg:SetAllPoints(); ebBg:SetColorTexture(0.04, 0.06, 0.08, 1)
            EllesmereUI.MakeBorder(editBox, 1, 1, 1, 0.12, EllesmereUI.PP)

            local placeholder = editBox:CreateFontString(nil, "ARTWORK")
            placeholder:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            placeholder:SetPoint("CENTER")
            placeholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
            placeholder:SetText(EllesmereUI.L("Spell ID"))
            editBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
            end)
            popup._editBox = editBox

            local status = popup:CreateFontString(nil, "OVERLAY")
            status:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            status:SetPoint("TOP", editBox, "BOTTOM", 0, -6)
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

            -- Permanent red note: a manually-entered custom spell has no live
            -- cooldown frame, so charge counts cannot be tracked for it. Shown
            -- only for CD/utility bars (charges do not apply to custom auras).
            local chargeWarn = popup:CreateFontString(nil, "OVERLAY")
            chargeWarn:SetFont(FONT_PATH, 10, GetCDMOptOutline())
            chargeWarn:SetPoint("LEFT", popup, "LEFT", 16, 0)
            chargeWarn:SetPoint("RIGHT", popup, "RIGHT", -16, 0)
            chargeWarn:SetPoint("BOTTOM", addBtn, "TOP", 0, 17)
            chargeWarn:SetJustifyH("CENTER")
            chargeWarn:SetTextColor(0.9, 0.3, 0.3, 1)
            chargeWarn:SetText(EllesmereUI.L("Custom spells cannot track charges."))
            popup._chargeWarn = chargeWarn

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

            editBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)

            local durLabel = popup:CreateFontString(nil, "OVERLAY")
            durLabel:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            durLabel:SetPoint("TOP", editBox, "BOTTOM", 0, -32)
            durLabel:SetTextColor(0.7, 0.7, 0.7, 0.85)
            durLabel:SetText(EllesmereUI.L("Duration (seconds)"))
            popup._durLabel = durLabel

            local durBox = CreateFrame("EditBox", nil, popup)
            durBox:SetSize(180, 28)
            durBox:SetPoint("TOP", durLabel, "BOTTOM", 0, -6)
            durBox:SetNumeric(true)
            durBox:SetMaxLetters(5)
            durBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            durBox:SetTextColor(1, 1, 1, 0.9)
            durBox:SetJustifyH("CENTER")
            local durBg = durBox:CreateTexture(nil, "BACKGROUND")
            durBg:SetAllPoints(); durBg:SetColorTexture(0.04, 0.06, 0.08, 1)
            EllesmereUI.MakeBorder(durBox, 1, 1, 1, 0.12, EllesmereUI.PP)
            local durPlaceholder = durBox:CreateFontString(nil, "ARTWORK")
            durPlaceholder:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            durPlaceholder:SetPoint("CENTER")
            durPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
            durPlaceholder:SetText(EllesmereUI.L("Required"))
            durBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then durPlaceholder:Show() else durPlaceholder:Hide() end
            end)
            durBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)
            popup._durBox = durBox

            popup._dimmer = dimmer
            _G[popupName] = popup
        end

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

        local function DoAdd()
            local text = popup._editBox:GetText()
            local sid = tonumber(text)
            if not sid or sid <= 0 then
                SetStatus("Enter a valid spell ID")
                return
            end
            sid = math.floor(sid)
            local spellName = C_Spell.GetSpellName(sid)
            if not spellName then
                SetStatus("Unknown spell ID")
                return
            end
            local dur
            if withDuration then
                local durText = popup._durBox:GetText()
                dur = tonumber(durText)
                if not dur or dur <= 0 then
                    SetStatus("Enter a duration in seconds")
                    return
                end
                dur = math.floor(dur)
            end
            local sdChk = ns.GetBarSpellData(barKey)
            if sdChk and sdChk.assignedSpells then
                for _, existing in ipairs(sdChk.assignedSpells) do
                    if existing == sid then
                        SetStatus("Already tracked")
                        return
                    end
                end
            end
            if withDuration and dur then
                local sdStore = ns.GetBarSpellData(barKey)
                if sdStore then
                    if not sdStore.spellDurations then sdStore.spellDurations = {} end
                    sdStore.spellDurations[sid] = dur
                end
            end
            popup._dimmer:Hide()
            local sdTag = ns.GetBarSpellData(barKey)
            if sdTag then
                if not sdTag.customSpellIDs then sdTag.customSpellIDs = {} end
                sdTag.customSpellIDs[sid] = true
            end
            if onAdded then onAdded(sid) end
        end

        popup._addBtn:SetScript("OnClick", DoAdd)
        popup._editBox:SetScript("OnEnterPressed", DoAdd)
        popup._editBox:SetText("")
        popup._status:SetText("")
        if withDuration then
            popup:SetHeight(220)
            popup._durLabel:Show()
            popup._durBox:Show()
            popup._durBox:SetText("")
            if popup._chargeWarn then popup._chargeWarn:Hide() end
        else
            popup:SetHeight(164)
            popup._durLabel:Hide()
            popup._durBox:Hide()
            if popup._chargeWarn then popup._chargeWarn:Show() end
        end
        popup._dimmer:Show()
        popup._editBox:SetFocus()
    end

    ---------------------------------------------------------------------------
    --  Custom Item ID popup (shared by ShowSpellPicker + ShowBuffBarPicker).
    --  Item is stored as a negative marker (-itemID) so the item-preset path
    --  renders icon/cooldown/count. onAdded runs after validation; the caller
    --  handles AddTrackedSpell.
    ---------------------------------------------------------------------------
    local function ShowCustomItemIDPopup(barKey, onAdded)
        local popupName = "EUI_CDM_ItemIDPopup"
        local popup = _G[popupName]
        if not popup then
            local POPUP_W, POPUP_H = 320, 164
            local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:Hide()
            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
            dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

            popup = CreateFrame("Frame", popupName, dimmer)
            popup:SetSize(POPUP_W, POPUP_H)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            popup:EnableMouse(true)
            local popBg = popup:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints(); popBg:SetColorTexture(0.06, 0.08, 0.10, 1)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)

            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
            title:SetPoint("TOP", popup, "TOP", 0, -18)
            title:SetTextColor(1, 1, 1, 1)
            title:SetText(EllesmereUI.L("Add Custom Item"))
            popup._title = title

            local editBox = CreateFrame("EditBox", nil, popup)
            editBox:SetSize(180, 28)
            editBox:SetPoint("TOP", title, "BOTTOM", 0, -16)
            editBox:SetAutoFocus(true)
            editBox:SetNumeric(true)
            editBox:SetMaxLetters(9)
            editBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            editBox:SetTextColor(1, 1, 1, 0.9)
            editBox:SetJustifyH("CENTER")
            local ebBg = editBox:CreateTexture(nil, "BACKGROUND")
            ebBg:SetAllPoints(); ebBg:SetColorTexture(0.04, 0.06, 0.08, 1)
            EllesmereUI.MakeBorder(editBox, 1, 1, 1, 0.12, EllesmereUI.PP)

            local placeholder = editBox:CreateFontString(nil, "ARTWORK")
            placeholder:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            placeholder:SetPoint("CENTER")
            placeholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
            placeholder:SetText(EllesmereUI.L("Item ID"))
            editBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
            end)
            popup._editBox = editBox

            local status = popup:CreateFontString(nil, "OVERLAY")
            status:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            status:SetPoint("TOP", editBox, "BOTTOM", 0, -6)
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

            editBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)

            popup._dimmer = dimmer
            _G[popupName] = popup
        end

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

        local function DoAdd()
            local text = popup._editBox:GetText()
            local itemID = tonumber(text)
            if not itemID or itemID <= 0 then
                SetStatus("Enter a valid item ID")
                return
            end
            itemID = math.floor(itemID)
            local itemName = C_Item.GetItemNameByID(itemID)
            if not itemName then
                -- Item data not cached yet -- request it and ask the user to retry.
                C_Item.RequestLoadItemDataByID(itemID)
                SetStatus("Loading item data, try again")
                return
            end
            local marker = -itemID
            local sdChk = ns.GetBarSpellData(barKey)
            if sdChk and sdChk.assignedSpells then
                for _, existing in ipairs(sdChk.assignedSpells) do
                    if existing == marker then
                        SetStatus("Already tracked")
                        return
                    end
                end
            end
            popup._dimmer:Hide()
            if onAdded then onAdded(marker) end
        end

        popup._addBtn:SetScript("OnClick", DoAdd)
        popup._editBox:SetScript("OnEnterPressed", DoAdd)
        popup._editBox:SetText("")
        popup._status:SetText("")
        popup._dimmer:Show()
        popup._editBox:SetFocus()
    end

    ---------------------------------------------------------------------------
    --  Buff Bar Spell Picker
    --  Shows ONLY spells from CDM buff categories (2, 3).
    --  None grayed out. Selecting moves the spell to the target bar.
    ---------------------------------------------------------------------------
    local function ShowBuffBarPicker(anchorFrame, targetBarKey, onChanged)
        if _spellPickerMenu and _spellPickerMenu:IsShown() then
            _spellPickerMenu:Hide()
            if _spellPickerMenu._anchorFrame == anchorFrame then return end
        end

        local mBgR  = EllesmereUI.DD_BG_R  or 0.075
        local mBgG  = EllesmereUI.DD_BG_G  or 0.113
        local mBgB  = EllesmereUI.DD_BG_B  or 0.141
        local mBgA  = EllesmereUI.DD_BG_HA or 0.98
        local mBrdA = EllesmereUI.DD_BRD_A or 0.20
        local hlA   = EllesmereUI.DD_ITEM_HL_A or 0.08
        local tDimR = EllesmereUI.DD_ITEM_R or 0.75
        local tDimG = EllesmereUI.DD_ITEM_G or 0.75
        local tDimB = EllesmereUI.DD_ITEM_B or 0.75
        local tDimA = EllesmereUI.DD_ITEM_A or 0.9
        local menuW = 240
        local ITEM_H = 26
        local MAX_H = 350

        -- Use the same data source as CD/utility: GetCDMSpellsForBar
        local allSpells = ns.GetCDMSpellsForBar and ns.GetCDMSpellsForBar(targetBarKey, true) or {}

        -- Every buff spell is shown and every row is clickable. Clicking a
        -- spell routes AddTrackedSpell, whose family sweep removes the
        -- spell from every other buff-family bar (including the ghost
        -- hidden bar) before claiming it for the target. Same model as
        -- CD/utility bars: one click, one move.
        local knownSpells = {}
        for _, sp in ipairs(allSpells) do
            if sp.cdmCatGroup == "buff" then
                knownSpells[#knownSpells + 1] = sp
            end
        end

        -- No early-out on an empty Blizzard buff list: preset buffs (and, later,
        -- a custom spell ID) are always available below.

        -- Build menu
        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetClampedToScreen(true)
        menu:SetSize(menuW, 10)

        local bgTex = menu:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints(); bgTex:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

        local inner = CreateFrame("Frame", nil, menu)
        inner:SetWidth(menuW)
        inner:SetPoint("TOPLEFT")

        local mH = 4

        -- Helper: create a spell row
        local function MakeSpellRow(sp)
            local item = CreateFrame("Button", nil, inner)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(menu:GetFrameLevel() + 2)

            local iconTex = item:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(ITEM_H - 4, ITEM_H - 4)
            iconTex:SetPoint("LEFT", 4, 0)
            iconTex:SetTexture(sp.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            lbl:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
            lbl:SetPoint("RIGHT", -4, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(EllesmereUI.L(sp.name or ""))
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)

            -- Tracked-but-untalented buffs stay fully clickable but render
            -- desaturated with a hint, matching the CD/utility picker, so bars
            -- can be arranged without swapping talents.
            local notLearned = (sp.isKnown == false)
            if notLearned then iconTex:SetDesaturated(true); iconTex:SetAlpha(0.5) end

            item:SetScript("OnEnter", function()
                lbl:SetTextColor(1, 1, 1, 1)
                hl:SetColorTexture(1, 1, 1, hlA)
                if notLearned then EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.L("Not currently talented")) end
            end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                hl:SetColorTexture(1, 1, 1, 0)
                if notLearned then EllesmereUI.HideWidgetTooltip() end
            end)

            -- Gray the row in place and make it inert. Called after the user
            -- clicks it to add the buff, so the picker can stay open for adding
            -- several buffs in a row.
            item._grayOut = function()
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                iconTex:SetDesaturated(true); iconTex:SetAlpha(0.4)
                hl:SetColorTexture(1, 1, 1, 0)
                if notLearned then EllesmereUI.HideWidgetTooltip() end
                item:SetScript("OnEnter", nil)
                item:SetScript("OnLeave", nil)
                item:SetScript("OnClick", nil)
            end

            mH = mH + ITEM_H
            return item
        end

        -- Custom Spell ID (with duration) entry -- add an arbitrary buff by spell
        -- ID, rendered as a cast-timer custom buff. Its own section at the top,
        -- matching the CD/utility picker.
        do
            local csItem = CreateFrame("Button", nil, inner)
            csItem:SetHeight(ITEM_H)
            csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            csItem:SetFrameLevel(menu:GetFrameLevel() + 2)
            local csHl = csItem:CreateTexture(nil, "ARTWORK")
            csHl:SetAllPoints(); csHl:SetColorTexture(1, 1, 1, 0); csHl:SetAlpha(0)
            local csLbl = csItem:CreateFontString(nil, "OVERLAY")
            csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            csLbl:SetPoint("LEFT", 10, 0); csLbl:SetJustifyH("LEFT")
            csLbl:SetText(EllesmereUI.L("Custom Spell ID"))
            csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            csItem:SetScript("OnEnter", function() csLbl:SetTextColor(1, 1, 1, 1); csHl:SetColorTexture(1, 1, 1, hlA); csHl:SetAlpha(1) end)
            csItem:SetScript("OnLeave", function() csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); csHl:SetAlpha(0) end)
            csItem:SetScript("OnClick", function()
                menu:Hide()
                ShowCustomSpellIDPopup(targetBarKey, true, function(sid)
                    ns.AddTrackedSpell(targetBarKey, sid)
                    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                    if ns.UpdateLustListener then ns.UpdateLustListener() end
                    if ns.QueueReanchor then ns.QueueReanchor() end
                    RefreshCDPreview()
                end)
            end)
            mH = mH + ITEM_H
        end

        -- NOTE: No "Custom Item ID" entry here. Buff bars track auras only (spell
        -- IDs); items (stored as negative -itemID markers) belong on CD/utility
        -- bars. The cdm_strip_buff_bar_item_ids_v1 migration removes any legacy
        -- item markers that were placed on buff bars before this restriction.

        -- Divider below Custom Spell ID, separating it from the presets/list.
        do
            local csDiv = inner:CreateTexture(nil, "ARTWORK")
            csDiv:SetHeight(1); csDiv:SetColorTexture(1, 1, 1, 0.10)
            csDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            csDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- Preset buffs (potions, consumables, Bloodlust, etc.) added as cast-timer
        -- custom buffs via AddPresetToBar; the buff phase injects an own-frame so
        -- they render alongside Blizzard-tracked buffs.
        do
            local alreadyTracked = {}
            local sdPS = ns.GetBarSpellData(targetBarKey)
            if sdPS and sdPS.assignedSpells then
                for _, sid in ipairs(sdPS.assignedSpells) do alreadyTracked[sid] = true end
            end
            local _, _pClass = UnitClass("player")
            for _, preset in ipairs(ns.BUFF_BAR_PRESETS or {}) do
                if (not preset.class or preset.class == _pClass)
                   and (not preset.tbbOnly or preset.customAuraToo) then
                    local primaryID = preset.spellIDs and preset.spellIDs[1]
                    local isAdded = primaryID and alreadyTracked[primaryID]
                    local si = CreateFrame("Button", nil, inner)
                    si:SetHeight(ITEM_H)
                    si:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    si:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    si:SetFrameLevel(menu:GetFrameLevel() + 2)
                    local sIco = si:CreateTexture(nil, "ARTWORK")
                    sIco:SetSize(ITEM_H - 4, ITEM_H - 4)
                    sIco:SetPoint("LEFT", 4, 0)
                    sIco:SetTexture(preset.icon); sIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local sLbl = si:CreateFontString(nil, "OVERLAY")
                    sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    sLbl:SetPoint("LEFT", sIco, "RIGHT", 6, 0); sLbl:SetPoint("RIGHT", -4, 0)
                    sLbl:SetJustifyH("LEFT"); sLbl:SetWordWrap(false); sLbl:SetMaxLines(1)
                    sLbl:SetText(EllesmereUI.L(preset.name or ""))
                    local sHl = si:CreateTexture(nil, "ARTWORK")
                    sHl:SetAllPoints(); sHl:SetColorTexture(1, 1, 1, 0)
                    if isAdded then
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                        sIco:SetDesaturated(true); sIco:SetAlpha(0.4)
                    else
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        si:SetScript("OnEnter", function() sLbl:SetTextColor(1, 1, 1, 1); sHl:SetColorTexture(1, 1, 1, hlA) end)
                        si:SetScript("OnLeave", function() sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); sHl:SetColorTexture(1, 1, 1, 0) end)
                        si:SetScript("OnClick", function()
                            EnsureAssignedSpells(targetBarKey)
                            ns.AddPresetToBar(targetBarKey, preset)
                            if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                            if ns.UpdateLustListener then ns.UpdateLustListener() end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                            RefreshCDPreview()
                            -- Keep the picker open so several buffs can be added
                            -- in a row; gray this preset in place once added.
                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                            sIco:SetDesaturated(true); sIco:SetAlpha(0.4)
                            sHl:SetColorTexture(1, 1, 1, 0)
                            si:SetScript("OnEnter", nil)
                            si:SetScript("OnLeave", nil)
                            si:SetScript("OnClick", nil)
                        end)
                    end
                    mH = mH + ITEM_H
                end
            end

            -- Divider between presets and the Blizzard-tracked buff list
            if #knownSpells > 0 then
                local pDiv = inner:CreateTexture(nil, "ARTWORK")
                pDiv:SetHeight(1); pDiv:SetColorTexture(1, 1, 1, 0.10)
                pDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                pDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9
            end
        end

        for _, sp in ipairs(knownSpells) do
            local item = MakeSpellRow(sp)
            item:SetScript("OnClick", function()
                if onChanged then onChanged(sp.spellID) end
                -- Keep the picker open so several buffs can be added in a row;
                -- gray this row in place to reflect that it was added.
                if item._grayOut then item._grayOut() end
            end)
        end

        -- "Missing Spells?" footer: centered, accent-colored prompt that opens
        -- Blizzard's CDM and closes EUI options, matching the CD/utility picker.
        do
            local fDiv = inner:CreateTexture(nil, "ARTWORK")
            fDiv:SetHeight(1); fDiv:SetColorTexture(1, 1, 1, 0.10)
            fDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            fDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9

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
            mbFS:SetText(EllesmereUI.L("Missing Spells?") .. "\n" .. EllesmereUI.L("Add in Blizzard CDM"))

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

        inner:SetHeight(mH + 4)
        local totalH = math.min(mH + 4, MAX_H)
        menu:SetSize(menuW, totalH)

        -- Scroll if needed
        if mH + 4 > MAX_H then
            local sf = CreateFrame("ScrollFrame", nil, menu)
            sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
            sf:SetFrameLevel(menu:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            sf:SetScrollChild(inner)
            inner:SetWidth(menuW)
            local scrollTarget = 0
            local maxScroll = (mH + 4) - MAX_H
            local SCROLL_STEP = 40
            local SMOOTH_SPEED = 12
            local smoothFrame = CreateFrame("Frame")
            smoothFrame:Hide()
            smoothFrame:SetScript("OnUpdate", function(_, elapsed)
                local cur = sf:GetVerticalScroll()
                scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
                local diff = scrollTarget - cur
                if math.abs(diff) < 0.3 then
                    sf:SetVerticalScroll(scrollTarget)
                    smoothFrame:Hide()
                    return
                end
                sf:SetVerticalScroll(cur + diff * math.min(1, SMOOTH_SPEED * elapsed))
            end)
            sf:SetScript("OnMouseWheel", function(_, delta)
                if maxScroll <= 0 then return end
                local base = smoothFrame:IsShown() and scrollTarget or sf:GetVerticalScroll()
                scrollTarget = math.max(0, math.min(maxScroll, base - delta * SCROLL_STEP))
                smoothFrame:Show()
            end)
        end

        menu:ClearAllPoints()
        menu:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
        menu._anchorFrame = anchorFrame
        _spellPickerMenu = menu

        menu:SetScript("OnUpdate", function(m)
            if not m:IsMouseOver() and not anchorFrame:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                m:Hide()
            end
        end)
        menu:SetScript("OnHide", function(m)
            m:SetScript("OnUpdate", nil)
        end)
        menu:Show()
    end

    -- Buff picker targeting a CD/UTILITY bar. A buff placed here is modelled as a
    -- custom injected spell (always-shown icon) whose Active State is aura-driven:
    -- ns.AddBuffToCDUtilBar wires the injection + the gold aura overlay together.
    -- Lists the class's CDM-trackable buffs plus a Custom Spell ID entry. No
    -- durations (aura-driven, never cast-timed) and no item/preset rows (those are
    -- cast-timer / CD-utility concepts that do not belong on an aura tracker).
    local function ShowBuffToCDPicker(anchorFrame, targetBarKey, onChanged)
        if _spellPickerMenu and _spellPickerMenu:IsShown() then
            _spellPickerMenu:Hide()
            if _spellPickerMenu._anchorFrame == anchorFrame then return end
        end

        local mBgR  = EllesmereUI.DD_BG_R  or 0.075
        local mBgG  = EllesmereUI.DD_BG_G  or 0.113
        local mBgB  = EllesmereUI.DD_BG_B  or 0.141
        local mBgA  = EllesmereUI.DD_BG_HA or 0.98
        local mBrdA = EllesmereUI.DD_BRD_A or 0.20
        local hlA   = EllesmereUI.DD_ITEM_HL_A or 0.08
        local tDimR = EllesmereUI.DD_ITEM_R or 0.75
        local tDimG = EllesmereUI.DD_ITEM_G or 0.75
        local tDimB = EllesmereUI.DD_ITEM_B or 0.75
        local tDimA = EllesmereUI.DD_ITEM_A or 0.9
        local menuW = 240
        local ITEM_H = 26
        local MAX_H = 350

        -- Buff catalog comes from the default buffs bar (passing a CD/util barKey
        -- would return Essential/Utility spells). Dedup against buffs already
        -- HOSTED on this bar so re-opening the menu never re-lists an added
        -- buff. The hosted flag table is the membership truth (assignedSpells
        -- stores hosted buffs as negative markers, and a PLAIN id entry is the
        -- spell's COOLDOWN form -- which must not hide its buff form here).
        local allSpells = ns.GetCDMSpellsForBar and ns.GetCDMSpellsForBar("buffs", true) or {}
        local already = {}
        local sdCur = ns.GetBarSpellData(targetBarKey)
        if sdCur and sdCur.hostedBuffSpellIDs then
            for sid in pairs(sdCur.hostedBuffSpellIDs) do already[sid] = true end
        end
        local knownSpells = {}
        for _, sp in ipairs(allSpells) do
            if sp.cdmCatGroup == "buff" and sp.spellID and not already[sp.spellID] then
                knownSpells[#knownSpells + 1] = sp
            end
        end

        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetClampedToScreen(true)
        menu:SetSize(menuW, 10)

        local bgTex = menu:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints(); bgTex:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

        local inner = CreateFrame("Frame", nil, menu)
        inner:SetWidth(menuW)
        inner:SetPoint("TOPLEFT")

        local mH = 4

        -- Post-add refresh; picker stays open so several buffs add in a row.
        -- onChanged reanchors the live bars and refreshes the preview in place
        -- (same flow as the CD/utility "+" add). No RefreshCDPreview here: its
        -- full page rebuild orphans this still-open picker's anchor, and the
        -- next click falls through onto the rebuilt preview slots -- popping
        -- the per-icon settings dropdown uninvited.
        local function AfterAdd()
            if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
            if ns.QueueReanchor then ns.QueueReanchor() end
            if onChanged then onChanged() end
        end

        -- Custom Spell ID (no duration -- aura-driven).
        do
            local csItem = CreateFrame("Button", nil, inner)
            csItem:SetHeight(ITEM_H)
            csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            csItem:SetFrameLevel(menu:GetFrameLevel() + 2)
            local csHl = csItem:CreateTexture(nil, "ARTWORK")
            csHl:SetAllPoints(); csHl:SetColorTexture(1, 1, 1, 0); csHl:SetAlpha(0)
            local csLbl = csItem:CreateFontString(nil, "OVERLAY")
            csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            csLbl:SetPoint("LEFT", 10, 0); csLbl:SetJustifyH("LEFT")
            csLbl:SetText(EllesmereUI.L("Custom Spell ID"))
            csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            csItem:SetScript("OnEnter", function() csLbl:SetTextColor(1, 1, 1, 1); csHl:SetColorTexture(1, 1, 1, hlA); csHl:SetAlpha(1) end)
            csItem:SetScript("OnLeave", function() csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); csHl:SetAlpha(0) end)
            csItem:SetScript("OnClick", function()
                menu:Hide()
                ShowCustomSpellIDPopup(targetBarKey, false, function(sid)
                    ns.AddBuffToCDUtilBar(targetBarKey, sid)
                    AfterAdd()
                end)
            end)
            mH = mH + ITEM_H
        end

        -- Divider below Custom Spell ID.
        do
            local csDiv = inner:CreateTexture(nil, "ARTWORK")
            csDiv:SetHeight(1); csDiv:SetColorTexture(1, 1, 1, 0.10)
            csDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            csDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- Class buff rows.
        local function MakeSpellRow(sp)
            local item = CreateFrame("Button", nil, inner)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(menu:GetFrameLevel() + 2)
            local iconTex = item:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(ITEM_H - 4, ITEM_H - 4)
            iconTex:SetPoint("LEFT", 4, 0)
            iconTex:SetTexture(sp.icon); iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            lbl:SetPoint("LEFT", iconTex, "RIGHT", 6, 0); lbl:SetPoint("RIGHT", -4, 0)
            lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false); lbl:SetMaxLines(1)
            lbl:SetText(EllesmereUI.L(sp.name or ""))
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)
            -- Tracked-but-untalented buffs: desaturate + hint, still clickable
            -- (AddBuffToCDUtilBar has no learned gate; routes when talented).
            local notLearned = (sp.isKnown == false)
            if notLearned then iconTex:SetDesaturated(true); iconTex:SetAlpha(0.5) end
            item:SetScript("OnEnter", function()
                lbl:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, hlA)
                if notLearned then EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.L("Not currently talented")) end
            end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); hl:SetColorTexture(1, 1, 1, 0)
                if notLearned then EllesmereUI.HideWidgetTooltip() end
            end)
            item:SetScript("OnClick", function()
                if notLearned then EllesmereUI.HideWidgetTooltip() end
                ns.AddBuffToCDUtilBar(targetBarKey, sp.spellID)
                AfterAdd()
                -- Gray this row in place; keep the picker open.
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                iconTex:SetDesaturated(true); iconTex:SetAlpha(0.4)
                hl:SetColorTexture(1, 1, 1, 0)
                item:SetScript("OnEnter", nil); item:SetScript("OnLeave", nil); item:SetScript("OnClick", nil)
            end)
            mH = mH + ITEM_H
            return item
        end
        for _, sp in ipairs(knownSpells) do MakeSpellRow(sp) end

        -- "Missing Buffs?" footer -- opens Blizzard's CDM to Display more buffs.
        do
            local fDiv = inner:CreateTexture(nil, "ARTWORK")
            fDiv:SetHeight(1); fDiv:SetColorTexture(1, 1, 1, 0.10)
            fDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            fDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9

            local FOOTER_H = 38
            local mbItem = CreateFrame("Button", nil, inner)
            mbItem:SetHeight(FOOTER_H)
            mbItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            mbItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            mbItem:SetFrameLevel(menu:GetFrameLevel() + 2)
            local mbFS = mbItem:CreateFontString(nil, "OVERLAY")
            mbFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            mbFS:SetAllPoints(); mbFS:SetJustifyH("CENTER"); mbFS:SetJustifyV("MIDDLE")
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            mbFS:SetTextColor(ar, ag, ab, 1)
            mbFS:SetText(EllesmereUI.L("Missing Buffs?") .. "\n" .. EllesmereUI.L("Add in Blizzard CDM"))
            mbItem:SetScript("OnEnter", function() mbFS:SetTextColor(1, 1, 1, 1) end)
            mbItem:SetScript("OnLeave", function()
                local r, g, b = EllesmereUI.GetAccentColor(); mbFS:SetTextColor(r, g, b, 1)
            end)
            mbItem:SetScript("OnClick", function()
                menu:Hide()
                if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
            end)
            mH = mH + FOOTER_H
        end

        inner:SetHeight(mH + 4)
        local totalH = math.min(mH + 4, MAX_H)
        menu:SetSize(menuW, totalH)

        if mH + 4 > MAX_H then
            local sf = CreateFrame("ScrollFrame", nil, menu)
            sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
            sf:SetFrameLevel(menu:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            sf:SetScrollChild(inner)
            inner:SetWidth(menuW)
            local scrollTarget = 0
            local maxScroll = (mH + 4) - MAX_H
            local SCROLL_STEP = 40
            local SMOOTH_SPEED = 12
            local smoothFrame = CreateFrame("Frame")
            smoothFrame:Hide()
            smoothFrame:SetScript("OnUpdate", function(_, elapsed)
                local cur = sf:GetVerticalScroll()
                scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
                local diff = scrollTarget - cur
                if math.abs(diff) < 0.3 then sf:SetVerticalScroll(scrollTarget); smoothFrame:Hide(); return end
                sf:SetVerticalScroll(cur + diff * math.min(1, SMOOTH_SPEED * elapsed))
            end)
            sf:SetScript("OnMouseWheel", function(_, delta)
                if maxScroll <= 0 then return end
                local base = smoothFrame:IsShown() and scrollTarget or sf:GetVerticalScroll()
                scrollTarget = math.max(0, math.min(maxScroll, base - delta * SCROLL_STEP))
                smoothFrame:Show()
            end)
        end

        menu:ClearAllPoints()
        menu:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
        menu._anchorFrame = anchorFrame
        _spellPickerMenu = menu

        menu:SetScript("OnUpdate", function(m)
            if not m:IsMouseOver() and not anchorFrame:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                m:Hide()
            end
        end)
        menu:SetScript("OnHide", function(m)
            m:SetScript("OnUpdate", nil)
        end)
        menu:Show()
    end

    -- Simple numeric "timer" popup for custom Active State on preset icons.
    -- onConfirm(seconds) fires only when a positive number is entered.
    local function ShowDurationPopup(currentVal, onConfirm)
        local popupName = "EUI_CDM_DurationPopup"
        local popup = _G[popupName]
        if not popup then
            local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:Hide()
            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
            dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

            popup = CreateFrame("Frame", popupName, dimmer)
            popup:SetSize(300, 150)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            popup:EnableMouse(true)
            local popBg = popup:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints(); popBg:SetColorTexture(0.06, 0.08, 0.10, 1)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)
            popup._dimmer = dimmer

            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
            title:SetPoint("TOP", popup, "TOP", 0, -18)
            title:SetTextColor(1, 1, 1, 1)
            title:SetText(EllesmereUI.L("Active State Duration"))

            local hint = popup:CreateFontString(nil, "OVERLAY")
            hint:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
            hint:SetTextColor(0.7, 0.7, 0.7, 0.85)
            hint:SetText(EllesmereUI.L("Seconds the active state shows after use"))

            local durBox = CreateFrame("EditBox", nil, popup)
            durBox:SetSize(180, 28)
            durBox:SetPoint("TOP", hint, "BOTTOM", 0, -12)
            durBox:SetAutoFocus(true)
            durBox:SetNumeric(true)
            durBox:SetMaxLetters(5)
            durBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            durBox:SetTextColor(1, 1, 1, 0.9)
            durBox:SetJustifyH("CENTER")
            local durBg = durBox:CreateTexture(nil, "BACKGROUND")
            durBg:SetAllPoints(); durBg:SetColorTexture(0.04, 0.06, 0.08, 1)
            EllesmereUI.MakeBorder(durBox, 1, 1, 1, 0.12, EllesmereUI.PP)
            popup._durBox = durBox

            local ar, ag, ab = EllesmereUI.GetAccentColor()
            local okBtn = CreateFrame("Button", nil, popup)
            okBtn:SetSize(80, 28)
            okBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
            local okBg = okBtn:CreateTexture(nil, "BACKGROUND")
            okBg:SetAllPoints(); okBg:SetColorTexture(ar, ag, ab, 0.15)
            EllesmereUI.MakeBorder(okBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
            local okLbl = okBtn:CreateFontString(nil, "OVERLAY")
            okLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            okLbl:SetPoint("CENTER"); okLbl:SetText(EllesmereUI.L("Save"))
            okLbl:SetTextColor(ar, ag, ab, 0.9)
            okBtn:SetScript("OnEnter", function() okLbl:SetTextColor(1, 1, 1, 1) end)
            okBtn:SetScript("OnLeave", function() okLbl:SetTextColor(ar, ag, ab, 0.9) end)

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

            local function Commit()
                local v = tonumber(durBox:GetText())
                if v and v > 0 then
                    dimmer:Hide()
                    if popup._onConfirm then popup._onConfirm(v) end
                end
            end
            okBtn:SetScript("OnClick", Commit)
            durBox:SetScript("OnEnterPressed", Commit)
            durBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)
        end
        popup._onConfirm = onConfirm
        popup._durBox:SetText(currentVal and tostring(currentVal) or "")
        popup._dimmer:Show()
        popup._durBox:SetFocus()
        popup._durBox:HighlightText()
    end

    -- Numeric popup for the "Lower Alpha (On CD)" cooldown-state effect: the user
    -- enters an opacity percent (1-100) that the icon uses while on cooldown.
    -- Mirrors ShowDurationPopup's look; onConfirm receives the integer percent.
    local function ShowAlphaPopup(currentPct, onConfirm)
        local popupName = "EUI_CDM_AlphaPopup"
        local popup = _G[popupName]
        if not popup then
            local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:Hide()
            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
            dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

            popup = CreateFrame("Frame", popupName, dimmer)
            popup:SetSize(300, 150)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            popup:EnableMouse(true)
            local popBg = popup:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints(); popBg:SetColorTexture(0.06, 0.08, 0.10, 1)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)
            popup._dimmer = dimmer

            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
            title:SetPoint("TOP", popup, "TOP", 0, -18)
            title:SetTextColor(1, 1, 1, 1)
            title:SetText(EllesmereUI.L("Lower Alpha"))

            local hint = popup:CreateFontString(nil, "OVERLAY")
            hint:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
            hint:SetTextColor(0.7, 0.7, 0.7, 0.85)
            hint:SetText(EllesmereUI.L("Icon opacity while on cooldown (1-100%)"))

            local box = CreateFrame("EditBox", nil, popup)
            box:SetSize(180, 28)
            box:SetPoint("TOP", hint, "BOTTOM", 0, -12)
            box:SetAutoFocus(true)
            box:SetNumeric(true)
            box:SetMaxLetters(3)
            box:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            box:SetTextColor(1, 1, 1, 0.9)
            box:SetJustifyH("CENTER")
            local boxBg = box:CreateTexture(nil, "BACKGROUND")
            boxBg:SetAllPoints(); boxBg:SetColorTexture(0.04, 0.06, 0.08, 1)
            EllesmereUI.MakeBorder(box, 1, 1, 1, 0.12, EllesmereUI.PP)
            popup._box = box

            local ar, ag, ab = EllesmereUI.GetAccentColor()
            local okBtn = CreateFrame("Button", nil, popup)
            okBtn:SetSize(80, 28)
            okBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
            local okBg = okBtn:CreateTexture(nil, "BACKGROUND")
            okBg:SetAllPoints(); okBg:SetColorTexture(ar, ag, ab, 0.15)
            EllesmereUI.MakeBorder(okBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
            local okLbl = okBtn:CreateFontString(nil, "OVERLAY")
            okLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            okLbl:SetPoint("CENTER"); okLbl:SetText(EllesmereUI.L("Save"))
            okLbl:SetTextColor(ar, ag, ab, 0.9)
            okBtn:SetScript("OnEnter", function() okLbl:SetTextColor(1, 1, 1, 1) end)
            okBtn:SetScript("OnLeave", function() okLbl:SetTextColor(ar, ag, ab, 0.9) end)

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

            local function Commit()
                local v = tonumber(box:GetText())
                if v and v >= 1 and v <= 100 then
                    dimmer:Hide()
                    if popup._onConfirm then popup._onConfirm(math.floor(v)) end
                end
            end
            okBtn:SetScript("OnClick", Commit)
            box:SetScript("OnEnterPressed", Commit)
            box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
        end
        popup._onConfirm = onConfirm
        popup._box:SetText(currentPct and tostring(currentPct) or "")
        popup._dimmer:Show()
        popup._box:SetFocus()
        popup._box:HighlightText()
    end

    -- Numeric popup for the per-spell "Threshold Seconds" (Threshold Text): the
    -- user enters the seconds-remaining boundary below which Threshold Color /
    -- Threshold Decimals apply. 0 disarms the feature for the spell. Mirrors
    -- ShowAlphaPopup's look; onConfirm receives the integer seconds (0-59).
    local function ShowThresholdSecondsPopup(currentVal, onConfirm)
        local popupName = "EUI_CDM_ThresholdSecondsPopup"
        local popup = _G[popupName]
        if not popup then
            local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:Hide()
            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
            dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

            popup = CreateFrame("Frame", popupName, dimmer)
            popup:SetSize(300, 150)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            popup:EnableMouse(true)
            local popBg = popup:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints(); popBg:SetColorTexture(0.06, 0.08, 0.10, 1)
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)
            popup._dimmer = dimmer

            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
            title:SetPoint("TOP", popup, "TOP", 0, -18)
            title:SetTextColor(1, 1, 1, 1)
            title:SetText(EllesmereUI.L("Threshold Seconds"))

            local hint = popup:CreateFontString(nil, "OVERLAY")
            hint:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
            hint:SetTextColor(0.7, 0.7, 0.7, 0.85)
            hint:SetText(EllesmereUI.L("Seconds left when threshold text starts (0 = off)"))

            local box = CreateFrame("EditBox", nil, popup)
            box:SetSize(180, 28)
            box:SetPoint("TOP", hint, "BOTTOM", 0, -12)
            box:SetAutoFocus(true)
            box:SetNumeric(true)
            box:SetMaxLetters(2)
            box:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            box:SetTextColor(1, 1, 1, 0.9)
            box:SetJustifyH("CENTER")
            local boxBg = box:CreateTexture(nil, "BACKGROUND")
            boxBg:SetAllPoints(); boxBg:SetColorTexture(0.04, 0.06, 0.08, 1)
            EllesmereUI.MakeBorder(box, 1, 1, 1, 0.12, EllesmereUI.PP)
            popup._box = box

            local ar, ag, ab = EllesmereUI.GetAccentColor()
            local okBtn = CreateFrame("Button", nil, popup)
            okBtn:SetSize(80, 28)
            okBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
            local okBg = okBtn:CreateTexture(nil, "BACKGROUND")
            okBg:SetAllPoints(); okBg:SetColorTexture(ar, ag, ab, 0.15)
            EllesmereUI.MakeBorder(okBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
            local okLbl = okBtn:CreateFontString(nil, "OVERLAY")
            okLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            okLbl:SetPoint("CENTER"); okLbl:SetText(EllesmereUI.L("Save"))
            okLbl:SetTextColor(ar, ag, ab, 0.9)
            okBtn:SetScript("OnEnter", function() okLbl:SetTextColor(1, 1, 1, 1) end)
            okBtn:SetScript("OnLeave", function() okLbl:SetTextColor(ar, ag, ab, 0.9) end)

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

            local function Commit()
                local v = tonumber(box:GetText())
                if v and v >= 0 and v <= 59 then
                    dimmer:Hide()
                    if popup._onConfirm then popup._onConfirm(math.floor(v)) end
                end
            end
            okBtn:SetScript("OnClick", Commit)
            box:SetScript("OnEnterPressed", Commit)
            box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
        end
        popup._onConfirm = onConfirm
        popup._box:SetText(currentVal and tostring(currentVal) or "")
        popup._dimmer:Show()
        popup._box:SetFocus()
        popup._box:HighlightText()
    end

    local function ShowSpellPicker(anchorFrame, barKey, slotIndex, excludeSet, onSelect, removeOnly)
        -- Toggle: if the picker is already open for this same icon, close it
        if _spellPickerMenu and _spellPickerMenu:IsShown() and _spellPickerMenu._anchorFrame == anchorFrame then
            _spellPickerMenu:Hide()
            return
        end
        -- Close existing
        if _spellPickerMenu then _spellPickerMenu:Hide() end

        local bd = SelectedCDMBar()
        local isCustomBuff = bd and bd.barType == "custom_buff"
        local isBuffBar = bd and ns.IsBarBuffFamily(bd)

        -- Per-icon buff settings key = the slot's DISPLAYED spell (its canonical /
        -- GetSpellID-derived id, _previewSpellID). NOT the cooldownInfo base: for
        -- some buffs the cooldownInfo base is an unrelated GENERIC spec spell shared
        -- by several icons (e.g. Consecration's standing-in aura resolves to
        -- Protection Paladin 137028), which both collides -- settings leak onto a
        -- "random" icon -- and never matches the real buff. The displayed id is
        -- specific to this buff, and the render resolves the same id canon-first
        -- (see RefreshCDMIconAppearance), so writer and reader agree. Custom/injected
        -- buffs have their own positive id as _previewSpellID, which works too.
        local function ResolveBuffSettingsKey(af)
            local sid = af and af._previewSpellID
            if not sid then return nil end
            -- Same-spellID collision (Diabolist Demonic Art vs Diabolic Ritual):
            -- when two viewer slots share this displayed id, key THIS slot by its
            -- own cooldownID so each is configured independently. Non-collided
            -- buffs keep the stable spellID key (survives talent swaps).
            local cdID = af and (af._previewCdID or af.cooldownID)
            if type(cdID) == "number" then
                local ckey = "c" .. cdID
                -- Read-your-writes: once a per-cooldownID entry exists, keep
                -- editing it even if the collision later ends (re-talent), so the
                -- menu never splits from what the runtime resolver reads (which
                -- prefers an existing c-entry whenever one is present).
                local bstore = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore("buffs")
                if bstore and bstore[ckey] then return ckey end
                if ns.IsCollidedBuffSid and ns.IsCollidedBuffSid(sid) then return ckey end
            end
            return sid
        end

        local allSpells = {}
        if not removeOnly and not isCustomBuff then
            allSpells = ns.GetCDMSpellsForBar(barKey) or {}
            if #allSpells == 0 and not isCustomBuff then return end
        end

        -- Standard EllesmereUI dropdown colors
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

        local menuW = 210
        local ITEM_H = 26
        local MAX_H = 400  -- tall enough for the fullest per-spell menus (buff branch: actions + 10 settings incl. Threshold Text + dividers); this menu has no scroll, so anything over MAX_H gets clipped

        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetClampedToScreen(true)
        menu:SetSize(menuW, 10)
        menu:EnableMouse(true)

        -- Background + border (standard dropdown style)
        local bg = menu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

        -- Build item list: tracked first (minus current), divider, rest, disabled at bottom
        local tracked = {}
        local bd = SelectedCDMBar()
        local sd = bd and ns.GetBarSpellData(bd.key)
        if sd and sd.assignedSpells then
            for _, sid in ipairs(sd.assignedSpells) do tracked[sid] = true end
        end

        -- Determine primary/secondary category order based on bar type.
        -- Cooldown-type bars: Essential (0) first, Utility (1) second.
        -- Utility-type bars: Utility (1) first, Essential (0) second.
        local resolvedType = ns.GetBarType and ns.GetBarType(bd or barKey) or barKey
        local isCooldownType = (resolvedType == "cooldowns")
        local isUtilityType  = (resolvedType == "utility")
        local isCDorUtil = isCooldownType or isUtilityType
        local primaryCat   = isCooldownType and 0 or (isUtilityType and 1 or nil)
        local secondaryCat = isCooldownType and 1 or (isUtilityType and 0 or nil)

        local isBuffBar = bd and ns.IsBarBuffFamily(bd)

        -- Buckets for cooldown/utility bars (three-section layout)
        local priUnassigned, priAssigned = {}, {}
        local secUnassigned, secAssigned = {}, {}
        local notTracked = {}
        local itemsExtra = {}
        -- Single bucket for buff/trinket/other bars (picker only enumerates
        -- live pool members, so all spells are tracked + learned).
        local itemsDisplayed = {}

        for _, sp in ipairs(allSpells) do
            if sp.isExtra then
                if not isBuffBar then itemsExtra[#itemsExtra + 1] = sp end
            elseif isCDorUtil then
                if sp.cdmCat == primaryCat then
                    if sp.onEUIBar then priAssigned[#priAssigned + 1] = sp
                    else priUnassigned[#priUnassigned + 1] = sp end
                elseif sp.cdmCat == secondaryCat then
                    if sp.onEUIBar then secAssigned[#secAssigned + 1] = sp
                    else secUnassigned[#secUnassigned + 1] = sp end
                else
                    notTracked[#notTracked + 1] = sp
                end
            else
                itemsDisplayed[#itemsDisplayed + 1] = sp
            end
        end

        -- Inner scroll container
        local inner = CreateFrame("Frame", nil, menu)
        inner:SetWidth(menuW)
        inner:SetPoint("TOPLEFT")

        local mH = 4
        local allItems = {}

        -- "Remove Spell" option at top (only for right-click on existing icon).
        -- The default buff bar (key == "buffs") can't remove Blizzard-tracked
        -- buffs (visibility is Blizzard's CDM), BUT injected custom/preset buffs
        -- the user added ARE removable there. Extra buff + CD/util bars always
        -- allow removal.
        local rmSpellID = nil
        local rmIsInjected = false
        do
            local rmSd = ns.GetBarSpellData(barKey)
            -- Buff bars: prefer the slot's own _previewSpellID (the default buffs
            -- bar's slots don't map to assignedSpells -- see the settings block).
            if isBuffBar then
                rmSpellID = ResolveBuffSettingsKey(anchorFrame)
                    or (rmSd and rmSd.assignedSpells and rmSd.assignedSpells[slotIndex])
            else
                rmSpellID = rmSd and rmSd.assignedSpells and rmSd.assignedSpells[slotIndex]
                if (not rmSpellID or rmSpellID == 0) and anchorFrame and anchorFrame._previewSpellID then
                    rmSpellID = anchorFrame._previewSpellID
                end
            end
            rmIsInjected = (rmSpellID and rmSd and (
                (rmSd.spellDurations and (rmSd.spellDurations[rmSpellID] or 0) > 0)
                or (rmSd.customSpellIDs and rmSd.customSpellIDs[rmSpellID]))) and true or false
        end
        if slotIndex and (barKey ~= "buffs" or rmIsInjected) then
            local rmItem = CreateFrame("Button", nil, inner)
            rmItem:SetHeight(ITEM_H)
            rmItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            rmItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            rmItem:SetFrameLevel(menu:GetFrameLevel() + 2)

            local rmLbl = rmItem:CreateFontString(nil, "OVERLAY")
            rmLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            rmLbl:SetPoint("LEFT", 10, 0)
            rmLbl:SetJustifyH("LEFT")
            rmLbl:SetText(EllesmereUI.L("Remove Spell"))
            rmLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local rmHl = rmItem:CreateTexture(nil, "ARTWORK")
            rmHl:SetAllPoints(); rmHl:SetColorTexture(1, 1, 1, 0); rmHl:SetAlpha(0)

            rmItem:SetScript("OnEnter", function()
                rmLbl:SetTextColor(1, 1, 1, 1)
                rmHl:SetColorTexture(1, 1, 1, hlA); rmHl:SetAlpha(1)
                if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
            end)
            rmItem:SetScript("OnLeave", function()
                rmLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                rmHl:SetAlpha(0)
            end)
            rmItem:SetScript("OnClick", function()
                menu:Hide()
                if barKey == "buffs" then
                    -- Main buffs bar: slotIndex maps to the mixed preview list
                    -- (Blizzard buffs + customs), not assignedSpells, so remove
                    -- the injected custom by spellID and clean its metadata.
                    if rmSpellID then
                        ns.RemoveSpellFromBar(barKey, rmSpellID)
                        local sdR = ns.GetBarSpellData(barKey)
                        if sdR and sdR.spellDurations then sdR.spellDurations[rmSpellID] = nil end
                        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                        if ns.QueueReanchor then ns.QueueReanchor() end
                    end
                else
                    -- A legacy-duplicate buff slot covers >1 assignedSpells entry
                    -- (anchorFrame._dataGroup); remove them all, highest index
                    -- first. Normal slots have one entry (or no group) -> plain remove.
                    local grp = anchorFrame and anchorFrame._dataGroup
                    if grp and #grp > 1 then
                        local order = {}
                        for _, v in ipairs(grp) do order[#order + 1] = v end
                        table.sort(order, function(a, b) return a > b end)
                        for _, gi in ipairs(order) do ns.RemoveTrackedSpell(barKey, gi) end
                    else
                        ns.RemoveTrackedSpell(barKey, slotIndex)
                    end
                end
                RefreshCDPreview()
            end)

            allItems[#allItems + 1] = rmItem
            mH = mH + ITEM_H
        end

        -- Main buffs bar, Blizzard-tracked buff (not an injected custom): it can't
        -- be removed in EUI (Blizzard owns its tracking), so offer a "Delete Spell"
        -- row that opens Blizzard's Cooldown Manager (closes EUI options + opens the
        -- Blizzard CDM), matching the page's link behavior.
        if slotIndex and barKey == "buffs" and not rmIsInjected and rmSpellID then
            local dsItem = CreateFrame("Button", nil, inner)
            dsItem:SetHeight(ITEM_H)
            dsItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            dsItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            dsItem:SetFrameLevel(menu:GetFrameLevel() + 2)

            local dsHl = dsItem:CreateTexture(nil, "ARTWORK")
            dsHl:SetAllPoints(); dsHl:SetColorTexture(1, 1, 1, 0); dsHl:SetAlpha(0)

            local dsLbl = dsItem:CreateFontString(nil, "OVERLAY")
            dsLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            dsLbl:SetPoint("LEFT", 10, 0)
            dsLbl:SetJustifyH("LEFT")
            dsLbl:SetText(EllesmereUI.L("Delete Spell"))
            dsLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            dsItem:SetScript("OnEnter", function()
                dsLbl:SetTextColor(1, 1, 1, 1)
                dsHl:SetColorTexture(1, 1, 1, hlA); dsHl:SetAlpha(1)
                if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
            end)
            dsItem:SetScript("OnLeave", function()
                dsLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                dsHl:SetAlpha(0)
            end)
            dsItem:SetScript("OnClick", function()
                menu:Hide()
                if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
            end)

            allItems[#allItems + 1] = dsItem
            mH = mH + ITEM_H
        end

        if removeOnly then
            -- Per-icon settings. CD/utility bars get the full menu; buff-family
            -- bars get a buff-specific subset. custom_buff (Auras) bars are
            -- excluded here (separate system, pending consolidation).
            if slotIndex and not isCustomBuff then
                local sd = ns.GetBarSpellData(barKey)
                -- Buff bars: the preview slot's own _previewSpellID is the
                -- authoritative id. The default buffs bar's preview maps to a MIXED
                -- list (Blizzard buffs + injected customs), NOT to assignedSpells, so
                -- indexing assignedSpells by the preview slot returns the WRONG entry
                -- there. CD/utility slots map 1:1 to assignedSpells (and carry
                -- negative trinket/item markers _previewSpellID doesn't), so keep
                -- the index path for those.
                local spellID
                if isBuffBar then
                    spellID = ResolveBuffSettingsKey(anchorFrame)
                        or (sd and sd.assignedSpells and sd.assignedSpells[slotIndex])
                else
                    spellID = sd and sd.assignedSpells and sd.assignedSpells[slotIndex]
                    if (not spellID or spellID == 0) and anchorFrame and anchorFrame._previewSpellID then
                        spellID = anchorFrame._previewSpellID
                    end
                    -- Hosted-buff MARKER slot: settings key by the DECODED spell id
                    -- (the id the render resolver and the buffs bar key by), never
                    -- the raw marker.
                    if spellID and ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(spellID) then
                        spellID = ns.HostedBuffMarkerToSpell(spellID)
                    end
                end
                if spellID and spellID ~= 0 then
                    -- Hosted-buff SLOT? The slot decides, not the flag alone: the
                    -- same spellID can also be this bar's cooldown entry, and that
                    -- slot must keep the CD store + cd/util menu. Legacy fallback:
                    -- flag set with no marker entry yet means the plain entry is
                    -- the buff (pre-marker data).
                    local isHostedBuff = (anchorFrame and anchorFrame._previewHostedBuff) or false
                    if not isHostedBuff and sd.hostedBuffSpellIDs and sd.hostedBuffSpellIDs[spellID]
                       and not (ns.ListHasHostedMarker and sd.assignedSpells
                                and ns.ListHasHostedMarker(sd.assignedSpells, spellID)) then
                        isHostedBuff = true
                    end
                    -- Per-spell entries live in the spec FAMILY store (they travel
                    -- with the spell across bars). The bar tiers sit below them:
                    -- sd.barSettings ("Apply to Bar") -> bd.barSpellSettings
                    -- ("Apply to Bar (All Specs)"). A hosted buff uses the BUFF
                    -- store -- the same entry it had on the buffs bar -- and never
                    -- chains to this bar's (cd/util) tiers.
                    local store = ns.GetSpellSettingsStore(isHostedBuff and "buffs" or barKey, true)
                    local bdSel = ns.barDataByKey and ns.barDataByKey[barKey]
                    local famKey = ns.SettingsFamilyKey(isHostedBuff and "buffs" or barKey)
                    -- Effective-read view: the entry (or a not-yet-persisted fresh
                    -- table) chained to the bar tiers, so the menu shows the values
                    -- the icon actually renders with. EnsureSS() persists the entry
                    -- on first WRITE.
                    local ss = store and store[spellID]
                    if not ss then ss = {} end
                    ns.ChainSettings(ss, isHostedBuff and nil or ns.GetBarTierSettings(sd, barKey))
                    local function EnsureSS()
                        if store and not store[spellID] then
                            store[spellID] = ss
                            -- Flip the runtime hot-path gate the moment a
                            -- cooldownID-scoped buff entry is first persisted.
                            if type(spellID) == "string" and string.byte(spellID, 1) == 99
                               and ns.MarkBuffFamHasCdKey then
                                ns.MarkBuffFamHasCdKey()
                            end
                        end
                        return ss
                    end
                    -- Own-value writer for clearable keys: writing nil would let an
                    -- inherited bar-tier value show through; when that would change
                    -- the effective value, store explicit false instead (false is
                    -- render-equivalent to nil for every settings key, but blocks
                    -- the inheritance).
                    local function SetOwn(key, val)
                        ss[key] = val
                        if val == nil and ss[key] ~= nil then
                            ss[key] = false
                        end
                    end

                    -----------------------------------------------------------
                    --  "Apply to Bar" machinery (hover strip on flyout items).
                    --  One table local (AB) instead of individual locals: this
                    --  function is enormous and Lua 5.1 caps active locals at 200.
                    -----------------------------------------------------------
                    local AB = {}
                    -- Run fn(sid, entry) for every per-spell entry belonging to a
                    -- bar in the given spec profile. The DEFAULT buffs bar owns
                    -- every buff-store entry not claimed by another buff bar
                    -- (Blizzard-tracked buffs are not in assignedSpells).
                    AB.ForEachMemberEntry = function(prof, bsX, fn)
                        local st = prof and prof[famKey]
                        if not st then return end
                        if barKey == "buffs" then
                            local claimed = {}
                            local bsAll = prof.barSpells
                            if bsAll then
                                for k2, b2 in pairs(bsAll) do
                                    if k2 ~= "buffs" and type(b2) == "table"
                                       and ns.IsBarBuffFamily and ns.IsBarBuffFamily(k2)
                                       and type(b2.assignedSpells) == "table" then
                                        for _, sid2 in ipairs(b2.assignedSpells) do
                                            claimed[sid2] = true
                                        end
                                    end
                                    -- Also exclude HOSTED buffs (on cd/util bars): they are
                                    -- removed from Apply-to-Bar, so a default-buffs-bar apply
                                    -- must not treat their buff-store entry as an unclaimed
                                    -- member and wipe it.
                                    if type(b2) == "table" and type(b2.hostedBuffSpellIDs) == "table" then
                                        for hsid in pairs(b2.hostedBuffSpellIDs) do
                                            claimed[hsid] = true
                                        end
                                    end
                                end
                            end
                            for sid2, e in pairs(st) do
                                if type(e) == "table" and not claimed[sid2] then fn(sid2, e) end
                            end
                        elseif bsX and type(bsX.assignedSpells) == "table" then
                            -- Hosted buffs are excluded from Apply-to-Bar: never treat one
                            -- as a bar member (so a bar apply can't clear/overwrite its
                            -- per-spell settings).
                            local hosted = bsX.hostedBuffSpellIDs
                            for _, sid2 in ipairs(bsX.assignedSpells) do
                                if not (hosted and hosted[sid2]) then
                                    local e = st[sid2]
                                    if type(e) == "table" then fn(sid2, e) end
                                end
                            end
                        end
                    end

                    -- Zero-cost feature gates: a bar-tier write can enable features
                    -- the per-spell setters normally arm -- flip the same flags.
                    AB.FlipSessionGates = function(t)
                        if not t then return end
                        if t.reverseSwipe then ns._cdmAnyReverseSwipe = true end
                        if t.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
                        if (tonumber(t.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end
                        if t.maxStacksGlow and t.maxStacksGlow > 0 then ns._cdmAnyMaxStacksGlow = true end
                        if t.desatNotActive then ns._cdmAnyDesatNotActive = true end
                        if t.chargeHideCdText then ns._cdmAnyChargeHideCdText = true end
                        if t.chargeHideSwipe or t.hideRechargeEdge then ns._cdmAnyChargeStyle = true end
                        if t.cdReadySoundKey and t.cdReadySoundKey ~= "none" then ns._cdmAnyCdReadySound = true end
                        if (t.buffActiveSoundKey and t.buffActiveSoundKey ~= "none")
                            or (t.buffLostSoundKey and t.buffLostSoundKey ~= "none") then
                            ns._cdmAnyBuffSound = true
                        end
                    end

                    -- Any Resource Aware CD-ready glow already saved in this spec
                    -- (per-spell entries or bar tiers)? Gates the one-time perf
                    -- confirm popup, mirroring the per-spell setter.
                    AB.AnyResourceAwareGlowSaved = function()
                        local function hit(b)
                            local e2 = b and b.cdStateEffect
                            return e2 == "pixelGlowReadyUsable" or e2 == "buttonGlowReadyUsable"
                        end
                        local st = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore(barKey)
                        if st then
                            for _, e in pairs(st) do
                                if type(e) == "table" and hit(e) then return true end
                            end
                        end
                        local cb = ns.ECME and ns.ECME.db and ns.ECME.db.profile
                            and ns.ECME.db.profile.cdmBars
                        local barsList = cb and cb.bars
                        if barsList then
                            for _, b2 in ipairs(barsList) do
                                if hit(b2.barSpellSettings) then return true end
                                local bsd = ns.GetBarSpellData and ns.GetBarSpellData(b2.key)
                                if bsd and hit(bsd.barSettings) then return true end
                            end
                        end
                        return false
                    end

                    -- Keys that preset/custom icons route through the profile-level
                    -- customActiveStates store instead of the ss/tier chain (their
                    -- Fake-Active engine reads rule.cas first). A bar apply touching
                    -- any of these also stamps each preset member's cas entry, so
                    -- "Apply to Bar" styles preset icons too.
                    AB.CAS_KEYS = {
                        activeSwipeMode = true, activeSwipeClassColor = true,
                        activeSwipeR = true, activeSwipeG = true,
                        activeSwipeB = true, activeSwipeA = true,
                        activeGlow = true, glowColor = true,
                        glowColorR = true, glowColorG = true, glowColorB = true,
                        cdStateEffect = true, cdStateLowerAlpha = true,
                        reverseSwipe = true, hideCDSwipe = true,
                        thresholdSeconds = true, thresholdDecimals = true,
                        thresholdColorEnabled = true, thresholdColorR = true,
                        thresholdColorG = true, thresholdColorB = true,
                    }
                    AB.StampMemberCas = function(bsX, applyWrite, val, keys)
                        if not (bsX and type(bsX.assignedSpells) == "table") then return end
                        if not (ns.GetCustomActiveState and ns.ResolveCustomActiveKey) then return end
                        -- cas semantics: nil = no cd-state effect (PresetHasCdState
                        -- checks effect presence). The explicit blocking-false is a
                        -- tier / per-trinket-exclusion concept -- strip it from
                        -- stamps. Threshold Text keys share the same cas semantics.
                        local function StripFalse(e)
                            if e.cdStateEffect == false then e.cdStateEffect = nil end
                            if e.thresholdSeconds == false then e.thresholdSeconds = nil end
                            if e.thresholdDecimals == false then e.thresholdDecimals = nil end
                            if e.thresholdColorEnabled == false then e.thresholdColorEnabled = nil end
                        end
                        for _, sid2 in ipairs(bsX.assignedSpells) do
                            local isInj = ((type(sid2) == "number" and sid2 < 0)
                                or (ns._myRacialsSet and ns._myRacialsSet[sid2])
                                or (bsX.customSpellIDs and bsX.customSpellIDs[sid2]))
                                -- Hosted-buff markers are reparented Blizzard buff
                                -- frames, not preset icons -- never mint cas entries
                                -- for them.
                                and not (ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid2))
                            if isInj then
                                if sid2 == -13 or sid2 == -14 then
                                    -- Trinket slots stamp the SLOT entry: one bar
                                    -- application that covers whatever trinket is
                                    -- equipped, now or after any swap -- no entry
                                    -- minted per equipped item.
                                    local e = ns.GetCustomActiveState(sid2, true)
                                    if e then
                                        applyWrite(e, val)
                                        StripFalse(e)
                                    end
                                    -- Clear the applied keys from the EQUIPPED
                                    -- trinket's own (item-keyed) entry so the apply
                                    -- visibly takes effect on it -- mirroring the
                                    -- member-entry clear RunBarApply does for family
                                    -- keys. A per-trinket exclusion is re-chosen in
                                    -- the menu AFTER an apply; benched trinkets keep
                                    -- their per-item choices untouched.
                                    local itemID = GetInventoryItemID("player", -sid2)
                                    local own = itemID and ns.GetCustomActiveState(-itemID) or nil
                                    if own and keys then
                                        for _, k2 in ipairs(keys) do own[k2] = nil end
                                    end
                                else
                                    local e = ns.GetCustomActiveState(ns.ResolveCustomActiveKey(sid2), true)
                                    if e then
                                        applyWrite(e, val)
                                        StripFalse(e)
                                    end
                                end
                            end
                        end
                    end

                    -- How many existing values would this apply REPLACE? Counts
                    -- member per-spell entries (and preset cas entries / other
                    -- specs' bar-tier values for All Specs) whose own value for a
                    -- touched key differs from the value being applied -- equal
                    -- values are consumed with zero loss and don't count. Drives
                    -- the "overwrite?" confirm popup.
                    AB.CountApplyOverwrites = function(keys, applyWrite, val, allSpecs)
                        keys = keys or {}
                        if #keys == 0 or not applyWrite then return 0 end
                        -- Simulate the write to learn the concrete per-key values.
                        local temp = {}
                        applyWrite(temp, val)
                        local touchesCas = false
                        for _, k in ipairs(keys) do
                            if AB.CAS_KEYS[k] then touchesCas = true; break end
                        end
                        local count = 0
                        local CAS_FALSE_STRIPPED = {
                            cdStateEffect = true, thresholdSeconds = true,
                            thresholdDecimals = true, thresholdColorEnabled = true,
                        }
                        local function entryLoses(e, isCas)
                            for _, k in ipairs(keys) do
                                local own = rawget(e, k)
                                local new = temp[k]
                                -- cas stamping normalizes the blocking-false away.
                                if isCas and CAS_FALSE_STRIPPED[k] and new == false then new = nil end
                                if own ~= nil and own ~= new then return true end
                            end
                            return false
                        end
                        local function sweep(prof)
                            if type(prof) ~= "table" then return end
                            local bsX = prof.barSpells and prof.barSpells[barKey]
                            if allSpecs and bsX and type(bsX.barSettings) == "table" then
                                for _, k in ipairs(keys) do
                                    local own = bsX.barSettings[k]
                                    if own ~= nil and own ~= temp[k] then
                                        count = count + 1
                                        break
                                    end
                                end
                            end
                            AB.ForEachMemberEntry(prof, bsX, function(_, e)
                                if entryLoses(e, false) then count = count + 1 end
                            end)
                            if touchesCas and bsX and type(bsX.assignedSpells) == "table"
                               and ns.GetCustomActiveState and ns.ResolveCustomActiveKey then
                                for _, sid2 in ipairs(bsX.assignedSpells) do
                                    local isInj = ((type(sid2) == "number" and sid2 < 0)
                                        or (ns._myRacialsSet and ns._myRacialsSet[sid2])
                                        or (bsX.customSpellIDs and bsX.customSpellIDs[sid2]))
                                        and not (ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid2))
                                    if isInj then
                                        -- Trinket slots resolve to the EQUIPPED item's
                                        -- own entry -- the values the stamp will clear;
                                        -- the slot entry is the bar-level stamp itself
                                        -- (analogous to the tier) and is not counted.
                                        local e = ns.GetCustomActiveState(ns.ResolveCustomActiveKey(sid2))
                                        if e and entryLoses(e, true) then count = count + 1 end
                                    end
                                end
                            end
                        end
                        local spAll = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                        if allSpecs then
                            if spAll then
                                for _, prof in pairs(spAll) do sweep(prof) end
                            end
                        else
                            local specKeyA = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                            local prof = spAll and specKeyA and spAll[specKeyA]
                            if prof then sweep(prof) end
                        end
                        return count
                    end

                    -- Write a picked value into a bar tier and clear the shadowing
                    -- per-spell overrides from the bar's member spells, so the
                    -- apply visibly takes effect everywhere. allSpecs writes the
                    -- profile-level bd tier (which specs with no CDM data yet
                    -- inherit) and sweeps every spec's spec-tier + overrides.
                    AB.RunBarApply = function(applyKeys, applyWrite, val, allSpecs)
                        if not applyWrite then return end
                        local keys = applyKeys or {}
                        local touchesCas = false
                        for _, k in ipairs(keys) do
                            if AB.CAS_KEYS[k] then touchesCas = true; break end
                        end
                        local function sweepProf(prof)
                            if type(prof) ~= "table" then return end
                            local bsX = prof.barSpells and prof.barSpells[barKey]
                            if allSpecs and bsX and type(bsX.barSettings) == "table" then
                                for _, k in ipairs(keys) do bsX.barSettings[k] = nil end
                                if next(bsX.barSettings) == nil then bsX.barSettings = nil end
                            end
                            AB.ForEachMemberEntry(prof, bsX, function(sid2, e)
                                for _, k in ipairs(keys) do rawset(e, k, nil) end
                                if next(e) == nil then
                                    local st = prof[famKey]
                                    if st then st[sid2] = nil end
                                end
                            end)
                            if touchesCas then
                                AB.StampMemberCas(bsX, applyWrite, val, keys)
                            end
                        end
                        if allSpecs then
                            if not bdSel then return end
                            local abs = bdSel.barSpellSettings
                            if not abs then abs = {}; bdSel.barSpellSettings = abs end
                            applyWrite(abs, val)
                            AB.FlipSessionGates(abs)
                            local spAll = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                            if spAll then
                                for _, prof in pairs(spAll) do sweepProf(prof) end
                            end
                        else
                            -- Mutual exclusivity: applying to THIS bar (this spec)
                            -- removes any "Apply to Bar (All Specs)" apply for these
                            -- keys, so the two scopes are never both active. (The
                            -- reverse -- an All Specs apply clearing the per-spec tier
                            -- across every spec -- is handled by sweepProf above.) The
                            -- canonical unapply also cleans up preset cas stamps; the
                            -- per-spec write below then re-stamps THIS spec's members.
                            -- No-op (and no refresh) when All Specs isn't active.
                            AB.RunBarUnapply(keys, true)
                            local bs = sd.barSettings
                            if not bs then bs = {}; sd.barSettings = bs end
                            ns.ChainSettings(bs, bdSel and bdSel.barSpellSettings)
                            applyWrite(bs, val)
                            AB.FlipSessionGates(bs)
                            local spAll = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                            local specKeyA = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                            local prof = spAll and specKeyA and spAll[specKeyA]
                            if prof then sweepProf(prof) end
                        end
                        -- The open menu's view keeps reading through the (possibly
                        -- freshly created) tier chain.
                        ns.ChainSettings(ss, ns.GetBarTierSettings(sd, barKey))
                        if touchesCas and ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        if ns.QueueReanchor then ns.QueueReanchor() end
                    end

                    -- True when a BAR tier drives this setting -- "Apply to Bar" (this
                    -- spec) or "Apply to Bar (All Specs)" holds a value for any of these
                    -- keys. A blocking false counts (it's a bar-spec "= Default" apply).
                    -- Exclusion is per-spell now (SpellHasOwn), so there is no spec-level
                    -- carve-out here: this only answers "does the bar drive this setting".
                    AB.KeysBarApplied = function(keys)
                        if not keys then return false end
                        local bs = sd.barSettings
                        local abs = bdSel and bdSel.barSpellSettings
                        for _, k in ipairs(keys) do
                            if (bs and rawget(bs, k) ~= nil) or (abs and abs[k] ~= nil) then
                                return true
                            end
                        end
                        return false
                    end

                    -- True when the SPELL holds its OWN value for any of these keys (a
                    -- per-spell override in THIS spec's store). This IS the "excluded
                    -- from the bar" state: the spell has broken out of the bar apply
                    -- into its own value. Inherently per spell AND spec, because the
                    -- store is the active spec's profile.
                    AB.SpellHasOwn = function(keys)
                        if not (keys and ss) then return false end
                        for _, k in ipairs(keys) do
                            if rawget(ss, k) ~= nil then return true end
                        end
                        return false
                    end

                    -- Include This Spell: drop this spell's own value for these keys so
                    -- it rejoins the bar apply (per spell+spec). Caller does the UI
                    -- refresh. Shared by the b3 button and by Apply to Bar/All Specs on
                    -- an already-excluded spell (which means the same thing).
                    AB.IncludeSpell = function(keys)
                        if not (keys and ss) then return end
                        for _, k in ipairs(keys) do rawset(ss, k, nil) end
                        ns.ChainSettings(ss, ns.GetBarTierSettings(sd, barKey))
                    end

                    -- Remove an active apply from one scope: clears the setting's
                    -- keys from that tier only. Per-spell values and the OTHER
                    -- scope are left alone (bar falls through to all-specs /
                    -- defaults). Preset members' cas stamps are removed only when
                    -- they still EQUAL the removed value -- per-icon cas tweaks
                    -- made after the apply survive.
                    AB.RunBarUnapply = function(applyKeys, allSpecs)
                        local keys = applyKeys or {}
                        local t
                        if allSpecs then
                            t = bdSel and bdSel.barSpellSettings
                        else
                            t = sd.barSettings
                        end
                        if not t then return end
                        local removed = {}
                        local touchesCas = false
                        for _, k in ipairs(keys) do
                            if AB.CAS_KEYS[k] then touchesCas = true end
                            removed[k] = rawget(t, k)
                            rawset(t, k, nil)
                        end
                        if next(t) == nil then
                            if allSpecs then
                                if bdSel then bdSel.barSpellSettings = nil end
                            else
                                sd.barSettings = nil
                            end
                        end
                        if touchesCas and ns.GetCustomActiveState and ns.ResolveCustomActiveKey then
                            -- Remove still-equal stamped values from one cas entry.
                            -- rawget: a trinket item entry may be CHAINED to its slot
                            -- entry, and an inherited value must not read as an own
                            -- stamp (clearing own nil is a no-op, but the equality
                            -- test has to see own values only).
                            local function unstampEntry(e)
                                if not e then return end
                                for _, k in ipairs(keys) do
                                    local rv = removed[k]
                                    -- cas never stores the blocking-false
                                    -- (cdStateEffect + Threshold Text keys).
                                    if rv == false and (k == "cdStateEffect"
                                        or k == "thresholdSeconds"
                                        or k == "thresholdDecimals"
                                        or k == "thresholdColorEnabled") then
                                        rv = nil
                                    end
                                    if rv ~= nil and rawget(e, k) == rv then e[k] = nil end
                                end
                            end
                            local function unstamp(bsX)
                                if not (bsX and type(bsX.assignedSpells) == "table") then return end
                                for _, sid2 in ipairs(bsX.assignedSpells) do
                                    local isInj = ((type(sid2) == "number" and sid2 < 0)
                                        or (ns._myRacialsSet and ns._myRacialsSet[sid2])
                                        or (bsX.customSpellIDs and bsX.customSpellIDs[sid2]))
                                        and not (ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid2))
                                    if isInj then
                                        if sid2 == -13 or sid2 == -14 then
                                            -- Trinket slots: the stamp lives on the SLOT
                                            -- entry. Also sweep the equipped trinket's
                                            -- item entry -- it may carry a legacy
                                            -- per-item stamp from before slot stamping.
                                            unstampEntry(ns.GetCustomActiveState(sid2))
                                            local itemID = GetInventoryItemID("player", -sid2)
                                            if itemID then
                                                unstampEntry(ns.GetCustomActiveState(-itemID))
                                            end
                                        else
                                            unstampEntry(ns.GetCustomActiveState(ns.ResolveCustomActiveKey(sid2)))
                                        end
                                    end
                                end
                            end
                            local spAll = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                            if allSpecs then
                                if spAll then
                                    for _, prof in pairs(spAll) do
                                        if type(prof) == "table" then
                                            unstamp(prof.barSpells and prof.barSpells[barKey])
                                        end
                                    end
                                end
                            else
                                local specKeyA = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                                local prof = spAll and specKeyA and spAll[specKeyA]
                                if prof then unstamp(prof.barSpells and prof.barSpells[barKey]) end
                            end
                            if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                        end
                        ns.ChainSettings(ss, ns.GetBarTierSettings(sd, barKey))
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        if ns.QueueReanchor then ns.QueueReanchor() end
                    end

                    -- The scope flyout itself: a vertical list (Apply to This
                    -- Spell / Apply to Bar / Apply to Bar (All Specs) / conditional
                    -- Exclude this spec) docked to the right of the hovered flyout
                    -- item. One shared frame per menu; context swapped on each hover.
                    AB.GetApplyStrip = function()
                        if menu._applyStrip then return menu._applyStrip end
                        -- Vertical flyout styled exactly like a subnav flyout: the
                        -- scope choices ("Apply to This Spell" / "Apply to Bar" /
                        -- "Apply to Bar (All Specs)", plus a conditional Exclude/
                        -- Include this spec) stack as rows with a left-aligned label
                        -- and the same white hover/selected overlay.
                        local SUBW = 180
                        local s = CreateFrame("Frame", nil, menu)
                        s:SetFrameStrata("FULLSCREEN_DIALOG")
                        s:SetFrameLevel(menu:GetFrameLevel() + 8)
                        s:SetClampedToScreen(true)
                        s:SetWidth(SUBW)
                        s:EnableMouse(true)
                        local bg = s:CreateTexture(nil, "BACKGROUND")
                        bg:SetAllPoints(); bg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                        EllesmereUI.MakeBorder(s, 1, 1, 1, mBrdA, EllesmereUI.PP)
                        local sInner = CreateFrame("Frame", nil, s)
                        sInner:SetWidth(SUBW)
                        sInner:SetPoint("TOPLEFT")
                        -- One scope row. _active drives BOTH the accent label colour
                        -- and the persistent white overlay (the "selected" look, same
                        -- as a subnav item); _rest repaints from it.
                        local function MakeScopeItem(text)
                            local b = CreateFrame("Button", nil, sInner)
                            b:SetHeight(ITEM_H)
                            b:SetFrameLevel(s:GetFrameLevel() + 2)
                            local l = b:CreateFontString(nil, "OVERLAY")
                            l:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                            l:SetPoint("LEFT", 10, 0)
                            l:SetJustifyH("LEFT")
                            l:SetText(text)
                            l:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            local hl = b:CreateTexture(nil, "ARTWORK")
                            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(0)
                            b._label = l
                            b._hl = hl
                            b._active = false
                            b._rest = function()
                                if b._active then
                                    local aR, aG, aB = EllesmereUI.GetAccentColor()
                                    l:SetTextColor(aR, aG, aB, 1)
                                    hl:SetAlpha(1)
                                else
                                    l:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                    hl:SetAlpha(0)
                                end
                            end
                            b:SetScript("OnEnter", function()
                                l:SetTextColor(1, 1, 1, 1); hl:SetAlpha(1)
                            end)
                            b:SetScript("OnLeave", function()
                                b._rest()
                            end)
                            b._setText = function(t) l:SetText(t) end
                            return b
                        end
                        local thisBtn = MakeScopeItem(EllesmereUI.L("Apply to This Spell"))
                        local b1 = MakeScopeItem(EllesmereUI.L("Apply to Bar"))
                        local b2 = MakeScopeItem(EllesmereUI.L("Apply to Bar (All Specs)"))
                        local b3 = MakeScopeItem(EllesmereUI.L("Exclude This Spell"))
                        b3._shown = false
                        -- Exclude/Include This Spell reads apart from the scope rows:
                        -- soft red when it will Exclude, soft green when it will
                        -- Include, and NO persistent white overlay when active (a
                        -- hover overlay only) -- b3._excluded (set in _updateActive)
                        -- picks the colour.
                        b3._rest = function()
                            if b3._excluded then
                                b3._label:SetTextColor(0.55, 0.82, 0.55, 1)  -- Include: soft green
                            else
                                b3._label:SetTextColor(0.90, 0.45, 0.45, 1)  -- Exclude: soft red
                            end
                            b3._hl:SetAlpha(0)
                        end
                        b3:SetScript("OnEnter", function()
                            -- Hover overlay same as the other rows (the texture's own
                            -- colour is already hlA, so SetAlpha(1) shows it); only the
                            -- ACTIVE/persistent overlay is suppressed, in _rest.
                            b3._rest(); b3._hl:SetAlpha(1)
                        end)
                        b3:SetScript("OnLeave", function()
                            b3._rest()
                        end)
                        -- (Re)stack the visible rows top-to-bottom and size the frame.
                        -- Row 1 is "Apply to This Spell" normally, but a bar apply
                        -- REPLACES it with "Exclude / Include This Spell" (b3._shown) --
                        -- the two are mutually exclusive there. Then Apply to Bar / All
                        -- Specs.
                        local function Relayout()
                            local y = 4
                            local function place(it)
                                it:ClearAllPoints()
                                it:SetPoint("TOPLEFT", sInner, "TOPLEFT", 1, -y)
                                it:SetPoint("TOPRIGHT", sInner, "TOPRIGHT", -1, -y)
                                it:Show()
                                y = y + ITEM_H
                            end
                            if b3._shown then place(b3); thisBtn:Hide() else place(thisBtn); b3:Hide() end
                            place(b1); place(b2)
                            local total = y + 4
                            sInner:SetHeight(total)
                            s:SetHeight(total)
                        end
                        -- Accent (and overlay) a scope ONLY when it holds an OWN value
                        -- for these keys that EQUALS the hovered item's value -- so the
                        -- highlight tracks the specific choice under the cursor, not
                        -- merely "this scope has some value applied".
                        s._updateActive = function()
                            local ctx = s._ctx
                            local keys = (ctx and ctx.keys) or {}
                            -- Simulate the write once: the hovered item's value as it
                            -- would land in a tier table (false-blocks and all).
                            local temp = {}
                            if ctx and ctx.write and ctx.valueOf then
                                ctx.write(temp, ctx.valueOf())
                            end
                            local function holds(tier, raw)
                                if not tier then return false end
                                local anyOwn, match = false, true
                                for _, k in ipairs(keys) do
                                    local own
                                    if raw then own = rawget(tier, k) else own = tier[k] end
                                    if own ~= nil then anyOwn = true end
                                    if own ~= temp[k] then match = false end
                                end
                                return anyOwn and match
                            end
                            -- Excluded = the spell holds its OWN value for these keys.
                            -- Exactly ONE scope is the effective source: this spell when
                            -- excluded, otherwise whichever bar tier drives it -- so the
                            -- overlay never sits on Apply to Bar while the spell is off
                            -- on its own (even though the bar still holds it for others).
                            local excluded = false
                            for _, k in ipairs(keys) do
                                if rawget(ss, k) ~= nil then excluded = true; break end
                            end
                            -- "Apply to This Spell" only shows when NO bar apply drives the
                            -- setting (a bar apply REPLACES it with Exclude/Include -- see
                            -- Relayout), so it just lights on the value the spell owns.
                            -- Toggles light whenever the spell has its own value (on OR off);
                            -- OR settings match the specific value.
                            if ctx and ctx.isToggle then
                                thisBtn._active = excluded
                            else
                                thisBtn._active = holds(ss, true)
                            end
                            b1._active = (not excluded) and holds(sd.barSettings, true)
                            b2._active = (not excluded) and holds(bdSel and bdSel.barSpellSettings, false)
                            thisBtn._rest(); b1._rest(); b2._rest()
                            -- Exclude/Include This Spell: shown whenever a bar apply drives
                            -- the setting (so this spell+spec can opt out / back in). Label
                            -- + soft red/green colour flip on the excluded state (b3._excluded
                            -- drives the colour -- see b3._rest above).
                            if AB.KeysBarApplied(keys) then
                                b3._excluded = excluded
                                b3._setText(excluded and ("+ " .. EllesmereUI.L("Include This Spell"))
                                    or ("+ " .. EllesmereUI.L("Exclude This Spell")))
                                b3._shown = true
                            else
                                b3._excluded = false
                                b3._shown = false
                            end
                            b3._rest()
                            Relayout()
                        end
                        -- Flash the border of whichever bar scope currently holds a
                        -- value for the hovered keys (the "selected apply to bar
                        -- setting"). Called when a subnav click was a no-op because
                        -- the bar already drives the setting -- the standard white
                        -- border flash used across the UI, as a "look here" cue.
                        s._flashScopeFor = function()
                            local ctx = s._ctx
                            local keys = ctx and ctx.keys
                            if not keys then return end
                            local abs = bdSel and bdSel.barSpellSettings
                            local allActive = false
                            if abs then
                                for _, k in ipairs(keys) do
                                    if abs[k] ~= nil then allActive = true; break end
                                end
                            end
                            local target = allActive and b2 or b1
                            if EllesmereUI.PlayWhiteFlash then EllesmereUI.PlayWhiteFlash(target) end
                        end
                        local function DoApply(allSpecs)
                            local ctx = s._ctx
                            if not ctx then return end
                            local val = ctx.valueOf and ctx.valueOf()
                            local keys = ctx.keys or {}
                            -- Simulate the write once: drives the rejoin match test,
                            -- the toggle-off check, and the replace warning below.
                            local temp = {}
                            if ctx.write then ctx.write(temp, val) end
                            local scopeT
                            if allSpecs then
                                scopeT = bdSel and bdSel.barSpellSettings
                            else
                                scopeT = sd.barSettings
                            end
                            local scopeActive, valuesMatch = false, true
                            for _, k in ipairs(keys) do
                                local own
                                if scopeT then
                                    if allSpecs then own = scopeT[k]
                                    else own = rawget(scopeT, k) end
                                end
                                if own ~= nil then scopeActive = true end
                                if own ~= temp[k] then valuesMatch = false end
                            end
                            -- On an EXCLUDED spell the flyout sits on the bar's own value,
                            -- so Apply to Bar / All Specs here means "rejoin the bar" -- the
                            -- same as Include This Spell. Do that instead of re-applying the
                            -- value already on the bar (which would just toggle it off).
                            -- Some items carry a payload the flyout val doesn't capture:
                            -- a scalar popup value (Threshold Seconds), a custom colour
                            -- ("custom" is a fixed identifier, the RGB lives in ss), and
                            -- the + Border Color toggle (an on/off flag plus its RGBA).
                            -- For those "sits on the bar's value" only holds when the
                            -- payload actually matches this scope -- rejoin then (keeps
                            -- the bar apply for other spells); otherwise fall through and
                            -- push it, which rejoining would silently discard.
                            if AB.KeysBarApplied(keys) and AB.SpellHasOwn(keys)
                               and (not (ctx.scalarApply or ctx.payloadValue)
                                    or (scopeActive and valuesMatch)) then
                                AB.IncludeSpell(keys)
                                if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                if ns.QueueReanchor then ns.QueueReanchor() end
                                if ctx.refresh then ctx.refresh() end
                                if s._updateActive then s._updateActive() end
                                return
                            end
                            -- Toggle OFF: clicking a scope that already holds this
                            -- exact value un-applies it. Binary toggles carry no value
                            -- of their own, so any active scope is an un-apply gesture.
                            -- The + Border Color toggle carries an RGBA payload, so
                            -- equality IS meaningful: un-apply only when the colour
                            -- matches, otherwise fall through and push the new one --
                            -- un-applying there would discard it and snap back to the
                            -- default. (Custom-colour value items aren't toggles, so
                            -- isToggle already gates them here; only the rejoin branch
                            -- above needed the payloadValue guard for them.)
                            if scopeActive and (valuesMatch or (ctx.isToggle and not ctx.payloadValue)) then
                                AB.RunBarUnapply(keys, allSpecs)
                                if ctx.refresh then ctx.refresh() end
                                if s._updateActive then s._updateActive() end
                                return
                            end
                            local function go()
                                AB.RunBarApply(keys, ctx.write, val, allSpecs)
                                if ctx.refresh then ctx.refresh() end
                                if s._updateActive then s._updateActive() end
                            end
                            -- Confirm before anything destructive or costly: a
                            -- first-time Resource Aware glow (perf note), replacing
                            -- this scope's active apply with a different value
                            -- (mutually exclusive selections un-check each other),
                            -- and/or replacing existing per-icon values. One
                            -- composed popup, never two in a row.
                            local needRA = ctx.confirmRA and not AB.AnyResourceAwareGlowSaved()
                            local replacing = scopeActive  -- (values differ, else un-applied above)
                            local overwrites = AB.CountApplyOverwrites(keys, ctx.write, val, allSpecs)
                            if not needRA and not replacing and overwrites == 0 then
                                go()
                                return
                            end
                            local title, message
                            if needRA then
                                title = "CD Ready Glow (Resource Aware)"
                                message = "Resource Aware CD Ready Glow may cause a slight loss in performance efficiency."
                            else
                                title = "Overwrite Existing Settings"
                                message = ""
                            end
                            if replacing then
                                local scopeName = allSpecs and "Apply to Bar (All Specs)" or "Apply to Bar"
                                local line = "This setting's active " .. scopeName .. " value will be replaced."
                                if message ~= "" then
                                    message = message .. "\n\n" .. line
                                else
                                    message = line
                                end
                            end
                            if overwrites > 0 then
                                local scope = allSpecs and "across your specs" or "on this bar"
                                local line = "This replaces " .. overwrites
                                    .. " existing value(s) for this setting " .. scope .. "."
                                if message ~= "" then
                                    message = message .. "\n\n" .. line
                                else
                                    message = line
                                end
                            end
                            message = message .. " Do you want to continue?"
                            menu:Hide()
                            EllesmereUI:ShowConfirmPopup({
                                title       = title,
                                message     = message,
                                confirmText = "Apply",
                                cancelText  = "Cancel",
                                onConfirm   = go,
                            })
                        end
                        -- Apply to This Spell: write the hovered value into the spell's
                        -- OWN entry in THIS spec's store (a per-spell override = excluding
                        -- this spell+spec from the bar). No dissolve, no popup -- only this
                        -- one spell changes; the bar apply stays for every other spell.
                        thisBtn:SetScript("OnClick", function()
                            local ctx = s._ctx
                            if not (ctx and ctx.write) then return end
                            EnsureSS()
                            ctx.write(ss, ctx.valueOf and ctx.valueOf())
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                            if ctx.refresh then ctx.refresh() end
                            if s:IsShown() and s._updateActive then s._updateActive() end
                        end)
                        b1:SetScript("OnClick", function() DoApply(false) end)
                        b2:SetScript("OnClick", function() DoApply(true) end)
                        -- Exclude / Include This Spell (per spell+spec, via ss).
                        b3:SetScript("OnClick", function()
                            local ctx = s._ctx
                            if not (ctx and ctx.write) then return end
                            local keys = ctx.keys or {}
                            if AB.SpellHasOwn(keys) then
                                -- Include: drop this spell's own value -> rejoin the bar.
                                AB.IncludeSpell(keys)
                            else
                                -- Exclude: break this spell out with its own value. OR
                                -- settings copy the current value (look unchanged); the
                                -- "+" toggles exclude by turning OFF for this spell.
                                EnsureSS()
                                local v
                                if ctx.isToggle then v = false else v = ctx.valueOf and ctx.valueOf() end
                                ctx.write(ss, v)
                            end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                            if ctx.refresh then ctx.refresh() end
                            if s._updateActive then s._updateActive() end
                        end)
                        Relayout()
                        s:Hide()
                        menu._applyStrip = s
                        return s
                    end
                    -- Attach the strip to a hovered flyout item. ctx carries the
                    -- row/item apply info + a flyout-refresh closure.
                    AB.ShowApplyStripFor = function(itemBtn, ctx)
                        local s = AB.GetApplyStrip()
                        s._ctx = ctx
                        s._ownerItem = itemBtn
                        if s._updateActive then s._updateActive() end
                        s:ClearAllPoints()
                        -- Same 2px offset as the subnav flyouts, top-aligned to the
                        -- hovered item. Like a subnav, the strip does NOT hide on
                        -- hover-out (crossing the gap would kill it otherwise) -- it
                        -- hides when its owner item goes away (flyout closed/rebuilt),
                        -- when another item retargets it, or when the menu closes.
                        s:SetPoint("TOPLEFT", itemBtn, "TOPRIGHT", 2, 0)
                        s:Show()
                    end

                    -- Divider
                    local div1 = inner:CreateTexture(nil, "ARTWORK")
                    div1:SetHeight(1)
                    div1:SetColorTexture(1, 1, 1, 0.10)
                    div1:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                    div1:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                    mH = mH + 9

                    local GLOW_ITEMS = {
                        { val = nil,  label = "Default" },
                        { val = 0,    label = "None" },
                        { val = 1,    label = "Pixel Glow" },
                        { val = 2,    label = "Shape Glow" },
                        { val = 3,    label = "Button Glow" },
                        { val = 4,    label = "Auto-Cast Shine" },
                        { val = 5,    label = "GCD" },
                        { val = 6,    label = "Modern WoW Glow" },
                        { val = 7,    label = "Classic WoW Glow" },
                    }
                    local ACTIVE_GLOW_ITEMS = {
                        { val = nil,  label = "None" },
                        { val = 1,    label = "Pixel Glow" },
                        { val = 2,    label = "Shape Glow" },
                        { val = 3,    label = "Button Glow" },
                        { val = 4,    label = "Auto-Cast Shine" },
                        { val = 5,    label = "GCD" },
                        { val = 6,    label = "Modern WoW Glow" },
                        { val = 7,    label = "Classic WoW Glow" },
                    }
                    local ACTIVE_SWIPE_ITEMS = {
                        { val = "custom",  label = "CD Swipe Color" },
                        { val = "class",   label = "CD Swipe Class Colored" },
                        { val = "none",    label = "Hide Active State" },
                        -- Independent toggle+swatch (NOT part of the swipe single-select
                        -- above): recolors the icon's border during active state. Its
                        -- bar-apply writes only the border keys (never the swipe ones).
                        { activeBorder = true, label = "+ Border Color",
                          applyKeys  = { "activeBorderEnabled", "activeBorderR", "activeBorderG", "activeBorderB", "activeBorderA" },
                          applyWrite = function(t, v)
                              t.activeBorderEnabled = v and true or false
                              if v then
                                  t.activeBorderR = ss.activeBorderR or 1
                                  t.activeBorderG = ss.activeBorderG or 0.776
                                  t.activeBorderB = ss.activeBorderB or 0.376
                                  t.activeBorderA = ss.activeBorderA or 1
                              end
                          end },
                    }
                    local CD_STATE_ITEMS = {
                        { val = nil,               label = "None" },
                        -- Charge-spell toggle (independent boolean, NOT part of the
                        -- single-select cdStateEffect below). Handled as a toggle in the
                        -- item loop (item.charge names the ss key). Bar-apply writes an
                        -- explicit true/false (false blocks the all-specs tier).
                        { charge = "chargeHideSwipe", label = "+ Hide Swipe (Charges)",
                          applyKeys  = { "chargeHideSwipe" },
                          applyWrite = function(t, v) t.chargeHideSwipe = v and true or false end },
                        { charge = "hideRechargeEdge", label = "+ Hide Recharge Edge",
                          applyKeys  = { "hideRechargeEdge" },
                          applyWrite = function(t, v) t.hideRechargeEdge = v and true or false end },
                        { charge = "chargeHideCdText", label = "+ Hide Duration (Charges > 0)",
                          applyKeys  = { "chargeHideCdText" },
                          applyWrite = function(t, v) t.chargeHideCdText = v and true or false end },
                        -- Same logic as Hidden (On CD) but with a customizable opacity
                        -- instead of a hard 0. Click prompts for the percent; the label
                        -- shows it (e.g. "50% Lower Alpha (On CD)") while it is selected.
                        -- Its bar apply skips the popup and pushes the current percent.
                        { val = "lowerAlphaOnCD",  label = "Lower Alpha (On CD)",
                          dynamicLabel = function()
                              local base = EllesmereUI.L("Lower Alpha (On CD)")
                              if ss and ss.cdStateEffect == "lowerAlphaOnCD" then
                                  local pct = math.floor(((ss.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                                  return pct .. "% " .. base
                              end
                              return base
                          end },
                        -- Shift variants: same hide as the plain modes below, but the
                        -- bar re-lays out so the remaining icons close the gap.
                        { val = "hiddenOnCDShift",  label = "Hidden on CD (Shift Icons)" },
                        { val = "hiddenReadyShift", label = "Hidden CD Ready (Shift Icons)" },
                        { val = "hiddenOnCD",      label = "Hidden (On CD)" },
                        { val = "hiddenReady",     label = "Hidden (CD Ready)" },
                        { val = "pixelGlowReady",  label = "Pixel Glow (CD Ready)" },
                        { val = "buttonGlowReady", label = "Button Glow (CD Ready)" },
                        -- Resource Aware variants: also require the spell to be
                        -- castable (resources/form) via the event-driven usability
                        -- watcher. That watcher has a small cost, so these are
                        -- separate opt-in values (with a confirm popup) and the
                        -- plain variants above stay cost-free.
                        { val = "pixelGlowReadyUsable",  label = "Pixel Glow CD Ready (Resource Aware)",
                          tooltip = "Pixel Glow CD Ready (Resource Aware)" },
                        { val = "buttonGlowReadyUsable", label = "Button Glow CD Ready (Resource Aware)",
                          tooltip = "Button Glow CD Ready (Resource Aware)" },
                    }
                    -- Reverse Swipe single-select (per-spell / per-preset). Shared by
                    -- both the regular-spell (ss) and preset/custom (cas) menus below.
                    local REVERSE_SWIPE_ITEMS = {
                        { val = nil,  label = "Off" },
                        { val = true, label = "Reverse Swipe" },
                    }
                    -- Cooldown Swipe (cd/utility spells + presets): a 3-way single-select
                    -- over two independent keys -- reverseSwipe and hideCDSwipe. "Off"
                    -- clears both; the getVal/setVal below map the selection to the keys.
                    local CD_SWIPE_ITEMS = {
                        { val = nil,       label = "Off" },
                        { val = "reverse", label = "Reverse Swipe" },
                        { val = "hide",    label = "Hide CD Swipe" },
                    }

                    -- Track open subnavs on the menu frame so OnUpdate can see them

                    -- Hosted buffs are fully removed from the Apply-to-Bar system: this
                    -- flag (set per-icon below, once isHostedBuff is known) suppresses the
                    -- "Apply to Bar" hover strip on every row for a hosted buff.
                    local hostedBuffNoApply = false

                    -- Helper: subnav flyout (same style as Potions & Healthstone)
                    -- isDefault: function returning true when the setting is at default value
                    -- onItemCreated: optional callback(si, item, sub) for custom widgets per subnav item
                    local function MakeSubnavRow(label, items, getVal, setVal, isDefault, onItemCreated, opts)
                        local row = CreateFrame("Button", nil, inner)
                        row:SetHeight(ITEM_H)
                        row:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                        row:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                        row:SetFrameLevel(menu:GetFrameLevel() + 2)

                        local acR, acG, acB = EllesmereUI.GetAccentColor()

                        local lbl = row:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        lbl:SetPoint("LEFT", 10, 0)
                        lbl:SetJustifyH("LEFT")
                        lbl:SetText(EllesmereUI.L(label))

                        -- Optional disabled state (opts.disabled = function -> bool):
                        -- greys the row, blocks the flyout, and shows a tooltip.
                        local function RowDisabled()
                            return opts and opts.disabled and opts.disabled() or false
                        end

                        local function UpdateLabelColor()
                            if RowDisabled() then
                                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                            elseif not isDefault() then
                                lbl:SetTextColor(acR, acG, acB, 1)
                            else
                                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            end
                        end
                        UpdateLabelColor()

                        local arrow = row:CreateTexture(nil, "ARTWORK")
                        arrow:SetSize(10, 10)
                        arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                        arrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
                        arrow:SetAlpha(RowDisabled() and 0.2 or 0.7)

                        local hl = row:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)

                        local sub
                        local function ShowSub()
                            if menu._openSub and menu._openSub ~= sub and menu._openSub.Hide then menu._openSub:Hide() end
                            if sub and sub:IsShown() then return end
                            if not sub then
                                sub = CreateFrame("Frame", nil, menu)
                                sub:SetFrameStrata("FULLSCREEN_DIALOG")
                                sub:SetFrameLevel(menu:GetFrameLevel() + 5)
                                sub:SetClampedToScreen(true)
                                sub:EnableMouse(true)
                            else
                                for _, ch in ipairs({sub:GetChildren()}) do ch:Hide(); ch:SetParent(nil) end
                                for _, rg in ipairs({sub:GetRegions()}) do if rg.Hide then rg:Hide() end end
                            end

                            local subW = 180
                            sub:SetSize(subW, 10)
                            sub:ClearAllPoints()
                            sub:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)

                            local subBg = sub:CreateTexture(nil, "BACKGROUND")
                            subBg:SetAllPoints()
                            subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                            EllesmereUI.MakeBorder(sub, 1, 1, 1, mBrdA, EllesmereUI.PP)

                            local subInner = CreateFrame("Frame", nil, sub)
                            subInner:SetWidth(subW)
                            subInner:SetPoint("TOPLEFT")

                            local subH = 4
                            local curVal = getVal()
                            -- "None"/default is stored as a blocking false; treat it as
                            -- nil so its item reads as selected (false ~= nil otherwise).
                            if curVal == false then curVal = nil end
                            local flyoutEntries = {}
                            -- Re-highlight the selection in place after a value click.
                            -- The flyout stays OPEN (no rebuild -- that would reset
                            -- scroll/search state and kill the apply strip's owner).
                            local function RefreshFlyoutSelection()
                                for _, e in ipairs(flyoutEntries) do
                                    -- computeSelected re-derives the live selected
                                    -- state per item -- single-select value match OR
                                    -- independent toggle key -- so a bar "Apply"
                                    -- re-highlights the applied item exactly like a
                                    -- direct click. The old value-only path skipped
                                    -- toggles (e.g. Hide Recharge Edge), leaving them
                                    -- un-highlighted after an apply.
                                    if e.setSelected and e.computeSelected then
                                        e.setSelected(e.computeSelected())
                                    end
                                    if e.refreshLabel then e.refreshLabel() end
                                    -- Applying / un-applying to the bar changes which value
                                    -- is the unclickable arrow row -- refresh it in place.
                                    if e.updateArrow then e.updateArrow() end
                                end
                            end
                            -- Reachable from onItemCreated closures (color swatches),
                            -- which live outside this scope but capture `sub`.
                            sub._refreshSelection = RefreshFlyoutSelection
                            -- True when apply keys contain an R/G/B triple, i.e. the item
                            -- carries a per-spell colour the flyout val doesn't capture.
                            -- Structural on purpose: keying off val == "custom" missed
                            -- payload toggles that use a different discriminator (Threshold
                            -- Color, + Border Color), silently reintroducing the reset bug.
                            local function hasColourPayload(ks)
                                if not ks then return false end
                                local set = {}
                                for _, k in ipairs(ks) do set[k] = true end
                                for _, k in ipairs(ks) do
                                    local base = k:match("^(.+)R$")
                                    if base and set[base .. "G"] and set[base .. "B"] then
                                        return true
                                    end
                                end
                                return false
                            end
                            for _, item in ipairs(items) do
                                if item.divider then
                                    -- Thin separator line (e.g. between built-in sounds
                                    -- and appended LibSharedMedia sounds). Never selectable.
                                    local div = subInner:CreateTexture(nil, "ARTWORK")
                                    div:SetHeight(1)
                                    div:SetColorTexture(1, 1, 1, 0.10)
                                    div:SetPoint("TOPLEFT", subInner, "TOPLEFT", 6, -subH - 4)
                                    div:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -6, -subH - 4)
                                    flyoutEntries[#flyoutEntries + 1] = { frame = div, isDivider = true }
                                    subH = subH + 9
                                else
                                local si = CreateFrame("Button", nil, subInner)
                                si:SetHeight(ITEM_H)
                                si:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -subH)
                                si:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -subH)
                                si:SetFrameLevel(sub:GetFrameLevel() + 2)

                                local sLbl = si:CreateFontString(nil, "OVERLAY")
                                sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                                sLbl:SetPoint("LEFT", 10, 0)
                                sLbl:SetJustifyH("LEFT")
                                -- item.dynamicLabel (optional) returns a fully-composed,
                                -- already-localized caption computed at render time (e.g.
                                -- "50% Lower Alpha (On CD)"); plain items localize item.label.
                                if item.dynamicLabel then
                                    sLbl:SetText(item.dynamicLabel())
                                else
                                    sLbl:SetText(EllesmereUI.L(item.label))
                                end

                                -- Highlight selected item. Charge entries are
                                -- independent toggles (item.charge names the ss
                                -- boolean key); item.toggleGet/toggleSet entries
                                -- are independent toggles over ANY store (the row
                                -- supplies the accessors, so the same items work
                                -- in the ss, buff and customActiveStates branches);
                                -- all other items are single-select on item.val.
                                local isChargeToggle = item.charge ~= nil
                                local isActiveBorder = item.activeBorder == true
                                local isFnToggle = item.toggleGet ~= nil
                                local isSelected
                                if isChargeToggle then
                                    isSelected = (ss[item.charge] == true)
                                elseif isActiveBorder then
                                    isSelected = (ss.activeBorderEnabled == true)
                                elseif isFnToggle then
                                    isSelected = item.toggleGet() and true or false
                                else
                                    isSelected = (curVal == item.val)
                                        or (curVal == nil and item.val == nil)
                                end
                                if isSelected then
                                    local acR, acG, acB = EllesmereUI.GetAccentColor()
                                    sLbl:SetTextColor(acR, acG, acB, 1)
                                else
                                    sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                end

                                local sHl = si:CreateTexture(nil, "ARTWORK")
                                -- Colour fixed to the hover white; alpha toggles it. The
                                -- SELECTED single-select item keeps this overlay on (a
                                -- persistent "hovered" look) so the active choice reads
                                -- clearly; the toggles ("+ " ones + Border Color) never do.
                                sHl:SetAllPoints(); sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(0)
                                if not (isChargeToggle or isActiveBorder or isFnToggle) and isSelected then
                                    sHl:SetAlpha(1)
                                end

                                -- "Apply to Bar" hover strip context. EVERY value item
                                -- and independent toggle exposes bar-scope apply (the
                                -- only settings without a strip are the action rows,
                                -- e.g. Add Active State, which have no flyout items).
                                local rowApply = opts and opts.apply
                                local applyKeys  = item.applyKeys or (rowApply and rowApply.keys)
                                local applyWrite = item.applyWrite or (rowApply and rowApply.write)
                                -- Hosted buffs are excluded from Apply-to-Bar entirely.
                                local canApply = applyWrite ~= nil and not hostedBuffNoApply
                                -- When a bar apply drives this setting, the value the BAR
                                -- applies acts like a submenu row: it shows a right-arrow and
                                -- is unclickable -- you manage it through the scope flyout that
                                -- opens on hover (Exclude / Include / Apply to Bar), never by
                                -- re-selecting the value. A bar-applied "+ " toggle counts too.
                                local function itemIsBarApplied()
                                    if not (applyKeys and AB.KeysBarApplied(applyKeys)) then return false end
                                    if isChargeToggle or isActiveBorder or isFnToggle then return true end
                                    local barTier = ns.GetBarTierSettings and ns.GetBarTierSettings(sd, barKey)
                                    local pk = applyKeys[1]
                                    if not (barTier and pk) then return false end
                                    local temp = {}
                                    applyWrite(temp, item.val)
                                    return barTier[pk] == temp[pk]
                                end
                                local sArrow = si:CreateTexture(nil, "ARTWORK")
                                sArrow:SetSize(10, 10)
                                sArrow:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                sArrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
                                sArrow:SetAlpha(0.7)
                                sArrow:Hide()
                                local function updateArrow()
                                    if canApply and itemIsBarApplied() then sArrow:Show() else sArrow:Hide() end
                                end
                                updateArrow()
                                si:SetScript("OnEnter", function()
                                    if not isSelected then sLbl:SetTextColor(1, 1, 1, 1) end
                                    sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                                    -- Optional hover tooltip (item.tooltip): shows the
                                    -- full text for labels wider than the flyout.
                                    if item.tooltip then
                                        EllesmereUI.ShowWidgetTooltip(si, item.tooltip)
                                    end
                                    -- Whenever a bar apply drives this setting, only the value the
                                    -- BAR applies keeps the Apply-to flyout (it's the arrow row);
                                    -- the OR-siblings hide theirs and stay normal clickable values.
                                    -- Holds on both a following spell and an excluded one (the flyout
                                    -- tracks the bar's value, never the spell's override). Settings
                                    -- with no bar apply show it on everything. "+ " toggles are never
                                    -- OR, so they keep it.
                                    -- A scalar popup value (Threshold Seconds) has only one
                                    -- item, so "the bar's value differs from this item" is
                                    -- meaningless -- never suppress it, or Apply-to-Bar
                                    -- vanishes the moment the entered number differs from the
                                    -- bar's.
                                    local suppressStrip = canApply and not item.scalarApply
                                        and not (isChargeToggle or isActiveBorder or isFnToggle)
                                        and AB.KeysBarApplied(applyKeys) and not itemIsBarApplied()
                                    if suppressStrip then
                                        if menu._applyStrip then menu._applyStrip:Hide() end
                                    elseif canApply then
                                        AB.ShowApplyStripFor(si, {
                                            keys  = applyKeys,
                                            write = applyWrite,
                                            scalarApply = item.scalarApply,
                                            isToggle = isChargeToggle or isActiveBorder or isFnToggle,
                                            -- Item whose val is only a discriminator while
                                            -- the real value carries a per-spell colour
                                            -- payload (an R/G/B triple in applyKeys). For
                                            -- those, equality must be judged by valuesMatch,
                                            -- not the identifier, or the rejoin/toggle-off
                                            -- shortcuts discard the colour (see the two
                                            -- branches in the apply handler above).
                                            payloadValue = hasColourPayload(applyKeys),
                                            -- Toggles: "Apply to Bar" ENABLES the feature
                                            -- on the bar (apply true). Disabling is the
                                            -- toggle-off press -- ctx.isToggle un-applies
                                            -- when the scope already holds the value. The
                                            -- old `not isSelected` flipped an ALREADY-ON
                                            -- toggle OFF when switching scopes (e.g. All
                                            -- Specs -> Apply to Bar deselected the setting
                                            -- and killed the effect). Value items apply
                                            -- the value they represent.
                                            valueOf = function()
                                                if isChargeToggle or isActiveBorder or isFnToggle then
                                                    return true
                                                end
                                                return item.val
                                            end,
                                            confirmRA = rowApply and rowApply.confirmRA
                                                and (item.val == "pixelGlowReadyUsable"
                                                  or item.val == "buttonGlowReadyUsable"),
                                            -- No flyout rebuild here: rebuilding would
                                            -- destroy the strip's owner item and hide
                                            -- the strip mid-interaction (e.g. between
                                            -- "Apply to Bar" and "(All Specs)"). The
                                            -- flyout re-renders fresh on its next open;
                                            -- only the row's accent cue updates now.
                                            refresh = function()
                                                -- Re-highlight the applied flyout item
                                                -- in place, exactly as a direct click
                                                -- would (single-select mutual exclusion
                                                -- AND toggles), then update the collapsed
                                                -- row label. No flyout rebuild -- that
                                                -- would kill the strip's owner item.
                                                RefreshFlyoutSelection()
                                                UpdateLabelColor()
                                            end,
                                        })
                                    end
                                end)
                                si:SetScript("OnLeave", function()
                                    if not isSelected then sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA) end
                                    -- Keep the overlay on for a selected single-select
                                    -- (persistent highlight); clear it for everything else.
                                    sHl:SetAlpha((not (isChargeToggle or isActiveBorder or isFnToggle) and isSelected) and 1 or 0)
                                    if item.tooltip then EllesmereUI.HideWidgetTooltip() end
                                end)
                                si:SetScript("OnClick", function()
                                    -- The value the bar applies is unclickable -- it's the
                                    -- submenu/arrow row. Manage it through the scope flyout
                                    -- (Exclude / Include / Apply to Bar), not by re-selecting.
                                    if itemIsBarApplied() then return end
                                    -- The write this click performs, always into the
                                    -- spell's OWN entry (charge toggle / active border /
                                    -- single-select value). Wrapped so the bar-override
                                    -- confirm below can defer it to the popup callback.
                                    local function doWrite()
                                        -- Generic independent toggle (item.toggleGet /
                                        -- item.toggleSet): flips its own boolean through
                                        -- the row's store accessors (the setter owns the
                                        -- persist + gate flip + refresh calls) and keeps
                                        -- the flyout open, exactly like the charge toggles.
                                        if isFnToggle and item.toggleSet then
                                            item.toggleSet(not item.toggleGet())
                                            isSelected = item.toggleGet() and true or false
                                            if isSelected then
                                                local acR, acG, acB = EllesmereUI.GetAccentColor()
                                                sLbl:SetTextColor(acR, acG, acB, 1)
                                            else
                                                sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                            end
                                            UpdateLabelColor()
                                            local strip = menu._applyStrip
                                            if strip and strip:IsShown() and strip._updateActive then strip._updateActive() end
                                            return
                                        end
                                        -- Charge toggles flip an independent boolean and
                                        -- keep the flyout open (so both can be set in one
                                        -- pass). They never touch the single-select
                                        -- cdStateEffect.
                                        if isChargeToggle then
                                            EnsureSS()
                                            if ss[item.charge] == true then
                                                SetOwn(item.charge, nil)
                                            else
                                                ss[item.charge] = true
                                            end
                                            isSelected = (ss[item.charge] == true)
                                            if isSelected then
                                                local acR, acG, acB = EllesmereUI.GetAccentColor()
                                                sLbl:SetTextColor(acR, acG, acB, 1)
                                                if item.charge == "chargeHideCdText" then
                                                    ns._cdmAnyChargeHideCdText = true
                                                else
                                                    ns._cdmAnyChargeStyle = true
                                                end
                                            else
                                                sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                            end
                                            -- Live-update the collapsed row's accent, like the
                                            -- single-select path does -- the toggles skipped it,
                                            -- so the parent nav only recoloured on reopen.
                                            UpdateLabelColor()
                                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                            if ns.QueueReanchor then ns.QueueReanchor() end
                                            local strip = menu._applyStrip
                                            if strip and strip:IsShown() and strip._updateActive then strip._updateActive() end
                                            return
                                        end
                                        -- Border Color: independent toggle (keeps flyout
                                        -- open). The inline swatch picks the color; the row
                                        -- toggles it on/off. Recolors the icon border during
                                        -- active state only.
                                        if isActiveBorder then
                                            EnsureSS()
                                            if ss.activeBorderEnabled == true then
                                                SetOwn("activeBorderEnabled", nil)
                                            else
                                                ss.activeBorderEnabled = true
                                            end
                                            isSelected = (ss.activeBorderEnabled == true)
                                            if isSelected then
                                                if not ss.activeBorderR then
                                                    ss.activeBorderR = 1; ss.activeBorderG = 0.776
                                                    ss.activeBorderB = 0.376; ss.activeBorderA = 1
                                                end
                                                local acR, acG, acB = EllesmereUI.GetAccentColor()
                                                sLbl:SetTextColor(acR, acG, acB, 1)
                                            else
                                                sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                            end
                                            UpdateLabelColor()
                                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                            if ns.QueueReanchor then ns.QueueReanchor() end
                                            local strip = menu._applyStrip
                                            if strip and strip:IsShown() and strip._updateActive then strip._updateActive() end
                                            return
                                        end
                                        setVal(item.val)
                                        -- Keep the flyout open (same as the toggle items):
                                        -- selecting a value should close neither the menu
                                        -- nor the subnav. Re-highlight in place.
                                        RefreshFlyoutSelection()
                                        UpdateLabelColor()
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                        if ns.QueueReanchor then ns.QueueReanchor() end
                                        local strip = menu._applyStrip
                                        if strip and strip:IsShown() and strip._updateActive then strip._updateActive() end
                                    end
                                    -- When the BAR drives this setting and the spell hasn't
                                    -- already broken out with its own value:
                                    --  * clicking the value the bar already applies changes
                                    --    nothing -> flash the scope holding it (no-op cue).
                                    --  * clicking a different value (or a "+" toggle) breaks
                                    --    THIS spell+spec out into its own value -- no popup,
                                    --    only this spell changes; the bar apply stays for
                                    --    every other spell. (doWrite flips a toggle OFF, which
                                    --    is the break-out for a bar-applied-ON toggle.)
                                    -- Once the spell owns a value it reports editable and
                                    -- writes straight through (the excluded state).
                                    if AB.KeysBarApplied(applyKeys) and not AB.SpellHasOwn(applyKeys) then
                                        if not (isChargeToggle or isActiveBorder or isFnToggle) then
                                            local cv = getVal()
                                            if (cv == item.val) or (cv == nil and item.val == nil) then
                                                local strip = menu._applyStrip
                                                if strip and strip._flashScopeFor then strip._flashScopeFor() end
                                                return
                                            end
                                        end
                                        doWrite()
                                        return
                                    end
                                    doWrite()
                                end)

                                if onItemCreated then onItemCreated(si, item, sub) end
                                flyoutEntries[#flyoutEntries + 1] = {
                                    frame = si, label = sLbl, name = item.label,
                                    itemVal = item.val,
                                    isToggle = isChargeToggle or isActiveBorder or isFnToggle,
                                    -- Live selected-state predicate, mirroring the
                                    -- render-time isSelected assignment above. Reads
                                    -- effective (chained) values, so it reflects a
                                    -- bar-tier apply, not just the spell's own entry.
                                    computeSelected = function()
                                        if isChargeToggle then return ss[item.charge] == true end
                                        if isActiveBorder then return ss.activeBorderEnabled == true end
                                        if isFnToggle then return item.toggleGet() and true or false end
                                        local cv = getVal()
                                        if cv == false then cv = nil end  -- None/default blocks with false
                                        return (cv == item.val) or (cv == nil and item.val == nil)
                                    end,
                                    -- In-place selection update for the keep-open
                                    -- click path (also keeps the item's OnLeave and
                                    -- the strip's toggle state in sync).
                                    setSelected = function(sel)
                                        isSelected = sel
                                        if sel then
                                            local acR2, acG2, acB2 = EllesmereUI.GetAccentColor()
                                            sLbl:SetTextColor(acR2, acG2, acB2, 1)
                                        else
                                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                        end
                                        -- Selected single-select keeps the white overlay
                                        -- (toggles never get the persistent look).
                                        if not (isChargeToggle or isActiveBorder) then
                                            sHl:SetAlpha(sel and 1 or 0)
                                        end
                                    end,
                                    refreshLabel = function()
                                        if item.dynamicLabel then sLbl:SetText(item.dynamicLabel()) end
                                    end,
                                    -- Live-update the arrow/unclickable state after an apply
                                    -- or un-apply (the flyout doesn't rebuild in place).
                                    updateArrow = updateArrow,
                                }
                                subH = subH + ITEM_H
                                end -- item.divider / else
                            end

                            -- Cap height + scroll for long lists (e.g. the Audio Effect
                            -- sound list), matching the Focus Cast Sound dropdown and the
                            -- Custom Tracking subnav. Mouse-wheel + smooth scroll; short
                            -- subnavs fall through to the unchanged fixed-height path.
                            local totalSubH = subH + 4
                            subInner:SetHeight(totalSubH)
                            -- 200 == the dropdown's DD_MAX_HEIGHT (Focus Cast Sound).
                            local FLYOUT_MAX_H = 200
                            if opts and opts.searchable then
                                -- Searchable flyout: a filter box pinned to the top with
                                -- the list scrolling below it. Items are uniform height
                                -- (ITEM_H), so filtering just repositions the survivors
                                -- and hides separators while a query is active. Scroll
                                -- range is recomputed live from the scroll child height.
                                local SEARCH_H = 24
                                local searchPad = SEARCH_H + 8
                                sub:SetSize(subW, FLYOUT_MAX_H + searchPad)

                                local searchEdit = CreateFrame("EditBox", nil, sub)
                                searchEdit:SetSize(subW - 12, SEARCH_H)
                                searchEdit:SetPoint("TOP", sub, "TOP", 0, -4)
                                searchEdit:SetFrameLevel(sub:GetFrameLevel() + 6)
                                searchEdit:SetFont(FONT_PATH, 11, "")
                                searchEdit:SetTextColor(1, 1, 1, 0.9)
                                searchEdit:SetJustifyH("LEFT")
                                searchEdit:SetAutoFocus(false)
                                searchEdit:SetMaxLetters(30)
                                searchEdit:SetTextInsets(4, 4, 0, 0)
                                local seBg = searchEdit:CreateTexture(nil, "BACKGROUND")
                                seBg:SetAllPoints()
                                seBg:SetColorTexture(0, 0, 0, 0.4)
                                local sePh = searchEdit:CreateFontString(nil, "OVERLAY")
                                sePh:SetFont(FONT_PATH, 11, "")
                                sePh:SetTextColor(0.5, 0.5, 0.5, 0.6)
                                sePh:SetPoint("LEFT", searchEdit, "LEFT", 4, 0)
                                sePh:SetText(EllesmereUI.L("Search..."))
                                searchEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                                searchEdit:SetScript("OnHide", function(self) self:ClearFocus() end)

                                subInner:ClearAllPoints()
                                local sf = CreateFrame("ScrollFrame", nil, sub)
                                sf:SetPoint("TOPLEFT", 0, -searchPad)
                                sf:SetPoint("BOTTOMRIGHT")
                                sf:SetFrameLevel(sub:GetFrameLevel() + 1)
                                sf:EnableMouseWheel(true)
                                sf:SetScrollChild(subInner)
                                subInner:SetWidth(subW)

                                local scrollTarget = 0
                                local SCROLL_STEP = 40
                                local SMOOTH_SPEED = 12
                                local smoothFrame = CreateFrame("Frame")
                                smoothFrame:Hide()
                                smoothFrame:SetScript("OnUpdate", function(_, elapsed)
                                    local cur = sf:GetVerticalScroll()
                                    local maxScroll = EllesmereUI.SafeScrollRange(sf)
                                    scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
                                    local diff = scrollTarget - cur
                                    if math.abs(diff) < 0.3 then
                                        sf:SetVerticalScroll(scrollTarget)
                                        smoothFrame:Hide()
                                        return
                                    end
                                    sf:SetVerticalScroll(cur + diff * math.min(1, SMOOTH_SPEED * elapsed))
                                end)
                                sf:SetScript("OnMouseWheel", function(_, delta)
                                    local maxScroll = EllesmereUI.SafeScrollRange(sf)
                                    if maxScroll <= 0 then return end
                                    local base = smoothFrame:IsShown() and scrollTarget or sf:GetVerticalScroll()
                                    scrollTarget = math.max(0, math.min(maxScroll, base - delta * SCROLL_STEP))
                                    smoothFrame:Show()
                                end)

                                local function ApplyFlyoutFilter(raw)
                                    local q = strlower(strtrim(raw or ""))
                                    sePh:SetShown(q == "")
                                    local yy = 4
                                    for _, e in ipairs(flyoutEntries) do
                                        if e.isDivider then
                                            -- Separators only make sense in the full list.
                                            if q == "" then
                                                e.frame:Show()
                                                e.frame:ClearAllPoints()
                                                e.frame:SetPoint("TOPLEFT", subInner, "TOPLEFT", 6, -yy - 4)
                                                e.frame:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -6, -yy - 4)
                                                yy = yy + 9
                                            else
                                                e.frame:Hide()
                                            end
                                        else
                                            local nm = e.name or (e.label and e.label:GetText()) or ""
                                            if q == "" or strfind(strlower(tostring(nm)), q, 1, true) then
                                                e.frame:Show()
                                                e.frame:ClearAllPoints()
                                                e.frame:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -yy)
                                                e.frame:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -yy)
                                                yy = yy + ITEM_H
                                            else
                                                e.frame:Hide()
                                            end
                                        end
                                    end
                                    subInner:SetHeight(math.max(1, yy + 4))
                                    scrollTarget = 0
                                    smoothFrame:Hide()
                                    sf:SetVerticalScroll(0)
                                end
                                searchEdit:SetScript("OnTextChanged", function(self) ApplyFlyoutFilter(self:GetText()) end)
                                ApplyFlyoutFilter("")
                            elseif totalSubH > FLYOUT_MAX_H then
                                sub:SetSize(subW, FLYOUT_MAX_H)
                                subInner:ClearAllPoints()
                                local sf = CreateFrame("ScrollFrame", nil, sub)
                                sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
                                sf:SetFrameLevel(sub:GetFrameLevel() + 1)
                                sf:EnableMouseWheel(true)
                                sf:SetScrollChild(subInner)
                                subInner:SetWidth(subW)
                                local scrollTarget = 0
                                local maxScroll = totalSubH - FLYOUT_MAX_H
                                local SCROLL_STEP = 40
                                local SMOOTH_SPEED = 12
                                local smoothFrame = CreateFrame("Frame")
                                smoothFrame:Hide()
                                smoothFrame:SetScript("OnUpdate", function(_, elapsed)
                                    local cur = sf:GetVerticalScroll()
                                    scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
                                    local diff = scrollTarget - cur
                                    if math.abs(diff) < 0.3 then
                                        sf:SetVerticalScroll(scrollTarget)
                                        smoothFrame:Hide()
                                        return
                                    end
                                    sf:SetVerticalScroll(cur + diff * math.min(1, SMOOTH_SPEED * elapsed))
                                end)
                                sf:SetScript("OnMouseWheel", function(_, delta)
                                    if maxScroll <= 0 then return end
                                    local base = smoothFrame:IsShown() and scrollTarget or sf:GetVerticalScroll()
                                    scrollTarget = math.max(0, math.min(maxScroll, base - delta * SCROLL_STEP))
                                    smoothFrame:Show()
                                end)
                            else
                                sub:SetSize(subW, totalSubH)
                            end
                            sub:Show()
                            menu._openSub = sub
                        end

                        row:SetScript("OnEnter", function()
                            if RowDisabled() then
                                if opts.disabledTooltip then
                                    EllesmereUI.ShowWidgetTooltip(row, opts.disabledTooltip)
                                end
                                return
                            end
                            lbl:SetTextColor(1, 1, 1, 1)
                            hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                            ShowSub()
                        end)
                        row:SetScript("OnLeave", function()
                            if opts and opts.disabledTooltip then EllesmereUI.HideWidgetTooltip() end
                            UpdateLabelColor()
                            hl:SetAlpha(0)
                            -- Don't auto-close sub here. It closes when:
                            -- 1. A different subnav row is hovered (ShowSub closes _openSub)
                            -- 2. The parent menu closes (OnHide propagates)
                            -- 3. An option is clicked (OnClick hides sub)
                        end)

                        mH = mH + ITEM_H
                        return row, sub
                    end

                    -- "Threshold Text" per-spell subnav, shared by the buff, cd/util
                    -- and preset/custom branches. Threshold Seconds arms the feature
                    -- for the spell (0 = off = zero cost); Threshold Color and
                    -- Threshold Decimals are independent toggles that apply below
                    -- that boundary (rendered by the engine countdown formatter --
                    -- ns.ApplyThresholdFormatter). acc bridges the branch's store
                    -- (per-spell family entry or customActiveStates):
                    --   get(key)      effective read
                    --   set(key, v)   own write (persists the entry first)
                    --   clear(key)    own clear (tier-blocking where applicable)
                    --   refresh()     post-change gate flip + apply calls
                    local function AddThresholdTextRow(acc)
                        local function armedSeconds()
                            return tonumber(acc.get("thresholdSeconds")) or 0
                        end
                        local TT_ITEMS = {
                            { val = "seconds", label = "Threshold Seconds",
                              -- Scalar popup value (not a discrete flyout choice): the
                              -- number lives in the store, entered via a popup, and
                              -- applyWrite pushes the spell's current seconds live. The
                              -- Apply-to-Bar strip must treat it as "always push my
                              -- value", never as a discrete value item -- otherwise the
                              -- rejoin shortcut discards the entered number and the
                              -- suppress-strip rule hides the strip whenever the bar's
                              -- number differs (see scalarApply guards below).
                              scalarApply = true,
                              dynamicLabel = function()
                                  local base = EllesmereUI.L("Threshold Seconds")
                                  local s = armedSeconds()
                                  if s > 0 then return base .. " (" .. s .. "s)" end
                                  return base
                              end,
                              tooltip = "Seconds remaining below which Threshold Color and Threshold Decimals apply (0 = off).",
                              toggleGet = function() return armedSeconds() > 0 end,
                              applyKeys = { "thresholdSeconds" },
                              applyWrite = function(t)
                                  -- Push this spell's current seconds; "off" applied
                                  -- bar-wide blocks the tier below.
                                  local s = armedSeconds()
                                  t.thresholdSeconds = (s > 0) and s or false
                              end },
                            { val = "color", label = "Threshold Color",
                              tooltip = "Recolor the countdown text below Threshold Seconds.",
                              toggleGet = function() return acc.get("thresholdColorEnabled") == true end,
                              toggleSet = function(v)
                                  if v then
                                      acc.set("thresholdColorEnabled", true)
                                      if not acc.get("thresholdColorR") then
                                          acc.set("thresholdColorR", 1)
                                          acc.set("thresholdColorG", 0.2)
                                          acc.set("thresholdColorB", 0.2)
                                      end
                                  else
                                      acc.clear("thresholdColorEnabled")
                                  end
                                  acc.refresh()
                              end,
                              applyKeys = { "thresholdColorEnabled", "thresholdColorR",
                                            "thresholdColorG", "thresholdColorB" },
                              applyWrite = function(t, v)
                                  t.thresholdColorEnabled = v or false
                                  if v then
                                      -- Push this spell's current color.
                                      t.thresholdColorR = acc.get("thresholdColorR") or 1
                                      t.thresholdColorG = acc.get("thresholdColorG") or 0.2
                                      t.thresholdColorB = acc.get("thresholdColorB") or 0.2
                                  else
                                      -- Colour keys belong to the enabled state only;
                                      -- clear them so a stale colour can't linger in
                                      -- the tier and make valuesMatch always fail.
                                      t.thresholdColorR = nil
                                      t.thresholdColorG = nil
                                      t.thresholdColorB = nil
                                  end
                              end },
                            { val = "decimals", label = "Threshold Decimals",
                              tooltip = "Show a 1-decimal countdown (2.7) below Threshold Seconds.",
                              toggleGet = function() return acc.get("thresholdDecimals") == true end,
                              toggleSet = function(v)
                                  if v then acc.set("thresholdDecimals", true)
                                  else acc.clear("thresholdDecimals") end
                                  acc.refresh()
                              end,
                              applyKeys = { "thresholdDecimals" },
                              applyWrite = function(t, v)
                                  t.thresholdDecimals = v or false
                              end },
                        }
                        return MakeSubnavRow("Threshold Text", TT_ITEMS,
                            function() return nil end,
                            function() end,
                            function()
                                return armedSeconds() == 0
                                    and acc.get("thresholdColorEnabled") ~= true
                                    and acc.get("thresholdDecimals") ~= true
                            end,
                            function(si, item, sub)
                                if item.val == "seconds" then
                                    -- Popup flow (mirrors Lower Alpha): close the
                                    -- menu so only the popup shows; 0 disarms.
                                    si:SetScript("OnClick", function()
                                        local cur = armedSeconds()
                                        menu:Hide()
                                        ShowThresholdSecondsPopup(cur > 0 and cur or nil, function(v)
                                            if v and v > 0 then
                                                acc.set("thresholdSeconds", v)
                                            else
                                                acc.clear("thresholdSeconds")
                                            end
                                            acc.refresh()
                                        end)
                                    end)
                                elseif item.val == "color" then
                                    -- Inline color swatch (same shape as the Active
                                    -- State swipe swatch): picking a color also
                                    -- enables the toggle.
                                    local swatchBtn = CreateFrame("Button", nil, si)
                                    swatchBtn:SetSize(14, 14)
                                    swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                    swatchBtn:SetFrameLevel(si:GetFrameLevel() + 3)
                                    local swatchTex = swatchBtn:CreateTexture(nil, "ARTWORK")
                                    swatchTex:SetAllPoints()
                                    swatchTex:SetColorTexture(
                                        acc.get("thresholdColorR") or 1,
                                        acc.get("thresholdColorG") or 0.2,
                                        acc.get("thresholdColorB") or 0.2, 1)
                                    swatchBtn:SetScript("OnClick", function()
                                        acc.set("thresholdColorEnabled", true)
                                        if not acc.get("thresholdColorR") then
                                            acc.set("thresholdColorR", 1)
                                            acc.set("thresholdColorG", 0.2)
                                            acc.set("thresholdColorB", 0.2)
                                        end
                                        -- Keep the dropdown AND flyout open (OnUpdate
                                        -- cpOpen guard); re-highlight the now-on toggle.
                                        if sub._refreshSelection then sub._refreshSelection() end
                                        acc.refresh()
                                        local snapR = acc.get("thresholdColorR") or 1
                                        local snapG = acc.get("thresholdColorG") or 0.2
                                        local snapB = acc.get("thresholdColorB") or 0.2
                                        EllesmereUI:ShowColorPicker({
                                            r = snapR, g = snapG, b = snapB,
                                            swatchFunc = function()
                                                local popup = EllesmereUI._colorPickerPopup
                                                if not popup then return end
                                                local r, g, b = popup:GetColorRGB()
                                                acc.set("thresholdColorR", r)
                                                acc.set("thresholdColorG", g)
                                                acc.set("thresholdColorB", b)
                                                swatchTex:SetColorTexture(r, g, b, 1)
                                                acc.refresh()
                                            end,
                                            cancelFunc = function()
                                                acc.set("thresholdColorR", snapR)
                                                acc.set("thresholdColorG", snapG)
                                                acc.set("thresholdColorB", snapB)
                                                acc.refresh()
                                            end,
                                        }, swatchBtn)
                                    end)
                                end
                            end)
                    end

                    -- A HOSTED buff (a buff placed on a CD/util bar) is a real
                    -- Blizzard buff frame reparented onto the bar, so it takes the
                    -- BUFF per-icon menu, not the CD/util one -- same settings as it
                    -- would have on a buffs bar. isHostedBuff is resolved above
                    -- (slot-based) where the settings store is selected.
                    -- Hosted buffs are removed from the Apply-to-Bar system (no strip on
                    -- their rows, no bar-tier chaining in ResolveSpellSettings).
                    hostedBuffNoApply = isHostedBuff
                    if isBuffBar or isHostedBuff then
                        -- Injected custom/preset buffs (cast-timer driven, identified
                        -- by a stored spellDuration) are show-on-cast only, so the
                        -- Always Show Buffs / Desaturate Inactive overrides (which act
                        -- on Blizzard-tracked inactive placeholders) don't apply to them.
                        local isInjectedCustom = (sd.spellDurations and (sd.spellDurations[spellID] or 0) > 0)
                            or (sd.customSpellIDs and sd.customSpellIDs[spellID]) or false
                        -- BUFF BAR per-icon menu. "Buff Glow" reuses the glow-style
                        -- picker but is driven by the while-shown buff-glow path
                        -- (not proc). nil = inherit the bar's Buff Glow; 0 = None
                        -- (force the glow off on this one icon).
                        local BUFF_GLOW_ITEMS = {
                            { val = nil, label = "Default" },
                            { val = 0,   label = "None" },
                            { val = 1,   label = "Pixel Glow" },
                            { val = 2,   label = "Shape Glow" },
                            { val = 3,   label = "Button Glow" },
                            { val = 4,   label = "Auto-Cast Shine" },
                            { val = 5,   label = "GCD" },
                            { val = 6,   label = "Modern WoW Glow" },
                            { val = 7,   label = "Classic WoW Glow" },
                        }
                        MakeSubnavRow("Buff Glow", BUFF_GLOW_ITEMS,
                            function() return ss.buffGlow end,
                            function(v) EnsureSS(); SetOwn("buffGlow", v) end,
                            function() return ss.buffGlow == nil end,
                            nil,
                            { apply = { keys = { "buffGlow" },
                                        write = function(t, v) t.buffGlow = v end } })

                        local BUFF_GLOW_COLOR_ITEMS = {
                            { val = nil,      label = "Default" },
                            { val = "class",  label = "Class Color" },
                            { val = "custom", label = "Custom" },
                        }
                        MakeSubnavRow("Glow Effect Color", BUFF_GLOW_COLOR_ITEMS,
                            function() return ss.buffGlowColor end,
                            function(v)
                                EnsureSS()
                                SetOwn("buffGlowColor", v)
                                if v == "custom" and not ss.buffGlowColorR then
                                    ss.buffGlowColorR = 1; ss.buffGlowColorG = 0.776; ss.buffGlowColorB = 0.376
                                end
                            end,
                            function() return ss.buffGlowColor == nil end,
                            function(si, item, sub)
                                if item.val == "custom" then
                                    local swatchBtn = CreateFrame("Button", nil, si)
                                    swatchBtn:SetSize(14, 14)
                                    swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                    swatchBtn:SetFrameLevel(si:GetFrameLevel() + 3)
                                    local swatchTex = swatchBtn:CreateTexture(nil, "ARTWORK")
                                    swatchTex:SetAllPoints()
                                    swatchTex:SetColorTexture(ss.buffGlowColorR or 1, ss.buffGlowColorG or 0.776, ss.buffGlowColorB or 0.376, 1)
                                    swatchBtn:SetScript("OnClick", function()
                                        EnsureSS()
                                        ss.buffGlowColor = "custom"
                                        if not ss.buffGlowColorR then
                                            ss.buffGlowColorR = 1; ss.buffGlowColorG = 0.776; ss.buffGlowColorB = 0.376
                                        end
                                        -- Keep the dropdown AND flyout open (the OnUpdate
                                        -- cpOpen guard holds them while the picker is up);
                                        -- just re-highlight the now-selected Custom row.
                                        if sub._refreshSelection then sub._refreshSelection() end
                                        local snapR, snapG, snapB = ss.buffGlowColorR, ss.buffGlowColorG, ss.buffGlowColorB
                                        EllesmereUI:ShowColorPicker({
                                            r = snapR, g = snapG, b = snapB,
                                            swatchFunc = function()
                                                local popup = EllesmereUI._colorPickerPopup
                                                if not popup then return end
                                                local r, g, b = popup:GetColorRGB()
                                                ss.buffGlowColorR = r; ss.buffGlowColorG = g; ss.buffGlowColorB = b
                                                swatchTex:SetColorTexture(r, g, b, 1)
                                                if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                            end,
                                            cancelFunc = function()
                                                ss.buffGlowColorR = snapR; ss.buffGlowColorG = snapG; ss.buffGlowColorB = snapB
                                            end,
                                        }, swatchBtn)
                                    end)
                                end
                            end,
                            { apply = { keys = { "buffGlowColor", "buffGlowColorR", "buffGlowColorG", "buffGlowColorB" },
                                        write = function(t, v)
                                            t.buffGlowColor = v
                                            if v == "custom" then
                                                t.buffGlowColorR = ss.buffGlowColorR or 1
                                                t.buffGlowColorG = ss.buffGlowColorG or 0.776
                                                t.buffGlowColorB = ss.buffGlowColorB or 0.376
                                            else
                                                t.buffGlowColorR = nil
                                                t.buffGlowColorG = nil
                                                t.buffGlowColorB = nil
                                            end
                                        end } })

                        -- Cooldown Swipe (buffs only): tints the aura-duration swipe.
                        -- Default = the bar's swipe colour; Class / Custom mirror Glow
                        -- Effect Color; None fully hides the swipe (alpha 0). Applied on
                        -- the buff frame by the SetSwipeColor hook (which reads these keys).
                        local CD_SWIPE_COLOR_ITEMS = {
                            { val = nil,      label = "Default" },
                            { val = "class",  label = "Class Color" },
                            { val = "custom", label = "Custom" },
                            { val = "none",   label = "None" },
                        }
                        MakeSubnavRow("Cooldown Swipe", CD_SWIPE_COLOR_ITEMS,
                            function() return ss.cdSwipeColor end,
                            function(v)
                                EnsureSS()
                                SetOwn("cdSwipeColor", v)
                                if v == "custom" and not ss.cdSwipeColorR then
                                    ss.cdSwipeColorR = 1; ss.cdSwipeColorG = 0.776; ss.cdSwipeColorB = 0.376
                                end
                                if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            end,
                            function() return ss.cdSwipeColor == nil end,
                            function(si, item, sub)
                                if item.val == "custom" then
                                    local swatchBtn = CreateFrame("Button", nil, si)
                                    swatchBtn:SetSize(14, 14)
                                    swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                    swatchBtn:SetFrameLevel(si:GetFrameLevel() + 3)
                                    local swatchTex = swatchBtn:CreateTexture(nil, "ARTWORK")
                                    swatchTex:SetAllPoints()
                                    swatchTex:SetColorTexture(ss.cdSwipeColorR or 1, ss.cdSwipeColorG or 0.776, ss.cdSwipeColorB or 0.376, 1)
                                    swatchBtn:SetScript("OnClick", function()
                                        EnsureSS()
                                        ss.cdSwipeColor = "custom"
                                        if not ss.cdSwipeColorR then
                                            ss.cdSwipeColorR = 1; ss.cdSwipeColorG = 0.776; ss.cdSwipeColorB = 0.376
                                        end
                                        if sub._refreshSelection then sub._refreshSelection() end
                                        local snapR, snapG, snapB = ss.cdSwipeColorR, ss.cdSwipeColorG, ss.cdSwipeColorB
                                        EllesmereUI:ShowColorPicker({
                                            r = snapR, g = snapG, b = snapB,
                                            swatchFunc = function()
                                                local popup = EllesmereUI._colorPickerPopup
                                                if not popup then return end
                                                local r, g, b = popup:GetColorRGB()
                                                ss.cdSwipeColorR = r; ss.cdSwipeColorG = g; ss.cdSwipeColorB = b
                                                swatchTex:SetColorTexture(r, g, b, 1)
                                                if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                            end,
                                            cancelFunc = function()
                                                ss.cdSwipeColorR = snapR; ss.cdSwipeColorG = snapG; ss.cdSwipeColorB = snapB
                                            end,
                                        }, swatchBtn)
                                    end)
                                end
                            end,
                            { apply = { keys = { "cdSwipeColor", "cdSwipeColorR", "cdSwipeColorG", "cdSwipeColorB" },
                                        write = function(t, v)
                                            t.cdSwipeColor = v
                                            if v == "custom" then
                                                t.cdSwipeColorR = ss.cdSwipeColorR or 1
                                                t.cdSwipeColorG = ss.cdSwipeColorG or 0.776
                                                t.cdSwipeColorB = ss.cdSwipeColorB or 0.376
                                            else
                                                t.cdSwipeColorR = nil
                                                t.cdSwipeColorG = nil
                                                t.cdSwipeColorB = nil
                                            end
                                        end } })

                        -- Duration Text + Charge/Stack Size: each row opens a cog
                        -- popup mirroring the bar's control. Per-icon values override
                        -- the bar; untouched fields inherit (get falls back to bar).
                        local cdmBd = ns.barDataByKey and ns.barDataByKey[barKey]
                        -- Accent cue helpers: a field counts as "changed" only when an
                        -- override is set AND its EFFECTIVE value differs from the bar's.
                        -- So an override that matches the bar (or a bar edit that catches
                        -- up to the override) leaves the field inheriting-equal -> no
                        -- accent. valChanged for scalars/toggles, colChanged for an RGB
                        -- triple (any component nil falls back to the bar component).
                        local function valChanged(sv, bv)
                            return sv ~= nil and sv ~= bv
                        end
                        local function colChanged(sr, sg, sb, br, bg, bb)
                            if sr == nil and sg == nil and sb == nil then return false end
                            return (sr or br) ~= br or (sg or bg) ~= bg or (sb or bb) ~= bb
                        end
                        -- isChanged: a function returning true when this cog's per-icon
                        -- values DIFFER from the bar; the row label then rests at accent
                        -- instead of dim (same "this is customized" cue as tri-state rows).
                        local function MakeCogRow(label, isChanged, buildCog)
                            local row = CreateFrame("Button", nil, inner)
                            row:SetHeight(ITEM_H)
                            row:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                            row:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                            row:SetFrameLevel(menu:GetFrameLevel() + 2)
                            local lbl = row:CreateFontString(nil, "OVERLAY")
                            lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                            lbl:SetPoint("LEFT", 10, 0); lbl:SetJustifyH("LEFT"); lbl:SetText(EllesmereUI.L(label))
                            -- Resting label color: accent when this cog's values differ
                            -- from the bar, dim when they all match / inherit it.
                            local function UpdateLabel()
                                if isChanged() then
                                    local aR, aG, aB = EllesmereUI.GetAccentColor()
                                    lbl:SetTextColor(aR, aG, aB, 1)
                                else
                                    lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                end
                            end
                            row._updateLabel = UpdateLabel
                            UpdateLabel()
                            local arrow = row:CreateTexture(nil, "ARTWORK")
                            arrow:SetSize(10, 10); arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                            arrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
                            arrow:SetAlpha(0.7)
                            local hl = row:CreateTexture(nil, "ARTWORK")
                            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)
                            -- Show on hover, anchored to the side, like the other
                            -- subnav flyouts. Reuse BuildCogPopup but drop its slide
                            -- animation + click-outside dismiss so the menu's _openSub
                            -- machinery (hover-to-switch, close-with-menu) controls it.
                            local showFn, pf
                            local function ShowCog()
                                if not showFn then _, showFn = buildCog(row) end
                                if not pf then
                                    showFn(row)            -- first call creates + shows it
                                    pf = showFn._popupFrame
                                else
                                    if pf._refresh then pf._refresh() end
                                    pf:Show()
                                end
                                if pf then
                                    pf:SetScript("OnUpdate", nil)
                                    pf:SetAlpha(1)
                                    pf:ClearAllPoints()
                                    pf:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)
                                end
                            end
                            row:SetScript("OnEnter", function()
                                lbl:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                                if menu._openSub and menu._openSub ~= pf and menu._openSub.Hide then menu._openSub:Hide() end
                                ShowCog()
                                menu._openSub = pf
                            end)
                            row:SetScript("OnLeave", function()
                                UpdateLabel(); hl:SetAlpha(0)
                            end)
                            mH = mH + ITEM_H
                            return row
                        end

                        MakeCogRow("Duration Text", function()
                            local b = cdmBd
                            return valChanged(ss.showCooldownText, (b and b.showCooldownText) ~= false)
                                or valChanged(ss.cooldownFontSize, (b and b.cooldownFontSize) or 12)
                                or colChanged(ss.cooldownTextR, ss.cooldownTextG, ss.cooldownTextB,
                                    (b and b.cooldownTextR) or 1, (b and b.cooldownTextG) or 1, (b and b.cooldownTextB) or 1)
                                or valChanged(ss.cooldownTextX, (b and b.cooldownTextX) or 0)
                                or valChanged(ss.cooldownTextY, (b and b.cooldownTextY) or 0)
                        end, function(row)
                            return EllesmereUI.BuildCogPopup({
                                -- Level 350: above the spell-picker menu (300) but below
                                -- the shared color picker (FULLSCREEN_DIALOG 400) so the
                                -- picker renders on top. The dropdown menu is bumped above
                                -- the popup in BuildCogPopup's dropdown OnClick hook.
                                title = "Duration Text", noOwnerDim = true,
                                frameStrata = "FULLSCREEN_DIALOG", frameLevel = 350,
                                rows = {
                                    { type="toggle", label="Show Duration",
                                      get=function() if ss.showCooldownText ~= nil then return ss.showCooldownText end return (cdmBd and cdmBd.showCooldownText) ~= false end,
                                      set=function(v) EnsureSS(); ss.showCooldownText = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="slider", label="Size", min=6, max=30, step=1,
                                      get=function() return ss.cooldownFontSize or (cdmBd and cdmBd.cooldownFontSize) or 12 end,
                                      set=function(v) EnsureSS(); ss.cooldownFontSize = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="colorpicker", label="Color",
                                      get=function() return ss.cooldownTextR or (cdmBd and cdmBd.cooldownTextR) or 1, ss.cooldownTextG or (cdmBd and cdmBd.cooldownTextG) or 1, ss.cooldownTextB or (cdmBd and cdmBd.cooldownTextB) or 1 end,
                                      set=function(r, g, b) EnsureSS(); ss.cooldownTextR = r; ss.cooldownTextG = g; ss.cooldownTextB = b; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                                      get=function() return ss.cooldownTextX or (cdmBd and cdmBd.cooldownTextX) or 0 end,
                                      set=function(v) EnsureSS(); ss.cooldownTextX = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                                      get=function() return ss.cooldownTextY or (cdmBd and cdmBd.cooldownTextY) or 0 end,
                                      set=function(v) EnsureSS(); ss.cooldownTextY = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                },
                            })
                        end)

                        MakeCogRow("Charge/Stack Text", function()
                            local b = cdmBd
                            return valChanged(ss.showItemCount, (b and b.showItemCount) ~= false)
                                or valChanged(ss.stackCountSize, (b and b.stackCountSize) or 11)
                                or colChanged(ss.stackCountR, ss.stackCountG, ss.stackCountB,
                                    (b and b.stackCountR) or 1, (b and b.stackCountG) or 1, (b and b.stackCountB) or 1)
                                or valChanged(ss.stackCountPosition, (b and b.stackCountPosition) or "bottomright")
                                or valChanged(ss.stackCountX, (b and b.stackCountX) or 0)
                                or valChanged(ss.stackCountY, (b and b.stackCountY) or 0)
                        end, function(row)
                            return EllesmereUI.BuildCogPopup({
                                title = "Charge/Stack Text", noOwnerDim = true,
                                frameStrata = "FULLSCREEN_DIALOG", frameLevel = 350,
                                rows = {
                                    { type="toggle", label="Show Item Count",
                                      get=function() if ss.showItemCount ~= nil then return ss.showItemCount end return (cdmBd and cdmBd.showItemCount) ~= false end,
                                      set=function(v) EnsureSS(); ss.showItemCount = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="slider", label="Size", min=6, max=30, step=1,
                                      get=function() return ss.stackCountSize or (cdmBd and cdmBd.stackCountSize) or 11 end,
                                      set=function(v) EnsureSS(); ss.stackCountSize = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="colorpicker", label="Color",
                                      get=function() return ss.stackCountR or (cdmBd and cdmBd.stackCountR) or 1, ss.stackCountG or (cdmBd and cdmBd.stackCountG) or 1, ss.stackCountB or (cdmBd and cdmBd.stackCountB) or 1 end,
                                      set=function(r, g, b) EnsureSS(); ss.stackCountR = r; ss.stackCountG = g; ss.stackCountB = b; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="dropdown", label="Position",
                                      values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                                      order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                                      get=function() return ss.stackCountPosition or (cdmBd and cdmBd.stackCountPosition) or "bottomright" end,
                                      set=function(v) EnsureSS(); ss.stackCountPosition = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="slider", label="X Offset", min=-150, max=150, step=1,
                                      get=function() return ss.stackCountX or (cdmBd and cdmBd.stackCountX) or 0 end,
                                      set=function(v) EnsureSS(); ss.stackCountX = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="slider", label="Y Offset", min=-150, max=150, step=1,
                                      get=function() return ss.stackCountY or (cdmBd and cdmBd.stackCountY) or 0 end,
                                      set=function(v) EnsureSS(); ss.stackCountY = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                },
                            })
                        end)

                        -- Border: per-icon override of the bar's border SIZE +
                        -- COLOR (never style). Mirrors the Charge/Stack Text cog
                        -- exactly; the render side reads (ssb and ssb.border*) or
                        -- the bar value in ApplyShapeToCDMIcon.
                        MakeCogRow("Border", function()
                            local b = cdmBd
                            return valChanged(ss.borderSize, (b and b.borderSize) or 1)
                                or colChanged(ss.borderR, ss.borderG, ss.borderB,
                                    (b and b.borderR) or 0, (b and b.borderG) or 0, (b and b.borderB) or 0)
                        end, function(row)
                            return EllesmereUI.BuildCogPopup({
                                title = "Border", noOwnerDim = true,
                                frameStrata = "FULLSCREEN_DIALOG", frameLevel = 350,
                                rows = {
                                    { type="slider", label="Size", min=0, max=8, step=1,
                                      get=function() return ss.borderSize or (cdmBd and cdmBd.borderSize) or 1 end,
                                      set=function(v) EnsureSS(); ss.borderSize = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="colorpicker", label="Color",
                                      get=function() return ss.borderR or (cdmBd and cdmBd.borderR) or 0, ss.borderG or (cdmBd and cdmBd.borderG) or 0, ss.borderB or (cdmBd and cdmBd.borderB) or 0 end,
                                      set=function(r, g, b) EnsureSS(); ss.borderR = r; ss.borderG = g; ss.borderB = b; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                },
                            })
                        end)

                        -- Audio on Buff Gain / Loss sound list + speaker-preview
                        -- decorator. Defined once here so the Blizzard-tracked-buff
                        -- rows AND the self-timed preset/custom gain row share the same
                        -- list + preview (entries mirror the Focus Cast Sound dropdown
                        -- via the shared ns.FOCUSKICK_SOUND_* tables).
                        local AUDIO_ITEMS = {}
                        for _, key in ipairs(ns.FOCUSKICK_SOUND_ORDER or { "none" }) do
                            if type(key) == "string" and key:sub(1, 3) == "---" then
                                -- Separator inserted by AppendSharedMediaSounds between
                                -- the built-in sounds and the appended LibSharedMedia
                                -- sounds. Render as a divider line, not a sound entry.
                                AUDIO_ITEMS[#AUDIO_ITEMS + 1] = { divider = true }
                            else
                                AUDIO_ITEMS[#AUDIO_ITEMS + 1] = {
                                    val   = key,
                                    label = (ns.FOCUSKICK_SOUND_NAMES and ns.FOCUSKICK_SOUND_NAMES[key]) or key,
                                }
                            end
                        end
                        -- Speaker-preview decorator: plays a row's focused sound without
                        -- selecting it (mirrors the dropdown's preview icon).
                        local function AddSoundPreview(si, item)
                            if item.val and item.val ~= "none" then
                                local play = CreateFrame("Button", nil, si)
                                play:SetSize(16, 16)
                                play:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                play:SetFrameLevel(si:GetFrameLevel() + 2)
                                play:SetNormalAtlas("common-icon-sound")
                                play:SetPushedAtlas("common-icon-sound-pressed")
                                play:SetScript("OnClick", function()
                                    local paths = ns.FOCUSKICK_SOUND_PATHS
                                    local path = paths and paths[item.val]
                                    if path then PlaySoundFile(path, "Master") end
                                end)
                                play:SetScript("OnEnter", function()
                                    EllesmereUI.ShowWidgetTooltip(play, "Preview Sound")
                                end)
                                play:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                            end
                        end
                        -- "Audio on Buff Gain": stored per-icon as ss.buffActiveSoundKey
                        -- ("none"/nil = silent). Blizzard-tracked buffs fire it via the
                        -- apply-edge hook (EnsureBuffSoundHook -> TriggerAuraAppliedAlert);
                        -- self-timed preset/custom buffs fire it from the cast-timer gain
                        -- edge in UpdateCustomBuffBars (CdmHooks) off the SAME stored key.
                        local function AddBuffGainRow()
                            MakeSubnavRow("Audio on Buff Gain", AUDIO_ITEMS,
                                function() return ss.buffActiveSoundKey or "none" end,
                                function(v)
                                    EnsureSS()
                                    SetOwn("buffActiveSoundKey", (v ~= "none" and v) or nil)
                                    -- Flip the 0-cost gate live so the edge hook / cast
                                    -- timer starts playing on the next activation.
                                    if ss.buffActiveSoundKey then ns._cdmAnyBuffSound = true end
                                end,
                                function() return ss.buffActiveSoundKey == nil end,
                                AddSoundPreview,
                                { searchable = true,
                                  apply = { keys = { "buffActiveSoundKey" },
                                            write = function(t, v)
                                                -- "None" applied bar-wide = explicitly
                                                -- silent (false blocks the tier below).
                                                t.buffActiveSoundKey = (v ~= "none" and v) or false
                                            end } })
                        end
                        -- "Audio on Buff Loss": stored per-icon as ss.buffLostSoundKey.
                        local function AddBuffLossRow()
                            MakeSubnavRow("Audio on Buff Loss", AUDIO_ITEMS,
                                function() return ss.buffLostSoundKey or "none" end,
                                function(v)
                                    EnsureSS()
                                    SetOwn("buffLostSoundKey", (v ~= "none" and v) or nil)
                                    if ss.buffLostSoundKey then ns._cdmAnyBuffSound = true end
                                end,
                                function() return ss.buffLostSoundKey == nil end,
                                AddSoundPreview,
                                { searchable = true,
                                  apply = { keys = { "buffLostSoundKey" },
                                            write = function(t, v)
                                                t.buffLostSoundKey = (v ~= "none" and v) or false
                                            end } })
                        end

                        -- Always Show Buffs + Desaturate Inactive apply only to
                        -- Blizzard-tracked buffs (inactive placeholders); injected
                        -- custom/preset buffs skip them and get only the gain row.
                        if not isInjectedCustom then
                            -- Hosted buffs (on a CD/util bar) OMIT these two bar-toggle
                            -- overrides: always-show and desaturate-inactive are baked in
                            -- (a cd/util bar has no such bar toggle to override). Audio
                            -- rows below still apply, so they stay outside this guard.
                            if not isHostedBuff then
                            -- Always Show Buffs: per-icon tri-state override of the bar
                            -- toggle. Default = inherit bar; Show = force the inactive
                            -- placeholder on; Hide = force it off. A reanchor (queued by
                            -- the row's setVal) creates/removes the placeholder.
                            local ALWAYS_SHOW_ITEMS = {
                                { val = nil,   label = "Default" },
                                { val = "on",  label = "Show" },
                                { val = "off", label = "Hide" },
                            }
                            MakeSubnavRow("Always Show Buff", ALWAYS_SHOW_ITEMS,
                                function() return ss.alwaysShow end,
                                function(v)
                                    EnsureSS(); SetOwn("alwaysShow", v)
                                    -- Refresh the page so "Keep Buffs in Same Place"
                                    -- grays/ungrays as this per-icon override flips.
                                    if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
                                end,
                                function() return ss.alwaysShow == nil end,
                                nil,
                                -- Mutually exclusive with the bar's "Keep Buffs in Same
                                -- Place": that mode reserves every buff's slot and ignores
                                -- per-icon overrides, so disable this row while it's on.
                                -- Escape hatch: if THIS icon is the one already forcing
                                -- "on" (legacy both-enabled data), keep the row editable so
                                -- the user can clear it, which re-enables Keep Buffs.
                                { disabled = function()
                                      local bd = ns.barDataByKey and ns.barDataByKey[barKey]
                                      return bd and bd.hidePlaceholderIcon == true
                                          and ss.alwaysShow ~= "on" or false
                                  end,
                                  disabledTooltip = "Disabled while Keep Buffs in Same Place is enabled",
                                  apply = { keys = { "alwaysShow" },
                                            write = function(t, v) t.alwaysShow = v end } })

                            -- Desaturate Inactive: per-icon tri-state override of the bar's
                            -- Always Show Buffs "Desaturate Off CD" cog setting. Applies to
                            -- this buff's inactive placeholder. Default = inherit bar.
                            local DESAT_ITEMS = {
                                { val = nil,   label = "Default" },
                                { val = "on",  label = "Desaturate" },
                                { val = "off", label = "Full Color" },
                            }
                            MakeSubnavRow("Desaturate Inactive", DESAT_ITEMS,
                                function() return ss.desatInactive end,
                                function(v) EnsureSS(); SetOwn("desatInactive", v) end,
                                function() return ss.desatInactive == nil end,
                                nil,
                                { apply = { keys = { "desatInactive" },
                                            write = function(t, v) t.desatInactive = v end } })
                            end  -- if not isHostedBuff (bar-toggle overrides omitted)

                            AddBuffGainRow()
                            AddBuffLossRow()
                        else
                            -- Self-timed preset/custom buffs: both edges driven off the
                            -- displayed timer in UpdateCustomBuffBars (no real aura event).
                            AddBuffGainRow()
                            AddBuffLossRow()
                        end

                        -- Reverse Swipe (buffs / custom buffs / buff presets):
                        -- reverses the buff's fill direction. Default off. Same
                        -- per-spell store (ss) + runtime apply + zero-cost gate as
                        -- cd/utility spells; placed outside the injected split so it
                        -- is offered for every buff type.
                        MakeSubnavRow("Reverse Swipe", REVERSE_SWIPE_ITEMS,
                            function() return ss.reverseSwipe and true or nil end,
                            function(v)
                                EnsureSS(); SetOwn("reverseSwipe", v or nil)
                                if v then ns._cdmAnyReverseSwipe = true end
                                if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            end,
                            function() return ss.reverseSwipe == nil end,
                            nil,
                            { apply = { keys = { "reverseSwipe" },
                                        write = function(t, v)
                                            -- "Off" applied bar-wide blocks the tier below.
                                            t.reverseSwipe = v or false
                                        end } })

                        -- Threshold Text (every buff type): decimals / color change
                        -- on the aura countdown below the spell's Threshold Seconds.
                        -- Same per-spell store (ss) + engine countdown formatter as
                        -- cd/utility spells; the engine evaluates it, so secret aura
                        -- durations format fine.
                        do
                            local acc = {}
                            acc.get = function(k) return ss[k] end
                            acc.set = function(k, v) EnsureSS(); ss[k] = v end
                            acc.clear = function(k) EnsureSS(); SetOwn(k, nil) end
                            acc.refresh = function()
                                if (tonumber(ss.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end
                                if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                if ns.QueueReanchor then ns.QueueReanchor() end
                            end
                            AddThresholdTextRow(acc)
                        end
                    else
                    local isCustomInjected = spellID < 0
                        or (ns._myRacialsSet and ns._myRacialsSet[spellID])
                        or (sd.customSpellIDs and sd.customSpellIDs[spellID])

                    if isCustomInjected then
                        -- Custom Active State for preset icons (trinkets / potions /
                        -- racials / custom spell IDs). These have no Blizzard active
                        -- detection, so the only setting is a user-defined active
                        -- overlay (EllesmereUICdmFakeActive.lua): a timer plus the
                        -- standard Active Swipe / Active Glow / Glow Effect Color.
                        -- The custom active state lives in a PROFILE-level store
                        -- keyed by the spell (ns.GetCustomActiveState), so it travels
                        -- with the spell across every bar and spec -- not in this
                        -- bar's per-spell settings. Trinket slots key by the EQUIPPED
                        -- item, so each trinket tracks separately (casKey).
                        local casKey = (ns.ResolveCustomActiveKey and ns.ResolveCustomActiveKey(spellID)) or spellID
                        local cas = ns.GetCustomActiveState and ns.GetCustomActiveState(casKey) or nil
                        -- Trinket slots: the menu DISPLAYS the effective view -- the
                        -- equipped item's own entry chained per-key over the slot's
                        -- "Apply to Bar" stamp (GetEffectiveCustomActiveState uses the
                        -- same chain at render time) -- while WRITES stay item-keyed
                        -- (casKey), so each trinket still tracks separately. casKey ==
                        -- spellID means no item is equipped (writes then target the
                        -- slot entry itself); never chain an entry to itself.
                        local casSlot = nil
                        if (spellID == -13 or spellID == -14) and casKey ~= spellID
                           and ns.GetCustomActiveState then
                            casSlot = ns.GetCustomActiveState(spellID)
                        end
                        -- Not-yet-persisted fresh view, persisted on first WRITE --
                        -- same contract as the family-store EnsureSS above.
                        if not cas then cas = {} end
                        if ns.ChainSettings then ns.ChainSettings(cas, casSlot) end
                        local function EnsureCAS()
                            local storeC = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
                            if storeC and not storeC[casKey] then storeC[casKey] = cas end
                            return cas
                        end
                        -- Own-value writer for nil-off keys: writing nil would let a
                        -- slot-stamp value show through the chain; when that would
                        -- change the effective value, store explicit false instead
                        -- (render-equivalent to nil, but blocks the inheritance --
                        -- the per-trinket exclusion). Mirrors the family SetOwn.
                        local function SetCasOwn(key, v2)
                            local e = EnsureCAS()
                            e[key] = v2
                            if v2 == nil and e[key] ~= nil then
                                e[key] = false
                            end
                        end
                        local hasActive = (cas.duration or 0) > 0

                        -- (The divider above the per-icon settings is already drawn
                        -- before the buff/CD branch, so we don't add another here.)

                        -- Plain clickable action row (label + hover highlight).
                        local function MakeActionRow(text, onClick)
                            local row = CreateFrame("Button", nil, inner)
                            row:SetHeight(ITEM_H)
                            row:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                            row:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                            row:SetFrameLevel(menu:GetFrameLevel() + 2)
                            local lbl = row:CreateFontString(nil, "OVERLAY")
                            lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                            lbl:SetPoint("LEFT", 10, 0); lbl:SetJustifyH("LEFT")
                            lbl:SetText(EllesmereUI.L(text))
                            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            local hl = row:CreateTexture(nil, "ARTWORK")
                            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)
                            row:SetScript("OnEnter", function()
                                lbl:SetTextColor(1, 1, 1, 1)
                                hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                                if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
                            end)
                            row:SetScript("OnLeave", function()
                                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); hl:SetAlpha(0)
                            end)
                            row:SetScript("OnClick", onClick)
                            mH = mH + ITEM_H
                            return row
                        end

                        local GLOW_COLOR_ITEMS = {
                            { val = nil,      label = "Default" },
                            { val = "class",  label = "Class Color" },
                            { val = "custom", label = "Custom" },
                        }
                        local CA_SWIPE_ITEMS = {
                            { val = "custom", label = "Swipe Color" },
                            { val = "class",  label = "Swipe Class Colored" },
                            { val = "none",   label = "Hide Active State" },
                        }
                        local CD_STATE_ITEMS = {
                            { val = nil,               label = "None" },
                            -- Same logic as Hidden (On CD) with a customizable opacity.
                            { val = "lowerAlphaOnCD",  label = "Lower Alpha (On CD)",
                              dynamicLabel = function()
                                  local base = EllesmereUI.L("Lower Alpha (On CD)")
                                  if cas and cas.cdStateEffect == "lowerAlphaOnCD" then
                                      local pct = math.floor(((cas.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                                      return pct .. "% " .. base
                                  end
                                  return base
                              end },
                            -- Shift variants: same hide as the plain modes below, but
                            -- the bar re-lays out so remaining icons close the gap.
                            { val = "hiddenOnCDShift",  label = "Hidden on CD (Shift Icons)" },
                            { val = "hiddenReadyShift", label = "Hidden CD Ready (Shift Icons)" },
                            { val = "hiddenOnCD",      label = "Hidden (On CD)" },
                            { val = "hiddenReady",     label = "Hidden (CD Ready)" },
                            { val = "pixelGlowReady",  label = "Pixel Glow (CD Ready)" },
                            { val = "buttonGlowReady", label = "Button Glow (CD Ready)" },
                        }

                        -- Right-aligned colour swatch on a subnav item.
                        local function MakeColorSwatch(si, getR, getG, getB, onChanged)
                            local sw = CreateFrame("Button", nil, si)
                            sw:SetSize(14, 14)
                            sw:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            sw:SetFrameLevel(si:GetFrameLevel() + 3)
                            local tex = sw:CreateTexture(nil, "ARTWORK")
                            tex:SetAllPoints(); tex:SetColorTexture(getR(), getG(), getB(), 1)
                            sw:SetScript("OnClick", function()
                                local sr, sg, sb = getR(), getG(), getB()
                                -- Keep the per-spell dropdown open (OnUpdate cpOpen guard).
                                EllesmereUI:ShowColorPicker({
                                    r = sr, g = sg, b = sb,
                                    swatchFunc = function()
                                        local pk = EllesmereUI._colorPickerPopup
                                        if not pk then return end
                                        local r, g, b = pk:GetColorRGB()
                                        tex:SetColorTexture(r, g, b, 1)
                                        onChanged(r, g, b)
                                    end,
                                    cancelFunc = function() onChanged(sr, sg, sb) end,
                                }, sw)
                            end)
                        end

                        -- Cooldown State Effect (always available for presets;
                        -- driven by the live cooldown, independent of the active
                        -- overlay).
                        MakeSubnavRow("Cooldown State Effect", CD_STATE_ITEMS,
                            function()
                                local v = cas.cdStateEffect
                                if v == false then v = nil end  -- blocked slot value = None
                                return v
                            end,
                            function(v)
                                SetCasOwn("cdStateEffect", v)
                                if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                            end,
                            function() return not cas.cdStateEffect end,
                            function(si, item, sub)
                                -- Lower Alpha (On CD): prompt for the opacity percent,
                                -- then select the effect (mirrors the setVal above).
                                if item.val == "lowerAlphaOnCD" then
                                    si:SetScript("OnClick", function()
                                        local cur = math.floor((((cas and cas.cdStateLowerAlpha) or 0.5) * 100) + 0.5)
                                        -- Close the per-spell dropdown so only the popup shows.
                                        menu:Hide()
                                        ShowAlphaPopup(cur, function(pct)
                                            local c = EnsureCAS()
                                            c.cdStateLowerAlpha = pct / 100
                                            c.cdStateEffect = "lowerAlphaOnCD"
                                            if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                                        end)
                                    end)
                                end
                            end,
                            { apply = { keys = { "cdStateEffect", "cdStateLowerAlpha" },
                                        write = function(t, v)
                                            t.cdStateEffect = v or false
                                            if v == "lowerAlphaOnCD" then
                                                -- Push this icon's current percent (no popup).
                                                t.cdStateLowerAlpha = (cas and cas.cdStateLowerAlpha) or 0.5
                                            else
                                                t.cdStateLowerAlpha = nil
                                            end
                                        end } })

                        -- Threshold Text (preset / custom): decimals / color change
                        -- on this icon's countdowns (item/spell cooldown and the
                        -- fake-active window) below its Threshold Seconds. Stored
                        -- in the profile customActiveStates so it travels with the
                        -- spell; the Fake-Active engine and the appearance pass
                        -- both read it.
                        do
                            local acc = {}
                            acc.get = function(k) return cas[k] end
                            acc.set = function(k, v) local e = EnsureCAS(); e[k] = v end
                            acc.clear = function(k)
                                -- Own clear; when a slot-stamp value would show
                                -- through the chain, store the blocking false.
                                cas[k] = nil
                                if cas[k] ~= nil then SetCasOwn(k, false) end
                            end
                            acc.refresh = function()
                                if (tonumber(cas.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end
                                if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                                if ns.QueueReanchor then ns.QueueReanchor() end
                            end
                            AddThresholdTextRow(acc)
                        end

                        -- Cooldown Swipe (preset / custom): Reverse Swipe flips this
                        -- icon's swipe direction; Hide CD Swipe removes it. Default off.
                        -- Stored in the profile customActiveStates so it travels with the spell.
                        MakeSubnavRow("Cooldown Swipe", CD_SWIPE_ITEMS,
                            function()
                                if cas and cas.hideCDSwipe then return "hide" end
                                if cas and cas.reverseSwipe then return "reverse" end
                                return nil
                            end,
                            function(v)
                                SetCasOwn("reverseSwipe", (v == "reverse") or nil)
                                SetCasOwn("hideCDSwipe", (v == "hide") or nil)
                                if v == "reverse" then ns._cdmAnyReverseSwipe = true end
                                if v == "hide" then ns._cdmAnyHideCDSwipe = true end
                                if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                            end,
                            function() return not (cas and (cas.reverseSwipe or cas.hideCDSwipe)) end,
                            nil,
                            { apply = { keys = { "reverseSwipe", "hideCDSwipe" },
                                        write = function(t, v)
                                            t.reverseSwipe = (v == "reverse") or false
                                            t.hideCDSwipe = (v == "hide") or false
                                        end } })

                        -- Audio Effect on CD Ready (preset / trinket / racial / custom):
                        -- fired when the ability comes off cooldown via the FakeActive
                        -- poll (PresetOnCD). Stored in customActiveStates so it travels
                        -- with the item. (Own list/preview: the buff-bar branch's shared
                        -- AUDIO_ITEMS/AddSoundPreview are out of scope in this branch.)
                        local CDR_ITEMS = {}
                        for _, key in ipairs(ns.FOCUSKICK_SOUND_ORDER or { "none" }) do
                            if type(key) == "string" and key:sub(1, 3) == "---" then
                                CDR_ITEMS[#CDR_ITEMS + 1] = { divider = true }
                            else
                                CDR_ITEMS[#CDR_ITEMS + 1] = { val = key,
                                    label = (ns.FOCUSKICK_SOUND_NAMES and ns.FOCUSKICK_SOUND_NAMES[key]) or key }
                            end
                        end
                        local function AddCdrPreview(si, item)
                            if not (item.val and item.val ~= "none") then return end
                            local play = CreateFrame("Button", nil, si)
                            play:SetSize(16, 16)
                            play:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            play:SetFrameLevel(si:GetFrameLevel() + 2)
                            play:SetNormalAtlas("common-icon-sound")
                            play:SetPushedAtlas("common-icon-sound-pressed")
                            play:SetScript("OnClick", function()
                                local path = ns.FOCUSKICK_SOUND_PATHS and ns.FOCUSKICK_SOUND_PATHS[item.val]
                                if path then PlaySoundFile(path, "Master") end
                            end)
                            play:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(play, "Preview Sound") end)
                            play:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        end
                        MakeSubnavRow("Audio Effect on CD Ready", CDR_ITEMS,
                            function() return (cas and cas.cdReadySoundKey) or "none" end,
                            function(v)
                                local e = EnsureCAS()
                                e.cdReadySoundKey = (v ~= "none" and v) or nil
                                if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                            end,
                            function() return not (cas and cas.cdReadySoundKey) end,
                            AddCdrPreview,
                            { searchable = true })

                        if not hasActive then
                            MakeActionRow("Add Active State", function()
                                ShowDurationPopup(nil, function(seconds)
                                    EnsureCAS().duration = seconds
                                    if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                                end)
                                menu:Hide()
                            end)
                        else
                            -- Active State (swipe colour / class / hide)
                            MakeSubnavRow("Active State", CA_SWIPE_ITEMS,
                                function()
                                    if cas and cas.activeSwipeMode == "none" then return "none" end
                                    if cas and cas.activeSwipeClassColor then return "class" end
                                    return "custom"
                                end,
                                function(v)
                                    local e = EnsureCAS()
                                    if v == "class" then
                                        SetCasOwn("activeSwipeMode", nil)
                                        SetCasOwn("activeSwipeClassColor", true)
                                    elseif v == "none" then
                                        SetCasOwn("activeSwipeMode", "none")
                                        SetCasOwn("activeSwipeClassColor", nil)
                                    else
                                        SetCasOwn("activeSwipeMode", "custom")
                                        SetCasOwn("activeSwipeClassColor", nil)
                                        -- Chained read: a slot-stamp color showing
                                        -- through is kept as the starting custom color.
                                        if not e.activeSwipeR then
                                            e.activeSwipeR = 1; e.activeSwipeG = 0.776
                                            e.activeSwipeB = 0.376; e.activeSwipeA = 0.7
                                        end
                                    end
                                end,
                                function() return cas and cas.activeSwipeMode ~= "none" and not cas.activeSwipeClassColor and not cas.activeSwipeR end,
                                function(si, item)
                                    if item.val == "custom" then
                                        MakeColorSwatch(si,
                                            function() return (cas and cas.activeSwipeR) or 1 end,
                                            function() return (cas and cas.activeSwipeG) or 0.776 end,
                                            function() return (cas and cas.activeSwipeB) or 0.376 end,
                                            function(r, g, b)
                                                local e = EnsureCAS()
                                                e.activeSwipeMode = "custom"
                                                SetCasOwn("activeSwipeClassColor", nil)
                                                e.activeSwipeR = r; e.activeSwipeG = g; e.activeSwipeB = b
                                                e.activeSwipeA = e.activeSwipeA or 0.7
                                            end)
                                    end
                                end,
                                { apply = { keys = { "activeSwipeMode", "activeSwipeClassColor",
                                                     "activeSwipeR", "activeSwipeG", "activeSwipeB", "activeSwipeA" },
                                            write = function(t, v)
                                                -- Colour keys belong to Custom only; clear them for
                                                -- class/none so a stale colour from an earlier Custom
                                                -- apply can't linger in the tier. Leftover R/G/B/A
                                                -- make valuesMatch always fail, so the apply never
                                                -- toggles off and re-prompts the overwrite popup
                                                -- forever without visibly changing anything.
                                                t.activeSwipeR = nil; t.activeSwipeG = nil
                                                t.activeSwipeB = nil; t.activeSwipeA = nil
                                                if v == "class" then
                                                    t.activeSwipeMode = false
                                                    t.activeSwipeClassColor = true
                                                elseif v == "none" then
                                                    t.activeSwipeMode = "none"
                                                    t.activeSwipeClassColor = false
                                                else
                                                    -- Custom: push this icon's current color.
                                                    t.activeSwipeMode = "custom"
                                                    t.activeSwipeClassColor = false
                                                    t.activeSwipeR = (cas and cas.activeSwipeR) or 1
                                                    t.activeSwipeG = (cas and cas.activeSwipeG) or 0.776
                                                    t.activeSwipeB = (cas and cas.activeSwipeB) or 0.376
                                                    t.activeSwipeA = (cas and cas.activeSwipeA) or 0.7
                                                end
                                            end } })

                            -- Active State Glow
                            MakeSubnavRow("Active State Glow", ACTIVE_GLOW_ITEMS,
                                function()
                                    local v = cas.activeGlow
                                    if v == false then v = nil end  -- blocked slot value = None
                                    return v
                                end,
                                function(v) SetCasOwn("activeGlow", v) end,
                                function() return not cas.activeGlow end,
                                nil,
                                { apply = { keys = { "activeGlow" },
                                            write = function(t, v) t.activeGlow = v end } })
                        end

                        -- Glow Effect Color (colours the active glow AND the CD-ready glow).
                        MakeSubnavRow("Glow Effect Color", GLOW_COLOR_ITEMS,
                            function()
                                if cas and cas.glowColor == "class" then return "class" end
                                if cas and cas.glowColor == "custom" then return "custom" end
                                return nil
                            end,
                            function(v)
                                SetCasOwn("glowColor", v)
                                -- Chained read: a slot-stamp color showing through
                                -- is kept as the starting custom color.
                                if v == "custom" and not cas.glowColorR then
                                    local e = EnsureCAS()
                                    e.glowColorR = 1; e.glowColorG = 0.788; e.glowColorB = 0.137
                                end
                            end,
                            function() return not (cas and cas.glowColor) end,
                            function(si, item)
                                if item.val == "custom" then
                                    MakeColorSwatch(si,
                                        function() return (cas and cas.glowColorR) or 1 end,
                                        function() return (cas and cas.glowColorG) or 0.788 end,
                                        function() return (cas and cas.glowColorB) or 0.137 end,
                                        function(r, g, b)
                                            local e = EnsureCAS()
                                            e.glowColor = "custom"
                                            e.glowColorR = r; e.glowColorG = g; e.glowColorB = b
                                        end)
                                end
                            end,
                            { apply = { keys = { "glowColor", "glowColorR", "glowColorG", "glowColorB" },
                                        write = function(t, v)
                                            t.glowColor = v
                                            if v == "custom" then
                                                -- Push this icon's current color.
                                                t.glowColorR = (cas and cas.glowColorR) or 1
                                                t.glowColorG = (cas and cas.glowColorG) or 0.788
                                                t.glowColorB = (cas and cas.glowColorB) or 0.137
                                            else
                                                t.glowColorR = nil
                                                t.glowColorG = nil
                                                t.glowColorB = nil
                                            end
                                        end } })

                        -- Remove Active State (clears only the cast-triggered overlay;
                        -- any Cooldown State Effect stays).
                        if hasActive then
                            MakeActionRow(EllesmereUI.L("Remove Active State") .. " (" .. (cas.duration or 0) .. "s)", function()
                                local store = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
                                local e = store and store[casKey]
                                if e then
                                    e.duration = nil
                                    -- rawget: a chained slot-stamp effect must not
                                    -- hold this own entry alive.
                                    if rawget(e, "cdStateEffect") == nil then store[casKey] = nil end
                                end
                                if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                                menu:Hide()
                            end)
                        end
                    else  -- regular Blizzard-tracked cooldown: full per-spell menu
                    local customDisabledTip = "Not available for custom injected spells"

                    -- Custom-shaped bars always render Shape Glow, so the per-spell proc
                    -- glow choice is locked (custom = any Icon Shape other than None/Cropped).
                    local cdmBd = ns.barDataByKey and ns.barDataByKey[barKey]
                    local barCustomShape = cdmBd and cdmBd.iconShape
                        and cdmBd.iconShape ~= "none" and cdmBd.iconShape ~= "cropped"

                    -- 1. Proc Glow (default = nil)
                    local procRow = MakeSubnavRow("Proc Glow", GLOW_ITEMS,
                        function() return ss.procGlow end,
                        function(v) EnsureSS(); SetOwn("procGlow", v) end,
                        function() return ss.procGlow == nil end,
                        function(si, item)
                            local isGlow = item.val and item.val > 0
                            local cse = ss.cdStateEffect
                            if isGlow and (cse == "pixelGlowReady" or cse == "buttonGlowReady"
                               or cse == "pixelGlowReadyUsable" or cse == "buttonGlowReadyUsable") then
                                si:SetAlpha(0.35)
                                si:SetScript("OnClick", function() end)
                                si:SetScript("OnEnter", function()
                                    EllesmereUI.ShowWidgetTooltip(si, "Disable CD Ready glow first")
                                end)
                                si:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                            end
                        end,
                        { apply = { keys = { "procGlow" },
                                    write = function(t, v) t.procGlow = v end } })
                    if procRow and (isCustomInjected or barCustomShape) then
                        local procDisabledTip = isCustomInjected and customDisabledTip
                            or "Custom shapes always use Shape Glow. Set the bar's Icon Shape to None or Cropped to pick a different glow."
                        procRow:SetAlpha(0.35)
                        procRow:SetScript("OnEnter", function()
                            if EllesmereUI.ShowWidgetTooltip then
                                EllesmereUI.ShowWidgetTooltip(procRow, procDisabledTip)
                            end
                        end)
                        procRow:SetScript("OnLeave", function()
                            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                        end)
                    end

                    -- 2. Active State (default = "custom" / CD Swipe Color #FFC660)
                    local activeRow = MakeSubnavRow("Active State", ACTIVE_SWIPE_ITEMS,
                        function()
                            if ss.activeSwipeMode == "none" then return "none" end
                            if ss.activeSwipeClassColor then return "class" end
                            return "custom"
                        end,
                        function(v)
                            EnsureSS()
                            if v == "class" then
                                SetOwn("activeSwipeMode", nil)
                                ss.activeSwipeClassColor = true
                            elseif v == "none" then
                                ss.activeSwipeMode = "none"
                                SetOwn("activeSwipeClassColor", nil)
                            else
                                -- Custom: keep existing color, only set defaults if none
                                ss.activeSwipeMode = "custom"
                                SetOwn("activeSwipeClassColor", nil)
                                if not ss.activeSwipeR then
                                    ss.activeSwipeR = 1; ss.activeSwipeG = 0.776
                                    ss.activeSwipeB = 0.376; ss.activeSwipeA = 0.7
                                end
                            end
                        end,
                        function()
                            if ss.activeBorderEnabled then return false end
                            if ss.activeSwipeMode == "none" or ss.activeSwipeClassColor then return false end
                            -- Check if custom color differs from default #FFC660
                            local dr, dg, db = 1, 0.776, 0.376
                            local cr = ss.activeSwipeR or dr
                            local cg = ss.activeSwipeG or dg
                            local cb = ss.activeSwipeB or db
                            if math.abs(cr - dr) > 0.01 or math.abs(cg - dg) > 0.01 or math.abs(cb - db) > 0.01 then
                                return false
                            end
                            return true
                        end,
                        function(si, item, sub)
                            if item.val == "custom" then
                                -- Clickable color swatch on right (opens color picker)
                                local swatchBtn = CreateFrame("Button", nil, si)
                                swatchBtn:SetSize(14, 14)
                                swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                swatchBtn:SetFrameLevel(si:GetFrameLevel() + 3)
                                local swatchTex = swatchBtn:CreateTexture(nil, "ARTWORK")
                                swatchTex:SetAllPoints()
                                swatchTex:SetColorTexture(
                                    ss.activeSwipeR or 1,
                                    ss.activeSwipeG or 0.776,
                                    ss.activeSwipeB or 0.376, 1)

                                -- Swatch click: open color picker
                                swatchBtn:SetScript("OnClick", function()
                                    -- Persist before mutating: for a spell with
                                    -- no saved settings yet (e.g. a freshly added
                                    -- Hero-talent spell like Wither / Celestial
                                    -- Conduit), `ss` is a throwaway {} -- without
                                    -- EnsureSS the picked colour is written to a
                                    -- temporary table and lost, so the swipe never
                                    -- changes and reverts to default on reopen.
                                    EnsureSS()
                                    -- Ensure custom mode is selected. SetOwn: a plain
                                    -- nil write would inherit a bar-tier "none"/class
                                    -- value instead of meaning custom.
                                    SetOwn("activeSwipeMode", nil)
                                    SetOwn("activeSwipeClassColor", nil)
                                    if not ss.activeSwipeR then
                                        ss.activeSwipeR = 1; ss.activeSwipeG = 0.776
                                        ss.activeSwipeB = 0.376; ss.activeSwipeA = 0.7
                                    end
                                    -- Keep the dropdown AND flyout open (OnUpdate cpOpen
                                    -- guard); re-highlight the now-selected Custom row.
                                    if sub._refreshSelection then sub._refreshSelection() end
                                    if ns.QueueReanchor then ns.QueueReanchor() end
                                    local snapR, snapG, snapB = ss.activeSwipeR, ss.activeSwipeG, ss.activeSwipeB
                                    local snapA = ss.activeSwipeA or 0.7
                                    local function OnPickerChanged()
                                        local popup = EllesmereUI._colorPickerPopup
                                        if not popup then return end
                                        local r, g, b = popup:GetColorRGB()
                                        local a = popup:GetColorAlpha()
                                        ss.activeSwipeR = r; ss.activeSwipeG = g; ss.activeSwipeB = b
                                        ss.activeSwipeA = a
                                        swatchTex:SetColorTexture(r, g, b, a)
                                        if ns.QueueReanchor then ns.QueueReanchor() end
                                    end
                                    EllesmereUI:ShowColorPicker({
                                        r = snapR, g = snapG, b = snapB,
                                        hasOpacity = true,
                                        opacity = snapA,
                                        opacityFunc = OnPickerChanged,
                                        swatchFunc = OnPickerChanged,
                                        cancelFunc = function()
                                            ss.activeSwipeR = snapR; ss.activeSwipeG = snapG; ss.activeSwipeB = snapB
                                            ss.activeSwipeA = snapA
                                        end,
                                    }, swatchBtn)
                                end)
                            elseif item.activeBorder then
                                -- Border Color swatch (mirrors CD Swipe Color). The
                                -- swatch picks the color and enables the override; the
                                -- row itself toggles it on/off (handled in the item loop).
                                local swatchBtn = CreateFrame("Button", nil, si)
                                swatchBtn:SetSize(14, 14)
                                swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                swatchBtn:SetFrameLevel(si:GetFrameLevel() + 3)
                                local swatchTex = swatchBtn:CreateTexture(nil, "ARTWORK")
                                swatchTex:SetAllPoints()
                                swatchTex:SetColorTexture(
                                    ss.activeBorderR or 1,
                                    ss.activeBorderG or 0.776,
                                    ss.activeBorderB or 0.376, 1)
                                swatchBtn:SetScript("OnClick", function()
                                    EnsureSS()
                                    ss.activeBorderEnabled = true
                                    if not ss.activeBorderR then
                                        ss.activeBorderR = 1; ss.activeBorderG = 0.776
                                        ss.activeBorderB = 0.376; ss.activeBorderA = 1
                                    end
                                    -- Keep the dropdown AND flyout open (OnUpdate cpOpen
                                    -- guard). The border toggle row manages its own
                                    -- highlight, so no selection refresh here.
                                    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    if ns.QueueReanchor then ns.QueueReanchor() end
                                    local snapR, snapG, snapB = ss.activeBorderR, ss.activeBorderG, ss.activeBorderB
                                    local snapA = ss.activeBorderA or 1
                                    local function OnPickerChanged()
                                        local popup = EllesmereUI._colorPickerPopup
                                        if not popup then return end
                                        local r, g, b = popup:GetColorRGB()
                                        local a = popup:GetColorAlpha()
                                        ss.activeBorderR = r; ss.activeBorderG = g; ss.activeBorderB = b
                                        ss.activeBorderA = a
                                        swatchTex:SetColorTexture(r, g, b, a)
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                        if ns.QueueReanchor then ns.QueueReanchor() end
                                    end
                                    EllesmereUI:ShowColorPicker({
                                        r = snapR, g = snapG, b = snapB,
                                        hasOpacity = true,
                                        opacity = snapA,
                                        opacityFunc = OnPickerChanged,
                                        swatchFunc = OnPickerChanged,
                                        cancelFunc = function()
                                            ss.activeBorderR = snapR; ss.activeBorderG = snapG; ss.activeBorderB = snapB
                                            ss.activeBorderA = snapA
                                        end,
                                    }, swatchBtn)
                                end)
                            end
                        end,
                        { apply = { keys = { "activeSwipeMode", "activeSwipeClassColor",
                                             "activeSwipeR", "activeSwipeG", "activeSwipeB", "activeSwipeA" },
                                    write = function(t, v)
                                        -- Colour keys belong to Custom only; clear them for
                                        -- class/none so a stale colour from an earlier Custom
                                        -- apply can't linger in the tier and make valuesMatch
                                        -- always fail (perpetual overwrite popup, no change).
                                        t.activeSwipeR = nil; t.activeSwipeG = nil
                                        t.activeSwipeB = nil; t.activeSwipeA = nil
                                        if v == "class" then
                                            t.activeSwipeMode = false
                                            t.activeSwipeClassColor = true
                                        elseif v == "none" then
                                            t.activeSwipeMode = "none"
                                            t.activeSwipeClassColor = false
                                        else
                                            -- Custom: push this spell's effective color.
                                            t.activeSwipeMode = "custom"
                                            t.activeSwipeClassColor = false
                                            t.activeSwipeR = ss.activeSwipeR or 1
                                            t.activeSwipeG = ss.activeSwipeG or 0.776
                                            t.activeSwipeB = ss.activeSwipeB or 0.376
                                            t.activeSwipeA = ss.activeSwipeA or 0.7
                                        end
                                    end } })
                    if isCustomInjected and activeRow then
                        activeRow:SetAlpha(0.35)
                        activeRow:SetScript("OnEnter", function()
                            if EllesmereUI.ShowWidgetTooltip then
                                EllesmereUI.ShowWidgetTooltip(activeRow, customDisabledTip)
                            end
                        end)
                        activeRow:SetScript("OnLeave", function()
                            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                        end)
                    end

                    -- 3. Active State Glow (default = nil / none)
                    local glowRow = MakeSubnavRow("Active State Glow", ACTIVE_GLOW_ITEMS,
                        function() return ss.activeGlow end,
                        function(v) EnsureSS(); SetOwn("activeGlow", v) end,
                        function() return ss.activeGlow == nil end,
                        nil,
                        { apply = { keys = { "activeGlow" },
                                    write = function(t, v) t.activeGlow = v end } })
                    if isCustomInjected and glowRow then
                        glowRow:SetAlpha(0.35)
                        glowRow:SetScript("OnEnter", function()
                            if EllesmereUI.ShowWidgetTooltip then
                                EllesmereUI.ShowWidgetTooltip(glowRow, customDisabledTip)
                            end
                        end)
                        glowRow:SetScript("OnLeave", function()
                            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                        end)
                    end

                    -- 3a. Max Charges Glow (default = nil / none). 1:1 with Active
                    -- State Glow; glows the icon while a charge spell is at max
                    -- charges. Shares the unified Glow Effect Color below. The
                    -- stored key stays maxStacksGlow (label-only rename).
                    local maxStacksGlowRow = MakeSubnavRow("Max Charges Glow", ACTIVE_GLOW_ITEMS,
                        function() return ss.maxStacksGlow end,
                        function(v) EnsureSS(); SetOwn("maxStacksGlow", v); if v and v > 0 then ns._cdmAnyMaxStacksGlow = true end end,
                        function() return ss.maxStacksGlow == nil end,
                        nil,
                        { apply = { keys = { "maxStacksGlow" },
                                    write = function(t, v) t.maxStacksGlow = v end } })
                    if isCustomInjected and maxStacksGlowRow then
                        maxStacksGlowRow:SetAlpha(0.35)
                        maxStacksGlowRow:SetScript("OnEnter", function()
                            if EllesmereUI.ShowWidgetTooltip then
                                EllesmereUI.ShowWidgetTooltip(maxStacksGlowRow, customDisabledTip)
                            end
                        end)
                        maxStacksGlowRow:SetScript("OnLeave", function()
                            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                        end)
                    end

                    -- 3b. Non Active State (default = nil / none). Desaturates the
                    -- icon when its active-state is NOT active -- the mirror of the
                    -- runtime's active-branch SetDesaturated(false).
                    local NONACTIVE_ITEMS = {
                        { val = nil,  label = "None" },
                        { val = true, label = "Desaturate When Not Active" },
                    }
                    local nonActiveRow = MakeSubnavRow("Non Active State", NONACTIVE_ITEMS,
                        function() return ss.desatNotActive and true or nil end,
                        function(v) EnsureSS(); SetOwn("desatNotActive", v or nil); if v then ns._cdmAnyDesatNotActive = true end end,
                        function() return ss.desatNotActive == nil end,
                        nil,
                        { apply = { keys = { "desatNotActive" },
                                    write = function(t, v) t.desatNotActive = v or false end } })
                    if isCustomInjected and nonActiveRow then
                        nonActiveRow:SetAlpha(0.35)
                        nonActiveRow:SetScript("OnEnter", function()
                            if EllesmereUI.ShowWidgetTooltip then
                                EllesmereUI.ShowWidgetTooltip(nonActiveRow, customDisabledTip)
                            end
                        end)
                        nonActiveRow:SetScript("OnLeave", function()
                            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                        end)
                    end

                    -- 4. Cooldown State Effect (default = nil / none)
                    local cdStateRow = MakeSubnavRow("Cooldown State Effect", CD_STATE_ITEMS,
                        function() return ss.cdStateEffect end,
                        function(v)
                            -- The Resource Aware glows run an event-driven usability
                            -- watcher SHARED by every spell that uses them: its events
                            -- register once, so only the FIRST enable in the current
                            -- spec pays the cost. Prompt only when no spell on any bar
                            -- in this spec already has a Resource Aware glow (a spell's
                            -- own current value counts, so pixel<->button switches and
                            -- re-selects never prompt). Plain CD Ready glows are
                            -- cost-free and never prompt.
                            local isGlow = (v == "pixelGlowReadyUsable" or v == "buttonGlowReadyUsable")
                            if isGlow and not AB.AnyResourceAwareGlowSaved() then
                                menu:Hide()
                                EllesmereUI:ShowConfirmPopup({
                                    title       = "CD Ready Glow (Resource Aware)",
                                    message     = "Resource Aware CD Ready Glow may cause a slight loss in performance efficiency. Do you want to enable it?",
                                    confirmText = "Enable",
                                    cancelText  = "Cancel",
                                    onConfirm   = function()
                                        EnsureSS(); ss.cdStateEffect = v
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    end,
                                })
                                return
                            end
                            EnsureSS(); SetOwn("cdStateEffect", v)
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        end,
                        function() return ss.cdStateEffect == nil and not ss.chargeHideSwipe and not ss.hideRechargeEdge and not ss.chargeHideCdText end,
                        function(si, item, sub)
                            -- Lower Alpha (On CD): clicking prompts for the opacity
                            -- percent, then selects the effect (mirrors the setVal above).
                            if item.val == "lowerAlphaOnCD" then
                                si:SetScript("OnClick", function()
                                    local cur = math.floor(((ss.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                                    -- Close the per-spell dropdown so only the popup shows.
                                    menu:Hide()
                                    ShowAlphaPopup(cur, function(pct)
                                        EnsureSS()
                                        ss.cdStateLowerAlpha = pct / 100
                                        ss.cdStateEffect = "lowerAlphaOnCD"
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    end)
                                end)
                                return
                            end
                            local isGlow = (item.val == "pixelGlowReady" or item.val == "buttonGlowReady"
                                or item.val == "pixelGlowReadyUsable" or item.val == "buttonGlowReadyUsable")
                            if isGlow and ss.procGlow and ss.procGlow > 0 then
                                si:SetAlpha(0.35)
                                si:SetScript("OnClick", function() end)
                                si:SetScript("OnEnter", function()
                                    EllesmereUI.ShowWidgetTooltip(si, "Disable Proc Glow first")
                                end)
                                si:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                            end
                        end,
                        { apply = { confirmRA = true,
                                    keys = { "cdStateEffect", "cdStateLowerAlpha" },
                                    write = function(t, v)
                                        -- "None" applied bar-wide = explicitly no effect
                                        -- (false blocks the all-specs tier below).
                                        t.cdStateEffect = v or false
                                        if v == "lowerAlphaOnCD" then
                                            -- Push this spell's current percent (no popup).
                                            t.cdStateLowerAlpha = ss.cdStateLowerAlpha or 0.5
                                        else
                                            t.cdStateLowerAlpha = nil
                                        end
                                    end } })
                    if isCustomInjected and cdStateRow then
                        cdStateRow:SetAlpha(0.35)
                        cdStateRow:SetScript("OnEnter", function()
                            if EllesmereUI.ShowWidgetTooltip then
                                EllesmereUI.ShowWidgetTooltip(cdStateRow, customDisabledTip)
                            end
                        end)
                        cdStateRow:SetScript("OnLeave", function()
                            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                        end)
                    end

                    -- 4a. Threshold Text: decimals / color change on this spell's
                    -- countdowns (cooldown, recharge and active state) below its
                    -- Threshold Seconds. Engine countdown formatter -- see
                    -- ns.ApplyThresholdFormatter; zero cost until armed.
                    do
                        local acc = {}
                        acc.get = function(k) return ss[k] end
                        acc.set = function(k, v) EnsureSS(); ss[k] = v end
                        acc.clear = function(k) EnsureSS(); SetOwn(k, nil) end
                        acc.refresh = function()
                            if (tonumber(ss.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                        end
                        AddThresholdTextRow(acc)
                    end

                    -- 4b. Cooldown Swipe (per-spell): Reverse Swipe flips the swipe
                    -- direction; Hide CD Swipe removes it. Default off. Runtime apply +
                    -- zero-cost gates live in RefreshCDMIconAppearance /
                    -- RescanReverseSwipeFlag and the SetDrawSwipe hook.
                    MakeSubnavRow("Cooldown Swipe", CD_SWIPE_ITEMS,
                        function()
                            if ss.hideCDSwipe then return "hide" end
                            if ss.reverseSwipe then return "reverse" end
                            return nil
                        end,
                        function(v)
                            EnsureSS()
                            SetOwn("reverseSwipe", (v == "reverse") or nil)
                            SetOwn("hideCDSwipe", (v == "hide") or nil)
                            if ss.reverseSwipe then ns._cdmAnyReverseSwipe = true end
                            if ss.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        end,
                        function() return ss.reverseSwipe == nil and ss.hideCDSwipe == nil end,
                        nil,
                        { apply = { keys = { "reverseSwipe", "hideCDSwipe" },
                                    write = function(t, v)
                                        -- "Off" applied bar-wide blocks the tier below.
                                        t.reverseSwipe = (v == "reverse") or false
                                        t.hideCDSwipe = (v == "hide") or false
                                    end } })

                    -- 4c. Audio Effect on CD Ready (cd/utility per-icon): play a sound
                    -- the moment the spell's real cooldown finishes. Same sound list +
                    -- speaker preview as the buff Audio rows / Focus Cast Sound (shared
                    -- ns.FOCUSKICK_SOUND_* tables); stored as ss.cdReadySoundKey
                    -- ("none"/nil = silent). The per-frame SetDesaturated edge hook
                    -- (gated by ns._cdmAnyCdReadySound) fires it on the on-CD -> ready edge.
                    local CDR_AUDIO_ITEMS = {}
                    for _, key in ipairs(ns.FOCUSKICK_SOUND_ORDER or { "none" }) do
                        if type(key) == "string" and key:sub(1, 3) == "---" then
                            CDR_AUDIO_ITEMS[#CDR_AUDIO_ITEMS + 1] = { divider = true }
                        else
                            CDR_AUDIO_ITEMS[#CDR_AUDIO_ITEMS + 1] = {
                                val   = key,
                                label = (ns.FOCUSKICK_SOUND_NAMES and ns.FOCUSKICK_SOUND_NAMES[key]) or key,
                            }
                        end
                    end
                    local function AddCdrSoundPreview(si, item)
                        if item.val and item.val ~= "none" then
                            local play = CreateFrame("Button", nil, si)
                            play:SetSize(16, 16)
                            play:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            play:SetFrameLevel(si:GetFrameLevel() + 2)
                            play:SetNormalAtlas("common-icon-sound")
                            play:SetPushedAtlas("common-icon-sound-pressed")
                            play:SetScript("OnClick", function()
                                local paths = ns.FOCUSKICK_SOUND_PATHS
                                local path = paths and paths[item.val]
                                if path then PlaySoundFile(path, "Master") end
                            end)
                            play:SetScript("OnEnter", function()
                                EllesmereUI.ShowWidgetTooltip(play, "Preview Sound")
                            end)
                            play:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        end
                    end
                    local cdReadySoundRow = MakeSubnavRow("Audio Effect on CD Ready", CDR_AUDIO_ITEMS,
                        function() return ss.cdReadySoundKey or "none" end,
                        function(v)
                            EnsureSS()
                            SetOwn("cdReadySoundKey", (v ~= "none" and v) or nil)
                            -- Flip the 0-cost gate live so the edge hook starts evaluating
                            -- on the next desaturation tick, and refresh so a CHARGE spell
                            -- registers on the SPELL_UPDATE_CHARGES watcher immediately.
                            if ss.cdReadySoundKey then ns._cdmAnyCdReadySound = true end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        end,
                        function() return ss.cdReadySoundKey == nil end,
                        AddCdrSoundPreview,
                        { searchable = true,
                          apply = { keys = { "cdReadySoundKey" },
                                    write = function(t, v)
                                        -- "None" applied bar-wide = explicitly silent.
                                        t.cdReadySoundKey = (v ~= "none" and v) or false
                                    end } })
                    -- Custom-injected spells drive their cd-state through the Fake-Active
                    -- engine, not the SetDesaturated/GetSpellCooldown edge this sound
                    -- rides, so dim the row for them (same as Cooldown State Effect above).
                    if isCustomInjected and cdReadySoundRow then
                        cdReadySoundRow:SetAlpha(0.35)
                        cdReadySoundRow:SetScript("OnEnter", function()
                            if EllesmereUI.ShowWidgetTooltip then
                                EllesmereUI.ShowWidgetTooltip(cdReadySoundRow, customDisabledTip)
                            end
                        end)
                        cdReadySoundRow:SetScript("OnLeave", function()
                            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                        end)
                    end

                    -- 5. Glow Effect Color (unified color for all glow types)
                    local GLOW_COLOR_ITEMS = {
                        { val = nil,      label = "Default" },
                        { val = "class",  label = "Class Color" },
                        { val = "custom", label = "Custom" },
                    }
                    local glowColorRow = MakeSubnavRow("Glow Effect Color", GLOW_COLOR_ITEMS,
                        function()
                            if ss.glowColor == "class" then return "class" end
                            if ss.glowColor == "custom" then return "custom" end
                            return nil
                        end,
                        function(v)
                            EnsureSS()
                            SetOwn("glowColor", v)
                            if v == "custom" and not ss.glowColorR then
                                ss.glowColorR = 1; ss.glowColorG = 0.788; ss.glowColorB = 0.137
                            end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        end,
                        function() return ss.glowColor == nil end,
                        function(si, item, sub)
                            if item.val == "custom" then
                                local swatchBtn = CreateFrame("Button", nil, si)
                                swatchBtn:SetSize(14, 14)
                                swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                swatchBtn:SetFrameLevel(si:GetFrameLevel() + 3)
                                local swatchTex = swatchBtn:CreateTexture(nil, "ARTWORK")
                                swatchTex:SetAllPoints()
                                swatchTex:SetColorTexture(
                                    ss.glowColorR or 1,
                                    ss.glowColorG or 0.788,
                                    ss.glowColorB or 0.137, 1)
                                swatchBtn:SetScript("OnClick", function()
                                    EnsureSS()
                                    ss.glowColor = "custom"
                                    if not ss.glowColorR then
                                        ss.glowColorR = 1; ss.glowColorG = 0.788; ss.glowColorB = 0.137
                                    end
                                    -- Keep the dropdown AND flyout open (OnUpdate cpOpen
                                    -- guard); re-highlight the now-selected Custom row.
                                    if sub._refreshSelection then sub._refreshSelection() end
                                    local snapR, snapG, snapB = ss.glowColorR, ss.glowColorG, ss.glowColorB
                                    local function OnPickerChanged()
                                        local popup = EllesmereUI._colorPickerPopup
                                        if not popup then return end
                                        local r, g, b = popup:GetColorRGB()
                                        ss.glowColorR = r; ss.glowColorG = g; ss.glowColorB = b
                                        swatchTex:SetColorTexture(r, g, b, 1)
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    end
                                    EllesmereUI:ShowColorPicker({
                                        r = snapR, g = snapG, b = snapB,
                                        swatchFunc = OnPickerChanged,
                                        cancelFunc = function()
                                            ss.glowColorR = snapR; ss.glowColorG = snapG; ss.glowColorB = snapB
                                        end,
                                    }, swatchBtn)
                                end)
                            end
                        end,
                        { apply = { keys = { "glowColor", "glowColorR", "glowColorG", "glowColorB" },
                                    write = function(t, v)
                                        t.glowColor = v
                                        if v == "custom" then
                                            -- Push this spell's effective color.
                                            t.glowColorR = ss.glowColorR or 1
                                            t.glowColorG = ss.glowColorG or 0.788
                                            t.glowColorB = ss.glowColorB or 0.137
                                        else
                                            t.glowColorR = nil
                                            t.glowColorG = nil
                                            t.glowColorB = nil
                                        end
                                    end } })

                    end  -- not isCustomInjected
                    end  -- isBuffBar per-icon rows

                    -- ("Sync All Bar Buttons" removed: superseded by the per-setting
                    -- "Apply to Bar / Apply to Bar (All Specs)" hover strip. Legacy
                    -- synced bars were promoted to bar-level settings by the
                    -- cdm_spell_settings_tiers_v1 migration.)

                    -- Copy to Other Specs (user Custom Spell ID / Custom Buff ID only
                    -- -- gated on the customSpellIDs tag, so racials / trinkets /
                    -- presets never show it). Placed at the COMMON rejoin point after
                    -- the buff + CD/util branches so it appears for custom IDs on any
                    -- bar type. One-time copy of this spell + its per-spell settings
                    -- onto the SAME bar in the picked specs; a spec that already has
                    -- it anywhere is skipped. Self-contained row (the branch-local
                    -- MakeActionRow helpers are out of scope here).
                    if sd.customSpellIDs and sd.customSpellIDs[spellID] then
                        -- Label flips to Remove once the spell lives on other specs.
                        local otherSpecs = (ns.SpecsWithCustomSpell and ns.SpecsWithCustomSpell(spellID)) or {}
                        local isRemove = next(otherSpecs) ~= nil
                        local copyRow = CreateFrame("Button", nil, inner)
                        copyRow:SetHeight(ITEM_H)
                        copyRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                        copyRow:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                        copyRow:SetFrameLevel(menu:GetFrameLevel() + 2)
                        local crLbl = copyRow:CreateFontString(nil, "OVERLAY")
                        crLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        crLbl:SetPoint("LEFT", 10, 0); crLbl:SetJustifyH("LEFT")
                        crLbl:SetText(EllesmereUI.L(isRemove and "Remove from Other Specs" or "Copy to Other Specs"))
                        crLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        local crHl = copyRow:CreateTexture(nil, "ARTWORK")
                        crHl:SetAllPoints(); crHl:SetColorTexture(1, 1, 1, 0); crHl:SetAlpha(0)
                        copyRow:SetScript("OnEnter", function()
                            crLbl:SetTextColor(1, 1, 1, 1)
                            crHl:SetColorTexture(1, 1, 1, hlA); crHl:SetAlpha(1)
                            if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
                        end)
                        copyRow:SetScript("OnLeave", function()
                            crLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); crHl:SetAlpha(0)
                        end)
                        copyRow:SetScript("OnClick", function()
                            menu:Hide()
                            local specs = (ns.GetCDMSpecInfo and ns.GetCDMSpecInfo()) or {}
                            local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                            if isRemove then
                                -- Remove picker: only specs that HAVE the spell are
                                -- pre-checked + selectable; the rest (and current) are
                                -- disabled. Confirm removes from the checked specs.
                                local disabled = {}
                                for _, s in ipairs(specs) do
                                    s.checked = otherSpecs[s.key] and true or false
                                    if s.key == curKey then
                                        disabled[s.key] = "You're on this spec."
                                    elseif not otherSpecs[s.key] then
                                        disabled[s.key] = "This spec doesn't have this spell."
                                    end
                                end
                                EllesmereUI:ShowCDMSpecPickerPopup({
                                    title         = "Remove from Other Specs",
                                    subtitle      = "Uncheck a spec to keep it. Confirm removes this custom spell and its settings from the checked specs.",
                                    confirmText   = "Remove",
                                    specs         = specs,
                                    disabledSpecs = disabled,
                                    onConfirm     = function(selectedSpecs)
                                        if ns.RemoveCustomSpellFromSpecs then
                                            ns.RemoveCustomSpellFromSpecs(spellID, selectedSpecs)
                                        end
                                    end,
                                })
                            else
                                local disabled
                                if curKey then disabled = { [curKey] = "You're on this spec." } end
                                EllesmereUI:ShowCDMSpecPickerPopup({
                                    title         = "Copy to Other Specs",
                                    subtitle      = "Copies this custom spell and its settings to the same bar on the specs you pick. Specs that already have it are skipped.",
                                    confirmText   = "Copy",
                                    specs         = specs,
                                    disabledSpecs = disabled,
                                    onConfirm     = function(selectedSpecs)
                                        if ns.CopyCustomSpellToSpecs then
                                            ns.CopyCustomSpellToSpecs(barKey, spellID, selectedSpecs)
                                        end
                                    end,
                                })
                            end
                        end)
                        mH = mH + ITEM_H
                    end
                end
            end

            -- Size and show
            inner:SetHeight(mH + 4)
            menu:SetSize(menuW, math.min(mH + 4, MAX_H))
            menu:ClearAllPoints()
            menu:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
            menu._anchorFrame = anchorFrame
            _spellPickerMenu = menu
            menu._openSub = nil  -- track open subnav for close checks
            menu:SetScript("OnUpdate", function(m)
                local overMenu = m:IsMouseOver() or anchorFrame:IsMouseOver()
                -- A cog flyout (Duration / Charge-Stack) drives itself through this
                -- menu, so also treat "mouse over the flyout's open dropdown menu"
                -- as over-the-sub. Without this, picking a Position option whose
                -- list extends below the flyout reads as an outside click and closes
                -- the whole menu.
                local sub = m._openSub
                local overSub = sub and sub:IsShown()
                    and (sub:IsMouseOver() or (sub._anyDropdownHovered and sub._anyDropdownHovered()))
                -- "Apply to Bar" strip: same lifecycle as a subnav flyout -- it
                -- never hides on hover-out (that made the 2px gap unreachable).
                -- It dies with its owner item: flyout closed, rebuilt, or the
                -- items reparented away (IsVisible sees through a hidden parent;
                -- IsShown would not).
                local strip = m._applyStrip
                local overStrip = strip and strip:IsShown() and strip:IsMouseOver()
                if strip and strip:IsShown() then
                    local owner = strip._ownerItem
                    if not (owner and owner:IsVisible()) then
                        strip:Hide()
                    end
                end
                -- Keep the menu open while the shared color picker is up: it's a
                -- separate popup, so interacting with it must not dismiss the
                -- menu (and its cog/subnav flyout).
                local cp = EllesmereUI._colorPickerPopup
                local cpOpen = cp and cp:IsShown()
                if not overMenu and not overSub and not overStrip and not cpOpen
                   and IsMouseButtonDown("LeftButton") then
                    m:Hide()
                end
            end)
            menu:SetScript("OnHide", function(m)
                m:SetScript("OnUpdate", nil)
                if m._openSub and m._openSub:IsShown() then m._openSub:Hide() end
                if m._applyStrip then m._applyStrip:Hide() end
            end)
            menu:Show()
            return
        end

        -- Divider after Remove Spell (only in full picker mode)
        if slotIndex then
            local div = inner:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- "Custom Spell ID" option — shown for CD/utility and custom_buff bars.
        -- Regular buff bars only show Blizzard CDM spells (no custom entry).
        if not isBuffBar then
            local csItem = CreateFrame("Button", nil, inner)
            csItem:SetHeight(ITEM_H)
            csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            csItem:SetFrameLevel(menu:GetFrameLevel() + 2)

            local csHl = csItem:CreateTexture(nil, "ARTWORK")
            csHl:SetAllPoints(); csHl:SetColorTexture(1, 1, 1, 0); csHl:SetAlpha(0)

            local csLbl = csItem:CreateFontString(nil, "OVERLAY")
            csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            csLbl:SetPoint("LEFT", 10, 0)
            csLbl:SetJustifyH("LEFT")
            csLbl:SetText(EllesmereUI.L("Custom Spell ID"))
            csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            csItem:SetScript("OnEnter", function()
                csLbl:SetTextColor(1, 1, 1, 1)
                csHl:SetColorTexture(1, 1, 1, hlA); csHl:SetAlpha(1)
            end)
            csItem:SetScript("OnLeave", function()
                csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                csHl:SetAlpha(0)
            end)
            csItem:SetScript("OnClick", function()
                menu:Hide()
                local popupName = "EUI_CDM_SpellIDPopup"
                local popup = _G[popupName]
                if not popup then
                    local POPUP_W, POPUP_H = 320, 160
                    local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
                    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
                    dimmer:SetAllPoints(UIParent)
                    dimmer:EnableMouse(true)
                    dimmer:Hide()
                    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
                    dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
                    dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

                    popup = CreateFrame("Frame", popupName, dimmer)
                    popup:SetSize(POPUP_W, POPUP_H)
                    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
                    popup:SetFrameStrata("FULLSCREEN_DIALOG")
                    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
                    popup:EnableMouse(true)
                    local popBg = popup:CreateTexture(nil, "BACKGROUND")
                    popBg:SetAllPoints(); popBg:SetColorTexture(0.06, 0.08, 0.10, 1)
                    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)

                    local title = popup:CreateFontString(nil, "OVERLAY")
                    title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
                    title:SetPoint("TOP", popup, "TOP", 0, -18)
                    title:SetTextColor(1, 1, 1, 1)
                    title:SetText(EllesmereUI.L("Add Custom Spell"))
                    popup._title = title

                    local editBox = CreateFrame("EditBox", nil, popup)
                    editBox:SetSize(180, 28)
                    editBox:SetPoint("TOP", title, "BOTTOM", 0, -16)
                    editBox:SetAutoFocus(true)
                    editBox:SetNumeric(true)
                    editBox:SetMaxLetters(7)
                    editBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
                    editBox:SetTextColor(1, 1, 1, 0.9)
                    editBox:SetJustifyH("CENTER")
                    local ebBg = editBox:CreateTexture(nil, "BACKGROUND")
                    ebBg:SetAllPoints(); ebBg:SetColorTexture(0.04, 0.06, 0.08, 1)
                    EllesmereUI.MakeBorder(editBox, 1, 1, 1, 0.12, EllesmereUI.PP)

                    local placeholder = editBox:CreateFontString(nil, "ARTWORK")
                    placeholder:SetFont(FONT_PATH, 12, GetCDMOptOutline())
                    placeholder:SetPoint("CENTER")
                    placeholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
                    placeholder:SetText(EllesmereUI.L("Spell ID"))
                    editBox:SetScript("OnTextChanged", function(self)
                        if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
                    end)
                    popup._editBox = editBox

                    local status = popup:CreateFontString(nil, "OVERLAY")
                    status:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    status:SetPoint("TOP", editBox, "BOTTOM", 0, -6)
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

                    -- Permanent red note: a manually-entered custom spell has no
                    -- live cooldown frame, so charge counts cannot be tracked.
                    -- Shown only for CD/utility bars (not custom aura bars).
                    local chargeWarn = popup:CreateFontString(nil, "OVERLAY")
                    chargeWarn:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    chargeWarn:SetPoint("LEFT", popup, "LEFT", 16, 0)
                    chargeWarn:SetPoint("RIGHT", popup, "RIGHT", -16, 0)
                    chargeWarn:SetPoint("BOTTOM", addBtn, "TOP", 0, 17)
                    chargeWarn:SetJustifyH("CENTER")
                    chargeWarn:SetTextColor(0.9, 0.3, 0.3, 1)
                    chargeWarn:SetText(EllesmereUI.L("Custom spells cannot track charges."))
                    popup._chargeWarn = chargeWarn

                    -- "Show Charges" opt-in (CD/utility custom spells): a manually
                    -- entered spell has no Blizzard charge frame, but its cast count
                    -- can still be shown on request. Replaces the old red "cannot
                    -- track charges" note for CD/utility; hidden for custom auras.
                    -- do-block so the build-time locals are released (this file has a
                    -- function at the Lua 5.1 200-local cap).
                    do
                        local wrap = CreateFrame("Button", nil, popup)
                        wrap:SetSize(16, 16)
                        wrap:SetPoint("BOTTOM", popup, "BOTTOM", -46, 60)
                        wrap:Hide()
                        local bg = wrap:CreateTexture(nil, "BACKGROUND")
                        bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.06, 0.08, 1)
                        EllesmereUI.MakeBorder(wrap, 1, 1, 1, 0.15, EllesmereUI.PP)
                        local mark = wrap:CreateTexture(nil, "ARTWORK")
                        mark:SetPoint("CENTER"); mark:SetSize(9, 9)
                        mark:SetColorTexture(ar, ag, ab, 1); mark:Hide()
                        local lbl = wrap:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        lbl:SetPoint("LEFT", wrap, "RIGHT", 6, 0)
                        lbl:SetText(EllesmereUI.L("Show Charges"))
                        lbl:SetTextColor(0.8, 0.8, 0.8, 0.9)
                        wrap:SetScript("OnClick", function()
                            popup._forceCountChecked = not popup._forceCountChecked
                            if popup._forceCountChecked then mark:Show() else mark:Hide() end
                        end)
                        popup._forceCountCheck = wrap
                        popup._forceCountMark = mark
                    end
                    popup._forceCountChecked = false

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

                    editBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)

                    local durLabel = popup:CreateFontString(nil, "OVERLAY")
                    durLabel:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    durLabel:SetPoint("TOP", editBox, "BOTTOM", 0, -32)
                    durLabel:SetTextColor(0.7, 0.7, 0.7, 0.85)
                    durLabel:SetText(EllesmereUI.L("Duration (seconds)"))
                    popup._durLabel = durLabel

                    local durBox = CreateFrame("EditBox", nil, popup)
                    durBox:SetSize(180, 28)
                    durBox:SetPoint("TOP", durLabel, "BOTTOM", 0, -6)
                    durBox:SetNumeric(true)
                    durBox:SetMaxLetters(5)
                    durBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
                    durBox:SetTextColor(1, 1, 1, 0.9)
                    durBox:SetJustifyH("CENTER")
                    local durBg = durBox:CreateTexture(nil, "BACKGROUND")
                    durBg:SetAllPoints(); durBg:SetColorTexture(0.04, 0.06, 0.08, 1)
                    EllesmereUI.MakeBorder(durBox, 1, 1, 1, 0.12, EllesmereUI.PP)
                    local durPlaceholder = durBox:CreateFontString(nil, "ARTWORK")
                    durPlaceholder:SetFont(FONT_PATH, 12, GetCDMOptOutline())
                    durPlaceholder:SetPoint("CENTER")
                    durPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
                    durPlaceholder:SetText(EllesmereUI.L("Required"))
                    durBox:SetScript("OnTextChanged", function(self)
                        if self:GetText() == "" then durPlaceholder:Show() else durPlaceholder:Hide() end
                    end)
                    durBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)
                    popup._durBox = durBox

                    popup._dimmer = dimmer
                    _G[popupName] = popup
                end

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

                local isCustomBuffPopup = isCustomBuff

                local function DoAdd()
                    local text = popup._editBox:GetText()
                    local sid = tonumber(text)
                    if not sid or sid <= 0 then
                        SetStatus("Enter a valid spell ID")
                        return
                    end
                    sid = math.floor(sid)
                    local spellName = C_Spell.GetSpellName(sid)
                    if not spellName then
                        SetStatus("Unknown spell ID")
                        return
                    end
                    -- Custom aura bars require a duration
                    local dur
                    if isCustomBuffPopup then
                        local durText = popup._durBox:GetText()
                        dur = tonumber(durText)
                        if not dur or dur <= 0 then
                            SetStatus("Enter a duration in seconds")
                            return
                        end
                        dur = math.floor(dur)
                    end
                    -- Check if already tracked
                    local sdChk = bd and ns.GetBarSpellData(bd.key)
                    if sdChk and sdChk.assignedSpells then
                        for _, existing in ipairs(sdChk.assignedSpells) do
                            if existing == sid then
                                SetStatus("Already tracked")
                                return
                            end
                        end
                    end
                    -- Store duration for custom aura bars
                    if isCustomBuffPopup and dur then
                        local sdStore = bd and ns.GetBarSpellData(bd.key)
                        if sdStore then
                            if not sdStore.spellDurations then sdStore.spellDurations = {} end
                            sdStore.spellDurations[sid] = dur
                        end
                    end
                    popup._dimmer:Hide()
                    -- Tag as custom spell so ghost bar routing can skip it
                    local sdTag = bd and ns.GetBarSpellData(bd.key)
                    if sdTag then
                        if not sdTag.customSpellIDs then sdTag.customSpellIDs = {} end
                        sdTag.customSpellIDs[sid] = true
                        -- "Show Charges" opt-in (CD/utility only; custom auras skip it).
                        -- Set/clear explicitly so a re-add with the box unchecked can't
                        -- leave a stale flag behind, and flip the runtime gate live.
                        if not isCustomBuffPopup then
                            if popup._forceCountChecked then
                                if not sdTag.customSpellForceCount then sdTag.customSpellForceCount = {} end
                                sdTag.customSpellForceCount[sid] = true
                                ns._cdmAnyCustomForceCount = true
                            elseif sdTag.customSpellForceCount then
                                sdTag.customSpellForceCount[sid] = nil
                            end
                        end
                    end
                    if onSelect then onSelect(sid, true) end
                end

                popup._addBtn:SetScript("OnClick", DoAdd)
                popup._editBox:SetScript("OnEnterPressed", DoAdd)
                popup._editBox:SetText("")
                popup._status:SetText("")
                if isCustomBuffPopup then
                    popup:SetHeight(220)
                    popup._durLabel:Show()
                    popup._durBox:Show()
                    popup._durBox:SetText("")
                    if popup._chargeWarn then popup._chargeWarn:Hide() end
                    if popup._forceCountCheck then popup._forceCountCheck:Hide() end
                else
                    popup:SetHeight(164)
                    popup._durLabel:Hide()
                    popup._durBox:Hide()
                    -- CD/utility: the old "cannot track charges" note is replaced by
                    -- the opt-in "Show Charges" toggle, reset unchecked each open.
                    if popup._chargeWarn then popup._chargeWarn:Hide() end
                    popup._forceCountChecked = false
                    if popup._forceCountMark then popup._forceCountMark:Hide() end
                    if popup._forceCountCheck then popup._forceCountCheck:Show() end
                end
                popup._dimmer:Show()
                popup._editBox:SetFocus()
            end)

            allItems[#allItems + 1] = csItem
            mH = mH + ITEM_H
        end

        -- "Custom Item ID" option -- CD/utility bars only (custom aura bars are
        -- cast-timer driven and don't render item-cooldown frames). Adds an
        -- arbitrary item by item ID, stored as a negative marker (-itemID).
        if not isBuffBar and not isCustomBuff then
            local ciItem = CreateFrame("Button", nil, inner)
            ciItem:SetHeight(ITEM_H)
            ciItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            ciItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            ciItem:SetFrameLevel(menu:GetFrameLevel() + 2)

            local ciHl = ciItem:CreateTexture(nil, "ARTWORK")
            ciHl:SetAllPoints(); ciHl:SetColorTexture(1, 1, 1, 0); ciHl:SetAlpha(0)

            local ciLbl = ciItem:CreateFontString(nil, "OVERLAY")
            ciLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            ciLbl:SetPoint("LEFT", 10, 0)
            ciLbl:SetJustifyH("LEFT")
            ciLbl:SetText(EllesmereUI.L("Custom Item ID"))
            ciLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            ciItem:SetScript("OnEnter", function()
                ciLbl:SetTextColor(1, 1, 1, 1)
                ciHl:SetColorTexture(1, 1, 1, hlA); ciHl:SetAlpha(1)
            end)
            ciItem:SetScript("OnLeave", function()
                ciLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                ciHl:SetAlpha(0)
            end)
            ciItem:SetScript("OnClick", function()
                menu:Hide()
                ShowCustomItemIDPopup(bd and bd.key, function(marker)
                    ns._cdmAnyCustomItem = true
                    if onSelect then onSelect(marker, true) end
                end)
            end)

            allItems[#allItems + 1] = ciItem
            mH = mH + ITEM_H
        end

        if false then -- misc bar custom item menu removed
            -- Bag scan + Custom Item button (moved from bottom to top)
            local BAG_ITEM_BLACKLIST = {
                [234389] = true, [234390] = true, [249699] = true,
            }
            local MIN_CD_SEC = 30
            local MAX_CD_SEC = 660
            local ITEM_PRIORITY_NAMES = {
                "Trinket Slot 1", "Trinket Slot 2", "Light's Potential",
                "Potion of Recklessness", "Silvermoon Health Potion",
                "Lightfused Mana Potion", "Healthstone",
            }
            local ITEM_PRIORITY = {}
            for i, n in ipairs(ITEM_PRIORITY_NAMES) do ITEM_PRIORITY[n:lower()] = i end

            local _candidateItems = {}
            do
                local seen = {}
                for slotIdx = 13, 14 do
                    local trinketID = GetInventoryItemID("player", slotIdx)
                    if trinketID and not seen[trinketID] and not BAG_ITEM_BLACKLIST[trinketID] then
                        seen[trinketID] = true
                        local spellName, spellID = C_Item.GetItemSpell(trinketID)
                        if spellName and spellID then
                            _candidateItems[#_candidateItems + 1] = {
                                itemID = trinketID, spellName = spellName,
                                spellID = spellID, isTrinket = slotIdx,
                            }
                            C_Item.RequestLoadItemDataByID(trinketID)
                        end
                    end
                end
                for bag = 0, 4 do
                    local numSlots = C_Container.GetContainerNumSlots(bag)
                    for slot = 1, numSlots do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.itemID and not seen[info.itemID] and not BAG_ITEM_BLACKLIST[info.itemID] then
                            seen[info.itemID] = true
                            local invType = C_Item.GetItemInventoryTypeByID(info.itemID)
                            local isTrinket = invType and invType == Enum.InventoryType.IndexTrinketType
                            if not isTrinket then
                                local spellName, spellID = C_Item.GetItemSpell(info.itemID)
                                if spellName and spellID then
                                    _candidateItems[#_candidateItems + 1] = {
                                        itemID = info.itemID, spellName = spellName, spellID = spellID,
                                    }
                                    C_Item.RequestLoadItemDataByID(info.itemID)
                                end
                            end
                        end
                    end
                end
            end

            local function ResolveBagItems()
                local results = {}
                local allResolved = true
                local _isEnglish = (GetLocale() == "enUS" or GetLocale() == "enGB")
                for _, cand in ipairs(_candidateItems) do
                    local passFilter = false
                    if cand.isTrinket then
                        passFilter = true
                    elseif _isEnglish then
                        -- English: parse tooltip for cooldown duration
                        local tipData = C_TooltipInfo.GetItemByID(cand.itemID)
                        if tipData and tipData.lines then
                            for _, line in ipairs(tipData.lines) do
                                local text = line.leftText
                                if text and text:find("Cooldown%)") then
                                    local cdStr = text:match(".*%((.+Cooldown)%)")
                                    if cdStr then
                                        local totalSec = 0
                                        for num, unit in cdStr:gmatch("(%d+)%s*(%a+)") do
                                            local n = tonumber(num)
                                            if n then
                                                local u = unit:lower()
                                                if u == "min" then totalSec = totalSec + n * 60
                                                elseif u == "sec" then totalSec = totalSec + n
                                                elseif u == "hr" or u == "hour" then totalSec = totalSec + n * 3600
                                                end
                                            end
                                        end
                                        if totalSec >= MIN_CD_SEC and totalSec <= MAX_CD_SEC then passFilter = true end
                                        break
                                    end
                                end
                            end
                        else
                            allResolved = false
                        end
                    elseif cand.spellID and cand.spellID > 0 then
                        -- Non-English: any item with a spell effect passes
                        passFilter = true
                    end
                    do
                        if passFilter then
                            local tex = C_Item.GetItemIconByID(cand.itemID)
                            local itemName = C_Item.GetItemNameByID(cand.itemID)
                            local displayName
                            if cand.isTrinket then
                                displayName = (itemName or cand.spellName) .. " (Trinket " .. (cand.isTrinket - 12) .. ")"
                            else
                                displayName = itemName or cand.spellName
                            end
                            results[#results + 1] = {
                                itemID = cand.itemID, name = displayName,
                                icon = tex, spellID = cand.spellID, isTrinket = cand.isTrinket,
                            }
                        end
                    end
                end
                local PRIORITY_COUNT = #ITEM_PRIORITY_NAMES
                table.sort(results, function(a, b)
                    local aKey = a.isTrinket and ("trinket slot " .. (a.isTrinket - 12)) or a.name:lower()
                    local bKey = b.isTrinket and ("trinket slot " .. (b.isTrinket - 12)) or b.name:lower()
                    local aPri = ITEM_PRIORITY[aKey] or (PRIORITY_COUNT + 1)
                    local bPri = ITEM_PRIORITY[bKey] or (PRIORITY_COUNT + 1)
                    if aPri ~= bPri then return aPri < bPri end
                    return a.name < b.name
                end)
                _cachedBagItems = results
                _bagScanComplete = allResolved
                return allResolved
            end
            ResolveBagItems()
            if not _bagScanComplete then
                local attempts = 0
                local ticker
                ticker = C_Timer.NewTicker(0.2, function()
                    attempts = attempts + 1
                    local done = ResolveBagItems()
                    if done or attempts >= 25 then
                        if ticker then ticker:Cancel() end
                        _bagScanComplete = true
                        if _customTrackingSub and _customTrackingSub:IsShown() then
                            _customTrackingSub._needsRebuild = true
                        end
                    elseif _customTrackingSub and _customTrackingSub:IsShown() then
                        _customTrackingSub._needsRebuild = true
                    end
                end)
                menu:HookScript("OnHide", function()
                    if ticker then ticker:Cancel(); ticker = nil end
                end)
            end

            local ctItem = CreateFrame("Button", nil, inner)
            ctItem:SetHeight(ITEM_H)
            ctItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            ctItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            ctItem:SetFrameLevel(menu:GetFrameLevel() + 2)
            local ctHl = ctItem:CreateTexture(nil, "ARTWORK")
            ctHl:SetAllPoints(); ctHl:SetColorTexture(1, 1, 1, 0); ctHl:SetAlpha(0)
            local ctLbl = ctItem:CreateFontString(nil, "OVERLAY")
            ctLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            ctLbl:SetPoint("LEFT", 10, 0); ctLbl:SetJustifyH("LEFT")
            ctLbl:SetText(EllesmereUI.L("Custom Item"))
            ctLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            local ctArrow = ctItem:CreateTexture(nil, "ARTWORK")
            ctArrow:SetSize(10, 10)
            ctArrow:SetPoint("RIGHT", ctItem, "RIGHT", -8, 0)
            ctArrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
            ctArrow:SetAlpha(0.7)

            local function ShowCustomTrackingSub()
                local items = _cachedBagItems or {}
                local alreadyTracked = {}
                local sdCT = bd and ns.GetBarSpellData(bd.key)
                if sdCT and sdCT.assignedSpells then
                    for _, sid in ipairs(sdCT.assignedSpells) do
                        if sid <= -100 then alreadyTracked[-sid] = true end
                    end
                end
                local filtered = {}
                for _, it in ipairs(items) do
                    if not alreadyTracked[it.itemID] then filtered[#filtered + 1] = it end
                end
                local prevCount = _customTrackingSub and _customTrackingSub._itemCount or -1
                if not _customTrackingSub then
                    _customTrackingSub = CreateFrame("Frame", nil, UIParent)
                    _customTrackingSub:SetFrameStrata("FULLSCREEN_DIALOG")
                    _customTrackingSub:SetFrameLevel(menu:GetFrameLevel() + 5)
                    _customTrackingSub:SetClampedToScreen(true)
                    _customTrackingSub:EnableMouse(true)
                elseif _customTrackingSub:IsShown() and #filtered == prevCount and not _customTrackingSub._needsRebuild then
                    return
                else
                    for _, child in ipairs({_customTrackingSub:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                    for _, rgn in ipairs({_customTrackingSub:GetRegions()}) do if rgn.Hide then rgn:Hide() end end
                end
                _customTrackingSub._itemCount = #filtered
                _customTrackingSub._needsRebuild = false
                local subW = 220
                local SUB_ITEM_H = 26
                local SUB_MAX_H = 260
                _customTrackingSub:SetSize(subW, 10)
                _customTrackingSub:ClearAllPoints()
                _customTrackingSub:SetPoint("TOPLEFT", ctItem, "TOPRIGHT", 2, 0)
                local subBg = _customTrackingSub:CreateTexture(nil, "BACKGROUND")
                subBg:SetAllPoints(); subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                EllesmereUI.MakeBorder(_customTrackingSub, 1, 1, 1, mBrdA, EllesmereUI.PP)
                local subInner = CreateFrame("Frame", nil, _customTrackingSub)
                subInner:SetWidth(subW); subInner:SetPoint("TOPLEFT")
                local subH = 4
                if #filtered == 0 then
                    local loadingText = (not _bagScanComplete) and "Loading items..." or "No on-use items in bags"
                    local emptyLbl = subInner:CreateFontString(nil, "OVERLAY")
                    emptyLbl:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    emptyLbl:SetPoint("TOPLEFT", subInner, "TOPLEFT", 10, -subH - 4)
                    emptyLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.6)
                    emptyLbl:SetText(loadingText)
                    subH = subH + SUB_ITEM_H
                else
                    for _, it in ipairs(filtered) do
                        local si = CreateFrame("Button", nil, subInner)
                        si:SetHeight(SUB_ITEM_H)
                        si:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -subH)
                        si:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -subH)
                        si:SetFrameLevel(_customTrackingSub:GetFrameLevel() + 2)
                        si:RegisterForClicks("AnyUp")
                        local sIco = si:CreateTexture(nil, "ARTWORK")
                        local icoSz = SUB_ITEM_H - 2
                        sIco:SetSize(icoSz, icoSz)
                        sIco:SetPoint("RIGHT", si, "RIGHT", -6, 0)
                        if it.icon then sIco:SetTexture(it.icon) end
                        sIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        local sLbl = si:CreateFontString(nil, "OVERLAY")
                        sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                        sLbl:SetPoint("RIGHT", sIco, "LEFT", -5, 0)
                        sLbl:SetJustifyH("LEFT"); sLbl:SetWordWrap(false); sLbl:SetMaxLines(1)
                        sLbl:SetText(EllesmereUI.L(it.name)); sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        local sHl = si:CreateTexture(nil, "ARTWORK")
                        sHl:SetAllPoints(); sHl:SetColorTexture(1, 1, 1, 0); sHl:SetAlpha(0)
                        si:SetScript("OnEnter", function()
                            sLbl:SetTextColor(1, 1, 1, 1); sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                        end)
                        si:SetScript("OnLeave", function()
                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); sHl:SetAlpha(0)
                        end)
                        si:SetScript("OnClick", function()
                            _customTrackingSub:Hide(); menu:Hide()
                            if onSelect then onSelect(-it.itemID, true) end
                        end)
                        subH = subH + SUB_ITEM_H
                    end
                end
                local totalSubH = subH + 4
                subInner:SetHeight(totalSubH)
                if totalSubH > SUB_MAX_H then
                    _customTrackingSub:SetHeight(SUB_MAX_H)
                    local sf = CreateFrame("ScrollFrame", nil, _customTrackingSub)
                    sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
                    sf:SetFrameLevel(_customTrackingSub:GetFrameLevel() + 1)
                    sf:EnableMouseWheel(true); sf:SetScrollChild(subInner)
                    subInner:SetWidth(subW)
                    local scrollTarget = 0
                    local maxScroll = totalSubH - SUB_MAX_H
                    local SCROLL_STEP = 40
                    local SMOOTH_SPEED = 12
                    local smoothFrame = CreateFrame("Frame")
                    smoothFrame:Hide()
                    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
                        local cur = sf:GetVerticalScroll()
                        scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
                        local diff = scrollTarget - cur
                        if math.abs(diff) < 0.3 then
                            sf:SetVerticalScroll(scrollTarget)
                            smoothFrame:Hide()
                            return
                        end
                        sf:SetVerticalScroll(cur + diff * math.min(1, SMOOTH_SPEED * elapsed))
                    end)
                    sf:SetScript("OnMouseWheel", function(_, delta)
                        if maxScroll <= 0 then return end
                        local base = smoothFrame:IsShown() and scrollTarget or sf:GetVerticalScroll()
                        scrollTarget = math.max(0, math.min(maxScroll, base - delta * SCROLL_STEP))
                        smoothFrame:Show()
                    end)
                else
                    _customTrackingSub:SetHeight(totalSubH)
                    subInner:SetParent(_customTrackingSub); subInner:SetPoint("TOPLEFT")
                end
                _customTrackingSub:SetScript("OnLeave", function(self)
                    C_Timer.After(0.1, function()
                        if self:IsShown() and not self:IsMouseOver() and not ctItem:IsMouseOver() then self:Hide() end
                    end)
                end)
                if not _bagScanComplete then
                    _customTrackingSub:SetScript("OnUpdate", function(self)
                        if self._needsRebuild then ShowCustomTrackingSub() end
                        if _bagScanComplete then self:SetScript("OnUpdate", nil) end
                    end)
                else
                    _customTrackingSub:SetScript("OnUpdate", nil)
                end
                _customTrackingSub:Show()
            end

            ctItem:SetScript("OnEnter", function()
                ctLbl:SetTextColor(1, 1, 1, 1); ctHl:SetColorTexture(1, 1, 1, hlA); ctHl:SetAlpha(1)
                ShowCustomTrackingSub()
            end)
            ctItem:SetScript("OnLeave", function()
                ctLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); ctHl:SetAlpha(0)
                C_Timer.After(0.15, function()
                    if _customTrackingSub and _customTrackingSub:IsShown()
                       and not _customTrackingSub:IsMouseOver() and not ctItem:IsMouseOver() then
                        _customTrackingSub:Hide()
                    end
                end)
            end)

            allItems[#allItems + 1] = ctItem
            mH = mH + ITEM_H
        end

        if not isBuffBar and not isCustomBuff then
            -- Divider below Custom Spell ID (CD/utility bars only —
            -- custom buff bars have their own divider before presets)
            local csDiv = inner:CreateTexture(nil, "ARTWORK")
            csDiv:SetHeight(1)
            csDiv:SetColorTexture(1, 1, 1, 0.10)
            csDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            csDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- Trinket slots + potion presets for CD/utility bars only
        -- (not buff bars, not custom buff bars)
        if not isBuffBar and not isCustomBuff then
            -- Build already-tracked set (this bar + other bars)
            local alreadyOnBar = {}
            local usedOnOtherBar = {}  -- [sid] = barName
            local sdTrk = bd and ns.GetBarSpellData(bd.key)
            if sdTrk and sdTrk.assignedSpells then
                for _, sid in ipairs(sdTrk.assignedSpells) do alreadyOnBar[sid] = true end
            end
            -- Check all other non-buff bars for cross-bar duplicate detection
            local prof = ns.ECME and ns.ECME.db and ns.ECME.db.profile
            if prof and prof.cdmBars and prof.cdmBars.bars then
                for _, otherBar in ipairs(prof.cdmBars.bars) do
                    if otherBar.key ~= barKey then
                        local otherType = otherBar.barType or otherBar.key
                        if otherType ~= "buffs" then
                            local osd = ns.GetBarSpellData(otherBar.key)
                            if osd and osd.assignedSpells then
                                for _, sid in ipairs(osd.assignedSpells) do
                                    if sid and sid ~= 0 and not usedOnOtherBar[sid] then
                                        usedOnOtherBar[sid] = otherBar.name or otherBar.key
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Trinket Slot 1 & 2
            for _, slot in ipairs({13, 14}) do
                local negSlot = -(slot)
                local itemID = GetInventoryItemID("player", slot)
                local label = EllesmereUI.L((slot == 13) and "Trinket Slot 1" or "Trinket Slot 2")
                local tex = itemID and C_Item.GetItemIconByID(itemID)
                local isAdded = alreadyOnBar[negSlot]
                -- Only gray out if it's already on THIS bar. Presets on OTHER
                -- bars stay claimable -- AddTrackedSpell auto-moves them, exactly
                -- like regular spells.
                local otherBarName = not isAdded and usedOnOtherBar[negSlot]
                local isDisabled = isAdded

                local ti = CreateFrame("Button", nil, inner)
                ti:SetHeight(ITEM_H)
                ti:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                ti:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                ti:SetFrameLevel(menu:GetFrameLevel() + 2)

                local tiLbl = ti:CreateFontString(nil, "OVERLAY")
                tiLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                tiLbl:SetPoint("LEFT", 10, 0)
                tiLbl:SetJustifyH("LEFT")
                tiLbl:SetText(label)

                if tex then
                    local tiIco = ti:CreateTexture(nil, "ARTWORK")
                    tiIco:SetSize(ITEM_H - 2, ITEM_H - 2)
                    tiIco:SetPoint("RIGHT", ti, "RIGHT", -6, 0)
                    tiIco:SetTexture(tex)
                    tiIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    if isDisabled then tiIco:SetDesaturated(true); tiIco:SetAlpha(0.4) end
                end

                local tiHl = ti:CreateTexture(nil, "ARTWORK")
                tiHl:SetAllPoints(); tiHl:SetColorTexture(1, 1, 1, 0); tiHl:SetAlpha(0)

                if isDisabled then
                    tiLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                    local tooltipName = isAdded and (bd and (bd.name or bd.key) or barKey) or otherBarName
                    ti:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(ti, EllesmereUI.Lf("Already on %s", EllesmereUI.L(tooltipName)))
                    end)
                    ti:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                else
                    tiLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    ti:SetScript("OnEnter", function()
                        tiLbl:SetTextColor(1, 1, 1, 1)
                        tiHl:SetColorTexture(1, 1, 1, hlA); tiHl:SetAlpha(1)
                    end)
                    ti:SetScript("OnLeave", function()
                        tiLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        tiHl:SetAlpha(0)
                    end)
                    ti:SetScript("OnClick", function()
                        menu:Hide()
                        EnsureAssignedSpells(barKey)
                        ns.AddTrackedSpell(barKey, negSlot)
                        RefreshCDPreview()
                    end)
                end
                allItems[#allItems + 1] = ti
                mH = mH + ITEM_H
            end

            -- Racial ability: one generic "Racial" entry that follows the
            -- character's race. Adds this character's active racial spell ID;
            -- ns.NormalizeRacialAssignments rewrites it on every other race so
            -- a shared profile only needs the racial added once.
            local rSid = ns._activeRacialSpellID
            if rSid then
                local rTex = C_Spell.GetSpellTexture(rSid)
                local isAdded = alreadyOnBar[rSid]
                local rOtherBar = not isAdded and usedOnOtherBar[rSid]
                local rIsDisabled = isAdded  -- other bars stay claimable (auto-move)
                local ri = CreateFrame("Button", nil, inner)
                ri:SetHeight(ITEM_H)
                ri:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                ri:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                ri:SetFrameLevel(menu:GetFrameLevel() + 2)
                local riLbl = ri:CreateFontString(nil, "OVERLAY")
                riLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                riLbl:SetPoint("LEFT", 10, 0)
                riLbl:SetJustifyH("LEFT")
                riLbl:SetText(EllesmereUI.L("Racial"))
                if rTex then
                    local riIco = ri:CreateTexture(nil, "ARTWORK")
                    riIco:SetSize(ITEM_H - 2, ITEM_H - 2)
                    riIco:SetPoint("RIGHT", ri, "RIGHT", -6, 0)
                    riIco:SetTexture(rTex)
                    riIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    if rIsDisabled then riIco:SetDesaturated(true); riIco:SetAlpha(0.4) end
                end
                local riHl = ri:CreateTexture(nil, "ARTWORK")
                riHl:SetAllPoints(); riHl:SetColorTexture(1, 1, 1, 0); riHl:SetAlpha(0)
                if rIsDisabled then
                    riLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                    local rTooltipName = isAdded and (bd and (bd.name or bd.key) or barKey) or rOtherBar
                    ri:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(ri, EllesmereUI.Lf("Already on %s", EllesmereUI.L(rTooltipName)))
                    end)
                    ri:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                else
                    riLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    ri:SetScript("OnEnter", function()
                        riLbl:SetTextColor(1, 1, 1, 1)
                        riHl:SetColorTexture(1, 1, 1, hlA); riHl:SetAlpha(1)
                    end)
                    ri:SetScript("OnLeave", function()
                        riLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        riHl:SetAlpha(0)
                    end)
                    ri:SetScript("OnClick", function()
                        menu:Hide()
                        EnsureAssignedSpells(barKey)
                        ns.AddTrackedSpell(barKey, rSid)
                        RefreshCDPreview()
                    end)
                end
                allItems[#allItems + 1] = ri
                mH = mH + ITEM_H
            end

            -- "Potions & Healthstone" flyout subnav
            local _potionsSub
            menu._potionsSub = nil  -- reference for OnUpdate close-check
            local itemPresets = ns.CDM_ITEM_PRESETS
            if itemPresets and #itemPresets > 0 then
                local potItem = CreateFrame("Button", nil, inner)
                potItem:SetHeight(ITEM_H)
                potItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                potItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                potItem:SetFrameLevel(menu:GetFrameLevel() + 2)

                local potHl = potItem:CreateTexture(nil, "ARTWORK")
                potHl:SetAllPoints(); potHl:SetColorTexture(1, 1, 1, 0); potHl:SetAlpha(0)

                local potLbl = potItem:CreateFontString(nil, "OVERLAY")
                potLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                potLbl:SetPoint("LEFT", 10, 0)
                potLbl:SetJustifyH("LEFT")
                potLbl:SetText(EllesmereUI.L("Potions & Healthstone"))
                potLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

                local potArrow = potItem:CreateTexture(nil, "ARTWORK")
                potArrow:SetSize(10, 10)
                potArrow:SetPoint("RIGHT", potItem, "RIGHT", -8, 0)
                potArrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
                potArrow:SetAlpha(0.7)

                local function ShowPotionsSub()
                    if not _potionsSub then
                        _potionsSub = CreateFrame("Frame", nil, menu)
                        menu._potionsSub = _potionsSub
                        _potionsSub:SetFrameStrata("FULLSCREEN_DIALOG")
                        _potionsSub:SetFrameLevel(menu:GetFrameLevel() + 5)
                        _potionsSub:SetClampedToScreen(true)
                        _potionsSub:EnableMouse(true)
                    elseif _potionsSub:IsShown() then
                        return
                    else
                        for _, child in ipairs({_potionsSub:GetChildren()}) do
                            child:Hide(); child:SetParent(nil)
                        end
                        for _, rgn in ipairs({_potionsSub:GetRegions()}) do
                            if rgn.Hide then rgn:Hide() end
                        end
                    end

                    local subW = 220
                    local SUB_ITEM_H = 26
                    _potionsSub:SetSize(subW, 10)
                    _potionsSub:ClearAllPoints()
                    _potionsSub:SetPoint("TOPLEFT", potItem, "TOPRIGHT", 2, 0)

                    local subBg = _potionsSub:CreateTexture(nil, "BACKGROUND")
                    subBg:SetAllPoints()
                    subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                    EllesmereUI.MakeBorder(_potionsSub, 1, 1, 1, mBrdA, EllesmereUI.PP)

                    local subInner = CreateFrame("Frame", nil, _potionsSub)
                    subInner:SetWidth(subW)
                    subInner:SetPoint("TOPLEFT")

                    local subH = 4
                    for _, preset in ipairs(itemPresets) do
                        do
                        local pID = -(preset.itemID)
                        local isAdded = alreadyOnBar[pID]
                        local pOtherBar = not isAdded and usedOnOtherBar[pID]
                        local pIsDisabled = isAdded  -- other bars stay claimable (auto-move)

                        local si = CreateFrame("Button", nil, subInner)
                        si:SetHeight(SUB_ITEM_H)
                        si:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -subH)
                        si:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -subH)
                        si:SetFrameLevel(_potionsSub:GetFrameLevel() + 2)
                        si:RegisterForClicks("AnyUp")

                        local sIco = si:CreateTexture(nil, "ARTWORK")
                        local icoSz = SUB_ITEM_H - 2
                        sIco:SetSize(icoSz, icoSz)
                        sIco:SetPoint("RIGHT", si, "RIGHT", -6, 0)
                        sIco:SetTexture(preset.icon or (preset.itemID and C_Item.GetItemIconByID(preset.itemID)))
                        sIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                        local sLbl = si:CreateFontString(nil, "OVERLAY")
                        sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                        sLbl:SetPoint("RIGHT", sIco, "LEFT", -5, 0)
                        sLbl:SetJustifyH("LEFT")
                        sLbl:SetWordWrap(false)
                        sLbl:SetMaxLines(1)
                        sLbl:SetText(EllesmereUI.L(preset.name))

                        local sHl = si:CreateTexture(nil, "ARTWORK")
                        sHl:SetAllPoints()
                        sHl:SetColorTexture(1, 1, 1, 0); sHl:SetAlpha(0)

                        if pIsDisabled then
                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                            sIco:SetDesaturated(true)
                            sIco:SetAlpha(0.4)
                            local pTooltipName = isAdded and (bd and (bd.name or bd.key) or barKey) or pOtherBar
                            si:SetScript("OnEnter", function()
                                EllesmereUI.ShowWidgetTooltip(si, EllesmereUI.Lf("Already on %s", EllesmereUI.L(pTooltipName)))
                            end)
                            si:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        else
                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            si:SetScript("OnEnter", function()
                                sLbl:SetTextColor(1, 1, 1, 1)
                                sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                            end)
                            si:SetScript("OnLeave", function()
                                sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                sHl:SetAlpha(0)
                            end)
                            si:SetScript("OnClick", function()
                                _potionsSub:Hide()
                                menu:Hide()
                                EnsureAssignedSpells(barKey)
                                ns.AddTrackedSpell(barKey, pID)
                                RefreshCDPreview()
                            end)
                        end
                        subH = subH + SUB_ITEM_H
                        end -- healthstone filter
                    end

                    local totalSubH = subH + 4
                    subInner:SetHeight(totalSubH)
                    _potionsSub:SetHeight(totalSubH)
                    subInner:SetParent(_potionsSub)
                    subInner:SetPoint("TOPLEFT")
                    _potionsSub:Show()
                end

                potItem:SetScript("OnEnter", function()
                    potLbl:SetTextColor(1, 1, 1, 1)
                    potHl:SetColorTexture(1, 1, 1, hlA); potHl:SetAlpha(1)
                    ShowPotionsSub()
                end)
                potItem:SetScript("OnLeave", function()
                    potLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    potHl:SetAlpha(0)
                    C_Timer.After(0.3, function()
                        if _potionsSub and _potionsSub:IsShown() and not _potionsSub:IsMouseOver() and not potItem:IsMouseOver() then
                            _potionsSub:Hide()
                        end
                    end)
                end)

                allItems[#allItems + 1] = potItem
                mH = mH + ITEM_H
            end

            -- Divider after trinkets/potions
            local trDiv = inner:CreateTexture(nil, "ARTWORK")
            trDiv:SetHeight(1)
            trDiv:SetColorTexture(1, 1, 1, 0.10)
            trDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            trDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- Presets (Heroism, potions, etc.) — flat list in custom buff bar picker
        if isCustomBuff then
            local alreadyTracked = {}
            local sdPS = bd and ns.GetBarSpellData(bd.key)
            if sdPS and sdPS.assignedSpells then
                for _, sid in ipairs(sdPS.assignedSpells) do alreadyTracked[sid] = true end
            end

            -- Divider before presets
            local psDiv = inner:CreateTexture(nil, "ARTWORK")
            psDiv:SetHeight(1)
            psDiv:SetColorTexture(1, 1, 1, 0.10)
            psDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            psDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9

            local _, _pClass = UnitClass("player")
            for _, preset in ipairs(ns.BUFF_BAR_PRESETS) do
                -- tbbOnly presets are excluded here UNLESS they opt in via
                -- customAuraToo (debuff-driven Bloodlust: rendered as a 40s
                -- self-timed icon, armed off the Sated edge instead of a cast).
                if (not preset.class or preset.class == _pClass)
                    and (not preset.tbbOnly or preset.customAuraToo) then
                    local primaryID = preset.spellIDs and preset.spellIDs[1]
                    local isAdded = primaryID and alreadyTracked[primaryID]

                    local si = CreateFrame("Button", nil, inner)
                    si:SetHeight(ITEM_H)
                    si:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    si:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    si:SetFrameLevel(menu:GetFrameLevel() + 2)

                    local sIco = si:CreateTexture(nil, "ARTWORK")
                    local icoSz = ITEM_H - 2
                    sIco:SetSize(icoSz, icoSz)
                    sIco:SetPoint("RIGHT", si, "RIGHT", -6, 0)
                    sIco:SetTexture(preset.icon)
                    sIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                    local sLbl = si:CreateFontString(nil, "OVERLAY")
                    sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                    sLbl:SetPoint("RIGHT", sIco, "LEFT", -5, 0)
                    sLbl:SetJustifyH("LEFT")
                    sLbl:SetWordWrap(false); sLbl:SetMaxLines(1)
                    sLbl:SetText(EllesmereUI.L(preset.name))

                    local sHl = si:CreateTexture(nil, "ARTWORK")
                    sHl:SetAllPoints(); sHl:SetColorTexture(1, 1, 1, 0); sHl:SetAlpha(0)

                    if isAdded then
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                        sIco:SetDesaturated(true); sIco:SetAlpha(0.4)
                    else
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        si:SetScript("OnEnter", function()
                            sLbl:SetTextColor(1, 1, 1, 1)
                            sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                        end)
                        si:SetScript("OnLeave", function()
                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            sHl:SetAlpha(0)
                        end)
                        si:SetScript("OnClick", function()
                            menu:Hide()
                            EnsureAssignedSpells(barKey)
                            ns.AddPresetToBar(barKey, preset)
                            -- Arm the shared Sated listener now (debuff-driven
                            -- presets like Bloodlust); no-op for cooldown presets.
                            if ns.UpdateLustListener then ns.UpdateLustListener() end
                            RefreshCDPreview()
                        end)
                    end

                    allItems[#allItems + 1] = si
                    mH = mH + ITEM_H
                end
            end
        end

        local function MakeItem(sp, isDisabled)
            -- Check if this spell belongs to the wrong category group for this bar type.
            local wrongCatGroup = false
            if not isDisabled and sp.cdmCatGroup then
                if isBuffBar and sp.cdmCatGroup == "cooldown" then
                    wrongCatGroup = true
                elseif not isBuffBar and sp.cdmCatGroup == "buff" then
                    wrongCatGroup = true
                end
            end
            local item = CreateFrame("Button", nil, inner)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(menu:GetFrameLevel() + 2)

            local ico = item:CreateTexture(nil, "ARTWORK")
            local icoSz = ITEM_H - 2
            ico:SetSize(icoSz, icoSz)
            ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            if sp.icon then ico:SetTexture(sp.icon) end
            local zoom = 0.08
            ico:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            lbl:SetPoint("LEFT", 10, 0)
            lbl:SetPoint("RIGHT", ico, "LEFT", -5, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            lbl:SetMaxLines(1)
            lbl:SetText(EllesmereUI.L(sp.name))

            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)

            -- Check if this spell is already on THIS bar (only gray-out we
            -- still do for CD/util/buff custom bars). Spells on OTHER bars
            -- are always claimable -- AddTrackedSpell auto-moves them.
            local onThisBar = not isDisabled and excludeSet
                and (excludeSet[sp.cdID] or excludeSet[sp.spellID])

            -- Apply the grayed "already on this bar" appearance and swap the row
            -- to its non-interactive state. Used both for spells already present
            -- when the picker opens AND for spells the user just clicked to add
            -- (the picker stays open so several can be added in a row).
            local barName = bd and (bd.name or bd.key) or barKey
            local function MarkOnThisBar()
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                ico:SetDesaturated(true)
                ico:SetAlpha(0.4)
                item:SetScript("OnClick", nil)
                item:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.Lf("This spell is already being used on %s", EllesmereUI.L(barName)))
                    hl:SetColorTexture(1, 1, 1, hlA * 0.3); hl:SetAlpha(1)
                end)
                item:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                    hl:SetAlpha(0)
                end)
            end

            if isDisabled then
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                ico:SetDesaturated(true)
                ico:SetAlpha(0.4)
            elseif onThisBar then
                -- Already on this bar: grayed out with tooltip
                MarkOnThisBar()
            else
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                -- Tracked-but-untalented spells stay fully clickable but
                -- render desaturated with a hint, so whole layouts can be
                -- arranged without swapping talents.
                local notLearned = (sp.isKnown == false)
                if notLearned then
                    ico:SetDesaturated(true)
                    ico:SetAlpha(0.5)
                end
                item:SetScript("OnEnter", function()
                    lbl:SetTextColor(1, 1, 1, 1)
                    hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                    if notLearned then
                        EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.L("Not currently talented"))
                    end
                end)
                item:SetScript("OnLeave", function()
                    lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    hl:SetAlpha(0)
                    if notLearned then EllesmereUI.HideWidgetTooltip() end
                end)
                item:SetScript("OnClick", function()
                    if wrongCatGroup then
                        menu:Hide()
                        ShowWrongBarTypePopup(sp.name, sp.cdmCatGroup == "buff")
                        return
                    end
                    -- Always pass spellID (assignedSpells stores spellIDs)
                    if onSelect then onSelect(sp.spellID, sp.isExtra) end
                    -- Keep the picker open so multiple spells can be added in a
                    -- row; gray this row in place to reflect that it was added.
                    if notLearned then EllesmereUI.HideWidgetTooltip() end
                    MarkOnThisBar()
                end)
            end

            allItems[#allItems + 1] = item
            mH = mH + ITEM_H
        end

        local function MakeDivider()
            local div = inner:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- Custom buff bars only show Custom Spell ID entry — no CDM spell list
        if isCustomBuff then
            -- Nothing to render — Custom Spell ID option is already above
        elseif isCDorUtil then
            -- Layout: Primary (unassigned first, then assigned)
            -- -> Secondary (unassigned first, then assigned)
            -- -> Not Tracked (unlearned or removed from Blizzard CDM)
            local hasPri = #priUnassigned > 0 or #priAssigned > 0
            local hasSec = #secUnassigned > 0 or #secAssigned > 0
            local hasNotTracked = #notTracked > 0
            local needDiv = false

            if hasPri then
                for _, sp in ipairs(priUnassigned) do MakeItem(sp, false) end
                for _, sp in ipairs(priAssigned) do MakeItem(sp, false) end
                needDiv = true
            end

            if hasSec then
                if needDiv then MakeDivider() end
                for _, sp in ipairs(secUnassigned) do MakeItem(sp, false) end
                for _, sp in ipairs(secAssigned) do MakeItem(sp, false) end
                needDiv = true
            end

            if hasNotTracked then
                if needDiv then MakeDivider() end
                table.sort(notTracked, function(a, b)
                    return (a.name or "") < (b.name or "")
                end)
                for _, sp in ipairs(notTracked) do MakeItem(sp, false) end
            end
        else
            -- Original layout for buff/trinket/other bars
            for _, sp in ipairs(itemsDisplayed) do MakeItem(sp, false) end

            if #itemsDisplayed > 0 and #itemsExtra > 0 then MakeDivider() end

            for _, sp in ipairs(itemsExtra) do MakeItem(sp, false) end
        end

        -- "Missing Spells?" footer: a centered, accent-colored prompt at the end
        -- of the real CDM spell sections. Clicking it opens Blizzard's CDM and
        -- closes EUI options -- the exact action of the link under the buff bar
        -- preview. Shown for bars that list Blizzard CDM spells (CD/utility and
        -- buff bars); skipped for custom-buff bars (Custom Spell ID only, no CDM
        -- list) so it never lands under the custom-spell-id / presets section.
        if not isCustomBuff then
            MakeDivider()
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
            mbFS:SetText(EllesmereUI.L("Missing Spells?") .. "\n" .. EllesmereUI.L("Add in Blizzard CDM"))

            mbItem:SetScript("OnEnter", function() mbFS:SetTextColor(1, 1, 1, 1) end)
            mbItem:SetScript("OnLeave", function()
                local r, g, b = EllesmereUI.GetAccentColor()
                mbFS:SetTextColor(r, g, b, 1)
            end)
            mbItem:SetScript("OnClick", function()
                menu:Hide()
                if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
            end)

            allItems[#allItems + 1] = mbItem
            mH = mH + FOOTER_H
        end

        local totalH = mH + 4
        inner:SetHeight(totalH)

        -- Scrollable if needed
        if totalH > MAX_H then
            menu:SetHeight(MAX_H)
            local sf = CreateFrame("ScrollFrame", nil, menu)
            sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
            sf:SetFrameLevel(menu:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            sf:SetScrollChild(inner)
            inner:SetWidth(menuW)
            local scrollTarget = 0
            local maxScroll = totalH - MAX_H
            local SCROLL_STEP = 40
            local SMOOTH_SPEED = 12
            local smoothFrame = CreateFrame("Frame")
            smoothFrame:Hide()
            smoothFrame:SetScript("OnUpdate", function(_, elapsed)
                local cur = sf:GetVerticalScroll()
                scrollTarget = max(0, min(maxScroll, scrollTarget))
                local diff = scrollTarget - cur
                if abs(diff) < 0.3 then
                    sf:SetVerticalScroll(scrollTarget)
                    smoothFrame:Hide()
                    return
                end
                sf:SetVerticalScroll(cur + diff * min(1, SMOOTH_SPEED * elapsed))
            end)
            sf:SetScript("OnMouseWheel", function(_, delta)
                if maxScroll <= 0 then return end
                local base = smoothFrame:IsShown() and scrollTarget or sf:GetVerticalScroll()
                scrollTarget = max(0, min(maxScroll, base - delta * SCROLL_STEP))
                smoothFrame:Show()
            end)
        else
            menu:SetHeight(totalH)
            inner:SetParent(menu)
            inner:SetPoint("TOPLEFT")
        end

        -- Position near anchor
        menu:ClearAllPoints()
        menu:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -2)

        -- Close on left-click outside (non-blocking, preserves world interactions)
        menu:SetScript("OnUpdate", function(m)
            local overSub = (_customTrackingSub and _customTrackingSub:IsShown() and _customTrackingSub:IsMouseOver())
                or (m._potionsSub and m._potionsSub:IsShown() and m._potionsSub:IsMouseOver())
            if not m:IsMouseOver() and not anchorFrame:IsMouseOver() and not overSub and IsMouseButtonDown("LeftButton") then
                m:Hide()
            end
        end)
        menu:HookScript("OnHide", function(m)
            m:SetScript("OnUpdate", nil)
            if _customTrackingSub then _customTrackingSub:Hide() end
            -- Per-icon cog settings for racials/pots/trinkets are edited in this
            -- menu; propagate them to synced specs when it closes.
            if ns.MaybePropagateRPT then ns.MaybePropagateRPT() end
        end)

        menu:Show()
        _spellPickerMenu = menu
        menu._anchorFrame = anchorFrame
    end

    --- Build the live CDM bar preview in the content header (interactive)
    local function BuildCDMLivePreview(parent, yOff)
        local p = DB()
        if not p or not p.cdmBars then return 0 end

        local barData = SelectedCDMBar()
        if not barData then return 0 end

        local barKey = barData.key
        local PAD = EllesmereUI.CONTENT_PAD or 10

        -- Create preview container scale to match real in-game icon sizes
        local previewScale = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
        local localParentW = (parent:GetWidth() - PAD * 2) / previewScale
        local initH = (barData.iconSize or 36) + 10

        -- Max visible height for the preview area (in parent-space pixels)
        local PREVIEW_MAX_H = 200

        -- Wrapper frame at parent scale; holds the scroll frame and scrollbar
        local wrapper = CreateFrame("Frame", nil, parent)
        wrapper:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, yOff)
        wrapper:SetSize(parent:GetWidth() - PAD * 2, PREVIEW_MAX_H)
        wrapper:SetClipsChildren(true)

        local pf = CreateFrame("Frame", nil, parent)
        pf:SetClipsChildren(false)
        pf:SetScale(previewScale)
        pf:SetSize(localParentW, initH)

        local sf = CreateFrame("ScrollFrame", nil, wrapper)
        sf:SetAllPoints()
        sf:SetScrollChild(pf)
        sf:EnableMouseWheel(true)

        -- Thin scrollbar track (4px, right side)
        local pvTrack = CreateFrame("Frame", nil, wrapper)
        pvTrack:SetWidth(4)
        pvTrack:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT", -2, -2)
        pvTrack:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", -2, 2)
        pvTrack:SetFrameLevel(wrapper:GetFrameLevel() + 5)
        do
            local bg = pvTrack:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.02)
        end
        pvTrack:Hide()

        local pvThumb = CreateFrame("Button", nil, pvTrack)
        pvThumb:SetWidth(4)
        pvThumb:SetFrameLevel(pvTrack:GetFrameLevel() + 1)
        pvThumb:EnableMouse(true)
        pvThumb:RegisterForDrag("LeftButton")
        pvThumb:SetScript("OnDragStart", function() end)
        pvThumb:SetScript("OnDragStop", function() end)
        do
            local t = pvThumb:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetColorTexture(1, 1, 1, 0.27)
        end

        -- Smooth scroll state
        local pvScrollTarget = 0
        local pvSmoothing = false
        local PV_SCROLL_STEP = 40
        local PV_SMOOTH_SPEED = 12
        local pvSmoothFrame = CreateFrame("Frame")
        pvSmoothFrame:Hide()

        local function UpdatePVThumb()
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            if maxScroll <= 0 then pvTrack:Hide(); return end
            pvTrack:Show()
            local trackH = pvTrack:GetHeight()
            local visH = sf:GetHeight()
            local ratio = visH / (visH + maxScroll)
            local thumbH = math.max(20, trackH * ratio)
            pvThumb:SetHeight(thumbH)
            local curScroll = 0
            do
                local ok, val = pcall(sf.GetVerticalScroll, sf)
                if ok and val then
                    local ok2, n = pcall(tonumber, val)
                    if ok2 and n then curScroll = n end
                end
            end
            local scrollRatio = curScroll / maxScroll
            local maxTravel = trackH - thumbH
            pvThumb:ClearAllPoints()
            pvThumb:SetPoint("TOP", pvTrack, "TOP", 0, -(scrollRatio * maxTravel))
        end

        pvSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
            local cur = sf:GetVerticalScroll()
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            pvScrollTarget = math.max(0, math.min(maxScroll, pvScrollTarget))
            local diff = pvScrollTarget - cur
            if math.abs(diff) < 0.3 then
                sf:SetVerticalScroll(pvScrollTarget)
                UpdatePVThumb()
                pvSmoothing = false
                pvSmoothFrame:Hide()
                return
            end
            local newScroll = cur + diff * math.min(1, PV_SMOOTH_SPEED * elapsed)
            newScroll = math.max(0, math.min(maxScroll, newScroll))
            sf:SetVerticalScroll(newScroll)
            UpdatePVThumb()
        end)

        local function PVSmoothScrollTo(target)
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            pvScrollTarget = math.max(0, math.min(maxScroll, target))
            if not pvSmoothing then
                pvSmoothing = true
                pvSmoothFrame:Show()
            end
        end

        sf:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = EllesmereUI.SafeScrollRange(self)
            if maxScroll <= 0 then return end
            local base = pvSmoothing and pvScrollTarget or self:GetVerticalScroll()
            PVSmoothScrollTo(base - delta * PV_SCROLL_STEP)
        end)
        sf:SetScript("OnScrollRangeChanged", UpdatePVThumb)

        -- Thumb drag
        pvThumb:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            pvSmoothing = false
            pvSmoothFrame:Hide()
            local _, cursorY = GetCursorPosition()
            local dragStartY = cursorY / self:GetEffectiveScale()
            local dragStartScroll = sf:GetVerticalScroll()
            self:SetScript("OnUpdate", function(self2)
                if not IsMouseButtonDown("LeftButton") then
                    self2:SetScript("OnUpdate", nil)
                    return
                end
                local _, cy = GetCursorPosition()
                cy = cy / self2:GetEffectiveScale()
                local deltaY = dragStartY - cy
                local trackH = pvTrack:GetHeight()
                local maxTravel = trackH - self2:GetHeight()
                if maxTravel <= 0 then return end
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
                local newScroll = math.max(0, math.min(maxScroll,
                    dragStartScroll + (deltaY / maxTravel) * maxScroll))
                pvScrollTarget = newScroll
                sf:SetVerticalScroll(newScroll)
                UpdatePVThumb()
            end)
        end)
        pvThumb:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            self:SetScript("OnUpdate", nil)
        end)

        -- Store refs for height management after Update()
        pf._wrapper = wrapper
        pf._scrollFrame = sf
        pf._previewScale = previewScale
        pf._PREVIEW_MAX_H = PREVIEW_MAX_H
        pf._updatePVThumb = UpdatePVThumb

        -- Pixel-snap helper for the preview's effective scale
        local function Snap(val)
            local s = pf:GetEffectiveScale()
            return math.floor(val * s + 0.5) / s
        end

        -- Bar background texture (shown when barBgEnabled)
        local pvBarBg = pf:CreateTexture(nil, "BACKGROUND", nil, -8)
        pvBarBg:SetColorTexture(0, 0, 0, 0.4)  -- default; updated in refresh
        if pvBarBg.SetSnapToPixelGrid then pvBarBg:SetSnapToPixelGrid(false); pvBarBg:SetTexelSnappingBias(0) end
        pvBarBg:Hide()

        -- Interactive preview icon slots
        local MAX_PREVIEW_ICONS = 30
        local previewSlots = {}

        -- Display-only dedupe for buff bars. A buff bar's assignedSpells can hold a
        -- LEGACY duplicate: the SAME tracked buff stored under two different spell ids
        -- (e.g. its spellID and one of its linkedSpellIDs) left over from the pre-fix
        -- live-icon append. They are NOT base/override variants -- the link is that
        -- both ids resolve to the same Blizzard cooldownID. BOTH ids must stay in the
        -- data (routing depends on them), so we collapse them in the PREVIEW only:
        -- one slot per cooldownID, remembering which assignedSpells index/indices each
        -- slot covers (for edit + remove). With no dupes (every bar after the append
        -- fix) this returns the raw list 1:1, so the preview behaves exactly as before.
        --
        -- spellID -> cooldownID is a function of the player's talents, so it is stable
        -- per spec: build it ONCE per spec from the static category sets (which list
        -- every tracked cooldown's spellID + overrideSpellID + linkedSpellIDs, covering
        -- buffs that are currently down too) and reuse it across refreshes. It is a
        -- private local fed ONLY into the dedupe below -- nothing here writes
        -- assignedSpells, the route map, or any live frame, so real bars are untouched,
        -- and the scan never runs during gameplay (pf.Update only runs with options open).
        local _buffIdToCd, _buffIdToCdSpec = nil, nil
        local function GetBuffIdToCdid()
            local specKey = (ns.GetActiveSpecKey and ns.GetActiveSpecKey()) or "?"
            if _buffIdToCdSpec == specKey then return _buffIdToCd end
            _buffIdToCdSpec = specKey
            local map
            local gcs = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
            local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
            if gcs and gci then
                for cat = 0, 3 do
                    local ids = gcs(cat, true)
                    if ids then
                        for _, cdID in ipairs(ids) do
                            local info = gci(cdID)
                            if info then
                                map = map or {}
                                if type(info.spellID) == "number" and info.spellID > 0 then map[info.spellID] = cdID end
                                if type(info.overrideSpellID) == "number" and info.overrideSpellID > 0 then map[info.overrideSpellID] = cdID end
                                if info.linkedSpellIDs then
                                    for _, l in ipairs(info.linkedSpellIDs) do
                                        if type(l) == "number" and l > 0 then map[l] = cdID end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            _buffIdToCd = map
            return map
        end

        local function BuildBuffDisplayDedup(raw)
            local idToCd = GetBuffIdToCdid()
            local dispList, dispGroups, slotOf = {}, {}, {}
            for rawIdx = 1, #raw do
                local sid = raw[rawIdx]
                -- Group by cooldownID when the id maps to a tracked buff; otherwise the
                -- entry stands alone (its own slot, keyed by the spell id).
                local cd = idToCd and idToCd[sid]
                local key = cd or ("s" .. tostring(sid))
                local at = slotOf[key]
                if at then
                    local g = dispGroups[at]; g[#g + 1] = rawIdx
                else
                    dispList[#dispList + 1] = sid
                    dispGroups[#dispList] = { rawIdx }
                    slotOf[key] = #dispList
                end
            end
            return dispList, dispGroups
        end

        -- Preview display index -> underlying assignedSpells index for buff bars
        -- that collapsed a duplicate (identity when there are no dupes / not a buff bar).
        local function BuffDataIdx(displayIdx)
            local g = pf._buffDispGroups and pf._buffDispGroups[displayIdx]
            return (g and g[1]) or displayIdx
        end

        -- Drag state
        local dragSlot, dragIdx, dragGhost
        local insertIdx = nil
        local lastInsertIdx = nil
        local dragMode = nil      -- "swap" or "insert"
        local swapTargetIdx = nil -- index of icon being swapped with
        local dragEndTime = 0 -- GetTime() when drag finished, suppresses OnClick

        local function EnsureDragGhost()
            if dragGhost then return dragGhost end
            local g = CreateFrame("Frame", nil, UIParent)
            g:SetFrameStrata("TOOLTIP")
            g:SetSize(36, 36)
            g:SetAlpha(0.7)
            local tex = g:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            g._icon = tex
            g:Hide()
            dragGhost = g
            return g
        end

        -- Insertion line indicator (vertical accent line between icons)
        local insertLine = pf:CreateTexture(nil, "OVERLAY", nil, 7)
        local eg = EllesmereUI.ELLESMERE_GREEN
        insertLine:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
        insertLine:SetWidth(2)
        insertLine:Hide()

        -- Animation: each slot has _targetOffX, _currentOffX; lerped inside drag OnUpdate
        local ANIM_SPEED = 48
        local animRunning = false

        local function StopAnimTicker()
            animRunning = false
        end

        local function StartAnimTicker()
            animRunning = true
        end

        local function TickAnimation(dt)
            if not animRunning then return end
            local allDone = true
            for i = 1, MAX_PREVIEW_ICONS do
                local s = previewSlots[i]
                if s and s._targetOffX and s._currentOffX then
                    local diff = s._targetOffX - s._currentOffX
                    if math.abs(diff) < 0.3 then
                        s._currentOffX = s._targetOffX
                    else
                        s._currentOffX = s._currentOffX + diff * math.min(ANIM_SPEED * dt, 1)
                        allDone = false
                    end
                    if s._baseX then
                        s:ClearAllPoints()
                        PP.Point(s, "TOPLEFT", pf, "TOPLEFT", s._baseX + s._currentOffX, s._baseY)
                    end
                end
            end
            if allDone then animRunning = false end
        end

        local function ClearInsertIndicator()
            insertLine:Hide()
            insertIdx = nil
            lastInsertIdx = nil
            -- Clear swap highlight
            if swapTargetIdx then
                local s = previewSlots[swapTargetIdx]
                if s and s._hlBrd then
                    s._hlBrd:Hide()
                end
                swapTargetIdx = nil
            end
            dragMode = nil
            -- Reset all slot offsets (snap, no animation)
            StopAnimTicker()
            for i = 1, MAX_PREVIEW_ICONS do
                local s = previewSlots[i]
                if s and s._baseX then
                    s._targetOffX = 0
                    s._currentOffX = 0
                    s:ClearAllPoints()
                    PP.Point(s, "TOPLEFT", pf, "TOPLEFT", s._baseX, s._baseY)
                end
            end
        end

        --- Find drag target: swap (centered on icon) or insert (between icons)
        --- Returns mode ("swap"/"insert"), targetIdx
        --- cx, cy are in screen units (GetCursorPosition / UIParent:GetEffectiveScale)
        local function FindDragTarget(cx, cy, slotCount, fromIdx)
            local bd = SelectedCDMBar()
            if not bd then return nil, nil end
            local iconSz = bd.iconSize or 36
            -- Match the preview render: width-matched bars show 32px icons.
            if EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget("CDM_" .. bd.key) then iconSz = 36 end
            local spacing = bd.spacing or 2
            -- Preview always renders left-to-right regardless of bar growDirection,
            -- so drag logic must also use left-to-right ordering.
            local growLeft = false

            -- Convert cursor from screen units to pf-local units
            local pfES = pf:GetEffectiveScale()
            local uiES = UIParent:GetEffectiveScale()
            local rawCX = cx * uiES
            local rawCY = cy * uiES
            local rawPfL = pf:GetLeft() * pfES
            local rawPfT = pf:GetTop() * pfES
            local localX = (rawCX - rawPfL) / pfES
            local localY = -((rawPfT - rawCY) / pfES)

            -- Group slots into rows by _baseY
            local bestRowStart, bestRowEnd, bestRowDist = 1, slotCount, math.huge
            local rowsByY = {}
            for i = 1, slotCount do
                local s = previewSlots[i]
                if s and s:IsShown() and s._baseY then
                    local yKey = math.floor(s._baseY * 10 + 0.5)
                    if not rowsByY[yKey] then rowsByY[yKey] = { y = s._baseY, startIdx = i, endIdx = i }
                    else rowsByY[yKey].endIdx = i end
                end
            end
            for _, row in pairs(rowsByY) do
                local rowCenterY = row.y - iconSz / 2
                local d = math.abs(localY - rowCenterY)
                if d < bestRowDist then
                    bestRowDist = d; bestRowStart = row.startIdx; bestRowEnd = row.endIdx
                end
            end

            -- Check Y range
            local refSlot = previewSlots[bestRowStart]
            if not refSlot or not refSlot:IsShown() or not refSlot._baseY then return nil, nil end
            if localY > refSlot._baseY + iconSz * 0.5 or localY < refSlot._baseY - iconSz * 1.5 then return nil, nil end

            -- Build a list of slots in this row sorted by visual X (left to right on screen).
            -- With growLeft, slot indices are reversed relative to screen X order.
            local rowSlots = {}
            for i = bestRowStart, bestRowEnd do
                local s = previewSlots[i]
                if s and s:IsShown() and s._baseX then
                    rowSlots[#rowSlots + 1] = { slot = s, idx = i }
                end
            end
            -- Sort by _baseX ascending (left to right on screen)
            table.sort(rowSlots, function(a, b) return a.slot._baseX < b.slot._baseX end)

            local swapZone = iconSz * 0.2
            local blankSwapZone = iconSz * 0.45

            -- If cursor is before the leftmost slot on screen, insert at the logical start of that side
            local firstEntry = rowSlots[1]
            if firstEntry and localX < firstEntry.slot._baseX - spacing * 0.5 then
                if growLeft then
                    return "insert", firstEntry.idx + 1
                else
                    return "insert", firstEntry.idx
                end
            end

            for vi = 1, #rowSlots do
                local entry = rowSlots[vi]
                local s = entry.slot
                local i = entry.idx
                local slotL = s._baseX
                local slotR = slotL + iconSz
                local slotCX = slotL + iconSz / 2
                local isBlank = not s._icon or not s._icon:GetTexture()
                local zone = isBlank and blankSwapZone or swapZone
                if localX >= slotL - spacing * 0.5 and localX < slotR + spacing * 0.5 then
                    if i ~= fromIdx and math.abs(localX - slotCX) < zone then
                        return "swap", i
                    elseif localX < slotCX then
                        -- Cursor is in the left half of this slot � insert before it logically
                        if growLeft then
                            return "insert", i + 1
                        else
                            return "insert", i
                        end
                    else
                        -- Cursor is in the right half of this slot � insert after it logically
                        if growLeft then
                            return "insert", i
                        else
                            return "insert", i + 1
                        end
                    end
                end
            end

            -- Past the rightmost slot on screen: insert at the logical end of that side
            local lastEntry = rowSlots[#rowSlots]
            if lastEntry then
                if growLeft then
                    return "insert", lastEntry.idx
                else
                    return "insert", lastEntry.idx + 1
                end
            end
            return "insert", bestRowEnd + 1
        end

        --- Apply visual feedback for drag: shift icons for insert, highlight for swap
        local function ApplyDragFeedback(mode, targetIdx, fromIdx, slotCount)
            local bd = SelectedCDMBar()
            -- Preview always renders left-to-right; drag feedback must match.
            local growLeft = false

            if mode == "swap" then
                insertLine:Hide()
                if swapTargetIdx and swapTargetIdx ~= targetIdx then
                    local s = previewSlots[swapTargetIdx]
                    if s and s._hlBrd then s._hlBrd:Hide() end
                end
                if lastInsertIdx then
                    for i = 1, slotCount do
                        local s = previewSlots[i]
                        if s and s._baseX then
                            s._targetOffX = 0
                            if not s._currentOffX then s._currentOffX = 0 end
                            if i ~= fromIdx then s:SetAlpha(1) end
                        end
                    end
                    StartAnimTicker()
                    lastInsertIdx = nil
                end
                swapTargetIdx = targetIdx
                local s = previewSlots[targetIdx]
                if s and s._hlBrd then s._hlBrd:Show() end
                return
            end

            -- Insert mode: clear swap highlight first
            if swapTargetIdx then
                local s = previewSlots[swapTargetIdx]
                if s and s._hlBrd then s._hlBrd:Hide() end
                swapTargetIdx = nil
            end

            if targetIdx == lastInsertIdx then return end
            lastInsertIdx = targetIdx

            if not bd then return end
            local iconSz = bd.iconSize or 36
            -- Match the preview render: width-matched bars show 32px icons.
            if EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget("CDM_" .. bd.key) then iconSz = 36 end
            local spacing = bd.spacing or 2
            local nudge = math.floor((iconSz + spacing) * 0.15)

            -- With growLeft, higher index = further left on screen.
            -- Flip nudge direction so slots shift away from the gap correctly.
            local shiftTowardEnd   =  nudge
            local shiftTowardStart = -nudge
            if growLeft then
                shiftTowardEnd   = -nudge
                shiftTowardStart =  nudge
            end

            -- Determine which row the target belongs to (by _baseY).
            -- Only shift slots on that row; other rows stay still.
            local targetRowY = nil
            if targetIdx >= 1 and targetIdx <= slotCount then
                local ts = previewSlots[targetIdx]
                if ts and ts._baseY then targetRowY = ts._baseY end
            end
            -- Fallback: check the slot just before targetIdx (insert at end of row)
            if not targetRowY and targetIdx > 1 and targetIdx - 1 <= slotCount then
                local ts = previewSlots[targetIdx - 1]
                if ts and ts._baseY then targetRowY = ts._baseY end
            end

            for i = 1, slotCount do
                local s = previewSlots[i]
                if not s or not s._baseX then
                    if s then s:SetAlpha(i == fromIdx and 0.3 or 1) end
                elseif i == fromIdx then
                    s:SetAlpha(0.3)
                    s._targetOffX = 0
                    if not s._currentOffX then s._currentOffX = 0 end
                else
                    -- Only shift slots on the same row as the target
                    local onTargetRow = targetRowY and s._baseY and math.abs(s._baseY - targetRowY) < 1
                    if not onTargetRow then
                        s._targetOffX = 0
                        if not s._currentOffX then s._currentOffX = 0 end
                        s:SetAlpha(1)
                    else
                        local virtualPos = i
                        if i > fromIdx then virtualPos = i - 1 end
                        local virtualInsert = targetIdx
                        if targetIdx > fromIdx then virtualInsert = targetIdx - 1 end

                        local offX = 0
                        if virtualPos >= virtualInsert then
                            offX = shiftTowardEnd
                        else
                            offX = shiftTowardStart
                        end

                        s._targetOffX = offX
                        if not s._currentOffX then s._currentOffX = 0 end
                        s:SetAlpha(1)
                    end
                end
            end
            StartAnimTicker()

            -- Position the insertion line between the two logical neighbors
            if targetIdx and targetIdx >= 1 then
                local iconSz2 = iconSz
                local leftSlot, rightSlot  -- screen-left, screen-right
                if growLeft then
                    -- With growLeft, slot targetIdx is to the right on screen, slot targetIdx-1 is to the left
                    if targetIdx > 1 and targetIdx <= slotCount then
                        rightSlot = previewSlots[targetIdx]
                        leftSlot  = previewSlots[targetIdx - 1]
                        if targetIdx == fromIdx and targetIdx + 1 <= slotCount then
                            rightSlot = previewSlots[targetIdx + 1]
                        elseif targetIdx - 1 == fromIdx and targetIdx - 2 >= 1 then
                            leftSlot = previewSlots[targetIdx - 2]
                        end
                    elseif targetIdx <= 1 then
                        rightSlot = previewSlots[1]
                    elseif targetIdx > slotCount then
                        leftSlot = previewSlots[slotCount]
                    end
                else
                    if targetIdx > 1 and targetIdx <= slotCount then
                        leftSlot  = previewSlots[targetIdx - 1]
                        rightSlot = previewSlots[targetIdx]
                        if targetIdx - 1 == fromIdx and targetIdx - 2 >= 1 then
                            leftSlot = previewSlots[targetIdx - 2]
                        elseif targetIdx == fromIdx and targetIdx + 1 <= slotCount then
                            rightSlot = previewSlots[targetIdx + 1]
                        end
                    elseif targetIdx <= 1 then
                        rightSlot = previewSlots[1]
                    elseif targetIdx > slotCount and slotCount > 0 then
                        leftSlot = previewSlots[slotCount]
                    end
                end

                local lineX, lineY
                if leftSlot and leftSlot:IsShown() and leftSlot._baseX
                   and rightSlot and rightSlot:IsShown() and rightSlot._baseX then
                    local leftRight = leftSlot._baseX + iconSz2 - nudge
                    local rightLeft = rightSlot._baseX + nudge
                    lineX = (leftRight + rightLeft) / 2
                    lineY = rightSlot._baseY
                elseif rightSlot and rightSlot:IsShown() and rightSlot._baseX then
                    lineX = rightSlot._baseX + nudge - math.floor(spacing / 2) - 1
                    lineY = rightSlot._baseY
                elseif leftSlot and leftSlot:IsShown() and leftSlot._baseX then
                    lineX = leftSlot._baseX + iconSz2 - nudge + math.floor(spacing / 2) + 1
                    lineY = leftSlot._baseY
                end

                if lineX and lineY then
                    insertLine:ClearAllPoints()
                    PP.Point(insertLine, "TOP", pf, "TOPLEFT", lineX, lineY)
                    PP.Point(insertLine, "BOTTOM", pf, "TOPLEFT", lineX, lineY - iconSz2)
                    insertLine:Show()
                else
                    insertLine:Hide()
                end
            else
                insertLine:Hide()
            end
        end

        -- Ensure assignedSpells is populated from live icons if empty.
        -- ONLY writes if live icons actually has spells (prevents wiping
        -- to empty array when no buffs are active).
        -- EnsureAssignedSpells is defined above ShowSpellPicker

        local function CreatePreviewSlot(idx)
            local slot = CreateFrame("Button", nil, pf)
            slot:SetSize(1, 1)
            slot:RegisterForClicks("LeftButtonUp", "RightButtonDown", "MiddleButtonDown")
            -- Expand hit area so small icons are easier to click/drag
            slot:SetHitRectInsets(-6, -6, -6, -6)
            slot:Hide()

            local sBg = slot:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints(); sBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
            if sBg.SetSnapToPixelGrid then sBg:SetSnapToPixelGrid(false); sBg:SetTexelSnappingBias(0) end
            slot._bg = sBg

            local sIcon = slot:CreateTexture(nil, "ARTWORK")
            sIcon:SetAllPoints()
            if sIcon.SetSnapToPixelGrid then sIcon:SetSnapToPixelGrid(false); sIcon:SetTexelSnappingBias(0) end
            slot._icon = sIcon
            slot._tex = sIcon  -- alias for shape system compatibility

            local sEdges = {}
            local PP = EllesmereUI and EllesmereUI.PP
            if PP then PP.CreateBorder(slot, 0, 0, 0, 1, 1, "OVERLAY", 7) end
            slot._edges = sEdges  -- empty; borders managed by PP

            -- Hosted-buff marker border: gold (same color as the buff "+" add
            -- button), same 2px geometry as the hover highlight, always ON for
            -- buff icons hosted on this CD/utility bar so they read apart from
            -- the cooldowns at a glance. Level +1 -- UNDER the hover highlight
            -- (+2), so hovering still shows the accent border on top.
            local slotPP = EllesmereUI and EllesmereUI.PP
            local slotHostCont = CreateFrame("Frame", nil, slot)
            slotHostCont:SetAllPoints()
            slotHostCont:SetFrameLevel(slot:GetFrameLevel() + 1)
            local hostBrd = slotPP and slotPP.CreateBorder(slotHostCont, 1, 0.82, 0.25, 1, 2, "OVERLAY", 7)
            if hostBrd then hostBrd:Hide() end
            slot._hostBrd = hostBrd
            -- Hover highlight (2px accent border, child container avoids conflict with existing PP border)
            local eg = EllesmereUI.ELLESMERE_GREEN
            local slotHlCont = CreateFrame("Frame", nil, slot)
            slotHlCont:SetAllPoints()
            slotHlCont:SetFrameLevel(slot:GetFrameLevel() + 2)
            local slotBrd = slotPP and slotPP.CreateBorder(slotHlCont, eg.r, eg.g, eg.b, 1, 2, "OVERLAY", 7)
            if slotBrd then slotBrd:Hide() end
            slot._hlBrd = slotBrd
            -- Text overlay (renders above border)
            local pvTextOvr = CreateFrame("Frame", nil, slot)
            pvTextOvr:SetAllPoints(slot)
            pvTextOvr:SetFrameLevel(slot:GetFrameLevel() + 3)
            pvTextOvr:EnableMouse(false)
            slot._pvTextOverlay = pvTextOvr

            slot._stackText = pvTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(slot._stackText, FONT_PATH, 11)
            slot._stackText:SetPoint("BOTTOMRIGHT", pvTextOvr, "BOTTOMRIGHT", 0, 2)
            slot._stackText:SetJustifyH("RIGHT")
            slot._stackText:Hide()
            local stackTxt = slot._stackText

            -- Keybind text (mirrors _keybindText on real CDM icons)
            local kbTxt = pvTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(kbTxt, FONT_PATH, 9)
            kbTxt:SetPoint("TOPLEFT", pvTextOvr, "TOPLEFT", 2, -2)
            kbTxt:SetJustifyH("LEFT")
            kbTxt:Hide()
            slot._keybindText = kbTxt

            slot:SetScript("OnEnter", function()
                if dragSlot then return end
                local bdHov = SelectedCDMBar()
                -- Custom shapes: tint the shape border instead of square edges
                if slot._shapeBorder and slot._shapeBorder:IsShown() then
                    slot._shapeBorder:SetVertexColor(eg.r, eg.g, eg.b, 1)
                else
                    if slotBrd then slotBrd:Show() end
                end
            end)
            slot:SetScript("OnLeave", function()
                if dragSlot then return end
                local bdHov = SelectedCDMBar()
                if slot._shapeBorder and slot._shapeBorder:IsShown() then
                    if slot._previewHostedBuff then
                        -- Hosted buff: restore the persistent gold tint, not
                        -- the bar border color.
                        slot._shapeBorder:SetVertexColor(1, 0.82, 0.25, 1)
                    else
                        local bR, bG, bB = 0, 0, 0
                        if bdHov then
                            bR, bG, bB = bdHov.borderR or 0, bdHov.borderG or 0, bdHov.borderB or 0
                            if bdHov.borderClassColor then
                                local _, ct = UnitClass("player")
                                if ct then
                                    local cc = RAID_CLASS_COLORS[ct]
                                    if cc then bR, bG, bB = cc.r, cc.g, cc.b end
                                end
                            end
                        end
                        slot._shapeBorder:SetVertexColor(bR, bG, bB, 1)
                    end
                else
                    if slotBrd then slotBrd:Hide() end
                end
            end)

            slot._slotIdx = idx

            -- Right-click: spell picker to replace; Middle-click: remove
            -- Default buff bar: no interaction (Blizzard controls the list)
            slot:SetScript("OnClick", function(self, button)
                if GetTime() - dragEndTime < 0.2 then
                    return
                end
                -- Override editing sessions: per-spell settings and spell
                -- placement are never part of the override system -- refuse
                -- the interaction with an explanatory tooltip.
                if EllesmereUI.SpecOverrides_EditSessionActive
                   and EllesmereUI.SpecOverrides_EditSessionActive() then
                    if EllesmereUI.ShowWidgetTooltip then
                        EllesmereUI.ShowWidgetTooltip(self,
                            "Per-spell settings are not part of the override system.")
                    end
                    return
                end
                local bd = SelectedCDMBar()
                if not bd then return end
                local isDefaultBuffs = (bd.key == "buffs")

                if button == "MiddleButton" then
                    local si = self._slotIdx
                    -- A per-icon settings dropdown may be open (anchored to this or
                    -- another slot). A remove reshuffles the preview slots, so any
                    -- open dropdown is about to point at the wrong spell -- close it.
                    if _spellPickerMenu and _spellPickerMenu:IsShown() then
                        _spellPickerMenu:Hide()
                    end
                    if isDefaultBuffs then
                        -- Custom item slot (negative -itemID marker): remove it
                        -- directly. slotIndex maps to the mixed preview list, so
                        -- key off the marker, not assignedSpells[si].
                        if self._previewItemID then
                            ns.RemoveSpellFromBar(bd.key, -self._previewItemID)
                            if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                            RefreshCDPreview()
                            return
                        end
                        -- Main buffs bar: only injected custom/preset buffs can be
                        -- deleted (Blizzard-tracked buffs are managed in Blizzard's
                        -- CDM). Remove by spellID since slotIndex maps to the mixed
                        -- preview list (Blizzard buffs + customs), not assignedSpells.
                        local sid = self._previewSpellID
                        if not sid then return end
                        local sdMid = ns.GetBarSpellData(bd.key)
                        local isInj = sdMid and (
                            (sdMid.spellDurations and (sdMid.spellDurations[sid] or 0) > 0)
                            or (sdMid.customSpellIDs and sdMid.customSpellIDs[sid]))
                        if not isInj then return end
                        ns.RemoveSpellFromBar(bd.key, sid)
                        if sdMid.spellDurations then sdMid.spellDurations[sid] = nil end
                        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                        if ns.QueueReanchor then ns.QueueReanchor() end
                        RefreshCDPreview()
                        return
                    end
                    local sdMid = EnsureAssignedSpells(bd.key)
                    if not sdMid or not sdMid.assignedSpells then return end
                    local t = sdMid.assignedSpells
                    -- Remove every assignedSpells entry collapsed into this preview
                    -- slot. A legacy duplicate buff maps >1 stored id to one slot;
                    -- a normal slot maps exactly one (so this is the plain remove).
                    -- Highest index first keeps the lower indices valid across removes.
                    local grp = (pf._buffDispGroups and pf._buffDispGroups[si]) or { si }
                    local order = {}
                    for _, v in ipairs(grp) do order[#order + 1] = v end
                    table.sort(order, function(a, b) return a > b end)
                    local removedAny = false
                    for _, idx in ipairs(order) do
                        if t[idx] and t[idx] ~= 0 then
                            ns.RemoveTrackedSpell(bd.key, idx)
                            removedAny = true
                        end
                    end
                    if not removedAny then return end
                    RefreshCDPreview()
                elseif button == "RightButton" or button == "LeftButton" then
                    local si = self._slotIdx
                    -- Custom item slots (default buffs bar) have no per-icon
                    -- settings and don't map to assignedSpells[si]; middle-click
                    -- removes them. Ignore left/right-click to avoid a mis-indexed
                    -- settings menu.
                    if isDefaultBuffs and self._previewItemID then return end
                    -- Translate the preview slot to its underlying assignedSpells
                    -- index (identity unless this buff slot collapsed a duplicate).
                    local dataIdx = BuffDataIdx(si)
                    -- A slot is configurable if it maps to an assignedSpells entry
                    -- OR (default buffs bar mirror) exposes a live spellID. The
                    -- per-icon settings menu keys off whichever is present.
                    local sdClick = ns.GetBarSpellData(bd.key)
                    local hasAssigned = sdClick and sdClick.assignedSpells
                        and sdClick.assignedSpells[dataIdx] and sdClick.assignedSpells[dataIdx] ~= 0
                    if not hasAssigned and not self._previewSpellID then return end

                    -- Show remove-only dropdown (per-icon settings + Remove)
                    ShowSpellPicker(self, bd.key, dataIdx, {}, function()
                        -- onSelect unused -- remove is handled inside ShowSpellPicker
                    end, true)  -- removeOnly flag
                end
            end)

            -- Manual drag detection: bypasses WoW's large built-in drag threshold
            local DRAG_THRESHOLD = 3  -- pixels of mouse movement before drag starts
            local pendingDragSlot, pendingStartX, pendingStartY

            -- After a drag ends, refresh hover highlights based on current cursor position
            local function RefreshHoverHighlight()
                local bd = SelectedCDMBar()
                local bR, bG, bB = 0, 0, 0
                if bd then
                    bR, bG, bB = bd.borderR or 0, bd.borderG or 0, bd.borderB or 0
                    if bd.borderClassColor then
                        local _, ct = UnitClass("player")
                        if ct then
                            local cc = RAID_CLASS_COLORS[ct]
                            if cc then bR, bG, bB = cc.r, cc.g, cc.b end
                        end
                    end
                end
                for i = 1, MAX_PREVIEW_ICONS do
                    local s = previewSlots[i]
                    if s then
                        local hovered = s:IsShown() and s:IsMouseOver()
                        local hasShape = s._shapeBorder and s._shapeBorder:IsShown()
                        if hasShape then
                            if hovered then
                                s._shapeBorder:SetVertexColor(eg.r, eg.g, eg.b, 1)
                            else
                                s._shapeBorder:SetVertexColor(bR, bG, bB, 1)
                            end
                        elseif s._hlBrd then
                            if hovered then
                                s._hlBrd:Show()
                            else
                                s._hlBrd:Hide()
                            end
                        end
                    end
                end
            end

            -- Drop handler: called when mouse is released during a drag
            local function FinishDrag()
                if not dragSlot then return end
                local self = dragSlot
                local bd = SelectedCDMBar()
                if dragGhost then dragGhost:Hide() end
                self:SetAlpha(1)
                self:SetFrameLevel(pf:GetFrameLevel() + 1)
                local didChange = false
                if insertIdx and bd then
                    local oldPos = {}
                    for i = 1, MAX_PREVIEW_ICONS do
                        local s = previewSlots[i]
                        if s and s:IsShown() and s._baseX then
                            local tex = s._icon and s._icon:GetTexture()
                            if tex then oldPos[tex] = s._baseX + (s._currentOffX or 0) end
                        end
                    end

                    -- Default buffs bar reorders a dedicated display-order array
                    -- (canon ids) instead of assignedSpells, which it shares with
                    -- routing/custom injection. Seed it from the rendered order on
                    -- the first drag so index-based moves line up with the preview.
                    local isDefBuffs = (bd.key == "buffs")
                    if isDefBuffs then
                        local sdBuf = ns.GetBarSpellData("buffs")
                        if sdBuf and not (sdBuf.buffDisplayOrder and #sdBuf.buffDisplayOrder > 0) then
                            local snap = pf._buffTrackedOrder
                            if snap and #snap > 0 then
                                local copy = {}
                                for i = 1, #snap do copy[i] = snap[i] end
                                sdBuf.buffDisplayOrder = copy
                            end
                        end
                    end
                    if dragMode == "swap" then
                        if insertIdx ~= dragIdx then
                            if isDefBuffs then
                                -- Slot -> stable-key translation: buffDisplayOrder
                                -- keeps absent (talent-gapped) keys in place, so
                                -- slot indices cannot address it directly.
                                local sk = pf._buffSlotKeys
                                if sk and ns.SwapBuffDisplayKeys
                                   and ns.SwapBuffDisplayKeys(sk[dragIdx], sk[insertIdx]) then
                                    didChange = true
                                end
                            else
                                ns.SwapTrackedSpells(bd.key, BuffDataIdx(dragIdx), BuffDataIdx(insertIdx))
                                didChange = true
                            end
                        end
                    else
                        local toIdx = insertIdx
                        if toIdx > dragIdx then toIdx = toIdx - 1 end
                        if toIdx ~= dragIdx then
                            if isDefBuffs then
                                local sk = pf._buffSlotKeys
                                if sk and ns.MoveBuffDisplayKey then
                                    -- Final rendered position toIdx = insert before
                                    -- the key at toIdx among the OTHER rendered keys
                                    -- (nil past the end = append after everything).
                                    local rk, n = {}, 0
                                    for i = 1, #sk do
                                        if i ~= dragIdx then n = n + 1; rk[n] = sk[i] end
                                    end
                                    if ns.MoveBuffDisplayKey(sk[dragIdx], rk[toIdx]) then
                                        didChange = true
                                    end
                                end
                            else
                                ns.MoveTrackedSpell(bd.key, BuffDataIdx(dragIdx), BuffDataIdx(toIdx))
                                didChange = true
                            end
                        end
                    end

                    if didChange then
                        local droppedIdx
                        if dragMode == "swap" then
                            droppedIdx = insertIdx
                        else
                            local toIdx = insertIdx
                            if toIdx > dragIdx then toIdx = toIdx - 1 end
                            droppedIdx = toIdx
                        end

                        insertLine:Hide()
                        if swapTargetIdx then
                            local sw = previewSlots[swapTargetIdx]
                            if sw and sw._hlBrd then sw._hlBrd:Hide() end
                            swapTargetIdx = nil
                        end

                        for i = 1, MAX_PREVIEW_ICONS do
                            local s = previewSlots[i]
                            if s then s._targetOffX = nil; s._currentOffX = nil end
                        end
                        animRunning = false

                        Refresh()
                        if pf.Update then pf:Update() end
                        UpdateCDMPreviewAndResize()

                        for i = 1, MAX_PREVIEW_ICONS do
                            local s = previewSlots[i]
                            if s and s:IsShown() and s._baseX then
                                if i == droppedIdx then
                                    s._currentOffX = 0
                                    s._targetOffX = 0
                                else
                                    local tex = s._icon and s._icon:GetTexture()
                                    if tex and oldPos[tex] then
                                        local diff = oldPos[tex] - s._baseX
                                        if math.abs(diff) > 0.5 then
                                            s._currentOffX = diff
                                            s._targetOffX = 0
                                        else
                                            s._currentOffX = 0
                                            s._targetOffX = 0
                                        end
                                    else
                                        s._currentOffX = 0
                                        s._targetOffX = 0
                                    end
                                end
                            end
                        end
                        animRunning = true
                        pf:SetScript("OnUpdate", function(_, dt)
                            TickAnimation(dt)
                            if not animRunning then
                                pf:SetScript("OnUpdate", nil)
                            end
                        end)
                        dragSlot = nil; dragIdx = nil; insertIdx = nil; dragMode = nil
                        dragEndTime = GetTime()
                        RefreshHoverHighlight()
                        return
                    end
                end
                ClearInsertIndicator()
                dragSlot = nil; dragIdx = nil; insertIdx = nil; dragMode = nil
                dragEndTime = GetTime()
                pf:SetScript("OnUpdate", nil)
                RefreshHoverHighlight()
            end

            local function BeginDrag(self)
                local bd = SelectedCDMBar()
                if not bd then return end
                local sdDrag = ns.GetBarSpellData(bd.key)
                local si = self._slotIdx
                if bd.key == "buffs" then
                    -- Default bar: a slot is draggable if it renders a buff
                    -- (_previewSpellID / a rendered stable key). buffDisplayOrder
                    -- is NOT indexed by slot -- it keeps absent keys in place.
                    if not self._previewSpellID
                       and not (pf._buffSlotKeys and pf._buffSlotKeys[si]) then return end
                else
                    local t = sdDrag and sdDrag.assignedSpells or {}
                    local di = BuffDataIdx(si)
                    if not t[di] or t[di] == 0 then return end
                end
                dragSlot = self; dragIdx = si
                -- Clear hover highlight on the dragged slot
                if self._shapeBorder and self._shapeBorder:IsShown() then
                    local bd2 = SelectedCDMBar()
                    local bR2, bG2, bB2 = 0, 0, 0
                    if bd2 then
                        bR2, bG2, bB2 = bd2.borderR or 0, bd2.borderG or 0, bd2.borderB or 0
                        if bd2.borderClassColor then
                            local _, ct = UnitClass("player")
                            if ct then
                                local cc = RAID_CLASS_COLORS[ct]
                                if cc then bR2, bG2, bB2 = cc.r, cc.g, cc.b end
                            end
                        end
                    end
                    self._shapeBorder:SetVertexColor(bR2, bG2, bB2, 1)
                elseif self._hlBrd then
                    self._hlBrd:Hide()
                end
                local ghost = EnsureDragGhost()
                local iSz = bd.iconSize or 36
                ghost:SetSize(iSz, iSz)
                ghost._icon:SetTexture(self._icon:GetTexture())
                local zm = bd.iconZoom or 0.08
                ghost._icon:SetTexCoord(zm, 1 - zm, zm, 1 - zm)
                ghost:SetScale(0.5)
                ghost:Show()
                self:SetAlpha(0.3)
                self:SetFrameLevel(pf:GetFrameLevel())
                -- Start cursor tracking + mouse-up detection
                pf:SetScript("OnUpdate", function(_, dt)
                    -- Detect mouse release
                    if not IsMouseButtonDown("LeftButton") then
                        pf:SetScript("OnUpdate", nil)
                        FinishDrag()
                        return
                    end
                    if not dragGhost or not dragGhost:IsShown() then return end
                    local cx, cy = GetCursorPosition()
                    local sc = UIParent:GetEffectiveScale()
                    cx, cy = cx / sc, cy / sc
                    local gs = dragGhost:GetScale() or 1
                    dragGhost:ClearAllPoints()
                    dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / gs, cy / gs)
                    TickAnimation(dt)
                    local tBd = SelectedCDMBar()
                    local tCount = 0
                    if tBd then
                        local sdT = ns.GetBarSpellData(tBd.key)
                        if tBd.key == "buffs" then
                            -- Rendered slot count, NOT #buffDisplayOrder: the stored
                            -- order keeps absent keys and can exceed what is shown.
                            if pf._buffSlotKeys then tCount = #pf._buffSlotKeys end
                        elseif sdT and sdT.assignedSpells then
                            tCount = #sdT.assignedSpells
                        end
                    end
                    local visCount = pf._gridSlots or tCount
                    local newMode, newTarget = FindDragTarget(cx, cy, visCount, dragIdx)
                    if newMode and newTarget then
                        local isNoop = false
                        if newMode == "insert" then
                            local effTo = newTarget
                            if effTo > dragIdx then effTo = effTo - 1 end
                            if effTo == dragIdx then isNoop = true end
                        elseif newMode == "swap" and newTarget == dragIdx then
                            isNoop = true
                        end
                        if isNoop then
                            ClearInsertIndicator()
                        else
                            dragMode = newMode
                            ApplyDragFeedback(newMode, newTarget, dragIdx, visCount)
                            insertIdx = newTarget
                        end
                    else
                        ClearInsertIndicator()
                    end
                end)
            end

            slot:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                -- Override editing sessions: spell placement never overrides.
                if EllesmereUI.SpecOverrides_EditSessionActive
                   and EllesmereUI.SpecOverrides_EditSessionActive() then
                    if EllesmereUI.ShowWidgetTooltip then
                        EllesmereUI.ShowWidgetTooltip(self,
                            "Per-spell settings are not part of the override system.")
                    end
                    return
                end
                -- Buff-family drag-reorder: extra/custom buff bars reorder via
                -- assignedSpells (1:1 preview), the default buffs bar via its
                -- dedicated buffDisplayOrder (stable cooldownID-keyed, reconciled
                -- from the live viewer pool). Only FocusKick stays locked -- its
                -- icon order is driven by nameplate state, not user order.
                local bdDrag = SelectedCDMBar()
                if bdDrag and bdDrag.key == ns.FOCUSKICK_BAR_KEY then return end
                local cx, cy = GetCursorPosition()
                pendingDragSlot = self
                pendingStartX = cx
                pendingStartY = cy
                -- Use a lightweight OnUpdate to detect threshold
                self:SetScript("OnUpdate", function()
                    if not pendingDragSlot then self:SetScript("OnUpdate", nil); return end
                    local nx, ny = GetCursorPosition()
                    local dx = nx - pendingStartX
                    local dy = ny - pendingStartY
                    if dx * dx + dy * dy >= DRAG_THRESHOLD * DRAG_THRESHOLD then
                        local s = pendingDragSlot
                        pendingDragSlot = nil
                        self:SetScript("OnUpdate", nil)
                        BeginDrag(s)
                    end
                end)
            end)

            slot:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" and pendingDragSlot then
                    -- Mouse released before threshold not a drag, let OnClick handle it
                    pendingDragSlot = nil
                    self:SetScript("OnUpdate", nil)
                end
            end)

            return slot
        end

        for i = 1, MAX_PREVIEW_ICONS do
            previewSlots[i] = CreatePreviewSlot(i)
        end

        -- "+" button to add new spells
        local addBtn = CreateFrame("Button", nil, pf)
        PP.Size(addBtn, 36, 36); addBtn:Hide()
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints(); addBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
        if addBg.SetSnapToPixelGrid then addBg:SetSnapToPixelGrid(false); addBg:SetTexelSnappingBias(0) end
        if PP then PP.CreateBorder(addBtn, 0.3, 0.3, 0.3, 0.5, 1, "OVERLAY", 7) end
        local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
        addLbl:SetFont(FONT_PATH, 22, GetCDMOptOutline())
        addLbl:SetPoint("CENTER", 0, 1)
        addLbl:SetText("+")

        -- Hover highlight for add button (2px accent border, same as slots)
        local eg = EllesmereUI.ELLESMERE_GREEN
        local addHlCont = CreateFrame("Frame", nil, addBtn)
        addHlCont:SetAllPoints()
        addHlCont:SetFrameLevel(addBtn:GetFrameLevel() + 1)
        local addPP = EllesmereUI and EllesmereUI.PP
        local addBrd = addPP and addPP.CreateBorder(addHlCont, eg.r, eg.g, eg.b, 1, 2, "OVERLAY", 7)
        if addBrd then addBrd:Hide() end

        addBtn:SetScript("OnEnter", function()
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            addLbl:SetTextColor(ar, ag, ab, 1)
            if addBrd then addBrd:Show() end
            if EllesmereUI.ShowWidgetTooltip then
                -- This same button adds buffs on buff-family bars, so the tip
                -- follows the selected bar rather than hard-coding CD/Utility.
                local bdHov = SelectedCDMBar()
                local tip
                if bdHov and ns.IsBarBuffFamily(bdHov) then
                    tip = "Add a Buff Spell"
                else
                    tip = "Add a CD/Utility Spell"
                end
                EllesmereUI.ShowWidgetTooltip(addBtn, EllesmereUI.L(tip))
            end
        end)
        addBtn:SetScript("OnLeave", function()
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            addLbl:SetTextColor(ar, ag, ab, 0.6)
            if addBrd then addBrd:Hide() end
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        addBtn:SetScript("OnClick", function(self)
            local bd = SelectedCDMBar()
            if not bd then return end

            -- Shared post-add finalization for ALL families (buff + CD/util).
            -- Forces an immediate reanchor so source bars (where the spell
            -- got auto-removed from) re-render without waiting for the
            -- throttled queue. Then schedules a +0.05s preview refresh.
            local function FinalizeAdd()
                if ns.CollectAndReanchor then ns.CollectAndReanchor() end
                C_Timer.After(0.05, function()
                    if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
                    if pf.Update then pf:Update() end
                    UpdateCDMPreviewAndResize()
                end)
            end

            if ns.IsBarBuffFamily(bd) then
                -- Buff bars use ShowBuffBarPicker (walks the BuffIcon
                -- viewer pool). Click routes AddTrackedSpell -- the
                -- family sweep removes the spell from every other
                -- buff-family bar (including the ghost hidden bar, which
                -- is the "unhide" step) before claiming it for bd.key.
                ShowBuffBarPicker(self, bd.key, function(newSpellID)
                    if newSpellID then
                        ns.AddTrackedSpell(bd.key, newSpellID)
                    end
                    FinalizeAdd()
                end)
            else
                -- CD/utility bars use ShowSpellPicker.
                local sdAdd = EnsureAssignedSpells(bd.key)
                local excl = {}
                local _FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
                if sdAdd and sdAdd.assignedSpells then
                    for _, sid in ipairs(sdAdd.assignedSpells) do
                        excl[sid] = true
                        -- Also exclude override forms so transformed spells
                        -- (e.g. Lay on Hands 633 -> 471195) are recognized.
                        if _FindOvr and sid > 0 then
                            local ovr = _FindOvr(sid)
                            if ovr and ovr > 0 then excl[ovr] = true end
                        end
                    end
                end
                ShowSpellPicker(self, bd.key, nil, excl, function(newSpellID, isExtra)
                    ns.AddTrackedSpell(bd.key, newSpellID, isExtra)
                    FinalizeAdd()
                end)
            end
        end)

        -- Second "+" button: add a BUFF to this CD/utility bar (buff-family bars
        -- keep the single "+" above). A buff placed here renders as a regular
        -- CD/utility icon whose gold Active State is driven by its aura. Gold-tinted
        -- so it reads apart from the standard add button; shown for CD/util only.
        local BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B = 1, 0.82, 0.25
        local buffAddBtn = CreateFrame("Button", nil, pf)
        PP.Size(buffAddBtn, 36, 36); buffAddBtn:Hide()
        local buffAddBg = buffAddBtn:CreateTexture(nil, "BACKGROUND")
        buffAddBg:SetAllPoints(); buffAddBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
        if buffAddBg.SetSnapToPixelGrid then buffAddBg:SetSnapToPixelGrid(false); buffAddBg:SetTexelSnappingBias(0) end
        -- Resting border matches the standard add button (neutral gray, not
        -- gold) -- the gold "+" glyph alone marks this as the buff-add button.
        if PP then PP.CreateBorder(buffAddBtn, 0.3, 0.3, 0.3, 0.5, 1, "OVERLAY", 7) end
        local buffAddLbl = buffAddBtn:CreateFontString(nil, "OVERLAY")
        buffAddLbl:SetFont(FONT_PATH, 22, GetCDMOptOutline())
        buffAddLbl:SetPoint("CENTER", 0, 1)
        buffAddLbl:SetText("+")
        buffAddLbl:SetTextColor(BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 0.7)

        local buffAddHlCont = CreateFrame("Frame", nil, buffAddBtn)
        buffAddHlCont:SetAllPoints()
        buffAddHlCont:SetFrameLevel(buffAddBtn:GetFrameLevel() + 1)
        local buffAddBrd = EllesmereUI and EllesmereUI.PP
            and EllesmereUI.PP.CreateBorder(buffAddHlCont, BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 1, 2, "OVERLAY", 7)
        if buffAddBrd then buffAddBrd:Hide() end

        buffAddBtn:SetScript("OnEnter", function()
            buffAddLbl:SetTextColor(BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 1)
            if buffAddBrd then buffAddBrd:Show() end
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(buffAddBtn, EllesmereUI.L("Add a Buff Spell"))
            end
        end)
        buffAddBtn:SetScript("OnLeave", function()
            buffAddLbl:SetTextColor(BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 0.7)
            if buffAddBrd then buffAddBrd:Hide() end
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        buffAddBtn:SetScript("OnClick", function(self)
            local bd = SelectedCDMBar()
            if not bd then return end
            -- CD/utility bars only (defensive: the button is hidden elsewhere).
            if ns.IsBarBuffFamily(bd) or bd.barType == "custom_buff" then return end
            ShowBuffToCDPicker(self, bd.key, function()
                if ns.CollectAndReanchor then ns.CollectAndReanchor() end
                -- The buff-mirror walk (10Hz) binds to the freshly-created icon on
                -- its own next tick; no re-arm needed.
                C_Timer.After(0.05, function()
                    if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
                    if pf.Update then pf:Update() end
                    UpdateCDMPreviewAndResize()
                end)
            end)
        end)

        -- Update: mirrors tracked spells with interactive slots
        pf.Update = function(self)
            local bd = SelectedCDMBar()
            if not bd then
                for i = 1, MAX_PREVIEW_ICONS do previewSlots[i]:Hide() end
                addBtn:Hide(); buffAddBtn:Hide(); self:SetHeight(1); return
            end

            local iconSize = bd.iconSize or 36
            -- Width-matched bars derive their real icon size from the matched
            -- target, so bd.iconSize (the disabled Icon Scale value) is ignored
            -- at runtime. Show a neutral 32px in the preview rather than the
            -- stale scale value.
            if EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget("CDM_" .. bd.key) then iconSize = 36 end
            local iconH = iconSize
            local pvShape = bd.iconShape or "none"
            if pvShape == "cropped" then
                iconH = math.floor(iconSize * 0.80 + 0.5)
            end
            local spacing  = bd.spacing or 2
            local zoom     = bd.iconZoom or 0.08
            local grow     = bd.growDirection or "RIGHT"
            local numRows  = bd.numRows or 1
            if numRows < 1 then numRows = 1 end

            local isBuffBar = ns.IsBarBuffFamily(bd)
            local isCustomBuffBar = (bd.barType == "custom_buff")
            local isFocusKick = (bd.key == "focuskick")

            -- All bars read from assignedSpells (user intent). The DEFAULT
            -- buff bar enumerates the viewer pool directly so the preview
            -- shows every tracked buff regardless of active state, minus
            -- spells diverted to other buff-family bars.
            local tracked
            -- Parallel to `tracked` for the default buffs bar: the stable viewer
            -- cooldownID for each Blizzard-tracked buff (nil for custom/injected
            -- entries). Per-icon buff settings MUST key off the cooldownID-derived
            -- stable spellID, never the live aura GetSpellID (secret/variant-drift).
            local trackedCd
            pf._buffDispGroups = nil
            pf._buffSlotKeys = nil
            if bd.key == "buffs" then
                if ns.ReconcileBuffDisplayOrder then ns.ReconcileBuffDisplayOrder() end
                local entries = ns.CollectDefaultBuffTrackEntries
                    and ns.CollectDefaultBuffTrackEntries() or {}
                tracked = {}
                trackedCd = {}
                local sdBuf = ns.GetBarSpellData("buffs")
                local order = sdBuf and sdBuf.buffDisplayOrder
                local byKey = {}
                for _, e in ipairs(entries) do byKey[e.key] = e end
                local finalKeys = {}
                if order and #order > 0 then
                    for _, key in ipairs(order) do finalKeys[#finalKeys + 1] = key end
                else
                    for _, e in ipairs(entries) do finalKeys[#finalKeys + 1] = e.key end
                end
                -- Rendered slot i <-> stable key map for the drag/reorder code:
                -- absent (talent-gapped) keys stay in buffDisplayOrder but render
                -- no slot, so slot indices cannot address the array directly.
                local slotKeys = {}
                for _, key in ipairs(finalKeys) do
                    local e = byKey[key]
                    if e then
                        tracked[#tracked + 1] = e.sid
                        trackedCd[#tracked] = e.cdID
                        slotKeys[#tracked] = key
                    end
                end
                pf._buffSlotKeys = slotKeys
                local snap = {}
                for i = 1, #finalKeys do snap[i] = finalKeys[i] end
                pf._buffTrackedOrder = snap
            else
                local sdUpd = EnsureAssignedSpells(bd.key)
                local raw = sdUpd and sdUpd.assignedSpells or {}
                if isBuffBar then
                    -- Collapse legacy duplicate buff ids in the PREVIEW only (the
                    -- stored data is left intact so routing is untouched).
                    tracked, pf._buffDispGroups = BuildBuffDisplayDedup(raw)
                else
                    tracked = raw
                end
            end
            -- Tracked-but-unlearned spells (assigned or materialized) render
            -- desaturated so it's obvious they aren't currently talented.
            -- CD/utility bars only: buff-family lists come from live pools
            -- (always learned), and custom-buff / focuskick ids are arbitrary
            -- spell ids IsPlayerSpell can't vouch for.
            local unlearnedSet
            if bd.key ~= "buffs" and not isBuffBar and not isCustomBuffBar
               and not isFocusKick and IsPlayerSpell then
                local sdUn = ns.GetBarSpellData(bd.key)
                local customUn  = sdUn and sdUn.customSpellIDs
                local cdursUn   = sdUn and sdUn.customSpellDurations
                local sdursUn   = sdUn and sdUn.spellDurations
                local groupsUn  = sdUn and sdUn.customSpellGroups
                local racialsUn = ns._myRacialsSet
                for _, id in ipairs(tracked) do
                    if type(id) == "number" and id > 0
                       and not (customUn and customUn[id])
                       and not (racialsUn and racialsUn[id])
                       and not (cdursUn and cdursUn[id])
                       and not (sdursUn and sdursUn[id])
                       and not (groupsUn and groupsUn[id])
                       and not (IsPlayerSpell(id)
                            or IsPlayerSpell(NormalizeToBase(id))
                            or IsPlayerSpell(ResolveToLive(id))) then
                        unlearnedSet = unlearnedSet or {}
                        unlearnedSet[id] = true
                    end
                end
            end
            local count = #tracked

            -- Use the same stride logic as the runtime (ComputeTopRowStride).
            -- Top and Bottom custom-row overrides are mutually exclusive; the
            -- Bottom override is the flip (pick the bottom count, top gets rest).
            local stride, topRowCount
            local customTop
            if numRows == 2 then
                if bd.customTopRowEnabled and bd.topRowCount and bd.topRowCount > 0 then
                    customTop = math.min(bd.topRowCount, count)
                elseif bd.customBottomRowEnabled and bd.bottomRowCount and bd.bottomRowCount > 0 then
                    customTop = count - math.min(bd.bottomRowCount, count)
                end
            end
            if customTop ~= nil then
                if customTop < 0 then customTop = 0 end
                topRowCount = customTop
                local bottomCount = count - topRowCount
                if bottomCount <= 0 or topRowCount <= 0 then
                    -- Match the runtime: collapse to one row until BOTH rows hold
                    -- an icon. This also keeps the "+" button on the single row.
                    numRows = 1
                    topRowCount = count
                    stride = math.max(count, 1)
                else
                    stride = math.max(topRowCount, bottomCount)
                end
            else
                stride = math.ceil(count / numRows)
                if stride < 1 then stride = 1 end
                topRowCount = count - (numRows - 1) * stride
                if topRowCount < 0 then topRowCount = 0 end
            end
            local gridSlots = (count > 0) and (stride * numRows) or 0
            self._stride = stride
            self._numRows = numRows
            self._gridSlots = gridSlots

            local bottomRowCount = count - topRowCount
            if bottomRowCount < 0 then bottomRowCount = 0 end

            -- Per-row icon count for centering
            local function RowIconCount(row)
                if row == 0 then return topRowCount end
                return bottomRowCount
            end

            -- Total dimensions: spell grid + 1 extra slot for the "+" button
            local isVert = (grow == "DOWN" or grow == "UP")
            local totalW, totalH
            if isVert then
                local totalCols = numRows + 1
                totalW = (totalCols * iconSize) + ((totalCols - 1) * spacing)
                totalH = (stride * iconH) + ((stride - 1) * spacing)
            else
                local totalCols = stride + 1
                totalW = (totalCols * iconSize) + ((totalCols - 1) * spacing)
                totalH = (numRows * iconH) + ((numRows - 1) * spacing)
            end

            -- CDM preview: no scale-to-fit — SetClipsChildren on the content
            -- header clips any overflow so icon scale remains accurate.
            local curParentW = (parent:GetWidth() - PAD * 2) / previewScale
            if curParentW > 0 then
                self:SetWidth(curParentW)
            end
            local startX = math.floor((curParentW - totalW) / 2)
            local startY = -5

            -- Position helper: places frame at grid position (col, row).
            -- Center any row that has fewer icons than stride.
            local function PosAtGrid(frame, col, row)
                PP.Size(frame, iconSize, iconH); frame:ClearAllPoints()
                local rowCount = RowIconCount(row)
                local rowHasLess = (rowCount > 0 and rowCount < stride)
                local rowOffset = 0
                if isVert then
                    if rowHasLess then
                        rowOffset = math.floor((stride - rowCount) * (iconH + spacing) / 2)
                    end
                    local px = startX + row * (iconSize + spacing)
                    local py = startY - col * (iconH + spacing) - rowOffset
                    PP.Point(frame, "TOPLEFT", self, "TOPLEFT", px, py)
                    frame._baseX = px
                    frame._baseY = py
                else
                    if rowHasLess then
                        rowOffset = math.floor((stride - rowCount) * (iconSize + spacing) / 2)
                    end
                    local px = startX + col * (iconSize + spacing) + rowOffset
                    local py = startY - row * (iconH + spacing)
                    PP.Point(frame, "TOPLEFT", self, "TOPLEFT", px, py)
                    frame._baseX = px
                    frame._baseY = py
                end
            end

            -- Border color
            local bR, bG, bB = bd.borderR or 0, bd.borderG or 0, bd.borderB or 0
            if bd.borderClassColor then
                local _, ct = UnitClass("player")
                if ct then
                    local cc = RAID_CLASS_COLORS[ct]
                    if cc then bR, bG, bB = cc.r, cc.g, cc.b end
                end
            end

            local shape = bd.iconShape or "none"

            -- Layout: fill bottom-up. Icons 1..topRowCount go to top row (row 0),
            -- remaining icons fill rows 1..numRows-1 (full bottom rows).
            for i = 1, math.min(gridSlots, MAX_PREVIEW_ICONS) do
                local slot = previewSlots[i]
                slot._slotIdx = i
                -- The assignedSpells indices this slot covers (a legacy-duplicate
                -- buff slot covers >1); nil when nothing was collapsed. Used by the
                -- settings popup's "Remove Spell" so it clears the whole duplicate.
                slot._dataGroup = pf._buffDispGroups and pf._buffDispGroups[i] or nil

                -- Map sequential index to bottom-up grid position
                local col, row
                if i <= topRowCount then
                    col = i - 1
                    row = 0
                else
                    local bottomIdx = i - topRowCount - 1
                    col = bottomIdx % stride
                    row = 1 + math.floor(bottomIdx / stride)
                end
                PosAtGrid(slot, col, row)

                if i <= count then
                    -- Spell slot
                    local id = tracked[i]
                    slot._previewSpellID = nil  -- reset each update
                    slot._previewCdID = trackedCd and trackedCd[i] or nil
                    slot._previewItemID = nil
                    slot._previewHostedBuff = nil
                    if id then
                        local tex
                        local hostedSid = ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(id)
                        if hostedSid then
                            -- Hosted-buff marker: previews as its spell, flagged so
                            -- the per-icon menu takes the buff branch while the same
                            -- id's cooldown slot keeps the cd/util one.
                            local displayID = ResolveToLive(hostedSid)
                            tex = C_Spell.GetSpellTexture(displayID)
                            if not tex and displayID ~= hostedSid then
                                tex = C_Spell.GetSpellTexture(hostedSid)
                            end
                            slot._previewSpellID = hostedSid
                            slot._previewHostedBuff = true
                        elseif id <= -100 then
                            -- On-use bag item: negated itemID
                            tex = C_Item.GetItemIconByID(-id)
                            slot._previewItemID = -id
                        elseif id < 0 then
                            -- Trinket slot: get icon from equipped item
                            local itemID = GetInventoryItemID("player", -id)
                            tex = itemID and C_Item.GetItemIconByID(itemID) or nil
                        else
                            -- Resolve to live override for texture lookup.
                            local displayID = ResolveToLive(id)
                            tex = C_Spell.GetSpellTexture(displayID)
                            if not tex and displayID ~= id then
                                tex = C_Spell.GetSpellTexture(id)
                            end
                            slot._previewSpellID = id
                        end
                        if tex then
                            slot._icon:SetTexture(tex)
                            slot._icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                            local pvUnlearned = (unlearnedSet and unlearnedSet[id]) or false
                            slot._icon:SetDesaturated(pvUnlearned)
                            slot._icon:SetAlpha(pvUnlearned and 0.55 or 1)
                        else slot._icon:SetTexture(nil) end
                    else slot._icon:SetTexture(nil) end
                else
                    -- Blank slot (empty grid filler)
                    slot._icon:SetTexture(nil)
                    slot._previewSpellID = nil
                    slot._previewCdID = nil
                    slot._previewItemID = nil
                    slot._previewHostedBuff = nil
                end

                local bSz = bd.borderSize or 1
                slot._icon:ClearAllPoints()
                PP.Point(slot._icon, "TOPLEFT", slot, "TOPLEFT", bSz, -bSz)
                PP.Point(slot._icon, "BOTTOMRIGHT", slot, "BOTTOMRIGHT", -bSz, bSz)
                slot._icon:Show()

                if PP.GetBorders(slot) then
                    PP.SetBorderColor(slot, bR, bG, bB, 1)
                    PP.SetBorderSize(slot, bSz)
                end
                slot._bg:SetColorTexture(bd.bgR or 0.08, bd.bgG or 0.08, bd.bgB or 0.08, bd.bgA or 0.6)
                if slot._bg.SetSnapToPixelGrid then slot._bg:SetSnapToPixelGrid(false); slot._bg:SetTexelSnappingBias(0) end

                ns.ApplyShapeToCDMIcon(slot, shape, bd)
                -- For custom shapes, ensure the square highlight border stays hidden
                -- (ApplyShapeToCDMIcon hides the slot's own PP border but not _hlBrd)
                if slot._hlBrd and shape ~= "square" and shape ~= "csquare" and shape ~= "none" then
                    slot._hlBrd:Hide()
                end
                -- Hosted-buff gold border: always on for a buff icon hosted on
                -- this CD/utility bar. Square-family shapes use the dedicated
                -- gold strips; masked shapes tint the shape border instead
                -- (their square strips are hidden, like the hover highlight).
                if slot._hostBrd then
                    if slot._previewHostedBuff
                       and not (slot._shapeBorder and slot._shapeBorder:IsShown()) then
                        slot._hostBrd:Show()
                    else
                        slot._hostBrd:Hide()
                    end
                end
                if slot._previewHostedBuff and slot._shapeBorder and slot._shapeBorder:IsShown() then
                    slot._shapeBorder:SetVertexColor(1, 0.82, 0.25, 1)
                end

                -- Stack count preview text
                if slot._stackText then
                    if i <= count then
                        -- Show charge count for charge-based spells (default: on)
                        -- Match real bar styling exactly (RefreshCDMIconAppearance)
                        local scFont = ns.GetCDMFont and ns.GetCDMFont() or FONT_PATH
                        local scSize = bd.stackCountSize or 11
                        local scR = bd.stackCountR or 1
                        local scG = bd.stackCountG or 1
                        local scB = bd.stackCountB or 1
                        local scX = bd.stackCountX or 0
                        local scY = bd.stackCountY or 0
                        local scPoint = bd.stackCountPosition or "bottomright"
                        if scPoint == "bottomleft" then scPoint = "BOTTOMLEFT"; scY = scY + 2
                        elseif scPoint == "topright" then scPoint = "TOPRIGHT"
                        elseif scPoint == "topleft" then scPoint = "TOPLEFT"
                        elseif scPoint == "center" then scPoint = "CENTER"
                        else scPoint = "BOTTOMRIGHT"; scY = scY + 2 end
                        EllesmereUI.ApplyIconTextFont(slot._stackText, scFont, scSize, "cdm")
                        slot._stackText:SetTextColor(scR, scG, scB)
                        slot._stackText:ClearAllPoints()
                        slot._stackText:SetPoint(scPoint, slot, scPoint, scX, scY)
                        local sid = slot._previewSpellID
                        local chargeInfo = sid and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
                        local maxC = chargeInfo and chargeInfo.maxCharges
                        if (bd.showCharges ~= false) and maxC and maxC > 1 then
                            slot._stackText:SetText(tostring(maxC))
                            slot._stackText:Show()
                        elseif slot._previewItemID and (bd.showItemCount ~= false) then
                            -- Preset potions/healthstones: fake item count so users can
                            -- preview and style the count text (mirrors charge preview).
                            slot._stackText:SetText("5")
                            slot._stackText:Show()
                        else
                            slot._stackText:Hide()
                        end
                    else
                        slot._stackText:Hide()
                    end
                end

                -- Keybind text preview (mirror live: our CDM font + outline,slug)
                if slot._keybindText then
                    EllesmereUI.ApplyIconTextFont(slot._keybindText, FONT_PATH, bd.keybindSize or 10, "cdm")
                    slot._keybindText:ClearAllPoints()
                    local kx = bd.keybindOffsetX or 2
                    local ky = bd.keybindOffsetY or -2
                    if bd.keybindAlign == "right" then
                        slot._keybindText:SetJustifyH("RIGHT")
                        slot._keybindText:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -kx, ky)
                    else
                        slot._keybindText:SetJustifyH("LEFT")
                        slot._keybindText:SetPoint("TOPLEFT", slot, "TOPLEFT", kx, ky)
                    end
                    slot._keybindText:SetTextColor(bd.keybindR or 1, bd.keybindG or 1, bd.keybindB or 1, bd.keybindA or 0.9)
                    local sid = slot._previewSpellID
                    if bd.showKeybind and sid then
                        local cache = ns.CDMKeybindCache or ns._cdmKeybindCache
                        local key = cache and cache[sid]
                        if not key and C_Spell.GetSpellName then
                            local n = C_Spell.GetSpellName(sid)
                            if n and cache then key = cache[n] end
                        end
                        if key then
                            slot._keybindText:SetText(key)
                            slot._keybindText:Show()
                        else
                            slot._keybindText:Hide()
                        end
                    else
                        slot._keybindText:Hide()
                    end
                end

                if i <= count then
                    slot:Show()
                else
                    slot:Hide()
                end
            end

            for i = gridSlots + 1, MAX_PREVIEW_ICONS do previewSlots[i]:Hide() end

            -- "+" button: placed right after the last icon on the bottom row.
            -- Bottom row is always full (or the only row).
            -- For empty bars (count=0), the "+" is the only visible element.
            local addPx, addPy
            if count == 0 then
                -- No spells: center the "+" button alone
                addPx = math.floor((curParentW - iconSize) / 2)
                addPy = startY
            elseif isVert then
                -- Vertical: "+" goes in the next column to the right, at the bottom
                addPx = startX + numRows * (iconSize + spacing)
                addPy = startY - (stride - 1) * (iconH + spacing)
            else
                -- Horizontal: "+" goes right after the last column on the bottom row
                local lastRow = numRows - 1
                addPx = startX + stride * (iconSize + spacing)
                addPy = startY - lastRow * (iconH + spacing)
            end
            PP.Size(addBtn, iconSize, iconH); addBtn:ClearAllPoints()
            PP.Point(addBtn, "TOPLEFT", self, "TOPLEFT", addPx, addPy)
            if PP.GetBorders(addBtn) then PP.SetBorderSize(addBtn, 1) end
            local ar, ag, ab = EllesmereUI.GetAccentColor()

            addLbl:SetTextColor(ar, ag, ab, 0.6)
            addBtn:Show()

            -- Second "+" (buff) button sits one slot right of the standard "+",
            -- on CD/utility bars only (buff-family / custom_buff / focuskick bars
            -- track buffs their own way).
            if not isBuffBar and not isCustomBuffBar and not isFocusKick then
                PP.Size(buffAddBtn, iconSize, iconH); buffAddBtn:ClearAllPoints()
                PP.Point(buffAddBtn, "TOPLEFT", self, "TOPLEFT", addPx + iconSize + spacing, addPy)
                if PP.GetBorders(buffAddBtn) then PP.SetBorderSize(buffAddBtn, 1) end
                buffAddBtn:Show()
            else
                buffAddBtn:Hide()
            end

            -- Bar background covers spell grid only (not the + column)
            local spellW, spellH
            if isVert then
                spellW = (numRows * iconSize) + ((numRows - 1) * spacing)
                spellH = (stride * iconH) + ((stride - 1) * spacing)
            else
                spellW = (stride * iconSize) + ((stride - 1) * spacing)
                spellH = totalH
            end
            if bd.barBgEnabled then
                pvBarBg:ClearAllPoints()
                pvBarBg:SetPoint("TOPLEFT", startX, startY)
                pvBarBg:SetPoint("BOTTOMRIGHT", pf, "TOPLEFT", startX + spellW, startY - spellH)
                pvBarBg:SetColorTexture(bd.barBgR or 0, bd.barBgG or 0, bd.barBgB or 0, bd.barBgA or 0.5)
                if pvBarBg.SetSnapToPixelGrid then pvBarBg:SetSnapToPixelGrid(false); pvBarBg:SetTexelSnappingBias(0) end
                pvBarBg:Show()
            else
                pvBarBg:Hide()
            end

            self:SetAlpha(1)

            -- Buff bar info text
            if not self._buffInfoText then
                local infoFS = self:CreateFontString(nil, "OVERLAY")
                infoFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                infoFS:SetJustifyH("CENTER")
                infoFS:SetWordWrap(true)
                infoFS:SetTextColor(0.6, 0.6, 0.6, 0.9)
                self._buffInfoText = infoFS
            end
            -- Reorder / per-icon hint shown directly below the preview icons.
            -- Buff bars and CD/utility bars get different wording; FocusKick has
            -- its own info text instead and is not user-reorderable.
            if not self._reorderHintText then
                local rh = self:CreateFontString(nil, "OVERLAY")
                rh:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                rh:SetJustifyH("CENTER")
                rh:SetWordWrap(true)
                rh:SetTextColor(0.62, 0.62, 0.62, 0.9)
                self._reorderHintText = rh
            end
            local function ShowReorderHint(text)
                local rh = self._reorderHintText
                rh:SetText(EllesmereUI.L(text))
                rh:ClearAllPoints()
                rh:SetPoint("TOP", self, "TOPLEFT", self:GetWidth() / 2, -(totalH + 14))
                rh:SetWidth(self:GetWidth() - 20)
                rh:Show()
                self:SetHeight(totalH + 10 + rh:GetStringHeight() + 20)
            end

            if isBuffBar then
                if self._buffInfoText then self._buffInfoText:Hide() end
                if self._buffInfoClick then self._buffInfoClick:Hide() end
                -- Clean up hidden rows from previous implementation
                if self._hiddenRows then
                    for _, hr in ipairs(self._hiddenRows) do hr:Hide() end
                end
                if self._hiddenHeader then self._hiddenHeader:Hide() end
                if self._focusKickInfoText then self._focusKickInfoText:Hide() end
                ShowReorderHint("Drag to Reorder. Click to override display settings and add custom effects per icon")
            elseif isFocusKick then
                if self._buffInfoText then self._buffInfoText:Hide() end
                if self._buffInfoClick then self._buffInfoClick:Hide() end
                if self._reorderHintText then self._reorderHintText:Hide() end
                if not self._focusKickInfoText then
                    local fkFS = self:CreateFontString(nil, "OVERLAY")
                    fkFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    fkFS:SetJustifyH("CENTER")
                    fkFS:SetWordWrap(true)
                    fkFS:SetTextColor(1, 1, 1, 1)
                    self._focusKickInfoText = fkFS
                end
                local fkFS = self._focusKickInfoText
                -- Wording must track the "Show on Target" toggle -- otherwise this
                -- text keeps promising focus-tracking even when the bar is
                -- configured to follow the current target instead.
                if bd.focusKickUseTarget then
                    fkFS:SetText(EllesmereUI.L("This bar will always be attached to your current target's nameplate"))
                else
                    fkFS:SetText(EllesmereUI.L("This bar will always be attached to your focus target's nameplate"))
                end
                fkFS:ClearAllPoints()
                fkFS:SetPoint("TOP", self, "TOPLEFT", self:GetWidth() / 2, -(totalH + 14))
                fkFS:SetWidth(self:GetWidth() - 20)
                fkFS:Show()
                self:SetHeight(totalH + 10 + fkFS:GetStringHeight() + 20)
            else
                if self._buffInfoText then self._buffInfoText:Hide() end
                if self._buffInfoClick then self._buffInfoClick:Hide() end
                if self._focusKickInfoText then self._focusKickInfoText:Hide() end
                ShowReorderHint("Drag to Reorder. Click to add custom glows, active/cooldown state effects and more.")
            end

            -- Resize wrapper to min(content, max) and toggle scrollbar
            local parentH = self:GetHeight() * (self._previewScale or 1)
            local maxH = self._PREVIEW_MAX_H or 200
            if parentH > maxH then
                -- Add bottom padding so info text is fully visible when scrolled down
                self:SetHeight(self:GetHeight() + 30)
                self._wrapper:SetHeight(maxH)
            else
                self._wrapper:SetHeight(parentH)
                if self._scrollFrame then self._scrollFrame:SetVerticalScroll(0) end
            end
            if self._updatePVThumb then self._updatePVThumb() end

            -- Restart active state preview on first icon if toggled on
            if _cdmActivePreviewOn then
                StopActiveStatePreview()
                StartActiveStatePreview()
            end
        end

        pf._previewSlots = previewSlots
        _cdmPreview = pf
        pf:Update()
        EllesmereUI._contentHeaderPreview = pf
        -- Start active state preview if toggled on
        if _cdmActivePreviewOn then
            StartActiveStatePreview()
        end
        -- Return wrapper height (already capped by Update's resize logic)
        return wrapper:GetHeight()
    end

    local function BuildCDMBarsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        local p = DB()
        if not p or not p.cdmBars then return math.abs(yOffset) end

        local bars = p.cdmBars.bars
        if not bars or #bars == 0 then return math.abs(yOffset) end


        -- Clamp selection
        if selectedCDMBarIndex < 1 then selectedCDMBarIndex = 1 end
        if selectedCDMBarIndex > #bars then selectedCDMBarIndex = #bars end

        local barData = bars[selectedCDMBarIndex]
        if not barData then return math.abs(yOffset) end

        -- Tag every option registered while building this page with the
        -- currently-selected bar, so a global-search jump to a bar-specific
        -- setting (e.g. HoverCast/FocusKick-only options) can restore this
        -- exact bar selection first via EllesmereUI._setCDMBar -- otherwise
        -- the matched row wouldn't exist under whatever bar happens to be
        -- selected when the player jumps there.
        EllesmereUI._buildingSelector = { setter = EllesmereUI._setCDMBar, key = barData.key }

        -- Capture the key so closures can always look up the CURRENT bar data
        -- from the profile, avoiding stale-reference bugs when the bars array
        -- is reordered or the page is rebuilt.
        -- Searchable single-select "Sync From" dropdown (source spec). Lists the
        -- player's specs with a search box on top; defaults to the current spec.
        -- Reuses one frame on ns so repeated opens don't leak.
        local function ShowRPTSourcePicker(defaultKey, onSelect)
            -- All-classes source list (current class always + other classes that
            -- have data), so the source isn't limited to the player's class.
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
                local scale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1
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

        -- Sync Generic CDs/Buffs across specs (per profile): trinkets, pots,
        -- racials and buff-bar presets (Bloodlust, etc.). First-time
        -- setup picks a SOURCE spec (searchable dropdown, default current spec),
        -- then a spec picker with the source locked ON (auto-checked, can't be
        -- deselected).
        local function DoRPTSyncSetup()
            local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
            ShowRPTSourcePicker(curKey, function(sourceKey)
                local srcName = sourceKey
                if GetSpecializationInfoByID and tonumber(sourceKey) then
                    local _, n = GetSpecializationInfoByID(tonumber(sourceKey))
                    if n and n ~= "" then srcName = n end
                end
                local specs = ns.GetCDMSpecInfo and ns.GetCDMSpecInfo() or {}
                for _, s in ipairs(specs) do
                    s.checked = (s.key == sourceKey)
                end
                EllesmereUI:ShowCDMSpecPickerPopup({
                    title       = "Sync Generic CDs/Buffs",
                    subtitle    = "Choose which specs sync with " .. srcName .. " (the source is always included)",
                    confirmText = "Sync",
                    specs       = specs,
                    lockedSpecs = { [sourceKey] = "This is the spec you're syncing from -- it's always included." },
                    onConfirm   = function(selectedSpecs)
                        selectedSpecs[sourceKey] = true
                        local cnt = 0
                        for _, v in pairs(selectedSpecs) do if v then cnt = cnt + 1 end end
                        if cnt <= 1 then
                            -- Only the source picked -> nothing to sync; clear any sync.
                            if ns.ClearRPTSync then ns.ClearRPTSync() end
                            EllesmereUI:RefreshPage(true)
                            return
                        end
                        if ns.SetupRPTSync then ns.SetupRPTSync(selectedSpecs, sourceKey) end
                        if ns.FullCDMRebuild then ns.FullCDMRebuild("profile_import") end
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
            -- Pre-check EVERY synced spec, not just the current class's. A sync
            -- can span specs from other classes (same profile used across
            -- characters; pots & trinkets are shared), and the picker grid shows
            -- all classes -- so seed the pre-checked set straight from the stored
            -- sync set rather than from the current class's spec list (which is
            -- all GetCDMSpecInfo returns).
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
                onConfirm   = function(selectedSpecs)
                    local cnt = 0
                    for _, v in pairs(selectedSpecs) do if v then cnt = cnt + 1 end end
                    if cnt <= 1 then
                        -- One or zero specs left -> nothing to sync; clear it.
                        if ns.ClearRPTSync then ns.ClearRPTSync() end
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
                            if _cdmPreview and _cdmPreview.Update then
                                _cdmPreview:Update()
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
        _cdmPreview = nil

        _cdmHeaderBuilder = function(hdr, hdrW)
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
                local bd = bars[selectedCDMBarIndex]
                local label = bd and EllesmereUI.L(bd.name or bd.key) or ""
                ddLbl:SetText(label)
            end
            UpdateDDLabel()

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

                for idx, b in ipairs(bars) do
                    if b.isGhostBar then
                        -- skip ghost bar in dropdown
                    else
                    -- FocusKick is treated as a built-in: cannot be deleted
                    -- or renamed even though its barType is "cooldowns".
                    local isFocusKick = (b.key == "focuskick")
                    local isCustom = (b.key ~= "cooldowns" and b.key ~= "utility" and b.key ~= "buffs" and not isFocusKick)
                    local item = CreateFrame("Button", nil, menu)
                    item:SetHeight(ITEM_H)
                    item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(menu:GetFrameLevel() + 2)

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
                    iHl:SetAlpha(idx == selectedCDMBarIndex and selA or 0)

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
                            iHl:SetAlpha(idx == selectedCDMBarIndex and selA or 0)
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
                                    selectedCDMBarIndex = 1
                                    for bi, bb in ipairs(bars) do
                                        if bb.key == "cooldowns" then selectedCDMBarIndex = bi; break end
                                    end
                                    Refresh()
                                    EllesmereUI:InvalidateContentHeaderCache()
                                    EllesmereUI:SetContentHeader(_cdmHeaderBuilder)
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
                                    EllesmereUI:SetContentHeader(_cdmHeaderBuilder)
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
                        iHl:SetAlpha(idx == selectedCDMBarIndex and selA or 0)
                        if delBtn then delBtn:SetAlpha(0.75) end
                        if editBtn then editBtn:SetAlpha(0.75) end
                    end)
                    item:SetScript("OnClick", function()
                        menu:Hide()
                        selectedCDMBarIndex = idx
                        EllesmereUI:InvalidateContentHeaderCache()
                        EllesmereUI:SetContentHeader(_cdmHeaderBuilder)
                        EllesmereUI:RefreshPage(true)
                    end)

                    mH = mH + ITEM_H
                end -- else (not ghost bar)
                end -- for idx, b

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
                            selectedCDMBarIndex = #p.cdmBars.bars
                            Refresh()
                            EllesmereUI:InvalidateContentHeaderCache()
                            EllesmereUI:SetContentHeader(_cdmHeaderBuilder)
                            EllesmereUI:RefreshPage(true)
                        end)
                    end
                    mH = mH + ITEM_H
                end

                menu:SetHeight(mH + 4)

                -- Close on left-click outside (non-blocking)
                menu:SetScript("OnUpdate", function(m)
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

            _cdmHeaderFixedH = 20 + DD_H + PV_PAD + PV_PAD

            return math.abs(fy)
        end
        EllesmereUI:SetContentHeader(_cdmHeaderBuilder)

        -- Refresh preview icons on mount/dismount (skyriding swaps action bar icons)
        --
        -- Skipped during a hidden search pre-build: same reasoning as the
        -- pageListener above in BuildBarGlowsPage -- its OnHide-based cleanup
        -- isn't guaranteed to fire for a wrapper that's never effectively
        -- visible, which would otherwise leak this listener (and the
        -- RefreshPage(true) it triggers on every mount/dismount) for the
        -- rest of the session.
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

        -- Helper to create cog button on a DualRow left region
        local function MakeCogBtn(rgn, showFn, anchorTo, iconPath)
            local anchor = anchorTo or (rgn and (rgn._lastInline or rgn._control)) or rgn
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(iconPath or EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) showFn(self) end)
            if rgn then rgn._lastInline = cogBtn end
            return cogBtn
        end


        -------------------------------------------------------------------
        --  BAR LAYOUT / ICON DISPLAY
        -------------------------------------------------------------------
        parent._showRowDivider = true

        if barData.key == "buffs" then
            --[[ DISABLED: Use Blizzard Buff Bar feature temporarily removed
            _, h = W:Toggle(parent, "Use Blizzard Buff Bar", y,
                function() return DB().cdmBars.useBlizzardBuffBars == true end,
                function(v)
                    DB().cdmBars.useBlizzardBuffBars = v
                    ns.BuildAllCDMBars()
                    EllesmereUI:RefreshPage(true)
                end
            );  y = y - h

            if DB().cdmBars.useBlizzardBuffBars then
                return math.abs(y)
            end
            --]]
        end

        -------------------------------------------------------------------
        --  BAR LAYOUT
        -------------------------------------------------------------------
        -- Sync helpers: different exclusion levels.
        -- FocusKick is excluded from every sync iterator -- it has its own
        -- nameplate-anchored identity that should never receive global syncs.
        -- General: all bars except ghost / focuskick
        local function ForEachSyncBar(fn)
            local pp = DB(); if not pp or not pp.cdmBars then return end
            for _, b in ipairs(pp.cdmBars.bars) do
                if not b.isGhostBar and b.key ~= "focuskick" then fn(b) end
            end
        end
        -- Pandemic: exclude ghost + custom_buff + focuskick
        local function ForEachPandemicSyncBar(fn)
            local pp = DB(); if not pp or not pp.cdmBars then return end
            for _, b in ipairs(pp.cdmBars.bars) do
                if not b.isGhostBar and b.barType ~= "custom_buff" and b.key ~= "focuskick" then fn(b) end
            end
        end
        -- Extras: exclude ghost + buffs + custom_buff + focuskick
        local function ForEachExtrasSyncBar(fn)
            local pp = DB(); if not pp or not pp.cdmBars then return end
            for _, b in ipairs(pp.cdmBars.bars) do
                if not b.isGhostBar and b.barType ~= "buffs" and b.key ~= "buffs" and b.barType ~= "custom_buff" and b.key ~= "focuskick" then fn(b) end
            end
        end

        if not isFocusKick then
        _, h = W:SectionHeader(parent, "BAR LAYOUT", y);  y = y - h

        -- Row 1: (Sync) Visibility | Visibility Options (checkbox dropdown)
        -- Mouseover stays structurally absent for CDM bars (noMouseover),
        -- matching the old VIS_VALUES_CDM list.
        local visRow, visH = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
            { getStore = BD, legacyKey = "barVisibility",
              caps = { partyIncludesRaid = true, noMouseover = true, luaDragonriding = true },
              onChanged = function()
                  ns.CDMApplyVisibility()
              end },
            { type="dropdown", text="Visibility Options",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end });  y = y - visH

        -- Replace the dummy right dropdown with our checkbox dropdown
        do
            local rightRgn = visRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local visItems = EllesmereUI.VIS_OPT_ITEMS
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                visItems,
                function(k) return BD()[k] or false end,
                function(k, v)
                    BD()[k] = v
                    ns.CDMApplyVisibility()
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Sync icon on Visibility (left) -- set-aware so multi-selections
        -- compare and copy correctly (uniform caps across CDM bars).
        do
            local rgn = visRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Visibility to all Bars",
                isSynced = function()
                    local src = BD()
                    local synced = true
                    ForEachSyncBar(function(b)
                        if not EllesmereUI.VisSelectionEquals(src, "barVisibility", b, "barVisibility") then synced = false end
                    end)
                    return synced
                end,
                onClick = function()
                    local src = BD()
                    ForEachSyncBar(function(b)
                        if b ~= src then EllesmereUI.VisCopySelection(b, src, "barVisibility") end
                    end)
                    ns.CDMApplyVisibility(); EllesmereUI:RefreshPage()
                end,
            })
        end

        -- Sync icon on Visibility Options (right)
        do
            local rgn = visRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Visibility Options to all Bars",
                isSynced = function()
                    local bd = BD()
                    local synced = true
                    for _, item in ipairs(EllesmereUI.VIS_OPT_ITEMS) do
                        local k = item.key
                        local cur = bd[k] or false
                        ForEachSyncBar(function(b) if (b[k] or false) ~= cur then synced = false end end)
                    end
                    return synced
                end,
                onClick = function()
                    local bd = BD()
                    for _, item in ipairs(EllesmereUI.VIS_OPT_ITEMS) do
                        local k = item.key
                        local v = bd[k] or false
                        ForEachSyncBar(function(b) b[k] = v end)
                    end
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
                makeCogBtn = MakeCogBtn,
            })
            y = y - cursorH
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
            { type="toggle", text="Vertical Orientation",
              getValue=function() return BD().verticalOrientation end,
              setValue=function(v)
                  local bd = BD()
                  bd.verticalOrientation = v
                  bd.growDirection = v and "DOWN" or "RIGHT"
                  -- Orientation flip swaps the meaning of width-axis vs
                  -- height-axis, so width/height match caches no longer apply.
                  bd._matchIconPhys = nil
                  bd._matchExtraPixels = nil
                  bd._matchStride = nil
                  bd._matchExtraPixelsH = nil
                  bd._matchStrideH = nil
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end });  y = y - h

        -- Inline color swatch on Bar Background (left)
        do
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

        -- Row 3: Number of Rows | Bar Opacity (cd/utility/buff, excl. focuskick)
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
        local numRowsRow
        numRowsRow, h = W:DualRow(parent, y,
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
                      if bd.anchorFirstRow then
                          -- The first-row pin rides on the 2-row custom split
                          -- (the only layout whose row count changes at
                          -- runtime). Clear it with the rest of the split
                          -- settings and re-store the position in plain edge
                          -- format from the bar's current spot.
                          bd.anchorFirstRow = nil
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
              end },
            row3Right);  y = y - h

        -- Inline cog on Number of Rows: Custom Top Row Count (only relevant when numRows == 2)
        do
            local leftRgn = numRowsRow._leftRegion
            local ctrl = leftRgn._control
            local function customTopOff()
                local bd = BD()
                return not bd or not bd.customTopRowEnabled
            end
            local function customBottomOff()
                local bd = BD()
                return not bd or not bd.customBottomRowEnabled
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
            local _, topRowCogShow = EllesmereUI.BuildCogPopup({
                title = "Row Icons",
                rows = {
                    { type="toggle", label="Anchor First Row",
                      tooltip="Keeps the first row in place when the second row appears or disappears.",
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
                      get=function() return BD().anchorFirstRow == true end,
                      set=function(v)
                          BD().anchorFirstRow = v or nil
                          -- Recapture the corner from the bar's current spot BEFORE
                          -- rebuilding, so the new anchor pins where the bar sits now.
                          if ns.RecaptureBarAnchor then ns.RecaptureBarAnchor(BD().key) end
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                      end },
                    { type="toggle", label="Custom Top Row Count",
                      -- Mutually exclusive with Custom Bottom Row Count: enabling one
                      -- disables the other's toggle. Clearing the sibling on enable
                      -- also prevents a both-on deadlock (both overlays showing).
                      disabled=function() return rowsNotTwo() or BD().customBottomRowEnabled == true end,
                      disabledTooltip=function()
                          if rowsNotTwo() then return "This option requires exactly 2 rows" end
                          return "Disabled while Custom Bottom Row Count is enabled"
                      end,
                      rawTooltip=true,
                      get=function() return BD().customTopRowEnabled end,
                      set=function(v)
                          BD().customTopRowEnabled = v
                          if v then BD().customBottomRowEnabled = nil end
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                      end },
                    { type="slider", label="Top Row Icons",
                      min=1, max=50, step=1,
                      tooltip="How many icons to show on the top row. The rest go on the bottom row.",
                      disabled=function() return rowsNotTwo() or customTopOff() end,
                      disabledTooltip=function()
                          if rowsNotTwo() then return "This option requires exactly 2 rows" end
                          return "Custom Top Row Count"
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
                    { type="toggle", label="Custom Bottom Row Count",
                      -- Flip of Custom Top Row Count; mutually exclusive with it.
                      disabled=function() return rowsNotTwo() or BD().customTopRowEnabled == true end,
                      disabledTooltip=function()
                          if rowsNotTwo() then return "This option requires exactly 2 rows" end
                          return "Disabled while Custom Top Row Count is enabled"
                      end,
                      rawTooltip=true,
                      get=function() return BD().customBottomRowEnabled end,
                      set=function(v)
                          BD().customBottomRowEnabled = v
                          if v then BD().customTopRowEnabled = nil end
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                      end },
                    { type="slider", label="Bottom Row Icons",
                      min=1, max=50, step=1,
                      tooltip="How many icons to show on the bottom row. The rest go on the top row.",
                      disabled=function() return rowsNotTwo() or customBottomOff() end,
                      disabledTooltip=function()
                          if rowsNotTwo() then return "This option requires exactly 2 rows" end
                          return "Custom Bottom Row Count"
                      end,
                      get=function()
                          local bd = BD()
                          if bd.bottomRowCount and bd.bottomRowCount > 0 then return bd.bottomRowCount end
                          local count = 0
                          local sdBR = ns.GetBarSpellData(bd.key)
                          if sdBR and sdBR.assignedSpells then
                              for _, sid in ipairs(sdBR.assignedSpells) do if sid and sid ~= 0 then count = count + 1 end end
                          end
                          if count == 0 then return 1 end
                          return math.max(1, math.floor(count / 2))
                      end,
                      set=function(v)
                          if v == 0 then v = nil end
                          BD().bottomRowCount = v
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                      end },
                    { type="toggle", label="Custom Top Row Size",
                      -- Mutually exclusive with Custom Bottom Row Size; also locked
                      -- while the bar is width/height matched (same as Icon Scale).
                      disabled=function() return rowsNotTwo() or rowSizeMatched() or BD().customBottomRowSizeEnabled == true end,
                      disabledTooltip=function()
                          if rowsNotTwo() then return "This option requires exactly 2 rows" end
                          if rowSizeMatched() then return rowSizeMatchTip() end
                          return "Disabled while Custom Bottom Row Size is enabled"
                      end,
                      rawTooltip=true,
                      get=function() return BD().customTopRowSizeEnabled end,
                      set=function(v)
                          BD().customTopRowSizeEnabled = v
                          if v then BD().customBottomRowSizeEnabled = nil end
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                      end },
                    { type="slider", label="Top Icon Size",
                      min=-20, max=20, step=1,
                      tooltip="Offsets the top row's icon size in pixels from Icon Scale. The bottom row keeps the base size.",
                      disabled=function() return rowsNotTwo() or rowSizeMatched() or not BD().customTopRowSizeEnabled end,
                      disabledTooltip=function()
                          if rowsNotTwo() then return "This option requires exactly 2 rows" end
                          if rowSizeMatched() then return rowSizeMatchTip() end
                          return "Custom Top Row Size"
                      end,
                      rawTooltip=function() return rowSizeMatched() end,
                      get=function() return BD().topRowSizeOffset or 0 end,
                      set=function(v)
                          if v == 0 then v = nil end
                          BD().topRowSizeOffset = v
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                      end },
                    { type="toggle", label="Custom Bottom Row Size",
                      -- Flip of Custom Top Row Size; mutually exclusive with it.
                      disabled=function() return rowsNotTwo() or rowSizeMatched() or BD().customTopRowSizeEnabled == true end,
                      disabledTooltip=function()
                          if rowsNotTwo() then return "This option requires exactly 2 rows" end
                          if rowSizeMatched() then return rowSizeMatchTip() end
                          return "Disabled while Custom Top Row Size is enabled"
                      end,
                      rawTooltip=true,
                      get=function() return BD().customBottomRowSizeEnabled end,
                      set=function(v)
                          BD().customBottomRowSizeEnabled = v
                          if v then BD().customTopRowSizeEnabled = nil end
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                      end },
                    { type="slider", label="Bottom Icon Size",
                      min=-20, max=20, step=1,
                      tooltip="Offsets the bottom row's icon size in pixels from Icon Scale. The top row keeps the base size.",
                      disabled=function() return rowsNotTwo() or rowSizeMatched() or not BD().customBottomRowSizeEnabled end,
                      disabledTooltip=function()
                          if rowsNotTwo() then return "This option requires exactly 2 rows" end
                          if rowSizeMatched() then return rowSizeMatchTip() end
                          return "Custom Bottom Row Size"
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
            MakeCogBtn(leftRgn, topRowCogShow, ctrl, EllesmereUI.COGS_ICON)
        end

        -- Inline cog on Bar Opacity: fade the bar to a chosen alpha while out
        -- of combat. Off by default.
        if isCDOrUtilityRow3 then
            local rgn = numRowsRow._rightRegion
            local ctrl = rgn and rgn._control
            local _, oocCogShow = EllesmereUI.BuildCogPopup({
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
            MakeCogBtn(rgn, oocCogShow, ctrl, EllesmereUI.COGS_ICON)
        end

        -- Max Icons + Overflow To: excess icons (beyond Max, the tail of this
        -- bar's order) render on the target bar for the session. Identity,
        -- per-spell settings and the options preview stay on this bar.
        -- Legacy profiles carry nil barType on default bars -- resolve the
        -- family via the shared helper, never the raw field.
        local ofBarType = ns.GetBarType and ns.GetBarType(barData) or barData.barType
        local isOverflowBar = (ofBarType == "cooldowns" or ofBarType == "utility")
            and not barData.isGhostBar
            and barData.key ~= (ns.FOCUSKICK_BAR_KEY or "focuskick")
        if isOverflowBar then
            local function OverflowShiftBlocked()
                return (ns.CdmBarHasShiftCdState and ns.CdmBarHasShiftCdState(BD().key)) or false
            end
            -- A bar may not BOTH receive overflow and have its own overflow
            -- config: incoming icons ignore the recipient's cap and never
            -- chain onward, so a cap on a recipient would promise behavior
            -- that does not exist. Recipient = ANY bar (enabled or not --
            -- re-enabling must not create the forbidden state) with an
            -- active cap+target pair pointing here.
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
                        -- Bars with their own active overflow config are not
                        -- offered as targets (the recipient rule, other door).
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
                    -- A stored target that the filter (or a bar delete) now
                    -- excludes still displays -- and can be cleared -- rather
                    -- than masquerading as "None" while active at runtime
                    -- (pre-rule configs keep working under no-chaining).
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
                  -- A blocked bar with a value already set can still lower/
                  -- clear it -- a disabled control must never trap an
                  -- existing value on.
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
                  -- Recipient bars cannot pick a fresh target (third door);
                  -- one with a stale target set stays enabled so it can be
                  -- cleared back to None.
                  disabled=function()
                      local b = BD()
                      return OverflowShiftBlocked()
                          or (BarIsOverflowRecipient(b.key) and not b.overflowTarget)
                          or not (b.maxIcons and b.maxIcons > 0)
                  end,
                  -- Tooltip priority: recipient block, then the plain Max
                  -- Icons requirement. The Shift Icons message only shows
                  -- when it is the ACTUAL blocker (Max Icons already above 0
                  -- but a spell carries a shift cooldown-state setting) --
                  -- most users never touch that setting, so the default
                  -- tooltip stays basic.
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

        -- Hide Buffs When Inactive (global setting, applies to all buff bars)
        if ns.IsBarBuffFamily(barData) then
            local prof = ns.ECME and ns.ECME.db and ns.ECME.db.profile
            -- Hide Buffs When Inactive toggle removed: always forced ON.
        end

        -- Keep Buffs in Same Place (native buff bars): reserves every tracked buff's
        -- slot so active buffs never reposition; inactive slots are invisible. Reuses
        -- the Always-Show placeholder path internally (placeholders injected, then
        -- rendered alpha 0). Mutually exclusive with Always Show Buffs -- disabled
        -- while that is on.
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
                { type="label", text="" }); y = y - h
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
            do
                local _, npCogShow = EllesmereUI.BuildCogPopup({
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
                local rgn = npRow._leftRegion
                MakeCogBtn(rgn, npCogShow, rgn._control, EllesmereUI.RESIZE_ICON)
            end

            -- Inline dual swatch + cog for Focus Reminders (right region).
            -- Layout right-to-left along the row's right region:
            --   [control] [accent swatch] [custom swatch] [cog]
            -- Accent swatch (closest to control) is the active mode by
            -- default; custom swatch dims and blocks while accent is on.
            do
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

                -- Block overlay: while accent mode is active, clicking the
                -- custom swatch flips accent mode off instead of opening the
                -- color picker.
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

                local _, frCogShow = EllesmereUI.BuildCogPopup({
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
                MakeCogBtn(rgn, frCogShow, customSwatch, EllesmereUI.RESIZE_ICON)

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

            -- Row 2: Focus Cast Sound (left) | Interrupt Spell picker (right)
            -- Sound dropdown values are built from the runtime sound table
            -- (built-in EllesmereUI sounds + LSM sounds appended at init).
            -- Spell picker is rebuilt fresh every page render so it always
            -- reflects the bar's current spell list.
            --
            -- Shallow-copy the runtime names table so we can attach per-row
            -- menu options (preview icon) without polluting the shared
            -- ns.FOCUSKICK_SOUND_NAMES table that other code reads.
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
                    return "common-icon-sound"
                end,
                iconPressedAtlas = function(key)
                    if key == "none" then return nil end
                    return "common-icon-sound-pressed"
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
                      return tostring(sid)
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

        -- Buff Glow dropdown values (buff bars only)
        local BUFF_GLOW_VALUES = { [0] = "None" }
        local BUFF_GLOW_ORDER = { 0 }
        do
            for i, entry in ipairs(ns.GLOW_STYLES) do
                if not entry.shapeGlow then
                    BUFF_GLOW_VALUES[i] = entry.name
                    BUFF_GLOW_ORDER[#BUFF_GLOW_ORDER + 1] = i
                end
            end
        end

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
                local _, asbCogShow = EllesmereUI.BuildCogPopup({
                    title = "Always Show Buffs",
                    rows = {
                        { type="toggle", label="Desaturate Off CD",
                          get=function() return BD().desaturateInactiveBuffs ~= false end,
                          set=function(v)
                              BD().desaturateInactiveBuffs = v
                          end },
                    },
                })
                local leftRgn = scaleAnimRow._leftRegion
                local asbCog = MakeCogBtn(leftRgn, asbCogShow, leftRgn._control, EllesmereUI.COGS_ICON)
                local function asbCogOff() return not BD().showInactiveBuffIcons end
                asbCog:SetAlpha(asbCogOff() and 0.15 or 0.4)
                local asbBlock = CreateFrame("Frame", nil, asbCog)
                asbBlock:SetAllPoints(); asbBlock:SetFrameLevel(asbCog:GetFrameLevel() + 10); asbBlock:EnableMouse(true)
                asbBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(asbCog, EllesmereUI.DisabledTooltip("Always Show Buffs"))
                end)
                asbBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                if asbCogOff() then asbBlock:Show() else asbBlock:Hide() end
                EllesmereUI.RegisterWidgetRefresh(function()
                    if asbCogOff() then asbCog:SetAlpha(0.15); asbBlock:Show()
                    else asbCog:SetAlpha(0.4); asbBlock:Hide() end
                end)
            end

            -- Row 2: Buff Glow + swatches | Icon Spacing
            local buffGlowRow
            buffGlowRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Buff Glow",
                  values=BUFF_GLOW_VALUES, order=BUFF_GLOW_ORDER,
                  disabled=function() return IsCustomShape() end,
                  disabledTooltip=EllesmereUI.DisabledTooltip("This option requires a non-custom button shape"),
                  getValue=function()
                      if IsCustomShape() then return 0 end
                      return BD().buffGlowType or 0
                  end,
                  setValue=function(v)
                      BD().buffGlowType = v; ns.BuildAllCDMBars(); Refresh()
                      C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                  end },
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

            -- Inline buff glow color swatches (left of row 2)
            do
                local leftRgn = buffGlowRow._leftRegion
                local ctrl = leftRgn._control

                local classSwatch, updateClassSwatch = EllesmereUI.BuildColorSwatch(
                    leftRgn, buffGlowRow:GetFrameLevel() + 3,
                    function()
                        local _, classFile = UnitClass("player")
                        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                        if cc then return cc.r, cc.g, cc.b end
                        return 1, 0.82, 0
                    end,
                    function() end,
                    false, 20)
                PP.Point(classSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                classSwatch:SetScript("OnClick", function()
                    BD().buffGlowClassColor = true; ns.BuildAllCDMBars()
                    Refresh(); EllesmereUI:RefreshPage()
                end)
                classSwatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Colored")
                end)
                classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(
                    leftRgn, buffGlowRow:GetFrameLevel() + 3,
                    function() return BD().buffGlowR or 1.0, BD().buffGlowG or 0.776, BD().buffGlowB or 0.376 end,
                    function(r, g, b)
                        BD().buffGlowR = r; BD().buffGlowG = g; BD().buffGlowB = b
                        ns.BuildAllCDMBars(); Refresh()
                    end,
                    false, 20)
                PP.Point(glowSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
                glowSwatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(glowSwatch, "Custom Colored")
                end)
                glowSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Click the dimmed custom swatch to switch back from class color (no block overlay)
                local origGlowClick = glowSwatch:GetScript("OnClick")
                glowSwatch:SetScript("OnClick", function(self, ...)
                    if BD().buffGlowClassColor then
                        BD().buffGlowClassColor = false; ns.BuildAllCDMBars()
                        Refresh(); EllesmereUI:RefreshPage()
                        return
                    end
                    -- No glow selected (or custom shape): allow swapping boxes but do not open the color picker
                    if (BD().buffGlowType or 0) == 0 or IsCustomShape() then return end
                    if origGlowClick then origGlowClick(self, ...) end
                end)

                -- Anchor for the inline pixel-glow cog (placed left of the swatches).
                leftRgn._lastInline = glowSwatch

                local function UpdateBuffGlowState()
                    local gt = BD().buffGlowType or 0
                    local noGlow = gt == 0 or IsCustomShape()
                    local isClassColored = BD().buffGlowClassColor
                    glowSwatch:SetAlpha((isClassColored or noGlow) and 0.3 or 1)
                    classSwatch:SetAlpha((isClassColored and not noGlow) and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateGlowSwatch(); updateClassSwatch(); UpdateBuffGlowState() end)
                UpdateBuffGlowState()
            end

            -- (Pixel Glow Thickness / Lines / Speed moved to a dedicated row at the
            -- bottom of this section -- see "Pixel Glow Thickness (buff bars)" below.
            -- Same buffGlow* variables, so user settings are unchanged.)

            -- Row 3: Custom Icon Shape | Icon Zoom
            local buffShapeZoomRow
            buffShapeZoomRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Custom Icon Shape",
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
                  end },
                { type="slider", text="Icon Zoom",
                  min=0, max=0.20, step=0.01,
                  getValue=function() return BD().iconZoom or 0.08 end,
                  setValue=function(v)
                      BD().iconZoom = v
                      ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                  end });  y = y - h

            -- Sync icon on Custom Icon Shape (left of row 3)
            EllesmereUI.BuildSyncIcon({
                region  = buffShapeZoomRow._leftRegion,
                tooltip = "Apply Icon Shape to all Bars",
                isSynced = function()
                    local bd = BD()
                    local v = bd.iconShape or "none"
                    local zoom = bd.iconZoom or 0.08
                    local synced = true
                    ForEachSyncBar(function(b) if (b.iconShape or "none") ~= v or (b.iconZoom or 0.08) ~= zoom then synced = false end end)
                    return synced
                end,
                onClick = function()
                    local bd = BD()
                    local v = bd.iconShape or "none"
                    local zoom = bd.iconZoom or 0.08
                    ForEachSyncBar(function(b)
                        b.iconShape = v; b.iconZoom = zoom
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
            -- Sync icon on Icon Zoom (right of row 3)
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

            -- Row 4: Border Size + swatches | Border Style dropdown + offset cog
            do
                local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
                local buffBsRow
                buffBsRow, h = W:DualRow(parent, y,
                    { type="dropdown", text="Border Size",
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
                      end },
                    { type="dropdown", text="Border Style",
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
                          if defTh then
                              bd.borderThickness = defTh; bd.borderSize = BORDER_SIZES[defTh] or 1
                          end
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                          EllesmereUI:RefreshPage()
                      end });  y = y - h
                -- Inline cog for border offset
                do
                    local rgn = buffBsRow._rightRegion
                    local _, cogShow = EllesmereUI.BuildCogPopup({
                        title = "Border Offset",
                        rows = {
                            { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                              get = function()
                                  local v = BD().borderTextureOffset
                                  if v then return v end
                                  local bd = BD()
                                  local tex = bd.borderTexture or "solid"
                                  local th = bd.borderThickness or "thin"
                                  local dox = EllesmereUI.GetBorderDefaults("cdm", tex, th)
                                  return dox
                              end,
                              set = function(v)
                                  BD().borderTextureOffset = v
                                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                              end },
                            { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                              get = function()
                                  local v = BD().borderTextureOffsetY
                                  if v then return v end
                                  local bd = BD()
                                  local tex = bd.borderTexture or "solid"
                                  local th = bd.borderThickness or "thin"
                                  local _, doy = EllesmereUI.GetBorderDefaults("cdm", tex, th)
                                  return doy
                              end,
                              set = function(v)
                                  BD().borderTextureOffsetY = v
                                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                              end },
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
                    local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                    local function UpdateCogVis()
                        local tex = BD().borderTexture or "solid"
                        if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                    end
                    EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                    UpdateCogVis()
                end
                -- Inline border color swatches on Border Size (left region of row 4)
                do
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
                            -- Picking a color always switches off class color so the
                            -- chosen custom color actually applies.
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

                    -- Clicking the custom swatch switches off class color (if on) AND
                    -- opens the color picker in the same click -- previously the first
                    -- click only toggled class color off, leaving the border black and
                    -- making it look like the swatch was stuck.
                    local origClick = swatch:GetScript("OnClick")
                    swatch:SetScript("OnClick", function(self, ...)
                        -- No border selected: don't open the color picker
                        if (BD().borderThickness or "thin") == "none" then return end
                        if BD().borderClassColor then
                            BD().borderClassColor = false
                            ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                            updateSwatch(); UpdateBorderState()
                        end
                        if origClick then origClick(self, ...) end
                    end)

                    function UpdateBorderState()
                        local isClassColored = BD().borderClassColor
                        local isNone = (BD().borderThickness or "thin") == "none"
                        swatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
                        classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
                    end
                    EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); updateClassBorderSwatch(); UpdateBorderState() end)
                    UpdateBorderState()
                end
                -- Sync icon: Border Size (left region)
                EllesmereUI.BuildSyncIcon({
                    region  = buffBsRow._leftRegion,
                    tooltip = "Apply Border Size to all Bars",
                    isSynced = function()
                        local bd = BD()
                        local v = bd.borderThickness or "thin"
                        local cc = bd.borderClassColor
                        local synced = true
                        ForEachSyncBar(function(b) if (b.borderThickness or "thin") ~= v or b.borderClassColor ~= cc then synced = false end end)
                        return synced
                    end,
                    onClick = function()
                        local bd = BD()
                        local v = bd.borderThickness or "thin"
                        local sz = bd.borderSize or 1
                        local cc = bd.borderClassColor
                        ForEachSyncBar(function(b)
                            b.borderThickness = v; b.borderSize = sz
                            b.borderClassColor = cc
                        end)
                        ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                    end,
                })
                -- Sync icon: Border Style (right region)
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
                  -- Spacing change invalidates the width/height match cache
                  -- because the cached _matchIconPhys was computed against
                  -- the old spacing -- new spacing means the icons no longer
                  -- fit the matched bar dimension.
                  bd._matchIconPhys = nil
                  bd._matchExtraPixels = nil
                  bd._matchStride = nil
                  bd._matchExtraPixelsH = nil
                  bd._matchStrideH = nil
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end });  y = y - h

        -- Sync icon on Icon Spacing (right of row 1)
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
        end -- isBuffBar else

        -- Border Style dropdown (CD/utility and non-buff bars only)
        if not isBuffGlowBar then
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local bsRow
            bsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
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
                      if defTh then
                          bd.borderThickness = defTh; bd.borderSize = BORDER_SIZES[defTh] or 1
                      end
                      ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Border Size",
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
                  end });  y = y - h
            -- Inline cog for border offset
            do
                local rgn = bsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local v = BD().borderTextureOffset
                              if v then return v end
                              local bd = BD()
                              local tex = bd.borderTexture or "solid"
                              local th = bd.borderThickness or "thin"
                              local dox = EllesmereUI.GetBorderDefaults("cdm", tex, th)
                              return dox
                          end,
                          set = function(v)
                              BD().borderTextureOffset = v
                              ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local v = BD().borderTextureOffsetY
                              if v then return v end
                              local bd = BD()
                              local tex = bd.borderTexture or "solid"
                              local th = bd.borderThickness or "thin"
                              local _, doy = EllesmereUI.GetBorderDefaults("cdm", tex, th)
                              return doy
                          end,
                          set = function(v)
                              BD().borderTextureOffsetY = v
                              ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                          end },
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
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local tex = BD().borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Sync icon: Border Style (left region of bsRow)
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
                    local bh = bd.borderBehind
                    local br, bg, bb, ba = bd.borderR, bd.borderG, bd.borderB, bd.borderA
                    local cc = bd.borderClassColor
                    ForEachSyncBar(function(b)
                        b.borderTexture = bt
                        b.borderTextureOffset = ox; b.borderTextureOffsetY = oy
                        b.borderTextureShiftX = sx; b.borderTextureShiftY = sy
                        b.borderThickness = th; b.borderSize = sz
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
            -- Inline color swatches on Border Size (right region)
            do
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
                    local isNone = (BD().borderThickness or "thin") == "none"
                    swatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
                    classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); updateClassBorderSwatch(); UpdateBorderSwatchState() end)
                UpdateBorderSwatchState()
            end
            -- Sync icon on Border Size (right region)
            EllesmereUI.BuildSyncIcon({
                region  = bsRow._rightRegion,
                tooltip = "Apply Border Size to all Bars",
                isSynced = function()
                    local bd = BD()
                    local v = bd.borderThickness or "thin"
                    local cc = bd.borderClassColor
                    local bt = bd.borderTexture or "solid"
                    local sx = bd.borderTextureShiftX
                    local sy = bd.borderTextureShiftY
                    local br, bg, bb, ba = bd.borderR or 0, bd.borderG or 0, bd.borderB or 0, bd.borderA or 1
                    local synced = true
                    ForEachSyncBar(function(b)
                        if (b.borderThickness or "thin") ~= v or b.borderClassColor ~= cc or (b.borderTexture or "solid") ~= bt then synced = false end
                        if b.borderTextureShiftX ~= sx or b.borderTextureShiftY ~= sy then synced = false end
                        if (b.borderR or 0) ~= br or (b.borderG or 0) ~= bg or (b.borderB or 0) ~= bb or (b.borderA or 1) ~= ba then synced = false end
                    end)
                    return synced
                end,
                onClick = function()
                    local bd = BD()
                    local v = bd.borderThickness or "thin"
                    local sz = bd.borderSize or 1
                    local cc = bd.borderClassColor
                    local bt = bd.borderTexture or "solid"
                    local sx = bd.borderTextureShiftX
                    local sy = bd.borderTextureShiftY
                    local br, bg, bb, ba = bd.borderR, bd.borderG, bd.borderB, bd.borderA
                    ForEachSyncBar(function(b)
                        b.borderThickness = v; b.borderSize = sz
                        b.borderClassColor = cc; b.borderTexture = bt
                        b.borderTextureShiftX = sx; b.borderTextureShiftY = sy
                        b.borderR = br; b.borderG = bg; b.borderB = bb; b.borderA = ba
                    end)
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                end,
            })
        end
        end -- not isBuffGlowBar

        -- (Active Animation UI removed -- active state is now per-icon via spell picker dropdown)

        -- (Sync) Custom Icon Shape | (Sync) Icon Zoom (CD/utility bars only;
        -- buff bars have both in their own Row 3 above)
        if not isBuffGlowBar then
        local shapeRow
        shapeRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Custom Icon Shape",
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
                end },
            { type="slider", text="Icon Zoom",
                min=0, max=0.20, step=0.01,
                getValue=function() return BD().iconZoom or 0.08 end,
                setValue=function(v)
                    BD().iconZoom = v
                    ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                end });  y = y - h

        EllesmereUI.BuildSyncIcon({
            region  = shapeRow._leftRegion,
            tooltip = "Apply Icon Shape to all Bars",
            isSynced = function()
                local bd = BD()
                local v = bd.iconShape or "none"
                local zoom = bd.iconZoom or 0.08
                local synced = true
                ForEachSyncBar(function(b) if (b.iconShape or "none") ~= v or (b.iconZoom or 0.08) ~= zoom then synced = false end end)
                return synced
            end,
            onClick = function()
                local bd = BD()
                local v = bd.iconShape or "none"
                local zoom = bd.iconZoom or 0.08
                ForEachSyncBar(function(b)
                    b.iconShape = v; b.iconZoom = zoom
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
        do
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

            local _, durCogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text",
                rows = {
                    { type="toggle", label="Show Duration",
                      get=function() return BD().showCooldownText ~= false end,
                      set=function(v)
                          BD().showCooldownText = v
                          ns.RefreshCDMIconAppearance(BD().key); Refresh(); EllesmereUI:RefreshPage()
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
            MakeCogBtn(leftRgn, durCogShow, durSwatch, EllesmereUI.DIRECTIONS_ICON)
        end

        -- Stack Size: inline color swatch + cog
        do
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

            local _, scCogShow = EllesmereUI.BuildCogPopup({
                title = "Charge/Stack Text",
                rows = {
                    { type="toggle", label="Show Item Count",
                      get=function() return BD().showItemCount ~= false end,
                      set=function(v)
                          BD().showItemCount = v
                          ns.RefreshCDMIconAppearance(BD().key); ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                      end },
                    { type="dropdown", label="Position",
                      values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                      order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
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
            })
            MakeCogBtn(rightRgn, scCogShow, scSwatch, EllesmereUI.DIRECTIONS_ICON)
        end

        -- Suppress GCD (CD/utility bars only) | Pixel Glow Thickness (+ cog: Lines/Speed)
        if not isBuffGlowBar then
        local isCDOrUtility = (barData.barType == "cooldowns" or barData.barType == "utility")
        if isCDOrUtility then
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
            do
                local rightRgn = sgcdRow._rightRegion
                local _, pgCogShow = EllesmereUI.BuildCogPopup({
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
                          disabledTooltip=EllesmereUI.DisabledTooltip("Pixel Glow Background") },
                    },
                })
                MakeCogBtn(rightRgn, pgCogShow, nil, EllesmereUI.RESIZE_ICON)
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
                { type="label", text="" });  y = y - h
            -- Inline cog on Pixel Glow Thickness: Lines + Speed (buffGlow* vars)
            do
                local leftRgn = pgRow._leftRegion
                local _, pgCogShow = EllesmereUI.BuildCogPopup({
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
                          disabledTooltip=EllesmereUI.DisabledTooltip("Pixel Glow Background") },
                    },
                })
                MakeCogBtn(leftRgn, pgCogShow, nil, EllesmereUI.RESIZE_ICON)
            end
        end

        _, h = W:Spacer(parent, y, 8);  y = y - h

        -------------------------------------------------------------------
        --  EXTRAS (not shown for custom aura bars or FocusKick)
        -------------------------------------------------------------------
        local isCustomBuffBar = (barData.barType == "custom_buff")
        local isAnyBuffBar = isBuffGlowBar  -- buffs or custom_buff
        if not isCustomBuffBar and not isFocusKick then
        _, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h

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
            { type="spacer" }
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
            { type="dropdown", text="Show Keybind",
              values = { none = "None", left = "Left Aligned", right = "Right Aligned" },
              order = { "none", "left", "right" },
              getValue=function()
                  local b = BD()
                  if not b.showKeybind then return "none" end
                  return (b.keybindAlign == "right") and "right" or "left"
              end,
              setValue=function(v)
                  local b = BD()
                  if v == "none" then
                      b.showKeybind = false
                  elseif v == "right" then
                      b.showKeybind = true; b.keybindAlign = "right"
                  else
                      b.showKeybind = true; b.keybindAlign = "left"
                  end
                  ns.RefreshCDMIconAppearance(b.key); ns.ApplyCachedKeybinds(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Inline color swatch + cog on Show Keybind (right region)
        do
            local rgn = kbRow._rightRegion
            local ctrl = rgn and rgn._control

            local kbSwatch, updateKbSwatch
            if ctrl and EllesmereUI.BuildColorSwatch then
                kbSwatch, updateKbSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, kbRow:GetFrameLevel() + 3,
                    function() return BD().keybindR or 1, BD().keybindG or 1, BD().keybindB or 1 end,
                    function(r, g, b)
                        BD().keybindR = r; BD().keybindG = g; BD().keybindB = b
                        ns.RefreshCDMIconAppearance(BD().key); ns.ApplyCachedKeybinds(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                    end,
                    false, 20)
                PP.Point(kbSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            end

            local _, kbCogShow = EllesmereUI.BuildCogPopup({
                title = "Keybind Text Settings",
                rows = {
                    { type = "slider", label = "Text Size", min = 6, max = 20, step = 1,
                      get = function() return BD().keybindSize or 10 end,
                      set = function(v) BD().keybindSize = v; ns.RefreshCDMIconAppearance(BD().key); ns.ApplyCachedKeybinds(); UpdateCDMPreview(); EllesmereUI:RefreshPage() end },
                    { type = "slider", label = "X Offset", min = -30, max = 30, step = 1,
                      get = function() return BD().keybindOffsetX or 2 end,
                      set = function(v) BD().keybindOffsetX = v; ns.RefreshCDMIconAppearance(BD().key); ns.ApplyCachedKeybinds(); UpdateCDMPreview(); EllesmereUI:RefreshPage() end },
                    { type = "slider", label = "Y Offset", min = -30, max = 30, step = 1,
                      get = function() return BD().keybindOffsetY or -2 end,
                      set = function(v) BD().keybindOffsetY = v; ns.RefreshCDMIconAppearance(BD().key); ns.ApplyCachedKeybinds(); UpdateCDMPreview(); EllesmereUI:RefreshPage() end },
                },
            })
            MakeCogBtn(rgn, kbCogShow, kbSwatch, EllesmereUI.RESIZE_ICON)

            if kbSwatch then
                local swatchBlock = CreateFrame("Frame", nil, kbSwatch)
                swatchBlock:SetAllPoints()
                swatchBlock:SetFrameLevel(kbSwatch:GetFrameLevel() + 10)
                swatchBlock:EnableMouse(true)
                swatchBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(kbSwatch, EllesmereUI.DisabledTooltip("Show Keybind"))
                end)
                swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                EllesmereUI.RegisterWidgetRefresh(function()
                    if updateKbSwatch then updateKbSwatch() end
                    local on = BD().showKeybind == true
                    kbSwatch:SetAlpha(on and 1 or 0.3)
                    if on then swatchBlock:Hide() else swatchBlock:Show() end
                end)
            end
        end
        end -- if isAnyBuffBar (tooltip only) / else (tooltip + keybind)

        -- Pandemic Glow
        do
            local function pandemicOff() return BD().pandemicGlow ~= true end
            local function antsOff()
                if pandemicOff() then return true end
                local raw = BD().pandemicGlowStyle
                return type(raw) ~= "number" or raw ~= 1
            end

            local panGlowRow
            panGlowRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Pandemic Glow",
                  values=PAN_GLOW_VALUES, order=PAN_GLOW_ORDER,
                  getValue=function()
                      if pandemicOff() then return 0 end
                      local raw = BD().pandemicGlowStyle
                      if type(raw) ~= "number" then return 1 end
                      return raw
                  end,
                  setValue=function(v)
                      if v == 0 then BD().pandemicGlow = false
                      else BD().pandemicGlow = true; BD().pandemicGlowStyle = v end
                      ns.BuildAllCDMBars(); Refresh()
                      if panGlowRow and panGlowRow._refreshPreview then panGlowRow._refreshPreview() end
                      C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                  end,
                  tooltip="Show a glow on icons when the remaining duration is in the pandemic window (last 30%)" },
                { type="label", text="Pandemic Glow Preview" });  y = y - h

            BuildPandemicPreview(panGlowRow, pandemicOff, BD)

            do
                local leftRgn = panGlowRow._leftRegion
                local ctrl = leftRgn and leftRgn._control
                if ctrl and EllesmereUI.BuildColorSwatch then
                    local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                        leftRgn, panGlowRow:GetFrameLevel() + 3,
                        function()
                            local c = BD().pandemicGlowColor
                            if c then return c.r or 1, c.g or 1, c.b or 0 end
                            return BD().pandemicR or 1, BD().pandemicG or 1, BD().pandemicB or 0
                        end,
                        function(r, g, b)
                            BD().pandemicGlowColor = { r = r, g = g, b = b }
                            ns.BuildAllCDMBars(); Refresh()
                            if panGlowRow._refreshPreview then panGlowRow._refreshPreview() end
                        end, nil, 20)
                    PP.Point(swatch, "RIGHT", ctrl, "LEFT", -12, 0)
                    leftRgn._lastInline = swatch
                    EllesmereUI.RegisterWidgetRefresh(function()
                        local off = pandemicOff()
                        swatch:SetAlpha(off and 0.15 or 1); swatch:EnableMouse(not off)
                        if updateSwatch then updateSwatch() end
                    end)
                    swatch:SetAlpha(pandemicOff() and 0.15 or 1)
                    swatch:EnableMouse(not pandemicOff())
                end
            end

            BuildPandemicCogButton(panGlowRow, antsOff, BD, function() ns.BuildAllCDMBars() end)

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

        -- Show Non-On Use Trinkets | Hide Rotation Helper
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Non-On Use Trinkets",
              tooltip = "Show equipped trinkets even if they don't have an on-use effect.",
              getValue=function() return BD().showPassiveTrinkets == true end,
              setValue=function(v)
                  BD().showPassiveTrinkets = v
                  if ns.FullCDMRebuild then ns.FullCDMRebuild("trinket_toggle") end
              end },
            { type="toggle", text="Hide Rotation Helper",
              tooltip = "Force-hide Blizzard's Assisted Combat Highlight (rotation helper glow) on all CDM bars, even if enabled in Blizzard's Combat settings.",
              getValue=function()
                  local p = DB(); return p and p.cdmBars and p.cdmBars.hideRotationHelper == true
              end,
              setValue=function(v)
                  local p = DB()
                  if p and p.cdmBars then
                      p.cdmBars.hideRotationHelper = v
                      if ns.UpdateRotationHighlights then ns.UpdateRotationHighlights() end
                  end
              end });  y = y - h

        -- Hide Items if Missing | Mirror Key Presses. Mirror Key Presses is not
        -- for buff-family bars (buffs are auto-tracked auras, not keybind-pressed
        -- abilities, so a "pressed" look has no meaning) -- those bars keep the
        -- right slot visually empty. (Per-spell threshold decimals/color moved to
        -- the per-icon dropdown: Threshold Text.)
        local mirrorCfg
        if not (ns.IsBarBuffFamily and ns.IsBarBuffFamily(barData)) then
            mirrorCfg = { type="toggle", text="Mirror Key Presses",
              tooltip = "When you press an ability's keybind, show the action button's \"pushed down\" look on its icon on this bar -- even while the ability is on cooldown.",
              getValue=function() return BD().pressMirror == true end,
              setValue=function(v)
                  BD().pressMirror = v
                  if ns.ClearCdmPressPush then ns.ClearCdmPressPush() end
              end }
        else
            mirrorCfg = { type="label", text="" }
        end
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Items if Missing",
              tooltip = "Hide consumable items (potions, healthstone) from the bar when you have none in your bags, instead of showing them dimmed. They reappear automatically once you have the item again.",
              getValue=function() return BD().hideItemsIfMissing == true end,
              setValue=function(v)
                  BD().hideItemsIfMissing = v
                  if ns.FullCDMRebuild then ns.FullCDMRebuild("hide_missing_toggle") end
              end },
            mirrorCfg);  y = y - h

        end -- custom_buff extras guard

        return math.abs(y)
    end


    ---------------------------------------------------------------------------
    --  Unlock Mode page  (opens EllesmereUI Unlock Mode overlay)
    ---------------------------------------------------------------------------
    local function BuildUnlockPage(pageName, parent, yOffset)
        C_Timer.After(0, function()
            if EllesmereUI and EllesmereUI._openUnlockMode then
                EllesmereUI._openUnlockMode()
            end
        end)
        return 0
    end

    ---------------------------------------------------------------------------
    --  One-time CDM button settings tip (shown on first CDM Bars page open)
    ---------------------------------------------------------------------------
    local _cdmButtonTip
    local function ShowCDMButtonTip()
        if EllesmereUIDB and EllesmereUIDB.cdmButtonTipSeen then return end
        local preview = EllesmereUI._contentHeaderPreview
        if not preview then return end
        if _cdmButtonTip and _cdmButtonTip:IsShown() then return end

        if not _cdmButtonTip then
            local TIP_W, TIP_H = 360, 105
            local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            local ar, ag, ab = EG.r, EG.g, EG.b
            local PP = EllesmereUI.PanelPP or EllesmereUI.PP

            local tip = CreateFrame("Frame", nil, EllesmereUI._mainFrame)
            tip:SetFrameStrata("FULLSCREEN_DIALOG")
            tip:SetFrameLevel(200)
            if PP and PP.Size then PP.Size(tip, TIP_W, TIP_H) else tip:SetSize(TIP_W, TIP_H) end
            tip:EnableMouse(true)
            tip:SetPoint("TOP", preview, "BOTTOM", 0, -12)

            -- Background
            local bg = tip:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.08, 0.10, 1)

            -- Border
            EllesmereUI.MakeBorder(tip, ar, ag, ab, 0.25, PP)

            -- Arrow pointing up
            local ARROW_SZ = 16
            local arrowClip = CreateFrame("Frame", nil, tip)
            arrowClip:SetFrameStrata("FULLSCREEN_DIALOG")
            arrowClip:SetFrameLevel(tip:GetFrameLevel() + 10)
            arrowClip:SetClipsChildren(true)
            arrowClip:SetSize(ARROW_SZ * 2, ARROW_SZ)
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
            local FONT_PATH2 = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("cdm"))
                or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
            local msg = tip:CreateFontString(nil, "OVERLAY")
            msg:SetFont(FONT_PATH2, 12, "")
            msg:SetTextColor(1, 1, 1, 0.85)
            msg:SetPoint("TOP", tip, "TOP", 0, -15)
            msg:SetWidth(TIP_W - 30)
            msg:SetJustifyH("CENTER")
            msg:SetSpacing(4)
            msg:SetText(EllesmereUI.L("CDM Buttons can have all their glow and active\nstates changed on a per icon (or synced to the bar)\nbasis. Click on a button to show that button's settings."))

            -- Okay button
            local okBtn = CreateFrame("Button", nil, tip)
            okBtn:SetSize(86, 26)
            okBtn:SetPoint("BOTTOM", tip, "BOTTOM", 0, 11)
            EllesmereUI.MakeStyledButton(okBtn, "Okay", 11,
                EllesmereUI.RB_COLOURS, function()
                    tip:Hide()
                    if EllesmereUIDB then EllesmereUIDB.cdmButtonTipSeen = true end
                end)

            _cdmButtonTip = tip
        end

        _cdmButtonTip:Show()
    end

    ---------------------------------------------------------------------------
    --  Buff bar preview overlay: a simple static frame that shows a 3-icon-
    --  width ghost over the buff bar when the CDM Bars page is open. The real
    --  buff bar is left completely untouched (no forced icons, no resize).
    ---------------------------------------------------------------------------
    local _buffBarOverlay
    -- Removed: the buffs bar no longer shows a "Buff Bar" locator overlay on the
    -- live bar while the EUI options panel is open. Kept as a no-op stub so the
    -- existing call sites (page open/close) need no changes.
    local function ShowBuffBarOverlay()
    end

    local function HideBuffBarOverlay()
        if _buffBarOverlay then _buffBarOverlay:Hide() end
    end
    ns.ShowBuffBarOverlay = ShowBuffBarOverlay
    ns.HideBuffBarOverlay = HideBuffBarOverlay

    -- Hook: show tip when CDM Bars page first renders with a preview visible
    local _cdmButtonTipQueued = false
    EllesmereUI:RegisterOnHide(function()
        if _cdmButtonTip then _cdmButtonTip:Hide() end
        -- Hide overlay and custom aura preview when panel closes
        HideBuffBarOverlay()
        ns._cdmBarsPageOpen = false
        if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
    end)


    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUICooldownManager", {
        title       = "Cooldown Manager",
        description = "CDM bar customization, action bar glows, and buff bars.",
        pages       = { PAGE_CDM_BARS, PAGE_BAR_GLOWS, PAGE_BUFF_BARS },
        disabledPages = {},
        disabledPageTooltips = {},
        buildPage   = function(pageName, parent, yOffset)
            -- ns._tbbPlaceholderMode / ns._cdmBarsPageOpen reflect whatever page
            -- the player is REALLY looking at, not the pageName this particular
            -- call happens to be building. During an off-screen search pre-build,
            -- pageName cycles through all three pages regardless of the player's
            -- actual page, so the "switched away" cleanup below (buff-bar
            -- injection/removal, placeholder toggling, the settings tip) would
            -- otherwise fire against whatever the player is really seeing. Only
            -- the requested page's content needs to be built here for indexing.
            --
            -- PAGE_BUFF_BARS is skipped entirely (not dispatched through): its
            -- builder unconditionally calls UpdateTBBPlaceholder() at its tail,
            -- which fetches each REAL tracked-buff-bar frame via
            -- ns.GetTBBFrame(i) (not scoped to `parent`) and forces it
            -- :Show() with an unlock-mode placeholder attached -- building it
            -- here would pop the player's live buff bars onto the screen. It's
            -- indexed normally the first time the player visits it live.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_CDM_BARS then
                    return BuildCDMBarsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_BAR_GLOWS then
                    return BuildBarGlowsPage(pageName, parent, yOffset)
                end
                return
            end
            -- Clear TBB placeholders when switching to any non-Tracking Bars page
            if pageName ~= PAGE_BUFF_BARS and ns._tbbPlaceholderMode then
                ns._tbbPlaceholderMode = false
                if ns.HideTBBPlaceholders then ns.HideTBBPlaceholders() end
            end
            -- Manage custom aura bar preview: flag-based, not GetActivePage
            if pageName ~= PAGE_CDM_BARS and ns._cdmBarsPageOpen then
                ns._cdmBarsPageOpen = false
                if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
                -- Page closed: reanchor so buff-bar injected custom/preset buffs
                -- that were shown for configuration (cdmPageOpen) hide unless active.
                if ns.QueueReanchor then ns.QueueReanchor() end
                HideBuffBarOverlay()
            end
            if pageName == PAGE_CDM_BARS then
                ns._cdmBarsPageOpen = true
                local h2 = BuildCDMBarsPage(pageName, parent, yOffset)
                if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
                ShowBuffBarOverlay()
                -- Show one-time button settings tip after preview renders
                C_Timer.After(0.1, ShowCDMButtonTip)
                return h2
            elseif pageName == PAGE_BAR_GLOWS then
                return BuildBarGlowsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_BUFF_BARS then
                return BuildBuffBarsPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_CDM_BARS then
                return _cdmHeaderBuilder
            elseif pageName == PAGE_BAR_GLOWS then
                return _glowHeaderBuilder
            end
            -- Tracking Bars has no content header (popout preview instead)
            return nil
        end,
        -- CDM Bars content is gated on whichever bar is currently selected
        -- (e.g. FocusKick's "Nameplate Anchor"/"Focus Text Reminders" only
        -- render while barData.key == "focuskick"), and the default selected
        -- bar is whatever's first in the player's list -- almost never
        -- FocusKick. Without this, a hidden pre-build only ever sees that one
        -- default bar's options, so every other bar's unique settings stay
        -- unsearchable until the player opens the dropdown and picks them
        -- live. Build once per distinct bar *shape* (cooldowns/utility/buffs/
        -- custom_buff/focuskick), not once per literal bar instance -- a
        -- player can have several custom bars of the same shape with
        -- identical available options, so indexing more than one of a shape
        -- would just be a wasted rebuild.
        getPrebuildVariants = function(pageName)
            if pageName ~= PAGE_CDM_BARS then return nil end
            local p = DB()
            local bars = p and p.cdmBars and p.cdmBars.bars
            if not bars or #bars == 0 then return nil end
            local seenShapes = {}
            local keys = {}
            for _, b in ipairs(bars) do
                local shape = (b.key == "focuskick") and "focuskick" or b.barType
                if shape and not seenShapes[shape] then
                    seenShapes[shape] = true
                    keys[#keys + 1] = b.key
                end
            end
            if selectedCDMBarIndex < 1 then selectedCDMBarIndex = 1 end
            if selectedCDMBarIndex > #bars then selectedCDMBarIndex = #bars end
            local currentBar = bars[selectedCDMBarIndex]
            return {
                setter = EllesmereUI._setCDMBar,
                keys = keys,
                currentKey = currentBar and currentBar.key,
            }
        end,
        onPageCacheRestore = function(pageName)
            -- Same flag management as buildPage
            if pageName ~= PAGE_BUFF_BARS and ns._tbbPlaceholderMode then
                ns._tbbPlaceholderMode = false
                if ns.HideTBBPlaceholders then ns.HideTBBPlaceholders() end
            end
            if pageName ~= PAGE_CDM_BARS and ns._cdmBarsPageOpen then
                ns._cdmBarsPageOpen = false
                if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
                -- Page closed: reanchor so buff-bar injected custom/preset buffs
                -- that were shown for configuration (cdmPageOpen) hide unless active.
                if ns.QueueReanchor then ns.QueueReanchor() end
                HideBuffBarOverlay()
            end
            if pageName == PAGE_BUFF_BARS then
                if ns.ShowTBBPlaceholders then ns.ShowTBBPlaceholders() end
                RefreshTBBPopout()
            end
            if pageName == PAGE_CDM_BARS then
                ns._cdmBarsPageOpen = true
                if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
                ShowBuffBarOverlay()
                -- Re-sync _cdmPreview after cache restore and refresh the preview
                if not _cdmPreview and EllesmereUI._contentHeaderPreview then
                    _cdmPreview = EllesmereUI._contentHeaderPreview
                end
                if _cdmPreview and _cdmPreview.Update then
                    _cdmPreview:Update()
                end
            end
        end,
        onReset = function()
            if _G._ECME_AceDB then
                _G._ECME_AceDB:ResetProfile()
                -- Clear the per-install capture flag so the snapshot re-runs
                -- after reload and picks up Blizzard's current CDM layout.
                if _G._ECME_AceDB.sv then
                    _G._ECME_AceDB.sv._capturedOnce_CDM = nil
                end
            end
            -- Wipe spell assignments for the current spec so the init
            -- snapshot re-populates from Blizzard's CDM. Spell data lives
            -- in EllesmereUIDB (per-profile store), not the AceDB profile, so
            -- ResetProfile doesn't touch it. Only clear the ACTIVE profile's
            -- current spec to preserve other specs and other profiles.
            if ns and ns.GetActiveSpecProfiles then
                local sp = ns.GetActiveSpecProfiles()
                local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                if sp and specKey and specKey ~= "0" then
                    sp[specKey] = nil
                end
            end
            ReloadUI()
        end,
    })

    SLASH_ECMEOPT1 = "/ecmeopt"
    SlashCmdList.ECMEOPT = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUICooldownManager")
    end



    -- Debug: /cdmpassive <spellID> -- checks why a spell is or isn't in the picker
    SLASH_CDMPASSIVE1 = "/cdmpassive"
    SlashCmdList.CDMPASSIVE = function(msg)
        local sid = tonumber(msg)
        if not sid then print("|cffff0000Usage: /cdmpassive <spellID>|r") return end
        local name = C_Spell.GetSpellName(sid) or "?"
        local isPassive = C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(sid)
        local baseCd = C_Spell.GetSpellBaseCooldown and C_Spell.GetSpellBaseCooldown(sid)
        local charges = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
        local maxCh = charges and charges.maxCharges or 0
        print("|cff00ccff[CDM Passive Debug]|r " .. name .. " (" .. sid .. ")")
        print("  IsSpellPassive: " .. tostring(isPassive))
        print("  GetSpellBaseCooldown: " .. tostring(baseCd))
        print("  maxCharges: " .. tostring(maxCh))
        -- Check all CDM categories for this spell
        if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
            for cat = 0, 3 do
                local allIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true) or {}
                local knownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, false) or {}
                local knownSet = {}
                for _, id in ipairs(knownIDs) do knownSet[id] = true end
                for _, cdID in ipairs(allIDs) do
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                    if info then
                        local infoSid = info.spellID
                        if info.overrideSpellID and info.overrideSpellID > 0 then infoSid = info.overrideSpellID end
                        if info.linkedSpellID and info.linkedSpellID > 0 then infoSid = info.linkedSpellID end
                        if infoSid == sid or info.spellID == sid then
                            print("  Found in cat " .. cat .. " cdID=" .. cdID .. " known=" .. tostring(knownSet[cdID] or false))
                        end
                    end
                end
            end
        end
        -- Check viewer children
        local viewers = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
        for _, vn in ipairs(viewers) do
            local vf = _G[vn]
            if vf then
                for i = 1, vf:GetNumChildren() do
                    local child = select(i, vf:GetChildren())
                    if child then
                        local csid
                        if child.GetSpellID then
                            local ok, v = pcall(child.GetSpellID, child)
                            if ok and v then csid = v end
                        end
                        if not csid and child.GetAuraSpellID then
                            local ok, v = pcall(child.GetAuraSpellID, child)
                            if ok and v then csid = v end
                        end
                        if csid == sid then
                            print("  Viewer child in " .. vn .. " index=" .. i)
                        end
                    end
                end
            end
        end
    end
end)
