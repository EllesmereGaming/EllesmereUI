-------------------------------------------------------------------------------
--  EllesmereUICooldownManager_Options.lua
--  Registers CDM Effects module with EllesmereUI
--  Tab 1: CDM Bars  |  Tab 2: Bar Glows  |  Tab 3: Buff Bars  |  Tab 4: Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_BAR_GLOWS = "Bar Glows"
local PAGE_BUFF_BARS = "Buff Bars"
local PAGE_CDM_BARS  = "CDM Bars"
local PAGE_UNLOCK    = "Unlock Mode"

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
        fs:SetFont(font, size, "OUTLINE")
        fs:SetShadowOffset(0, 0)
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

        -- Get tracked and untracked buff spells
        local tracked, untracked = ns.GetAllCDMBuffSpells()
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

            -- Checkbox
            local cbSize = 14
            local cb = item:CreateTexture(nil, "ARTWORK")
            cb:SetSize(cbSize, cbSize)
            cb:SetPoint("LEFT", 8, 0)
            local isChecked = assignedSet[sp.spellID] or false
            if isChecked then
                cb:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1)
            else
                cb:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            end
            -- Checkbox border
            local cbPx = PP.Scale(1)
            for edge = 1, 4 do
                local t = item:CreateTexture(nil, "OVERLAY", nil, 7)
                t:SetColorTexture(0.4, 0.4, 0.4, 0.6)
                if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                if edge == 1 then t:SetPoint("TOPLEFT", cb, "TOPLEFT"); t:SetPoint("TOPRIGHT", cb, "TOPRIGHT"); t:SetHeight(cbPx)
                elseif edge == 2 then t:SetPoint("BOTTOMLEFT", cb, "BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT"); t:SetHeight(cbPx)
                elseif edge == 3 then t:SetPoint("TOPLEFT", cb, "TOPLEFT"); t:SetPoint("BOTTOMLEFT", cb, "BOTTOMLEFT"); t:SetWidth(cbPx)
                else t:SetPoint("TOPRIGHT", cb, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT"); t:SetWidth(cbPx)
                end
            end

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
                    cb:SetColorTexture(0.2, 0.2, 0.2, 0.8)
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
                    cb:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                end
                bg.assignments[assignKey] = buffList
                Refresh()
                if onChanged then onChanged() end
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

        local closer = CreateFrame("Button", nil, UIParent)
        closer:SetFrameStrata("FULLSCREEN_DIALOG")
        closer:SetFrameLevel(menu:GetFrameLevel() - 1)
        closer:SetAllPoints(UIParent)
        closer:SetScript("OnClick", function() menu:Hide(); closer:Hide() end)
        menu:HookScript("OnHide", function() closer:Hide() end)
        closer:Show()

        menu:Show()
        _bgSpellPickerMenu = menu
    end

    ---------------------------------------------------------------------------
    --  Bar Glows: BuildBarGlowsPage (v2)
    ---------------------------------------------------------------------------
    local function BuildBarGlowsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        local bg = ns.GetBarGlows()
        local curBar = bg.selectedBar or 1
        local curBtn = bg.selectedButton  -- nil = no selection

        local ACCENT = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }

        -------------------------------------------------------------------
        --  Content Header: Live Action Bar Preview (replica of BuildLivePreview)
        -------------------------------------------------------------------
        EllesmereUI:ClearContentHeader()

        -- Stop any lingering preview glows
        for idx, ov in pairs(_bgPreviewGlowOverlays) do
            ns.StopNativeGlow(ov)
            _bgPreviewGlowActive[idx] = false
        end

        local ok, EAB_ADDON = pcall(EllesmereUI.Lite.GetAddon, "EllesmereUIActionBars")
        if not ok then EAB_ADDON = nil end
        local barKeys = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8" }
        local barKey = barKeys[curBar] or "MainBar"

        -- Read bar settings from EAB addon
        local barSettings, barInfo
        if EAB_ADDON and EAB_ADDON.db and EAB_ADDON.db.profile then
            barSettings = EAB_ADDON.db.profile.bars[barKey]
        end
        -- Fallback bar info
        barInfo = { buttonPrefix = BAR_BUTTON_PREFIXES[curBar], count = 12 }

        local headerBuilder = function(headerFrame, width)
            local NUM_BUTTONS = 12
            local prefix = BAR_BUTTON_PREFIXES[curBar] or "ActionButton"

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
            local headerH = scaledBtnH + 20  -- 10px top + bottom padding
            local startX = math.max(0, math.floor((width - gridW) / 2))
            local startY = -10

            -- Disable WoW's automatic pixel snapping on a texture
            local function UnsnapTex(tex)
                if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0) end
            end

            for i = 1, NUM_BUTTONS do
                if i > numVisible then break end

                local xOff = startX + (i - 1) * (scaledBtnW + scaledPad)
                local isSelected = (curBtn == i)

                local bf = CreateFrame("Button", nil, headerFrame)
                bf:SetSize(scaledBtnW, scaledBtnH)
                bf:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", xOff, startY)
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

                -- Selection / hover highlight
                if isSelected then
                    for e = 1, 4 do
                        local t = bf:CreateTexture(nil, "OVERLAY", nil, 8)
                        t:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                        if e == 1 then t:SetHeight(2); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT")
                        elseif e == 2 then t:SetHeight(2); t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT")
                        elseif e == 3 then t:SetWidth(2); t:SetPoint("TOPLEFT", 0, -2); t:SetPoint("BOTTOMLEFT", 0, 2)
                        else t:SetWidth(2); t:SetPoint("TOPRIGHT", 0, -2); t:SetPoint("BOTTOMRIGHT", 0, 2) end
                    end
                else
                    -- Hover highlight: use a child container so PP.CreateBorder
                    -- doesn't conflict with the existing border on bf.
                    local eg = EllesmereUI.ELLESMERE_GREEN
                    local hlCont = CreateFrame("Frame", nil, bf)
                    hlCont:SetAllPoints()
                    hlCont:SetFrameLevel(bf:GetFrameLevel() + 1)
                    local PP = EllesmereUI and EllesmereUI.PP
                    local brd = PP and PP.CreateBorder(hlCont, eg.r, eg.g, eg.b, 1, 2, "OVERLAY", 7)
                    if brd then brd:Hide() end
                    bf:SetScript("OnEnter", function() if brd then brd:Show() end end)
                    bf:SetScript("OnLeave", function() if brd then brd:Hide() end end)
                end

                -- Buff assignment indicator dots (small colored dots below button for each assigned buff)
                local assignKey = curBar .. "_" .. i
                local assigns = bg.assignments[assignKey]
                if assigns and #assigns > 0 then
                    local dotSize = 4
                    local dotGap = 2
                    local totalDotsW = #assigns * dotSize + (#assigns - 1) * dotGap
                    local dotStartX = (scaledBtnW - totalDotsW) / 2
                    for di, aEntry in ipairs(assigns) do
                        local dot = bf:CreateTexture(nil, "OVERLAY", nil, 9)
                        dot:SetSize(dotSize, dotSize)
                        dot:SetPoint("BOTTOM", bf, "BOTTOM", dotStartX + (di - 1) * (dotSize + dotGap) + dotSize / 2 - scaledBtnW / 2, 2)
                        if aEntry.classColor then
                            local _, ct = UnitClass("player")
                            if ct then
                                local cc = RAID_CLASS_COLORS[ct]
                                if cc then dot:SetColorTexture(cc.r, cc.g, cc.b, 1) end
                            else
                                dot:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                            end
                        elseif aEntry.glowColor then
                            dot:SetColorTexture(aEntry.glowColor.r, aEntry.glowColor.g, aEntry.glowColor.b, 1)
                        else
                            dot:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1)
                        end
                    end
                end

                -- Click handlers
                bf:SetScript("OnClick", function(self, button)
                    if button == "LeftButton" then
                        bg.selectedButton = i
                        EllesmereUI:RefreshPage()
                    elseif button == "RightButton" then
                        ShowBarGlowSpellPicker(self, curBar, i, function()
                            EllesmereUI:RefreshPage()
                        end)
                    end
                end)
            end

            return headerH
        end

        EllesmereUI:SetContentHeader(headerBuilder)

        -------------------------------------------------------------------
        --  Scrollable content area
        -------------------------------------------------------------------

        -- Action Bar selector dropdown
        _, h = W:Dropdown(parent, "Action Bar", y,
            BG_ACTION_BAR_VALUES,
            function() return bg.selectedBar or 1 end,
            function(v)
                bg.selectedBar = tonumber(v) or 1
                bg.selectedButton = nil  -- deselect button on bar change
                EllesmereUI:RefreshPage()
            end,
            BG_ACTION_BAR_ORDER
        );  y = y - h

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
            hintText:SetText("Left click a button to edit an existing glow, right click to add a new glow")
            y = y - 40
        else
            -- Button selected: show assignments
            local assignKey = curBar .. "_" .. curBtn
            local buffList = bg.assignments[assignKey] or {}

            _, h = W:SectionHeader(parent, "ACTION BAR " .. curBar .. " BUTTON " .. curBtn .. " BUFF ASSIGNMENTS", y);  y = y - h

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
                -- Build dropdown values for assigned buffs
                local buffLabels = {}
                local buffOrder = {}
                for idx, entry in ipairs(buffList) do
                    local name = "Unknown"
                    if entry.spellID and entry.spellID > 0 then
                        name = C_Spell.GetSpellName(entry.spellID) or ("Spell " .. entry.spellID)
                    end
                    buffLabels[idx] = name
                    buffOrder[#buffOrder + 1] = idx
                end

                local selectedAssign = bg.selectedAssignment or 1
                if selectedAssign > #buffList then selectedAssign = 1 end

                _, h = W:Dropdown(parent, "Assigned Buff", y,
                    buffLabels,
                    function() return selectedAssign end,
                    function(v)
                        bg.selectedAssignment = tonumber(v) or 1
                        EllesmereUI:RefreshPage()
                    end,
                    buffOrder
                );  y = y - h

                _, h = W:Spacer(parent, y, 6);  y = y - h

                -- Per-buff settings
                local entry = buffList[selectedAssign]
                if entry then
                    local hasCustomShape = BarHasCustomShape(curBar)

                    -- Row 1: Glow Type | Class Colored Glow
                    local glowLabels, glowOrder = GetGlowStyleValues()
                    local glowRow
                    glowRow, h = W:DualRow(parent, y,
                        { type = "dropdown", text = "Glow Type",
                          values = glowLabels, order = glowOrder,
                          disabled = function() return hasCustomShape end,
                          disabledTooltip = "Custom shapes always use Shape Glow. Change your bar shape to None or Cropped to pick a different glow.",
                          getValue = function()
                              if hasCustomShape then return 2 end  -- Shape Glow
                              return entry.glowStyle or 1
                          end,
                          setValue = function(v)
                              entry.glowStyle = tonumber(v) or 1
                              Refresh()
                          end,
                        },
                        { type = "toggle", text = "Class Colored Glow",
                          getValue = function() return entry.classColor end,
                          setValue = function(v)
                              entry.classColor = v
                              Refresh()
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
                            local pvKey = assignKey .. "_" .. selectedAssign
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
                                local prefix = BAR_BUTTON_PREFIXES[curBar]
                                local realBtn = prefix and _G[prefix .. curBtn]
                                if not realBtn then return end
                                if not _bgPreviewGlowOverlays[pvKey] then
                                    local ov = CreateFrame("Frame", nil, realBtn)
                                    ov:SetAllPoints(realBtn)
                                    ov:SetFrameLevel(realBtn:GetFrameLevel() + 10)
                                    _bgPreviewGlowOverlays[pvKey] = ov
                                end
                                local ov = _bgPreviewGlowOverlays[pvKey]
                                if _bgPreviewGlowActive[pvKey] then
                                    ns.StopNativeGlow(ov)
                                    _bgPreviewGlowActive[pvKey] = false
                                else
                                    local style = hasCustomShape and 2 or (entry.glowStyle or 1)
                                    local cr, cg, cb = 1, 0.82, 0.1
                                    if entry.classColor then
                                        local _, ct = UnitClass("player")
                                        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
                                    elseif entry.glowColor then
                                        cr, cg, cb = entry.glowColor.r, entry.glowColor.g, entry.glowColor.b
                                    end
                                    ns.StartNativeGlow(ov, style, cr, cg, cb)
                                    _bgPreviewGlowActive[pvKey] = true
                                end
                                RefreshEye()
                            end)
                            eyeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                            eyeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                        end
                    end

                    -- Inline color swatch for glow color (on right region of row 1)
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
                                    EllesmereUI:RefreshPage()
                                end,
                                false, 20)
                            PP.Point(glowSwatch, "RIGHT", toggle, "LEFT", -8, 0)
                        end
                    end

                    -- Row 2: Glow When (mode)
                    _, h = W:Dropdown(parent, "Glow When", y,
                        BG_MODE_VALUES,
                        function() return entry.mode or "ACTIVE" end,
                        function(v)
                            entry.mode = v
                            Refresh()
                        end,
                        BG_MODE_ORDER
                    );  y = y - h

                    _, h = W:Spacer(parent, y, 10);  y = y - h

                    -- Remove this buff assignment button
                    _, h = W:WideButton(parent, "Remove This Buff", y,
                        function()
                            EllesmereUI:ShowConfirmPopup({
                                title = "Remove Buff Assignment",
                                message = "Remove this buff from this button's glow assignments?",
                                confirmText = "Remove",
                                cancelText = "Cancel",
                                onConfirm = function()
                                    table.remove(buffList, selectedAssign)
                                    if #buffList == 0 then
                                        bg.assignments[assignKey] = nil
                                    end
                                    bg.selectedAssignment = 1
                                    Refresh()
                                    EllesmereUI:RefreshPage()
                                end,
                            })
                        end
                    );  y = y - h
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

    -- Buff spell picker for tracked buff bars (reuses CDM buff spell list)
    local _tbbSpellPickerMenu
    local function ShowTBBSpellPicker(anchorFrame, barCfg, onChanged)
        if _tbbSpellPickerMenu then _tbbSpellPickerMenu:Hide() end

        local tracked, untracked = ns.GetAllCDMBuffSpells()
        if #tracked == 0 and #untracked == 0 then return end

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

        local function MakeSpellItem(sp, isUntracked)
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

            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            lbl:SetPoint("LEFT", 8, 0)
            lbl:SetPoint("RIGHT", ico, "LEFT", -4, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false); lbl:SetMaxLines(1)
            lbl:SetText(sp.name)
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local hl = item:CreateTexture(nil, "ARTWORK", nil, -1)
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)

            item:SetScript("OnEnter", function()
                lbl:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, hlA)
            end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); hl:SetColorTexture(1, 1, 1, 0)
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
                barCfg.spellID = sp.spellID
                barCfg.name = sp.name
                Refresh()
                ns.BuildTrackedBuffBars()
                if onChanged then onChanged() end
            end)
            mH = mH + ITEM_H
        end

        for _, sp in ipairs(tracked) do MakeSpellItem(sp, false) end
        if #tracked > 0 and #untracked > 0 then
            local div = inner:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1); div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
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
        local closer = CreateFrame("Button", nil, UIParent)
        closer:SetFrameStrata("FULLSCREEN_DIALOG")
        closer:SetFrameLevel(menu:GetFrameLevel() - 1)
        closer:SetAllPoints(UIParent)
        closer:SetScript("OnClick", function() menu:Hide(); closer:Hide() end)
        menu:HookScript("OnHide", function() closer:Hide() end)
        closer:Show()
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
                    if bd.spellID and bd.spellID > 0 then
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
                    if b.spellID and b.spellID > 0 then
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
                local closer = CreateFrame("Button", nil, UIParent)
                closer:SetFrameStrata("FULLSCREEN_DIALOG")
                closer:SetFrameLevel(menu:GetFrameLevel() - 1)
                closer:SetAllPoints(UIParent)
                closer:SetScript("OnClick", function() menu:Hide(); closer:Hide() end)
                menu:HookScript("OnHide", function() closer:Hide() end)
                closer:Show()
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

            -- Bar preview (uses bar's actual dimensions)
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
                local texPath = ns.TBB_TEXTURES and ns.TBB_TEXTURES[bd.texture or "none"]
                if texPath then pvBar:SetStatusBarTexture(texPath)
                else pvBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8") end
                pvBar:SetMinMaxValues(0, 1)
                pvBar:SetValue(0.65)
                local pvFillR, pvFillG, pvFillB, pvFillA = bd.fillR or 0.05, bd.fillG or 0.82, bd.fillB or 0.62, bd.fillA or 1
                pvBar:GetStatusBarTexture():SetVertexColor(pvFillR, pvFillG, pvFillB, pvFillA)

                local pvBg = pvBar:CreateTexture(nil, "BACKGROUND")
                pvBg:SetAllPoints(); pvBg:SetColorTexture(bd.bgR or 0, bd.bgG or 0, bd.bgB or 0, bd.bgA or 0.4)

                if bd.gradientEnabled and pvBar._gradient == nil then
                    local grad = pvBar:CreateTexture(nil, "ARTWORK", nil, 1)
                    grad:SetAllPoints(pvBar:GetStatusBarTexture())
                    grad:SetBlendMode("BLEND")
                    local dir = bd.gradientDir or "HORIZONTAL"
                    if grad.SetGradient then
                        grad:SetGradient(dir,
                            CreateColor(pvFillR, pvFillG, pvFillB, pvFillA),
                            CreateColor(bd.gradientR or 0.20, bd.gradientG or 0.20, bd.gradientB or 0.80, bd.gradientA or 1))
                    end
                    grad:Show()
                end

                if bd.showSpark then
                    local spark = pvBar:CreateTexture(nil, "OVERLAY", nil, 2)
                    spark:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\cast_spark.tga")
                    spark:SetBlendMode("ADD")
                    spark:SetSize(8, bd.height or 24)
                    spark:SetPoint("CENTER", pvBar:GetStatusBarTexture(), "RIGHT", 0, 0)
                end

                if bd.showTimer then
                    local timer = pvBar:CreateFontString(nil, "OVERLAY")
                    SetPVFont(timer, FONT_PATH, bd.timerSize or 11)
                    timer:SetTextColor(1, 1, 1, 0.9)
                    timer:SetPoint("RIGHT", pvBar, "RIGHT", -8 + (bd.timerX or 0), bd.timerY or 0)
                    timer:SetText("3.2")
                end

                -- Spell name
                if bd.showName ~= false then
                    local nameFs = pvBar:CreateFontString(nil, "OVERLAY")
                    SetPVFont(nameFs, FONT_PATH, bd.nameSize or 11)
                    nameFs:SetTextColor(1, 1, 1, 0.9)
                    nameFs:SetPoint("LEFT", pvBar, "LEFT", 8 + (bd.nameX or 0), bd.nameY or 0)
                    if bd.spellID and bd.spellID > 0 then
                        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(bd.spellID)
                        nameFs:SetText(info and info.name or bd.name or "")
                    else
                        nameFs:ClearAllPoints()
                        nameFs:SetPoint("CENTER", pvBar, "CENTER", 0, 0)
                        nameFs:SetJustifyH("CENTER")
                        nameFs:SetText("Click to assign a buff")
                        nameFs:SetTextColor(1, 1, 1, 1)
                    end
                else
                    -- No name text, but still show hint if no spell assigned
                    if not bd.spellID or bd.spellID == 0 then
                        local nameFs = pvBar:CreateFontString(nil, "OVERLAY")
                        nameFs:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        nameFs:SetTextColor(1, 1, 1, 1)
                        nameFs:SetPoint("CENTER", pvBar, "CENTER", 0, 0)
                        nameFs:SetJustifyH("CENTER")
                        nameFs:SetText("Click to assign a buff")
                    end
                end

                pvBar:SetAlpha(bd.opacity or 1.0)

                -- Icon preview
                local pvIconMode = bd.iconDisplay or "none"
                _tbbPvIcon = nil
                local pvIconFrame  -- reference for hover highlight extension
                if pvIconMode ~= "none" and bd.spellID and bd.spellID > 0 then
                    local pvIcon = pvFrame:CreateTexture(nil, "ARTWORK")
                    local iSize = bd.iconSize or PREVIEW_H
                    pvIcon:SetSize(iSize, iSize)
                    pvIcon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
                    local ix, iy = bd.iconX or 0, bd.iconY or 0
                    if pvIconMode == "left" then
                        pvIcon:SetPoint("RIGHT", pvBar, "LEFT", ix, iy)
                    elseif pvIconMode == "right" then
                        pvIcon:SetPoint("LEFT", pvBar, "RIGHT", ix, iy)
                    end
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(bd.spellID)
                    pvIcon:SetTexture(spInfo and spInfo.iconID or 134400)
                    _tbbPvIcon = pvIcon

                    -- Icon border in preview
                    local bSz = bd.iconBorderSize or 0
                    if bSz > 0 then
                        local pvIconBorder = CreateFrame("Frame", nil, pvFrame)
                        pvIconBorder:SetFrameLevel(pvFrame:GetFrameLevel() + 3)
                        pvIconBorder:SetAllPoints(pvIcon)
                        local PP = EllesmereUI and EllesmereUI.PP
                        if PP then PP.CreateBorder(pvIconBorder, bd.borderR or 0, bd.borderG or 0, bd.borderB or 0, 1, bSz) end
                    end
                end

                -- Hover highlight covers bar + icon
                local eg = EllesmereUI.ELLESMERE_GREEN
                -- Build a container that wraps both bar and icon for the highlight
                local hlContainer = CreateFrame("Frame", nil, pvFrame)
                hlContainer:SetFrameLevel(pvFrame:GetFrameLevel() + 2)
                if pvIconMode ~= "none" and bd.spellID and bd.spellID > 0 then
                    local iSize = bd.iconSize or PREVIEW_H
                    if pvIconMode == "left" then
                        hlContainer:SetPoint("TOPLEFT",     pvFrame, "TOPLEFT",  -(iSize + math.abs(bd.iconX or 0)), 0)
                        hlContainer:SetPoint("BOTTOMRIGHT", pvFrame, "BOTTOMRIGHT", 0, 0)
                    elseif pvIconMode == "right" then
                        hlContainer:SetPoint("TOPLEFT",     pvFrame, "TOPLEFT",  0, 0)
                        hlContainer:SetPoint("BOTTOMRIGHT", pvFrame, "BOTTOMRIGHT", iSize + math.abs(bd.iconX or 0), 0)
                    end
                else
                    hlContainer:SetAllPoints(pvFrame)
                end
                local PP = EllesmereUI and EllesmereUI.PP
                local pvBrd = PP and PP.CreateBorder(hlContainer, eg.r, eg.g, eg.b, 1, 2, "OVERLAY", 7)
                if pvBrd then pvBrd:Hide() end

                -- Click to assign buff
                pvFrame:EnableMouse(true)
                pvFrame:SetScript("OnEnter", function() if pvBrd then pvBrd:Show() end end)
                pvFrame:SetScript("OnLeave", function() if pvBrd then pvBrd:Hide() end end)
                pvFrame:SetScript("OnMouseDown", function(self)
                    ShowTBBSpellPicker(self, bd, function()
                        EllesmereUI:RefreshPage(true)
                    end)
                end)
            else
                local hint = pvFrame:CreateFontString(nil, "OVERLAY")
                hint:SetFont(FONT_PATH, 12, GetCDMOptOutline())
                hint:SetTextColor(1, 1, 1, 0.35)
                hint:SetPoint("CENTER")
                hint:SetText("Use the dropdown above to add a new bar")
            end

            -- Preview visual height = tallest element (bar or icon)
            local pvIconMode = bd and bd.iconDisplay or "none"
            local pvVisH = PREVIEW_H
            if bd and pvIconMode ~= "none" and bd.spellID and bd.spellID > 0 then
                local iSize = bd.iconSize or PREVIEW_H
                if iSize > pvVisH then pvVisH = iSize end
            end

            fy = fy - pvVisH - 15
            _tbbHeaderFixedH = 20 + DD_H + 15 + 15
            return math.abs(fy)
        end
        EllesmereUI:SetContentHeader(_tbbHeaderBuilder)

        -------------------------------------------------------------------
        --  Scrollable settings (below content header)
        -------------------------------------------------------------------
        if not SelectedTBB() then
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
                      if pvIconMode ~= "none" and bd.spellID and bd.spellID > 0 then
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

        -- Buff Name (cog: size + x/y) | Buff Duration (cog: size + x/y)
        local nameRow
        nameRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Buff Name",
              getValue = function() local bd = SelectedTBB(); return bd and bd.showName ~= false end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.showName = v; RefreshTBB()
              end },
            { type = "toggle", text = "Buff Duration",
              getValue = function() local bd = SelectedTBB(); return bd and bd.showTimer end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.showTimer = v; RefreshTBB()
              end }
        );  y = y - h
        -- Cog on Buff Name: text size + x/y
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
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Buff Name"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisName()
                local bd = SelectedTBB()
                if bd and bd.showName == false then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisName)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisName)
            UpdateCogDisName()
        end
        -- Cog on Buff Duration: timer size + x/y
        do
            local rgn = nameRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Duration Settings",
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
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Buff Duration"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisTimer()
                local bd = SelectedTBB()
                if bd and not bd.showTimer then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisTimer)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisTimer)
            UpdateCogDisTimer()
        end

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "Display", y);  y = y - h

        -- Show Icon (cog: size/x/y/border size) | Opacity
        local iconRow
        iconRow, h = W:DualRow(parent, y,
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
        -- Inline border swatch + cog on Show Icon
        do
            local rgn = iconRow._leftRegion
            local ctrl = rgn._control
            local iconBorderSwatch, updateIconBorderSwatch = EllesmereUI.BuildColorSwatch(
                rgn, iconRow:GetFrameLevel() + 3,
                function()
                    local bd = SelectedTBB()
                    return (bd and bd.borderR or 0), (bd and bd.borderG or 0), (bd and bd.borderB or 0)
                end,
                function(r, g, b)
                    local bd = SelectedTBB(); if not bd then return end
                    bd.borderR, bd.borderG, bd.borderB = r, g, b; RefreshTBB()
                end,
                false, 20)
            PP.Point(iconBorderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local _, iconCogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Settings",
                rows = {
                    { type = "slider", label = "Size", min = 8, max = 64, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.iconSize or 24 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.iconSize = v
                          if _tbbPvIcon then _tbbPvIcon:SetSize(v, v) end
                          local pvIconMode = bd.iconDisplay or "none"
                          local pvVisH = bd.height or 24
                          if pvIconMode ~= "none" and bd.spellID and bd.spellID > 0 then
                              if v > pvVisH then pvVisH = v end
                          end
                          EllesmereUI:UpdateContentHeaderHeight(20 + 34 + 15 + pvVisH + 15)
                          ns.BuildTrackedBuffBars()
                      end },
                    { type = "slider", label = "X Offset", min = -40, max = 40, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.iconX or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.iconX = v; RefreshTBB()
                      end },
                    { type = "slider", label = "Y Offset", min = -40, max = 40, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.iconY or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.iconY = v; RefreshTBB()
                      end },
                    { type = "slider", label = "Border Size", min = 0, max = 5, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.iconBorderSize or 0 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.iconBorderSize = v; RefreshTBB()
                      end },
                },
            })
            MakeCogBtn(rgn, iconCogShow, iconBorderSwatch, EllesmereUI.RESIZE_ICON)
            local iconSwatchBlock = CreateFrame("Frame", nil, iconBorderSwatch)
            iconSwatchBlock:SetAllPoints()
            iconSwatchBlock:SetFrameLevel(iconBorderSwatch:GetFrameLevel() + 10)
            iconSwatchBlock:EnableMouse(true)
            iconSwatchBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(iconBorderSwatch, EllesmereUI.DisabledTooltip("Set Show Icon to Left or Right"))
            end)
            iconSwatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateIconState()
                local bd = SelectedTBB()
                local disabled = not bd or (bd.iconDisplay or "none") == "none"
                if disabled then iconBorderSwatch:SetAlpha(0.3); iconSwatchBlock:Show()
                else iconBorderSwatch:SetAlpha(1); iconSwatchBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateIconBorderSwatch(); UpdateIconState() end)
            UpdateIconState()
        end

        -- Fill Color (cog: gradient) | Show Spark
        local fillRow
        fillRow, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Fill Color",
              swatches = {
                  { tooltip = "Gradient End Color", hasAlpha = true,
                    getValue = function()
                        local bd = SelectedTBB()
                        if not bd then return 0.20, 0.20, 0.80, 1 end
                        return bd.gradientR, bd.gradientG, bd.gradientB, bd.gradientA
                    end,
                    setValue = function(r, g, b, a)
                        local bd = SelectedTBB(); if not bd then return end
                        bd.gradientR, bd.gradientG, bd.gradientB, bd.gradientA = r, g, b, a; RefreshTBB()
                    end },
                  { tooltip = "Fill Color", hasAlpha = true,
                    getValue = function()
                        local bd = SelectedTBB()
                        if not bd then
                            local _, cf = UnitClass("player")
                            local cc = RAID_CLASS_COLORS[cf]
                            return cc and cc.r or 1, cc and cc.g or 0.70, cc and cc.b or 0, 1
                        end
                        return bd.fillR, bd.fillG, bd.fillB, bd.fillA
                    end,
                    setValue = function(r, g, b, a)
                        local bd = SelectedTBB(); if not bd then return end
                        bd.fillR, bd.fillG, bd.fillB, bd.fillA = r, g, b, a; RefreshTBB()
                    end },
              } },
            { type = "toggle", text = "Show Spark",
              getValue = function() local bd = SelectedTBB(); return bd and bd.showSpark end,
              setValue = function(v)
                  local bd = SelectedTBB(); if not bd then return end
                  bd.showSpark = v; RefreshTBB()
              end }
        );  y = y - h
        -- Cog on Fill Color: gradient settings
        do
            local rgn = fillRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Gradient Settings",
                rows = {
                    { type = "toggle", label = "Enable Gradient",
                      get = function() local bd = SelectedTBB(); return bd and bd.gradientEnabled end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.gradientEnabled = v; RefreshTBB(); EllesmereUI:RefreshPage()
                      end },
                    { type = "dropdown", label = "Gradient Direction",
                      values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                      order = { "HORIZONTAL", "VERTICAL" },
                      get = function() local bd = SelectedTBB(); return bd and bd.gradientDir or "HORIZONTAL" end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.gradientDir = v; RefreshTBB()
                      end },
                },
            })
            MakeCogBtn(rgn, cogShow, nil, EllesmereUI.COGS_ICON)
        end
        -- Gradient swatch disabled when gradient off
        do
            local swatch = fillRow._leftRegion._control
            local function UpdateGradientSwatch()
                local bd = SelectedTBB()
                if not bd or not bd.gradientEnabled then
                    swatch:SetAlpha(0.15); swatch:Disable()
                    swatch._disabledTooltip = "Enable Gradient"
                else
                    swatch:SetAlpha(1); swatch:Enable()
                    swatch._disabledTooltip = nil
                end
            end
            UpdateGradientSwatch()
            EllesmereUI.RegisterWidgetRefresh(UpdateGradientSwatch)
        end

        -- Border Color (cog: border size) | Background Color
        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Border Color",
              swatches = {
                  { tooltip = "Border Color", hasAlpha = false,
                    getValue = function()
                        local bd = SelectedTBB()
                        return (bd and bd.borderR or 0), (bd and bd.borderG or 0), (bd and bd.borderB or 0)
                    end,
                    setValue = function(r, g, b)
                        local bd = SelectedTBB(); if not bd then return end
                        bd.borderR, bd.borderG, bd.borderB = r, g, b; RefreshTBB()
                    end },
              } },
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
        -- Cog on Border Color: border size
        do
            local rgn = borderRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Settings",
                rows = {
                    { type = "slider", label = "Border Size", min = 1, max = 5, step = 1,
                      get = function() local bd = SelectedTBB(); return bd and bd.borderSize or 1 end,
                      set = function(v)
                          local bd = SelectedTBB(); if not bd then return end
                          bd.borderSize = v; RefreshTBB()
                      end },
                },
            })
            MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
        end

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
    local function ShowSpellPicker(anchorFrame, barKey, slotIndex, excludeSet, onSelect)
        -- Close existing
        if _spellPickerMenu then _spellPickerMenu:Hide() end

        local allSpells = ns.GetCDMSpellsForBar(barKey)
        if not allSpells or #allSpells == 0 then return end

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

        local isTrinketBar = bd and bd.barType == "trinkets"
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

        local function MakeItem(sp, isDisabled, firesPopup)
            -- Check if this spell belongs to the wrong category group for this bar type.
            -- e.g. a cooldown-category spell on a buffs bar, or vice versa.
            local wrongCatGroup = false
            if not isDisabled and sp.cdmCatGroup then
                if isBuffBar and sp.cdmCatGroup == "cooldown" then
                    wrongCatGroup = true
                elseif not isBuffBar and not isTrinketBar and sp.cdmCatGroup == "buff" then
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

        if isCDorUtil then
            -- Layout: available primary → unavailable primary → available secondary
            -- → unavailable secondary → disabled (unlearned)
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

        -- Close on click outside: invisible full-screen button behind menu
        local closer = CreateFrame("Button", nil, UIParent)
        closer:SetFrameStrata("FULLSCREEN_DIALOG")
        closer:SetFrameLevel(menu:GetFrameLevel() - 1)
        closer:SetAllPoints(UIParent)
        closer:SetScript("OnClick", function() menu:Hide(); closer:Hide() end)
        menu:HookScript("OnHide", function() closer:Hide() end)
        closer:Show()

        menu:Show()
        _spellPickerMenu = menu
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
                if s and s._hlEdges then
                    for e = 1, 4 do s._hlEdges[e]:Hide() end
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
                    if s and s._hlEdges then
                        for e = 1, 4 do s._hlEdges[e]:Hide() end
                    end
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
                if s and s._hlEdges then
                    for e = 1, 4 do s._hlEdges[e]:Show() end
                end
                return
            end

            -- Insert mode: clear swap highlight first
            if swapTargetIdx then
                local s = previewSlots[swapTargetIdx]
                if s and s._hlEdges then
                    for e = 1, 4 do s._hlEdges[e]:Hide() end
                end
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

            for i = 1, slotCount do
                local s = previewSlots[i]
                if not s or not s._baseX then
                    if s then s:SetAlpha(i == fromIdx and 0.3 or 1) end
                elseif i == fromIdx then
                    s:SetAlpha(0.3)
                    s._targetOffX = 0
                    if not s._currentOffX then s._currentOffX = 0 end
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
                            if sw and sw._hlEdges then
                                for e = 1, 4 do sw._hlEdges[e]:Hide() end
                            end
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
                        RefreshHoverHighlight()
                        return
                    end
                end
                ClearInsertIndicator()
                dragSlot = nil; dragIdx = nil; insertIdx = nil; dragMode = nil
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
                elseif self._hlEdges then
                    for e = 1, 4 do self._hlEdges[e]:Hide() end
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
            if numRows > 3 then numRows = 3 end

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
            local gridSlots = stride * numRows  -- total grid positions (spells + blanks)
            self._stride = stride
            self._numRows = numRows
            self._gridSlots = gridSlots

            -- Total width includes +1 column for the "+" button
            local totalCols = stride + 1
            local totalW = (totalCols * iconSize) + ((totalCols - 1) * spacing)
            local totalH = (numRows * iconH) + ((numRows - 1) * spacing)

            local startX = math.floor((localParentW - totalW) / 2)
            local startY = -5

            -- Position helper: places frame at grid position (col, row)
            -- Row 0 = top, row numRows-1 = bottom
            -- When grow == "LEFT", mirror column order so icon 1 is rightmost
            local function PosAtGrid(frame, col, row)
                local px
                if grow == "LEFT" then
                    px = startX + (stride - 1 - col) * (iconSize + spacing)
                else
                    px = startX + col * (iconSize + spacing)
                end
                local py = startY - row * (iconH + spacing)
                PP.Size(frame, iconSize, iconH); frame:ClearAllPoints()
                PP.Point(frame, "TOPLEFT", self, "TOPLEFT", px, py)
                frame._baseX = px
                frame._baseY = py
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

            -- Layout: fill bottom row first, then top. Blanks end up at end of top row.
            -- gridIdx 0..stride-1 = bottom row, stride..2*stride-1 = next row up, etc.
            for i = 1, math.min(gridSlots, MAX_PREVIEW_ICONS) do
                local slot = previewSlots[i]
                slot._slotIdx = i

                local gridIdx = i - 1
                local col = gridIdx % stride
                local fillRow = math.floor(gridIdx / stride)  -- 0 = first filled row
                local visRow = (numRows - 1) - fillRow         -- map to visual: 0=first filled bottom
                PosAtGrid(slot, col, visRow)

                if i <= count then
                    -- Spell slot
                    local id = tracked[i]
                    slot._previewSpellID = nil  -- reset each update
                    if id then
                        local tex
                        if isCustomBar then
                            if id < 0 then
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
                                -- Extra spell (trinket/racial/potion)
                                if id < 0 then
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

                slot:Show()
            end

            for i = gridSlots + 1, MAX_PREVIEW_ICONS do previewSlots[i]:Hide() end

            -- "+" button: always at the far right (its own column, not mirrored)
            local addPx = startX + stride * (iconSize + spacing)
            local addPy = startY - (numRows - 1) * (iconH + spacing)
            PP.Size(addBtn, iconSize, iconH); addBtn:ClearAllPoints()
            PP.Point(addBtn, "TOPLEFT", self, "TOPLEFT", addPx, addPy)
            if addBtn._ppBorders then PP.SetBorderSize(addBtn, 1) end
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            addLbl:SetTextColor(ar, ag, ab, 0.6)
            addBtn:Show()

            -- Bar background covers spell grid only (not the + column)
            local spellW = (stride * iconSize) + ((stride - 1) * spacing)
            if bd.barBgEnabled then
                pvBarBg:ClearAllPoints()
                pvBarBg:SetPoint("TOPLEFT", startX, 0)
                pvBarBg:SetPoint("BOTTOMRIGHT", pf, "TOPLEFT", startX + spellW, -totalH)
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
                if bd and bd.barType == "trinkets" then
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
                    if b.barType == "trinkets" then
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
                    { type = "trinkets",  label = "+ Add Trinket/Racials/Potion Bar" },
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

                -- Close on outside click
                local closer = CreateFrame("Button", nil, UIParent)
                closer:SetFrameStrata("FULLSCREEN_DIALOG")
                closer:SetFrameLevel(menu:GetFrameLevel() - 1)
                closer:SetAllPoints(UIParent)
                closer:SetScript("OnClick", function() menu:Hide(); closer:Hide() end)
                menu:HookScript("OnHide", function() closer:Hide() end)
                closer:Show()

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

        -------------------------------------------------------------------
        --  BAR LAYOUT
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "Bar Layout", y);  y = y - h

        -- Row 1: (Sync) Bar Visibility | (Sync) Bar Opacity
        local visRow, visH = W:DualRow(parent, y,
            { type="dropdown", text="Bar Visibility",
              values = { always="Always", in_combat="In Combat", mouseover="Mouseover", never="Never" },
              order = { "always", "in_combat", "mouseover", "never" },
              getValue=function() return BD().barVisibility or "always" end,
              setValue=function(v)
                  BD().barVisibility = v
                  ns.CDMApplyVisibility()
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Bar Opacity",
              min=0, max=100, step=5,
              getValue=function() return math.floor((BD().barBgAlpha or 1) * 100 + 0.5) end,
              setValue=function(v)
                  BD().barBgAlpha = v / 100
                  ns.BuildAllCDMBars(); Refresh()
                  UpdateCDMPreview()
              end });  y = y - visH

        -- Sync icon on Bar Visibility (left)
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

        -- Sync icon on Bar Opacity (right)
        do
            local rgn = visRow._rightRegion
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

        -- Inline cog on Bar Visibility (left) Housing hide + Background
        do
            local leftRgn = visRow._leftRegion
            local ctrl = leftRgn._control
            local _, housingCogShow = EllesmereUI.BuildCogPopup({
                title = "Visibility Options",
                rows = {
                    { type="toggle", label="Hide in Housing",
                      get=function() return BD().housingHideEnabled ~= false end,
                      set=function(v)
                          BD().housingHideEnabled = v
                          ns.CDMApplyVisibility()
                      end },
                },
            })
            MakeCogBtn(leftRgn, housingCogShow, ctrl, EllesmereUI.COGS_ICON)
        end

        -- Inline cog on Bar Opacity (right) Background toggle + color
        do
            local rightRgn = visRow._rightRegion
            local ctrl = rightRgn._control
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
            MakeCogBtn(rightRgn, bgCogShow, ctrl)
        end

        -- Row 2: Number of Rows | Vertical Orientation
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

        -- Tooltip
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Tooltip on Hover",
              getValue=function() return BD().showTooltip == true end,
              setValue=function(v)
                  BD().showTooltip = v
                  Refresh()
              end },
            { type="label", text="" }
        );  y = y - h

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

        -- Inline active anim color swatch + eye + cog on Active Animation (right of row 1)
        do
            local rightRgn = scaleAnimRow._rightRegion
            local ctrl = rightRgn._control

            -- Eye preview button
            local EYE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
            local EYE_VIS   = EYE_MEDIA .. "eui-visible.png"
            local EYE_INVIS = EYE_MEDIA .. "eui-invisible.png"
            local eyeBtn = CreateFrame("Button", nil, rightRgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", ctrl, "LEFT", -8, 0)
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

            -- Color swatch
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
            PP.Point(animSwatch, "RIGHT", eyeBtn, "LEFT", -8, 0)

            local animSwatchBlock = CreateFrame("Frame", nil, animSwatch)
            animSwatchBlock:SetAllPoints(); animSwatchBlock:SetFrameLevel(animSwatch:GetFrameLevel() + 10)
            animSwatchBlock:EnableMouse(true)
            animSwatchBlock:SetScript("OnEnter", function()
                local reason
                local a = BD().activeStateAnim or "blizzard"
                if a == "none" or a == "hideActive" or IsCustomShape() then
                    reason = "This option requires an active state selection"
                else
                    reason = "Color is controlled by class color"
                end
                EllesmereUI.ShowWidgetTooltip(animSwatch, EllesmereUI.DisabledTooltip(reason))
            end)
            animSwatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Cog popup with class color toggle
            local _, animCogShow = EllesmereUI.BuildCogPopup({
                title = "Animation Options",
                rows = {
                    { type="toggle", label="Class Colored Animation",
                      get=function() return BD().activeAnimClassColor end,
                      set=function(v)
                          BD().activeAnimClassColor = v; ns.BuildAllCDMBars()
                          if _cdmActivePreviewOn and _cdmPreview then StopActiveStatePreview(); StartActiveStatePreview() end
                          Refresh(); EllesmereUI:RefreshPage()
                      end },
                },
            })
            MakeCogBtn(rightRgn, animCogShow, animSwatch, EllesmereUI.COGS_ICON)

            local function UpdateAnimState()
                local a = BD().activeStateAnim or "blizzard"
                local noAnim = a == "none" or a == "hideActive" or IsCustomShape()
                RefreshEye()
                if noAnim then eyeBtn:SetAlpha(0.15); eyeBlock:Show()
                else eyeBtn:SetAlpha(0.4); eyeBlock:Hide() end
                local swatchDis = BD().activeAnimClassColor or noAnim
                if swatchDis then animSwatch:SetAlpha(0.3); animSwatchBlock:Show()
                else animSwatch:SetAlpha(1); animSwatchBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateAnimSwatch(); UpdateAnimState() end)
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

        -- Inline border color swatch + cog (class color) on Border Size (left of row 3)
        do
            local leftRgn = borderRow._leftRegion
            local ctrl = leftRgn._control
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                leftRgn, borderRow:GetFrameLevel() + 3,
                function() return BD().borderR or 0, BD().borderG or 0, BD().borderB or 0 end,
                function(r, g, b)
                    BD().borderR, BD().borderG, BD().borderB = r, g, b
                    ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                end,
                false, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)

            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Border color is controlled by class color"))
            end)
            swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local _, borderCogShow = EllesmereUI.BuildCogPopup({
                title = "Border Options",
                rows = {
                    { type="toggle", label="Class Colored Border",
                      get=function() return BD().borderClassColor end,
                      set=function(v)
                          BD().borderClassColor = v
                          ns.RefreshCDMIconAppearance(BD().key); Refresh(); UpdateCDMPreview()
                          EllesmereUI:RefreshPage()
                      end },
                },
            })
            MakeCogBtn(leftRgn, borderCogShow, swatch, EllesmereUI.COGS_ICON)

            local function UpdateBorderSwatchState()
                if BD().borderClassColor then
                    swatch:SetAlpha(0.3); swatchBlock:Show()
                else
                    swatch:SetAlpha(1); swatchBlock:Hide()
                end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); UpdateBorderSwatchState() end)
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
        disabledPages = { PAGE_BAR_GLOWS, PAGE_BUFF_BARS },
        disabledPageTooltips = { [PAGE_BAR_GLOWS] = "Coming Soon", [PAGE_BUFF_BARS] = "Coming Soon" },
        buildPage   = function(pageName, parent, yOffset)
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
            elseif pageName == PAGE_BUFF_BARS then
                return _tbbHeaderBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
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
            end
            ReloadUI()
        end,
    })

    SLASH_ECMEOPT1 = "/ecmeopt"
    SlashCmdList.ECMEOPT = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUICooldownManager")
    end
end)
