if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_BuffBarPresets.lua
--
--  Stacks, pandemic glow, the Blizzard bar font strings, icon spell ids and
--  the self-timed presets (Bloodlust, Time Spiral, potions).
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._buffBarInternals
-- EllesmereUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local GetTime = GetTime
local pcall = pcall

local _blizzBarFS, BBFS, StartGlow, StopGlow = I._blizzBarFS, I.BBFS, I.StartGlow, I.StopGlow
local _tbbWake, StableCooldownSpellID = I._tbbWake, I.StableCooldownSpellID
local _tbbAssignment, CfgWantsSID = I._tbbAssignment, I.CfgWantsSID

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local _tbbAssignDirty = true
I.assignDirtySetters[#I.assignDirtySetters + 1] = function(v) _tbbAssignDirty = v end

-------------------------------------------------------------------------------
--  Stacks Helper (reads Blizzard child Applications frame)
-------------------------------------------------------------------------------
-- Applications count for a Blizzard child, avoiding the aura-instance query where
-- possible: the child's auraDataCached table reads without erroring on every client,
-- its applications field is plain on live and secret under the 12.1 combat
-- restriction, and both feed StatusBar:SetValue/FontString:SetText natively. The
-- instance-id query is the fallback for an unpopulated cache and HARD-ERRORS on 12.1
-- restricted units, hence the pcall and the secret-iid guard.
local function ReadStackApplications(blzChild)
    local ad = blzChild.auraDataCached
    if ad and ad.applications then return ad.applications end
    local auraInstID = blzChild.auraInstanceID
    local auraUnit = blzChild.auraDataUnit
    if auraInstID and auraUnit and not issecretvalue(auraInstID) then
        local ok, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, auraUnit, auraInstID)
        if ok and d and d.applications then return d.applications end
    end
    return nil
end

local function UpdateStacks(bar, blzChild, cfg)
    -- Stack-based fill needs a live count even when Blizzard renders no Applications text
    -- (hidden at 1 stack), plus a restricted marker so the fill site fails open instead of an empty bar.
    local stackFill = cfg and cfg.stackBasedBar and cfg.trackType ~= "cooldown"
        and cfg.stackThresholdMaxEnabled
    bar._stackUnreadable = nil
    if stackFill and blzChild then
        -- Stack-based bar: skip the Blizzard text mirror (blank below 2 stacks) and drive
        -- fill/text from the aura data. This helper only runs for active frames, so the aura is
        -- up and a readable count floors at 1; a secret count passes through to SetValue/SetText untouched.
        local apps = ReadStackApplications(blzChild)
        if apps then
            if not issecretvalue(apps) and apps < 1 then apps = 1 end
            bar._stackCount = apps
            if bar._stacksText then
                if bar._stacksHidden then
                    bar._stacksText:Hide()
                else
                    bar._stacksText:SetText(apps)
                    bar._stacksText:Show()
                end
            end
        else
            -- No cached aura table and no readable instance id: count is unknowable, so the fill site fails open.
            bar._stackCount = 0
            bar._stackUnreadable = true
            if bar._stacksText then bar._stacksText:Hide() end
        end
        return
    end
    -- Read stacks from blzChild.Icon.Applications FontString.
    if blzChild and blzChild.Icon and blzChild.Icon.Applications then
        -- NEVER compare the text (it may be secret); SetText takes it natively.
        local ok, txt = pcall(blzChild.Icon.Applications.GetText, blzChild.Icon.Applications)
        if ok and txt then
            -- _stacksHidden (Stacks Position: None) gates every writer lane:
            -- this helper runs for EVERY active bar once ANY bar wants stacks
            -- (_anyStacks is a global gate), so an unguarded show here painted
            -- stacks onto bars that disabled them.
            if bar._stacksText and not bar._stacksHidden then
                bar._stacksText:SetText(txt)
                bar._stacksText:Show()
            elseif bar._stacksText then
                bar._stacksText:Hide()
            end
            -- Stack count for the threshold overlay: applications can be a secret number we
            -- cannot compare, but the overlay consumes it via SetValue (FeedTBBThresholdOverlay), which accepts secrets.
            bar._stackCount = ReadStackApplications(blzChild) or 0
            return
        end
    end
    -- Fallback: top-level Applications (BuffIcon children)
    if blzChild and blzChild.Applications and blzChild.Applications:IsShown() then
        local appsText = blzChild.Applications.Applications
        if appsText then
            local ok, txt = pcall(appsText.GetText, appsText)
            if ok and txt and (issecretvalue(txt) or txt ~= "") then
                if bar._stacksText and not bar._stacksHidden then
                    bar._stacksText:SetText(txt)
                    bar._stacksText:Show()
                end
                bar._stackCount = ReadStackApplications(blzChild) or 0
                return
            end
        end
    end
    -- No stacks text
    if bar._stacksText then bar._stacksText:Hide() end
    bar._stackCount = 0
