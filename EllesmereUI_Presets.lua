-------------------------------------------------------------------------------
--  EllesmereUI_Presets.lua
--
--  Spec assignment popup for the global profile system.
--  Split from EllesmereUI.lua -- see EllesmereUI.lua for the base addon code.
--
--  Load order (via TOC):
--    1. EllesmereUI.lua        -- constants, utils, popups, main frame
--    2. EllesmereUI_Widgets.lua -- shared widget helpers, widget factory
--    3. EllesmereUI_Presets.lua -- THIS FILE
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
local PP = EllesmereUI.PanelPP

-- Utility functions
local MakeFont         = EllesmereUI.MakeFont
local MakeBorder       = EllesmereUI.MakeBorder
local DisablePixelSnap = EllesmereUI.DisablePixelSnap
local lerp             = EllesmereUI.lerp
local MakeDropdownArrow = EllesmereUI.MakeDropdownArrow

-- Visual constants
local ELLESMERE_GREEN  = EllesmereUI.ELLESMERE_GREEN
local CLASS_COLOR_MAP  = EllesmereUI.CLASS_COLOR_MAP

-- Numeric constants used in spec assignment popup
local BORDER_R     = EllesmereUI.BORDER_R
local BORDER_G     = EllesmereUI.BORDER_G
local BORDER_B     = EllesmereUI.BORDER_B
local CB_BOX_R     = EllesmereUI.CB_BOX_R
local CB_BOX_G     = EllesmereUI.CB_BOX_G
local CB_BOX_B     = EllesmereUI.CB_BOX_B
local CB_BRD_A     = EllesmereUI.CB_BRD_A
local CB_ACT_BRD_A = EllesmereUI.CB_ACT_BRD_A


