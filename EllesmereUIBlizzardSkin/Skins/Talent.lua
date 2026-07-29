local WSkin = _G.EllesmereUIBlizzardSkin
local _G = _G

--Lua functions
local unpack = unpack

-- Standard icon tex coordinates to crop the default icon border
local TEXCOORDS = { 0.08, 0.92, 0.08, 0.92 }

WSkin:AddCallback("Skin_Talent", function()

	WSkin:StripTextures(PlayerTalentFrame, true)
	WSkin:CreateBackdrop(PlayerTalentFrame, "Transparent")
	PlayerTalentFrame.WSkin:Point(backdrop, "TOPLEFT", 11, -12)
	PlayerTalentFrame.WSkin:Point(backdrop, "BOTTOMRIGHT", -32, 76)

	WSkin:SetBackdropHitRect(PlayerTalentFrame)

	do
		local offset

		local talentGroups = GetNumTalentGroups(false, false)
		local petTalentGroups = GetNumTalentGroups(false, true)

		if talentGroups + petTalentGroups > 1 then
			WSkin:SetUIPanelWindowInfo(PlayerTalentFrame, "width", nil, 31)
			offset = true
		else
			WSkin:SetUIPanelWindowInfo(PlayerTalentFrame, "width")
		end

		hooksecurefunc("PlayerTalentFrame_UpdateSpecs", function(_, numTalentGroups, _, numPetTalentGroups)
			if offset and numTalentGroups + numPetTalentGroups <= 1 then
				WSkin:SetUIPanelWindowInfo(PlayerTalentFrame, "width")
				offset = nil
			elseif not offset and numTalentGroups + numPetTalentGroups > 1 then
				WSkin:SetUIPanelWindowInfo(PlayerTalentFrame, "width", nil, 31)
				offset = true
			end
		end)
	end

	WSkin:HandleCloseButton(PlayerTalentFrameCloseButton, PlayerTalentFrame.backdrop)

	local function glyphFrameOnShow(self)
		if GlyphFrame and GlyphFrame:IsShown() then
			self:Hide()
		end
	end

	PlayerTalentFrameStatusFrame:HookScript("OnShow", glyphFrameOnShow)
	PlayerTalentFrameActivateButton:HookScript("OnShow", glyphFrameOnShow)

	WSkin:StripTextures(PlayerTalentFrameStatusFrame)
	WSkin:StripTextures(PlayerTalentFramePointsBar)
	WSkin:StripTextures(PlayerTalentFramePreviewBar)

	WSkin:HandleButton(PlayerTalentFrameActivateButton)
	WSkin:HandleButton(PlayerTalentFrameResetButton)
	WSkin:HandleButton(PlayerTalentFrameLearnButton)

	WSkin:StripTextures(PlayerTalentFramePreviewBarFiller)

	WSkin:StripTextures(PlayerTalentFrameScrollFrame)
	WSkin:CreateBackdrop(PlayerTalentFrameScrollFrame, "Default")
	WSkin:HandleScrollBar(PlayerTalentFrameScrollFrameScrollBar)

	for i = 1, MAX_NUM_TALENTS do
		local talent = _G["PlayerTalentFrameTalent"..i]
		local icon = _G["PlayerTalentFrameTalent"..i.."IconTexture"]

		if talent then
			WSkin:StripTextures(talent)
			WSkin:CreateBackdrop(talent, "Default")

			if icon then
				WSkin:SetInside(icon)
				icon:SetTexCoord(unpack(TEXCOORDS))
				icon:SetDrawLayer("ARTWORK")
			end
		end
	end

	for i = 1, 4 do
		WSkin:HandleTab(_G["PlayerTalentFrameTab"..i])
	end

	if MAX_TALENT_TABS then
		for i = 1, MAX_TALENT_TABS do
			local tab = _G["PlayerSpecTab"..i]
			if tab then
				tab:GetRegions():Hide()
				WSkin:CreateBackdrop(tab, "Default")
				local norm = tab:GetNormalTexture()
				if norm then
					WSkin:SetInside(norm)
					norm:SetTexCoord(unpack(TEXCOORDS))
				end
			end
		end
	end

	WSkin:Point(PlayerTalentFrameStatusFrame, "TOPLEFT", 57, -40)
	WSkin:Point(PlayerTalentFrameActivateButton, "TOP", 0, -40)

	WSkin:Width(PlayerTalentFrameScrollFrame, 302)
	WSkin:Point(PlayerTalentFrameScrollFrame, "TOPRIGHT", PlayerTalentFrame, "TOPRIGHT", -62, -77)
	PlayerTalentFrameScrollFrame:SetPoint("BOTTOM", PlayerTalentFramePointsBar, "TOP", 0, 0)

	WSkin:Point(PlayerTalentFrameScrollFrameScrollBar, "TOPLEFT", PlayerTalentFrameScrollFrame, "TOPRIGHT", 4, -18)
	WSkin:Point(PlayerTalentFrameScrollFrameScrollBar, "BOTTOMLEFT", PlayerTalentFrameScrollFrame, "BOTTOMRIGHT", 4, 18)

	WSkin:Point(PlayerTalentFrameResetButton, "RIGHT", -4, 1)
	WSkin:Point(PlayerTalentFrameLearnButton, "RIGHT", PlayerTalentFrameResetButton, "LEFT", -3, 0)

	WSkin:Point(PlayerSpecTab1, "TOPLEFT", PlayerTalentFrame, "TOPRIGHT", -33, -65)
	PlayerSpecTab1.ClearAllPoints = function() end
	PlayerSpecTab1.SetPoint = function() end

	WSkin:Point(PlayerTalentFrameTab1, "BOTTOMLEFT", 11, 46)
end)