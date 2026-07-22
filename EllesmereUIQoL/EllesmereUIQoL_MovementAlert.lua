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

local inCombat = false

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
        [265] = {48020}, [266] = {48020}, [267] = {48020},
        filter = {[385899] = {385899}},
    },
    WARRIOR = {[71] = {6544}, [72] = {6544}, [73] = {6544}},
}

-- Buff-active spells (label shown while the aura is up instead of a
-- cooldown countdown). Currently empty -- Burning Rush was removed from
-- tracking -- but the machinery stays for future aura-style mobility spells.
local BUFF_ACTIVE_SPELLS = {}

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
            displayMode      = "text",   -- text (legacy) | text_nd | text_dn | icon | bar
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
    local _, class = UnitClass("player")
    return ec[class] == true
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
local BAR_TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local BAR_TEXTURES = {
    ["none"]          = nil,
    ["melli"]         = BAR_TEX_BASE .. "melli.tga",
    ["beautiful"]     = BAR_TEX_BASE .. "beautiful.tga",
    ["plating"]       = BAR_TEX_BASE .. "plating.tga",
    ["atrocity"]      = BAR_TEX_BASE .. "atrocity.tga",
    ["divide"]        = BAR_TEX_BASE .. "divide.tga",
    ["glass"]         = BAR_TEX_BASE .. "glass.tga",
    ["fade-right"]    = BAR_TEX_BASE .. "fade-right.tga",
    ["thin-line-top"]    = BAR_TEX_BASE .. "thin-line-top.tga",
    ["thin-line-bottom"] = BAR_TEX_BASE .. "thin-line-bottom.tga",
    ["fade"]          = BAR_TEX_BASE .. "fade.tga",
    ["gradient-lr"]   = BAR_TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = BAR_TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = BAR_TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = BAR_TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = BAR_TEX_BASE .. "matte.tga",
    ["sheer"]         = BAR_TEX_BASE .. "sheer.tga",
}
local BAR_TEXTURE_ORDER = {
    "none", "melli", "atrocity",
    "fade", "fade-right",
    "thin-line-top", "thin-line-bottom",
    "beautiful", "plating",
    "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local BAR_TEXTURE_NAMES = {
    ["none"]        = "None",
    ["melli"]       = "Melli (ElvUI)",
    ["beautiful"]   = "Beautiful",
    ["plating"]     = "Plating",
    ["atrocity"]    = "Atrocity",
    ["divide"]      = "Divide",
    ["glass"]       = "Glass",
    ["fade-right"]  = "Fade Right",
    ["thin-line-top"]    = "Thin Line Top",
    ["thin-line-bottom"] = "Thin Line Bottom",
    ["fade"]        = "Fade",
    ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left",
    ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down",
    ["matte"]       = "Matte",
    ["sheer"]       = "Sheer",
}
EllesmereUI._MovementBarTextures = {
    lookup = BAR_TEXTURES, order = BAR_TEXTURE_ORDER, names = BAR_TEXTURE_NAMES,
}

-- Named font object for the icon mode's cooldown countdown numbers --
-- SetCountdownFont takes the NAME of a named font object, and StyleSlot
-- re-points this one at the user's font/size.
local movementCdFont = CreateFont("EUI_MovementAlertCdFont")

local displayPool = {}
local activeSlotCount = 0
-- Tracks which tracked (non-buffActive) spellIDs were on cooldown as of the
-- last poll, so the "ready" TTS callout fires exactly once per cooldown
-- ending instead of every poll tick while the spell sits ready.
local readyAlertShown = {}

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
    slot.icon:Hide()

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
        local dur = C_Spell.GetSpellCooldownDuration(spellId)
        if dur then
            local total = dur:GetTotalDuration()
            if not IsSecret(total) and total and total > 1.5 then return total end
        end
    end
    if C_Spell.GetSpellBaseCooldown then
        local ms = C_Spell.GetSpellBaseCooldown(spellId)
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

    return result
end

