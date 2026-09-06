if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmAuraSounds.lua
--  Audio on Buff Gain/Loss for AURA-TRACKED custom buffs (customSpellIDs
--  entries with no stored duration -- the AuraKit engine population).
--
--  These icons render from engine containers whose per-button aura identity is
--  SECRET, so none of the Lua sound paths can reach them: the Blizzard-viewer
--  apply-edge hook needs TriggerAuraAppliedAlert (engine buttons have none),
--  and the cast-timer preset path is gated on a stored duration. Instead the
--  CLIENT does the edge detection: C_UnitAuras.AddAuraSound (12.1, any aura)
--  takes a clean spell id + sound file and plays it on the aura event with no
--  secret read anywhere. buffActiveSoundKey registers the Added trigger,
--  buffLostSoundKey the Removed trigger; ApplicationsIncreased is deliberately
--  not registered (stack gains stay silent, pending a product call).
--
--  Sync model: ns.QueueCustomAuraSoundSync() is the ONLY entry point --
--  coalesced to end of frame, then DIFFED against the live registrations so a
--  no-op sync makes zero API calls. Structural changes ride the tail of
--  UpdateCustomBuffAuraTracking; the options sound rows and the Apply-to-Bar
--  executors queue it directly. Registration honors the same trust boundaries
--  as the Lua sound paths: deferred while InCombatLockdown (the API's
--  private-aura ancestor was combat-locked; retried on PLAYER_REGEN_ENABLED)
--  and while ns._cdmSoundSuppressed (login/zone settle -- timer retry).
--  LOADING_SCREEN_ENABLED tears every registration down so the zone-in
--  re-apply burst cannot phantom-cue; PLAYER_ENTERING_WORLD re-syncs.
--
--  Cross-path dedupe: the same spell id can ALSO be a Blizzard-tracked buff or
--  a cast-timer custom on another bar -- both resolve the same settings entry
--  and would double-cue. ns.IsClientAuraSoundOwner(sid) answers "the client
--  owns this id's cues" (keyed by every registered identity form) and the
--  three Lua players early-out on it. Empty-table lookup for everyone else.
-------------------------------------------------------------------------------
local _, ns = ...

local AddSound    = C_UnitAuras and C_UnitAuras.AddAuraSound
local RemoveSound = C_UnitAuras and C_UnitAuras.RemoveAuraSound
local Triggers    = Enum and Enum.UnitAuraSoundTrigger
-- API absent or renamed again: the whole module stays inert (guarded callers
-- no-op on the missing ns functions) and behavior reverts to pre-fix silence.
if not (AddSound and RemoveSound and Triggers
        and Triggers.Added ~= nil and Triggers.Removed ~= nil) then
    return
end

local TRIG_ADDED   = Triggers.Added
local TRIG_REMOVED = Triggers.Removed

-- Live registrations: ["idForm:trigger"] = { id = auraSoundID, key = soundKey,
-- owner = assignedSpells id }. _liveForm counts registrations per identity
-- form id, so the dedupe test covers canonical/override matches too.
local _regs = {}
local _liveForm = {}

local _syncQueued = false
local _regenArmed = false

local function DBG(...)
    if ns._auraSoundDebug then print("|cff0cd29fEUI CDM aura-sound:|r", ...) end
end

function ns.IsClientAuraSoundOwner(sid)
    return _liveForm[sid] ~= nil
end

local function DropReg(rk, reg)
    pcall(RemoveSound, reg.id)
    _regs[rk] = nil
    for _, formKey in ipairs(reg.forms) do
        local c = _liveForm[formKey]
        if c and c > 1 then _liveForm[formKey] = c - 1 else _liveForm[formKey] = nil end
    end
    DBG("unregistered", rk, "key=" .. tostring(reg.key))
end

-- Identity forms for one custom id: the id itself plus its live override and
-- base-spell bridges -- the SAME set _AC.Build feeds the engine's include map,
-- so whichever form the real aura carries is covered. Only one aura instance
-- ever exists per application, so extra forms cannot double-fire.
local function CollectForms(sid, out)
    out[1], out[2], out[3] = sid, nil, nil
    local n = 1
    local ovr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
        and C_SpellBook.FindSpellOverrideByID(sid)
    if ovr and ovr > 0 and ovr ~= sid then n = n + 1; out[n] = ovr end
    local base = C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(sid)
    if base and base > 0 and base ~= sid and base ~= ovr then n = n + 1; out[n] = base end
    return n
end

