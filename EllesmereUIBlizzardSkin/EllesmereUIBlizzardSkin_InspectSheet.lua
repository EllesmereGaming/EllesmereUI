-------------------------------------------------------------------------------
--  Themed Inspect Sheet
--  Mirrors the Character Sheet skinning for inspected characters.
--  Shared helpers (EllesmereUI.GetUpgradeTrack, EllesmereUI.GetEnchantText)
--  are exported by CharacterSheet and loaded before this file.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local skinned = false

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

local MP_COLOR_BRACKETS = {
    { 3850, "ff8000" }, { 3695, "f9753f" }, { 3575, "f16961" },
    { 3455, "e75e7f" }, { 3335, "db529c" }, { 3215, "cc47b9" },
    { 3095, "b83dd6" }, { 2965, "9c3eed" }, { 2845, "715be5" },
    { 2725, "2c6dde" }, { 2565, "3b7fcd" }, { 2445, "5292b9" },
    { 2325, "5ca6a4" }, { 2205, "5fba8d" }, { 2085, "5cce75" },
    { 1965, "50e258" }, { 1845, "35f72d" }, { 1725, "3eff26" },
    { 1600, "5eff43" }, { 1475, "74ff58" }, { 1350, "88ff6b" },
    { 1225, "98ff7d" }, { 1100, "a8ff8d" }, { 975,  "b6ff9e" },
    { 850,  "c3ffae" }, { 725,  "cfffbd" }, { 600,  "dbffcd" },
    { 475,  "e7ffdd" }, { 350,  "f2ffec" }, { 225,  "fdfffc" },
    { 200,  "ffffff" },
}

-- Equipment slot lists
local EUI_ALL_SLOTS = {
    "InspectHeadSlot", "InspectNeckSlot", "InspectShoulderSlot", "InspectBackSlot",
    "InspectChestSlot", "InspectShirtSlot", "InspectTabardSlot", "InspectWristSlot",
    "InspectHandsSlot", "InspectWaistSlot", "InspectLegsSlot", "InspectFeetSlot",
    "InspectTrinket0Slot", "InspectTrinket1Slot", "InspectFinger0Slot", "InspectFinger1Slot",
    "InspectMainHandSlot", "InspectSecondaryHandSlot",
}

-- Slot grid layout mapping
local slotGridMap = {
    InspectHeadSlot = {col = 0, row = 0},
    InspectNeckSlot = {col = 0, row = 1},
    InspectShoulderSlot = {col = 0, row = 2},
    InspectBackSlot = {col = 0, row = 3},
    InspectChestSlot = {col = 0, row = 4},
    InspectShirtSlot = {col = 0, row = 5},
    InspectTabardSlot = {col = 0, row = 6},
    InspectWristSlot = {col = 0, row = 7},
    InspectHandsSlot = {col = 1, row = 0},
    InspectWaistSlot = {col = 1, row = 1},
    InspectLegsSlot = {col = 1, row = 2},
    InspectFeetSlot = {col = 1, row = 3},
    InspectFinger0Slot = {col = 1, row = 4},
    InspectFinger1Slot = {col = 1, row = 5},
    InspectTrinket0Slot = {col = 1, row = 6},
    InspectTrinket1Slot = {col = 1, row = 7},
    InspectMainHandSlot = {slot = "MainHand"},
    InspectSecondaryHandSlot = {slot = "SecondaryHand"},
}

-- Slots that can have enchants in current expansion (mirrors CharacterSheet)
local INSPECT_ENCHANT_SLOTS = {
    [INVSLOT_HEAD] = true,
    [INVSLOT_SHOULDER] = true,
    [INVSLOT_BACK] = false,
    [INVSLOT_CHEST] = true,
    [INVSLOT_WRIST] = false,
    [INVSLOT_LEGS] = true,
    [INVSLOT_FEET] = true,
    [INVSLOT_FINGER1] = true,
    [INVSLOT_FINGER2] = true,
    [INVSLOT_MAINHAND] = true,
}

