if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_InGameNavigation.lua  (WoW Forever only)
--  Show Waypoints in the World: turns on the game's own in-game navigation
--  (showInGameNavigation CVar, which no options page offers on Forever), held
--  while on and given back after. The marker is Blizzard's own; nothing of it
--  is drawn, moved or hidden here.
-------------------------------------------------------------------------------
local _, module = ...
local OWNER = "EllesmereUIForeverEssentials"
local CVAR = "showInGameNavigation"

-- Settings live in EllesmereUIDB.inGameNavigation; unset keys read these.
-- navWas: the game's showInGameNavigation before ours.
local F = module.Feature("inGameNavigation", {
    enabled = false,
})

-- Whether turning the feature on or off would write the CVar.
local function Writes(on)
    local cur = C_CVar.GetCVar(CVAR)
    if on then return cur ~= nil and cur ~= "1" end
    local was = F.Read().navWas
    return was ~= nil and cur ~= was
end

-- The game's navigation on while ours is; back to what it was after.
local function HoldNavigation(on)
    local cfg = F.Read()
    local cur = C_CVar.GetCVar(CVAR)
    if on then
        cfg = F.Cfg()
        if cfg.navWas == nil then cfg.navWas = cur end
        if cur and cur ~= "1" then EllesmereUI.HoldCVar(CVAR, "1", OWNER) end
    elseif cfg.navWas ~= nil then
        local was = cfg.navWas
        cfg.navWas = nil
        if was and cur ~= was then EllesmereUI.ReleaseCVar(CVAR, was, OWNER) end
    end
end

-- Login and the options; takes effect at once.
local function Apply()
    HoldNavigation(F.Enabled())
end

-- The options switch. CVAR_UPDATE fires inside the CVar write and the open
-- world map's pin providers listen to it, so a change that writes the CVar
-- waits for the map to close; false when refused.
local function Set(on)
    if Writes(on) and WorldMapFrame and WorldMapFrame:IsShown() then return false end
    F.Cfg().enabled = on
    Apply()
    return true
end

-- Options-page entry points.
EllesmereUI._InGameNavigation = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Set = Set,
}

F.Start(Apply)
