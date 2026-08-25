if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_MovementAlert.lua
--  Three independent on-screen trackers for class mobility abilities:
--    1. Movement Cooldown Alert -- shows the current spec's mobility spell(s)
--       counting down on cooldown (text / icon / bar), so you always know
--       exactly when your gap-closer/escape is back up.
--    2. Time Spiral -- flashes a "FREE MOVEMENT" banner whenever a tracked
--       mobility spell's cooldown is proc-reset (Blizzard's generic
--       "spell activation overlay glow" on a spell we're tracking). A second,
--       CDM-bar based implementation of the same proc also exists as the
--       "timespiral" Tracked Buff Bar preset in
--       EllesmereUICooldownManager\EllesmereUICdmBuffBars.lua (~line 3590,
--       TIME_SPIRAL_TRIGGERS/TIME_SPIRAL_GLOW_FILTERS) for users who run CDM
--       bars. The two are intentionally independent (this one needs no CDM
--       bar at all), but they track the same spell/talent-filter lists --
--       keep both in sync if either list changes.
--    3. Gateway Shard -- Warlock only. Alerts when the Gateway Control Shard
--       item is usable.
--  Sits under EllesmereUIQoLDB.profile.movementAlert, an additive sibling of
--  battleRes/bloodlust/cursor (see EllesmereUIQoL_BattleRes.lua). Zero cost
--  when idle: no combat/spell events are registered until a tracker's master
--  toggle is on.
-------------------------------------------------------------------------------

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- Secret values throw on any comparison (==, <, ...) once execution is
-- tainted, so route a payload field through this before comparing it.
local function PlainValue(value)
    if IsSecret(value) then return nil end
    return value
end

local inCombat = false
local playerClassToken = select(2, UnitClass("player")) -- class never changes: resolved once

-------------------------------------------------------------------------------
--  Mobility spell tables
--  spellID lists are keyed by class -> specID. These are the actual ability
--  IDs and WILL drift as talents/expansions change -- validate against the
--  live client before shipping and keep an eye on the in-options "Tracked
--  Spells" add/override list, which lets users self-correct gaps without an
--  addon update. The `filter` sub-table (Time Spiral cast filtering) mirrors
--  EllesmereUICdmBuffBars.lua's TIME_SPIRAL_GLOW_FILTERS -- keep both in sync.
-------------------------------------------------------------------------------
local MOVEMENT_ABILITIES = {
    DEATHKNIGHT = {[250] = {48265, 212552}, [251] = {48265, 212552}, [252] = {48265, 444010, 444347, 212552}},
    DEMONHUNTER = {
        [577] = {195072}, [581] = {189110}, [1480] = {1234796},
        filter = {
            [427640] = {198793, 370965, 195072},
            [427794] = {195072},
        },
    },
    DRUID = {[102] = {102401, 252216, 1850, 102417}, [103] = {102401, 252216, 1850, 102417}, [104] = {102401, 252216, 106898, 1850, 102417}, [105] = {102401, 252216, 1850, 102417}},
    EVOKER = {[1467] = {358267}, [1468] = {358267}, [1473] = {358267}},
    HUNTER = {[253] = {186257, 781}, [254] = {186257, 781}, [255] = {186257, 781}},
    MAGE = {[62] = {212653, 1953}, [63] = {212653, 1953}, [64] = {212653, 1953}},
    MONK = {[268] = {115008, 109132, 119085, 361138}, [269] = {109132, 119085, 361138, 101545}, [270] = {109132, 119085, 361138}},
    PALADIN = {[65] = {190784}, [66] = {190784}, [70] = {190784}},
    PRIEST = {[256] = {121536, 73325}, [257] = {121536, 73325}, [258] = {121536, 73325}},
    ROGUE = {[259] = {36554, 2983}, [260] = {195457, 2983}, [261] = {36554, 2983}},
    SHAMAN = {[262] = {79206, 90328, 192063, 58875}, [263] = {90328, 192063, 58875}, [264] = {79206, 90328, 192063, 58875}},
    WARLOCK = {
        [265] = {48020, 111400}, [266] = {48020, 111400}, [267] = {48020, 111400},
        filter = {[385899] = {385899}},
    },
    WARRIOR = {[71] = {6544}, [72] = {6544}, [73] = {6544}},
}

-- Buff-active spells: the label shown while the aura is up, in place of a
-- cooldown countdown. Membership here decides HOW a spell is tracked, never
-- whether it is on -- Burning Rush ships unchecked via MOVEMENT_DEFAULT_OFF
-- below. It has no cooldown and no duration to count down, so the presence of
-- its aura is the only thing there is to track.
local BUFF_ACTIVE_SPELLS = {
    [111400] = "Burning Rush Active!",
}

local SPELL_ALIAS_GROUPS = {
    {102401, 16979, 102417, 252216},
    {106898, 77761, 77764},
}

local SPELL_CATEGORY_DURATION = {
    [102401] = 15, [16979] = 15, [102417] = 15, [252216] = 15,
    [1850] = 18,
    [106898] = 120, [77761] = 120,
}

local TALENT_CD_REDUCTIONS = {
    { talent = 451041, trigger = 116841, spell = 109132, reduce = 5 },
    { talent = 451041, trigger = 116841, spell = 115008, reduce = 5 },
}
local TALENT_CD_TRIGGER_SPELLS = {}
for _, mod in ipairs(TALENT_CD_REDUCTIONS) do
    TALENT_CD_TRIGGER_SPELLS[mod.trigger] = true
end

EllesmereUI.MOVEMENT_ABILITIES = MOVEMENT_ABILITIES

-- Preset spells that default to DISABLED: with no saved override, these are
-- not tracked (checking their box writes an explicit enabled=true override;
-- everything else stays enabled-by-absence). Shared with the options grid
-- via the export so the checkboxes and the tracker read the same truth.
local MOVEMENT_DEFAULT_OFF = {
    [2983]   = true,               -- Sprint
    [73325]  = true,               -- Leap of Faith
    [106898] = true, [77761] = true, [77764] = true, -- Stampeding Roar
    [1850]   = true,               -- Dash
    [252216] = true,               -- Tiger Dash
    [212552] = true,               -- Wraith Walk
    [79206]  = true,               -- Spiritwalker's Grace
    [58875]  = true, [90328] = true, -- Spirit Walk
    [111400] = true,               -- Burning Rush (off by default since 8.5.3)
}
EllesmereUI._MovementDefaultOff = MOVEMENT_DEFAULT_OFF

-- Effective enabled state for a preset/tracked spell id: an explicit saved
-- enabled wins; otherwise absence means enabled unless default-off.
local function SpellEffectivelyEnabled(override, spellId)
    if override and override.enabled ~= nil then
        return override.enabled ~= false
    end
    return not MOVEMENT_DEFAULT_OFF[spellId]
end

local SPELL_ALIAS_MAP = {}
do
    for _, group in ipairs(SPELL_ALIAS_GROUPS) do
        for _, id in ipairs(group) do SPELL_ALIAS_MAP[id] = group end
        for _, id in ipairs(group) do
            if not SPELL_CATEGORY_DURATION[id] then
                for _, other in ipairs(group) do
                    if SPELL_CATEGORY_DURATION[other] then
                        SPELL_CATEGORY_DURATION[id] = SPELL_CATEGORY_DURATION[other]
                        break
                    end
                end
            end
        end
    end
end

local function GetKnownCategoryDuration(spellId)
    if SPELL_CATEGORY_DURATION[spellId] then return SPELL_CATEGORY_DURATION[spellId] end
    local group = SPELL_ALIAS_MAP[spellId]
    if group then
        for _, id in ipairs(group) do
            if SPELL_CATEGORY_DURATION[id] then return SPELL_CATEGORY_DURATION[id] end
        end
    end
    return 0
end

-- Shared lockout vs. the ability's own cooldown. Casting one charge-type
-- ability briefly locks out its siblings through a start-recovery/cooldown
-- category -- Druid Skull Bash does this to Wild Charge for ~2s -- and the
-- client reports that window through the very same cooldown fields a real
-- cooldown uses, with isOnGCD false, so the GCD gate above it never catches
-- it. The discriminator is magnitude: a window far shorter than the ability's
-- own base cooldown cannot BE that cooldown, so it is not something to alert
-- on. Blizzard classifies the same way in Blizzard_CooldownViewer
-- (MIN_GLOBAL_RECOVERY_TIME), just at GCD length. Gated on the base cooldown
-- being the longer of the two, so a user-added spell that genuinely has a
-- 1-2s cooldown still tracks normally.
local MIN_REAL_COOLDOWN = 3

-- entry.baseDuration is learned from LIVE cooldown reads, and those are secret in
-- instanced content, so an entry first cached there carries no base at all. That
-- disabled the classifier below exactly where the lockout is most visible: in
-- combat. Static spell data is not live cooldown state and stays readable, so
-- fall back to it rather than treating an unknown base as "cannot classify".
-- GetSpellBaseCooldown is the GLOBAL (client-verified: no C_Spell form exists).
local function ResolveBaseDuration(entry)
    local base = entry and entry.baseDuration
    if type(base) == "number" and not IsSecret(base) then return base end
    local id = entry and (entry.baseSpellId or entry.spellId)
    if not id then return 0 end
    if GetSpellBaseCooldown then
        local ms = GetSpellBaseCooldown(id)
        if type(ms) == "number" and not IsSecret(ms) then
            local secs = ms / 1000
            if secs > MIN_REAL_COOLDOWN then return secs end
        end
    end
    return GetKnownCategoryDuration(id)
end

local function IsLockoutWindow(entry, seconds)
    if type(seconds) ~= "number" or IsSecret(seconds) then return false end
    local base = ResolveBaseDuration(entry)
    if type(base) ~= "number" or base <= MIN_REAL_COOLDOWN then return false end
    return seconds < MIN_REAL_COOLDOWN
end

-- The same classification when the window is SECRET, which is the case Lua cannot
-- do at all: IsLockoutWindow refuses a secret and lets it through, so in instanced
-- content the lockout reached the display with a number on it. Hand the comparison
-- to the engine instead, with the curve trick the charge-visibility path already
-- uses: a step curve is 0 below the threshold and 1 above, the duration object
-- evaluates it in C, and the result drives alpha. Never read the result, only feed it.
local lockoutAlphaCurve = nil   -- nil = not built, false = API unavailable
local function GetLockoutAlphaCurve()
    if lockoutAlphaCurve == nil then
        if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, 0)                   -- cross-ability lockout: hide
            c:AddPoint(MIN_REAL_COOLDOWN, 1)   -- the ability's own cooldown: show
            lockoutAlphaCurve = c
        else
            lockoutAlphaCurve = false
        end
    end
    return lockoutAlphaCurve or nil
end

-- 1, or a possibly-secret 0/1 from the engine. Gated on the entry's own base being
-- the longer of the two, so a user-added spell with a genuine 1-2s cooldown still
-- tracks normally -- the same condition IsLockoutWindow applies.
local function LockoutAlpha(entry, duration)
    if not duration or not duration.EvaluateTotalDuration then return 1 end
    local base = ResolveBaseDuration(entry)
    if type(base) ~= "number" or base <= MIN_REAL_COOLDOWN then return 1 end
    local curve = GetLockoutAlphaCurve()
    if not curve then return 1 end
    return duration:EvaluateTotalDuration(curve, 1) or 1
end

-------------------------------------------------------------------------------
--  DB
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        movementAlert = {
            -- nil = feature fully disabled (zero cost); { WARRIOR = true, ... }
            -- = enabled while playing a checked class (Totem Bar convention).
            enabledClasses   = nil,
            combatOnly       = false,
            -- text_nd = "Name Duration", text_dn = "Duration Name"; the
            -- legacy "text" value renders identically to text_dn.
            displayMode      = "text",   -- text (legacy) | text_nd | text_dn | text_d (number only) | icon | bar
            textSize         = 24,
            iconSize         = 40,
            textColorR       = 1, textColorG = 1, textColorB = 1,
            textColorUseClass = false,
            barShowIcon      = true,
            barShowDuration  = true,     -- bar mode's countdown number
            barTexture       = "none",   -- key into the bar texture catalog
            precision        = 1,
            spellOverrides   = {},        -- [spellId] = { enabled, customText, class }
            pos              = nil,       -- { point, relPoint, x, y, width, height }
            maSoundKey       = "none",   -- EllesmereUI._groupDeathSoundPaths key
            maTtsEnabled     = false,   -- takes priority over maSoundKey when on; speaks the ability name once when it comes off cooldown
            maTtsVoiceID     = 0,
            maTtsVolume      = 100,

            tsEnabled        = false,
            tsTextFormat     = "FREE MOVEMENT\\n%.1f",
            tsColorR         = 0.53, tsColorG = 1, tsColorB = 0,
            tsColorUseClass  = false,
            tsSoundKey       = "none",   -- EllesmereUI._groupDeathSoundPaths key
            tsTtsEnabled     = false,   -- takes priority over tsSoundKey when on
            tsTtsVoiceID     = 0,
            tsTtsMessage     = "Free movement",
            tsTtsVolume      = 100,
            tsPos            = nil,

            gwEnabled        = false,
            gwCombatOnly     = false,
            gwText           = "GATEWAY READY",
            gwColorR         = 0.7, gwColorG = 0, gwColorB = 1,
            gwColorUseClass  = false,
            gwSoundKey       = "none",   -- EllesmereUI._groupDeathSoundPaths key
            gwTtsEnabled     = false,   -- takes priority over gwSoundKey when on
            gwTtsVoiceID     = 0,
            gwTtsMessage     = "Gateway ready",
            gwTtsVolume      = 100,
            gwPos            = nil,
        },
    },
}