local function EUI_UpdateSlotStyle(slotName, slotID, textOverlayFrame, isRightColumn)
    local slot = _G[slotName]
    if not slot or not textOverlayFrame then return end

    local skipLabels = (slotName == "InspectShirtSlot" or slotName == "InspectTabardSlot")

    local inspectUnit = InspectFrame and InspectFrame.unit
    if not inspectUnit then return end

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
    local itemLink = GetInventoryItemLink(inspectUnit, slotID)
    GetFFD(slot).itemLink = itemLink

    local borderR, borderG, borderB = 0.4, 0.4, 0.4
    if itemLink then
        local rarity = C_Item.GetItemQualityByID(itemLink)
        if rarity then
            borderR, borderG, borderB = C_Item.GetItemQualityColor(rarity)
        end
    end

    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.SetBorderColor(slot, borderR, borderG, borderB, 1)
    end
    GetFFD(slot).border = true

    -- Item level label (font size matches CharacterSheet)
    if itemLink and not GetFFD(slot).iLvlText and not skipLabels then
        local ilvl = select(4, GetItemInfo(itemLink))
        if ilvl and ilvl > 0 then
            local itemLevelSize = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelSize or 11
            local ilvlText = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            ilvlText:SetFont(fontPath, itemLevelSize, "")
            ilvlText:SetTextColor(1, 1, 1, 0.8)
            ilvlText:SetJustifyH("CENTER")

            if slotName == "InspectMainHandSlot" then
                ilvlText:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "InspectSecondaryHandSlot" then
                ilvlText:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            elseif isRightColumn then
                ilvlText:SetPoint("CENTER", slot, "LEFT", -15, 10)
            else
                ilvlText:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            end

            ilvlText:SetText(ilvl)

            local upgradeTrackText, upgradeTrackColor = EllesmereUI.GetUpgradeTrack(itemLink)
            local displayColor
            if EllesmereUIDB and EllesmereUIDB.charSheetItemLevelUseColor and EllesmereUIDB.charSheetItemLevelColor then
                displayColor = EllesmereUIDB.charSheetItemLevelColor
            elseif upgradeTrackText ~= "" and upgradeTrackColor then
                displayColor = upgradeTrackColor
            elseif (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) then
                local _, _, quality = GetItemInfo(itemLink)
                if quality then
                    local r, g, b = GetItemQualityColor(quality)
                    displayColor = { r = r, g = g, b = b }
                end
            end
            displayColor = displayColor or { r = 1, g = 1, b = 1 }
            ilvlText:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.9)

            GetFFD(slot).iLvlText = ilvlText
        end
    end

    -- Enchant label (font size matches CharacterSheet)
    if itemLink and not GetFFD(slot).enchantText and not skipLabels then
        local enchantSize = EllesmereUIDB and EllesmereUIDB.charSheetEnchantSize or 9
        local enchantText = EllesmereUI.GetEnchantText(slotID, inspectUnit)
        local canHaveEnchant = INSPECT_ENCHANT_SLOTS[slotID]
        local inspLvl = UnitLevel(inspectUnit)
        local atEnchantLevel = inspLvl and not (issecretvalue and issecretvalue(inspLvl)) and inspLvl >= 90 or false
        local isMissing = atEnchantLevel and canHaveEnchant and itemLink and (enchantText == "" or not enchantText)
        local hasEnchant = enchantText and enchantText ~= ""

        local iconOnly, tooltipText
        if isMissing then
            iconOnly    = "|A:Professions-ChatIcon-Quality-Tier5:14:14:0:0:229:73:73|a"
            tooltipText = "Enchant missing"
        elseif hasEnchant then
            local icons = {}
            for atlas in enchantText:gmatch("|A:[^|]+|a") do
                icons[#icons + 1] = atlas
            end
            iconOnly    = table.concat(icons, "")
            tooltipText = enchantText:gsub("|A:[^|]+|a", ""):gsub("^%s+", ""):gsub("%s+$", "")
            tooltipText = tooltipText:gsub("^.-%s*%-%s*", "")
        end

        local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowEnchants ~= false)

        if showEnchants and iconOnly and iconOnly ~= "" then
            local enchantLabel = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            enchantLabel:SetFont(fontPath, enchantSize, "")
            enchantLabel:SetTextColor(1, 1, 1, 0.8)

            if slotName == "InspectMainHandSlot" then
                enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            elseif slotName == "InspectSecondaryHandSlot" then
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 5, -5)
            elseif isRightColumn then
                enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            else
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 5, -5)
            end

            enchantLabel:SetText(iconOnly)
            GetFFD(slot).enchantText = enchantLabel

            local hoverFrame = CreateFrame("Frame", nil, textOverlayFrame)
            hoverFrame:SetSize(20, 20)
            hoverFrame:SetFrameLevel(textOverlayFrame:GetFrameLevel() + 20)
            if slotName == "InspectMainHandSlot" then
                hoverFrame:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            elseif slotName == "InspectSecondaryHandSlot" then
                hoverFrame:SetPoint("LEFT", slot, "RIGHT", 5, -5)
            elseif isRightColumn then
                hoverFrame:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            else
                hoverFrame:SetPoint("LEFT", slot, "RIGHT", 5, -5)
            end
            hoverFrame:EnableMouse(true)

            hoverFrame:SetScript("OnEnter", function()
                if tooltipText and tooltipText ~= "" and EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(hoverFrame, tooltipText)
                end
            end)
            hoverFrame:SetScript("OnLeave", function()
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)

            GetFFD(slot).enchantHoverFrame = hoverFrame
        end
    end

    -- Upgrade track label (font size matches CharacterSheet)
    if itemLink and not GetFFD(slot).upgradeText and GetFFD(slot).iLvlText and not skipLabels then
        local upgradeTrackSize = EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackSize or 11
        local upgradeText, upgradeColor = EllesmereUI.GetUpgradeTrack(itemLink)
        if upgradeText and upgradeText ~= "" then
            local upgradeLabel = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            upgradeLabel:SetFont(fontPath, upgradeTrackSize, "")
            upgradeLabel:SetTextColor(upgradeColor.r, upgradeColor.g, upgradeColor.b, 0.8)
            upgradeLabel:SetJustifyH("CENTER")

            if slotName == "InspectMainHandSlot" then
                upgradeLabel:SetPoint("RIGHT", GetFFD(slot).iLvlText, "LEFT", -3, 0)
            elseif slotName == "InspectSecondaryHandSlot" then
                upgradeLabel:SetPoint("LEFT", GetFFD(slot).iLvlText, "RIGHT", 3, 0)
            elseif isRightColumn then
                upgradeLabel:SetPoint("RIGHT", GetFFD(slot).iLvlText, "LEFT", -3, 0)
            else
                upgradeLabel:SetPoint("LEFT", GetFFD(slot).iLvlText, "RIGHT", 3, 0)
            end

            upgradeLabel:SetText("(" .. upgradeText .. ")")
            GetFFD(slot).upgradeText = upgradeLabel
        end
    end
end

-- Apply tab visibility: show labels only on Tab 1
-- Similar to ApplyTabVisibility in CharacterSheet.lua
-- Takes a boolean parameter: true = show labels (Tab 1), false = hide labels (Tab 2/3)
local function ApplyTabVisibility(showLabels)
    local frame = InspectFrame
    if not frame then return end

    -- Show/hide individual labels based on settings
    local showItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowItemLevel ~= false)
    local showUpgradeTrack = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowUpgradeTrack ~= false)
    local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowEnchants ~= false)

    for slotName, _ in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot then
            -- Only show labels if on Tab 1 and settings allow
            if GetFFD(slot).iLvlText then
                GetFFD(slot).iLvlText:SetShown(showLabels and showItemLevel)
            end
            if GetFFD(slot).upgradeText then
                GetFFD(slot).upgradeText:SetShown(showLabels and showUpgradeTrack)
            end
            if GetFFD(slot).enchantText then
                GetFFD(slot).enchantText:SetShown(showLabels and showEnchants)
            end
        end
    end

    -- Hide/show avg ilvl + M+ score
    local frame = InspectFrame
    if frame then
        if GetFFD(frame).avgIlvlText then GetFFD(frame).avgIlvlText:SetShown(showLabels) end
        if GetFFD(frame).mPlusScoreText then GetFFD(frame).mPlusScoreText:SetShown(showLabels) end
    end
end

-- Calculate average item level from inspected player
local function CalculateAverageItemLevel()
    if not InspectFrame or not InspectFrame.unit then
        return 0
    end

    local unit = InspectFrame.unit

    -- Use the proper WoW API for getting inspect item level
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
        if ilvl and ilvl > 0 then
            return ilvl
        end
    end

    return 0
end

