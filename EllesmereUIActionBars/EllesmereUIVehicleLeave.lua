-- VehicleLeave.lua -- vehicle exit button: movable + resizable via Unlock Mode,
-- reusing the original Blizzard art cropped square with a 1px border. Kept in its
-- own file so its locals don't count against the main chunk's 200-local budget.
-- Taint-safe: only methods are called on the secure button (no field writes).
local EAB = EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
local btn = MainMenuBarVehicleLeaveButton
if not (EAB and btn) then return end

local KEY, CROP, MIN, MAX = "VehicleLeave", 0.2, 0.5, 3.0
local DEFAULT = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 180 }
local native = btn:GetWidth(); if not native or native <= 0 then native = 36 end
local bordered, unlockShow

local function db()   return EAB.db and EAB.db.profile end
local function size() local p = db(); return (p and p.vehicleLeaveSize) or native end

-- Apply position, size and restyle (all guarded out of combat).
local function apply()
    if InCombatLockdown() then return end
    local p = db()
    local pos = (p and p.barPositions and p.barPositions[KEY]) or DEFAULT
    btn:ClearAllPoints()
    btn:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    pcall(btn.SetSize, btn, size(), size())
    for _, t in ipairs({ btn:GetNormalTexture(), btn:GetPushedTexture() }) do
        if t then pcall(function() t:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP); t:SetAllPoints(btn) end) end
    end
    if not bordered and EllesmereUI.PP and EllesmereUI.PP.CreateBorder then
        pcall(EllesmereUI.PP.CreateBorder, btn, 0, 0, 0, 1, 1, "OVERLAY", 1); bordered = true
    end
end

local function setSize(v)
    v = tonumber(v); local p = db(); if not (v and p) then return end
    p.vehicleLeaveSize = math.max(native * MIN, math.min(native * MAX, v))
    if not InCombatLockdown() then pcall(btn.SetSize, btn, size(), size()) end
end

-- Force-show while unlocking (so it can be dragged off-vehicle); else restore
-- the main file's Blizzard-owned visibility.
local function show(force)
    unlockShow = force
    if force then btn:Show(); return end
    if not (InCombatLockdown() and EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance()) then
        btn:SetShown((CanExitVehicle and CanExitVehicle()) or false)
    end
    apply()
end

local function register()
    local MK = EllesmereUI.MakeUnlockElement
    if not (MK and EllesmereUI.RegisterUnlockElements) then return end
    EllesmereUI:RegisterUnlockElements({ MK({
        key = KEY, label = "Vehicle Exit Button", group = "Action Bars", order = 280,
        linkedDimensions = true,
        getFrame  = function() return btn end,
        getSize   = function() return size(), size() end,
        setWidth  = function(_, w) setSize(w) end,
        setHeight = function(_, h) setSize(h) end,
        savePos = function(_, point, relPoint, x, y)
            local p = db()
            if p and point then p.barPositions[KEY] = { point = point, relPoint = relPoint or point, x = x, y = y } end
            if not EllesmereUI._unlockActive then apply() end
        end,
        loadPos = function()
            local p = db(); local s = p and p.barPositions and p.barPositions[KEY]
            return s and { point = s.point, relPoint = s.relPoint or s.point, x = s.x, y = s.y } or nil
        end,
        clearPos = function() local p = db(); if p then p.barPositions[KEY] = nil end end,
        applyPos = apply,
    }) }, "EllesmereUIActionBars")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("UNIT_ENTERED_VEHICLE")
f:SetScript("OnEvent", function(_, e, unit)
    if e == "PLAYER_LOGIN" then
        register()
        if _G._EAB_UnlockModeOpen then   -- post-hook the main file's unlock notifiers
            hooksecurefunc("_EAB_UnlockModeOpen",  function() show(true) end)
            hooksecurefunc("_EAB_UnlockModeClose", function() show(false) end)
        end
    elseif e == "UNIT_ENTERED_VEHICLE" then
        if unit == "player" and C_Timer then C_Timer.After(0.05, apply) end  -- Blizzard reset the art
    elseif C_Timer then
        C_Timer.After(0.3, apply)   -- after setup / after combat
    else
        apply()
    end
end)
