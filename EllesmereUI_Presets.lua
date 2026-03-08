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
        { class = "DEATHKNIGHT",  name = "Death Knight",  specs = {
            { id = 250, name = "Blood" },
            { id = 251, name = "Frost" },
            { id = 252, name = "Unholy" },
        }},
        { class = "DEMONHUNTER",  name = "Demon Hunter",  specs = {
            { id = 577, name = "Havoc" },
            { id = 581, name = "Vengeance" },
            { id = 1480, name = "Devourer" },
        }},
        { class = "DRUID",        name = "Druid",         specs = {
            { id = 102, name = "Balance" },
            { id = 103, name = "Feral" },
            { id = 104, name = "Guardian" },
            { id = 105, name = "Restoration" },
        }},
        { class = "EVOKER",       name = "Evoker",        specs = {
            { id = 1467, name = "Devastation" },
            { id = 1468, name = "Preservation" },
            { id = 1473, name = "Augmentation" },
        }},
        { class = "HUNTER",       name = "Hunter",        specs = {
            { id = 253, name = "Beast Mastery" },
            { id = 254, name = "Marksmanship" },
            { id = 255, name = "Survival" },
        }},
        { class = "MAGE",         name = "Mage",          specs = {
            { id = 62,  name = "Arcane" },
            { id = 63,  name = "Fire" },
            { id = 64,  name = "Frost" },
        }},
        { class = "MONK",         name = "Monk",          specs = {
            { id = 268, name = "Brewmaster" },
            { id = 270, name = "Mistweaver" },
            { id = 269, name = "Windwalker" },
        }},
        { class = "PALADIN",      name = "Paladin",       specs = {
            { id = 65,  name = "Holy" },
            { id = 66,  name = "Protection" },
            { id = 70,  name = "Retribution" },
        }},
        { class = "PRIEST",       name = "Priest",        specs = {
            { id = 256, name = "Discipline" },
            { id = 257, name = "Holy" },
            { id = 258, name = "Shadow" },
        }},
        { class = "ROGUE",        name = "Rogue",         specs = {
            { id = 259, name = "Assassination" },
            { id = 260, name = "Outlaw" },
            { id = 261, name = "Subtlety" },
        }},
        { class = "SHAMAN",       name = "Shaman",        specs = {
            { id = 262, name = "Elemental" },
            { id = 263, name = "Enhancement" },
            { id = 264, name = "Restoration" },
        }},
        { class = "WARLOCK",      name = "Warlock",       specs = {
            { id = 265, name = "Affliction" },
            { id = 266, name = "Demonology" },
            { id = 267, name = "Destruction" },
        }},
        { class = "WARRIOR",      name = "Warrior",       specs = {
            { id = 71,  name = "Arms" },
            { id = 72,  name = "Fury" },
            { id = 73,  name = "Protection" },
        }},
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
        local titleText = opts.titleText
        local subtitleBuilder = opts.subtitleBuilder

        -- Ensure assignments table exists
        if not db[dbKey] then db[dbKey] = {} end
        if not db[dbKey][presetKey] then db[dbKey][presetKey] = {} end

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
            spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); PP.Height(spT, 2)
            local spB = popup:CreateTexture(nil, "BORDER"); spB:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spB.SetSnapToPixelGrid then spB:SetSnapToPixelGrid(false); spB:SetTexelSnappingBias(0) end
            spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); PP.Height(spB, 2)
            local spL = popup:CreateTexture(nil, "BORDER"); spL:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spL.SetSnapToPixelGrid then spL:SetSnapToPixelGrid(false); spL:SetTexelSnappingBias(0) end
            spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); PP.Width(spL, 2)
            local spR = popup:CreateTexture(nil, "BORDER"); spR:SetColorTexture(1, 1, 1, BRD_A_SP)
            if spR.SetSnapToPixelGrid then spR:SetSnapToPixelGrid(false); spR:SetTexelSnappingBias(0) end
            spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); PP.Width(spR, 2)

            -- Title
            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT, 22, "")
            title:SetTextColor(1, 1, 1, 1)
            PP.Point(title, "TOP", popup, "TOP", 0, -32)
            title:SetText("Assign Preset to Specs")
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
            checkAllLbl:SetText("Check All")
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
            PP.Width(linkDivider, 1)
            PP.Height(linkDivider, 12)

            local uncheckAllBtn = CreateFrame("Button", nil, popup)
            uncheckAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            local uncheckAllLbl = uncheckAllBtn:CreateFontString(nil, "OVERLAY")
            uncheckAllLbl:SetFont(FONT, 14, "")
            uncheckAllLbl:SetText("Uncheck All")
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
            defDDLabel:SetText("Default Profile (for non-assigned specs)")
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
            defBrdT:SetPoint("TOPLEFT"); defBrdT:SetPoint("TOPRIGHT"); PP.Height(defBrdT, 1)
            local defBrdB = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdB:SetColorTexture(1, 1, 1, 0.20)
            if defBrdB.SetSnapToPixelGrid then defBrdB:SetSnapToPixelGrid(false); defBrdB:SetTexelSnappingBias(0) end
            defBrdB:SetPoint("BOTTOMLEFT"); defBrdB:SetPoint("BOTTOMRIGHT"); PP.Height(defBrdB, 1)
            local defBrdL = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdL:SetColorTexture(1, 1, 1, 0.20)
            if defBrdL.SetSnapToPixelGrid then defBrdL:SetSnapToPixelGrid(false); defBrdL:SetTexelSnappingBias(0) end
            defBrdL:SetPoint("TOPLEFT", defBrdT, "BOTTOMLEFT"); defBrdL:SetPoint("BOTTOMLEFT", defBrdB, "TOPLEFT"); PP.Width(defBrdL, 1)
            local defBrdR = defDDBtn:CreateTexture(nil, "OVERLAY", nil, 7)
            defBrdR:SetColorTexture(1, 1, 1, 0.20)
            if defBrdR.SetSnapToPixelGrid then defBrdR:SetSnapToPixelGrid(false); defBrdR:SetTexelSnappingBias(0) end
            defBrdR:SetPoint("TOPRIGHT", defBrdT, "BOTTOMRIGHT"); defBrdR:SetPoint("BOTTOMRIGHT", defBrdB, "TOPRIGHT"); PP.Width(defBrdR, 1)
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
            dmT:SetPoint("TOPLEFT"); dmT:SetPoint("TOPRIGHT"); PP.Height(dmT, 1)
            local dmB = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmB:SetColorTexture(1,1,1,0.20)
            if dmB.SetSnapToPixelGrid then dmB:SetSnapToPixelGrid(false); dmB:SetTexelSnappingBias(0) end
            dmB:SetPoint("BOTTOMLEFT"); dmB:SetPoint("BOTTOMRIGHT"); PP.Height(dmB, 1)
            local dmL = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmL:SetColorTexture(1,1,1,0.20)
            if dmL.SetSnapToPixelGrid then dmL:SetSnapToPixelGrid(false); dmL:SetTexelSnappingBias(0) end
            dmL:SetPoint("TOPLEFT", dmT, "BOTTOMLEFT"); dmL:SetPoint("BOTTOMLEFT", dmB, "TOPLEFT"); PP.Width(dmL, 1)
            local dmR = defMenu:CreateTexture(nil, "OVERLAY", nil, 7); dmR:SetColorTexture(1,1,1,0.20)
            if dmR.SetSnapToPixelGrid then dmR:SetSnapToPixelGrid(false); dmR:SetTexelSnappingBias(0) end
            dmR:SetPoint("TOPRIGHT", dmT, "BOTTOMRIGHT"); dmR:SetPoint("BOTTOMRIGHT", dmB, "TOPRIGHT"); PP.Width(dmR, 1)
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
            local closeBrd = closeBtn:CreateTexture(nil, "BACKGROUND")
            closeBrd:SetAllPoints()
            closeBrd:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
            PP.DisablePixelSnap(closeBrd)
            local closeFill = closeBtn:CreateTexture(nil, "BORDER")
            PP.Point(closeFill, "TOPLEFT", closeBtn, "TOPLEFT", 1, -1)
            PP.Point(closeFill, "BOTTOMRIGHT", closeBtn, "BOTTOMRIGHT", -1, 1)
            closeFill:SetColorTexture(0.06, 0.08, 0.10, 0.92)
            PP.DisablePixelSnap(closeFill)
            local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
            closeLbl:SetFont(FONT, 16, "")
            closeLbl:SetPoint("CENTER")
            closeLbl:SetText("Done")
            closeLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            closeBtn:SetScript("OnEnter", function()
                closeLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
                closeBrd:SetColorTexture(EG.r, EG.g, EG.b, 1)
            end)
            closeBtn:SetScript("OnLeave", function()
                closeLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
                closeBrd:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
            end)
            popup._closeBtn = closeBtn

            popup:EnableMouse(true)

            dimmer:SetScript("OnMouseDown", function(self)
                if not popup:IsMouseOver() then
                    self:Hide()
                end
            end)

            popup:EnableKeyboard(true)
            popup:SetScript("OnKeyDown", function(self, key)
                if key == "ESCAPE" then
                    self:SetPropagateKeyboardInput(false)
                    dimmer:Hide()
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
            specPopup = popup
        end

        local function ResolvePresetDisplayName(key)
            if not key then return "" end
            if key == "custom" then return "Custom" end
            if key == "ellesmereui" then return "EllesmereUI" end
            if key == "spinthewheel" then return "Spin the Wheel" end
            if key:sub(1, 5) == "user:" then return key:sub(6) end
            return key
        end

        -- Update title with preset name
        local presetName = ResolvePresetDisplayName(presetKey)
        specPopup._title:SetText(titleText or "Assign Preset to Specs")
        if subtitleBuilder then
            specPopup._subtitle:SetText(subtitleBuilder(presetName, presetKey) or "")
        else
            specPopup._subtitle:SetText("Select which specs you want " .. presetName .. " to be assigned to")
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

        local fullMap = db[dbKey] or {}

        local function GetAssignedProfileKey(specID)
            for profileKey, specList in pairs(fullMap) do
                if type(specList) == "table" and specList[specID] then
                    return profileKey
                end
            end
            return nil
        end

        local function SetAssignedProfileKey(specID, targetProfileKey)
            for profileKey, specList in pairs(fullMap) do
                if type(specList) == "table" then
                    specList[specID] = nil
                end
            end

            if targetProfileKey then
                if not fullMap[targetProfileKey] then
                    fullMap[targetProfileKey] = {}
                end
                fullMap[targetProfileKey][specID] = true
            end
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
                hdr._label:SetText(cls.name)
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
                        PP.DisablePixelSnap(boxBg)
                        row._boxBg = boxBg
                        local boxBorder = MakeBorder(box, BORDER_R, BORDER_G, BORDER_B, CB_BRD_A, PP)
                        row._boxBorder = boxBorder
                        local check = box:CreateTexture(nil, "ARTWORK")
                        PP.DisablePixelSnap(check)
                        PP.Point(check, "TOPLEFT", box, "TOPLEFT", CHECK_INSET, -CHECK_INSET)
                        PP.Point(check, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -CHECK_INSET, CHECK_INSET)
                        check:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
                        row._check = check
                        row._box = box

                        local hint = row:CreateFontString(nil, "OVERLAY")
                        hint:SetFont(FONT, 11, "")
                        hint:SetWidth(72)
                        hint:SetJustifyH("RIGHT")
                        PP.Point(hint, "RIGHT", row, "RIGHT", -6, 0)
                        hint:SetTextColor(1, 1, 1, 0.32)
                        row._hint = hint

                        local lbl = row:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT, 17, "")
                        PP.Point(lbl, "LEFT", box, "RIGHT", 8, 0)
                        lbl:SetPoint("RIGHT", hint, "LEFT", -6, 0)
                        lbl:SetJustifyH("LEFT")
                        lbl:SetTextColor(1, 1, 1, 0.65)
                        row._lbl = lbl
                    end
                    PP.Size(row, COL_W, SPEC_H)
                    row:ClearAllPoints()
                    PP.Point(row, "TOPLEFT", col, "TOPLEFT", 0, -yOff)
                    row:Show()

                    row._lbl:SetText(spec.name)
                    row._specID = spec.id
                    row._priorOwner = row._priorOwner or nil

                    local EG = ELLESMERE_GREEN
                    local function UpdateVisual(r, hovered)
                        local assignedProfileKey = GetAssignedProfileKey(r._specID)
                        local assignedProfileName = ResolvePresetDisplayName(assignedProfileKey)

                        r._checked = (assignedProfileKey == presetKey)
                        if r._checked then
                            r._check:Show()
                            r._boxBorder:SetColor(EG.r, EG.g, EG.b, CB_ACT_BRD_A)
                            r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                            r._lbl:SetTextColor(1, 1, 1, hovered and 0.90 or 0.65)
                            if r._priorOwner and r._priorOwner ~= presetKey then
                                r._hint:SetText("Replaces " .. ResolvePresetDisplayName(r._priorOwner))
                                r._hint:SetTextColor(EG.r, EG.g, EG.b, hovered and 0.90 or 0.70)
                            else
                                r._hint:SetText("")
                            end
                        else
                            r._check:Hide()
                            r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
                            r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                            r._lbl:SetTextColor(1, 1, 1, hovered and 0.90 or 0.65)
                            if assignedProfileKey and assignedProfileKey ~= presetKey then
                                r._hint:SetText("Assigned: " .. assignedProfileName)
                                r._hint:SetTextColor(1, 1, 1, hovered and 0.50 or 0.32)
                            else
                                r._hint:SetText("")
                            end
                        end
                    end
                    UpdateVisual(row)
                    allCheckboxes[#allCheckboxes + 1] = row

                    row:SetScript("OnClick", function(self)
                        if self._checked then
                            if self._priorOwner and self._priorOwner ~= presetKey then
                                SetAssignedProfileKey(self._specID, self._priorOwner)
                                self._priorOwner = nil
                            else
                                SetAssignedProfileKey(self._specID, nil)
                            end
                        else
                            local currentOwner = GetAssignedProfileKey(self._specID)
                            if currentOwner and currentOwner ~= presetKey then
                                self._priorOwner = currentOwner
                            else
                                self._priorOwner = nil
                            end
                            SetAssignedProfileKey(self._specID, presetKey)
                        end
                        UpdateVisual(self, true)
                    end)
                    row:SetScript("OnEnter", function(self)
                        UpdateVisual(self, true)
                    end)
                    row:SetScript("OnLeave", function(self)
                        UpdateVisual(self, false)
                    end)

                    yOff = yOff + SPEC_H
                end
            end
        end

        -- Check All / Uncheck All wiring
        specPopup._checkAll:SetScript("OnClick", function()
            for _, row in ipairs(allCheckboxes) do
                if not row._checked then
                    local currentOwner = GetAssignedProfileKey(row._specID)
                    if currentOwner and currentOwner ~= presetKey then
                        row._priorOwner = currentOwner
                    end
                    SetAssignedProfileKey(row._specID, presetKey)
                    if row:GetScript("OnLeave") then
                        row:GetScript("OnLeave")(row)
                    end
                end
            end
        end)
        specPopup._uncheckAll:SetScript("OnClick", function()
            for _, row in ipairs(allCheckboxes) do
                if row._checked then
                    if row._priorOwner and row._priorOwner ~= presetKey then
                        SetAssignedProfileKey(row._specID, row._priorOwner)
                        row._priorOwner = nil
                    else
                        SetAssignedProfileKey(row._specID, nil)
                    end
                    if row:GetScript("OnLeave") then
                        row:GetScript("OnLeave")(row)
                    end
                end
            end
        end)

        -- Default Profile dropdown (populate phase)
        local selectedDefaultKey = defaultKey and db[defaultKey] or nil

        if defaultKey and allPresetKeysFn then
            specPopup._defDDContainer:Show()

            local function DefPresetDisplayName(key)
                return ResolvePresetDisplayName(key)
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
            if onDone then onDone() end
        end)

        specPopup._dimmer:Show()
    end
end