local function UpdateCachedCharges()
    if inCombat or InCombatLockdown() then return end
    for _, entry in ipairs(cachedMovementSpells) do
        if entry.isChargeSpell then
            local chargeId = entry.baseSpellId or entry.spellId
            local chargeInfo = C_Spell.GetSpellCharges(chargeId)
            if chargeInfo and chargeInfo.currentCharges and not IsSecret(chargeInfo.currentCharges) then
                cachedChargeCount[entry.spellId] = chargeInfo.currentCharges
            end
        else
            local cdInfo = C_Spell.GetSpellCooldown(entry.spellId)
            if cdInfo and cdInfo.duration and not IsSecret(cdInfo.duration) and cdInfo.duration > 0 then
                entry.baseDuration = cdInfo.duration
            end
        end
    end
end

-- Buff-active tracking (e.g. Warlock Burning Rush): tracks auraInstanceID
-- from UNIT_AURA payloads so it also works while in combat.
local buffActiveState = {}
local expectingBuffAura = {}
local function BuffActiveKey(entry) return entry.spellId end
local function IsBuffActiveTrackedSpell(castSpellId)
    if BUFF_ACTIVE_SPELLS[castSpellId] then return castSpellId end
    local mapped = trackedSpellSet[castSpellId]
    if mapped and BUFF_ACTIVE_SPELLS[mapped] then return mapped end
    return nil
end
local function SetBuffActiveState(spellId, active, instanceID)
    buffActiveState[spellId] = { active = active, instanceID = instanceID }
end
local function ClearBuffActiveTracking()
    wipe(buffActiveState); wipe(expectingBuffAura)
end
local function IsBuffActiveDisplayed(entry)
    local key = BuffActiveKey(entry)
    local state = buffActiveState[key]
    if state and state.active then return true end
    if not inCombat and not InCombatLockdown() then
        return C_UnitAuras.GetPlayerAuraBySpellID(entry.spellId) ~= nil
    end
    return false
end
local function SyncBuffActiveOnCombatStart()
    for _, entry in ipairs(cachedMovementSpells) do
        if entry.checkType == "buffActive" then
            local key = BuffActiveKey(entry)
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(key)
            if aura and aura.auraInstanceID then SetBuffActiveState(key, true, aura.auraInstanceID) end
        end
    end
end
local function OnBuffActiveSpellCast(castSpellId)
    local key = IsBuffActiveTrackedSpell(castSpellId)
    if not key then return end
    local state = buffActiveState[key]
    if state and state.active then expectingBuffAura[key] = nil else expectingBuffAura[key] = true end
end
local function OnPlayerBuffActiveAuraUpdate(updateInfo)
    if not updateInfo then return end
    if updateInfo.removedAuraInstanceIDs then
        for _, entry in ipairs(cachedMovementSpells) do
            if entry.checkType == "buffActive" then
                local key = BuffActiveKey(entry)
                local state = buffActiveState[key]
                if state and state.instanceID then
                    for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
                        if instanceID == state.instanceID then
                            SetBuffActiveState(key, false, nil)
                            expectingBuffAura[key] = nil
                            break
                        end
                    end
                end
            end
        end
    end
    if updateInfo.addedAuras then
        for _, entry in ipairs(cachedMovementSpells) do
            if entry.checkType == "buffActive" then
                local key = BuffActiveKey(entry)
                if expectingBuffAura[key] then
                    -- Prefer an exact spellId match. Only fall back to
                    -- accepting a nil/secret spellId (can't compare it
                    -- directly) when it's the ONLY aura in this batch --
                    -- otherwise an unrelated aura landing in the same batch
                    -- as the real one could get matched instead.
                    local unambiguous = #updateInfo.addedAuras == 1
                    for _, aura in ipairs(updateInfo.addedAuras) do
                        local matches = (aura.spellId == key)
                            or (unambiguous and (not aura.spellId or IsSecret(aura.spellId)))
                        if matches and aura.auraInstanceID then
                            SetBuffActiveState(key, true, aura.auraInstanceID)
                            expectingBuffAura[key] = nil
                            break
                        end
                    end
                end
                for _, aura in ipairs(updateInfo.addedAuras) do
                    if aura.spellId and not IsSecret(aura.spellId) and aura.spellId == key and aura.auraInstanceID then
                        SetBuffActiveState(key, true, aura.auraInstanceID)
                    end
                end
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
        ClearBuffActiveTracking()
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

