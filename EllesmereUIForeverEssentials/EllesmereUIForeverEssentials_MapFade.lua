if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_MapFade.lua  (WoW Forever only)
--  Fade Map While Moving: turns on the game's own map fade (mapFade CVar,
--  which no options page offers), held while on and given back after.
--  Show the Game Behind the Map: the black behind the maximized map goes to
--  the chosen opacity and, with Click Through on, lets the mouse through to
--  the world. Blizzard only shows and hides BlackoutFrame, so the change
--  holds until turned off.
-------------------------------------------------------------------------------
local _, module = ...
local OWNER = "EllesmereUIForeverEssentials"

-- Settings live in EllesmereUIDB.worldMapFade; unset keys read these.
-- mapFadeWas: the game's mapFade before ours.
-- dimOpacity: 0-100, the black behind the maximized map while dim is on.
-- dimClickThrough: while dim is on, the mouse goes through to the world.
local F = module.Feature("worldMapFade", {
    enabled = false,
    dim = false,
    dimOpacity = 20,
    dimClickThrough = false,
})

local waiter
local dimmed = false      -- the background's alpha is ours
local mouseHeld = false   -- BlackoutFrame's mouse and wheel are ours
local mouseWas, wheelWas  -- BlackoutFrame's mouse and wheel before ours

-- The game's fade on while ours is; back to what it was after.
local function HoldGameFade(on)
    local cfg = F.Read()
    local cur = C_CVar.GetCVar("mapFade")
    if on then
        cfg = F.Cfg()
        if cfg.mapFadeWas == nil then cfg.mapFadeWas = cur end
        if cur and cur ~= "1" then EllesmereUI.HoldCVar("mapFade", "1", OWNER) end
    elseif cfg.mapFadeWas ~= nil then
        local was = cfg.mapFadeWas
        cfg.mapFadeWas = nil
        if was and cur ~= was then EllesmereUI.ReleaseCVar("mapFade", was, OWNER) end
    end
end

-- The black behind the maximized map. The world map loads on demand.
local function ApplyBackground()
    local dim = F.Get("dim") == true
    if not (dim or dimmed or mouseHeld) then return end
    if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
        if not waiter then
            waiter = CreateFrame("Frame")
            waiter:SetScript("OnEvent", function(self, _, name)
                if name ~= "Blizzard_WorldMap" then return end
                self:UnregisterEvent("ADDON_LOADED")
                ApplyBackground()
            end)
        end
        waiter:RegisterEvent("ADDON_LOADED")
        return
    end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("MapFadeBackground", ApplyBackground)
        return
    end
    local b = WorldMapFrame.BlackoutFrame
    if not (b and b.Blackout) then return end
    b.Blackout:SetAlpha(dim and (tonumber(F.Get("dimOpacity")) or 20) / 100 or 1)
    dimmed = dim
    local through = dim and F.Get("dimClickThrough") == true
    if through then
        if not mouseHeld then
            mouseWas = b:IsMouseEnabled()
            wheelWas = b:IsMouseWheelEnabled()
        end
        b:EnableMouse(false)
        if wheelWas then b:EnableMouseWheel(false) end
    elseif mouseHeld then
        b:EnableMouse(mouseWas)
        if wheelWas then b:EnableMouseWheel(true) end
    end
    mouseHeld = through
end

-- Login and the options; takes effect at once.
local function Apply()
    HoldGameFade(F.Enabled())
    if waiter and F.Get("dim") ~= true then waiter:UnregisterEvent("ADDON_LOADED") end
    ApplyBackground()
end

-- Options-page entry points.
EllesmereUI._MapFade = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