local db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", defaults)
local function MA() return db.profile.movementAlert end

-- Movement Cooldown Alert enable state: enabledClasses is a per-class
-- checkbox set (nil = nothing checked = fully disabled). Everything at
-- runtime keys off the PLAYER's class -- a character whose class is
-- unchecked pays exactly the same zero cost as the feature being off.
local function MovementEnabled()
    local ma = MA()
    local ec = ma and ma.enabledClasses
    if not ec then return false end
    return ec[playerClassToken] == true
end
_G._EUI_MovementAlert_DB = function() return db end
EllesmereUI._ResetMovementAlert = function()
    db:ResetProfile()
    if EllesmereUI._RebuildMovementSpellLookup then EllesmereUI._RebuildMovementSpellLookup() end
    if EllesmereUI._CacheMovementSpells then EllesmereUI._CacheMovementSpells(true) end
    if EllesmereUI._UpdateMovementAlertEvents then EllesmereUI._UpdateMovementAlertEvents() end
    if EllesmereUI._applyMovementAlert then EllesmereUI._applyMovementAlert() end
    if EllesmereUI._applyTimeSpiral then EllesmereUI._applyTimeSpiral() end
    if EllesmereUI._applyGateway then EllesmereUI._applyGateway() end
    -- Explicit self-correct: ApplyMovementFrame/CheckGatewayUsable only hide
    -- an actively-displayed frame when their own tracker is enabled, which
    -- ResetProfile() just turned off -- without these, a frame that was
    -- showing at reset-time stays frozen on screen.
    if EllesmereUI._CheckMovementCooldown then EllesmereUI._CheckMovementCooldown() end
    if EllesmereUI._CheckGatewayUsable then EllesmereUI._CheckGatewayUsable() end
end

-------------------------------------------------------------------------------
--  Font / color helpers -- reuses the shared "extras" font/outline settings
--  (same category Combat Alert uses) instead of a dedicated per-feature font
--  picker, and the shared Group Death sound list instead of building a new
--  sound/TTS system.
-------------------------------------------------------------------------------
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local function AlertFontPath()
    return (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or FALLBACK_FONT
end
local function AlertFontOutline()
    local o = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("extras")) or ""
    if not o:find("OUTLINE") then o = (o == "") and "OUTLINE" or (o .. ", OUTLINE") end
    return o
end
local function ResolveAlertColor(prefix, useClassKey)
    local ma = MA()
    if ma[useClassKey] then
        local _, classToken = UnitClass("player")
        local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        if c then return c.r, c.g, c.b end
    end
    return ma[prefix .. "R"] or 1, ma[prefix .. "G"] or 1, ma[prefix .. "B"] or 1
end
-- LSM "sound" entries are either a file path (string) or a Blizzard
-- SoundKitID (number -- most of the built-in SOUNDKIT.* entries other addons
-- register use this). PlaySoundFile only understands the former, so route by
-- type. Shared with EUI_QoL_MovementAlert_Options.lua's preview button via
-- EllesmereUI._PlayLSMSound so both play a given LSM value identically.
local function PlayLSMSound(value)
    if not value or value == 1 then return end
    if type(value) == "number" then
        PlaySound(value, "Master")
    else
        PlaySoundFile(value, "Master")
    end
end
EllesmereUI._PlayLSMSound = PlayLSMSound

-- Resolves through EllesmereUI._groupDeathSoundPaths -- the addon's existing
-- sound-list table (curated built-ins + every LibSharedMedia "sound" entry,
-- merged in once at login by EllesmereUI.AppendSharedMediaSounds). Reuses
-- that instead of querying LSM directly a second time, so there's one sound
-- list/preview implementation in the addon, not two.
local function PlayAlertSound(key)
    if not key or key == "none" then return end
    local value = EllesmereUI._groupDeathSoundPaths and EllesmereUI._groupDeathSoundPaths[key]
    if value then PlayLSMSound(value) end
end

-- Text-to-speech: local-only playback via C_VoiceChat. The live-client
-- argument order is (voiceID, text, destination, volume, interrupt), NOT
-- (voiceID, text, destination, rate, volume) as older API docs suggest.
-- Enum.VoiceTtsDestination doesn't exist on live clients either, so
-- destination is the literal 1 (local playback). Silently no-ops if TTS
-- isn't available instead of erroring.
local function SpeakAlertText(voiceId, text, volume)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return end
    if not text or text == "" then return end
    pcall(C_VoiceChat.SpeakText, voiceId or 0, text, 1, volume or 100, true)
end