local function HideMovementDisplay()
    wipe(readyAlertShown)
    movementFrame:Hide()
    for _, slot in ipairs(displayPool) do
        slot.text:Hide(); slot.icon:Hide(); slot.icon.cooldown:Clear(); slot.bar:Hide(); slot:Hide()
    end
    activeSlotCount = 0
    CancelMovementCountdown()
end

local function ShowMovementSlot(index, cdInfo, spellEntry, duration)
    local ma = MA()
    local slot = GetDisplaySlot(index)
    StyleSlot(slot)
    local displayMode = ma.displayMode or "text"
    local precision   = ma.precision or 1
    local spellName   = spellEntry.customText or spellEntry.spellName or "Movement"
    local spellIcon   = spellEntry.spellIcon
    local precFmt     = "%." .. precision .. "f"
    -- spellName is free-form user text (per-spell Custom Text); escape
    -- literal "%" so SetFormattedText cannot misread it as a format
    -- directive expecting arguments it never gets.
    local escapedName = (spellName:gsub("%%", "%%%%"))
    -- Two fixed text arrangements, both reading as "No <ability>" (the
    -- alert shows while the spell is unavailable); the legacy "text" value
    -- keeps the old default's duration-first order.
    local fmtStr
    if displayMode == "text_nd" then
        fmtStr = "No " .. escapedName .. " " .. precFmt
    else
        fmtStr = precFmt .. " No " .. escapedName
    end

    slot.text:Hide(); slot.icon:Hide(); slot.bar:Hide()

    if cdInfo and cdInfo.timeUntilEndOfStartRecovery then
        if displayMode == "icon" and spellIcon then
            slot.icon.tex:SetTexture(spellIcon)
            slot.icon.cooldown:Clear()
            slot.icon.cooldown:SetHideCountdownNumbers(false)
            slot.icon:Show()
        elseif displayMode == "bar" then
            local rechDur = spellEntry.rechargeDuration or 0
            slot.bar:SetMinMaxValues(0, rechDur)
            slot.bar:SetValue(cdInfo.timeUntilEndOfStartRecovery)
            local r, g, b = ResolveAlertColor("textColor", "textColorUseClass")
            slot.bar:SetStatusBarColor(r, g, b)
            slot.bar.text:SetShown(ma.barShowDuration ~= false)
            if ma.barShowDuration ~= false then
                slot.bar.text:SetFormattedText("%." .. precision .. "f", cdInfo.timeUntilEndOfStartRecovery)
            end
            if ma.barShowIcon ~= false and spellIcon then slot.bar.icon:SetTexture(spellIcon); slot.bar.icon:Show() else slot.bar.icon:Hide() end
            slot.bar:Show()
        else
            slot.text:SetFormattedText(fmtStr, cdInfo.timeUntilEndOfStartRecovery)
            slot.text:Show()
        end
        slot:Show()
        return true
    end

    local cdRemaining, cdStart, cdDuration, cdModRate
    local hasSecretDuration = false
    if duration then
        local rem, total = duration:GetRemainingDuration(), duration:GetTotalDuration()
        if IsSecret(rem) or IsSecret(total) then
            hasSecretDuration = true
            cdRemaining, cdDuration = rem, total
            cdStart, cdModRate = duration:GetStartTime(), duration:GetModRate()
        elseif total and total > 1.5 and rem and rem > 0 then
            cdRemaining, cdDuration = rem, total
            cdStart, cdModRate = duration:GetStartTime(), duration:GetModRate()
        end
    end

    if not cdRemaining and cdInfo then
        local s, d, m = cdInfo.startTime or 0, cdInfo.duration or 0, cdInfo.modRate or 1
        if IsSecret(s) or IsSecret(d) then
            hasSecretDuration = true
            cdStart, cdDuration, cdModRate, cdRemaining = s, d, m, true
        elseif d > 0 then
            cdStart, cdDuration, cdModRate = s, d, m
            cdRemaining = math.max(0, (s + d) - GetTime())
        end
    end

    if not cdRemaining then return false end
    if not hasSecretDuration and cdRemaining <= 0 then return false end

    if displayMode == "icon" then
        if spellIcon then
            slot.icon.tex:SetTexture(spellIcon)
            if duration and slot.icon.cooldown.SetCooldownFromDurationObject then
                slot.icon.cooldown:SetCooldownFromDurationObject(duration, true)
            else
                slot.icon.cooldown:SetCooldown(cdStart, cdDuration, cdModRate)
            end
            slot.icon.cooldown:SetHideCountdownNumbers(false)
            slot.icon:Show()
        else
            slot.text:SetFormattedText(fmtStr, cdRemaining)
            slot.text:Show()
        end
    elseif displayMode == "bar" then
        slot.bar:SetMinMaxValues(0, cdDuration)
        slot.bar:SetValue(cdRemaining)
        local r, g, b = ResolveAlertColor("textColor", "textColorUseClass")
        slot.bar:SetStatusBarColor(r, g, b)
        slot.bar.text:SetShown(ma.barShowDuration ~= false)
        if ma.barShowDuration ~= false then
            slot.bar.text:SetFormattedText("%." .. precision .. "f", cdRemaining)
        end
        if ma.barShowIcon ~= false and spellIcon then slot.bar.icon:SetTexture(spellIcon); slot.bar.icon:Show() else slot.bar.icon:Hide() end
        slot.bar:Show()
    else -- any text mode (text_nd / text_dn / legacy "text")
        slot.text:SetFormattedText(fmtStr, cdRemaining)
        slot.text:Show()
    end

    slot:Show()
    return true