-- Desired registrations from the CURRENT profile. Mirrors the eligibility loop
-- of UpdateCustomBuffAuraTracking exactly: enabled custom_buff/buffs bars,
-- assignedSpells entries tagged in customSpellIDs with no stored duration.
-- Settings resolve through the same nil-frame ResolveSpellSettings the preset
-- gain path uses (per-spell tier shadows bar tier; explicit false and "none"
-- read as silent). First bar wins per sid, matching the preset throttle.
local formsScratch = {}
local function CollectDesired()
    local desired = {}
    local p = ns.ECME and ns.ECME.db and ns.ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    if not bars then return desired end
    local seenSid = {}
    for _, bd in ipairs(bars) do
        if bd.enabled and (bd.barType == "custom_buff" or bd.barType == "buffs") then
            local sd = ns.GetBarSpellData and ns.GetBarSpellData(bd.key)
            local list = sd and sd.assignedSpells
            local tags = sd and sd.customSpellIDs
            if list and tags then
                local durs = sd.spellDurations
                for _, sid in ipairs(list) do
                    if type(sid) == "number" and sid > 0 and tags[sid]
                       and (not durs or (durs[sid] or 0) <= 0)
                       and not seenSid[sid] then
                        seenSid[sid] = true
                        local ss = ns.ResolveSpellSettings
                            and ns.ResolveSpellSettings(nil, sid, sd, bd.key)
                        local gain = ss and ss.buffActiveSoundKey
                        local loss = ss and ss.buffLostSoundKey
                        if gain == "none" or gain == false then gain = nil end
                        if loss == "none" or loss == false then loss = nil end
                        if gain or loss then
                            local n = CollectForms(sid, formsScratch)
                            for i = 1, n do
                                local f = formsScratch[i]
                                if gain then
                                    desired[f .. ":" .. TRIG_ADDED] =
                                        { key = gain, owner = sid, form = f, trigger = TRIG_ADDED }
                                end
                                if loss then
                                    desired[f .. ":" .. TRIG_REMOVED] =
                                        { key = loss, owner = sid, form = f, trigger = TRIG_REMOVED }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return desired
end

local ArmRegenRetry -- forward (defined with its event frame below)

local function Flush()
    _syncQueued = false
    -- The API's ancestor was combat-locked; assume the same and retry on regen.
    if InCombatLockdown() then
        DBG("deferred: in combat")
        ArmRegenRetry()
        return
    end
    -- Login/zone settle: aura state is transient and registrations landed here
    -- could catch the re-apply burst. Same gate every CDM sound edge consults.
    if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then
        DBG("deferred: load settle")
        C_Timer.After(2.6, function() ns.QueueCustomAuraSoundSync() end)
        return
    end
    local desired = CollectDesired()
    -- Stale or re-keyed registrations out first (a changed key re-adds below).
    for rk, reg in pairs(_regs) do
        local want = desired[rk]
        if not want or want.key ~= reg.key then
            DropReg(rk, reg)
        end
    end
    -- Missing registrations in.
    local failed = false
    for rk, want in pairs(desired) do
        if not _regs[rk] then
            local paths = ns.FOCUSKICK_SOUND_PATHS
            local path = paths and paths[want.key]
            if path then
                local info = { unitToken = "player", spellID = want.form, outputChannel = "Master" }
                if type(path) == "number" then info.soundFileID = path
                else info.soundFileName = path end
                local ok, id = pcall(AddSound, want.trigger, info)
                if ok and id then
                    _regs[rk] = { id = id, key = want.key, owner = want.owner,
                                  forms = { want.form } }
                    _liveForm[want.form] = (_liveForm[want.form] or 0) + 1
                    DBG("registered", rk, "key=" .. want.key, "id=" .. tostring(id))
                else
                    failed = true
                    DBG("FAILED", rk, "key=" .. want.key,
                        ok and "nil return" or ("error: " .. tostring(id)))
                end
            end
        end
    end
    -- A failed add is most plausibly a combat/instance restriction race: retry
    -- on regen; every natural sync (rebuilds, zone-ins) retries too. No timer
    -- loop -- a persistently failing registration must not spin.
    if failed then ArmRegenRetry() end
end

function ns.QueueCustomAuraSoundSync()
    if _syncQueued then return end
    _syncQueued = true
    C_Timer.After(0, Flush)
end

local regenFrame = CreateFrame("Frame")
regenFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    _regenArmed = false
    ns.QueueCustomAuraSoundSync()
end)
ArmRegenRetry = function()
    if _regenArmed then return end
    _regenArmed = true
    regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Zone/login boundary: buffs re-apply behind the loading screen and the client
-- would cue every one of them. Tear down before the burst, re-sync after --
-- PLAYER_ENTERING_WORLD lands inside the settle window, so the flush's
-- suppressed branch delays the actual re-registration past it.
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("LOADING_SCREEN_ENABLED")
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loadFrame:SetScript("OnEvent", function(_, event)
    if event == "LOADING_SCREEN_ENABLED" then
        if next(_regs) then
            DBG("loading screen: tearing down all registrations")
            for _, reg in pairs(_regs) do pcall(RemoveSound, reg.id) end
            wipe(_regs)
            wipe(_liveForm)
        end
    else
        ns.QueueCustomAuraSoundSync()
    end
end)

-- Chat-reachable debug helpers (ns is addon-private, so these ride the shared
-- EllesmereUI table; zero cost unless called):
--   /run EllesmereUI.DumpCdmAuraSounds()
--   /run EllesmereUI.CdmAuraSoundDebug(true)   -- verbose register/defer prints
function ns.DumpAuraSoundRegs()
    local n = 0
    for rk, reg in pairs(_regs) do
        n = n + 1
        print(("EUI CDM aura-sound %s: key=%s id=%s owner=%d")
            :format(rk, tostring(reg.key), tostring(reg.id), reg.owner))
    end
    print("EUI CDM aura-sound: " .. n .. " registration(s) live"
        .. (_syncQueued and " (sync pending)" or "")
        .. (_regenArmed and " (regen retry armed)" or ""))
end
EllesmereUI.DumpCdmAuraSounds = ns.DumpAuraSoundRegs
EllesmereUI.CdmAuraSoundDebug = function(on)
    ns._auraSoundDebug = on and true or nil
    print("EUI CDM aura-sound debug " .. (on and "ON" or "OFF"))
end
