-- EUI_ResourceBars_ThresholdSound.lua
-- Class Resource threshold alert sound: plays a cue on every gain while the
-- resource is at/above (or, in reverse mode, at/below) its configured
-- threshold -- not just the initial crossing.
--
-- Kept in its own file (mirrors EUI_ResourceBars_EbonMight121.lua) so the
-- main runtime file only needs a single call at each point it already
-- resolves `cur` and `useThresh` for a non-secret pip resource. All state
-- (previous value, throttle, login/zone settle window) lives here.
--
-- WoW has no discrete "resource gained a point" event -- UNIT_POWER_UPDATE /
-- UNIT_POWER_FREQUENT / UNIT_POWER_POINT_CHARGE only mean "power changed, go
-- re-read it", and already drive UpdateSecondaryResource. Comparing the
-- freshly-read value against the last-seen one is how a gain is told apart
-- from a loss or a same-value re-fire; the main file's Essence pip tracker
-- (_essenceLastCount) uses the same technique for gain/loss detection.
--
-- Secret values (WoW 12.0, instanced combat): callers only invoke this from
-- clean-value (non-secret) branches, so `cur` here is always a plain
-- comparable number.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

local _lastPlay = 0
local function PlaySoundKey(key)
    if not key or key == "none" then return end
    local paths = EllesmereUI.GetSoundCatalog()
    local path = paths[key]
    if not path then return end
    local now = GetTime()
    if (now - _lastPlay) < 0.3 then return end
    _lastPlay = now
    if EllesmereUI._PlayLSMSound then
        EllesmereUI._PlayLSMSound(path)
    else
        PlaySoundFile(path, "Master")
    end
end

-- Resynced (not fired) whenever the resolved config generation moves, so a
-- profile/spec/threshold edit never causes a spurious cue.
local _prevCur, _prevGen

-- Settle window after a loading screen: a zone-in that lands above the
-- threshold must not blare immediately.
local _settleUntil = 0
local settleFrame = CreateFrame("Frame")
settleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
settleFrame:SetScript("OnEvent", function()
    _settleUntil = GetTime() + 2
    _prevGen = nil
end)

-- entry:     resolved thresholdSpecs entry for the active spec (has
--            thresholdSoundEnabled / thresholdSoundKey), or nil when the
--            Threshold toggle itself is off
-- cur:       current resource count (already resolved by the caller; must
--            be a clean, comparable number -- never a secret value)
-- useThresh: the pre-multi-band threshold boolean the caller already
--            computed for this update
function ns.EvalThresholdSound(entry, cur, useThresh)
    if not entry or not entry.thresholdSoundEnabled then
        _prevCur = cur
        return
    end
    -- Sound is single-threshold only, mirroring the cog's own gating
    -- (Threshold Sound is greyed out while Multi-band coloring is on).
    if entry.multiBandEnabled then return end

    if ns.CfgGen ~= _prevGen then
        _prevGen = ns.CfgGen
        _prevCur = cur
        return
    end
    if GetTime() < _settleUntil then
        _prevCur = cur
        return
    end

    local gained = _prevCur ~= nil and cur > _prevCur
    _prevCur = cur
    if gained and useThresh then
        PlaySoundKey(entry.thresholdSoundKey)
    end
end
