if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil


local issecretvalue = issecretvalue


function addon.IsSecret(...)
    if not issecretvalue then return false end
    local n = select("#", ...)
    if n == 1 then return issecretvalue((...)) and true or false end
    for i = 1, n do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end



local settle = { running = false, cycles = 0 }
local driver

local function Settle(self)
    local started = debugprofilestop()
    repeat
        settle.steps = settle.steps + 1
        if collectgarbage("step", 100) then
            settle.cycles = settle.cycles + 1

            if settle.cycles >= 2 or settle.from - collectgarbage("count") >= settle.expect then
                settle.running = false
                self:Hide()
                if addon.Log then
                    addon.Log:D("Util", "settled", settle.cycles, "cycle(s)", settle.steps, "steps, freed",
                        math.floor(settle.from - collectgarbage("count")), "KB in", math.floor(debugprofilestop() - settle.began), "ms")
                end
                return
            end
        end
    until debugprofilestop() - started >= 1
end

function addon.SettleGC(expectKB)
    if settle.running or not (CreateFrame and collectgarbage and debugprofilestop) then return end
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", Settle)
    end
    settle.running, settle.cycles, settle.steps, settle.expect = true, 0, 0, expectKB or 1000
    settle.from, settle.began = collectgarbage("count"), debugprofilestop()
    if addon.Log then addon.Log:D("Util", "settling the collector from", math.floor(settle.from), "KB") end
    driver:Show()
end



function addon.DateText(epoch, utc, short)
    if utc then return short and date("!%d/%m/%y", epoch) or date("!%d/%m/%Y", epoch) end
    return short and date("%d/%m/%y", epoch) or date("%d/%m/%Y", epoch)
end


function addon.StoredDateText(text, short)
    local y, m, d = tostring(text):match("^(%d%d%d%d)/(%d%d)/(%d%d)$")
    if not y then return text end
    return ("%s/%s/%s"):format(d, m, short and y:sub(3) or y)
end


function addon.DayText(epoch)
    return ("%s %d"):format(date("%b", epoch), tonumber(date("%d", epoch)) or 0)
end


function addon.WhenText(epoch)
    local hour = tonumber(date("%H", epoch)) or 0
    local twelve = hour % 12
    if twelve == 0 then twelve = 12 end
    return ("%s, %d:%s%s"):format(addon.DayText(epoch), twelve, date("%M", epoch),
        hour < 12 and "am" or "pm")
end
