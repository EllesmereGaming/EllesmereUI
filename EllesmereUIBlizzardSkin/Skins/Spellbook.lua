local WSkin = _G.EllesmereUIBlizzardSkin
local _G = _G
local unpack = unpack
local MAX_SKILLLINE_TABS = MAX_SKILLLINE_TABS

WSkin:AddCallback("Skin_Spellbook", function()
	WSkin:StripTextures(SpellBookFrame, true)
	WSkin:CreateBackdrop(SpellBookFrame, "Transparent")
	WSkin:Point(SpellBookFrame.backdrop, "TOPLEFT", 11, -12)
	WSkin:Point(SpellBookFrame.backdrop, "BOTTOMRIGHT", -32, 76)

	WSkin:SetUIPanelWindowInfo(SpellBookFrame, "width", nil, 31)
	WSkin:SetBackdropHitRect(SpellBookFrame)

	for i = 1, 3 do
		local tab = _G["SpellBookFrameTabButton"..i]
		WSkin:Size(tab, 122, 32)
		tab:GetNormalTexture():SetTexture(nil)
		tab:GetDisabledTexture():SetTexture(nil)
		tab:GetRegions():SetPoint("CENTER", 0, 2)
		WSkin:HandleTab(tab)
	end

	WSkin:Point(SpellBookFrameTabButton1, "CENTER", SpellBookFrame, "BOTTOMLEFT", 72, 62)
	WSkin:Point(SpellBookFrameTabButton2, "LEFT", SpellBookFrameTabButton1, "RIGHT", -15, 0)
	WSkin:Point(SpellBookFrameTabButton3, "LEFT", SpellBookFrameTabButton2, "RIGHT", -15, 0)

	WSkin:HandleNextPrevButton(SpellBookPrevPageButton, nil, nil, true)
	WSkin:HandleNextPrevButton(SpellBookNextPageButton, nil, nil, true)

	WSkin:HandleCloseButton(SpellBookCloseButton, SpellBookFrame.backdrop)

	WSkin:HandleCheckBox(ShowAllSpellRanksCheckBox)

	for i = 1, SPELLS_PER_PAGE do
		local button = _G["SpellButton"..i]
		local autoCast = _G["SpellButton"..i.."AutoCastable"]
		WSkin:StripTextures(button)

		autoCast:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
		WSkin:SetOutside(autoCast, button, 16, 16)

		WSkin:CreateBackdrop(button, "Default", true)

		_G["SpellButton"..i.."IconTexture"]:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	hooksecurefunc("SpellButton_UpdateButton", function(self)
		local name = self:GetName()
		_G[name.."SpellName"]:SetTextColor(1, 0.80, 0.10)
		_G[name.."SubSpellName"]:SetTextColor(1, 1, 1)
		_G[name.."Highlight"]:SetTexture(1, 1, 1, 0.3)
	end)

	for i = 1, MAX_SKILLLINE_TABS do
		local tab = _G["SpellBookSkillLineTab"..i]

		WSkin:StripTextures(tab)
		WSkin:StyleButton(tab, nil, true)
		WSkin:SetTemplate(tab, "Default", true)

		WSkin:SetInside(tab:GetNormalTexture())
		tab:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	WSkin:Point(SpellBookSkillLineTab1, "TOPLEFT", SpellBookFrame, "TOPRIGHT", -33, -65)

	SpellBookPageText:SetTextColor(1, 1, 1)
end)
