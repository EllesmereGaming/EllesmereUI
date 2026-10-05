if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Text.lua
--
--  ns.Colors and the engine painters, smart power percent, text decimals,
--  tags, nicknames and zone formatters. Publishes through I; loads before
--  Layout and Power, which re-import from it. db is set through I.dbSetters.
-------------------------------------------------------------------------------
local addonName, ns = ...

local GetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
local string_format = string.format
local issecretvalue = issecretvalue

local I = ns._internals
local frames, AbbreviateNumbers = I.frames, I.AbbreviateNumbers
local UF_SecretSafeHealthColor = I.UF_SecretSafeHealthColor
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Engine painters (oUF extraction). ns.Colors carries the exact color table
--  the shared color chains read through frame.colors: same value sources and
--  shapes as before, so every existing color decision lands on identical
--  numbers. Class entries are overwritten by the suite palette sync (the same
--  flow that used to write the library's table); reaction entries by the
--  module's own reaction sync. Published as EllesmereUI._UFColors so the
--  parent's color chokepoint can reach it.
-------------------------------------------------------------------------------
do
    local CreateColor = _G.CreateColor
    local colors = {
        health       = CreateColor(49 / 255, 207 / 255, 37 / 255),
        disconnected = CreateColor(0.6, 0.6, 0.6),
        tapped       = CreateColor(0.6, 0.6, 0.6),
        class    = {},
        reaction = {},
        threat   = {},
        power    = {},
    }
    for token, c in pairs(RAID_CLASS_COLORS) do
        colors.class[token] = CreateColor(c.r, c.g, c.b)
    end
    for idx, c in pairs(FACTION_BAR_COLORS) do
        colors.reaction[idx] = CreateColor(c.r, c.g, c.b)
    end
    for i = 0, 3 do
        colors.threat[i] = CreateColor(GetThreatStatusColor(i))
    end
    -- Both key forms land: Blizzard's table carries string tokens plus numeric
    -- aliases, and the painter looks up number-first, token-second.
    for key, c in pairs(PowerBarColor) do
        if type(c) == "table" and c.r then
            colors.power[key] = CreateColor(c.r, c.g, c.b)
        end
    end
    -- Dispel colors keyed by the game's dispel-type indices (the aura rows'
    -- type overlay reads these through a step curve). Blizzard's shared color
    -- objects are referenced directly; Enrage has no stock color.
    colors.dispel = {
        [0]  = _G.DEBUFF_TYPE_NONE_COLOR,
        [1]  = _G.DEBUFF_TYPE_MAGIC_COLOR,
        [2]  = _G.DEBUFF_TYPE_CURSE_COLOR,
        [3]  = _G.DEBUFF_TYPE_DISEASE_COLOR,
        [4]  = _G.DEBUFF_TYPE_POISON_COLOR,
        [9]  = CreateColor(243 / 255, 95 / 255, 245 / 255),
        [11] = _G.DEBUFF_TYPE_BLEED_COLOR,
    }
    ns.Colors = colors
    EllesmereUI._UFColors = colors

    -- Health value pass: min/max plus current (offline paints a full bar, the
    -- behavior users already see), native interpolation via the bar's own
    -- .smoothing, then the shared secret-safe color chain.
    local function PaintHealth(frame, unit, event)
        local element = frame.Health
        if not element or not unit then return end
        -- A UNIT_HEALTH delivery for this token proves the unit exists (the
        -- tracker only routes real unit events under that name); the identity
        -- and forced paths still pay the probe.
        if event ~= "UNIT_HEALTH" and not UnitExists(unit) then return end
        if not ns.Engine.ElementOn(frame, "Health") then return end
        -- Bar bounds ride the max-health/identity events (Blizzard's own
        -- contract); a pure UNIT_HEALTH value tick pushes only the value.
        if event ~= "UNIT_HEALTH" or not element._maxSet then
            element._maxSet = true
            element:SetMinMaxValues(0, UnitHealthMax(unit))
        end
        -- A corpse fires no further UNIT_HEALTH, so the death tick's paint is the
        -- last one the bar gets: zero it from the dead flag (a plain boolean in
        -- restricted content, where the value is secret) instead of the value,
        -- and without the interpolation, which otherwise eases toward zero and
        -- leaves a sliver standing on a bar that gets no further ticks.
        -- UnitIsDead, not UnitIsDeadOrGhost: a ghost is at full health, and
        -- Blizzard's own bar reads it the same way (CompactUnitFrame_UpdateHealthColor).
        if not UnitIsConnected(unit) then
            element:SetValue(UnitHealthMax(unit), element.smoothing)
        elseif UnitIsDead(unit) then
            element:SetValue(0)
        else
            element:SetValue(UnitHealth(unit), element.smoothing)
        end
        -- Color inputs (class/reaction/dark/disconnect/tap) change via their
        -- own events or identity repaints -- a pure health tick re-runs the
        -- color chain only for modes whose color follows health/combat state
        -- per tick (dynamic curve, threat). The color* flags are
        -- never set by this engine; the dynamic modes live in PostUpdateColor
        -- (ns.UF_DynamicHealthColor) behind the unit's healthColorMode, so that
        -- setting is the gate that keeps a dynamic bar tracking every tick.
        local unitKey = element._euiUnitKey
        local unitColorMode = unitKey and db.profile[unitKey]
        unitColorMode = unitColorMode and unitColorMode.healthColorMode
        if event ~= "UNIT_HEALTH" or element.colorSmooth or element.colorThreat
           or (unitColorMode and unitColorMode ~= "none") then
            UF_SecretSafeHealthColor(frame, event, unit)
        end
    end
    ns.Engine.SetPainter("health", PaintHealth)

    -- Power value pass: display-power resolution first (the player bar's
    -- spec-override hook publishes the resolved type for the text formatters),
    -- then min/max/value with offline painting full, then the base power-type
    -- color with the bar's own PostUpdateColor/PostUpdate layered on top in
    -- the same order as before.
    local function PaintPower(frame, unit, event)
        local element = frame.Power
        if not element or not unit or not UnitExists(unit) then return end
        if not ns.Engine.ElementOn(frame, "Power") then return end
        local ptype
        if element.displayAltPower and element.GetDisplayPower then
            ptype = element:GetDisplayPower(unit)
        end
        element.displayType = ptype
        local pnum, ptoken
        if ptype then pnum = ptype else pnum, ptoken = UnitPowerType(unit) end
        -- The resolved type for the value pass below, and its token in the
        -- power events' payload form for the engine's event filter. A secret
        -- type stashes nothing (no filter; the value pass paints in full).
        if issecretvalue(pnum) then
            element._euiPNum, element._euiPTok = nil, nil
        else
            element._euiPNum = pnum
            element._euiPTok = (not issecretvalue(ptoken) and ptoken)
                or EllesmereUI.POWER_ENUM_TO_KEY[pnum]
        end
        if element._manaRegenSpark then
            EllesmereUI.ManaRegenSpark.SetMana("uf", not issecretvalue(pnum) and pnum == Enum.PowerType.Mana)
        end
        local max = UnitPowerMax(unit, pnum)
        element:SetMinMaxValues(0, max)
        local cur
        if UnitIsConnected(unit) then
            cur = UnitPower(unit, pnum)
            element:SetValue(cur, element.smoothing)
        else
            cur = max
            element:SetValue(max, element.smoothing)
        end
        if element.colorPower then
            local color = ns.Colors.power[pnum] or (ptoken and ns.Colors.power[ptoken])
            if color then element:SetStatusBarColor(color:GetRGB()) end
        end
        if element.PostUpdateColor then element:PostUpdateColor(unit) end
        if element.PostUpdate then element:PostUpdate(unit, cur, 0, max) end
    end
    ns.Engine.SetPainter("power", PaintPower)

    -- Power value pass (the player's powerval channel, UNIT_POWER_FREQUENT):
    -- the bar value and the text zones that read power, nothing else. Bounds,
    -- colours, the gray-out, the display-type override and the regen spark's
    -- mana flag follow the power type, the unit or the settings, never the
    -- value, and stay on the full pass (UNIT_POWER_UPDATE, UNIT_MAXPOWER,
    -- UNIT_DISPLAYPOWER and every identity repaint), which also refreshes the
    -- stashed type. The cost prediction segment is anchored to the fill edge
    -- and moves with SetValue. With no readable stashed type the full pass
    -- runs instead.
    ns.Engine.SetValuePainter(function(frame, unit)
        local element = frame.Power
        if not element or not unit or not UnitExists(unit) then return end
        if not ns.Engine.ElementOn(frame, "Power") then return end
        local pnum = element._euiPNum
        if pnum == nil then
            PaintPower(frame, unit, "UNIT_POWER_FREQUENT")
        elseif UnitIsConnected(unit) then
            element:SetValue(UnitPower(unit, pnum), element.smoothing)
        end
        ns.UF_PaintPowerText(frame, unit)
    end)

    -- Absorbs: the HealthPrediction Override was always our own complete
    -- painter (bars, clips, text gates); the engine simply becomes its event
    -- source. Identity repaints arrive as pseudo-events, which the Override
    -- already treats as gate-refresh triggers.
    local function PaintAbsorb(frame, unit, event)
        if not ns.Engine.ElementOn(frame, "HealthPrediction") then return end
        local hp = frame.HealthPrediction
        if hp and hp.Override then hp.Override(frame, event or "ForceUpdate", unit) end
    end
    ns.Engine.SetPainter("absorb", PaintAbsorb)
end

-- Global Dark Mode master: exposes darkTheme so the parent addon's master toggle can
-- flip it with other modules. setOn mirrors the individual toggle (write flag + reload).
EllesmereUI.RegisterDarkModeToggle({
    id = "unitFrames",
    isOn = function()
        return (db and db.profile and db.profile.darkTheme) or false
    end,
    setOn = function(on)
        if not (db and db.profile) then return end
        db.profile.darkTheme = on
        if ns.ReloadFrames then ns.ReloadFrames() end
    end,
})

-- Smart power text: percent for healers/prot pally/arcane mage, numeric for the rest.
-- Shared by the oUF tag and the resource bars renderer. `displayedPowerType` (optional
-- Enum.PowerType) is the power the caller's bar actually shows; for form/spec-shifting
-- classes (Druid, Monk) the decision MUST follow the displayed power, not UnitPowerType --
-- a Balance druid's UnitPowerType is Astral Power even while the bar shows Mana, so the
-- mana number would render raw instead of percent otherwise.
local function EUI_IsSmartPowerPercent(displayedPowerType)
    local _, cls = UnitClass("player")
    if not cls then return false end
    -- Druid/Monk shift displayed power with form/spec: percent only while the bar shows
    -- Mana (Druid caster/Tree/travel + Mistweaver); raw otherwise (Cat=Energy, Bear=Rage,
    -- Moonkin=Astral, WW/BRM=Energy, incl. Restoration weaving Cat/Bear). Prefer the
    -- caller-supplied displayed power, else the live primary power type.
    if cls == "DRUID" or cls == "MONK" then
        local pt = displayedPowerType or UnitPowerType("player")
        return pt == Enum.PowerType.Mana
    end
    if cls == "PRIEST" or cls == "SHAMAN" then
        return true
    end
    -- Paladin: Holy and Protection (mana-based specs).
    if cls == "PALADIN" then
        local spec = GetSpecialization()
        return spec == 1 or spec == 2  -- Holy, Protection
    end
    -- Mage: only Arcane
    if cls == "MAGE" then
        local spec = GetSpecialization()
        return spec == 1  -- Arcane
    end
    -- Evoker: only Preservation
    if cls == "EVOKER" then
        local spec = GetSpecialization()
        return spec == 2  -- Preservation
    end
    return false
end
ns.EUI_IsSmartPowerPercent = EUI_IsSmartPowerPercent
EllesmereUI.IsSmartPowerPercent = EUI_IsSmartPowerPercent

-- Show Decimal on Text (global): AbbreviateNumbers config emitting one decimal per
-- magnitude band (240500 -> "240.5k", 2405000 -> "2.4m"). AbbreviateNumbers runs in
-- Blizzard's secure context, so a secret value plus this config stays secret-safe
-- (like the no-config call on secret health/power). Tags read these _G flags:
--   _G._EUI_AbbrevDecimalCfg = this table when on, nil when off
--   _G._EUI_TextDecimals     = true/false, selects "%.1f" vs "%d" for percents
--   _G._EUI_PctTrim          = { curve, cfg } trimming the percent, nil when off
-- Per band: significandDivisor = breakpoint / d, fractionDivisor = d (d = 10 for
-- one decimal, 100 for two). Ten-thousand-grouping locales (koKR/zhCN/zhTW) take
-- the shared number engine's thousand/wan/yi units instead of k/m/b, so these
-- frames read the same as Damage Meters and the gold bar on those clients.
local function DecimalAbbrevConfig(d)
    local g = EllesmereUI.NumberAbbrevGlyphs()
    if g then
        return { breakpointData = {
            { breakpoint = 1e8, abbreviation = g[3], significandDivisor = 1e8 / d, fractionDivisor = d, abbreviationIsGlobal = false },
            { breakpoint = 1e4, abbreviation = g[2], significandDivisor = 1e4 / d, fractionDivisor = d, abbreviationIsGlobal = false },
            { breakpoint = 1e3, abbreviation = g[1], significandDivisor = 1e3 / d, fractionDivisor = d, abbreviationIsGlobal = false },
        } }
    end
    return { breakpointData = {
        { breakpoint = 1e9, abbreviation = "b", significandDivisor = 1e9 / d, fractionDivisor = d, abbreviationIsGlobal = false },
        { breakpoint = 1e6, abbreviation = "m", significandDivisor = 1e6 / d, fractionDivisor = d, abbreviationIsGlobal = false },
        { breakpoint = 1e3, abbreviation = "k", significandDivisor = 1e3 / d, fractionDivisor = d, abbreviationIsGlobal = false },
    } }
end
-- WoW Forever: nothing under 10,000 abbreviates, so the k band starts there and
-- the thousand band goes (the shared engine's trim, EllesmereUI_NumberFormat.lua).
if EllesmereUI.IS_FOREVER then
    local bands = DecimalAbbrevConfig
    DecimalAbbrevConfig = function(d)
        local cfg = bands(d)
        cfg.breakpointData = EllesmereUI.ForeverAbbrevTiers(cfg.breakpointData)
        return cfg
    end
end
-- "Hide Trailing Zeros": AbbreviateNumbers drops a zero fraction ("100") but keeps a
-- real one ("99.5"), which "%.1f" cannot do and a SECRET percent forbids doing with
-- Lua string ops. It TRUNCATES though, so a fractional significandDivisor reads a tenth
-- low (0.1 renders 33.3 as "33.2"); the curve scales instead, handing over whole
-- tenths/hundredths, +0.5 so truncation lands where "%.1f" would have rounded.
local function MakePctTrim(scale, fractionDivisor)
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    curve:AddPoint(0.0, 0.5)
    curve:AddPoint(1.0, scale + 0.5)
    return {
        curve = curve,
        cfg = { breakpointData = {
            { breakpoint = 0, abbreviation = "", significandDivisor = 1, fractionDivisor = fractionDivisor, abbreviationIsGlobal = false },
        } },
    }
end
ns._pctTrim  = MakePctTrim(1000, 10)
ns._pctTrim2 = MakePctTrim(10000, 100)
function ns.ApplyTextDecimalGlobals()
    if db and db.profile and db.profile.showDecimalOnText then
        -- Built on first use, not at file load: a standalone build reads the Language
        -- override at its own ADDON_LOADED, after this file. The locale is fixed per session.
        if not ns._decimalAbbrevConfig then
            ns._decimalAbbrevConfig = DecimalAbbrevConfig(10)
            -- Two-decimal variant for boss frames ("Show 2 for Boss"): 240.55k / 2.45m.
            ns._decimalAbbrevConfig2 = DecimalAbbrevConfig(100)
        end
        _G._EUI_TextDecimals = true
        -- "Only Show for % Health": decimal on PERCENT, health/absorb VALUES whole --
        -- withhold the abbreviate configs (values fall back to plain AbbreviateNumbers)
        -- while _EUI_TextDecimals stays true for percents.
        local percentOnly = db.profile.showDecimalPercentOnly
        _G._EUI_AbbrevDecimalCfg = ns._decimalAbbrevConfig
        if percentOnly then _G._EUI_AbbrevDecimalCfg = nil end
        -- Percent-only, so "Only Show for % Health" never withholds these.
        local trimZeros = db.profile.showDecimalTrimZeros
        _G._EUI_PctTrim = trimZeros and ns._pctTrim or nil
        -- Boss frames get a second decimal place. Tags use the 1-decimal path
        -- for non-boss units when the flag is set, and ignore it when nil.
        if db.profile.showDecimalBoss2 ~= false then
            _G._EUI_BossExtraDecimal = true
            _G._EUI_AbbrevDecimalCfg2 = ns._decimalAbbrevConfig2
            if percentOnly then _G._EUI_AbbrevDecimalCfg2 = nil end
            _G._EUI_PctTrim2 = trimZeros and ns._pctTrim2 or nil
        else
            _G._EUI_BossExtraDecimal = false
            _G._EUI_AbbrevDecimalCfg2 = nil
            _G._EUI_PctTrim2 = nil
        end
    else
        _G._EUI_TextDecimals = false
        _G._EUI_AbbrevDecimalCfg = nil
        _G._EUI_BossExtraDecimal = false
        _G._EUI_AbbrevDecimalCfg2 = nil
        _G._EUI_PctTrim = nil
        _G._EUI_PctTrim2 = nil
    end
end

-- Shared text-piece functions consumed by the zone formatter table below.
local TagFns = {}

do
  local function AbbrevHP(unit)
    if not unit or not UnitExists(unit) then return "" end
    if not UnitIsConnected(unit) then return "OFFLINE" end
    if UnitIsDeadOrGhost(unit) then return "DEAD" end
    local hp = UnitHealth(unit) or 0
    local cfg = _G._EUI_AbbrevDecimalCfg
    -- Boss frames use the 2-decimal config when "Show 2 for Boss" is on.
    if _G._EUI_BossExtraDecimal and string.sub(unit, 1, 4) == "boss" then
      cfg = _G._EUI_AbbrevDecimalCfg2
    end
    return cfg and AbbreviateNumbers(hp, cfg) or AbbreviateNumbers(hp)
  end

  TagFns.curhpshort = AbbrevHP
end

do
  -- Health percent under the decimal options. "Hide Trailing Zeros" reads the percent
  -- through a scaling curve so AbbreviateNumbers can drop the zero "%.1f" would pad.
  local function PercentHP(unit)
    -- Predicted percent (incoming heals) can outlive the unit: a corpse fires no
    -- further UNIT_HEALTH and the text channel never hears UNIT_HEAL_PREDICTION.
    -- Corpses only, like Blizzard's health paths: a ghost is at full health, and
    -- the neighbouring DEAD zone is the piece that speaks for dead-or-ghost.
    if UnitIsDead(unit) then return "0" end
    local boss = _G._EUI_BossExtraDecimal and string.sub(unit, 1, 4) == "boss"
    local trim = _G._EUI_PctTrim
    if boss then trim = _G._EUI_PctTrim2 end
    if trim then
      local scaled = UnitHealthPercent(unit, true, trim.curve)
      if not scaled then return "0" end
      return AbbreviateNumbers(scaled, trim.cfg)
    end
    local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    if not pct then return "0" end
    if boss then return string_format("%.2f", pct) end
    return string_format(_G._EUI_TextDecimals and "%.1f" or "%d", pct)
  end

  TagFns.perhp = PercentHP
  TagFns.perhpnosign = function(unit)
    if not unit or not UnitExists(unit) then return "" end
    if not UnitIsConnected(unit) then return "OFFLINE" end
    if UnitIsDeadOrGhost(unit) then return "DEAD" end
    return PercentHP(unit)
  end
end

-- Resolved power type per unit. Updated by the GetDisplayPower override so the
-- power text matches the power bar when powerTypeOverride is active (e.g.
-- Balance Druid showing Mana instead of Astral Power).
_G._EUI_ResolvedPowerType = _G._EUI_ResolvedPowerType or {}

local PLAYER_POWER_DEFAULT = {
    PRIEST = { [3] = 0 },   -- Shadow: default to Mana
    MONK   = { [2] = 0 },   -- Mistweaver: default to Mana
}
local PLAYER_POWER_ALT = {
    DRUID  = { [1] = 0, [2] = 0, [3] = 0 },  -- Balance/Feral/Guardian -> Mana
    PRIEST = { [3] = nil },                     -- Shadow alt -> Insanity (UnitPowerType)
    SHAMAN = { [1] = 0 },                       -- Elemental -> Mana
}

-- Forced display power type for the player (number = Enum.PowerType, nil =
-- UnitPowerType decides). Shared by the bar's GetDisplayPower, the color
-- resolver and the options preview so all three agree.
function EllesmereUI.GetPlayerPowerOverride()
    if not (db and db.profile) then return nil end
    local _, classFile = UnitClass("player")
    -- WoW Forever has no retail specs, so the spec tables below never apply
    -- there: only the druid "Power Type: Mana" choice, under its own string key.
    if EllesmereUI.IS_FOREVER then
        if classFile ~= "DRUID" then return nil end
        local ov = db.profile.player and db.profile.player.powerTypeOverride
        return (ov and ov.foreverDruid) and 0 or nil
    end
    local classDef = PLAYER_POWER_DEFAULT[classFile]
    local classAlt = PLAYER_POWER_ALT[classFile]
    if not (classDef or classAlt) then return nil end
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return nil end
    -- powerTypeOverride is keyed by SPEC ID, never the GetSpecialization() index:
    -- the set is profile-wide, so an index key collides across classes (slot 3 is
    -- Guardian, Shadow AND Augmentation). classAlt/classDef stay index-keyed --
    -- they are nested per class already, so they cannot collide. Resource Bars may
    -- be disabled, hence the direct fallback.
    local sid = (_G._ERB_ResolveSpecIDCached and _G._ERB_ResolveSpecIDCached())
        or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(spec))
        or nil
    local ov = db.profile.player and db.profile.player.powerTypeOverride
    if sid and ov and ov[sid] and classAlt then
        return classAlt[spec]
    elseif classDef and classDef[spec] ~= nil then
        return classDef[spec]
    end
    return nil
end

-- (The perpp/curpp/absorb piece functions live in the zone-formatter block
-- below; they read the _EUI_ globals above.)

-- Effective level (scaling-aware), "??" when unknowable (skull bosses). A
-- SECRET level is returned RAW -- display-safe as a %s arg through
-- SetFormattedText, never compared/formatted in Lua (same rule as the secret
-- name in the target-name piece).
TagFns.level = function(u)
    if not u or not UnitExists(u) then return "" end
    local l = UnitEffectiveLevel(u)
    if UnitIsWildBattlePet(u) or UnitIsBattlePetCompanion(u) then
        l = UnitBattlePetLevel(u)
    end
    if l and issecretvalue and issecretvalue(l) then return l end
    if not l or l <= 0 then return "??" end
    return l
end

-- Class/reaction color for a unit's NAME, enemy-aware: players (and AI party members)
-- get class color; NPCs use reaction color (hostile red, neutral yellow, friendly
-- green, tap-denied gray). Custom Enemy Colors override is honored via oUF.colors.reaction.
-- Returns r,g,b (0-1) or nil (caller's own default); secret-safe for uninspectable units.
-- On ns for the local cap; shared by ApplyClassColor and eui-tgtname so "Name > Target"
-- colors like the unit frame name.
ns.ResolveUnitNameColor = function(unit)
    if not unit then return nil end
    if UnitIsPlayer(unit) or (UnitInPartyIsAI and UnitInPartyIsAI(unit)) then
        local _, class = UnitClass(unit)
        if not issecretvalue(class) and class then
            local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
            if c then return c.r, c.g, c.b end
        end
        return nil
    end
    if UnitExists(unit) then
        if UnitIsTapDenied and UnitIsTapDenied(unit) then
            return 0.6, 0.6, 0.6
        end
        local reaction = UnitReaction(unit, "player")
        if reaction and not issecretvalue(reaction) then
            local c = (ns.Colors and ns.Colors.reaction and ns.Colors.reaction[reaction])
                or FACTION_BAR_COLORS[reaction]
            if c then return c.r, c.g, c.b end
        end
    end
    return nil
end

-- Shared secret-class-color recovery for identity-restricted units (ToT, focus-target):
-- the user's custom color for a matching group member, else Blizzard's shade. Used by
-- ResolveBgClassColor and ApplyClassColor; ResolveUnitNameColor does NOT use this, since
-- its result also feeds the [eui-tgtcol] hex-escape tag, which cannot format secret
-- channels itself (that tag takes a secret hex from GenerateHexColor on its own and
-- hands it to SetFormattedText untouched).
-- Returns ok, r, g, b -- ok is a PLAIN boolean, r/g/b may be SECRET, only safe as setter args.
local function ResolveRestrictedClassColor(unit, class)
    local ok, r, g, b = EllesmereUI.GetClassColorForRestrictedUnit(unit, class)
    if ok then return true, r, g, b end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(class)
        if c then return true, c.r, c.g, c.b end
    end
    return false
end

-- Background class-color source, enemy-aware. UnitClass() reports WARRIOR for NPCs
-- rather than nil, so a bare lookup paints every mob Warrior tan. Players (and AI
-- party members) keep EllesmereUI.GetClassColor (custom colors + Class Color Darken
-- baked in); NPCs fall through to the reaction color, matching the unit name, the
-- border and the custom Enemy Colors override. On ns for the local cap.
-- Returns ok, r, g, b -- ok is a PLAIN boolean, r/g/b may be SECRET numbers on an
-- identity-restricted unit (ToT/focus-target): callers must branch on ok, never on
-- the truthiness of r, and may only ever hand r/g/b to a setter like SetColorTexture.
ns.ResolveBgClassColor = function(classUnit)
    if not classUnit then return false end
    if UnitIsPlayer(classUnit) or (UnitInPartyIsAI and UnitInPartyIsAI(classUnit)) then
        local _, ct = UnitClass(classUnit)
        if issecretvalue(ct) then
            return ResolveRestrictedClassColor(classUnit, ct)
        end
        local cc = ct and EllesmereUI.GetClassColor(ct)
        if cc then return true, cc.r, cc.g, cc.b end
        return false
    end
    local r, g, b = ns.ResolveUnitNameColor(classUnit)
    return r ~= nil, r, g, b
end

-- External nickname providers key us by this addon name. Suite = "EllesmereUI" (the
-- registered brand) so one provider checkbox controls every EUI module; standalone =
-- our renamed folder name, which always contains "Standalone" (rename-immune token).
-- On ns for the Lua 5.1 200-local ceiling.
ns.NICK_ADDON = addonName:find("Standalone") and addonName or "EllesmereUI"

-- Resolve a unit's display name through MethodInternal's authoritative surface
-- choice for known Method players, then the normal provider order: NSAPI ->
-- TimelineReminders -> LiquidAPI, then the raw unit name. Each
-- external call is pcall-wrapped so a misbehaving API can never break names.
--
-- SECRET-SAFE: an enemy unit's UnitName is secret in protected content and any Lua op
-- on it (==, .., format) throws. Nicknames only apply to your own group, so: non-players
-- short-circuit to the raw name; name-keyed providers (NSAPI, LiquidAPI) are skipped
-- when the name is secret; TimelineReminders is UNIT-keyed (GetNickname(unit)), safe to
-- consult regardless (result still re-validated as a clean string). The final return
-- may be the raw (possibly secret) name -- display-safe since oUF feeds tag returns to
-- SetFormattedText as a %s arg without inspecting them.
function ns.ResolveUnitNickname(unit)
    local name, surname = UnitName(unit)
    if not name then return "" end
    -- Nicknames are player-only; NPCs (bosses, etc.) keep their name.
    if not UnitIsPlayer(unit) then return name end
    local nameSecret = issecretvalue and issecretvalue(name)
    local display
    -- MethodInternal's surface choice is authoritative for known Method players,
    -- including Character Name (which deliberately equals the raw name). It sits
    -- ahead of the EUI master toggle so the MethodInternal-owned setting works on
    -- its selected surface; unknown players continue through EUI's normal chain.
    if EasyNicknameAPI and EasyNicknameAPI.GetNicknameForUnitForSurface then
        local ok, dn, handled = pcall(
            EasyNicknameAPI.GetNicknameForUnitForSurface, unit, "unitFrames")
        if ok and handled == true then
            if type(dn) == "string"
               and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                return dn
            end
            return EllesmereUI.WithSurname(name, surname)
        end
    end
    -- Master toggle (Unit Frames > main frames > Display, default OFF): when off,
    -- skip the remaining provider lookups and show the raw unit name (display-safe;
    -- with the surname on WoW Forever).
    if not (db and db.profile and db.profile.showNicknames) then return EllesmereUI.WithSurname(name, surname) end
    if not nameSecret and NSAPI and NSAPI.GetName then
        local ok, dn = pcall(NSAPI.GetName, NSAPI, name, "EUI")
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    if not display then
        local TR = TimelineReminders
        if TR and TR.GetNickname and TR.HasNickname and TR.NicknamesEnabledForAddOn then
            local okGate, enabled = pcall(TR.NicknamesEnabledForAddOn, TR, ns.NICK_ADDON)
            if okGate and enabled then
                local okHas, has = pcall(TR.HasNickname, TR, unit)
                if okHas and has then
                    local ok, dn = pcall(TR.GetNickname, TR, unit)
                    if ok and type(dn) == "string"
                       and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                        display = dn
                    end
                end
            end
        end
    end
    if not display and not nameSecret and LiquidAPI and LiquidAPI.GetNicknameForEllesmereUI then
        local ok, dn = pcall(LiquidAPI.GetNicknameForEllesmereUI, name)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
            display = dn
        end
    end
    if display then return display end
    return EllesmereUI.WithSurname(name, surname)
end

-- Nickname-aware replacement for the stock [name] tag (see ContentToTag). Returns
-- the nickname when one applies, else the raw unit name.
TagFns.name = function(unit)
    -- Truncation is width-based (per-slot Width % clamp), never character-based:
    -- FontString width boxes ellipsize in the renderer, which also works on SECRET
    -- enemy names Lua cannot measure or substring.
    return ns.ResolveUnitNickname(unit)
end

-- Live name refresh: repaint every frame's text zones so added/removed
-- nicknames (or a flipped provider checkbox) apply without a /reload. Fired by
-- the provider callbacks below; cheap (a handful of frames).
function ns.RefreshAllUnitNames()
    for _, f in pairs(frames) do
        if type(f) == "table" and f._euiTextZones then
            ns.UF_PaintText(f, f._euiUnit)
        end
    end
end
-- Name text only re-renders on name events or via the refresh above, so a raw
-- db restore (Spec Overrides apply, profile swap) needs this exported.
_G._EUF_RefreshUnitNames = ns.RefreshAllUnitNames

-- Cold-login text repaint: on a first (uncached) login a fontstring can hold the
-- correct string yet render blank until /reload, since it only repaints on a text
-- CHANGE and repainting sets the same string (a no-op). Force a "" -> value
-- transition on every zone fontstring shortly after login, repeated since timing
-- varies; the zone repaint restores the real strings synchronously, no flicker.
do
    local function ForceTextRepaint()
        for _, f in pairs(frames) do
            -- The painter refuses an empty token, so a frame between units must
            -- not be blanked here either -- it would never get the value back.
            if type(f) == "table" and f._euiTextZones
               and f._euiUnit and UnitExists(f._euiUnit) then
                local zones = f._euiTextZones
                for i = 1, #zones do
                    local fs = zones[i].fs
                    if fs and fs.SetText then fs:SetText("") end
                end
                if #zones > 0 then ns.UF_PaintText(f, f._euiUnit) end
            end
        end
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        for _, delay in ipairs({ 0.25, 1, 3 }) do
            C_Timer.After(delay, ForceTextRepaint)
        end
    end)
end

-- Provider callbacks. MethodInternal uses the addon-loaded callback; NSAPI and
-- TimelineReminders retry on PLAYER_LOGIN/PLAYER_ENTERING_WORLD. Registrant key MUST
-- be "EllesmereUIUnitFrames", not "EllesmereUI": Raid Frames owns that key and
-- CallbackHandler keys registrations by it, so reuse would clobber one module. The
-- provider CHECKBOX key stays shared (ns.NICK_ADDON/"EUI") so one toggle drives raid AND unit frames.
do
    local function RefreshNames() if ns.RefreshAllUnitNames then ns.RefreshAllUnitNames() end end
    local function RegisterMethodInternal()
        if ns._methodInternalSurfaceNickHooked then return end
        if EasyNicknameAPI and EasyNicknameAPI.RegisterCallback then
            EasyNicknameAPI.RegisterCallback(
                "SurfaceNicknamesChanged", RefreshNames, "EllesmereUIUnitFrames")
            ns._methodInternalSurfaceNickHooked = true
        end
    end
    local function RegisterNSRT()
        if ns._nsrtNickHooked then return true end
        if NSAPI and NSAPI.RegisterCallback then
            NSAPI.RegisterCallback("EllesmereUIUnitFrames", "NSRT_NICKNAME_UPDATED", RefreshNames)
            NSAPI.RegisterCallback("EllesmereUIUnitFrames", "EUI_NICKNAME_TOGGLE", RefreshNames)
            ns._nsrtNickHooked = true
            return true
        end
        return false
    end
    local function RegisterTR()
        if ns._trNickHooked then return true end
        local TR = TimelineReminders
        if TR and TR.RegisterCallback then
            TR.RegisterCallback("EllesmereUIUnitFrames", "TimelineReminders_NicknameToggle", function(_, _, addOnName)
                if addOnName == ns.NICK_ADDON then RefreshNames() end
            end)
            TR.RegisterCallback("EllesmereUIUnitFrames", "TimelineReminders_NicknameUpdate", function()
                RefreshNames()
            end)
            ns._trNickHooked = true
            return true
        end
        return false
    end
    if not (RegisterNSRT() and RegisterTR()) then
        local nf = CreateFrame("Frame")
        nf:RegisterEvent("PLAYER_LOGIN")
        nf:RegisterEvent("PLAYER_ENTERING_WORLD")
        nf:SetScript("OnEvent", function(self, event)
            local a = RegisterNSRT()
            local b = RegisterTR()
            if (a and b) or event == "PLAYER_ENTERING_WORLD" then self:UnregisterAllEvents() end
        end)
    end
    EventUtil.ContinueOnAddOnLoaded("MethodInternal", RegisterMethodInternal)
end

-- "Name > Target" is built from FOUR tags so the (possibly SECRET) target name is never
-- compared/concatenated/formatted in Lua -- oUF joins tag returns via SetFormattedText,
-- where the name is only a %s display arg. ContentToTag maps "nametotarget" to
-- "[name][eui-tgtsep(...)][eui-tgtcol][eui-tgtname]": [name] = unit's own name (stock
-- oUF tag); [eui-tgtsep] = indicator shown only when the unit has a target (per-slot
-- separator/color ride in tag ARGS, see BuildTgtSepTag; no args = " > "); [eui-tgtcol] =
-- target's class/reaction COLOR escape (no name involved); [eui-tgtname] = target's name,
-- returned RAW. The colour escape precedes the raw name and runs to end of string, so
-- the target name colours IDENTICALLY to the ToT frame name (both via
-- ns.ResolveUnitNameColor) -- works for a SECRET name only because colour and name are
-- SEPARATE tags joined by SetFormattedText, never touched together in Lua.
--
-- PLAYER_TARGET_CHANGED is unitless in oUF (refreshes every frame), covering the player
-- frame's target; UNIT_TARGET covers target/focus frames' own target.

