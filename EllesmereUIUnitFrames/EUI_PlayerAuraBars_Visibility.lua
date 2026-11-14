if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_Visibility.lua
--
--  Visibility for the default Buffs and Debuffs bars, from the shared
--  Visibility row's verdict. Hidden Opacity above 0 dims the bar by alpha.
--  At 0 the parent is really hidden, because a transparent bar still takes
--  the mouse (tooltips, right-click cancel). Show/Hide on the parent is
--  protected in combat, so:
--    a selection made only of combat conditions (no option row, no
--    mouseover) is a secure state driver, which shows and hides by itself;
--    every other selection is decided in Lua: out of combat a hidden bar is
--    hidden through SetParentShownSafe's gate, and an escape driver shows the
--    parent whenever combat starts, where alpha carries the verdict, so a
--    condition that changes mid-fight (a target, a dismount, a hover) shows
--    the bar at once. The hide is taken again when combat ends.
--  Costs nothing until an enabled bar has a visibility condition set: no
--  updater, driver or mouseover target is registered otherwise.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._pabInternals
-- EllesmereUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not I or I.broken then return end
I.broken = true

local PAB, DefaultBuffsCfg, DefaultDebuffsCfg = I.PAB, I.DefaultBuffsCfg, I.DefaultDebuffsCfg
local SetParentDim, SetParentGate = I.SetParentDim, I.SetParentGate

