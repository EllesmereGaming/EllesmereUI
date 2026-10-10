if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_FocusKick.lua
--
--  The Focus Kick bar and the focus reminders.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- The main file or an earlier CDM file failed to load.
if not I or I.broken then return end
I.broken = true

local GetTime = GetTime

local ECME, _ecmeFC, barDataByKey = I.ECME, I._ecmeFC, I.barDataByKey
local cdmBarFrames, cdmBarIcons = I.cdmBarFrames, I.cdmBarIcons

-- FocusKick bar: a special CD bar pinned to the focus target's nameplate.
-- Internally it is just another custom cooldowns bar so every existing code
-- path treats it identically. Three behavior overrides handled elsewhere:
--   1. Visibility forced to "always" in _CDMApplyVisibility
--   2. Skipped in RegisterCDMUnlockElements
--   3. Position driven by ApplyFocusKickAnchor (nameplate hook)
local FOCUSKICK_BAR_KEY = "focuskick"
ns.FOCUSKICK_BAR_KEY = FOCUSKICK_BAR_KEY
local function EnsureFocusKickBar()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return end
    -- Desired position: directly after the "buffs" default bar and before any custom bars (skipping ghost bars).
    local bars = p.cdmBars.bars
    local targetIdx
    for i, b in ipairs(bars) do
        if b.key == "buffs" then targetIdx = i + 1; break end
    end
    if not targetIdx then targetIdx = #bars + 1 end
    local existingIdx
    for i, b in ipairs(bars) do
        if b.key == FOCUSKICK_BAR_KEY then existingIdx = i; break end
    end
    if existingIdx then
        -- Backfill suppressGCD on existing FocusKick bars (default to on)
        if bars[existingIdx].suppressGCD == nil then
            bars[existingIdx].suppressGCD = true
        end
        if existingIdx == targetIdx or existingIdx == targetIdx - 1 then
            -- Already in the right spot relative to "buffs"
            return
        end
        local entry = table.remove(bars, existingIdx)
        if existingIdx < targetIdx then targetIdx = targetIdx - 1 end
        table.insert(bars, targetIdx, entry)
        return
    end
    table.insert(bars, targetIdx, {
        key = FOCUSKICK_BAR_KEY,
        name = "FocusKick",
        barType = "cooldowns",
        enabled = true,
        iconSize = 28, numRows = 1, spacing = 2,
        borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
        borderClassColor = false, borderTexture = "solid", borderThickness = "thin",
        bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
        iconZoom = 0.08, iconShape = "none",
        verticalOrientation = false, barBgEnabled = false,
        barBgR = 0, barBgG = 0, barBgB = 0,
        showCooldownText = true, cooldownTextPosition = "center",
        showItemCount = true, cooldownFontSize = 12,
        showCharges = true, chargeFontSize = 11,
        desaturateOnCD = true, swipeAlpha = 0.7,
        suppressGCD = true,
        activeStateAnim = "blizzard",
        anchorTo = "none", anchorPosition = "left",
        anchorOffsetX = 0, anchorOffsetY = 0,
        barVisibility = "always",
        showStackCount = false, stackCountSize = 11, stackCountPosition = "bottomright",
        outOfRangeOverlay = false,
        pandemicGlow = false,
        -- FocusKick-specific: nameplate side + offsets
        nameplateAnchorSide = "LEFT",
        nameplateOffsetX = 0,
        nameplateOffsetY = 0,
        -- FocusKick-specific: "FOCUS" reminder text on caster/miniboss plates
        focusReminderEnabled = false,
        focusReminderUseAccent = true,
        focusReminderR = 1, focusReminderG = 1, focusReminderB = 1,
        focusReminderSize = 26,
        focusReminderOffsetX = 0,
        focusReminderOffsetY = 0,
        -- FocusKick-specific: show on target instead of focus
        focusKickUseTarget = false,
        -- FocusKick-specific: focus-cast sound trigger
        focusCastSoundKey = "none",
        focusKickInterruptSpellID = nil,
        growDirection = "RIGHT",
    })
    local sd = ns.GetBarSpellData(FOCUSKICK_BAR_KEY)
    if sd then sd.assignedSpells = {} end
end
ns.EnsureFocusKickBar = EnsureFocusKickBar

-- Returns the unit token the FocusKick bar tracks: "target" when the user has enabled Show on Target, "focus" otherwise.
local function GetFocusKickUnit()
    local bd = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    return (bd and bd.focusKickUseTarget) and "target" or "focus"
end
ns.GetFocusKickUnit = GetFocusKickUnit

-- Set the bar frame and all of its icons to the given alpha. CDM icons are parented to the
-- Blizzard viewer pool, not the bar frame, so hiding the bar frame alone leaves the icons visible -- per-icon alpha is required.
local function SetFocusKickAlpha(a)
    local frame = cdmBarFrames[FOCUSKICK_BAR_KEY]
    if frame then
        frame:SetAlpha(a)
        if frame.EnableMouseMotion and not InCombatLockdown() then
            -- Container never captures motion (steals hover from frames underneath); icon hover is owned by the tooltip setting.
            frame:EnableMouseMotion(false)
        end
        frame._visHidden = (a == 0)
    end
    local icons = cdmBarIcons and cdmBarIcons[FOCUSKICK_BAR_KEY]
    if icons then
        for i = 1, #icons do
            if icons[i] then icons[i]:SetAlpha(a) end
        end
    end
end

