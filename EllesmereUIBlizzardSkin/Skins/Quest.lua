local WSkin = _G.EllesmereUIBlizzardSkin
local _G = _G

--Lua functions
local _G = _G
local select = select
local unpack = unpack
local find, gsub = string.find, string.gsub
--WoW API / Variables
local GetItemInfo = GetItemInfo
local GetItemQualityColor = GetItemQualityColor
local GetMoney = GetMoney
local GetNumQuestLeaderBoards = GetNumQuestLeaderBoards
local GetQuestItemLink = GetQuestItemLink
local GetQuestLogItemLink = GetQuestLogItemLink
local GetQuestLogLeaderBoard = GetQuestLogLeaderBoard
local GetQuestLogRequiredMoney = GetQuestLogRequiredMoney
local hooksecurefunc = hooksecurefunc
local GetQuestMoneyToGet = GetQuestMoneyToGet

local MAX_NUM_ITEMS = MAX_NUM_ITEMS
local MAX_REPUTATIONS = MAX_REPUTATIONS

WSkin:AddCallback("Skin_Quest", function()

	WSkin:StripTextures(QuestLogFrame)
	WSkin:CreateBackdrop(QuestLogFrame, "Transparent")
	QuestLogFrame.WSkin:Point(backdrop, "TOPLEFT", 11, -12)
	QuestLogFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", -1, 11)

	WSkin:SetUIPanelWindowInfo(QuestLogFrame, "width")
	WSkin:SetBackdropHitRect(QuestLogFrame)

	WSkin:HandleCloseButton(QuestLogFrameCloseButton, QuestLogFrame.backdrop)

	WSkin:StripTextures(QuestLogCount)
	WSkin:CreateBackdrop(QuestLogCount, "Transparent")
	QuestLogCount.WSkin:Point(backdrop, "TOPLEFT", -1, 0)
	QuestLogCount.WSkin:Point(backdrop, "BOTTOMRIGHT", 1, -4)

	WSkin:StripTextures(QuestLogFrameShowMapButton)
	WSkin:HandleButton(QuestLogFrameShowMapButton)

	WSkin:CreateBackdrop(QuestLogScrollFrame, "Transparent")
	QuestLogScrollFrame.WSkin:Point(backdrop, "TOPLEFT", 0, 2)
	QuestLogScrollFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", 0, -2)

	WSkin:StripTextures(QuestLogDetailScrollFrame)
	WSkin:CreateBackdrop(QuestLogDetailScrollFrame, "Transparent")
	QuestLogDetailScrollFrame.WSkin:Point(backdrop, "TOPLEFT", 0, 1)
	QuestLogDetailScrollFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", 0, -2)

	WSkin:StripTextures(EmptyQuestLogFrame)

	WSkin:HandleButton(QuestLogFrameAbandonButton)
	WSkin:HandleButton(QuestLogFramePushQuestButton)
	WSkin:HandleButton(QuestLogFrameTrackButton)
	WSkin:HandleButton(QuestLogFrameCancelButton)

	QuestLogSkillHighlight:SetTexture("Interface\\Buttons\\WHITE8x8")
	QuestLogSkillHighlight:SetAlpha(0.35)

	WSkin:HandleScrollBar(QuestLogScrollFrameScrollBar)
	WSkin:HandleScrollBar(QuestLogDetailScrollFrameScrollBar)
	WSkin:HandleScrollBar(QuestDetailScrollFrameScrollBar)
	WSkin:HandleScrollBar(QuestProgressScrollFrameScrollBar)
	WSkin:HandleScrollBar(QuestRewardScrollFrameScrollBar)

	QuestLogCount:ClearAllPoints()
	WSkin:Point(QuestLogCount, "BOTTOMLEFT", QuestLogScrollFrame, "TOPLEFT", 1, 13)
	QuestLogCount.SetPoint = function() end

	QuestLogFrameShowMapButton.text:ClearAllPoints()
	QuestLogFrameShowMapButton.text:SetPoint("CENTER")
	WSkin:Size(QuestLogFrameShowMapButton, QuestLogFrameShowMapButton.text:GetWidth() + 32, 32)

	WSkin:Point(QuestLogScrollFrame, "TOPLEFT", 19, -62)

	WSkin:Point(QuestLogScrollFrameScrollBar, "TOPLEFT", QuestLogScrollFrame, "TOPRIGHT", 3, -17)
	WSkin:Point(QuestLogScrollFrameScrollBar, "BOTTOMLEFT", QuestLogScrollFrame, "BOTTOMRIGHT", 3, 17)

	WSkin:Width(QuestLogDetailScrollFrame, 304)
	QuestLogDetailScrollFrame.Hide = function() end
	QuestLogDetailScrollFrame:Show()

	WSkin:Height(QuestLogFrameTrackButton, 22)
	WSkin:Height(QuestLogFrameAbandonButton, 22)
	WSkin:Height(QuestLogFramePushQuestButton, 22)

	WSkin:Point(QuestLogFrameTrackButton, "RIGHT", -1, 2)
	WSkin:Point(QuestLogFrameAbandonButton, "LEFT", 1, 2)

	WSkin:Point(QuestLogFramePushQuestButton, "LEFT", QuestLogFrameAbandonButton, "RIGHT", 3, 0)
	WSkin:Point(QuestLogFramePushQuestButton, "RIGHT", QuestLogFrameTrackButton, "LEFT", -3, 0)

	WSkin:Point(QuestLogFrameCancelButton, "BOTTOMRIGHT", -9, 19)

	QuestLogFrame:HookScript("OnShow", function()
		QuestLogDetailScrollFrame.backdrop:Show()

		WSkin:Point(QuestLogFrameShowMapButton, "TOPRIGHT", -30, -23)

		WSkin:Height(QuestLogDetailScrollFrame, 336)
		WSkin:Point(QuestLogDetailScrollFrame, "TOPRIGHT", -30, -61)

		WSkin:Point(QuestLogDetailScrollFrameScrollBar, "TOPLEFT", QuestLogDetailScrollFrame, "TOPRIGHT", 3, -18)
		WSkin:Point(QuestLogDetailScrollFrameScrollBar, "BOTTOMLEFT", QuestLogDetailScrollFrame, "BOTTOMRIGHT", 3, 17)

		QuestLogControlPanel:SetPoint("BOTTOMLEFT", 18, 15)
	end)

	for _, questLogTitle in ipairs(QuestLogScrollFrame.buttons) do
		WSkin:HandleCollapseExpandButton(questLogTitle, "+")
	end

	-- QuestLog Detail Frame
	WSkin:StripTextures(QuestLogDetailFrame)
	WSkin:Height(QuestLogDetailFrame, 513)
	WSkin:CreateBackdrop(QuestLogDetailFrame, "Transparent")
	QuestLogDetailFrame.WSkin:Point(backdrop, "TOPLEFT", 11, -12)
	QuestLogDetailFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", 2, 1)

	WSkin:SetUIPanelWindowInfo(QuestLogDetailFrame, "height", nil, nil, true)
	WSkin:SetUIPanelWindowInfo(QuestLogDetailFrame, "width")
	WSkin:SetBackdropHitRect(QuestLogDetailFrame)

	WSkin:HandleCloseButton(QuestLogDetailFrameCloseButton, QuestLogDetailFrame.backdrop)

	WSkin:Point(QuestLogDetailTitleText, "TOP", QuestLogDetailFrame, "TOP", 0, -18)

	QuestLogDetailFrame:HookScript("OnShow", function()
		QuestLogDetailScrollFrame.backdrop:Hide()

		WSkin:Height(QuestLogDetailScrollFrame, 402)
		WSkin:Point(QuestLogDetailScrollFrame, "TOPLEFT", 19, -73)

		WSkin:Point(QuestLogDetailScrollFrameScrollBar, "TOPLEFT", QuestLogDetailScrollFrame, "TOPRIGHT", 3, -19)
		WSkin:Point(QuestLogDetailScrollFrameScrollBar, "BOTTOMLEFT", QuestLogDetailScrollFrame, "BOTTOMRIGHT", 3, 19)

		WSkin:Point(QuestLogFrameShowMapButton, "TOPRIGHT", -27, -34)
	end)

	-- Quest Frame
	WSkin:StripTextures(QuestFrame, true)
	WSkin:CreateBackdrop(QuestFrame, "Transparent")
	QuestFrame.WSkin:Point(backdrop, "TOPLEFT", 11, -12)
	QuestFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", -32, 0)

	WSkin:SetUIPanelWindowInfo(QuestFrame, "width")
	WSkin:SetBackdropHitRect(QuestFrame)

	WSkin:HandleCloseButton(QuestFrameCloseButton, QuestFrame.backdrop)

	WSkin:StripTextures(QuestFrameDetailPanel, true)
	WSkin:StripTextures(QuestDetailScrollFrame, true)
	WSkin:StripTextures(QuestDetailScrollChildFrame, true)
	WSkin:StripTextures(QuestRewardScrollFrame, true)
	WSkin:StripTextures(QuestRewardScrollChildFrame, true)
	WSkin:StripTextures(QuestFrameProgressPanel, true)
	WSkin:StripTextures(QuestFrameRewardPanel, true)

	WSkin:HandleButton(QuestFrameAcceptButton)
	WSkin:HandleButton(QuestFrameCompleteButton)
	WSkin:HandleButton(QuestFrameCompleteQuestButton)
	WSkin:HandleButton(QuestFrameDeclineButton)
	WSkin:HandleButton(QuestFrameGoodbyeButton)
	WSkin:HandleButton(QuestFrameCancelButton)

	QuestFrameNpcNameText:ClearAllPoints()
	WSkin:Point(QuestFrameNpcNameText, "TOP", QuestFrame, "TOP", -6, -15)

	WSkin:Size(QuestDetailScrollFrame, 304, 402)
	WSkin:Size(QuestRewardScrollFrame, 304, 402)
	WSkin:Size(QuestProgressScrollFrame, 304, 402)

	WSkin:Point(QuestDetailScrollFrame, "TOPLEFT", QuestFrame, "TOPLEFT", 19, -73)
	WSkin:Point(QuestRewardScrollFrame, "TOPLEFT", QuestFrame, "TOPLEFT", 19, -73)
	WSkin:Point(QuestProgressScrollFrame, "TOPLEFT", QuestFrame, "TOPLEFT", 19, -73)

	WSkin:Point(QuestDetailScrollFrameScrollBar, "TOPLEFT", QuestDetailScrollFrame, "TOPRIGHT", 3, -19)
	WSkin:Point(QuestDetailScrollFrameScrollBar, "BOTTOMLEFT", QuestDetailScrollFrame, "BOTTOMRIGHT", 3, 19)

	WSkin:Point(QuestRewardScrollFrameScrollBar, "TOPLEFT", QuestRewardScrollFrame, "TOPRIGHT", 3, -19)
	WSkin:Point(QuestRewardScrollFrameScrollBar, "BOTTOMLEFT", QuestRewardScrollFrame, "BOTTOMRIGHT", 3, 19)

	WSkin:Point(QuestProgressScrollFrameScrollBar, "TOPLEFT", QuestProgressScrollFrame, "TOPRIGHT", 3, -19)
	WSkin:Point(QuestProgressScrollFrameScrollBar, "BOTTOMLEFT", QuestProgressScrollFrame, "BOTTOMRIGHT", 3, 19)

	WSkin:Point(QuestFrameAcceptButton, "BOTTOMLEFT", 19, 8)
	WSkin:Point(QuestFrameCompleteButton, "BOTTOMLEFT", 19, 8)
	WSkin:Point(QuestFrameCompleteQuestButton, "BOTTOMLEFT", 19, 8)
	WSkin:Point(QuestFrameDeclineButton, "BOTTOMRIGHT", -40, 8)
	WSkin:Point(QuestFrameGoodbyeButton, "BOTTOMRIGHT", -40, 8)
	WSkin:Point(QuestFrameCancelButton, "BOTTOMRIGHT", -40, 8)

	-- Quest Greeting Frame
	WSkin:StripTextures(QuestFrameGreetingPanel, true)
	WSkin:Kill(QuestGreetingFrameHorizontalBreak)

	WSkin:HandleButton(QuestFrameGreetingGoodbyeButton, true)
	WSkin:HandleScrollBar(QuestGreetingScrollFrameScrollBar)

	GreetingText:SetTextColor(1, 1, 1)
	CurrentQuestsText:SetTextColor(1, 0.80, 0.10)
	AvailableQuestsText:SetTextColor(1, 0.80, 0.10)

	GreetingText.SetTextColor = function() end
	CurrentQuestsText.SetTextColor = function() end
	AvailableQuestsText.SetTextColor = function() end

	WSkin:Size(QuestGreetingScrollFrame, 304, 402)
	WSkin:Point(QuestGreetingScrollFrame, "TOPLEFT", GossipFrame, "TOPLEFT", 19, -73)

	WSkin:Point(QuestGreetingScrollFrameScrollBar, "TOPLEFT", QuestGreetingScrollFrame, "TOPRIGHT", 3, -19)
	WSkin:Point(QuestGreetingScrollFrameScrollBar, "BOTTOMLEFT", QuestGreetingScrollFrame, "BOTTOMRIGHT", 3, 19)

	WSkin:Point(QuestFrameGreetingGoodbyeButton, "BOTTOMRIGHT", -40, 8)

	QuestFrameGreetingPanel:HookScript("OnShow", function()
		for i = 1, MAX_NUM_QUESTS do
			local button = _G["QuestTitleButton"..i]

			if button:GetFontString() then
				local text = button:GetText()
				if text and find(text, "|cff000000") then
					button:SetText(gsub(text, "|cff000000", "|cffFFFF00"))
				end
			end
		end
	end)

	-- Quest Progress + Reward
	WSkin:StripTextures(QuestInfoItemHighlight)

	QuestInfoTimerText:SetTextColor(1, 1, 1)
	QuestInfoAnchor:SetTextColor(1, 1, 1)

	local items = {
		["QuestInfoItem"] = MAX_NUM_ITEMS,
		["QuestProgressItem"] = MAX_REQUIRED_ITEMS
	}
	for frame, numItems in pairs(items) do
		for i = 1, numItems do
			local item = _G[frame..i]
			local icon = _G[frame..i.."IconTexture"]
			local count = _G[frame..i.."Count"]

			WSkin:StripTextures(item)
			WSkin:SetTemplate(item, "Default")
			WSkin:StyleButton(item)
			WSkin:Size(item, 143, 40)
			item:SetFrameLevel(item:GetFrameLevel() + 2)

			WSkin:Size(icon, false and 38 or 32)
			icon:SetDrawLayer("OVERLAY")
			WSkin:Point(icon, "TOPLEFT", false and 1 or 4, -(false and 1 or 4))
			WSkin:HandleIcon(icon)

			count:SetParent(item.backdrop)
			count:SetDrawLayer("OVERLAY")
		end
	end

	local function questQualityColors(frame, text, link)
		local quality = link and select(3, GetItemInfo(link))

		if quality then
			local r, g, b = GetItemQualityColor(quality)

			frame:SetBackdropBorderColor(r, g, b)
			frame.backdrop:SetBackdropBorderColor(r, g, b)

			text:SetTextColor(r, g, b)
		else
			frame:SetBackdropBorderColor(0, 0, 0)
			frame.backdrop:SetBackdropBorderColor(0, 0, 0)

			text:SetTextColor(1, 1, 1)
		end
	end

	hooksecurefunc("QuestFrameProgressItems_Update", function()
		QuestProgressTitleText:SetTextColor(1, 0.80, 0.10)
		QuestProgressText:SetTextColor(1, 1, 1)
		QuestProgressRequiredItemsText:SetTextColor(1, 0.80, 0.10)

		local moneyToGet = GetQuestMoneyToGet()

		if moneyToGet > 0 then
			if moneyToGet > GetMoney() then
				QuestProgressRequiredMoneyText:SetTextColor(0.6, 0.6, 0.6)
			else
				QuestProgressRequiredMoneyText:SetTextColor(1, 0.80, 0.10)
			end
		end

		local item, name, link

		for i = 1, MAX_REQUIRED_ITEMS do
			item = _G["QuestProgressItem"..i]
			name = _G["QuestProgressItem"..i.."Name"]
			link = item.type and GetQuestItemLink(item.type, item:GetID())

			questQualityColors(item, name, link)
		end
	end)

	hooksecurefunc("QuestInfoItem_OnClick", function(self)
		if self.type == "choice" then
			self:SetBackdropBorderColor(1, 0.80, 0.10)
			self.backdrop:SetBackdropBorderColor(1, 0.80, 0.10)
			_G[self:GetName().."Name"]:SetTextColor(1, 0.80, 0.10)

			local item, name, link

			for i = 1, MAX_NUM_ITEMS do
				item = _G["QuestInfoItem"..i]

				if item ~= self then
					name = _G["QuestInfoItem"..i.."Name"]
					link = item.type and (QuestInfoFrame.questLog and GetQuestLogItemLink or GetQuestItemLink)(item.type, item:GetID())

					questQualityColors(item, name, link)
				end
			end
		end
	end)

	local function questObjectiveText()
		local numObjectives = GetNumQuestLeaderBoards()
		local _, objType, finished, objective
		local numVisibleObjectives = 0

		for i = 1, numObjectives do
			_, objType, finished = GetQuestLogLeaderBoard(i)

			if objType ~= "spell" then
				numVisibleObjectives = numVisibleObjectives + 1
				objective = _G["QuestInfoObjective"..numVisibleObjectives]

				if finished then
					objective:SetTextColor(1, 0.80, 0.10)
				else
					objective:SetTextColor(0.6, 0.6, 0.6)
				end
			end
		end
	end

	hooksecurefunc("QuestInfo_Display", function()
		QuestInfoTitleHeader:SetTextColor(1, 0.80, 0.10)
		QuestInfoDescriptionHeader:SetTextColor(1, 0.80, 0.10)
		QuestInfoObjectivesHeader:SetTextColor(1, 0.80, 0.10)
		QuestInfoRewardsHeader:SetTextColor(1, 0.80, 0.10)

		QuestInfoDescriptionText:SetTextColor(1, 1, 1)
		QuestInfoObjectivesText:SetTextColor(1, 1, 1)
		QuestInfoGroupSize:SetTextColor(1, 1, 1)
		QuestInfoRewardText:SetTextColor(1, 1, 1)

		QuestInfoItemChooseText:SetTextColor(1, 1, 1)
		QuestInfoItemReceiveText:SetTextColor(1, 1, 1)
		QuestInfoSpellLearnText:SetTextColor(1, 1, 1)
		QuestInfoHonorFrameReceiveText:SetTextColor(1, 1, 1)
		QuestInfoArenaPointsFrameReceiveText:SetTextColor(1, 1, 1)
		QuestInfoTalentFrameReceiveText:SetTextColor(1, 1, 1)
		QuestInfoXPFrameReceiveText:SetTextColor(1, 1, 1)
		QuestInfoReputationText:SetTextColor(1, 1, 1)

		for i = 1, MAX_REPUTATIONS do
			_G["QuestInfoReputation"..i.."Faction"]:SetTextColor(1, 1, 1)
		end

		local requiredMoney = GetQuestLogRequiredMoney()

		if requiredMoney > 0 then
			if requiredMoney > GetMoney() then
				QuestInfoRequiredMoneyText:SetTextColor(0.6, 0.6, 0.6)
			else
				QuestInfoRequiredMoneyText:SetTextColor(1, 0.80, 0.10)
			end
		end

		questObjectiveText()

		local item, name, link

		for i = 1, MAX_NUM_ITEMS do
			item = _G["QuestInfoItem"..i]
			name = _G["QuestInfoItem"..i.."Name"]
			link = item.type and (QuestInfoFrame.questLog and GetQuestLogItemLink or GetQuestItemLink)(item.type, item:GetID())

			questQualityColors(item, name, link)
		end
	end)

	hooksecurefunc("QuestInfo_ShowRewards", function()
		local item, name, link

		for i = 1, MAX_NUM_ITEMS do
			item = _G["QuestInfoItem"..i]
			name = _G["QuestInfoItem"..i.."Name"]
			link = item.type and (QuestInfoFrame.questLog and GetQuestLogItemLink or GetQuestItemLink)(item.type, item:GetID())

			questQualityColors(item, name, link)
		end
	end)

	hooksecurefunc("QuestInfo_ShowRequiredMoney", function()
		local requiredMoney = GetQuestLogRequiredMoney()

		if requiredMoney > 0 then
			if requiredMoney > GetMoney() then
				QuestInfoRequiredMoneyText:SetTextColor(0.6, 0.6, 0.6)
			else
				QuestInfoRequiredMoneyText:SetTextColor(1, 0.80, 0.10)
			end
		end
	end)
end)