-- Fires TTS if enabled for this tracker (prefix "ts"/"gw"/"ma"), otherwise
-- falls back to the tracker's configured sound. TTS always wins when both
-- are configured -- keeps the two controls from fighting over which one
-- plays. abilityName, if given, substitutes "%a" in the TTS message (used by
-- the Movement Cooldown Alert's per-spell "ready" callout).
local function FireTrackerAlert(prefix, abilityName)
    local ma = MA()
    if ma[prefix .. "TtsEnabled"] then
        -- The Movement Cooldown Alert always speaks the ability name (or its
        -- per-spell Custom Text) -- there is no message setting for it. The
        -- other trackers speak their fixed configured message.
        local msg = abilityName or ma[prefix .. "TtsMessage"]
        SpeakAlertText(ma[prefix .. "TtsVoiceID"], msg, ma[prefix .. "TtsVolume"])
    else
        PlayAlertSound(ma[prefix .. "SoundKey"])
    end
end

-------------------------------------------------------------------------------
--  Movement Cooldown Alert display frame (pooled multi-slot: some specs
--  track more than one mobility spell, e.g. Druid across forms)
-------------------------------------------------------------------------------
local movementFrame = CreateFrame("Frame", "EUI_MovementAlertFrame", UIParent)
movementFrame:SetSize(200, 40)
movementFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
movementFrame:Hide()

-- Bar texture catalog: the same curated set the CDM Tracking Bars "Bar
-- Texture" dropdown uses (EllesmereUICooldownManager\EllesmereUICdmBuffBars.lua);
-- the options page appends SharedMedia statusbar textures into these tables.
-- Rendering resolves through ResolveTexturePath ("none" = flat WHITE8x8).
local BAR_TEXTURES, BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER =
    EllesmereUI.BuildBarTextureTables()
EllesmereUI._MovementBarTextures = {
    lookup = BAR_TEXTURES, order = BAR_TEXTURE_ORDER, names = BAR_TEXTURE_NAMES,
}

-- Named font object for the icon mode's cooldown countdown numbers --
-- SetCountdownFont takes the NAME of a named font object, and StyleSlot
-- re-points this one at the user's font/size.
local movementCdFont = CreateFont("EUI_MovementAlertCdFont")
-- A fresh font object has no font file; give it one immediately so text
-- attached to it can render before the first StyleSlot pass re-points it
-- at the user's font and size.
movementCdFont:SetFont(FALLBACK_FONT, 24, "OUTLINE")

local displayPool = {}
local activeSlotCount = 0
-- Tracks which tracked (non-buffActive) spellIDs were on cooldown as of the
-- last poll, so the "ready" TTS callout fires exactly once per cooldown
-- ending instead of every poll tick while the spell sits ready.
local readyAlertShown = {}
local readyAlertScratch = {} -- swapped with readyAlertShown each check: no per-check table

local function CreateDisplaySlot()
    local slot = CreateFrame("Frame", nil, movementFrame)
    slot:SetSize(200, 40)

    slot.text = slot:CreateFontString(nil, "OVERLAY")
    slot.text:SetPoint("CENTER")

    slot.icon = CreateFrame("Frame", nil, slot)
    slot.icon:SetSize(40, 40)
    slot.icon:SetPoint("CENTER")
    slot.icon.border = slot.icon:CreateTexture(nil, "BACKGROUND")
    slot.icon.border:SetAllPoints()
    slot.icon.border:SetColorTexture(0, 0, 0, 1)
    slot.icon.tex = slot.icon:CreateTexture(nil, "ARTWORK")
    slot.icon.tex:SetPoint("TOPLEFT", 2, -2)
    slot.icon.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.icon.cooldown = CreateFrame("Cooldown", nil, slot.icon, "CooldownFrameTemplate")
    slot.icon.cooldown:SetAllPoints(slot.icon.tex)
    slot.icon.cooldown:SetDrawEdge(false)
    if slot.icon.cooldown.SetCountdownFont then
        slot.icon.cooldown:SetCountdownFont("EUI_MovementAlertCdFont")
    end
    -- Own countdown text for icon mode: the poll drives this FontString for
    -- readable durations (our precision/decimal control); the engine numbers
    -- take over only for secret durations, which Lua cannot format (see the
    -- engine-countdown block below for the CVar posture).
    slot.icon.timeText = slot.icon.cooldown:CreateFontString(nil, "OVERLAY")
    slot.icon.timeText:SetFontObject(movementCdFont)
    slot.icon.timeText:SetPoint("CENTER")
    slot.icon.timeText:SetText("")
    slot.icon:Hide()

    -- Engine-drawn countdown for text modes. See ShowEngineCountdown.
    slot.cdNum = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.cdNum:SetDrawSwipe(false)
    slot.cdNum:SetDrawEdge(false)
    if slot.cdNum.SetDrawBling then slot.cdNum:SetDrawBling(false) end
    slot.cdNum:SetHideCountdownNumbers(false)
    if slot.cdNum.SetCountdownFont then
        slot.cdNum:SetCountdownFont("EUI_MovementAlertCdFont")
    end
    -- Blizzard suppresses countdown text on short cooldowns by default, which
    -- would silently drop the number on exactly the short mobility cooldowns
    -- this feature exists for.
    if slot.cdNum.SetMinimumCountdownDuration then
        slot.cdNum:SetMinimumCountdownDuration(0)
    end
    -- The engine exposes the FontString it draws into, so the number can be
    -- placed and sized against our own text instead of being inferred from the
    -- host frame's geometry (which is what made it render at a different size).
    if slot.cdNum.GetCountdownFontString then
        slot.cdNumText = slot.cdNum:GetCountdownFontString()
    end
    slot.cdNum:Hide()

    slot.bar = CreateFrame("StatusBar", nil, slot)
    slot.bar:SetSize(150, 20)
    slot.bar:SetPoint("CENTER")
    slot.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    slot.bar:SetMinMaxValues(0, 1)
    slot.bar:SetValue(0)
    slot.bar.bg = slot.bar:CreateTexture(nil, "BACKGROUND")
    slot.bar.bg:SetAllPoints()
    slot.bar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    slot.bar.text = slot.bar:CreateFontString(nil, "OVERLAY")
    slot.bar.text:SetPoint("CENTER")
    slot.bar.icon = slot.bar:CreateTexture(nil, "OVERLAY")
    slot.bar.icon:SetSize(20, 20)
    slot.bar.icon:SetPoint("RIGHT", slot.bar, "LEFT", -4, 0)
    slot.bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.bar:Hide()

    return slot
end

local function GetDisplaySlot(index)
    if not displayPool[index] then displayPool[index] = CreateDisplaySlot() end
    return displayPool[index]
end

local function LayoutDisplaySlots(count)
    local frameW, frameH = movementFrame:GetWidth(), movementFrame:GetHeight()
    for i = 1, count do
        local slot = displayPool[i]
        if slot then
            slot:ClearAllPoints()
            slot:SetSize(frameW, frameH)
            if i == 1 then
                slot:SetPoint("BOTTOM", movementFrame, "BOTTOM", 0, 0)
            else
                slot:SetPoint("BOTTOM", displayPool[i - 1], "TOP", 0, 2)
            end
        end
    end
end

local function StyleSlot(slot)
    local ma = MA()
    local fontPath, outline = AlertFontPath(), AlertFontOutline()
    local frameH, frameW = movementFrame:GetHeight(), movementFrame:GetWidth()
    local fontSize = math.max(8, math.min(72, ma.textSize or 24))
    local tR, tG, tB = ResolveAlertColor("textColor", "textColorUseClass")

    if not slot.text:SetFont(fontPath, fontSize, outline) then
        slot.text:SetFont(FALLBACK_FONT, fontSize, outline)
    end
    slot.text:SetTextColor(tR, tG, tB)
    slot.icon.timeText:SetTextColor(tR, tG, tB)
    -- Pin the engine's countdown FontString to the same font object and colour
    -- every pass: left alone it sizes itself against its host frame rather than
    -- the user's Text Size.
    if slot.cdNumText then
        slot.cdNumText:SetFontObject(movementCdFont)
        slot.cdNumText:SetTextColor(tR, tG, tB)
    end

    local barH = math.max(12, math.floor(frameH * 0.5))
    local barW = frameW - (ma.barShowIcon ~= false and (barH + 8) or 0) - 10
    slot.bar:SetSize(math.max(50, barW), barH)
    slot.bar.icon:SetSize(barH, barH)
    -- Text Size drives every mode's text: the free text, the bar's number,
    -- and (via the named countdown font) the icon's countdown numbers.
    -- Font-object SetFont has no success return; reuse the fontstring's
    -- validation to pick the path that actually loaded.
    if not slot.bar.text:SetFont(fontPath, fontSize, outline) then
        slot.bar.text:SetFont(FALLBACK_FONT, fontSize, outline)
        movementCdFont:SetFont(FALLBACK_FONT, fontSize, outline)
    else
        movementCdFont:SetFont(fontPath, fontSize, outline)
    end
    -- The engine draws its countdown numbers straight from this font object,
    -- so the colour has to live here too or the prototype's number ignores the
    -- user's Text Colour.
    movementCdFont:SetTextColor(tR, tG, tB)

    -- Bar texture (change-guarded: StyleSlot runs on every poll tick)
    local texPath = (EllesmereUI.ResolveTexturePath
        and EllesmereUI.ResolveTexturePath(BAR_TEXTURES, ma.barTexture or "none", "Interface\\Buttons\\WHITE8x8"))
        or "Interface\\Buttons\\WHITE8x8"
    if slot.bar._lastTexPath ~= texPath then
        slot.bar:SetStatusBarTexture(texPath)
        slot.bar._lastTexPath = texPath
    end

    local iconSz = math.max(16, math.min(128, ma.iconSize or 40))
    slot.icon:SetSize(iconSz, iconSz)
end

-------------------------------------------------------------------------------
--  Engine-drawn countdown for the text modes
--
--  A secret remaining cannot be formatted in Lua (that is the 0.0 bug), but
--  the ENGINE can draw it: a Cooldown widget handed the same duration object
--  renders the number itself, which is exactly why icon mode still counts down
--  in combat. Everything except the number is switched off here, so all this
--  widget contributes is text sitting beside the name.
--
--  CVar posture: Blizzard READS countdownForCooldowns and passes it into
--  SetHideCountdownNumbers for its own buttons (Blizzard_ActionBar/Shared/
--  ActionButton.lua) -- the CVar gates Blizzard's calls, not the widget
--  internals -- so forcing false here draws numbers regardless
--  (field-verified 8.7.8). If a client configuration exists where it does
--  not, the degradation is no number, same as before this path existed.
-------------------------------------------------------------------------------
-- The duration OBJECT is the only safe way to drive this. Cooldown:SetCooldown
-- is SecretArguments = "AllowedWhenUntainted", so handing it the secret start
-- and duration from the cdInfo path would error out of our own tainted ticker;
-- the object itself is not a secret value, so passing it is fine. When there is
-- no object there is simply no number, which is the same degradation as before.
local function BindEngineCountdown(cd, duration)
    if duration and cd.SetCooldownFromDurationObject then
        cd:SetCooldownFromDurationObject(duration)
        return true
    end
    return false
end

local function HideEngineCountdown(slot)
    if slot.cdNum then slot.cdNum:Hide() end
    -- ShowEngineCountdown slides the name off centre to make room for the
    -- number, so every render has to start from the plain centred layout or
    -- the offset accumulates across modes.
    if slot.text then
        slot.text:ClearAllPoints()
        slot.text:SetPoint("CENTER")
    end
end

local function ShowEngineCountdown(slot, displayMode, duration)
    local cd = slot.cdNum
    if not cd then return false end
    local ma = MA()
    local fontSize = math.max(8, math.min(72, ma.textSize or 24))
    -- Decimals: this is the engine's version of the Show Decimal toggle. Above
    -- the threshold it prints whole seconds, below it one decimal place, so
    -- "always" is a threshold past any cooldown and "never" is zero.
    local precision = ((tonumber(ma.precision) or 1) > 0) and 1 or 0
    if cd.SetCountdownMillisecondsThreshold then
        cd:SetCountdownMillisecondsThreshold(precision == 1 and 86400 or 0)
    end
    -- Blizzard abbreviates past two minutes by default, so a 90s cooldown would
    -- print "1:30" where every other path in this feature prints "90".
    if cd.SetCountdownAbbrevThreshold then
        cd:SetCountdownAbbrevThreshold(0)
    end
    -- Layout. The number is a separate object from the name, so the pair has to
    -- be centred as a unit: reserve a fixed width for the number and slide the
    -- name half of that the other way. The width is RESERVED rather than
    -- measured because the number's own width changes as it counts down
    -- (100.0 -> 9.9), and centring on a measured width would shuffle the name
    -- sideways on every tick.
    local gap = math.max(2, fontSize * 0.15)
    local reserved = fontSize * (precision == 1 and 2.4 or 1.6)
    local shift = (reserved + gap) / 2
    local numberFirst = (displayMode ~= "text_nd")
    -- text_d: no name at all, the number IS the text -- centre it on the slot.
    local numberOnly = (displayMode == "text_d")
    if numberOnly then shift = 0 end

    slot.text:ClearAllPoints()
    slot.text:SetPoint("CENTER", slot, "CENTER", numberFirst and shift or -shift, 0)

    -- Position the FontString itself when the engine hands it over, so the
    -- number matches our own text exactly; fall back to moving the host frame
    -- (whose centred number only approximates the same place) when it does not.
    cd:ClearAllPoints()
    local fs = slot.cdNumText
    if fs then
        cd:SetSize(1, 1)
        cd:SetPoint("CENTER", slot.text, "CENTER", 0, 0)
        fs:ClearAllPoints()
        -- No SetWidth: the anchor below already grows the digits outward, and a
        -- hard width clips five-glyph values like "120.0" (Stampeding Roar).
        -- reserved is only an estimate for the centring shift above.
        if numberOnly then
            fs:SetJustifyH("CENTER")
            fs:SetPoint("CENTER", slot.text, "CENTER", 0, 0)
        elseif numberFirst then
            fs:SetJustifyH("RIGHT")
            fs:SetPoint("RIGHT", slot.text, "LEFT", -gap, 0)
        else
            fs:SetJustifyH("LEFT")
            fs:SetPoint("LEFT", slot.text, "RIGHT", gap, 0)
        end
    else
        cd:SetSize(reserved, fontSize * 1.4)
        if numberOnly then
            cd:SetPoint("CENTER", slot.text, "CENTER", 0, 0)
        elseif numberFirst then
            cd:SetPoint("RIGHT", slot.text, "LEFT", -gap, 0)
        else
            cd:SetPoint("LEFT", slot.text, "RIGHT", gap, 0)
        end
    end
    if not BindEngineCountdown(cd, duration) then
        -- Nothing to drive the number with: undo the room made for it, or the
        -- name is left sitting off centre with an empty gap beside it.
        HideEngineCountdown(slot)
        return false
    end
    cd:Show()
    return true
end

-- Bar mode's number lives centred in the bar with no name beside it, so it
-- needs the binding but none of the two-object layout above.
local function ShowEngineCountdownCentred(slot, anchor, duration)
    local cd = slot.cdNum
    if not cd then return false end
    local ma = MA()
    local fontSize = math.max(8, math.min(72, ma.textSize or 24))
    local precision = ((tonumber(ma.precision) or 1) > 0) and 1 or 0
    if cd.SetCountdownMillisecondsThreshold then
        cd:SetCountdownMillisecondsThreshold(precision == 1 and 86400 or 0)
    end
    -- Blizzard abbreviates past two minutes by default, so a 90s cooldown would
    -- print "1:30" where every other path in this feature prints "90".
    if cd.SetCountdownAbbrevThreshold then
        cd:SetCountdownAbbrevThreshold(0)
    end
    cd:ClearAllPoints()
    -- The host frame is created before slot.bar, so without this the number is
    -- painted under the bar's background and fill and never appears.
    if anchor.GetFrameLevel then
        cd:SetFrameLevel(anchor:GetFrameLevel() + 5)
    end
    local fs = slot.cdNumText
    if fs then
        cd:SetSize(1, 1)
        cd:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        fs:ClearAllPoints()
        fs:SetWidth(0)
        fs:SetJustifyH("CENTER")
        fs:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        cd:SetSize(fontSize * 3, fontSize * 1.4)
        cd:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
    if not BindEngineCountdown(cd, duration) then
        cd:Hide()
        return false
    end
    cd:Show()
    return true
end

-------------------------------------------------------------------------------
--  Spell tracking core (charges, cooldowns, spec resolution)
-------------------------------------------------------------------------------
local knownChargeSpells = {}

local function SafeGetChargeInfo(spellId)
    local chargeInfo = C_Spell.GetSpellCharges(spellId)
    if not chargeInfo then
        local cached = knownChargeSpells[spellId]
        if cached then return true, cached.maxCh, cached.rechDur end
        return false, 1, 0
    end
    local m = chargeInfo.maxCharges or 1
    local r = chargeInfo.cooldownDuration or 0
    if IsSecret(m) or IsSecret(r) then
        local cached = knownChargeSpells[spellId]
        if cached then return true, cached.maxCh, cached.rechDur end
        return false, 1, 0
    end
    if m > 1 then
        knownChargeSpells[spellId] = { maxCh = m, rechDur = r }
        return true, m, r
    end
    local cached = knownChargeSpells[spellId]
    if cached then return true, cached.maxCh, cached.rechDur end
    return false, m, r
end

local function SafeGetBaseDuration(spellId)
    if C_Spell.GetSpellCooldownDuration then
        -- ignoreGCD: without it this reads the global cooldown whenever one is
        -- running, and the 1.5 floor below then throws the answer away.
        local dur = C_Spell.GetSpellCooldownDuration(spellId, true)
        if dur then
            local total = dur:GetTotalDuration()
            if not IsSecret(total) and total and total > 1.5 then return total end
        end
    end
    -- Global, not C_Spell (client-verified: no C_Spell form exists). Static
    -- spell data, so it stays readable when the live cooldown is secret.
    if GetSpellBaseCooldown then
        local ms = GetSpellBaseCooldown(spellId)
        if not IsSecret(ms) and ms and ms > 1500 then return ms / 1000 end
    end
    local cdInfo = C_Spell.GetSpellCooldown(spellId)
    if cdInfo and cdInfo.duration then
        local d = cdInfo.duration
        if not IsSecret(d) and d > 1.5 then return d end
    end
    return 0
end

local function ResolvePlayerSpecId()
    local spec = GetSpecialization()
    if not spec then return nil end
    local specId = select(1, GetSpecializationInfo(spec))
    if specId and specId > 0 then return specId end
    return nil
end

local cachedMovementSpells = {}
local cachedChargeCount = {}
local rechargeTimers = {}
local chargeRechargeStart = {}
local spellWasCast = {}
local spellCastTime = {}
local trackedSpellSet = {}
local cacheResetTime = 0
local movementCountdownTimer = nil
local movementPreviewTicker = nil -- options-panel preview loop (nil = off)
local CheckMovementCooldown
local CancelAllRechargeTimers

local function GetPlayerMovementSpells()
    local class = select(2, UnitClass("player"))
    local specId = ResolvePlayerSpecId()
    if not specId then return {} end

    local overrides = MA().spellOverrides or {}
    local classAbilities = MOVEMENT_ABILITIES[class]
    if not classAbilities then return {} end
    local specAbilities = classAbilities[specId]
    if not specAbilities then return {} end

    local result, seen = {}, {}

    for _, spellId in ipairs(specAbilities) do
        if not seen[spellId] then
            local override = overrides[spellId]
            if SpellEffectivelyEnabled(override, spellId) then
                if (IsPlayerSpell and IsPlayerSpell(spellId))
                   or (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellId)) then
                    local displayId = spellId
                    if C_Spell.GetOverrideSpell then
                        local okOvr, oid = pcall(C_Spell.GetOverrideSpell, spellId)
                        if okOvr and oid and oid > 0 and oid ~= spellId then displayId = oid end
                    end
                    if not seen[displayId] then
                        seen[spellId] = true
                        seen[displayId] = true
                        local spellInfo = C_Spell.GetSpellInfo(displayId)
                        local isCharge, maxCh, rechDur = SafeGetChargeInfo(displayId)
                        local baseId = (displayId ~= spellId) and spellId or nil
                        if not isCharge and baseId then
                            isCharge, maxCh, rechDur = SafeGetChargeInfo(baseId)
                        end
                        if spellInfo then
                            local defaultCustom = BUFF_ACTIVE_SPELLS[displayId] or BUFF_ACTIVE_SPELLS[spellId]
                            if defaultCustom then
                                table.insert(result, {
                                    spellId = displayId,
                                    spellName = spellInfo.name,
                                    spellIcon = spellInfo.iconID,
                                    customText = override and override.customText ~= "" and override.customText or defaultCustom,
                                    checkType = "buffActive",
                                })
                            else
                                local rawBaseDur = SafeGetBaseDuration(displayId)
                                if rawBaseDur <= 0 and baseId then rawBaseDur = SafeGetBaseDuration(baseId) end
                                if not isCharge and rawBaseDur <= 0 and rechDur > 0 then rawBaseDur = rechDur end
                                if rawBaseDur <= 0 then rawBaseDur = GetKnownCategoryDuration(displayId) end
                                if rawBaseDur <= 0 and baseId then rawBaseDur = GetKnownCategoryDuration(baseId) end
                                table.insert(result, {
                                    spellId = displayId,
                                    baseSpellId = baseId,
                                    spellName = spellInfo.name,
                                    spellIcon = spellInfo.iconID,
                                    customText = override and override.customText ~= "" and override.customText or nil,
                                    isChargeSpell = isCharge,
                                    maxCharges = maxCh,
                                    rechargeDuration = rechDur,
                                    baseDuration = isCharge and rechDur or rawBaseDur,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- User-added custom overrides for this class not already covered above
    for spellId, override in pairs(overrides) do
        if not seen[spellId] and override.class == class and override.enabled ~= false then
            if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellId) then
                local displayId = spellId
                if C_Spell.GetOverrideSpell then
                    local okOvr, oid = pcall(C_Spell.GetOverrideSpell, spellId)
                    if okOvr and oid and oid > 0 and oid ~= spellId then displayId = oid end
                end
                if not seen[displayId] then
                    seen[spellId] = true
                    seen[displayId] = true
                    local spellInfo = C_Spell.GetSpellInfo(displayId)
                    local isCharge, maxCh, rechDur = SafeGetChargeInfo(displayId)
                    local baseId = (displayId ~= spellId) and spellId or nil
                    if not isCharge and baseId then isCharge, maxCh, rechDur = SafeGetChargeInfo(baseId) end
                    if spellInfo then
                        -- Same buff-active branch the default path takes above.
                        -- Without it a user-added aura-toggle spell was always
                        -- built as a cooldown entry, and since it has no cooldown
                        -- the display loop had nothing to show.
                        local defaultCustom = BUFF_ACTIVE_SPELLS[displayId] or BUFF_ACTIVE_SPELLS[spellId]
                        if defaultCustom then
                            table.insert(result, {
                                spellId = displayId,
                                spellName = spellInfo.name,
                                spellIcon = spellInfo.iconID,
                                customText = override.customText ~= "" and override.customText or defaultCustom,
                                checkType = "buffActive",
                            })
                        else
                            local rawBaseDur = SafeGetBaseDuration(displayId)
                            if rawBaseDur <= 0 and baseId then rawBaseDur = SafeGetBaseDuration(baseId) end
                            if not isCharge and rawBaseDur <= 0 and rechDur > 0 then rawBaseDur = rechDur end
                            if rawBaseDur <= 0 then rawBaseDur = GetKnownCategoryDuration(displayId) end
                            table.insert(result, {
                                spellId = displayId,
                                baseSpellId = baseId,
                                spellName = spellInfo.name,
                                spellIcon = spellInfo.iconID,
                                customText = override.customText ~= "" and override.customText or nil,
                                isChargeSpell = isCharge,
                                maxCharges = maxCh,
                                rechargeDuration = rechDur,
                                baseDuration = isCharge and rechDur or rawBaseDur,
                            })
                        end
                    end
                end
            end
        end
    end

    return result
end

local function UpdateCachedCharges()
    if inCombat or InCombatLockdown() then return end
    for _, entry in ipairs(cachedMovementSpells) do
        if entry.checkType == "buffActive" then
            -- Aura-tracked: no cooldown and no charges to cache.
        elseif entry.isChargeSpell then
            local chargeId = entry.baseSpellId or entry.spellId
            local chargeInfo = C_Spell.GetSpellCharges(chargeId)
            if chargeInfo and chargeInfo.currentCharges and not IsSecret(chargeInfo.currentCharges) then
                cachedChargeCount[entry.spellId] = chargeInfo.currentCharges
            end
        else
            local cdInfo = C_Spell.GetSpellCooldown(entry.spellId)
            -- A shared lockout must not be adopted as the ability's base
            -- cooldown either -- that would poison the very value
            -- IsLockoutWindow classifies against.
            if cdInfo and cdInfo.duration and not IsSecret(cdInfo.duration) and cdInfo.duration > 0
               and not IsLockoutWindow(entry, cdInfo.duration) then
                entry.baseDuration = cdInfo.duration
            end
        end
    end
end


local function CacheMovementSpells(fullReset)
    local class = select(2, UnitClass("player"))
    local specId = ResolvePlayerSpecId()

    if fullReset then
        CancelAllRechargeTimers()
        wipe(spellWasCast); wipe(spellCastTime); wipe(chargeRechargeStart)
        cacheResetTime = GetTime()
    end

    local prevSpells = cachedMovementSpells
    local newSpells = GetPlayerMovementSpells()
    if #newSpells == 0 and prevSpells and #prevSpells > 0 and not specId then
        cachedMovementSpells = prevSpells
    else
        cachedMovementSpells = newSpells
    end

    if not fullReset and prevSpells and #prevSpells > 0 then
        for _, newEntry in ipairs(cachedMovementSpells) do
            local newBase = newEntry.baseSpellId or newEntry.spellId
            for _, oldEntry in ipairs(prevSpells) do
                local oldBase = oldEntry.baseSpellId or oldEntry.spellId
                if oldBase == newBase and oldEntry.spellId ~= newEntry.spellId then
                    local oldId, newId = oldEntry.spellId, newEntry.spellId
                    if spellWasCast[oldId] ~= nil then spellWasCast[newId] = spellWasCast[oldId]; spellWasCast[oldId] = nil end
                    if spellCastTime[oldId] ~= nil then spellCastTime[newId] = spellCastTime[oldId]; spellCastTime[oldId] = nil end
                    if cachedChargeCount[oldId] ~= nil then cachedChargeCount[newId] = cachedChargeCount[oldId]; cachedChargeCount[oldId] = nil end
                    if chargeRechargeStart[oldId] ~= nil then chargeRechargeStart[newId] = chargeRechargeStart[oldId]; chargeRechargeStart[oldId] = nil end
                    if rechargeTimers[oldId] ~= nil then rechargeTimers[newId] = rechargeTimers[oldId]; rechargeTimers[oldId] = nil end
                end
            end
        end
    end

    wipe(trackedSpellSet)
    for _, entry in ipairs(cachedMovementSpells) do
        trackedSpellSet[entry.spellId] = entry.spellId
        if C_Spell.GetOverrideSpell then
            local okOvr, oid = pcall(C_Spell.GetOverrideSpell, entry.spellId)
            if okOvr and oid and oid > 0 and oid ~= entry.spellId then trackedSpellSet[oid] = entry.spellId end
        end
    end

    local overrides = MA().spellOverrides or {}
    local classAbilities = MOVEMENT_ABILITIES[class]
    local specAbilities = classAbilities and specId and classAbilities[specId]
    if specAbilities then
        for _, spellId in ipairs(specAbilities) do
            local spellOverride = overrides[spellId]
            if SpellEffectivelyEnabled(spellOverride, spellId) and not trackedSpellSet[spellId] then
                local group = SPELL_ALIAS_MAP[spellId]
                if group then
                    for _, aliasId in ipairs(group) do
                        if trackedSpellSet[aliasId] and not trackedSpellSet[spellId] then
                            trackedSpellSet[spellId] = trackedSpellSet[aliasId]
                        end
                    end
                end
            end
        end
    end

    UpdateCachedCharges()
end
EllesmereUI._CacheMovementSpells = CacheMovementSpells

CancelAllRechargeTimers = function()
    for _, timer in pairs(rechargeTimers) do timer:Cancel() end
    wipe(rechargeTimers)
end

local function StartRechargeTimer(entry, delay)
    if rechargeTimers[entry.spellId] then return end
    local duration = delay or entry.rechargeDuration or 0
    if duration <= 0 then return end
    rechargeTimers[entry.spellId] = C_Timer.NewTimer(duration, function()
        rechargeTimers[entry.spellId] = nil
        local cur = cachedChargeCount[entry.spellId] or 0
        local max = entry.maxCharges or 1
        local newVal = math.min(cur + 1, max)
        cachedChargeCount[entry.spellId] = newVal
        if newVal < max then
            chargeRechargeStart[entry.spellId] = GetTime()
            StartRechargeTimer(entry)
        else
            chargeRechargeStart[entry.spellId] = nil
        end
        if CheckMovementCooldown then CheckMovementCooldown() end
    end)
end

local function OnTrackedSpellCast(spellId)
    if (GetTime() - cacheResetTime) < 2 then return end
    if TALENT_CD_TRIGGER_SPELLS[spellId] then return end
    local baseId = trackedSpellSet[spellId]
    if not baseId then return end
    spellWasCast[baseId] = true
    spellCastTime[baseId] = GetTime()

    if not inCombat then
        for _, entry in ipairs(cachedMovementSpells) do
            if entry.spellId == baseId and not entry.isChargeSpell then
                local dur = SafeGetBaseDuration(baseId)
                if dur <= 0 and entry.baseSpellId then dur = SafeGetBaseDuration(entry.baseSpellId) end
                if dur <= 0 and entry.rechargeDuration and entry.rechargeDuration > 0 then dur = entry.rechargeDuration end
                if dur <= 0 then dur = GetKnownCategoryDuration(baseId) end
                if dur <= 0 and entry.baseSpellId then dur = GetKnownCategoryDuration(entry.baseSpellId) end
                if dur > 0 then entry.baseDuration = dur end
                break
            end
        end
    end

    if not inCombat then return end
    for _, entry in ipairs(cachedMovementSpells) do
        if entry.spellId == baseId and entry.isChargeSpell then
            local cur = cachedChargeCount[baseId] or entry.maxCharges or 1
            cachedChargeCount[baseId] = math.max(0, cur - 1)
            if not chargeRechargeStart[baseId] then chargeRechargeStart[baseId] = GetTime() end
            if not rechargeTimers[baseId] then StartRechargeTimer(entry) end
            return
        end
    end
end

-------------------------------------------------------------------------------
--  Movement bar rendering
-------------------------------------------------------------------------------
local function CancelMovementCountdown()
    if movementCountdownTimer then movementCountdownTimer:Cancel(); movementCountdownTimer = nil end
end

-- buffActive engine-lane handles (declared here so HideMovementDisplay -- the
-- universal off-path -- can park the host; defined in the lane block below).
local buffAlertHost, buffAlertBuilt, buffAlertRegenArm, buffAlertLastCount
local buffAlertContainer, buffAlertAssist, buffAlertVehicle

-- keepBuffLane: the cooldown display is going away but the buffActive lane is
-- not. A buffActive spell takes no slot, so an empty cooldown stack is its
-- NORMAL state -- parking the host there would hide the alert permanently.
local function HideMovementDisplay(keepBuffLane)
    wipe(readyAlertShown)
    movementFrame:Hide()
    for _, slot in ipairs(displayPool) do
        slot.text:Hide(); slot.icon:Hide(); slot.icon.cooldown:Clear(); slot.bar:Hide(); HideEngineCountdown(slot); slot:Hide()
    end
    activeSlotCount = 0
    if buffAlertHost and not keepBuffLane then buffAlertHost:Hide() end
    CancelMovementCountdown()
end

local function ShowMovementSlot(index, cdInfo, spellEntry, duration)
    local ma = MA()
    local slot = GetDisplaySlot(index)
    StyleSlot(slot)
    local displayMode = ma.displayMode or "text"
    -- Clamp to a clean 0/1 (matches the binary Show Decimal toggle). A legacy
    -- numeric-input value could be a string ("1") or a stored -0; feeding -0 to
    -- the format below builds an invalid "%.-0f". This local drives all three
    -- format sites (precFmt and the two bar-text SetFormattedText calls).
    local precision   = ((tonumber(ma.precision) or 1) > 0) and 1 or 0
    local spellName   = spellEntry.customText or spellEntry.spellName or "Movement"
    local spellIcon   = spellEntry.spellIcon
    local precFmt     = "%." .. precision .. "f"
    -- spellName is free-form user text (per-spell Custom Text); escape
    -- literal "%" so SetFormattedText cannot misread it as a format
    -- directive expecting arguments it never gets.
    local escapedName = (spellName:gsub("%%", "%%%%"))
    -- Three fixed text arrangements: two read as "No <ability>" (the alert
    -- shows while the spell is unavailable), text_d is the bare number; the
    -- legacy "text" value keeps the old default's duration-first order.
    local fmtStr
    if displayMode == "text_nd" then
        fmtStr = "No " .. escapedName .. " " .. precFmt
    elseif displayMode == "text_d" then
        fmtStr = precFmt
    else
        fmtStr = precFmt .. " No " .. escapedName
    end

    slot.text:Hide(); slot.icon:Hide(); slot.bar:Hide()
    HideEngineCountdown(slot)

    -- Start-recovery branch. GetSpellCooldown's timeUntilEndOfStartRecovery
    -- is ALWAYS present as a number on this client (0 outside an actual
    -- start-recovery window), so it must be gated on a POSITIVE value --
    -- plain truthiness hijacked EVERY render into this branch, which is why
    -- icon mode never drew its cooldown swipe or number. Secret check comes
    -- first (relational compares on secret numbers throw); a secret recovery
    -- falls through to the main path, whose engine sinks accept secrets.
    local recov = cdInfo and cdInfo.timeUntilEndOfStartRecovery
    if issecretvalue and issecretvalue(recov) then recov = nil end
    if type(recov) == "number" and recov > 0 and not IsLockoutWindow(spellEntry, recov) then
        if displayMode == "icon" and spellIcon then
            slot.icon.tex:SetTexture(spellIcon)
            -- Recharge swipe: derived from the entry's recharge duration
            -- (same source the bar branch scales by).
            local rechDur = spellEntry.rechargeDuration or 0
            if rechDur > 0 then
                slot.icon.cooldown:SetCooldown(GetTime() - (rechDur - recov), rechDur)
            else
                slot.icon.cooldown:Clear()
            end
            slot.icon.cooldown:SetHideCountdownNumbers(true)
            slot.icon.timeText:SetFormattedText("%." .. precision .. "f", recov)
            slot.icon:Show()
        elseif displayMode == "bar" then
            local rechDur = spellEntry.rechargeDuration or 0
            slot.bar:SetMinMaxValues(0, rechDur)
            slot.bar:SetValue(recov)
            local r, g, b = ResolveAlertColor("textColor", "textColorUseClass")
            slot.bar:SetStatusBarColor(r, g, b)
            slot.bar.text:SetShown(ma.barShowDuration ~= false)
            if ma.barShowDuration ~= false then
                slot.bar.text:SetFormattedText("%." .. precision .. "f", recov)
            end
            if ma.barShowIcon ~= false and spellIcon then slot.bar.icon:SetTexture(spellIcon); slot.bar.icon:Show() else slot.bar.icon:Hide() end
            slot.bar:Show()
        else
            slot.text:SetFormattedText(fmtStr, recov)
            slot.text:Show()
        end
        slot:Show()
        return true
    end

    local cdRemaining, cdStart, cdDuration, cdModRate
    local hasSecretDuration = false
    -- True only when the duration OBJECT supplied the values below. The engine
    -- countdown is driven from that object, so anything resolved from cdInfo
    -- instead must not try to use it: the object was either absent or already
    -- rejected here, and SetCooldownFromDurationObject clears to nothing on an
    -- expired one while still reporting success.
    local fromDuration = false
    if duration then
        local rem, total = duration:GetRemainingDuration(), duration:GetTotalDuration()
        if IsSecret(rem) or IsSecret(total) then
            hasSecretDuration = true
            fromDuration = true
            cdRemaining, cdDuration = rem, total
            cdStart, cdModRate = duration:GetStartTime(), duration:GetModRate()
        elseif total and total > 1.5 and not IsLockoutWindow(spellEntry, total) and rem and rem > 0 then
            fromDuration = true
            cdRemaining, cdDuration = rem, total
            cdStart, cdModRate = duration:GetStartTime(), duration:GetModRate()
        end
    end

    if not cdRemaining and cdInfo then
        local s, d, m = cdInfo.startTime or 0, cdInfo.duration or 0, cdInfo.modRate or 1
        if IsSecret(s) or IsSecret(d) then
            hasSecretDuration = true
            cdStart, cdDuration, cdModRate, cdRemaining = s, d, m, true
        -- This fallback never had the duration-object branch's own GCD floor,
        -- so anything the branch above rejected as too short landed here and
        -- rendered anyway.
        elseif d > 0 and not IsLockoutWindow(spellEntry, d) then
            cdStart, cdDuration, cdModRate = s, d, m
            cdRemaining = math.max(0, (s + d) - GetTime())
        end
    end

    if not cdRemaining then return false end
    if not hasSecretDuration and cdRemaining <= 0 then return false end

    -- The text branches format cdRemaining themselves, so what decides them is
    -- whether THAT value can be rendered, not whether some other field of the
    -- same cooldown happened to be secret: hasSecretDuration is set when EITHER
    -- the remaining or the total is secret, and a secret total leaves a
    -- perfectly renderable remaining behind. Bar mode keeps using
    -- hasSecretDuration because it also feeds cdDuration to SetMinMaxValues.
    -- Both tests are secret-safe (no comparison against a secret): the sentinel
    -- is a plain boolean, and IsSecret is issecretvalue.
    local unreadableRemaining = type(cdRemaining) == "boolean" or IsSecret(cdRemaining)
    -- Show a number only when there is a real, positive one to show. The <= 0
    -- test is reachable ONLY once unreadableRemaining is false, so it never
    -- compares against a secret. It matters because the guard above lets a
    -- non-positive remaining through whenever hasSecretDuration was set by the
    -- OTHER field, which is the last route by which a literal 0.0 could still
    -- reach the display.
    local showRemaining = not unreadableRemaining and cdRemaining > 0

    if displayMode == "icon" then
        if spellIcon then
            slot.icon.tex:SetTexture(spellIcon)
            -- Single-argument form: every proven duration-object consumer in
            -- the suite calls it this way; the extra boolean is not part of
            -- the working pattern.
            if duration and slot.icon.cooldown.SetCooldownFromDurationObject then
                slot.icon.cooldown:SetCooldownFromDurationObject(duration)
            else
                slot.icon.cooldown:SetCooldown(cdStart, cdDuration, cdModRate)
            end
            if hasSecretDuration then
                -- Secret timing: only the engine can render the number.
                slot.icon.cooldown:SetHideCountdownNumbers(false)
                slot.icon.timeText:SetText("")
            else
                -- Our own countdown text for readable durations, refreshed by
                -- the poll every tick; the engine numbers are suppressed here
                -- and serve only the secret branch.
                slot.icon.cooldown:SetHideCountdownNumbers(true)
                slot.icon.timeText:SetFormattedText("%." .. precision .. "f", cdRemaining)
            end
            slot.icon:Show()
        else
            -- Icon mode with no icon falls back to text, so it needs the same
            -- guard as the text branch below.
            if not showRemaining then
                slot.text:SetText("No " .. spellName)
                if fromDuration then ShowEngineCountdown(slot, displayMode, duration) end
            else
                slot.text:SetFormattedText(fmtStr, cdRemaining)
            end
            slot.text:Show()
        end
    elseif displayMode == "bar" then
        local r, g, b = ResolveAlertColor("textColor", "textColorUseClass")
        slot.bar:SetStatusBarColor(r, g, b)
        if type(cdRemaining) == "boolean" then
            -- Only the sentinel leaves nothing to scale the fill with: show a
            -- full bar so the alert still reads as "unavailable" instead of an
            -- empty one, which would look like a cooldown that just finished.
            slot.bar:SetMinMaxValues(0, 1)
            slot.bar:SetValue(1)
        else
            -- A SECRET remaining still animates: SimpleStatusBar's SetValue and
            -- SetMinMaxValues are both AllowedWhenTainted, so the engine scales
            -- the fill from values Lua may not read. Gating this on
            -- hasSecretDuration would freeze the bar at 100% for no reason.
            slot.bar:SetMinMaxValues(0, cdDuration)
            slot.bar:SetValue(cdRemaining)
        end
        -- The NUMBER is the part Lua cannot produce, so it comes from our own
        -- formatter when readable and from the engine when not.
        if ma.barShowDuration == false then
            slot.bar.text:SetShown(false)
        elseif showRemaining then
            slot.bar.text:SetShown(true)
            slot.bar.text:SetFormattedText("%." .. precision .. "f", cdRemaining)
        else
            slot.bar.text:SetShown(false)
            if fromDuration then ShowEngineCountdownCentred(slot, slot.bar, duration) end
        end
        if ma.barShowIcon ~= false and spellIcon then slot.bar.icon:SetTexture(spellIcon); slot.bar.icon:Show() else slot.bar.icon:Hide() end
        slot.bar:Show()
    else -- any text mode (text_nd / text_dn / legacy "text")
        if not showRemaining then
            -- Whenever the remaining is unreadable, drop the number: the alert
            -- still says the ability is unavailable, which is the part that
            -- matters. Formatting it ourselves renders 0.0, which reads as
            -- "ready" -- the exact opposite of what the alert means.
            --
            -- BOTH producers land here, which is what the first pass at this
            -- got wrong. The cdInfo fallback stores a BOOLEAN sentinel (Lua
            -- cannot compute a remaining from a secret start plus duration),
            -- and the Duration-object path above stores a raw SECRET NUMBER.
            -- Only the sentinel used to be guarded, on the assumption that
            -- SetFormattedText being AllowedWhenTainted meant the engine would
            -- render a secret's real value. It does not: field-confirmed on
            -- 8.7.8, a secret remaining renders as 0.0 here. Icon mode never
            -- relied on that assumption -- it blanks its own text and lets the
            -- Cooldown widget draw the secret -- so the two branches disagreed
            -- and the text one was wrong. Gating on hasSecretDuration covers
            -- both producers and drops the fragile type() test with it.
            -- text_d shows only the number, so the label stays empty and the
            -- engine countdown is centred on the slot instead of beside it.
            slot.text:SetText(displayMode == "text_d" and "" or ("No " .. spellName))
            -- The number Lua cannot format, drawn by the engine.
            if fromDuration then ShowEngineCountdown(slot, displayMode, duration) end
        else
            slot.text:SetFormattedText(fmtStr, cdRemaining)
        end
        slot.text:Show()
    end

    slot:Show()
    return true
end

-------------------------------------------------------------------------------
--  buffActive lane (Burning Rush): ENGINE-OWNED end to end.
--  GetPlayerAuraBySpellID is RequiresNonSecretAura -- under aura restriction
--  (/euidev = M+/raid combat, the viability bar) it returns ZERO VALUES for a
--  flagged spell WHILE THE BUFF IS UP, indistinguishable from absent
--  (field-settled 2026-08-13). No Lua probe or payload state machine can know
--  presence there; the engine can. One hidden AuraContainer with
--  includeSpellIDs shows/hides its button on presence entirely C-side,
--  identical in and out of restriction; the alert visual is a region ON the
--  engine button (visibility inherits, SetText is a display-only sink).
--  HOST RULES (forbidden-dependent geometry lock): UIParent-parented AND
--  UIParent-anchored, positioned NUMERICALLY, out of combat only -- the
--  engine child makes the host's own geometry writes ADDON_ACTION_BLOCKED
--  inside lockdown, so combat repositions park on a one-shot regen re-apply.
-------------------------------------------------------------------------------
local BUFF_ALERT_STYLE = "qol:movealert"

local function BuffAlertApplyExtra(button, d, style)
    local ma = MA()
    local mode = ma.displayMode or "text"
    if not d.maText then
        d.maText = button:CreateFontString(nil, "OVERLAY")
    end
    local entry = style.maEntry
    local label = (entry and (entry.customText or entry.spellName)) or "Active!"
    local r, g, b = ResolveAlertColor("textColor", "textColorUseClass")
    local fp = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("qol")) or STANDARD_TEXT_FONT
    d.maText:SetFont(fp, ma.textSize or 16, "OUTLINE")
    d.maText:SetTextColor(r, g, b)
    d.maText:ClearAllPoints()
    if mode == "icon" then
        if d.icon then d.icon:SetAlpha(1) end
        d.maText:Hide()
    else
        -- text AND bar modes render as the plain label: a permanent toggle
        -- buff has no duration for a bar to add, and the engine button is the
        -- only restriction-safe visibility carrier either way.
        if d.icon then d.icon:SetAlpha(0) end
        d.maText:SetPoint("CENTER", button, "CENTER", 0, 0)
        d.maText:SetText(label)
        d.maText:Show()
    end
