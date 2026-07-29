-------------------------------------------------------------------------------
--  EUI_UpgradeCalc_Options.lua
--  Options page for the Upgrade Calculator feature (part of EllesmereUIQoL).
-------------------------------------------------------------------------------

local function GetAddonDB()
    -- Always delegate to the main module so we read from the same profile
    -- slice that persists via EllesmereUIDB (not the wiped EllesmereUIQoLDB).
    if EUIUpgCalc and EUIUpgCalc.GetOptsDB then
        return EUIUpgCalc.GetOptsDB()
    end
    EllesmereUIQoLDB                         = EllesmereUIQoLDB or {}
    EllesmereUIQoLDB.upgradeCalcOpts         = EllesmereUIQoLDB.upgradeCalcOpts or {}
    return EllesmereUIQoLDB.upgradeCalcOpts
end

local function BuildUpgradeCalcPage(pageName, parent, yOffset)
    local W  = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y  = yOffset
    local _, h

    parent._showRowDivider = true

    if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end

    local function LiveRefresh()
        local fr = _G["EUIUpgCalcFrame"]
        if fr and fr:IsShown() and EUIUpgCalc and EUIUpgCalc.PopulateGear then
            EUIUpgCalc.PopulateGear()
        end
    end

    ---------------------------------------------------------------------------
    --  Top action buttons: Open Calculator + Clear Upgrade Cache
    ---------------------------------------------------------------------------
    do
        local BTN_W = 312
        local BTN_H = 38
        local GAP = 40
        local ROW_H = BTN_H + 20
        local rowFrame = CreateFrame("Frame", nil, parent)
        local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
        PP.Size(rowFrame, totalW, ROW_H)
        PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

        local openBtn = CreateFrame("Button", nil, rowFrame)
        PP.Size(openBtn, BTN_W, BTN_H)
        PP.Point(openBtn, "RIGHT", rowFrame, "CENTER", -(GAP / 2), 0)
        openBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
        EllesmereUI.MakeStyledButton(openBtn, "Open Calculator", 14,
            EllesmereUI.WB_COLOURS, function()
                local frame = _G["EUIUpgCalcFrame"]
                if frame then
                    if frame:IsShown() then frame:Hide() else frame:Show() end
                end
            end)

        local clearBtn = CreateFrame("Button", nil, rowFrame)
        PP.Size(clearBtn, BTN_W, BTN_H)
        PP.Point(clearBtn, "LEFT", rowFrame, "CENTER", GAP / 2, 0)
        clearBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
        EllesmereUI.MakeStyledButton(clearBtn, "Clear Upgrade Cache", 14,
            EllesmereUI.WB_COLOURS, function()
                if EUIUpgCalc and EUIUpgCalc.ClearCache then
                    EUIUpgCalc:ClearCache()
                end
            end)

        y = y - ROW_H
    end

    -- Reposition hint
    do
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local infoFrame = CreateFrame("Frame", nil, parent)
        infoFrame:SetSize(parent:GetWidth(), 20)
        infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 10)
        infoFrame._isSpacer = true
        local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
        line1:SetFont(fontPath, 15, "")
        line1:SetTextColor(1, 1, 1, 0.75)
        line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
        line1:SetJustifyH("CENTER")
        line1:SetText(EllesmereUI.L("Reposition this element with Shift+Click and Drag."))
        y = y - 36
    end

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

    -- Row 1: Open with Character Sheet | Window Scale
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Open with Character Sheet",
          tooltip = "Automatically opens and closes the Upgrade Calculator when the Character Sheet is opened or closed.",
          getValue = function() return GetAddonDB().openWithCharSheet or false end,
          setValue = function(v) GetAddonDB().openWithCharSheet = v end },
        { type = "slider", text = "Window Scale", min = 50, max = 150, step = 5,
          getValue = function() return GetAddonDB().uiScale or 100 end,
          setValue = function(v)
              GetAddonDB().uiScale = v
              if EUIUpgCalc and EUIUpgCalc.ApplyScale then
                  EUIUpgCalc.ApplyScale()
              end
          end }
    ); y = y - h

    -- Row 2: Show Fully-Upgraded Items | Hide Crafted Items
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Fully-Upgraded Items",
          tooltip = "Show gear tiles for items already at their maximum item level.",
          getValue = function() return GetAddonDB().showMaxed or false end,
          setValue = function(v) GetAddonDB().showMaxed = v; LiveRefresh() end },
        { type = "toggle", text = "Hide Crafted Items",
          tooltip = "Hide crafted items from the gear tile list.\nCrafted items cannot be upgraded at the Upgrade NPC.",
          getValue = function() return GetAddonDB().hideCrafted or false end,
          setValue = function(v) GetAddonDB().hideCrafted = v; LiveRefresh() end }
    ); y = y - h

    -- Row 3: Slot Groups | Crest Rows
    local SLOT_GROUP_ITEMS = {
        { key = "Armour",    label = "Armour"    },
        { key = "Jewellery", label = "Jewelry"   },
        { key = "Trinkets",  label = "Trinkets"  },
        { key = "Weapons",   label = "Weapons"   },
    }

    local CREST_TRACK_ITEMS = {
        { key = "Adventurer", label = "Adventurer" },
        { key = "Veteran",    label = "Veteran"    },
        { key = "Champion",   label = "Champion"   },
        { key = "Hero",       label = "Hero"       },
        { key = "Myth",       label = "Myth"       },
    }

    local filterRow, filterRowH = W:DualRow(parent, y,
        { type = "dropdown", text = "Slot Groups",
          values = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end },
        { type = "dropdown", text = "Crest Rows",
          values = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end }
    )
    do
        local leftRgn = filterRow._leftRegion
        if leftRgn._control then leftRgn._control:Hide() end
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            leftRgn, 210, leftRgn:GetFrameLevel() + 2,
            SLOT_GROUP_ITEMS,
            function(k)
                local sf = GetAddonDB().slotFilter
                return sf == nil or sf[k] ~= false
            end,
            function(k, v)
                local db = GetAddonDB()
                db.slotFilter = db.slotFilter or {}
                db.slotFilter[k] = v
                LiveRefresh()
            end
        )
        PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
        leftRgn._control = cbDD
        leftRgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end
    do
        local rightRgn = filterRow._rightRegion
        if rightRgn._control then rightRgn._control:Hide() end
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rightRgn, 210, rightRgn:GetFrameLevel() + 2,
            CREST_TRACK_ITEMS,
            function(k)
                local cf = GetAddonDB().crestFilter
                return cf == nil or cf[k] ~= false
            end,
            function(k, v)
                local db = GetAddonDB()
                db.crestFilter = db.crestFilter or {}
                db.crestFilter[k] = v
                LiveRefresh()
            end
        )
        PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = cbDD
        rightRgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end
    y = y - filterRowH

    -- Row 4: Show Earned/Cap Column | Show Still Available Column
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Earned / Cap Column",
          tooltip = "Show the seasonal Earned / Cap column in the crest table.",
          getValue = function() return GetAddonDB().showEarnedCap or false end,
          setValue = function(v) GetAddonDB().showEarnedCap = v; LiveRefresh() end },
        { type = "toggle", text = "Show Still Available Column",
          tooltip = "Show how many crests you can still earn before hitting the season cap (cap minus earned so far).",
          getValue = function() return GetAddonDB().showWeeklyRemaining or false end,
          setValue = function(v) GetAddonDB().showWeeklyRemaining = v; LiveRefresh() end }
    ); y = y - h

    -- Row 5: Show Calc Button on Character Sheet | Open with Crest Upgrader
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Calc Button on Character Sheet",
          tooltip = "Adds a Calc toggle button to the character sheet that opens and closes the Upgrade Calculator.",
          getValue = function() return GetAddonDB().showCalcButton or false end,
          setValue = function(v) GetAddonDB().showCalcButton = v end },
        { type = "toggle", text = "Open with Crest Upgrader",
          tooltip = "Automatically opens the Upgrade Calculator when the Crest Upgrade NPC window is opened.",
          getValue = function() return GetAddonDB().openWithUpgrader or false end,
          setValue = function(v) GetAddonDB().openWithUpgrader = v end }
    ); y = y - h

    _, h = W:Spacer(parent, y, 20); y = y - h

    parent:SetHeight(math.abs(y - yOffset))

    return math.abs(y)
