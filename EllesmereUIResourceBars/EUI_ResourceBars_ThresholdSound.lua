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

-------------------------------------------------------------------------------
-- Per-band alert sound (multi-band coloring): plays a distinct cue as the
-- resource crosses into a HIGHER band on a gain -- same "gain, not every
-- tick" spirit as EvalThresholdSound above, but keyed on which band matches
-- instead of the raw count.
--
-- Rank, not raw count: bands[i] holds { to, r, g, b, a, soundKey }, sorted
-- ascending by `to`. FindCountBand's matched index moves monotonically with
-- `cur` in BOTH directions (forward scan for "Up to", backward scan for
-- "From"), so tracking "which index matched" and firing when it INCREASES is
-- a correct, direction-agnostic gain signal. A raw _prevCur comparison can't
-- do this cleanly: FindCountBand returns nil on both sides of the band list,
-- and nil means something different per direction (above the top band for
-- "Up to", below the first band for "From") -- BandRank folds both cases into
-- a single monotonic 0..#bands+1 scale so "rank increased" always means "cur
-- moved toward the more severe end", regardless of direction.
-------------------------------------------------------------------------------
local function BandRank(bands, cur, reverse)
    if not bands or #bands == 0 then return 0 end
    local band = ns.FindCountBand and ns.FindCountBand(bands, cur, reverse)
    if not band then
        -- "Up to": no match = above every band (most severe, no sound to
        -- play there -- nothing configured past the last band). "From": no
        -- match = below every band (least severe, baseline).
        return reverse and 0 or (#bands + 1)
    end
    for i = 1, #bands do
        if bands[i] == band then return i end
    end
    return 0
end

local _prevRank
-- Own generation tracker, NOT shared with EvalThresholdSound's _prevGen: the
-- two are called back-to-back at every wiring site (threshold unconditionally,
-- then band inside "if band mode on"). If they shared _prevGen, whichever
-- runs first on the tick ns.CfgGen changes would consume the resync, and the
-- other would compare against a stale baseline from before the edit instead
-- of resyncing -- silently breaking the "no spurious cue after a
-- profile/spec/threshold edit" guarantee for whichever call comes second.
local _prevGenBand

-- bands:  the resolved band array for the active entry (already includes the
--         sp.bands fallback the caller applied via ResolveBandConfig). The
--         caller only invokes this from inside its own "band mode is on"
--         branch (_tsBandOn/bandOn), so there is no separate enabled flag to
--         re-check here -- unlike EvalThresholdSound's `entry`, which the
--         caller passes unconditionally every tick and which can legitimately
--         be nil (single threshold off) while band mode is independently on.
-- cur:    current resource count -- same clean-value contract as
--         EvalThresholdSound; never call this with a possibly-secret value
-- reverse: the resolved band direction ("Up to"/false vs "From"/true)
function ns.EvalBandSound(bands, cur, reverse)
    if not bands or #bands == 0 then
        _prevRank = nil
        return
    end
    if ns.CfgGen ~= _prevGenBand then
        _prevGenBand = ns.CfgGen
        _prevRank = BandRank(bands, cur, reverse)
        return
    end
    if GetTime() < _settleUntil then
        _prevRank = BandRank(bands, cur, reverse)
        return
    end

    local rank = BandRank(bands, cur, reverse)
    local prevRank = _prevRank
    _prevRank = rank
    -- prevRank can still be nil on the very first call of a session (no
    -- resync branch has run yet) -- just establish the baseline, no cue,
    -- mirroring EvalThresholdSound's own resync-then-observe behavior.
    if prevRank == nil then return end
    if rank > prevRank and rank >= 1 and rank <= #bands then
        local band = bands[rank]
        if band and band.soundKey then PlaySoundKey(band.soundKey) end
    end
end