end

local function BuildBuffAlertStyle(entry)
    local ma = MA()
    local px = (EllesmereUI.PP and EllesmereUI.PP.Scale and EllesmereUI.PP.Scale(ma.iconSize or 32)) or ma.iconSize or 32
    return {
        width = px, height = px,
        iconCrop = true,
        hideDurationText = true, -- permanent buff: no countdown to draw
        hideSwipe = true,
        noTooltips = true,
        applyExtra = BuffAlertApplyExtra,
        maEntry = entry,
    }
end

-- Identity gate (Blizzard_AuraContainer/Blizzard_AuraContainerUtil.lua,
-- AuraContainerUtil.CanApplyIdentityCandidateFilters + DoesAuraPassCandidateFilters,
-- verified 12.1.0.69299): includeSpellIDs is applied to a HELPFUL aura only while
-- UnitCanAssist("player", unit) holds, and it FAILS OPEN -- when the gate fails the
-- spell-ID filter is skipped entirely and the aura passes on its filter string
-- alone, so a group asking for one spell renders every buff. Boarding a
-- vehicle drops the player's own assistability, so this one-button HELPFUL group
-- stops meaning "Burning Rush" and renders whatever buff it finds first, wearing
-- the Burning Rush label. Membership is cached per aura instance and UNIT_AURA
-- only re-parses what changed, so the degraded parse outlived the ride: the alert
-- stayed up after dismounting until a reload rebuilt the container.
-- Latched from the vehicle events rather than probed here, because
-- UnitUsingVehicle is still true across the EXIT transition (see the RF assist
-- gate's AssistProbe, which guards the same engine gate one unit over).
local function BuffAlertAssistable()
    if buffAlertVehicle then return false end
    -- Cinematics flip the same flag without a vehicle (UNIT_FACTION edge). A
    -- CLEANLY-false answer denies; unreadable ones stay fail-open, since a
    -- transient nil must not blank a working alert.
    local ok, canAssist = pcall(UnitCanAssist, "player", "player")
    if ok and not IsSecret(canAssist) and canAssist == false then return false end
    return true
end

-- Reconcile the latch against the live flag. Needed wherever the EXITED edge
-- could have been missed: while the tracker's events are unregistered nothing
-- clears the latch, so a tracker switched off mid-ride (or a profile swap, or
-- being teleported out of a vehicle) would otherwise come back with the lane
-- suppressed for the rest of the session.
local function SyncBuffAlertVehicleLatch()
    local probe = UnitUsingVehicle or UnitInVehicle
    buffAlertVehicle = (probe and probe("player")) and true or false
end

-- Build once per session on first eligible pass (warlock + Movement Alerts on
-- + Burning Rush checked); later passes only refresh the style (mode/size/
-- color edits ride RestyleSoon) and the host's shown state. Engine frames are
-- permanent, so disable parks via host:Hide() (the container is a CHILD of the
-- host -- creation-time parenting is legal) and re-enable reuses everything.
local function EnsureBuffAlertLane()
    local AK = EllesmereUI.AuraKit
    if not (AK and AK.RequestContainer and AK.AddGroupToContainer and AK.RestyleSoon) then return end
    local entry
    for _, e in ipairs(cachedMovementSpells) do
        if e.checkType == "buffActive" then entry = e; break end
    end
    if not entry then
        if buffAlertHost then buffAlertHost:Hide() end
        return
    end
    -- Resolved ahead of the Show() below, not beside it: every pass runs through
    -- here, so a gate applied anywhere else would be undone by the next tick.
    local assist = BuffAlertAssistable()
    local wasDenied = (buffAlertAssist == false)
    buffAlertAssist = assist
    if buffAlertBuilt then
        if not assist then buffAlertHost:Hide(); return end
        buffAlertHost:Show()
        -- Whatever was parsed during the degraded window is wrong, and leaving a
        -- vehicle produces no aura edge for buffs that were already up, so the
        -- engine would keep serving the stale membership (it is cached per aura
        -- instance; UNIT_AURA re-parses only what changed). The Show() above
        -- re-parses on its own -- AuraContainerPrivateMixin:OnShow_Intrinsic in
        -- Blizzard_AuraContainer/Blizzard_AuraContainer.lua calls UpdateAllAuras --
        -- and this is that same lever stated outright, so the recovery does not
        -- silently depend on the host being hidden rather than faded. NOTE the
        -- method is a no-op on AuraContainerSharedMixin; the real
        -- MarkDirty(FullAuraRebuild) is ManagedAuraContainerSharedMixin's
        -- override, which reaches the addon-callable partition through
        -- ManagedAuraContainerInboundMixin. Bounded to the real denied->allowed flip.
        if wasDenied and buffAlertContainer and buffAlertContainer.UpdateAllAuras then
            buffAlertContainer:UpdateAllAuras()
        end
        AK.styles[BUFF_ALERT_STYLE] = BuildBuffAlertStyle(entry)
        AK.RestyleSoon(BUFF_ALERT_STYLE)
        return
    end
    -- Denial must not postpone the BUILD, only the display: logging in inside a
    -- vehicle (or behind an intro cinematic) would otherwise defer creation to
    -- the first allowed pass. Build unconditionally and park at the end; the
    -- container is created and hidden inside one call, so nothing renders in
    -- between.
    buffAlertBuilt = true
    buffAlertHost = CreateFrame("Frame", nil, UIParent)
    buffAlertHost:SetSize(2, 2)
    -- Provisional numeric seat; RepositionBuffAlertHost follows the alert
    -- stack on every out-of-combat render pass.
    buffAlertHost:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
    AK.styles[BUFF_ALERT_STYLE] = BuildBuffAlertStyle(entry)
    local include = { [entry.spellId] = true }
    -- Override form too (talent variants share the alert); Burning Rush has
    -- none today, guarded for the day it grows one.
    if FindSpellOverrideByID then
        local ov = FindSpellOverrideByID(entry.spellId)
        if type(ov) == "number" and ov > 0 then include[ov] = true end
    end
    AK.RequestContainer(buffAlertHost, "player", {
        point = { "CENTER", buffAlertHost, "CENTER", 0, 0 },
        layout = { anchorPoint = "CENTER", padding = { 0, 0, 0, 0 }, rowWidth = 400 },
    }, function(container)
        buffAlertContainer = container
        AK.AddGroupToContainer(container, {
            key = "buffalert",
            filter = { "HELPFUL" },
            style = BUFF_ALERT_STYLE,
            maxFrameCount = 1,
            candidateFilters = { includeSpellIDs = include },
            layout = { anchorPoint = "CENTER", padding = { 0, 0, 0, 0 }, rowWidth = 400 },
        })
    end)
    if not assist then buffAlertHost:Hide() end
end

-- Numeric follow of the alert stack's top (slots grow UP from movementFrame's
-- bottom, +2px gaps). Geometry reads are on OUR movementFrame (no engine
-- content beneath it -- always legal); the WRITE on the host is lockdown-
-- blocked, so combat passes arm a one-shot regen re-apply reading the LAST
-- counted stack height.
local function RepositionBuffAlertHost(count)
    if not buffAlertHost then return end
    buffAlertLastCount = count
    if InCombatLockdown() then
        if not buffAlertRegenArm then
            buffAlertRegenArm = CreateFrame("Frame")
            buffAlertRegenArm:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                RepositionBuffAlertHost(buffAlertLastCount or 0)
            end)
        end
        buffAlertRegenArm:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local fw, fh = movementFrame:GetWidth(), movementFrame:GetHeight()
    local left, bottom = movementFrame:GetLeft(), movementFrame:GetBottom()
    if not (fw and fh and left and bottom) then return end
    buffAlertHost:ClearAllPoints()
    buffAlertHost:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
        left + fw / 2, bottom + count * (fh + 2) + fh / 2)
