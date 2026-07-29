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
	CharacterFrame:StripTextures(true)
	CharacterFrame:CreateBackdrop("Transparent")
	CharacterFrame.backdrop:Point("TOPLEFT", 11, -12)
	CharacterFrame.backdrop:Point("BOTTOMRIGHT", -32, 76)

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

	PaperDollFrame:StripTextures(true)

	for i = 1, #CHARACTERFRAME_SUBFRAMES do
		local tab = _G["CharacterFrameTab"..i]
		if tab then
			WSkin:HandleTab(tab)
		end
	end

	hooksecurefunc("PetPaperDollFrame_UpdateIsAvailable", function()
		if not PetPaperDollFrame.hidden and CharacterFrameTab3 then
			CharacterFrameTab3:Point("LEFT", "CharacterFrameTab2", "RIGHT", -15, 0)
		end
	end)

	-- PaperDollFrame
	PlayerTitleFrame:StripTextures()
	PlayerTitleFrame:CreateBackdrop("Default")
	PlayerTitleFrame.backdrop:Point("TOPLEFT", 20, 3)
	PlayerTitleFrame.backdrop:Point("BOTTOMRIGHT", -16, 15)
	PlayerTitleFrame.backdrop:SetFrameLevel(PlayerTitleFrame:GetFrameLevel())

	WSkin:HandleNextPrevButton(PlayerTitleFrameButton)
	PlayerTitleFrameButton:Size(16, 16)
	PlayerTitleFrameButton:Point("TOPRIGHT", PlayerTitleFrameRight, "TOPRIGHT", -18, -16)

	PlayerTitlePickerFrame:StripTextures()
	PlayerTitlePickerFrame:CreateBackdrop("Transparent")
	PlayerTitlePickerFrame.backdrop:Point("TOPLEFT", 6, -10)
	PlayerTitlePickerFrame.backdrop:Point("BOTTOMRIGHT", -13, 6)
	PlayerTitlePickerFrame.backdrop:SetFrameLevel(PlayerTitlePickerFrame:GetFrameLevel())
	WSkin:HandleScrollBar(PlayerTitlePickerScrollFrameScrollBar)

	PlayerTitlePickerScrollFrameScrollBar:Point("TOPLEFT", PlayerTitlePickerScrollFrame, "TOPRIGHT", 1, -14)
	PlayerTitlePickerScrollFrameScrollBar:Point("BOTTOMLEFT", PlayerTitlePickerScrollFrame, "BOTTOMRIGHT", 1, 15)

	if PlayerTitlePickerScrollFrame.buttons then
		for _, button in ipairs(PlayerTitlePickerScrollFrame.buttons) do
			if button.text then
				button.text:SetFontObject("GameFontNormal")
			end
		end
	end

	WSkin:HandleRotateButton(CharacterModelFrameRotateLeftButton)
	WSkin:HandleRotateButton(CharacterModelFrameRotateRightButton)

	PlayerStatFrameLeftDropDown:Point("BOTTOMLEFT", PlayerStatLeftTop, "TOPLEFT", -19, -8)
	WSkin:HandleDropDownBox(PlayerStatFrameLeftDropDown, 140, "down")
	WSkin:HandleDropDownBox(PlayerStatFrameRightDropDown, 140, "down")

	CharacterAttributesFrame:StripTextures()

	if PaperDollFrameItemFlyoutButtons then PaperDollFrameItemFlyoutButtons:EnableMouse(false) end
	if PaperDollFrameItemFlyoutHighlight then PaperDollFrameItemFlyoutHighlight:Hide() end

	GearManagerToggleButton:Size(25, 29)
	GearManagerToggleButton:Point("TOPRIGHT", -46, -40)
	GearManagerToggleButton:CreateBackdrop("Default")
	local gNormal = GearManagerToggleButton:GetNormalTexture()
	if gNormal then gNormal:SetTexCoord(0.203125, 0.828125, 0.15625, 0.875) end
	local gPushed = GearManagerToggleButton:GetPushedTexture()
	if gPushed then gPushed:SetTexCoord(0.1875, 0.8125, 0.1875, 0.90625) end
	local gHighlight = GearManagerToggleButton:GetHighlightTexture()
	if gHighlight then
		gHighlight:SetTexture(1, 1, 1, 0.3)
		gHighlight:SetAllPoints()
	end

	PlayerTitleFrame:Point("TOP", CharacterLevelText, "BOTTOM", -7, -7)
	PlayerTitlePickerFrame:Point("TOPLEFT", PlayerTitleFrame, "BOTTOMLEFT", 14, 26)

	CharacterModelFrame:Size(237, 217)
	CharacterModelFrame:Point("TOPLEFT", 63, -76)

	CharacterModelFrameRotateLeftButton:Point("TOPLEFT", 4, -4)
	CharacterModelFrameRotateRightButton:Point("TOPLEFT", CharacterModelFrameRotateLeftButton, "TOPRIGHT", 3, 0)

	CharacterResistanceFrame:Point("TOPRIGHT", PaperDollFrame, "TOPLEFT", 300, -81)

	CharacterHeadSlot:Point("TOPLEFT", 19, -76)
	CharacterHandsSlot:Point("TOPLEFT", 307, -76)
	CharacterMainHandSlot:Point("TOPLEFT", PaperDollFrame, "BOTTOMLEFT", 110, 131)
	CharacterAttributesFrame:Point("TOPLEFT", 66, -292)

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

		slotFrame:StripTextures()
		slotFrame:StyleButton(false)
		slotFrame:SetTemplate("Default", true, true)

		if icon then
			icon:SetInside()
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end

		slotFrame:SetFrameLevel(PaperDollFrame:GetFrameLevel() + 2)

		if i ~= 20 then
			local popout = _G[slotFrameName.."PopoutButton"]
			if popout then
				popout:StripTextures()
				popout:HookScript("OnEnter", popoutButtonOnEnter)
				popout:HookScript("OnLeave", popoutButtonOnLeave)

				popout.icon = popout:CreateTexture(nil, "ARTWORK")
				popout.icon:Size(16)
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
				PaperDollFrameItemFlyoutButtons:StripTextures()
			end
		end)
	end

	hooksecurefunc("PaperDollFrameItemFlyout_DisplayButton", function(button)
		if not button.isSkinned then
			button.icon = _G[button:GetName().."IconTexture"]

			local norm = button:GetNormalTexture()
			if norm then norm:SetTexture(nil) end
			button:SetTemplate("Default")
			button:StyleButton()

			if button.icon then
				button.icon:SetInside()
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
				frame:Size(24)
				frame:SetTemplate("Default")

				if i ~= 1 then
					local prevFrame = _G[frameName..i-1]
					if prevFrame then
						frame:Point("TOP", prevFrame, "BOTTOM", 0, -2)
					end
				end

				local texture, text = frame:GetRegions()
				if texture then
					texture:SetInside()
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
					text:Point("CENTER", -1, 0)
				end
			end
		end
	end

	handleResistanceFrame("MagicResFrame")

	-- GearManager Dialog
	if GearManagerDialog then
		GearManagerDialog:StripTextures()
		GearManagerDialog:CreateBackdrop("Transparent")
		GearManagerDialog.backdrop:Point("TOPLEFT", 5, -2)
		GearManagerDialog.backdrop:Point("BOTTOMRIGHT", -3, 4)

		WSkin:SetBackdropHitRect(GearManagerDialog)
		WSkin:HandleCloseButton(GearManagerDialogClose, GearManagerDialog.backdrop)

		if GearManagerDialog.buttons then
			for i, button in ipairs(GearManagerDialog.buttons) do
				button:StripTextures()
				button:CreateBackdrop("Default")
				button.backdrop:SetAllPoints()
				button:StyleButton(nil, true)

				if button.icon then
					button.icon:SetInside()
					button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				end
			end
		end

		WSkin:HandleButton(GearManagerDialogDeleteSet)
		WSkin:HandleButton(GearManagerDialogEquipSet)
		WSkin:HandleButton(GearManagerDialogSaveSet)

		if GearSetButton1 then GearSetButton1:Point("TOPLEFT", 15, -29) end
		if GearSetButton6 then GearSetButton6:Point("TOP", GearSetButton1, "BOTTOM", 0, -13) end

		GearManagerDialogDeleteSet:Point("BOTTOMLEFT", 11, 12)
		GearManagerDialogEquipSet:Point("BOTTOMLEFT", 92, 12)
		GearManagerDialogSaveSet:Point("BOTTOMRIGHT", -10, 12)
	end

	-- GearManager DialogPopup
	if GearManagerDialogPopup then
		GearManagerDialogPopup:EnableMouse(true)
		GearManagerDialogPopup:StripTextures()
		GearManagerDialogPopup:CreateBackdrop("Transparent")
		GearManagerDialogPopup.backdrop:Point("TOPLEFT", 5, -10)
		GearManagerDialogPopup.backdrop:Point("BOTTOMRIGHT", -39, 8)

		WSkin:SetBackdropHitRect(GearManagerDialogPopup)
		GearManagerDialogPopupScrollFrame:StripTextures()
		WSkin:HandleScrollBar(GearManagerDialogPopupScrollFrameScrollBar)
		WSkin:HandleEditBox(GearManagerDialogPopupEditBox)

		if GearManagerDialogPopup.buttons then
			for i, button in ipairs(GearManagerDialogPopup.buttons) do
				button:StripTextures()
				button:SetFrameLevel(button:GetFrameLevel() + 2)
				button:CreateBackdrop("Default")
				button.backdrop:SetAllPoints()
				button:StyleButton(true, true)

				if button.icon then
					button.icon:SetInside()
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
		if text1 then text1:Point("TOPLEFT", 24, -19) end

		GearManagerDialogPopupEditBox:Point("TOPLEFT", 24, -36)
		if GearManagerDialogPopupButton1 then GearManagerDialogPopupButton1:Point("TOPLEFT", 17, -83) end

		GearManagerDialogPopupScrollFrame:SetTemplate("Transparent")
		GearManagerDialogPopupScrollFrame:Size(216, 130)
		GearManagerDialogPopupScrollFrame:Point("TOPRIGHT", -68, -79)
		GearManagerDialogPopupScrollFrameScrollBar:Point("TOPLEFT", GearManagerDialogPopupScrollFrame, "TOPRIGHT", 3, -19)
		GearManagerDialogPopupScrollFrameScrollBar:Point("BOTTOMLEFT", GearManagerDialogPopupScrollFrame, "BOTTOMRIGHT", 3, 19)

		GearManagerDialogPopupOkay:Point("BOTTOMRIGHT", GearManagerDialogPopupCancel, "BOTTOMLEFT", -3, 0)
		GearManagerDialogPopupCancel:Point("BOTTOMRIGHT", -47, 16)
	end

	-- PetPaperDollFrame
	PetPaperDollFrame:StripTextures(true)

	for i = 1, 3 do
		local tab = _G["PetPaperDollFrameTab"..i]
		if tab then
			tab:StripTextures()
			tab:CreateBackdrop("Default", true)
			tab.backdrop:Point("TOPLEFT", 2, -7)
			tab.backdrop:Point("BOTTOMRIGHT", -1, -1)
			WSkin:SetBackdropHitRect(tab)

			tab:HookScript("OnEnter", WSkin.SetModifiedBackdrop)
			tab:HookScript("OnLeave", WSkin.SetOriginalBackdrop)
		end
	end

	WSkin:HandleRotateButton(PetModelFrameRotateLeftButton)
	WSkin:HandleRotateButton(PetModelFrameRotateRightButton)

	handleResistanceFrame("PetMagicResFrame")
	PetAttributesFrame:StripTextures()

	PetPaperDollFrameExpBar:StripTextures()
	PetPaperDollFrameExpBar:CreateBackdrop("Default")
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

	PetModelFrame:Width(325)
	PetModelFrame:Point("TOPLEFT", 19, -71)

	PetModelFrameRotateLeftButton:Point("TOPLEFT", PetPaperDollFrame, "TOPLEFT", 23, -75)
	PetModelFrameRotateRightButton:Point("TOPLEFT", PetModelFrameRotateLeftButton, "TOPRIGHT", 3, 0)

	PetResistanceFrame:Point("TOPRIGHT", PetPaperDollFrame, "TOPLEFT", 344, -75)

	PetPaperDollPetInfo:SetFrameLevel(PetModelFrame:GetFrameLevel() + 2)
	PetPaperDollPetInfo:CreateBackdrop("Default")
	PetPaperDollPetInfo:Size(25)
	PetPaperDollPetInfo:Point("TOPLEFT", PetModelFrameRotateLeftButton, "BOTTOMLEFT", 10, -4)

	local infoTexture = PetPaperDollPetInfo:GetRegions()
	if infoTexture then
		infoTexture:SetTexCoord(0.03125, 0.15625, 0.0625, 0.3125)
	end

	PetPaperDollPetInfo:RegisterEvent("UNIT_HAPPINESS")
	PetPaperDollPetInfo:SetScript("OnEvent", updateHappiness)
	PetPaperDollPetInfo:SetScript("OnShow", updateHappiness)
	updateHappiness(PetPaperDollPetInfo)

	PetLevelText:Point("CENTER", 0, -50)
	PetAttributesFrame:Point("TOPLEFT", 67, -310)

	PetPaperDollFrameExpBar:Width(323)
	PetPaperDollFrameExpBar:Point("BOTTOMLEFT", 20, 112)

	PetPaperDollCloseButton:Point("CENTER", PetPaperDollFramePetFrame, "TOPLEFT", 304, -417)

	-- CompanionFrame
	PetPaperDollFrameCompanionFrame:StripTextures()

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
					iconNormal:SetInside()
				end
			end
		end
	end)

	for i = 1, 12 do
		local button = _G["CompanionButton"..i]
		if button then
			local iconDisabled = button:GetDisabledTexture()
			local activeTexture = _G["CompanionButton"..i.."ActiveTexture"]

			button:StyleButton(nil, true)
			button:SetTemplate("Default", true)

			if iconDisabled then iconDisabled:SetAlpha(0) end

			if activeTexture then
				activeTexture:SetInside(button)
				activeTexture:SetTexture(1, 1, 1, .15)
			end

			if i == 7 then
				button:Point("TOP", CompanionButton1, "BOTTOM", 0, -5)
			elseif i ~= 1 then
				local prevBtn = _G["CompanionButton"..i-1]
				if prevBtn then
					button:Point("LEFT", prevBtn, "RIGHT", 5, 0)
				end
			end
		end
	end

	CompanionModelFrame:Size(325, 174)
	CompanionModelFrame:Point("TOPLEFT", 19, -71)

	CompanionModelFrameRotateLeftButton:Point("TOPLEFT", PetPaperDollFrame, "TOPLEFT", 23, -75)
	CompanionModelFrameRotateRightButton:Point("TOPLEFT", CompanionModelFrameRotateLeftButton, "TOPRIGHT", 3, 0)

	if CompanionButton1 then CompanionButton1:Point("TOPLEFT", 58, -308) end

	CompanionSummonButton:Width(149)
	CompanionSummonButton:Point("CENTER", -11, -24)

	CompanionPrevPageButton:Point("BOTTOMLEFT", 122, 92)
	CompanionNextPageButton:Point("LEFT", CompanionPrevPageButton, "RIGHT", 83, 0)

	CompanionPageNumber:Point("CENTER", -10, -155)

	-- Reputation Frame
	ReputationFrame:StripTextures(true)

	for i = 1, 15 do
		local factionRow = _G["ReputationBar"..i]
		local factionBar = _G["ReputationBar"..i.."ReputationBar"]
		local factionButton = _G["ReputationBar"..i.."ExpandOrCollapseButton"]

		if factionRow then factionRow:StripTextures(true) end

		if factionBar then
			factionBar:StripTextures()
			factionBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
			factionBar:CreateBackdrop("Default")
		end

		if factionButton then
			factionButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
			factionButton.SetNormalTexture = function() end
			factionButton:GetNormalTexture():Size(15)
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

	ReputationListScrollFrame:StripTextures()
	WSkin:HandleScrollBar(ReputationListScrollFrameScrollBar)

	ReputationFrameFactionLabel:Point("TOPLEFT", 70, -60)
	ReputationFrameStandingLabel:Point("TOPLEFT", 235, -60)

	if ReputationBar1 then ReputationBar1:Point("TOPRIGHT", -51, -81) end

	ReputationListScrollFrame:Width(304)
	ReputationListScrollFrame:Point("TOPRIGHT", -61, -74)
	ReputationListScrollFrameScrollBar:Point("TOPLEFT", ReputationListScrollFrame, "TOPRIGHT", 3, -19)
	ReputationListScrollFrameScrollBar:Point("BOTTOMLEFT", ReputationListScrollFrame, "BOTTOMRIGHT", 3, 19)

	ReputationListScrollFrame:SetScript("OnShow", function()
		if ReputationBar1 then ReputationBar1:Point("TOPRIGHT", -75, -81) end
	end)
	ReputationListScrollFrame:SetScript("OnHide", function()
		if ReputationBar1 then ReputationBar1:Point("TOPRIGHT", -51, -81) end
	end)

	-- Reputation DetailFrame
	ReputationDetailFrame:StripTextures()
	ReputationDetailFrame:SetTemplate("Transparent")
	ReputationDetailFrame:Point("TOPLEFT", ReputationFrame, "TOPRIGHT", -33, -12)

	WSkin:HandleCloseButton(ReputationDetailCloseButton, ReputationDetailFrame)

	WSkin:HandleCheckBox(ReputationDetailAtWarCheckBox)
	if ReputationDetailAtWarCheckBox then
		ReputationDetailAtWarCheckBox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-SwordCheck")
	end
	WSkin:HandleCheckBox(ReputationDetailInactiveCheckBox)
	WSkin:HandleCheckBox(ReputationDetailMainScreenCheckBox)

	-- Skill Frame
	SkillFrame:StripTextures(true)
	SkillFrameExpandButtonFrame:StripTextures()
	WSkin:HandleCollapseExpandButton(SkillFrameCollapseAllButton, "+")

	for i = 1, 12 do
		local statusBar = _G["SkillRankFrame"..i]
		local statusBarBorder = _G["SkillRankFrame"..i.."Border"]
		local statusBarBackground = _G["SkillRankFrame"..i.."Background"]
		local skillTypeLabel = _G["SkillTypeLabel"..i]

		if statusBar then
			statusBar:Width(276)
			statusBar:CreateBackdrop("Default")
			statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		end

		if statusBarBorder then statusBarBorder:StripTextures() end
		if statusBarBackground then statusBarBackground:SetTexture(nil) end

		if skillTypeLabel then
			WSkin:HandleCollapseExpandButton(skillTypeLabel, "+")
		end
	end

	SkillDetailStatusBar:StripTextures()
	SkillDetailStatusBar:SetParent(SkillDetailScrollFrame)
	SkillDetailStatusBar:CreateBackdrop("Default")
	SkillDetailStatusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

	WSkin:HandleCloseButton(SkillDetailStatusBarUnlearnButton)
	if SkillDetailStatusBarUnlearnButton then
		SkillDetailStatusBarUnlearnButton:SetPoint("LEFT", SkillDetailStatusBarBorder, "RIGHT")
		if SkillDetailStatusBarUnlearnButton.Texture then
			SkillDetailStatusBarUnlearnButton.Texture:Size(16)
			SkillDetailStatusBarUnlearnButton.Texture:SetVertexColor(1, 0, 0)
		end
		SkillDetailStatusBarUnlearnButton:HookScript("OnEnter", function(btn) if btn.Texture then btn.Texture:SetVertexColor(1, 1, 1) end end)
		SkillDetailStatusBarUnlearnButton:HookScript("OnLeave", function(btn) if btn.Texture then btn.Texture:SetVertexColor(1, 0, 0) end end)
	end

	SkillListScrollFrame:StripTextures()
	WSkin:HandleScrollBar(SkillListScrollFrameScrollBar)

	SkillDetailScrollFrame:StripTextures()
	WSkin:HandleScrollBar(SkillDetailScrollFrameScrollBar)

	WSkin:HandleButton(SkillFrameCancelButton)

	SkillFrameExpandButtonFrame:Point("TOPLEFT", 30, -50)

	if SkillTypeLabel1 then SkillTypeLabel1:Point("LEFT", SkillFrame, "TOPLEFT", 22, -85) end
	if SkillRankFrame1 then SkillRankFrame1:Point("TOPLEFT", 38, -78) end

	SkillListScrollFrame:Width(304)
	SkillListScrollFrame:Point("TOPRIGHT", -61, -74)

	SkillListScrollFrameScrollBar:Point("TOPLEFT", SkillListScrollFrame, "TOPRIGHT", 3, -19)
	SkillListScrollFrameScrollBar:Point("BOTTOMLEFT", SkillListScrollFrame, "BOTTOMRIGHT", 3, 19)

	SkillDetailScrollFrame:Size(304, 98)
	SkillDetailScrollFrame:Point("TOPLEFT", SkillListScrollFrame, "BOTTOMLEFT", 0, -7)

	SkillDetailScrollFrameScrollBar:Point("TOPLEFT", SkillDetailScrollFrame, "TOPRIGHT", 3, -19)
	SkillDetailScrollFrameScrollBar:Point("BOTTOMLEFT", SkillDetailScrollFrame, "BOTTOMRIGHT", 3, 19)

	SkillFrameCancelButton:Point("CENTER", SkillFrame, "TOPLEFT", 304, -417)

	-- Token Frame
	local function skinTokenFrame()
		if not TokenFrame then return end
		TokenFrame:StripTextures(true)

		local tChildren = {TokenFrame:GetChildren()}
		if tChildren[4] then tChildren[4]:Hide() end

		WSkin:HandleScrollBar(TokenFrameContainerScrollBar)
		WSkin:HandleButton(TokenFrameCancelButton)

		TokenFrameContainer:Size(304, 360)
		TokenFrameContainer:Point("TOPLEFT", 19, -39)

		TokenFrameContainerScrollBar:Point("TOPLEFT", TokenFrameContainer, "TOPRIGHT", 3, -19)
		TokenFrameContainerScrollBar:Point("BOTTOMLEFT", TokenFrameContainer, "BOTTOMRIGHT", 3, 19)

		TokenFrameMoneyFrame:Point("BOTTOMRIGHT", -115, 88)
		TokenFrameCancelButton:Point("CENTER", TokenFrame, "TOPLEFT", 304, -417)

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
					button.expandIcon:Size(16)
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

		TokenFramePopup:StripTextures()
		TokenFramePopup:SetTemplate("Transparent")

		WSkin:HandleCloseButton(TokenFramePopupCloseButton, TokenFramePopup)
		WSkin:HandleCheckBox(TokenFramePopupInactiveCheckBox)
		WSkin:HandleCheckBox(TokenFramePopupBackpackCheckBox)

		TokenFramePopup:Point("TOPLEFT", TokenFrame, "TOPRIGHT", -33, -12)
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