local buffsParent, debuffsParent
I.buffsParentSetters[#I.buffsParentSetters + 1] = function(v) buffsParent = v end
I.debuffsParentSetters[#I.debuffsParentSetters + 1] = function(v) debuffsParent = v end

local BARS = {
    { key = "buffs", isBuff = true },
    { key = "debuffs", isBuff = false },
}
local hovered, hoverArmed, proxies, drivers = {}, {}, {}, {}
-- Shows the parent in combat and does nothing out of it: the state driver acts
-- only on "show" and "hide", and this string parses to neither out of combat.
local COMBAT_ESCAPE = "[combat] show"
local updaterOn = false
local SyncVisibility

local function ParentOf(bar)
    if bar.isBuff then return buffsParent end
    return debuffsParent
end

-- The bar's config, or nil while the bar is switched off (same check as
-- ApplyDefaultBarShown).
local function CfgOf(bar)
    local s = PAB()
    if not s then return nil end
    local cfg
    if bar.isBuff then cfg = DefaultBuffsCfg(s) else cfg = DefaultDebuffsCfg(s) end
    if s.enabled == true and cfg.enabled ~= false and s.useBlizzardBuffs ~= true then
        return cfg
    end
end

local function Configured(cfg)
    local v = cfg.visibility
    if v ~= nil and v ~= "always" then return true end
    return EllesmereUI.GetActiveVisibilityModes(cfg, "visibility") ~= nil
        or EllesmereUI.VisHasAnyOption(cfg)
end

-- Macro-conditional string for a combat-dependent selection, or nil.
local function DriverString(cfg, vm)
    if cfg.visibilityMatch == "any" and EllesmereUI.BuildAnyMatchTail then
        return (EllesmereUI.BuildAnyMatchTail(cfg, "visibility", vm))
    end
    if vm then return EllesmereUI.BuildVisibilityDriverString("", vm) end
    if cfg.visibility == "in_combat" then return "[combat] show; hide" end
    if cfg.visibility == "out_of_combat" then return "[nocombat] show; hide" end
end

-- Sets the parent's gate and driver. Registering or unregistering a driver
-- evaluates it at once, so that only happens out of combat; the dispatcher's
-- regen edge re-runs it for anything skipped.
local function SetGate(bar, parent, gate, str)
    local key = bar.key
    if drivers[key] ~= str then
        if InCombatLockdown() then
            ns.CombatQueue.Defer("PAB:vis", SyncVisibility)
            return
        end
        if str then
            RegisterStateDriver(parent, "visibility", str)
        else
            UnregisterStateDriver(parent, "visibility")
        end
        drivers[key] = str
    end
    -- The gate decides the parent's shown state; replay it through the shared path.
    if SetParentGate(parent, gate) then I.ApplyDefaultBarShown(bar.isBuff) end
end

-- Hands the bar back: no dim, gate, driver or mouseover target.
local function Release(bar, parent)
    local key = bar.key
    hoverArmed[key], hovered[key] = nil, nil
    if proxies[key] then
        EllesmereUI.UnregisterMouseoverTarget(proxies[key])
        proxies[key] = nil
    end
    SetParentDim(parent, nil)
    SetGate(bar, parent, nil, nil)
end

-- Applies one bar's verdict. Returns true while the bar is enabled and has a
-- condition set.
local function ApplyBar(bar)
    local parent = ParentOf(bar)
    if not parent then return false end
    local cfg = CfgOf(bar)
    if not cfg or not Configured(cfg) then
        Release(bar, parent)
        return false
    end
    local key = bar.key

    local verdict = EllesmereUI.EvalVisibility(cfg)
    hoverArmed[key] = verdict == "mouseover" or nil
    if not hoverArmed[key] then hovered[key] = nil end

    if hoverArmed[key] and not proxies[key] then
        local proxy = {}
        proxy.GetRect = function()
            local p = ParentOf(bar)
            if p then return p:GetRect() end
        end
        proxy.GetEffectiveScale = function()
            local p = ParentOf(bar)
            return p and p:GetEffectiveScale() or 1
        end
        proxy.SetAlpha = function() end
        proxy.EnableMouse = function() end
        proxy.Show = function() hovered[key] = true; ApplyBar(bar) end
        proxy.Hide = function() hovered[key] = nil; ApplyBar(bar) end
        proxies[key] = proxy
        EllesmereUI.RegisterMouseoverTarget(proxy, function() return hoverArmed[key] == true end)
    end

    local shown = verdict == true or hovered[key]
    local opacity = cfg.hiddenOpacity or 0
    if opacity > 0 then
        -- Dim by alpha; the parent stays shown.
        SetParentDim(parent, (not shown) and opacity / 100 or nil)
        SetGate(bar, parent, nil, nil)
        return true
    end

    local vm = EllesmereUI.GetActiveVisibilityModes(cfg, "visibility")
    local hasHover = (vm and vm.mouseover) or cfg.visibility == "mouseover"
    local str = not hasHover and not EllesmereUI.VisHasAnyOption(cfg)
        and EllesmereUI.VisDependsOnCombat(cfg, "visibility") and DriverString(cfg, vm) or nil
    if str then
        SetParentDim(parent, nil)
        SetGate(bar, parent, "driver", str)
        return true
    end

    -- Decided in Lua. The alpha is 0 while hidden, so the parent the escape
    -- driver shows at the start of a fight stays invisible until the verdict
    -- says otherwise.
    local gate = (not shown) and "hide" or nil
    SetParentDim(parent, gate and 0 or nil)
    SetGate(bar, parent, gate, COMBAT_ESCAPE)
    -- After a fight the parent is still shown by the escape driver: hide it.
    -- (That pass ends in SyncVisibility, which finds the parent hidden.)
    if gate and not InCombatLockdown() then
        local up = parent:IsShown()
        if not issecretvalue(up) and up then I.ApplyDefaultBarShown(bar.isBuff) end
    end
    return true
end

local function UpdateAll()
    for i = 1, #BARS do ApplyBar(BARS[i]) end
end

-- Registers the shared dispatcher's updater only while a bar needs it.
function SyncVisibility()
    local any = false
    for i = 1, #BARS do
        if ApplyBar(BARS[i]) then any = true end
    end
    if any and not updaterOn then
        updaterOn = true
        EllesmereUI.RegisterVisibilityUpdater(UpdateAll)
    elseif not any and updaterOn then
        updaterOn = false
        EllesmereUI.UnregisterVisibilityUpdater(UpdateAll)
    end
end

I.SetSyncVisibility(SyncVisibility)
-- The options rows' apply: a Visibility or Hidden Opacity write needs no restyle.
ns.PAB_SyncVisibility = SyncVisibility
I.broken = false