end

-------------------------------------------------------------------------------
--  Charge spells: "no movement remaining" must mean ZERO charges left.
--  currentCharges is a SECRET value -- verified live on Devourer's Shift, where
--  maxCharges reads 3 but currentCharges, cooldownDuration and every timing
--  field come back SECRET even out of combat -- so Lua can never branch on the
--  count, and IsSpellUsable reads true at 0 charges as well (also verified), so
--  it cannot stand in.
--  Blizzard's own discriminator is the cooldown's TOTAL duration: while a
--  charge is banked the spell reports only a GCD-length cooldown, and the full
--  recharge drives it only once the last charge is spent. A Step curve turns
--  that secret total into a secret ALPHA the engine resolves itself, with no
--  Lua comparison anywhere -- the same trick Action Bars uses to stop
--  banked-charge buttons desaturating (desatCurveReal / GetCdAlphaCurve).
--  Non-charge spells get LockoutAlpha instead: 1 in every readable case, and the
--  engine-resolved 0/1 when a secret window needs classifying -- a pooled slot
--  still can't keep a stale 0, because this runs for every shown slot each pass.
-------------------------------------------------------------------------------
local chargeAlphaCurve = nil   -- nil = not built, false = API unavailable
local function GetChargeAlphaCurve()
    if chargeAlphaCurve == nil then
        if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, 0)     -- GCD-length cooldown: a charge is banked -> hide
            c:AddPoint(1.6, 1)   -- real recharge: out of charges -> show
            chargeAlphaCurve = c
        else
            chargeAlphaCurve = false
        end
    end
    return chargeAlphaCurve or nil
