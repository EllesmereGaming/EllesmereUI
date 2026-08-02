local _, ns = ...
local Private = ns.oUF.Private

function Private.argcheck(value, num, ...)
	assert(type(num) == 'number', "Bad argument #2 to 'argcheck' (number expected, got " .. type(num) .. ')')

	for i = 1, select('#', ...) do
		if(type(value) == select(i, ...)) then return end
	end

	local types = strjoin(', ', ...)
	local name = debugstack(2,2,0):match(": in function [`<](.-)['>]")
	error(string.format("Bad argument #%d to '%s' (%s expected, got %s)", num, name, types, type(value)), 3)
end

function Private.print(...)
	print('|cff33ff99oUF:|r', ...)
end

function Private.error(...)
	Private.print('|cffff0000Error:|r ' .. string.format(...))
end

-- Modern oUF reports programming errors through the client's configured error
-- handler. Keep Private.error above for layouts which used the old, non-fatal
-- helper directly.
function Private.nierror(message)
	return geterrorhandler()(message)
end

function Private.unitExists(unit)
	return unit and UnitExists(unit)
end

function Private.unitIsUnit(unit1, unit2)
	return unit1 and unit2 and UnitIsUnit(unit1, unit2)
end

function Private.unitSelectionType(unit, considerHostile)
	if(considerHostile and UnitThreatSituation('player', unit)) then
		return 0
	elseif(UnitIsDead(unit) or UnitIsGhost(unit)) then
		return 9
	elseif(UnitIsPlayer(unit)) then
		if(UnitIsUnit(unit, 'player')) then
			return 5
		elseif(UnitInParty(unit) or UnitInRaid(unit)) then
			return 6
		elseif(UnitIsFriend('player', unit)) then
			return 8
		end
	end

	local reaction = UnitReaction(unit, 'player')
	if(not reaction) then return end
	if(reaction <= 2) then
		return 0
	elseif(reaction == 3) then
		return 1
	elseif(reaction == 4) then
		return 2
	else
		return 3
	end
end
