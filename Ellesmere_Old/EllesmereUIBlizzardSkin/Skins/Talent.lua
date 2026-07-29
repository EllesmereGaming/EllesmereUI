local WSkin = _G.EllesmereUIBlizzardSkin
local _G = _G

--Lua functions
local unpack = unpack

-- Standard icon tex coordinates to crop the default icon border
local TEXCOORDS = { 0.08, 0.92, 0.08, 0.92 }

WSkin:AddCallback("Skin_Talent", function()

	PlayerTalentFrame:StripTextures(true)
	PlayerTalentFrame:CreateBackdrop("Transparent")
	PlayerTalentFrame.backdrop:Point("TOPLEFT", 11, -12)
	PlayerTalentFrame.backdrop:Point("BOTTOMRIGHT", -32, 76)

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

	PlayerTalentFrameStatusFrame:StripTextures()
	PlayerTalentFramePointsBar:StripTextures()
	PlayerTalentFramePreviewBar:StripTextures()

	WSkin:HandleButton(PlayerTalentFrameActivateButton)
	WSkin:HandleButton(PlayerTalentFrameResetButton)
	WSkin:HandleButton(PlayerTalentFrameLearnButton)

	PlayerTalentFramePreviewBarFiller:StripTextures()

	PlayerTalentFrameScrollFrame:StripTextures()
	PlayerTalentFrameScrollFrame:CreateBackdrop("Default")
	WSkin:HandleScrollBar(PlayerTalentFrameScrollFrameScrollBar)

	for i = 1, MAX_NUM_TALENTS do
		local talent = _G["PlayerTalentFrameTalent"..i]
		local icon = _G["PlayerTalentFrameTalent"..i.."IconTexture"]

		if talent then
			talent:StripTextures()
			talent:CreateBackdrop("Default")

			if icon then
				icon:SetInside()
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
				tab:CreateBackdrop("Default")
				local norm = tab:GetNormalTexture()
				if norm then
					norm:SetInside()
					norm:SetTexCoord(unpack(TEXCOORDS))
				end
			end
		end
	end

	PlayerTalentFrameStatusFrame:Point("TOPLEFT", 57, -40)
	PlayerTalentFrameActivateButton:Point("TOP", 0, -40)

	PlayerTalentFrameScrollFrame:Width(302)
	PlayerTalentFrameScrollFrame:Point("TOPRIGHT", PlayerTalentFrame, "TOPRIGHT", -62, -77)
	PlayerTalentFrameScrollFrame:SetPoint("BOTTOM", PlayerTalentFramePointsBar, "TOP", 0, 0)

	PlayerTalentFrameScrollFrameScrollBar:Point("TOPLEFT", PlayerTalentFrameScrollFrame, "TOPRIGHT", 4, -18)
	PlayerTalentFrameScrollFrameScrollBar:Point("BOTTOMLEFT", PlayerTalentFrameScrollFrame, "BOTTOMRIGHT", 4, 18)

	PlayerTalentFrameResetButton:Point("RIGHT", -4, 1)
	PlayerTalentFrameLearnButton:Point("RIGHT", PlayerTalentFrameResetButton, "LEFT", -3, 0)

	PlayerSpecTab1:Point("TOPLEFT", PlayerTalentFrame, "TOPRIGHT", -33, -65)
	PlayerSpecTab1.ClearAllPoints = function() end
	PlayerSpecTab1.SetPoint = function() end

	PlayerTalentFrameTab1:Point("BOTTOMLEFT", 11, 46)
end)