end

local function ApplyChargeVisibility(slot, spellId, chargeInfo, entry, duration)
    if not slot then return end
    -- maxCharges stays PLAIN even when the rest of the charge record is secret,
    -- so this branch is safe (and is why the entry's cached isChargeSpell flag
    -- is not consulted -- SafeGetChargeInfo throws the whole record away when
    -- cooldownDuration is secret, leaving Shift cached as a 1-charge cooldown).
    local mc = chargeInfo and chargeInfo.maxCharges
    -- Non-charge: the only thing that hides the slot is a cross-ability lockout,
    -- and when its window is secret the engine-side compare in LockoutAlpha is
    -- the ONLY way to classify it. This is also the single writer of alpha on
    -- that path, so it must not be reduced to a bare SetAlpha(1) -- that is what
    -- let the lockout show through.
    if mc == nil or IsSecret(mc) or mc <= 1 then
        slot:SetAlpha(LockoutAlpha(entry, duration))
        return
    end
    local curve = GetChargeAlphaCurve()
    -- Deliberately WITHOUT ignoreGCD: the GCD-length total IS the banked-charge
    -- signal the step curve keys on (a banked charge reports only a GCD-length
    -- cooldown; the full recharge drives it only once the last charge is spent).
    -- Asking the API to skip the GCD would change that signal's class and show
    -- the alert while a charge is still banked.
    local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellId)
    if curve and durObj and durObj.EvaluateTotalDuration then
        -- Result may be SECRET: never compare it. SetAlpha accepts secrets, and
        -- "or 1" on a secret number is safe (a secret is always truthy).
        slot:SetAlpha(durObj:EvaluateTotalDuration(curve, 1) or 1)
    else
        slot:SetAlpha(1)
    end
end

-- Same-frame coalescer for the check: cooldown/usable/charge storms and player
-- aura batches fire several times per frame, and every check re-queries each
-- tracked spell, so duplicates collapse into ONE check on the next OnUpdate.
-- The frame is shown only while a check is pending (zero cost idle); the
-- 100 ms countdown repaint rides the same funnel so it can never double up
-- with an event-driven check in the same frame.
local movementCheckCharges = false
local movementCheckFrame = CreateFrame("Frame")
movementCheckFrame:Hide()
movementCheckFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    if movementCheckCharges then
        movementCheckCharges = false
        UpdateCachedCharges()
    end
    CheckMovementCooldown()
end)
local function RequestMovementCheck()
    movementCheckFrame:Show()
end
local function RequestMovementCheckWithCharges()
    movementCheckCharges = true
    movementCheckFrame:Show()
end

CheckMovementCooldown = function()
    -- The options-panel preview owns the display while it runs; the real
    -- renderer resumes from the preview's stop path. Costs one nil-check.
    if movementPreviewTicker then return end
    local ma = MA()
    if not MovementEnabled() then HideMovementDisplay(); return end
    if ma.combatOnly and not inCombat then HideMovementDisplay(); return end
    if #cachedMovementSpells == 0 then HideMovementDisplay(); return end

    local count = 0
    local nowShownReady = readyAlertScratch
    wipe(nowShownReady)
    for _, entry in ipairs(cachedMovementSpells) do
        if entry.checkType == "buffActive" then
            -- Engine-owned lane: presence rendering never passes through Lua
            -- (see EnsureBuffAlertLane). The entry deliberately takes no slot.
        else
            local spellId = entry.baseSpellId or entry.spellId
            local hasCharges = C_Spell.GetSpellCharges(spellId)
            local spellInfo  = C_Spell.GetSpellCooldown(spellId)
            if spellInfo and spellInfo.timeUntilEndOfStartRecovery and
               (spellInfo.isOnGCD == false or (spellInfo.isOnGCD == nil and not hasCharges)) then
                -- The duration OBJECT is the only thing that can put a number on
                -- screen while the cooldown is secret, so getting one matters more
                -- than which API supplies it. Two reasons it used to come back
                -- empty in combat: GetSpellCooldownDuration's second argument is
                -- ignoreGCD and it DEFAULTS TO FALSE, so while a global cooldown
                -- is running -- which in combat is most of the time -- it
                -- describes the GCD rather than the spell's own cooldown, and a
                -- GCD-length total is then rejected downstream; and an entry
                -- cached while its charge data was secret has isChargeSpell false
                -- even for a charge spell, sending it to the wrong API entirely.
                -- Ask for the real cooldown, and fall back to the other API
                -- rather than giving up.
                local duration
                if entry.isChargeSpell and C_Spell.GetSpellChargeDuration then
                    duration = C_Spell.GetSpellChargeDuration(spellId)
                elseif C_Spell.GetSpellCooldownDuration then
                    duration = C_Spell.GetSpellCooldownDuration(spellId, true)
                end
                if not duration then
                    if entry.isChargeSpell and C_Spell.GetSpellCooldownDuration then
                        duration = C_Spell.GetSpellCooldownDuration(spellId, true)
                    elseif C_Spell.GetSpellChargeDuration then
                        duration = C_Spell.GetSpellChargeDuration(spellId)
                    end
                end
                if ShowMovementSlot(count + 1, spellInfo, entry, duration) then
                    count = count + 1
                    nowShownReady[entry.spellId] = entry
                    -- Charge spells alpha-hide while a charge is still banked;
                    -- non-charge slots get the secret-lockout classification.
                    ApplyChargeVisibility(GetDisplaySlot(count), spellId, hasCharges, entry, duration)
                end
            end
        end
    end

    -- Engine lane: resolve build/park once per pass (self-hides when no
    -- buffActive spell is enabled for the spec), then seat the host at the
    -- stack top -- write side is OOC-gated inside RepositionBuffAlertHost.
    EnsureBuffAlertLane()
    RepositionBuffAlertHost(count)

    -- "Ready" TTS callout: fires once per spell exactly when it drops out of
    -- the on-cooldown set above (not while it sits ready, and not on the
    -- first poll after the feature/spec/class gates just opened up).
    if ma.maTtsEnabled then
        for spellId, entry in pairs(readyAlertShown) do
            if not nowShownReady[spellId] then
                FireTrackerAlert("ma", entry.customText or entry.spellName)
            end
        end
    end
    readyAlertShown, readyAlertScratch = nowShownReady, readyAlertShown

    for i = count + 1, activeSlotCount do
        local slot = displayPool[i]
        if slot then slot.text:Hide(); slot.icon:Hide(); slot.icon.cooldown:Clear(); slot.bar:Hide(); HideEngineCountdown(slot); slot:Hide() end
    end

    if count > 0 then
        activeSlotCount = count
        LayoutDisplaySlots(count)
        movementFrame:Show()
        CancelMovementCountdown()
        -- Fixed 100ms display refresh (smooth 1-decimal countdown).
        movementCountdownTimer = C_Timer.NewTimer(0.1, RequestMovementCheck)
    else
        activeSlotCount = 0
        -- EnsureBuffAlertLane just showed/parked the host for this pass; leave
        -- its verdict alone (see keepBuffLane).
        HideMovementDisplay(true)
    end
end
EllesmereUI._CheckMovementCooldown = function() if CheckMovementCooldown then CheckMovementCooldown() end end

local function ApplyMovementFrame()
    local ma = MA()
    if not ma then return end
    movementFrame:ClearAllPoints()
    local pos = ma.pos
    if pos and pos.point then
        movementFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        movementFrame:SetSize(pos.width or 200, pos.height or 40)
    else
        movementFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
        movementFrame:SetSize(200, 40)
    end
    for _, slot in ipairs(displayPool) do StyleSlot(slot) end
    if MovementEnabled() and not (EllesmereUI._unlockActive) then CheckMovementCooldown() end
