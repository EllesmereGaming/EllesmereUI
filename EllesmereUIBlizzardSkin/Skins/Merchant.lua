local WSkin = _G.EllesmereUIBlizzardSkin
local _G = _G

--Lua functions
local _G = _G
local unpack = unpack
local floor = math.floor
--WoW API / Variables
local GetBuybackItemInfo = GetBuybackItemInfo
local GetItemInfo = GetItemInfo
local GetItemQualityColor = GetItemQualityColor
local GetMerchantNumItems = GetMerchantNumItems

WSkin:AddCallback("Skin_Merchant", function()

	local MerchantFrame = _G.MerchantFrame
	WSkin:StripTextures(MerchantFrame, true)
	WSkin:CreateBackdrop(MerchantFrame, "Transparent")
	MerchantFrame.WSkin:Point(backdrop, "TOPLEFT", 11, -12)
	MerchantFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", -32, 76)

	WSkin:SetUIPanelWindowInfo(MerchantFrame, "width")
	WSkin:SetBackdropHitRect(MerchantFrame)

	MerchantFrame:EnableMouseWheel(true)
	MerchantFrame:SetScript("OnMouseWheel", function(_, value)
		if value > 0 then
			if MerchantPrevPageButton:IsShown() and MerchantPrevPageButton:IsEnabled() == 1 then
				MerchantPrevPageButton_OnClick()
			end
		else
			if MerchantNextPageButton:IsShown() and MerchantNextPageButton:IsEnabled() == 1 then
				MerchantNextPageButton_OnClick()
			end
		end
	end)

	WSkin:HandleCloseButton(MerchantFrameCloseButton, MerchantFrame.backdrop)

	local function skinMerchantButton(buttonName, buyback)
		local button = _G[buttonName]
		local itemButton = _G[buttonName.."ItemButton"]
		local icon = _G[buttonName.."ItemButtonIconTexture"]
		local name = _G[buttonName.."Name"]
		local nameFrame = _G[buttonName.."NameFrame"]
		local money = _G[buttonName.."MoneyFrame"]
		local slot = _G[buttonName.."SlotTexture"]

		WSkin:StripTextures(button, true)
		WSkin:CreateBackdrop(button, "Default")
		button.WSkin:Point(backdrop, "TOPLEFT", -2, 2)

		if buyback then
			button.WSkin:Point(backdrop, "BOTTOMRIGHT", 4, -13)
		else
			button.WSkin:Point(backdrop, "BOTTOMRIGHT", 4, -6)
		end

		WSkin:StripTextures(itemButton)
		WSkin:StyleButton(itemButton)
		WSkin:SetTemplate(itemButton, "Default", true)
		WSkin:Size(itemButton, 40)
		WSkin:Point(itemButton, "TOPLEFT", 4, -4)

		icon:SetTexCoord(unpack(E.TexCoords))
		WSkin:SetInside(icon)

		WSkin:Point(name, "LEFT", slot, "RIGHT", -4, 5)
		WSkin:Point(nameFrame, "LEFT", slot, "RIGHT", -6, -17)

		money:ClearAllPoints()
		WSkin:Point(money, "BOTTOMLEFT", itemButton, "BOTTOMRIGHT", 3, 0)

		if not buyback then
			for j = 1, 2 do
				local currencyItem = _G[buttonName.."AltCurrencyFrameItem"..j]
				local currencyIcon = _G[buttonName.."AltCurrencyFrameItem"..j.."Texture"]

				currencyIcon.backdrop = CreateFrame("Frame", nil, currencyItem)
				currencyIcon.WSkin:SetTemplate(backdrop, "Default")
				currencyIcon.backdrop:SetFrameLevel(currencyItem:GetFrameLevel())
				currencyIcon.WSkin:SetOutside(backdrop, currencyIcon)

				currencyIcon:SetTexCoord(unpack(E.TexCoords))
				currencyIcon:SetParent(currencyIcon.backdrop)
			end
		end
	end

	for i = 1, 12 do
		skinMerchantButton("MerchantItem"..i)

		if i % 2 == 0 then
			WSkin:Point(_G["MerchantItem"..i], "TOPLEFT", _G["MerchantItem"..i-1], "TOPRIGHT", 13, 0)
		end
	end

	skinMerchantButton("MerchantBuyBackItem", true)

	WSkin:HandleNextPrevButton(MerchantNextPageButton, nil, nil, true)
	WSkin:HandleNextPrevButton(MerchantPrevPageButton, nil, nil, true)

	WSkin:HandleButton(MerchantRepairItemButton)
	WSkin:StyleButton(MerchantRepairItemButton, false)
	-- texWidth, texHeight, cropWidth, cropHeight, offsetX, offsetY = 128, 64, 26, 26, 5, 6
	MerchantRepairItemButton:GetRegions():SetTexCoord(0.0390625, 0.2421875, 0.09375, 0.5)
	WSkin:SetInside(MerchantRepairItemButton:GetRegions())

	WSkin:HandleButton(MerchantRepairAllButton)
	WSkin:StyleButton(MerchantRepairAllIcon, false)
	-- texWidth, texHeight, cropWidth, cropHeight, offsetX, offsetY = 128, 64, 26, 26, 41, 6
	MerchantRepairAllIcon:SetTexCoord(0.3203125, 0.5234375, 0.09375, 0.5)
	WSkin:SetInside(MerchantRepairAllIcon)

	WSkin:HandleButton(MerchantGuildBankRepairButton)
	WSkin:StyleButton(MerchantGuildBankRepairButton)
	-- texWidth, texHeight, cropWidth, cropHeight, offsetX, offsetY = 128, 64, 26, 26, 77, 6
	MerchantGuildBankRepairButtonIcon:SetTexCoord(0.6015625, 0.8046875, 0.09375, 0.5)
	WSkin:SetInside(MerchantGuildBankRepairButtonIcon)

	WSkin:HandleTab(MerchantFrameTab1)
	WSkin:HandleTab(MerchantFrameTab2)

	WSkin:Point(MerchantNameText, "TOP", -6, -22)

	MerchantItem1:SetPoint("TOPLEFT", 21, -54)

	WSkin:Point(MerchantPrevPageButton, "CENTER", MerchantFrame, "BOTTOMLEFT", 37, 172)
	WSkin:Point(MerchantNextPageButton, "CENTER", MerchantFrame, "BOTTOMLEFT", 324, 172)

	WSkin:Point(MerchantPageText, "BOTTOM", -14, 166)

	WSkin:Point(MerchantBuyBackItem, "TOPLEFT", MerchantItem10, "BOTTOMLEFT", 0, -39)

	WSkin:Point(MerchantGuildBankRepairButton, "LEFT", MerchantRepairAllButton, "RIGHT", 5, 0)
	WSkin:Point(MerchantRepairItemButton, "RIGHT", MerchantRepairAllButton, "LEFT", -5, 0)
	MerchantRepairItemButton.SetPoint = function() end

	WSkin:Point(MerchantMoneyFrame, "BOTTOMRIGHT", -30, 86)

	WSkin:Point(MerchantFrameTab1, "CENTER", MerchantFrame, "BOTTOMLEFT", 54, 62)
	WSkin:Point(MerchantFrameTab2, "LEFT", MerchantFrameTab1, "RIGHT", -15, 0)

	hooksecurefunc(MerchantRepairAllButton, "Show", function(self)
		-- CanMerchantRepair && CanGuildBankRepair
		if floor(self:GetWidth() + 0.5) == 32 then
			MerchantRepairText:SetPoint("CENTER", MerchantFrame, "BOTTOMLEFT", 94, 151)
			WSkin:Point(MerchantRepairAllButton, "BOTTOMRIGHT", MerchantFrame, "BOTTOMLEFT", 111, 105)
		else
			MerchantRepairText:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 26, 125)
			WSkin:Point(MerchantRepairAllButton, "BOTTOMRIGHT", MerchantFrame, "BOTTOMLEFT", 172, 113)
		end
	end)

	hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
		local numMerchantItems = GetMerchantNumItems()
		local index = (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE
		local _, button, name, quality

		for i = 1, BUYBACK_ITEMS_PER_PAGE do
			index = index + 1

			if index <= numMerchantItems then
				button = _G["MerchantItem"..i.."ItemButton"]
				name = _G["MerchantItem"..i.."Name"]

				if button.link then
					_, _, quality = GetItemInfo(button.link)

					if quality then
						local r, g, b = GetItemQualityColor(quality)
						button:SetBackdropBorderColor(r, g, b)
						name:SetTextColor(r, g, b)
					else
						button:SetBackdropBorderColor(0, 0, 0)
						name:SetTextColor(1, 1, 1)
					end
				else
					button:SetBackdropBorderColor(0, 0, 0)
					name:SetTextColor(1, 1, 1)
				end
			end

			local itemName = GetBuybackItemInfo(GetNumBuybackItems())
			if itemName then
				_, _, quality = GetItemInfo(itemName)

				if quality then
					local r, g, b = GetItemQualityColor(quality)
					MerchantBuyBackItemItemButton:SetBackdropBorderColor(r, g, b)
					MerchantBuyBackItemName:SetTextColor(r, g, b)
				else
					MerchantBuyBackItemItemButton:SetBackdropBorderColor(0, 0, 0)
					MerchantBuyBackItemName:SetTextColor(1, 1, 1)
				end
			else
				MerchantBuyBackItemItemButton:SetBackdropBorderColor(0, 0, 0)
			end
		end

		MerchantItem3:SetPoint("TOPLEFT", "MerchantItem1", "BOTTOMLEFT", 0, -11)
		MerchantItem5:SetPoint("TOPLEFT", "MerchantItem3", "BOTTOMLEFT", 0, -11)
		MerchantItem7:SetPoint("TOPLEFT", "MerchantItem5", "BOTTOMLEFT", 0, -11)
		MerchantItem9:SetPoint("TOPLEFT", "MerchantItem7", "BOTTOMLEFT", 0, -11)
	end)

	hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function()
		local numBuybackItems = GetNumBuybackItems()
		local _, button, name, quality

		for i = 1, BUYBACK_ITEMS_PER_PAGE do
			if i <= numBuybackItems then
				local itemName = GetBuybackItemInfo(i)

				if itemName then
					button = _G["MerchantItem"..i.."ItemButton"]
					name = _G["MerchantItem"..i.."Name"]
					_, _, quality = GetItemInfo(itemName)

					if quality then
						local r, g, b = GetItemQualityColor(quality)
						button:SetBackdropBorderColor(r, g, b)
						name:SetTextColor(r, g, b)
					else
						button:SetBackdropBorderColor(0, 0, 0)
						name:SetTextColor(1, 1, 1)
					end
				end
			end
		end

		MerchantItem3:SetPoint("TOPLEFT", "MerchantItem1", "BOTTOMLEFT", 0, -15)
		MerchantItem5:SetPoint("TOPLEFT", "MerchantItem3", "BOTTOMLEFT", 0, -15)
		MerchantItem7:SetPoint("TOPLEFT", "MerchantItem5", "BOTTOMLEFT", 0, -15)
		MerchantItem9:SetPoint("TOPLEFT", "MerchantItem7", "BOTTOMLEFT", 0, -15)
	end)
end)