if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_SpecOverrides_Hooks.lua
--
--  The page hooks and the events.
--  Reads the earlier Spec Overrides files through EUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
local I = EUI_NS._soInternals
-- EllesmereUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not I or I.broken then return end
I.broken = true

local DeepCopy, GetStore, RunRefreshers = I.DeepCopy, I.GetStore, I.RunRefreshers
local PruneRedundantValues, RequestGoldWalk = I.PruneRedundantValues, I.RequestGoldWalk
local OnPageRebuilt, PruneOrphanEntries = I.OnPageRebuilt, I.PruneOrphanEntries
local SetCombatFolders, SetWatchResync = I.SetCombatFolders, I.SetWatchResync

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of EllesmereUI_SpecOverrides.lua).
local _combatFolders = nil
I.combatFoldersSetters[#I.combatFoldersSetters + 1] = function(v) _combatFolders = v end

-------------------------------------------------------------------------------
--  Hooks + events
-------------------------------------------------------------------------------
-- Golden borders + watcher seed-absorption on page changes. RefreshPage only
-- rebuilds rows when forced; the fast path neither seeds nor re-rows.
if EllesmereUI.SelectModule then
    hooksecurefunc(EllesmereUI, "SelectModule", OnPageRebuilt)
end
if EllesmereUI.SelectPage then
    hooksecurefunc(EllesmereUI, "SelectPage", OnPageRebuilt)
end
if EllesmereUI.RefreshPage then
    hooksecurefunc(EllesmereUI, "RefreshPage", function(_, force)
        if force then
            SetWatchResync(true)
        end
        RequestGoldWalk()
    end)
end


local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_LOGOUT")
evFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Ellesmere: moved unchanged by the file split; multi-event frame (login, logout, combat end)
evFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- De-alias repair for stores that banked live TABLE references, which aliased
        -- the store to the live profile (any later live edit silently mutated the
        -- stored "override"). DeepCopy every table-typed value once so stores own their
        -- data. Harvests skip table values, so it cannot recur.
        local function DeAlias(store)
            for _, e in ipairs(store or {}) do
                if e.values then
                    for _, m in pairs(e.values) do
                        if type(m) == "table" then
                            for fkey, v in pairs(m) do
                                if type(v) == "table" then m[fkey] = DeepCopy(v) end
                            end
                        end
                    end
                end
            end
        end
        DeAlias(GetStore())
        if EllesmereUI._CondOv then DeAlias(EllesmereUI._CondOv.GetStore()) end
        -- One-time tidy: drop orphaned entries plus fkeys no group holds a value for.
        PruneOrphanEntries()
        PruneRedundantValues()
        if EllesmereUI._CondOv then
            EllesmereUI._CondOv.PruneEntries()
            EllesmereUI._CondOv.PruneRedundant()
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Keep the current spec's stored values in sync with live edits so a
        -- shared profile opened on another character applies fresh data. Also
        -- banks + restores an active Editing-as session.
        EllesmereUI.SpecOverrides_HarvestCurrent()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if _combatFolders then
            local fl = _combatFolders
            SetCombatFolders(nil)
            RunRefreshers(fl)
        end
    end
end)

I.broken = false