end

local function ShowBuffActiveSlot(index, spellEntry)
    local ma = MA()
    local slot = GetDisplaySlot(index)
    StyleSlot(slot)
    local displayMode = ma.displayMode or "text"
    local spellName = spellEntry.customText or spellEntry.spellName or "Active!"
    local spellIcon = spellEntry.spellIcon

    slot.text:Hide(); slot.icon:Hide(); slot.bar:Hide()

    if displayMode == "icon" and spellIcon then
        slot.icon.tex:SetTexture(spellIcon)
        slot.icon.cooldown:Clear()
        slot.icon.cooldown:SetHideCountdownNumbers(true)
        slot.icon:Show()
    elseif displayMode == "bar" then
        slot.bar:SetMinMaxValues(0, 1); slot.bar:SetValue(1)
        local r, g, b = ResolveAlertColor("textColor", "textColorUseClass")
        slot.bar:SetStatusBarColor(r, g, b)
        -- Name label, not a duration -- always shown (and the shared
        -- fontstring may have been hidden by the Show Duration Text gate).
        slot.bar.text:Show()
        slot.bar.text:SetText(spellName)
        if ma.barShowIcon ~= false and spellIcon then slot.bar.icon:SetTexture(spellIcon); slot.bar.icon:Show() else slot.bar.icon:Hide() end
        slot.bar:Show()
    else
        slot.text:SetText(spellName)
        slot.text:Show()
    end

    slot:Show()
    return true
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
    local nowShownReady = {}
    for _, entry in ipairs(cachedMovementSpells) do
        if entry.checkType == "buffActive" then
            if IsBuffActiveDisplayed(entry) then
                if ShowBuffActiveSlot(count + 1, entry) then count = count + 1 end
            end
        else
            local spellId = entry.baseSpellId or entry.spellId
            local hasCharges = C_Spell.GetSpellCharges(spellId)
            local spellInfo  = C_Spell.GetSpellCooldown(spellId)
            if spellInfo and spellInfo.timeUntilEndOfStartRecovery and
               (spellInfo.isOnGCD == false or (spellInfo.isOnGCD == nil and not hasCharges)) then
                local duration
                if entry.isChargeSpell and C_Spell.GetSpellChargeDuration then
                    duration = C_Spell.GetSpellChargeDuration(spellId)
                elseif not entry.isChargeSpell and C_Spell.GetSpellCooldownDuration then
                    duration = C_Spell.GetSpellCooldownDuration(spellId)
                end
                if ShowMovementSlot(count + 1, spellInfo, entry, duration) then
                    count = count + 1
                    nowShownReady[entry.spellId] = entry
                end
            end
        end
    end

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
    readyAlertShown = nowShownReady

    for i = count + 1, activeSlotCount do
        local slot = displayPool[i]
        if slot then slot.text:Hide(); slot.icon:Hide(); slot.icon.cooldown:Clear(); slot.bar:Hide(); slot:Hide() end
    end

    if count > 0 then
        activeSlotCount = count
        LayoutDisplaySlots(count)
        movementFrame:Show()
        CancelMovementCountdown()
        -- Fixed 100ms display refresh (smooth 1-decimal countdown).
        movementCountdownTimer = C_Timer.NewTimer(0.1, CheckMovementCooldown)
    else
        activeSlotCount = 0
        HideMovementDisplay()
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
        and EllesmereUI.GetActivePage and EllesmereUI:GetActivePage() == "Movement Alerts"
    if not ma or not onPage then StopMovementPreview(); return end

    local now = GetTime()
    if now >= previewEnds then previewEnds = now + PREVIEW_CD end
    previewCdInfo.startTime = previewEnds - PREVIEW_CD
    if ShowMovementSlot(1, previewCdInfo, previewEntry) then
        for i = 2, activeSlotCount do
            local slot = displayPool[i]
            if slot then slot.text:Hide(); slot.icon:Hide(); slot.icon.cooldown:Clear(); slot.bar:Hide(); slot:Hide() end
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
local gatewayText = gatewayFrame:CreateFontString(nil, "OVERLAY")
gatewayText:SetPoint("CENTER")