-- Separator/indicator between the names, shown only when the unit has a target. Plain
-- literal plus color escapes; no secret is touched. Args: sepHex = separator string,
-- hex-encoded per byte (safe inside tag brackets), rendered space-padded like " > ";
-- colorSpec = "class" for the TARGET's class/reaction color (same resolver as the
-- target name), else a fixed "rrggbb" hex, closed with |r so a missing [eui-tgtcol]
-- can't inherit it. Decoded separators/escapes are cached: fires on every target
-- change, must not allocate after warmup.
-- (The separator between "Name > Target" is built per-zone by
-- ns.MakeTgtSepPiece in the formatter block below; it closes over the decoded
-- separator and color mode from settings and recolors class-mode per call.)

-- The target's class/reaction colour escape (e.g. "|cffc41f3b"), or "". Uses
-- ns.ResolveUnitNameColor, the SAME resolver ApplyClassColor uses for the Target
-- of Target name. No unit NAME is touched, so it is fully secret-safe.
TagFns.tgtcol = function(unit)
    local tunit = unit and (unit .. "target")
    if not tunit or not UnitExists(tunit) then return "" end
    local r, g, b = ns.ResolveUnitNameColor(tunit)
    if not r then
        -- Secret class token (identity-restricted target, e.g. a boss's own
        -- target): GenerateHexColor's result may itself be secret, but still
        -- renders correctly through SetFormattedText's arg lane -- don't reject it.
        if UnitIsPlayer(tunit) and C_ClassColor and C_ClassColor.GetClassColor then
            local _, class = UnitClass(tunit)
            if issecretvalue(class) then
                local cc = C_ClassColor.GetClassColor(class)
                if cc and cc.GenerateHexColor then
                    local ok, hex = pcall(cc.GenerateHexColor, cc)
                    if ok and type(hex) == "string" then
                        return "|c" .. hex
                    end
                end
            end
        end
        -- Still nothing usable: the plain reaction colour instead of "".
        local reaction = UnitReaction(tunit, "player")
        if reaction and not issecretvalue(reaction) then
            local c = (ns.Colors and ns.Colors.reaction and ns.Colors.reaction[reaction])
                or FACTION_BAR_COLORS[reaction]
            if c then r, g, b = c.r, c.g, c.b end
        end
    end
    if not r then return "" end
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- The unit's target NAME (nickname-aware via ResolveUnitNickname; otherwise the
-- raw, possibly secret name -- display-safe via SetFormattedText, never
-- inspected). Colour comes from [eui-tgtcol] in front of it.
TagFns.tgtname = function(unit)
    local tunit = unit and (unit .. "target")
    if not tunit or not UnitExists(tunit) then return "" end
    return ns.ResolveUnitNickname(tunit)
