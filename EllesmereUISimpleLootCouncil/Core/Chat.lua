if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Chat = {}
addon.Chat = Chat



local function Emit(isError, prefix, text)
    local override = addon.ChatSinkOverride
    if override then
        local fn = isError and override.Error or override.Print
        if fn and pcall(fn, prefix .. text) then return end
    end
    print(prefix .. text)
end

local function Prefix(kind)
    local prefixes = addon.Log and addon.Log.CHAT_PREFIX
    return prefixes and prefixes[kind] or ""
end


function Chat.Print(text) Emit(false, Prefix("accent"), text) end
function Chat.Warn(text) Emit(false, Prefix("warn"), text) end
function Chat.Error(text) Emit(true, Prefix("error"), text) end


function Chat.Raw(text) Emit(false, "", text) end


function Chat.Echo(level, text)
    local prefixes = addon.Log and addon.Log.ECHO_PREFIX
    Emit(level == "ERROR", prefixes and prefixes[level] or "", text)
end