-- Find the scale-aware anchor frame inside a Blizzard nameplate. The EllesmereUINameplates
-- addon mixes a custom NameplateFrame into a child of the plate and applies "Scale Target
-- Nameplate"/"Scale Nameplate On Cast" via NameplateFrame:ApplyScale(); the Blizzard plate itself
-- does NOT scale, so anchoring to the plate ignores those settings. Walk the plate's children for the mixed-in frame's visible health bar (correct scaled bounds). Returns (healthFrame, scaledParent) or nil.
local function GetScaledPlateHealth(plate)
    if not plate then return nil end
    local children = { plate:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        if c and c._mixedIn and c.health then
            return c.health, c
        end
    end
    return nil
end

-- Position the FocusKick bar against the tracked unit's nameplate. Called on focus/target change,
-- nameplate add/remove, and nameplate moves. The stored nameplateAnchorSide picks the plate side (LEFT/RIGHT/TOP/BOTTOM); stored offsets shift from that anchor point.
local function ApplyFocusKickAnchor()
    local frame = cdmBarFrames[FOCUSKICK_BAR_KEY]
    if not frame then return end
    local p = ECME.db and ECME.db.profile
    local bd = p and barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    if not bd then return end
    local fkUnit = GetFocusKickUnit()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(fkUnit)
    if not plate then
        SetFocusKickAlpha(0)
        return
    end
    -- Prefer the scaled health bar from our custom NameplateFrame so the icon tracks Target/Cast
    -- scale changes. Fall back to the raw plate when the nameplates addon isn't loaded or the plate hasn't been decorated yet.
    local anchorFrame = GetScaledPlateHealth(plate) or plate
    local side = bd.nameplateAnchorSide or "LEFT"
    local ox = bd.nameplateOffsetX or 0
    local oy = bd.nameplateOffsetY or 0
    frame:ClearAllPoints()
    if side == "LEFT" then
        frame:SetPoint("RIGHT", anchorFrame, "LEFT", ox, oy)
    elseif side == "RIGHT" then
        frame:SetPoint("LEFT", anchorFrame, "RIGHT", ox, oy)
    elseif side == "TOP" then
        frame:SetPoint("BOTTOM", anchorFrame, "TOP", ox, oy)
    elseif side == "BOTTOM" then
        frame:SetPoint("TOP", anchorFrame, "BOTTOM", ox, oy)
    else
        frame:SetPoint("CENTER", anchorFrame, "CENTER", ox, oy)
    end
    SetFocusKickAlpha(1)
end
ns.ApplyFocusKickAnchor = ApplyFocusKickAnchor

-- Single event proxy, created once and persistent; just calls ApplyFocusKickAnchor on relevant
-- events. Range-fade handling: when the tracked unit walks out of range, Blizzard fades the
-- nameplate alpha without firing NAME_PLATE_UNIT_REMOVED. The bar icons don't inherit plate
-- visibility (parented to the Blizzard viewer pool), so throttle-poll the plate's visibility and propagate alpha to the icons manually -- only while a tracked plate exists; zero work otherwise.
local _focusKickProxy
local _focusKickLastPlateVisible
local _FOCUSKICK_TICK_INTERVAL = 0.1
local function EnsureFocusKickProxy()
    if _focusKickProxy then
        -- Re-apply/re-activate paths must restore the event set (a demand-gate teardown
        -- unregisters it; RegisterEvent is idempotent) and re-arm the watcher: a focus can already exist with no event forthcoming (settings apply, /reload with focus).
        _focusKickProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
        _focusKickProxy:RegisterEvent("PLAYER_TARGET_CHANGED")
        _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        if _focusKickProxy._arm then _focusKickProxy._arm() end
        return _focusKickProxy
    end
    _focusKickProxy = ns.TakeShell()
    _focusKickProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
    _focusKickProxy:RegisterEvent("PLAYER_TARGET_CHANGED")
    _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    _focusKickProxy:SetScript("OnEvent", function(self, event, unit)
        local fkUnit = GetFocusKickUnit()
        if event == "PLAYER_FOCUS_CHANGED" then
            if fkUnit ~= "focus" then return end
            _focusKickLastPlateVisible = nil
            ApplyFocusKickAnchor()
            if self._arm then self._arm() end
        elseif event == "PLAYER_TARGET_CHANGED" then
            if fkUnit ~= "target" then return end
            _focusKickLastPlateVisible = nil
            ApplyFocusKickAnchor()
            if self._arm then self._arm() end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            -- Only react when the tracked unit's plate is removed. Reacting to every plate removal caused the bar to flicker off during AoE when unrelated mobs died or faded.
            if unit and (unit == fkUnit or UnitIsUnit(unit, fkUnit)) then
                _focusKickLastPlateVisible = nil
                ApplyFocusKickAnchor()
            end
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            if unit and (unit == fkUnit or UnitIsUnit(unit, fkUnit)) then
                _focusKickLastPlateVisible = nil
                ApplyFocusKickAnchor()
                if self._arm then self._arm() end
            end
        end
    end)
    -- Plate fade/occlusion has no event, so watching the tracked unit's plate visibility needs a
    -- poll -- but ONLY while a tracked unit exists, on a self-stopping anim ticker (the C engine
    -- sleeps between 0.1s fires) rather than a per-render-frame OnUpdate. The ticker stops itself the moment the unit is gone; the proxy's own events (focus/target changed, plate added) and EnsureFocusKickProxy re-arm it.
    local fkTicker
    local function FocusKickTick()
        local fkUnit = GetFocusKickUnit()
        if not UnitExists(fkUnit) then return false end
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
            and C_NamePlate.GetNamePlateForUnit(fkUnit)
        local visibleNow
        if plate then
            local alpha = plate:GetEffectiveAlpha() or 0
            visibleNow = plate:IsVisible() and alpha > 0.01
        else
            visibleNow = false
        end
        if visibleNow ~= _focusKickLastPlateVisible then
            _focusKickLastPlateVisible = visibleNow
            SetFocusKickAlpha(visibleNow and 1 or 0)
        end
        return true
    end
    _focusKickProxy._arm = function()
        if not fkTicker then
            fkTicker = EllesmereUI.Tick.NewAnimTicker(_focusKickProxy,
                FocusKickTick, _FOCUSKICK_TICK_INTERVAL)
        end
        fkTicker.Start()
    end
    _focusKickProxy._stop = function()
        if fkTicker then fkTicker.Stop() end
    end
    _focusKickProxy._arm()
    return _focusKickProxy
end
ns.EnsureFocusKickProxy = EnsureFocusKickProxy

-- Sound dropdown data: built-in EllesmereUI sounds + LibSharedMedia sounds appended at runtime via EllesmereUI.AppendSharedMediaSounds.
local FOCUSKICK_SOUND_PATHS, FOCUSKICK_SOUND_NAMES, FOCUSKICK_SOUND_ORDER =
    EllesmereUI.BuildAlertSoundTables()
ns.FOCUSKICK_SOUND_PATHS = FOCUSKICK_SOUND_PATHS
ns.FOCUSKICK_SOUND_NAMES = FOCUSKICK_SOUND_NAMES
ns.FOCUSKICK_SOUND_ORDER = FOCUSKICK_SOUND_ORDER

-- Focus-cast sound trigger. When the focus target starts a cast and the user's selected interrupt
-- is off cooldown, play the configured sound. One single proxy registered with RegisterUnitEvent on "focus" -- the token follows focus changes automatically.
local _focusCastProxy
local function RefreshFocusCastProxyUnit()
    if not _focusCastProxy then
        -- No proxy to re-point: the bar had no assigned spell at the last arming (RefreshFocusKickProxies
        -- only builds on its hasContent branch, and its ONLY callers are setup and the tail of
        -- BuildAllCDMBars). Adding a spell in the options writes assignedSpells without re-arming
        -- anything, which left the sound dead on a fully populated bar -- so run the full refresh here instead of returning, letting this path create the proxy.
        if ns.RefreshFocusKickProxies then ns.RefreshFocusKickProxies() end
        return
    end
    local unit = GetFocusKickUnit()
    _focusCastProxy:UnregisterAllEvents()
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
end
ns.RefreshFocusCastProxyUnit = RefreshFocusCastProxyUnit

function ns.IsSpellInPlayerBook(id, includeOverrides)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
        and C_SpellBook.IsSpellKnownOrInSpellBook(id, Enum.SpellBookSpellBank.Player, includeOverrides ~= false) then
        return true
    end
    return false
end

-- Returns the id of the stored interrupt in the form this character can actually cast, or nil.
-- Validate on READ and never write: focusKickInterruptSpellID is profile-level while the spellbook
-- behind it is per-spec, so the id stays correct for the spec that set it -- clearing it here would
-- destroy that spec's setting the first time the player logged in on another one. Asks the
-- SPELLBOOK, never a class/spec table (a hardcoded list goes stale on a patch). Pet-bank interrupts
-- (a Warlock's Axe Toss, a Hunter's pet kick) are legitimate picks IsPlayerSpell cannot see, so
-- check both banks. Returning the resolved id (not a boolean) is the point: a talent swap moves an
-- interrupt between base and override forms while the stored id stays put; answering "known" but leaving the caller the un-castable form would feed the readiness gate an id that is never on cooldown.
function ns.ResolveCastableInterrupt(sid)
    if type(sid) ~= "number" or sid <= 0 then return nil end
    local knownInBook = ns.IsSpellInPlayerBook
    -- Resolve replacements first: Command Demon can remain known while its
    -- active pet command has the cooldown we need to check.
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local ovr = C_SpellBook.FindSpellOverrideByID(sid)
        if ovr and ovr > 0 and ovr ~= sid and knownInBook(ovr) then return ovr end
    end
    if knownInBook(sid) then return sid end
    -- Talented back out, stored id is the replacement form.
    if C_Spell and C_Spell.GetBaseSpell then
        local base = C_Spell.GetBaseSpell(sid)
        if base and base > 0 and base ~= sid and knownInBook(base) then return base end
    end
    -- Pet bank last: it has no override/base indirection to walk.
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
        and Enum and Enum.SpellBookSpellBank
        and C_SpellBook.IsSpellKnownOrInSpellBook(sid, Enum.SpellBookSpellBank.Pet) then
        return sid
    end
    return nil
end

local function EnsureFocusCastProxy()
    if _focusCastProxy then
        -- Demand-gate re-activation: re-register (idempotent; re-applying RegisterUnitEvent also picks up a changed kick-unit setting).
        local unit = GetFocusKickUnit()
        _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
        _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
        return _focusCastProxy
    end
    _focusCastProxy = ns.TakeShell()
    local unit = GetFocusKickUnit()
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    _focusCastProxy:SetScript("OnEvent", function()
        local bd = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
        if not bd then return end
        local soundKey = bd.focusCastSoundKey or "none"
        if soundKey == "none" then return end
        local spellID = bd.focusKickInterruptSpellID
        -- An explicit pick is only trusted while this character can cast it: a stale profile-level
        -- id sails through the cooldown gate below forever (a spell you do not know is never on
        -- cooldown), so a Holy Paladin inheriting a Ret's Rebuke would be pinged on every focus
        -- cast. Deliberately checked HERE and not at arming time: arming runs during loading
        -- screens, when the spellbook reads empty for reasons unrelated to spec, and folding "not
        -- loaded yet" into "cannot cast it" silently unregisters a working proxy. This handler only runs on a live cast, by which point the spellbook is settled.
        if spellID then spellID = ns.ResolveCastableInterrupt(spellID) end
        -- Auto-fallback: with no explicit pick, use the first CASTABLE positive spell on the bar
        -- (the picker exists for users who want a specific one). The bar's own list needs the same
        -- castability check -- not because it crosses specs (assignedSpells is per-spec) but
        -- because it can hold spells this spec no longer has: "Include CDM Spell Layout" imports
        -- write another character's layout into these spec keys wholesale, and talent changes strand entries the same way. Either way, an uncastable interrupt reads as permanently ready below.
        if not spellID or spellID <= 0 then
            local sd = ns.GetBarSpellData and ns.GetBarSpellData(FOCUSKICK_BAR_KEY)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if type(sid) == "number" and sid > 0 then
                        local castable = ns.ResolveCastableInterrupt(sid)
                        if castable then
                            spellID = castable
                            break
                        end
                    end
                end
            end
        end
        if not spellID or spellID <= 0 then return end

        -- No interruptible check. The kickProtected flag on UnitCastingInfo and UnitChannelInfo is
        -- a secret boolean in Midnight and any laundering path that returns a value back into Lua
        -- produces a tainted result we cannot branch on. We accept that the sound will occasionally fire on uninterruptible casts -- the nameplate shield icon still tells the player visually.

        -- Cooldown check: only play if our interrupt is ready. cdInfo.isActive is a clean bool --
        -- the duration/startTime fields are secret in Midnight and can't be compared in Lua, but isActive is safe.
        if C_Spell and C_Spell.GetSpellCooldown then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.isActive then return end
        end
        local path = FOCUSKICK_SOUND_PATHS[soundKey]
        if not path then return end
        PlaySoundFile(path, "Master")
    end)
    return _focusCastProxy
end
ns.EnsureFocusCastProxy = EnsureFocusCastProxy

-- Per-icon "Audio on Buff Gain/Loss": play a sound when a buff becomes active (gain) or drops
-- (loss). Blizzard's buff viewer item frames fire TriggerAuraAppliedAlert on the apply edge and
-- TriggerAuraRemovedAlert on the drop edge, so hooksecurefunc both (taint-safe post-hook, no
-- polling). The frame's GetSpellID is a SECRET value while the aura is active, so resolve the
-- clean canonical id via GetCanonicalSpellIDForFrame (the same id the options menu writes the
-- setting under) -- never index a table with the live secret id. Hooked-frame + throttle state
-- live in a do-block, off the Blizzard frame table per the no-custom-props rule. Reuses the
-- FocusKick sound table (option list identical to Focus Cast Sound). Edges are COALESCED to
-- the end of the frame rather than played on the spot: some auras are reapplied by REPLACING
-- the instance instead of refreshing it, and Blizzard checks its removed-alert triggers before
-- the item frames adopt the new instance, so the drop edge fires while the buff is still up.
-- Death and Decay does this on every entry into the circle, cueing a loss at the moment the
-- buff was GAINED. Both alerts for a replacement fire inside the SAME CooldownViewerMixin
-- :OnUnitAura call -- confirmed live to be indistinguishable from a genuine same-tick
-- drop+reproc (e.g. Prismatic Bolt consumed by a cast and reprocced by Salvo), so only the
-- loss cue is cancelled on a pair. A real gain always plays, even on a replacement, rather
-- than silently eating the reported case with no way to tell the two apart.
do
    local _soundHooked = setmetatable({}, { __mode = "k" })
    -- Edges seen this frame: [spellID] = sound key, or false for "edge happened,
    -- configured silent". A silent edge MUST still be recorded or a replacement
    -- whose gain has no sound (the usual setup -- loss cue only) never pairs.
    local _pendGain = {}
    local _pendLoss = {}
    local _flushQueued = false
    local _pendStamp = 0                 -- GetTime() of the frame the pending edges belong to
    -- Overlap guard, NOT an edge filter: two cues for the same spell and edge closer
    -- together than this would talk over each other. Replacements are cancelled by the
    -- pairing above, so this no longer hides them.
    local _soundThrottle = {}            -- [spellID] = last GetTime() (gain)
    local _soundThrottleLost = {}        -- [spellID] = last GetTime() (loss)
    local SOUND_MIN_GAP = 0.3

    -- Setting key for one edge, nil = silent. A frame the CDM decorates answers
    -- from its own settings first. A Tracked Bars frame then asks its tracking
    -- bar before FindBuffSoundKey, whose bar tier answers for every spell no
    -- extra buff bar claims (a Buffs bar "Apply to Bar" sound would otherwise
    -- shadow the bar's own). A bar with a sound on its other edge only keeps
    -- this edge silent (false), so the Buffs bar is not asked either. A buff
    -- icon frame asks the tracking bars last.
    local function PickBuffSoundKey(ss, sid, field, f)
        local k = ss and ss[field]
        if not k then
            local tbbOn = ns._tbbAnyBuffSound
            local bv = tbbOn and f and _G.BuffBarCooldownViewer
            local barFrame = bv and f.viewerFrame == bv
            local owned
            if barFrame then
                k = ns.FindTBBSoundKey(f, sid, field)
                owned = k == false
            end
            if not k and not owned then k = ns.FindBuffSoundKey(sid, field) end
            if not k and tbbOn and not barFrame then k = ns.FindTBBSoundKey(f, sid, field) end
        end
        if not k or k == "none" then return nil end
        return k
    end

    local function PlayThrottled(key, sid, throttle)
        if not key then return end
        local now = GetTime()
        local last = throttle[sid]
        if last and (now - last) < SOUND_MIN_GAP then return end
        throttle[sid] = now
        local path = FOCUSKICK_SOUND_PATHS[key]
        if path then PlaySoundFile(path, "Master") end
    end

    -- Edge entry point for Tracking Bars' self-timed presets (Bloodlust, Time
    -- Spiral, potions). They never fire a Blizzard aura alert, so their own timer
    -- start/stop hands the cue here: same loading-screen suppression, same 0.3s
    -- overlap guard (id is a "tbb:<preset>" string, clear of spell ids).
    function ns.PlayBuffSoundEdge(key, id, gainEdge)
        if not key or key == "none" then return end
        if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then return end
        PlayThrottled(key, id, gainEdge and _soundThrottle or _soundThrottleLost)
    end

    local function FlushBuffEdges()
        _flushQueued = false
        -- Still inside the frame these edges were recorded in (the timer can tick
        -- after some of the frame's aura events but before the rest): a later edge
        -- could still pair with them, so decide next frame instead.
        if GetTime() == _pendStamp then
            _flushQueued = true
            C_Timer.After(0, FlushBuffEdges)
            return
        end
        -- Entries are cleared BEFORE playing so a throw inside PlaySoundFile cannot
        -- strand one and have it cancel an unrelated edge on a later flush.
        for sid, key in pairs(_pendLoss) do
            -- Paired with a gain this frame = replacement: the loss cue is spurious
            -- (the buff never really left). The gain may still be real (e.g. a proc
            -- landing the same tick a cast consumes the old stack), so it is left for
            -- the gain loop below instead of being cancelled here too.
            local paired = _pendGain[sid] ~= nil
            _pendLoss[sid] = nil
            if not paired then PlayThrottled(key, sid, _soundThrottleLost) end
        end
        for sid, key in pairs(_pendGain) do
            _pendGain[sid] = nil
            PlayThrottled(key, sid, _soundThrottle)
        end
    end

    -- Record one edge for the end-of-frame flush. gainEdge picks the side.
    local function RecordBuffEdge(f, gainEdge)
        -- Loading screen / login settle: buffs re-apply and viewer frames re-show
        -- across a zone/login, firing phantom apply/remove alerts. Drop them.
        if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then return end
        local sid = ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(f)
        if not sid then return end
        -- Preferred: the frame's decorated context (fast; ResolveSpellSettings also
        -- handles variant/override spells). Falls back to an id-only lookup for the
        -- FIRST gain after login, whose alert fires before DecorateFrame populates
        -- _ecmeFC -- keying off that context dropped the very first cue.
        local ss
        local fc = _ecmeFC[f]
        local barKey = fc and fc.barKey
        if barKey then
            local sd = ns.GetBarSpellData and ns.GetBarSpellData(barKey)
            ss = ns.ResolveSpellSettings and ns.ResolveSpellSettings(f, sid, sd, barKey)
        end
        -- A silent edge still has to be recorded so it can cancel its partner, but only
        -- when the OTHER edge has a cue -- so the second lookup runs only on that path.
        local key = PickBuffSoundKey(ss, sid, gainEdge and "buffActiveSoundKey" or "buffLostSoundKey", f)
        if not key and not PickBuffSoundKey(ss, sid, gainEdge and "buffLostSoundKey" or "buffActiveSoundKey", f) then
            return
        end
        -- A new frame closes the previous batch: pairing must never reach across the
        -- boundary, or a real drop and an unrelated real gain a frame later cancel out.
        local now = GetTime()
        if now ~= _pendStamp then
            FlushBuffEdges()
            _pendStamp = now
        end
        if gainEdge then
            _pendGain[sid] = key or false
        else
            _pendLoss[sid] = key or false
        end
        if not _flushQueued then
            _flushQueued = true
            C_Timer.After(0, FlushBuffEdges)
        end
    end

    function ns.EnsureBuffSoundHook(frame)
        if not frame or _soundHooked[frame] then return end
        -- Own placeholder/custom frames (and anything that isn't a Blizzard buff
        -- viewer item) have no aura alert -- mark hooked so we never retry.
        if type(frame.TriggerAuraAppliedAlert) ~= "function" then
            _soundHooked[frame] = true
            return
        end
        _soundHooked[frame] = true
        hooksecurefunc(frame, "TriggerAuraAppliedAlert", function(f)
            RecordBuffEdge(f, true)
        end)
        -- Loss edge: Blizzard fires TriggerAuraRemovedAlert when the buff drops.
        if type(frame.TriggerAuraRemovedAlert) == "function" then
            hooksecurefunc(frame, "TriggerAuraRemovedAlert", function(f)
                RecordBuffEdge(f, false)
            end)
        end
    end
end

-- "FOCUS" reminder text shown on caster/miniboss nameplates when the player
-- has no focus set. Activated by the FocusKick bar's focusReminderEnabled.
-- Performance design:
--   * _focusKickHasFocus updates only on PLAYER_FOCUS_CHANGED so the hot
--     per-plate path never calls UnitExists("focus").
--   * Per-plate font strings live in _focusReminders keyed by token and are
--     reused across show/hide cycles -- never recreated.
--   * Each font string caches its last applied size/text/color/offsets so
--     SetFont / SetText / SetTextColor / SetPoint are skipped when unchanged
--     (SetFont is the most expensive call here).
--   * NAME_PLATE_UNIT_ADDED skips the work entirely when focus is set or the
--     bar setting is off -- no per-plate overhead in the normal case.
local _focusReminders = {}        -- nameplate token -> font string (with _holder/_lastX cache)
local _focusReminderProxy
local _focusKickHasFocus = false
-- Context flags updated only on world/zone/spec events. Cached so the
-- per-nameplate hot path is one local read instead of repeated API calls.
local _focusKickInDungeon = false
local _focusKickNoKick    = false
local _FOCUS_TEXT = "F O C U S"
local _FR_FALLBACK_FONT = "Fonts/FRIZQT__.TTF"

-- Mirror of the Quest Tracker font handling pattern: tolerate nil/OTF
-- paths, fall back to FRIZQT, and (if SetFont still fails) try alternate
-- separators / Blizzard's default font.
local function FRSafeFont(p)
    if not p or p == "" then return _FR_FALLBACK_FONT end
    local ext = p:match("%.(%a+)$")
    if ext and ext:lower() == "otf" then return _FR_FALLBACK_FONT end
    return p
end
local function FRGlobalFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return FRSafeFont(EllesmereUI.GetFontPath("cdm"))
    end
    return _FR_FALLBACK_FONT
end
local function FROutlineFlag()
    if EllesmereUI and EllesmereUI.GetFontOutlineFlag then
        local f = EllesmereUI.GetFontOutlineFlag("cdm")
        if f and f ~= "" then return f end
    end
    return "NONE"
end
local function FRSetFontSafe(fs, path, size, flags)
    if not fs then return end
    local safe = FRSafeFont(path)
    size = size or 11
    if flags == "NONE" then flags = "" end
    flags = flags or ""
    local curPath, curSize, curFlags = fs:GetFont()
    if curPath == safe and curSize == size and (curFlags or "") == flags then return end
    fs:SetFont(safe, size, flags)
    if not fs:GetFont() then fs:SetFont("Fonts/FRIZQT__.TTF", size, flags) end
    if not fs:GetFont() then fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags) end
    if not fs:GetFont() then
        local gf = GameFontNormal and GameFontNormal:GetFont()
        if gf then fs:SetFont(gf, size, flags) end
    end
