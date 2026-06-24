--------------------------------------------------------------------------------
--  EllesmereUI_ExternalModules.lua
--  Public extension surface for third-party addons to register as native
--  EllesmereUI modules with their own sidebar entry and options page.
--
--  Two layers live here:
--    1. Callback bus  -- EllesmereUI.RegisterModuleCallback / FireModuleCallback
--       Lets external modules subscribe to host lifecycle events they cannot
--       otherwise observe (e.g. in-session profile switches). Internal callers
--       (EllesmereUI_Profiles.lua etc.) fire events through Fire*; external
--       modules subscribe through Register*. Every listener is xpcall'd so one
--       bad callback cannot block the host lifecycle.
--    2. RegisterExternalModule(spec) -- injects a third-party addon into the
--       sidebar builder, page dispatch, and reset roster, with full error
--       isolation so a buggy module cannot brick the options UI. (Layer 2 is
--       added by a follow-up commit on this branch.)
--
--  Loaded after EllesmereUI.lua. All API surface is exposed on the
--  _G.EllesmereUI table; this file intentionally adds NO locals to
--  EllesmereUI.lua's main chunk, which sits at the Lua 5.1 200-upvalue limit.
--------------------------------------------------------------------------------
local ADDON_NAME = ...

local EllesmereUI = EllesmereUI or {}
_G.EllesmereUI = EllesmereUI

-- Lua/WoW API locals (kept on this file's chunk, not EllesmereUI.lua's)
local type, pairs, ipairs, error = type, pairs, ipairs, error
local tinsert, xpcall, geterrorhandler = table.insert, xpcall, geterrorhandler
local safecall_iter

do
    -- xpcall wrapper used by the callback bus. Errors route through the
    -- global error handler (which the user can override via /console) so a
    -- failing listener shows up in the BugGrabber/AddOns debug stream rather
    -- than silently disappearing.
    local function errorHandler(err)
        local h = geterrorhandler()
        if h then h(err) end
    end
    safecall_iter = function(list, ...)
        for i = 1, #list do
            local fn = list[i]
            if type(fn) == "function" then
                xpcall(fn, errorHandler, ...)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Layer 1: External Module Callback Bus
-------------------------------------------------------------------------------
-- Event name -> array of listener functions. Populated lazily by
-- RegisterModuleCallback; drained by FireModuleCallback. Lives on this file's
-- chunk so it does not consume an upvalue in EllesmereUI.lua.
local moduleCallbacks = {}

--- Subscribe to a host lifecycle event.
-- Known events (fired by the host):
--   "ProfileChanged"  -- fired by EllesmereUI.SwitchProfile after the active
--                       profile is repointed. Receives (profileName).
-- @param event  string event name
-- @param fn     function callback; xpcall'd on dispatch
function EllesmereUI.RegisterModuleCallback(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return end
    local list = moduleCallbacks[event]
    if not list then list = {}; moduleCallbacks[event] = list end
    list[#list + 1] = fn
end

--- Fire a lifecycle event to all registered listeners. Internal use only.
-- External modules subscribe via RegisterModuleCallback; only the host fires.
-- @param event  string event name
-- @param ...    payload forwarded to every listener
function EllesmereUI.FireModuleCallback(event, ...)
    local list = moduleCallbacks[event]
    if not list then return end
    safecall_iter(list, ...)
end