end

-------------------------------------------------------------------------------
--  Pandemic Glow Helpers
-------------------------------------------------------------------------------
local function ClearPandemic(bar)
    if bar._pandemicGlowTarget then StopGlow(bar._pandemicGlowTarget) end
    bar._pandemicGlowActive   = false
    bar._pandemicGlowStyleIdx = nil
    bar._pandemicGlowTarget   = nil
end

--- Start or update the pandemic glow on a bar. Caller checks the threshold and drives alpha from the tick (smooth fade on remaining%).
local function UpdatePandemic(bar, cfg)
    -- Glow always wraps the whole bar: the overlay covers the entire wrapFrame footprint, so an enabled icon is included rather than glowed alone.
    local glowTarget = bar._pandemicGlowOverlay

    -- Bar rectangle: Pixel Glow or Auto-Cast Shine only (texture styles stretch);
    -- any other stored style, and Blizzard Default (-1), render as Pixel Glow.
    local style = ns.PG_TbbEffectiveStyle(cfg)

    -- Start/restart glow on style or target change
    if not bar._pandemicGlowActive or bar._pandemicGlowStyleIdx ~= style
       or bar._pandemicGlowTarget ~= glowTarget then
        if bar._pandemicGlowActive and bar._pandemicGlowTarget
           and bar._pandemicGlowTarget ~= glowTarget then
            StopGlow(bar._pandemicGlowTarget)
        end
        local c
        if cfg.pandemicGlowMode == "class" then
            c = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
        elseif cfg.pandemicGlowMode == "custom" then
            c = cfg.pandemicGlowColor
        end
        local glowOpts = (style == 1) and {
            N      = cfg.pandemicGlowLines or 8,
            th     = cfg.pandemicGlowThickness or 2,
            period = cfg.pandemicGlowSpeed or 4,
            bg     = cfg.pandemicGlowBackground and {
                r = (cfg.pandemicGlowBackgroundColor and cfg.pandemicGlowBackgroundColor.r) or 0,
                g = (cfg.pandemicGlowBackgroundColor and cfg.pandemicGlowBackgroundColor.g) or 0,
                b = (cfg.pandemicGlowBackgroundColor and cfg.pandemicGlowBackgroundColor.b) or 0,
            } or nil,
        } or nil
        StartGlow(glowTarget, style, c and c.r, c and c.g, c and c.b, glowOpts)
        bar._pandemicGlowActive   = true
        bar._pandemicGlowStyleIdx = style
        bar._pandemicGlowTarget   = glowTarget
    end

end