local function SkinInspectSheet()
    if skinned then return end
    skinned = true

    local frame = InspectFrame
    if not frame then return end


    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    -- Create custom background texture FIRST before hiding anything
    if GetFFD(frame).bg then
        GetFFD(frame).bg:Show()
    else
        local BG_ASPECT = 561 / 433
        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
        bg:SetAllPoints(frame)
        bg:SetAlpha(1)
        GetFFD(frame).bg = bg
        GetFFD(frame).bgOverlay = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        GetFFD(frame).bgOverlay:SetColorTexture(0, 0, 0, 0.62)
        GetFFD(frame).bgOverlay:SetAllPoints(frame)
        -- Aspect-ratio-preserving cover mode (matches character sheet)
        local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
        local BASE_U = BASE_R - BASE_L
        local BASE_V = BASE_B - BASE_T
        local function UpdateBgTexCoords()
            local fw, fh = frame:GetSize()
            if fw == 0 or fh == 0 then return end
            local frameAspect = fw / fh
            if frameAspect > BG_ASPECT then
                local visV = BASE_V * (BG_ASPECT / frameAspect)
                local trimV = (BASE_V - visV) / 2
                bg:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
            else
                local visU = BASE_U * (frameAspect / BG_ASPECT)
                local trimU = (BASE_U - visU) / 2
                bg:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
            end
        end
        hooksecurefunc(frame, "SetSize", UpdateBgTexCoords)
        hooksecurefunc(frame, "SetWidth", UpdateBgTexCoords)
        hooksecurefunc(frame, "SetHeight", UpdateBgTexCoords)
        UpdateBgTexCoords()
        -- Follows the Character Sheet window's style pick (the two share one
        -- enable + style setting).
        if ns.WSkin and ns.WSkin.AdoptShell then
            ns.WSkin.AdoptShell("charsheet", frame, bg, GetFFD(frame).bgOverlay)
        end
    end

    -- Standard window-reskin border (the AdventureMap_TopBorder atlas texture),
    -- same as the character sheet and every other skinned Blizzard window.
    if ns.WSkin and ns.WSkin.AtlasBorder then ns.WSkin.AtlasBorder(frame) end

    -- Hide Blizzard backgrounds and borders
    for _, elem in ipairs({frame.NineSlice, frame.Background, frame.TitleBg,
                           frame.TopTileStreaks, frame.Portrait, frame.Bg,
                           InspectModelFrameBackgroundOverlay,
                           InspectModelFrameBorderRight, InspectModelFrameBorderLeft,
                           InspectModelFrameBorderBottom, InspectModelFrameBorderTop}) do
        if elem then elem:Hide() end
    end


    -- Hide Blizzard Bg textures (our atlas bg covers everything)
    if InspectFrameBg then InspectFrameBg:SetAlpha(0) end
    if InspectFrameInset and InspectFrameInset.Bg then InspectFrameInset.Bg:SetAlpha(0) end

    -- Create model background (matches character sheet: character-bg.png, no glow/gradient)
    -- Deferred until InspectModelFrame exists (created lazily by Blizzard)
    local function TryCreateModelBg()
        if GetFFD(frame).modelBgFrame then return end
        local myModel = _G.InspectModelFrame
        if not myModel then return end
        local bgFrame = CreateFrame("Frame", nil, myModel)
        bgFrame:SetFrameLevel(math.max(1, myModel:GetFrameLevel() - 1))
        bgFrame:ClearAllPoints()
        -- Match the Character sheet: span the backdrop across the full gear
        -- width (left gear column to right gear column) and down to the model
        -- bottom, so character-bg.png covers the whole gear + model area. The
        -- inspect model sits at Blizzard's default center spot, so its right edge
        -- stops short of the right gear; anchor the right edge to the right gear
        -- column instead. Falls back progressively if the slots are not up yet.
        local headSlot  = _G.InspectHeadSlot
        local handsSlot = _G.InspectHandsSlot
        if headSlot and handsSlot then
            bgFrame:SetPoint("TOPLEFT", headSlot, "TOPLEFT", -8, 10)
            bgFrame:SetPoint("RIGHT", handsSlot, "RIGHT", 8, 0)
            bgFrame:SetPoint("BOTTOM", myModel, "BOTTOM", 0, -18)
        elseif headSlot then
            bgFrame:SetPoint("TOPLEFT", headSlot, "TOPLEFT", -8, 10)
            bgFrame:SetPoint("BOTTOMRIGHT", myModel, "BOTTOMRIGHT", 0, -18)
        else
            bgFrame:SetPoint("TOPLEFT", myModel, "TOPLEFT", -8, 10)
            bgFrame:SetPoint("BOTTOMRIGHT", myModel, "BOTTOMRIGHT", 0, -18)
        end
        local bgTex = bgFrame:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints(bgFrame)
        bgTex:SetTexture("Interface\\AddOns\\EllesmereUIBlizzardSkin\\Media\\character-bg.png")
        bgTex:SetAlpha(1)

        GetFFD(frame).modelBg      = bgTex
        GetFFD(frame).modelBgFrame = bgFrame
    end
    TryCreateModelBg()
    -- Retry on show in case model frame wasn't ready on first skin.
    -- Staggered retries: Blizzard creates InspectModelFrame lazily
    -- after the inspect target is set, which can take multiple frames.
    -- HookScript only once to prevent accumulation on repeated reskins.
    if not GetFFD(frame)._modelBgHooked then
        GetFFD(frame)._modelBgHooked = true
        frame:HookScript("OnShow", function()
            C_Timer.After(0, TryCreateModelBg)
            C_Timer.After(0.2, TryCreateModelBg)
            C_Timer.After(0.5, TryCreateModelBg)
        end)
    end

    -- Hide portrait (separate handling to ensure it's fully hidden)
    if InspectFramePortrait then
        InspectFramePortrait:Hide()
        InspectFramePortrait:SetAlpha(0)
    end

    -- Hide TopTileStreaks explicitly
    if frame.TopTileStreaks then
        frame.TopTileStreaks:Hide()
        frame.TopTileStreaks:SetAlpha(0)
    end

    -- Hide InspectModelScene ControlFrame (similar to CharacterModelScene in CharacterSheet)
    if InspectModelScene then
        if InspectModelScene.ControlFrame then
            InspectModelScene.ControlFrame:SetAlpha(0)
            InspectModelScene.ControlFrame:EnableMouse(false)
        end
    end

    -- Hide individual control buttons and textures
    local controlButtons = {
        "InspectModelFrameControlFrameZoomInButton",
        "InspectModelFrameControlFrameZoomOutButton",
        "InspectModelFrameControlFramePanButton",
        "InspectModelFrameControlFrameRotateLeftButton",
        "InspectModelFrameControlFrameRotateRightButton",
        "InspectModelFrameControlFrameRotateResetButton",
        "InspectModelFrameControlFrameLeft",
        "InspectModelFrameControlFrameMiddle",
        "InspectModelFrameControlFrameRight",
    }
    for _, buttonName in ipairs(controlButtons) do
        local btn = _G[buttonName]
        if btn then
            btn:SetAlpha(0)
            btn:EnableMouse(false)
        end
    end

    -- Hide InspectModelFrameBorder edges and corners explicitly
    for _, border in ipairs({InspectModelFrameBorderBottom, InspectModelFrameBorderLeft,
                             InspectModelFrameBorderTop, InspectModelFrameBorderRight,
                             InspectModelFrameBorderBottomRight, InspectModelFrameBorderBottomLeft,
                             InspectModelFrameBorderTopRight, InspectModelFrameBorderTopLeft,
                             InspectModelFrameBorderBottom2}) do
        if border then
            border:Hide()
            border:SetAlpha(0)
        end
    end

    -- Hide InspectModelFrameBackgroundOverlay explicitly
    if InspectModelFrameBackgroundOverlay then
        InspectModelFrameBackgroundOverlay:Hide()
        InspectModelFrameBackgroundOverlay:SetAlpha(0)
    end

    -- Hide InspectFrameInset.NineSlice (borders) but keep the frame for background
    if InspectFrameInset then
        if InspectFrameInset.NineSlice then
            InspectFrameInset.NineSlice:Hide()
            InspectFrameInset.NineSlice:SetAlpha(0)
        end
    end

    -- Hide InspectModelFrameBackground corners
    for _, corner in ipairs({InspectModelFrameBackgroundTopLeft, InspectModelFrameBackgroundTopRight,
                             InspectModelFrameBackgroundBotLeft, InspectModelFrameBackgroundBotRight}) do
        if corner then
            corner:Hide()
            corner:SetAlpha(0)
        end
    end

    if frame.PaperDollFrame and frame.PaperDollFrame.InnerBorder then
        for _, name in ipairs({"Top", "Bottom", "Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight"}) do
            if frame.PaperDollFrame.InnerBorder[name] then
                frame.PaperDollFrame.InnerBorder[name]:Hide()
            end
        end
    end

    -- Hide PVP Frame background elements. Frames other addons parent in here
    -- are theirs to draw (see WSkin.IsForeignFrame).
    local IsForeign = ns.WSkin and ns.WSkin.IsForeignFrame
    if InspectPVPFrame then
        local numChildren = InspectPVPFrame:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, InspectPVPFrame:GetChildren())
            if child and not child:GetName()
               and not (IsForeign and IsForeign(child, InspectPVPFrame)) then
                child:Hide()
            end
        end
    end

    -- Hide Guild Frame background elements
    if InspectGuildFrame then
        local numChildren = InspectGuildFrame:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, InspectGuildFrame:GetChildren())
            if child and not child:GetName()
               and not (IsForeign and IsForeign(child, InspectGuildFrame)) then
                child:Hide()
            end
        end
    end

    -- Hide unnamed decoration frames in main InspectFrame
    local numChildren = frame:GetNumChildren()
    for i = 1, numChildren do
        local child = select(i, frame:GetChildren())
        if child and not child:GetName() and child:GetObjectType() == "Frame"
           and not (IsForeign and IsForeign(child, frame)) then
            -- Only hide if it's not one of our known frames and not the TitleFrame or title parent
            local isTitleFrame = (frame.TitleFrame and child == frame.TitleFrame)
            local isTitleParent = (_G.inspectFrameTitleText and child == _G.inspectFrameTitleText:GetParent())
            if child ~= frame.PaperDollFrame and child ~= InspectPVPFrame and child ~= InspectGuildFrame
               and not isTitleFrame and not isTitleParent then
                child:Hide()
            end
        end
    end

    -- Add pixel-perfect border to the frame
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(frame, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 7)
    end

    -- Style close button
    local closeBtn = frame.CloseButton or _G.InspectFrameCloseButton
    if closeBtn then
        if closeBtn.SetNormalTexture then closeBtn:SetNormalTexture("") end
        if closeBtn.SetPushedTexture then closeBtn:SetPushedTexture("") end
        if closeBtn.SetHighlightTexture then closeBtn:SetHighlightTexture("") end
        if closeBtn.SetDisabledTexture then closeBtn:SetDisabledTexture("") end

        for i = 1, select("#", closeBtn:GetRegions()) do
            local region = select(i, closeBtn:GetRegions())
            if region and region:IsObjectType("Texture") and region ~= GetFFD(closeBtn).x then
                region:SetAlpha(0)
            end
        end

        if not GetFFD(closeBtn).x then
            local closeX = closeBtn:CreateTexture(nil, "OVERLAY")
            closeX:SetAtlas("uitools-icon-close")
            closeX:SetSize(14, 14)
            closeX:SetPoint("CENTER", -2, 0)
            closeX:SetVertexColor(1, 1, 1, 0.75)
            GetFFD(closeBtn).x = closeX

            closeBtn:HookScript("OnEnter", function()
                if GetFFD(closeBtn).x then GetFFD(closeBtn).x:SetVertexColor(1, 1, 1, 1) end
            end)
            closeBtn:HookScript("OnLeave", function()
                if GetFFD(closeBtn).x then GetFFD(closeBtn).x:SetVertexColor(1, 1, 1, 0.75) end
            end)
        end
    end

    -- Restyle Blizzard's Talents + View (dressing room) buttons in place.
    -- User clicks the actual Blizzard button so the secure handler fires
    -- natively with no addon taint in the call stack.
    do
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
        local BTN_W, BTN_H = 90, 21
        local BTN_Y = 8

        local function RestyleButton(btn, labelText, anchor, anchorPoint, xOff)
            if not btn then return end
            local ffd = GetFFD(btn)
            if ffd.restyled then return end
            ffd.restyled = true

            btn:ClearAllPoints()
            btn:SetPoint(anchor, frame, anchorPoint, xOff, BTN_Y)
            btn:SetSize(BTN_W, BTN_H)
            btn:SetFrameLevel(frame:GetFrameLevel() + 20)

            -- Standard Blizzard-window-skin button look: dark fill + theme
            -- border + hover highlight. WSkin.Button fades the native textures.
            if ns.WSkin and ns.WSkin.Button then ns.WSkin.Button(btn) end

            -- Hide the native label (the View button is a dressing-room icon,
            -- not "Transmog") and draw our own, white like other skinned buttons.
            for _, region in ipairs({ btn:GetRegions() }) do
                if region.GetObjectType and region:GetObjectType() == "FontString" then
                    region:SetTextColor(0, 0, 0, 0)
                end
            end
            local label = btn:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 10, "")
            label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetText(labelText)
            label:SetTextColor(1, 1, 1, 1)
            ffd.label = label

            btn:SetAlpha(1)
            btn:EnableMouse(true)
            btn:Show()
        end

        -- Suppress other unnamed buttons in InspectPaperDollItemsFrame.
        -- Never touch buttons other addons parent in here (theirs to run).
        local paperDollItemsFrame = InspectPaperDollItemsFrame
        if paperDollItemsFrame then
            local IsForeignBtn = ns.WSkin and ns.WSkin.IsForeignFrame
            local talentsBtn = paperDollItemsFrame.InspectTalents
            for i = 1, paperDollItemsFrame:GetNumChildren() do
                local child = select(i, paperDollItemsFrame:GetChildren())
                if child and child:GetObjectType() == "Button" and not child:GetName()
                   and child ~= talentsBtn
                   and not (IsForeignBtn and IsForeignBtn(child, paperDollItemsFrame)) then
                    child:SetAlpha(0)
                    child:EnableMouse(false)
                end
            end
            RestyleButton(talentsBtn, "Talents", "BOTTOMRIGHT", "BOTTOMRIGHT", -7)
        end

        local blizViewBtn = InspectPaperDollFrame and InspectPaperDollFrame.ViewButton
        RestyleButton(blizViewBtn, "Transmog", "BOTTOMLEFT", "BOTTOMLEFT", 10)
    end

    -- Hide slot wrapper frames
    for _, slotName in ipairs(EUI_ALL_SLOTS) do
        local frameName = slotName .. "Frame"
        if _G[frameName] then
            _G[frameName]:Hide()
        end
    end

    -- Show actual slot buttons and style them
    for _, slotName in ipairs(EUI_ALL_SLOTS) do
        local slot = _G[slotName]
        if slot then
            slot:Show()

            -- Hide ALL unnamed Texturen in den Slots (die Dekoration)
            local numRegions = slot:GetNumRegions()
            for i = 1, numRegions do
                local region = select(i, slot:GetRegions())
                if region and region:IsObjectType("Texture") then
                    local regionName = region:GetName()
                    -- Hide nur unnamed Texturen (nicht die Icon)
                    if not regionName or regionName ~= (slotName .. "IconTexture") then
                        region:SetAlpha(0)
                    end
                end
            end

            -- Hide Blizzard border and textures
            if slot.IconBorder then
                slot.IconBorder:Hide()
            end
            if slot.IconOverlay then
                slot.IconOverlay:Hide()
            end
            if slot.IconOverlay2 then
                slot.IconOverlay2:Hide()
            end

            -- Crop icon
            if slot.icon then
                local z = (EllesmereUIDB and EllesmereUIDB.charSheetIconZoom) or 0.07
                slot.icon:SetTexCoord(z, 1 - z, z, 1 - z)
            end

            local normalTexture = _G[slotName .. "NormalTexture"]
            if normalTexture then
                normalTexture:Hide()
            end

            -- Get item rarity for border color
            local itemLink = GetInventoryItemLink("inspect", slot:GetID())
            local borderR, borderG, borderB = 0.4, 0.4, 0.4  -- Default gray
            if itemLink then
                local _, _, rarity = GetItemInfo(itemLink)
                if rarity then
                    borderR, borderG, borderB = C_Item.GetItemQualityColor(rarity)
                end
            end

            -- Add rarity-colored border
            if EllesmereUI and EllesmereUI.PanelPP then
                EllesmereUI.PanelPP.CreateBorder(slot, borderR, borderG, borderB, 1, 2, "OVERLAY", 7)
            end

            local parent = slot:GetParent()
            if parent then
                parent:Show()
            end
        end
    end

    -- Grid layout: 2 columns, 8 rows
    local cellWidth = 280
    local cellHeight = 41
    local gridStartX = 10
    local gridStartY = -60

    -- Create overlay frame for text labels (above items, transparent, no mouse input)
    -- Reuse existing overlay to prevent frame multiplication on repeated reskins
    local textOverlayFrame = GetFFD(frame).textOverlayFrame
    if not textOverlayFrame then
        textOverlayFrame = CreateFrame("Frame", "EUI_InspectSheet_TextOverlay", frame)
        textOverlayFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        textOverlayFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        textOverlayFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
        textOverlayFrame:EnableMouse(false)
        GetFFD(frame).textOverlayFrame = textOverlayFrame
    end
    textOverlayFrame:SetAlpha(GetFFD(frame).textHidden and 0 or 1)
    textOverlayFrame:Show()

    -- Top-left eyeball toggle: temporarily hides all item slot text (item level,
    -- upgrade track, enchants) by alpha-ing the shared overlay. Session-only,
    -- matches the CharacterSheet eyeball. State lives in FFD so it survives the
    -- frequent inspect re-skins (the SetAlpha above re-applies it each pass).
    if not GetFFD(frame).textEyeBtn then
        local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
        local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
        local eyeBtn = CreateFrame("Button", "EUI_InspectSheet_TextEyeBtn", frame)
        eyeBtn:SetSize(20, 20)
        eyeBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -6)
        eyeBtn:SetFrameLevel(frame:GetFrameLevel() + 20)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        eyeTex:SetTexture(GetFFD(frame).textHidden and EYE_INVISIBLE or EYE_VISIBLE)
        eyeBtn:SetScript("OnClick", function()
            local hidden = not GetFFD(frame).textHidden
            GetFFD(frame).textHidden = hidden
            eyeTex:SetTexture(hidden and EYE_INVISIBLE or EYE_VISIBLE)
            if GetFFD(frame).textOverlayFrame then
                GetFFD(frame).textOverlayFrame:SetAlpha(hidden and 0 or 1)
            end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.8)
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, GetFFD(frame).textHidden and "Show Item Text" or "Hide Item Text", { width = 135 })
            end
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        GetFFD(frame).textEyeBtn = eyeBtn
    end

    -- Position slots and style them
    if InspectPaperDollItemsFrame then
        for slotName, gridPos in pairs(slotGridMap) do
            local slot = _G[slotName]
            if slot then
                -- Skip weapon slots (they have no col/row, positioned separately)
                if not gridPos.col then
                    -- Still style them, but don't position
                    local isRightColumn = false
                    EUI_UpdateSlotStyle(slotName, slot:GetID(), textOverlayFrame, isRightColumn)
                else
                    slot:ClearAllPoints()
                    local xOffset = gridStartX + (gridPos.col * cellWidth)
                    local yOffset = gridStartY - (gridPos.row * cellHeight)
                    slot:SetPoint("TOPLEFT", InspectPaperDollItemsFrame, "TOPLEFT", xOffset, yOffset)

                    -- Style the slot with borders, ilvl, enchants (right column = col 1)
                    local isRightColumn = gridPos.col == 1
                    EUI_UpdateSlotStyle(slotName, slot:GetID(), textOverlayFrame, isRightColumn)
                end
            end
        end
    end

    -- Position weapon slots at bottom (matches CharacterSheet pattern --
    -- hardcoded offset, no GetWidth which can return a secret value).
    if InspectMainHandSlot and InspectSecondaryHandSlot then
        InspectMainHandSlot:ClearAllPoints()
        InspectMainHandSlot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 128, 10)
        InspectSecondaryHandSlot:ClearAllPoints()
        InspectSecondaryHandSlot:SetPoint("TOPLEFT", InspectMainHandSlot, "TOPRIGHT", 12, 0)
    end

    -- Average item level + M+ score, centered below the title/level text.
    -- Anchored to frame TOP so they sit below the character info header.
    do
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT

        -- Text overlay frame above model bg and fade
        if not GetFFD(frame).textOverlay then
            local txo = CreateFrame("Frame", nil, frame)
            txo:SetAllPoints(frame)
            txo:SetFrameLevel((_G.InspectModelFrame and _G.InspectModelFrame:GetFrameLevel() or frame:GetFrameLevel()) + 5)
            txo:EnableMouse(false)
            GetFFD(frame).textOverlay = txo
        end
        local txo = GetFFD(frame).textOverlay
        txo:Show()

        if not GetFFD(frame).avgIlvlText then
            local ilvlFS = txo:CreateFontString(nil, "OVERLAY")
            ilvlFS:SetFont(fontPath, 16, "")
            ilvlFS:SetTextColor(0.6, 0.2, 1, 1)
            ilvlFS:SetJustifyH("CENTER")
            ilvlFS:SetPoint("TOP", frame, "TOP", 0, -43)
            GetFFD(frame).avgIlvlText = ilvlFS
        end

        if not GetFFD(frame).mPlusScoreText then
            local mpFS = txo:CreateFontString(nil, "OVERLAY")
            mpFS:SetFont(fontPath, 12, "")
            mpFS:SetTextColor(0.8, 0.8, 0.8, 1)
            mpFS:SetJustifyH("CENTER")
            mpFS:SetPoint("TOP", GetFFD(frame).avgIlvlText, "BOTTOM", 0, -2)
            GetFFD(frame).mPlusScoreText = mpFS
        end

        local avg = CalculateAverageItemLevel()
        if avg and avg > 0 then
            GetFFD(frame).avgIlvlText:SetFormattedText("%.2f", avg)
            GetFFD(frame).avgIlvlText:Show()
        else
            GetFFD(frame).avgIlvlText:Hide()
        end

        local inspectUnit = frame.unit
        local mpScore = 0
        if inspectUnit and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
            local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(inspectUnit)
            if summary and summary.currentSeasonScore then
                mpScore = summary.currentSeasonScore
            end
        end
        if mpScore > 0 then
            local hex = "ffffff"
            for i = 1, #MP_COLOR_BRACKETS do
                if mpScore >= MP_COLOR_BRACKETS[i][1] then
                    hex = MP_COLOR_BRACKETS[i][2]; break
                end
            end
            GetFFD(frame).mPlusScoreText:SetFormattedText("M+ Score: |cff%s%d|r", hex, math.floor(mpScore))
            GetFFD(frame).mPlusScoreText:Show()
        else
            GetFFD(frame).mPlusScoreText:Hide()
        end
    end

    -- Style Tabs (InspectFrameTab1, 2, 3)
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }
    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    local inspTabs = {}
    for i = 1, 3 do
        local tab = _G["InspectFrameTab" .. i]
        if tab then
            inspTabs[#inspTabs + 1] = tab
            -- Remove Blizzard textures
            for j = 1, select("#", tab:GetRegions()) do
                local region = select(j, tab:GetRegions())
                if region and region:IsObjectType("Texture") then
                    region:SetTexture("")
                    if region.SetAtlas then region:SetAtlas("") end
                end
            end

            if tab.Left then tab.Left:SetTexture("") end
            if tab.Middle then tab.Middle:SetTexture("") end
            if tab.Right then tab.Right:SetTexture("") end
            if tab.LeftDisabled then tab.LeftDisabled:SetTexture("") end
            if tab.MiddleDisabled then tab.MiddleDisabled:SetTexture("") end
            if tab.RightDisabled then tab.RightDisabled:SetTexture("") end

            local hl = tab:GetHighlightTexture()
            if hl then hl:SetTexture("") end

            -- Add custom background (matches character sheet tab color)
            if not GetFFD(tab).bg then
                GetFFD(tab).bg = tab:CreateTexture(nil, "BACKGROUND")
                GetFFD(tab).bg:SetAllPoints()
                GetFFD(tab).bg:SetColorTexture(0.043, 0.031, 0.027, 1)
            else
                GetFFD(tab).bg:Show()
                GetFFD(tab).bg:SetColorTexture(0.043, 0.031, 0.027, 1)
            end

            -- Add active highlight
            if not GetFFD(tab).activeHL then
                local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.02)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                GetFFD(tab).activeHL = activeHL
            else
                -- The Blizzard-texture strip loop above clears EVERY one of the
                -- tab's texture regions, including this one, on each re-skin
                -- (inspect re-skins on every INSPECT_READY as data streams in).
                -- Restore the fill, or the active-tab highlight blanks out --
                -- the same reason the background is re-colored above.
                GetFFD(tab).activeHL:SetColorTexture(1, 1, 1, 0.02)
                GetFFD(tab).activeHL:SetBlendMode("ADD")
            end

            -- Replace Blizzard label with custom font
            local blizLabel = tab:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
            tab:SetPushedTextOffset(0, 0)

            if not GetFFD(tab).label then
                local label = tab:CreateFontString(nil, "OVERLAY")
                label:SetFont(fontPath, 9, nil)
                label:SetPoint("CENTER", tab, "CENTER", 0, 0)
                label:SetJustifyH("CENTER")
                label:SetText(labelText)
                GetFFD(tab).label = label

                hooksecurefunc(tab, "SetText", function(_, newText)
                    if newText and label then label:SetText(newText) end
                end)
            end

            -- Add underline for active tab
            if not GetFFD(tab).underline then
                local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
                if EllesmereUI and EllesmereUI.PanelPP and EllesmereUI.PanelPP.DisablePixelSnap then
                    EllesmereUI.PanelPP.DisablePixelSnap(underline)
                    underline:SetHeight(EllesmereUI.PanelPP.mult or 1)
                else
                    underline:SetHeight(1)
                end
                underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                underline:SetColorTexture(EG.r or 0.51, EG.g or 0.784, EG.b or 1, 1)
                if EllesmereUI and EllesmereUI.RegAccent then
                    EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                end
                underline:Hide()
                GetFFD(tab).underline = underline
            else
                -- Same strip-loop restore as activeHL above: re-apply the accent
                -- fill so the active-tab underline does not blank out on re-skin.
                GetFFD(tab).underline:SetColorTexture(EG.r or 0.51, EG.g or 0.784, EG.b or 1, 1)
            end
        end
    end
    if ns.WSkin and ns.WSkin.NormalizeTabRow then ns.WSkin.NormalizeTabRow(inspTabs) end

    -- Update tab visuals on show
    local function UpdateTabVisuals()
        local isTab1 = (frame.selectedTab or 1) == 1

        -- Show model background only on Tab 1
        if GetFFD(frame).modelBg then
            GetFFD(frame).modelBg:SetShown(isTab1)
        end
        if GetFFD(frame).modelBgGlow then
            GetFFD(frame).modelBgGlow:SetShown(isTab1)
        end

        -- Show Talents/Transmog buttons only on Tab 1 (Character sheet)
        if GetFFD(frame).talentsBtn then
            GetFFD(frame).talentsBtn:SetShown(isTab1)
        end
        if GetFFD(frame).transmogBtn then
            GetFFD(frame).transmogBtn:SetShown(isTab1)
        end

        -- Update label visibility with ApplyTabVisibility - only show on Tab 1
        ApplyTabVisibility(isTab1)

        for i = 1, 3 do
            local tab = _G["InspectFrameTab" .. i]
            if tab then
                local isActive = (frame.selectedTab or 1) == i
                -- Ensure background is always visible
                if GetFFD(tab).bg then
                    GetFFD(tab).bg:Show()
                end
                if GetFFD(tab).label then
                    GetFFD(tab).label:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
                end
                if GetFFD(tab).underline then
                    GetFFD(tab).underline:SetShown(isActive)
                end
                if GetFFD(tab).activeHL then
                    GetFFD(tab).activeHL:SetShown(isActive)
                end
            end
        end
    end

    -- Hook to update tabs when they change (once only)
    if frame.HookScript and not GetFFD(frame)._tabHooked then
        GetFFD(frame)._tabHooked = true
        frame:HookScript("OnShow", function()
            UpdateTabVisuals()
        end)

        for i = 1, 3 do
            local tab = _G["InspectFrameTab" .. i]
            if tab then
                tab:HookScript("OnClick", function()
                    UpdateTabVisuals()
                    local isTab1 = (frame.selectedTab or 1) == 1
                    ApplyTabVisibility(isTab1)
                end)
            end
        end
    end

    UpdateTabVisuals()

    -- Scale fully owned by Blizzard (SetScale on secure panels taints
    -- UIParentPanelManager execution context).
    frame:SetFrameStrata("HIGH")

    -- Center the title within the frame (406px wide). Hardcoded to avoid
    -- frame:GetWidth() which can return a secret value and cause taint.
    if frame.TitleContainer then
        frame.TitleContainer:Show()
        frame.TitleContainer:SetAlpha(1)
        frame.TitleContainer:SetFrameStrata("HIGH")
        frame.TitleContainer:SetFrameLevel(20)
        frame.TitleContainer:ClearAllPoints()
        frame.TitleContainer:SetWidth(406)
        frame.TitleContainer:SetPoint("TOP", frame, "TOP", 0, 0)

        for i = 1, frame.TitleContainer:GetNumChildren() do
            local child = select(i, frame.TitleContainer:GetChildren())
            if child and child:GetObjectType() == "FontString" then
                child:SetJustifyH("CENTER")
            end
        end
    end

