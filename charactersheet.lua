--------------------------------------------------------------------------------
--  Themed Character Sheet
--------------------------------------------------------------------------------

local ADDON_NAME = ...
local skinned = false
local activeEquipmentSetID = nil  -- Track currently equipped set

-- Apply EUI theme to character sheet frame
local function SkinCharacterSheet()
    if skinned then return end
    skinned = true

    local frame = CharacterFrame
    if not frame then return end

    -- Hide Blizzard decorations
    if CharacterFrame.NineSlice then CharacterFrame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.Background then frame.Background:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end
    if frame.Portrait then frame.Portrait:Hide() end
    if CharacterFramePortrait then CharacterFramePortrait:Hide() end
    if CharacterFrameBg then CharacterFrameBg:Hide() end
    if CharacterModelFrameBackgroundOverlay then CharacterModelFrameBackgroundOverlay:Hide() end
    if CharacterModelFrameBackgroundTopLeft then CharacterModelFrameBackgroundTopLeft:Hide() end
    if CharacterModelFrameBackgroundBotLeft then CharacterModelFrameBackgroundBotLeft:Hide() end
    if CharacterModelFrameBackgroundTopRight then CharacterModelFrameBackgroundTopRight:Hide() end
    if CharacterModelFrameBackgroundBotRight then CharacterModelFrameBackgroundBotRight:Hide() end
    if CharacterFrameInsetRight then
        if CharacterFrameInsetRight.NineSlice then CharacterFrameInsetRight.NineSlice:Hide() end
        CharacterFrameInsetRight:ClearAllPoints()
        CharacterFrameInsetRight:SetPoint("TOPLEFT", frame, "TOPLEFT", 500, -500)
    end
    if CharacterFrameInsetBG then CharacterFrameInsetBG:Hide() end
    if CharacterFrameInset and CharacterFrameInset.NineSlice then
        for _, edge in ipairs({"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner"}) do
            if CharacterFrameInset.NineSlice[edge] then
                CharacterFrameInset.NineSlice[edge]:Hide()
            end
        end
    end
    -- Add colored backgrounds to CharacterFrameInset (EUI FriendsList style)
    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05
    if CharacterFrameInset then
        if CharacterFrameInset.AbsBg then
            CharacterFrameInset.AbsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
        end
        if CharacterFrameInset.Bg then
            CharacterFrameInset.Bg:SetColorTexture(0.02, 0.02, 0.025, 1)  -- Darker for ScrollBox
        end
    end

    if CharacterModelScene then
        CharacterModelScene:Show()
        CharacterModelScene:ClearAllPoints()
        CharacterModelScene:SetPoint("TOPLEFT", frame, "TOPLEFT", 110, -60)
        CharacterModelScene:SetFrameLevel(2)

        -- Hide control frame (zoom, rotation buttons)
        if CharacterModelScene.ControlFrame then
            CharacterModelScene.ControlFrame:Hide()
        end
    end

    -- Center the level text under character name
    if CharacterLevelText and CharacterFrameTitleText then
        CharacterLevelText:ClearAllPoints()
        CharacterLevelText:SetPoint("TOP", CharacterFrameTitleText, "BOTTOM", 0, -5)
        CharacterLevelText:SetJustifyH("CENTER")
    end

    -- Hide model control help text
    if CharacterModelFrameHelpText then CharacterModelFrameHelpText:Hide() end

    if CharacterFrameInsetBG then CharacterFrameInsetBG:Hide() end
    if CharacterFrameInset and CharacterFrameInset.NineSlice then
        for _, edge in ipairs({"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner"}) do
            if CharacterFrameInset.NineSlice[edge] then
                CharacterFrameInset.NineSlice[edge]:Hide()
            end
        end
    end


    -- Hide PaperDoll borders (Blizzard's outer window frame)
    if frame.PaperDollFrame then
        if frame.PaperDollFrame.InnerBorder then
            for _, name in ipairs({"Top", "Bottom", "Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight"}) do
                if frame.PaperDollFrame.InnerBorder[name] then
                    frame.PaperDollFrame.InnerBorder[name]:Hide()
                end
            end
        end
    end

    -- Hide all PaperDollInnerBorder textures
    for _, name in ipairs({"TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "Left", "Right", "Bottom2"}) do
        if _G["PaperDollInnerBorder" .. name] then
            _G["PaperDollInnerBorder" .. name]:Hide()
        end
    end

    if PaperDollItemsFrame then PaperDollItemsFrame:Hide() end
    if CharacterStatPane then
        -- Hide ClassBackground
        if CharacterStatPane.ClassBackground then
            CharacterStatPane.ClassBackground:Hide()
        end
        -- Move CharacterStatPane off-screen
        CharacterStatPane:ClearAllPoints()
        CharacterStatPane:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -500)
    end

    -- Hide secondary hand slot extra element for testing
    if _G["CharacterSecondaryHandSlot.26129b81ae0"] then
        _G["CharacterSecondaryHandSlot.26129b81ae0"]:Hide()
    end


    -- Hide all SlotFrame wrapper containers (Frame versions)
    _G.CharacterBackSlotFrame:Hide()
    _G.CharacterChestSlotFrame:Hide()
    _G.CharacterFeetSlotFrame:Hide()
    _G.CharacterFinger0SlotFrame:Hide()
    _G.CharacterFinger1SlotFrame:Hide()
    _G.CharacterHandsSlotFrame:Hide()
    _G.CharacterHeadSlotFrame:Hide()
    _G.CharacterLegsSlotFrame:Hide()
    _G.CharacterMainHandSlotFrame:Hide()
    _G.CharacterNeckSlotFrame:Hide()
    _G.CharacterSecondaryHandSlotFrame:Hide()
    _G.CharacterShirtSlotFrame:Hide()
    _G.CharacterShoulderSlotFrame:Hide()
    _G.CharacterTabardSlotFrame:Hide()
    _G.CharacterTrinket0SlotFrame:Hide()
    _G.CharacterTrinket1SlotFrame:Hide()
    _G.CharacterWaistSlotFrame:Hide()
    _G.CharacterWristSlotFrame:Hide()

    -- 2-Column layout from CharacterSheetINSPO (exact placement)
    local vpad = 5
    local hpad = 8

    -- Reparent all slots to CharacterFrame so they're visible even when SlotFrames are hidden
    local slotNames = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
        "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }
    for _, slotName in ipairs(slotNames) do
        local slot = _G[slotName]
        if slot then
            slot:SetParent(frame)
            slot:Show()
        end
    end

    -- All slots on the left (under head) are tied back to this slot
    _G.CharacterHeadSlot:ClearAllPoints()
    _G.CharacterHeadSlot:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -60)
    _G.CharacterNeckSlot:ClearAllPoints()
    _G.CharacterNeckSlot:SetPoint("TOPLEFT", _G.CharacterHeadSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterShoulderSlot:ClearAllPoints()
    _G.CharacterShoulderSlot:SetPoint("TOPLEFT", _G.CharacterNeckSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterBackSlot:ClearAllPoints()
    _G.CharacterBackSlot:SetPoint("TOPLEFT", _G.CharacterShoulderSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterChestSlot:ClearAllPoints()
    _G.CharacterChestSlot:SetPoint("TOPLEFT", _G.CharacterBackSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterShirtSlot:ClearAllPoints()
    _G.CharacterShirtSlot:SetPoint("TOPLEFT", _G.CharacterChestSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterTabardSlot:ClearAllPoints()
    _G.CharacterTabardSlot:SetPoint("TOPLEFT", _G.CharacterShirtSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterWristSlot:ClearAllPoints()
    _G.CharacterWristSlot:SetPoint("TOPLEFT", _G.CharacterTabardSlot, "BOTTOMLEFT", 0, -vpad)

    -- All slots on the right (under hands) are tied back to this slot
    _G.CharacterHandsSlot:ClearAllPoints()
    _G.CharacterHandsSlot:SetPoint("TOPLEFT", frame, "TOPLEFT", 380 + hpad, -60)
    _G.CharacterWaistSlot:ClearAllPoints()
    _G.CharacterWaistSlot:SetPoint("TOPLEFT", _G.CharacterHandsSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterLegsSlot:ClearAllPoints()
    _G.CharacterLegsSlot:SetPoint("TOPLEFT", _G.CharacterWaistSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterFeetSlot:ClearAllPoints()
    _G.CharacterFeetSlot:SetPoint("TOPLEFT", _G.CharacterLegsSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterFinger0Slot:ClearAllPoints()
    _G.CharacterFinger0Slot:SetPoint("TOPLEFT", _G.CharacterFeetSlot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterFinger1Slot:ClearAllPoints()
    _G.CharacterFinger1Slot:SetPoint("TOPLEFT", _G.CharacterFinger0Slot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterTrinket0Slot:ClearAllPoints()
    _G.CharacterTrinket0Slot:SetPoint("TOPLEFT", _G.CharacterFinger1Slot, "BOTTOMLEFT", 0, -vpad)
    _G.CharacterTrinket1Slot:ClearAllPoints()
    _G.CharacterTrinket1Slot:SetPoint("TOPLEFT", _G.CharacterTrinket0Slot, "BOTTOMLEFT", 0, -vpad)

    -- Weapons (main and secondary hand)
    _G.CharacterMainHandSlot:ClearAllPoints()
    _G.CharacterMainHandSlot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 180, 15)
    _G.CharacterSecondaryHandSlot:ClearAllPoints()
    _G.CharacterSecondaryHandSlot:SetPoint("TOPLEFT", _G.CharacterMainHandSlot, "TOPRIGHT", hpad, 0)

    -- Hide special regions on weapon slots
    select(16, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    select(17, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    select(16, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    select(17, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)

    -- Show all slots with blending
    local slotNames = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
        "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }
    for _, slotName in ipairs(slotNames) do
        local slot = _G[slotName]
        if slot then
            slot:Show()
            if slot._slotBg then
                slot._slotBg:SetBlendMode("BLEND")
            end
        end
    end

    -- Apply scale if saved
    local scale = EllesmereUIDB and EllesmereUIDB.themedCharacterSheetScale or 1
    frame:SetScale(scale)

    -- Raise frame strata for visibility
    frame:SetFrameStrata("HIGH")

    -- Resize frame to be wider
    -- Resize frame and hook to keep the size
    local origW = frame:GetWidth()
    local origH = frame:GetHeight()
    local newWidth = origW + 360
    local newHeight = origH + 50
    frame:SetWidth(newWidth)
    frame:SetHeight(newHeight)

    -- Hook SetWidth to prevent Blizzard from changing it back
    hooksecurefunc(frame, "SetWidth", function(self, w)
        if w ~= newWidth then
            self:SetWidth(newWidth)
        end
    end)

    -- Hook SetHeight to prevent Blizzard from changing it back
    hooksecurefunc(frame, "SetHeight", function(self, h)
        if h ~= newHeight then
            self:SetHeight(newHeight)
        end
    end)

    -- Strip textures from frame regions
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end

    -- Add custom background with EUI colors (same as FriendsFrame)
    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    -- Main frame background at BACKGROUND layer -8
    frame._ebsBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
    frame._ebsBg:SetAllPoints()
    frame._ebsBg:SetAlpha(1)

    -- Create dark gray border using PP.CreateBorder
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(frame, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 7)
    end

    -- Skin close button
    local closeBtn = frame.CloseButton or _G.CharacterFrameCloseButton
    if closeBtn then
        -- Strip button textures
        if closeBtn.SetNormalTexture then closeBtn:SetNormalTexture("") end
        if closeBtn.SetPushedTexture then closeBtn:SetPushedTexture("") end
        if closeBtn.SetHighlightTexture then closeBtn:SetHighlightTexture("") end
        if closeBtn.SetDisabledTexture then closeBtn:SetDisabledTexture("") end

        -- Strip texture regions
        for i = 1, select("#", closeBtn:GetRegions()) do
            local region = select(i, closeBtn:GetRegions())
            if region and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end

        -- Get font path for close button
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

        -- Create X text
        closeBtn._ebsX = closeBtn:CreateFontString(nil, "OVERLAY")
        closeBtn._ebsX:SetFont(fontPath, 14, "")
        closeBtn._ebsX:SetText("x")
        closeBtn._ebsX:SetTextColor(1, 1, 1, 0.5)
        closeBtn._ebsX:SetPoint("CENTER", -2, -3)

        -- Hover effect
        closeBtn:HookScript("OnEnter", function()
            if closeBtn._ebsX then closeBtn._ebsX:SetTextColor(1, 1, 1, 0.9) end
        end)
        closeBtn:HookScript("OnLeave", function()
            if closeBtn._ebsX then closeBtn._ebsX:SetTextColor(1, 1, 1, 0.5) end
        end)
    end

    -- Restyle character frame tabs (matching FriendsFrame pattern)
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }

    for i = 1, 3 do
        local tab = _G["CharacterFrameTab" .. i]
        if tab then
            -- Strip Blizzard's tab textures
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

            -- Dark background
            if not tab._ebsBg then
                tab._ebsBg = tab:CreateTexture(nil, "BACKGROUND")
                tab._ebsBg:SetAllPoints()
                tab._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
            end

            -- Active highlight
            if not tab._activeHL then
                local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.05)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                tab._activeHL = activeHL
            end

            -- Hide Blizzard's label and use our own
            local blizLabel = tab:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
            tab:SetPushedTextOffset(0, 0)

            if not tab._label then
                local label = tab:CreateFontString(nil, "OVERLAY")
                label:SetFont(fontPath, 9, "")
                label:SetPoint("CENTER", tab, "CENTER", 0, 0)
                label:SetJustifyH("CENTER")
                label:SetText(labelText)
                tab._label = label
                -- Sync our label when Blizzard updates the text
                hooksecurefunc(tab, "SetText", function(_, newText)
                    if newText and label then label:SetText(newText) end
                end)
            end

            -- Accent underline (pixel-perfect)
            if not tab._underline then
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
                tab._underline = underline
            end
        end
    end

    -- Hook to update tab visuals when selection changes
    local function UpdateTabVisuals()
        for i = 1, 3 do
            local tab = _G["CharacterFrameTab" .. i]
            if tab then
                -- PanelTemplates_GetSelectedTab doesn't work reliably, use frame's attribute
                local isActive = (frame.selectedTab or 1) == i
                if tab._label then
                    tab._label:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
                end
                if tab._underline then
                    tab._underline:SetShown(isActive)
                end
                if tab._activeHL then
                    tab._activeHL:SetShown(isActive)
                end
            end
        end
    end

    -- Hook Blizzard's tab selection to update our visuals and show/hide slots
    hooksecurefunc("PanelTemplates_SetTab", function(panel)
        if panel == frame then
            UpdateTabVisuals()

            -- Show slots only on tab 1 (Character tab)
            local isCharacterTab = (frame.selectedTab or 1) == 1
            if frame._themedSlots then
                for _, slotName in ipairs(frame._themedSlots) do
                    local slot = _G[slotName]
                    if slot then
                        if isCharacterTab then
                            slot:Show()
                            if slot._itemLevelLabel then slot._itemLevelLabel:Show() end
                            if slot._enchantLabel then slot._enchantLabel:Show() end
                            if slot._upgradeTrackLabel then slot._upgradeTrackLabel:Show() end
                        else
                            slot:Hide()
                            if slot._itemLevelLabel then slot._itemLevelLabel:Hide() end
                            if slot._enchantLabel then slot._enchantLabel:Hide() end
                            if slot._upgradeTrackLabel then slot._upgradeTrackLabel:Hide() end
                        end
                    end
                end
            end

            -- Show/hide custom buttons based on tab
            for _, btnName in ipairs({"EUI_CharSheet_Stats", "EUI_CharSheet_Titles", "EUI_CharSheet_Equipment"}) do
                local btn = _G[btnName]
                if btn then
                    if isCharacterTab then
                        btn:Show()
                    else
                        btn:Hide()
                    end
                end
            end

            -- Show/hide stats panel and titles panel based on tab
            if frame._statsPanel then
                if isCharacterTab then
                    frame._statsPanel:Show()
                else
                    frame._statsPanel:Hide()
                end
            end

            if frame._titlesPanel then
                if not isCharacterTab then
                    frame._titlesPanel:Hide()
                end
            end

            if frame._equipPanel then
                if not isCharacterTab then
                    frame._equipPanel:Hide()
                end
            end

            if frame._socketContainer then
                if not isCharacterTab then
                    frame._socketContainer:Hide()
                else
                    frame._socketContainer:Show()
                end
            end
        end
    end)
    UpdateTabVisuals()

    -- Create custom stats panel with scroll
    local statsPanel = CreateFrame("Frame", "EUI_CharSheet_StatsPanel", frame)
    statsPanel:SetSize(220, 340)  -- Limited to window height
    statsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 452, -90)
    statsPanel:SetFrameLevel(50)

    -- Stats panel background
    local statsBg = statsPanel:CreateTexture(nil, "BACKGROUND")
    statsBg:SetColorTexture(0.03, 0.045, 0.05, 0.95)
    statsBg:SetAllPoints()

    -- Itemlevel display
    local iLvlText = statsPanel:CreateFontString(nil, "OVERLAY")
    iLvlText:SetFont(fontPath, 20, "")
    iLvlText:SetPoint("TOP", statsPanel, "TOP", 0, 60)
    iLvlText:SetTextColor(0.6, 0.2, 1, 1)

    -- Function to update itemlevel
    local function UpdateItemLevelDisplay()
        local avgItemLevel, avgItemLevelEquipped = GetAverageItemLevel()

        -- Format with two decimals
        local avgFormatted = format("%.2f", avgItemLevel)
        local avgEquippedFormatted = format("%.2f", avgItemLevelEquipped)

        -- Display format: equipped / average
        iLvlText:SetText(format("%s / %s", avgEquippedFormatted, avgFormatted))
    end

    -- Create update frame for itemlevel
    local iLvlUpdateFrame = CreateFrame("Frame")
    iLvlUpdateFrame:SetScript("OnUpdate", function()
        UpdateItemLevelDisplay()
    end)

    UpdateItemLevelDisplay()

    --[[ Stats panel border
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(statsPanel, 0.15, 0.15, 0.15, 1, 1, "OVERLAY", 1)
    end
    ]]--

    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_ScrollFrame", statsPanel)
    scrollFrame:SetSize(260, 320)
    scrollFrame:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 5, -10)
    scrollFrame:SetFrameLevel(51)

    -- Create scroll child
    local scrollChild = CreateFrame("Frame", "EUI_CharSheet_ScrollChild", scrollFrame)
    scrollChild:SetWidth(200)
    scrollFrame:SetScrollChild(scrollChild)

    -- Create scrollbar
    local scrollBar = CreateFrame("Slider", "EUI_CharSheet_ScrollBar", statsPanel, "BackdropTemplate")
    scrollBar:SetSize(8, 320)
    scrollBar:SetPoint("TOPRIGHT", statsPanel, "TOPRIGHT", -5, -10)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = nil })
    scrollBar:SetBackdropColor(0.1, 0.1, 0.1, 0.5)

    -- Scrollbar thumb
    local scrollBarThumb = scrollBar:GetThumbTexture()
    if scrollBarThumb then
        scrollBarThumb:SetTexture("Interface/Buttons/UI-SliderBar-Button-Horizontal")
        scrollBarThumb:SetSize(8, 20)
    end

    -- Scroll handler
    scrollBar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    -- Update scrollbar visibility
    scrollChild:SetScript("OnSizeChanged", function()
        local scrollHeight = scrollChild:GetHeight()
        local viewHeight = scrollFrame:GetHeight()
        if scrollHeight > viewHeight then
            scrollBar:SetMinMaxValues(0, scrollHeight - viewHeight)
            scrollBar:Show()
        else
            scrollBar:SetValue(0)
            scrollBar:Hide()
        end
    end)

    -- Enable mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local newVal = scrollBar:GetValue() - (delta * 20)
        newVal = math.max(minVal, math.min(maxVal, newVal))
        scrollBar:SetValue(newVal)
    end)

    -- Helper function to get crest values
    local function GetCrestValue(currencyID)
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if info then
                return info.quantity or 0
            end
        end
        return 0
    end

    -- Define stat sections with colors
    local statSections = {
        {
            title = "Attributes",
            color = { r = 0.047, g = 0.824, b = 0.616 },  -- Teal
            stats = {
                { name = "Intellect", func = function() return UnitStat("player", 4) end },
                { name = "Stamina", func = function() return UnitStat("player", 3) end },
                { name = "Health", func = function() return UnitHealthMax("player") end },
            }
        },
        {
            title = "Secondary Stats",
            color = { r = 0.471, g = 0.255, b = 0.784 },  -- Purple
            stats = {
                { name = "Crit", func = function() return GetCritChance("player") or 0 end, format = "%.2f%%" },
                { name = "Haste", func = function() return UnitSpellHaste("player") or 0 end, format = "%.2f%%" },
                { name = "Mastery", func = function() return GetMasteryEffect() or 0 end, format = "%.2f%%" },
                { name = "Versatility", func = function() return GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0 end, format = "%.2f%%" },
            }
        },
        {
            title = "Attack",
            color = { r = 1, g = 0.353, b = 0.122 },  -- Orange
            stats = {
                { name = "Spell Power", func = function() return GetSpellBonusDamage(7) end },
                { name = "Attack Speed", func = function() return UnitAttackSpeed("player") or 0 end, format = "%.2f" },
            }
        },
        {
            title = "Defense",
            color = { r = 0.247, g = 0.655, b = 1 },  -- Blue
            stats = {
                { name = "Armor", func = function() local base, effectiveArmor = UnitArmor("player") return effectiveArmor end },
                { name = "Dodge", func = function() return GetDodgeChance() or 0 end, format = "%.2f%%" },
                { name = "Parry", func = function() return GetParryChance() or 0 end, format = "%.2f%%" },
            }
        },
        {
            title = "Crests",
            color = { r = 1, g = 0.784, b = 0.341 },  -- Gold
            stats = {
                { name = "Myth", func = function() return GetCrestValue(3347) end, format = "%d" },  -- Myth Dawncrest
                { name = "Hero", func = function() return GetCrestValue(3345) end, format = "%d" },  -- Hero Dawncrest
                { name = "Champion", func = function() return GetCrestValue(3344) end, format = "%d" },  -- Champion Dawncrest
                { name = "Veteran", func = function() return GetCrestValue(3341) end, format = "%d" },  -- Veteran Dawncrest
                { name = "Adventurer", func = function() return GetCrestValue(3391) end, format = "%d" },  -- Adventurer Dawncrest
            }
        }
    }

    frame._statsPanel = statsPanel
    frame._statsValues = {}
    frame._statsSections = {}  -- Store sections for collapse/expand

    -- Function to recalculate all section positions
    local function RecalculateSectionPositions()
        local yOffset = 0
        for _, sectionData in ipairs(frame._statsSections) do
            local sectionHeight = sectionData.isCollapsed and 16 or sectionData.height
            sectionData.container:ClearAllPoints()
            sectionData.container:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
            sectionData.container:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, yOffset)
            sectionData.container:SetHeight(sectionHeight)
            yOffset = yOffset - sectionHeight - 16
        end
        scrollChild:SetHeight(-yOffset)
    end
    frame._recalculateSections = RecalculateSectionPositions

    -- Create sections in scroll child
    local yOffset = 0
    for sectionIdx, section in ipairs(statSections) do
        -- Section container
        local sectionContainer = CreateFrame("Frame", nil, scrollChild)
        sectionContainer:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        sectionContainer:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, yOffset)
        sectionContainer:SetWidth(260)

        -- Container for title and bars (clickable)
        local titleContainer = CreateFrame("Button", nil, sectionContainer)
        titleContainer:SetPoint("TOP", sectionContainer, "TOPLEFT", 100, 0)
        titleContainer:SetSize(200, 16)
        titleContainer:RegisterForClicks("LeftButtonUp")

        -- Section title (centered in container)
        local sectionTitle = titleContainer:CreateFontString(nil, "OVERLAY")
        sectionTitle:SetFont(fontPath, 13, "")
        sectionTitle:SetTextColor(section.color.r, section.color.g, section.color.b, 1)
        sectionTitle:SetPoint("CENTER", titleContainer, "CENTER", 0, 0)
        sectionTitle:SetText(section.title)

        -- Left bar (from left edge of container to text)
        local leftBar = titleContainer:CreateTexture(nil, "ARTWORK")
        leftBar:SetColorTexture(section.color.r, section.color.g, section.color.b, 0.8)
        leftBar:SetPoint("LEFT", titleContainer, "LEFT", 0, 0)
        leftBar:SetPoint("RIGHT", sectionTitle, "LEFT", -8, 0)
        leftBar:SetHeight(2)

        -- Right bar (from text to right edge of container)
        local rightBar = titleContainer:CreateTexture(nil, "ARTWORK")
        rightBar:SetColorTexture(section.color.r, section.color.g, section.color.b, 0.8)
        rightBar:SetPoint("LEFT", sectionTitle, "RIGHT", 8, 0)
        rightBar:SetPoint("RIGHT", titleContainer, "RIGHT", 0, 0)
        rightBar:SetHeight(2)

        local statYOffset = -22

        -- Store section data for collapse/expand
        local sectionData = {
            title = titleContainer,
            container = sectionContainer,
            stats = {},
            isCollapsed = false,
            height = 0
        }
        table.insert(frame._statsSections, sectionData)

        -- Stats in section
        for statIdx, stat in ipairs(section.stats) do
            -- Stat label
            local label = sectionContainer:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 12, "")
            label:SetTextColor(0.7, 0.7, 0.7, 0.8)
            label:SetPoint("TOPLEFT", sectionContainer, "TOPLEFT", 15, statYOffset)
            label:SetText(stat.name)

            -- Stat value
            local value = sectionContainer:CreateFontString(nil, "OVERLAY")
            value:SetFont(fontPath, 12, "")
            value:SetTextColor(section.color.r, section.color.g, section.color.b, 1)
            value:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", -2, statYOffset)
            value:SetJustifyH("RIGHT")
            value:SetText("0")

            -- Store for updates
            table.insert(frame._statsValues, {
                value = value,
                func = stat.func,
                format = stat.format or "%d"
            })

            -- Store stat elements for collapse/expand
            table.insert(sectionData.stats, {label = label, value = value})

            -- Divider line between stats
            if statIdx < #section.stats then
                local divider = sectionContainer:CreateTexture(nil, "OVERLAY")
                divider:SetColorTexture(0.1, 0.1, 0.1, 0.4)
                divider:SetPoint("TOPLEFT", sectionContainer, "TOPLEFT", 10, statYOffset - 8)
                divider:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", -10, statYOffset - 8)
                divider:SetHeight(1)
                table.insert(sectionData.stats, {divider = divider})
            end

            statYOffset = statYOffset - 16
        end

        sectionData.height = -statYOffset

        -- Click handler for collapse/expand
        titleContainer:SetScript("OnClick", function()
            sectionData.isCollapsed = not sectionData.isCollapsed
            for _, stat in ipairs(sectionData.stats) do
                if sectionData.isCollapsed then
                    if stat.label then stat.label:Hide() end
                    if stat.value then stat.value:Hide() end
                    if stat.divider then stat.divider:Hide() end
                else
                    if stat.label then stat.label:Show() end
                    if stat.value then stat.value:Show() end
                    if stat.divider then stat.divider:Show() end
                end
            end
            frame._recalculateSections()
        end)

        sectionContainer:SetHeight(sectionData.height)
        yOffset = yOffset - sectionData.height - 16
    end

    -- Set scroll child height
    scrollChild:SetHeight(-yOffset)

    -- Monitor to update stats
    local statsMonitor = CreateFrame("Frame")
    statsMonitor:SetScript("OnUpdate", function()
        if not (EllesmereUIDB and EllesmereUIDB.themedCharacterSheet) then
            return
        end
        if frame and frame:IsShown() and (frame.selectedTab or 1) == 1 then
            -- Update all stored stats
            for _, statEntry in ipairs(frame._statsValues) do
                local result = statEntry.func()
                if result ~= nil then
                    if statEntry.format:find("%%") then
                        statEntry.value:SetText(format(statEntry.format, result))
                    else
                        statEntry.value:SetText(format(statEntry.format, result))
                    end
                else
                    statEntry.value:SetText("0")
                end
            end
        end
    end)

    -- Apply custom rarity borders to slots (like CharacterSheetINSPO style)
    local function ApplyCustomSlotBorder(slotName)
        local slot = _G[slotName]
        if not slot then return end

        -- Hide Blizzard IconBorder
        if slot.IconBorder then
            slot.IconBorder:Hide()
        end

        -- Hide overlay textures
        if slot.IconOverlay then
            slot.IconOverlay:Hide()
        end
        if slot.IconOverlay2 then
            slot.IconOverlay2:Hide()
        end

        -- Crop icon inward
        if slot.icon then
            slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end

        -- Hide NormalTexture
        local normalTexture = _G[slotName .. "NormalTexture"]
        if normalTexture then
            normalTexture:Hide()
        end

        -- Get item rarity color for border
        local itemLink = GetInventoryItemLink("player", slot:GetID())
        local borderR, borderG, borderB = 1, 1, 0  -- Default yellow
        if itemLink then
            local _, _, rarity = GetItemInfo(itemLink)
            if rarity then
                borderR, borderG, borderB = C_Item.GetItemQualityColor(rarity)
            end
        end

        -- Add border directly on the slot with item color (2px thickness)
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.CreateBorder(slot, borderR, borderG, borderB, 1, 2, "OVERLAY", 7)
        end
    end

    -- Apply custom rarity borders to all item slots
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot",
        "CharacterFeetSlot", "CharacterWristSlot", "CharacterHandsSlot",
        "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot",
        "CharacterBackSlot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
        "CharacterShirtSlot", "CharacterTabardSlot"
    }

    -- Store on frame for use in tab hooks
    frame._themedSlots = itemSlots

    -- Create custom buttons for right side (Character, Titles, Equipment Manager)
    local buttonWidth = 70
    local buttonHeight = 25
    local buttonSpacing = 5
    -- Center buttons in right column (right column is ~268px wide starting at x=420)
    local totalButtonWidth = (buttonWidth * 3) + (buttonSpacing * 2)
    local rightColumnWidth = 268
    local startX = 425 + (rightColumnWidth - totalButtonWidth) / 2
    local startY = -60  -- Position near bottom of frame, but within bounds

    local function CreateEUIButton(name, label, onClick)
        local btn = CreateFrame("Button", "EUI_CharSheet_" .. name, frame, "SecureActionButtonTemplate")
        btn:SetSize(buttonWidth, buttonHeight)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX, startY)

        -- Background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0.03, 0.045, 0.05, 1)
        bg:SetAllPoints()

        -- Border
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.CreateBorder(btn, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 2)
        end

        -- Text
        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFont(fontPath, 11, "")
        text:SetTextColor(1, 1, 1, 0.8)
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
        text:SetText(label)

        -- Hover effect
        btn:SetScript("OnEnter", function()
            text:SetTextColor(1, 1, 1, 1)
            bg:SetColorTexture(0.05, 0.07, 0.08, 1)
        end)
        btn:SetScript("OnLeave", function()
            text:SetTextColor(1, 1, 1, 0.8)
            bg:SetColorTexture(0.03, 0.045, 0.05, 1)
        end)

        -- Click handler
        btn:SetScript("OnClick", onClick)

        return btn
    end

    -- Character button (will be updated after stats panel is created)
    local characterBtn = CreateEUIButton("Stats", "Character", function() end)

    -- Create Titles Panel (same position and size as stats panel)
    local titlesPanel = CreateFrame("Frame", "EUI_CharSheet_TitlesPanel", frame)
    titlesPanel:SetSize(220, 340)
    titlesPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 452, -90)
    titlesPanel:SetFrameLevel(50)
    titlesPanel:Hide()
    frame._titlesPanel = titlesPanel  -- Store reference on frame

    -- Titles panel background
    local titlesBg = titlesPanel:CreateTexture(nil, "BACKGROUND")
    titlesBg:SetColorTexture(0.03, 0.045, 0.05, 0.95)
    titlesBg:SetAllPoints()

    -- Search box for titles
    local titlesSearchBox = CreateFrame("EditBox", "EUI_CharSheet_TitlesSearchBox", titlesPanel)
    titlesSearchBox:SetSize(200, 24)
    titlesSearchBox:SetPoint("TOPLEFT", titlesPanel, "TOPLEFT", 10, -10)
    titlesSearchBox:SetAutoFocus(false)
    titlesSearchBox:SetMaxLetters(20)

    local searchBg = titlesSearchBox:CreateTexture(nil, "BACKGROUND")
    searchBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)
    searchBg:SetAllPoints()

    titlesSearchBox:SetTextColor(1, 1, 1, 1)
    titlesSearchBox:SetFont(fontPath, 10, "")

    -- Hint text
    local hintText = titlesSearchBox:CreateFontString(nil, "OVERLAY")
    hintText:SetFont(fontPath, 10, "")
    hintText:SetText("search for title")
    hintText:SetTextColor(0.6, 0.6, 0.6, 0.7)
    hintText:SetPoint("LEFT", titlesSearchBox, "LEFT", 5, 0)

    -- Create scroll frame for titles
    local titlesScrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_TitlesScrollFrame", titlesPanel)
    titlesScrollFrame:SetSize(200, 300)
    titlesScrollFrame:SetPoint("TOPLEFT", titlesPanel, "TOPLEFT", 5, -40)
    titlesScrollFrame:EnableMouseWheel(true)

    -- Create scroll child
    local titlesScrollChild = CreateFrame("Frame", "EUI_CharSheet_TitlesScrollChild", titlesScrollFrame)
    titlesScrollChild:SetWidth(200)
    titlesScrollFrame:SetScrollChild(titlesScrollChild)

    -- Mousewheel support
    titlesScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = titlesScrollFrame:GetVerticalScroll()
        local maxScroll = math.max(0, titlesScrollChild:GetHeight() - titlesScrollFrame:GetHeight())
        local newScroll = currentScroll - delta * 20
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        titlesScrollFrame:SetVerticalScroll(newScroll)
    end)

    -- Populate titles
    local function RefreshTitlesList()
        -- Clear old buttons
        for _, child in ipairs({titlesScrollChild:GetChildren()}) do
            child:Hide()
        end

        local currentTitle = GetCurrentTitle()
        local yOffset = 0
        local searchText = titlesSearchBox:GetText():lower()
        local titleButtons = {}  -- Store button references

        -- Add "No Title" button
        local noTitleBtn = CreateFrame("Button", nil, titlesScrollChild)
        noTitleBtn:SetWidth(240)
        noTitleBtn:SetHeight(24)
        noTitleBtn:SetPoint("TOPLEFT", titlesScrollChild, "TOPLEFT", 10, yOffset)

        local noTitleBg = noTitleBtn:CreateTexture(nil, "BACKGROUND")
        noTitleBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
        noTitleBg:SetAllPoints()
        titleButtons[0] = { btn = noTitleBtn, bg = noTitleBg }

        local noTitleText = noTitleBtn:CreateFontString(nil, "OVERLAY")
        noTitleText:SetFont(fontPath, 11, "")
        noTitleText:SetText("No Title")
        noTitleText:SetTextColor(1, 1, 1, 1)
        noTitleText:SetPoint("LEFT", noTitleBtn, "LEFT", 10, 0)

        noTitleBtn:SetScript("OnClick", function()
            SetCurrentTitle(0)
            titlesSearchBox:SetText("")
            hintText:Show()
            RefreshTitlesList()
        end)

        noTitleBtn:SetScript("OnEnter", function()
            noTitleBg:SetColorTexture(0.047, 0.824, 0.616, 0.2)
        end)

        noTitleBtn:SetScript("OnLeave", function()
            if GetCurrentTitle() == 0 then
                noTitleBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)  -- Lighter gray for active title
            else
                noTitleBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
            end
        end)

        yOffset = yOffset - 28

        -- Add all available titles
        for titleIndex = 1, GetNumTitles() do
            if IsTitleKnown(titleIndex) then
                local titleName = GetTitleName(titleIndex)
                if titleName and (searchText == "" or titleName:lower():find(searchText, 1, true)) then
                    local titleBtn = CreateFrame("Button", nil, titlesScrollChild)
                    titleBtn:SetWidth(240)
                    titleBtn:SetHeight(24)
                    titleBtn:SetPoint("TOPLEFT", titlesScrollChild, "TOPLEFT", 10, yOffset)
                    titleBtn._titleIndex = titleIndex

                    local btnBg = titleBtn:CreateTexture(nil, "BACKGROUND")
                    btnBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
                    btnBg:SetAllPoints()
                    titleButtons[titleIndex] = { btn = titleBtn, bg = btnBg }

                    local titleText = titleBtn:CreateFontString(nil, "OVERLAY")
                    titleText:SetFont(fontPath, 11, "")
                    titleText:SetText(titleName)
                    titleText:SetTextColor(1, 1, 1, 1)
                    titleText:SetPoint("LEFT", titleBtn, "LEFT", 10, 0)

                    titleBtn:SetScript("OnClick", function()
                        SetCurrentTitle(titleBtn._titleIndex)
                        titlesSearchBox:SetText("")
                        hintText:Show()
                        -- Schedule refresh after a frame to ensure the title is updated
                        C_Timer.After(0, RefreshTitlesList)
                    end)

                    titleBtn:SetScript("OnEnter", function()
                        btnBg:SetColorTexture(0.047, 0.824, 0.616, 0.2)
                    end)

                    titleBtn:SetScript("OnLeave", function()
                        if GetCurrentTitle() == titleIndex then
                            btnBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)  -- Lighter gray for active title
                        else
                            btnBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
                        end
                    end)

                    yOffset = yOffset - 28
                end
            end
        end

        -- Re-read current title to ensure it's updated
        currentTitle = GetCurrentTitle()

        -- Update colors based on current title
        for titleIndex, btnData in pairs(titleButtons) do
            if currentTitle == titleIndex then
                btnData.bg:SetColorTexture(0.1, 0.12, 0.14, 0.9)
            else
                btnData.bg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
            end
        end

        titlesScrollChild:SetHeight(-yOffset)
    end

    -- Search input handler
    titlesSearchBox:SetScript("OnTextChanged", function()
        RefreshTitlesList()
    end)

    -- Focus gained handler
    titlesSearchBox:SetScript("OnEditFocusGained", function()
        if titlesSearchBox:GetText() == "" then
            hintText:Hide()
        end
    end)

    -- Focus lost handler
    titlesSearchBox:SetScript("OnEditFocusLost", function()
        if titlesSearchBox:GetText() == "" then
            hintText:Show()
        end
    end)

    -- Hook to refresh titles when shown
    frame._titlesPanel:HookScript("OnShow", function()
        titlesSearchBox:SetText("")
        RefreshTitlesList()
    end)

    -- Update the Character button to show stats
    characterBtn:SetScript("OnClick", function()
        if not statsPanel:IsShown() then
            statsPanel:Show()
            frame._titlesPanel:Hide()
            frame._equipPanel:Hide()
        end
    end)

    -- Titles button to show titles
    CreateEUIButton("Titles", "Titles", function()
        if not frame._titlesPanel:IsShown() then
            frame._titlesPanel:Show()
            statsPanel:Hide()
            frame._equipPanel:Hide()
        end
    end)

    -- Create Equipment Panel (same position and size as stats panel)
    local equipPanel = CreateFrame("Frame", "EUI_CharSheet_EquipPanel", frame)
    equipPanel:SetSize(220, 340)
    equipPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 452, -90)
    equipPanel:SetFrameLevel(50)
    equipPanel:Hide()
    frame._equipPanel = equipPanel

    -- Equipment panel background
    local equipBg = equipPanel:CreateTexture(nil, "BACKGROUND")
    equipBg:SetColorTexture(0.03, 0.045, 0.05, 0.95)
    equipBg:SetAllPoints()

    -- Create scroll frame for equipment
    local equipScrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_EquipScrollFrame", equipPanel)
    equipScrollFrame:SetSize(200, 320)
    equipScrollFrame:SetPoint("TOPLEFT", equipPanel, "TOPLEFT", 5, -10)
    equipScrollFrame:EnableMouseWheel(true)

    -- Create scroll child
    local equipScrollChild = CreateFrame("Frame", "EUI_CharSheet_EquipScrollChild", equipScrollFrame)
    equipScrollChild:SetWidth(200)
    equipScrollFrame:SetScrollChild(equipScrollChild)

    -- Mousewheel support
    equipScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = equipScrollFrame:GetVerticalScroll()
        local maxScroll = math.max(0, equipScrollChild:GetHeight() - equipScrollFrame:GetHeight())
        local newScroll = currentScroll - delta * 20
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        equipScrollFrame:SetVerticalScroll(newScroll)
    end)

    -- Track selected equipment set
    local selectedSetID = nil

    -- Function to reload equipment sets
    local function RefreshEquipmentSets()
        -- Clear old buttons
        for _, child in ipairs({equipScrollChild:GetChildren()}) do
            child:Hide()
        end

        local equipmentSets = {}
        if C_EquipmentSet then
            local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
            if setIDs then
                for _, setID in ipairs(setIDs) do
                    local setName = C_EquipmentSet.GetEquipmentSetInfo(setID)
                    if setName and setName ~= "" then
                        table.insert(equipmentSets, {id = setID, name = setName})
                    end
                end
            end
        end

        -- "New Set" button at top
        local newSetBtn = CreateFrame("Button", nil, equipScrollChild)
        newSetBtn:SetWidth(200)
        newSetBtn:SetHeight(24)
        newSetBtn:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 0, 0)

        local newSetBg = newSetBtn:CreateTexture(nil, "BACKGROUND")
        newSetBg:SetColorTexture(0.047, 0.824, 0.616, 0.3)
        newSetBg:SetAllPoints()

        local newSetText = newSetBtn:CreateFontString(nil, "OVERLAY")
        newSetText:SetFont(fontPath, 11, "")
        newSetText:SetText("+ New Set")
        newSetText:SetTextColor(1, 1, 1, 1)
        newSetText:SetPoint("CENTER", newSetBtn, "CENTER", 0, 0)

        newSetBtn:SetScript("OnClick", function()
            StaticPopupDialogs["EUI_NEW_EQUIPMENT_SET"] = {
                text = "New equipment set name:",
                button1 = "Create",
                button2 = "Cancel",
                OnAccept = function(dialog)
                    local newName = dialog.EditBox:GetText()
                    if newName ~= "" then
                        C_EquipmentSet.CreateEquipmentSet(newName)
                        RefreshEquipmentSets()
                    end
                end,
                hasEditBox = true,
                editBoxWidth = 350,
                timeout = 0,
                whileDead = false,
                hideOnEscape = true,
            }
            StaticPopup_Show("EUI_NEW_EQUIPMENT_SET")
        end)

        newSetBtn:SetScript("OnEnter", function()
            newSetBg:SetColorTexture(0.047, 0.824, 0.616, 0.5)
        end)

        newSetBtn:SetScript("OnLeave", function()
            newSetBg:SetColorTexture(0.047, 0.824, 0.616, 0.3)
        end)

        -- Equip and Save buttons at top
        local equipTopBtn = CreateFrame("Button", nil, equipScrollChild)
        equipTopBtn:SetWidth(95)
        equipTopBtn:SetHeight(24)
        equipTopBtn:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 0, -44)

        local equipTopBg = equipTopBtn:CreateTexture(nil, "BACKGROUND")
        equipTopBg:SetColorTexture(0.05, 0.07, 0.08, 1)
        equipTopBg:SetAllPoints()

        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.CreateBorder(equipTopBtn, 0.8, 0.8, 0.8, 1, 1, "OVERLAY", 1)
        end

        local equipTopText = equipTopBtn:CreateFontString(nil, "OVERLAY")
        equipTopText:SetFont(fontPath, 10, "")
        equipTopText:SetText("Equip")
        equipTopText:SetTextColor(1, 1, 1, 1)
        equipTopText:SetPoint("CENTER", equipTopBtn, "CENTER", 0, 0)

        equipTopBtn:SetScript("OnClick", function()
            if selectedSetID then
                C_EquipmentSet.UseEquipmentSet(selectedSetID)
                activeEquipmentSetID = selectedSetID
                -- Save to DB for persistence
                if EllesmereUIDB then
                    EllesmereUIDB.lastEquippedSet = selectedSetID
                end
                RefreshEquipmentSets()
            end
        end)

        -- Save button at top
        local saveTopBtn = CreateFrame("Button", nil, equipScrollChild)
        saveTopBtn:SetWidth(95)
        saveTopBtn:SetHeight(24)
        saveTopBtn:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 105, -44)

        local saveTopBg = saveTopBtn:CreateTexture(nil, "BACKGROUND")
        saveTopBg:SetColorTexture(0.05, 0.07, 0.08, 1)
        saveTopBg:SetAllPoints()

        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.CreateBorder(saveTopBtn, 0.8, 0.8, 0.8, 1, 1, "OVERLAY", 1)
        end

        local saveTopText = saveTopBtn:CreateFontString(nil, "OVERLAY")
        saveTopText:SetFont(fontPath, 10, "")
        saveTopText:SetText("Save")
        saveTopText:SetTextColor(1, 1, 1, 1)
        saveTopText:SetPoint("CENTER", saveTopBtn, "CENTER", 0, 0)

        saveTopBtn:SetScript("OnClick", function()
            if selectedSetID then
                C_EquipmentSet.SaveEquipmentSet(selectedSetID)
            end
        end)

        local yOffset = -88  -- After buttons
        for _, setData in ipairs(equipmentSets) do
            local setBtn = CreateFrame("Button", nil, equipScrollChild)
            setBtn:SetWidth(200)
            setBtn:SetHeight(24)
            setBtn:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 0, yOffset)

            -- Background
            local btnBg = setBtn:CreateTexture(nil, "BACKGROUND")
            if activeEquipmentSetID == setData.id then
                btnBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)  -- Lighter gray for active set
            else
                btnBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
            end
            btnBg:SetAllPoints()

            -- Text
            local setText = setBtn:CreateFontString(nil, "OVERLAY")
            setText:SetFont(fontPath, 10, "")
            setText:SetText(setData.name)
            setText:SetTextColor(1, 1, 1, 1)
            setText:SetPoint("LEFT", setBtn, "LEFT", 10, 0)

            -- Spec icon
            local assignedSpec = C_EquipmentSet.GetEquipmentSetAssignedSpec(setData.id)
            if assignedSpec then
                local _, specName, _, specIcon = GetSpecializationInfo(assignedSpec)
                if specIcon then
                    local specIconTexture = setBtn:CreateTexture(nil, "OVERLAY")
                    specIconTexture:SetTexture(specIcon)
                    specIconTexture:SetSize(16, 16)
                    specIconTexture:SetPoint("RIGHT", setBtn, "RIGHT", -25, 0)
                end
            end


            -- Click handler (select set)
            setBtn:SetScript("OnClick", function()
                selectedSetID = setData.id
                RefreshEquipmentSets()
            end)

            -- Hover effect
            setBtn:SetScript("OnEnter", function()
                btnBg:SetColorTexture(0.047, 0.824, 0.616, 0.2)
            end)

            setBtn:SetScript("OnLeave", function()
                if selectedSetID == setData.id then
                    btnBg:SetColorTexture(0.047, 0.824, 0.616, 0.5)
                elseif activeEquipmentSetID == setData.id then
                    btnBg:SetColorTexture(0.1, 0.12, 0.14, 0.9)  -- Lighter gray for active set
                else
                    btnBg:SetColorTexture(0.05, 0.07, 0.08, 0.8)
                end
            end)

            -- Highlight selected set
            if selectedSetID == setData.id then
                btnBg:SetColorTexture(0.047, 0.824, 0.616, 0.5)
            end

            -- Border for active set
            if activeEquipmentSetID == setData.id then
                if EllesmereUI and EllesmereUI.PanelPP then
                    EllesmereUI.PanelPP.CreateBorder(setBtn, 0.15, 0.17, 0.19, 1, 1, "OVERLAY", 1)
                end
            end

            -- Cogwheel button for spec assignment
            local cogBtn = CreateFrame("Button", nil, setBtn)
            cogBtn:SetWidth(14)
            cogBtn:SetHeight(14)
            cogBtn:SetPoint("RIGHT", setBtn, "RIGHT", -5, 0)

            local cogIcon = cogBtn:CreateTexture(nil, "OVERLAY")
            cogIcon:SetTexture("Interface/Buttons/UI-OptionsButton")
            cogIcon:SetAllPoints()

            -- Hover highlight
            local cogHL = cogBtn:CreateTexture(nil, "HIGHLIGHT")
            cogHL:SetColorTexture(0.047, 0.824, 0.616, 0.3)
            cogHL:SetAllPoints()
            cogBtn:SetHighlightTexture(cogHL)

            cogBtn:SetScript("OnClick", function(self, button)
                -- Create a simple spec selection menu
                local specs = {}
                local numSpecs = GetNumSpecializations()
                for i = 1, numSpecs do
                    local id, name = GetSpecializationInfo(i)
                    if id then
                        table.insert(specs, {index = i, name = name})
                    end
                end

                -- Create or reuse menu frame
                if not cogBtn.menuFrame then
                    -- Create invisible backdrop to catch clicks outside menu
                    local backdrop = CreateFrame("Button", nil, UIParent)
                    backdrop:SetFrameStrata("DIALOG")
                    backdrop:SetFrameLevel(99)
                    backdrop:SetSize(2560, 1440)
                    backdrop:SetPoint("CENTER", UIParent, "CENTER")
                    backdrop:SetScript("OnClick", function()
                        cogBtn.menuFrame:Hide()
                        backdrop:Hide()
                    end)
                    cogBtn.menuBackdrop = backdrop

                    cogBtn.menuFrame = CreateFrame("Frame", nil, UIParent)
                    cogBtn.menuFrame:SetFrameStrata("DIALOG")
                    cogBtn.menuFrame:SetFrameLevel(100)
                    cogBtn.menuFrame:SetSize(120, #specs * 24 + 10)

                    -- Add background texture
                    local bg = cogBtn.menuFrame:CreateTexture(nil, "BACKGROUND")
                    bg:SetColorTexture(0.05, 0.07, 0.08, 0.9)
                    bg:SetAllPoints()

                    -- Add border
                    local border = cogBtn.menuFrame:CreateTexture(nil, "BORDER")
                    border:SetColorTexture(0.047, 0.824, 0.616, 1)
                    border:SetPoint("TOPLEFT", cogBtn.menuFrame, "TOPLEFT", 0, 0)
                    border:SetPoint("TOPRIGHT", cogBtn.menuFrame, "TOPRIGHT", 0, 0)
                    border:SetHeight(1)

                    border = cogBtn.menuFrame:CreateTexture(nil, "BORDER")
                    border:SetColorTexture(0.047, 0.824, 0.616, 1)
                    border:SetPoint("BOTTOMLEFT", cogBtn.menuFrame, "BOTTOMLEFT", 0, 0)
                    border:SetPoint("BOTTOMRIGHT", cogBtn.menuFrame, "BOTTOMRIGHT", 0, 0)
                    border:SetHeight(1)

                    border = cogBtn.menuFrame:CreateTexture(nil, "BORDER")
                    border:SetColorTexture(0.047, 0.824, 0.616, 1)
                    border:SetPoint("TOPLEFT", cogBtn.menuFrame, "TOPLEFT", 0, 0)
                    border:SetPoint("BOTTOMLEFT", cogBtn.menuFrame, "BOTTOMLEFT", 0, 0)
                    border:SetWidth(1)

                    border = cogBtn.menuFrame:CreateTexture(nil, "BORDER")
                    border:SetColorTexture(0.047, 0.824, 0.616, 1)
                    border:SetPoint("TOPRIGHT", cogBtn.menuFrame, "TOPRIGHT", 0, 0)
                    border:SetPoint("BOTTOMRIGHT", cogBtn.menuFrame, "BOTTOMRIGHT", 0, 0)
                    border:SetWidth(1)
                end

                -- Clear previous buttons
                for _, btn in ipairs(cogBtn.menuFrame.specButtons or {}) do
                    btn:Hide()
                end
                cogBtn.menuFrame.specButtons = {}

                -- Create spec buttons
                local yOffset = 0
                for _, spec in ipairs(specs) do
                    local btn = CreateFrame("Button", nil, cogBtn.menuFrame)
                    btn:SetSize(110, 24)
                    btn:SetPoint("TOP", cogBtn.menuFrame, "TOP", 0, -5 - (yOffset * 24))
                    btn:SetNormalFontObject(GameFontNormal)
                    btn:SetText(spec.name)

                    local texture = btn:CreateTexture(nil, "BACKGROUND")
                    texture:SetColorTexture(0.05, 0.07, 0.08, 0.5)
                    texture:SetAllPoints()
                    btn:SetNormalTexture(texture)

                    local hlTexture = btn:CreateTexture(nil, "HIGHLIGHT")
                    hlTexture:SetColorTexture(0.047, 0.824, 0.616, 0.3)
                    hlTexture:SetAllPoints()
                    btn:SetHighlightTexture(hlTexture)

                    btn:SetScript("OnClick", function()
                        C_EquipmentSet.AssignSpecToEquipmentSet(setData.id, spec.index)
                        RefreshEquipmentSets()
                        cogBtn.menuFrame:Hide()
                        cogBtn.menuBackdrop:Hide()
                    end)

                    table.insert(cogBtn.menuFrame.specButtons, btn)
                    yOffset = yOffset + 1
                end

                -- Position and show menu
                cogBtn.menuFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -5)
                cogBtn.menuFrame:Show()
                cogBtn.menuBackdrop:Show()
            end)

            yOffset = yOffset - 30
        end

        equipScrollChild:SetHeight(-yOffset)
    end

    -- Event handler for equipment set changes
    local equipSetChangeFrame = CreateFrame("Frame")
    equipSetChangeFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    equipSetChangeFrame:SetScript("OnEvent", function()
        -- activeEquipmentSetID is set by the Equip button and auto-equip logic
        if CharacterFrame and CharacterFrame:IsShown() and frame._equipPanel and frame._equipPanel:IsShown() then
            RefreshEquipmentSets()
        end
    end)

    -- Hook to refresh equipment sets when shown
    equipPanel:HookScript("OnShow", function()
        RefreshEquipmentSets()
    end)

    -- Equipment Manager button
    CreateEUIButton("Equipment", "Equipment", function()
        if not frame._equipPanel:IsShown() then
            frame._equipPanel:Show()
            statsPanel:Hide()
            frame._titlesPanel:Hide()
        end
    end)

    -- Update button positions to stack horizontally
    local buttons = {
        "EUI_CharSheet_Stats",
        "EUI_CharSheet_Titles",
        "EUI_CharSheet_Equipment"
    }
    for i, btnName in ipairs(buttons) do
        local btn = _G[btnName]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + (i - 1) * (buttonWidth + buttonSpacing), startY)
        end
    end

    -- Left column slots (show itemlevel on right)
    local leftColumnSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
        "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
        "CharacterTabardSlot", "CharacterWristSlot"
    }

    -- Right column slots (show itemlevel on left)
    local rightColumnSlots = {
        "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot",
        "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot"
    }

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

    -- Create global socket container for all slot icons
    local globalSocketContainer = CreateFrame("Frame", "EUI_CharSheet_SocketContainer", frame)
    globalSocketContainer:SetFrameLevel(100)
    globalSocketContainer:Show()
    frame._socketContainer = globalSocketContainer  -- Store reference on frame

    for _, slotName in ipairs(itemSlots) do
        ApplyCustomSlotBorder(slotName)

        -- Create itemlevel labels
        local slot = _G[slotName]
        if slot and not slot._itemLevelLabel then
            local label = frame:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 11, "")
            label:SetTextColor(1, 1, 1, 0.8)
            label:SetJustifyH("CENTER")

            -- Position based on column
            if tContains(leftColumnSlots, slotName) then
                -- Left column: show on right side
                label:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            elseif tContains(rightColumnSlots, slotName) then
                -- Right column: show on left side
                label:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "CharacterMainHandSlot" then
                -- MainHand: show on left side
                label:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "CharacterSecondaryHandSlot" then
                -- OffHand: show on right side
                label:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            end

            slot._itemLevelLabel = label
        end

        -- Create enchant labels
        if slot and not slot._enchantLabel then
            local enchantLabel = frame:CreateFontString(nil, "OVERLAY")
            enchantLabel:SetFont(fontPath, 9, "")
            enchantLabel:SetTextColor(1, 1, 1, 0.8)
            enchantLabel:SetJustifyH("CENTER")

            -- Position based on column (below itemlevel)
            if tContains(leftColumnSlots, slotName) then
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 5, -5)
            elseif tContains(rightColumnSlots, slotName) then
                enchantLabel:SetPoint("Right", slot, "LEFT", -5, -5)
            elseif slotName == "CharacterMainHandSlot" then
                enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            elseif slotName == "CharacterSecondaryHandSlot" then
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 15, -5)
            end

            slot._enchantLabel = enchantLabel
        end

        -- Create upgrade track labels (positioned relative to itemlevel)
        if slot and not slot._upgradeTrackLabel and slot._itemLevelLabel then
            local upgradeTrackLabel = frame:CreateFontString(nil, "OVERLAY")
            upgradeTrackLabel:SetFont(fontPath, 11, "")
            upgradeTrackLabel:SetTextColor(1, 1, 1, 0.6)
            upgradeTrackLabel:SetJustifyH("CENTER")

            -- Position beside itemlevel label based on column
            if tContains(leftColumnSlots, slotName) then
                -- Left column: upgradeTrack RIGHT of itemLevel
                upgradeTrackLabel:SetPoint("LEFT", slot._itemLevelLabel, "RIGHT", 3, 0)
            elseif tContains(rightColumnSlots, slotName) then
                -- Right column: upgradeTrack LEFT of itemLevel
                upgradeTrackLabel:SetPoint("RIGHT", slot._itemLevelLabel, "LEFT", -3, 0)
            elseif slotName == "CharacterMainHandSlot" then
                -- MainHand: upgradeTrack LEFT of itemLevel
                upgradeTrackLabel:SetPoint("RIGHT", slot._itemLevelLabel, "LEFT", -3, 0)
            elseif slotName == "CharacterSecondaryHandSlot" then
                -- OffHand: upgradeTrack RIGHT of itemLevel
                upgradeTrackLabel:SetPoint("LEFT", slot._itemLevelLabel, "RIGHT", 3, 0)
            end

            slot._upgradeTrackLabel = upgradeTrackLabel
        end
    end

    -- Socket icon creation and display logic
    local function GetOrCreateSocketIcons(slot, side, slotIndex)
        if slot._euiCharSocketsIcons then return slot._euiCharSocketsIcons end

        slot._euiCharSocketsIcons = {}
        for i = 1, 4 do  -- Max 4 sockets per item
            local icon = globalSocketContainer:CreateTexture(nil, "OVERLAY")
            icon:SetSize(16, 16)
            icon:Hide()
            slot._euiCharSocketsIcons[i] = icon
        end

        slot._euiCharSocketsSide = side
        slot._euiCharSocketsSlotIndex = slotIndex

        return slot._euiCharSocketsIcons
    end

    -- Update socket icons for all slots
    local function UpdateSocketIcons(slotName)
        local slot = _G[slotName]
        if not slot then return end

        local slotIndex = slot:GetID()
        local side = tContains(leftColumnSlots, slotName) and "RIGHT" or "LEFT"

        local socketIcons = GetOrCreateSocketIcons(slot, side, slotIndex)

        local link = GetInventoryItemLink("player", slotIndex)
        if not link then
            for _, icon in ipairs(socketIcons) do icon:Hide() end
            return
        end

        -- Create tooltip to extract socket textures
        local tooltip = CreateFrame("GameTooltip", "EUI_CharSheet_SocketTooltip_" .. slotName, nil, "GameTooltipTemplate")
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:SetInventoryItem("player", slotIndex)

        -- Extract socket textures from tooltip
        local socketTextures = {}
        for i = 1, 10 do
            local texture = _G["EUI_CharSheet_SocketTooltip_" .. slotName .. "Texture" .. i]
            if texture and texture:IsShown() then
                local tex = texture:GetTexture() or texture:GetTextureFileID()
                if tex then
                    table.insert(socketTextures, tex)
                end
            end
        end

        tooltip:Hide()

        -- Position and show socket icons
        if #socketTextures > 0 then
            for i, icon in ipairs(socketIcons) do
                if socketTextures[i] then
                    icon:SetTexture(socketTextures[i])
                    icon:SetScale(1)

                    -- Position icons based on column
                    if side == "LEFT" then
                        icon:SetPoint("RIGHT", slot, "RIGHT", 20, 0 - (i-1)*18)
                    else
                        icon:SetPoint("LEFT", slot, "LEFT", -20, 0 - (i-1)*18)
                    end
                    icon:Show()
                else
                    icon:Hide()
                end
            end
        else
            for _, icon in ipairs(socketIcons) do
                icon:Hide()
            end
        end
    end

    -- Refresh socket icons for all slots
    local function RefreshAllSocketIcons()
        for _, slotName in ipairs(itemSlots) do
            UpdateSocketIcons(slotName)
        end
    end

    -- Hook into equipment changes
    local socketWatcher = CreateFrame("Frame")
    socketWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    socketWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    socketWatcher:SetScript("OnEvent", function()
        if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet then
            C_Timer.After(0.1, RefreshAllSocketIcons)
        end
    end)

    -- Hook frame show/hide
    frame:HookScript("OnShow", function()
        RefreshAllSocketIcons()
        globalSocketContainer:Show()
        -- Reset to Stats panel on open
        if statsPanel and frame._titlesPanel and frame._equipPanel then
            statsPanel:Show()
            frame._titlesPanel:Hide()
            frame._equipPanel:Hide()
        end
    end)

    frame:HookScript("OnHide", function()
        globalSocketContainer:Hide()
    end)

    -- Wrap EquipmentFlyout_UpdateFlyout to suppress errors from reparented slots
    if not frame._equipmentFlyoutWrapped then
        local originalEquipmentFlyoutUpdate = _G.EquipmentFlyout_UpdateFlyout
        _G.EquipmentFlyout_UpdateFlyout = function(...)
            pcall(originalEquipmentFlyoutUpdate, ...)
        end
        frame._equipmentFlyoutWrapped = true
    end

    -- Create reusable tooltip for enchant scanning
    local enchantTooltip = CreateFrame("GameTooltip", "EUICharacterSheetEnchantTooltip", nil, "GameTooltipTemplate")
    enchantTooltip:SetOwner(UIParent, "ANCHOR_NONE")

    -- Cache item IDs to only update when items change
    local itemIdCache = {}

    -- Function to update enchant text and upgrade track for a slot
    local function UpdateSlotInfo(slotName)
        local slot = _G[slotName]
        if not slot then return end

        local itemLink = GetInventoryItemLink("player", slot:GetID())
        local itemLevel = ""
        local enchantText = ""
        local upgradeTrackText = ""
        local upgradeTrackColor = { r = 1, g = 1, b = 1 }

        if itemLink then
            itemLevel = select(4, GetItemInfo(itemLink)) or ""

            -- Get enchant and upgrade track from tooltip
            enchantTooltip:SetInventoryItem("player", slot:GetID())
            for i = 1, enchantTooltip:NumLines() do
                local textLeft = _G["EUICharacterSheetEnchantTooltipTextLeft" .. i]:GetText() or ""

                -- Get enchant text
                if textLeft:match("Enchanted:") then
                    enchantText = textLeft:gsub("Enchanted:%s*", "")
                    enchantText = enchantText:gsub("^Enchant%s+[^-]+%s*-%s*", "")
                end

                -- Get upgrade track
                if textLeft:match("Upgrade Level:") then
                    local trackInfo = textLeft:gsub("Upgrade Level:%s*", "")
                    local trk, nums = trackInfo:match("^(%w+)%s+(.+)$")

                    if trk and nums then
                        -- Map track types to short names and colors
                        if trk == "Champion" then
                            upgradeTrackText = "(Champion " .. nums .. ")"
                            upgradeTrackColor = { r = 0.6, g = 0, b = 1 }  -- purple
                        elseif trk:match("Myth") then
                            upgradeTrackText = "(Myth " .. nums .. ")"
                            upgradeTrackColor = { r = 1, g = 0.6, b = 0 }  -- orange
                        elseif trk:match("Hero") then
                            upgradeTrackText = "(Hero " .. nums .. ")"
                            upgradeTrackColor = { r = 0.2, g = 0.8, b = 1 }  -- cyan
                        elseif trk:match("Veteran") then
                            upgradeTrackText = "(Veteran " .. nums .. ")"
                            upgradeTrackColor = { r = 0, g = 1, b = 0 }  -- green
                        elseif trk:match("Adventurer") then
                            upgradeTrackText = "(Adventurer " .. nums .. ")"
                            upgradeTrackColor = { r = 1, g = 1, b = 0 }  -- yellow
                        elseif trk:match("Delve") then
                            upgradeTrackText = "(Delve " .. nums .. ")"
                            upgradeTrackColor = { r = 1, g = 0.5, b = 1 }  -- magenta
                        end
                    end
                end
            end
        end

        -- Update itemlevel label
        if slot._itemLevelLabel then
            slot._itemLevelLabel:SetText(tostring(itemLevel) or "")
        end

        -- Update enchant label
        if slot._enchantLabel then
            slot._enchantLabel:SetText(enchantText or "")
        end

        -- Update upgrade track label
        if slot._upgradeTrackLabel then
            slot._upgradeTrackLabel:SetText(upgradeTrackText or "")
            slot._upgradeTrackLabel:SetTextColor(upgradeTrackColor.r, upgradeTrackColor.g, upgradeTrackColor.b, 0.8)
        end
    end

    -- Monitor and update only when items change
    if not frame._itemLevelMonitor then
        frame._itemLevelMonitor = CreateFrame("Frame")
        frame._itemLevelMonitor:SetScript("OnUpdate", function()
            if not (EllesmereUIDB and EllesmereUIDB.themedCharacterSheet) then
                return
            end
            if frame and frame:IsShown() then
                for _, slotName in ipairs(itemSlots) do
                    -- Use GetItemInfoInstant to check if item changed without tooltip overhead
                    local itemLink = GetInventoryItemLink("player", _G[slotName]:GetID())
                    local itemId = itemLink and GetItemInfoInstant(itemLink) or nil

                    -- Only update if item ID changed
                    if itemIdCache[slotName] ~= itemId then
                        itemIdCache[slotName] = itemId
                        UpdateSlotInfo(slotName)
                    end
                end
            end
        end)
    end