end
local function FRApplyFontShadow(fs)
    if not fs then return end
    local useShadow = (EllesmereUI.GetFontUseShadow("cdm")) and true or false
    -- Font is set by FRSetFontSafe before this call; capture and restore it so
    -- priming the shadow FontObject does not change the typeface.
    local _pf, _ps, _pfl = fs:GetFont()
    EllesmereUI.PrimeFontShadow(fs, useShadow)
    if _pf then fs:SetFont(_pf, _ps, _pfl) end
end

local function GetFocusKickBarData()
    return barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
end
local function FocusReminderUnitMatches(unit)
    if not unit then return false end
    -- Caster = the unit actually has a mana pool (12.1 moved caster marking
    -- off the old internal "PALADIN" class tag; same lane as the nameplate
    -- caster color). Second arg is the typed PowerType enum NUMBER, not the
    -- localized MANA global; the return carries no secrecy flag, so it is
    -- safe to branch on directly even on protected-content nameplates.
    if UnitHasPowerType and Enum and Enum.PowerType
        and UnitHasPowerType(unit, Enum.PowerType.Mana) then
        return true
    end
    -- Elite fallback: identity reads here DO return secrets in protected
    -- content; a secret can vouch nothing, so the signal is dropped, never
    -- compared -- this arm quietly stands down there while the mana arm
    -- above keeps carrying the feature.
    local cls = UnitClassification and UnitClassification(unit)
    if issecretvalue and issecretvalue(cls) then cls = nil end
    if cls == "elite" or cls == "rareelite" or cls == "worldboss" then
        local lvl = UnitLevel(unit)
        local plvl = UnitLevel("player")
        local lvlClean = lvl and not (issecretvalue and issecretvalue(lvl))
        local plvlClean = plvl and not (issecretvalue and issecretvalue(plvl))
        if lvlClean and (lvl == -1 or (plvlClean and lvl >= plvl + 1)) then return true end
    end
    return false