end

-- Replicates stock Blizzard's Inspect-docks-beside-Character layout, since
-- nothing here pairs the two otherwise and InspectFrame's live model bleeds
-- through CharacterFrame's when they overlap. Docking beside CharacterFrame
-- removes the overlap, so no strata/z-order fight is needed -- a strata write
-- on a protected frame is an insecure, tainting write, so we never do one.
local DOCK_MARGIN = 4

-- InspectFrame can be a protected frame, and a plain ClearAllPoints/SetPoint on
-- a protected frame taints its tree. Reposition through a SecureHandler
-- restricted-environment snippet instead: it executes securely and never
-- taints. The handler is parented to UIParent, so self:GetParent() inside the
-- snippet IS UIParent and the frame anchors relative to UIParent. Combat-gated,
-- since secure repositioning of a protected frame is blocked in combat.
local securePositioner = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local function SecureSetPoint(frame, point, relPoint, x, y)
    if InCombatLockdown() then return false end
    securePositioner:SetFrameRef("f", frame)
    securePositioner:SetAttribute("p", point)
    securePositioner:SetAttribute("rp", relPoint)
    securePositioner:SetAttribute("x", x)
    securePositioner:SetAttribute("y", y)
    securePositioner:Execute([[
        local f = self:GetFrameRef("f")
        if not f then return end
        f:ClearAllPoints()
        f:SetPoint(self:GetAttribute("p"), self:GetParent(), self:GetAttribute("rp"), self:GetAttribute("x"), self:GetAttribute("y"))
    ]])
    return true
