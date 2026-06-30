-------------------------------------------------------------------------------
--  EllesmereUI_Visibility.lua
--  Shared visibility dispatcher. Each module (Minimap, Friends, QuestTracker,
--  Cursor) registers its own update function here; this file owns the event
--  frame, combat state, mouseover polling, and the global bridge names.
-------------------------------------------------------------------------------
local EUI = _G.EllesmereUI or {}
_G.EllesmereUI = EUI

-------------------------------------------------------------------------------
--  Combat state (single source of truth)
-------------------------------------------------------------------------------
local _inCombat = false

local function IsInCombat() return _inCombat end

EUI.IsInCombat = IsInCombat

-------------------------------------------------------------------------------
--  Eval helper (shared by all modules' cfg checks)
-------------------------------------------------------------------------------
-- Returns true = show, false = hide, "mouseover" = mouseover mode
local function EvalVisibility(cfg)
    if not cfg then return true end
    if EUI.CheckVisibilityOptions and EUI.CheckVisibilityOptions(cfg) then
        return false
    end
    local mode = cfg.visibility or "always"
    if mode == "mouseover" then return "mouseover" end
    if mode == "always" then return true end
    if mode == "never" then return false end
    if mode == "in_combat" then return _inCombat end
    if mode == "out_of_combat" then return not _inCombat end
    local inGroup = IsInGroup()
    local inRaid  = IsInRaid()
    if mode == "in_raid"  then return inRaid end
    if mode == "in_party" then return inGroup and not inRaid end
    if mode == "solo"     then return not inGroup end
    return true
end

EUI.EvalVisibility = EvalVisibility

-------------------------------------------------------------------------------
--  Updater registry
-------------------------------------------------------------------------------
local updaters = {}

-- Register a module's update function. Called whenever visibility state may
-- have changed (combat/zone/group/target change). The function should read
-- its own DB state and Show/Hide its frame accordingly.
function EUI.RegisterVisibilityUpdater(fn)
    if type(fn) ~= "function" then return end
    updaters[#updaters + 1] = fn
end

function EUI.UnregisterVisibilityUpdater(fn)
    for i = #updaters, 1, -1 do
        if updaters[i] == fn then
            table.remove(updaters, i)
            return
        end
    end
end

-- Mouseover poll registry: each entry is { frame=, visible=, isActive=fn }.
-- isActive returns true when that frame currently wants mouseover behavior.
local mouseoverTargets = {}

function EUI.RegisterMouseoverTarget(frame, isActive)
    if not frame or type(isActive) ~= "function" then return end
    mouseoverTargets[#mouseoverTargets + 1] = { frame = frame, visible = false, isActive = isActive }
end

-------------------------------------------------------------------------------
--  Dispatcher
-------------------------------------------------------------------------------
local function RequestVisibilityUpdate()
    for i = 1, #updaters do
        local ok = pcall(updaters[i])
        if not ok then
            -- swallow; one bad updater should not take down the rest
        end
    end
end

EUI.RequestVisibilityUpdate = RequestVisibilityUpdate

-- Deferred callback so we don't re-allocate a closure on every event
local function DeferredRequest()
    RequestVisibilityUpdate()
end

-------------------------------------------------------------------------------
--  Event frame
-------------------------------------------------------------------------------
local visFrame = CreateFrame("Frame")
visFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visFrame:RegisterEvent("PLAYER_DEAD")
visFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
visFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
visFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
visFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
visFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

visFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        _inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        _inCombat = false
    elseif event == "PLAYER_DEAD" then
        -- A dead player is never in combat, but PLAYER_REGEN_ENABLED is not
        -- guaranteed to fire on death (notably when dying mid-encounter in an
        -- instance). A missed "left combat" event would otherwise leave
        -- _inCombat stuck true, hiding every "Out of Combat" frame until a
        -- reload. Clearing it here is the safety net for that case.
        _inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-sync from the real combat state across world / instance boundaries
        -- in case a regen toggle was missed while loading.
        _inCombat = InCombatLockdown() and true or false
    end
    C_Timer.After(0, DeferredRequest)
end)

-------------------------------------------------------------------------------
--  Mouseover poll
-------------------------------------------------------------------------------
local mouseoverPoll = CreateFrame("Frame")
-- Cursor-in-bounds check (works on hidden frames using saved position/size)
local function IsCursorOver(frame)
    if not frame.GetRect then return false end
    local l, b, w, h = frame:GetRect()
    if not l then return false end
    local es = frame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / es, cy / es
    return cx >= l and cx <= l + w and cy >= b and cy <= b + h
end

local moElapsed = 0
mouseoverPoll:SetScript("OnUpdate", function(_, dt)
    moElapsed = moElapsed + dt
    if moElapsed < 0.15 then return end
    moElapsed = 0
    for i = 1, #mouseoverTargets do
        local t = mouseoverTargets[i]
        local frame = t.frame
        if frame then
            if t.isActive() then
                t._wasActive = true
                local over = IsCursorOver(frame)
                if over and not t.visible then
                    t.visible = true
                    frame:SetAlpha(1); frame:EnableMouse(true); frame:Show()
                elseif not over and t.visible then
                    t.visible = false
                    frame:Hide()
                end
            elseif t._wasActive then
                -- isActive just turned off -- clear tracking state and let
                -- UpdateVisibility handle the alpha for the new mode.
                t._wasActive = false
                t.visible = nil
            end
        end
    end
end)

-------------------------------------------------------------------------------
--  Compat globals (kept for the many call sites already using them)
-------------------------------------------------------------------------------
_G._EBS_InCombat         = IsInCombat
_G._EBS_EvalVisibility   = EvalVisibility
_G._EBS_UpdateVisibility = RequestVisibilityUpdate
-- UpdateVisEventRegistration is a no-op now -- the events are always on,
-- but the overhead is trivial (a handful of rarely-firing events).
_G._EBS_UpdateVisEventRegistration = function() end
