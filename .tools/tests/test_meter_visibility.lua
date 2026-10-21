local override = false
local shown, instance, vis, hovered = true, false, true, false
local preview, options, toggle = false, false, false
local frame = {}
function frame:Hide() self.shown = false end
function frame:Show() self.shown = true end
function frame:SetAlpha() end
function frame:EnableMouse() end
local W = { idx = 1 }
local ns = {}
local bars = { MeterDockState = function() return true, shown end, PlaceDockMeter = function() end }
bars.MeterDockOverridesVisibility = function() return override end
local EUI = { _ModuleNS = { EllesmereUIDataBars = bars }, EvalVisibility = function() return vis end,
 VisWantsMouseover = function() return hovered end }
local function DB() return {} end
local function InstanceHidden() return instance end
    function W.UpdateVisibility()
        if not frame then return end
        local bars = EUI._ModuleNS.EllesmereUIDataBars
        local docked, shown
        if bars and bars.MeterDockState then docked, shown = bars.MeterDockState(W.idx) end
        if docked then
            bars.PlaceDockMeter(frame, W.idx)
            if not shown then frame:Hide(); return end
            if bars.MeterDockOverridesVisibility and bars.MeterDockOverridesVisibility() then
                frame:SetAlpha(1)
                frame:EnableMouse(true)
                frame:Show()
                return
            end
        end
        local c = DB()
        if EUI._unlockActive or ns._optionsOpen then frame:SetAlpha(1); frame:EnableMouse(true); frame:Show(); return end
        -- Hotkey toggle outranks every configured rule but yields to the two modes above
        if ns._toggleHidden then frame:Hide(); return end
        local vis = EUI.EvalVisibility(c)
        if not vis or vis == false then frame:Hide(); return end
        -- Per-window instance visibility
        if InstanceHidden() then frame:Hide(); return end
        if vis == "mouseover" then frame:Hide()
        else frame:SetAlpha(1); frame:EnableMouse(true); frame:Show() end
    end

    -- The mouseover scan's predicate (registered here and again by W.Reapply). Hover-gated
    -- sets only reveal while their conditions pass; a legacy single "mouseover" behaves exactly as before
    local function MouseoverActive()
        -- The mouseover scanner shows the frame without going through UpdateVisibility,
        -- so the toggle and the window's instance rules have to be refused here as well
        local bars = EUI._ModuleNS.EllesmereUIDataBars
        if bars and bars.MeterDockState then
            local docked, shown = bars.MeterDockState(W.idx)
            if docked and not shown then return false end
        end
        if ns._toggleHidden or InstanceHidden() then return false end
        local c = DB()
        return c ~= nil and EUI.VisWantsMouseover(c, "visibility")
    end

W.UpdateVisibility(); assert(frame.shown)
vis = false; W.UpdateVisibility(); assert(not frame.shown)
vis = true; instance = true; W.UpdateVisibility(); assert(not frame.shown)
instance = false; ns._toggleHidden = true; W.UpdateVisibility(); assert(not frame.shown)
ns._toggleHidden = false; shown = false; W.UpdateVisibility(); assert(not frame.shown)
shown = true; vis = 'mouseover'; hovered = true; W.UpdateVisibility(); assert(not frame.shown)
assert(MouseoverActive())
shown = false; assert(not MouseoverActive())
shown = true; ns._toggleHidden = true; assert(not MouseoverActive())
ns._toggleHidden = false; instance = true; assert(not MouseoverActive())
instance = false; EUI._unlockActive = true; W.UpdateVisibility(); assert(frame.shown)
shown = false; W.UpdateVisibility(); assert(not frame.shown)
print('PASS: dock respects visibility, instance filters, hotkey, mouseover and manual hide')

EUI._unlockActive = false; shown = true; override = true
vis = false; instance = true; ns._toggleHidden = true
W.UpdateVisibility(); assert(frame.shown)
shown = false; W.UpdateVisibility(); assert(not frame.shown)
print('PASS: manual show overrides all rules; manual hide still wins')
