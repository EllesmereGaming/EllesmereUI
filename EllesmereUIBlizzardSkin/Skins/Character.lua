local WSkin = _G.EllesmereUIBlizzardSkin
local _G = _G
local ipairs = ipairs
local select = select
local unpack = unpack
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local GetInventoryItemQuality = GetInventoryItemQuality
local GetInventoryItemTexture = GetInventoryItemTexture
local GetItemInfo = GetItemInfo
local GetItemQualityColor = GetItemQualityColor
local GetNumFactions = GetNumFactions
local GetPetHappiness = GetPetHappiness
local HasPetUI = HasPetUI
local UnitFactionGroup = UnitFactionGroup

WSkin:AddCallback("Skin_Character", function()
	-- CharacterFrame
	WSkin:StripTextures(CharacterFrame, true)
	WSkin:CreateBackdrop(CharacterFrame, "Transparent")
	CharacterFrame.WSkin:Point(backdrop, "TOPLEFT", 11, -12)
	CharacterFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", -32, 76)

	WSkin:SetUIPanelWindowInfo(CharacterFrame, "width")

	WSkin:SetBackdropHitRect(PaperDollFrame, CharacterFrame.backdrop)
	WSkin:SetBackdropHitRect(PetPaperDollFrame, CharacterFrame.backdrop)
	WSkin:SetBackdropHitRect(PetPaperDollFrameCompanionFrame, CharacterFrame.backdrop)
	WSkin:SetBackdropHitRect(PetPaperDollFramePetFrame, CharacterFrame.backdrop)
	WSkin:SetBackdropHitRect(ReputationFrame, CharacterFrame.backdrop)
	WSkin:SetBackdropHitRect(SkillFrame, CharacterFrame.backdrop)
	if TokenFrame then
		WSkin:SetBackdropHitRect(TokenFrame, CharacterFrame.backdrop)
	end

	WSkin:HandleCloseButton(CharacterFrameCloseButton, CharacterFrame.backdrop)

	WSkin:StripTextures(PaperDollFrame, true)

	for i = 1, #CHARACTERFRAME_SUBFRAMES do
		local tab = _G["CharacterFrameTab"..i]
		if tab then
			WSkin:HandleTab(tab)
		end
	end

	hooksecurefunc("PetPaperDollFrame_UpdateIsAvailable", function()
		if not PetPaperDollFrame.hidden and CharacterFrameTab3 then
			WSkin:Point(CharacterFrameTab3, "LEFT", "CharacterFrameTab2", "RIGHT", -15, 0)
		end
	end)

	-- PaperDollFrame
	WSkin:StripTextures(PlayerTitleFrame)
	WSkin:CreateBackdrop(PlayerTitleFrame, "Default")
	PlayerTitleFrame.WSkin:Point(backdrop, "TOPLEFT", 20, 3)
	PlayerTitleFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", -16, 15)
	PlayerTitleFrame.backdrop:SetFrameLevel(PlayerTitleFrame:GetFrameLevel())

	WSkin:HandleNextPrevButton(PlayerTitleFrameButton)
	WSkin:Size(PlayerTitleFrameButton, 16, 16)
	WSkin:Point(PlayerTitleFrameButton, "TOPRIGHT", PlayerTitleFrameRight, "TOPRIGHT", -18, -16)

	WSkin:StripTextures(PlayerTitlePickerFrame)
	WSkin:CreateBackdrop(PlayerTitlePickerFrame, "Transparent")
	PlayerTitlePickerFrame.WSkin:Point(backdrop, "TOPLEFT", 6, -10)
	PlayerTitlePickerFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", -13, 6)
	PlayerTitlePickerFrame.backdrop:SetFrameLevel(PlayerTitlePickerFrame:GetFrameLevel())
	WSkin:HandleScrollBar(PlayerTitlePickerScrollFrameScrollBar)

	WSkin:Point(PlayerTitlePickerScrollFrameScrollBar, "TOPLEFT", PlayerTitlePickerScrollFrame, "TOPRIGHT", 1, -14)
	WSkin:Point(PlayerTitlePickerScrollFrameScrollBar, "BOTTOMLEFT", PlayerTitlePickerScrollFrame, "BOTTOMRIGHT", 1, 15)

	if PlayerTitlePickerScrollFrame.buttons then
		for _, button in ipairs(PlayerTitlePickerScrollFrame.buttons) do
			if button.text then
				button.text:SetFontObject("GameFontNormal")
			end
		end
	end

	WSkin:HandleRotateButton(CharacterModelFrameRotateLeftButton)
	WSkin:HandleRotateButton(CharacterModelFrameRotateRightButton)

	WSkin:Point(PlayerStatFrameLeftDropDown, "BOTTOMLEFT", PlayerStatLeftTop, "TOPLEFT", -19, -8)
	WSkin:HandleDropDownBox(PlayerStatFrameLeftDropDown, 140, "down")
	WSkin:HandleDropDownBox(PlayerStatFrameRightDropDown, 140, "down")

	WSkin:StripTextures(CharacterAttributesFrame)

	if PaperDollFrameItemFlyoutButtons then PaperDollFrameItemFlyoutButtons:EnableMouse(false) end
	if PaperDollFrameItemFlyoutHighlight then PaperDollFrameItemFlyoutHighlight:Hide() end

	WSkin:Size(GearManagerToggleButton, 25, 29)
	WSkin:Point(GearManagerToggleButton, "TOPRIGHT", -46, -40)
	WSkin:CreateBackdrop(GearManagerToggleButton, "Default")
	local gNormal = GearManagerToggleButton:GetNormalTexture()
	if gNormal then gNormal:SetTexCoord(0.203125, 0.828125, 0.15625, 0.875) end
	local gPushed = GearManagerToggleButton:GetPushedTexture()
	if gPushed then gPushed:SetTexCoord(0.1875, 0.8125, 0.1875, 0.90625) end
	local gHighlight = GearManagerToggleButton:GetHighlightTexture()
	if gHighlight then
		gHighlight:SetTexture(1, 1, 1, 0.3)
		gHighlight:SetAllPoints()
	end

	WSkin:Point(PlayerTitleFrame, "TOP", CharacterLevelText, "BOTTOM", -7, -7)
	WSkin:Point(PlayerTitlePickerFrame, "TOPLEFT", PlayerTitleFrame, "BOTTOMLEFT", 14, 26)

	WSkin:Size(CharacterModelFrame, 237, 217)
	WSkin:Point(CharacterModelFrame, "TOPLEFT", 63, -76)

	WSkin:Point(CharacterModelFrameRotateLeftButton, "TOPLEFT", 4, -4)
	WSkin:Point(CharacterModelFrameRotateRightButton, "TOPLEFT", CharacterModelFrameRotateLeftButton, "TOPRIGHT", 3, 0)

	WSkin:Point(CharacterResistanceFrame, "TOPRIGHT", PaperDollFrame, "TOPLEFT", 300, -81)

	WSkin:Point(CharacterHeadSlot, "TOPLEFT", 19, -76)
	WSkin:Point(CharacterHandsSlot, "TOPLEFT", 307, -76)
	WSkin:Point(CharacterMainHandSlot, "TOPLEFT", PaperDollFrame, "BOTTOMLEFT", 110, 131)
	WSkin:Point(CharacterAttributesFrame, "TOPLEFT", 66, -292)

	local popoutButtonOnEnter = function(self) if self.icon then self.icon:SetVertexColor(1, 0.8, 0) end end
	local popoutButtonOnLeave = function(self) if self.icon then self.icon:SetVertexColor(1, 1, 1) end end

	local slots = {
		[1] = CharacterHeadSlot,
		[2] = CharacterNeckSlot,
		[3] = CharacterShoulderSlot,
		[4] = CharacterShirtSlot,
		[5] = CharacterChestSlot,
		[6] = CharacterWaistSlot,
		[7] = CharacterLegsSlot,
		[8] = CharacterFeetSlot,
		[9] = CharacterWristSlot,
		[10] = CharacterHandsSlot,
		[11] = CharacterFinger0Slot,
		[12] = CharacterFinger1Slot,
		[13] = CharacterTrinket0Slot,
		[14] = CharacterTrinket1Slot,
		[15] = CharacterBackSlot,
		[16] = CharacterMainHandSlot,
		[17] = CharacterSecondaryHandSlot,
		[18] = CharacterRangedSlot,
		[19] = CharacterTabardSlot,
		[20] = CharacterAmmoSlot,
	}

	for i, slotFrame in ipairs(slots) do
		local slotFrameName = slotFrame:GetName()
		local icon = _G[slotFrameName.."IconTexture"]

		WSkin:StripTextures(slotFrame)
		WSkin:StyleButton(slotFrame, false)
		WSkin:SetTemplate(slotFrame, "Default", true, true)

		if icon then
			WSkin:SetInside(icon)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end

		slotFrame:SetFrameLevel(PaperDollFrame:GetFrameLevel() + 2)

		if i ~= 20 then
			local popout = _G[slotFrameName.."PopoutButton"]
			if popout then
				WSkin:StripTextures(popout)
				popout:HookScript("OnEnter", popoutButtonOnEnter)
				popout:HookScript("OnLeave", popoutButtonOnLeave)

				popout.icon = popout:CreateTexture(nil, "ARTWORK")
				popout.WSkin:Size(icon, 16)
				popout.icon:SetPoint("CENTER")
				popout.icon:SetTexture("Interface\\Buttons\\Arrow-Down-Up")

				if slotFrame.verticalFlyout then
					popout.icon:SetTexCoord(0, 1, 0, 1)
				else
					popout.icon:SetTexCoord(0, 1, 1, 0)
				end
			end
		end
	end

	local function updateSlotFrame(self, event, slotID, exist)
		if event then
			self = slots[slotID]
		end
		if not self then return end

		if exist then
			local quality = GetInventoryItemQuality("player", self:GetID())
			if quality then
				self:SetBackdropBorderColor(GetItemQualityColor(quality))
			else
				self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
			end
		else
			self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
		end
	end

	local function colorItemBorder()
		for _, slotFrame in ipairs(slots) do
			local slotID = slotFrame:GetID()
			updateSlotFrame(slotFrame, nil, slotID, GetInventoryItemTexture("player", slotID) ~= nil)
		end
	end

	if CharacterAmmoSlotIconTexture then
		hooksecurefunc(CharacterAmmoSlotIconTexture, "SetTexture", function(self, texture)
			local parent = self:GetParent()
			updateSlotFrame(parent, nil, 0, texture ~= parent.backgroundTextureName)
		end)
	end

	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	f:SetScript("OnEvent", updateSlotFrame)

	CharacterFrame:HookScript("OnShow", colorItemBorder)
	colorItemBorder()

	local nStripped = 0
	if PaperDollFrameItemFlyoutButtons then
		hooksecurefunc("PaperDollFrameItemFlyout_Show", function()
			if nStripped < PaperDollFrameItemFlyoutButtons.numBGs then
				nStripped = PaperDollFrameItemFlyoutButtons.numBGs
				WSkin:StripTextures(PaperDollFrameItemFlyoutButtons)
			end
		end)
	end

	hooksecurefunc("PaperDollFrameItemFlyout_DisplayButton", function(button)
		if not button.isSkinned then
			button.icon = _G[button:GetName().."IconTexture"]

			local norm = button:GetNormalTexture()
			if norm then norm:SetTexture(nil) end
			WSkin:SetTemplate(button, "Default")
			WSkin:StyleButton(button)

			if button.icon then
				button.WSkin:SetInside(icon)
				button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end
			button.isSkinned = true
		end

		if not button.location or button.location >= 100000 then return end

		local id = EquipmentManager_GetItemInfoByLocation(button.location)
		if id then
			local _, _, quality = GetItemInfo(id)
			if quality then
				button:SetBackdropBorderColor(GetItemQualityColor(quality))
				return
			end
		end
		button:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
	end)

	local function handleResistanceFrame(frameName)
		for i = 1, 5 do
			local frame = _G[frameName..i]
			if frame then
				WSkin:Size(frame, 24)
				WSkin:SetTemplate(frame, "Default")

				if i ~= 1 then
					local prevFrame = _G[frameName..i-1]
					if prevFrame then
						WSkin:Point(frame, "TOP", prevFrame, "BOTTOM", 0, -2)
					end
				end

				local texture, text = frame:GetRegions()
				if texture then
					WSkin:SetInside(texture)
					texture:SetDrawLayer("ARTWORK")
					if i == 1 then      -- Arcane
						texture:SetTexCoord(0.25, 0.8125, 0.25, 0.3203125)
					elseif i == 2 then  -- Fire
						texture:SetTexCoord(0.25, 0.8125, 0.0234375, 0.09375)
					elseif i == 3 then  -- Nature
						texture:SetTexCoord(0.25, 0.8125, 0.13671875, 0.20703125)
					elseif i == 4 then  -- Frost
						texture:SetTexCoord(0.25, 0.8125, 0.3671875, 0.4375)
					elseif i == 5 then  -- Shadow
						texture:SetTexCoord(0.25, 0.8125, 0.4765625, 0.546875)
					end
				end

				if text then
					text:SetDrawLayer("OVERLAY")
					WSkin:Point(text, "CENTER", -1, 0)
				end
			end
		end
	end

	handleResistanceFrame("MagicResFrame")

	-- GearManager Dialog
	if GearManagerDialog then
		WSkin:StripTextures(GearManagerDialog)
		WSkin:CreateBackdrop(GearManagerDialog, "Transparent")
		GearManagerDialog.WSkin:Point(backdrop, "TOPLEFT", 5, -2)
		GearManagerDialog.WSkin:Point(backdrop, "BOTTOMRIGHT", -3, 4)

		WSkin:SetBackdropHitRect(GearManagerDialog)
		WSkin:HandleCloseButton(GearManagerDialogClose, GearManagerDialog.backdrop)

		if GearManagerDialog.buttons then
			for i, button in ipairs(GearManagerDialog.buttons) do
				WSkin:StripTextures(button)
				WSkin:CreateBackdrop(button, "Default")
				button.backdrop:SetAllPoints()
				WSkin:StyleButton(button, nil, true)

				if button.icon then
					button.WSkin:SetInside(icon)
					button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				end
			end
		end

		WSkin:HandleButton(GearManagerDialogDeleteSet)
		WSkin:HandleButton(GearManagerDialogEquipSet)
		WSkin:HandleButton(GearManagerDialogSaveSet)

		if GearSetButton1 then WSkin:Point(GearSetButton1, "TOPLEFT", 15, -29) end
		if GearSetButton6 then WSkin:Point(GearSetButton6, "TOP", GearSetButton1, "BOTTOM", 0, -13) end

		WSkin:Point(GearManagerDialogDeleteSet, "BOTTOMLEFT", 11, 12)
		WSkin:Point(GearManagerDialogEquipSet, "BOTTOMLEFT", 92, 12)
		WSkin:Point(GearManagerDialogSaveSet, "BOTTOMRIGHT", -10, 12)
	end

	-- GearManager DialogPopup
	if GearManagerDialogPopup then
		GearManagerDialogPopup:EnableMouse(true)
		WSkin:StripTextures(GearManagerDialogPopup)
		WSkin:CreateBackdrop(GearManagerDialogPopup, "Transparent")
		GearManagerDialogPopup.WSkin:Point(backdrop, "TOPLEFT", 5, -10)
		GearManagerDialogPopup.WSkin:Point(backdrop, "BOTTOMRIGHT", -39, 8)

		WSkin:SetBackdropHitRect(GearManagerDialogPopup)
		WSkin:StripTextures(GearManagerDialogPopupScrollFrame)
		WSkin:HandleScrollBar(GearManagerDialogPopupScrollFrameScrollBar)
		WSkin:HandleEditBox(GearManagerDialogPopupEditBox)

		if GearManagerDialogPopup.buttons then
			for i, button in ipairs(GearManagerDialogPopup.buttons) do
				WSkin:StripTextures(button)
				button:SetFrameLevel(button:GetFrameLevel() + 2)
				WSkin:CreateBackdrop(button, "Default")
				button.backdrop:SetAllPoints()
				WSkin:StyleButton(button, true, true)

				if button.icon then
					button.WSkin:SetInside(icon)
					button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				end

				if i > 1 then
					local lastPos = (i - 1) / 5
					if lastPos == math.floor(lastPos) then
						button:SetPoint("TOPLEFT", GearManagerDialogPopup.buttons[i-5], "BOTTOMLEFT", 0, -7)
					else
						button:SetPoint("TOPLEFT", GearManagerDialogPopup.buttons[i-1], "TOPRIGHT", 7, 0)
					end
				end
			end
		end

		WSkin:HandleButton(GearManagerDialogPopupOkay)
		WSkin:HandleButton(GearManagerDialogPopupCancel)

		local text1 = select(5, GearManagerDialogPopup:GetRegions())
		if text1 then WSkin:Point(text1, "TOPLEFT", 24, -19) end

		WSkin:Point(GearManagerDialogPopupEditBox, "TOPLEFT", 24, -36)
		if GearManagerDialogPopupButton1 then WSkin:Point(GearManagerDialogPopupButton1, "TOPLEFT", 17, -83) end

		WSkin:SetTemplate(GearManagerDialogPopupScrollFrame, "Transparent")
		WSkin:Size(GearManagerDialogPopupScrollFrame, 216, 130)
		WSkin:Point(GearManagerDialogPopupScrollFrame, "TOPRIGHT", -68, -79)
		WSkin:Point(GearManagerDialogPopupScrollFrameScrollBar, "TOPLEFT", GearManagerDialogPopupScrollFrame, "TOPRIGHT", 3, -19)
		WSkin:Point(GearManagerDialogPopupScrollFrameScrollBar, "BOTTOMLEFT", GearManagerDialogPopupScrollFrame, "BOTTOMRIGHT", 3, 19)

		WSkin:Point(GearManagerDialogPopupOkay, "BOTTOMRIGHT", GearManagerDialogPopupCancel, "BOTTOMLEFT", -3, 0)
		WSkin:Point(GearManagerDialogPopupCancel, "BOTTOMRIGHT", -47, 16)
	end

	-- PetPaperDollFrame
	WSkin:StripTextures(PetPaperDollFrame, true)

	for i = 1, 3 do
		local tab = _G["PetPaperDollFrameTab"..i]
		if tab then
			WSkin:StripTextures(tab)
			WSkin:CreateBackdrop(tab, "Default", true)
			tab.WSkin:Point(backdrop, "TOPLEFT", 2, -7)
			tab.WSkin:Point(backdrop, "BOTTOMRIGHT", -1, -1)
			WSkin:SetBackdropHitRect(tab)

			tab:HookScript("OnEnter", WSkin.SetModifiedBackdrop)
			tab:HookScript("OnLeave", WSkin.SetOriginalBackdrop)
		end
	end

	WSkin:HandleRotateButton(PetModelFrameRotateLeftButton)
	WSkin:HandleRotateButton(PetModelFrameRotateRightButton)

	handleResistanceFrame("PetMagicResFrame")
	WSkin:StripTextures(PetAttributesFrame)

	WSkin:StripTextures(PetPaperDollFrameExpBar)
	WSkin:CreateBackdrop(PetPaperDollFrameExpBar, "Default")
	PetPaperDollFrameExpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

	WSkin:HandleButton(PetPaperDollCloseButton)

	local function updateHappiness(self)
		local _, isHunterPet = HasPetUI()
		local happiness = GetPetHappiness()
		if not isHunterPet or not happiness then return end

		local textureRegion = self:GetRegions()
		if textureRegion then
			if happiness == 1 then
				textureRegion:SetTexCoord(0.40625, 0.53125, 0.0625, 0.3125)
			elseif happiness == 2 then
				textureRegion:SetTexCoord(0.21875, 0.34375, 0.0625, 0.3125)
			elseif happiness == 3 then
				textureRegion:SetTexCoord(0.03125, 0.15625, 0.0625, 0.3125)
			end
		end
	end

	WSkin:Width(PetModelFrame, 325)
	WSkin:Point(PetModelFrame, "TOPLEFT", 19, -71)

	WSkin:Point(PetModelFrameRotateLeftButton, "TOPLEFT", PetPaperDollFrame, "TOPLEFT", 23, -75)
	WSkin:Point(PetModelFrameRotateRightButton, "TOPLEFT", PetModelFrameRotateLeftButton, "TOPRIGHT", 3, 0)

	WSkin:Point(PetResistanceFrame, "TOPRIGHT", PetPaperDollFrame, "TOPLEFT", 344, -75)

	PetPaperDollPetInfo:SetFrameLevel(PetModelFrame:GetFrameLevel() + 2)
	WSkin:CreateBackdrop(PetPaperDollPetInfo, "Default")
	WSkin:Size(PetPaperDollPetInfo, 25)
	WSkin:Point(PetPaperDollPetInfo, "TOPLEFT", PetModelFrameRotateLeftButton, "BOTTOMLEFT", 10, -4)

	local infoTexture = PetPaperDollPetInfo:GetRegions()
	if infoTexture then
		infoTexture:SetTexCoord(0.03125, 0.15625, 0.0625, 0.3125)
	end

	PetPaperDollPetInfo:RegisterEvent("UNIT_HAPPINESS")
	PetPaperDollPetInfo:SetScript("OnEvent", updateHappiness)
	PetPaperDollPetInfo:SetScript("OnShow", updateHappiness)
	updateHappiness(PetPaperDollPetInfo)

	WSkin:Point(PetLevelText, "CENTER", 0, -50)
	WSkin:Point(PetAttributesFrame, "TOPLEFT", 67, -310)

	WSkin:Width(PetPaperDollFrameExpBar, 323)
	WSkin:Point(PetPaperDollFrameExpBar, "BOTTOMLEFT", 20, 112)

	WSkin:Point(PetPaperDollCloseButton, "CENTER", PetPaperDollFramePetFrame, "TOPLEFT", 304, -417)

	-- CompanionFrame
	WSkin:StripTextures(PetPaperDollFrameCompanionFrame)

	WSkin:HandleRotateButton(CompanionModelFrameRotateLeftButton)
	WSkin:HandleRotateButton(CompanionModelFrameRotateRightButton)

	WSkin:HandleButton(CompanionSummonButton)
	WSkin:HandleNextPrevButton(CompanionPrevPageButton)
	WSkin:HandleNextPrevButton(CompanionNextPageButton)

	hooksecurefunc("PetPaperDollFrame_UpdateCompanions", function()
		for i = 1, 12 do
			local button = _G["CompanionButton"..i]
			if button and button.creatureID then
				local iconNormal = button:GetNormalTexture()
				if iconNormal then
					iconNormal:SetTexCoord(0.08, 0.92, 0.08, 0.92)
					WSkin:SetInside(iconNormal)
				end
			end
		end
	end)

	for i = 1, 12 do
		local button = _G["CompanionButton"..i]
		if button then
			local iconDisabled = button:GetDisabledTexture()
			local activeTexture = _G["CompanionButton"..i.."ActiveTexture"]

			WSkin:StyleButton(button, nil, true)
			WSkin:SetTemplate(button, "Default", true)

			if iconDisabled then iconDisabled:SetAlpha(0) end

			if activeTexture then
				WSkin:SetInside(activeTexture, button)
				activeTexture:SetTexture(1, 1, 1, .15)
			end

			if i == 7 then
				WSkin:Point(button, "TOP", CompanionButton1, "BOTTOM", 0, -5)
			elseif i ~= 1 then
				local prevBtn = _G["CompanionButton"..i-1]
				if prevBtn then
					WSkin:Point(button, "LEFT", prevBtn, "RIGHT", 5, 0)
				end
			end
		end
	end

	WSkin:Size(CompanionModelFrame, 325, 174)
	WSkin:Point(CompanionModelFrame, "TOPLEFT", 19, -71)

	WSkin:Point(CompanionModelFrameRotateLeftButton, "TOPLEFT", PetPaperDollFrame, "TOPLEFT", 23, -75)
	WSkin:Point(CompanionModelFrameRotateRightButton, "TOPLEFT", CompanionModelFrameRotateLeftButton, "TOPRIGHT", 3, 0)

	if CompanionButton1 then WSkin:Point(CompanionButton1, "TOPLEFT", 58, -308) end

	WSkin:Width(CompanionSummonButton, 149)
	WSkin:Point(CompanionSummonButton, "CENTER", -11, -24)

	WSkin:Point(CompanionPrevPageButton, "BOTTOMLEFT", 122, 92)
	WSkin:Point(CompanionNextPageButton, "LEFT", CompanionPrevPageButton, "RIGHT", 83, 0)

	WSkin:Point(CompanionPageNumber, "CENTER", -10, -155)

	-- Reputation Frame
	WSkin:StripTextures(ReputationFrame, true)

	for i = 1, 15 do
		local factionRow = _G["ReputationBar"..i]
		local factionBar = _G["ReputationBar"..i.."ReputationBar"]
		local factionButton = _G["ReputationBar"..i.."ExpandOrCollapseButton"]

		if factionRow then WSkin:StripTextures(factionRow, true) end

		if factionBar then
			WSkin:StripTextures(factionBar)
			factionBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
			WSkin:CreateBackdrop(factionBar, "Default")
		end

		if factionButton then
			factionButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
			factionButton.SetNormalTexture = function() end
			WSkin:Size(factionButton:GetNormalTexture(), 15)
			factionButton:SetHighlightTexture(nil)
		end
	end

	hooksecurefunc("ReputationFrame_Update", function()
		local factionOffset = FauxScrollFrame_GetOffset(ReputationListScrollFrame)
		local numFactions = GetNumFactions()
		local factionIndex, factionButton

		for i = 1, 15 do
			factionIndex = factionOffset + i

			if factionIndex <= numFactions then
				factionButton = _G["ReputationBar"..i.."ExpandOrCollapseButton"]
				local row = _G["ReputationBar"..i]

				if factionButton and row then
					if row.isCollapsed then
						factionButton:GetNormalTexture():SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
					else
						factionButton:GetNormalTexture():SetTexture("Interface\\Buttons\\UI-MinusButton-UP")
					end
				end
			end
		end
	end)

	WSkin:StripTextures(ReputationListScrollFrame)
	WSkin:HandleScrollBar(ReputationListScrollFrameScrollBar)

	WSkin:Point(ReputationFrameFactionLabel, "TOPLEFT", 70, -60)
	WSkin:Point(ReputationFrameStandingLabel, "TOPLEFT", 235, -60)

	if ReputationBar1 then WSkin:Point(ReputationBar1, "TOPRIGHT", -51, -81) end

	WSkin:Width(ReputationListScrollFrame, 304)
	WSkin:Point(ReputationListScrollFrame, "TOPRIGHT", -61, -74)
	WSkin:Point(ReputationListScrollFrameScrollBar, "TOPLEFT", ReputationListScrollFrame, "TOPRIGHT", 3, -19)
	WSkin:Point(ReputationListScrollFrameScrollBar, "BOTTOMLEFT", ReputationListScrollFrame, "BOTTOMRIGHT", 3, 19)

	ReputationListScrollFrame:SetScript("OnShow", function()
		if ReputationBar1 then WSkin:Point(ReputationBar1, "TOPRIGHT", -75, -81) end
	end)
	ReputationListScrollFrame:SetScript("OnHide", function()
		if ReputationBar1 then WSkin:Point(ReputationBar1, "TOPRIGHT", -51, -81) end
	end)

	-- Reputation DetailFrame
	WSkin:StripTextures(ReputationDetailFrame)
	WSkin:SetTemplate(ReputationDetailFrame, "Transparent")
	WSkin:Point(ReputationDetailFrame, "TOPLEFT", ReputationFrame, "TOPRIGHT", -33, -12)

	WSkin:HandleCloseButton(ReputationDetailCloseButton, ReputationDetailFrame)

	WSkin:HandleCheckBox(ReputationDetailAtWarCheckBox)
	if ReputationDetailAtWarCheckBox then
		ReputationDetailAtWarCheckBox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-SwordCheck")
	end
	WSkin:HandleCheckBox(ReputationDetailInactiveCheckBox)
	WSkin:HandleCheckBox(ReputationDetailMainScreenCheckBox)

	-- Skill Frame
	WSkin:StripTextures(SkillFrame, true)
	WSkin:StripTextures(SkillFrameExpandButtonFrame)
	WSkin:HandleCollapseExpandButton(SkillFrameCollapseAllButton, "+")

	for i = 1, 12 do
		local statusBar = _G["SkillRankFrame"..i]
		local statusBarBorder = _G["SkillRankFrame"..i.."Border"]
		local statusBarBackground = _G["SkillRankFrame"..i.."Background"]
		local skillTypeLabel = _G["SkillTypeLabel"..i]

		if statusBar then
			WSkin:Width(statusBar, 276)
			WSkin:CreateBackdrop(statusBar, "Default")
			statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		end

		if statusBarBorder then WSkin:StripTextures(statusBarBorder) end
		if statusBarBackground then statusBarBackground:SetTexture(nil) end

		if skillTypeLabel then
			WSkin:HandleCollapseExpandButton(skillTypeLabel, "+")
		end
	end

	WSkin:StripTextures(SkillDetailStatusBar)
	SkillDetailStatusBar:SetParent(SkillDetailScrollFrame)
	WSkin:CreateBackdrop(SkillDetailStatusBar, "Default")
	SkillDetailStatusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

	WSkin:HandleCloseButton(SkillDetailStatusBarUnlearnButton)
	if SkillDetailStatusBarUnlearnButton then
		SkillDetailStatusBarUnlearnButton:SetPoint("LEFT", SkillDetailStatusBarBorder, "RIGHT")
		if SkillDetailStatusBarUnlearnButton.Texture then
			SkillDetailStatusBarUnlearnButton.WSkin:Size(Texture, 16)
			SkillDetailStatusBarUnlearnButton.Texture:SetVertexColor(1, 0, 0)
		end
		SkillDetailStatusBarUnlearnButton:HookScript("OnEnter", function(btn) if btn.Texture then btn.Texture:SetVertexColor(1, 1, 1) end end)
		SkillDetailStatusBarUnlearnButton:HookScript("OnLeave", function(btn) if btn.Texture then btn.Texture:SetVertexColor(1, 0, 0) end end)
	end

	WSkin:StripTextures(SkillListScrollFrame)
	WSkin:HandleScrollBar(SkillListScrollFrameScrollBar)

	WSkin:StripTextures(SkillDetailScrollFrame)
	WSkin:HandleScrollBar(SkillDetailScrollFrameScrollBar)

	WSkin:HandleButton(SkillFrameCancelButton)

	WSkin:Point(SkillFrameExpandButtonFrame, "TOPLEFT", 30, -50)

	if SkillTypeLabel1 then WSkin:Point(SkillTypeLabel1, "LEFT", SkillFrame, "TOPLEFT", 22, -85) end
	if SkillRankFrame1 then WSkin:Point(SkillRankFrame1, "TOPLEFT", 38, -78) end

	WSkin:Width(SkillListScrollFrame, 304)
	WSkin:Point(SkillListScrollFrame, "TOPRIGHT", -61, -74)

	WSkin:Point(SkillListScrollFrameScrollBar, "TOPLEFT", SkillListScrollFrame, "TOPRIGHT", 3, -19)
	WSkin:Point(SkillListScrollFrameScrollBar, "BOTTOMLEFT", SkillListScrollFrame, "BOTTOMRIGHT", 3, 19)

	WSkin:Size(SkillDetailScrollFrame, 304, 98)
	WSkin:Point(SkillDetailScrollFrame, "TOPLEFT", SkillListScrollFrame, "BOTTOMLEFT", 0, -7)

	WSkin:Point(SkillDetailScrollFrameScrollBar, "TOPLEFT", SkillDetailScrollFrame, "TOPRIGHT", 3, -19)
	WSkin:Point(SkillDetailScrollFrameScrollBar, "BOTTOMLEFT", SkillDetailScrollFrame, "BOTTOMRIGHT", 3, 19)

	WSkin:Point(SkillFrameCancelButton, "CENTER", SkillFrame, "TOPLEFT", 304, -417)

	-- Token Frame
	local function skinTokenFrame()
		if not TokenFrame then return end
		WSkin:StripTextures(TokenFrame, true)

		local tChildren = {TokenFrame:GetChildren()}
		if tChildren[4] then tChildren[4]:Hide() end

		WSkin:HandleScrollBar(TokenFrameContainerScrollBar)
		WSkin:HandleButton(TokenFrameCancelButton)

		WSkin:Size(TokenFrameContainer, 304, 360)
		WSkin:Point(TokenFrameContainer, "TOPLEFT", 19, -39)

		WSkin:Point(TokenFrameContainerScrollBar, "TOPLEFT", TokenFrameContainer, "TOPRIGHT", 3, -19)
		WSkin:Point(TokenFrameContainerScrollBar, "BOTTOMLEFT", TokenFrameContainer, "BOTTOMRIGHT", 3, 19)

		WSkin:Point(TokenFrameMoneyFrame, "BOTTOMRIGHT", -115, 88)
		WSkin:Point(TokenFrameCancelButton, "CENTER", TokenFrame, "TOPLEFT", 304, -417)

		TokenFrameContainerScrollBar.Show = function(self)
			TokenFrameContainer:SetWidth(304)
			if TokenFrameContainer.buttons then
				for _, button in ipairs(TokenFrameContainer.buttons) do
					button:SetWidth(300)
				end
			end
			local mt = getmetatable(self)
			if mt and mt.__index and mt.__index.Show then mt.__index.Show(self) end
		end

		TokenFrameContainerScrollBar.Hide = function(self)
			TokenFrameContainer:SetWidth(325)
			if TokenFrameContainer.buttons then
				for _, button in ipairs(TokenFrameContainer.buttons) do
					button:SetWidth(325)
				end
			end
			local mt = getmetatable(self)
			if mt and mt.__index and mt.__index.Hide then mt.__index.Hide(self) end
		end

		local function skinTokenButton(button)
			if not button.isSkinned then
				if button.categoryLeft then button.categoryLeft:Hide() end
				if button.categoryRight then button.categoryRight:Hide() end
				if button.highlight then button.highlight:SetTexture(nil) end

				if button.expandIcon then
					button.WSkin:Size(expandIcon, 16)
					button.expandIcon:SetTexCoord(0, 1, 0, 1)
					button.expandIcon.SetTexCoord = function() end
				end
				button.isSkinned = true
			end
		end

		local tokenSkinned = 0

		local function updateTokenContainer()
			local offset = HybridScrollFrame_GetOffset(TokenFrameContainer)
			local buttons = TokenFrameContainer.buttons
			if not buttons then return end
			local numButtons = #buttons
			local index, button
			local name, isHeader, isExpanded, extraCurrencyType, icon

			if numButtons > tokenSkinned then
				for i = tokenSkinned + 1, numButtons do
					skinTokenButton(buttons[i])
				end
				tokenSkinned = numButtons
			end

			for i = 1, numButtons do
				index = offset + i
				button = buttons[i]

				name, isHeader, isExpanded, _, _, _, extraCurrencyType, icon = GetCurrencyListInfo(index)

				if name and button then
					if isHeader then
						if isExpanded then
							if button.expandIcon then button.expandIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-UP") end
						else
							if button.expandIcon then button.expandIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-UP") end
						end
					else
						if extraCurrencyType == 1 then
							if button.icon then button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
						elseif extraCurrencyType == 2 then
							local factionGroup = UnitFactionGroup("player")
							if factionGroup and button.icon then
								button.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-"..factionGroup)
								button.icon:SetTexCoord(0.0625, 0.625, 0.015625, 0.578125)
							elseif button.icon then
								button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
							end
						else
							if button.icon then
								button.icon:SetTexture(icon)
								button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
							end
						end
					end
				end
			end
		end

		hooksecurefunc("TokenFrame_Update", updateTokenContainer)
		hooksecurefunc(TokenFrameContainer, "update", updateTokenContainer)

		WSkin:StripTextures(TokenFramePopup)
		WSkin:SetTemplate(TokenFramePopup, "Transparent")

		WSkin:HandleCloseButton(TokenFramePopupCloseButton, TokenFramePopup)
		WSkin:HandleCheckBox(TokenFramePopupInactiveCheckBox)
		WSkin:HandleCheckBox(TokenFramePopupBackpackCheckBox)

		WSkin:Point(TokenFramePopup, "TOPLEFT", TokenFrame, "TOPRIGHT", -33, -12)
	end

	if TokenFrame then
		skinTokenFrame()
	else
		local tf = CreateFrame("Frame")
		tf:RegisterEvent("ADDON_LOADED")
		tf:SetScript("OnEvent", function(self, event, name)
			if name == "Blizzard_TokenUI" then
				skinTokenFrame()
				self:UnregisterEvent("ADDON_LOADED")
			end
		end)
	end
end)
