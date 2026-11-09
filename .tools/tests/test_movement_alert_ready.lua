-- Stub harness: loads the Movement Alert file outside the game and plays the
-- WoW Forever wand case. Each wand shot puts Blink, which is ready, in a short
-- window the check cannot tell from a cooldown (readable while no base cooldown
-- is known, or secret); when the window ends Blink drops out of the shown set.
-- The "ready" sound must fire only for a cooldown the player started: a cast of
-- the spell, or a readable cooldown of a real length.
--   python run_with_file.py <repo> .tools/tests/test_movement_alert_ready.lua [file]
-- (real Lua 5.1 through lupa; arg[2] picks another copy of the file under test)
local ROOT = arg and arg[1] or "."
local FILE = arg and arg[2] or "EllesmereUIQoL/EllesmereUIQoL_MovementAlert.lua"

local function ReadSource(name)
    local f = assert(io.open(name:find("^%a:") and name or (ROOT .. "/" .. name), "rb"))
    local src = f:read("*a")
    f:close()
    if src:sub(1, 3) == "\239\187\191" then src = src:sub(4) end
    return src
end
local SRC = ReadSource(FILE)

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local BLINK, SHOOT = 1953, 5019

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = DeepCopy(v) end
    return out
end

local function Load(opts)
    opts = opts or {}
    local T = { now = 100, sounds = 0, frames = {}, timers = {}, inCombat = false,
                cd = { start = 0, dur = 0, secret = false } }
    local cd = T.cd
    local noop = function() end

    -- Frames: methods by name, a few with state; Create* makes another stub.
    local META
    local function New(name, parent)
        return setmetatable({ _s = {}, _ev = {}, _shown = true, _alpha = 1, _name = name, _parent = parent }, META)
    end
    local METHODS = {
        SetScript = function(self, name, fn) self._s[name] = fn end,
        GetScript = function(self, name) return self._s[name] end,
        HookScript = function(self, name, fn)
            local old = self._s[name]
            self._s[name] = old and function(...) old(...); fn(...) end or fn
        end,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        SetShown = function(self, v) self._shown = v and true or false end,
        IsShown = function(self) return self._shown end,
        IsVisible = function(self) return self._shown end,
        SetAlpha = function(self, a) self._alpha = a end,
        GetAlpha = function(self) return self._alpha end,
        RegisterEvent = function(self, ev)
            self._ev[ev] = true
            if ev == "PLAYER_LOGIN" and not T.loader then T.loader = self end
        end,
        UnregisterEvent = function(self, ev) self._ev[ev] = nil end,
        RegisterUnitEvent = function(self, ev) self._ev[ev] = true end,
        IsEventRegistered = function(self, ev) return self._ev[ev] == true end,
        GetFrameLevel = function() return 1 end,
        GetFrameStrata = function() return "MEDIUM" end,
        GetWidth = function() return 0 end,
        GetHeight = function() return 0 end,
        GetSize = function() return 0, 0 end,
        GetStringWidth = function() return 0 end,
        GetStringHeight = function() return 0 end,
        GetEffectiveScale = function() return 1 end,
        GetScale = function() return 1 end,
        GetNumPoints = function() return 0 end,
        GetText = function(self) return self._text end,
        SetText = function(self, t) self._text = t end,
        SetFormattedText = function(self, fmt) self._text = fmt end,
        GetParent = function(self) return self._parent end,
        GetName = function(self) return self._name end,
        GetObjectType = function() return "Frame" end,
        GetFont = function() return "font", 12, "" end,
    }
    local CREATE = function(self) return New(nil, self) end
    META = {
        __index = function(_, k)
            local m = METHODS[k]
            if m then return m end
            if type(k) == "string" and k:sub(1, 6) == "Create" then return CREATE end
            -- Unknown widget methods do nothing; unknown fields stay nil.
            if type(k) == "string" and k:find("^%u") then return noop end
            return nil
        end,
    }

    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.EUI_CLIENT_BLOCKED = nil
    env.issecretvalue = function(v) return v == SECRET end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.GetTime = function() return T.now end
    env.UnitClass = function() return "Mage", "MAGE", 8 end
    env.UnitAffectingCombat = function() return T.inCombat end
    env.InCombatLockdown = function() return T.inCombat end
    env.UnitInVehicle = function() return false end
    env.UnitCanAssist = function() return true end
    env.IsPlayerSpell = function(id) return id == BLINK end
    env.GetSpellBaseCooldown = opts.baseCooldown and function(id) return id == BLINK and 15000 or 0 end or nil
    env.PlaySound = function() T.sounds = T.sounds + 1 end
    env.PlaySoundFile = function() T.sounds = T.sounds + 1 end
    env.RAID_CLASS_COLORS = {}
    env.C_Timer = {
        After = function(_, fn) T.timers[#T.timers + 1] = fn end,
        NewTimer = function() return { Cancel = noop } end,
        NewTicker = function() return { Cancel = noop } end,
    }
    env.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 62 end,
    }
    env.C_SpellBook = { IsSpellKnown = function(id) return id == BLINK end }
    env.C_CurveUtil = { CreateCurve = function() return { SetType = noop, AddPoint = noop } end }
    env.Enum = { LuaCurveType = { Step = 1 } }

    -- Blink's cooldown as the client reports it OUTSIDE a SPELL_UPDATE_COOLDOWN
    -- response: isOnGCD clear whatever the window is.
    local function Rem() return math.max(0, cd.start + cd.dur - T.now) end
    local function Live() return cd.dur > 0 and Rem() > 0 end
    local function Duration()
        return {
            GetRemainingDuration = function() if cd.secret then return SECRET end return Live() and Rem() or 0 end,
            GetTotalDuration = function() if cd.secret then return SECRET end return Live() and cd.dur or 0 end,
            GetStartTime = function() if cd.secret then return SECRET end return Live() and cd.start or 0 end,
            GetModRate = function() return 1 end,
            EvaluateTotalDuration = function(_, _, default)
                if cd.secret then return SECRET end
                if not Live() then return default end
                return cd.dur >= 3 and 1 or 0
            end,
        }
    end
    env.C_Spell = {
        GetSpellCooldown = function(id)
            if id ~= BLINK then return nil end
            if cd.secret then
                return { startTime = SECRET, duration = SECRET, isEnabled = true, isActive = true, modRate = 1,
                         timeUntilEndOfStartRecovery = SECRET, isOnGCD = false }
            end
            local live = Live()
            return { startTime = live and cd.start or 0, duration = live and cd.dur or 0, isEnabled = true,
                     isActive = live, modRate = 1, timeUntilEndOfStartRecovery = 0, isOnGCD = false }
        end,
        GetSpellCooldownDuration = function(id) if id == BLINK then return Duration() end end,
        GetSpellCharges = function() return nil end,
        GetSpellChargeDuration = function() return nil end,
        GetOverrideSpell = function(id) return id end,
        GetSpellInfo = function(id) if id == BLINK then return { name = "Blink", iconID = 135736 } end end,
    }

    env.CreateFrame = function(_, name, parent)
        local o = New(name, parent)
        T.frames[#T.frames + 1] = o
        if name then env[name] = o end
        return o
    end
    env.CreateFont = function(name) return New(name) end
    env.UIParent = New("UIParent")

    local db = { profile = {} }
    env.EllesmereUI = {
        IS_FOREVER = true,
        IsSecret = function(v) return v ~= nil and env.issecretvalue(v) end,
        Lite = {
            NewDB = function(_, defaults)
                db.profile = DeepCopy(defaults.profile)
                db.ResetProfile = noop
                return db
            end,
        },
        BuildBarTextureTables = function() return {}, {}, {} end,
        AppendSharedMediaTextures = noop,
        GetFontPath = function() return "font" end,
        GetFontOutlineFlag = function() return "" end,
        ResolveTexturePath = function() return "texture" end,
        ForeverClassSpecIDs = function() return { 62, 63, 64 } end,
        _groupDeathSoundPaths = { horn = "Interface\\AddOns\\horn.ogg" },
    }

    local chunk = assert(loadstring(SRC, "=EllesmereUIQoL_MovementAlert.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUIQoL", {})

    local ma = db.profile.movementAlert
    ma.enabledClasses = { MAGE = true }
    ma.maSoundKey = "horn"
    ma.combatOnly = opts.combatOnly or false
    T.env, T.ma = env, ma
    return T
end

local function Event(T, event, ...)
    local handler = T.loader:GetScript("OnEvent")
    handler(T.loader, event, ...)
end
-- One game frame: every shown frame's OnUpdate, three times so a repaint that
-- asks for a check gets it.
local function Frames(T)
    for _ = 1, 3 do
        for _, f in ipairs(T.frames) do
            local fn = f._s.OnUpdate
            if fn and f._shown then fn(f, 0.016) end
        end
    end
end
local function Login(T)
    Event(T, "PLAYER_LOGIN")
    local list = T.timers
    T.timers = {}
    for i = 1, #list do list[i]() end
    Frames(T)
    T.now = T.now + 3   -- past the cast guard after the login cache reset
end
local function Combat(T, on)
    T.inCombat = on
    Event(T, on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    Frames(T)
end
-- A wand shot: Blink, ready, sits in a 1.5 s window, then reads ready again.
local function WandShot(T, secret)
    local cd = T.cd
    cd.start, cd.dur, cd.secret = T.now, 1.5, secret and true or false
    Event(T, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-wand", SHOOT)
    Event(T, "SPELL_UPDATE_COOLDOWN")
    Frames(T)
    T.now = T.now + 1.6
    cd.start, cd.dur, cd.secret = 0, 0, false
    Event(T, "SPELL_UPDATE_COOLDOWN")
    Frames(T)
end
local function CastBlink(T, secret)
    local cd = T.cd
    cd.start, cd.dur, cd.secret = T.now, 15, secret and true or false
    Event(T, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-blink", BLINK)
    Event(T, "SPELL_UPDATE_COOLDOWN")
    Frames(T)
end
local function BlinkReady(T)
    local cd = T.cd
    T.now = cd.start + cd.dur + 0.1
    cd.start, cd.dur, cd.secret = 0, 0, false
    Event(T, "SPELL_UPDATE_COOLDOWN")
    Frames(T)
end

local fails = 0
local function Expect(name, got, want)
    if got ~= want then
        fails = fails + 1
        print(("FAIL: %s: %d sound(s), expected %d"):format(name, got, want))
    end
end

-- 1. Wand shots while Blink is ready, the window readable and no base cooldown
--    known (the client gives none): no sound.
do
    local T = Load()
    Login(T)
    Combat(T, true)
    for _ = 1, 5 do WandShot(T, false) end
    Expect("wand shots, readable window, no base cooldown", T.sounds, 0)
end

-- 2. The same with the window secret: no sound.
do
    local T = Load({ baseCooldown = true })
    Login(T)
    Combat(T, true)
    for _ = 1, 5 do WandShot(T, true) end
    Expect("wand shots, secret window", T.sounds, 0)
end

-- 3. Blink cast: one sound when it is back, none for the wand shots after.
do
    local T = Load({ baseCooldown = true })
    Login(T)
    Combat(T, true)
    CastBlink(T, false)
    BlinkReady(T)
    Expect("Blink cast, readable cooldown", T.sounds, 1)
    for _ = 1, 3 do WandShot(T, true) end
    Expect("wand shots after Blink is back", T.sounds, 1)
end

-- 4. Blink cast with the cooldown secret: the cast arms the sound.
do
    local T = Load({ baseCooldown = true })
    Login(T)
    Combat(T, true)
    CastBlink(T, true)
    BlinkReady(T)
    Expect("Blink cast, secret cooldown", T.sounds, 1)
end

-- 5. A cooldown already running at login (a /reload): its readable length arms it.
do
    local T = Load({ baseCooldown = true })
    T.cd.start, T.cd.dur = T.now - 5, 15
    Login(T)
    BlinkReady(T)
    Expect("cooldown running at login", T.sounds, 1)
end

-- 6. Combat Only: Blink cast and back out of combat, then wand shots in combat
--    with a secret window: no sound (the stale arm is dropped).
do
    local T = Load({ baseCooldown = true, combatOnly = true })
    Login(T)
    CastBlink(T, false)
    BlinkReady(T)
    Combat(T, true)
    for _ = 1, 3 do WandShot(T, true) end
    Expect("Combat Only, Blink back before combat", T.sounds, 0)
end

-- 7. Combat Only: Blink cast before combat and back during it: one sound.
do
    local T = Load({ baseCooldown = true, combatOnly = true })
    Login(T)
    CastBlink(T, false)
    T.now = T.now + 5
    Combat(T, true)
    BlinkReady(T)
    Expect("Combat Only, Blink back in combat", T.sounds, 1)
end

print(fails == 0 and "movement alert ready sound harness: ok"
    or ("movement alert ready sound harness: " .. fails .. " failure(s)"))