-------------------------------------------------------------------------------
--  Blizzard Bar FontString Discovery: finds the name/timer FontStrings on a Blizzard
--  Bar StatusBar and caches the refs externally (zero alloc after the first call).
-------------------------------------------------------------------------------
local function GetBlizzBarFontStrings(blizzBar)
    if not blizzBar then return nil, nil end
    local cached = _blizzBarFS[blizzBar]
    if cached and cached.nameFS then
        return cached.nameFS, cached.timerFS
    end
    -- Discover by iterating regions. The StatusBar has exactly 2 FontStrings: 1st = spell name, 2nd = timer text.
    local nameFS, timerFS
    local fsIdx = 0
    for _, rgn in pairs({ blizzBar:GetRegions() }) do
        if rgn:GetObjectType() == "FontString" then
            fsIdx = fsIdx + 1
            if fsIdx == 1 then nameFS = rgn end
            if fsIdx == 2 then timerFS = rgn end
        end
    end
    -- External cache (false = "searched, not found"), never on the Blizzard frame
    local d = BBFS(blizzBar)
    d.nameFS  = nameFS or false
    d.timerFS = timerFS or false
    return nameFS, timerFS
end

-------------------------------------------------------------------------------
--  EffectiveIconSpellID
--  Which spell id's ICON represents a config right now. cfg.spellID is the pick-time
--  form; talents can override it to a different form with a different icon
--  (C_Spell.GetOverrideSpell), and a bar saved for an override form loses that form
--  when untalented (only its base stays known). Icon FALLBACK paths only -- a bound
--  Blizzard frame or live aura data wins when available.
-------------------------------------------------------------------------------
local function EffectiveIconSpellID(cfg)
    local sid = cfg.spellID
    if not sid or sid <= 0 then return nil end
    -- Saved form currently overridden by a talent: show the override's icon.
    if C_Spell and C_Spell.GetOverrideSpell then
        local ov = C_Spell.GetOverrideSpell(sid)
        if type(ov) == "number" and ov > 0 and ov ~= sid then return ov end
    end
    -- Saved the override form, now untalented: the saved form is no longer known but its captured base is, so show the base form's icon.
    if cfg.baseSpellID and cfg.baseSpellID > 0 and IsPlayerSpell
       and not IsPlayerSpell(sid) and IsPlayerSpell(cfg.baseSpellID) then
        return cfg.baseSpellID
    end
    return sid
end

-- Cooldown-bar spell resolution. Charge Hash Lines needs a STABLE identity (segment math
-- breaks if the tracked id flips to a proc override mid-recharge), so bars with that toggle
-- resolve via StableCooldownSpellID; every other cooldown bar follows overrides via EffectiveIconSpellID.
local function CooldownBarSpellID(cfg)
    if cfg and cfg.chargeHashLines == true then
        return StableCooldownSpellID(cfg)
    end
    return EffectiveIconSpellID(cfg)
end

-- Mirror the 12.1 engine-written decimal timer string (hidden FS on the aura slot
-- button; see EllesmereUICdmTbbDecimals.lua) onto the bar's timer FS. SECRET RULES:
-- the slot button's IsShown() is a SECRET BOOLEAN (aura presence) -- never test it in
-- Lua, route through engine-side SetAlphaFromBoolean (present->1, gone->0) so a stale
-- string can never be visible on a filter miss. The engine string may itself be
-- secret: nil-check via type tag only, SetText accepts secret strings. Returns true
-- only when a string was written AND the alpha gate applied (failure degrades
-- precision, never accuracy); bar._tbbAlphaGated tracks the gate so the fallback
-- path never inherits a stuck alpha-0 FS.
local function MirrorEngineTimer(bar, cfg)
    local engBtn = bar._tbbEngineText
    if not engBtn then return false end
    local out = bar._timerText
    local engFS = bar._tbbEngineFS
    local wrote = false
    if cfg.showTimer and out and engFS then
        local ok, txt = pcall(engFS.GetText, engFS)
        if ok and type(txt) ~= "nil" then
            wrote = (pcall(out.SetText, out, txt))
        end
    end
    -- Alpha gate is best-effort: every call site has already established aura presence
    -- (viewer isActive/a live aura read), so a missing setter must not disable the mirror itself.
    if wrote and out.SetAlphaFromBoolean then
        pcall(out.SetAlphaFromBoolean, out, engBtn:IsShown(), 1, 0)
        bar._tbbAlphaGated = true
    elseif bar._tbbAlphaGated then
        if out then out:SetAlpha(1) end
        bar._tbbAlphaGated = nil
    end
    return wrote