end
local function HideFocusReminder(token)
    local fs = _focusReminders[token]
    if fs and fs:IsShown() then fs:Hide() end
end
local function HideAllFocusReminders()
    for _, fs in pairs(_focusReminders) do
        if fs and fs:IsShown() then fs:Hide() end
    end
end
local function ShowFocusReminder(token)
    -- Cheap rejects first
    if _focusKickHasFocus then HideFocusReminder(token); return end
    if not _focusKickInDungeon then HideFocusReminder(token); return end
    if _focusKickNoKick then HideFocusReminder(token); return end
    local bd = GetFocusKickBarData()
    if not bd or bd.focusReminderEnabled ~= true then
        HideFocusReminder(token); return
    end
    if not FocusReminderUnitMatches(token) then
        HideFocusReminder(token); return
    end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(token)
    if not plate then HideFocusReminder(token); return end

    local fs = _focusReminders[token]
    if not fs then
        local holder = CreateFrame("Frame", nil, plate)
        holder:SetSize(1, 1)
        holder:SetFrameStrata("HIGH")
        holder:SetFrameLevel(plate:GetFrameLevel() + 10)
        fs = holder:CreateFontString(nil, "OVERLAY")
        fs._holder = holder
        fs:SetPoint("CENTER", holder, "CENTER", 0, 0)
        -- IMPORTANT: SetFont must run before SetText. Initialize the font using the safe helper
        -- here so the very first SetText below has a valid font. (Calling SetText on a font string with no font set raises "FontString:SetText(): Font not set".)
        FRSetFontSafe(fs, FRGlobalFont(), bd.focusReminderSize or 26, FROutlineFlag())
        FRApplyFontShadow(fs)
        fs:SetText(_FOCUS_TEXT)
        fs._lastText = _FOCUS_TEXT
        _focusReminders[token] = fs
    end

    -- Reparent only when the plate frame for this token actually changed
    if fs._holder:GetParent() ~= plate then
        fs._holder:SetParent(plate)
        fs._lastOX, fs._lastOY = nil, nil  -- force point reapply on parent change
    end

    -- Anchor: only re-SetPoint if X or Y changed
    local ox = bd.focusReminderOffsetX or 0
    local oy = (bd.focusReminderOffsetY or 0) - 15  -- internal -15 baseline
    if fs._lastOX ~= ox or fs._lastOY ~= oy then
        fs._holder:ClearAllPoints()
        fs._holder:SetPoint("TOP", plate, "BOTTOM", ox, oy)
        fs._lastOX, fs._lastOY = ox, oy
    end

    -- Font: re-apply only if size, font path, or outline changed. Goes through FRSetFontSafe so
    -- the user's global font + outline (EllesmereUI -> Fonts) drives the look, with fallbacks for missing/unsupported paths.
    local size = bd.focusReminderSize or 26
    local fontPath = FRGlobalFont()
    local outline = FROutlineFlag()
    if fs._lastSize ~= size or fs._lastFontPath ~= fontPath or fs._lastOutline ~= outline then
        FRSetFontSafe(fs, fontPath, size, outline)
        FRApplyFontShadow(fs)
        fs._lastSize = size
        fs._lastFontPath = fontPath
        fs._lastOutline = outline
    end

    -- Color: accent mode reads the live ELLESMERE_GREEN; custom mode reads the stored RGB. Re-SetTextColor only if the resolved color changed.
    local r, g, b
    if bd.focusReminderUseAccent then
        local eg = EllesmereUI.ELLESMERE_GREEN
        r = (eg and eg.r) or 0.047
        g = (eg and eg.g) or 0.824
        b = (eg and eg.b) or 0.624
    else
        r = bd.focusReminderR or 1
        g = bd.focusReminderG or 1
        b = bd.focusReminderB or 1
    end
    if fs._lastR ~= r or fs._lastG ~= g or fs._lastB ~= b then
        fs:SetTextColor(r, g, b)
        fs._lastR, fs._lastG, fs._lastB = r, g, b
    end

    if not fs:IsShown() then fs:Show() end
