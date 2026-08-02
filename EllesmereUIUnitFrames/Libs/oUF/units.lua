local parent, ns = ...
local oUF = ns.oUF
local Private = oUF.Private

local enableTargetUpdate = Private.enableTargetUpdate

-- Handles unit specific actions.
function oUF:HandleUnit(object, unit)
	local unit = object.unit or unit
	if(unit == 'target') then
		object:RegisterEvent('PLAYER_TARGET_CHANGED', object.UpdateAllElements)
	elseif(unit == 'mouseover') then
		object:RegisterEvent('UPDATE_MOUSEOVER_UNIT', object.UpdateAllElements)
	elseif(unit == 'focus') then
		object:RegisterEvent('PLAYER_FOCUS_CHANGED', object.UpdateAllElements)
	elseif(unit:match('%w+target') or unit:match('boss%d?$')) then
		enableTargetUpdate(object)
	end
end

-- Public in current oUF. Wrath has no unit tokens for these frames, so it uses
-- the same polling mechanism as target-of-target and boss units.
function oUF:HandleEventlessUnit(object)
	return enableTargetUpdate(object)
end