end

-------------------------------------------------------------------------------
--  Bloodlust / Heroism duration bar (debuff-driven, self-timed)
--  The lust buff is cast by others and is secret, so it can't be mirrored from a
--  Blizzard buff-bar child. Watch ONLY the player's Sated/Exhaustion debuff
--  (player-only UNIT_AURA, NEVER a global scan) and start a 40s bar on its rising
--  edge. No login/reload reconstruction: reloading mid-lust gives no bar (debuff
--  was not just acquired). Matching preset: popularKey == "bloodlust".
-------------------------------------------------------------------------------
local SATED_DEBUFFS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435 }
local _lustExpiry   = 0
local _satedPresent = false
local _satedSince                 -- GetTime() of the rise this listener armed on (nil = unknown age)
local _lustZoneGuard = 0          -- suppress rising edges until this time (set on zone-in)
local _lustListenerActive = false -- baseline _satedPresent only on (re)enable, not every rebuild
local _lustListener

local function _playerHasSated()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    for i = 1, #SATED_DEBUFFS do
        -- Querying a KNOWN spellID returns the aura even when its fields are secret in
        -- combat, so the edge is detected mid-fight; the (possibly secret) spellID is never read back.
        if C_UnitAuras.GetPlayerAuraBySpellID(SATED_DEBUFFS[i]) then return true end
    end
    return false
end

-- Toggle the player-only Sated listener. Registered only while a lust bar exists; baselines _satedPresent on enable so it fires only on NEW edges.
local function _ensureLustListener(enable)
    if enable then
        if not _lustListener then
            _lustListener = ns.TakeShell()
            _lustListener:SetScript("OnEvent", function(_, event, _, updateInfo)
                if event == "PLAYER_ENTERING_WORLD" then
                    -- Zone/login aura refresh: re-baseline WITHOUT arming and suppress edges
                    -- briefly. An already-carried Sated debuff (zoning out of a dungeon) must
                    -- never read as a fresh cast and pop a phantom 40s bar in the open world.
                    _satedPresent = _playerHasSated()
                    _satedSince = nil
                    _lustZoneGuard = GetTime() + 1.5
                    return
                end
                if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
                    -- Death strips the lockout debuff, so the 590s pin below has to be
                    -- released here: a wipe followed by a fresh lust would otherwise be
                    -- swallowed for the rest of the window the pin was stamped for.
                    _satedPresent = _playerHasSated()
                    _satedSince = nil
                    return
                end
                -- Nothing but death lifts the lockout early (handled above), so a rise
                -- this listener armed on pins the debuff for the next 590s: skip the
                -- (allocating) aura probe until it can possibly have dropped.
                if _satedPresent and _satedSince and GetTime() < _satedSince + 590 then return end
                local present = _playerHasSated()
                -- Arm ONLY on a genuine incremental application: not a full
                -- aura refresh (zone/login resends every aura), and not inside
                -- the post-zone grace window. The UNIT_AURA payload and its
                -- fields can be SECRET in combat, and boolean use of a secret
                -- errors, so a secret payload is treated as incremental (full
                -- refreshes come from zone/login, covered by the zone guard).
                local isFull = false
                if updateInfo and not issecretvalue(updateInfo) then
                    local v = updateInfo.isFullUpdate
                    if not issecretvalue(v) and v then isFull = true end
                end
                if present and not _satedPresent and not isFull
                    and GetTime() >= _lustZoneGuard then
                    _lustExpiry = GetTime() + 40  -- rising edge: lust just went out
                    ns.TBBPresetSoundEdge("bloodlust", true, _lustExpiry)
                    _satedSince = GetTime()
                    _tbbWake.Wake()  -- lust can come from other players: no local cast/aura edge is guaranteed
                    -- Drive Custom Auras (icon) lust displays sharing this edge.
                    if ns.SignalLustCast then ns.SignalLustCast() end
                end
                _satedPresent = present
                if not present then _satedSince = nil end
            end)
        end
        -- Baseline ONLY on the OFF->ON transition. Re-baselining on every BuildTrackedBuffBars
        -- (fires during zone changes, sometimes while the aura table is momentarily empty)
        -- could set _satedPresent=false and make the debuff's return look like a cast.
        if not _lustListenerActive then
            _satedPresent = _playerHasSated()
            _satedSince = nil
            _lustListener:RegisterUnitEvent("UNIT_AURA", "player")
            _lustListener:RegisterEvent("PLAYER_ENTERING_WORLD")
            _lustListener:RegisterEvent("PLAYER_DEAD")
            _lustListener:RegisterEvent("PLAYER_ALIVE")
            _lustListenerActive = true
        end
    elseif _lustListener and _lustListenerActive then
        _lustListener:UnregisterAllEvents()
        _lustListenerActive = false
    end