end

-- Open/close with Character Sheet hook
local _charSheetHooked = false
local function HookCharacterSheet()
    if _charSheetHooked then return end
    if not CharacterFrame then return end
    _charSheetHooked = true
    CharacterFrame:HookScript("OnShow", function()
        if GetAddonDB().openWithCharSheet then
            local fr = _G["EUIUpgCalcFrame"]
            if fr and not fr:IsShown() then fr:Show() end
        end
    end)
    CharacterFrame:HookScript("OnHide", function()
        if GetAddonDB().openWithCharSheet then
            local fr = _G["EUIUpgCalcFrame"]
            if fr and fr:IsShown() then fr:Hide() end
        end
    end)
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    HookCharacterSheet()
end)

-- Expose page builder for EUI_QoL_Options.lua
_G._EUI_BuildUpgradeCalcPage = BuildUpgradeCalcPage

-- Expose reset helper for QoL onReset
_G._EUI_ResetUpgradeCalc = function()
    if EUIUpgCalc and EUIUpgCalc.GetOptsDB then
        local opts = EUIUpgCalc.GetOptsDB()
        for k in pairs(opts) do opts[k] = nil end
    elseif EllesmereUIQoLDB then
        EllesmereUIQoLDB.upgradeCalcOpts = {}
    end
    if EUIUpgCalc and EUIUpgCalc.ClearCache then
        EUIUpgCalc:ClearCache()
    end
    -- Also wipe the persisted queue and crest manual-add offsets.
    if EUIUpgCalc and EUIUpgCalc.GetOptsDB then
        local db = EUIUpgCalc.GetCalcDB and EUIUpgCalc.GetCalcDB()
        if db then db.queue = {}; db.crestManualAdds = {} end
    end
end
