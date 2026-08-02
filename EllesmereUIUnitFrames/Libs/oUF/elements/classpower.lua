--[[
# Element: ClassPower (Wrath compatibility)

Exposes Wrath combo points through the modern oUF ClassPower widget. The
original ComboPoints element remains available for older layouts.
--]]

local _, ns = ...
local oUF = ns.oUF

local _, playerClass = UnitClass('player')
local MAX_POINTS = MAX_COMBO_POINTS or 5
local POWER_TYPE = 'COMBO_POINTS'

local function getPoints()
	if(UnitHasVehicleUI('player')) then
		return GetComboPoints('vehicle', 'target')
	end

	return GetComboPoints('player', 'target')
end

local function UpdateColor(element)
	local color = element.__owner.colors.power[POWER_TYPE]
		or element.__owner.colors.power.ENERGY
		or element.__owner.colors.power[3]

	if(color) then
		for index = 1, #element do
			local widget = element[index]
			if(widget:IsObjectType('StatusBar')) then
				widget:SetStatusBarColor(color[1], color[2], color[3])
			elseif(widget.SetVertexColor) then
				widget:SetVertexColor(color[1], color[2], color[3])
			end
		end
	end

	if(element.PostUpdateColor) then
		element:PostUpdateColor(color)
	end
end

local function Update(self, event)
	local element = self.ClassPower
	local current = getPoints()
	local maximum = MAX_POINTS
	local hasMaxChanged = maximum ~= element.__max

	if(element.PreUpdate) then
		element:PreUpdate('player')
	end

	for index = 1, #element do
		local widget = element[index]
		if(index <= maximum) then
			if(widget:IsObjectType('StatusBar')) then
				widget:Show()
				widget:SetValue(index <= current and 1 or 0)
			elseif(index <= current) then
				widget:Show()
			else
				widget:Hide()
			end
		else
			widget:Hide()
		end
	end

	element.__cur = current
	element.__max = maximum

	if(element.PostUpdate) then
		return element:PostUpdate(current, maximum, hasMaxChanged, POWER_TYPE)
	end
end

local function Path(self, ...)
	return (self.ClassPower.Override or Update)(self, ...)
end

local function Visibility(self, event)
	local element = self.ClassPower
	local visible = playerClass == 'ROGUE'
		or (playerClass == 'DRUID' and select(1, UnitPowerType('player')) == Enum.PowerType.Energy)
		or UnitHasVehicleUI('player')

	if(visible) then
		UpdateColor(element)
		Path(self, event)
	else
		for index = 1, #element do
			element[index]:Hide()
		end
	end

	if(visible ~= element.__visible and element.PostVisibility) then
		element:PostVisibility(visible)
	end
	element.__visible = visible
end

local function VisibilityPath(self, ...)
	return (self.ClassPower.OverrideVisibility or Visibility)(self, ...)
end

local function ForceUpdate(element)
	return VisibilityPath(element.__owner, 'ForceUpdate')
end

local function Enable(self, unit)
	local element = self.ClassPower
	if(element and (unit == 'player' or UnitIsUnit(unit, 'player'))) then
		element.__owner = self
		element.__max = 0
		element.ForceUpdate = ForceUpdate

		self:RegisterEvent('UNIT_COMBO_POINTS', Path, true)
		self:RegisterEvent('PLAYER_TARGET_CHANGED', Path, true)
		self:RegisterEvent('UNIT_DISPLAYPOWER', VisibilityPath)
		self:RegisterEvent('UNIT_ENTERED_VEHICLE', VisibilityPath)
		self:RegisterEvent('UNIT_EXITED_VEHICLE', VisibilityPath)

		for index = 1, #element do
			local widget = element[index]
			if(widget:IsObjectType('StatusBar')) then
				if(not widget:GetStatusBarTexture()) then
					widget:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
				end
				widget:SetMinMaxValues(0, 1)
			end
		end

		return true
	end
end

local function Disable(self)
	if(self.ClassPower) then
		self:UnregisterEvent('UNIT_COMBO_POINTS', Path)
		self:UnregisterEvent('PLAYER_TARGET_CHANGED', Path)
		self:UnregisterEvent('UNIT_DISPLAYPOWER', VisibilityPath)
		self:UnregisterEvent('UNIT_ENTERED_VEHICLE', VisibilityPath)
		self:UnregisterEvent('UNIT_EXITED_VEHICLE', VisibilityPath)

		for index = 1, #self.ClassPower do
			self.ClassPower[index]:Hide()
		end
	end
end

oUF:AddElement('ClassPower', VisibilityPath, Enable, Disable)