end

-- Arm the shared Sated listener if EITHER a Tracking Bar lust bar OR a Custom Auras (icon)
-- lust display is enabled. Authoritative (scans the DB), safe to call from any rebuild/toggle path.
function ns.UpdateLustListener()
    local any = false
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, cfg in ipairs(tbb.bars) do
            if cfg.enabled ~= false and cfg.popularKey == "bloodlust" then any = true; break end
        end
    end
    if not any and ns.AnyCustomAuraLust then any = ns.AnyCustomAuraLust() end
    -- WoW Forever has no raid lust and no Sated debuff: a lust bar or icon saved
    -- on another client stays dormant there and never arms the listener.
    if EllesmereUI.IS_FOREVER then any = false end
    _ensureLustListener(any)
    -- Sibling preset listeners refresh from the same change sites: every add/remove/rebuild path already calls UpdateLustListener.
    if ns.UpdateTimeSpiralListener then ns.UpdateTimeSpiralListener() end
    if ns.UpdatePotionCastListener then ns.UpdatePotionCastListener() end
    if ns.UpdateCooldownCastListener then ns.UpdateCooldownCastListener() end
    if ns.UpdateSealListener then ns.UpdateSealListener() end  -- Paladin Seals (EUI_CDM_Seals.lua, WoW Forever)
end

-- Profile-wide smooth-fill switches (Bar Layout > Smooth Bars), resolved ONCE per tick by
-- UpdateTrackedBuffBarTimers for every fill site. buffs = buff mirrors + self-timed
-- presets (lust/time spiral/potions); cooldowns = trackType=="cooldown" bars; off = values
-- snap (no easing). Defaults: buffs ON, cooldowns OFF (absent keys read that way).
-- Fields on _tbbWake: the fill sites sit in three files and the tick writes both every pass.
_tbbWake._smoothBuffs, _tbbWake._smoothCooldowns = true, false

-- Self-driven display for an event-armed, self-timed preset bar (Bloodlust 40s, Time Spiral
-- 10s): fill+timer come from our own countdown, not a Blizzard frame (name/icon are set in
-- BuildTrackedBuffBars). `expiry` = GetTime() the window ends at; `duration` = full window length.
local function _UpdateSelfTimedBar(bar, cfg, expiry, duration)
    local remaining = expiry - GetTime()
    if remaining <= 0 then
        -- The loss cue comes from the preset's latch in the tick, shown or not.
        if bar:IsShown() then bar:Hide() end
        return
    end
    local wasShown = bar:IsShown()
    if not wasShown then bar:Show() end
    local sb = bar._bar
    if sb then
        sb:SetMinMaxValues(0, duration)
        -- Smooth fill is baseline for tracking bars: they move one direction at a known rate
        -- (unlike a health bar, no sudden jump needs instant read), so interpolation only
        -- removes judder. The wasShown gate snaps a fresh appearance instead of animating from a stale value.
        local smooth = _tbbWake._smoothBuffs and wasShown and Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
        if smooth then
            sb:SetValue(remaining, smooth)
        else
            sb:SetValue(remaining)
        end
        if cfg.showSpark and bar._spark then bar._spark:Show() end
    end
    if cfg.showTimer and bar._timerText then
        -- The string changes only when its displayed bucket does (rounded tenths
        -- under 10s, whole seconds above), so stamp the bucket and skip the
        -- per-tick format + SetText otherwise. A fresh appearance always writes
        -- (wasShown false) and the placeholder exit clears the stamp, so no other
        -- writer of this FontString can strand it.
        local key
        if remaining < 10 then
            key = math.floor(remaining * 10 + 0.5)
        else
            key = math.floor(remaining)
        end
        if not wasShown or bar._stTxtKey ~= key then
            bar._stTxtKey = key
            if remaining < 10 then
                bar._timerText:SetText(string.format("%.1f", remaining))
            else
                bar._timerText:SetText(string.format("%d", remaining))
            end
        end
        bar._timerText:Show()
    elseif bar._timerText then
        bar._timerText:Hide()
    end
    return true  -- window active: keep the tick awake