end

local function ShifterPinned(name)
    return EllesmereUIDB and EllesmereUIDB.shifterPositions
        and EllesmereUIDB.shifterPositions[name] ~= nil
end

-- Reposition `mover` immediately beside `anchor`, on whichever side has screen
-- room. Room is compared in SCREEN-ABSOLUTE units (each frame's coords
-- normalized through ITS OWN effective scale), so a scaled or edge-pinned anchor
-- never shoves the mover off screen and back into an overlap. A protected mover
-- goes through SecureSetPoint (never a raw SetPoint -> taint); since that only
-- anchors to UIParent, the beside-anchor target is converted to a UIParent-
-- CENTER offset.
local function DockBeside(mover, anchor)
    if not mover or not anchor then return end
    local as  = anchor:GetEffectiveScale() or 1
    local ms  = mover:GetEffectiveScale() or 1
    local ues = UIParent:GetEffectiveScale() or 1
    local wAbs = (mover:GetWidth() or 0) * ms
    local leftRoom  = (anchor:GetLeft() or 0) * as
    local rightRoom = (GetScreenWidth() or 0) * ues - (anchor:GetRight() or 0) * as
    local dockLeft = leftRoom >= wAbs + DOCK_MARGIN * ms or leftRoom >= rightRoom

    if mover:IsProtected() then
        if InCombatLockdown() then return end
        local hAbs = (mover:GetHeight() or 0) * ms
        local absCenterX
        if dockLeft then
            absCenterX = leftRoom - DOCK_MARGIN * ms - wAbs / 2
        else
            absCenterX = (anchor:GetRight() or 0) * as + DOCK_MARGIN * ms + wAbs / 2
        end
        local absCenterY = (anchor:GetTop() or 0) * as - hAbs / 2
        local ucx, ucy = UIParent:GetCenter()
        if ucx and ms > 0 then
            SecureSetPoint(mover, "CENTER", "CENTER",
                (absCenterX - ucx * ues) / ms,
                (absCenterY - ucy * ues) / ms)
        end
    else
        mover:ClearAllPoints()
        if dockLeft then
            mover:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -DOCK_MARGIN, 0)
        else
            mover:SetPoint("TOPLEFT", anchor, "TOPRIGHT", DOCK_MARGIN, 0)
        end
    end