end

local function RefreshFocusReminders()
    -- Clear all, then re-show for currently visible nameplates. Iterate unit tokens directly:
    -- plate.namePlateUnitToken can be nil when polled outside of NAME_PLATE_UNIT_ADDED events, so the safer path is to walk nameplate1..nameplate40 and let UnitExists filter.
    HideAllFocusReminders()
    if _focusKickHasFocus then return end
    if not _focusKickInDungeon then return end
    if _focusKickNoKick then return end
    local bd = GetFocusKickBarData()
    if not bd or bd.focusReminderEnabled ~= true then return end
    for i = 1, 40 do
        local token = "nameplate" .. i
        if UnitExists(token) then
            ShowFocusReminder(token)
        end
    end
end
ns.RefreshFocusReminders = RefreshFocusReminders
_G._ECME_RefreshFocusReminders = RefreshFocusReminders

-- Refresh the cached context flags (instance type + role) and trigger a visual refresh if either
-- flag transitioned. Called on PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA, and PLAYER_SPECIALIZATION_CHANGED.
-- Healer specs that have no kick (Resto Shaman has Wind Shear, so excluded)
local _HEALER_NO_KICK = {
    [65]  = true, -- Holy Paladin
    [256] = true, -- Discipline Priest
    [257] = true, -- Holy Priest
    [105] = true, -- Restoration Druid
    [270] = true, -- Mistweaver Monk
    [1468] = true, -- Preservation Evoker
}