end
local function UpdateLustBar(bar, cfg)
    return _UpdateSelfTimedBar(bar, cfg, _lustExpiry, 40)
end

-------------------------------------------------------------------------------
--  Time Spiral "Free Move" preset (popularKey == "timespiral")
--  Mirrors Bloodlust, but armed off Blizzard's spell-activation glow on the player's
--  class movement ability (free-cast proc) instead of an aura: a whitelisted
--  glow-SHOW starts a self-timed 10s window; like Bloodlust, only a fresh glow arms
--  it, no login/reload reconstruction. Talent-aware suppression drops glows firing on
--  a movement ability for unrelated reasons (DH Inertia/Dash of Chaos, Warlock Soulburn).
-------------------------------------------------------------------------------
local TIME_SPIRAL_DURATION = 10
-- Per-class movement abilities that glow when Time Spiral grants a free cast.
local TIME_SPIRAL_TRIGGERS = {
    [48265] = true,   -- Death's Advance
    [195072] = true,  -- Fel Rush
    [189110] = true,  -- Infernal Strike
    [1850] = true,    -- Dash
    [252216] = true,  -- Tiger Dash
    [358267] = true,  -- Hover
    [186257] = true,  -- Aspect of the Cheetah
    [1953] = true,    -- Blink
    [212653] = true,  -- Shimmer
    [361138] = true,  -- Roll
    [119085] = true,  -- Chi Torpedo
    [190784] = true,  -- Divine Steed
    [73325] = true,   -- Leap of Faith
    [2983] = true,    -- Sprint
    [192063] = true,  -- Gust of Wind
    [58875] = true,   -- Spirit Walk
    [79206] = true,   -- Spiritwalker's Grace
    [48020] = true,   -- Demonic Circle: Teleport
    [6544] = true,    -- Heroic Leap
}
-- Talent-gated abilities that ALSO glow a movement ability for reasons unrelated to the proc.
-- While the talent is known, casting one suppresses the glow that follows for a short window.
local TIME_SPIRAL_GLOW_FILTERS = {
    { talent = 427640, spells = { 198793, 370965, 195072 } },  -- DH Inertia
    { talent = 427794, spells = { 195072 } },                  -- DH Dash of Chaos
    { talent = 385899, spells = { 385899 } },                  -- Warlock Soulburn
}
-- State grouped in one table.
local _ts = { expiry = 0, suppressUntil = 0, suppress = {}, active = false, frame = nil }

local function _rebuildTimeSpiralSuppress()
    wipe(_ts.suppress)
    local known = C_SpellBook and C_SpellBook.IsSpellKnown
    if not known then return end
    for _, e in ipairs(TIME_SPIRAL_GLOW_FILTERS) do
        if known(e.talent) then
            for _, sid in ipairs(e.spells) do _ts.suppress[sid] = true end
        end
    end
end