local lastGatewayUsable = false
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

    if isUsable then
        gatewayText:SetText(ma.gwText or "GATEWAY READY")
        gatewayFrame:Show()
    else
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
        movementEventsRegistered = true
        -- Toggling the master switch off then back on mid-combat would
        -- otherwise leave buffActiveState (e.g. Burning Rush) stale until
        -- the next aura change, since it's normally only synced on
        -- PLAYER_REGEN_DISABLED/PLAYER_ENTERING_WORLD.
        if inCombat then SyncBuffActiveOnCombatStart() end
    elseif not moveOn and movementEventsRegistered then
        loader:UnregisterEvent("SPELL_UPDATE_USABLE")
        loader:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        loader:UnregisterEvent("SPELL_UPDATE_CHARGES")
        loader:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        loader:UnregisterEvent("UNIT_AURA")
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
        wipe(timeSpiralActiveSpells)
        timeSpiralActiveTime = nil
        CacheMovementSpells(true)
        if inCombat then SyncBuffActiveOnCombatStart() end
        CheckMovementCooldown()
        CheckGatewayUsable()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        SyncBuffActiveOnCombatStart()
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
        UpdateCachedCharges()
        CheckMovementCooldown()
    elseif event == "UNIT_AURA" then
        local unit, updateInfo = ...
        if unit == "player" then OnPlayerBuffActiveAuraUpdate(updateInfo) end
        UpdateCachedCharges()
        CheckMovementCooldown()
    elseif event == "PLAYER_DEAD" then
        ClearBuffActiveTracking()
        CheckMovementCooldown()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellId = ...
        if unit == "player" then OnBuffActiveSpellCast(spellId) end
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
        CheckMovementCooldown()
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