end

-- Get item rarity color from link
local function GetRarityColorFromLink(itemLink)
    if not itemLink then
        return 0.9, 0.9, 0.9, 1  -- Default gray
    end

    local itemRarity = select(3, GetItemInfo(itemLink))
    if not itemRarity then
        return 0.9, 0.9, 0.9, 1
    end

    -- WoW standard rarity colors
    local rarityColors = {
        [0] = { 0.62, 0.62, 0.62 },  -- Poor
        [1] = { 1, 1, 1 },            -- Common
        [2] = { 0.12, 1, 0 },         -- Uncommon
        [3] = { 0, 0.44, 0.87 },      -- Rare
        [4] = { 0.64, 0.21, 0.93 },   -- Epic
        [5] = { 1, 0.5, 0 },          -- Legendary
        [6] = { 0.9, 0.8, 0.5 },      -- Artifact
        [7] = { 0.9, 0.8, 0.5 },      -- Heirloom
    }

    local color = rarityColors[itemRarity] or rarityColors[1]
    return color[1], color[2], color[3], 1
end

-- Style a character slot with rarity-based border
local function SkinCharacterSlot(slotName, slotID)
    local slot = _G[slotName]
    if not slot or slot._ebsSkinned then return end
    slot._ebsSkinned = true

    -- Hide Blizzard IconBorder
    if slot.IconBorder then
        slot.IconBorder:Hide()
    end

    -- Adjust IconTexture
    local iconTexture = _G[slotName .. "IconTexture"]
    if iconTexture then
        iconTexture:SetTexCoord(0.07, 0.07, 0.07, 0.93, 0.93, 0.07, 0.93, 0.93)
    end

    -- Test: Hide CharacterHandsSlot completely
    if slotName == "CharacterHandsSlot" then
        slot:Hide()
    end

    -- Hide NormalTexture
    local normalTexture = _G[slotName .. "NormalTexture"]
    if normalTexture then
        normalTexture:Hide()
    end

    -- EUI-style background for the slot
    local slotBg = slot:CreateTexture(nil, "BACKGROUND", nil, -5)
    slotBg:SetAllPoints(slot)
    slotBg:SetColorTexture(0.03, 0.045, 0.05, 0.7)  -- EUI frame BG with transparency
    slot._slotBg = slotBg

    -- Create custom border on the slot using PP.CreateBorder
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(slot, 1, 1, 1, 0.4, 2, "OVERLAY", 7)
    end
