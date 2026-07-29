local WSkin = _G.EllesmereUIBlizzardSkin
local _G = _G
local unpack = unpack
local MAX_SKILLLINE_TABS = MAX_SKILLLINE_TABS

WSkin:AddCallback("Skin_Spellbook", function()
	SpellBookFrame:StripTextures(true)
	SpellBookFrame:CreateBackdrop("Transparent")
	SpellBookFrame.backdrop:Point("TOPLEFT", 11, -12)
	SpellBookFrame.backdrop:Point("BOTTOMRIGHT", -32, 76)

	WSkin:SetUIPanelWindowInfo(SpellBookFrame, "width", nil, 31)
	WSkin:SetBackdropHitRect(SpellBookFrame)

	for i = 1, 3 do
		local tab = _G["SpellBookFrameTabButton"..i]
		tab:Size(122, 32)
		tab:GetNormalTexture():SetTexture(nil)
		tab:GetDisabledTexture():SetTexture(nil)
		tab:GetRegions():SetPoint("CENTER", 0, 2)
		WSkin:HandleTab(tab)
	end

	SpellBookFrameTabButton1:Point("CENTER", SpellBookFrame, "BOTTOMLEFT", 72, 62)
	SpellBookFrameTabButton2:Point("LEFT", SpellBookFrameTabButton1, "RIGHT", -15, 0)
	SpellBookFrameTabButton3:Point("LEFT", SpellBookFrameTabButton2, "RIGHT", -15, 0)

	WSkin:HandleNextPrevButton(SpellBookPrevPageButton, nil, nil, true)
	WSkin:HandleNextPrevButton(SpellBookNextPageButton, nil, nil, true)

	WSkin:HandleCloseButton(SpellBookCloseButton, SpellBookFrame.backdrop)

	WSkin:HandleCheckBox(ShowAllSpellRanksCheckBox)

	for i = 1, SPELLS_PER_PAGE do
		local button = _G["SpellButton"..i]
		local autoCast = _G["SpellButton"..i.."AutoCastable"]
		button:StripTextures()

		autoCast:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
		autoCast:SetOutside(button, 16, 16)

		button:CreateBackdrop("Default", true)

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

		tab:StripTextures()
		tab:StyleButton(nil, true)
		tab:SetTemplate("Default", true)

		tab:GetNormalTexture():SetInside()
		tab:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	SpellBookSkillLineTab1:Point("TOPLEFT", SpellBookFrame, "TOPRIGHT", -33, -65)

	SpellBookPageText:SetTextColor(1, 1, 1)
end)