end

-- Each window's pre-dock anchor, captured the first time WE move it so it can be
-- put back once its partner is gone. Keyed in an external table (never written
-- onto the Blizzard frame -> no taint). _ignoreSP guards the SetPoint hooks
-- against our own repositioning.
local _savedPoint = {}
local _moved = {}
local _ignoreSP = false

local function CapturePoint(frame)
    if not frame or _savedPoint[frame] then return end
    local p, rel, rp, x, y = frame:GetPoint(1)
    if p then _savedPoint[frame] = { p, rel, rp, x, y } end
end

local function RestorePoint(frame)
    local p = _savedPoint[frame]
    if not p or not frame then return end
    if frame:IsProtected() then
        -- Secure restore reproduces the native anchor only when it was
        -- UIParent-relative (the usual case for a top-level panel; a nil
        -- relativeTo defaults to the parent, UIParent, inside the snippet).
        if p[2] == nil or p[2] == UIParent then
            SecureSetPoint(frame, p[1], p[3], p[4], p[5])
        end
    else
        frame:ClearAllPoints()
        frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
end

-- Keep the Inspect and Character windows from overlapping while both are open.
-- The INSPECT window is held still and the CHARACTER sheet is the one that docks
-- beside it. If the user has pinned the character sheet with the Shifter, that is
-- respected (it stays put) and the inspect window yields instead; if both are
-- pinned, neither moves.
local function RefreshDock()
    local insp, cf = InspectFrame, _G.CharacterFrame
    if not insp or not cf then return end
    if EllesmereUIDB and (EllesmereUIDB.themedInspectSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end

    if not (insp:IsShown() and cf:IsShown()) then
        _ignoreSP = true
        if _moved[cf]   then _moved[cf]   = nil; RestorePoint(cf);   _savedPoint[cf]   = nil end
        if _moved[insp] then _moved[insp] = nil; RestorePoint(insp); _savedPoint[insp] = nil end
        _ignoreSP = false
        return
    end

    local mover, anchor
    if not ShifterPinned("CharacterFrame") then
        mover, anchor = cf, insp
    elseif not ShifterPinned("InspectFrame") then
        mover, anchor = insp, cf
    else
        return
    end

    _ignoreSP = true
    CapturePoint(mover)
    _moved[mover] = true
    DockBeside(mover, anchor)
    _ignoreSP = false
end

-- Main function to apply themed inspect sheet
local function ApplyThemedInspectSheet()
    if EllesmereUIDB and (EllesmereUIDB.themedInspectSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then
        return
    end

    if InspectFrame then
        SkinInspectSheet()
        -- Show labels on Tab 1
        ApplyTabVisibility((InspectFrame.selectedTab or 1) == 1)
    end
end

-- Persistently hide NineSlice borders
local function EnsureInspectNineSliceHidden()
    if EllesmereUIDB and (EllesmereUIDB.themedInspectSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end
    if not InspectFrame then return end

    local frame = InspectFrame

    -- Hide InspectFrame.NineSlice
    if frame.NineSlice then
        frame.NineSlice:Hide()
        frame.NineSlice:SetAlpha(0)
    end

    -- Hide InspectFrameInset.NineSlice (borders). The inset is left transparent
    -- so the window's modern_blizz bg + 0.62 black overlay show through, matching
    -- the character sheet. Filling it with a solid color stacked a second dark
    -- layer behind the model.
    if InspectFrameInset and InspectFrameInset.NineSlice then
        InspectFrameInset.NineSlice:Hide()
        InspectFrameInset.NineSlice:SetAlpha(0)
    end
end

-- Register with parent addon
if EllesmereUI then
    EllesmereUI.ApplyThemedInspectSheet = ApplyThemedInspectSheet

    -- Register hooks when Blizzard_InspectUI loads (it's load-on-demand,
    -- so InspectFrame doesn't exist at PLAYER_LOGIN)
    local initFrame = CreateFrame("Frame")
    local _inspHooked = false

    local function HookInspectFrame()
        if _inspHooked or not InspectFrame then return end
        _inspHooked = true

        InspectFrame:HookScript("OnShow", function()
            skinned = false
            ApplyThemedInspectSheet()
            RefreshDock()
            C_Timer.After(0.1, function()
                if not InspectFrame or not InspectFrame:IsShown() then return end
                if EllesmereUI._refreshInspectItemLevelVisibility then
                    EllesmereUI._refreshInspectItemLevelVisibility()
                end
                if EllesmereUI._refreshInspectUpgradeTrackVisibility then
                    EllesmereUI._refreshInspectUpgradeTrackVisibility()
                end
                if EllesmereUI._refreshInspectEnchantsVisibility then
                    EllesmereUI._refreshInspectEnchantsVisibility()
                end
            end)
        end)

        InspectFrame:HookScript("OnHide", function()
            skinned = false
            RefreshDock()
        end)

        -- When the inspect window itself moves (Shifter drag, Blizzard relayout),
        -- the docked character sheet follows it, so re-pair on its SetPoint too.
        hooksecurefunc(InspectFrame, "SetPoint", function()
            if not _ignoreSP then RefreshDock() end
        end)

        -- CharacterFrame is core UI, already loaded here (unlike InspectFrame).
        -- OnShow/OnHide re-pair; the SetPoint hook catches Blizzard's own panel
        -- relayout (which otherwise blinks the sheet back to its default spot).
        if _G.CharacterFrame then
            _G.CharacterFrame:HookScript("OnShow", RefreshDock)
            _G.CharacterFrame:HookScript("OnHide", RefreshDock)
            hooksecurefunc(_G.CharacterFrame, "SetPoint", function()
                if not _ignoreSP then RefreshDock() end
            end)
        end

        local nineSliceHiddenFrame = CreateFrame("Frame")
        nineSliceHiddenFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        nineSliceHiddenFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
        nineSliceHiddenFrame:SetScript("OnEvent", function(self, event, ...)
            if InspectFrame and InspectFrame:IsShown() then
                EnsureInspectNineSliceHidden()
            end
        end)

        InspectFrame:HookScript("OnShow", EnsureInspectNineSliceHidden)
    end

    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:RegisterEvent("ADDON_LOADED")
    initFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_LOGIN" then
            HookInspectFrame()
        elseif event == "ADDON_LOADED" and arg1 == "Blizzard_InspectUI" then
            self:UnregisterEvent("ADDON_LOADED")
            HookInspectFrame()
        end
    end)

    -- Function to refresh all slot styles when inspect data changes
    local function RefreshSlotStyles()
        if not InspectPaperDollItemsFrame then return end
        if not InspectFrame then return end
        local textOverlayFrame = GetFFD(InspectFrame).textOverlayFrame
        if not textOverlayFrame then return end

        for slotName, gridPos in pairs(slotGridMap) do
            local slot = _G[slotName]
            if slot then
                -- Hide and clear old labels BEFORE creating new ones
                if GetFFD(slot).iLvlText then
                    GetFFD(slot).iLvlText:Hide()
                    GetFFD(slot).iLvlText = nil
                end
                if GetFFD(slot).enchantText then
                    GetFFD(slot).enchantText:Hide()
                    GetFFD(slot).enchantText = nil
                end
                if GetFFD(slot).enchantHoverFrame then
                    GetFFD(slot).enchantHoverFrame:Hide()
                    GetFFD(slot).enchantHoverFrame = nil
                end
                if GetFFD(slot).upgradeText then
                    GetFFD(slot).upgradeText:Hide()
                    GetFFD(slot).upgradeText = nil
                end

                -- Clear old styling
                GetFFD(slot).border = false
                -- Re-style (right column = col 1)
                local isRightColumn = gridPos.col == 1
                EUI_UpdateSlotStyle(slotName, slot:GetID(), textOverlayFrame, isRightColumn)
            end
        end
        -- Update label visibility after all slots have been styled
        local frame = InspectFrame
        if frame then
            ApplyTabVisibility(InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown())
        end
    end

    -- Also hook to INSPECT_READY to reskin when new inspection data arrives
    local inspectHook = CreateFrame("Frame")
    inspectHook:RegisterEvent("INSPECT_READY")
    inspectHook:SetScript("OnEvent", function(self, event, guid)
        if not InspectFrame or not InspectFrame:IsShown() then return end
        skinned = false
        ApplyThemedInspectSheet()
        EnsureInspectNineSliceHidden()
        RefreshSlotStyles()
        local frame = InspectFrame
        if frame then
            ApplyTabVisibility(InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown())
            -- Apply visibility settings after styling
            if EllesmereUI._refreshInspectItemLevelVisibility then
                EllesmereUI._refreshInspectItemLevelVisibility()
            end
            if EllesmereUI._refreshInspectUpgradeTrackVisibility then
                EllesmereUI._refreshInspectUpgradeTrackVisibility()
            end
            if EllesmereUI._refreshInspectEnchantsVisibility then
                EllesmereUI._refreshInspectEnchantsVisibility()
            end
            if EllesmereUI._refreshInspectAverageItemLevelVisibility then
                EllesmereUI._refreshInspectAverageItemLevelVisibility()
            end
        end
    end)

else
    -- EllesmereUI.Print not available here (EllesmereUI is nil)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error:|r EllesmereUI not found! Themed Inspect Sheet requires EllesmereUI.")
end

-- Initialize defaults
do
    local defaultStamp = CreateFrame("Frame")
    defaultStamp:RegisterEvent("ADDON_LOADED")
    defaultStamp:SetScript("OnEvent", function(self, _, addon)
        if addon ~= "EllesmereUI" then return end
        self:UnregisterAllEvents()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        local defaults = {
            themedInspectSheet = true,
            inspectShowItemLevel = true,
            inspectShowUpgradeTrack = true,
            inspectShowEnchants = true,
        }
        for k, v in pairs(defaults) do
            if EllesmereUIDB[k] == nil then
                EllesmereUIDB[k] = v
            end
        end
    end)
end

-- Function to refresh item level visibility when toggle changes
function EllesmereUI._refreshInspectItemLevelVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then return end

    local showItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowItemLevel ~= false)
    local isTab1 = InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown()

    for slotName, _ in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).iLvlText then
            -- Only show if Tab 1 AND setting is enabled
            GetFFD(slot).iLvlText:SetShown(isTab1 and showItemLevel)
        end
    end
end

-- Function to refresh upgrade track visibility when toggle changes
function EllesmereUI._refreshInspectUpgradeTrackVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then return end

    local showUpgradeTrack = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowUpgradeTrack ~= false)
    local isTab1 = InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown()

    for slotName, _ in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).upgradeText then
            -- Only show if Tab 1 AND setting is enabled
            GetFFD(slot).upgradeText:SetShown(isTab1 and showUpgradeTrack)
        end
    end
end

-- Function to refresh enchants visibility when toggle changes
function EllesmereUI._refreshInspectEnchantsVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then return end

    local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.inspectShowEnchants ~= false)
    local isTab1 = InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown()

    for slotName, _ in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).enchantText then
            -- Only show if Tab 1 AND setting is enabled
            GetFFD(slot).enchantText:SetShown(isTab1 and showEnchants)
        end
    end
end

