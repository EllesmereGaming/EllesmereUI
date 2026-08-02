--[[
# Element: Totems (Wrath compatibility)

Handles the player's four totem slots using the modern oUF Totems widget.
Each entry may expose optional Icon and Cooldown sub-widgets.
--]]

local _, ns = ...
local oUF = ns.oUF

local _, playerClass = UnitClass('player')
local priorities = STANDARD_TOTEM_PRIORITIES or {1, 2, 3, 4}
if(playerClass == 'SHAMAN' and SHAMAN_TOTEM_PRIORITIES) then
	priorities = SHAMAN_TOTEM_PRIORITIES
end

local function UpdateTooltip(self)
	GameTooltip:SetTotem(self:GetID())
end

local function OnEnter(self)
	if(not self:IsVisible()) then return end
	GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
	self:UpdateTooltip()
end

local function OnLeave()
	GameTooltip:Hide()
end

local function UpdateTotem(self, event, slot)
	local element = self.Totems
	if(not slot or slot > #element) then return end

	if(element.PreUpdate) then
		element:PreUpdate(slot)
	end

	local totem = element[priorities[slot] or slot]
	local haveTotem, name, start, duration, icon = GetTotemInfo(slot)

	if(haveTotem) then
		totem:Show()
	else
		totem:Hide()
	end

	if(totem.Icon) then
		totem.Icon:SetTexture(icon)
	end

	if(totem.Cooldown) then
		if(haveTotem and duration and duration > 0) then
			totem.Cooldown:SetCooldown(start, duration)
			totem.Cooldown:Show()
		else
			totem.Cooldown:Hide()
		end
	end

	if(element.PostUpdate) then
		return element:PostUpdate(slot, haveTotem, name, start, duration, icon)
	end
end

local function Path(self, ...)
	return (self.Totems.Override or UpdateTotem)(self, ...)
end

local function Update(self, event)
	for slot = 1, #self.Totems do
		Path(self, event, slot)
	end
end

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate')
end

local function Enable(self)
	local element = self.Totems
	if(element) then
		element.__owner = self
		element.ForceUpdate = ForceUpdate

		for slot = 1, #element do
			local totem = element[priorities[slot] or slot]
			totem:SetID(slot)

			if(totem.IsMouseEnabled and totem:IsMouseEnabled()) then
				totem:SetScript('OnEnter', OnEnter)
				totem:SetScript('OnLeave', OnLeave)
				totem.UpdateTooltip = totem.UpdateTooltip or UpdateTooltip
			end
		end

		self:RegisterEvent('PLAYER_TOTEM_UPDATE', Path, true)

		if(TotemFrame) then
			TotemFrame:UnregisterEvent('PLAYER_TOTEM_UPDATE')
			TotemFrame:UnregisterEvent('PLAYER_ENTERING_WORLD')
			TotemFrame:UnregisterEvent('UPDATE_SHAPESHIFT_FORM')
			TotemFrame:UnregisterEvent('PLAYER_TALENT_UPDATE')
		end

		return true
	end
end

local function Disable(self)
	local element = self.Totems
	if(element) then
		for slot = 1, #element do
			element[slot]:Hide()
		end

		if(TotemFrame) then
			TotemFrame:RegisterEvent('PLAYER_TOTEM_UPDATE')
			TotemFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
			TotemFrame:RegisterEvent('UPDATE_SHAPESHIFT_FORM')
			TotemFrame:RegisterEvent('PLAYER_TALENT_UPDATE')
		end

		self:UnregisterEvent('PLAYER_TOTEM_UPDATE', Path)
	end
end

oUF:AddElement('Totems', Update, Enable, Disable)
