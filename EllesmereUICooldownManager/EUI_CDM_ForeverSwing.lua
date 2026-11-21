if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_ForeverSwing.lua -- WoW FOREVER ONLY: the Cooldown Manager's one
--  weapon swing source.
--
--  One PLAYER_SWING listener for the module's two swing readers, the Bar Glows
--  swing window (EllesmereUICdmBarGlowSwing.lua) and the Swing Timer swipe on
--  icons (EUI_CDM_ForeverSwingSweep.lua). Registered only while one of them
--  watches; each swing's start and duration are kept per swing type and
--  handed to the watchers as the swing starts.
--
--    ns.CDM_Swing.Watch(key, fn)   fn(swing, start, duration) on every swing
--    ns.CDM_Swing.Unwatch(key)
--    ns.CDM_Swing.Last(swing)      -> start, duration of that hand's last swing
--
--  Off WoW Forever (no swing API) this file returns and ns.CDM_Swing is nil;
--  both readers return earlier on the same test.
-------------------------------------------------------------------------------
local _, ns = ...

if not (C_SwingTimer and Enum.PlayerSwingType) then return end

local GetTime = GetTime
local start, dur = {}, {}   -- [swing type] = the last swing's start / duration
local watchers = {}         -- [key] = fn
local ev = ns.TakeShell()

ev:SetScript("OnEvent", function(_, _, d, swing)
    if issecretvalue(d) or issecretvalue(swing) or swing == nil then return end
    if type(d) ~= "number" or d ~= d or d <= 0 or d == math.huge then return end
    local now = GetTime()
    start[swing], dur[swing] = now, d
    for _, fn in pairs(watchers) do fn(swing, now, d) end
end)

local S = {}

function S.Watch(key, fn)
    if watchers[key] == fn then return end
    local first = next(watchers) == nil
    watchers[key] = fn
    if first then ev:RegisterEvent("PLAYER_SWING") end
end

function S.Unwatch(key)
    if watchers[key] == nil then return end
    watchers[key] = nil
    if next(watchers) == nil then
        ev:UnregisterEvent("PLAYER_SWING")
        wipe(start)
        wipe(dur)
    end
end

function S.Last(swing)
    return start[swing], dur[swing]
end

ns.CDM_Swing = S
