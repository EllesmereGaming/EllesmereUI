local WSkin = _G.EllesmereUIBlizzardSkin
local _G = _G

--Lua functions
local _G = _G
local select = select
local find, gsub = string.find, string.gsub
--WoW API / Variables

WSkin:AddCallback("Skin_Gossip", function()

	-- Gossip
	GossipFramePortrait:Kill()
	GossipFrameGreetingPanel:StripTextures()

	GossipFrame:CreateBackdrop("Transparent")
	GossipFrame.backdrop:Point("TOPLEFT", 11, -12)
	GossipFrame.backdrop:Point("BOTTOMRIGHT", -32, 0)

	WSkin:SetUIPanelWindowInfo(GossipFrame, "width")
	WSkin:SetBackdropHitRect(GossipFrame)

	GossipGreetingText:SetTextColor(1, 1, 1)

	WSkin:HandleCloseButton(GossipFrameCloseButton, GossipFrame.backdrop)

	WSkin:HandleScrollBar(GossipGreetingScrollFrameScrollBar)
	WSkin:HandleButton(GossipFrameGreetingGoodbyeButton)

	for i = 1, NUMGOSSIPBUTTONS do
		local button = _G["GossipTitleButton"..i]
		WSkin:HandleButtonHighlight(button)
		select(3, button:GetRegions()):SetTextColor(1, 1, 1)
	end

	GossipFrameNpcNameText:ClearAllPoints()
	GossipFrameNpcNameText:Point("TOP", GossipFrame, "TOP", -6, -15)

	GossipGreetingScrollFrame:Size(304, 402)
	GossipGreetingScrollFrame:Point("TOPLEFT", GossipFrame, "TOPLEFT", 19, -73)

	GossipGreetingScrollFrameScrollBar:Point("TOPLEFT", GossipGreetingScrollFrame, "TOPRIGHT", 3, -19)
	GossipGreetingScrollFrameScrollBar:Point("BOTTOMLEFT", GossipGreetingScrollFrame, "BOTTOMRIGHT", 3, 19)

	GossipFrameGreetingGoodbyeButton:Point("BOTTOMRIGHT", -40, 8)

	hooksecurefunc("GossipFrameUpdate", function()
		for i = 1, GossipFrame.buttonIndex do
			local button = _G["GossipTitleButton"..i]

			if button:GetText() and find(button:GetText(), "|cff000000") then
				button:SetText(gsub(button:GetText(), "|cff000000", "|cffFFFF00"))
			end
		end
	end)

	-- ItemText
	ItemTextScrollFrame:StripTextures()
	ItemTextFrame:StripTextures(true)
	ItemTextFrame:CreateBackdrop("Transparent")
	ItemTextFrame.backdrop:Point("TOPLEFT", 11, -12)
	ItemTextFrame.backdrop:Point("BOTTOMRIGHT", -32, 76)

	WSkin:SetUIPanelWindowInfo(ItemTextFrame, "width")
	WSkin:SetBackdropHitRect(ItemTextFrame)

	ItemTextPageText:SetTextColor(1, 1, 1)
	ItemTextPageText.SetTextColor = function() end

	WSkin:HandleCloseButton(ItemTextCloseButton, ItemTextFrame.backdrop)

	WSkin:HandleNextPrevButton(ItemTextPrevPageButton)
	WSkin:HandleNextPrevButton(ItemTextNextPageButton)

	WSkin:HandleScrollBar(ItemTextScrollFrameScrollBar)

	ItemTextTitleText:Point("CENTER", -15, 230)

	ItemTextCurrentPage:Point("TOP", -15, -52)

	ItemTextPrevPageButton:Point("CENTER", ItemTextFrame, "TOPLEFT", 100, -58)
	ItemTextNextPageButton:Point("CENTER", ItemTextFrame, "TOPRIGHT", -130, -58)

	ItemTextPrevPageButton:GetRegions():Point("LEFT", ItemTextPrevPageButton, "RIGHT", 3, 0)
	ItemTextNextPageButton:GetRegions():Point("RIGHT", ItemTextNextPageButton, "LEFT", -3, 0)

	ItemTextScrollFrame:Width(283)
	ItemTextScrollFrame:Point("TOPRIGHT", -61, -73)

	ItemTextScrollFrameScrollBar:Point("TOPLEFT", ItemTextScrollFrame, "TOPRIGHT", 3, -19)
	ItemTextScrollFrameScrollBar:Point("BOTTOMLEFT", ItemTextScrollFrame, "BOTTOMRIGHT", 3, 19)
end)