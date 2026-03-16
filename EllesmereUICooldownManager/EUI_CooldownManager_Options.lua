-------------------------------------------------------------------------------
--  EllesmereUICooldownManager_Options.lua
--  Registers CDM Effects module with EllesmereUI
--  Tab 1: CDM Bars  |  Tab 2: Bar Glows  |  Tab 3: Buff Bars  |  Tab 4: Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_BAR_GLOWS    = "Bar Glows"
local PAGE_BUFF_BARS    = "Buff Bars"
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
        fs:SetFont(font, size, GetCDMOptOutline())
        if GetCDMOptUseShadow() then
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
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

    local BG_ACTION_BAR_VALUES = {
        [1] = "Action Bar 1 (Main)", [2] = "Action Bar 2", [3] = "Action Bar 3", [4] = "Action Bar 4",
        [5] = "Action Bar 5", [6] = "Action Bar 6", [7] = "Action Bar 7", [8] = "Action Bar 8",
    }
    local BG_ACTION_BAR_ORDER = { 1, 2, 3, 4, 5, 6, 7, 8 }

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

    -- Check if a specific action bar uses a custom shape (not "none"/"cropped")
    local function BarHasCustomShape(barIdx)
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

    local function ShowBarGlowSpellPicker(anchorFrame, barIdx, btnIdx, onChanged)
        if _bgSpellPickerMenu then _bgSpellPickerMenu:Hide() end

        local bg = ns.GetBarGlows()
        local assignKey = barIdx .. "_" .. btnIdx
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

        -- Get tracked and untracked buff spells
        local displayed, known = ns.GetTBBSpellPool()
        local tracked, untracked = displayed, known
        if #tracked == 0 and #untracked == 0 then return end

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

        local function MakeCheckItem(sp, isUntracked)
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
                if isUntracked then
                    -- Fire popup to send user to Blizzard CDM
                    menu:Hide()
                    if EllesmereUI and EllesmereUI.ShowConfirmPopup then
                        EllesmereUI:ShowConfirmPopup({
                            title = "Spell Not Tracked",
                            message = "This spell is not currently tracked in any of your CDM bars. Add it to a CDM bar first, or enable it in Blizzard's Cooldown Manager.",
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
                    return
                end
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
                    buffList[#buffList + 1] = {
                        spellID = sp.spellID,
                        glowStyle = 1,
                        glowColor = { r = 1, g = 0.82, b = 0.1 },
                        classColor = false,
                        mode = "ACTIVE",
                    }
                    UpdateCB()
                    bg.assignments[assignKey] = buffList
                    Refresh()
                    ImmediateUpdate()
                end
            end)

            mH = mH + ITEM_H
        end

        -- Tracked buffs
        for _, sp in ipairs(tracked) do MakeCheckItem(sp, false) end

        -- Divider
        if #tracked > 0 and #untracked > 0 then
            local div = inner:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1); div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- Untracked buffs
        for _, sp in ipairs(untracked) do MakeCheckItem(sp, true) end

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
        local curBar = bg.selectedBar or 1
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
            local barIdx = bgData.selectedBar or 1
            local ok, EAB_ADDON = pcall(EllesmereUI.Lite.GetAddon, "EllesmereUIActionBars")
            if not ok then EAB_ADDON = nil end
            local barKeyList = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8" }
            local barKeyStr = barKeyList[barIdx] or "MainBar"
            local barSettings = nil
            if EAB_ADDON and EAB_ADDON.db and EAB_ADDON.db.profile then
                barSettings = EAB_ADDON.db.profile.bars[barKeyStr]
            end

            local NUM_BUTTONS = 12
            local prefix = BAR_BUTTON_PREFIXES[barIdx] or "ActionButton"

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
            ddLbl:SetText(BG_ACTION_BAR_VALUES[barIdx] or "Action Bar 1 (Main)")

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
                for _, idx in ipairs(BG_ACTION_BAR_ORDER) do
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
                    iLbl:SetText(BG_ACTION_BAR_VALUES[idx] or ("Action Bar " .. idx))
                    local iHl = item:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints(); iHl:SetColorTexture(1, 1, 1, 1)
                    iHl:SetAlpha(idx == barIdx and selA or 0)
                    item:SetScript("OnEnter", function() iLbl:SetTextColor(1,1,1,1); iHl:SetAlpha(hlA) end)
                    item:SetScript("OnLeave", function() iLbl:SetTextColor(tDimR,tDimG,tDimB,tDimA); iHl:SetAlpha(idx == barIdx and selA or 0) end)
                    item:SetScript("OnClick", function()
                        menu:Hide()
                        bgData.selectedBar = idx
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
            local btn1 = _G[prefix .. "1"]
            local realBtnW = (btn1 and btn1:GetWidth() or 36)
            local realBtnH = (btn1 and btn1:GetHeight() or 36)
            if realBtnW < 1 then realBtnW = 36 end
            if realBtnH < 1 then realBtnH = 36 end

            -- Read bar scale
            local barScale = (barSettings and barSettings.barScale) or 1.0
            local scaledBtnW = math.floor(realBtnW * barScale + 0.5)
            local scaledBtnH = math.floor(realBtnH * barScale + 0.5)

            -- Custom shape expansion
            local btnShape = (barSettings and barSettings.buttonShape) or "none"
            if btnShape ~= "none" and btnShape ~= "cropped" then
                local shapeExp = math.floor(10 * barScale + 0.5)
                scaledBtnW = scaledBtnW + shapeExp
                scaledBtnH = scaledBtnH + shapeExp
            end
            if btnShape == "cropped" then
                scaledBtnH = math.floor(scaledBtnH * 0.80 + 0.5)
            end

            local spacing = (barSettings and barSettings.buttonPadding) or 2
            local scaledPad = math.floor(spacing * barScale + 0.5)

            -- How many buttons visible
            local numVisible = NUM_BUTTONS
            if barSettings then
                local ov = barSettings.overrideNumIcons
                if ov and ov > 0 and ov < numVisible then numVisible = ov end
            end

            -- Read zoom
            local zoom = ((barSettings and barSettings.iconZoom) or 5.5) / 100
            local square = EAB_ADDON and EAB_ADDON.db and EAB_ADDON.db.profile.squareIcons

            -- Read border settings
            local brdSize = 0
            if barSettings then
                -- Read raw borderThickness setting
                local thickness = barSettings.borderThickness or "thin"
                if thickness == "none" then brdSize = 0
                elseif thickness == "thin" then brdSize = 1
                elseif thickness == "medium" then brdSize = 2
                elseif thickness == "thick" then brdSize = 3
                else brdSize = 1 end
            end
            local brdColor = (barSettings and barSettings.borderColor) or { r = 0, g = 0, b = 0, a = 1 }
            local brdClassColor = barSettings and barSettings.borderClassColor

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

                -- Icon from real action button
                local realBtn = _G[prefix .. i]
                local hasAction = realBtn and realBtn.icon and realBtn.icon:GetTexture()
                local iconTex = bf:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                UnsnapTex(iconTex)
                if hasAction then
                    iconTex:SetTexture(realBtn.icon:GetTexture())
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
                local SHAPE_MASKS = AB_SHAPE_MASKS
                local SHAPE_BORDERS = AB_SHAPE_BORDERS
                if btnShape ~= "none" and btnShape ~= "cropped" and SHAPE_MASKS and SHAPE_MASKS[btnShape] then
                    local mask = bf:CreateMaskTexture()
                    mask:SetAllPoints(bf)
                    mask:SetTexture(SHAPE_MASKS[btnShape], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    iconTex:AddMaskTexture(mask)
                    -- Shape border
                    if SHAPE_BORDERS and SHAPE_BORDERS[btnShape] and brdSize > 0 then
                        local sbt = bf:CreateTexture(nil, "OVERLAY", nil, 6)
                        sbt:SetAllPoints(bf)
                        sbt:SetTexture(SHAPE_BORDERS[btnShape])
                        local cr, cg, cb = brdColor.r, brdColor.g, brdColor.b
                        if brdClassColor then
                            local _, ct = UnitClass("player")
                            if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
                        end
                        sbt:SetVertexColor(cr, cg, cb, brdColor.a or 1)
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
                local assignKey = barIdx .. "_" .. i
                local assigns = bgData.assignments[assignKey]
                local hasAssign = assigns and #assigns > 0

                -- Pre-create accent border on every button (hidden unless needed)
                local accentCont = CreateFrame("Frame", nil, bf)
                accentCont:SetAllPoints()
                accentCont:SetFrameLevel(bf:GetFrameLevel() + 2)
                local PP2 = EllesmereUI and EllesmereUI.PP

                -- Active button gets accent border; assigned (non-active) buttons get white border
                local accentBrd
                if isSelected then
                    accentBrd = PP2 and PP2.CreateBorder(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1, 2, "OVERLAY", 7)
                else
                    accentBrd = PP2 and PP2.CreateBorder(accentCont, 1, 1, 1, 0.6, 2, "OVERLAY", 7)
                end
                if accentBrd then accentBrd:Hide() end

                -- Show active state
                if isSelected then
                    if accentBrd then accentBrd:Show() end
                end

                -- Show white border for assigned buttons (even if not active)
                if hasAssign and not isSelected then
                    if accentBrd then accentBrd:Show() end
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
                if not isSelected then
                    if hasAssign then
                        -- Has assignments: swap white border to accent on hover
                        bf:SetScript("OnEnter", function()
                            if PP2 and accentCont then PP2.SetBorderColor(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1) end
                        end)
                        bf:SetScript("OnLeave", function()
                            if PP2 and accentCont then PP2.SetBorderColor(accentCont, 1, 1, 1, 0.6) end
                        end)
                    else
                        -- No assignments: show accent border + bump alpha on hover, revert on leave
                        bf:SetScript("OnEnter", function()
                            bf:SetAlpha(0.55)
                            if PP2 and accentCont then PP2.SetBorderColor(accentCont, ACCENT.r, ACCENT.g, ACCENT.b, 1) end
                            if accentBrd then accentBrd:Show() end
                        end)
                        bf:SetScript("OnLeave", function()
                            bf:SetAlpha(0.50)
                            if accentBrd then accentBrd:Hide() end
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
                        local prevKey = barIdx .. "_" .. (prev._btnIdx or 0)
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
                                end)
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
            tipFS:SetText("Left click a button to edit its glow, right click to add a new glow")

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
            pageListener:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
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
            hintText:SetText("Left click a button to edit its glow, right click to add a new glow")
            y = y - 40
        else
            -- Button selected: show per-buff sections
            local assignKey = curBar .. "_" .. curBtn
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
                emptyText:SetText("No buffs assigned. Right click a button in the preview to assign buffs.")
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
                    do
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
    EllesmereUI:RegisterOnHide(HideTBBPlaceholder)

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
            title:SetText("Custom Buff ID")

            local sidLbl = popup:CreateFontString(nil, "OVERLAY")
            sidLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            sidLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", 24, -52)
            sidLbl:SetTextColor(0.7, 0.7, 0.7, 1)
            sidLbl:SetText("Spell ID")

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
            sidPh:SetText("e.g. 12345")
            sidBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then sidPh:Show() else sidPh:Hide() end
            end)
            popup._sidBox = sidBox

            local durLbl = popup:CreateFontString(nil, "OVERLAY")
            durLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            durLbl:SetPoint("TOPLEFT", sidBox, "BOTTOMLEFT", 0, -12)
            durLbl:SetTextColor(0.7, 0.7, 0.7, 1)
            durLbl:SetText("Duration (seconds)")

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
            durPh:SetText("e.g. 30")
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
            addLbl:SetPoint("CENTER"); addLbl:SetText("Add")
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
            cLbl:SetPoint("CENTER"); cLbl:SetText("Cancel")
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

        local displayed, known, disabled = ns.GetTBBSpellPool()
        local tracked   = displayed
        local untracked = known
        local popular   = ns.TBB_POPULAR_BUFFS or {}

        local hasAny = #tracked > 0 or #untracked > 0 or #popular > 0
        if not hasAny then return end

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
        csLbl:SetText("Custom Buff ID")
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
                barCfg.name           = entry.name
                Refresh()
                ns.BuildTrackedBuffBars()
                if onChanged then onChanged() end
            end)
            mH = mH + ITEM_H
        end

        for _, entry in ipairs(popular) do MakePopularItem(entry) end

        -- Divider before CDM-tracked buffs (only if there are any)
        if #tracked > 0 or #untracked > 0 then
            local div2 = inner:CreateTexture(nil, "ARTWORK")
            div2:SetHeight(1); div2:SetColorTexture(1, 1, 1, 0.10)
            div2:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div2:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        local function MakeSpellItem(sp, isUntracked)
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

            item:SetScript("OnEnter", function() lbl:SetTextColor(1,1,1,1); hl:SetColorTexture(1,1,1,hlA) end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(baseR, baseG, baseB, baseA)
                hl:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)
            end)
            item:SetScript("OnClick", function()
                menu:Hide()
                if isUntracked then
                    if EllesmereUI and EllesmereUI.ShowConfirmPopup then
                        EllesmereUI:ShowConfirmPopup({
                            title = "Spell Not Tracked",
                            message = "This spell is not currently tracked in any of your CDM bars. Add it to a CDM bar first.",
                            confirmText = "Open Blizzard CDM",
                            cancelText = "Close",
                            onConfirm = function()
                                if CooldownViewerSettings and CooldownViewerSettings.Show then CooldownViewerSettings:Show() end
                                if EllesmereUI._mainFrame then EllesmereUI._mainFrame:Hide() end
                            end,
                        })
                    end
                    return
                end
                barCfg.spellID        = sp.spellID
                barCfg.spellIDs       = nil
                barCfg.popularKey     = nil
                barCfg.glowBased      = nil
                barCfg.customDuration = nil
                barCfg.name           = sp.name
                Refresh()
                ns.BuildTrackedBuffBars()
                if onChanged then onChanged() end
            end)
            mH = mH + ITEM_H
        end

        for _, sp in ipairs(tracked) do MakeSpellItem(sp, false) end
        if #tracked > 0 and #untracked > 0 then
            local div3 = inner:CreateTexture(nil, "ARTWORK")
            div3:SetHeight(1); div3:SetColorTexture(1, 1, 1, 0.10)
            div3:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div3:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end
        for _, sp in ipairs(untracked) do MakeSpellItem(sp, true) end

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
                    ddLbl:SetText("No Bars - Click to Add")
                else
                    ddLbl:SetText("Select a bar")
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
                            message = "Delete \"" .. displayName .. "\"?",
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
                addLbl:SetText("+ Add New Bar")
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

            -- Bar preview (uses bar's actual dimensions; always rendered horizontal)
            local bd = SelectedTBB()
            local PREVIEW_H = bd and bd.height or 24
            local PREVIEW_W = bd and bd.width or 270
            if PREVIEW_W > (hdrW - PAD * 2) then PREVIEW_W = hdrW - PAD * 2 end

            local pvFrame = CreateFrame("Frame", nil, hdr)
            pvFrame:SetSize(PREVIEW_W, PREVIEW_H)
            PP.Point(pvFrame, "TOP", hdr, "TOP", 0, fy)
            _tbbPvFrame = pvFrame

            if bd then
                local pvBar = CreateFrame("StatusBar", nil, pvFrame)
                pvBar:SetAllPoints()
                local texPath = EllesmereUI.ResolveTexturePath(ns.TBB_TEXTURES, bd.texture or "none", "Interface\\Buttons\\WHITE8x8")
                pvBar:SetStatusBarTexture(texPath)
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
                    spark:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\cast_spark.tga")
                    spark:SetBlendMode("ADD")
                    spark:SetSize(8, PREVIEW_H)
                    spark:SetPoint("CENTER", pvBar:GetStatusBarTexture(), "RIGHT", 0, 0)
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
                        nameFs:SetText("Click to assign a buff")
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
                        nameFs:SetText("Click to assign a buff")
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

                -- Icon preview: parented to hdr so it can sit outside pvFrame bounds.
                -- Size always matches bar height.
                local pvIconMode = (not bd.verticalOrientation) and (bd.iconDisplay or "none") or "none"
                _tbbPvIcon = nil
                local pvIconFrame = nil
                local hasIcon = (bd.spellID and bd.spellID > 0) or bd.glowBased
                if pvIconMode ~= "none" and hasIcon then
                    pvIconFrame = CreateFrame("Frame", nil, hdr)
                    local iSize = PREVIEW_H
                    pvIconFrame:SetSize(iSize, iSize)
                    pvIconFrame:SetFrameLevel(pvFrame:GetFrameLevel() + 1)
                    local pvIconTex = pvIconFrame:CreateTexture(nil, "ARTWORK")
                    pvIconTex:SetAllPoints()
                    pvIconTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
                    if pvIconMode == "left" then
                        pvIconFrame:SetPoint("RIGHT", pvFrame, "LEFT", 0, 0)
                    elseif pvIconMode == "right" then
                        pvIconFrame:SetPoint("LEFT", pvFrame, "RIGHT", 0, 0)
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

                -- Border preview: parented to hdr so it can span bar + icon.
                -- Reflects the actual borderSize/borderR/G/B settings.
                local bSz = bd.borderSize or 0
                if bSz > 0 then
                    local pvBorderFrame = CreateFrame("Frame", nil, hdr)
                    pvBorderFrame:SetFrameLevel(pvFrame:GetFrameLevel() + 4)
                    local PP2 = EllesmereUI and EllesmereUI.PP
                    if PP2 then
                        if pvIconMode ~= "none" and pvIconFrame then
                            if pvIconMode == "left" then
                                pvBorderFrame:SetPoint("TOPLEFT",     pvIconFrame, "TOPLEFT",     -bSz,  bSz)
                                pvBorderFrame:SetPoint("BOTTOMRIGHT", pvFrame,     "BOTTOMRIGHT",  bSz, -bSz)
                            else
                                pvBorderFrame:SetPoint("TOPLEFT",     pvFrame,     "TOPLEFT",     -bSz,  bSz)
                                pvBorderFrame:SetPoint("BOTTOMRIGHT", pvIconFrame, "BOTTOMRIGHT",  bSz, -bSz)
                            end
                        else
                            PP2.SetOutside(pvBorderFrame, pvFrame, bSz, bSz)
                        end
                        PP2.CreateBorder(pvBorderFrame,
                            bd.borderR or 0, bd.borderG or 0, bd.borderB or 0, 1, bSz)
                    end
                end

                -- Hover highlight covers bar + icon (parented to hdr for same reason)
                local eg = EllesmereUI.ELLESMERE_GREEN
                local hlContainer = CreateFrame("Frame", nil, hdr)
                hlContainer:SetFrameLevel(pvFrame:GetFrameLevel() + 6)
                if pvIconMode ~= "none" and pvIconFrame then
                    if pvIconMode == "left" then
                        hlContainer:SetPoint("TOPLEFT",     pvIconFrame, "TOPLEFT",     0, 0)
                        hlContainer:SetPoint("BOTTOMRIGHT", pvFrame,     "BOTTOMRIGHT", 0, 0)
                    elseif pvIconMode == "right" then
                        hlContainer:SetPoint("TOPLEFT",     pvFrame,     "TOPLEFT",     0, 0)
                        hlContainer:SetPoint("BOTTOMRIGHT", pvIconFrame, "BOTTOMRIGHT", 0, 0)
                    end
                else
                    hlContainer:SetAllPoints(pvFrame)
                end
                local PP2 = EllesmereUI and EllesmereUI.PP
                local pvBrd = PP2 and PP2.CreateBorder(hlContainer, eg.r, eg.g, eg.b, 1, 2, "OVERLAY", 7)
                if pvBrd then pvBrd:Hide() end

                -- Click to assign buff: toggle the picker open/closed
                pvFrame:EnableMouse(true)
                pvFrame:SetScript("OnEnter", function() if pvBrd then pvBrd:Show() end end)
                pvFrame:SetScript("OnLeave", function() if pvBrd then pvBrd:Hide() end end)
                pvFrame:SetScript("OnMouseDown", function(self)
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
                hint:SetText("Use the dropdown above to add a new bar")
            end

            -- Preview visual height = bar height (icon is always same size as bar)
            local pvVisH = PREVIEW_H

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
        --  BAR LAYOUT
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "Bar Layout", y);  y = y - h

        -- Height | Width
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 60, step = 1,
              getValue = function() local bd = SelectedTBB(); return bd and bd.height or 24 end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.height = v
                  if _tbbPvFrame then
                      _tbbPvFrame:SetHeight(v)
                      local pvIconMode = bd.iconDisplay or "none"
                      local pvVisH = v
                      if pvIconMode ~= "none" and ((bd.spellID and bd.spellID > 0) or bd.glowBased) then
                          local iSize = bd.iconSize or v
                          if iSize > pvVisH then pvVisH = iSize end
                      end
                      EllesmereUI:UpdateContentHeaderHeight(20 + 34 + 15 + pvVisH + 15)
                  end
                  ns.BuildTrackedBuffBars()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 500, step = 1,
              getValue = function() local bd = SelectedTBB(); return bd and bd.width or 270 end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.width = v
                  if _tbbPvFrame then _tbbPvFrame:SetWidth(v) end
                  ns.BuildTrackedBuffBars()
              end }
        );  y = y - h

        -- Vertical Orientation | Bar Texture
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Vertical Orientation",
              getValue = function() local bd = SelectedTBB(); return bd and bd.verticalOrientation end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.verticalOrientation = v; RefreshTBB()
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn); cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Set Name Text above None"))
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn); cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Set Duration Text above None"))
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
            { type = "label", text = "" }
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn); cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Set Stacks Text above None"))
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
              values = { none = "None", left = "Left", right = "Right" },
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

        -- Fill Color (dropdown: gradient mode + 2 inline swatches) | Show Spark
        local fillRow
        fillRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Fill Color",
              values = { none = "No Gradient", VERTICAL = "Vertical Gradient", HORIZONTAL = "Horizontal Gradient" },
              order = { "none", "VERTICAL", "HORIZONTAL" },
              getValue = function()
                  local bd = SelectedTBB(); if not bd then return "none" end
                  if not bd.gradientEnabled then return "none" end
                  return bd.gradientDir or "HORIZONTAL"
              end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
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

            -- Disable block on gradient swatch when gradient is off
            local gradBlock = CreateFrame("Frame", nil, gradSwatch)
            gradBlock:SetAllPoints(); gradBlock:SetFrameLevel(gradSwatch:GetFrameLevel() + 10)
            gradBlock:EnableMouse(true)
            gradBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(gradSwatch, EllesmereUI.DisabledTooltip("This option requires a gradient to be set"))
            end)
            gradBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateGradSwatchState()
                local bd = SelectedTBB()
                local off = not bd or not bd.gradientEnabled
                if off then gradSwatch:SetAlpha(0.3); gradBlock:Show()
                else gradSwatch:SetAlpha(1); gradBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateFillSwatch(); updateGradSwatch(); UpdateGradSwatchState() end)
            UpdateGradSwatchState()
        end

        -- Enable Stack Threshold (toggle + inline swatch) | Stack Threshold (slider)
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
              disabledTooltip = EllesmereUI.DisabledTooltip("Enable Stack Threshold"),
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
            -- Disable block when threshold is off
            local threshBlock = CreateFrame("Frame", nil, threshSwatch)
            threshBlock:SetAllPoints(); threshBlock:SetFrameLevel(threshSwatch:GetFrameLevel() + 10)
            threshBlock:EnableMouse(true)
            threshBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(threshSwatch, EllesmereUI.DisabledTooltip("Enable Stack Threshold"))
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
        -- Cog on Stack Threshold slider: enable max stacks + max stacks slider + tick marks
        do
            local rgn = threshRow._rightRegion
            local function maxStacksOff()
                local bd = SelectedTBB()
                return not bd or not bd.stackThresholdMaxEnabled
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Threshold Settings",
                rows = {
                    { type = "toggle", label = "Enable Max Stacks",
                      get = function() local bd = SelectedTBB(); return bd and bd.stackThresholdMaxEnabled end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.stackThresholdMaxEnabled = v; RefreshTBB()
                      end },
                    { type = "slider", label = "Max Stacks", min = 1, max = 50, step = 1,
                      disabled = maxStacksOff,
                      disabledTooltip = "Enable Max Stacks",
                      get = function() local bd = SelectedTBB(); return bd and bd.stackThresholdMax or 10 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.stackThresholdMax = v; RefreshTBB()
                      end },
                    { type = "input", label = "Ticks at Stacks (Ex: 1,5,8)", inputWidth = 80,
                      disabled = maxStacksOff,
                      disabledTooltip = "Enable Max Stacks",
                      get = function() local bd = SelectedTBB(); return bd and bd.stackThresholdTicks or "" end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.stackThresholdTicks = v; RefreshTBB()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
            local function UpdateThreshCogState()
                local bd = SelectedTBB()
                local off = not bd or not bd.stackThresholdEnabled
                if off then
                    cogBtn:SetAlpha(0.15); cogBtn:Disable()
                else
                    cogBtn:SetAlpha(0.4); cogBtn:Enable()
                end
            end
            cogBtn:SetScript("OnEnter", function(self)
                local bd = SelectedTBB()
                if bd and bd.stackThresholdEnabled then self:SetAlpha(0.7)
                else EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Stack Threshold")) end
            end)
            cogBtn:SetScript("OnLeave", function(self)
                UpdateThreshCogState(); EllesmereUI.HideWidgetTooltip()
            end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            EllesmereUI.RegisterWidgetRefresh(UpdateThreshCogState)
            UpdateThreshCogState()
        end

        -- Border Style (slider + inline swatch) | Background Color
        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Border Style",
              min = 0, max = 5, step = 1,
              getValue = function() local bd = SelectedTBB(); return bd and bd.borderSize or 0 end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.borderSize = v; RefreshTBB()
              end },
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
              } }
        );  y = y - h
        -- Inline border color swatch on Border Style slider
        do
            local rgn = borderRow._leftRegion
            local ctrl = rgn._control
            local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                rgn, borderRow:GetFrameLevel() + 3,
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
            local newTotal = _cdmHeaderFixedH + _cdmPreview:GetHeight() * (_cdmPreview:GetScale() or 1)
            EllesmereUI:UpdateContentHeaderHeight(newTotal)
        end
    end

    EllesmereUI:RegisterOnShow(UpdateCDMPreview)

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

        -- Ensure glow overlay exists (extended 3px like real icons)
        if not slot._glowOverlay then
            local ov = CreateFrame("Frame", nil, slot)
            ov:ClearAllPoints()
            ov:SetPoint("TOPLEFT",     slot, "TOPLEFT",     -3,  3)
            ov:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT",  3, -3)
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
            if _cdmActivePreviewOverlay then
                ns.StopNativeGlow(_cdmActivePreviewOverlay)
            end
            if slot._previewCD then
                slot._previewCD:Clear()
                slot._previewCD:Hide()
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  "Not Displayed in CDM" popup  (standard EllesmereUI confirm style)
    ---------------------------------------------------------------------------
    local function ShowNotDisplayedPopup()
        if not EllesmereUI or not EllesmereUI.ShowConfirmPopup then return end
        EllesmereUI:ShowConfirmPopup({
            title = "Spell Not Displayed",
            message = "This spell is not currently displayed in your Blizzard Cooldown Manager. Enable it there to get full cooldown, charge, and active state tracking.",
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

    local function ShowConflictBarPopup(spellName, targetIsBuffBar)
        if not EllesmereUI or not EllesmereUI.ShowConfirmPopup then return end
        local otherType = targetIsBuffBar and "a Cooldown or Utility bar" or "a Buff bar"
        EllesmereUI:ShowConfirmPopup({
            title = "Already Tracked",
            message = (spellName or "This spell") .. " is already tracked on " .. otherType .. ". Remove it from there first to add it here.",
            confirmText = "OK",
            cancelText = "Close",
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
    local function ShowSpellPicker(anchorFrame, barKey, slotIndex, excludeSet, onSelect)
        -- Toggle: if the picker is already open for this same icon, close it
        if _spellPickerMenu and _spellPickerMenu:IsShown() and _spellPickerMenu._anchorFrame == anchorFrame then
            _spellPickerMenu:Hide()
            return
        end
        -- Close existing
        if _spellPickerMenu then _spellPickerMenu:Hide() end

        local allSpells = ns.GetCDMSpellsForBar(barKey)
        -- Misc bars only show custom options (no spell list needed)
        local isMiscBarEarly = false
        do
            local bde = SelectedCDMBar()
            isMiscBarEarly = bde and bde.barType == "misc"
        end
        if not isMiscBarEarly and (not allSpells or #allSpells == 0) then return end
        if not allSpells then allSpells = {} end

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

        -- Background + border (standard dropdown style)
        local bg = menu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

        -- Build item list: tracked first (minus current), divider, rest, disabled at bottom
        local tracked = {}
        local bd = SelectedCDMBar()
        if bd and bd.customSpells then
            -- Custom bar: build tracked set by spellID
            for _, sid in ipairs(bd.customSpells) do tracked[sid] = true end
        elseif bd and bd.trackedSpells then
            for _, sid in ipairs(bd.trackedSpells) do tracked[sid] = true end
            if bd.extraSpells then
                for _, eid in ipairs(bd.extraSpells) do tracked[eid] = true end
            end
        end
        local isCustomBar = bd and bd.customSpells ~= nil

        -- Determine primary/secondary category order based on bar type.
        -- Cooldown-type bars: Essential (0) first, Utility (1) second.
        -- Utility-type bars: Utility (1) first, Essential (0) second.
        local resolvedType = (bd and bd.barType) or barKey
        local isCooldownType = (resolvedType == "cooldowns")
        local isUtilityType  = (resolvedType == "utility")
        local isCDorUtil = isCooldownType or isUtilityType
        local primaryCat   = isCooldownType and 0 or (isUtilityType and 1 or nil)
        local secondaryCat = isCooldownType and 1 or (isUtilityType and 0 or nil)

        local isMiscBar = bd and bd.barType == "misc"
        local isBuffBar = bd and (bd.barType == "buffs" or bd.key == "buffs")

        -- Buckets for cooldown/utility bars (two-section layout)
        local priDisplayed, priNotDisplayed = {}, {}
        local secDisplayed, secNotDisplayed = {}, {}
        local itemsExtra, itemsDisabled = {}, {}
        -- Buckets for other bar types (original single-section layout)
        local itemsDisplayed, itemsOther = {}, {}

        for _, sp in ipairs(allSpells) do
            local excluded = excludeSet and (excludeSet[sp.cdID] or excludeSet[sp.spellID])
            if not excluded then
                if sp.isExtra then
                    if not isBuffBar then itemsExtra[#itemsExtra + 1] = sp end
                elseif not sp.isKnown then
                    itemsDisabled[#itemsDisabled + 1] = sp
                elseif isCDorUtil then
                    if sp.cdmCat == primaryCat then
                        if sp.isDisplayed then priDisplayed[#priDisplayed + 1] = sp
                        else priNotDisplayed[#priNotDisplayed + 1] = sp end
                    elseif sp.cdmCat == secondaryCat then
                        if sp.isDisplayed then secDisplayed[#secDisplayed + 1] = sp
                        else secNotDisplayed[#secNotDisplayed + 1] = sp end
                    end
                else
                    if sp.isDisplayed then itemsDisplayed[#itemsDisplayed + 1] = sp
                    else itemsOther[#itemsOther + 1] = sp end
                end
            end
        end

        -- Inner scroll container
        local inner = CreateFrame("Frame", nil, menu)
        inner:SetWidth(menuW)
        inner:SetPoint("TOPLEFT")

        local mH = 4
        local allItems = {}

        -- "Remove Spell" option at top (only for right-click on existing icon)
        if slotIndex then
            local rmItem = CreateFrame("Button", nil, inner)
            rmItem:SetHeight(ITEM_H)
            rmItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            rmItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            rmItem:SetFrameLevel(menu:GetFrameLevel() + 2)

            local rmLbl = rmItem:CreateFontString(nil, "OVERLAY")
            rmLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            rmLbl:SetPoint("LEFT", 10, 0)
            rmLbl:SetJustifyH("LEFT")
            rmLbl:SetText("Remove Spell")
            rmLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local rmHl = rmItem:CreateTexture(nil, "ARTWORK")
            rmHl:SetAllPoints(); rmHl:SetColorTexture(1, 1, 1, 0); rmHl:SetAlpha(0)

            rmItem:SetScript("OnEnter", function()
                rmLbl:SetTextColor(1, 1, 1, 1)
                rmHl:SetColorTexture(1, 1, 1, hlA); rmHl:SetAlpha(1)
            end)
            rmItem:SetScript("OnLeave", function()
                rmLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                rmHl:SetAlpha(0)
            end)
            rmItem:SetScript("OnClick", function()
                menu:Hide()
                ns.RemoveTrackedSpell(barKey, slotIndex)
                Refresh()
                if _cdmPreview and _cdmPreview.Update then _cdmPreview:Update() end
                UpdateCDMPreviewAndResize()
            end)

            allItems[#allItems + 1] = rmItem
            mH = mH + ITEM_H

            -- Divider after Remove Spell
            local div = inner:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- "Custom Spell ID" option for all bar types: opens a popup to enter a spell ID
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
            csLbl:SetPoint("LEFT", 10, 0)
            csLbl:SetJustifyH("LEFT")
            csLbl:SetText("Custom Spell ID")
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
                    title:SetText("Add Custom Spell")
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
                    placeholder:SetText("Spell ID")
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
                    addLbl:SetPoint("CENTER"); addLbl:SetText("Add")
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
                    cLbl:SetPoint("CENTER"); cLbl:SetText("Cancel")
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
                    durLabel:SetText("Duration (seconds)")
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
                    durPlaceholder:SetText("Required")
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
                    -- Check if already tracked
                    if bd and bd.customSpells then
                        for _, existing in ipairs(bd.customSpells) do
                            if existing == sid then
                                SetStatus("Already tracked")
                                return
                            end
                        end
                    end
                    if bd and bd.trackedSpells then
                        for _, existing in ipairs(bd.trackedSpells) do
                            if existing == sid then
                                SetStatus("Already tracked")
                                return
                            end
                        end
                    end
                    if bd and bd.extraSpells then
                        for _, existing in ipairs(bd.extraSpells) do
                            if existing == sid then
                                SetStatus("Already tracked")
                                return
                            end
                        end
                    end
                    popup._dimmer:Hide()
                    if onSelect then onSelect(sid, true) end
                end

                popup._addBtn:SetScript("OnClick", DoAdd)
                popup._editBox:SetScript("OnEnterPressed", DoAdd)
                popup._editBox:SetText("")
                popup._status:SetText("")
                popup:SetHeight(160)
                popup._durLabel:Hide()
                popup._durBox:Hide()
                popup._dimmer:Show()
                popup._editBox:SetFocus()
            end)

            allItems[#allItems + 1] = csItem
            mH = mH + ITEM_H

            -- Divider below Custom Spell ID
            local csDiv = inner:CreateTexture(nil, "ARTWORK")
            csDiv:SetHeight(1)
            csDiv:SetColorTexture(1, 1, 1, 0.10)
            csDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            csDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        -- "Custom Item" sub-menu for misc bars: on-use bag items
        -- Bag scan starts immediately when the picker opens so tooltip data
        -- can cache in the background; the sub-menu refreshes live as items load.
        local _customTrackingSub
        local _cachedBagItems       -- cached scan results (populated async)
        local _bagScanComplete = false
        if isMiscBar then
            -- Scan bags for on-use items with real cooldowns
            -- Blacklist: items that pass filters but should not appear
            local BAG_ITEM_BLACKLIST = {
                [234389] = true, -- Gallagio Loyalty Rewards Card: Silver
                [234390] = true, -- Gallagio Loyalty Rewards Card: Gold
                [249699] = true, -- Shadowguard Translocator
            }
            local MIN_CD_SEC = 30
            local MAX_CD_SEC = 660  -- 11 minutes

            -- Collect candidate itemIDs from bags (fast, no tooltip needed)
            local _candidateItems = {}
            do
                local seen = {}
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
                                        itemID = info.itemID,
                                        spellName = spellName,
                                        spellID = spellID,
                                    }
                                    -- Pre-request item data so tooltip info caches
                                    C_Item.RequestLoadItemDataByID(info.itemID)
                                end
                            end
                        end
                    end
                end
            end

            -- Resolve candidates into final results using tooltip cooldown data.
            -- Returns true if all candidates have been resolved.
            local function ResolveBagItems()
                local results = {}
                local allResolved = true
                for _, cand in ipairs(_candidateItems) do
                    local tipData = C_TooltipInfo.GetItemByID(cand.itemID)
                    if tipData and tipData.lines then
                        local cdSec = nil
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
                                    if totalSec > 0 then cdSec = totalSec end
                                    break
                                end
                            end
                        end
                        if cdSec and cdSec >= MIN_CD_SEC and cdSec <= MAX_CD_SEC then
                            local tex = C_Item.GetItemIconByID(cand.itemID)
                            local itemName = C_Item.GetItemNameByID(cand.itemID)
                            results[#results + 1] = {
                                itemID = cand.itemID,
                                name = itemName or cand.spellName,
                                icon = tex,
                                spellID = cand.spellID,
                            }
                        end
                        -- Item data loaded (even if it didn't qualify) -- resolved
                    else
                        allResolved = false
                    end
                end
                table.sort(results, function(a, b) return a.name < b.name end)
                _cachedBagItems = results
                _bagScanComplete = allResolved
                return allResolved
            end

            -- Kick off the first resolve immediately (will get whatever is cached)
            ResolveBagItems()

            -- If not all resolved, poll until done (tooltip data loads async)
            if not _bagScanComplete then
                local attempts = 0
                local ticker
                ticker = C_Timer.NewTicker(0.2, function()
                    attempts = attempts + 1
                    local done = ResolveBagItems()
                    if done or attempts >= 25 then
                        if ticker then ticker:Cancel() end
                        _bagScanComplete = true
                        -- If the sub-menu is already visible, rebuild it live
                        if _customTrackingSub and _customTrackingSub:IsShown() then
                            _customTrackingSub._needsRebuild = true
                        end
                    elseif _customTrackingSub and _customTrackingSub:IsShown() then
                        -- Rebuild live as more items resolve
                        _customTrackingSub._needsRebuild = true
                    end
                end)
                -- Clean up ticker when menu closes
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
            ctLbl:SetPoint("LEFT", 10, 0)
            ctLbl:SetJustifyH("LEFT")
            ctLbl:SetText("Custom Item")
            ctLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local ctArrow = ctItem:CreateTexture(nil, "ARTWORK")
            ctArrow:SetSize(10, 10)
            ctArrow:SetPoint("RIGHT", ctItem, "RIGHT", -8, 0)
            ctArrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
            ctArrow:SetAlpha(0.7)

            local function ShowCustomTrackingSub()
                -- Filter out items already tracked on this bar
                local items = _cachedBagItems or {}
                local alreadyTracked = {}
                if bd and bd.customSpells then
                    for _, sid in ipairs(bd.customSpells) do
                        if sid <= -100 then alreadyTracked[-sid] = true end
                    end
                end
                local filtered = {}
                for _, it in ipairs(items) do
                    if not alreadyTracked[it.itemID] then
                        filtered[#filtered + 1] = it
                    end
                end

                -- Track the last filtered count so we know when to rebuild
                local prevCount = _customTrackingSub and _customTrackingSub._itemCount or -1

                if not _customTrackingSub then
                    _customTrackingSub = CreateFrame("Frame", nil, UIParent)
                    _customTrackingSub:SetFrameStrata("FULLSCREEN_DIALOG")
                    _customTrackingSub:SetFrameLevel(menu:GetFrameLevel() + 5)
                    _customTrackingSub:SetClampedToScreen(true)
                    _customTrackingSub:EnableMouse(true)
                elseif _customTrackingSub:IsShown() and #filtered == prevCount and not _customTrackingSub._needsRebuild then
                    return -- already showing with same items
                else
                    -- Clear previous children
                    for _, child in ipairs({_customTrackingSub:GetChildren()}) do
                        child:Hide(); child:SetParent(nil)
                    end
                    for _, rgn in ipairs({_customTrackingSub:GetRegions()}) do
                        if rgn.Hide then rgn:Hide() end
                    end
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
                subBg:SetAllPoints()
                subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                EllesmereUI.MakeBorder(_customTrackingSub, 1, 1, 1, mBrdA, EllesmereUI.PP)

                -- Inner frame for items (scrollable if needed)
                local subInner = CreateFrame("Frame", nil, _customTrackingSub)
                subInner:SetWidth(subW)
                subInner:SetPoint("TOPLEFT")

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
                        local zoom = 0.08
                        sIco:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

                        local sLbl = si:CreateFontString(nil, "OVERLAY")
                        sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                        sLbl:SetPoint("RIGHT", sIco, "LEFT", -5, 0)
                        sLbl:SetJustifyH("LEFT")
                        sLbl:SetWordWrap(false)
                        sLbl:SetMaxLines(1)
                        sLbl:SetText(it.name)
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

                        local sHl = si:CreateTexture(nil, "ARTWORK")
                        sHl:SetAllPoints()
                        sHl:SetColorTexture(1, 1, 1, 0); sHl:SetAlpha(0)

                        si:SetScript("OnEnter", function()
                            sLbl:SetTextColor(1, 1, 1, 1)
                            sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                        end)
                        si:SetScript("OnLeave", function()
                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            sHl:SetAlpha(0)
                        end)
                        si:SetScript("OnClick", function()
                            _customTrackingSub:Hide()
                            menu:Hide()
                            -- Store as negated itemID
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
                    sf:EnableMouseWheel(true)
                    sf:SetScrollChild(subInner)
                    subInner:SetWidth(subW)
                    local scrollPos = 0
                    local maxScroll = totalSubH - SUB_MAX_H
                    sf:SetScript("OnMouseWheel", function(_, delta)
                        scrollPos = math.max(0, math.min(maxScroll, scrollPos - delta * 30))
                        sf:SetVerticalScroll(scrollPos)
                    end)
                else
                    _customTrackingSub:SetHeight(totalSubH)
                    subInner:SetParent(_customTrackingSub)
                    subInner:SetPoint("TOPLEFT")
                end
                _customTrackingSub:SetScript("OnLeave", function(self)
                    C_Timer.After(0.1, function()
                        if self:IsShown() and not self:IsMouseOver()
                           and not ctItem:IsMouseOver() then
                            self:Hide()
                        end
                    end)
                end)
                -- Live-rebuild when async item data finishes loading
                if not _bagScanComplete then
                    _customTrackingSub:SetScript("OnUpdate", function(self)
                        if self._needsRebuild then
                            ShowCustomTrackingSub()
                        end
                        -- Stop polling once scan is done
                        if _bagScanComplete then
                            self:SetScript("OnUpdate", nil)
                        end
                    end)
                else
                    _customTrackingSub:SetScript("OnUpdate", nil)
                end
                _customTrackingSub:Show()
            end

            ctItem:SetScript("OnEnter", function()
                ctLbl:SetTextColor(1, 1, 1, 1)
                ctHl:SetColorTexture(1, 1, 1, hlA); ctHl:SetAlpha(1)
                ShowCustomTrackingSub()
            end)
            ctItem:SetScript("OnLeave", function()
                ctLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                ctHl:SetAlpha(0)
                -- Delay hide so user can move mouse to sub-menu
                C_Timer.After(0.15, function()
                    if _customTrackingSub and _customTrackingSub:IsShown()
                       and not _customTrackingSub:IsMouseOver()
                       and not ctItem:IsMouseOver() then
                        _customTrackingSub:Hide()
                    end
                end)
            end)

            allItems[#allItems + 1] = ctItem
            mH = mH + ITEM_H

            -- "Custom Spell ID" option: opens a popup to enter a spell ID
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
            csLbl:SetText("Custom Spell ID")
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
                -- Show spell ID input popup
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
                    title:SetText("Add Custom Spell")
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
                    placeholder:SetText("Spell ID")
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

                    -- Add button
                    local ar, ag, ab = EllesmereUI.GetAccentColor()
                    local addBtn = CreateFrame("Button", nil, popup)
                    addBtn:SetSize(80, 28)
                    addBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
                    local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
                    addBg:SetAllPoints(); addBg:SetColorTexture(ar, ag, ab, 0.15)
                    EllesmereUI.MakeBorder(addBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
                    local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
                    addLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
                    addLbl:SetPoint("CENTER"); addLbl:SetText("Add")
                    addLbl:SetTextColor(ar, ag, ab, 0.9)
                    addBtn:SetScript("OnEnter", function() addLbl:SetTextColor(1, 1, 1, 1) end)
                    addBtn:SetScript("OnLeave", function() addLbl:SetTextColor(ar, ag, ab, 0.9) end)
                    popup._addBtn = addBtn

                    -- Cancel button
                    local cancelBtn = CreateFrame("Button", nil, popup)
                    cancelBtn:SetSize(80, 28)
                    cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)
                    local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
                    cBg:SetAllPoints(); cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
                    EllesmereUI.MakeBorder(cancelBtn, 1, 1, 1, 0.10, EllesmereUI.PP)
                    local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
                    cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
                    cLbl:SetPoint("CENTER"); cLbl:SetText("Cancel")
                    cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
                    cancelBtn:SetScript("OnEnter", function() cLbl:SetTextColor(1, 1, 1, 1) end)
                    cancelBtn:SetScript("OnLeave", function() cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8) end)
                    cancelBtn:SetScript("OnClick", function() dimmer:Hide() end)
                    popup._cancelBtn = cancelBtn

                    editBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)

                    -- Duration field (shown only for buff-type bars)
                    local durLabel = popup:CreateFontString(nil, "OVERLAY")
                    durLabel:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    durLabel:SetPoint("TOP", editBox, "BOTTOM", 0, -32)
                    durLabel:SetTextColor(0.7, 0.7, 0.7, 0.85)
                    durLabel:SetText("Duration (seconds)")
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
                    durPlaceholder:SetText("Required")
                    durBox:SetScript("OnTextChanged", function(self)
                        if self:GetText() == "" then durPlaceholder:Show() else durPlaceholder:Hide() end
                    end)
                    durBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)
                    popup._durBox = durBox

                    popup._dimmer = dimmer
                    _G[popupName] = popup
                end

                -- Wire up the Add action for this invocation
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
                    -- Check if already tracked
                    if bd and bd.customSpells then
                        for _, existing in ipairs(bd.customSpells) do
                            if existing == sid then
                                SetStatus("Already tracked")
                                return
                            end
                        end
                    end
                    -- Store duration (required for buff bars, optional otherwise)
                    if isBuffBar then
                        if not popup._durBox or not popup._durBox:IsShown() then
                            SetStatus("Duration is required")
                            return
                        end
                        local durText = popup._durBox:GetText()
                        local dur = tonumber(durText)
                        if not dur or dur <= 0 then
                            SetStatus("Enter a duration in seconds")
                            return
                        end
                        if not bd.customSpellDurations then bd.customSpellDurations = {} end
                        bd.customSpellDurations[sid] = math.floor(dur)
                    end
                    popup._dimmer:Hide()
                    if onSelect then onSelect(sid, true) end
                end

                popup._addBtn:SetScript("OnClick", DoAdd)
                popup._editBox:SetScript("OnEnterPressed", DoAdd)
                popup._editBox:SetText("")
                popup._status:SetText("")
                -- Show/hide duration field based on bar type
                if isBuffBar then
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

        -- "Presets" flyout row for buff bars
        local _presetsSub
        if isBuffBar then
            local psItem = CreateFrame("Button", nil, inner)
            psItem:SetHeight(ITEM_H)
            psItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            psItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            psItem:SetFrameLevel(menu:GetFrameLevel() + 2)

            local psHl = psItem:CreateTexture(nil, "ARTWORK")
            psHl:SetAllPoints(); psHl:SetColorTexture(1, 1, 1, 0); psHl:SetAlpha(0)

            local psLbl = psItem:CreateFontString(nil, "OVERLAY")
            psLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            psLbl:SetPoint("LEFT", 10, 0)
            psLbl:SetJustifyH("LEFT")
            psLbl:SetText("Presets")
            psLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local psArrow = psItem:CreateTexture(nil, "ARTWORK")
            psArrow:SetSize(10, 10)
            psArrow:SetPoint("RIGHT", psItem, "RIGHT", -8, 0)
            psArrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
            psArrow:SetAlpha(0.7)

            local function ShowPresetsSub()
                -- Build the already-tracked primary IDs so we can grey out duplicates
                local alreadyTracked = {}
                if bd and bd.customSpells then
                    for _, sid in ipairs(bd.customSpells) do alreadyTracked[sid] = true end
                end

                if not _presetsSub then
                    _presetsSub = CreateFrame("Frame", nil, UIParent)
                    _presetsSub:SetFrameStrata("FULLSCREEN_DIALOG")
                    _presetsSub:SetFrameLevel(menu:GetFrameLevel() + 5)
                    _presetsSub:SetClampedToScreen(true)
                    _presetsSub:EnableMouse(true)
                elseif _presetsSub:IsShown() then
                    return -- already visible, nothing to do
                else
                    for _, child in ipairs({_presetsSub:GetChildren()}) do
                        child:Hide(); child:SetParent(nil)
                    end
                    for _, rgn in ipairs({_presetsSub:GetRegions()}) do
                        if rgn.Hide then rgn:Hide() end
                    end
                end

                local subW = 220
                local SUB_ITEM_H = 26
                _presetsSub:SetSize(subW, 10)
                _presetsSub:ClearAllPoints()
                _presetsSub:SetPoint("TOPLEFT", psItem, "TOPRIGHT", 2, 0)

                local subBg = _presetsSub:CreateTexture(nil, "BACKGROUND")
                subBg:SetAllPoints()
                subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                EllesmereUI.MakeBorder(_presetsSub, 1, 1, 1, mBrdA, EllesmereUI.PP)

                local subInner = CreateFrame("Frame", nil, _presetsSub)
                subInner:SetWidth(subW)
                subInner:SetPoint("TOPLEFT")

                local subH = 4

                for _, preset in ipairs(ns.BUFF_BAR_PRESETS) do
                    local primaryID = preset.spellIDs[1]
                    local isAdded = alreadyTracked[primaryID]

                    local si = CreateFrame("Button", nil, subInner)
                    si:SetHeight(SUB_ITEM_H)
                    si:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -subH)
                    si:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -subH)
                    si:SetFrameLevel(_presetsSub:GetFrameLevel() + 2)
                    si:RegisterForClicks("AnyUp")

                    local sIco = si:CreateTexture(nil, "ARTWORK")
                    local icoSz = SUB_ITEM_H - 2
                    sIco:SetSize(icoSz, icoSz)
                    sIco:SetPoint("RIGHT", si, "RIGHT", -6, 0)
                    sIco:SetTexture(preset.icon)
                    local zoom = 0.08
                    sIco:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

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

                    if isAdded then
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                        sIco:SetDesaturated(true)
                        sIco:SetAlpha(0.4)
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
                            _presetsSub:Hide()
                            menu:Hide()
                            ns.AddPresetToBar(barKey, preset)
                            Refresh()
                            if _cdmPreview and _cdmPreview.Update then _cdmPreview:Update() end
                            UpdateCDMPreviewAndResize()
                        end)
                    end

                    subH = subH + SUB_ITEM_H
                end

                local totalSubH = subH + 4
                subInner:SetHeight(totalSubH)
                _presetsSub:SetHeight(totalSubH)
                subInner:SetParent(_presetsSub)
                subInner:SetPoint("TOPLEFT")

                _presetsSub:SetScript("OnLeave", function(self)
                    C_Timer.After(0.1, function()
                        if self:IsShown() and not self:IsMouseOver()
                           and not psItem:IsMouseOver() then
                            self:Hide()
                        end
                    end)
                end)
                _presetsSub:Show()
            end

            psItem:SetScript("OnEnter", function()
                psLbl:SetTextColor(1, 1, 1, 1)
                psHl:SetColorTexture(1, 1, 1, hlA); psHl:SetAlpha(1)
                ShowPresetsSub()
            end)
            psItem:SetScript("OnLeave", function()
                psLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                psHl:SetAlpha(0)
                C_Timer.After(0.15, function()
                    if _presetsSub and _presetsSub:IsShown()
                       and not _presetsSub:IsMouseOver()
                       and not psItem:IsMouseOver() then
                        _presetsSub:Hide()
                    end
                end)
            end)

            allItems[#allItems + 1] = psItem
            mH = mH + ITEM_H
        end

        local function MakeItem(sp, isDisabled, firesPopup)
            -- Check if this spell belongs to the wrong category group for this bar type.
            -- e.g. a cooldown-category spell on a buffs bar, or vice versa.
            local wrongCatGroup = false
            if not isDisabled and sp.cdmCatGroup then
                if isBuffBar and sp.cdmCatGroup == "cooldown" then
                    wrongCatGroup = true
                elseif not isBuffBar and not isMiscBar and sp.cdmCatGroup == "buff" then
                    wrongCatGroup = true
                end
            end
            -- Conflict: spell is already tracked on a bar of the opposite type
            local isConflict = not isDisabled and not wrongCatGroup and sp.isConflict
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

            if isDisabled then
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                ico:SetDesaturated(true)
                ico:SetAlpha(0.4)
            elseif isConflict then
                -- Spell is tracked on a bar of the opposite type: show dimmed, clickable for info
                lbl:SetTextColor(tDimR * 0.7, tDimG * 0.7, tDimB * 0.7, tDimA * 0.5)
                ico:SetDesaturated(true)
                ico:SetAlpha(0.35)
                item:SetScript("OnEnter", function()
                    lbl:SetTextColor(1, 0.6, 0.2, 0.9)
                    hl:SetColorTexture(1, 1, 1, hlA * 0.5); hl:SetAlpha(1)
                end)
                item:SetScript("OnLeave", function()
                    lbl:SetTextColor(tDimR * 0.7, tDimG * 0.7, tDimB * 0.7, tDimA * 0.5)
                    hl:SetAlpha(0)
                end)
                item:SetScript("OnClick", function()
                    menu:Hide()
                    ShowConflictBarPopup(sp.name, isBuffBar)
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
                    if firesPopup then
                        ShowNotDisplayedPopup()
                        return
                    end
                    -- Always pass spellID (trackedSpells stores spellIDs)
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

        if isMiscBar then
            -- Misc bars: only show extras (trinket slots, racials, etc.)
            -- Skip all cooldown/utility/buff spell categories.
            if isMiscBar and mH > 4 and #itemsExtra > 0 then MakeDivider() end
            for _, sp in ipairs(itemsExtra) do MakeItem(sp, false, false) end
        elseif isCDorUtil then
            -- Layout: available primary -> unavailable primary -> available secondary
            -- -> unavailable secondary -> disabled (unlearned)
            local hasPriDisp    = #priDisplayed > 0
            local hasPriNotDisp = #priNotDisplayed > 0
            local hasSecDisp    = #secDisplayed > 0
            local hasSecNotDisp = #secNotDisplayed > 0
            local hasDisabled   = #itemsDisabled > 0
            local needDiv = false

            for _, sp in ipairs(priDisplayed) do MakeItem(sp, false, false) end
            needDiv = hasPriDisp

            if hasPriNotDisp then
                if needDiv then MakeDivider() end
                for _, sp in ipairs(priNotDisplayed) do MakeItem(sp, false, true) end
                needDiv = true
            end

            if hasSecDisp then
                if needDiv then MakeDivider() end
                for _, sp in ipairs(secDisplayed) do MakeItem(sp, false, false) end
                needDiv = true
            end

            if hasSecNotDisp then
                if needDiv then MakeDivider() end
                for _, sp in ipairs(secNotDisplayed) do MakeItem(sp, false, true) end
                needDiv = true
            end

            if hasDisabled then
                if needDiv then MakeDivider() end
                for _, sp in ipairs(itemsDisabled) do MakeItem(sp, true, false) end
            end
        else
            -- Original layout for buff/trinket/other bars
            for _, sp in ipairs(itemsDisplayed) do MakeItem(sp, false, false) end

            local hasAfterDisplayed = #itemsExtra > 0 or #itemsOther > 0 or #itemsDisabled > 0
            if #itemsDisplayed > 0 and hasAfterDisplayed then MakeDivider() end

            for _, sp in ipairs(itemsExtra) do MakeItem(sp, false, false) end

            if #itemsExtra > 0 and (#itemsOther > 0 or #itemsDisabled > 0) then MakeDivider() end

            for _, sp in ipairs(itemsOther) do MakeItem(sp, false, true) end

            if #itemsDisabled > 0 and (#itemsDisplayed > 0 or #itemsExtra > 0 or #itemsOther > 0) then MakeDivider() end

            for _, sp in ipairs(itemsDisabled) do MakeItem(sp, true, false) end
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
            local scrollPos = 0
            local maxScroll = totalH - MAX_H
            sf:SetScript("OnMouseWheel", function(_, delta)
                scrollPos = max(0, min(maxScroll, scrollPos - delta * 30))
                sf:SetVerticalScroll(scrollPos)
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
            local overSub = _customTrackingSub and _customTrackingSub:IsShown() and _customTrackingSub:IsMouseOver()
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
        local pf = CreateFrame("Frame", nil, parent)
        pf:SetClipsChildren(false)

        local previewScale = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
        pf:SetScale(previewScale)

        local localParentW = (parent:GetWidth() - PAD * 2) / previewScale
        local initH = (barData.iconSize or 36) + 10
        pf:SetSize(localParentW, initH)
        PP.Point(pf, "TOPLEFT", parent, "TOPLEFT", PAD / previewScale, yOff / previewScale)

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
            local spacing = bd.spacing or 2
            local grow = bd.growDirection or "RIGHT"
            local growLeft = (grow == "LEFT")

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
                        -- Cursor is in the left half of this slot — insert before it logically
                        if growLeft then
                            return "insert", i + 1
                        else
                            return "insert", i
                        end
                    else
                        -- Cursor is in the right half of this slot — insert after it logically
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
            local growLeft = bd and (bd.growDirection or "RIGHT") == "LEFT"

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
            slot._edges = sEdges  -- kept empty for compat; borders managed by PP

            -- Hover highlight (2px accent border, child container avoids conflict with existing PP border)
            local eg = EllesmereUI.ELLESMERE_GREEN
            local slotHlCont = CreateFrame("Frame", nil, slot)
            slotHlCont:SetAllPoints()
            slotHlCont:SetFrameLevel(slot:GetFrameLevel() + 1)
            local slotPP = EllesmereUI and EllesmereUI.PP
            local slotBrd = slotPP and slotPP.CreateBorder(slotHlCont, eg.r, eg.g, eg.b, 1, 2, "OVERLAY", 7)
            if slotBrd then slotBrd:Hide() end
            slot._hlBrd = slotBrd
            slot._stackText = slot:CreateFontString(nil, "OVERLAY")
            SetPVFont(slot._stackText, FONT_PATH, 11)
            slot._stackText:SetPoint("BOTTOMRIGHT", 0, 2)
            slot._stackText:SetJustifyH("RIGHT")
            slot._stackText:Hide()
            local stackTxt = slot._stackText

            -- Keybind text (mirrors _keybindText on real CDM icons)
            local kbTxt = slot:CreateFontString(nil, "OVERLAY")
            SetPVFont(kbTxt, FONT_PATH, 9)
            kbTxt:SetPoint("TOPLEFT", 2, -2)
            kbTxt:SetJustifyH("LEFT")
            kbTxt:Hide()
            slot._keybindText = kbTxt

            slot:SetScript("OnEnter", function()
                if dragSlot then return end
                -- Custom shapes: tint the shape border instead of square edges
                if slot._shapeBorder and slot._shapeBorder:IsShown() then
                    slot._shapeBorder:SetVertexColor(eg.r, eg.g, eg.b, 1)
                else
                    if slotBrd then slotBrd:Show() end
                end
            end)
            slot:SetScript("OnLeave", function()
                if dragSlot then return end
                if slot._shapeBorder and slot._shapeBorder:IsShown() then
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
                    slot._shapeBorder:SetVertexColor(bR, bG, bB, 1)
                else
                    if slotBrd then slotBrd:Hide() end
                end
            end)

            slot._slotIdx = idx

            -- Right-click: spell picker to replace; Middle-click: remove
            slot:SetScript("OnClick", function(self, button)
                if GetTime() - dragEndTime < 0.2 then
                    return
                end
                if button == "MiddleButton" then
                    local bd = SelectedCDMBar()
                    if not bd then return end
                    local si = self._slotIdx
                    if bd.customSpells then
                        local t = bd.customSpells
                        if not t[si] or t[si] == 0 then return end
                    else
                        local tLen = bd.trackedSpells and #bd.trackedSpells or 0
                        local eLen = bd.extraSpells and #bd.extraSpells or 0
                        if si < 1 or si > tLen + eLen then return end
                    end
                    ns.RemoveTrackedSpell(bd.key, si)
                    Refresh()
                    if _cdmPreview and _cdmPreview.Update then _cdmPreview:Update() end
                    UpdateCDMPreviewAndResize()
                elseif button == "RightButton" or button == "LeftButton" then
                    local bd = SelectedCDMBar()
                    if not bd then return end
                    local si = self._slotIdx

                    -- Determine if this slot is occupied or empty
                    local isOccupied = false
                    if bd.customSpells then
                        local t = bd.customSpells
                        isOccupied = t and t[si] and t[si] ~= 0
                    else
                        local tLen = bd.trackedSpells and #bd.trackedSpells or 0
                        local eLen = bd.extraSpells and #bd.extraSpells or 0
                        isOccupied = si >= 1 and si <= tLen + eLen
                    end

                    if isOccupied then
                        -- Occupied slot: open picker to replace, exclude only this spell
                        local excl = {}
                        if bd.customSpells then
                            local t = bd.customSpells
                            excl[t[si]] = true
                        else
                            local tLen = bd.trackedSpells and #bd.trackedSpells or 0
                            if si <= tLen then
                                if bd.trackedSpells[si] and bd.trackedSpells[si] ~= 0 then
                                    excl[bd.trackedSpells[si]] = true
                                end
                            else
                                local eIdx = si - tLen
                                if bd.extraSpells and bd.extraSpells[eIdx] then
                                    excl[bd.extraSpells[eIdx]] = true
                                end
                            end
                        end
                        ShowSpellPicker(self, bd.key, si, excl, function(newSpellID, isExtra)
                            ns.ReplaceTrackedSpell(bd.key, si, newSpellID, isExtra)
                            ns.BuildAllCDMBars(); Refresh()
                            C_Timer.After(0.05, function()
                                if pf.Update then pf:Update() end
                                UpdateCDMPreviewAndResize()
                            end)
                        end)
                    else
                        -- Empty slot: open picker to add, exclude all currently tracked spells
                        local excl = {}
                        if bd.customSpells then
                            for _, sid in ipairs(bd.customSpells) do excl[sid] = true end
                        else
                            if bd.trackedSpells then
                                for _, sid in ipairs(bd.trackedSpells) do excl[sid] = true end
                            end
                            if bd.extraSpells then
                                for _, eid in ipairs(bd.extraSpells) do excl[eid] = true end
                            end
                        end
                        ShowSpellPicker(self, bd.key, nil, excl, function(newSpellID, isExtra)
                            ns.AddTrackedSpell(bd.key, newSpellID, isExtra)
                            ns.BuildAllCDMBars(); Refresh()
                            C_Timer.After(0.05, function()
                                if pf.Update then pf:Update() end
                                UpdateCDMPreviewAndResize()
                            end)
                        end)
                    end
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
                local t
                if bd.customSpells then
                    t = bd.customSpells
                else
                    t = {}
                    if bd.trackedSpells then for _, v in ipairs(bd.trackedSpells) do t[#t + 1] = v end end
                    if bd.extraSpells then for _, v in ipairs(bd.extraSpells) do t[#t + 1] = v end end
                end
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
                        if tBd.customSpells then
                            tCount = #tBd.customSpells
                        else
                            tCount = (tBd.trackedSpells and #tBd.trackedSpells or 0) + (tBd.extraSpells and #tBd.extraSpells or 0)
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
            local excl = {}
            if bd.customSpells then
                -- Custom bar: exclude by spellID (customSpells stores spellIDs)
                for _, sid in ipairs(bd.customSpells) do excl[sid] = true end
            else
                if bd.trackedSpells then
                    for _, sid in ipairs(bd.trackedSpells) do excl[sid] = true end
                end
                if bd.extraSpells then
                    for _, eid in ipairs(bd.extraSpells) do excl[eid] = true end
                end
            end
            ShowSpellPicker(self, bd.key, nil, excl, function(newSpellID, isExtra)
                ns.AddTrackedSpell(bd.key, newSpellID, isExtra)
                ns.BuildAllCDMBars(); Refresh()
                C_Timer.After(0.05, function()
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
                addBtn:Hide(); self:SetHeight(1); return
            end

            local iconSize = bd.iconSize or 36
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

            local tracked
            local isCustomBar = (bd.customSpells ~= nil)
            if isCustomBar then
                tracked = bd.customSpells
            else
                -- Default bar: combine trackedSpells + extraSpells into one display list
                tracked = {}
                if bd.trackedSpells then
                    for _, v in ipairs(bd.trackedSpells) do tracked[#tracked + 1] = v end
                end
                if bd.extraSpells then
                    for _, v in ipairs(bd.extraSpells) do tracked[#tracked + 1] = v end
                end
            end
            local count = #tracked

            -- Spell columns: enough to fit all spells with full rows
            local stride = math.ceil(count / numRows)
            if stride < 1 then stride = 1 end
            local gridSlots = (count > 0) and (stride * numRows) or 0
            self._stride = stride
            self._numRows = numRows
            self._gridSlots = gridSlots

            -- How many icons on the top row (remainder). Bottom rows are full.
            local topRowCount = count - (numRows - 1) * stride
            if topRowCount < 0 then topRowCount = 0 end
            local topRowHasLess = (topRowCount > 0 and topRowCount < stride)

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

            local curParentW = (parent:GetWidth() - PAD * 2) / previewScale
            if curParentW > 0 then
                self:SetWidth(curParentW)
            end
            local startX = math.floor((curParentW - totalW) / 2)
            -- For LEFT grow, the "+" button sits to the left of the spell grid.
            -- Shift the spell grid right by one slot so the whole group stays centered.
            if not isVert and grow == "LEFT" then
                startX = startX + (iconSize + spacing)
            end
            local startY = -5

            -- Position helper: places frame at grid position (col, row).
            -- Row 0 = top row (partial, centered when fewer icons).
            -- Rows 1..numRows-1 = bottom rows (always full).
            local function PosAtGrid(frame, col, row)
                PP.Size(frame, iconSize, iconH); frame:ClearAllPoints()
                -- Centering only applies to top row when it has fewer icons
                local rowOffset = 0
                if isVert then
                    if row == 0 and topRowHasLess then
                        rowOffset = math.floor((stride - topRowCount) * (iconH + spacing) / 2)
                    end
                    local px = startX + row * (iconSize + spacing)
                    local py
                    if grow == "UP" then
                        py = startY - (stride - 1 - col) * (iconH + spacing) - rowOffset
                    else
                        py = startY - col * (iconH + spacing) - rowOffset
                    end
                    PP.Point(frame, "TOPLEFT", self, "TOPLEFT", px, py)
                    frame._baseX = px
                    frame._baseY = py
                else
                    if row == 0 and topRowHasLess then
                        rowOffset = math.floor((stride - topRowCount) * (iconSize + spacing) / 2)
                    end
                    local px
                    if grow == "LEFT" then
                        px = startX + (stride - 1 - col) * (iconSize + spacing) + rowOffset
                    else
                        px = startX + col * (iconSize + spacing) + rowOffset
                    end
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
                    if id then
                        local tex
                        if isCustomBar then
                            if id <= -100 then
                                -- On-use bag item: negated itemID
                                tex = C_Item.GetItemIconByID(-id)
                            elseif id < 0 then
                                -- Trinket slot: get icon from equipped item
                                local itemID = GetInventoryItemID("player", -id)
                                tex = itemID and C_Item.GetItemIconByID(itemID) or nil
                            else
                                tex = C_Spell.GetSpellTexture(id)
                                slot._previewSpellID = id
                            end
                        else
                            -- Default bar: check if this is an extra spell
                            local trackedLen = bd.trackedSpells and #bd.trackedSpells or 0
                            if i > trackedLen then
                                -- Extra spell (trinket/racial/potion/bag item)
                                if id <= -100 then
                                    tex = C_Item.GetItemIconByID(-id)
                                elseif id < 0 then
                                    local itemID = GetInventoryItemID("player", -id)
                                    tex = itemID and C_Item.GetItemIconByID(itemID) or nil
                                else
                                    tex = C_Spell.GetSpellTexture(id)
                                    slot._previewSpellID = id
                                end
                            else
                                -- Tracked spell (spellID-based)
                                tex = C_Spell.GetSpellTexture(id)
                                slot._previewSpellID = id > 0 and id or nil
                            end
                        end
                        if tex then
                            slot._icon:SetTexture(tex)
                            slot._icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                            slot._icon:SetDesaturated(false)
                        else slot._icon:SetTexture(nil) end
                    else slot._icon:SetTexture(nil) end
                else
                    -- Blank slot (empty grid filler)
                    slot._icon:SetTexture(nil)
                    slot._previewSpellID = nil
                end

                local bSz = bd.borderSize or 1
                slot._icon:ClearAllPoints()
                PP.Point(slot._icon, "TOPLEFT", slot, "TOPLEFT", bSz, -bSz)
                PP.Point(slot._icon, "BOTTOMRIGHT", slot, "BOTTOMRIGHT", -bSz, bSz)
                slot._icon:Show()

                if slot._ppBorders then
                    PP.SetBorderColor(slot, bR, bG, bB, 1)
                    PP.SetBorderSize(slot, bSz)
                end
                slot._bg:SetColorTexture(bd.bgR or 0.08, bd.bgG or 0.08, bd.bgB or 0.08, bd.bgA or 0.6)
                if slot._bg.SetSnapToPixelGrid then slot._bg:SetSnapToPixelGrid(false); slot._bg:SetTexelSnappingBias(0) end

                ns.ApplyShapeToCDMIcon(slot, shape, bd)

                -- Stack count preview text
                if slot._stackText then
                    if i <= count then
                        SetPVFont(slot._stackText, FONT_PATH, bd.stackCountSize or 11)
                        slot._stackText:ClearAllPoints()
                        slot._stackText:SetPoint("BOTTOMRIGHT", bd.stackCountX or 0, (bd.stackCountY or 0) + 2)
                        slot._stackText:SetTextColor(bd.stackCountR or 1, bd.stackCountG or 1, bd.stackCountB or 1)
                        -- Only show charge count preview for charge-based spells when showCharges is enabled
                        local sid = slot._previewSpellID
                        if sid and not (InCombatLockdown and InCombatLockdown()) then ns.CacheMultiChargeSpell(sid) end
                        local isChargeSp = sid and ns._multiChargeSpells and ns._multiChargeSpells[sid]
                        if bd.showCharges and isChargeSp then
                            local maxC = ns._maxChargeCount and ns._maxChargeCount[sid]
                            slot._stackText:SetText(maxC and tostring(maxC) or "2")
                            slot._stackText:Show()
                        else
                            slot._stackText:Hide()
                        end
                    else
                        slot._stackText:Hide()
                    end
                end

                -- Keybind text preview
                if slot._keybindText then
                    SetPVFont(slot._keybindText, FONT_PATH, bd.keybindSize or 10)
                    slot._keybindText:ClearAllPoints()
                    slot._keybindText:SetPoint("TOPLEFT", slot, "TOPLEFT", bd.keybindOffsetX or 2, bd.keybindOffsetY or -2)
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
                if grow == "LEFT" then
                    addPx = startX - (iconSize + spacing)
                else
                    addPx = startX + stride * (iconSize + spacing)
                end
                addPy = startY - lastRow * (iconH + spacing)
            end
            PP.Size(addBtn, iconSize, iconH); addBtn:ClearAllPoints()
            PP.Point(addBtn, "TOPLEFT", self, "TOPLEFT", addPx, addPy)
            if addBtn._ppBorders then PP.SetBorderSize(addBtn, 1) end
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
                pvBarBg:SetPoint("TOPLEFT", startX, 0)
                pvBarBg:SetPoint("BOTTOMRIGHT", pf, "TOPLEFT", startX + spellW, -spellH)
                pvBarBg:SetColorTexture(bd.barBgR or 0, bd.barBgG or 0, bd.barBgB or 0, 0.5)
                if pvBarBg.SetSnapToPixelGrid then pvBarBg:SetSnapToPixelGrid(false); pvBarBg:SetTexelSnappingBias(0) end
                pvBarBg:Show()
            else
                pvBarBg:Hide()
            end

            -- Bar opacity affects entire preview
            self:SetAlpha(bd.barBgAlpha or 1)

            self:SetHeight(totalH + 10)

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
        return pf:GetHeight() * previewScale
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
                -- Clean up legacy verbose names for display
                if bd and bd.barType == "misc" then
                    label = label:gsub("Custom ", ""):gsub("Trinkets/Racials/Potions Bar ", "Miscellaneous "):gsub("Trinkets Bar ", "Miscellaneous "):gsub("^Trinkets ", "Miscellaneous ")
                end
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
                    if b.key ~= "cooldowns" and b.key ~= "utility" and b.key ~= "buffs" then
                        customCount = customCount + 1
                    end
                end

                for idx, b in ipairs(bars) do
                    local isCustom = (b.key ~= "cooldowns" and b.key ~= "utility" and b.key ~= "buffs")
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
                    -- Clean up legacy verbose names for display
                    if b.barType == "misc" then
                        displayName = displayName:gsub("Custom ", ""):gsub("Trinkets/Racials/Potions Bar ", "Miscellaneous "):gsub("Trinkets Bar ", "Miscellaneous "):gsub("^Trinkets ", "Miscellaneous ")
                    end
                    iLbl:SetText(displayName)

                    local iHl = item:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints(); iHl:SetColorTexture(1, 1, 1, 1)
                    iHl:SetAlpha(idx == selectedCDMBarIndex and selA or 0)

                    -- Delete button for custom bars (X icon, same as preset delete)
                    local delBtn
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
                        iLbl:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)

                        delBtn:SetScript("OnEnter", function()
                            delBtn:SetAlpha(1)
                            iLbl:SetTextColor(1, 1, 1, 1)
                            iHl:SetAlpha(hlA)
                        end)
                        delBtn:SetScript("OnLeave", function()
                            if item:IsMouseOver() then return end
                            delBtn:SetAlpha(0.75)
                            iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            iHl:SetAlpha(idx == selectedCDMBarIndex and selA or 0)
                        end)
                        delBtn:SetScript("OnClick", function()
                            menu:Hide()
                            local delName = b.name or b.key
                            local delKey = b.key
                            EllesmereUI:ShowConfirmPopup({
                                title = "Delete Bar",
                                message = "Are you sure you want to delete \"" .. delName .. "\"?",
                                confirmText = "Delete",
                                cancelText = "Cancel",
                                onConfirm = function()
                                    ns.RemoveCDMBar(delKey)
                                    if selectedCDMBarIndex > #bars then
                                        selectedCDMBarIndex = #bars
                                    end
                                    if selectedCDMBarIndex < 1 then selectedCDMBarIndex = 1 end
                                    Refresh()
                                    EllesmereUI:InvalidateContentHeaderCache()
                                    EllesmereUI:SetContentHeader(_cdmHeaderBuilder)
                                    EllesmereUI:RefreshPage(true)
                                end,
                            })
                        end)
                    end

                    item:SetScript("OnEnter", function()
                        iLbl:SetTextColor(1, 1, 1, 1)
                        iHl:SetAlpha(hlA)
                        if delBtn then delBtn:SetAlpha(1) end
                    end)
                    item:SetScript("OnLeave", function()
                        iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        iHl:SetAlpha(idx == selectedCDMBarIndex and selA or 0)
                        if delBtn then delBtn:SetAlpha(0.75) end
                    end)
                    item:SetScript("OnClick", function()
                        menu:Hide()
                        selectedCDMBarIndex = idx
                        EllesmereUI:InvalidateContentHeaderCache()
                        EllesmereUI:SetContentHeader(_cdmHeaderBuilder)
                        EllesmereUI:RefreshPage(true)
                    end)

                    mH = mH + ITEM_H
                end

                -- Divider before add-bar options
                local div = menu:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1)
                div:SetColorTexture(1, 1, 1, 0.10)
                div:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH - 4)
                div:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9

                -- "Add New ..." items (disabled if at cap)
                local atCap = customCount >= (ns.MAX_CUSTOM_BARS or 6)
                local addBarTypes = {
                    { type = "cooldowns", label = "+ Add New Cooldowns Bar" },
                    { type = "utility",   label = "+ Add New Utility Bar" },
                    { type = "buffs",     label = "+ Add New Buff Bar" },
                    { type = "misc",      label = "+ Add Miscellaneous Bar" },
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
                        addLbl:SetText(entry.label .. " (max " .. (ns.MAX_CUSTOM_BARS or 6) .. ")")
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
            _, h = W:Toggle(parent, "Use Blizzard Buff Bar", y,
                function() return DB().cdmBars.useBlizzardBuffBars == true end,
                function(v)
                    DB().cdmBars.useBlizzardBuffBars = v
                    ns.BuildAllCDMBars()
                    Refresh()
                end
            );  y = y - h

            if DB().cdmBars.useBlizzardBuffBars then
                return math.abs(y)
            end
        end

        -------------------------------------------------------------------
        --  BAR LAYOUT
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "Bar Layout", y);  y = y - h

        -- Row 1: (Sync) Visibility | Visibility Options (checkbox dropdown)
        local visRow, visH = W:DualRow(parent, y,
            { type="dropdown", text="Visibility",
              values = EllesmereUI.VIS_VALUES,
              order = EllesmereUI.VIS_ORDER,
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
                    local pp = DB(); if not pp or not pp.cdmBars then return false end
                    for _, b in ipairs(pp.cdmBars.bars) do
                        if (b.barVisibility or "always") ~= v then return false end
                    end
                    return true
                end,
                onClick = function()
                    local v = BD().barVisibility or "always"
                    local pp = DB(); if not pp or not pp.cdmBars then return end
                    for _, b in ipairs(pp.cdmBars.bars) do b.barVisibility = v end
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
                    local pp = DB(); if not pp or not pp.cdmBars then return false end
                    for _, item in ipairs(EllesmereUI.VIS_OPT_ITEMS) do
                        local k = item.key
                        local cur = bd[k] or false
                        for _, b in ipairs(pp.cdmBars.bars) do
                            if (b[k] or false) ~= cur then return false end
                        end
                    end
                    return true
                end,
                onClick = function()
                    local bd = BD()
                    local pp = DB(); if not pp or not pp.cdmBars then return end
                    for _, item in ipairs(EllesmereUI.VIS_OPT_ITEMS) do
                        local k = item.key
                        local v = bd[k] or false
                        for _, b in ipairs(pp.cdmBars.bars) do b[k] = v end
                    end
                    ns.CDMApplyVisibility(); EllesmereUI:RefreshPage()
                end,
            })
        end

        -- Row 2: Bar Opacity | Show Tooltip on Hover
        local opacityRow
        opacityRow, h = W:DualRow(parent, y,
            { type="slider", text="Bar Opacity",
              min=0, max=100, step=5,
              getValue=function() return math.floor((BD().barBgAlpha or 1) * 100 + 0.5) end,
              setValue=function(v)
                  BD().barBgAlpha = v / 100
                  ns.BuildAllCDMBars(); Refresh()
                  UpdateCDMPreview()
              end },
            { type="toggle", text="Show Tooltip on Hover",
              getValue=function() return BD().showTooltip == true end,
              setValue=function(v)
                  BD().showTooltip = v
                  ns.ApplyCDMTooltipState(BD().key)
                  Refresh()
              end });  y = y - h

        -- Sync icon on Bar Opacity (left)
        do
            local rgn = opacityRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Opacity to all Bars",
                isSynced = function()
                    local v = BD().barBgAlpha or 1
                    local pp = DB(); if not pp or not pp.cdmBars then return false end
                    for _, b in ipairs(pp.cdmBars.bars) do
                        if (b.barBgAlpha or 1) ~= v then return false end
                    end
                    return true
                end,
                onClick = function()
                    local v = BD().barBgAlpha or 1
                    local pp = DB(); if not pp or not pp.cdmBars then return end
                    for _, b in ipairs(pp.cdmBars.bars) do b.barBgAlpha = v end
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                end,
            })
        end

        -- Inline cog on Bar Opacity (left) Background toggle + color
        do
            local leftRgn = opacityRow._leftRegion
            local ctrl = leftRgn._control
            local _, bgCogShow = EllesmereUI.BuildCogPopup({
                title = "Bar Background",
                rows = {
                    { type="toggle", label="Background",
                      get=function() return BD().barBgEnabled end,
                      set=function(v)
                          BD().barBgEnabled = v
                          ns.BuildAllCDMBars(); Refresh()
                          UpdateCDMPreview(); EllesmereUI:RefreshPage()
                      end },
                    { type="color", label="Background Color",
                      get=function() return BD().barBgR or 0, BD().barBgG or 0, BD().barBgB or 0 end,
                      set=function(r, g, b)
                          BD().barBgR, BD().barBgG, BD().barBgB = r, g, b
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
                      end },
                },
            })
            MakeCogBtn(leftRgn, bgCogShow, ctrl)
        end

        -- Row 3: Number of Rows | Vertical Orientation
        _, h = W:DualRow(parent, y,
            { type="slider", text="Number of Rows",
              min=1, max=6, step=1,
              getValue=function() return BD().numRows or 1 end,
              setValue=function(v)
                  BD().numRows = v
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end },
            { type="toggle", text="Vertical Orientation",
              getValue=function() return BD().verticalOrientation end,
              setValue=function(v)
                  BD().verticalOrientation = v
                  BD().growDirection = v and "DOWN" or "RIGHT"
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end });  y = y - h

        -- Row 3: Anchored To | Anchor Position (cog: Growth + X + Y)
        local _erbLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUIResourceBars")
        local ERB_ANCHOR_KEYS = { erb_castbar = true, erb_powerbar = true, erb_classresource = true }
        local function GetAnchorChoices()
            local vals, order = { none = "None" }, { "none" }
            local p = DB()
            if p and p.cdmBars and p.cdmBars.bars then
                for _, b in ipairs(p.cdmBars.bars) do
                    if b.key ~= barKey then
                        local label = b.name or b.key
                        label = label:gsub("Custom ", ""):gsub("Trinkets/Racials/Potions", "Miscellaneous"):gsub(" Bar ", " ")
                        vals[b.key] = label
                        order[#order + 1] = b.key
                    end
                end
            end
            order[#order + 1] = "---"
            vals.mouse = "Mouse Cursor"; order[#order + 1] = "mouse"
            vals.partyframe = "Party Frame"; order[#order + 1] = "partyframe"
            vals.playerframe = "Player Frame"; order[#order + 1] = "playerframe"
            vals.erb_castbar = "Cast Bar"; order[#order + 1] = "erb_castbar"
            vals.erb_powerbar = "Power Bar"; order[#order + 1] = "erb_powerbar"
            vals.erb_classresource = "Class Resource Bar"; order[#order + 1] = "erb_classresource"
            return vals, order
        end
        local anchorVals, anchorOrder = GetAnchorChoices()
        local isPartyAnchor = function() return BD().anchorTo == "partyframe" end
        local isPlayerFrameAnchor = function() return BD().anchorTo == "playerframe" end
        local isERBAnchor = function() return ERB_ANCHOR_KEYS[BD().anchorTo] end
        local row3AnchorFrame
        row3AnchorFrame, h = W:DualRow(parent, y,
            { type="dropdown", text="Anchored To",
              values=anchorVals, order=anchorOrder,
              disabledValues=function(key)
                  if ERB_ANCHOR_KEYS[key] and not _erbLoaded then
                      return "This option requires EllesmereUI Resource Bars addon to be enabled"
                  end
                  local p = DB()
                  if p and p.cdmBars and p.cdmBars.bars and key ~= "none" and key ~= "partyframe" and key ~= "playerframe" and key ~= "mouse" and not ERB_ANCHOR_KEYS[key] then
                      local visited = { [barKey] = true }
                      local check = key
                      while check and check ~= "none" and check ~= "partyframe" and check ~= "playerframe" and not ERB_ANCHOR_KEYS[check] do
                          if visited[check] then return "This would create a circular anchor chain" end
                          visited[check] = true
                          local found = false
                          for _, b in ipairs(p.cdmBars.bars) do
                              if b.key == check then check = b.anchorTo; found = true; break end
                          end
                          if not found then break end
                      end
                  end
              end,
              getValue=function() return BD().anchorTo or "none" end,
              setValue=function(v)
                  BD().anchorTo = v
                  ns.BuildAllCDMBars(); ns.RegisterCDMUnlockElements(); Refresh()
              end },
            { type="dropdown", text="Anchor Position",
              values={ left="Left", right="Right", top="Top", bottom="Bottom" },
              order={ "left", "right", "top", "bottom" },
              disabled=function() local a = BD().anchorTo or "none"; return a == "none" end,
              disabledTooltip=EllesmereUI.DisabledTooltip("Anchored To"),
              getValue=function()
                  if isPartyAnchor() then return (BD().partyFrameSide or "LEFT"):lower() end
                  if isPlayerFrameAnchor() then return (BD().playerFrameSide or "LEFT"):lower() end
                  return BD().anchorPosition or "left"
              end,
              setValue=function(v)
                  if isPartyAnchor() then BD().partyFrameSide = v:upper()
                  elseif isPlayerFrameAnchor() then BD().playerFrameSide = v:upper()
                  else BD().anchorPosition = v end
                  ns.BuildAllCDMBars(); Refresh()
              end });  y = y - h

        -- Inline cog on Anchor Position (DIRECTIONS icon) Growth + X + Y
        do
            local posRgn = row3AnchorFrame._rightRegion
            local _, posCogShow = EllesmereUI.BuildCogPopup({
                title = "Anchor Settings",
                rows = {
                    { type="dropdown", label="Growth Direction",
                      values=growValues, order=growOrder,
                      disabled=function() return (BD().anchorTo or "none") == "mouse" end,
                      disabledTooltip=EllesmereUI.DisabledTooltip("Not available for Mouse Cursor anchor"),
                      get=function() return BD().growDirection or "RIGHT" end,
                      set=function(v)
                          BD().growDirection = v
                          ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
                      end },
                    { type="toggle", label="Grow Centered",
                      disabled=function() return (BD().anchorTo or "none") == "mouse" end,
                      disabledTooltip=EllesmereUI.DisabledTooltip("Not available for Mouse Cursor anchor"),
                      get=function() return BD().growCentered ~= false end,
                      set=function(v)
                          BD().growCentered = v
                          ns.BuildAllCDMBars(); Refresh()
                      end },
                    { type="slider", label="X Offset", min=-125, max=125, step=1,
                      get=function()
                          if isPartyAnchor() then return BD().partyFrameOffsetX or 0
                          elseif isPlayerFrameAnchor() then return BD().playerFrameOffsetX or 0
                          else return BD().anchorOffsetX or 0 end
                      end,
                      set=function(v)
                          if isPartyAnchor() then BD().partyFrameOffsetX = v
                          elseif isPlayerFrameAnchor() then BD().playerFrameOffsetX = v
                          else BD().anchorOffsetX = v end
                          ns.BuildAllCDMBars(); Refresh()
                      end },
                    { type="slider", label="Y Offset", min=-125, max=125, step=1,
                      get=function()
                          if isPartyAnchor() then return BD().partyFrameOffsetY or 0
                          elseif isPlayerFrameAnchor() then return BD().playerFrameOffsetY or 0
                          else return BD().anchorOffsetY or 0 end
                      end,
                      set=function(v)
                          if isPartyAnchor() then BD().partyFrameOffsetY = v
                          elseif isPlayerFrameAnchor() then BD().playerFrameOffsetY = v
                          else BD().anchorOffsetY = v end
                          ns.BuildAllCDMBars(); Refresh()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(posRgn, posCogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local function UpdateAnchorCogState()
                if (BD().anchorTo or "none") == "none" then
                    cogBtn:SetAlpha(0.15); cogBtn:Disable()
                else
                    cogBtn:SetAlpha(0.4); cogBtn:Enable()
                end
            end
            cogBtn:SetScript("OnEnter", function(self)
                if (BD().anchorTo or "none") ~= "none" then self:SetAlpha(0.7)
                else EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Anchored To")) end
            end)
            cogBtn:SetScript("OnLeave", function(self)
                UpdateAnchorCogState(); EllesmereUI.HideWidgetTooltip()
            end)
            cogBtn:SetScript("OnClick", function(self) posCogShow(self) end)
            UpdateAnchorCogState()
            EllesmereUI.RegisterWidgetRefresh(UpdateAnchorCogState)
        end

        -- Hide Buffs When Inactive / Out of Range + Show Keybind
        local kbRow
        if barData.barType == "buffs" or barData.key == "buffs" then
            kbRow, h = W:DualRow(parent, y,
                { type="toggle", text="Hide Buffs When Inactive",
                  getValue=function() return BD().hideBuffsWhenInactive ~= false end,
                  setValue=function(v) BD().hideBuffsWhenInactive = v; Refresh() end },
                { type="toggle", text="Show Keybind",
                  getValue=function() return BD().showKeybind == true end,
                  setValue=function(v)
                      BD().showKeybind = v
                      ns.RefreshCDMIconAppearance(BD().key); ns.ApplyCachedKeybinds(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                  end }
            );  y = y - h
        else
            kbRow, h = W:DualRow(parent, y,
                { type="toggle", text="Out of Range Overlay",
                  getValue=function() return BD().outOfRangeOverlay == true end,
                  setValue=function(v) BD().outOfRangeOverlay = v; Refresh() end,
                  tooltip="Show a red overlay on icons when the target is out of range" },
                { type="toggle", text="Show Keybind",
                  getValue=function() return BD().showKeybind == true end,
                  setValue=function(v)
                      BD().showKeybind = v
                      ns.RefreshCDMIconAppearance(BD().key); ns.ApplyCachedKeybinds(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                  end }
            );  y = y - h
        end

        -- Inline color swatch + cog on Show Keybind (right region)
        do
            local rgn = kbRow._rightRegion
            local ctrl = rgn and rgn._control

            -- Color swatch
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

            -- Cog: size + x/y offsets
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

            -- Blocking overlay when Show Keybind is off
            if kbSwatch then
                local swatchBlock = CreateFrame("Frame", nil, kbSwatch)
                swatchBlock:SetAllPoints()
                swatchBlock:SetFrameLevel(kbSwatch:GetFrameLevel() + 10)
                swatchBlock:EnableMouse(true)
                EllesmereUI.RegisterWidgetRefresh(function()
                    local on = BD().showKeybind == true
                    kbSwatch:SetAlpha(on and 1 or 0.3)
                    if on then swatchBlock:Hide() else swatchBlock:Show() end
                end)
            end
        end

        _, h = W:Spacer(parent, y, 8);  y = y - h

        -------------------------------------------------------------------
        --  ICON DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "Icon Display", y);  y = y - h

        -- Active State Animation dropdown values
        local ACTIVE_ANIM_VALUES = {
            blizzard    = "Blizzard",
            ["1"]       = "Pixel Glow",
            hideActive  = "Hide Active State",
            ["3"]       = "Action Button Glow",
            ["4"]       = "Auto-Cast Shine",
            ["5"]       = "GCD",
            ["7"]       = "Classic WoW Glow",
            none        = "No Animation",
        }
        local ACTIVE_ANIM_ORDER = { "blizzard", "1", "hideActive", "---", "3", "4", "5", "7", "none" }

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

        -- Row 1: Icon Scale | Active Animation (no sync icons on either)
        local scaleAnimRow
        scaleAnimRow, h = W:DualRow(parent, y,
            { type="slider", text="Icon Scale",
              min=16, max=80, step=1,
              getValue=function() return BD().iconSize or 36 end,
              setValue=function(v)
                  BD().iconSize = v
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end },
            { type="dropdown", text="Active Animation",
              values=ACTIVE_ANIM_VALUES, order=ACTIVE_ANIM_ORDER,
              disabled=function() return IsCustomShape() end,
              disabledTooltip=EllesmereUI.DisabledTooltip("This option is not available for custom shapes"),
              getValue=function()
                  if IsCustomShape() then return "blizzard" end
                  return BD().activeStateAnim or "blizzard"
              end,
              setValue=function(v)
                  local bd = BD()
                  local wasOff = (bd.activeStateAnim == "blizzard") or (bd.activeStateAnim == "none") or (bd.activeStateAnim == "hideActive") or not bd.activeStateAnim
                  local turningOn = wasOff and tonumber(v) ~= nil
                  if turningOn then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Active State Animation",
                          message     = "Custom active state animations may cause a slight loss in performance efficiency. Do you want to enable it?",
                          confirmText = "Enable",
                          cancelText  = "Cancel",
                          onConfirm   = function()
                              bd.activeStateAnim = v; ns.BuildAllCDMBars()
                              if _cdmActivePreviewOn and _cdmPreview then StopActiveStatePreview(); StartActiveStatePreview() end
                              Refresh(); EllesmereUI:RefreshPage()
                          end,
                          onCancel = function() if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end end,
                      })
                      return
                  end
                  bd.activeStateAnim = v; ns.BuildAllCDMBars()
                  if _cdmActivePreviewOn and _cdmPreview then StopActiveStatePreview(); StartActiveStatePreview() end
                  Refresh()
              end });  y = y - h

        -- Inline active anim color swatches + eye on Active Animation (right of row 1)
        -- Order right-to-left: [class swatch] [custom swatch] [eye]
        do
            local rightRgn = scaleAnimRow._rightRegion
            local ctrl = rightRgn._control

            -- Class color swatch (rightmost, single-click activates class color mode)
            local classSwatch, updateClassSwatch = EllesmereUI.BuildColorSwatch(
                rightRgn, scaleAnimRow:GetFrameLevel() + 3,
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
                BD().activeAnimClassColor = true; ns.BuildAllCDMBars()
                if _cdmActivePreviewOn and _cdmPreview then StopActiveStatePreview(); StartActiveStatePreview() end
                Refresh(); EllesmereUI:RefreshPage()
            end)
            classSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Colored")
            end)
            classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Custom color swatch (left of class swatch, two-click: first activates custom mode)
            local animSwatch, updateAnimSwatch = EllesmereUI.BuildColorSwatch(
                rightRgn, scaleAnimRow:GetFrameLevel() + 3,
                function() return BD().activeAnimR or 1.0, BD().activeAnimG or 0.85, BD().activeAnimB or 0.0 end,
                function(r, g, b)
                    BD().activeAnimR = r; BD().activeAnimG = g; BD().activeAnimB = b
                    ns.BuildAllCDMBars()
                    if _cdmActivePreviewOn and _cdmPreview then StopActiveStatePreview(); StartActiveStatePreview() end
                    Refresh()
                end,
                false, 20)
            PP.Point(animSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
            animSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(animSwatch, "Custom Colored")
            end)
            animSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Block overlay on custom swatch -- clicking while class colored deactivates class color mode
            local animSwatchBlock = CreateFrame("Button", nil, animSwatch)
            animSwatchBlock:SetAllPoints(); animSwatchBlock:SetFrameLevel(animSwatch:GetFrameLevel() + 10)
            animSwatchBlock:EnableMouse(true)
            animSwatchBlock:SetScript("OnClick", function()
                local a = BD().activeStateAnim or "blizzard"
                local noAnim = a == "none" or a == "hideActive" or IsCustomShape()
                if not noAnim and BD().activeAnimClassColor then
                    BD().activeAnimClassColor = false; ns.BuildAllCDMBars()
                    if _cdmActivePreviewOn and _cdmPreview then StopActiveStatePreview(); StartActiveStatePreview() end
                    Refresh(); EllesmereUI:RefreshPage()
                end
            end)
            animSwatchBlock:SetScript("OnEnter", function()
                local a = BD().activeStateAnim or "blizzard"
                local reason
                if a == "none" or a == "hideActive" or IsCustomShape() then
                    reason = "This option requires an active state selection"
                else
                    reason = "Color is controlled by class color"
                end
                EllesmereUI.ShowWidgetTooltip(animSwatch, EllesmereUI.DisabledTooltip(reason))
            end)
            animSwatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Eye preview button (leftmost, left of custom swatch)
            local EYE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
            local EYE_VIS   = EYE_MEDIA .. "eui-visible.png"
            local EYE_INVIS = EYE_MEDIA .. "eui-invisible.png"
            local eyeBtn = CreateFrame("Button", nil, rightRgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", animSwatch, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshEye()
                eyeTex:SetTexture(_cdmActivePreviewOn and EYE_INVIS or EYE_VIS)
            end
            RefreshEye()
            eyeBtn:SetScript("OnClick", function()
                _cdmActivePreviewOn = not _cdmActivePreviewOn; RefreshEye()
                if _cdmActivePreviewOn then StartActiveStatePreview() else StopActiveStatePreview() end
            end)
            eyeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            eyeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            local eyeBlock = CreateFrame("Frame", nil, eyeBtn)
            eyeBlock:SetAllPoints(); eyeBlock:SetFrameLevel(eyeBtn:GetFrameLevel() + 10)
            eyeBlock:EnableMouse(true)
            eyeBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(eyeBtn, EllesmereUI.DisabledTooltip("This option requires an active state selection"))
            end)
            eyeBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function UpdateAnimState()
                local a = BD().activeStateAnim or "blizzard"
                local noAnim = a == "none" or a == "hideActive" or IsCustomShape()
                RefreshEye()
                if noAnim then eyeBtn:SetAlpha(0.15); eyeBlock:Show()
                else eyeBtn:SetAlpha(0.4); eyeBlock:Hide() end
                local isClassColored = BD().activeAnimClassColor
                -- Custom swatch: dim when class colored or no anim
                local customDis = isClassColored or noAnim
                if customDis then animSwatch:SetAlpha(0.3); animSwatchBlock:Show()
                else animSwatch:SetAlpha(1); animSwatchBlock:Hide() end
                -- Class swatch: bright when class colored, dim when custom or no anim
                classSwatch:SetAlpha((isClassColored and not noAnim) and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateAnimSwatch(); updateClassSwatch(); UpdateAnimState() end)
            UpdateAnimState()
        end

        -- Row 2: (Sync) Custom Icon Shape | (Sync) Icon Spacing
        local shapeRow
        shapeRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Custom Icon Shape",
              values=SHAPE_VALUES, order=SHAPE_ORDER,
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
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end },
            { type="slider", text="Icon Spacing",
              min=-10, max=20, step=1,
              getValue=function() return BD().spacing or 2 end,
              setValue=function(v)
                  BD().spacing = v
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize()
              end });  y = y - h

        -- Sync icons on Shape and Spacing
        do
            EllesmereUI.BuildSyncIcon({
                region  = shapeRow._leftRegion,
                tooltip = "Apply Icon Shape to all Bars",
                isSynced = function()
                    local bd = BD()
                    local v = bd.iconShape or "none"
                    local zoom = bd.iconZoom or 0.08
                    local pp = DB(); if not pp or not pp.cdmBars then return false end
                    for _, b in ipairs(pp.cdmBars.bars) do
                        if (b.iconShape or "none") ~= v or (b.iconZoom or 0.08) ~= zoom then return false end
                    end
                    return true
                end,
                onClick = function()
                    local bd = BD()
                    local v = bd.iconShape or "none"
                    local zoom = bd.iconZoom or 0.08
                    local pp = DB(); if not pp or not pp.cdmBars then return end
                    for _, b in ipairs(pp.cdmBars.bars) do
                        b.iconShape = v; b.iconZoom = zoom
                        local isCS = (v ~= "none" and v ~= "cropped")
                        if isCS then b.borderThickness = "strong"; b.borderSize = BORDER_SIZES["strong"]
                        else b.borderThickness = "thin"; b.borderSize = BORDER_SIZES["thin"] end
                    end
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize(); EllesmereUI:RefreshPage()
                end,
            })
            EllesmereUI.BuildSyncIcon({
                region  = shapeRow._rightRegion,
                tooltip = "Apply Icon Spacing to all Bars",
                isSynced = function()
                    local v = BD().spacing or 2
                    local pp = DB(); if not pp or not pp.cdmBars then return false end
                    for _, b in ipairs(pp.cdmBars.bars) do
                        if (b.spacing or 2) ~= v then return false end
                    end
                    return true
                end,
                onClick = function()
                    local v = BD().spacing or 2
                    local pp = DB(); if not pp or not pp.cdmBars then return end
                    for _, b in ipairs(pp.cdmBars.bars) do b.spacing = v end
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreviewAndResize(); EllesmereUI:RefreshPage()
                end,
            })
        end

        -- Row 3: (Sync) Border Size (swatch + cog) | (Sync) Icon Zoom
        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Size",
              values=BORDER_LABELS, order=BORDER_ORDER,
              disabled=function() return IsCustomShape() end,
              disabledTooltip="This option is not available for custom shapes",
              getValue=function() return BD().borderThickness or "thin" end,
              setValue=function(v)
                  BD().borderThickness = v; BD().borderSize = BORDER_SIZES[v] or 1
                  ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
              end },
            { type="slider", text="Icon Zoom",
              min=0, max=0.20, step=0.01,
              getValue=function() return BD().iconZoom or 0.08 end,
              setValue=function(v)
                  BD().iconZoom = v
                  ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
              end });  y = y - h

        -- Sync icons on Border Size and Icon Zoom
        do
            EllesmereUI.BuildSyncIcon({
                region  = borderRow._leftRegion,
                tooltip = "Apply Border Size to all Bars",
                isSynced = function()
                    local bd = BD()
                    local v = bd.borderThickness or "thin"
                    local cc = bd.borderClassColor
                    local pp = DB(); if not pp or not pp.cdmBars then return false end
                    for _, b in ipairs(pp.cdmBars.bars) do
                        if (b.borderThickness or "thin") ~= v or b.borderClassColor ~= cc then return false end
                    end
                    return true
                end,
                onClick = function()
                    local bd = BD()
                    local v = bd.borderThickness or "thin"
                    local sz = bd.borderSize or 1
                    local cc = bd.borderClassColor
                    local pp = DB(); if not pp or not pp.cdmBars then return end
                    for _, b in ipairs(pp.cdmBars.bars) do
                        b.borderThickness = v; b.borderSize = sz
                        b.borderClassColor = cc
                    end
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                end,
            })
            EllesmereUI.BuildSyncIcon({
                region  = borderRow._rightRegion,
                tooltip = "Apply Icon Zoom to all Bars",
                isSynced = function()
                    local v = BD().iconZoom or 0.08
                    local pp = DB(); if not pp or not pp.cdmBars then return false end
                    for _, b in ipairs(pp.cdmBars.bars) do
                        if (b.iconZoom or 0.08) ~= v then return false end
                    end
                    return true
                end,
                onClick = function()
                    local v = BD().iconZoom or 0.08
                    local pp = DB(); if not pp or not pp.cdmBars then return end
                    for _, b in ipairs(pp.cdmBars.bars) do b.iconZoom = v end
                    ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview(); EllesmereUI:RefreshPage()
                end,
            })
        end

        -- Inline border color swatches on Border Size (left of row 3)
        -- Order right-to-left: [class swatch] [custom swatch]
        do
            local leftRgn = borderRow._leftRegion
            local ctrl = leftRgn._control

            -- Class color swatch (rightmost, single-click activates class color mode)
            local classBorderSwatch, updateClassBorderSwatch = EllesmereUI.BuildColorSwatch(
                leftRgn, borderRow:GetFrameLevel() + 3,
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

            -- Custom color swatch (left of class swatch, two-click: first activates custom mode)
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                leftRgn, borderRow:GetFrameLevel() + 3,
                function() return BD().borderR or 0, BD().borderG or 0, BD().borderB or 0 end,
                function(r, g, b)
                    BD().borderR, BD().borderG, BD().borderB = r, g, b
                    ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                end,
                false, 20)
            PP.Point(swatch, "RIGHT", classBorderSwatch, "LEFT", -8, 0)
            swatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, "Custom Colored")
            end)
            swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Block overlay on custom swatch -- clicking while class colored deactivates class color mode
            local swatchBlock = CreateFrame("Button", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnClick", function()
                if BD().borderClassColor then
                    BD().borderClassColor = false
                    ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                    EllesmereUI:RefreshPage()
                end
            end)
            swatchBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Border color is controlled by class color"))
            end)
            swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function UpdateBorderSwatchState()
                local isClassColored = BD().borderClassColor
                if isClassColored then
                    swatch:SetAlpha(0.3); swatchBlock:Show()
                else
                    swatch:SetAlpha(1); swatchBlock:Hide()
                end
                classBorderSwatch:SetAlpha(isClassColored and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); updateClassBorderSwatch(); UpdateBorderSwatchState() end)
            UpdateBorderSwatchState()
        end

        -- Row 4: Show Duration (colorpicker + resize cog) | Stack Count (colorpicker + resize cog)
        local durationRow
        durationRow, h = W:DualRow(parent, y,
            { type="colorpicker", text="Show Duration",
              getValue=function() return BD().cooldownTextR or 1, BD().cooldownTextG or 1, BD().cooldownTextB or 1 end,
              setValue=function(r, g, b)
                  BD().cooldownTextR, BD().cooldownTextG, BD().cooldownTextB = r, g, b
                  ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
              end },
            { type="colorpicker", text="Stack Count",
              getValue=function() return BD().stackCountR or 1, BD().stackCountG or 1, BD().stackCountB or 1 end,
              setValue=function(r, g, b)
                  BD().stackCountR, BD().stackCountG, BD().stackCountB = r, g, b
                  ns.RefreshCDMIconAppearance(BD().key); ns.BuildAllCDMBars(); Refresh(); UpdateCDMPreview()
              end }
        );  y = y - h

        -- Show Duration: resize cog (left)
        do
            local leftRgn = durationRow._leftRegion
            local _, fontCogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Text Settings",
                rows = {
                    { type="slider", label="Font Size", min=6, max=24, step=1,
                      get=function() return BD().cooldownFontSize or 15 end,
                      set=function(v)
                          BD().cooldownFontSize = v
                          ns.RefreshCDMIconAppearance(BD().key); Refresh()
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
            MakeCogBtn(leftRgn, fontCogShow, nil, EllesmereUI.RESIZE_ICON)
        end

        -- Stack Count: resize cog (right)
        do
            local rightRgn = durationRow._rightRegion
            local _, scCogShow = EllesmereUI.BuildCogPopup({
                title = "Stack Count Settings",
                rows = {
                    { type="slider", label="Size", min=6, max=24, step=1,
                      get=function() return BD().stackCountSize or 11 end,
                      set=function(v)
                          BD().stackCountSize = v
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
            MakeCogBtn(rightRgn, scCogShow, nil, EllesmereUI.RESIZE_ICON)
        end


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
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUICooldownManager", {
        title       = "Cooldown Manager",
        description = "CDM bar customization, action bar glows, and buff bars.",
        pages       = { PAGE_CDM_BARS, PAGE_BAR_GLOWS, PAGE_BUFF_BARS },
        disabledPages = {},
        disabledPageTooltips = {},
        buildPage   = function(pageName, parent, yOffset)
            -- Clear buff bar placeholders when switching away
            if pageName ~= PAGE_BUFF_BARS and ns._tbbPlaceholderMode then
                ns._tbbPlaceholderMode = false
                for _, ph in ipairs(_tbbPlaceholders) do if ph then ph:Hide() end end
            end
            if pageName == PAGE_BAR_GLOWS then
                return BuildBarGlowsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_BUFF_BARS then
                return BuildBuffBarsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_CDM_BARS then
                return BuildCDMBarsPage(pageName, parent, yOffset)
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
            -- Clear buff bar placeholders when switching away
            if pageName ~= PAGE_BUFF_BARS and ns._tbbPlaceholderMode then
                ns._tbbPlaceholderMode = false
                for _, ph in ipairs(_tbbPlaceholders) do if ph then ph:Hide() end end
            end
            -- Re-show placeholders when returning to Buff Bars from cache
            if pageName == PAGE_BUFF_BARS then
                UpdateTBBPlaceholder()
            end
            if pageName == PAGE_CDM_BARS then
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
                    _G._ECME_AceDB.sv._capturedOnce = nil
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