end
EllesmereUI._applyMovementAlert = ApplyMovementFrame

-------------------------------------------------------------------------------
--  Options-panel preview: loops a fake cooldown through the real display
--  path, so every user setting (mode, size, color, format, precision, poll
--  rate) renders exactly as it will live. Zero cost while off: nothing here
--  exists but the functions, one ticker is created on activation, and the
--  real renderer pays a single nil-check. The tick self-terminates when the
--  options window closes or the user leaves the Movement Alerts page.
-------------------------------------------------------------------------------
local PREVIEW_CD = 8
local previewEnds = 0
local previewEntry = nil
local previewCdInfo = { startTime = 0, duration = PREVIEW_CD, modRate = 1 }

local function PreviewEntry()
    -- Prefer the player's first real tracked cooldown so the preview shows a
    -- familiar name/icon; fall back to any known class mobility spell.
    local e = cachedMovementSpells[1]
    if e and e.checkType ~= "buffActive" then return e end
    local class = select(2, UnitClass("player"))
    local classAbilities = MOVEMENT_ABILITIES[class]
    if classAbilities then
        for key, list in pairs(classAbilities) do
            if type(key) == "number" and type(list) == "table" then
                for _, sid in ipairs(list) do
                    local info = C_Spell.GetSpellInfo(sid)
                    if info then
                        return { spellId = sid, spellName = info.name, spellIcon = info.iconID }
                    end
                end
            end
        end
    end
    local info = C_Spell.GetSpellInfo(2983) -- Sprint: any-class fallback art
    return { spellId = 2983, spellName = (info and info.name) or "Movement",
        spellIcon = info and info.iconID }
end

local function StopMovementPreview()
    if not movementPreviewTicker then return end
    movementPreviewTicker:Cancel()
    movementPreviewTicker = nil
    previewEntry = nil
    HideMovementDisplay()
    -- Hand the display back to the real tracker state.
    CheckMovementCooldown()
end

local function PreviewTick()
    local ma = MA()
    -- Auto-shutoff: options window closed, or the user navigated to another
    -- page/module. (Page name must match PAGE_MOVEMENT in EUI_QoL_Options.lua.)
    local shown = EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown()
    local onPage = shown
        and EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule() == "EllesmereUIQoL"
        and EllesmereUI.GetActivePage and EllesmereUI:GetActivePage() == "MoveAlert"
    if not ma or not onPage then StopMovementPreview(); return end

    local now = GetTime()
    if now >= previewEnds then previewEnds = now + PREVIEW_CD end
    previewCdInfo.startTime = previewEnds - PREVIEW_CD
    if ShowMovementSlot(1, previewCdInfo, previewEntry) then
        for i = 2, activeSlotCount do
            local slot = displayPool[i]
            if slot then slot.text:Hide(); slot.icon:Hide(); slot.icon.cooldown:Clear(); slot.bar:Hide(); HideEngineCountdown(slot); slot:Hide() end
        end
        activeSlotCount = 1
        LayoutDisplaySlots(1)
        movementFrame:Show()
    end
end

local function StartMovementPreview()
    if movementPreviewTicker then return end
    local ma = MA()
    if not ma then return end
    previewEntry = PreviewEntry()
    previewEnds = GetTime() + PREVIEW_CD
    -- The preview owns the display: stop the real poll loop (its state
    -- resumes from StopMovementPreview's CheckMovementCooldown call).
    CancelMovementCountdown()
    movementPreviewTicker = C_Timer.NewTicker(0.1, PreviewTick)
    PreviewTick()
end

EllesmereUI._MovementAlertPreviewActive = function() return movementPreviewTicker ~= nil end
EllesmereUI._MovementAlertPreview = function(on)
    if on then StartMovementPreview() else StopMovementPreview() end
end

-------------------------------------------------------------------------------
--  Time Spiral -- flashes when a tracked mobility spell's cooldown is
--  proc-reset (generic spell-activation-overlay glow on a tracked spell).
--  A second, CDM-bar based implementation of this same proc exists in
--  EllesmereUICooldownManager\EllesmereUICdmBuffBars.lua's "timespiral"
--  Tracked Buff Bar preset (~line 3590). The two are independent (this one
--  works without any CDM bar) but share the same spell/talent-filter lists --
--  keep MOVEMENT_ABILITIES[...].filter above in sync with that file's
--  TIME_SPIRAL_GLOW_FILTERS if either changes. Enabling both trackers at
--  once will fire both alerts off the same glow event -- harmless, just a
--  possible double-notification if a user turns both on.
-------------------------------------------------------------------------------
local timeSpiralFrame = CreateFrame("Frame", "EUI_TimeSpiralFrame", UIParent)
timeSpiralFrame:SetSize(200, 40)
timeSpiralFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
timeSpiralFrame:Hide()
local timeSpiralText = timeSpiralFrame:CreateFontString(nil, "OVERLAY")
timeSpiralText:SetPoint("CENTER")

local timeSpiralActiveTime = nil
local timeSpiralActiveSpells = {}
local timeSpiralCountdownTimer = nil
local glowCooldown = 0
local procDebounce = 0
local castFilters = {}

local function RefreshCastFilters()
    wipe(castFilters)
    local classData = MOVEMENT_ABILITIES[select(2, UnitClass("player"))]
    if not classData or not classData.filter then return end
    for talentId, spells in pairs(classData.filter) do
        if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(talentId) then
            for _, id in ipairs(spells) do castFilters[id] = true end
        end
    end
end

local function OnSpellCast(spellId)
    if castFilters[spellId] then glowCooldown = GetTime() + 1.5 end
end

local allMobilitySpells = {}
local function RebuildMobilitySpellLookup()
    wipe(allMobilitySpells)
    for _, classData in pairs(MOVEMENT_ABILITIES) do
        for key, value in pairs(classData) do
            if type(key) == "number" and type(value) == "table" then
                for _, spellId in ipairs(value) do
                    if not BUFF_ACTIVE_SPELLS[spellId] then allMobilitySpells[spellId] = true end
                end
            end
        end
    end
    local overrides = MA().spellOverrides
    if overrides then
        for spellId, override in pairs(overrides) do
            if override.enabled ~= false and not BUFF_ACTIVE_SPELLS[spellId] then allMobilitySpells[spellId] = true end
        end
    end
end
EllesmereUI._RebuildMovementSpellLookup = RebuildMobilitySpellLookup

local function IsValidTimeSpiralProc(spellId)
    local now = GetTime()
    if BUFF_ACTIVE_SPELLS[spellId] then return false end
    local class = select(2, UnitClass("player"))
    local specId = ResolvePlayerSpecId()
    local classData = MOVEMENT_ABILITIES[class]
    local specSpells = classData and specId and classData[specId]
    local matched = false
    if specSpells then
        for _, id in ipairs(specSpells) do
            if id == spellId then matched = true; break end
            if C_Spell.GetOverrideSpell then
                local okOvr, oid = pcall(C_Spell.GetOverrideSpell, id)
                if okOvr and oid and oid == spellId then matched = true; break end
            end
        end
    end
    if not matched and allMobilitySpells[spellId] then matched = true end
    if not matched then return false end
    if now < glowCooldown then return false end
    if (now - procDebounce) < 0.12 then return false end
    return true
end

local function CancelTimeSpiralCountdown()
    if timeSpiralCountdownTimer then timeSpiralCountdownTimer:Cancel(); timeSpiralCountdownTimer = nil end
end

local function UpdateTimeSpiralCountdown()
    local ma = MA()
    if not ma.tsEnabled or not timeSpiralActiveTime then
        timeSpiralFrame:Hide()
        CancelTimeSpiralCountdown()
        return
    end
    local remaining = 10 - (GetTime() - timeSpiralActiveTime)
    if remaining > 0 then
        local fmtStr = (ma.tsTextFormat or "FREE MOVEMENT\\n%.1f"):gsub("\\n", "\n")
        timeSpiralText:SetFormattedText(fmtStr, remaining)
        timeSpiralFrame:Show()
        timeSpiralCountdownTimer = C_Timer.NewTimer(0.1, UpdateTimeSpiralCountdown)
    else
        timeSpiralActiveTime = nil
        timeSpiralFrame:Hide()
        CancelTimeSpiralCountdown()
    end
end

local function ApplyTimeSpiralFrame()
    local ma = MA()
    if not ma then return end
    -- Self-correct: if this got turned off while the banner was actively
    -- showing/counting down, the disable path only cancels the countdown
    -- timer (the one thing that would otherwise hide it) -- explicitly hide
    -- here so it can't get stuck on screen.
    if not ma.tsEnabled then
        timeSpiralActiveTime = nil
        CancelTimeSpiralCountdown()
        timeSpiralFrame:Hide()
        return
    end
    timeSpiralFrame:ClearAllPoints()
    local pos = ma.tsPos
    if pos and pos.point then
        timeSpiralFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        timeSpiralFrame:SetSize(pos.width or 200, pos.height or 40)
    else
        timeSpiralFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        timeSpiralFrame:SetSize(200, 40)
    end
    local fontPath, outline = AlertFontPath(), AlertFontOutline()
    local fontSize = math.max(10, math.min(72, math.floor(timeSpiralFrame:GetHeight() * 0.55)))
    if not timeSpiralText:SetFont(fontPath, fontSize, outline) then timeSpiralText:SetFont(FALLBACK_FONT, fontSize, outline) end
    local r, g, b = ResolveAlertColor("tsColor", "tsColorUseClass")
    timeSpiralText:SetTextColor(r, g, b)
end
EllesmereUI._applyTimeSpiral = ApplyTimeSpiralFrame

-------------------------------------------------------------------------------
--  Gateway Shard -- Warlock's Demonic Gateway control item
-------------------------------------------------------------------------------
local GATEWAY_SHARD_ITEM_ID = 188152
local gatewayFrame = CreateFrame("Frame", "EUI_GatewayShardFrame", UIParent)
gatewayFrame:SetSize(200, 40)
gatewayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
gatewayFrame:Hide()
local gatewayText = gatewayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
gatewayText:SetPoint("CENTER")

local lastGatewayUsable = false
local lastGatewayText = nil
local gatewayPollTicker = nil

local function StopGatewayPolling()
    if gatewayPollTicker then gatewayPollTicker:Cancel(); gatewayPollTicker = nil end
end

local function CheckGatewayUsable()
    local ma = MA()
    if not ma.gwEnabled then gatewayFrame:Hide(); StopGatewayPolling(); return end

    local ok, itemCount = pcall(C_Item.GetItemCount, GATEWAY_SHARD_ITEM_ID)
    itemCount = ok and itemCount or 0
    if itemCount == 0 then gatewayFrame:Hide(); lastGatewayUsable = false; return end

    -- Combat Only + out of combat: the result can't change until the next
    -- combat transition (PLAYER_REGEN_DISABLED resumes polling), so pause
    -- the ticker instead of continuing to poll the item API 10x/second for
    -- nothing.
    if ma.gwCombatOnly and not inCombat then
        gatewayFrame:Hide(); lastGatewayUsable = false
        StopGatewayPolling()
        return
    end

    local isUsable = not not C_Item.IsUsableItem(GATEWAY_SHARD_ITEM_ID)
    if isUsable and not lastGatewayUsable then FireTrackerAlert("gw") end
    lastGatewayUsable = isUsable

    -- 10 Hz poll: only the usability read is per-tick work; the label and
    -- visibility are written on change (a label edit still lands live).
    if isUsable then
        local txt = ma.gwText or "GATEWAY READY"
        if txt ~= lastGatewayText then
            lastGatewayText = txt
            gatewayText:SetText(txt)
        end
        if not gatewayFrame:IsShown() then gatewayFrame:Show() end
    elseif gatewayFrame:IsShown() then
        gatewayFrame:Hide()
    end
end
EllesmereUI._CheckGatewayUsable = CheckGatewayUsable

local function StartGatewayPolling()
    StopGatewayPolling()
    local ma = MA()
    if not ma.gwEnabled then return end
    CheckGatewayUsable()
    -- CheckGatewayUsable already self-pauses (via StopGatewayPolling) when
    -- Combat Only is on and we're out of combat -- don't immediately
    -- recreate the ticker it just stopped. PLAYER_REGEN_DISABLED calls
    -- StartGatewayPolling() again on combat entry to resume it.
    if ma.gwCombatOnly and not inCombat then return end
    gatewayPollTicker = C_Timer.NewTicker(0.1, CheckGatewayUsable)
end

local function ApplyGatewayFrame()
    local ma = MA()
    if not ma then return end
    gatewayFrame:ClearAllPoints()
    local pos = ma.gwPos
    if pos and pos.point then
        gatewayFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        gatewayFrame:SetSize(pos.width or 200, pos.height or 40)
    else
        gatewayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        gatewayFrame:SetSize(200, 40)
    end
    local fontPath, outline = AlertFontPath(), AlertFontOutline()
    local fontSize = math.max(10, math.min(72, math.floor(gatewayFrame:GetHeight() * 0.55)))
    if not gatewayText:SetFont(fontPath, fontSize, outline) then gatewayText:SetFont(FALLBACK_FONT, fontSize, outline) end
    local r, g, b = ResolveAlertColor("gwColor", "gwColorUseClass")
    gatewayText:SetTextColor(r, g, b)
    if not ma.gwEnabled then
        StopGatewayPolling()
        gatewayFrame:Hide()
    elseif EllesmereUI._unlockActive then
        -- Pause the poll ticker while Unlock Mode is active: CheckGatewayUsable
        -- can Hide() this frame the instant the item isn't currently usable
        -- (the common case), fighting the user mid-drag. Force it visible
        -- instead so it can be repositioned regardless of current item state.
        StopGatewayPolling()
        gatewayFrame:Show()
    else
        StartGatewayPolling()
    end
end
EllesmereUI._applyGateway = ApplyGatewayFrame

-------------------------------------------------------------------------------
--  Event registration
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")

-- Baseline events (spec/talent/combat/world transitions) drive the shared
-- caches all three trackers read. They are registered only while at least
-- one tracker is enabled, so a user with the whole page off pays for
-- nothing: no events fire and no spellbook cache work ever runs.
local BASELINE_EVENTS = {
    "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_ENTERING_WORLD", "PLAYER_DEAD",
}

local baselineEventsRegistered = false
local movementEventsRegistered = false
local timeSpiralEventsRegistered = false

local function UpdateEventRegistration()
    local ma = MA()
    if not ma then return end

    local moveOn = MovementEnabled()
    local anyEnabled = moveOn or ma.tsEnabled or ma.gwEnabled
    if anyEnabled and not baselineEventsRegistered then
        for _, ev in ipairs(BASELINE_EVENTS) do loader:RegisterEvent(ev) end
        baselineEventsRegistered = true
        -- The lookup/cache passes are skipped at login while everything is
        -- off, so the first enable must build them (and pick up the real
        -- combat state) before any tracker logic runs.
        inCombat = UnitAffectingCombat("player")
        RebuildMobilitySpellLookup()
        CacheMovementSpells(true)
        -- Register the bar-texture tables with SharedMedia (idempotent; also
        -- installs the session-long late-registration callback), matching the
        -- CDM Tracking Bars setup: a saved SM texture renders correctly
        -- without the options panel ever opening.
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER, nil, BAR_TEXTURES)
        end
    elseif not anyEnabled and baselineEventsRegistered then
        for _, ev in ipairs(BASELINE_EVENTS) do loader:UnregisterEvent(ev) end
        baselineEventsRegistered = false
        CancelAllRechargeTimers()
    end

    if moveOn and not movementEventsRegistered then
        loader:RegisterEvent("SPELL_UPDATE_USABLE")
        loader:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        loader:RegisterEvent("SPELL_UPDATE_CHARGES")
        loader:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        loader:RegisterUnitEvent("UNIT_AURA", "player")
        -- buffActive lane's identity gate (see BuffAlertAssistable): the
        -- occupancy latch plus the faction edge cinematics flip. Player-only,
        -- and only while the tracker is on. ENTERING as well as ENTERED --
        -- the filters degrade from the boarding transition. CINEMATIC_STOP
        -- covers the addon-cancelled skip, whose faction restore can order
        -- ahead of the edge above (the RF gate carries it for the same reason);
        -- the lane runs no ticker, so a missed restore leaves it hidden.
        loader:RegisterUnitEvent("UNIT_ENTERING_VEHICLE", "player")
        loader:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        loader:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
        loader:RegisterUnitEvent("UNIT_FACTION", "player")
        loader:RegisterEvent("CINEMATIC_STOP")
        -- The EXITED edge cannot reach a lane whose events are unregistered.
        SyncBuffAlertVehicleLatch()
        movementEventsRegistered = true
    elseif not moveOn and movementEventsRegistered then
        loader:UnregisterEvent("SPELL_UPDATE_USABLE")
        loader:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        loader:UnregisterEvent("SPELL_UPDATE_CHARGES")
        loader:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        loader:UnregisterEvent("UNIT_AURA")
        loader:UnregisterEvent("UNIT_ENTERING_VEHICLE")
        loader:UnregisterEvent("UNIT_EXITED_VEHICLE")
        loader:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        loader:UnregisterEvent("UNIT_FACTION")
        loader:UnregisterEvent("CINEMATIC_STOP")
        movementEventsRegistered = false
        CancelMovementCountdown()
    end

    if ma.tsEnabled and not timeSpiralEventsRegistered then
        loader:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        loader:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        loader:RegisterEvent("UNIT_SPELLCAST_SENT")
        timeSpiralEventsRegistered = true
        RefreshCastFilters()
    elseif not ma.tsEnabled and timeSpiralEventsRegistered then
        loader:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        loader:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        loader:UnregisterEvent("UNIT_SPELLCAST_SENT")
        timeSpiralEventsRegistered = false
        CancelTimeSpiralCountdown()
    end

    if ma.gwEnabled then StartGatewayPolling() else StopGatewayPolling(); if not ma.gwEnabled then gatewayFrame:Hide() end end
