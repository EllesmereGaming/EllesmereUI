if EUI_CLIENT_BLOCKED then return end
local _, ns = ...
local EUI = EllesmereUI
local button, busy, manualOverride
local function Meters() return EUI._ModuleNS.EllesmereUIDamageMeters end
local function Target()
    local p = ns.GetProfile()
    local id = p and p.meterDockBar
    local cfg = id and ns.GetBar(id)
    local rec = id and ns._live[id]
    return p, cfg and cfg.orientation ~= "V" and rec and rec.enabled and rec.bar or nil
end
function ns.MeterDockState(idx)
    local p = ns.GetProfile()
    if not p or not p.meterDockBar then return false end
    if idx ~= 1 and idx ~= 2 and not (idx == 3 and p.meterDockHasSecond) then return false end
    if idx == 3 or (idx == 2 and p.meterDockCount == 1) then return true, false end
    local _, bar = Target()
    return true, bar and bar:IsShown() and (not manualOverride or p.meterDockShown ~= false) or false
end
function ns.MeterDockOverridesVisibility() return manualOverride == true end
function ns.ToggleMeterDock()
    local p = ns.GetProfile()
    if not p or not p.meterDockBar then return end
    local visible = false
    local dm = Meters()
    if dm and dm._windows then
        for i = 1, 2 do
            local win = dm._windows[i]
            if win and win.frame and win.frame:IsShown() then visible = true; break end
        end
    end
    manualOverride = true
    p.meterDockShown = not visible
    ns.RefreshMeterDock()
end
function ns.PlaceDockMeter(frame, idx)
    local docked = ns.MeterDockState(idx)
    if not docked then return false end
    local p, bar = Target()
    if not bar then return true end
    local x, y, w, h = bar:GetRect()
    if not x or not y or not w or not h then return true end
    local parentScale = UIParent:GetEffectiveScale()
    local barScale = bar:GetEffectiveScale() / parentScale
    local frameScale = frame:GetEffectiveScale() / parentScale
    local width = w * barScale
    local count = p.meterDockCount == 1 and 1 or 2
    local slot = idx == 2 and 1 or 0
    local height = p.meterDockHeight or 210
    local mw = (width - (count - 1) * 2) / count
    local left = x * barScale + slot * (mw + 2)
    local bottom = (y + h) * barScale + 2
    frame:SetClampedToScreen(false)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / frameScale, bottom / frameScale)
    frame:SetSize(mw / frameScale, height / frameScale)
    return true
end
function ns.RefreshMeterDock()
    if busy then return end
    busy = true
    local p, bar = Target()
    if p and p.meterDockBar and bar then
        if not bar._meterDockHooks then
            bar._meterDockHooks = true
            local function changed()
                local profile = ns.GetProfile()
                if profile and profile.meterDockBar then ns.RefreshMeterDock() end
            end
            bar:HookScript("OnShow", changed)
            bar:HookScript("OnHide", changed)
            bar:HookScript("OnSizeChanged", changed)
            hooksecurefunc(bar, "SetPoint", changed)
        end
        if p.meterDockShowButton ~= false then
        if not button then
            button = CreateFrame("Button", nil, UIParent)
            local bg = button:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.04, 0.04, 1)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetAllPoints()
            button:SetScript("OnClick", ns.ToggleMeterDock)
            button:SetScript("OnEnter", function(self)
                EUI.ShowWidgetTooltip(self, "Show / hide docked meters (overrides visibility until reload)")
            end)
            button:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
        end
        local x, y, w, h = bar:GetRect()
        if x and y and w and h then
            local scale = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
            button:ClearAllPoints()
            if p.meterDockButtonSide == "left" then
                button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x * scale, y * scale)
            else
                button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", (x + w) * scale, y * scale)
            end
            button:SetSize(math.max(16, h * scale), h * scale)
            button:SetFrameStrata(bar:GetFrameStrata())
            button:SetFrameLevel(bar:GetFrameLevel() + 20)
            button.text:SetText(p.meterDockShown == false and "+" or "-")
            button:SetShown(bar:IsShown())
        end
        elseif button then button:Hide() end
    elseif button then button:Hide() end
    local dm = Meters()
    if dm and dm._windows then
        for i = 1, 3 do
            local win = dm._windows[i]
            if win then
                if not ns.MeterDockState(i) and win.ApplyPosition then
                    win.frame:SetClampedToScreen(true)
                    win.ApplyPosition()
                end
                win.UpdateVisibility()
            end
        end
    end
    busy = false
end
function ns.SetMeterDock(id)
    local p = ns.GetProfile()
    local dm = Meters()
    if not p then return end
    if id and (not dm or not _EDM_Apply) then
        print("EllesmereUI: Enable Damage Meters, then reload before docking.")
        return
    end
    manualOverride = nil
    if id then p.meterDockSelectedBar = id end
    p.meterDockBar = id
    if id then
        p.meterDockShown = true
        local cfg = dm.EDM.DB()
        local count = p.meterDockCount == 1 and 1 or 2
        cfg.windowCount = math.max(count, cfg.windowCount or 1)
        cfg.windows = cfg.windows or {}
        for i = 1, count do cfg.windows[i] = cfg.windows[i] or {} end
        cfg.windows[1].curDMType = cfg.windows[1].curDMType or Enum.DamageMeterType.DamageDone
        if count == 2 then cfg.windows[2].curDMType = cfg.windows[2].curDMType or Enum.DamageMeterType.DamageDone end
        _EDM_Apply()
    else
        if _EDM_Apply then _EDM_Apply() end
    end
    ns.RefreshMeterDock()
end

function ns.SetDockMeterCount(value)
    local p = ns.GetProfile()
    if not p then return end
    p.meterDockCount = value == 1 and 1 or 2
    if p.meterDockBar then
        local shown = p.meterDockShown
        ns.SetMeterDock(p.meterDockBar)
        p.meterDockShown = shown
        ns.RefreshMeterDock()
    end
end
function ns.GetDockMeterType(idx)
    local dm = Meters()
    local cfg = dm and dm.EDM.DB()
    local win = cfg and cfg.windows and cfg.windows[idx]
    return win and win.curDMType or Enum.DamageMeterType.DamageDone
end
function ns.SetDockMeterType(idx, value)
    if idx ~= 1 and idx ~= 2 then return end
    local dm = Meters()
    if not dm then return end
    local cfg = dm.EDM.DB()
    cfg.windows = cfg.windows or {}
    cfg.windows[idx] = cfg.windows[idx] or {}
    cfg.windows[idx].curDMType = value
    local win = dm._windows and dm._windows[idx]
    if win and win.SetDMType then win.SetDMType(value) end
end

function ns.SetMeterDockEnabled(enabled)
    local p = ns.GetProfile()
    if not p then return end
    local id = p.meterDockBar or p.meterDockSelectedBar
    if enabled and not id then
        for _, bar in ipairs(ns.BarsInOrder()) do
            if bar.orientation ~= "V" then id = bar.id; break end
        end
    end
    ns.SetMeterDock(enabled and id or nil)
end
function ns.SelectDockBar(id)
    local p = ns.GetProfile()
    if not p then return end
    local enabled = p.meterDockBar ~= nil
    p.meterDockSelectedBar = id
    if enabled then ns.SetMeterDock(id) end
end
