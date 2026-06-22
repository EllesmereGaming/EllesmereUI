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
                        label = bd.name or bd.key,
                    }
                end
            end
        end
        for i = 1, 8 do
            list[#list + 1] = { value = i, label = BG_ACTION_BAR_LABELS[i] }
        end
        return list
    end

    local function GetBGTargetLabel(sel)
        sel = NormalizeSelectedBar(sel)
        if type(sel) == "number" then
            return BG_ACTION_BAR_LABELS[sel] or ("Action Bar " .. sel)
        end
        local p = ns.ECME and ns.ECME.db and ns.ECME.db.profile
        if p and p.cdmBars and p.cdmBars.bars then
            for _, bd in ipairs(p.cdmBars.bars) do
                if bd.key == sel then return bd.name or bd.key end
            end
        end
        return tostring(sel)
    end

    local BG_MODE_VALUES = { ACTIVE = "Buff Active", MISSING = "Buff Missing" }
    local BG_MODE_ORDER  = { "ACTIVE", "MISSING" }

    -- Build glow style dropdown values from ns.GLOW_STYLES
    local function GetGlowStyleValues()
        local labels, order = {}, {}
        if ns.GLOW_STYLES then
            for i, entry in ipairs(ns.GLOW_STYLES) do
                labels[i] = entry.name or ("Style " .. i)
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

    -- Get nameplate profile from central DB
    local function GetNPProfile()
        if not EllesmereUIDB or not EllesmereUIDB.profiles then return nil end
        local pName = EllesmereUIDB.activeProfile or "Default"
        local prof = EllesmereUIDB.profiles[pName]
        return prof and prof.addons and prof.addons.EllesmereUINameplates
    end

    -- Copy pandemic fields from one table to another
    local function CopyPandemicFields(src, dst)
        dst.pandemicGlow = src.pandemicGlow
        dst.pandemicGlowStyle = src.pandemicGlowStyle
        dst.pandemicGlowColor = src.pandemicGlowColor and CopyTable(src.pandemicGlowColor) or nil
        dst.pandemicGlowLines = src.pandemicGlowLines
        dst.pandemicGlowThickness = src.pandemicGlowThickness
        dst.pandemicGlowSpeed = src.pandemicGlowSpeed
    end

    -- Compare pandemic fields between two tables
    local function PandemicFieldsMatch(a, b)
        if (a.pandemicGlow or false) ~= (b.pandemicGlow or false) then return false end
        if (a.pandemicGlowStyle or 1) ~= (b.pandemicGlowStyle or 1) then return false end
        local ac = a.pandemicGlowColor or {}
        local bc = b.pandemicGlowColor or {}
        if (ac.r or 1) ~= (bc.r or 1) or (ac.g or 1) ~= (bc.g or 1) or (ac.b or 0) ~= (bc.b or 0) then return false end
        if (a.pandemicGlowLines or 8) ~= (b.pandemicGlowLines or 8) then return false end
        if (a.pandemicGlowThickness or 2) ~= (b.pandemicGlowThickness or 2) then return false end
        if (a.pandemicGlowSpeed or 4) ~= (b.pandemicGlowSpeed or 4) then return false end
        return true
    end

    -- Apply pandemic settings to all targets (NP, CDM bars) except skipKey
    local function ApplyPandemicToAll(src, skipCdmKey)
        local np = GetNPProfile()
        if np then CopyPandemicFields(src, np) end
        local pdb = DB()
        if pdb and pdb.cdmBars and pdb.cdmBars.bars then
            for _, b in ipairs(pdb.cdmBars.bars) do
                if b.key ~= skipCdmKey and not b.isGhostBar and b.barType ~= "custom_buff" then
                    CopyPandemicFields(src, b)
                end
            end
        end
        ns.BuildAllCDMBars()
        if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
        Refresh()
    end

    -- Check if pandemic settings are synced across all targets
    local function IsPandemicSyncedEverywhere(src, skipCdmKey)
        local np = GetNPProfile()
        if np and not PandemicFieldsMatch(src, np) then return false end
        local pdb = DB()
        if pdb and pdb.cdmBars and pdb.cdmBars.bars then
            for _, b in ipairs(pdb.cdmBars.bars) do
                if b.key ~= skipCdmKey and not b.isGhostBar and b.barType ~= "custom_buff"
                   and not PandemicFieldsMatch(src, b) then return false end
            end
        end
        return true
    end

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
    local PG_DEFAULT_KEYS = { lines = "pandemicGlowLines", thickness = "pandemicGlowThickness", speed = "pandemicGlowSpeed" }
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
            local BORDER_COLOR   = EllesmereUI.BORDER_COLOR

            local SIDE_PAD = 14; local TOP_PAD = 14
            local TITLE_H = 11; local TITLE_GAP = 10; local GAP = 10
            local ROW_H = 24; local POPUP_INPUT_A = 0.55
            local INPUT_W = 34; local SLIDER_INPUT_GAP = 8; local LABEL_SLIDER_GAP = 12
            local MIN_POPUP_W = 180

            local totalH = TOP_PAD + TITLE_H + TITLE_GAP + GAP + ROW_H + GAP + ROW_H + GAP + ROW_H + TOP_PAD

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
            for _, txt in ipairs({"Lines", "Thickness", "Speed"}) do
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
            lbl:SetText(sp.name)
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

            -- CDM bars: count icons dynamically; action bars: always 12
            local NUM_BUTTONS = 12
            if isCDMBar and ns.cdmBarIcons and ns.cdmBarIcons[cdmBarKey] then
                NUM_BUTTONS = #ns.cdmBarIcons[cdmBarKey]
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
                local _rbTex = realBtn and ((ns._hookFrameData[realBtn] and ns._hookFrameData[realBtn].tex) or realBtn._tex)
                local hasAction = realBtn and ((realBtn.icon and realBtn.icon:GetTexture()) or (_rbTex and _rbTex:GetTexture()))
                local iconTex = bf:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                UnsnapTex(iconTex)
                if hasAction then
                    local srcTex = (realBtn.icon and realBtn.icon:GetTexture()) or (_rbTex and _rbTex:GetTexture())
                    iconTex:SetTexture(srcTex)
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
                        for _, region in ipairs({bf:GetRegions()}) do
                            if region:IsObjectType("Texture") and region:GetTexture() and SHAPE_BORDERS and SHAPE_BORDERS[btnShape]
                               and region:GetDrawLayer() == "OVERLAY" then
                                region:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            end
                        end
                    elseif accentBrd then
                        accentBrd:Show()
                    end
                end

                -- Show white border for assigned buttons (even if not active)
                if hasAssign and not isSelected then
                    if isCustomShape then
                        for _, region in ipairs({bf:GetRegions()}) do
                            if region:IsObjectType("Texture") and region:GetTexture() and SHAPE_BORDERS and SHAPE_BORDERS[btnShape]
                               and region:GetDrawLayer() == "OVERLAY" then
                                region:SetVertexColor(1, 1, 1, 0.6)
                            end
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
                bf._shapeBorderTex = nil
                if isCustomShape and SHAPE_BORDERS and SHAPE_BORDERS[btnShape] then
                    for _, region in ipairs({bf:GetRegions()}) do
                        if region:IsObjectType("Texture") and region:GetDrawLayer() == "OVERLAY" then
                            bf._shapeBorderTex = region
                            break
                        end
                    end
                end
                local origBrdR, origBrdG, origBrdB, origBrdA = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
                if isCDMBar and cdmBd then
                    origBrdR = cdmBd.borderR or 0
                    origBrdG = cdmBd.borderG or 0
                    origBrdB = cdmBd.borderB or 0
                    origBrdA = (cdmBd.borderSize or 1) > 0 and (cdmBd.borderA or 1) or 0
                elseif brdSize == 0 then
                    origBrdA = 0
                end
                if not isSelected then
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
        do
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

                    -- Get the button's spell name for the header
                    local btnSpellName = "Button " .. curBtn
                    if isCurCDM then
                        local cdmIcons = ns.cdmBarIcons and ns.cdmBarIcons[curBar]
                        local icon = cdmIcons and cdmIcons[curBtn]
                        if icon and icon.cooldownID then
                            btnSpellName = C_Spell.GetSpellName(icon.cooldownID) or btnSpellName
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

                    -- Row 1: Glow When | Remove Glow
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
                        { type = "labeledButton", text = "Remove Glow", buttonText = "Remove", width = 150,
                          onClick = function()
                              table.remove(buffList, removeAIdx)
                              if #buffList == 0 then
                                  bg.assignments[assignKey] = nil
                              end
                              Refresh()
                              EllesmereUI:RefreshPage(true)
                          end,
                        }
                    );  y = y - h

                    -- Buff icon next to the Remove button
                    do
                        local rightRgn = modeRow._rightRegion
                        if rightRgn and rightRgn._control then
                            local btn = rightRgn._control
                            local btnH = btn:GetHeight()
                            local ico = rightRgn:CreateTexture(nil, "ARTWORK")
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
                          disabledValues = function(v)
                              if not BarHasCustomShape(curBar) and tonumber(v) == 2 then
                                  return "Custom Shape Glow requires a custom button shape"
                              end
                          end,
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
                end
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Buff Bars page per-bar tracked buff bars with individual settings)
    ---------------------------------------------------------------------------
    local _tbbSelectedBar = 1
    local _tbbHeaderBuilder
    local _tbbHeaderFixedH = 0
    local _tbbPvFrame
    local _tbbPvIcon

    -- Pool of unlock placeholders, one per bar (module-scope for cross-page access)
    local _tbbPlaceholders = {}
    local function UpdateTBBPlaceholder()
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

        local trackedBars = ns.GetTrackedBarSpells and ns.GetTrackedBarSpells() or {}
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
        local isCustomSelected = barCfg.spellID and barCfg.spellID > 0 and not barCfg.popularKey and not barCfg.spellIDs
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
            lbl:SetText(entry.name)
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
            lbl:SetText(sp.name)
            lbl:SetTextColor(baseR, baseG, baseB, baseA)

            local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)

            -- Gray out if already used on another bar
            if usedOnBar and not isSelected then
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                ico:SetDesaturated(true); ico:SetAlpha(0.4)
                item:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(item, "Already assigned to " .. usedOnBar)
                    hl:SetColorTexture(1, 1, 1, hlA * 0.3); hl:SetAlpha(1)
                end)
                item:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                    hl:SetAlpha(0)
                end)
                mH = mH + ITEM_H
                return
            end

            item:SetScript("OnEnter", function() lbl:SetTextColor(1,1,1,1); hl:SetColorTexture(1,1,1,hlA) end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(baseR, baseG, baseB, baseA)
                hl:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)
            end)
            item:SetScript("OnClick", function()
                menu:Hide()
                barCfg.spellID        = sp.spellID
                barCfg.spellIDs       = nil
                barCfg.popularKey     = nil
                barCfg.glowBased      = nil
                barCfg.customDuration = nil
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

        -- Action buttons: use Blizzard bars + open Blizzard CDM
        _, h = W:WideDualButton(parent,
            "Use Blizzard CDM Bars", "Open Blizzard CDM", y,
            function()
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
            end,
            function()
                if ns.OpenBlizzardCDMTab then
                    ns.OpenBlizzardCDMTab(true)
                end
            end, 310);  y = y - h

        local tbb = ns.GetTrackedBuffBars()
        local bars = tbb.bars
        if _tbbSelectedBar > #bars then _tbbSelectedBar = math.max(1, #bars) end

        local function SelectedTBB()
            local t = ns.GetTrackedBuffBars()
            if _tbbSelectedBar < 1 or _tbbSelectedBar > #t.bars then return nil end
            return t.bars[_tbbSelectedBar]
        end

        local _tbbRefreshTimer

        local function RefreshTBB()
            if _tbbRefreshTimer then _tbbRefreshTimer:Cancel() end
            _tbbRefreshTimer = C_Timer.NewTimer(0.05, function()
                _tbbRefreshTimer = nil
                Refresh()
                ns.BuildTrackedBuffBars()
                EllesmereUI:SetContentHeader(_tbbHeaderBuilder)
                UpdateTBBPlaceholder()
            end)
        end

        -------------------------------------------------------------------
        --  CONTENT HEADER  (dropdown + bar preview)
        -------------------------------------------------------------------
        EllesmereUI:ClearContentHeader()

        _tbbHeaderBuilder = function(hdr, hdrW)
            local PAD = EllesmereUI.CONTENT_PAD or 10
            local PV_PAD = 10
            local fy = -20

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
            local arrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, EllesmereUI.PanelPP)
            ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

            local function UpdateDDLabel()
                local bd = SelectedTBB()
                if bd then
                    local label = bd.name or "Bar"
                    if not bd.popularKey and bd.spellID and bd.spellID > 0 then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(bd.spellID)
                        if info and info.name then label = info.name end
                    end
                    ddLbl:SetText(label)
                elseif #bars == 0 then
                    ddLbl:SetText(EllesmereUI.L("No Bars - Click to Add"))
                else
                    ddLbl:SetText(EllesmereUI.L("Select a bar"))
                end
            end
            UpdateDDLabel()

            -- Custom dropdown menu
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

                local mH = 4
                for idx, b in ipairs(t.bars) do
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
                    local displayName = b.name or ("Bar " .. idx)
                    if not b.popularKey and b.spellID and b.spellID > 0 then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(b.spellID)
                        if info and info.name then displayName = info.name end
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
                        _tbbSelectedBar = idx
                        EllesmereUI:RefreshPage(true)
                    end)
                    mH = mH + ITEM_H
                end

                -- Divider
                local div = menu:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1); div:SetColorTexture(1, 1, 1, 0.10)
                div:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH - 4)
                div:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9

                -- Add New Bar
                local addItem = CreateFrame("Button", nil, menu)
                addItem:SetHeight(ITEM_H)
                addItem:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
                addItem:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                addItem:SetFrameLevel(menu:GetFrameLevel() + 2)
                local addLbl = addItem:CreateFontString(nil, "OVERLAY")
                addLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                addLbl:SetPoint("LEFT", addItem, "LEFT", 10, 0)
                addLbl:SetJustifyH("LEFT")
                addLbl:SetText(EllesmereUI.L("+ Add New Bar"))
                addLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                local addHl = addItem:CreateTexture(nil, "ARTWORK")
                addHl:SetAllPoints(); addHl:SetColorTexture(1, 1, 1, 1); addHl:SetAlpha(0)
                addItem:SetScript("OnEnter", function() addLbl:SetTextColor(1,1,1,1); addHl:SetAlpha(hlA) end)
                addItem:SetScript("OnLeave", function() addLbl:SetTextColor(tDimR,tDimG,tDimB,tDimA); addHl:SetAlpha(0) end)
                addItem:SetScript("OnClick", function()
                    menu:Hide()
                    local newIdx = ns.AddTrackedBuffBar()
                    _tbbSelectedBar = newIdx
                    EllesmereUI:RefreshPage(true)
                end)
                mH = mH + ITEM_H

                menu:SetHeight(mH + 4)
                menu:SetScript("OnUpdate", function(m)
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
            ddBtn:SetScript("OnClick", function() if ddMenu and ddMenu:IsShown() then ddMenu:Hide() else BuildDDMenu() end end)
            ddBtn:HookScript("OnHide", function() if ddMenu then ddMenu:Hide() end end)

            PP.Point(ddBtn, "TOP", hdr, "TOP", 0, fy)
            fy = fy - DD_H - 15

            -- Bar preview: matches real bar orientation and dimensions.
            -- Wrapped in a scroll container capped at 200px so tall vertical
            -- bars don't push the options section off-screen.
            local bd = SelectedTBB()
            local rawW = bd and bd.width or 270
            local rawH = bd and bd.height or 24
            local isVert = bd and bd.verticalOrientation
            local PREVIEW_W = rawW
            local PREVIEW_H = rawH
            local maxAvailW = hdrW - PAD * 2
            if PREVIEW_W > maxAvailW then PREVIEW_W = maxAvailW end

            -- Include icon in total preview dimensions (mirrors live wrapFrame sizing)
            local pvIconMode = bd and bd.iconDisplay or "none"
            local hasIcon = bd and ((bd.spellID and bd.spellID > 0) or bd.glowBased)
            local pvHasIcon = pvIconMode ~= "none" and hasIcon
            local pvIconSize = 0
            if pvHasIcon then
                pvIconSize = isVert and PREVIEW_W or PREVIEW_H
                if isVert then PREVIEW_H = PREVIEW_H + pvIconSize
                else PREVIEW_W = PREVIEW_W + pvIconSize end
                if PREVIEW_W > maxAvailW then PREVIEW_W = maxAvailW end
            end

            local TBB_PREVIEW_MAX_H = 200

            -- Wrapper: clips children, capped height
            local pvWrapper = CreateFrame("Frame", nil, hdr)
            local visH = math.min(PREVIEW_H, TBB_PREVIEW_MAX_H)
            pvWrapper:SetSize(maxAvailW, visH)
            PP.Point(pvWrapper, "TOP", hdr, "TOP", 0, fy)
            pvWrapper:SetClipsChildren(true)

            -- Scroll frame inside wrapper
            local pvSF = CreateFrame("ScrollFrame", nil, pvWrapper)
            pvSF:SetAllPoints()
            pvSF:EnableMouseWheel(true)

            -- Actual preview content frame (scroll child)
            local pvFrame = CreateFrame("Frame", nil, pvSF)
            pvFrame:SetSize(maxAvailW, PREVIEW_H)
            pvSF:SetScrollChild(pvFrame)

            -- Scrollbar track + thumb (same pattern as action bar preview)
            local pvTrack, pvThumb
            if PREVIEW_H > TBB_PREVIEW_MAX_H then
                pvTrack = CreateFrame("Frame", nil, pvWrapper)
                pvTrack:SetWidth(4)
                pvTrack:SetPoint("TOPRIGHT", pvWrapper, "TOPRIGHT", -2, -2)
                pvTrack:SetPoint("BOTTOMRIGHT", pvWrapper, "BOTTOMRIGHT", -2, 2)
                pvTrack:SetFrameLevel(pvWrapper:GetFrameLevel() + 5)
                local tbg = pvTrack:CreateTexture(nil, "BACKGROUND")
                tbg:SetAllPoints(); tbg:SetColorTexture(1, 1, 1, 0.02)

                pvThumb = CreateFrame("Button", nil, pvTrack)
                pvThumb:SetWidth(4)
                pvThumb:SetFrameLevel(pvTrack:GetFrameLevel() + 1)
                pvThumb:EnableMouse(true)
                pvThumb:RegisterForDrag("LeftButton")
                local tt = pvThumb:CreateTexture(nil, "ARTWORK")
                tt:SetAllPoints(); tt:SetColorTexture(1, 1, 1, 0.27)
            end

            local pvScrollTarget = 0
            local pvSmoothing = false
            local PV_SCROLL_STEP = 40
            local PV_SMOOTH_SPEED = 12
            local pvSmoothFrame = CreateFrame("Frame")
            pvSmoothFrame:Hide()

            local function UpdatePVThumb()
                if not pvTrack then return end
                local maxScroll = EllesmereUI.SafeScrollRange(pvSF)
                if maxScroll <= 0 then pvTrack:Hide(); return end
                pvTrack:Show()
                local trackH = pvTrack:GetHeight()
                local sfVisH = pvSF:GetHeight()
                local ratio = sfVisH / (sfVisH + maxScroll)
                local thumbH = math.max(20, trackH * ratio)
                pvThumb:SetHeight(thumbH)
                local curScroll = 0
                do
                    local ok, val = pcall(pvSF.GetVerticalScroll, pvSF)
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
                local cur = pvSF:GetVerticalScroll()
                local maxScroll = EllesmereUI.SafeScrollRange(pvSF)
                pvScrollTarget = math.max(0, math.min(maxScroll, pvScrollTarget))
                local diff = pvScrollTarget - cur
                if math.abs(diff) < 0.3 then
                    pvSF:SetVerticalScroll(pvScrollTarget)
                    UpdatePVThumb()
                    pvSmoothing = false
                    pvSmoothFrame:Hide()
                    return
                end
                local newScroll = cur + diff * math.min(1, PV_SMOOTH_SPEED * elapsed)
                newScroll = math.max(0, math.min(maxScroll, newScroll))
                pvSF:SetVerticalScroll(newScroll)
                UpdatePVThumb()
            end)

            local function PVSmoothScrollTo(target)
                local maxScroll = EllesmereUI.SafeScrollRange(pvSF)
                pvScrollTarget = math.max(0, math.min(maxScroll, target))
                if not pvSmoothing then
                    pvSmoothing = true
                    pvSmoothFrame:Show()
                end
            end

            pvSF:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = EllesmereUI.SafeScrollRange(self)
                if maxScroll <= 0 then return end
                local base = pvSmoothing and pvScrollTarget or self:GetVerticalScroll()
                PVSmoothScrollTo(base - delta * PV_SCROLL_STEP)
            end)
            pvSF:SetScript("OnScrollRangeChanged", UpdatePVThumb)

            if pvThumb then
                pvThumb:SetScript("OnMouseDown", function(self, button)
                    if button ~= "LeftButton" then return end
                    pvSmoothing = false
                    pvSmoothFrame:Hide()
                    local _, cursorY = GetCursorPosition()
                    local dragStartY = cursorY / self:GetEffectiveScale()
                    local dragStartScroll = pvSF:GetVerticalScroll()
                    self:SetScript("OnUpdate", function(self2)
                        if not IsMouseButtonDown("LeftButton") then
                            self2:SetScript("OnUpdate", nil); return
                        end
                        local _, cy = GetCursorPosition()
                        cy = cy / self2:GetEffectiveScale()
                        local deltaY = dragStartY - cy
                        local trackH = pvTrack:GetHeight()
                        local maxTravel = trackH - self2:GetHeight()
                        if maxTravel <= 0 then return end
                        local maxScroll = EllesmereUI.SafeScrollRange(pvSF)
                        local newScroll = math.max(0, math.min(maxScroll,
                            dragStartScroll + (deltaY / maxTravel) * maxScroll))
                        pvScrollTarget = newScroll
                        pvSF:SetVerticalScroll(newScroll)
                        UpdatePVThumb()
                    end)
                end)
                pvThumb:SetScript("OnMouseUp", function(self, button)
                    if button ~= "LeftButton" then return end
                    self:SetScript("OnUpdate", nil)
                end)
            end

            _tbbPvFrame = pvFrame
            _tbbPvFrame._wrapper = pvWrapper

            if bd then
                -- Content wrapper: sized to bar+icon, centered in pvFrame.
                -- Bar, icon, border, and highlight all parent to this.
                local pvContent = CreateFrame("Frame", nil, pvFrame)
                pvContent:SetSize(PREVIEW_W, PREVIEW_H)
                pvContent:SetPoint("TOP", pvFrame, "TOP", 0, 0)

                local barW = rawW
                local barH = rawH
                if barW > maxAvailW then barW = maxAvailW end
                local pvBar = CreateFrame("StatusBar", nil, pvContent)
                pvBar:SetSize(barW, barH)
                -- Position bar within content: leave room for icon
                if pvHasIcon and isVert and pvIconMode == "left" then
                    pvBar:SetPoint("TOP", pvContent, "TOP", 0, -pvIconSize)
                elseif pvHasIcon and not isVert and pvIconMode == "left" then
                    pvBar:SetPoint("TOPLEFT", pvContent, "TOPLEFT", pvIconSize, 0)
                else
                    pvBar:SetPoint("TOP", pvContent, "TOP", 0, 0)
                end
                local texPath = EllesmereUI.ResolveTexturePath(ns.TBB_TEXTURES, bd.texture or "none", "Interface\\Buttons\\WHITE8x8")
                pvBar:SetStatusBarTexture(texPath)
                pvBar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
                pvBar:SetMinMaxValues(0, 1)
                pvBar:SetValue(0.65)
                local pvFillR, pvFillG, pvFillB, pvFillA = bd.fillR or 0.05, bd.fillG or 0.82, bd.fillB or 0.62, bd.fillA or 1
                local fillTex = pvBar:GetStatusBarTexture()
                if bd.gradientEnabled then
                    local dir = bd.gradientDir or "HORIZONTAL"
                    fillTex:SetGradient(dir,
                        CreateColor(pvFillR, pvFillG, pvFillB, pvFillA),
                        CreateColor(bd.gradientR or 0.20, bd.gradientG or 0.20, bd.gradientB or 0.80, bd.gradientA or 1))
                else
                    fillTex:SetVertexColor(pvFillR, pvFillG, pvFillB, pvFillA)
                end

                local pvBg = pvBar:CreateTexture(nil, "BACKGROUND")
                pvBg:SetAllPoints(); pvBg:SetColorTexture(bd.bgR or 0, bd.bgG or 0, bd.bgB or 0, bd.bgA or 0.4)

                if bd.showSpark then
                    local spark = pvBar:CreateTexture(nil, "OVERLAY", nil, 2)
                    spark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
                    spark:SetBlendMode("ADD")
                    if isVert then
                        spark:SetSize(PREVIEW_W, 8)
                        spark:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
                        spark:SetPoint("CENTER", pvBar:GetStatusBarTexture(), "TOP", 0, 0)
                    else
                        spark:SetSize(8, PREVIEW_H)
                        spark:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
                        spark:SetPoint("CENTER", pvBar:GetStatusBarTexture(), "RIGHT", 0, 0)
                    end
                end

                -- Text overlay: sits above fill and gradient so text is never obscured
                local pvTextOverlay = CreateFrame("Frame", nil, pvBar)
                pvTextOverlay:SetAllPoints(pvBar)
                pvTextOverlay:SetFrameLevel(pvBar:GetFrameLevel() + 3)

                -- Helper: position a preview FontString based on a position key
                local function PositionPVText(fs, pos, xOff, yOff)
                    fs:ClearAllPoints()
                    if pos == "center" then
                        fs:SetPoint("CENTER", pvBar, "CENTER", xOff, yOff)
                        fs:SetJustifyH("CENTER")
                    elseif pos == "top" then
                        fs:SetPoint("BOTTOM", pvBar, "TOP", xOff, 5 + yOff)
                        fs:SetJustifyH("CENTER")
                    elseif pos == "bottom" then
                        fs:SetPoint("TOP", pvBar, "BOTTOM", xOff, -5 + yOff)
                        fs:SetJustifyH("CENTER")
                    elseif pos == "left" then
                        fs:SetPoint("LEFT", pvBar, "LEFT", 5 + xOff, yOff)
                        fs:SetJustifyH("LEFT")
                    elseif pos == "right" then
                        fs:SetPoint("RIGHT", pvBar, "RIGHT", -5 + xOff, yOff)
                        fs:SetJustifyH("RIGHT")
                    end
                end

                -- Timer preview
                local timerPos = bd.timerPosition or (bd.showTimer and "right" or "none")
                if timerPos ~= "none" then
                    local timer = pvTextOverlay:CreateFontString(nil, "OVERLAY")
                    SetPVFont(timer, FONT_PATH, bd.timerSize or 11)
                    timer:SetTextColor(1, 1, 1, 0.9)
                    PositionPVText(timer, timerPos, bd.timerX or 0, bd.timerY or 0)
                    timer:SetText("3.2")
                end

                -- Stacks preview
                local stacksPos = bd.stacksPosition or "center"
                if stacksPos ~= "none" then
                    local stacksFs = pvTextOverlay:CreateFontString(nil, "OVERLAY")
                    SetPVFont(stacksFs, FONT_PATH, bd.stacksSize or 11)
                    stacksFs:SetTextColor(1, 1, 1, 0.9)
                    PositionPVText(stacksFs, stacksPos, bd.stacksX or 0, bd.stacksY or 0)
                    stacksFs:SetText("3")
                end

                -- Name preview (hidden in vertical orientation)
                local namePos = bd.namePosition or ((bd.showName ~= false) and "left" or "none")
                if namePos ~= "none" and not bd.verticalOrientation then
                    local nameFs = pvTextOverlay:CreateFontString(nil, "OVERLAY")
                    SetPVFont(nameFs, FONT_PATH, bd.nameSize or 11)
                    nameFs:SetTextColor(1, 1, 1, 0.9)
                    PositionPVText(nameFs, namePos, bd.nameX or 0, bd.nameY or 0)
                    -- Prefer bd.name (custom name) over spell lookup so custom items show correctly
                    local displayName = bd.name
                    if (not displayName or displayName == "" or displayName == "New Bar") and bd.spellID and bd.spellID > 0 then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(bd.spellID)
                        displayName = info and info.name
                    end
                    if displayName and displayName ~= "" and ((bd.spellID and bd.spellID > 0) or bd.glowBased) then
                        nameFs:SetText(displayName)
                    else
                        nameFs:ClearAllPoints()
                        nameFs:SetPoint("CENTER", pvBar, "CENTER", 0, 0)
                        nameFs:SetJustifyH("CENTER")
                        nameFs:SetText(EllesmereUI.L("Click to assign a buff"))
                        nameFs:SetTextColor(1, 1, 1, 1)
                    end
                else
                    -- No name text, but still show hint if no spell assigned
                    if (not bd.spellID or bd.spellID == 0) and not bd.glowBased then
                        local nameFs = pvTextOverlay:CreateFontString(nil, "OVERLAY")
                        nameFs:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        nameFs:SetTextColor(1, 1, 1, 1)
                        nameFs:SetPoint("CENTER", pvBar, "CENTER", 0, 0)
                        nameFs:SetJustifyH("CENTER")
                        nameFs:SetText(EllesmereUI.L("Click to assign a buff"))
                    end
                end

                -- Dark overlay for unassigned bars so the hint text is readable
                if (not bd.spellID or bd.spellID == 0) and not bd.glowBased then
                    local darkOv = pvBar:CreateTexture(nil, "ARTWORK", nil, 2)
                    darkOv:SetAllPoints(pvBar)
                    darkOv:SetColorTexture(0, 0, 0, 0.75)
                end

                pvBar:SetAlpha(bd.opacity or 1.0)

                -- Threshold tick marks on preview bar
                if bd.stackThresholdEnabled and bd.stackThresholdMaxEnabled and ns.ApplyTBBTickMarks then
                    if not pvBar._threshTicks then pvBar._threshTicks = {} end
                    ns.ApplyTBBTickMarks(pvBar, bd, pvBar._threshTicks, bd.verticalOrientation)
                end

                -- Icon preview: parented to pvFrame (scroll child).
                -- Size always matches bar short side.
                _tbbPvIcon = nil
                local pvIconFrame = nil
                if pvHasIcon then
                    pvIconFrame = CreateFrame("Frame", nil, pvContent)
                    local iSize = isVert and PREVIEW_W or PREVIEW_H
                    pvIconFrame:SetSize(iSize, iSize)
                    pvIconFrame:SetFrameLevel(pvFrame:GetFrameLevel() + 1)
                    local pvIconTex = pvIconFrame:CreateTexture(nil, "ARTWORK")
                    pvIconTex:SetAllPoints()
                    pvIconTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
                    if isVert then
                        if pvIconMode == "left" then
                            pvIconFrame:SetPoint("TOP", pvBar, "BOTTOM", 0, 0)
                        elseif pvIconMode == "right" then
                            pvIconFrame:SetPoint("BOTTOM", pvBar, "TOP", 0, 0)
                        end
                    else
                        if pvIconMode == "left" then
                            pvIconFrame:SetPoint("RIGHT", pvBar, "LEFT", 0, 0)
                        elseif pvIconMode == "right" then
                            pvIconFrame:SetPoint("LEFT", pvBar, "RIGHT", 0, 0)
                        end
                    end
                    local pvIconID = nil
                    if bd.popularKey and ns.TBB_POPULAR_BUFFS then
                        for _, pe in ipairs(ns.TBB_POPULAR_BUFFS) do
                            if pe.key == bd.popularKey then pvIconID = pe.icon; break end
                        end
                    end
                    if not pvIconID then
                        local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(bd.spellID)
                        pvIconID = spInfo and spInfo.iconID or 134400
                    end
                    pvIconTex:SetTexture(pvIconID)
                    _tbbPvIcon = pvIconTex
                end

                -- Border preview: anchored to pvBar (not pvFrame which is
                -- full-width container). Spans bar + icon like the highlight.
                -- Uses ApplyBorderStyle for both PP and textured borders.
                local bSz = bd.borderSize or 0
                do
                    -- Border wraps bar + icon (mirrors live wrapFrame._barBorder)
                    local pvBorderFrame = CreateFrame("Frame", nil, pvContent)
                    pvBorderFrame:SetFrameLevel(bd.borderBehind and math.max(0, pvContent:GetFrameLevel() - 1) or (pvContent:GetFrameLevel() + 5))
                    pvBorderFrame:SetSize(PREVIEW_W, PREVIEW_H)
                    pvBorderFrame:SetAllPoints(pvContent)
                    EllesmereUI.ApplyBorderStyle(pvBorderFrame, bSz,
                        bd.borderR or 0, bd.borderG or 0, bd.borderB or 0, 1,
                        bd.borderTexture or "solid", bd.borderTextureOffset, bd.borderTextureOffsetY,
                        bd.borderTextureShiftX, bd.borderTextureShiftY, "resourcebars", bSz)
                end

                -- Hover highlight covers bar + icon
                local eg = EllesmereUI.ELLESMERE_GREEN
                local hlContainer = CreateFrame("Frame", nil, pvContent)
                hlContainer:SetFrameLevel(pvContent:GetFrameLevel() + 6)
                hlContainer:SetAllPoints(pvContent)
                local PP2 = EllesmereUI and EllesmereUI.PP
                local pvBrd = PP2 and PP2.CreateBorder(hlContainer, eg.r, eg.g, eg.b, 1, 2, "OVERLAY", 7)
                if pvBrd then pvBrd:Hide() end

                -- Click to assign buff: toggle the picker open/closed
                pvContent:EnableMouse(true)
                pvContent:SetScript("OnEnter", function() if pvBrd then pvBrd:Show() end end)
                pvContent:SetScript("OnLeave", function() if pvBrd then pvBrd:Hide() end end)
                pvContent:SetScript("OnMouseDown", function(self)
                    if _tbbSpellPickerMenu and _tbbSpellPickerMenu:IsShown() then
                        _tbbSpellPickerMenu:Hide()
                    else
                        ShowTBBSpellPicker(self, bd, function()
                            EllesmereUI:RefreshPage(true)
                        end)
                    end
                end)
            else
                local hint = pvFrame:CreateFontString(nil, "OVERLAY")
                hint:SetFont(FONT_PATH, 12, GetCDMOptOutline())
                hint:SetTextColor(1, 1, 1, 0.35)
                hint:SetPoint("CENTER")
                hint:SetText(EllesmereUI.L("Use the dropdown above to add a new bar"))
            end

            -- Preview visual height = bar height, capped at scroll container max
            local pvVisH = math.min(PREVIEW_H, TBB_PREVIEW_MAX_H)

            fy = fy - pvVisH - 15
            _tbbHeaderFixedH = 20 + DD_H + 15 + 15
            return math.abs(fy)
        end
        EllesmereUI:SetContentHeader(_tbbHeaderBuilder)

        -------------------------------------------------------------------
        --  Scrollable settings (below content header)
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
        --  BAR GROUPING (shared across all bars)
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "Bar Grouping", y);  y = y - h

        -- Group Tracking Bars (per-bar checkbox dropdown) | Grouped Grow Direction
        -- The checkbox dropdown lists every bar; checked bars chain together and
        -- share width/height, unchecked bars are independent. Grow/spacing apply
        -- to the chain and only matter once 2+ bars are checked.
        local grpRow
        grpRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Group Tracking Bars",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end, setValue = function() end },
            { type = "dropdown", text = "Grouped Grow Direction",
              values = { DOWN = "Down", UP = "Up", LEFT = "Left", RIGHT = "Right" },
              order = { "DOWN", "UP", "LEFT", "RIGHT" },
              disabled = function() return ns.TBBGroupedCount() < 2 end,
              disabledTooltip = "Group 2 or more Tracking Bars",
              getValue = function()
                  local t = ns.GetTrackedBuffBars()
                  return t and t.groupGrowDirection or "DOWN"
              end,
              setValue = function(v)
                  local t = ns.GetTrackedBuffBars()
                  if t then t.groupGrowDirection = v end
                  ns.BuildTrackedBuffBars()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Replace the dummy left dropdown with the per-bar grouped checkbox dropdown
        do
            local leftRgn = grpRow._leftRegion
            if leftRgn._control then leftRgn._control:Hide() end
            local t = ns.GetTrackedBuffBars()
            local grpItems = {}
            for idx, b in ipairs(t.bars or {}) do
                local nm = b.name or ("Bar " .. idx)
                if not b.popularKey and b.spellID and b.spellID > 0 then
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(b.spellID)
                    if info and info.name then nm = info.name end
                end
                grpItems[#grpItems + 1] = { key = tostring(idx), label = nm }
            end
            local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                grpItems,
                function(k)
                    local tt = ns.GetTrackedBuffBars()
                    return ns.TBBBarGrouped(tt.bars and tt.bars[tonumber(k)])
                end,
                function(k, v)
                    local tt = ns.GetTrackedBuffBars()
                    local b = tt.bars and tt.bars[tonumber(k)]
                    if b then b.grouped = v and true or false end
                    ns.BuildTrackedBuffBars()
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbRefresh)
        end

        -- Bar Spacing slider | empty label
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Bar Spacing", min = -2, max = 20, step = 1,
              disabled = function() return ns.TBBGroupedCount() < 2 end,
              disabledTooltip = "Group 2 or more Tracking Bars",
              getValue = function()
                  local t = ns.GetTrackedBuffBars()
                  return t and t.groupSpacing or 2
              end,
              setValue = function(v)
                  local t = ns.GetTrackedBuffBars()
                  if t then t.groupSpacing = v end
                  ns.BuildTrackedBuffBars()
                  EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "" }
        );  y = y - h

        -------------------------------------------------------------------
        --  BAR LAYOUT
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "Bar Layout", y);  y = y - h

        -- Height | Width
        -- The whole group shares one width/height, so a grouped member inherits
        -- the group ANCHOR's match-lock: if the anchor is size-matched, every
        -- member's slider is disabled (match wins) instead of silently fighting it.
        local tbbKey = "TBB_" .. _tbbSelectedBar
        do
            local selBd = SelectedTBB()
            if selBd and ns.TBBBarGrouped(selBd) then
                local ai = ns.TBBGroupAnchorIndex()
                if ai then tbbKey = "TBB_" .. ai end
            end
        end
        local thDis, thTip, thRaw = EllesmereUI.MatchGuard(tbbKey, "Height")
        local twDis, twTip, twRaw = EllesmereUI.MatchGuard(tbbKey, "Width")
        local hwRow
        hwRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 500, step = 1,
              disabled = thDis, disabledTooltip = thTip, rawTooltip = thRaw,
              getValue = function() local bd = SelectedTBB(); return bd and bd.height or 24 end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.height = v
                  -- Grouped bars share height: write every other checked bar too.
                  if ns.TBBBarGrouped(bd) then
                      local t = ns.GetTrackedBuffBars()
                      for _, b in ipairs(t.bars or {}) do
                          if b ~= bd and ns.TBBBarGrouped(b) then b.height = v end
                      end
                  end
                  ns.BuildTrackedBuffBars()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 500, step = 1,
              disabled = twDis, disabledTooltip = twTip, rawTooltip = twRaw,
              getValue = function() local bd = SelectedTBB(); return bd and bd.width or 270 end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.width = v
                  -- Grouped bars share width: write every other checked bar too.
                  if ns.TBBBarGrouped(bd) then
                      local t = ns.GetTrackedBuffBars()
                      for _, b in ipairs(t.bars or {}) do
                          if b ~= bd and ns.TBBBarGrouped(b) then b.width = v end
                      end
                  end
                  ns.BuildTrackedBuffBars()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Sync icon: Apply Height to all Bars
        if EllesmereUI.BuildSyncIcon then
            EllesmereUI.BuildSyncIcon({
                region = hwRow._leftRegion,
                tooltip = "Apply Height to all Bars",
                isSynced = function()
                    local bd = SelectedTBB(); if not bd then return false end
                    local val = bd.height or 24
                    local t = ns.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if (b.height or 24) ~= val then return false end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB(); if not bd then return end
                    local val = bd.height or 24
                    local t = ns.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do b.height = val end
                    RefreshTBB(); EllesmereUI:RefreshPage()
                end,
            })
            -- Sync icon: Apply Width to all Bars
            EllesmereUI.BuildSyncIcon({
                region = hwRow._rightRegion,
                tooltip = "Apply Width to all Bars",
                isSynced = function()
                    local bd = SelectedTBB(); if not bd then return false end
                    local val = bd.width or 270
                    local t = ns.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if (b.width or 270) ~= val then return false end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB(); if not bd then return end
                    local val = bd.width or 270
                    local t = ns.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do b.width = val end
                    RefreshTBB(); EllesmereUI:RefreshPage()
                end,
            })
        end

        -- Vertical Orientation | Bar Texture
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Vertical Orientation",
              getValue = function() local bd = SelectedTBB(); return bd and bd.verticalOrientation end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  -- Swap width/height so visual dimensions stay correct
                  bd.width, bd.height = (bd.height or 24), (bd.width or 200)
                  bd.verticalOrientation = v; RefreshTBB()
                  EllesmereUI:RefreshPage()
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
        -- already sitting in that slot so two labels never overlap.
        local function EvictTBBTextConflicts(bd, changedKey, newPos)
            if newPos == "none" then return end
            local function resolvePos(key)
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
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("This option requires a Name Text position other than None"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisName()
                local bd = SelectedTBB()
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
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text Settings",
                rows = {
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
                },
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
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.stacksX or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.stacksX = v; RefreshTBB()
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
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

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "Display", y);  y = y - h

        -- Show Icon | Opacity
        _, h = W:DualRow(parent, y,
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
        _, h = W:SectionHeader(parent, "Extras", y);  y = y - h

        -- Row 1: Enable Max Stacks (toggle + inline slider) | Ticks at Stacks (label + inline input)
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
                1, 50, 1,
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

        -- Row 2: Enable Stack Threshold (toggle + inline swatch) | Stack Threshold (slider)
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

        -- Row 3: Pandemic Glow | Pandemic Glow Preview
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
                      if tbbPanRow and tbbPanRow._refreshPreview then tbbPanRow._refreshPreview() end
                      C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
                  end,
                  tooltip = "Show a glow on the bar when the remaining duration is in the pandemic window (last 30%)" },
                { type = "label", text = "Pandemic Glow Preview" });  y = y - h

            BuildPandemicPreview(tbbPanRow, tbbPandemicOff, SelectedTBB)

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
                            if tbbPanRow._refreshPreview then tbbPanRow._refreshPreview() end
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
            if EllesmereUI.BuildSyncIcon then
                EllesmereUI.BuildSyncIcon({
                    region = tbbPanRow._leftRegion,
                    tooltip = "Apply Pandemic Glow settings to all (Nameplates, CDM Bars)",
                    isSynced = function()
                        local src = SelectedTBB(); if not src then return true end
                        return IsPandemicSyncedEverywhere(src, nil, _tbbSelectedBar)
                    end,
                    onClick = function()
                        local src = SelectedTBB(); if not src then return end
                        ApplyPandemicToAll(src, nil, _tbbSelectedBar)
                    end,
                })
            end
        end

        -- Ensure bar frames exist before showing placeholders
        ns.BuildTrackedBuffBars()
        UpdateTBBPlaceholder()
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
        local liveIcons = ns.cdmBarIcons and ns.cdmBarIcons[barKeyE]
        if liveIcons then
            if not sd.assignedSpells then sd.assignedSpells = {} end
            local seen = {}
            for _, existing in ipairs(sd.assignedSpells) do
                seen[existing] = true
            end
            local removed = sd.removedSpells
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
                if _sid and _sid > 0 then
                    _sid = NormalizeToBase(_sid)
                    if not seen[_sid] and not (removed and removed[_sid]) then
                        sd.assignedSpells[#sd.assignedSpells + 1] = _sid
                        seen[_sid] = true
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
        else
            popup:SetHeight(160)
            popup._durLabel:Hide()
            popup._durBox:Hide()
        end
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
        local allSpells = ns.GetCDMSpellsForBar and ns.GetCDMSpellsForBar(targetBarKey) or {}

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
            lbl:SetText(sp.name or "")
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)

            item:SetScript("OnEnter", function()
                lbl:SetTextColor(1, 1, 1, 1)
                hl:SetColorTexture(1, 1, 1, hlA)
            end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                hl:SetColorTexture(1, 1, 1, 0)
            end)

            mH = mH + ITEM_H
            return item
        end

        -- Preset buffs (potions, consumables, Bloodlust, etc.) added as cast-timer
        -- custom buffs via AddPresetToBar; the buff phase injects an own-frame so
        -- they render alongside Blizzard-tracked buffs. Shown at the top.
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
                    sLbl:SetText(preset.name or "")
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
                            menu:Hide()
                            EnsureAssignedSpells(targetBarKey)
                            ns.AddPresetToBar(targetBarKey, preset)
                            if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                            if ns.UpdateLustListener then ns.UpdateLustListener() end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                            RefreshCDPreview()
                        end)
                    end
                    mH = mH + ITEM_H
                end
            end

            -- Custom Spell ID (with duration) entry -- add an arbitrary buff by
            -- spell ID, rendered as a cast-timer custom buff like the presets.
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
                menu:Hide()
                if onChanged then onChanged(sp.spellID) end
            end)
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
            return af and af._previewSpellID
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
        local MAX_H = 260

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
                    ns.RemoveTrackedSpell(barKey, slotIndex)
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
                end
                if spellID and spellID ~= 0 then
                    if not sd.spellSettings then sd.spellSettings = {} end
                    -- Read from existing settings or empty table for defaults.
                    -- EnsureSS() creates the persistent entry on first WRITE.
                    local ss = sd.spellSettings[spellID] or {}
                    local function EnsureSS()
                        if not sd.spellSettings[spellID] then
                            sd.spellSettings[spellID] = ss
                        end
                        return ss
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
                        -- above): recolors the icon's border during active state.
                        { activeBorder = true, label = "Border Color" },
                    }
                    local CD_STATE_ITEMS = {
                        { val = nil,               label = "None" },
                        -- Charge-spell toggle (independent boolean, NOT part of the
                        -- single-select cdStateEffect below). Handled as a toggle in the
                        -- item loop (item.charge names the ss key).
                        { charge = "chargeHideSwipe", label = "Hide Swipe (Charges)" },
                        { val = "hiddenOnCD",      label = "Hidden (On CD)" },
                        { val = "hiddenReady",     label = "Hidden (CD Ready)" },
                        { val = "pixelGlowReady",  label = "Pixel Glow (CD Ready)" },
                        { val = "buttonGlowReady", label = "Button Glow (CD Ready)" },
                    }

                    -- Track open subnavs on the menu frame so OnUpdate can see them

                    -- Helper: subnav flyout (same style as Potions & Healthstone)
                    -- isDefault: function returning true when the setting is at default value
                    -- onItemCreated: optional callback(si, item, sub) for custom widgets per subnav item
                    local function MakeSubnavRow(label, items, getVal, setVal, isDefault, onItemCreated)
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
                        lbl:SetText(label)

                        local function UpdateLabelColor()
                            if not isDefault() then
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
                        arrow:SetAlpha(0.7)

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
                            for _, item in ipairs(items) do
                                local si = CreateFrame("Button", nil, subInner)
                                si:SetHeight(ITEM_H)
                                si:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -subH)
                                si:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -subH)
                                si:SetFrameLevel(sub:GetFrameLevel() + 2)

                                local sLbl = si:CreateFontString(nil, "OVERLAY")
                                sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                                sLbl:SetPoint("LEFT", 10, 0)
                                sLbl:SetJustifyH("LEFT")
                                sLbl:SetText(item.label)

                                -- Highlight selected item. Charge entries are
                                -- independent toggles (item.charge names the ss
                                -- boolean key); all other items are single-select
                                -- on item.val.
                                local isChargeToggle = item.charge ~= nil
                                local isActiveBorder = item.activeBorder == true
                                local isSelected
                                if isChargeToggle then
                                    isSelected = (ss[item.charge] == true)
                                elseif isActiveBorder then
                                    isSelected = (ss.activeBorderEnabled == true)
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
                                sHl:SetAllPoints(); sHl:SetColorTexture(1, 1, 1, 0); sHl:SetAlpha(0)

                                si:SetScript("OnEnter", function()
                                    if not isSelected then sLbl:SetTextColor(1, 1, 1, 1) end
                                    sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                                end)
                                si:SetScript("OnLeave", function()
                                    if not isSelected then sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA) end
                                    sHl:SetAlpha(0)
                                end)
                                si:SetScript("OnClick", function()
                                    -- Charge toggles flip an independent boolean and
                                    -- keep the flyout open (so both can be set in one
                                    -- pass). They never touch the single-select
                                    -- cdStateEffect.
                                    if isChargeToggle then
                                        EnsureSS()
                                        ss[item.charge] = (not (ss[item.charge] == true)) or nil
                                        isSelected = (ss[item.charge] == true)
                                        if isSelected then
                                            local acR, acG, acB = EllesmereUI.GetAccentColor()
                                            sLbl:SetTextColor(acR, acG, acB, 1)
                                            ns._cdmAnyChargeStyle = true
                                        else
                                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                        end
                                        if sd._syncIconSettings and sd.assignedSpells then
                                            for _, otherSid in ipairs(sd.assignedSpells) do
                                                if otherSid and otherSid > 0 and otherSid ~= spellID then
                                                    if not sd.spellSettings[otherSid] then
                                                        sd.spellSettings[otherSid] = {}
                                                    end
                                                    sd.spellSettings[otherSid][item.charge] = ss[item.charge]
                                                end
                                            end
                                        end
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                        if ns.QueueReanchor then ns.QueueReanchor() end
                                        return
                                    end
                                    -- Border Color: independent toggle (keeps flyout
                                    -- open). The inline swatch picks the color; the row
                                    -- toggles it on/off. Recolors the icon border during
                                    -- active state only.
                                    if isActiveBorder then
                                        EnsureSS()
                                        ss.activeBorderEnabled = (not (ss.activeBorderEnabled == true)) or nil
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
                                        if sd._syncIconSettings and sd.assignedSpells then
                                            for _, otherSid in ipairs(sd.assignedSpells) do
                                                if otherSid and otherSid > 0 and otherSid ~= spellID then
                                                    if not sd.spellSettings[otherSid] then
                                                        sd.spellSettings[otherSid] = {}
                                                    end
                                                    local os = sd.spellSettings[otherSid]
                                                    os.activeBorderEnabled = ss.activeBorderEnabled
                                                    os.activeBorderR = ss.activeBorderR
                                                    os.activeBorderG = ss.activeBorderG
                                                    os.activeBorderB = ss.activeBorderB
                                                    os.activeBorderA = ss.activeBorderA
                                                end
                                            end
                                        end
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                        if ns.QueueReanchor then ns.QueueReanchor() end
                                        return
                                    end
                                    setVal(item.val)
                                    -- Sync to all bar buttons if enabled (CD/utility
                                    -- only; buff bars have no per-icon sync).
                                    if not isBuffBar and sd._syncIconSettings and sd.assignedSpells then
                                        for _, otherSid in ipairs(sd.assignedSpells) do
                                            if otherSid and otherSid > 0 and otherSid ~= spellID then
                                                if not sd.spellSettings[otherSid] then
                                                    sd.spellSettings[otherSid] = {}
                                                end
                                                local os = sd.spellSettings[otherSid]
                                                -- Copy all settings from source spell
                                                os.procGlow = ss.procGlow
                                                os.procGlowClassColor = ss.procGlowClassColor
                                                os.procGlowR = ss.procGlowR
                                                os.procGlowG = ss.procGlowG
                                                os.procGlowB = ss.procGlowB
                                                os.activeSwipeMode = ss.activeSwipeMode
                                                os.activeSwipeClassColor = ss.activeSwipeClassColor
                                                os.activeSwipeR = ss.activeSwipeR
                                                os.activeSwipeG = ss.activeSwipeG
                                                os.activeSwipeB = ss.activeSwipeB
                                                os.activeSwipeA = ss.activeSwipeA
                                                os.activeBorderEnabled = ss.activeBorderEnabled
                                                os.activeBorderR = ss.activeBorderR
                                                os.activeBorderG = ss.activeBorderG
                                                os.activeBorderB = ss.activeBorderB
                                                os.activeBorderA = ss.activeBorderA
                                                os.activeGlow = ss.activeGlow
                                                os.activeGlowClassColor = ss.activeGlowClassColor
                                                os.activeGlowR = ss.activeGlowR
                                                os.activeGlowG = ss.activeGlowG
                                                os.activeGlowB = ss.activeGlowB
                                                os.cdStateEffect = ss.cdStateEffect
                                                os.chargeHideSwipe = ss.chargeHideSwipe
                                                os.glowColor = ss.glowColor
                                                os.glowColorR = ss.glowColorR
                                                os.glowColorG = ss.glowColorG
                                                os.glowColorB = ss.glowColorB
                                                os.desatNotActive = ss.desatNotActive
                                            end
                                        end
                                    end
                                    sub:Hide()
                                    UpdateLabelColor()
                                    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    if ns.QueueReanchor then ns.QueueReanchor() end
                                end)

                                if onItemCreated then onItemCreated(si, item, sub) end
                                subH = subH + ITEM_H
                            end

                            subInner:SetHeight(subH + 4)
                            sub:SetSize(subW, subH + 4)
                            sub:Show()
                            menu._openSub = sub
                        end

                        row:SetScript("OnEnter", function()
                            lbl:SetTextColor(1, 1, 1, 1)
                            hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                            ShowSub()
                        end)
                        row:SetScript("OnLeave", function()
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

                    if isBuffBar then
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
                            function(v) EnsureSS(); ss.buffGlow = v end,
                            function() return ss.buffGlow == nil end)

                        local BUFF_GLOW_COLOR_ITEMS = {
                            { val = nil,      label = "Default" },
                            { val = "class",  label = "Class Color" },
                            { val = "custom", label = "Custom" },
                        }
                        MakeSubnavRow("Glow Effect Color", BUFF_GLOW_COLOR_ITEMS,
                            function() return ss.buffGlowColor end,
                            function(v)
                                EnsureSS()
                                ss.buffGlowColor = v
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
                                        sub:Hide(); menu:Hide()
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
                            end)

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
                            lbl:SetPoint("LEFT", 10, 0); lbl:SetJustifyH("LEFT"); lbl:SetText(label)
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
                                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                                      get=function() return ss.stackCountX or (cdmBd and cdmBd.stackCountX) or 0 end,
                                      set=function(v) EnsureSS(); ss.stackCountX = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                                      get=function() return ss.stackCountY or (cdmBd and cdmBd.stackCountY) or 0 end,
                                      set=function(v) EnsureSS(); ss.stackCountY = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                },
                            })
                        end)

                        -- Always Show Buffs + Desaturate Inactive apply only to
                        -- Blizzard-tracked buffs (inactive placeholders); they are
                        -- omitted entirely for injected custom/preset buffs.
                        if not isInjectedCustom then
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
                                function(v) EnsureSS(); ss.alwaysShow = v end,
                                function() return ss.alwaysShow == nil end)

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
                                function(v) EnsureSS(); ss.desatInactive = v end,
                                function() return ss.desatInactive == nil end)
                        end
                    else
                    local isCustomInjected = spellID < 0
                        or (ns._myRacialsSet and ns._myRacialsSet[spellID])
                        or (sd.customSpellIDs and sd.customSpellIDs[spellID])
                    local customDisabledTip = "Not available for custom injected spells"

                    -- Custom-shaped bars always render Shape Glow, so the per-spell proc
                    -- glow choice is locked (custom = any Icon Shape other than None/Cropped).
                    local cdmBd = ns.barDataByKey and ns.barDataByKey[barKey]
                    local barCustomShape = cdmBd and cdmBd.iconShape
                        and cdmBd.iconShape ~= "none" and cdmBd.iconShape ~= "cropped"

                    -- 1. Proc Glow (default = nil)
                    local procRow = MakeSubnavRow("Proc Glow", GLOW_ITEMS,
                        function() return ss.procGlow end,
                        function(v) EnsureSS(); ss.procGlow = v end,
                        function() return ss.procGlow == nil end,
                        function(si, item)
                            local isGlow = item.val and item.val > 0
                            local cse = ss.cdStateEffect
                            if isGlow and (cse == "pixelGlowReady" or cse == "buttonGlowReady") then
                                si:SetAlpha(0.35)
                                si:SetScript("OnClick", function() end)
                                si:SetScript("OnEnter", function()
                                    EllesmereUI.ShowWidgetTooltip(si, "Disable CD Ready glow first")
                                end)
                                si:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                            end
                        end)
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
                                ss.activeSwipeMode = nil
                                ss.activeSwipeClassColor = true
                            elseif v == "none" then
                                ss.activeSwipeMode = "none"
                                ss.activeSwipeClassColor = nil
                            else
                                -- Custom: keep existing color, only set defaults if none
                                ss.activeSwipeMode = "custom"
                                ss.activeSwipeClassColor = nil
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
                                    -- Ensure custom mode is selected
                                    ss.activeSwipeMode = nil
                                    ss.activeSwipeClassColor = nil
                                    if not ss.activeSwipeR then
                                        ss.activeSwipeR = 1; ss.activeSwipeG = 0.776
                                        ss.activeSwipeB = 0.376; ss.activeSwipeA = 0.7
                                    end
                                    sub:Hide()
                                    menu:Hide()
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
                                        if sd._syncIconSettings and sd.assignedSpells and sd.spellSettings then
                                            for _, otherSid in ipairs(sd.assignedSpells) do
                                                if otherSid and otherSid > 0 and otherSid ~= spellID then
                                                    if not sd.spellSettings[otherSid] then sd.spellSettings[otherSid] = {} end
                                                    local os2 = sd.spellSettings[otherSid]
                                                    os2.activeSwipeR = r; os2.activeSwipeG = g; os2.activeSwipeB = b
                                                    os2.activeSwipeA = a
                                                end
                                            end
                                        end
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
                                    sub:Hide()
                                    menu:Hide()
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
                                        if sd._syncIconSettings and sd.assignedSpells and sd.spellSettings then
                                            for _, otherSid in ipairs(sd.assignedSpells) do
                                                if otherSid and otherSid > 0 and otherSid ~= spellID then
                                                    if not sd.spellSettings[otherSid] then sd.spellSettings[otherSid] = {} end
                                                    local os2 = sd.spellSettings[otherSid]
                                                    os2.activeBorderEnabled = true
                                                    os2.activeBorderR = r; os2.activeBorderG = g; os2.activeBorderB = b
                                                    os2.activeBorderA = a
                                                end
                                            end
                                        end
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
                        end)
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
                        function(v) EnsureSS(); ss.activeGlow = v end,
                        function() return ss.activeGlow == nil end)
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

                    -- 3b. Non Active State (default = nil / none). Desaturates the
                    -- icon when its active-state is NOT active -- the mirror of the
                    -- runtime's active-branch SetDesaturated(false).
                    local NONACTIVE_ITEMS = {
                        { val = nil,  label = "None" },
                        { val = true, label = "Desaturate When Not Active" },
                    }
                    local nonActiveRow = MakeSubnavRow("Non Active State", NONACTIVE_ITEMS,
                        function() return ss.desatNotActive and true or nil end,
                        function(v) EnsureSS(); ss.desatNotActive = v or nil; if v then ns._cdmAnyDesatNotActive = true end end,
                        function() return ss.desatNotActive == nil end)
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
                            EnsureSS(); ss.cdStateEffect = v
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        end,
                        function() return ss.cdStateEffect == nil and not ss.chargeHideSwipe end,
                        function(si, item)
                            local isGlow = (item.val == "pixelGlowReady" or item.val == "buttonGlowReady")
                            if isGlow and ss.procGlow and ss.procGlow > 0 then
                                si:SetAlpha(0.35)
                                si:SetScript("OnClick", function() end)
                                si:SetScript("OnEnter", function()
                                    EllesmereUI.ShowWidgetTooltip(si, "Disable Proc Glow first")
                                end)
                                si:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                            end
                        end)
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
                            ss.glowColor = v
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
                                    sub:Hide()
                                    menu:Hide()
                                    local snapR, snapG, snapB = ss.glowColorR, ss.glowColorG, ss.glowColorB
                                    local function OnPickerChanged()
                                        local popup = EllesmereUI._colorPickerPopup
                                        if not popup then return end
                                        local r, g, b = popup:GetColorRGB()
                                        ss.glowColorR = r; ss.glowColorG = g; ss.glowColorB = b
                                        swatchTex:SetColorTexture(r, g, b, 1)
                                        if sd._syncIconSettings and sd.assignedSpells and sd.spellSettings then
                                            for _, otherSid in ipairs(sd.assignedSpells) do
                                                if otherSid and otherSid > 0 and otherSid ~= spellID then
                                                    if not sd.spellSettings[otherSid] then sd.spellSettings[otherSid] = {} end
                                                    local os2 = sd.spellSettings[otherSid]
                                                    os2.glowColor = "custom"
                                                    os2.glowColorR = r; os2.glowColorG = g; os2.glowColorB = b
                                                end
                                            end
                                        end
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
                        end)

                    end  -- isBuffBar per-icon rows

                    -- "Sync All Bar Buttons" is CD/utility-only; buff bars have no
                    -- per-icon sync, so the whole toggle is skipped for them.
                    if not isBuffBar then
                    -- Divider before sync toggle
                    local div2 = inner:CreateTexture(nil, "ARTWORK")
                    div2:SetHeight(1)
                    div2:SetColorTexture(1, 1, 1, 0.10)
                    div2:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                    div2:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                    mH = mH + 9

                    -- Sync All Bar Buttons toggle
                    -- When enabled, changing any setting on this icon applies
                    -- to ALL icons on the same bar.
                    local syncRow = CreateFrame("Button", nil, inner)
                    syncRow:SetHeight(ITEM_H)
                    syncRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    syncRow:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    syncRow:SetFrameLevel(menu:GetFrameLevel() + 2)

                    local syncLbl = syncRow:CreateFontString(nil, "OVERLAY")
                    syncLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    syncLbl:SetPoint("LEFT", 10, 0)
                    syncLbl:SetJustifyH("LEFT")
                    syncLbl:SetText(EllesmereUI.L("Sync All Bar Buttons"))
                    syncLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

                    local syncVal = syncRow:CreateFontString(nil, "OVERLAY")
                    syncVal:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    syncVal:SetPoint("RIGHT", -10, 0)
                    syncVal:SetJustifyH("RIGHT")

                    local syncHl = syncRow:CreateTexture(nil, "ARTWORK")
                    syncHl:SetAllPoints(); syncHl:SetColorTexture(1, 1, 1, 0); syncHl:SetAlpha(0)

                    -- Sync state stored per-bar (not per-spell). Default on.
                    if sd._syncIconSettings == nil then sd._syncIconSettings = true end
                    local function UpdateSyncLabel()
                        local acR, acG, acB = EllesmereUI.GetAccentColor()
                        if sd._syncIconSettings then
                            syncVal:SetText(EllesmereUI.L("Enabled"))
                            syncVal:SetTextColor(acR, acG, acB, 1)
                        else
                            syncVal:SetText(EllesmereUI.L("Disabled"))
                            syncVal:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        end
                    end
                    UpdateSyncLabel()

                    syncRow:SetScript("OnEnter", function()
                        syncLbl:SetTextColor(1, 1, 1, 1)
                        syncHl:SetColorTexture(1, 1, 1, hlA); syncHl:SetAlpha(1)
                        if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
                    end)
                    syncRow:SetScript("OnLeave", function()
                        syncLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        syncHl:SetAlpha(0)
                    end)
                    syncRow:SetScript("OnClick", function()
                        sd._syncIconSettings = not sd._syncIconSettings
                        -- When enabling: sync this icon's settings to all others.
                        -- Only sync if source spell has been explicitly configured
                        -- (persisted in spellSettings). Empty/default = don't propagate.
                        if sd._syncIconSettings and sd.assignedSpells
                           and sd.spellSettings and sd.spellSettings[spellID] then
                            for _, otherSid in ipairs(sd.assignedSpells) do
                                if otherSid and otherSid > 0 and otherSid ~= spellID then
                                    if not sd.spellSettings[otherSid] then
                                        sd.spellSettings[otherSid] = {}
                                    end
                                    local os = sd.spellSettings[otherSid]
                                    os.procGlow = ss.procGlow
                                    os.procGlowClassColor = ss.procGlowClassColor
                                    os.procGlowR = ss.procGlowR
                                    os.procGlowG = ss.procGlowG
                                    os.procGlowB = ss.procGlowB
                                    os.activeSwipeMode = ss.activeSwipeMode
                                    os.activeSwipeClassColor = ss.activeSwipeClassColor
                                    os.activeSwipeR = ss.activeSwipeR
                                    os.activeSwipeG = ss.activeSwipeG
                                    os.activeSwipeB = ss.activeSwipeB
                                    os.activeSwipeA = ss.activeSwipeA
                                    os.activeBorderEnabled = ss.activeBorderEnabled
                                    os.activeBorderR = ss.activeBorderR
                                    os.activeBorderG = ss.activeBorderG
                                    os.activeBorderB = ss.activeBorderB
                                    os.activeBorderA = ss.activeBorderA
                                    os.activeGlow = ss.activeGlow
                                    os.activeGlowClassColor = ss.activeGlowClassColor
                                    os.activeGlowR = ss.activeGlowR
                                    os.activeGlowG = ss.activeGlowG
                                    os.activeGlowB = ss.activeGlowB
                                    os.cdStateEffect = ss.cdStateEffect
                                    os.chargeHideSwipe = ss.chargeHideSwipe
                                    os.glowColor = ss.glowColor
                                    os.glowColorR = ss.glowColorR
                                    os.glowColorG = ss.glowColorG
                                    os.glowColorB = ss.glowColorB
                                end
                            end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                        end
                        UpdateSyncLabel()
                    end)

                    mH = mH + ITEM_H
                    end  -- not isBuffBar (sync toggle)
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
                local overSub = m._openSub and m._openSub:IsShown() and m._openSub:IsMouseOver()
                -- Keep the menu open while the shared color picker is up: it's a
                -- separate popup, so interacting with it must not dismiss the
                -- menu (and its cog/subnav flyout).
                local cp = EllesmereUI._colorPickerPopup
                local cpOpen = cp and cp:IsShown()
                if not overMenu and not overSub and not cpOpen and IsMouseButtonDown("LeftButton") then
                    m:Hide()
                end
            end)
            menu:SetScript("OnHide", function(m)
                m:SetScript("OnUpdate", nil)
                if m._openSub and m._openSub:IsShown() then m._openSub:Hide() end
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
                else
                    popup:SetHeight(160)
                    popup._durLabel:Hide()
                    popup._durBox:Hide()
                end
                popup._dimmer:Show()
                popup._editBox:SetFocus()
            end)

            allItems[#allItems + 1] = csItem
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
                        sLbl:SetText(it.name); sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
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
                local label = (slot == 13) and "Trinket Slot 1" or "Trinket Slot 2"
                local tex = itemID and C_Item.GetItemIconByID(itemID)
                local isAdded = alreadyOnBar[negSlot]
                local otherBarName = not isAdded and usedOnOtherBar[negSlot]
                local isDisabled = isAdded or otherBarName

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
                        EllesmereUI.ShowWidgetTooltip(ti, "Already on " .. tooltipName)
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
                local rIsDisabled = isAdded or rOtherBar
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
                        EllesmereUI.ShowWidgetTooltip(ri, "Already on " .. rTooltipName)
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
                        local pIsDisabled = isAdded or pOtherBar

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
                        sLbl:SetText(preset.name)

                        local sHl = si:CreateTexture(nil, "ARTWORK")
                        sHl:SetAllPoints()
                        sHl:SetColorTexture(1, 1, 1, 0); sHl:SetAlpha(0)

                        if pIsDisabled then
                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                            sIco:SetDesaturated(true)
                            sIco:SetAlpha(0.4)
                            local pTooltipName = isAdded and (bd and (bd.name or bd.key) or barKey) or pOtherBar
                            si:SetScript("OnEnter", function()
                                EllesmereUI.ShowWidgetTooltip(si, "Already on " .. pTooltipName)
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
                    sLbl:SetText(preset.name)

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
            lbl:SetText(sp.name)

            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)

            -- Check if this spell is already on THIS bar (only gray-out we
            -- still do for CD/util/buff custom bars). Spells on OTHER bars
            -- are always claimable -- AddTrackedSpell auto-moves them.
            local onThisBar = not isDisabled and excludeSet
                and (excludeSet[sp.cdID] or excludeSet[sp.spellID])

            if isDisabled then
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                ico:SetDesaturated(true)
                ico:SetAlpha(0.4)
            elseif onThisBar then
                -- Already on this bar: grayed out with tooltip
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                ico:SetDesaturated(true)
                ico:SetAlpha(0.4)
                local barName = bd and (bd.name or bd.key) or barKey
                item:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(item, "This spell is already being used on " .. barName)
                    hl:SetColorTexture(1, 1, 1, hlA * 0.3); hl:SetAlpha(1)
                end)
                item:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                    hl:SetAlpha(0)
                end)
            else
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                item:SetScript("OnEnter", function()
                    lbl:SetTextColor(1, 1, 1, 1)
                    hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                end)
                item:SetScript("OnLeave", function()
                    lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    hl:SetAlpha(0)
                end)
                item:SetScript("OnClick", function()
                    menu:Hide()
                    if wrongCatGroup then
                        ShowWrongBarTypePopup(sp.name, sp.cdmCatGroup == "buff")
                        return
                    end
                    -- Always pass spellID (assignedSpells stores spellIDs)
                    if onSelect then onSelect(sp.spellID, sp.isExtra) end
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

            -- Hover highlight (2px accent border, child container avoids conflict with existing PP border)
            local eg = EllesmereUI.ELLESMERE_GREEN
            local slotHlCont = CreateFrame("Frame", nil, slot)
            slotHlCont:SetAllPoints()
            slotHlCont:SetFrameLevel(slot:GetFrameLevel() + 1)
            local slotPP = EllesmereUI and EllesmereUI.PP
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
                local bd = SelectedCDMBar()
                if not bd then return end
                local isDefaultBuffs = (bd.key == "buffs")

                if button == "MiddleButton" then
                    local si = self._slotIdx
                    if isDefaultBuffs then
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
                    if not t[si] or t[si] == 0 then return end
                    ns.RemoveTrackedSpell(bd.key, si)
                    RefreshCDPreview()
                elseif button == "RightButton" or button == "LeftButton" then
                    local si = self._slotIdx
                    -- A slot is configurable if it maps to an assignedSpells entry
                    -- OR (default buffs bar mirror) exposes a live spellID. The
                    -- per-icon settings menu keys off whichever is present.
                    local sdClick = ns.GetBarSpellData(bd.key)
                    local hasAssigned = sdClick and sdClick.assignedSpells
                        and sdClick.assignedSpells[si] and sdClick.assignedSpells[si] ~= 0
                    if not hasAssigned and not self._previewSpellID then return end

                    -- Show remove-only dropdown (per-icon settings + Remove)
                    ShowSpellPicker(self, bd.key, si, {}, function()
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

                    if dragMode == "swap" then
                        if insertIdx ~= dragIdx then
                            ns.SwapTrackedSpells(bd.key, dragIdx, insertIdx)
                            didChange = true
                        end
                    else
                        local toIdx = insertIdx
                        if toIdx > dragIdx then toIdx = toIdx - 1 end
                        if toIdx ~= dragIdx then
                            ns.MoveTrackedSpell(bd.key, dragIdx, toIdx)
                            didChange = true
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
                local t = sdDrag and sdDrag.assignedSpells or {}
                local si = self._slotIdx
                if not t[si] or t[si] == 0 then return end
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
                        if sdT and sdT.assignedSpells then
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
                -- No drag reordering on buff bars (Blizzard controls order)
                local bdDrag = SelectedCDMBar()
                if bdDrag and ns.IsBarBuffFamily(bdDrag) then return end
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
        end)
        addBtn:SetScript("OnLeave", function()
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            addLbl:SetTextColor(ar, ag, ab, 0.6)
            if addBrd then addBrd:Hide() end
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

        -- Update: mirrors tracked spells with interactive slots
        pf.Update = function(self)
            local bd = SelectedCDMBar()
            if not bd then
                for i = 1, MAX_PREVIEW_ICONS do previewSlots[i]:Hide() end
                addBtn:Hide(); self:SetHeight(1); return
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
            if bd.key == "buffs" then
                -- Build exclusion set: spells claimed by other buff bars
                local diverted = {}
                local pp = DB()
                if pp and pp.cdmBars and pp.cdmBars.bars then
                    for _, otherBd in ipairs(pp.cdmBars.bars) do
                        if otherBd.enabled and otherBd.key ~= "buffs"
                           and (otherBd.barType == "buffs" or otherBd.barType == "custom_buff") then
                            local otherSd = ns.GetBarSpellData(otherBd.key)
                            if otherSd and otherSd.assignedSpells then
                                for _, sid in ipairs(otherSd.assignedSpells) do
                                    if type(sid) == "number" and sid > 0 then
                                        diverted[sid] = true
                                    end
                                end
                            end
                        end
                    end
                end
                -- Enumerate all buff viewer pool spells (active + inactive)
                local entries = ns.EnumerateCDMViewerSpells
                    and ns.EnumerateCDMViewerSpells(true) or {}
                tracked = {}
                trackedCd = {}
                for _, e in ipairs(entries) do
                    if not diverted[e.sid] then
                        tracked[#tracked + 1] = e.sid
                        trackedCd[#tracked] = e.cdID
                    end
                end
                -- Also include this bar's own custom/preset buffs (cast-timer
                -- injected) -- they aren't in the Blizzard viewer enumeration.
                local sdSelf = ns.GetBarSpellData(bd.key)
                if sdSelf and sdSelf.assignedSpells and sdSelf.spellDurations then
                    for _, sid in ipairs(sdSelf.assignedSpells) do
                        if type(sid) == "number" and sid > 0
                           and (sdSelf.spellDurations[sid] or 0) > 0 then
                            tracked[#tracked + 1] = sid
                        end
                    end
                end
            else
                local sdUpd = EnsureAssignedSpells(bd.key)
                tracked = sdUpd and sdUpd.assignedSpells or {}
            end
            local count = #tracked

            -- Use the same stride logic as the runtime (ComputeTopRowStride)
            local stride, topRowCount
            if numRows == 2 and bd.customTopRowEnabled and bd.topRowCount and bd.topRowCount > 0 then
                topRowCount = math.min(bd.topRowCount, count)
                local bottomCount = count - topRowCount
                if bottomCount <= 0 then
                    -- Match the runtime: collapse to one row until the icon count
                    -- exceeds the top-row count and actually fills a second row.
                    -- This also keeps the "+" button on the top row.
                    numRows = 1
                    stride = math.max(topRowCount, 1)
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
                    if id then
                        local tex
                        if id <= -100 then
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
                            slot._icon:SetDesaturated(false)
                            slot._icon:SetAlpha(1)
                        else slot._icon:SetTexture(nil) end
                    else slot._icon:SetTexture(nil) end
                else
                    -- Blank slot (empty grid filler)
                    slot._icon:SetTexture(nil)
                    slot._previewSpellID = nil
                    slot._previewCdID = nil
                    slot._previewItemID = nil
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

                local clickBtn = CreateFrame("Button", nil, self)
                clickBtn:SetHeight(14)
                clickBtn:SetScript("OnClick", function()
                    if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
                end)
                local clickFS = clickBtn:CreateFontString(nil, "OVERLAY")
                clickFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                clickFS:SetAllPoints()
                clickFS:SetJustifyH("CENTER")
                local ar, ag, ab = EllesmereUI.GetAccentColor()
                clickFS:SetTextColor(ar, ag, ab, 1)
                clickFS:SetText(EllesmereUI.L("Manage shown buffs through Blizzard CDM Settings"))
                clickBtn._fs = clickFS
                clickBtn:SetScript("OnEnter", function() clickFS:SetTextColor(1, 1, 1, 1) end)
                clickBtn:SetScript("OnLeave", function()
                    local r, g, b = EllesmereUI.GetAccentColor()
                    clickFS:SetTextColor(r, g, b, 1)
                end)
                self._buffInfoClick = clickBtn
            end
            if isBuffBar then
                if self._buffInfoText then self._buffInfoText:Hide() end
                local clickBtn = self._buffInfoClick
                clickBtn:ClearAllPoints()
                clickBtn:SetPoint("TOP", self, "TOPLEFT", self:GetWidth() / 2, -(totalH + 14))
                local fs = clickBtn._fs
                local textW = fs and fs:GetStringWidth() or 0
                clickBtn:SetWidth(math.max(textW + 4, 30))
                clickBtn:Show()
                -- Clean up hidden rows from previous implementation
                if self._hiddenRows then
                    for _, hr in ipairs(self._hiddenRows) do hr:Hide() end
                end
                if self._hiddenHeader then self._hiddenHeader:Hide() end
                if self._focusKickInfoText then self._focusKickInfoText:Hide() end
                self:SetHeight(totalH + 10 + 14 + 20)
            elseif isFocusKick then
                if self._buffInfoText then self._buffInfoText:Hide() end
                if self._buffInfoClick then self._buffInfoClick:Hide() end
                if not self._focusKickInfoText then
                    local fkFS = self:CreateFontString(nil, "OVERLAY")
                    fkFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    fkFS:SetJustifyH("CENTER")
                    fkFS:SetWordWrap(true)
                    fkFS:SetTextColor(1, 1, 1, 1)
                    fkFS:SetText(EllesmereUI.L("This bar will always be attached to your focus target's nameplate"))
                    self._focusKickInfoText = fkFS
                end
                local fkFS = self._focusKickInfoText
                fkFS:ClearAllPoints()
                fkFS:SetPoint("TOP", self, "TOPLEFT", self:GetWidth() / 2, -(totalH + 14))
                fkFS:SetWidth(self:GetWidth() - 20)
                fkFS:Show()
                self:SetHeight(totalH + 10 + fkFS:GetStringHeight() + 20)
            else
                if self._buffInfoText then self._buffInfoText:Hide() end
                if self._buffInfoClick then self._buffInfoClick:Hide() end
                if self._focusKickInfoText then self._focusKickInfoText:Hide() end
                self:SetHeight(totalH + 10)
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

        -- Capture the key so closures can always look up the CURRENT bar data
        -- from the profile, avoiding stale-reference bugs when the bars array
        -- is reordered or the page is rebuilt.
        -- Action buttons: repopulate + open Blizzard CDM
        _, h = W:WideDualButton(parent,
            "Repopulate from Blizzard CDM", "Open Blizzard CDM", y,
            function()
                EllesmereUI:ShowConfirmPopup({
                    title = "Repopulate Bars",
                    message = "This will reset all default bar spell assignments for the current spec to match Blizzard's CDM layout. Custom bars are not affected. Continue?",
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
            end, 310);  y = y - h

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
                local label = bd and (bd.name or bd.key) or ""
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
                    local displayName = b.name or b.key
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
                    { type = "cooldowns",   label = "+ Add New Cooldowns Bar" },
                    { type = "utility",     label = "+ Add New Utility Bar" },
                    { type = "buffs",       label = "+ Add New Buff Bar" },
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
        do
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
        _, h = W:SectionHeader(parent, "Bar Layout", y);  y = y - h

        -- Row 1: (Sync) Visibility | Visibility Options (checkbox dropdown)
        local visRow, visH = W:DualRow(parent, y,
            { type="dropdown", text="Visibility",
              values = EllesmereUI.VIS_VALUES_CDM or EllesmereUI.VIS_VALUES,
              order = EllesmereUI.VIS_ORDER_CDM or EllesmereUI.VIS_ORDER,
              getValue=function() return BD().barVisibility or "always" end,
              setValue=function(v)
                  BD().barVisibility = v
                  ns.CDMApplyVisibility()
                  EllesmereUI:RefreshPage()
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

        -- Sync icon on Visibility (left)
        do
            local rgn = visRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Visibility to all Bars",
                isSynced = function()
                    local v = BD().barVisibility or "always"
                    local synced = true
                    ForEachSyncBar(function(b) if (b.barVisibility or "always") ~= v then synced = false end end)
                    return synced
                end,
                onClick = function()
                    local v = BD().barVisibility or "always"
                    ForEachSyncBar(function(b) b.barVisibility = v end)
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
                  if v ~= 2 then bd.topRowCount = nil; bd.customTopRowEnabled = nil end
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
            local _, topRowCogShow = EllesmereUI.BuildCogPopup({
                title = "Top Row Icons",
                rows = {
                    { type="toggle", label="Custom Top Row Count",
                      get=function() return BD().customTopRowEnabled end,
                      set=function(v)
                          BD().customTopRowEnabled = v
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                      end },
                    { type="slider", label="Top Row Icons",
                      min=1, max=50, step=1,
                      tooltip="How many icons to show on the top row. The rest go on the bottom row.",
                      disabled=customTopOff,
                      disabledTooltip="Custom Top Row Count",
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
                },
            })
            local cogBtn = MakeCogBtn(leftRgn, topRowCogShow, ctrl, EllesmereUI.COGS_ICON)
            -- Disable cog when numRows ~= 2
            local block = CreateFrame("Frame", nil, cogBtn)
            block:SetAllPoints(); block:SetFrameLevel(cogBtn:GetFrameLevel() + 10); block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("This option requires exactly 2 rows"))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local notTwo = (BD().numRows or 1) ~= 2
                if notTwo then cogBtn:SetAlpha(0.15); block:Show() else cogBtn:SetAlpha(0.4); block:Hide() end
            end)
            local notTwo = (BD().numRows or 1) ~= 2
            if notTwo then cogBtn:SetAlpha(0.15); block:Show() else cogBtn:SetAlpha(0.4); block:Hide() end
        end

        -- Hide Buffs When Inactive (global setting, applies to all buff bars)
        if ns.IsBarBuffFamily(barData) then
            local prof = ns.ECME and ns.ECME.db and ns.ECME.db.profile
            -- Hide Buffs When Inactive toggle removed: always forced ON.
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
        -- Centered hint: per-icon overrides are reached by right-clicking a
        -- preview icon. Buff bars expose display overrides (Buff Glow, Duration
        -- Text, Charge/Stack, ...); CD/utility bars expose glows + active-state
        -- effects. One hint per bar type so both never show together.
        do
            local hintText = isBuffBar
                and "Override display settings per icon by right clicking on icons in the preview"
                or "Add Custom Glows and Active State Effects by right clicking on icons in the preview"
            local hint = parent:CreateFontString(nil, "OVERLAY")
            hint:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            hint:SetJustifyH("CENTER")
            hint:SetWidth(parent:GetWidth() - 60)
            hint:SetPoint("TOP", parent, "TOP", 0, y - 20)
            hint:SetText(EllesmereUI.L(hintText))
            hint:SetTextColor(0.62, 0.62, 0.62, 0.9)
            y = y - 32
        end
        _, h = W:SectionHeader(parent, "Icon Display", y);  y = y - h

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
                  min=16, max=80, step=1,
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
                { type="slider", text="Icon Spacing",
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

            -- Inline pixel-glow cog on Buff Glow: 1:1 replica of the Pandemic Glow
            -- cog (Lines / Thickness / Speed), enabled only when Pixel Glow is chosen.
            do
                local function buffAntsOff()
                    return (BD().buffGlowType or 0) ~= 1 or IsCustomShape()
                end
                BuildPandemicCogButton(buffGlowRow, buffAntsOff, BD, function()
                    ns.BuildAllCDMBars()
                    -- Re-apply to already-active glows so the permanent custom aura
                    -- preview reflects the new Lines/Thickness/Speed immediately.
                    if ns.RefreshBuffGlows then ns.RefreshBuffGlows() end
                end, { lines = "buffGlowLines", thickness = "buffGlowThickness", speed = "buffGlowSpeed" })
            end

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
              min=16, max=80, step=1,
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
            { type="slider", text="Icon Spacing",
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
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return BD().stackCountX or 0 end,
                      set=function(v)
                          BD().stackCountX = v
                          ns.RefreshCDMIconAppearance(BD().key); ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                      end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
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
                    },
                })
                MakeCogBtn(rightRgn, pgCogShow, nil, EllesmereUI.RESIZE_ICON)
            end
        end
        end

        _, h = W:Spacer(parent, y, 8);  y = y - h

        -------------------------------------------------------------------
        --  EXTRAS (not shown for custom aura bars or FocusKick)
        -------------------------------------------------------------------
        local isCustomBuffBar = (barData.barType == "custom_buff")
        local isAnyBuffBar = isBuffGlowBar  -- buffs or custom_buff
        if not isCustomBuffBar and not isFocusKick then
        _, h = W:SectionHeader(parent, "Extras", y);  y = y - h

        -- Show Tooltip | Show Keybind (not for buff bars)
        if not isAnyBuffBar then
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
        end -- tooltip/keybind buff bar guard

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

            if EllesmereUI.BuildSyncIcon then
                EllesmereUI.BuildSyncIcon({
                    region = panGlowRow._leftRegion,
                    tooltip = "Apply Pandemic Glow settings to all (Nameplates, CDM Bars)",
                    isSynced = function()
                        return IsPandemicSyncedEverywhere(BD(), barKey)
                    end,
                    onClick = function()
                        ApplyPandemicToAll(BD(), barKey)
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

        -- Hide Items if Missing
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Items if Missing",
              tooltip = "Hide consumable items (potions, healthstone) from the bar when you have none in your bags, instead of showing them dimmed. They reappear automatically once you have the item again.",
              getValue=function() return BD().hideItemsIfMissing == true end,
              setValue=function(v)
                  BD().hideItemsIfMissing = v
                  if ns.FullCDMRebuild then ns.FullCDMRebuild("hide_missing_toggle") end
              end },
            { type="label", text="" });  y = y - h

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
            elseif pageName == PAGE_BUFF_BARS then
                return _tbbHeaderBuilder
            end
            return nil
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
