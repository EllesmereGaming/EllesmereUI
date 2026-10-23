if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text


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



local MONTHS
local function MonthText(epoch)
    MONTHS = MONTHS or { T["Jan"], T["Feb"], T["Mar"], T["Apr"], T["May"], T["Jun"],
        T["Jul"], T["Aug"], T["Sep"], T["Oct"], T["Nov"], T["Dec"] }
    return MONTHS[tonumber(date("%m", epoch))] or date("%m", epoch)
end

function addon.DayText(epoch)

    return addon.Locale.Format(T["%s %d"], MonthText(epoch),
        tonumber(date("%d", epoch)) or 0)
end

local function ClockText(epoch)
    local hour, minute = tonumber(date("%H", epoch)) or 0, tonumber(date("%M", epoch)) or 0


    if GameTime_GetFormattedTime then return GameTime_GetFormattedTime(hour, minute, true) end
    return ("%02d:%02d"):format(hour, minute)
end

function addon.WhenText(epoch)

    return addon.Locale.Format(T["%s, %s"], addon.DayText(epoch), ClockText(epoch))
end