-- Toggle the glow listener; registered only while an enabled Time Spiral bar or Custom Auras (icon) display exists. Glow-event spellIDs are never secret.
local function _ensureTimeSpiralListener(enable)
    if enable then
        if not _ts.frame then
            _ts.frame = ns.TakeShell()
            _ts.frame:SetScript("OnEvent", function(_, event, ...)
                if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                    local sid = ...
                    if not TIME_SPIRAL_TRIGGERS[sid] then return end
                    if GetTime() < _ts.suppressUntil then return end
                    _ts.expiry = GetTime() + TIME_SPIRAL_DURATION  -- free move just granted
                    ns.TBBPresetSoundEdge("timespiral", true, _ts.expiry)
                    _tbbWake.Wake()  -- glow edge is outside the sleeper's wake events
                    -- Drive Custom Auras (icon) displays sharing this edge.
                    if ns.SignalTimeSpiralCast then ns.SignalTimeSpiralCast() end
                elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
                    local sid = ...
                    if not TIME_SPIRAL_TRIGGERS[sid] then return end
                    -- Proc consumed or expired: end the window now so bar/icon disappear with
                    -- the glow rather than riding out the full 10s. Guarded on an active window
                    -- so an unrelated trigger's hide cannot fire spuriously.
                    if _ts.expiry > GetTime() then
                        _ts.expiry = 0
                        ns.TBBPresetSoundEdge("timespiral", false)
                        if ns.SignalTimeSpiralEnd then ns.SignalTimeSpiralEnd() end
                    end
                elseif event == "UNIT_SPELLCAST_SENT" then
                    -- (unit, target, castGUID, spellID); arg4 is the spellID.
                    local _, _, _, sid = ...
                    if sid and _ts.suppress[sid] then
                        _ts.suppressUntil = GetTime() + 1.5
                    end
                elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_ENTERING_WORLD" then
                    _rebuildTimeSpiralSuppress()
                end
            end)
        end
        if not _ts.active then
            _rebuildTimeSpiralSuppress()
            _ts.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            _ts.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            _ts.frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
            _ts.frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
            _ts.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            _ts.active = true
        end
    elseif _ts.frame and _ts.active then
        _ts.frame:UnregisterAllEvents()
        _ts.active = false
    end
end

-- Arm the glow listener if EITHER a Time Spiral Tracking Bar OR a Custom Auras (icon) Time Spiral display is enabled. Authoritative (scans the DB).
function ns.UpdateTimeSpiralListener()
    local any = false
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, cfg in ipairs(tbb.bars) do
            if cfg.enabled ~= false and cfg.popularKey == "timespiral" then any = true; break end
        end
    end
    if not any and ns.AnyCustomAuraTimeSpiral then any = ns.AnyCustomAuraTimeSpiral() end
    -- WoW Forever has no Time Spiral: a bar or icon saved on another client stays
    -- dormant there and never arms the glow listener.
    if EllesmereUI.IS_FOREVER then any = false end
    _ensureTimeSpiralListener(any)
end

-------------------------------------------------------------------------------
--  Self-cast potion presets (Light's Potential, Potion of Recklessness, Invisibility
--  Potion). NEVER aura-tracked: a hardcoded window starts the moment the potion's
--  spell is cast, matching the CDM buff-bar/Fake-Active potions. Same self-timed model
--  as Bloodlust/Time Spiral -- only a fresh cast arms it, so a reload mid-buff shows
--  nothing until next use. Built from BUFF_BAR_PRESETS: every non-tbbOnly preset
--  (bloodlust/timespiral are tbbOnly, event-driven above) is cast-timed.
-------------------------------------------------------------------------------
local _potionDur = {}       -- [popularKey] = hardcoded window seconds
local _potionTrigger = {}   -- [castSpellID] = popularKey
do
    local presets = ns.BUFF_BAR_PRESETS
    if presets then
        for _, p in ipairs(presets) do
            if not p.tbbOnly and p.spellIDs and p.duration then
                _potionDur[p.key] = p.duration
                for _, sid in ipairs(p.spellIDs) do
                    if type(sid) == "number" and sid > 0 then _potionTrigger[sid] = p.key end
                end
            end
        end
    end
end
local _potionExpiry = {}    -- [popularKey] = GetTime() the window ends at
local _potionFrame
local _potionActive = false