end
EllesmereUI._UpdateMovementAlertEvents = UpdateEventRegistration

loader:SetScript("OnEvent", function(self, event, ...)
    local ma = MA()
    if not ma then return end

    if event == "PLAYER_LOGIN" then
        -- Zero cost while every tracker is off: UpdateEventRegistration does
        -- the lookup/cache build when the first tracker registers baseline
        -- events (now, or later from the options toggle) -- nothing below
        -- runs for a user with the whole page disabled except the cheap
        -- unlock-mover registration.
        UpdateEventRegistration()
        if MovementEnabled() or ma.tsEnabled or ma.gwEnabled then
            ApplyMovementFrame(); ApplyTimeSpiralFrame(); ApplyGatewayFrame()
            CheckMovementCooldown()
            C_Timer.After(0.5, function()
                if ResolvePlayerSpecId() then CacheMovementSpells(true); CheckMovementCooldown() end
            end)
        end
        -- Unlock Mode elements: RegisterUnlockElements/MakeUnlockElement are
        -- safe to call immediately at login (no need for the extra delay
        -- some older modules used) -- registration itself just stores the
        -- config, it doesn't require Unlock Mode's own body to be loaded yet.
        if EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement then
            local MK = EllesmereUI.MakeUnlockElement

            local function MakeMoverEntry(key, label, order, isHiddenKey, getFrameFn, applyFn, posKey)
                return MK({
                    key   = key,
                    label = label,
                    group = "Quality of Life",
                    order = order,
                    -- isHiddenKey: profile key name, or a predicate function
                    -- (the movement tracker's enable state is per-class).
                    isHidden = function()
                        if type(isHiddenKey) == "function" then return not isHiddenKey() end
                        return not MA()[isHiddenKey]
                    end,
                    getFrame = getFrameFn,
                    getSize = function()
                        local pos = MA()[posKey]
                        return (pos and pos.width) or 200, (pos and pos.height) or 40
                    end,
                    setWidth = function(_, w)
                        local m = MA()
                        m[posKey] = m[posKey] or {}
                        m[posKey].width = math.max(60, math.floor(w + 0.5))
                        applyFn()
                    end,
                    setHeight = function(_, h)
                        local m = MA()
                        m[posKey] = m[posKey] or {}
                        m[posKey].height = math.max(20, math.floor(h + 0.5))
                        applyFn()
                    end,
                    savePos = function(_, point, relPoint, x, y)
                        if not point then return end
                        local m = MA()
                        m[posKey] = m[posKey] or {}
                        m[posKey].point, m[posKey].relPoint, m[posKey].x, m[posKey].y = point, relPoint, x, y
                    end,
                    loadPos = function()
                        local pos = MA()[posKey]
                        if pos and pos.point then return pos end
                        return nil
                    end,
                    clearPos = function()
                        MA()[posKey] = nil
                        applyFn()
                    end,
                    applyPos = applyFn,
                })
            end

            EllesmereUI:RegisterUnlockElements({
                MakeMoverEntry("EUI_MovementAlert", "Movement Alerts", 750, MovementEnabled, function() return movementFrame end, ApplyMovementFrame, "pos"),
                MakeMoverEntry("EUI_TimeSpiralAlert", "Movement Alerts - Time Spiral", 751, "tsEnabled", function() return timeSpiralFrame end, ApplyTimeSpiralFrame, "tsPos"),
                MakeMoverEntry("EUI_GatewayShardAlert", "Movement Alerts - Gateway Shard", 752, "gwEnabled", function() return gatewayFrame end, ApplyGatewayFrame, "gwPos"),
            })
        end
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
        if not InCombatLockdown() then
            CacheMovementSpells(true)
            CheckMovementCooldown()
            RefreshCastFilters()
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        CacheMovementSpells()
        CheckMovementCooldown()
    elseif event == "PLAYER_ENTERING_WORLD" then
        inCombat = UnitAffectingCombat("player")
        -- Safety net for an exit that never fires UNIT_EXITED_VEHICLE (being
        -- teleported out of one).
        SyncBuffAlertVehicleLatch()
        wipe(timeSpiralActiveSpells)
        timeSpiralActiveTime = nil
        CacheMovementSpells(true)
        CheckMovementCooldown()
        CheckGatewayUsable()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        CheckMovementCooldown()
        -- Combat Only paused the ticker on the last out-of-combat check;
        -- StartGatewayPolling() resumes it now that inCombat is true.
        -- (No-op beyond a single CheckGatewayUsable call when Combat Only
        -- isn't set, since the ticker was never stopped in that case.)
        if ma.gwEnabled then StartGatewayPolling() else CheckGatewayUsable() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        CancelAllRechargeTimers()
        wipe(chargeRechargeStart)
        for spellId in pairs(spellWasCast) do
            local cdInfo = C_Spell.GetSpellCooldown(spellId)
            local cdRemain = 0
            if cdInfo and cdInfo.startTime and cdInfo.duration
               and not IsSecret(cdInfo.startTime) and not IsSecret(cdInfo.duration) and cdInfo.duration > 0 then
                cdRemain = math.max(0, (cdInfo.startTime + cdInfo.duration) - GetTime())
            end
            if cdRemain <= 0 then spellWasCast[spellId] = nil; spellCastTime[spellId] = nil end
        end
        CacheMovementSpells()
        CheckMovementCooldown()
        CheckGatewayUsable()
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" or event == "SPELL_UPDATE_CHARGES" then
        RequestMovementCheckWithCharges()
    elseif event == "UNIT_AURA" then
        RequestMovementCheckWithCharges()
    elseif event == "UNIT_ENTERING_VEHICLE" or event == "UNIT_ENTERED_VEHICLE" then
        buffAlertVehicle = true
        RequestMovementCheck()
    elseif event == "UNIT_EXITED_VEHICLE" then
        buffAlertVehicle = false
        RequestMovementCheck()
    elseif event == "UNIT_FACTION" or event == "CINEMATIC_STOP" then
        -- Re-drive ONLY: a cinematic flips assistability with no vehicle
        -- involved, and BuffAlertAssistable's own probe reads that. Neither
        -- may touch the latch -- UNIT_FACTION also fires on the BOARDING
        -- transition, where clearing it would undo the suppression we just set.
        RequestMovementCheck()
    elseif event == "PLAYER_DEAD" then
        RequestMovementCheck()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellId = ...
        for _, mod in ipairs(TALENT_CD_REDUCTIONS) do
            if spellId == mod.trigger and IsPlayerSpell and IsPlayerSpell(mod.talent) then
                for _, entry in ipairs(cachedMovementSpells) do
                    if entry.spellId == mod.spell or entry.baseSpellId == mod.spell then
                        local sid = entry.spellId
                        local cur = cachedChargeCount[sid] or 0
                        if cur == 0 then
                            local rechargeStart = chargeRechargeStart[sid] or spellCastTime[sid]
                            local rechDur = entry.rechargeDuration or 0
                            if rechargeStart and rechDur > 0 then
                                local remaining = math.max(0, (rechargeStart + rechDur) - GetTime())
                                if remaining > 0 then
                                    if rechargeTimers[sid] then rechargeTimers[sid]:Cancel(); rechargeTimers[sid] = nil end
                                    local newRemaining = remaining - mod.reduce
                                    if newRemaining > 0 then
                                        chargeRechargeStart[sid] = GetTime() - (rechDur - newRemaining)
                                        StartRechargeTimer(entry, newRemaining)
                                    else
                                        cachedChargeCount[sid] = math.min(cur + 1, entry.maxCharges or 1)
                                        spellWasCast[sid] = nil; spellCastTime[sid] = nil
                                        if (cachedChargeCount[sid] or 0) < (entry.maxCharges or 1) then
                                            chargeRechargeStart[sid] = GetTime()
                                            StartRechargeTimer(entry)
                                        else
                                            chargeRechargeStart[sid] = nil
                                        end
                                    end
                                end
                            end
                        end
                        break
                    end
                end
            end
        end
        OnTrackedSpellCast(spellId)
        RequestMovementCheck()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, _, _, spellId = ...
        OnSpellCast(spellId)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local spellId = ...
        if ma.tsEnabled and IsValidTimeSpiralProc(spellId) then
            procDebounce = GetTime()
            timeSpiralActiveSpells[spellId] = true
            timeSpiralActiveTime = GetTime()
            FireTrackerAlert("ts")
            CancelTimeSpiralCountdown()
            UpdateTimeSpiralCountdown()
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellId = ...
        if spellId then timeSpiralActiveSpells[spellId] = nil end
        if not next(timeSpiralActiveSpells) then
            timeSpiralActiveTime = nil
            CancelTimeSpiralCountdown()
            timeSpiralFrame:Hide()
        end
    end
end)
