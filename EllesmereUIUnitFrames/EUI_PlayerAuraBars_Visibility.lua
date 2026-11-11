if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_Visibility.lua
--
--  Visibility for the default Buffs and Debuffs bars. The shared Visibility
--  row's verdict dims the bar to its Hidden Opacity instead of hiding it.
--  Costs nothing until a bar has a visibility condition set: no updater and no
--  mouseover target is registered while both bars are unconfigured.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._pabInternals
-- EllesmereUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not I or I.broken then return end
I.broken = true

local PAB, DefaultBuffsCfg, DefaultDebuffsCfg = I.PAB, I.DefaultBuffsCfg, I.DefaultDebuffsCfg
local SetParentDim = I.SetParentDim

local buffsParent, debuffsParent
I.buffsParentSetters[#I.buffsParentSetters + 1] = function(v) buffsParent = v end
I.debuffsParentSetters[#I.debuffsParentSetters + 1] = function(v) debuffsParent = v end

local BARS = {
    { key = "buffs", isBuff = true },
    { key = "debuffs", isBuff = false },
}
local hovered, hoverArmed, proxies = {}, {}, {}
local updaterOn = false

local function ParentOf(bar)
    if bar.isBuff then return buffsParent end
    return debuffsParent
end

local function CfgOf(bar)
    local s = PAB()
    if not s then return nil end
    if bar.isBuff then return DefaultBuffsCfg(s) end
    return DefaultDebuffsCfg(s)
end

local function Configured(cfg)
    local v = cfg.visibility
    if v ~= nil and v ~= "always" then return true end
    return EllesmereUI.GetActiveVisibilityModes(cfg, "visibility") ~= nil
        or EllesmereUI.VisHasAnyOption(cfg)
end

-- Applies one bar's verdict. Returns true while the bar has a condition set.
local function ApplyBar(bar)
    local parent, cfg = ParentOf(bar), CfgOf(bar)
    if not parent or not cfg then return false end
    local key = bar.key
    if not Configured(cfg) then
        hoverArmed[key], hovered[key] = nil, nil
        if proxies[key] then
            EllesmereUI.UnregisterMouseoverTarget(proxies[key])
            proxies[key] = nil
        end
        SetParentDim(parent, nil)
        return false
    end

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

    if verdict == true or hovered[key] then
        SetParentDim(parent, nil)
    else
        SetParentDim(parent, (cfg.hiddenOpacity or 0) / 100)
    end
    return true
end

local function UpdateAll()
    for i = 1, #BARS do ApplyBar(BARS[i]) end
end

-- Registers the shared dispatcher's updater only while a bar needs it.
local function SyncVisibility()
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

I.SyncVisibility = SyncVisibility
I.broken = false