local function UpdateFocusKickContext()
    local _, instanceType = IsInInstance()
    local nowInDungeon = (instanceType == "party")
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID = specIndex > 0 and C_SpecializationInfo.GetSpecializationInfo(specIndex)
    local nowNoKick = specID and _HEALER_NO_KICK[specID] or false
    local changed = (nowInDungeon ~= _focusKickInDungeon) or (nowNoKick ~= _focusKickNoKick)
    _focusKickInDungeon = nowInDungeon
    _focusKickNoKick    = nowNoKick
    if changed then
        RefreshFocusReminders()
    end
end
ns.UpdateFocusKickContext = UpdateFocusKickContext

local function EnsureFocusReminderProxy()
    if _focusReminderProxy then
        -- Demand-gate re-activation: restore the event set (idempotent) and re-seed the state the creation path seeds.
        _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        _focusReminderProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
        _focusReminderProxy:RegisterEvent("PLAYER_ENTERING_WORLD")
        _focusReminderProxy:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        _focusReminderProxy:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        _focusKickHasFocus = UnitExists("focus") and true or false
        UpdateFocusKickContext()
        return _focusReminderProxy
    end
    -- Initialize focus + context state once at proxy creation
    _focusKickHasFocus = UnitExists("focus") and true or false
    UpdateFocusKickContext()
    _focusReminderProxy = ns.TakeShell()
    _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    _focusReminderProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
    _focusReminderProxy:RegisterEvent("PLAYER_ENTERING_WORLD")
    _focusReminderProxy:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    _focusReminderProxy:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _focusReminderProxy:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_FOCUS_CHANGED" then
            local hadFocus = _focusKickHasFocus
            _focusKickHasFocus = UnitExists("focus") and true or false
            if hadFocus ~= _focusKickHasFocus then
                RefreshFocusReminders()
            end
        elseif event == "PLAYER_ENTERING_WORLD"
            or event == "ZONE_CHANGED_NEW_AREA"
            or event == "PLAYER_SPECIALIZATION_CHANGED" then
            UpdateFocusKickContext()
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            if _focusKickHasFocus then return end
            if not _focusKickInDungeon then return end
            if _focusKickIsHealer then return end
            ShowFocusReminder(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            HideFocusReminder(unit)
        end
    end)
    return _focusReminderProxy