end

-- Main function to apply themed character sheet
local function ApplyThemedCharacterSheet()
    if not (EllesmereUIDB and EllesmereUIDB.themedCharacterSheet) then
        return
    end

    if CharacterFrame then
        SkinCharacterSheet()
    end
end

-- Register the feature
if EllesmereUI then
    EllesmereUI.ApplyThemedCharacterSheet = ApplyThemedCharacterSheet

    -- Setup at PLAYER_LOGIN to register drag hooks early
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if CharacterFrame then
            -- Setup drag functionality at login (before first open)
            CharacterFrame:SetMovable(true)
            CharacterFrame:SetClampedToScreen(true)
            local _ebsDragging = false

            CharacterFrame:SetScript("OnMouseDown", function(btn, button)
                if button ~= "LeftButton" then return end
                if not IsShiftKeyDown() and not IsControlKeyDown() then return end
                _ebsDragging = IsShiftKeyDown() and "save" or "temp"
                btn:StartMoving()
            end)

            CharacterFrame:SetScript("OnMouseUp", function(btn, button)
                if button ~= "LeftButton" or not _ebsDragging then return end
                btn:StopMovingOrSizing()
                _ebsDragging = false
            end)

            -- Hook styling on OnShow
            CharacterFrame:HookScript("OnShow", ApplyThemedCharacterSheet)
            ApplyThemedCharacterSheet()

            -- Function to detect and set active equipment set
            local function UpdateActiveEquipmentSet()
                local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                if setIDs then
                    for _, setID in ipairs(setIDs) do
                        local setItems = C_EquipmentSet.GetEquipmentSetItemIDs(setID)
                        if setItems then
                            local allMatch = true
                            for slotIndex, itemID in pairs(setItems) do
                                if itemID ~= 0 then
                                    local currentItemID = GetInventoryItemID("player", slotIndex)
                                    if currentItemID ~= itemID then
                                        allMatch = false
                                        break
                                    end
                                end
                            end
                            if allMatch then
                                activeEquipmentSetID = setID
                                return
                            end
                        end
                    end
                end
                activeEquipmentSetID = nil
            end

            -- Auto-equip equipment set when spec changes
            local specChangeFrame = CreateFrame("Frame")
            specChangeFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            specChangeFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
            specChangeFrame:SetScript("OnEvent", function(self, event)
                if event == "EQUIPMENT_SETS_CHANGED" then
                    -- Update active set when equipment changes
                    UpdateActiveEquipmentSet()
                    if CharacterFrame and CharacterFrame:IsShown() and frame._equipPanel and frame._equipPanel:IsShown() then
                        RefreshEquipmentSets()
                    end
                else
                    -- Auto-equip when spec changes
                    local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                    if setIDs then
                        for _, setID in ipairs(setIDs) do
                            local assignedSpec = C_EquipmentSet.GetEquipmentSetAssignedSpec(setID)
                            if assignedSpec then
                                local currentSpecIndex = GetSpecialization()
                                if assignedSpec == currentSpecIndex then
                                    C_EquipmentSet.UseEquipmentSet(setID)
                                    activeEquipmentSetID = setID
                                    if EllesmereUIDB then
                                        EllesmereUIDB.lastEquippedSet = setID
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end)

            -- Initialize active set on login
            local loginFrame = CreateFrame("Frame")
            loginFrame:RegisterEvent("PLAYER_LOGIN")
            loginFrame:SetScript("OnEvent", function()
                loginFrame:UnregisterEvent("PLAYER_LOGIN")
                -- Restore last equipped set if available
                if EllesmereUIDB and EllesmereUIDB.lastEquippedSet then
                    activeEquipmentSetID = EllesmereUIDB.lastEquippedSet
                end
            end)
        end
    end)
end
