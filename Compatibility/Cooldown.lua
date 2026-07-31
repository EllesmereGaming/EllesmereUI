-- Cooldown.lua

local function CooldownFrame_Set(cd, start, duration, enable)
    if not cd then return end
    start = start or 0
    duration = duration or 0
    local active = enable ~= 0 and start > 0 and duration > 0

    if active then
        -- SetCooldown already animates and completes the swipe in 3.3.5.
        -- Hiding/showing the frame around every call forced a render/layout
        -- update, and scheduling one Lua timer per GCD button produced large
        -- allocation bursts on ranged auto attacks.  Only push genuinely new
        -- timing data; the existing cooldown frame remains engine-driven.
        if cd._eabStart ~= start or cd._eabDuration ~= duration or not cd._eabActive then
            cd._eabStart = start
            cd._eabDuration = duration
            cd._eabActive = true
            cd:SetCooldown(start, duration)
            cd:Show()
        end
    else
        if cd._eabActive or cd:IsShown() then
            cd._eabStart = 0
            cd._eabDuration = 0
            cd._eabActive = false
            cd:SetCooldown(0, 0)
            cd:Hide()
        end
    end
end

-- Cooldown:Clear() is unavailable on 3.3.5. Keep callers cross-version and
-- allow this shim to be replaced by a library implementation if desired.
local function CooldownFrame_Clear(cd)
    if not cd then return end
    if cd.Clear then
        cd:Clear()
    else
        cd:SetCooldown(0, 0)
    end
end

_G.CooldownFrame_Set = CooldownFrame_Set
_G.CooldownFrame_SetTimer = CooldownFrame_Set
_G.CooldownFrame_Clear = CooldownFrame_Clear