end
ns.EnsureFocusReminderProxy = EnsureFocusReminderProxy

-- Demand gate for the whole FocusKick feature family (anchor proxy + plate watcher, reminder
-- text, cast sound). An EMPTY kick bar -- no positive spell assigned, or the bar disabled --
-- means the feature does not exist at runtime: no events registered anywhere, no ticker, zero
-- cost. Called from setup and from the tail of every BuildAllCDMBars, so assigning the first kick spell (or removing the last) flips the family on/off live.
function ns.RefreshFocusKickProxies()
    local bd = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    local hasContent = false
    -- "No spell data available" is NOT the same as "the bar is empty": GetBarSpellData returns nil
    -- while the active spec key is unresolved, which is exactly the loading-screen state. Treating
    -- that as empty ran the teardown below and UNREGISTERED a perfectly good proxy (sound dying after a port/zone until something rebuilt the bars). With the store not ready, leave the proxy exactly as it is; the next rebuild arms it.
    local storeReady, soundWanted = true, false
    if bd and bd.enabled ~= false then
        local sd = ns.GetBarSpellData and ns.GetBarSpellData(FOCUSKICK_BAR_KEY)
        if not sd then storeReady = false end
        local spells = sd and sd.assignedSpells
        if spells then
            for _, sid in ipairs(spells) do
                if type(sid) == "number" and sid > 0 then
                    hasContent = true
                    break
                end
            end
        end
        -- The cast SOUND has a weaker requirement than the rest of the family: its handler needs a
        -- configured sound plus an interrupt id for the readiness check, and the bar's assigned
        -- spells are only the FALLBACK source for that id -- an explicit focusKickInterruptSpellID
        -- satisfies it alone. Gating the sound on hasContent made a legitimate setup impossible: the focus-cast sound WITHOUT the kick icon.
        local sk = bd.focusCastSoundKey
        if sk and sk ~= "none" then
            local pick = bd.focusKickInterruptSpellID
            soundWanted = (type(pick) == "number" and pick > 0) or hasContent
        end
    end

    if not hasContent and not storeReady then
        -- Spell store unresolved: hold the current state rather than tearing down something that
        -- may still be correct, and COME BACK -- arming is otherwise a one-shot (its only callers
        -- are setup and the tail of BuildAllCDMBars), so a login/zone where the spec key has not
        -- resolved yet would leave the proxy unbuilt all session on a fully populated bar. An explicit interrupt spell id lives on the bar data, not the spell store, so the sound can arm right now; only the bar-content dependent parts have to wait.
        if soundWanted then EnsureFocusCastProxy() end
        -- One pending retry at a time, self-cancelling.
        if not ns._fkRearmPending then
            ns._fkRearmPending = true
            C_Timer.After(2, function()
                ns._fkRearmPending = nil
                if ns.RefreshFocusKickProxies then ns.RefreshFocusKickProxies() end
            end)
        end
        return
    end
    -- Icon-bearing parts of the family keep the original bar-content gate.
    if hasContent then
        EnsureFocusKickProxy()
        ApplyFocusKickAnchor()
        EnsureFocusReminderProxy()
        RefreshFocusReminders()
    else
        if _focusKickProxy then
            _focusKickProxy:UnregisterAllEvents()
            if _focusKickProxy._stop then _focusKickProxy._stop() end
            SetFocusKickAlpha(0)
        end
        if _focusReminderProxy then
            _focusReminderProxy:UnregisterAllEvents()
            HideAllFocusReminders()
        end
    end

    if soundWanted then
        EnsureFocusCastProxy()
    elseif _focusCastProxy then
        _focusCastProxy:UnregisterAllEvents()
    end
end


I.EnsureFocusKickBar, I.FOCUSKICK_BAR_KEY = EnsureFocusKickBar, FOCUSKICK_BAR_KEY
I.FOCUSKICK_SOUND_NAMES, I.FOCUSKICK_SOUND_ORDER = FOCUSKICK_SOUND_NAMES, FOCUSKICK_SOUND_ORDER
I.FOCUSKICK_SOUND_PATHS = FOCUSKICK_SOUND_PATHS
I.broken = false
