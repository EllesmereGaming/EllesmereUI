-- Timer.lua

-- 2. C_Timer Polyfill with OnUpdate Accumulator Pool
if not C_Timer then
    C_Timer = {}
    local timers = {}
    local newTimers = {}
    local iterating = false
    local tickerId = 0
    local timerFrame = CreateFrame("Frame")

    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        iterating = true
        for id, t in pairs(timers) do
            if not t.cancelled then
                t.remaining = t.remaining - elapsed
                if t.remaining <= 0 then
                    if t.isTicker then
                        t.iterations = t.iterations + 1
                        t.remaining = t.remaining + t.duration
                        if t.remaining <= 0 then
                            t.remaining = t.duration
                        end
                        local success, err = pcall(t.callback, t)
                        if not success then
                            geterrorhandler()(err)
                        end
                        if t.cancelled then
                            timers[id] = nil
                        elseif t.maxIterations and t.iterations >= t.maxIterations then
                            t.cancelled = true
                            timers[id] = nil
                        end
                    else
                        t.cancelled = true
                        timers[id] = nil
                        local success, err = pcall(t.callback)
                        if not success then
                            geterrorhandler()(err)
                        end
                    end
                end
            else
                timers[id] = nil
            end
        end
        iterating = false
        
        for id, t in pairs(newTimers) do
            timers[id] = t
            newTimers[id] = nil
        end

        if not next(timers) then
            self:Hide()
        end
    end)
    timerFrame:Hide()

    local function createTimer(duration, callback, isTicker, maxIterations)
        tickerId = tickerId + 1
        local id = tickerId
        local t = {
            id = id,
            duration = duration,
            remaining = duration,
            callback = callback,
            isTicker = isTicker,
            iterations = 0,
            maxIterations = maxIterations,
            cancelled = false,
        }
        function t:Cancel()
            self.cancelled = true
            timers[id] = nil
            newTimers[id] = nil
        end
        if iterating then
            newTimers[id] = t
        else
            timers[id] = t
        end
        timerFrame:Show()
        return t
    end

    function C_Timer.After(duration, callback)
        createTimer(duration, callback, false)
    end

    function C_Timer.NewTimer(duration, callback)
        return createTimer(duration, callback, false)
    end

    function C_Timer.NewTicker(duration, callback, iterations)
        return createTimer(duration, callback, true, iterations)
    end
end
