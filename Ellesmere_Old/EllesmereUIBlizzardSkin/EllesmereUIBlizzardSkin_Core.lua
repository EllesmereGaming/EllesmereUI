local WSkin = _G.EllesmereUIBlizzardSkin

if not C_Timer then
	C_Timer = {}
	local ticker = CreateFrame("Frame")
	local timers = {}
	ticker:SetScript("OnUpdate", function(self, elapsed)
		for i = #timers, 1, -1 do
			local t = timers[i]
			t.timeLeft = t.timeLeft - elapsed
			if t.timeLeft <= 0 then
				t.func()
				if t.isTicker then
					t.timeLeft = t.duration
				else
					table.remove(timers, i)
				end
			end
		end
	end)
	function C_Timer.After(duration, func)
		table.insert(timers, {duration = duration, timeLeft = duration, func = func})
	end
	function C_Timer.NewTimer(duration, func)
		local t = {duration = duration, timeLeft = duration, func = func}
		table.insert(timers, t)
		return {
			Cancel = function()
				for i, v in ipairs(timers) do
					if v == t then table.remove(timers, i); break end
				end
			end
		}
	end
	function C_Timer.NewTicker(duration, func)
		local t = {duration = duration, timeLeft = duration, func = func, isTicker = true}
		table.insert(timers, t)
		return {
			Cancel = function()
				for i, v in ipairs(timers) do
					if v == t then table.remove(timers, i); break end
				end
			end
		}
	end
end

WSkin.callbacks = {}

function WSkin:AddCallback(name, func)
	self.callbacks[name] = func
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, addon)
	if event == "PLAYER_LOGIN" then
		for name, func in pairs(WSkin.callbacks) do
			func()
		end
		self:UnregisterEvent("PLAYER_LOGIN")
	end
end)