-------------------------------------------------------------------------------
--  SPEC ASSIGNMENT POPUP
--
--  Shows every spec sorted by class with checkboxes in a 5-column layout.
--  Stores assignments in db[dbKey][presetKey] = { [specID] = true, ... }
-------------------------------------------------------------------------------
do
    -- All WoW Retail classes and their specs (as of TWW / 12.0)
    local SPEC_DATA = {
        {
            class = "DEATHKNIGHT",
            name = "Death Knight",
            specs = {
                { id = 250, name = "Blood" },
                { id = 251, name = "Frost" },
                { id = 252, name = "Unholy" },
            }
        },
        {
            class = "DEMONHUNTER",
            name = "Demon Hunter",
            specs = {
                { id = 577,  name = "Havoc" },
                { id = 581,  name = "Vengeance" },
                { id = 1480, name = "Devourer" },
            }
        },
        {
            class = "DRUID",
            name = "Druid",
            specs = {
                { id = 102, name = "Balance" },
                { id = 103, name = "Feral" },
                { id = 104, name = "Guardian" },
                { id = 105, name = "Restoration" },
            }
        },
        {
            class = "EVOKER",
            name = "Evoker",
            specs = {
                { id = 1467, name = "Devastation" },
                { id = 1468, name = "Preservation" },
                { id = 1473, name = "Augmentation" },
            }
        },
        {
            class = "HUNTER",
            name = "Hunter",
            specs = {
                { id = 253, name = "Beast Mastery" },
                { id = 254, name = "Marksmanship" },
                { id = 255, name = "Survival" },
            }
        },
        {
            class = "MAGE",
            name = "Mage",
            specs = {
                { id = 62, name = "Arcane" },
                { id = 63, name = "Fire" },
                { id = 64, name = "Frost" },
            }
        },
        {
            class = "MONK",
            name = "Monk",
            specs = {
                { id = 268, name = "Brewmaster" },
                { id = 270, name = "Mistweaver" },
                { id = 269, name = "Windwalker" },
            }
        },
        {
            class = "PALADIN",
            name = "Paladin",
            specs = {
                { id = 65, name = "Holy" },
                { id = 66, name = "Protection" },
                { id = 70, name = "Retribution" },
            }
        },
        {
            class = "PRIEST",
            name = "Priest",
            specs = {
                { id = 256, name = "Discipline" },
                { id = 257, name = "Holy" },
                { id = 258, name = "Shadow" },
            }
        },
        {
            class = "ROGUE",
            name = "Rogue",
            specs = {
                { id = 259, name = "Assassination" },
                { id = 260, name = "Outlaw" },
                { id = 261, name = "Subtlety" },
            }
        },
        {
            class = "SHAMAN",
            name = "Shaman",
            specs = {
                { id = 262, name = "Elemental" },
                { id = 263, name = "Enhancement" },
                { id = 264, name = "Restoration" },
            }
        },
        {
            class = "WARLOCK",
            name = "Warlock",
            specs = {
                { id = 265, name = "Affliction" },
                { id = 266, name = "Demonology" },
                { id = 267, name = "Destruction" },
            }
        },
        {
            class = "WARRIOR",
            name = "Warrior",
            specs = {
                { id = 71, name = "Arms" },
                { id = 72, name = "Fury" },
                { id = 73, name = "Protection" },
            }
        },
    }
    EllesmereUI._SPEC_DATA = SPEC_DATA

    -- 5-column layout, sorted alphabetically left-to-right, top-to-bottom
    local NUM_COLS = 5
    local COL_LISTS = { {1,6,11}, {2,7,12}, {3,8,13}, {4,9}, {5,10} }

    local specPopup  -- reusable popup frame

    function EllesmereUI:ShowSpecAssignPopup(opts)
        local db        = opts.db
        local dbKey     = opts.dbKey
        local presetKey = opts.presetKey
        local defaultKey = opts.defaultKey
        local allPresetKeysFn = opts.allPresetKeys
        local onDefaultChanged = opts.onDefaultChanged
        local onDone = opts.onDone

        -- Ensure assignments table exists
        if not db[dbKey] then db[dbKey] = {} end
        if not db[dbKey][presetKey] then db[dbKey][presetKey] = {} end
        local assignments = db[dbKey][presetKey]

        -- Build or reuse the popup
        if not specPopup then
            local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
            local COL_W = 165
            local COL_GAP = 12
            local CONTENT_LEFT = 41
            local CONTENT_RIGHT = 36
            local CONTENT_TOP = 120
            local CLASS_H = 32
            local CLASS_PAD_TOP = 4
            local CLASS_PAD_BOT = 2
            local SPEC_H = 28
            local CLASS_GAP = 10

            local POPUP_W = CONTENT_LEFT + CONTENT_RIGHT + NUM_COLS * COL_W + (NUM_COLS - 1) * COL_GAP
            local POPUP_H = 740
            local ppScale = EllesmereUI.GetPopupScale()

            -- Dimmer
            local dimmer = CreateFrame("Frame", "EUISpecAssignDimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:EnableMouseWheel(true)
            dimmer:SetScript("OnMouseWheel", function() end)
            dimmer:Hide()
            dimmer:SetScale(ppScale)

            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0, 0, 0, 0.25)

            -- Popup frame
            local popup = CreateFrame("Frame", "EUISpecAssignPopup", dimmer)
            popup:SetScale(ppScale)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)

            local pf = EllesmereUI._popupFrames
            if pf then pf[#pf + 1] = { popup = popup, dimmer = dimmer } end
            PP.Size(popup, POPUP_W, POPUP_H)
            PP.Point(popup, "CENTER", EllesmereUI._mainFrame, "CENTER", 0, 0)

            -- Background
            local bg = popup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.08, 0.10, 1)

            -- Border (2px inset)
            local BRD_A_SP = 0.15
            local spT = popup:CreateTexture(nil, "BORDER"); spT:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spT.SetSnapToPixelGrid then spT:SetSnapToPixelGrid(false); spT:SetTexelSnappingBias(0) end
            spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); spT:SetHeight(2)
            local spB = popup:CreateTexture(nil, "BORDER"); spB:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spB.SetSnapToPixelGrid then spB:SetSnapToPixelGrid(false); spB:SetTexelSnappingBias(0) end
            spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); spB:SetHeight(2)
            local spL = popup:CreateTexture(nil, "BORDER"); spL:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spL.SetSnapToPixelGrid then spL:SetSnapToPixelGrid(false); spL:SetTexelSnappingBias(0) end
            spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); spL:SetWidth(2)
            local spR = popup:CreateTexture(nil, "BORDER"); spR:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spR.SetSnapToPixelGrid then spR:SetSnapToPixelGrid(false); spR:SetTexelSnappingBias(0) end
            spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); spR:SetWidth(2)

            -- Title
            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT, 22, "")
            title:SetTextColor(1, 1, 1, 1)
            PP.Point(title, "TOP", popup, "TOP", 0, -32)
            title:SetText(EllesmereUI.L("Assign Preset to Specs"))
            popup._title = title

            -- Subtitle
            local sub = popup:CreateFontString(nil, "OVERLAY")
            sub:SetFont(FONT, 14, "")
            sub:SetTextColor(1, 1, 1, 0.45)
            PP.Point(sub, "TOP", title, "BOTTOM", 0, -8)
            sub:SetWidth(POPUP_W - 60)
            sub:SetJustifyH("CENTER")
            sub:SetWordWrap(true)
            popup._subtitle = sub

            -- Check All / Uncheck All links
            local LINK_Y = -103
            local LINK_GAP = 20

            local checkAllBtn = CreateFrame("Button", nil, popup)
            checkAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            local checkAllLbl = checkAllBtn:CreateFontString(nil, "OVERLAY")
            checkAllLbl:SetFont(FONT, 14, "")
            checkAllLbl:SetText(EllesmereUI.L("Check All"))
            checkAllLbl:SetTextColor(1, 1, 1, 0.45)
            checkAllLbl:SetPoint("CENTER")
            checkAllBtn:SetSize(checkAllLbl:GetStringWidth() + 4, 20)
            PP.Point(checkAllBtn, "TOPLEFT", popup, "TOPLEFT", CONTENT_LEFT, LINK_Y)
            checkAllBtn:SetScript("OnEnter", function() checkAllLbl:SetTextColor(1, 1, 1, 0.80) end)
            checkAllBtn:SetScript("OnLeave", function() checkAllLbl:SetTextColor(1, 1, 1, 0.45) end)
            popup._checkAll = checkAllBtn

            local linkDivider = popup:CreateTexture(nil, "OVERLAY", nil, 7)
            linkDivider:SetColorTexture(1, 1, 1, 0.18)
            if linkDivider.SetSnapToPixelGrid then linkDivider:SetSnapToPixelGrid(false); linkDivider:SetTexelSnappingBias(0) end
            PP.Point(linkDivider, "LEFT", checkAllBtn, "RIGHT", LINK_GAP / 2, 0)
            linkDivider:SetWidth(1)
            linkDivider:SetHeight(12)

            local uncheckAllBtn = CreateFrame("Button", nil, popup)
            uncheckAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            local uncheckAllLbl = uncheckAllBtn:CreateFontString(nil, "OVERLAY")
            uncheckAllLbl:SetFont(FONT, 14, "")
            uncheckAllLbl:SetText(EllesmereUI.L("Uncheck All"))
            uncheckAllLbl:SetTextColor(1, 1, 1, 0.45)
            uncheckAllLbl:SetPoint("CENTER")
            uncheckAllBtn:SetSize(uncheckAllLbl:GetStringWidth() + 4, 20)
            PP.Point(uncheckAllBtn, "LEFT", checkAllBtn, "RIGHT", LINK_GAP, 0)
            uncheckAllBtn:SetScript("OnEnter", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.80) end)
            uncheckAllBtn:SetScript("OnLeave", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.45) end)
            popup._uncheckAll = uncheckAllBtn

            -- Column container frames
            popup._columns = {}
            for colIdx = 1, NUM_COLS do
                local col = CreateFrame("Frame", nil, popup)
                col:SetFrameLevel(popup:GetFrameLevel() + 1)
                local colX = CONTENT_LEFT + (colIdx - 1) * (COL_W + COL_GAP)
                PP.Point(col, "TOPLEFT", popup, "TOPLEFT", colX, -CONTENT_TOP)
                PP.Size(col, COL_W, POPUP_H - CONTENT_TOP - 80)
                col._rows = {}
                popup._columns[colIdx] = col
            end

            -- Bottom area: default dropdown + Done button
            local BOTTOM_ROW_Y = 88
            local DEFAULT_DD_W = 280
            local DEFAULT_DD_H = 30

            -- Default Profile dropdown container (hidden by default)
            local defDDContainer = CreateFrame("Frame", nil, popup)
            defDDContainer:SetFrameLevel(popup:GetFrameLevel() + 2)
            PP.Size(defDDContainer, POPUP_W - 52, 68)
            PP.Point(defDDContainer, "BOTTOM", popup, "BOTTOM", 0, BOTTOM_ROW_Y)
            defDDContainer:Hide()
            popup._defDDContainer = defDDContainer

            local defDDLabel = defDDContainer:CreateFontString(nil, "OVERLAY")
            defDDLabel:SetFont(FONT, 14, "")
            defDDLabel:SetTextColor(1, 1, 1, 0.45)
            PP.Point(defDDLabel, "BOTTOM", defDDContainer, "CENTER", 0, 7)
            defDDLabel:SetText(EllesmereUI.L("Default Profile (for non-assigned specs)"))
            popup._defDDLabel = defDDLabel

            local defDDBtn = CreateFrame("Button", nil, defDDContainer)
            defDDBtn:SetFrameLevel(defDDContainer:GetFrameLevel() + 2)
            PP.Size(defDDBtn, DEFAULT_DD_W, DEFAULT_DD_H)
            PP.Point(defDDBtn, "TOP", defDDContainer, "CENTER", 0, -7)

            local defDDBg = defDDBtn:CreateTexture(nil, "BACKGROUND")
            defDDBg:SetAllPoints()
            defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)

            -- Border textures for the default dropdown
            local defBrdT = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdT:SetColorTexture(1, 1, 1, 0.20)
            if defBrdT.SetSnapToPixelGrid then defBrdT:SetSnapToPixelGrid(false); defBrdT:SetTexelSnappingBias(0) end
            defBrdT:SetPoint("TOPLEFT"); defBrdT:SetPoint("TOPRIGHT"); defBrdT:SetHeight(1)
            local defBrdB = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdB:SetColorTexture(1, 1, 1, 0.20)
            if defBrdB.SetSnapToPixelGrid then defBrdB:SetSnapToPixelGrid(false); defBrdB:SetTexelSnappingBias(0) end
            defBrdB:SetPoint("BOTTOMLEFT"); defBrdB:SetPoint("BOTTOMRIGHT"); defBrdB:SetHeight(1)
            local defBrdL = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdL:SetColorTexture(1, 1, 1, 0.20)
            if defBrdL.SetSnapToPixelGrid then defBrdL:SetSnapToPixelGrid(false); defBrdL:SetTexelSnappingBias(0) end
            defBrdL:SetPoint("TOPLEFT", defBrdT, "BOTTOMLEFT"); defBrdL:SetPoint("BOTTOMLEFT", defBrdB, "TOPLEFT"); defBrdL:SetWidth(1)
            local defBrdR = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdR:SetColorTexture(1, 1, 1, 0.20)
            if defBrdR.SetSnapToPixelGrid then defBrdR:SetSnapToPixelGrid(false); defBrdR:SetTexelSnappingBias(0) end
            defBrdR:SetPoint("TOPRIGHT", defBrdT, "BOTTOMRIGHT"); defBrdR:SetPoint("BOTTOMRIGHT", defBrdB, "TOPRIGHT"); defBrdR:SetWidth(1)
            popup._defBrdEdges = { defBrdT, defBrdB, defBrdL, defBrdR }

            local defDDLbl = defDDBtn:CreateFontString(nil, "OVERLAY")
            defDDLbl:SetFont(FONT, 13, "")
            defDDLbl:SetPoint("LEFT", defDDBtn, "LEFT", 12, 0)
            defDDLbl:SetTextColor(1, 1, 1, 0.50)
            popup._defDDLbl = defDDLbl

            local defArrow = MakeDropdownArrow(defDDBtn, 12, PP)
            popup._defDDBtn = defDDBtn

            -- Flash animation for error state on the default dropdown
            local defFlashFrame = CreateFrame("Frame", nil, defDDBtn)
            defFlashFrame:Hide()
            local defFlashElapsed = 0
            local DEF_FLASH_DUR = 0.7
            defFlashFrame:SetScript("OnUpdate", function(self, elapsed)
                defFlashElapsed = defFlashElapsed + elapsed
                if defFlashElapsed >= DEF_FLASH_DUR then
                    self:Hide()
                    for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.20) end
                    return
                end
                local t = defFlashElapsed / DEF_FLASH_DUR
                local lr = lerp(0.9, 1, t)
                local lg = lerp(0.15, 1, t)
                local lb = lerp(0.15, 1, t)
                local la = lerp(0.7, 0.20, t)
                for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(lr, lg, lb, la) end
            end)
            popup._flashDefaultDD = function()
                defFlashElapsed = 0
                for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(0.9, 0.15, 0.15, 0.7) end
                defFlashFrame:Show()
            end

            -- Default dropdown menu (popout list)
            local defMenu = CreateFrame("Frame", nil, UIParent)
            defMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            defMenu:SetFrameLevel(300)
            defMenu:SetClampedToScreen(true)
            defMenu:SetSize(DEFAULT_DD_W, 4)
            defMenu:SetPoint("TOPLEFT", defDDBtn, "BOTTOMLEFT", 0, -2)
            defMenu:Hide()
            local defMenuBg = defMenu:CreateTexture(nil, "BACKGROUND")
            defMenuBg:SetAllPoints()
            defMenuBg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
            local dmT = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmT:SetColorTexture(1,1,1,0.20)
            if dmT.SetSnapToPixelGrid then dmT:SetSnapToPixelGrid(false); dmT:SetTexelSnappingBias(0) end
            dmT:SetPoint("TOPLEFT"); dmT:SetPoint("TOPRIGHT"); dmT:SetHeight(1)
            local dmB = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmB:SetColorTexture(1,1,1,0.20)
            if dmB.SetSnapToPixelGrid then dmB:SetSnapToPixelGrid(false); dmB:SetTexelSnappingBias(0) end
            dmB:SetPoint("BOTTOMLEFT"); dmB:SetPoint("BOTTOMRIGHT"); dmB:SetHeight(1)
            local dmL = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmL:SetColorTexture(1,1,1,0.20)
            if dmL.SetSnapToPixelGrid then dmL:SetSnapToPixelGrid(false); dmL:SetTexelSnappingBias(0) end
            dmL:SetPoint("TOPLEFT", dmT, "BOTTOMLEFT"); dmL:SetPoint("BOTTOMLEFT", dmB, "TOPLEFT"); dmL:SetWidth(1)
            local dmR = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmR:SetColorTexture(1,1,1,0.20)
            if dmR.SetSnapToPixelGrid then dmR:SetSnapToPixelGrid(false); dmR:SetTexelSnappingBias(0) end
            dmR:SetPoint("TOPRIGHT", dmT, "BOTTOMRIGHT"); dmR:SetPoint("BOTTOMRIGHT", dmB, "TOPRIGHT"); dmR:SetWidth(1)
            popup._defMenu = defMenu
            popup._defMenuItems = {}

            defDDBtn:SetScript("OnEnter", function()
                defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
                defDDLbl:SetTextColor(1, 1, 1, 0.60)
                for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.30) end
            end)
            defDDBtn:SetScript("OnLeave", function()
                if not defMenu:IsShown() then
                    defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
                    defDDLbl:SetTextColor(1, 1, 1, 0.50)
                    for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.20) end
                end
            end)
            defDDBtn:SetScript("OnClick", function()
                if defMenu:IsShown() then defMenu:Hide() else
                    if popup._rebuildDefMenu then popup._rebuildDefMenu() end
                    defMenu:Show()
                end
            end)
            defDDBtn:HookScript("OnHide", function() defMenu:Hide() end)

            defMenu:SetScript("OnShow", function(self)
                local btnScale = defDDBtn:GetEffectiveScale()
                local uiScale  = UIParent:GetEffectiveScale()
                self:SetScale(btnScale / uiScale)
                self:SetScript("OnUpdate", function(m)
                    if not defDDBtn:IsMouseOver() and not m:IsMouseOver() then
                        if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide() end
                    end
                end)
            end)
            defMenu:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                if defDDBtn:IsMouseOver() then
                    defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
                    defDDLbl:SetTextColor(1, 1, 1, 0.60)
                    for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.30) end
                else
                    defDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
                    defDDLbl:SetTextColor(1, 1, 1, 0.50)
                    for _, e in ipairs(popup._defBrdEdges) do e:SetColorTexture(1, 1, 1, 0.20) end
                end
            end)

            -- Done button
            local EG = ELLESMERE_GREEN
            local closeBtn = CreateFrame("Button", nil, popup)
            closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            PP.Size(closeBtn, 200, 39)
            PP.Point(closeBtn, "BOTTOM", popup, "BOTTOM", 0, 38)
            local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
            closeBg:SetAllPoints()
            closeBg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
            local closeBrd = MakeBorder(closeBtn, EG.r, EG.g, EG.b, 0.9, PP)
            local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
            closeLbl:SetFont(FONT, 16, "")
            PP.Point(closeLbl, "CENTER", closeBtn, "CENTER", 0, 0)
            closeLbl:SetText(EllesmereUI.L("Done"))
            closeLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            closeBtn:SetScript("OnEnter", function()
                closeLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
                closeBrd:SetColor(EG.r, EG.g, EG.b, 1)
            end)
            closeBtn:SetScript("OnLeave", function()
                closeLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
                closeBrd:SetColor(EG.r, EG.g, EG.b, 0.9)
            end)
            popup._closeBtn = closeBtn
            popup._closeLbl = closeLbl

            -- Cancel button (hidden by default, shown when onCancel is provided)
            local cancelBtn = CreateFrame("Button", nil, popup)
            cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            PP.Size(cancelBtn, 200, 39)
            PP.Point(cancelBtn, "BOTTOM", popup, "BOTTOM", 0, 38)
            local cancelBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
            cancelBg:SetAllPoints()
            cancelBg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
            local cancelBrd = MakeBorder(cancelBtn, 1, 1, 1, 0.25, PP)
            local cancelLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
            cancelLbl:SetFont(FONT, 16, "")
            PP.Point(cancelLbl, "CENTER", cancelBtn, "CENTER", 0, 0)
            cancelLbl:SetText(EllesmereUI.L("Cancel"))
            cancelLbl:SetTextColor(1, 1, 1, 0.50)
            cancelBtn:SetScript("OnEnter", function()
                cancelLbl:SetTextColor(1, 1, 1, 0.75)
                cancelBrd:SetColor(1, 1, 1, 0.40)
            end)
            cancelBtn:SetScript("OnLeave", function()
                cancelLbl:SetTextColor(1, 1, 1, 0.50)
                cancelBrd:SetColor(1, 1, 1, 0.25)
            end)
            cancelBtn:SetScript("OnClick", function()
                dimmer:Hide()
                if popup._onCancel then popup._onCancel() end
            end)
            cancelBtn:Hide()
            popup._cancelBtn = cancelBtn

            popup:EnableMouse(true)

            dimmer:SetScript("OnMouseDown", function(self)
                if not popup:IsMouseOver() then
                    self:Hide()
                    if popup._onCancel then popup._onCancel() end
                end
            end)

            popup:EnableKeyboard(true)
            popup:SetScript("OnKeyDown", function(self, key)
                if key == "ESCAPE" then
                    self:SetPropagateKeyboardInput(false)
                    dimmer:Hide()
                    if popup._onCancel then popup._onCancel() end
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end)

            popup._CLASS_H = CLASS_H
            popup._CLASS_PAD_TOP = CLASS_PAD_TOP
            popup._CLASS_PAD_BOT = CLASS_PAD_BOT
            popup._SPEC_H  = SPEC_H
            popup._COL_W   = COL_W
            popup._CLASS_GAP = CLASS_GAP
            popup._dimmer = dimmer
            popup._POPUP_W = POPUP_W
            popup._POPUP_H = POPUP_H
            specPopup = popup
        end

        -- Update title / subtitle
        if opts.title then
            specPopup._title:SetText(opts.title)
        else
            specPopup._title:SetText(EllesmereUI.L("Assign Preset to Specs"))
        end
        if opts.subtitle then
            specPopup._subtitle:SetText(opts.subtitle)
        else
            local presetName
            if presetKey == "custom" then presetName = EllesmereUI.L("Custom")
            elseif presetKey == "ellesmereui" then presetName = "EllesmereUI"
            elseif presetKey and type(presetKey) == "string" and presetKey:sub(1, 5) == "user:" then presetName = presetKey:sub(6)
            else presetName = presetKey or "" end
            specPopup._subtitle:SetText(EllesmereUI.Lf("Select which specs you want %1$s to be assigned to", presetName))
        end
        -- Per-call subtitle color (default dim white). Lets a caller render a red
        -- overwrite warning in the subtitle slot. Reset every call (popup is cached).
        if opts.subtitleColor then
            local c = opts.subtitleColor
            specPopup._subtitle:SetTextColor(c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or 1)
        else
            specPopup._subtitle:SetTextColor(1, 1, 1, 0.45)
        end
        -- Placement: a bottom warning (CDM export/import) drops into the blank
        -- space above the buttons -- the spec grid never fills the full height,
        -- so no resize is needed (the popup stays the same height as every other
        -- spec picker). Normal callers keep the subtitle under the title. The
        -- warning also renders 2px larger for emphasis.
        specPopup._subtitle:ClearAllPoints()
        PP.Size(specPopup, specPopup._POPUP_W, specPopup._POPUP_H)
        local subFont = specPopup._subtitle:GetFont()
        if opts.subtitleAtBottom then
            specPopup._subtitle:SetFont(subFont, 16, "")
            -- Buttons sit 38px up at 39px tall (top edge ~77px); ~30px gap above.
            PP.Point(specPopup._subtitle, "BOTTOM", specPopup, "BOTTOM", 0, 107)
        else
            specPopup._subtitle:SetFont(subFont, 14, "")
            PP.Point(specPopup._subtitle, "TOP", specPopup._title, "BOTTOM", 0, -8)
        end

        -- Update Done button text
        if specPopup._closeLbl then
            specPopup._closeLbl:SetText(opts.buttonText or EllesmereUI.L("Done"))
        end

        -- Populate columns
        local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
        local CLASS_H = specPopup._CLASS_H
        local CLASS_PAD_TOP = specPopup._CLASS_PAD_TOP
        local CLASS_PAD_BOT = specPopup._CLASS_PAD_BOT
        local SPEC_H  = specPopup._SPEC_H
        local COL_W   = specPopup._COL_W
        local CLASS_GAP = specPopup._CLASS_GAP
        local allCheckboxes = {}
        local BOX_SZ = 18
        local CHECK_INSET = 3

        -- Build lookup: specID -> presetKey for specs assigned to OTHER presets
        local lockedSpecs = {}
        local disabledSpecs = opts.disabledSpecs or {}
        local lockedOnSpecs = opts.lockedOnSpecs or {}
        local preCheckedSpecs = opts.preCheckedSpecs
        do
            local fullMap = db and db[dbKey]
            if fullMap then
                for pKey, specList in pairs(fullMap) do
                    if pKey ~= presetKey and type(specList) == "table" then
                        for sID in pairs(specList) do
                            local dName
                            if pKey == "custom" then dName = EllesmereUI.L("Custom")
                            elseif pKey == "ellesmereui" then dName = "EllesmereUI"
                            elseif pKey:sub(1, 5) == "user:" then dName = pKey:sub(6)
                            else dName = pKey end
                            lockedSpecs[sID] = dName
                        end
                    end
                end
            end
        end

        -- Pre-check specs if requested
        if preCheckedSpecs then
            for sID in pairs(preCheckedSpecs) do
                assignments[sID] = true
            end
        end
        -- Locked-on specs are always checked and cannot be toggled off.
        for sID in pairs(lockedOnSpecs) do
            assignments[sID] = true
        end

        for colIdx = 1, NUM_COLS do
            local col = specPopup._columns[colIdx]
            for _, row in ipairs(col._rows) do row:Hide() end

            local list = COL_LISTS[colIdx]
            local rowIdx = 0
            local yOff = 0
            local isFirstClass = true

            for _, classIdx in ipairs(list) do
                local cls = SPEC_DATA[classIdx]

                if not isFirstClass then
                    yOff = yOff + CLASS_GAP
                end
                isFirstClass = false

                -- Class header
                yOff = yOff + CLASS_PAD_TOP
                rowIdx = rowIdx + 1
                local hdr = col._rows[rowIdx]
                if not hdr then
                    hdr = CreateFrame("Frame", nil, col)
                    col._rows[rowIdx] = hdr
                end
                PP.Size(hdr, COL_W, CLASS_H)
                hdr:ClearAllPoints()
                PP.Point(hdr, "TOPLEFT", col, "TOPLEFT", 0, -yOff)
                hdr:Show()

                if not hdr._label then
                    hdr._label = hdr:CreateFontString(nil, "OVERLAY")
                    hdr._label:SetFont(FONT, 18, "")
                    PP.Point(hdr._label, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 4, 4)
                end
                local clr = CLASS_COLOR_MAP[cls.class]
                if clr then
                    hdr._label:SetTextColor(clr.r, clr.g, clr.b, 0.9)
                else
                    hdr._label:SetTextColor(1, 1, 1, 0.7)
                end
                hdr._label:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls.class]) or cls.name)
                yOff = yOff + CLASS_H + CLASS_PAD_BOT

                -- Spec checkboxes
                for _, spec in ipairs(cls.specs) do
                    rowIdx = rowIdx + 1
                    local row = col._rows[rowIdx]
                    if not row then
                        row = CreateFrame("Button", nil, col)
                        col._rows[rowIdx] = row

                        local box = CreateFrame("Frame", nil, row)
                        PP.Size(box, BOX_SZ, BOX_SZ)
                        PP.Point(box, "LEFT", row, "LEFT", 8, 0)
                        box:SetFrameLevel(row:GetFrameLevel() + 1)
                        local boxBg = box:CreateTexture(nil, "BACKGROUND")
                        boxBg:SetAllPoints()
                        boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                        row._boxBg = boxBg
                        local boxBorder = MakeBorder(box, BORDER_R, BORDER_G, BORDER_B, CB_BRD_A, PP)
                        row._boxBorder = boxBorder
                        local check = box:CreateTexture(nil, "ARTWORK")
                        PP.Point(check, "TOPLEFT", box, "TOPLEFT", CHECK_INSET, -CHECK_INSET)
                        PP.Point(check, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -CHECK_INSET, CHECK_INSET)
                        check:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
                        row._check = check
                        row._box = box

                        local lbl = row:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT, 17, "")
                        PP.Point(lbl, "LEFT", box, "RIGHT", 8, 0)
                        lbl:SetTextColor(1, 1, 1, 0.65)
                        row._lbl = lbl
                    end
                    PP.Size(row, COL_W, SPEC_H)
                    row:ClearAllPoints()
                    PP.Point(row, "TOPLEFT", col, "TOPLEFT", 0, -yOff)
                    row:Show()

                    local locSpecName = spec.name
                    if GetSpecializationInfoByID then
                        local sn = select(2, GetSpecializationInfoByID(spec.id))
                        if sn and sn ~= "" then locSpecName = sn end
                    end
                    row._lbl:SetText(locSpecName)
                    row._specID = spec.id

                    local lockedBy = lockedSpecs[spec.id]
                    local disabledTip = disabledSpecs[spec.id]
                    local lockedOnTip = lockedOnSpecs[spec.id]
                    row._locked = lockedBy ~= nil
                    row._disabled = disabledTip ~= nil
                    row._lockedOn = lockedOnTip ~= nil and lockedOnTip ~= false

                    local checked = assignments[spec.id] == true
                    row._checked = checked
                    local EG = ELLESMERE_GREEN
                    local function UpdateVisual(r)
                        if r._lockedOn then
                            -- Always-on (e.g. the sync source): checked but locked/grayed.
                            r._check:Show()
                            r._boxBorder:SetColor(EG.r, EG.g, EG.b, CB_ACT_BRD_A * 0.5)
                            r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 0.5)
                            r._lbl:SetTextColor(1, 1, 1, 0.4)
                        elseif r._locked or r._disabled then
                            r._check:Hide()
                            r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A * 0.4)
                            r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 0.35)
                            r._lbl:SetTextColor(1, 1, 1, 0.25)
                        elseif r._checked then
                            r._check:Show()
                            r._boxBorder:SetColor(EG.r, EG.g, EG.b, CB_ACT_BRD_A)
                            r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                            r._lbl:SetTextColor(1, 1, 1, 0.65)
                        else
                            r._check:Hide()
                            r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
                            r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                            r._lbl:SetTextColor(1, 1, 1, 0.65)
                        end
                    end
                    UpdateVisual(row)
                    allCheckboxes[#allCheckboxes + 1] = row

                    row:SetScript("OnClick", function(self)
                        if self._lockedOn or self._locked or self._disabled then return end
                        self._checked = not self._checked
                        assignments[spec.id] = self._checked or nil
                        UpdateVisual(self)
                    end)
                    row:SetScript("OnEnter", function(self)
                        if self._disabled and disabledTip then
                            EllesmereUI.ShowWidgetTooltip(self._box,
                                EllesmereUI.DisabledTooltip(disabledTip))
                        elseif self._lockedOn and type(lockedOnTip) == "string" then
                            EllesmereUI.ShowWidgetTooltip(self._box,
                                EllesmereUI.DisabledTooltip(lockedOnTip))
                        end
                        if self._lockedOn or self._locked or self._disabled then return end
                        self._lbl:SetTextColor(1, 1, 1, 0.90)
                    end)
                    row:SetScript("OnLeave", function(self)
                        EllesmereUI.HideWidgetTooltip()
                        if self._lockedOn or self._locked or self._disabled then return end
                        self._lbl:SetTextColor(1, 1, 1, 0.65)
                    end)

                    yOff = yOff + SPEC_H
                end
            end
        end

        -- Check All / Uncheck All wiring
        specPopup._checkAll:SetScript("OnClick", function()
            local EG2 = ELLESMERE_GREEN
            for _, row in ipairs(allCheckboxes) do
                if not row._locked and not row._disabled and not row._lockedOn then
                    row._checked = true
                    assignments[row._specID] = true
                    row._check:Show()
                    row._boxBorder:SetColor(EG2.r, EG2.g, EG2.b, CB_ACT_BRD_A)
                end
            end
        end)
        specPopup._uncheckAll:SetScript("OnClick", function()
            for _, row in ipairs(allCheckboxes) do
                if not row._locked and not row._disabled and not row._lockedOn then
                    row._checked = false
                    assignments[row._specID] = nil
                    row._check:Hide()
                    row._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
                end
            end
        end)

        -- Default Profile dropdown (populate phase)
        local selectedDefaultKey = defaultKey and db[defaultKey] or nil

        if defaultKey and allPresetKeysFn then
            specPopup._defDDContainer:Show()

            local function DefPresetDisplayName(key)
                if not key then return "" end
                if key == "custom" then return EllesmereUI.L("Custom") end
                if key == "ellesmereui" then return "EllesmereUI" end
                if key:sub(1, 5) == "user:" then return key:sub(6) end
                return key
            end

            if selectedDefaultKey then
                specPopup._defDDLbl:SetText(DefPresetDisplayName(selectedDefaultKey))
                specPopup._defDDLbl:SetTextColor(1, 1, 1, 0.50)
            else
                specPopup._defDDLbl:SetText("")
                specPopup._defDDLbl:SetTextColor(1, 1, 1, 0.35)
            end

            specPopup._rebuildDefMenu = function()
                local items = specPopup._defMenuItems
                for _, itm in ipairs(items) do itm:Hide() end

                local presetList = allPresetKeysFn()
                local mH = 4
                local ITEM_FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")

                for idx, entry in ipairs(presetList) do
                    local itm = items[idx]
                    if not itm then
                        itm = CreateFrame("Button", nil, specPopup._defMenu)
                        itm:SetHeight(26)
                        itm:SetFrameLevel(specPopup._defMenu:GetFrameLevel() + 1)
                        local lbl = itm:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(ITEM_FONT, 13, "")
                        lbl:SetPoint("LEFT", itm, "LEFT", 10, 0)
                        lbl:SetTextColor(0.55, 0.60, 0.65, 1)
                        itm._lbl = lbl
                        local hl = itm:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints()
                        hl:SetColorTexture(1, 1, 1, 1)
                        hl:SetAlpha(0)
                        itm._hl = hl
                        itm:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 1); hl:SetAlpha(0.08) end)
                        itm:SetScript("OnLeave", function()
                            local isSel = (itm._key == selectedDefaultKey)
                            lbl:SetTextColor(0.55, 0.60, 0.65, 1)
                            hl:SetAlpha(isSel and 0.04 or 0)
                        end)
                        items[idx] = itm
                    end
                    itm:SetPoint("TOPLEFT", specPopup._defMenu, "TOPLEFT", 1, -mH)
                    itm:SetPoint("TOPRIGHT", specPopup._defMenu, "TOPRIGHT", -1, -mH)
                    itm._lbl:SetText(entry.name)
                    itm._key = entry.key
                    local isSel = (entry.key == selectedDefaultKey)
                    itm._hl:SetAlpha(isSel and 0.04 or 0)
                    itm:SetScript("OnClick", function()
                        selectedDefaultKey = entry.key
                        specPopup._defDDLbl:SetText(entry.name)
                        specPopup._defDDLbl:SetTextColor(1, 1, 1, 0.50)
                        specPopup._defMenu:Hide()
                    end)
                    itm:Show()
                    mH = mH + 26
                end
                specPopup._defMenu:SetHeight(mH + 4)
            end
        else
            specPopup._defDDContainer:Hide()
        end

        -- Store callbacks on the popup for dimmer/ESC access
        specPopup._onCancel = opts.onCancel

        -- Show/hide Cancel button and reposition Done button
        local BTN_GAP = 12
        if opts.onCancel then
            specPopup._cancelBtn:Show()
            specPopup._closeBtn:ClearAllPoints()
            PP.Point(specPopup._closeBtn, "BOTTOMRIGHT", specPopup, "BOTTOM", -(BTN_GAP / 2), 38)
            specPopup._cancelBtn:ClearAllPoints()
            PP.Point(specPopup._cancelBtn, "BOTTOMLEFT", specPopup, "BOTTOM", (BTN_GAP / 2), 38)
        else
            specPopup._cancelBtn:Hide()
            specPopup._closeBtn:ClearAllPoints()
            PP.Point(specPopup._closeBtn, "BOTTOM", specPopup, "BOTTOM", 0, 38)
        end

        -- Done button: validate default selection if spec feature is active
        specPopup._closeBtn:SetScript("OnClick", function()
            if defaultKey and allPresetKeysFn and not selectedDefaultKey then
                specPopup._flashDefaultDD()
                return
            end
            if defaultKey and selectedDefaultKey then
                db[defaultKey] = selectedDefaultKey
                if onDefaultChanged then onDefaultChanged() end
            end
            specPopup._dimmer:Hide()
            if opts.onConfirm then
                opts.onConfirm(assignments)
            elseif onDone then
                onDone()
            end
        end)

        specPopup._dimmer:Show()
    end
end