end

-------------------------------------------------------------------------------
--  Text pieces + zone formatters (oUF extraction). Each options content key
--  maps to a format string plus piece functions; the engine's text painter
--  renders a zone with SetFormattedText(fmt, piece1(u), piece2(u), ...).
--  Secret rule: name/level/target-name pieces may return RAW secret values by
--  design; they are never concatenated or inspected in Lua -- the format-arg
--  lane is the only thing that touches them, exactly as the tag engine did,
--  so restricted-content rendering is unchanged.
-------------------------------------------------------------------------------
do
    local sf = string.format
    local P = {}
    ns.TextPieces = P

    -- Function-registered tag methods are shared directly: one body, no drift.
    P.curhpshort  = TagFns.curhpshort
    P.perhp       = TagFns.perhp
    P.perhpnosign = TagFns.perhpnosign
    P.level       = TagFns.level
    -- Level in Blizzard's difficulty colors (Level Difficulty Color). A secret
    -- level passes through raw and uncolored, same rule as P.level.
    P.levelcol    = function(u)
        local l = TagFns.level(u)
        if issecretvalue(l) or l == "" then return l end
        local r, g, b = EllesmereUI.GetLevelColor(u, (l == "??") and -1 or l)
        return EllesmereUI.ColorText(l, r, g, b)
    end
    -- Same, with friendly units in their difficulty color too (Include Friendly).
    P.levelcolall = function(u)
        local l = TagFns.level(u)
        if issecretvalue(l) or l == "" then return l end
        local r, g, b = EllesmereUI.GetLevelColor(u, (l == "??") and -1 or l, true)
        return EllesmereUI.ColorText(l, r, g, b)
    end
    P.name        = TagFns.name
    P.tgtcol      = TagFns.tgtcol
    P.tgtname     = TagFns.tgtname

    -- String-compiled tag methods get real equivalents (same logic, same
    -- _EUI_ globals; the compiled strings stay registered only while the tag
    -- engine still runs).
    P.perpp = function(u)
        local pType = _G._EUI_ResolvedPowerType[u] or UnitPowerType(u)
        return sf("%d", UnitPowerPercent(u, pType, true, CurveConstants.ScaleTo100))
    end
    P.curpp = function(u)
        local pType = _G._EUI_ResolvedPowerType[u] or UnitPowerType(u)
        return AbbreviateNumbers(UnitPower(u, pType))
    end
    P.absorb = function(u)
        if not u or not UnitExists(u) then return "" end
        return sf("%s", C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(u) or 0))
    end
    P.absorbshort = function(u)
        if not u or not UnitExists(u) then return "" end
        local cfg = _G._EUI_AbbrevDecimalCfg
        return cfg and AbbreviateNumbers(UnitGetTotalAbsorbs(u) or 0, cfg)
            or AbbreviateNumbers(UnitGetTotalAbsorbs(u) or 0)
    end
    P.healabsorb = function(u)
        if not u or not UnitExists(u) then return "" end
        return sf("%s", C_StringUtil.TruncateWhenZero(UnitGetTotalHealAbsorbs(u) or 0))
    end
    P.healabsorbshort = function(u)
        if not u or not UnitExists(u) then return "" end
        local cfg = _G._EUI_AbbrevDecimalCfg
        return cfg and AbbreviateNumbers(UnitGetTotalHealAbsorbs(u) or 0, cfg)
            or AbbreviateNumbers(UnitGetTotalHealAbsorbs(u) or 0)
    end
    P.group = function(u)
        if not IsInRaid() then return "" end
        local idx = UnitInRaid(u)
        if idx then
            local _, _, subgroup = GetRaidRosterInfo(idx)
            return subgroup or ""
        end
        return ""
    end

    -- Separator piece for "Name > Target": resolved from settings at apply
    -- time (re-applied whenever settings change, like everything else on the
    -- page), closing over the decoded separator and its color mode. Class
    -- mode recolors per call so the indicator tracks the target's reaction.
    -- literal (optional): an already padded string drawn in place of the
    -- separator in the same Indicator Color (the Target content's prefix).
    function ns.MakeTgtSepPiece(prefix, settings, literal)
        local sep = literal
        if not sep then
            sep = settings[prefix .. "TargetSep"]
            if type(sep) ~= "string" or sep == "" then sep = ">" end
            sep = " " .. sep .. " "
        end
        if settings[prefix .. "TargetSepClassColor"] then
            return function(u)
                if not (u and UnitExists(u .. "target")) then return "" end
                local r, g, b = ns.ResolveUnitNameColor(u .. "target")
                if r then
                    return sf("|cff%02x%02x%02x%s|r",
                        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                        math.floor(b * 255 + 0.5), sep)
                end
                return sep
            end
        end
        local c = settings[prefix .. "TargetSepColor"]
        local esc
        if type(c) == "table" then
            esc = EllesmereUI.HexColor(c.r or 1, c.g or 1, c.b or 1)
        else
            esc = EllesmereUI.COLOR_CODES.WHITE
        end
        local colored = esc .. sep .. "|r"
        return function(u)
            if not (u and UnitExists(u .. "target")) then return "" end
            return colored
        end
    end

    -- Content key -> zone definition. Mirrors ContentToTag's output shapes
    -- one-for-one so rendered text is byte-identical.
    local ZONE_STATIC = {
        name         = { "%s", "name" },
        levelname    = { "%s | %s", "level", "name" },
        namelevel    = { "%s | %s", "name", "level" },
        level        = { "%s", "level" },
        both         = { "%s | %s%%", "curhpshort", "perhp" },
        bothdash     = { "%s - %s%%", "curhpshort", "perhp" },
        perhpnum     = { "%s%% | %s", "perhp", "curhpshort" },
        perhpnumdash = { "%s%% - %s", "perhp", "curhpshort" },
        curhpshort   = { "%s", "curhpshort" },
        perhp        = { "%s%%", "perhp" },
        perhpnosign  = { "%s", "perhpnosign" },
        perpp        = { "%s%%", "perpp" },
        curpp        = { "%s", "curpp" },
        curhp_curpp  = { "%s | %s", "curhpshort", "curpp" },
        perhp_perpp  = { "%s%% | %s%%", "perhp", "perpp" },
        absorb       = { "%s", "absorb" },
        absorbshort  = { "%s", "absorbshort" },
        healabsorb   = { "%s", "healabsorb" },
        healabsorbshort = { "%s", "healabsorbshort" },
        group        = { "%s", "group" },
    }
    -- Identity-only zones: their pieces read name/level, which change only on
    -- identity edges (UNIT_NAME_UPDATE, UNIT_LEVEL, repoints, provider
    -- callbacks) -- Blizzard paints names on UNIT_NAME_UPDATE alone. Not
    -- listed: nametotarget (target names churn) and group (roster-driven,
    -- repainted by the value ticks it always rode).
    local ZONE_IDENTITY = { name = true, levelname = true, namelevel = true, level = true }
    -- Value-class events: a static zone skips these and repaints on anything
    -- else (identity events, ForceUpdate, UnitChanged, PEW, nil = repaint all).
    -- UNIT_TARGET is here too: only the Name > Target zone (never static)
    -- reads the unit's target, so the name and level zones sit it out.
    local VALUE_EVENTS = {
        UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_MAX_HEALTH_MODIFIERS_CHANGED = true,
        UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true,
        UNIT_ABSORB_AMOUNT_CHANGED = true, UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
        UNIT_TARGET = true,
        Resettle = true, EUI_AbsorbEnd = true, EUI_AbsorbBelt = true,
    }

    --- Resolves a content key to (fmt, piecesArray, static) for a zone, or nil
    --- for "none"/unknown. nametotarget builds its settings-closure separator.
    function ns.ContentToZone(content, prefix, settings)
        if content == "nametotarget" then
            return "%s%s%s%s", { P.name, ns.MakeTgtSepPiece(prefix, settings), P.tgtcol, P.tgtname }
        end
        -- Target: the unit's target name alone, after the slot's Prefix
        -- (nil = "T:", "" = none) in the Indicator Color. The target's colour
        -- escape rides only while the slot is Class Colored; otherwise the
        -- name keeps the slot colour. Every piece is "" without a target.
        if content == "targetname" then
            local pieces = {}
            local pre = settings[prefix .. "TargetPrefix"]
            if type(pre) ~= "string" then pre = "T:" end
            if pre ~= "" then pieces[1] = ns.MakeTgtSepPiece(prefix, settings, pre .. " ") end
            if settings[prefix .. "ClassColor"] then pieces[#pieces + 1] = P.tgtcol end
            pieces[#pieces + 1] = P.tgtname
            return string.rep("%s", #pieces), pieces
        end
        local def = ZONE_STATIC[content]
        if not def then return nil end
        local pieces = { }
        local lvlCol = settings and settings.levelDifficultyColor
        for i = 2, #def do
            local key = def[i]
            if key == "level" and lvlCol then
                key = settings.levelDifficultyColorFriendly and "levelcolall" or "levelcol"
            end
            pieces[#pieces + 1] = P[key]
        end
        return def[1], pieces, ZONE_IDENTITY[content] or nil
    end

    -- Name Format (WoW Forever only): a slot set to First Name or Last Name
    -- (<prefix>NameFormat) gets short-name twins of its name pieces when the
    -- zone is applied, so the painter and every unset slot run as before.
    -- Level, separator and colour pieces stay; Name > Target shortens both
    -- names. ForeverShortName passes a secret name through whole and caches
    -- the short forms, so a zone repainted on every health tick builds no
    -- strings.
    if EllesmereUI.IS_FOREVER == true then
        local short, nameFn, tgtFn = EllesmereUI.ForeverShortName, P.name, P.tgtname
        local function Twins(mode)
            return {
                [nameFn] = function(u) return short(nameFn(u), mode) end,
                [tgtFn]  = function(u) return short(tgtFn(u), mode) end,
            }
        end
        local twinsByMode = { first = Twins("first"), last = Twins("last") }
        local base = ns.ContentToZone
        function ns.ContentToZone(content, prefix, settings)
            local fmt, pieces, static = base(content, prefix, settings)
            local twins = fmt and settings and twinsByMode[settings[prefix .. "NameFormat"]]
            if twins then
                for i = 1, #pieces do pieces[i] = twins[pieces[i]] or pieces[i] end
            end
            return fmt, pieces, static
        end
    end

    -- The text painter: renders every registered zone on the frame. Piece
    -- returns route through a scratch table + unpack (tables carry secrets
    -- fine; nothing inspects them). Identity-only zones (name/level) are
    -- skipped on value-class events: the nickname provider chain behind the
    -- name piece was running on every health tick.
    local scratch = {}
    local function PaintText(frame, unit, event)
        local zones = frame._euiTextZones
        if not zones then return end
        -- An empty token renders every zone blank, and a boss frame outlives the
        -- gap: the unit watch is a 0.2s poll, so the frame is still shown while
        -- its slot sits between units. Same probe the health painter pays.
        if not (unit and UnitExists(unit)) then return end
        -- Faction flip: slot colour is set by ApplyClassColor, never by the
        -- pieces below, so recolour first (the health bar recolours on this
        -- same event); the render then refreshes any target-colour piece.
        if event == "UNIT_FACTION" and ns.UF_RecolorTexts then
            ns.UF_RecolorTexts(frame, unit)
        end
        local valueOnly = event ~= nil and VALUE_EVENTS[event]
        for i = 1, #zones do
            local z = zones[i]
            if not (valueOnly and z.static) then
                local pieces = z.pieces
                local n = #pieces
                for k = 1, n do scratch[k] = pieces[k](unit) end
                z.fs:SetFormattedText(z.fmt, unpack(scratch, 1, n))
            end
        end
    end
    ns.UF_PaintText = PaintText
    ns.Engine.SetPainter("text", PaintText)

    -- Power-only text repaint for the power value pass: renders just the
    -- zones whose pieces read the unit's power (flagged when the zone is set).
    function ns.UF_PaintPowerText(frame, unit)
        local zones = frame._euiTextZones
        if not zones then return end
        for i = 1, #zones do
            local z = zones[i]
            if z.power then
                local pieces = z.pieces
                local n = #pieces
                for k = 1, n do scratch[k] = pieces[k](unit) end
                z.fs:SetFormattedText(z.fmt, unpack(scratch, 1, n))
            end
        end
    end

    -- True when a zone's pieces read power (the power text pieces), so the
    -- power value pass repaints it.
    local function ReadsPower(pieces)
        for i = 1, #pieces do
            local p = pieces[i]
            if p == P.perpp or p == P.curpp then return true end
        end
        return nil
    end

    --- Registers/updates one text zone on a frame: resolves the content key
    --- and stores the def the text painter renders. nil/none content removes
    --- the zone (the position code hides the fontstring separately, as
    --- before). Zones are keyed by fontstring; re-apply replaces in place.
    function ns.SetTextZone(frame, fs, content, prefix, settings)
        local zones = frame._euiTextZones
        if not zones then zones = {}; frame._euiTextZones = zones end
        local fmt, pieces, static
        if content then fmt, pieces, static = ns.ContentToZone(content, prefix, settings) end
        for i = #zones, 1, -1 do
            if zones[i].fs == fs then table.remove(zones, i) end
        end
        if fmt then
            zones[#zones + 1] = { fs = fs, fmt = fmt, pieces = pieces, static = static,
                                  power = ReadsPower(pieces) }
        else
            fs:SetText("")
        end
        -- A power text zone added or removed can switch the player's power
        -- value channel.
        if frame._euiBaseUnit == "player" then ns.UF_PowerValSync(frame) end
    end

    --- Raw-zone variant for callers that assemble their own format (the power
    --- percent text's curpp/perpp/smart combinations). nil fmt removes.
    function ns.SetTextZoneRaw(frame, fs, fmt, pieces)
        local zones = frame._euiTextZones
        if not zones then zones = {}; frame._euiTextZones = zones end
        for i = #zones, 1, -1 do
            if zones[i].fs == fs then table.remove(zones, i) end
        end
        if fmt then
            zones[#zones + 1] = { fs = fs, fmt = fmt, pieces = pieces, power = ReadsPower(pieces) }
        else
            fs:SetText("")
        end
        if frame._euiBaseUnit == "player" then ns.UF_PowerValSync(frame) end
    end
end

I.EUI_IsSmartPowerPercent, I.ResolveRestrictedClassColor = EUI_IsSmartPowerPercent, ResolveRestrictedClassColor
I.PLAYER_POWER_DEFAULT, I.PLAYER_POWER_ALT = PLAYER_POWER_DEFAULT, PLAYER_POWER_ALT