local function _ensurePotionCastListener(enable)
    if enable then
        if not _potionFrame then
            _potionFrame = ns.TakeShell()
            -- UNIT_SPELLCAST_SUCCEEDED (player): same edge the CDM buff-bar potions fire on. arg4 = cast spellID (never secret).
            _potionFrame:SetScript("OnEvent", function(_, _, _, _, spellID)
                local key = spellID and _potionTrigger[spellID]
                if not key then return end
                _potionExpiry[key] = GetTime() + (_potionDur[key] or 30)
                ns.TBBPresetSoundEdge(key, true, _potionExpiry[key])
            end)
        end
        if not _potionActive then
            _potionFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            _potionActive = true
        end
    elseif _potionFrame and _potionActive then
        _potionFrame:UnregisterAllEvents()
        _potionActive = false
    end
end

-- Arm the cast listener only while an enabled potion-preset Tracking Bar exists. Refreshed
-- from the same change sites as the other preset listeners (fanned out from UpdateLustListener).
function ns.UpdatePotionCastListener()
    local any = false
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, cfg in ipairs(tbb.bars) do
            if cfg.enabled ~= false and cfg.popularKey and _potionDur[cfg.popularKey] then
                any = true; break
            end
        end
    end
    _ensurePotionCastListener(any)
end

-- Can a sound set on this tracking bar ever play? Options-side predicate:
-- cheap, allocation-free, secret-safe. Cooldown-tracking bars never cue. A
-- preset cues from its own window, so only the self-timed ones count. Any
-- other bar cues only through a Blizzard buff viewer's aura alert, so its
-- spell has to be in the Tracked Bars or Tracked Buffs viewer: the bar's
-- current pairing, or a live frame of either viewer whose spell the bar
-- wants (the id match the alert path uses).
function ns.TBB_BarCanCue(cfg)
    if type(cfg) ~= "table" or cfg.trackType == "cooldown" then return false end
    local pk = cfg.popularKey
    if pk then
        -- The lust and Time Spiral windows never open on WoW Forever (their
        -- listeners stay off there), so only a cast-timed preset can cue.
        if EllesmereUI.IS_FOREVER then return _potionDur[pk] ~= nil end
        return pk == "bloodlust" or pk == "timespiral" or _potionDur[pk] ~= nil
    end
    -- A dirty map still holds the previous pass's pairings: trust it only once rebuilt,
    -- and only while Tracking Bars are on (the tick is the only thing that keeps it current).
    if _tbbWake._enabled and not _tbbAssignDirty and _tbbAssignment[cfg] then return true end
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    if not GetCanonical then return false end
    for vi = 1, 2 do
        local viewer
        if vi == 1 then viewer = _G.BuffBarCooldownViewer else viewer = _G.BuffIconCooldownViewer end
        local pool = viewer and viewer.itemFramePool
        if pool then
            for frame in pool:EnumerateActive() do
                if CfgWantsSID(cfg, GetCanonical(frame)) then return true end
            end
        end
    end
    return false
end

-- True when v is a plain, readable number. A secret value fails BEFORE any type/comparison touches it; nil and non-numbers fail too.
local function _tbbCleanNum(v)
    if issecretvalue and issecretvalue(v) then return false end
    return type(v) == "number"
end

I._potionDur, I._potionExpiry, I._tbbCleanNum = _potionDur, _potionExpiry, _tbbCleanNum
I._ts, I._UpdateSelfTimedBar, I.ClearPandemic = _ts, _UpdateSelfTimedBar, ClearPandemic
I.CooldownBarSpellID, I.EffectiveIconSpellID = CooldownBarSpellID, EffectiveIconSpellID
I.GetBlizzBarFontStrings, I.MirrorEngineTimer = GetBlizzBarFontStrings, MirrorEngineTimer
I.TIME_SPIRAL_DURATION, I.UpdateLustBar = TIME_SPIRAL_DURATION, UpdateLustBar
I.UpdatePandemic, I.UpdateStacks = UpdatePandemic, UpdateStacks
I.broken = false
