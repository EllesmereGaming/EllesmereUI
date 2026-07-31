local WSkin = _G.EllesmereUIBlizzardSkin
local _G = _G

--Lua functions
--WoW API / Variables

WSkin:AddCallback("Skin_WorldMap", function()

	WorldMapFrame:DisableDrawLayer("BACKGROUND")
	WorldMapFrame:DisableDrawLayer("ARTWORK")
	WorldMapFrame:DisableDrawLayer("OVERLAY")
	WSkin:CreateBackdrop(WorldMapFrame, "Transparent")
	WSkin:Point(WorldMapFrame.backdrop, "TOPRIGHT", WorldMapFrameCloseButton, -3, 0)
	WSkin:Point(WorldMapFrame.backdrop, "BOTTOMRIGHT", WorldMapTrackQuest, 0, -3)
	WorldMapFrame:SetClampRectInsets(3, 0, 2, 1)

	WorldMapFrameTitle:SetDrawLayer("BORDER")

	WSkin:Width(WorldMapTitleButton, 530)
	WSkin:Point(WorldMapTitleButton, "TOPLEFT", WorldMapFrameMiniBorderLeft, "TOPLEFT", 4, 1)

	WSkin:CreateBackdrop(WorldMapDetailFrame)
	WSkin:Point(WorldMapDetailFrame.backdrop, "TOPLEFT", -2, 2)
	WSkin:Point(WorldMapDetailFrame.backdrop, "BOTTOMRIGHT", 2, -1)

	WSkin:Width(WorldMapQuestDetailScrollFrame, 348)
	WSkin:Point(WorldMapQuestDetailScrollFrame, "BOTTOMLEFT", WorldMapDetailFrame, "BOTTOMLEFT", -25, -207)
	WSkin:CreateBackdrop(WorldMapQuestDetailScrollFrame, "Transparent")
	WSkin:Point(WorldMapQuestDetailScrollFrame.backdrop, "TOPLEFT", 24, 2)
	WSkin:Point(WorldMapQuestDetailScrollFrame.backdrop, "BOTTOMRIGHT", 23, -4)
	WorldMapQuestDetailScrollFrame.backdrop:SetFrameLevel(WorldMapQuestDetailScrollFrame:GetFrameLevel())
	WorldMapQuestDetailScrollFrame:SetHitRectInsets(24, -23, 0, -2)

	WorldMapQuestDetailScrollChildFrame:SetScale(1)

	WSkin:Kill(WorldMapQuestDetailScrollFrameTrack)

	WSkin:Width(WorldMapQuestRewardScrollFrame, 340)
	WSkin:Point(WorldMapQuestRewardScrollFrame, "LEFT", WorldMapQuestDetailScrollFrame, "RIGHT", 8, 0)
	WSkin:CreateBackdrop(WorldMapQuestRewardScrollFrame, "Transparent")
	WSkin:Point(WorldMapQuestRewardScrollFrame.backdrop, "TOPLEFT", 20, 2)
	WSkin:Point(WorldMapQuestRewardScrollFrame.backdrop, "BOTTOMRIGHT", 22, -4)
	WorldMapQuestRewardScrollFrame.backdrop:SetFrameLevel(WorldMapQuestRewardScrollFrame:GetFrameLevel())
	WorldMapQuestRewardScrollFrame:SetHitRectInsets(20, -22, 0, -2)

	WorldMapQuestRewardScrollChildFrame:SetScale(1)

	WorldMapQuestRewardScrollFrameTrack:SetTexture()

	WSkin:Point(WorldMapQuestScrollFrame, "TOPLEFT", WorldMapDetailFrame, "TOPRIGHT", 6, -1)
	WSkin:CreateBackdrop(WorldMapQuestScrollFrame, "Transparent")
	WSkin:Point(WorldMapQuestScrollFrame.backdrop, "TOPLEFT", 0, 2)
	WSkin:Point(WorldMapQuestScrollFrame.backdrop, "BOTTOMRIGHT", 25, -1)
	WorldMapQuestScrollFrame.backdrop:SetFrameLevel(WorldMapQuestScrollFrame:GetFrameLevel())

	WorldMapQuestSelectBar:SetTexture("Interface\\Buttons\\WHITE8x8")
	WorldMapQuestSelectBar:SetAlpha(0.35)

	WorldMapQuestHighlightBar:SetTexture("Interface\\Buttons\\WHITE8x8")
	WorldMapQuestHighlightBar:SetAlpha(0.35)

	WSkin:HandleScrollBar(WorldMapQuestScrollFrameScrollBar)
	WSkin:HandleScrollBar(WorldMapQuestDetailScrollFrameScrollBar)
	WSkin:HandleScrollBar(WorldMapQuestRewardScrollFrameScrollBar)

	WSkin:Point(WorldMapQuestScrollFrameScrollBar, "TOPLEFT", WorldMapQuestScrollFrame, "TOPRIGHT", 5, -19)
	WSkin:Point(WorldMapQuestScrollFrameScrollBar, "BOTTOMLEFT", WorldMapQuestScrollFrame, "BOTTOMRIGHT", 5, 20)

	WSkin:Point(WorldMapQuestDetailScrollFrameScrollBar, "TOPLEFT", WorldMapQuestDetailScrollFrame, "TOPRIGHT", 3, -19)
	WSkin:Point(WorldMapQuestDetailScrollFrameScrollBar, "BOTTOMLEFT", WorldMapQuestDetailScrollFrame, "BOTTOMRIGHT", 3, 17)

	WSkin:Point(WorldMapQuestRewardScrollFrameScrollBar, "TOPLEFT", WorldMapQuestRewardScrollFrame, "TOPRIGHT", 2, -19)
	WSkin:Point(WorldMapQuestRewardScrollFrameScrollBar, "BOTTOMLEFT", WorldMapQuestRewardScrollFrame, "BOTTOMRIGHT", 2, 17)

	WSkin:HandleCloseButton(WorldMapFrameCloseButton)

	WorldMapFrameSizeDownButton:ClearAllPoints()
	WSkin:Point(WorldMapFrameSizeDownButton, "RIGHT", WorldMapFrameCloseButton, "LEFT", 4, 0)
	WorldMapFrameSizeDownButton.SetPoint = function() end
	WSkin:Kill(WorldMapFrameSizeDownButton:GetHighlightTexture())
	WSkin:HandleNextPrevButton(WorldMapFrameSizeDownButton, "down", nil, true)
	WSkin:Size(WorldMapFrameSizeDownButton, 26)

	WSkin:Kill(WorldMapFrameSizeUpButton:GetHighlightTexture())
	WSkin:HandleNextPrevButton(WorldMapFrameSizeUpButton, "up", nil, true)
	WSkin:Size(WorldMapFrameSizeUpButton, 26)

	WSkin:HandleDropDownBox(WorldMapLevelDropDown)
	WSkin:HandleDropDownBox(WorldMapZoneMinimapDropDown)
	WSkin:HandleDropDownBox(WorldMapContinentDropDown)
	WSkin:HandleDropDownBox(WorldMapZoneDropDown)

	WSkin:Point(WorldMapLevelUpButton, "TOPLEFT", WorldMapLevelDropDown, "TOPRIGHT", -6, 4)
	WSkin:Point(WorldMapLevelDownButton, "BOTTOMLEFT", WorldMapLevelDropDown, "BOTTOMRIGHT", -6, 0)

	WSkin:HandleButton(WorldMapZoomOutButton)
	WSkin:Point(WorldMapZoomOutButton, "LEFT", WorldMapZoneDropDown, "RIGHT", 0, 3)

	WSkin:HandleCheckBox(WorldMapTrackQuest)
	WSkin:HandleCheckBox(WorldMapQuestShowObjectives)

	WSkin:FontTemplate(WorldMapFrameAreaLabel, nil, 50, "OUTLINE")
	WorldMapFrameAreaLabel:SetShadowOffset(2, -2)
	WorldMapFrameAreaLabel:SetTextColor(0.90, 0.8294, 0.6407)

	WSkin:FontTemplate(WorldMapFrameAreaDescription, nil, 40, "OUTLINE")
	WorldMapFrameAreaDescription:SetShadowOffset(2, -2)

	WSkin:FontTemplate(WorldMapZoneInfo, nil, 27, "OUTLINE")
	WorldMapZoneInfo:SetShadowOffset(2, -2)

	WorldMapLevelDropDown.SetPoint = function() end

	local setPoint = UIParent.SetPoint
	local currentMapMode

	local function SmallSkin()
		if WORLDMAP_SETTINGS.advanced then
			if currentMapMode == 0 then return end
			currentMapMode = 0

			WSkin:Point(WorldMapFrame.backdrop, "TOPLEFT", 3, 2)
			WSkin:Point(WorldMapFrame.backdrop, "TOPRIGHT", WorldMapFrameCloseButton, -3, 0)

			WSkin:Point(WorldMapDetailFrame.backdrop, "TOPLEFT", -2, 2)
			WSkin:Point(WorldMapDetailFrame.backdrop, "BOTTOMRIGHT", 1, -1)

			setPoint(WorldMapLevelDropDown, "TOPRIGHT", WorldMapPositioningGuide, "TOPRIGHT", -419, -24)
		else
			if currentMapMode == 1 then return end
			currentMapMode = 1

			WSkin:Point(WorldMapFrame.backdrop, "TOPLEFT", 11, -12)
			WSkin:Point(WorldMapFrame.backdrop, "TOPRIGHT", WorldMapFrameCloseButton, -1, 0)

			WSkin:Point(WorldMapDetailFrame.backdrop, "TOPLEFT", -2, 2)
			WSkin:Point(WorldMapDetailFrame.backdrop, "BOTTOMRIGHT", 2, -1)

			setPoint(WorldMapLevelDropDown, "TOPRIGHT", WorldMapPositioningGuide, "TOPRIGHT", -439, -38)
		end
	end

	local function LargeSkin()
		if currentMapMode == 2 then return end
		currentMapMode = 2

		WSkin:Point(WorldMapFrame.backdrop, "TOPLEFT", WorldMapDetailFrame, "TOPLEFT", -8, 70)
		WSkin:Point(WorldMapFrame.backdrop, "TOPRIGHT", WorldMapFrameCloseButton, -3, 0)

		WSkin:Point(WorldMapDetailFrame.backdrop, "TOPLEFT", -1, 1)
		WSkin:Point(WorldMapDetailFrame.backdrop, "BOTTOMRIGHT", 1, -1)

		setPoint(WorldMapLevelDropDown, "TOPRIGHT", WorldMapPositioningGuide, "TOPRIGHT", -50, -35)
	end

	local function QuestSkin()
		if currentMapMode == 3 then return end
		currentMapMode = 3

		WSkin:Point(WorldMapFrame.backdrop, "TOPLEFT", WorldMapDetailFrame, "TOPLEFT", -9, 70)
		WSkin:Point(WorldMapFrame.backdrop, "TOPRIGHT", WorldMapFrameCloseButton, -3, 0)

		WSkin:Point(WorldMapDetailFrame.backdrop, "TOPLEFT", -1, 1)
		WSkin:Point(WorldMapDetailFrame.backdrop, "BOTTOMRIGHT", 1, -1)

		setPoint(WorldMapLevelDropDown, "TOPRIGHT", WorldMapPositioningGuide, "TOPRIGHT", -50, -35)
	end

	local function FixSkin()
		if WORLDMAP_SETTINGS.size == WORLDMAP_FULLMAP_SIZE then
			LargeSkin()
		elseif WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE then
			SmallSkin()
		elseif WORLDMAP_SETTINGS.size == WORLDMAP_QUESTLIST_SIZE then
			QuestSkin()
		end
	end

	if _G.E and _G.E.private and _G.E.private.worldmap and not _G.E.private.worldmap.enable then
		WorldMapFrame:EnableMouse(false)
		WorldMapFrame.EnableMouse = function() end
	end

	WorldMapTitleButton:Hide()
	WorldMapFrame.backdrop:EnableMouse(true)

	FixSkin()
	WSkin:SetUIPanelWindowInfo(WorldMapFrame, "width", 594)

	hooksecurefunc("WorldMapFrame_SetQuestMapView", QuestSkin)
	hooksecurefunc("WorldMapFrame_SetFullMapView", LargeSkin)
	hooksecurefunc("WorldMapFrame_SetMiniMode", SmallSkin)
	hooksecurefunc("ToggleMapFramerate", FixSkin)
	hooksecurefunc("WorldMapFrame_ToggleAdvanced", FixSkin)
end)