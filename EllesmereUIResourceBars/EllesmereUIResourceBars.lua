-------------------------------------------------------------------------------
--  EllesmereUIResourceBars.lua
--  Custom class resource, health, and mana bar display
--  Features: Health bar, primary resource bar (mana/rage/energy/etc),
--  secondary resource display (combo points, holy power, runes, etc),
--  smooth animations, combat fade, low-resource alerts, class-colored bars
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local ERB = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.ERB = ERB

local PP = EllesmereUI.PP

-- Per-addon border texture defaults (size key = borderSize 0-4)
-- Shared by TBB, class/power/health bars, and cast bar
do
    local function AllSizes(ox, oy, sx, sy)
        local t = {}
        for k = 0, 4 do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
        return t
    end
    EllesmereUI.RegisterBorderDefaults("resourcebars", {
        ["glow"] = {
            defaultSize = 1,
            sizes = AllSizes(0, 0, 0, 0),
        },
        ["blizz"] = {
            defaultSize = 3,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 3, offsetY = 2, shiftX = 1, shiftY = 0 },
                [3] = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
                [4] = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
            },
        },
        ["dialog"] = {
            defaultSize = 1,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 3, offsetY = 3, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 3, offsetY = 5, shiftX = 0, shiftY = 0 },
                [3] = { offsetX = 3, offsetY = 5, shiftX = 0, shiftY = 0 },
                [4] = { offsetX = 5, offsetY = 10, shiftX = 0, shiftY = 0 },
            },
        },
        ["sm:Blizzard Achievement Wood"] = {
            defaultSize = 1,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 1, offsetY = 1, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 1, offsetY = 1, shiftX = 0, shiftY = 0 },
                [3] = { offsetX = 1, offsetY = 6, shiftX = 0, shiftY = 0 },
                [4] = { offsetX = 1, offsetY = 8, shiftX = 0, shiftY = 0 },
            },
        },
    })
end

-- Snap x/y to the physical pixel grid for a given frame.
-- Optional `pos` table provides the anchor type so CENTER-anchored positions
-- get dim-aware snapping (preserves the +0.5 center offset that odd-pixel-dim
-- frames need so their edges land on whole physical pixels).
local function SnapXY(x, y, frame, pos)
    local PPa = EllesmereUI and EllesmereUI.PP
    if not (PPa and x and y and frame) then return x or 0, y or 0 end
    local es = frame:GetEffectiveScale()
    local isCenterAnchor = pos and (pos.point == "CENTER")
        and (pos.relPoint == "CENTER" or pos.relPoint == nil)
    if isCenterAnchor and PPa.SnapCenterForDim then
        return PPa.SnapCenterForDim(x, frame:GetWidth() or 0, es),
               PPa.SnapCenterForDim(y, frame:GetHeight() or 0, es)
    elseif PPa.SnapForES then
        return PPa.SnapForES(x, es), PPa.SnapForES(y, es)
    end
    return x, y
end

local floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
local format = string.format
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitClass = UnitClass
local GetSpecialization = GetSpecialization
local InCombatLockdown = InCombatLockdown
local GetShapeshiftFormID = GetShapeshiftFormID
local IsPlayerSpell = IsPlayerSpell
local UnitSpellHaste = UnitSpellHaste

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local RB_FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetRBFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("resourceBars")
    end
    return RB_FONT_FALLBACK
end
local function GetRBOutline()
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("resourceBars")) or ""
end
local function GetRBUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("resourceBars")
end
local function SetRBFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    local f = GetRBOutline()
    fs:SetFont(font, size, f)
    if f == "" then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
    else fs:SetShadowOffset(0, 0) end
end

-- PowerType enum values (Enum.PowerType)
local PT = {
    MANA        = 0,
    RAGE        = 1,
    FOCUS       = 2,
    ENERGY      = 3,
    COMBO       = 4,
    RUNES       = 5,
    RUNIC_POWER = 6,
    SOUL_SHARDS = 7,
    LUNAR_POWER = 8,  -- Astral Power (Balance Druid)
    HOLY_POWER  = 9,
    MAELSTROM   = 11,
    CHI         = 12,
    INSANITY    = 13,
    ARCANE      = 16, -- Arcane Charges
    FURY        = 17,
    PAIN        = 18, -- Demon Hunter (Vengeance)
    ESSENCE     = 19, -- Evoker
}

-------------------------------------------------------------------------------
--  Channel tick data — spellID → { ticks, [modSpell, modTicks] } or { tickInterval }
--  ticks: fixed tick count (haste changes tick speed, count stays the same).
--  tickInterval: fixed interval in seconds (haste extends duration, adding ticks).
--  modSpell/modTicks: if the player knows modSpell (talent), use modTicks instead.
--  Spell IDs verified against Wowhead/Warcraft Wiki as of 12.0.1 — if a spell
--  is reworked or a new channeled spell is added, add a row here.
-------------------------------------------------------------------------------
local CHANNEL_TICK_DATA = {
    -- Evoker
    [356995]  = { ticks = 4, modSpell = 1219723, modTicks = 5 },   -- Disintegrate / Azure Celerity
    -- Priest
    [15407]   = { ticks = 6 },                                     -- Mind Flay
    [48045]   = { ticks = 6 },                                     -- Mind Sear
    [64843]   = { ticks = 4 },                                     -- Divine Hymn
    [47757]   = { ticks = 3 },                                     -- Penance (Heal)
    [47758]   = { ticks = 3 },                                     -- Penance (DPS)
    [373129]  = { ticks = 3 },                                     -- Penance / Dark Reprimand (DPS)
    [400171]  = { ticks = 3 },                                     -- Penance / Dark Reprimand (Heal)
    -- Mage
    [5143]    = { ticks = 5 },                                     -- Arcane Missiles
    [12051]   = { ticks = 6 },                                     -- Evocation
    [205021]  = { ticks = 5 },                                     -- Ray of Frost
    -- Druid
    [740]     = { ticks = 4 },                                     -- Tranquility
    -- Demon Hunter
    [198013]  = { tickInterval = 0.2 },                            -- Eye Beam
    [473728]  = { tickInterval = 0.2 },                            -- Void Ray (Devourer)
    [212084]  = { ticks = 10 },                                    -- Fel Devastation
    -- Warlock
    [198590]  = { ticks = 5 },                                     -- Drain Soul
    [755]     = { ticks = 5 },                                     -- Health Funnel
    [234153]  = { ticks = 5 },                                     -- Drain Life
    -- Death Knight
    [206931]  = { ticks = 3 },                                     -- Blooddrinker
    -- Monk
    [113656]  = { ticks = 4 },                                     -- Fists of Fury
    [115175]  = { ticks = 12 },                                     -- Soothing Mist
    [443028]  = { ticks = 4 },                                     -- Celestial Conduit
    -- Racial
    [291944]  = { ticks = 6 },                                     -- Regeneratin (Zandalari)
}


-------------------------------------------------------------------------------
--  Class/Spec resource mapping
-------------------------------------------------------------------------------
-- Class and power colors read from EllesmereUI's global color system
-- (EllesmereUI.GetClassColor / GetPowerColor). These respect the user's
-- custom color overrides from General Options. Metatable wrappers convert
-- the {r=,g=,b=} table format to {r,g,b} arrays for existing callsites.
local CLASS_COLORS = setmetatable({}, { __index = function(_, classFile)
    if not EllesmereUI or not EllesmereUI.GetClassColor then return nil end
    local c = EllesmereUI.GetClassColor(classFile)
    if c then return { c.r, c.g, c.b } end
    return nil
end })

-- Power type enum -> EUI power key string mapping for GetPowerColor lookup
local POWER_ENUM_TO_KEY = {
    [PT.MANA]        = "MANA",
    [PT.RAGE]        = "RAGE",
    [PT.FOCUS]       = "FOCUS",
    [PT.ENERGY]      = "ENERGY",
    [PT.RUNIC_POWER] = "RUNIC_POWER",
    [PT.LUNAR_POWER] = "LUNAR_POWER",
    [PT.MAELSTROM]   = "MAELSTROM",
    [PT.INSANITY]    = "INSANITY",
    [PT.FURY]        = "FURY",
    [PT.PAIN]        = "PAIN",
}

-- Resolve any power key (enum number, string, or _BAR variant) to the
-- canonical string key used by EllesmereUI.GetPowerColor.
local POWER_KEY_ALIAS = {
    ["FOCUS_BAR"]       = "FOCUS",
    ["INSANITY_BAR"]    = "INSANITY",
    ["LUNAR_POWER_BAR"] = "LUNAR_POWER",
    ["MAELSTROM_BAR"]   = "MAELSTROM",
    ["MAELSTROM_WEAPON"] = "MAELSTROM",
}

local function ResolvePowerKey(powerKey)
    if type(powerKey) == "number" then return POWER_ENUM_TO_KEY[powerKey] end
    return POWER_KEY_ALIAS[powerKey] or powerKey
end

-- Power color lookup: resolves all keys through EUI's global color system.
-- Falls back to class color if no power color exists for the key.
local POWER_COLORS = setmetatable({}, { __index = function(_, powerKey)
    if not EllesmereUI then return nil end
    local key = ResolvePowerKey(powerKey)
    if key and EllesmereUI.GetPowerColor then
        local c = EllesmereUI.GetPowerColor(key)
        if c then return { c.r, c.g, c.b } end
    end
    if EllesmereUI.GetClassColor then
        local _, classFile = UnitClass("player")
        local cc = classFile and EllesmereUI.GetClassColor(classFile)
        if cc then return { cc.r, cc.g, cc.b } end
    end
    return nil
end })

-- Dark theme colors (matches unit frames)
local DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, DARK_FILL_A = 0x11/255, 0x11/255, 0x11/255, 0.90
local DARK_BG_R, DARK_BG_G, DARK_BG_B, DARK_BG_A = 0x4f/255, 0x4f/255, 0x4f/255, 1


local PRIMARY_CLASS_MAP = {
    WARRIOR     = PT.RAGE,
    PALADIN     = PT.MANA,
    HUNTER      = PT.FOCUS,
    ROGUE       = PT.ENERGY,
    PRIEST      = PT.MANA,
    DEATHKNIGHT = PT.RUNIC_POWER,
    SHAMAN      = PT.MANA,
    MAGE        = PT.MANA,
    WARLOCK     = PT.MANA,
    MONK        = PT.ENERGY,
    DEMONHUNTER = PT.FURY,
    EVOKER      = PT.MANA,
}

local function GetPrimaryPowerType()
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization()
    local form = GetShapeshiftFormID()

    -- Druid form handling
    if classFile == "DRUID" then
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local ov = pp and pp.powerTypeOverride
        if ov and ov[spec] then
            if spec == 1 then return PT.LUNAR_POWER end  -- Balance alt: Astral Power
            return PT.MANA                                -- Feral/Guardian alt: Mana
        end
        if form == 1 then return PT.ENERGY end
        if form == 5 then return PT.RAGE end
        return PT.MANA
    end

    if classFile == "SHAMAN" and spec == 1 then
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local ov = pp and pp.powerTypeOverride
        if ov and ov[spec] then return PT.MAELSTROM end  -- Elemental alt: Maelstrom
    end
    if classFile == "PRIEST" and spec == 3 then
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local ov = pp and pp.powerTypeOverride
        if ov and ov[spec] then return PT.INSANITY end   -- Shadow alt: Insanity
    end
    if classFile == "HUNTER" then
        -- BM and MM: Focus is displayed as a class resource bar (secondary),
        -- not the power bar. Survival keeps Focus as the power bar.
        -- Users can override this with hunterFocusAsPower.
        if spec == 1 or spec == 2 then
            local pp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
            if pp and pp.hunterFocusAsPower then return PT.FOCUS end
            return nil
        end
    end
    if classFile == "MONK" then
        if spec == 1 then return PT.ENERGY end  -- Brewmaster
        if spec == 2 then return PT.MANA end    -- Mistweaver
        if spec == 3 then return PT.ENERGY end  -- Windwalker
    end
    if classFile == "DEMONHUNTER" then
        return PT.FURY
    end
    if classFile == "EVOKER" and spec == 3 then
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local ov = pp and pp.powerTypeOverride
        if not (ov and ov[spec]) then return "EBON_MIGHT" end
        return PT.MANA
    end

    return PRIMARY_CLASS_MAP[classFile] or PT.MANA
end

-- Ebon Might (Augmentation Evoker) -- aura-based countdown on the power bar
local EBON_MIGHT_SPELL_ID = 395296
local EBON_MIGHT_DURATION = 20

--Function to get Icicles for Frost
local ICICLES_SPELL_ID = 205473

-- Prot Warrior Ignore Pain (Midnight): stacking buff 190456 (0-100 stacks),
-- but ALL player aura fields are SECRET (field-confirmed: spellId, name and
-- applications return secrets even out of combat), so stacks cannot be read
-- from aura APIs. The absorb amount IS readable: IP caps at 30% of max
-- health (CAP), so total absorbs vs that cap gives the same 0-100% fullness
-- (100 stacks = cap = full bar). DURATION drives the moving hash line
-- (reset on cast -- aura expiry is secret, same approach as Ironfur ticks).
-- ONE namespace table for the whole feature: the file's main chunk is at
-- Lua 5.1's 200-local cap, so the feature occupies a single local slot.
local IP = {
    SPELL = 190456,
    CAP = 0.30,
    DURATION = 12,
    hashEndTime = 0,
    hookedFS = {},
    nextScan = 0,
}

local function GetIcicleCount()
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization()
    if classFile ~= "MAGE" or spec ~= 3 then
        return 0
    end

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(ICICLES_SPELL_ID)
        if aura then
            local count = aura.applications or aura.charges or aura.points or 0
            if count > 5 then count = 5 end
            return count
        end
        return 0
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 255 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            if aura.spellId == ICICLES_SPELL_ID then
                local count = aura.applications or aura.charges or aura.points or 0
                if count > 5 then count = 5 end
                return count
            end
        end
    end

    return 0
end

-------------------------------------------------------------------------------
--  Guardian Druid Ironfur tracker (bar-based, moving hash lines)
--  Each Ironfur cast adds a "tick" that moves right -> left across the bar as
--  its buff decays. Duration is talent-aware (Ursoc's Endurance = 9s base,
--  otherwise 7s; Guardian of Elune adds +3s to the next cast after a Mangle).
--  Event-driven from UNIT_SPELLCAST_SUCCEEDED so 12.x secret-value aura
--  restrictions can't cause drift.
-------------------------------------------------------------------------------
local IRONFUR_SPELL       = 192081
local URSOCS_ENDURANCE    = 393611  -- base 9s vs 7s
local GUARDIAN_OF_ELUNE   = 155578  -- talent: Mangle -> next Ironfur +3s
local MANGLE_SPELL        = 33917
local FRENZIED_REGEN      = 22842
local IRONFUR_GOE_BONUS   = 3
local IRONFUR_GOE_WINDOW  = 15
local ironfurTicks        = {}   -- array of { endTime=, duration= }
local ironfurBaseDur      = 7
local ironfurGoEUntil     = 0

local function IronfurBaseDuration()
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(URSOCS_ENDURANCE) then
        return 9
    end
    return 7
end

local function GetSecondaryResource()
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization()
    local form = GetShapeshiftFormID()

    if classFile == "PALADIN" then
        local mx = UnitPowerMax("player", PT.HOLY_POWER)
        return { power = PT.HOLY_POWER, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "ROGUE" then
        local mx = UnitPowerMax("player", PT.COMBO)
        return { power = PT.COMBO, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "DRUID" and spec == 3
           and ERB.db and ERB.db.profile and ERB.db.profile.secondary
           and ERB.db.profile.secondary.guardianIronfurBar then
        -- Guardian Ironfur duration bar (moving hash lines). Checked BEFORE the
        -- cat-form combo-points branch so entering Cat Form never swaps a
        -- Guardian's bar to Feral combo points -- the Ironfur bar persists in
        -- every form. max is a normalized fraction (0..1).
        ironfurBaseDur = IronfurBaseDuration()
        return { power = "IRONFUR_BAR", max = 1, type = "bar" }
    elseif classFile == "DRUID" and form == 1 then
        local mx = UnitPowerMax("player", PT.COMBO)
        return { power = PT.COMBO, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "DRUID" and spec == 1 then
        -- Balance: Astral Power as a class resource bar (like Elemental maelstrom)
        local mx = UnitPowerMax("player", PT.LUNAR_POWER)
        if issecretvalue and issecretvalue(mx) then mx = 100 end
        if not mx or mx <= 0 then mx = 100 end
        return { power = "LUNAR_POWER_BAR", max = mx, type = "bar" }
    elseif classFile == "DRUID" and spec == 3 then
        -- Guardian with the Ironfur bar disabled: no class resource (and no
        -- cat-form combo swap, since the form==1 branch above already passed).
        return nil
    elseif classFile == "MONK" and (spec == 3) then
        local mx = UnitPowerMax("player", PT.CHI)
        return { power = PT.CHI, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "MONK" and (spec == 1) then
        -- Brewmaster: stagger as a bar (max = player max health)
        local mx = UnitHealthMax("player") or 1
        if issecretvalue and issecretvalue(mx) then mx = 1 end
        if mx <= 0 then mx = 1 end
        return { power = "BREWMASTER_STAGGER", max = mx, type = "bar" }
    elseif classFile == "WARLOCK" then
        local mx = UnitPowerMax("player", PT.SOUL_SHARDS)
        return { power = PT.SOUL_SHARDS, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "DEATHKNIGHT" then
        return { power = PT.RUNES, max = 6, type = "runes" }
    elseif classFile == "EVOKER" then
        local mx = UnitPowerMax("player", PT.ESSENCE)
        return { power = PT.ESSENCE, max = (not issecretvalue or not issecretvalue(mx)) and mx or 5, type = "points" }
    elseif classFile == "MAGE" and spec == 1 then
        local mx = UnitPowerMax("player", PT.ARCANE)
        return { power = PT.ARCANE, max = (not issecretvalue or not issecretvalue(mx)) and mx or 4, type = "points" }
    elseif classFile == "MAGE" and spec == 3 then
        return { power = "ICICLES", max = 5, type = "custom" }
    elseif classFile == "DEMONHUNTER" then
        -- Resolve specID: 581=Vengeance, 1480=Devourer, 577=Havoc
        local specID = spec and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(spec)
        if specID == 581 then -- Vengeance: 6 soul fragment pips
            return { power = "SOUL_FRAGMENTS_VENGEANCE", max = 6, type = "custom" }
        elseif specID == 1480 then -- Devourer: soul fragments as a bar (35-50 max)
            local maxC = 50
            if EllesmereUI and EllesmereUI.GetSoulFragments then
                local _, m = EllesmereUI.GetSoulFragments()
                if m and m > 0 then maxC = m end
            end
            return { power = "SOUL_FRAGMENTS_DEVOURER", max = maxC, type = "bar" }
        end
        -- Havoc (577) has no secondary resource.
        return nil
    elseif classFile == "SHAMAN" and spec == 1 then
        -- Elemental: Maelstrom as a bar (like Devourer soul fragments)
        local mx = UnitPowerMax("player", PT.MAELSTROM)
        if issecretvalue and issecretvalue(mx) then mx = 100 end
        if not mx or mx <= 0 then mx = 100 end
        return { power = "MAELSTROM_BAR", max = mx, type = "bar" }
    elseif classFile == "PRIEST" and spec == 3 then
        -- Shadow: Insanity as a bar (like Elemental maelstrom)
        local mx = UnitPowerMax("player", PT.INSANITY)
        if issecretvalue and issecretvalue(mx) then mx = 100 end
        if not mx or mx <= 0 then mx = 100 end
        return { power = "INSANITY_BAR", max = mx, type = "bar" }
    elseif classFile == "SHAMAN" and spec == 2 then
        -- Base max 5, or 10 with Raging Maelstrom talent; BuildBars
        -- overrides from GetMaelstromWeapon() at runtime.
        return { power = "MAELSTROM_WEAPON", max = 5, type = "custom" }
    elseif classFile == "HUNTER" and spec == 3 then
        return { power = "TIP_OF_THE_SPEAR", max = 3, type = "custom" }
    elseif classFile == "HUNTER" and (spec == 1 or spec == 2) then
        -- BM and MM: Focus as a class resource bar (unless overridden)
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
        if pp and pp.hunterFocusAsPower then return nil end
        local mx = UnitPowerMax("player", PT.FOCUS)
        if issecretvalue and issecretvalue(mx) then mx = 100 end
        if not mx or mx <= 0 then mx = 100 end
        return { power = "FOCUS_BAR", max = mx, type = "bar" }
    elseif classFile == "WARRIOR" and spec == 3
           and ERB.db and ERB.db.profile and ERB.db.profile.secondary
           and ERB.db.profile.secondary.protIgnorePainBar then
        -- Protection Ignore Pain bar: total absorbs vs the IP absorb cap
        -- (30% of max health), so 100 stacks = full bar. Stacks are not
        -- readable (aura data is fully secret); see the IP table (IP.CAP).
        -- Toggle-gated; existing users are pinned OFF via migration
        -- "resourcebars_protwar_ignorepain_existing_off_v1".
        local mx = UnitHealthMax("player") or 1
        if issecretvalue and issecretvalue(mx) then mx = 1 end
        if mx <= 0 then mx = 1 end
        return { power = "IGNOREPAIN_BAR", max = mx * IP.CAP, type = "bar" }
    elseif classFile == "WARRIOR" and spec == 2 then
        return { power = "WHIRLWIND_STACKS", max = 4, type = "custom" }
    end

    return nil
end

-------------------------------------------------------------------------------
--  Bar-type spec lookup: maps specID -> true for specs that use a bar-type
--  secondary resource (Astral Power, Maelstrom, Insanity, Stagger, Focus,
--  Devourer Soul Fragments). Built once at init; exposed for options panel.
-------------------------------------------------------------------------------
local BAR_TYPE_SPECS = {}

local function BuildBarTypeSpecMap()
    if not GetNumClasses then return end
    for classID = 1, GetNumClasses() do
        local _, classFile = GetClassInfo(classID)
        if classFile then
            local numSpecs = GetNumSpecializationsForClassID(classID) or 0
            for specIndex = 1, numSpecs do
                local specID = GetSpecializationInfoForClassID(classID, specIndex)
                if specID then
                    local isBar = false
                    if classFile == "DRUID" and specIndex == 1 then isBar = true
                    elseif classFile == "SHAMAN" and specIndex == 1 then isBar = true
                    elseif classFile == "PRIEST" and specIndex == 3 then isBar = true
                    elseif classFile == "MONK" and specIndex == 1 then isBar = true
                    elseif classFile == "HUNTER" and (specIndex == 1 or specIndex == 2) then isBar = true
                    elseif classFile == "DEMONHUNTER" and specID == 1480 then isBar = true
                    end
                    BAR_TYPE_SPECS[specID] = isBar
                end
            end
        end
    end
end

-- Resolve the active threshold spec entry for the current player spec.
-- Returns the matching entry from thresholdSpecs, or nil.
-- Priority: specific specID match > All Specs (specID 0) > nil.
local function ResolveThresholdSpecEntry(sp)
    local entries = sp.thresholdSpecs
    if not entries or #entries == 0 then return nil end

    local specIdx = GetSpecialization()
    if not specIdx then return nil end
    local specID = specIdx and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(specIdx)
    if not specID then return nil end

    local allSpecsEntry = nil
    for _, entry in ipairs(entries) do
        if entry.specIDs then
            for _, sid in ipairs(entry.specIDs) do
                if sid == specID then return entry end
                if sid == 0 then allSpecsEntry = entry end
            end
        end
    end
    return allSpecsEntry
end

-- Expose for options panel
_G._ERB_BAR_TYPE_SPECS = BAR_TYPE_SPECS
_G._ERB_BuildBarTypeSpecMap = BuildBarTypeSpecMap
_G._ERB_ResolveThresholdSpecEntry = ResolveThresholdSpecEntry

-------------------------------------------------------------------------------
--  ColorCurve helper for secret-value-safe bar threshold coloring
--  Builds a two-point step curve: base color below threshold, threshold color
--  at or above. Pass the curve to UnitPowerPercent as the 4th arg � WoW
--  evaluates the secret value on the C side and returns a Color object.
-------------------------------------------------------------------------------
local _barColorCurve = nil
local _barColorCurveHash = nil

local function GetBarThresholdCurve(baseR, baseG, baseB, threshR, threshG, threshB, threshPct)
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end

    local hash = format("%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.1f",
        baseR, baseG, baseB, threshR, threshG, threshB, threshPct)
    if _barColorCurveHash == hash then return _barColorCurve end

    local curve = C_CurveUtil.CreateColorCurve()
    local t = math.max(0, math.min(1, threshPct / 100))
    local EPSILON = 0.0001

    -- At or below threshold -> use threshold color
    curve:AddPoint(0.0, CreateColor(threshR, threshG, threshB, 1))

    if t > EPSILON then
        curve:AddPoint(t, CreateColor(threshR, threshG, threshB, 1))
    end

    -- Above threshold -> revert to base bar color
    if t < 1.0 then
        curve:AddPoint(math.min(1.0, t + EPSILON), CreateColor(baseR, baseG, baseB, 1))
    end

    curve:AddPoint(1.0, CreateColor(baseR, baseG, baseB, 1))

    _barColorCurve = curve
    _barColorCurveHash = hash
    return curve
end

-- per-element scale, border, colors, text, alerts
-------------------------------------------------------------------------------
local _, playerClassFile = UnitClass("player")
-- Static neutral defaults for custom fill colors. Class/power colors are
-- applied at runtime when customColored=false; these only matter as the
-- initial custom color when the user first enables "Custom Colored."
-- IMPORTANT: Using class-specific values caused StripDefaults on logout
-- to nil-out any channel that matched the current class's default, then
-- DeepMergeDefaults on a different class filled it with the wrong color.
local CUSTOM_FILL_DEFAULT = { 1, 1, 1 }

local DEFAULTS = {
    profile = {
        health = {
            enabled     = false,
            width       = 214,
            height      = 16,
            borderSize  = 0,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            darkTheme   = false,
            customColored = false,
            fillR       = CUSTOM_FILL_DEFAULT[1], fillG = CUSTOM_FILL_DEFAULT[2], fillB = CUSTOM_FILL_DEFAULT[3], fillA = 1,
            bgR         = 0x11/255, bgG = 0x11/255, bgB = 0x11/255, bgA = 0.75,
            textFormat  = "none",  -- "none","both","curhpshort","perhp"
            textSize    = 11,
            textXOffset = 0,
            textYOffset = 0,
            textCustomColored = true,  -- text color: true = custom, false = class color
            textFillR   = 1, textFillG = 1, textFillB = 1, textFillA = 1,
            gradientEnabled = false,  -- additive: gradient fill (custom/class base -> end). Off = existing behavior.
            gradientR     = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
            gradientDir   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL"
            offsetX     = 0,
            offsetY     = -64,
            barAlpha    = 1.0,
            visibility  = "always",  -- "always","combat","target","mouseover","never","in_combat","in_raid","in_party","solo"
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            orientation = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            thresholdEnabled = false,
            thresholdPct     = 30,
            thresholdR = 1.0, thresholdG = 0.2, thresholdB = 0.2, thresholdA = 1,
            thresholdSpecs = {},
        },
        primary = {
            enabled     = true,
            width       = 214,
            height      = 14,
            borderSize  = 1,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            darkTheme   = false,
            customColored = false,
            fillR       = CUSTOM_FILL_DEFAULT[1], fillG = CUSTOM_FILL_DEFAULT[2], fillB = CUSTOM_FILL_DEFAULT[3], fillA = 1,
            bgR         = 0x11/255, bgG = 0x11/255, bgB = 0x11/255, bgA = 0.75,
            textFormat  = "perpp",  -- "none","smart","curpp","perpp","both"
            showPercent = true,
            textSize    = 10,
            textXOffset = 0,
            textYOffset = 0,
            textCustomColored = true,  -- text color: true = custom, false = power-type color
            textFillR   = 1, textFillG = 1, textFillB = 1, textFillA = 1,
            gradientEnabled = false,  -- additive: gradient fill (custom/power base -> end). Off = existing behavior.
            gradientR     = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
            gradientDir   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL"
            offsetX     = 0,
            offsetY     = -54,
            barAlpha    = 1.0,
            visibility  = "always",  -- "always","combat","target","mouseover","never","in_combat","in_raid","in_party","solo"
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            orientation = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            thresholdEnabled = false,
            thresholdPct     = 30,
            thresholdPartialOnly = false,
            thresholdR = 1.0, thresholdG = 0.2, thresholdB = 0.2, thresholdA = 1,
            thresholdSpecs = {},
            expandIfNoResource = false,
        },
        secondary = {
            enabled     = true,
            pipWidth    = 214,
            pipHeight   = 20,
            pipSpacing  = 1,
            pipOrientation = "HORIZONTAL",
            borderSize  = 1,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            darkTheme   = false,
            classColored = true,
            fillR       = 0.95, fillG = 0.90, fillB = 0.60, fillA = 1,
            bgR         = 1, bgG = 1, bgB = 1, bgA = 0.1,
            showText    = true,
            showPercent = true,
            showMaxStacks = true,
            textSize    = 11,
            textR       = 1, textG = 1, textB = 1,
            textXOffset = 0,
            textYOffset = 0,
            barBgR      = 0, barBgG = 0, barBgB = 0, barBgA = 0.5,
            barAlpha    = 1.0,
            thresholdEnabled = false,
            thresholdCount   = 3,
            thresholdPartialOnly = false,
            thresholdR = 0x0c/255, thresholdG = 0xd2/255, thresholdB = 0x9d/255, thresholdA = 1,
            tickValues  = "",   -- comma-separated absolute resource values for tick marks (bar-type only)
            thresholdSpecs = {},  -- per-spec threshold/hash entries: { specIDs={0}, hashValues="", thresholdCount=3, thresholdPartialOnly=false }
            guardianIronfurBar = true,     -- Guardian Druid: show Ironfur duration bar (moving hash lines). New-user default; existing profiles pinned off via migration "resourcebars_guardian_ironfur_existing_off_v1".
            guardianShowHashLines = true,  -- Guardian Ironfur: draw the moving per-cast hash lines
            protIgnorePainBar = true,      -- Prot Warrior: show Ignore Pain bar (total absorbs vs the IP cap = 30% max health; aura stacks are secret). New-user default; existing profiles pinned off via migration "resourcebars_protwar_ignorepain_existing_off_v1".
            protIgnorePainHashLine = true, -- Prot Ignore Pain: draw the moving duration hash line (resets on cast)
            runesSimple = false,  -- DK: treat runes as flat pips (no recharge animation/timer)
            chargedR = 0.44, chargedG = 0.77, chargedB = 1.00, chargedA = 1,
            enhanceFiveBar = true,  -- Enhance Shaman: show 5 pips with overflow coloring
            enhanceOverflowR = 1, enhanceOverflowG = 0.6, enhanceOverflowB = 0.2,
            visibility  = "always",  -- "always","combat","target","mouseover","never","in_combat","in_raid","in_party","solo"
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            oocAlpha    = 1.0,
            offsetX     = 0,
            offsetY     = -38,
            -- Shift elements anchored to the class resource bar when the spec
            -- has no class resource. "None" / "Up" / "Down". Visual-only.
            shiftElementsIfNoResource = "None",
        },
        castBar = {
            enabled       = true,
            showIcon      = true,
            width         = 220,
            height        = 20,
            anchorX       = 0,
            anchorY       = -54,
            classColored  = false,
            fillR         = 0.898, fillG = 0.729, fillB = 0.267, fillA = 1,
            gradientEnabled = false,
            gradientR     = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
            gradientDir   = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL"
            texture       = "none",
            showSpark     = true,
            borderSize    = 1,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            bgR           = 0, bgG = 0, bgB = 0, bgA = 0.7,
            showTimer     = true,
            timerSize     = 11,
            timerX        = 0,
            timerY        = 0,
            showSpellText = true,
            spellTextSize = 11,
            spellTextX    = 0,
            spellTextY    = 0,
            unlockPos     = nil,
            showChannelTicks  = true,
            showTickMarks     = true,
            tickMarksR = 1.0, tickMarksG = 1.0, tickMarksB = 1.0, tickMarksA = 0.7,
            showLastTick      = false,
            lastTickR = 1.0, lastTickG = 0.82, lastTickB = 0.0, lastTickA = 0.95,
            showGCDBoundary   = false,
            gcdBoundaryR = 1.0, gcdBoundaryG = 0.82, gcdBoundaryB = 0.0, gcdBoundaryA = 0.95,
            coloredEmpowerStages = false,  -- Color empowered spells from red to green per stage
            showTotalDuration = false,
            latencyEnabled    = false,
            latencyShowText   = false,
            latencyR = 0.835, latencyG = 0.290, latencyB = 0.290, latencyA = 1.0,
        },
        totemBar = {
            iconSize      = 30,
            spacing       = 2,
            showTimer     = true,
            timerSize     = 11,
            borderSize    = 1,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            borderTexture = "solid",
            unlockPos     = nil,
            enabledClasses = nil,  -- nil = disabled; { SHAMAN = true, ... } = enabled for listed classes
        },
        general = {
            anchorX     = 0,
            anchorY     = -100,
            orientation = "HORIZONTAL",  -- "HORIZONTAL","VERTICAL_UP","VERTICAL_DOWN"
            barTexture  = "none",
        },
    },
}


-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local mainFrame
local healthBar
local primaryBar
local secondaryFrame
local secondaryBar  -- bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom)
local secondaryBarTicks = {}  -- tick mark texture cache for bar-type secondary
local secondaryPipTicks = {}  -- tick mark texture cache for pip-type secondary hash lines
local castBarFrame
local totemBarFrame
local _totemBorderOverlays = setmetatable({}, { __mode = "k" })
local _totemHooked = false
local _totemOrigParent
local _latencySendTime      -- GetTime() at CURRENT_SPELL_CAST_CHANGED
local _latencyEventActive   -- true when CURRENT_SPELL_CAST_CHANGED is registered
local _erbEventFrame        -- file-scoped ref to the event frame (assigned in OnEnable)
local isInCombat = false
local currentAlpha = 1
local targetAlpha = 1
local cachedClass
local cachedPrimary
local cachedSecondary
local _ebonMightExpiry = 0
local _ebonMightThrottle = 0
local RefreshAnchoredBarsForUnlockTarget

-- Forward declarations
local UpdateCastBar
local BuildCastBar
local OnCastStart, OnChannelStart, OnChannelUpdate, OnCastStop, OnEmpowerStart, OnEmpowerUpdate
local ShowChannelTicks, HideChannelTicks

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function GetAccent()
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    if eg then return eg.r, eg.g, eg.b end
    return 12/255, 210/255, 157/255
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function FormatNumber(n)
    if n >= 1e6 then return format("%.1fM", n / 1e6) end
    if n >= 1e3 then return format("%.1fK", n / 1e3) end
    return tostring(floor(n))
end

local function IsVerticalOrientation(ori)
    return ori == "VERTICAL_UP" or ori == "VERTICAL_DOWN"
end

-- Cached empower stage thresholds (set once at empower start, avoids per-frame API call)
local cachedStageThresholds
-- Reusable CreateColor objects for gradient (avoids per-frame allocation)
local empowerColorA = CreateColor(1, 0, 0, 1)
local empowerColorB = CreateColor(1, 0, 0, 1)

-- Additive bar gradients use two REUSED color objects so applying the gradient
-- allocates nothing (CreateColor would allocate two tables per call). The gradient
-- is re-issued on every color update -- that is cheap (same order as SetVertexColor,
-- which flat bars already call each tick) and is never skipped or cached, so it can
-- never go stale.
local _gradColorA = CreateColor(1, 1, 1, 1)
local _gradColorB = CreateColor(1, 1, 1, 1)

local function ApplyBarGradient(ft, dir, br, bg, bb, ba, er, eg, eb, ea)
    ft:SetVertexColor(1, 1, 1, 1)
    _gradColorA:SetRGBA(br, bg, bb, ba)
    _gradColorB:SetRGBA(er, eg, eb, ea)
    ft:SetGradient(dir, _gradColorA, _gradColorB)
end

-- Flat-color a bar fill (no gradient).
local function ApplyBarFlat(ft, r, g, b, a)
    ft:SetVertexColor(r, g, b, a or 1)
end

-- Returns the current empowered stage (0-based) based on progress and cached thresholds
local function GetCurrentEmpowerStage(progress, numStages)
    if not numStages or numStages <= 0 then return 0 end
    local thresholds = cachedStageThresholds
    if not thresholds then return 0 end

    for i = 1, #thresholds do
        if progress < thresholds[i] then
            return i - 1
        end
    end
    return #thresholds
end

-- Returns RGB color for the current empower stage (red -> yellow -> green gradient)
local function GetEmpowerStageColor(stage, maxStages)
    if maxStages <= 1 then
        return 0, 1, 0
    end

    local t = stage / maxStages

    if t < 0.5 then
        return 1, t * 2, 0
    else
        return 1 - (t - 0.5) * 2, 1, 0
    end
end

local function OrientedSize(w, h, orientation)
    if IsVerticalOrientation(orientation) then
        return h, w  -- swap width and height for vertical bars
    end
    return w, h
end

local function ApplyBarOrientation(bar, orientation)
    if not bar then return end
    if orientation == "VERTICAL_UP" then
        bar:SetOrientation("VERTICAL")
        bar:SetRotatesTexture(true)
        bar:SetReverseFill(false)
    elseif orientation == "VERTICAL_DOWN" then
        bar:SetOrientation("VERTICAL")
        bar:SetRotatesTexture(true)
        bar:SetReverseFill(true)
    else
        bar:SetOrientation("HORIZONTAL")
        bar:SetRotatesTexture(false)
        bar:SetReverseFill(false)
    end
end

-------------------------------------------------------------------------------
--  Bar texture helper
-------------------------------------------------------------------------------
local function ApplyBarTexture(bar, texKey)
    if not bar then return end
    local path = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarTexture(path)
end


-- Compute pixel-snapped pip geometry for a given frame's effective scale.
-- Returns a table of {x0, x1} pairs (in logical units, snapped to physical
-- pixels) for each pip index 1..numPips. Spacing between every adjacent pair
-- is guaranteed to be exactly pipSp physical pixels at any UI scale.
local function CalcPipGeometry(totalW, numPips, pipSp, frame, esOverride)
    -- esOverride lets the caller pass the same effective scale used to
    -- snap the frame's outer dimensions. When omitted, falls back to the
    -- frame's live es. Passing an override eliminates the 1-px mismatch
    -- that arises when the frame's effective scale changes between the
    -- outer SetSize and this layout pass (parent reparent, scale chain
    -- update, etc.). The caller always owns the source of truth.
    local es = esOverride or frame:GetEffectiveScale()
    if es <= 0 then es = 1 end
    -- 1 physical pixel in this frame's coordinate space
    local onePixel = PP.perfect / es

    -- Snap spacing to nearest whole physical pixel (minimum 1px)
    local spPx = math.max(1, math.floor(pipSp / onePixel + 0.5))

    -- Total physical pixels for the whole bar
    local totalPx = math.floor(totalW / onePixel + 0.5)
    local gapPx   = spPx * (numPips - 1)
    local pipPx   = totalPx - gapPx
    local basePx  = math.floor(pipPx / numPips)
    local extraPx = pipPx - basePx * numPips -- first extraPx pips get +1px

    -- Build per-pip positions in physical pixels, convert to logical units once.
    local slots = {}
    local cursor = 0
    for i = 1, numPips do
        local w = basePx + (i <= extraPx and 1 or 0)
        local x1 = (cursor + w) * onePixel
        -- Clamp last pip's right edge to totalW so it never exceeds the container
        if i == numPips and x1 > totalW then x1 = totalW end
        slots[i] = { x0 = cursor * onePixel, x1 = x1 }
        cursor = cursor + w + spPx
    end

    return slots, spPx * onePixel, onePixel, totalPx * onePixel
end

local function MakePixelBorder(parent, r, g, b, a, size, textureKey, texOffset, texOffsetY, shiftX, shiftY)
    local alpha = a or 1
    local sz = size or 1
    local bf = CreateFrame("Frame", nil, parent)
    bf:SetAllPoints(parent)
    bf:SetFrameLevel(parent:GetFrameLevel() + 1)

    -- Use ApplyBorderStyle which handles both PP and BackdropTemplate
    EllesmereUI.ApplyBorderStyle(bf, sz, r, g, b, alpha, textureKey or "solid", texOffset, texOffsetY, shiftX, shiftY)

    return {
        _frame = bf,
        edges = PP.GetBorders(bf),
        SetColor = function(self, cr, cg, cb, ca)
            EllesmereUI.SetBorderStyleColor(bf, cr, cg, cb, ca or 1)
        end,
        SetSize = function(self, newSz)
            PP.SetBorderSize(bf, newSz)
        end,
        SetShown = function(self, shown)
            if shown then PP.ShowBorder(bf) else PP.HideBorder(bf) end
        end,
        ApplyStyle = function(self, newSz, cr, cg, cb, ca, texKey, texOff, texOffY, sX, sY, addonKey, sizeKey)
            EllesmereUI.ApplyBorderStyle(bf, newSz, cr, cg, cb, ca or 1, texKey or "solid", texOff, texOffY, sX, sY, addonKey, sizeKey)
        end,
    }
end

-------------------------------------------------------------------------------
--  Bar creation helpers
-------------------------------------------------------------------------------
local function CreateStatusBar(parent, name, w, h, borderSize, borderR, borderG, borderB, borderA)
    -- Outer container: holds the border and text (never clipped).
    local bar = CreateFrame("Frame", name, parent)
    bar:SetSize(w, h)
    bar:EnableMouse(false)

    -- Inner StatusBar: clips its fill. Inset by half a physical pixel so
    -- the fill can never bleed past the border at any resolution.
    local sb = CreateFrame("StatusBar", nil, bar)
    local halfPx = PP.mult * 0.5
    sb:SetPoint("TOPLEFT", bar, "TOPLEFT", halfPx, -halfPx)
    sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -halfPx, halfPx)
    sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetClipsChildren(true)
    bar._sb = sb

    -- Forward StatusBar methods to the inner bar so callers don't change
    bar.SetMinMaxValues = function(_, ...) sb:SetMinMaxValues(...) end
    bar.SetValue = function(_, ...) sb:SetValue(...) end
    bar.GetValue = function(_) return sb:GetValue() end
    bar.SetStatusBarTexture = function(_, ...) sb:SetStatusBarTexture(...) end
    bar.GetStatusBarTexture = function(_) return sb:GetStatusBarTexture() end
    bar.SetStatusBarColor = function(_, ...) sb:SetStatusBarColor(...) end
    bar.GetStatusBarColor = function(_) return sb:GetStatusBarColor() end
    bar.SetFillStyle = function(_, ...) sb:SetFillStyle(...) end
    bar.SetOrientation = function(_, ...) sb:SetOrientation(...) end
    bar.SetRotatesTexture = function(_, ...) sb:SetRotatesTexture(...) end
    bar.SetReverseFill = function(_, ...) sb:SetReverseFill(...) end

    -- Background (inside the clipped area)
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0x11/255, 0x11/255, 0x11/255, 0.75)
    bar._bg = bg

    -- Pixel-perfect border (on outer container, not clipped)
    local bSz = borderSize or 1
    bar._border = MakePixelBorder(bar, borderR or 0, borderG or 0, borderB or 0, borderA or 1, bSz)

    function bar:ApplyBorder(sz, r, g, b, a, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey, behind)
        -- "Show Behind": set the border frame level before styling so the textured
        -- backdrop inherits it. +1 draws in front of the fill, level-1 behind it.
        if self._border._frame then
            local pl = self:GetFrameLevel()
            self._border._frame:SetFrameLevel(behind and math.max(0, pl - 1) or (pl + 1))
        end
        self._border:ApplyStyle(sz, r, g, b, a, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey)
    end

    -- Text overlay (above all bar borders)
    local textFrame = CreateFrame("Frame", nil, bar)
    textFrame:SetAllPoints(bar)
    textFrame:SetFrameLevel(25)
    textFrame:EnableMouse(false)
    local text = textFrame:CreateFontString(nil, "OVERLAY")
    SetRBFont(text, GetRBFont(), 11)
    text:SetTextColor(1, 1, 1, 0.9)
    text:SetPoint("CENTER", textFrame, "CENTER")
    bar._text = text

    -- Smooth animation state
    bar._smoothTarget = 0
    bar._smoothCurrent = 0

    return bar
end

-- Create a single pip (for combo points, holy power, etc.)
local function CreatePip(parent, w, h, idx, borderSize, borderR, borderG, borderB, borderA)
    local pip = CreateFrame("Frame", nil, parent)
    pip:SetSize(w, h)

    local bg = pip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    pip._bg = bg

    local fill = pip:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetColorTexture(1, 1, 1, 1)
    pip._fill = fill
    pip._texKey = nil  -- current bar texture key

    -- Pixel-perfect border with variable size
    local bSz = borderSize or 1
    pip._border = MakePixelBorder(pip, borderR or 0, borderG or 0, borderB or 0, borderA or 1, bSz)

    function pip:ApplyBorder(sz, r, g, b, a, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey)
        self._border:ApplyStyle(sz, r, g, b, a, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey)
    end

    function pip:ApplyTexture(texKey)
        self._texKey = texKey
        local path = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
        self._fill:SetTexture(path)
        if self._rechargeBar then
            self._rechargeBar:SetStatusBarTexture(path)
        end
    end

    pip._active = false
    pip._idx = idx

    function pip:SetActive(active, r, g, b, a)
        self._active = active
        if active then
            self._fill:SetVertexColor(r, g, b, a or 1)
            self._fill:Show()
        else
            self._fill:Hide()
        end
    end

    return pip
end


-------------------------------------------------------------------------------
--  Main frame construction
-------------------------------------------------------------------------------
local pips = {}
local runeFrames = {}

-------------------------------------------------------------------------------
--  Smooth animation helper for actual bar scale / offset changes
-------------------------------------------------------------------------------
local _barAnimTimers = {}
local BAR_ANIM_DURATION = 0.18

local function SmoothBarAnimate(frame, key, targetVal, applyFn)
    if not frame then return end
    if not _barAnimTimers[frame] then _barAnimTimers[frame] = {} end
    if _barAnimTimers[frame][key] then
        _barAnimTimers[frame][key]:Cancel()
        _barAnimTimers[frame][key] = nil
    end
    local startVal = frame["_barAnim_" .. key] or targetVal
    if math.abs(startVal - targetVal) < 0.001 then
        frame["_barAnim_" .. key] = targetVal
        applyFn(targetVal)
        return
    end
    local elapsed = 0
    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        elapsed = elapsed + 0.016
        local t = math.min(elapsed / BAR_ANIM_DURATION, 1)
        t = 1 - (1 - t) * (1 - t)  -- ease-out quad
        local v = startVal + (targetVal - startVal) * t
        frame["_barAnim_" .. key] = v
        applyFn(v)
        if t >= 1 then
            frame["_barAnim_" .. key] = targetVal
            ticker:Cancel()
            if _barAnimTimers[frame] then _barAnimTimers[frame][key] = nil end
        end
    end)
    _barAnimTimers[frame][key] = ticker
end

local function BuildMainFrame()
    if mainFrame then return mainFrame end

    local g = ERB.db.profile.general or DEFAULTS.profile.general

    mainFrame = CreateFrame("Frame", "EllesmereUIResourceBarsFrame", UIParent)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", g.anchorX or 0, g.anchorY or -100)
    mainFrame:SetSize(1, 1)  -- invisible anchor point
    mainFrame:SetFrameStrata(g.frameStrata or "MEDIUM")
    mainFrame:SetFrameLevel(5)

    return mainFrame
end


-------------------------------------------------------------------------------
--  Per-spec bar enable check
-------------------------------------------------------------------------------
local function IsSpecDisabled(barCfg)
    local disabledSpecs = barCfg and barCfg.disabledSpecs
    if not disabledSpecs then return false end
    local specIdx = GetSpecialization()
    if not specIdx then return false end
    local specID = specIdx and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(specIdx)
    return specID and disabledSpecs[specID] or false
end

-------------------------------------------------------------------------------
--  Unlock mode: register with shared EllesmereUI unlock system
-------------------------------------------------------------------------------
local function RegisterUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement

    -- Shared helper: save position to a settings sub-table and apply to frame
    local function MakePosHelpers(getSettings, frame_fn, defaultOffX, defaultOffY)
        local function savePos(key, point, relPoint, x, y)
            if not point then return end
            local s = getSettings()
            s.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive then
                local f = frame_fn()
                if f then
                    f:ClearAllPoints()
                    f:SetPoint(point, UIParent, relPoint or point, x, y)
                end
            end
        end
        local function loadPos()
            local pos = getSettings().unlockPos
            if not pos then return nil end
            local pt = pos.point
            return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
        end
        local function clearPos()
            local s = getSettings()
            s.unlockPos = nil
            if defaultOffX then s.offsetX = defaultOffX end
            if defaultOffY then s.offsetY = defaultOffY end
        end
        local function applyPos()
            local s = getSettings()
            if s.anchorTo and s.anchorTo ~= "none" then return end
            local pos = s.unlockPos
            if not pos then return end
            local f = frame_fn()
            if f then
                local pt = pos.point
                local px, py = pos.x, pos.y
                local PPa = EllesmereUI and EllesmereUI.PP
                if PPa and px and py then
                    local es = f:GetEffectiveScale()
                    -- For CENTER anchor with stored CENTER offsets, use
                    -- SnapCenterForDim with the frame's actual size so odd-
                    -- pixel-dim frames get the +0.5 center offset that places
                    -- their edges on whole pixels (plain SnapForES rounds the
                    -- center to a whole pixel and forces edges to half pixels,
                    -- causing 1px drift on save & exit / spec swap).
                    local isCenterAnchor = (pt == "CENTER")
                        and (pos.relPoint == "CENTER" or pos.relPoint == nil)
                    if isCenterAnchor and PPa.SnapCenterForDim then
                        px = PPa.SnapCenterForDim(px, f:GetWidth() or 0, es)
                        py = PPa.SnapCenterForDim(py, f:GetHeight() or 0, es)
                    elseif PPa.SnapForES then
                        px = PPa.SnapForES(px, es)
                        py = PPa.SnapForES(py, es)
                    end
                end
                f:ClearAllPoints()
                f:SetPoint(pt, UIParent, pos.relPoint or pt, px, py)
            end
        end
        return savePos, loadPos, clearPos, applyPos
    end

    local function Rebuild() ERB:ApplyAll() end
    local function LiveMove(key)
        if RefreshAnchoredBarsForUnlockTarget then RefreshAnchoredBarsForUnlockTarget(key) end
    end

    local elements = {}

    -- Health Bar
    do
        local function S() return ERB.db.profile.health end
        local save, load, clear, apply = MakePosHelpers(S, function() return healthBar end, 0, -65)
        elements[#elements + 1] = MK({
            key = "ERB_Health", label = "Health Bar", group = "Resource Bars", order = 500,
            getFrame = function() return healthBar end,
            isHidden = function() local s = S(); return not s.enabled or IsSpecDisabled(s) end,
            getSize  = function()
                local s = S(); return s.width, s.height
            end,
            setWidth = function(_, w) S().width = PP.Snap(w); Rebuild() end,
            setHeight = function(_, h) S().height = PP.Snap(h); Rebuild() end,
            isAnchored = function() local s = S(); return s.anchorTo and s.anchorTo ~= "none" end,
            onLiveMove = LiveMove,
            savePos = save, loadPos = load, clearPos = clear, applyPos = apply,
        })
    end

    -- Power Bar
    do
        local function S() return ERB.db.profile.primary end
        local save, load, clear, apply = MakePosHelpers(S, function() return primaryBar end, 0, -74)
        elements[#elements + 1] = MK({
            key = "ERB_Power", label = "Power Bar", group = "Resource Bars", order = 501,
            getFrame = function() return primaryBar end,
            isHidden = function() local s = S(); return s.enabled == false or IsSpecDisabled(s) end,
            getSize  = function()
                local s = S(); return s.width or 214, s.height or 14
            end,
            setWidth = function(_, w) S().width = PP.Snap(w); Rebuild() end,
            setHeight = function(_, h) S().height = PP.Snap(h); Rebuild() end,
            isAnchored = function() local s = S(); return s.anchorTo and s.anchorTo ~= "none" end,
            onLiveMove = LiveMove,
            savePos = save, loadPos = load, clearPos = clear, applyPos = apply,
        })
    end

    -- Class Resource (pips/runes)
    do
        local function S() return ERB.db.profile.secondary end
        local save, load, clear, apply = MakePosHelpers(S, function() return secondaryFrame end, 0, -38)
        elements[#elements + 1] = MK({
            key = "ERB_ClassResource", label = "Class Resource", group = "Resource Bars", order = 502,
            getFrame = function() return secondaryFrame end,
            getSize  = function()
                local s = S()
                return s.pipWidth, s.pipHeight
            end,
            setWidth = function(_, w)
                local s = S()
                s.pipWidth = PP.Snap(w)
                Rebuild()
            end,
            setHeight = function(_, h) S().pipHeight = PP.Snap(h); Rebuild() end,
            isAnchored = function() local s = S(); return s.anchorTo and s.anchorTo ~= "none" end,
            onLiveMove = LiveMove,
            savePos = save, loadPos = load, clearPos = clear, applyPos = apply,
        })
    end

    -- Cast Bar
    do
        local function S() return ERB.db.profile.castBar end
        local function castSave(key, point, relPoint, x, y)
            if not point then return end
            local cb = S()
            cb.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive and castBarFrame then
                castBarFrame:ClearAllPoints()
                castBarFrame:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end
        local function castLoad()
            local pos = S().unlockPos
            if not pos then return nil end
            local pt = pos.point
            return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
        end
        local function castClear()
            local cb = S()
            cb.unlockPos = nil
            cb.anchorX = 0; cb.anchorY = -54
        end
        local function castApply()
            local pos = S().unlockPos
            if not pos then return end
            if castBarFrame then
                local pt = pos.point
                local sx, sy = SnapXY(pos.x, pos.y, castBarFrame, pos)
                castBarFrame:ClearAllPoints()
                castBarFrame:SetPoint(pt, UIParent, pos.relPoint or pt, sx, sy)
            end
        end
        elements[#elements + 1] = MK({
            key = "ERB_CastBar", label = "Cast Bar", group = "Resource Bars", order = 504,
            noAnchorTarget = true,
            getFrame = function() return castBarFrame end,
            getSize  = function()
                local cb = S()
                local iconW = (cb.showIcon ~= false) and cb.height or 0
                return cb.width + iconW, cb.height
            end,
            setWidth = function(_, w)
                local cb = S()
                local iconW = (cb.showIcon ~= false) and cb.height or 0
                cb.width = PP.Snap(math.max(w - iconW, 10))
                Rebuild()
            end,
            setHeight = function(_, h) S().height = PP.Snap(h); Rebuild() end,
            savePos = castSave, loadPos = castLoad, clearPos = castClear, applyPos = castApply,
        })
    end

    -- Totem Bar
    do
        local function S() return ERB.db.profile.totemBar end
        local function totemSave(key, point, relPoint, x, y)
            if not point then return end
            local tb = S()
            tb.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive and totemBarFrame then
                totemBarFrame:ClearAllPoints()
                totemBarFrame:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end
        local function totemLoad()
            local pos = S().unlockPos
            if not pos then return nil end
            local pt = pos.point
            return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
        end
        local function totemClear()
            S().unlockPos = nil
        end
        local function totemApply()
            local pos = S().unlockPos
            if not pos then return end
            if totemBarFrame then
                local pt = pos.point
                local sx, sy = SnapXY(pos.x, pos.y, totemBarFrame, pos)
                totemBarFrame:ClearAllPoints()
                totemBarFrame:SetPoint(pt, UIParent, pos.relPoint or pt, sx, sy)
            end
        end
        elements[#elements + 1] = MK({
            key = "ERB_TotemBar", label = "Totem Bar", group = "Resource Bars", order = 505,
            noResize = true,
            noAnchorTarget = true,
            getFrame = function() return totemBarFrame end,
            getSize  = function()
                local tb = S()
                local iconSz = tb.iconSize or 30
                local spacing = tb.spacing or 2
                -- Estimate width based on max 5 totems
                return iconSz * 5 + spacing * 4, iconSz
            end,
            savePos = totemSave, loadPos = totemLoad, clearPos = totemClear, applyPos = totemApply,
        })
    end

    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIResourceBars")
end

_G._ERB_ApplyUnlock = function()
    -- The shared unlock system handles everything now
end
_G._ERB_RegisterUnlock = RegisterUnlockElements

-------------------------------------------------------------------------------
--  Anchor resolution helper
--  Returns the target frame for a given anchorTo key, or nil if not available.
-------------------------------------------------------------------------------
local ERB_ANCHOR_FRAMES = {
    erb_classresource = function() return secondaryFrame end,
    erb_powerbar      = function() return primaryBar end,
    erb_health        = function() return healthBar end,
    erb_castbar       = function() return castBarFrame end,
    erb_cdm           = function() return _G._ECME_GetBarFrame and _G._ECME_GetBarFrame("cooldowns") end,
    mouse             = nil,  -- handled separately
    partyframe        = nil,  -- handled separately
    playerframe       = nil,  -- handled separately
}

local ERB_VALID_ANCHORS = EllesmereUI.RESOURCE_BAR_ANCHOR_KEYS

local function ResolveAnchorFrame(anchorKey)
    local fn = ERB_ANCHOR_FRAMES[anchorKey]
    if fn then return fn() end
    return nil
end

local function NormalizeAnchorKey(anchorKey)
    if anchorKey and ERB_VALID_ANCHORS[anchorKey] then
        return anchorKey
    end
    return "none"
end

-- Vertical "effective Y" of a resource bar read from STORED config (screen up =
-- +y). Used by the expand-direction detection below: when the spec has no class
-- resource the class resource frame is never laid out, so live bounds (GetTop /
-- GetCenter) are unavailable and direction must come from config. Dragged bars
-- store unlockPos as CENTER/CENTER; free bars use offsetY relative to the
-- screen-centered mainFrame -- both are CENTER-relative and comparable.
local function BarEffectiveY(cfg)
    if cfg and cfg.unlockPos and cfg.unlockPos.point and cfg.unlockPos.y then
        return cfg.unlockPos.y
    end
    return (cfg and cfg.offsetY) or 0
end

-- "Expand Power Bar if No Resource" direction. The power bar fills the area the
-- (absent) class resource bar would occupy, so it grows TOWARD the class
-- resource: +1 = class resource sits ABOVE the power bar -> grow up; -1 = below
-- -> grow down. Pure read of stored config (no writes, no live bounds). Falls
-- back to +1 (grow up -- the default layout has the class resource above) when
-- the class resource is disabled or the two bars are co-located.
local function ResolveExpandDirSign(pp, sp)
    if not sp or sp.enabled == false then return 1 end
    -- Anchored: class resource pinned relative to the power bar.
    if NormalizeAnchorKey(sp.anchorTo) == "erb_powerbar" then
        if sp.anchorPosition == "bottom" then return -1 end
        if sp.anchorPosition == "top" then return 1 end
    end
    -- Anchored the other way: power bar pinned relative to the class resource.
    if NormalizeAnchorKey(pp.anchorTo) == "erb_classresource" then
        if pp.anchorPosition == "top" then return -1 end     -- power above CR -> CR below -> grow down
        if pp.anchorPosition == "bottom" then return 1 end   -- power below CR -> CR above -> grow up
    end
    -- Free / dragged: compare stored vertical positions.
    local sy, py = BarEffectiveY(sp), BarEffectiveY(pp)
    if sy > py then return 1 elseif sy < py then return -1 end
    return 1
end

-- Apply anchor-based positioning for a bar frame.
-- anchorKey: the anchorTo setting value
-- anchorPos: "left"/"right"/"top"/"bottom"
-- frame: the bar frame to position
-- offsetX, offsetY: additional offsets
-- growthDir: "UP", "DOWN", "LEFT", "RIGHT" -- which direction the bar grows from the anchor edge
-- growCentered: true = bar centered on anchor edge midpoint; false = bar corner at anchor edge midpoint
-- Recursively set mouse passthrough on a frame and all its children.
-- Stores original state on first call so it can be restored.
local function SetFrameClickThrough(frame, clickThrough)
    if not frame then return end
    if clickThrough then
        -- Store original state if not already stored
        if frame._erbMouseWas == nil then
            frame._erbMouseWas = frame:IsMouseEnabled()
        end
        frame:EnableMouse(false)
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
    else
        -- Restore original state
        if frame._erbMouseWas ~= nil then
            frame:EnableMouse(frame._erbMouseWas)
            frame._erbMouseWas = nil
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        SetFrameClickThrough(child, clickThrough)
    end
end

local function ApplyBarAnchor(frame, anchorKey, anchorPos, offsetX, offsetY, growthDir, growCentered)
    -- Always clear any previous mouse-tracking OnUpdate
    if frame._erbMouseTrack then
        frame:SetScript("OnUpdate", nil)
        frame._erbMouseTrack = nil
        local g = ERB.db and ERB.db.profile and ERB.db.profile.general
        frame:SetFrameStrata(g and g.frameStrata or "MEDIUM")
        frame:SetFrameLevel(5)
        -- Restore mouse on frame and all children
        SetFrameClickThrough(frame, false)
        if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
    end

    if not anchorKey or anchorKey == "none" then return false end
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    -- Snap offsets to physical pixel grid
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa and PPa.SnapForES then
        local es = frame:GetEffectiveScale()
        offsetX = PPa.SnapForES(offsetX, es)
        offsetY = PPa.SnapForES(offsetY, es)
    end
    anchorPos = anchorPos or "left"
    growthDir = growthDir or "UP"
    local centered = (growCentered ~= false)

    local function GetAnchorPoints()
        if anchorPos == "left" then
            return "RIGHT", "LEFT"
        elseif anchorPos == "right" then
            return "LEFT", "RIGHT"
        elseif anchorPos == "top" then
            return "BOTTOM", "TOP"
        elseif anchorPos == "bottom" then
            return "TOP", "BOTTOM"
        end
        return "LEFT", "RIGHT"
    end

    if anchorKey == "mouse" then
        -- Determine SetPoint anchor and directional nudge based on anchorPos
        local pointFrom, baseOX, baseOY
        if anchorPos == "left" then
            pointFrom = "RIGHT"; baseOX = -15 + offsetX; baseOY = offsetY
        elseif anchorPos == "right" then
            pointFrom = "LEFT"; baseOX = 15 + offsetX; baseOY = offsetY
        elseif anchorPos == "top" then
            pointFrom = "BOTTOM"; baseOX = offsetX; baseOY = 15 + offsetY
        elseif anchorPos == "bottom" then
            pointFrom = "TOP"; baseOX = offsetX; baseOY = -15 + offsetY
        else
            pointFrom = "LEFT"; baseOX = 15 + offsetX; baseOY = offsetY
        end
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(9980)
        frame:ClearAllPoints()
        frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        frame._erbMouseTrack = true
        -- Make frame and all children fully click-through while following cursor
        SetFrameClickThrough(frame, true)
        local lastMX, lastMY
        frame:SetScript("OnUpdate", function()
            local s = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx = floor(cx / s + 0.5)
            cy = floor(cy / s + 0.5)
            if cx ~= lastMX or cy ~= lastMY then
                lastMX, lastMY = cx, cy
                frame:ClearAllPoints()
                frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", cx + baseOX, cy + baseOY)
            end
        end)
        return true
    elseif anchorKey == "partyframe" then
        local partyFrame = EllesmereUI and EllesmereUI.FindPlayerPartyFrame and EllesmereUI.FindPlayerPartyFrame()
        if not partyFrame then return false end
        local framePoint, targetPoint = GetAnchorPoints()
        frame:ClearAllPoints()
        frame:SetPoint(framePoint, partyFrame, targetPoint, offsetX, offsetY)
        return true
    elseif anchorKey == "playerframe" then
        local playerFrame = EllesmereUI and EllesmereUI.FindPlayerUnitFrame and EllesmereUI.FindPlayerUnitFrame()
        if not playerFrame then return false end
        local framePoint, targetPoint = GetAnchorPoints()
        frame:ClearAllPoints()
        frame:SetPoint(framePoint, playerFrame, targetPoint, offsetX, offsetY)
        return true
    end

    local targetFrame = ResolveAnchorFrame(anchorKey)
    if not targetFrame or not targetFrame:IsShown() then return false end

    frame:ClearAllPoints()
    local framePoint, targetPoint = GetAnchorPoints()
    local ok
    ok = pcall(frame.SetPoint, frame, framePoint, targetFrame, targetPoint, offsetX, offsetY)
    return ok or false
end

local UNLOCK_TARGET_TO_ERB_ANCHOR = {
    ERB_Health = "erb_health",
    ERB_Power = "erb_powerbar",
    ERB_ClassResource = "erb_classresource",
    ERB_CastBar = "erb_castbar",
}

local function GetAnchorOffsets(settings)
    if not settings then return 0, 0 end
    local offsetX = settings.anchorOffsetX
    if offsetX == nil then offsetX = settings.anchorX end
    local offsetY = settings.anchorOffsetY
    if offsetY == nil then offsetY = settings.anchorY end
    return offsetX or 0, offsetY or 0
end

local function ApplyFreeBarPosition(frame, settings, defaultX, defaultY, width, height)
    if not frame then return end

    local pos = settings and settings.unlockPos
    frame:SetSize(width, height)
    frame:ClearAllPoints()

    if pos and pos.point then
        local sx, sy = SnapXY(pos.x, pos.y, frame, pos)
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
        return
    end

    frame:SetPoint("CENTER", mainFrame, "CENTER", settings.offsetX or defaultX or 0, settings.offsetY or defaultY or 0)
end

local function ReapplyInternalBarAnchors()
    if not (ERB and ERB.db and ERB.db.profile) then return end

    local p = ERB.db.profile
    local anchoredBars = {
        { frame = healthBar, settings = p.health },
        { frame = primaryBar, settings = p.primary },
        { frame = secondaryFrame, settings = p.secondary },
    }

    for _ = 1, 2 do
        for _, info in ipairs(anchoredBars) do
            local frame = info.frame
            local settings = info.settings
            local anchorKey = settings and settings.anchorTo
            if frame and settings and frame:IsShown()
                and anchorKey and anchorKey ~= "none"
                and ERB_ANCHOR_FRAMES[anchorKey]
            then
                local offsetX, offsetY = GetAnchorOffsets(settings)
                ApplyBarAnchor(frame, anchorKey, settings.anchorPosition, offsetX, offsetY, settings.growthDirection, settings.growCentered)
            end
        end
    end
end

RefreshAnchoredBarsForUnlockTarget = function(unlockKey)
    local targetAnchor = UNLOCK_TARGET_TO_ERB_ANCHOR[unlockKey]
    if not (targetAnchor and ERB and ERB.db and ERB.db.profile) then return end

    local p = ERB.db.profile
    local bars = {
        { frame = healthBar, settings = p.health },
        { frame = primaryBar, settings = p.primary },
        { frame = secondaryFrame, settings = p.secondary },
    }

    for _ = 1, 2 do
        for _, info in ipairs(bars) do
            local frame = info.frame
            local settings = info.settings
            if frame and settings and frame:IsShown()
                and settings.anchorTo == targetAnchor
            then
                local offsetX, offsetY = GetAnchorOffsets(settings)
                ApplyBarAnchor(frame, settings.anchorTo, settings.anchorPosition, offsetX, offsetY, settings.growthDirection, settings.growCentered)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Resource bar tick marks (bar-type secondary only)
-------------------------------------------------------------------------------

-- Parse comma-separated tick values string into a table of numbers.
local function ParseTickValues(str)
    if not str or str == "" then return nil end
    local vals = {}
    for s in str:gmatch("[^,]+") do
        local n = tonumber(s:match("^%s*(.-)%s*$"))
        if n and n > 0 then vals[#vals + 1] = n end
    end
    if #vals == 0 then return nil end
    return vals
end

-- Apply tick marks to a resource bar or pip container.
-- sb: the frame, maxVal: max resource value, tickStr: comma-separated values,
-- tickCache: table to store tick textures,
-- hashWidth: pixel width (default 1), hashR/G/B/A: color (default white)
local function ApplyResourceBarTicks(sb, maxVal, tickStr, tickCache, hashWidth, hashR, hashG, hashB, hashA)
    local vals = ParseTickValues(tickStr)

    for i = 1, #tickCache do tickCache[i]:Hide() end

    if not vals or not sb or maxVal <= 0 then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local tickW = hashWidth or 1
    local tR, tG, tB, tA = hashR or 1, hashG or 1, hashB or 1, hashA or 0.7

    -- Tick textures must live on a frame ABOVE the inner StatusBar (_sb) so the
    -- fill texture doesn't cover them. Use a dedicated overlay frame parented to
    -- the outer bar container, sitting one level above the inner StatusBar.
    if not sb._tickOverlay then
        local ov = CreateFrame("Frame", nil, sb)
        ov:SetAllPoints()
        local innerSb = sb._sb
        if innerSb then
            ov:SetFrameLevel(innerSb:GetFrameLevel() + 1)
        end
        sb._tickOverlay = ov
    end
    local tickParent = sb._tickOverlay

    -- Create tick textures as needed
    while #tickCache < #vals do
        local t = tickParent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        tickCache[#tickCache + 1] = t
    end

    local pxW = PP and (tickW * PP.mult) or tickW
    local barW = sb:GetWidth()
    local barH = sb:GetHeight()
    for i, v in ipairs(vals) do
        if v <= maxVal then
            local t = tickCache[i]
            t:SetColorTexture(tR, tG, tB, tA)
            local frac = v / maxVal
            t:ClearAllPoints()
            local off = PP and PP.Scale(barW * frac) or (barW * frac)
            t:SetSize(pxW, barH)
            t:SetPoint("TOPLEFT", sb, "TOPLEFT", off, 0)
            t:Show()
        end
    end
end

-- Moving-hash overlay for the Guardian Ironfur bar. Lives above the inner
-- StatusBar fill so the tick textures are never covered. Tick textures are
-- pooled in ironfurTickTex (secondaryBar is a singleton).
local ironfurTickTex = {}
local function EnsureIronfurOverlay(sb)
    if sb._ifOverlay then return sb._ifOverlay end
    local ov = CreateFrame("Frame", nil, sb)
    ov:SetAllPoints()
    local innerSb = sb._sb
    if innerSb then ov:SetFrameLevel(innerSb:GetFrameLevel() + 2) end
    sb._ifOverlay = ov
    return ov
end

-------------------------------------------------------------------------------
--  BuildBars -- applies per-element scale, border, colors, text positioning
-------------------------------------------------------------------------------

local function BuildBars()
    local p = ERB.db.profile

    -- If the profile is missing critical sub-tables, reset to defaults
    if type(p.primary) ~= "table" or type(p.secondary) ~= "table"
    or type(p.general) ~= "table" then
        ERB.db:ResetProfile()
        p = ERB.db.profile
    end

    local g = p.general or DEFAULTS.profile.general

    if not mainFrame then BuildMainFrame() end

    -- Clear animation state so DB values are always authoritative on a fresh build
    local _animClearKeys = { "scale", "ox", "oy", "w", "h" }
    for _, _animBar in ipairs({ healthBar, primaryBar, secondaryFrame, castBarFrame }) do
        if _animBar then
            for _, _k in ipairs(_animClearKeys) do
                _animBar["_barAnim_" .. _k] = nil
            end
        end
    end

    -- Fallback defaults for nil-safe reads
    local FALLBACK = DEFAULTS.profile

    -- Health bar
    local hp = p.health or FALLBACK.health
    -- Snap stored width/height to the physical pixel grid so the frame is
    -- always a whole number of physical pixels. Use SnapForES (round to
    -- nearest) rather than PP.Scale (truncate) -- see Power bar note below.
    local hpWidth = hp.width or 214
    local hpHeight = hp.height or 16
    local _hpEs = (healthBar and healthBar:GetEffectiveScale()) or (UIParent and UIParent:GetEffectiveScale()) or 1
    if PP and PP.SnapForES then
        hpWidth = PP.SnapForES(hpWidth, _hpEs)
        hpHeight = PP.SnapForES(hpHeight, _hpEs)
    end
    do
        local hpOri = hp.orientation or g.orientation or "HORIZONTAL"
        if not healthBar then
            healthBar = CreateStatusBar(mainFrame, "ERB_HealthBar", hpWidth, hpHeight,
                hp.borderSize, hp.borderR, hp.borderG, hp.borderB, hp.borderA)
            healthBar:SetFrameStrata(g.frameStrata or "MEDIUM")
            healthBar:SetFrameLevel(10)
        end
        if not hp.enabled then
            -- Disabled: keep frame positioned at zero alpha for anchors
            local ow, oh = OrientedSize(hpWidth, hpHeight, hpOri)
            healthBar:SetSize(ow, oh)
            healthBar:Show()
            if hp.unlockPos and hp.unlockPos.point then
                local rp = hp.unlockPos.relPoint or hp.unlockPos.point
                local sx, sy = SnapXY(hp.unlockPos.x, hp.unlockPos.y, healthBar, hp.unlockPos)
                healthBar:ClearAllPoints()
                healthBar:SetPoint(hp.unlockPos.point, UIParent, rp, sx, sy)
            end
            EllesmereUI.SetElementVisibility(healthBar, false)
        else
        local healthAnchorKey = NormalizeAnchorKey(hp.anchorTo)
        if healthAnchorKey ~= "none" then
            local ow, oh = OrientedSize(hpWidth, hpHeight, hpOri)
            local offsetX, offsetY = GetAnchorOffsets(hp)
            healthBar:SetSize(ow, oh)
            if not ApplyBarAnchor(healthBar, healthAnchorKey, hp.anchorPosition, offsetX, offsetY, hp.growthDirection, hp.growCentered) then
                ApplyFreeBarPosition(healthBar, hp, 0, -64, ow, oh)
            end
        elseif hp.unlockPos and hp.unlockPos.point then
            local rp = hp.unlockPos.relPoint or hp.unlockPos.point
            local ow, oh = OrientedSize(hpWidth, hpHeight, hpOri)
            ApplyBarAnchor(healthBar, "none")
            healthBar:SetSize(ow, oh)
            if not EllesmereUI._unlockActive then
                if not EllesmereUI.IsUnlockAnchored("ERB_Health") or not healthBar:GetLeft() then
                    local sx, sy = SnapXY(hp.unlockPos.x, hp.unlockPos.y, healthBar, hp.unlockPos)
                    healthBar:ClearAllPoints()
                    healthBar:SetPoint(hp.unlockPos.point, UIParent, rp, sx, sy)
                end
            end
        else
            -- Clear any mouse-tracking OnUpdate from a previous anchor
            ApplyBarAnchor(healthBar, "none")
            if EllesmereUI._unlockActive then
                -- During unlock mode, only update size -- position is managed by the mover
                local ow, oh = OrientedSize(hpWidth, hpHeight, hpOri)
                healthBar:SetSize(ow, oh)
            else
                local function ApplyHealthBarTransform()
                    local ox = healthBar["_barAnim_ox"] or hp.offsetX or 0
                    local oy = healthBar["_barAnim_oy"] or hp.offsetY or -64
                    local w = healthBar["_barAnim_w"] or hpWidth
                    local h2 = healthBar["_barAnim_h"] or hpHeight
                    local ow, oh = OrientedSize(w, h2, hpOri)
                    healthBar:ClearAllPoints()
                    healthBar:SetPoint("CENTER", mainFrame, "CENTER", ox, oy)
                    healthBar:SetSize(ow, oh)
                end
                SmoothBarAnimate(healthBar, "ox", hp.offsetX or 0, function() ApplyHealthBarTransform() end)
                SmoothBarAnimate(healthBar, "oy", hp.offsetY or -64, function() ApplyHealthBarTransform() end)
                SmoothBarAnimate(healthBar, "w", hpWidth, function() ApplyHealthBarTransform() end)
                SmoothBarAnimate(healthBar, "h", hpHeight, function() ApplyHealthBarTransform() end)
            end
        end
        healthBar:ApplyBorder(hp.borderSize, hp.borderR, hp.borderG, hp.borderB, hp.borderA, hp.borderTexture, hp.borderTextureOffset, hp.borderTextureOffsetY, hp.borderTextureShiftX, hp.borderTextureShiftY, "resourcebars", hp.borderSize, hp.borderBehind)

        -- Bar texture (must be applied before colors since SetStatusBarTexture resets vertex color)
        ApplyBarTexture(healthBar, g.barTexture or "none")

        -- Colors: dark theme > custom colored > class color.
        -- Gradient is additive: when enabled it fills from the resolved custom/class
        -- base color to the gradient end color. Dark theme ignores gradient.
        local hft = healthBar:GetStatusBarTexture()
        if hp.darkTheme then
            hft:SetVertexColor(DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, DARK_FILL_A)
            healthBar._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, DARK_BG_A)
        else
            local fR, fG, fB, fA
            if hp.customColored then
                fR, fG, fB, fA = hp.fillR, hp.fillG, hp.fillB, hp.fillA
            else
                local cc = CLASS_COLORS[cachedClass]
                if cc then fR, fG, fB, fA = cc[1], cc[2], cc[3], 1
                else fR, fG, fB, fA = 0.15, 0.75, 0.30, 1 end
            end
            if hp.gradientEnabled then
                ApplyBarGradient(hft, hp.gradientDir or "HORIZONTAL",
                    fR, fG, fB, fA,
                    hp.gradientR, hp.gradientG, hp.gradientB, hp.gradientA)
            else
                ApplyBarFlat(hft, fR, fG, fB, fA)
            end
            healthBar._bg:SetColorTexture(hp.bgR, hp.bgG, hp.bgB, hp.bgA)
        end

        -- Text positioning
        healthBar._text:ClearAllPoints()
        healthBar._text:SetPoint("CENTER", healthBar, "CENTER", hp.textXOffset, hp.textYOffset)
        SetRBFont(healthBar._text, GetRBFont(), hp.textSize)
        -- Text color: class color when textCustomColored == false, else custom (default custom)
        if hp.textCustomColored == false then
            local tcc = CLASS_COLORS[cachedClass]
            if tcc then
                healthBar._text:SetTextColor(tcc[1], tcc[2], tcc[3], 1)
            else
                healthBar._text:SetTextColor(1, 1, 1, 1)
            end
        else
            healthBar._text:SetTextColor(hp.textFillR or 1, hp.textFillG or 1, hp.textFillB or 1, hp.textFillA or 1)
        end
        healthBar:Show()
        healthBar:SetAlpha(hp.barAlpha or 1)
        ApplyBarOrientation(healthBar, hpOri)
        if IsSpecDisabled(hp) then
            EllesmereUI.SetElementVisibility(healthBar, false)
        end
        end
    end

    -- Power bar (primary resource)
    cachedPrimary = GetPrimaryPowerType()
    local pp = p.primary or FALLBACK.primary
    -- Expand height when spec has no class resource and the option is enabled.
    -- Suppress the expand when unlock mode or EUI options panel is open so
    -- the mover/getSize reflects the real stored height, not the expanded one.
    local ppHeight = pp.height or 14
    local ppExpandDelta = 0
    local ppDirSign = 1  -- expand direction: +1 grow up (class resource above), -1 grow down (below)
    local _heightMatched = EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power")
    -- Runtime suppression: regular size while unlock mode or the EUI options
    -- panel is open (mover/getSize must see the true stored height). Never reads
    -- or writes the saved setting -- see _ERB_SuppressExpand in OnInitialize.
    if pp.expandIfNoResource and not _heightMatched
       and not EllesmereUI._erbExpandSuppressed and not EllesmereUI._unlockActive then
        local secRes = GetSecondaryResource()
        if not secRes then
            local sp2 = p.secondary or FALLBACK.secondary
            ppExpandDelta = sp2.pipHeight or 20
            ppHeight = ppHeight + ppExpandDelta
            ppDirSign = ResolveExpandDirSign(pp, sp2)
        end
    end
    -- Clean stale key from old suppress/restore system
    if pp._expandWasOn ~= nil then pp._expandWasOn = nil end
    -- Snap stored width/height to the physical pixel grid so the frame is
    -- always a whole number of physical pixels. Use SnapForES (round to
    -- nearest) rather than PP.Scale (truncate toward zero) so a stored
    -- value like 214.6 rounds to 215 instead of losing 1px to 214. Without
    -- this, a stale stored value (e.g. from a previous ui scale) can land
    -- 1px short of the width-match target, and the user would have to
    -- un-match/re-match to correct it.
    local ppWidthRaw = pp.width or 214
    local _ppEs = (primaryBar and primaryBar:GetEffectiveScale()) or (UIParent and UIParent:GetEffectiveScale()) or 1
    if PP and PP.SnapForES then
        ppWidthRaw = PP.SnapForES(ppWidthRaw, _ppEs)
        ppHeight = PP.SnapForES(ppHeight, _ppEs)
    end
    local ppWidth = ppWidthRaw
    -- Always create the frame when enabled so anchored elements (CDM bars,
    -- cast bar, etc.) have a valid target. If the spec has no primary power
    -- the frame stays at zero alpha but retains its position.
    if not primaryBar then
        primaryBar = CreateStatusBar(mainFrame, "ERB_PrimaryBar", ppWidth, ppHeight,
            pp.borderSize, pp.borderR, pp.borderG, pp.borderB, pp.borderA)
        primaryBar:SetFrameStrata(g.frameStrata or "MEDIUM")
        primaryBar:SetFrameLevel(10)
    end
    if pp.enabled ~= false and cachedPrimary then
        local ppOri = pp.orientation or g.orientation or "HORIZONTAL"
        local primaryAnchorKey = NormalizeAnchorKey(pp.anchorTo)
        local primaryUnlockAnchored = EllesmereUI.IsUnlockAnchored("ERB_Power")
        if primaryUnlockAnchored then
            -- Unlock anchor system owns positioning; only update size
            local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
            primaryBar:SetSize(ow, oh)
        elseif primaryAnchorKey ~= "none" then
            local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
            local offsetX, offsetY = GetAnchorOffsets(pp)
            primaryBar:SetSize(ow, oh)
            if not ApplyBarAnchor(primaryBar, primaryAnchorKey, pp.anchorPosition, offsetX, offsetY, pp.growthDirection, pp.growCentered) then
                ApplyFreeBarPosition(primaryBar, pp, 0, -54, ow, oh)
            end
        elseif pp.unlockPos and pp.unlockPos.point then
            local rp = pp.unlockPos.relPoint or pp.unlockPos.point
            local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
            ApplyBarAnchor(primaryBar, "none")
            primaryBar:SetSize(ow, oh)
            if not EllesmereUI._unlockActive then
                if not EllesmereUI.IsUnlockAnchored("ERB_Power") or not primaryBar:GetLeft() then
                    local sx, sy = SnapXY(pp.unlockPos.x, pp.unlockPos.y, primaryBar, pp.unlockPos)
                    -- Dragged bars store the UNexpanded CENTER (expand is
                    -- suppressed during unlock capture), so SetSize alone would
                    -- grow them symmetrically. Shift the center toward the class
                    -- resource (ppDirSign) so the bar grows that direction.
                    if ppExpandDelta > 0 and pp.unlockPos.point == "CENTER" then
                        sy = sy + ppDirSign * ppExpandDelta * 0.5
                    end
                    primaryBar:ClearAllPoints()
                    primaryBar:SetPoint(pp.unlockPos.point, UIParent, rp, sx, sy)
                end
            end
        else
            -- Clear any mouse-tracking OnUpdate from a previous anchor
            ApplyBarAnchor(primaryBar, "none")
            if EllesmereUI._unlockActive then
                -- During unlock mode, only update size -- position is managed by the mover
                local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
                primaryBar:SetSize(ow, oh)
            else
                local function ApplyPowerBarTransform()
                    local ox = primaryBar["_barAnim_ox"] or pp.offsetX or 0
                    local oy = primaryBar["_barAnim_oy"] or pp.offsetY or -54
                    local w = primaryBar["_barAnim_w"] or ppWidth
                    local h2 = primaryBar["_barAnim_h"] or ppHeight
                    local ow, oh = OrientedSize(w, h2, ppOri)
                    primaryBar:ClearAllPoints()
                    -- Expand toward the class resource: keep the edge facing AWAY
                    -- from the class resource fixed and grow toward it (ppDirSign
                    -- +1 = grow up, -1 = grow down). Derive the shift from the
                    -- ANIMATED height (h2), not the full final delta, so the fixed
                    -- edge stays put for the whole tween (no mid-animation float).
                    local base = ppHeight - ppExpandDelta
                    local extra = (ppExpandDelta > 0) and (ppDirSign * (h2 - base) * 0.5) or 0
                    primaryBar:SetPoint("CENTER", mainFrame, "CENTER", ox, oy + extra)
                    primaryBar:SetSize(ow, oh)
                end
                SmoothBarAnimate(primaryBar, "ox", pp.offsetX or 0, function() ApplyPowerBarTransform() end)
                SmoothBarAnimate(primaryBar, "oy", pp.offsetY or -54, function() ApplyPowerBarTransform() end)
                SmoothBarAnimate(primaryBar, "w", ppWidth, function() ApplyPowerBarTransform() end)
                SmoothBarAnimate(primaryBar, "h", ppHeight, function() ApplyPowerBarTransform() end)
            end
        end
        -- expandIfNoResource grows the power bar toward where the class resource
        -- bar sits (above -> up, below -> down) via ppDirSign / ResolveExpandDirSign.
        -- Implemented for the free + dragged (unlockPos) branches above; the
        -- anchorTo and unlock-anchored branches grow per their own anchor edge.
        primaryBar:ApplyBorder(pp.borderSize, pp.borderR, pp.borderG, pp.borderB, pp.borderA, pp.borderTexture, pp.borderTextureOffset, pp.borderTextureOffsetY, pp.borderTextureShiftX, pp.borderTextureShiftY, "resourcebars", pp.borderSize, pp.borderBehind)

        -- Bar texture (must be applied before colors since SetStatusBarTexture resets vertex color)
        ApplyBarTexture(primaryBar, g.barTexture or "none")

        -- Colors: dark theme > custom colored > power type color.
        -- Gradient is additive: when enabled it fills from the resolved custom/power
        -- base color to the gradient end color. Dark theme ignores gradient.
        local pft = primaryBar:GetStatusBarTexture()
        if pp.darkTheme then
            pft:SetVertexColor(DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, DARK_FILL_A)
            primaryBar._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, DARK_BG_A)
        else
            local fR, fG, fB, fA
            if pp.customColored then
                fR, fG, fB, fA = pp.fillR, pp.fillG, pp.fillB, pp.fillA
            else
                local pc = POWER_COLORS[cachedPrimary]
                if pc then fR, fG, fB, fA = pc[1], pc[2], pc[3], 1
                else fR, fG, fB, fA = 1, 1, 1, 1 end
            end
            if pp.gradientEnabled then
                ApplyBarGradient(pft, pp.gradientDir or "HORIZONTAL",
                    fR, fG, fB, fA,
                    pp.gradientR, pp.gradientG, pp.gradientB, pp.gradientA)
            else
                ApplyBarFlat(pft, fR, fG, fB, fA)
            end
            primaryBar._bg:SetColorTexture(pp.bgR, pp.bgG, pp.bgB, pp.bgA)
        end

        -- Text positioning
        primaryBar._text:ClearAllPoints()
        primaryBar._text:SetPoint("CENTER", primaryBar, "CENTER", pp.textXOffset, pp.textYOffset)
        SetRBFont(primaryBar._text, GetRBFont(), pp.textSize)
        -- Text color: power-type color when textCustomColored == false, else custom (default custom)
        if pp.textCustomColored == false then
            local tpc = POWER_COLORS[cachedPrimary]
            if tpc then
                primaryBar._text:SetTextColor(tpc[1], tpc[2], tpc[3], 1)
            else
                primaryBar._text:SetTextColor(1, 1, 1, 1)
            end
        else
            primaryBar._text:SetTextColor(pp.textFillR or 1, pp.textFillG or 1, pp.textFillB or 1, pp.textFillA or 1)
        end
        primaryBar:Show()
        local hidePower = p.secondary and p.secondary.hidePowerIfResource and cachedSecondary
        if hidePower then
            EllesmereUI.SetElementVisibility(primaryBar, false)
        else
            primaryBar:SetAlpha(pp.barAlpha or 1)
        end
        ApplyBarOrientation(primaryBar, ppOri)
        if IsSpecDisabled(pp) then
            EllesmereUI.SetElementVisibility(primaryBar, false)
        end
    elseif primaryBar then
        -- Enabled but no resource for this spec: keep the frame positioned
        -- at zero alpha so anchored elements (CDM bars, etc.) have a target.
        local ppOri = pp.orientation or g.orientation or "HORIZONTAL"
        local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
        primaryBar:SetSize(ow, oh)
        primaryBar:Show()
        if not EllesmereUI.IsUnlockAnchored("ERB_Power") then
            if pp.unlockPos and pp.unlockPos.point then
                local rp = pp.unlockPos.relPoint or pp.unlockPos.point
                local sx, sy = SnapXY(pp.unlockPos.x, pp.unlockPos.y, primaryBar, pp.unlockPos)
                primaryBar:ClearAllPoints()
                primaryBar:SetPoint(pp.unlockPos.point, UIParent, rp, sx, sy)
            elseif not primaryBar:GetLeft() then
                primaryBar:ClearAllPoints()
                primaryBar:SetPoint("CENTER", mainFrame, "CENTER", pp.offsetX or 0, pp.offsetY or -54)
            end
        end
        EllesmereUI.SetElementVisibility(primaryBar, false)
    end


    -- Class resource (secondary: pips / runes)
    cachedSecondary = GetSecondaryResource()
    local sp = p.secondary or FALLBACK.secondary
    -- Always create the frame when enabled so anchored elements have a target
    if sp.enabled ~= false and not secondaryFrame then
        secondaryFrame = CreateFrame("Frame", "ERB_SecondaryFrame", mainFrame)
        secondaryFrame:SetFrameStrata(g.frameStrata or "MEDIUM")
        secondaryFrame:SetFrameLevel(10)
    end
    if sp.enabled ~= false and cachedSecondary then

        local maxPts = cachedSecondary.max or 5
        if cachedSecondary.type == "custom" and EllesmereUI then
            local powerType = cachedSecondary.power
            if powerType == "SOUL_FRAGMENTS" and EllesmereUI.GetSoulFragments then
                local _, realMax = EllesmereUI.GetSoulFragments()
                if realMax and realMax > 0 then maxPts = realMax end
            elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI.GetMaelstromWeapon then
                local _, realMax = EllesmereUI.GetMaelstromWeapon()
                if realMax and realMax > 0 then maxPts = realMax end
                -- Enhance 5-bar mode: cap visual pips to 5, overflow handled at render time
                if sp.enhanceFiveBar and maxPts > 5 then
                    cachedSecondary._realMax = maxPts
                    maxPts = 5
                else
                    cachedSecondary._realMax = nil
                end
            elseif powerType == "TIP_OF_THE_SPEAR" and EllesmereUI.GetTipOfTheSpear then
                local _, realMax = EllesmereUI.GetTipOfTheSpear()
                if realMax and realMax > 0 then maxPts = realMax end
            elseif powerType == "WHIRLWIND_STACKS" and EllesmereUI.GetWhirlwindStacks then
                local _, realMax = EllesmereUI.GetWhirlwindStacks()
                if realMax and realMax > 0 then maxPts = realMax end
            elseif powerType == "ICICLES" then
                maxPts = 5
            end
        end
        -- Single source of truth for effective scale: capture once, pass
        -- to every snap and to CalcPipGeometry so frame outer dimensions
        -- and pip layout cannot disagree by 1 physical pixel due to
        -- effective-scale changes mid-build (parent reparent, etc.).
        local _crEs = (secondaryFrame and secondaryFrame:GetEffectiveScale())
                      or (UIParent and UIParent:GetEffectiveScale()) or 1
        local pipH = PP.SnapForES(sp.pipHeight or 20, _crEs)
        local pipSp = sp.pipSpacing or 1
        local pipOri = sp.pipOrientation or "HORIZONTAL"
        local isVertical = (pipOri ~= "HORIZONTAL")
        local isReversed = (pipOri == "VERTICAL_UP")
        local totalW

        local isBarType = cachedSecondary.type == "bar"
        totalW = sp.pipWidth or 214

        -- Frame dimensions: snapped ONCE to the physical pixel grid using
        -- the captured _crEs. Pip layout below uses the SAME _crEs and the
        -- SAME totalW, so its slot positions align with the frame edges
        -- exactly. NO post-layout frame resize is needed (and in fact one
        -- would re-introduce the 1px shift this design eliminates).
        local widthSnapped  = PP.SnapForES(totalW, _crEs)
        local heightSnapped = PP.SnapForES(pipH,   _crEs)
        local frameW = isVertical and heightSnapped or widthSnapped
        local frameH = isVertical and widthSnapped  or heightSnapped
        local secondaryAnchorKey = NormalizeAnchorKey(sp.anchorTo)
        local secondaryUnlockAnchored = EllesmereUI.IsUnlockAnchored("ERB_ClassResource")
        if secondaryUnlockAnchored then
            -- Unlock anchor system owns positioning; only update size
            secondaryFrame:SetSize(frameW, frameH)
        elseif secondaryAnchorKey ~= "none" then
            local offsetX, offsetY = GetAnchorOffsets(sp)
            secondaryFrame:SetSize(frameW, frameH)
            if not ApplyBarAnchor(secondaryFrame, secondaryAnchorKey, sp.anchorPosition, offsetX, offsetY, sp.growthDirection, sp.growCentered) then
                ApplyFreeBarPosition(secondaryFrame, sp, 0, -38, frameW, frameH)
            end
        elseif sp.unlockPos and sp.unlockPos.point then
            ApplyBarAnchor(secondaryFrame, "none")
            secondaryFrame:SetSize(frameW, frameH)
            -- Position is applied by ApplySavedPositions (the single
            -- authority for unlock positions). Applying it here too
            -- causes a double-snap: BuildBars and applyPos capture
            -- effective scale at different times, and SnapCenterForDim
            -- can produce coordinates that differ by 1px. Only fall
            -- back to inline positioning when the frame has no bounds
            -- at all (first-ever build before ApplySavedPositions has
            -- run).
            if not secondaryFrame:GetLeft() then
                local sx, sy = SnapXY(sp.unlockPos.x, sp.unlockPos.y, secondaryFrame, sp.unlockPos)
                secondaryFrame:ClearAllPoints()
                secondaryFrame:SetPoint(sp.unlockPos.point, UIParent, sp.unlockPos.relPoint or sp.unlockPos.point, sx, sy)
            end
        else
            ApplyBarAnchor(secondaryFrame, "none")
            if EllesmereUI._unlockActive then
                -- During unlock mode, only update size -- position is managed by the mover
                secondaryFrame:SetSize(frameW, frameH)
            else
                local function ApplySecondaryBarTransform()
                    local ox = secondaryFrame["_barAnim_ox"] or sp.offsetX or 0
                    local oy = secondaryFrame["_barAnim_oy"] or sp.offsetY or -38
                    local w  = secondaryFrame["_barAnim_w"] or frameW
                    local h2 = secondaryFrame["_barAnim_h"] or frameH
                    secondaryFrame:ClearAllPoints()
                    secondaryFrame:SetPoint("CENTER", mainFrame, "CENTER", ox, oy)
                    secondaryFrame:SetSize(w, h2)
                end
                SmoothBarAnimate(secondaryFrame, "ox", sp.offsetX or 0, function() ApplySecondaryBarTransform() end)
                SmoothBarAnimate(secondaryFrame, "oy", sp.offsetY or -38, function() ApplySecondaryBarTransform() end)
                SmoothBarAnimate(secondaryFrame, "w", frameW, function() ApplySecondaryBarTransform() end)
                SmoothBarAnimate(secondaryFrame, "h", frameH, function() ApplySecondaryBarTransform() end)
            end
        end

        -- Create/reuse pips or bar
        if isBarType then
            -- Bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom)
            -- Hide all pips, runes, and pip tick marks
            for i = 1, #pips do if pips[i] then pips[i]:Hide() end end
            for i = 1, #runeFrames do if runeFrames[i] then runeFrames[i]:Hide() end end
            for i = 1, #secondaryPipTicks do secondaryPipTicks[i]:Hide() end

            if not secondaryBar then
                secondaryBar = CreateStatusBar(secondaryFrame, "ERB_SecondaryBar", totalW, pipH,
                    0, 0, 0, 0, 0)
                secondaryBar:SetMinMaxValues(0, maxPts)
                secondaryBar:SetValue(0)
            else
                -- For existing bars, only update min/max if needed (don't reset value to 0)
                local actualMax = maxPts
                if cachedSecondary.power == "BREWMASTER_STAGGER" then
                    actualMax = UnitHealthMax("player") or 1
                    if actualMax <= 0 then actualMax = 1 end
                elseif cachedSecondary.power == "IGNOREPAIN_BAR" then
                    local hm = UnitHealthMax("player")
                    if hm and not (issecretvalue and issecretvalue(hm)) and hm > 0 then
                        actualMax = hm * IP.CAP
                    end
                end
                if secondaryBar._lastMaxC ~= actualMax then
                    secondaryBar._lastMaxC = actualMax
                    secondaryBar:SetMinMaxValues(0, actualMax)
                end
            end
            secondaryBar:SetSize(totalW, pipH)
            secondaryBar:ClearAllPoints()
            secondaryBar:SetAllPoints(secondaryFrame)

            -- Bar texture and orientation must be applied before colors since
            -- SetStatusBarTexture and SetRotatesTexture both reset vertex color.
            -- Use the Class Resource's own pipOrientation setting (same key the
            -- dropdown writes to), not p.general.orientation which was unrelated
            -- and caused vertical fill to render horizontally.
            ApplyBarTexture(secondaryBar, g.barTexture or "none")
            ApplyBarOrientation(secondaryBar, pipOri)

            -- Colors
            local pc = POWER_COLORS[cachedSecondary.power]
            if sp.darkTheme then
                secondaryBar:GetStatusBarTexture():SetVertexColor(DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, DARK_FILL_A)
                secondaryBar._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, DARK_BG_A)
            elseif cachedSecondary.power == "BREWMASTER_STAGGER" then
                -- Brewmaster Stagger: always use threshold colors (green/yellow/red), start with green
                secondaryBar:GetStatusBarTexture():SetVertexColor(0.2, 0.8, 0.2, 1)
                secondaryBar._lastStaggerR, secondaryBar._lastStaggerG, secondaryBar._lastStaggerB = 0.2, 0.8, 0.2
                secondaryBar._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            elseif sp.classColored ~= false then
                -- Power types in secondary slot use power color; class resources use class color
                local pc2 = POWER_COLORS[cachedSecondary.power]
                if pc2 then
                    secondaryBar:GetStatusBarTexture():SetVertexColor(pc2[1], pc2[2], pc2[3], sp.fillA or 1)
                else
                    local cc = CLASS_COLORS[cachedClass]
                    if cc then
                        secondaryBar:GetStatusBarTexture():SetVertexColor(cc[1], cc[2], cc[3], sp.fillA or 1)
                    end
                end
                secondaryBar._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            else
                -- classColored explicitly false -- use custom fill color
                secondaryBar:GetStatusBarTexture():SetVertexColor(sp.fillR, sp.fillG, sp.fillB, sp.fillA)
                secondaryBar._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            end
            secondaryBar:ApplyBorder(0, 0, 0, 0, 0)
            if cachedSecondary.power == "IRONFUR_BAR" then
                -- Guardian Ironfur: no static threshold hash lines; the moving
                -- per-cast hash lines are drawn live in UpdateIronfurBar.
                for i = 1, #secondaryBarTicks do secondaryBarTicks[i]:Hide() end
                EnsureIronfurOverlay(secondaryBar)
            else
                -- Resolve hash lines from thresholdSpecs entry (falls back to legacy tickValues)
                local _buildTsEntry = ResolveThresholdSpecEntry(sp)
                local _buildTickStr = (_buildTsEntry and _buildTsEntry.hashValues ~= "") and _buildTsEntry.hashValues or sp.tickValues
                local _buildHW = _buildTsEntry and _buildTsEntry.hashWidth or 1
                local _buildHR = _buildTsEntry and _buildTsEntry.hashColorR or 1
                local _buildHG = _buildTsEntry and _buildTsEntry.hashColorG or 1
                local _buildHB = _buildTsEntry and _buildTsEntry.hashColorB or 1
                local _buildHA = _buildTsEntry and _buildTsEntry.hashColorA or 0.7
                ApplyResourceBarTicks(secondaryBar, maxPts, _buildTickStr, secondaryBarTicks, _buildHW, _buildHR, _buildHG, _buildHB, _buildHA)
            end
            secondaryBar:Show()
        elseif cachedSecondary.type == "runes" then
            local numPips = 6
            -- Frame size already set above with the SAME _crEs. Slot
            -- positions are computed within that fixed frame; no resize.
            local slots = CalcPipGeometry(totalW, numPips, pipSp, secondaryFrame, _crEs)
            for i = 1, 6 do
                if not runeFrames[i] then
                    runeFrames[i] = CreatePip(secondaryFrame, 20, pipH, i,
                        0, 0, 0, 0, 0)
                    local cdText = runeFrames[i]:CreateFontString(nil, "OVERLAY")
                    runeFrames[i]._cdText = cdText
                end
                -- Re-apply font size, color, and offsets every rebuild so textSize,
                -- textXOffset, and textYOffset changes take effect live
                local cdText = runeFrames[i]._cdText
                if cdText then
                    cdText:SetTextColor(sp.textR or 1, sp.textG or 1, sp.textB or 1, 0.8)
                    SetRBFont(cdText, GetRBFont(), sp.textSize or 9)
                    cdText:ClearAllPoints()
                    cdText:SetPoint("CENTER", runeFrames[i], "CENTER",
                        sp.textXOffset or 0, sp.textYOffset or 0)
                end
                local x0 = slots[i].x0
                local x1 = slots[i].x1
                local rf = runeFrames[i]
                local function ApplyRunePos()
                    local ap0 = rf["_barAnim_x0"] or x0
                    local aw  = rf["_barAnim_x1"] or (x1 - x0)
                    local ah  = rf["_barAnim_ph"] or pipH
                    rf:ClearAllPoints()
                    if isVertical then
                        if isReversed then
                            rf:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, ap0)
                        else
                            rf:SetPoint("TOP", secondaryFrame, "TOP", 0, -ap0)
                        end
                        rf:SetHeight(aw)
                        rf:SetWidth(ah)
                    else
                        rf:SetPoint("LEFT", secondaryFrame, "LEFT", ap0, 0)
                        rf:SetWidth(aw)
                        rf:SetHeight(ah)
                    end
                end
                rf["_barAnim_x0"] = x0
                rf["_barAnim_x1"] = x1 - x0
                rf["_barAnim_ph"] = pipH
                ApplyRunePos()
                runeFrames[i]:ApplyBorder(0, 0, 0, 0, 0)
                runeFrames[i]:ApplyTexture(g.barTexture or "none")
                if sp.darkTheme then
                    runeFrames[i]._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
                elseif sp.classColored then
                    runeFrames[i]._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                else
                    runeFrames[i]._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                end
                runeFrames[i]:Show()
            end
            for i = 7, #pips do if pips[i] then pips[i]:Hide() end end
            if secondaryBar then secondaryBar:Hide() end
            for i = 1, #secondaryBarTicks do secondaryBarTicks[i]:Hide() end
            -- Hash lines for rune-type resources (drawn on secondaryFrame)
            local _runeTsEntry = ResolveThresholdSpecEntry(sp)
            local _runeTickStr = (_runeTsEntry and _runeTsEntry.hashValues ~= "") and _runeTsEntry.hashValues or nil
            local _runeHW = _runeTsEntry and _runeTsEntry.hashWidth or 1
            local _runeHR = _runeTsEntry and _runeTsEntry.hashColorR or 1
            local _runeHG = _runeTsEntry and _runeTsEntry.hashColorG or 1
            local _runeHB = _runeTsEntry and _runeTsEntry.hashColorB or 1
            local _runeHA = _runeTsEntry and _runeTsEntry.hashColorA or 0.7
            ApplyResourceBarTicks(secondaryFrame, 6, _runeTickStr, secondaryPipTicks, _runeHW, _runeHR, _runeHG, _runeHB, _runeHA)
        else
            -- Frame size already set above with the SAME _crEs. Slot
            -- positions are computed within that fixed frame; no resize.
            local slots = CalcPipGeometry(totalW, maxPts, pipSp, secondaryFrame, _crEs)
            for i = 1, maxPts do
                if not pips[i] then
                    pips[i] = CreatePip(secondaryFrame, 20, pipH, i,
                        0, 0, 0, 0, 0)
                end
                local x0 = slots[i].x0
                local x1 = slots[i].x1
                local pip = pips[i]
                local function ApplyPipPos()
                    local ap0 = pip["_barAnim_x0"] or x0
                    local aw  = pip["_barAnim_x1"] or (x1 - x0)
                    local ah  = pip["_barAnim_ph"] or pipH
                    pip:ClearAllPoints()
                    if isVertical then
                        if isReversed then
                            pip:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, ap0)
                        else
                            pip:SetPoint("TOP", secondaryFrame, "TOP", 0, -ap0)
                        end
                        pip:SetHeight(aw)
                        pip:SetWidth(ah)
                    else
                        pip:SetPoint("LEFT", secondaryFrame, "LEFT", ap0, 0)
                        pip:SetWidth(aw)
                        pip:SetHeight(ah)
                    end
                end
                pip["_barAnim_x0"] = x0
                pip["_barAnim_x1"] = x1 - x0
                pip["_barAnim_ph"] = pipH
                ApplyPipPos()
                pips[i]:ApplyBorder(0, 0, 0, 0, 0)
                pips[i]:ApplyTexture(g.barTexture or "none")
                if sp.darkTheme then
                    pips[i]._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
                elseif sp.classColored then
                    pips[i]._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                else
                    pips[i]._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                end
                pips[i]:Show()
            end
            for i = maxPts + 1, #pips do if pips[i] then pips[i]:Hide() end end
            for i = 1, #runeFrames do if runeFrames[i] then runeFrames[i]:Hide() end end
            if secondaryBar then secondaryBar:Hide() end
            for i = 1, #secondaryBarTicks do secondaryBarTicks[i]:Hide() end
            -- Hash lines for pip-type resources (drawn on secondaryFrame)
            local _pipTsEntry = ResolveThresholdSpecEntry(sp)
            local _pipTickStr = (_pipTsEntry and _pipTsEntry.hashValues ~= "") and _pipTsEntry.hashValues or nil
            local _pipHW = _pipTsEntry and _pipTsEntry.hashWidth or 1
            local _pipHR = _pipTsEntry and _pipTsEntry.hashColorR or 1
            local _pipHG = _pipTsEntry and _pipTsEntry.hashColorG or 1
            local _pipHB = _pipTsEntry and _pipTsEntry.hashColorB or 1
            local _pipHA = _pipTsEntry and _pipTsEntry.hashColorA or 0.7
            ApplyResourceBarTicks(secondaryFrame, maxPts, _pipTickStr, secondaryPipTicks, _pipHW, _pipHR, _pipHG, _pipHB, _pipHA)
        end

        -- Full-bar border (wraps the entire class resource bar)
        if not secondaryFrame._barBorder then
            secondaryFrame._barBorder = MakePixelBorder(secondaryFrame,
                sp.borderR, sp.borderG, sp.borderB, sp.borderA, sp.borderSize, sp.borderTexture, sp.borderTextureOffset, sp.borderTextureOffsetY)
        end
        -- "Show Behind": set level before ApplyStyle so the textured backdrop
        -- inherits it. +5 in front (above bar-type secondaries), level-1 behind.
        if secondaryFrame._barBorder._frame then
            local pl = secondaryFrame:GetFrameLevel()
            secondaryFrame._barBorder._frame:SetFrameLevel(sp.borderBehind and math.max(0, pl - 1) or (pl + 5))
        end
        secondaryFrame._barBorder:ApplyStyle(sp.borderSize, sp.borderR, sp.borderG, sp.borderB, sp.borderA,
            sp.borderTexture, sp.borderTextureOffset, sp.borderTextureOffsetY,
            sp.borderTextureShiftX, sp.borderTextureShiftY, "resourcebars", sp.borderSize)

        -- Full-bar background (behind all pips) -- this is what shows through
        -- the pip spacing/gaps. In dark theme the inactive pips are opaque gray
        -- (DARK_BG, alpha 1), so a semi-transparent gap reads as "no background"
        -- next to them. Force the gap to an opaque black so it stays a solid
        -- dark separator, cohesive with the opaque pips.
        if not secondaryFrame._barBg then
            secondaryFrame._barBg = secondaryFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
        end
        secondaryFrame._barBg:ClearAllPoints()
        secondaryFrame._barBg:SetAllPoints(secondaryFrame)
        if sp.darkTheme then
            secondaryFrame._barBg:SetColorTexture(0, 0, 0, 1)
        else
            secondaryFrame._barBg:SetColorTexture(sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5)
        end

        -- Count text
        if sp.showText then
            if not secondaryFrame._countText then
                -- Parent to a high-level overlay so text renders above pip fills and borders
                if not secondaryFrame._countTextOverlay then
                    secondaryFrame._countTextOverlay = CreateFrame("Frame", nil, secondaryFrame)
                    secondaryFrame._countTextOverlay:SetAllPoints(secondaryFrame)
                end
                secondaryFrame._countTextOverlay:SetFrameLevel(25)
                secondaryFrame._countText = secondaryFrame._countTextOverlay:CreateFontString(nil, "OVERLAY")
            end
            secondaryFrame._countText:SetTextColor(sp.textR or 1, sp.textG or 1, sp.textB or 1, 0.9)
            -- Keep overlay level current in case frame levels shifted
            if secondaryFrame._countTextOverlay then
                secondaryFrame._countTextOverlay:SetFrameLevel(25)
            end
            secondaryFrame._countText:ClearAllPoints()
            secondaryFrame._countText:SetParent(secondaryFrame._countTextOverlay)
            secondaryFrame._countText:SetPoint("CENTER", secondaryFrame, "CENTER", sp.textXOffset, sp.textYOffset)
            SetRBFont(secondaryFrame._countText, GetRBFont(), sp.textSize)
            secondaryFrame._countText:Show()
        elseif secondaryFrame._countText then
            secondaryFrame._countText:Hide()
        end

        secondaryFrame:Show()
        secondaryFrame:SetAlpha(sp.barAlpha or 1)
    elseif secondaryFrame then
        -- Enabled but no resource for this spec: keep the frame positioned
        -- at zero alpha so anchored elements have a valid target.
        local pipH = sp.pipHeight or 20
        local pipW = sp.pipWidth or ((pp.width or 214))
        secondaryFrame:SetSize(pipW, pipH)
        secondaryFrame:Show()
        if not EllesmereUI.IsUnlockAnchored("ERB_ClassResource") then
            if sp.unlockPos and sp.unlockPos.point then
                local rp = sp.unlockPos.relPoint or sp.unlockPos.point
                local sx, sy = SnapXY(sp.unlockPos.x, sp.unlockPos.y, secondaryFrame, sp.unlockPos)
                secondaryFrame:ClearAllPoints()
                secondaryFrame:SetPoint(sp.unlockPos.point, UIParent, rp, sx, sy)
            elseif not secondaryFrame:GetLeft() then
                secondaryFrame:ClearAllPoints()
                secondaryFrame:SetPoint("CENTER", mainFrame, "CENTER", sp.offsetX or 0, sp.offsetY or -74)
            end
        end
        EllesmereUI.SetElementVisibility(secondaryFrame, false)
    end

    ReapplyInternalBarAnchors()

    -- "Shift Elements if No Resource": re-cascade the class resource bar so any
    -- elements anchored to it pick up (or drop) the temporary shift. The
    -- resource-present/absent transition keeps the frame at the same size, so
    -- neither OnSizeChanged nor the SetPoint move-hook fires automatically -- we
    -- must trigger the cascade explicitly. Gated so a None-forever profile
    -- schedules ZERO anchor work, and never fired during unlock mode (unlock
    -- entry/exit manage the shift separately).
    do
        local sp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
        local active = sp ~= nil and (sp.shiftElementsIfNoResource == "Up"
            or sp.shiftElementsIfNoResource == "Down")
        if (active or ERB._shiftWasActive)
           and not EllesmereUI._unlockActive
           and EllesmereUI.PropagateAnchorChain then
            ERB._shiftWasActive = active
            EllesmereUI.PropagateAnchorChain("ERB_ClassResource")
        end
    end
end


-------------------------------------------------------------------------------
--  Update functions (event-driven)
-------------------------------------------------------------------------------
local function UpdateHealthBar()
    if not healthBar or not healthBar:IsShown() then return end
    local hp = ERB.db.profile.health

    local cur = UnitHealth("player")
    local mx = UnitHealthMax("player")
    if not cur or not mx or mx <= 0 then return end

    healthBar:SetMinMaxValues(0, mx)

    local curTainted = issecretvalue and issecretvalue(cur)
    -- Percent for text display. UnitHealthPercent returns a value that may be
    -- secret, but string.format handles secret values natively (C function).
    -- We store it as-is and only pass it to format/SetFormattedText, never arithmetic.
    local pctRaw
    if UnitHealthPercent then
        pctRaw = UnitHealthPercent("player", true, CurveConstants and CurveConstants.ScaleTo100)
    elseif not curTainted and mx > 0 then
        pctRaw = cur / mx * 100
    else
        pctRaw = 0
    end

    -- Color: threshold via ColorCurve, matching the power bar implementation.
    -- Resolve per-spec threshold entry for health bar
    local _hpTsEntry = ResolveThresholdSpecEntry(hp)
    local _hpTsEnabled = _hpTsEntry and (_hpTsEntry.thresholdEnabled ~= false) or false
    if not _hpTsEnabled then _hpTsEntry = nil end
    local ft = healthBar:GetStatusBarTexture()
    if _hpTsEntry and ft and UnitHealthPercent then
        local baseR, baseG, baseB
        if hp.darkTheme then
            baseR, baseG, baseB = DARK_FILL_R, DARK_FILL_G, DARK_FILL_B
        elseif hp.customColored then
            baseR, baseG, baseB = hp.fillR, hp.fillG, hp.fillB
        else
            local cc = CLASS_COLORS[cachedClass]
            if cc then baseR, baseG, baseB = cc[1], cc[2], cc[3] else baseR, baseG, baseB = 0.15, 0.75, 0.30 end
        end
        local tR = _hpTsEntry.thresholdR or hp.thresholdR or 1
        local tG = _hpTsEntry.thresholdG or hp.thresholdG or 0.2
        local tB = _hpTsEntry.thresholdB or hp.thresholdB or 0.2
        local curve = GetBarThresholdCurve(baseR, baseG, baseB, tR, tG, tB, _hpTsEntry.thresholdPct or hp.thresholdPct or 30)
        if curve then
            local ok, colorResult = pcall(UnitHealthPercent, "player", false, curve)
            if ok and colorResult and colorResult.GetRGBA then
                ft:SetVertexColor(colorResult:GetRGBA())
            end
        end
    elseif ft and not hp.darkTheme and not hp.customColored then
        local r, g, b
        local cc = CLASS_COLORS[cachedClass]
        if cc then r, g, b = cc[1], cc[2], cc[3] else r, g, b = 0.15, 0.75, 0.30 end
        if hp.gradientEnabled then
            ApplyBarGradient(ft, hp.gradientDir or "HORIZONTAL",
                r, g, b, 1,
                hp.gradientR, hp.gradientG, hp.gradientB, hp.gradientA)
        else
            ApplyBarFlat(ft, r, g, b, 1)
        end
    end

    -- Smooth animation
    if not curTainted then
        healthBar._smoothTarget = cur
    else
        healthBar:SetValue(cur)
    end

    -- Text
    if hp.textFormat ~= "none" then
        local fmt = hp.textFormat
        local pctStr = format("%d", pctRaw)
        local curStr = AbbreviateNumbers(cur)
        local txt
        if fmt == "both" then
            txt = curStr .. " | " .. pctStr .. "%"
        elseif fmt == "curhpshort" then
            txt = curStr
        elseif fmt == "perhp" then
            txt = pctStr .. "%"
        elseif fmt == "perhpnosign" then
            txt = pctStr
        elseif fmt == "perhpnum" then
            txt = pctStr .. "% | " .. curStr
        else
            txt = pctStr .. "%"
        end
        healthBar._text:SetText(txt)
        healthBar._text:Show()
    else
        healthBar._text:Hide()
    end
end

local function UpdatePrimaryBar()
    if not primaryBar or not primaryBar:IsShown() then return end
    local pp = ERB.db.profile.primary

    cachedPrimary = GetPrimaryPowerType()
    if not cachedPrimary then return end

    -- Ebon Might: aura-based countdown, not a standard power type.
    -- OnUpdate ticker handles smooth frame-by-frame updates; this path
    -- runs on UNIT_AURA to pick up buff gain/loss/refresh.
    if cachedPrimary == "EBON_MIGHT" then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(EBON_MIGHT_SPELL_ID)
        _ebonMightExpiry = (aura and aura.expirationTime) or 0
        local remaining = (_ebonMightExpiry > 0) and max(0, _ebonMightExpiry - GetTime()) or 0
        primaryBar:SetMinMaxValues(0, EBON_MIGHT_DURATION)
        primaryBar:SetValue(remaining)
        primaryBar._smoothTarget = remaining
        primaryBar._smoothCurrent = remaining
        -- Color: dark > custom > power color (same priority as standard)
        local ft = primaryBar:GetStatusBarTexture()
        if not pp.darkTheme and not pp.customColored then
            local pc = POWER_COLORS["EBON_MIGHT"]
            local r, g, b = 1, 1, 1
            if pc then r, g, b = pc[1], pc[2], pc[3] end
            if pp.gradientEnabled then
                ApplyBarGradient(ft, pp.gradientDir or "HORIZONTAL", r, g, b, 1,
                    pp.gradientR, pp.gradientG, pp.gradientB, pp.gradientA)
            else
                ApplyBarFlat(ft, r, g, b, 1)
            end
        end
        -- Text
        if pp.textFormat and pp.textFormat ~= "none" then
            local fmt = pp.textFormat
            local percentSuffix = (pp.showPercent == false) and "" or "%"
            local pct = format("%d", remaining / EBON_MIGHT_DURATION * 100)
            local timeText = remaining > 0 and format("%.1f", remaining) or "0"
            local txt
            if fmt == "perpp" then txt = pct .. percentSuffix
            elseif fmt == "both" then txt = timeText .. " | " .. pct .. percentSuffix
            else txt = timeText end
            primaryBar._text:SetText(txt)
            primaryBar._text:Show()
        else
            primaryBar._text:Hide()
        end
        return
    end

    local cur = UnitPower("player", cachedPrimary)
    local mx = UnitPowerMax("player", cachedPrimary)
    if not mx or mx <= 0 then return end

    primaryBar:SetMinMaxValues(0, mx)

    local pctRaw = UnitPowerPercent and UnitPowerPercent("player", cachedPrimary, true, CurveConstants and CurveConstants.ScaleTo100) or 0
    local pctTainted = issecretvalue and issecretvalue(pctRaw)
    local pct01 = (not pctTainted) and (pctRaw / 100) or 1

    -- Color: threshold via ColorCurve (secret-safe) for non-mana specs;
    -- Resolve per-spec threshold entry for power bar
    local _ppTsEntry = ResolveThresholdSpecEntry(pp)
    local _ppTsEnabled = _ppTsEntry and (_ppTsEntry.thresholdEnabled ~= false) or false
    if not _ppTsEnabled then _ppTsEntry = nil end
    local ft = primaryBar:GetStatusBarTexture()
    if _ppTsEntry and ft and UnitPowerPercent then
        local baseR, baseG, baseB
        if pp.darkTheme then
            baseR, baseG, baseB = DARK_FILL_R, DARK_FILL_G, DARK_FILL_B
        elseif pp.customColored then
            baseR, baseG, baseB = pp.fillR, pp.fillG, pp.fillB
        else
            local pc = POWER_COLORS[cachedPrimary]
            if pc then baseR, baseG, baseB = pc[1], pc[2], pc[3] else baseR, baseG, baseB = 1, 1, 1 end
        end
        local tR = _ppTsEntry.thresholdR or pp.thresholdR or 1
        local tG = _ppTsEntry.thresholdG or pp.thresholdG or 0.2
        local tB = _ppTsEntry.thresholdB or pp.thresholdB or 0.2
        local tPct = _ppTsEntry.thresholdPct or pp.thresholdPct or 30
        local _ppPartial = _ppTsEntry.thresholdPartialOnly
        if _ppPartial == nil then _ppPartial = pp.thresholdPartialOnly end
        local curve
        -- Default for a power resource: fill color BELOW the threshold, threshold
        -- color AT/ABOVE it -- matching the segmented-resource path (Holy Power,
        -- combo points, runes), where reaching the threshold count turns the
        -- resource the threshold color. The "Reverse Threshold Fill Color" toggle
        -- (thresholdPartialOnly) flips it so the threshold color shows BELOW the
        -- threshold instead.
        if _ppPartial then
            curve = GetBarThresholdCurve(baseR, baseG, baseB, tR, tG, tB, tPct)
        else
            curve = GetBarThresholdCurve(tR, tG, tB, baseR, baseG, baseB, tPct)
        end
        if curve then
            local ok, colorResult = pcall(UnitPowerPercent, "player", cachedPrimary, false, curve)
            if ok and colorResult and colorResult.GetRGBA then
                ft:SetVertexColor(colorResult:GetRGBA())
            end
        end
    elseif not pp.darkTheme and not pp.customColored then
        local r, g, b
        local pc = POWER_COLORS[cachedPrimary]
        if pc then r, g, b = pc[1], pc[2], pc[3] else r, g, b = 1, 1, 1 end
        if pp.gradientEnabled then
            ApplyBarGradient(ft, pp.gradientDir or "HORIZONTAL",
                r, g, b, 1,
                pp.gradientR, pp.gradientG, pp.gradientB, pp.gradientA)
        else
            ApplyBarFlat(ft, r, g, b, 1)
        end
    end

    -- Smooth animation
    local tainted = issecretvalue and issecretvalue(cur)
    if not tainted then
        primaryBar._smoothTarget = cur
    else
        primaryBar:SetValue(cur)
    end

    -- Text
    if pp.textFormat ~= "none" then
        local fmt = pp.textFormat
        local percentSuffix = (pp.showPercent == false) and "" or "%"
        local percentText = format("%d", pctRaw) .. percentSuffix
        local txt
        if fmt == "smart" then
            local isPercent = EllesmereUI.IsSmartPowerPercent and EllesmereUI.IsSmartPowerPercent()
            txt = isPercent and percentText or AbbreviateNumbers(cur)
        elseif fmt == "both" then
            txt = AbbreviateNumbers(cur) .. " | " .. percentText
        elseif fmt == "curpp" then
            txt = AbbreviateNumbers(cur)
        elseif fmt == "perpp" then
            txt = percentText
        else
            txt = AbbreviateNumbers(cur)
        end
        primaryBar._text:SetText(txt)
        primaryBar._text:Show()
    else
        primaryBar._text:Hide()
    end
end

-- Pre-allocated rune sorting buffers to avoid per-tick table creation.
-- Uses parallel arrays instead of tables-of-tables for zero GC pressure.
local _runeOrder = {}       -- [slot] = rune index (1-6)
local _runeRemaining = {}   -- [rune index] = remaining time
local _runeStart = {}       -- [rune index] = cooldown start
local _runeDuration = {}    -- [rune index] = cooldown duration
local _runeReady = {}       -- [rune index] = true/false

-- Evoker Essence recharge state (timer-based, UnitPower partial doesn't work for Essence)
local _essenceNextTick = nil   -- GetTime() when the next pip will be ready
local _essenceLastCount = nil  -- last known whole-pip count
local _essenceTickDur = 0      -- seconds per pip recharge

-- Cast handler for the Prot Ignore Pain bar's moving hash line: each cast
-- refreshes the buff, so the line resets to the right edge and slides left.
IP.HandleCast = function(spellID)
    if spellID ~= IP.SPELL then return end
    if not (cachedSecondary and cachedSecondary.power == "IGNOREPAIN_BAR") then return end
    IP.hashEndTime = GetTime() + IP.DURATION
end

-- Cast handler for the Guardian Ironfur bar. Only tracks while the Ironfur
-- bar is the active class resource so the tick list can't grow unbounded.
local function HandleIronfurCast(spellID)
    if not (cachedSecondary and cachedSecondary.power == "IRONFUR_BAR") then return end
    local now = GetTime()
    if spellID == IRONFUR_SPELL then
        ironfurBaseDur = IronfurBaseDuration()
        local hasGoE = ironfurGoEUntil > 0 and now < ironfurGoEUntil
            and C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(GUARDIAN_OF_ELUNE)
        local dur = ironfurBaseDur + (hasGoE and IRONFUR_GOE_BONUS or 0)
        ironfurTicks[#ironfurTicks + 1] = { endTime = now + dur, duration = dur }
        if hasGoE then ironfurGoEUntil = 0 end
    elseif spellID == MANGLE_SPELL then
        if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(GUARDIAN_OF_ELUNE) then
            ironfurGoEUntil = now + IRONFUR_GOE_WINDOW
        end
    elseif spellID == FRENZIED_REGEN then
        ironfurGoEUntil = 0
    end
end

-- Per-frame render for the Guardian Ironfur bar: prune expired ticks, position
-- the moving hash lines (right -> left as each cast decays), and drive the fill
-- to the longest-remaining fraction.
local function UpdateIronfurBar()
    if not (secondaryBar and secondaryBar:IsShown()) then return end
    local sp = ERB.db.profile.secondary
    local now = GetTime()

    -- Prune expired casts
    for i = #ironfurTicks, 1, -1 do
        if ironfurTicks[i].endTime <= now then
            table.remove(ironfurTicks, i)
        end
    end

    local count = #ironfurTicks
    local barW = secondaryBar:GetWidth() or 0
    local barH = secondaryBar:GetHeight() or 0
    local overlay = secondaryBar._ifOverlay
    local showHash = sp.guardianShowHashLines ~= false
    local PP = EllesmereUI and EllesmereUI.PP
    local tickW = PP and (2 * PP.mult) or 2
    local maxFrac = 0
    local shown = 0

    for i = 1, count do
        local t = ironfurTicks[i]
        local frac = (t.duration > 0) and ((t.endTime - now) / t.duration) or 0
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        if frac > maxFrac then maxFrac = frac end
        if showHash and overlay and barW > 0 then
            shown = shown + 1
            local tex = ironfurTickTex[shown]
            if not tex then
                tex = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:SetSnapToPixelGrid(false)
                tex:SetTexelSnappingBias(0)
                ironfurTickTex[shown] = tex
            end
            tex:SetColorTexture(1, 1, 1, 0.9)
            local x = frac * barW
            if x > barW - tickW then x = barW - tickW end
            if x < 0 then x = 0 end
            tex:ClearAllPoints()
            tex:SetSize(tickW, barH)
            tex:SetPoint("TOPLEFT", secondaryBar, "TOPLEFT", x, 0)
            tex:Show()
        end
    end

    -- Hide any leftover pooled tick textures
    for i = shown + 1, #ironfurTickTex do ironfurTickTex[i]:Hide() end

    -- Fill color: class/custom/dark base, swapped to the per-spec threshold
    -- color while the active Ironfur stack count is at or above the threshold.
    local r, g, b, a
    if sp.darkTheme then
        r, g, b, a = DARK_FILL_R, DARK_FILL_G, DARK_FILL_B, sp.fillA or 1
    elseif sp.classColored ~= false then
        local cc = CLASS_COLORS[cachedClass]
        if cc then r, g, b = cc[1], cc[2], cc[3] else r, g, b = 1, 1, 1 end
        a = sp.fillA or 1
    else
        r, g, b, a = sp.fillR, sp.fillG, sp.fillB, sp.fillA or 1
    end
    local tsEntry = ResolveThresholdSpecEntry(sp)
    if tsEntry and tsEntry.thresholdEnabled ~= false then
        local threshCount = tsEntry.thresholdCount or sp.thresholdCount or 3
        if count >= threshCount then
            r = tsEntry.thresholdR or sp.thresholdR or r
            g = tsEntry.thresholdG or sp.thresholdG or g
            b = tsEntry.thresholdB or sp.thresholdB or b
            a = tsEntry.thresholdA or sp.thresholdA or a
        end
    end
    local ft = secondaryBar:GetStatusBarTexture()
    if ft then ft:SetVertexColor(r, g, b, a) end

    -- Fill = longest remaining fraction (min/max is 0..1 for this bar), so the
    -- bar depletes with the longest-lived Ironfur stack. Set directly (no
    -- smoothing) and keep the smoother in sync so the generic secondaryBar
    -- lerp can't fight it.
    secondaryBar:SetValue(maxFrac)
    secondaryBar._smoothTarget = maxFrac
    secondaryBar._smoothCurrent = maxFrac

    if sp.showText and secondaryFrame and secondaryFrame._countText then
        secondaryFrame._countText:SetText(count > 0 and tostring(count) or "")
    end
end

-- Single moving hash line for the Prot Ignore Pain bar (Ironfur-style):
-- resets to the right edge on each Ignore Pain cast and slides left as the
-- buff duration decays. Reuses the Ironfur overlay host; one pooled texture.
-- Driven every frame from the main OnUpdate while the bar is shown.
IP.UpdateHash = function()
    local sp = ERB.db.profile.secondary
    local remain = IP.hashEndTime - GetTime()
    if sp.protIgnorePainHashLine == false or remain <= 0 then
        if IP.hashTex then IP.hashTex:Hide() end
        return
    end
    local barW = secondaryBar:GetWidth() or 0
    local barH = secondaryBar:GetHeight() or 0
    if barW <= 0 then return end
    local overlay = EnsureIronfurOverlay(secondaryBar)
    if not IP.hashTex then
        IP.hashTex = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
        IP.hashTex:SetSnapToPixelGrid(false)
        IP.hashTex:SetTexelSnappingBias(0)
        IP.hashTex:SetColorTexture(1, 1, 1, 0.9)
    end
    local PP = EllesmereUI and EllesmereUI.PP
    local tickW = PP and (2 * PP.mult) or 2
    local frac = remain / IP.DURATION
    if frac > 1 then frac = 1 end
    local x = frac * barW
    if x > barW - tickW then x = barW - tickW end
    if x < 0 then x = 0 end
    IP.hashTex:ClearAllPoints()
    IP.hashTex:SetSize(tickW, barH)
    IP.hashTex:SetPoint("TOPLEFT", secondaryBar, "TOPLEFT", x, 0)
    IP.hashTex:Show()
end

-- In-combat text source: the ONLY clean stack number available in combat is
-- the one Blizzard's own tracked-buff (cooldown viewer) Ignore Pain icon
-- displays -- Blizzard code reads the real aura and passes a plain value to
-- the icon's stack FontString, observable via hooksecurefunc. Every direct
-- read is secret (field-confirmed: absorbs, aura data, bar value AND the
-- rendered fill rect). Self-contained: no dependency on the EUI CDM module
-- (it keeps these Blizzard frames alive as data truth anyway). Graceful:
-- viewer hidden / IP untracked -> no viewer value, the text falls back to
-- the fill-width readback (works where values are clean) or stays blank.
IP.FrameSpellID = function(frame)
    if frame.GetSpellID then
        local ok, sid = pcall(frame.GetSpellID, frame)
        if ok and sid and not (issecretvalue and issecretvalue(sid)) then return sid end
    end
    local cdID = frame.cooldownID or (frame.cooldownInfo and frame.cooldownInfo.cooldownID)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok and info then
            local sid = info.spellID
            if sid and not (issecretvalue and issecretvalue(sid)) then return sid end
        end
    end
end

IP.HookViewerFS = function(frame, appFS)
    IP.viewerFrame = frame
    IP.viewerFS = appFS
    if not IP.hookedFS[appFS] then
        IP.hookedFS[appFS] = true
        hooksecurefunc(appFS, "SetText", function(_, val)
            if IP.viewerFS ~= appFS then return end
            -- Pool recycling: this frame may now show another buff
            if IP.FrameSpellID(frame) ~= IP.SPELL then
                IP.viewerFrame = nil
                IP.viewerFS = nil
                IP.value = nil
                return
            end
            -- Secrets pass through raw (SetText renders them);
            -- clean strings normalize to numbers.
            if issecretvalue and issecretvalue(val) then
                IP.value = val
            elseif type(val) == "number" then
                IP.value = val
            elseif type(val) == "string" then
                IP.value = tonumber(val)
            else
                IP.value = nil
            end
        end)
    end
    -- Seed from whatever the icon currently shows
    local ok, cur = pcall(appFS.GetText, appFS)
    if ok then
        if issecretvalue and issecretvalue(cur) then
            IP.value = cur
        elseif type(cur) == "string" then
            IP.value = tonumber(cur)
        end
    end
end

-- Scan BOTH Blizzard viewers for the Ignore Pain entry. Tracked Buffs icons
-- carry the stack FontString at frame.Applications.Applications; Tracked
-- Bars carry it at frame.Icon.Applications (the same child the EUI CDM
-- buff bars read stacks from). Whichever has IP wins.
IP.ScanViewer = function()
    if IP.viewerFrame then return end
    local function scanPool(viewer, resolve)
        if not viewer or not viewer.itemFramePool then return end
        for frame in viewer.itemFramePool:EnumerateActive() do
            if IP.FrameSpellID(frame) == IP.SPELL then
                local fs = resolve(frame)
                if fs then IP.HookViewerFS(frame, fs) end
                return
            end
        end
    end
    scanPool(_G.BuffIconCooldownViewer, function(f)
        return f.Applications and f.Applications.Applications
    end)
    if not IP.viewerFrame then
        scanPool(_G.BuffBarCooldownViewer, function(f)
            return f.Icon and f.Icon.Applications
        end)
    end
end

-- Per-frame stack text for the IP bar. Preferred source: the exact stack
-- number captured from Blizzard's tracked-buff icon (above). Fallback: the
-- rendered fill width (fill/bar = percent of cap = stacks) for contexts
-- where values read clean but the viewer is unavailable. Change-detected;
-- blank when no clean source exists, the bar is empty, or text is disabled.
IP.UpdateText = function()
    if not (secondaryFrame and secondaryFrame._countText) then return end
    local sp = ERB.db.profile.secondary
    if not sp.showText then
        if IP.lastTextStacks then
            secondaryFrame._countText:SetText("")
            IP.lastTextStacks = nil
        end
        return
    end
    -- Lazy (re)scan for the Blizzard tracked-buff IP icon (2s throttle)
    if not IP.viewerFrame and GetTime() >= IP.nextScan then
        IP.nextScan = GetTime() + 2
        IP.ScanViewer()
    end
    -- The captured viewer value is usually a SECRET number (type() says
    -- "number" and truthiness works, but comparisons/format error). SetText
    -- renders secret numbers natively -- it is exactly what Blizzard's own
    -- icon does with this same value -- so pass it through UNTOUCHED: no
    -- clamp, no change-detection, no tostring.
    if issecretvalue and issecretvalue(IP.value) then
        if IP.viewerFS and IP.viewerFS:IsVisible() then
            secondaryFrame._countText:SetText(IP.value)
            IP.lastTextStacks = nil  -- secrets cannot be change-detected
        elseif IP.lastTextStacks ~= 0 then
            IP.lastTextStacks = 0
            secondaryFrame._countText:SetText("")
        end
        return
    end
    local stacks = 0
    if IP.value and IP.viewerFS and IP.viewerFS:IsVisible() then
        stacks = IP.value
        if stacks > 100 then stacks = 100 end
        if stacks < 0 then stacks = 0 end
    else
        local ft = secondaryBar.GetStatusBarTexture and secondaryBar:GetStatusBarTexture()
        if ft then
            local okW, fw = pcall(ft.GetWidth, ft)
            local okB, bw = pcall(secondaryBar.GetWidth, secondaryBar)
            if okW and okB and fw and bw
               and not (issecretvalue and (issecretvalue(fw) or issecretvalue(bw)))
               and bw > 0 then
                stacks = math.floor(fw / bw * 100 + 0.5)
                if stacks > 100 then stacks = 100 end
            end
        end
    end
    if stacks == IP.lastTextStacks then return end
    IP.lastTextStacks = stacks
    secondaryFrame._countText:SetText(stacks > 0 and tostring(stacks) or "")
end

local function UpdateSecondaryResource()
    if not secondaryFrame or not secondaryFrame:IsShown() then return end
    if not cachedSecondary then return end

    local powerType = cachedSecondary.power
    local maxPts = cachedSecondary.max or 5

    if powerType == "IRONFUR_BAR" then
        UpdateIronfurBar()
        return
    end

    local sp = ERB.db.profile.secondary
    -- Resolve per-spec threshold entry once per update
    local _tsEntry = ResolveThresholdSpecEntry(sp)
    -- Per-entry thresholdEnabled (defaults to true for migrated entries without the field)
    local _tsEnabled = _tsEntry and (_tsEntry.thresholdEnabled ~= false) or false
    if not _tsEnabled then _tsEntry = nil end
    local _tsThreshCount = _tsEntry and _tsEntry.thresholdCount or sp.thresholdCount
    local _tsPartialOnly = _tsEntry and _tsEntry.thresholdPartialOnly
    if _tsPartialOnly == nil then _tsPartialOnly = sp.thresholdPartialOnly end
    -- Per-entry threshold color (falls back to global sp.thresholdR/G/B/A)
    local _tsR = _tsEntry and _tsEntry.thresholdR or sp.thresholdR
    local _tsG = _tsEntry and _tsEntry.thresholdG or sp.thresholdG
    local _tsB = _tsEntry and _tsEntry.thresholdB or sp.thresholdB
    local _tsA = _tsEntry and _tsEntry.thresholdA or sp.thresholdA
    local r, g, b, a = 1, 1, 1, 1

    -- Color: dark theme > class colored > custom fill color
    if sp.darkTheme then
        r, g, b = DARK_FILL_R, DARK_FILL_G, DARK_FILL_B
    elseif sp.classColored ~= false then
        -- Power types in secondary slot use power color; class resources use class color
        local pc = POWER_COLORS[powerType]
        if pc then r, g, b = pc[1], pc[2], pc[3]
        else
            local cc = CLASS_COLORS[cachedClass]
            if cc then r, g, b = cc[1], cc[2], cc[3] end
        end
        a = sp.fillA or 1
    else
        -- classColored explicitly false -- custom fill
        r, g, b, a = sp.fillR, sp.fillG, sp.fillB, sp.fillA or 1
    end

    if cachedSecondary.type == "runes" then
        local now = GetTime()
        local readyN, cdN = 0, 0
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
            _runeStart[i] = start
            _runeDuration[i] = duration
            if ready then
                _runeReady[i] = true
                _runeRemaining[i] = 0
                readyN = readyN + 1
                _runeOrder[readyN] = i
            else
                _runeReady[i] = false
                _runeRemaining[i] = (start and duration and duration > 0)
                    and max(0, start + duration - now) or 999
                cdN = cdN + 1
            end
        end

        -- Threshold: color ready runes differently when enough are available
        local runeUseThresh = _tsEntry and readyN >= _tsThreshCount
        local tr, tg, tb = _tsR, _tsG, _tsB

        if sp.runesSimple then
            -- Simple mode: flat pips like Holy Power (active/inactive, no recharge animation)
            local numPips = 6
            local totalW = sp.pipWidth or 214
            local pipSp = sp.pipSpacing or 1
            local slots = CalcPipGeometry(totalW, numPips, pipSp, secondaryFrame)

            for i = 1, 6 do
                local rf = runeFrames[i]
                if rf and rf:IsShown() then
                    local slot = slots[i]
                    local x0 = slot.x0
                    local w  = slot.x1 - slot.x0
                    local pipOri = sp.pipOrientation or "HORIZONTAL"
                    rf:ClearAllPoints()
                    if pipOri == "VERTICAL_UP" then
                        rf:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, x0)
                        rf:SetHeight(w)
                    elseif pipOri == "VERTICAL_DOWN" or pipOri == "VERTICAL" then
                        rf:SetPoint("TOP", secondaryFrame, "TOP", 0, -x0)
                        rf:SetHeight(w)
                    else
                        rf:SetPoint("LEFT", secondaryFrame, "LEFT", x0, 0)
                        rf:SetWidth(w)
                    end

                    local active = (i <= readyN)
                    if active and runeUseThresh then
                        if _tsPartialOnly and i < _tsThreshCount then
                            rf:SetActive(true, r, g, b, a)
                        else
                            rf:SetActive(true, tr, tg, tb)
                        end
                    else
                        rf:SetActive(active, r, g, b, a)
                    end
                    if rf._rechargeBar then rf._rechargeBar:Hide() end
                    if rf._cdText then rf._cdText:SetText("") end
                end
            end

            -- Central count text (like other pip resources)
            if sp.showText and secondaryFrame._countText then
                secondaryFrame._countText:SetText(tostring(readyN))
            end
        else
            -- Full rune mode: sort ready left, cooling right with recharge animation
            -- Clear central count text (used by simple mode)
            if secondaryFrame._countText then secondaryFrame._countText:SetText("") end
            -- Append cd runes after ready runes in _runeOrder
            local ci = readyN
            for i = 1, 6 do
                if not _runeReady[i] then
                    ci = ci + 1
                    _runeOrder[ci] = i
                end
            end
            -- Insertion-sort the cd portion (indices readyN+1..readyN+cdN) by
            -- remaining time. Max 6 elements so this is faster than table.sort
            -- and avoids creating a comparator closure each tick.
            for i = readyN + 2, readyN + cdN do
                local key = _runeOrder[i]
                local keyRem = _runeRemaining[key]
                local j = i - 1
                while j > readyN and _runeRemaining[_runeOrder[j]] > keyRem do
                    _runeOrder[j + 1] = _runeOrder[j]
                    j = j - 1
                end
                _runeOrder[j + 1] = key
            end
            local totalRunes = readyN + cdN

            -- Compute pixel-snapped pip geometry (spacing guaranteed >= 1 physical pixel)
            local numPips = 6
            local totalW = sp.pipWidth or 214
            local pipSp = sp.pipSpacing or 1
            local slots = CalcPipGeometry(totalW, numPips, pipSp, secondaryFrame)

            for pos = 1, totalRunes do
                local runeIdx = _runeOrder[pos]
                local rf = runeFrames[runeIdx]
                if rf and rf:IsShown() then
                    local slot = slots[pos]
                    local x0 = slot.x0
                    local w  = slot.x1 - slot.x0
                    local pipOri = sp.pipOrientation or "HORIZONTAL"
                    rf:ClearAllPoints()
                    if pipOri == "VERTICAL_UP" then
                        rf:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, x0)
                        rf:SetHeight(w)
                    elseif pipOri == "VERTICAL_DOWN" or pipOri == "VERTICAL" then
                        rf:SetPoint("TOP", secondaryFrame, "TOP", 0, -x0)
                        rf:SetHeight(w)
                    else
                        rf:SetPoint("LEFT", secondaryFrame, "LEFT", x0, 0)
                        rf:SetWidth(w)
                    end

                    if _runeReady[runeIdx] then
                        -- Ready rune: full brightness, hide recharge overlay
                        if runeUseThresh then
                            if _tsPartialOnly and pos < _tsThreshCount then
                                rf:SetActive(true, r, g, b, a)
                            else
                                rf:SetActive(true, tr, tg, tb)
                            end
                        else
                            rf:SetActive(true, r, g, b, a)
                        end
                        if rf._rechargeBar then rf._rechargeBar:Hide() end
                        if rf._cdText then rf._cdText:SetText("") end
                    else
                        -- Cooling-down rune: hide normal fill, show recharge bar
                        rf:SetActive(false, r, g, b, a)

                        -- Lazily create a StatusBar overlay for recharge progress
                        if not rf._rechargeBar then
                            local sb = CreateFrame("StatusBar", nil, rf)
                            sb:SetAllPoints(rf)
                            sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                            sb:SetFrameLevel(rf:GetFrameLevel())
                            sb:SetMinMaxValues(0, 1)
                            -- Apply the same bar texture if one is set
                            if rf._texKey then
                                local path = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, rf._texKey, nil)
                                if path then sb:SetStatusBarTexture(path) end
                            end
                            rf._rechargeBar = sb
                        end

                        -- Compute recharge fraction (0 = just started, 1 = almost ready)
                        local frac = 0
                        local rStart, rDur = _runeStart[runeIdx], _runeDuration[runeIdx]
                        if rStart and rDur and rDur > 0 then
                            local elapsed = now - rStart
                            frac = max(0, min(1, elapsed / rDur))
                        end
                        rf._rechargeBar:SetValue(frac)
                        -- 75% brightness while recharging (subtle dim), matching threshold color when active
                        if runeUseThresh then
                            rf._rechargeBar:SetStatusBarColor(tr * 0.75, tg * 0.75, tb * 0.75, a)
                        else
                            rf._rechargeBar:SetStatusBarColor(r * 0.75, g * 0.75, b * 0.75, a)
                        end
                        rf._rechargeBar:Show()

                        -- Show duration text if Resource Text is enabled (DK runes use it for cooldown)
                        if rf._cdText then
                            local rem = _runeRemaining[runeIdx]
                            if sp.showText and rem > 0 and rem < 999 then
                                rf._cdText:SetText(format("%d", ceil(rem)))
                            else
                                rf._cdText:SetText("")
                            end
                        end
                    end
                end
            end
        end
    elseif cachedSecondary.type == "bar" then
        -- Bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom, Brewmaster stagger)
        if secondaryBar then
            local cur, maxC = 0, maxPts
            if powerType == "SOUL_FRAGMENTS_DEVOURER" and EllesmereUI and EllesmereUI.GetSoulFragments then
                cur, maxC = EllesmereUI.GetSoulFragments()
                if not maxC or maxC <= 0 then maxC = maxPts end
            elseif powerType == "MAELSTROM_BAR" then
                cur = UnitPower("player", PT.MAELSTROM) or 0
                maxC = UnitPowerMax("player", PT.MAELSTROM) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "INSANITY_BAR" then
                cur = UnitPower("player", PT.INSANITY) or 0
                maxC = UnitPowerMax("player", PT.INSANITY) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "FOCUS_BAR" then
                cur = UnitPower("player", PT.FOCUS) or 0
                maxC = UnitPowerMax("player", PT.FOCUS) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "LUNAR_POWER_BAR" then
                cur = UnitPower("player", PT.LUNAR_POWER) or 0
                maxC = UnitPowerMax("player", PT.LUNAR_POWER) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "BREWMASTER_STAGGER" then
                cur = UnitStagger("player") or 0
                maxC = UnitHealthMax("player") or 1
                local curTainted = issecretvalue and issecretvalue(cur)
                local maxTainted = issecretvalue and issecretvalue(maxC)
                -- Apply stagger threshold colors (green/yellow/red) unless darkTheme is active
                -- Note: classColored is ignored for Stagger since the threshold colors ARE the feature
                if not sp.darkTheme then
                    if not curTainted and not maxTainted and maxC > 0 then
                        local pct = cur / maxC
                        local newR, newG, newB
                        if pct >= 0.6 then
                            newR, newG, newB = 1.0, 0.2, 0.2
                        elseif pct >= 0.3 then
                            newR, newG, newB = 1.0, 0.85, 0.2
                        else
                            newR, newG, newB = 0.2, 0.8, 0.2
                        end
                        -- Only update color if it actually changed (prevents flicker)
                        local lastR, lastG, lastB = secondaryBar._lastStaggerR, secondaryBar._lastStaggerG, secondaryBar._lastStaggerB
                        if lastR ~= newR or lastG ~= newG or lastB ~= newB then
                            secondaryBar._lastStaggerR, secondaryBar._lastStaggerG, secondaryBar._lastStaggerB = newR, newG, newB
                            secondaryBar:GetStatusBarTexture():SetVertexColor(newR, newG, newB, 1)
                        end
                    end
                end
                if maxTainted then maxC = maxPts end
                if not maxTainted and maxC <= 0 then maxC = 1 end
            elseif powerType == "IGNOREPAIN_BAR" then
                -- Prot Ignore Pain: total absorbs vs the IP cap (30% max
                -- health) -- the only readable source; aura stack data is
                -- fully secret in Midnight. A secret absorb value flows into
                -- SetValue via the always-updated smooth target.
                cur = UnitGetTotalAbsorbs("player") or 0
                maxC = UnitHealthMax("player")
                if (issecretvalue and issecretvalue(maxC)) or not maxC or maxC <= 0 then
                    maxC = maxPts
                else
                    maxC = maxC * IP.CAP
                end
            end
            -- Only call SetMinMaxValues if max actually changed (prevents flicker)
            local maxChanged = secondaryBar._lastMaxC ~= maxC
            if maxChanged then
                secondaryBar._lastMaxC = maxC
                secondaryBar:SetMinMaxValues(0, maxC)
            end
            -- Reapply hash line positions when max changes or on first valid layout
            -- (bar width may be 0 at BuildBars time before layout settles)
            local barW = secondaryBar:GetWidth()
            if barW > 0 and (maxChanged or not secondaryBar._hashApplied) then
                secondaryBar._hashApplied = true
                local _rtTsEntry = ResolveThresholdSpecEntry(sp)
                local _rtTickStr = (_rtTsEntry and _rtTsEntry.hashValues ~= "") and _rtTsEntry.hashValues or sp.tickValues
                local _rtHW = _rtTsEntry and _rtTsEntry.hashWidth or 1
                local _rtHR = _rtTsEntry and _rtTsEntry.hashColorR or 1
                local _rtHG = _rtTsEntry and _rtTsEntry.hashColorG or 1
                local _rtHB = _rtTsEntry and _rtTsEntry.hashColorB or 1
                local _rtHA = _rtTsEntry and _rtTsEntry.hashColorA or 0.7
                ApplyResourceBarTicks(secondaryBar, maxC, _rtTickStr, secondaryBarTicks, _rtHW, _rtHR, _rtHG, _rtHB, _rtHA)
            end
            -- Apply fill color (dark theme / class colored / custom).
            -- Brewmaster stagger uses threshold colors unless darkTheme is active.
            -- For bar-type resources (Maelstrom, Insanity), threshold triggers
            -- at or above thresholdCount treated as a percent value.
            if powerType ~= "BREWMASTER_STAGGER" or sp.darkTheme then
                local ft = secondaryBar:GetStatusBarTexture()
                if ft then
                    local pType = (powerType == "MAELSTROM_BAR") and PT.MAELSTROM
                               or (powerType == "INSANITY_BAR") and PT.INSANITY
                               or (powerType == "FOCUS_BAR") and PT.FOCUS
                               or (powerType == "LUNAR_POWER_BAR") and PT.LUNAR_POWER
                               or nil
                    if _tsEntry and pType and UnitPowerPercent then
                        -- Use ColorCurve + UnitPowerPercent: WoW evaluates the secret
                        -- value against the curve on the C side, returns a Color object.
                        local curve = GetBarThresholdCurve(
                            r, g, b,
                            _tsR or 1, _tsG or 0.2, _tsB or 0.2,
                            _tsThreshCount or 30)
                        if curve then
                            local ok, colorResult = pcall(UnitPowerPercent, "player", pType, false, curve)
                            if ok and colorResult and colorResult.GetRGBA then
                                ft:SetVertexColor(colorResult:GetRGBA())
                            else
                                ft:SetVertexColor(r, g, b, a)
                            end
                        else
                            ft:SetVertexColor(r, g, b, a)
                        end
                    elseif _tsEntry and powerType == "SOUL_FRAGMENTS_DEVOURER" then
                        local threshVal = _tsThreshCount or 30
                        if cur >= threshVal then
                            ft:SetVertexColor(_tsR or 1, _tsG or 0.2, _tsB or 0.2, _tsA or 1)
                        else
                            ft:SetVertexColor(r, g, b, a)
                        end
                    else
                        ft:SetVertexColor(r, g, b, a)
                    end
                end
            end
            -- Secret-aware update: pass secret values directly to the
            -- StatusBar (the C widget handles them natively).  Only use
            -- smooth animation for clean numeric values. The smooth target
            -- must ALWAYS be updated -- the OnUpdate smoother runs every
            -- frame, and a stale clean target left from before combat would
            -- lerp the bar right back over the direct secret SetValue (the
            -- "bar never fills in combat" bug). The smoother already passes
            -- a secret target straight through to SetValue.
            local tainted = issecretvalue and issecretvalue(cur)
            secondaryBar._smoothTarget = cur
            if tainted then
                secondaryBar:SetValue(cur)
            end
            -- Count text
            if sp.showText and secondaryFrame._countText then
                local percentSuffix = (sp.showPercent == false) and "" or "%"
                if not tainted then
                    if powerType == "BREWMASTER_STAGGER" then
                        -- Show stagger as percentage of max health
                        local pct = maxC > 0 and (cur / maxC * 100) or 0
                        secondaryFrame._countText:SetText(format("%d", pct) .. percentSuffix)
                    elseif powerType == "IGNOREPAIN_BAR" then
                        -- Text is driven per-frame by IP.UpdateText (viewer
                        -- capture preferred, fill-width fallback). No-op here.
                    elseif sp.showMaxStacks == false then
                        -- Devourer with Show Max Stacks off: current count only.
                        secondaryFrame._countText:SetFormattedText("%s", cur)
                    else
                        -- Current / max. SetFormattedText renders the (possibly
                        -- secret) current and keeps the clean max -- no Lua concat
                        -- of a secret value (see the note at the primary bar).
                        secondaryFrame._countText:SetFormattedText("%s / %s", cur, maxC)
                    end
                else
                    -- Secret value path: try UnitPowerPercent first, fall back to tostring
                    if powerType == "MAELSTROM_BAR" then
                        local pct = UnitPowerPercent and UnitPowerPercent("player", PT.MAELSTROM) or 0
                        if not issecretvalue(pct) then
                            secondaryFrame._countText:SetText(format("%d", pct) .. percentSuffix)
                        else
                            secondaryFrame._countText:SetText(tostring(cur))
                        end
                    elseif powerType == "INSANITY_BAR" then
                        local pct = UnitPowerPercent and UnitPowerPercent("player", PT.INSANITY) or 0
                        if not issecretvalue(pct) then
                            secondaryFrame._countText:SetText(format("%d", pct) .. percentSuffix)
                        else
                            secondaryFrame._countText:SetText(tostring(cur))
                        end
                    elseif powerType == "FOCUS_BAR" then
                        local pct = UnitPowerPercent and UnitPowerPercent("player", PT.FOCUS) or 0
                        if not issecretvalue(pct) then
                            secondaryFrame._countText:SetText(format("%d", pct) .. percentSuffix)
                        else
                            secondaryFrame._countText:SetText(tostring(cur))
                        end
                    elseif powerType == "LUNAR_POWER_BAR" then
                        local pct = UnitPowerPercent and UnitPowerPercent("player", PT.LUNAR_POWER) or 0
                        if not issecretvalue(pct) then
                            secondaryFrame._countText:SetText(format("%d", pct) .. percentSuffix)
                        else
                            secondaryFrame._countText:SetText(tostring(cur))
                        end
                    elseif powerType == "IGNOREPAIN_BAR" then
                        -- Text is driven per-frame by IP.UpdateText. No-op here.
                    elseif sp.showMaxStacks == false then
                        secondaryFrame._countText:SetFormattedText("%s", cur)
                    else
                        secondaryFrame._countText:SetFormattedText("%s / %s", cur, maxC)
                    end
                end
            end
        end
    elseif cachedSecondary.type == "custom" then
        local cur, maxC = 0, maxPts
        local isSecret = false
        if powerType == "SOUL_FRAGMENTS_VENGEANCE" then
            -- Vengeance DH: GetSpellCastCount returns a SECRET value in 12.0+.
            -- We cannot compare it in Lua.  Instead we pass the raw value to
            -- StatusBar widgets embedded in each pip (SetMinMaxValues(i-1, i)
            -- + SetValue(secret)) which fill/empty entirely on the C side.
            local rawCur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
            cur = rawCur
            isSecret = true
            maxC = 6
        elseif powerType == "SOUL_FRAGMENTS" and EllesmereUI and EllesmereUI.GetSoulFragments then
            cur, maxC = EllesmereUI.GetSoulFragments()
            if not maxC or maxC <= 0 then maxC = maxPts end
        elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
            cur, maxC = EllesmereUI.GetMaelstromWeapon()
            -- Enhance 5-bar mode: clamp visual to 5 pips
            if sp.enhanceFiveBar and maxC > 5 then maxC = 5 end
        elseif powerType == "TIP_OF_THE_SPEAR" and EllesmereUI and EllesmereUI.GetTipOfTheSpear then
            cur, maxC = EllesmereUI.GetTipOfTheSpear()
        elseif powerType == "WHIRLWIND_STACKS" and EllesmereUI and EllesmereUI.GetWhirlwindStacks then
            cur, maxC = EllesmereUI.GetWhirlwindStacks()
            if not maxC or maxC <= 0 then
                for i = 1, #pips do if pips[i] then pips[i]:Hide() end end
                return
            end
        elseif powerType == "ICICLES" then
            cur = GetIcicleCount()
            maxC = 5
        end
        -- For pips using class color, prefer the per-class resource color
        if sp.classColored ~= false and not sp.darkTheme then
            local pc2 = POWER_COLORS[powerType]
            if pc2 then
                r, g, b = pc2[1], pc2[2], pc2[3]
            elseif EllesmereUI and EllesmereUI.GetResourceColor then
                local _, classFile = UnitClass("player")
                local rc = EllesmereUI.GetResourceColor(classFile)
                if rc then r, g, b = rc.r, rc.g, rc.b end
            end
        end

        if isSecret then
            -- Secret-value path: drive each pip via a StatusBar overlay.
            -- The StatusBar accepts the secret number natively; when the
            -- value falls within [i-1, i] the bar fills proportionally,
            -- giving us a binary active/inactive look for integer counts.
            for i = 1, maxC do
                local pip = pips[i]
                if pip and pip:IsShown() then
                    -- Lazily create a StatusBar overlay inside the pip
                    local texKey = ERB.db and ERB.db.profile and ERB.db.profile.general and ERB.db.profile.general.barTexture or "none"
                    local texPath = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
                    if not pip._secretBar then
                        local sb = CreateFrame("StatusBar", nil, pip)
                        sb:SetAllPoints(pip._fill)
                        sb:SetStatusBarTexture(texPath)
                        sb:SetStatusBarColor(r, g, b, a)
                        sb:SetFrameLevel(pip:GetFrameLevel())
                        pip._secretBar = sb
                    else
                        pip._secretBar:SetStatusBarTexture(texPath)
                    end
                    pip._secretBar:SetMinMaxValues(i - 1, i)
                    pip._secretBar:SetValue(cur)
                    pip._secretBar:SetStatusBarColor(r, g, b, a)
                    pip._secretBar:Show()
                    -- Hide the normal fill; the StatusBar replaces it
                    pip._fill:Hide()
                end
            end
            -- Count text -- tostring handles secret values safely
            if sp.showText and secondaryFrame._countText then
                secondaryFrame._countText:SetText(tostring(cur))
            end
        else
            -- Clean-value path: normal boolean comparisons
            -- Hide any leftover secret StatusBar overlays
            for i = 1, maxC do
                if pips[i] and pips[i]._secretBar then pips[i]._secretBar:Hide() end
            end
            -- Enhance 5-bar overflow: stacks 6-10 recolor pips 1-5
            local _enhFive = sp.enhanceFiveBar and powerType == "MAELSTROM_WEAPON"
            local _enhOverflow = _enhFive and cur > 5
            local _enhOverCount = _enhOverflow and (cur - 5) or 0
            local _enhRealCur = cur  -- preserve for count text
            local _enhOR, _enhOG, _enhOB = sp.enhanceOverflowR or 1, sp.enhanceOverflowG or 0.6, sp.enhanceOverflowB or 0.2
            if _enhOverflow then cur = 5 end  -- all 5 pips active when overflowing

            local useThresh = _tsEntry and cur >= _tsThreshCount and not _enhFive
            local tr, tg, tb = _tsR, _tsG, _tsB
            for i = 1, maxC do
                if pips[i] and pips[i]:IsShown() then
                    local active = i <= cur
                    if active and _enhOverflow and i <= _enhOverCount then
                        pips[i]:SetActive(true, _enhOR, _enhOG, _enhOB)
                    elseif active and useThresh then
                        if _tsPartialOnly and i < _tsThreshCount then
                            pips[i]:SetActive(true, r, g, b, a)
                        else
                            pips[i]:SetActive(true, tr, tg, tb)
                        end
                    else
                        pips[i]:SetActive(active, r, g, b, a)
                    end
                end
            end
            -- Count text (use real count, not clamped)
            if sp.showText and secondaryFrame._countText then
                secondaryFrame._countText:SetText(tostring(_enhRealCur or cur))
            end
        end
    else
        local cur = UnitPower("player", powerType)
        local useThresh = _tsEntry and cur >= _tsThreshCount
        local tr, tg, tb = _tsR, _tsG, _tsB

        -- Fractional resource detection
        local frac = 0
        local preciseCur = cur
        if powerType == PT.SOUL_SHARDS then
            -- Destruction warlock: UnitPower partial values work
            local specIdx = GetSpecialization()
            local specID = specIdx and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(specIdx)
            if specID == 267 then
                local raw = UnitPower("player", powerType, true)
                if raw and (not issecretvalue or not issecretvalue(raw)) then
                    preciseCur = raw / 10
                    frac = preciseCur - cur
                end
            end
        elseif powerType == PT.ESSENCE then
            -- Evoker Essence: timer-based recharge (UnitPower partial doesn't work)
            local now = GetTime()
            local maxE = UnitPowerMax("player", PT.ESSENCE) or maxPts
            if issecretvalue and issecretvalue(maxE) then maxE = maxPts end

            -- Safely query essence regen rate (secret in combat)
            local function EssenceTickDuration()
                if not GetPowerRegenForPowerType then return _essenceTickDur > 0 and _essenceTickDur or 5 end
                local regen = GetPowerRegenForPowerType(PT.ESSENCE)
                if not regen or (issecretvalue and issecretvalue(regen)) then
                    return _essenceTickDur > 0 and _essenceTickDur or 5
                end
                return regen > 0 and (1 / regen) or 5
            end

            -- Detect pip gain/loss and reset the timer
            if _essenceLastCount == nil then _essenceLastCount = cur end
            if cur ~= _essenceLastCount then
                if cur < maxE then
                    _essenceTickDur = EssenceTickDuration()
                    _essenceNextTick = now + _essenceTickDur
                else
                    _essenceNextTick = nil
                end
                _essenceLastCount = cur
            end

            -- If below max and no timer running, start one
            if cur < maxE and not _essenceNextTick then
                _essenceTickDur = EssenceTickDuration()
                _essenceNextTick = now + _essenceTickDur
            end

            -- At max: clear timer
            if cur >= maxE then _essenceNextTick = nil end

            -- Compute fill fraction for the recharging pip
            if _essenceNextTick and _essenceTickDur > 0 then
                local remaining = max(0, _essenceNextTick - now)
                frac = 1 - (remaining / _essenceTickDur)
                frac = max(0, min(1, frac))
                preciseCur = cur + frac
            end
        end

        -- Charged combo points (e.g. Supercharger talent)
        local chargedSet
        if powerType == PT.COMBO then
            local fn = GetUnitChargedPowerPoints
            if fn then
                local pts = fn("player")
                if pts and #pts > 0 then
                    chargedSet = {}
                    for _, idx in ipairs(pts) do chargedSet[idx] = true end
                end
            end
        end
        local cr, cg, cb, ca = sp.chargedR or 0.44, sp.chargedG or 0.77, sp.chargedB or 1.00, sp.chargedA or 1

        for i = 1, maxPts do
            if pips[i] and pips[i]:IsShown() then
                local active = i <= cur
                if chargedSet and chargedSet[i] then
                    if active then
                        pips[i]:SetActive(true, cr, cg, cb, ca)
                    else
                        pips[i]:SetActive(true, cr * 0.5, cg * 0.5, cb * 0.5, ca)
                    end
                elseif active and useThresh then
                    if _tsPartialOnly and i < _tsThreshCount then
                        pips[i]:SetActive(true, r, g, b, a)
                    else
                        pips[i]:SetActive(true, tr, tg, tb)
                    end
                else
                    pips[i]:SetActive(active, r, g, b, a)
                end
                -- Hide any leftover partial-fill overlay on non-fractional pips
                if pips[i]._rechargeBar then pips[i]._rechargeBar:Hide() end
            end
        end

        -- Partial pip fill for fractional resources (reuses DK rune recharge pattern)
        if frac > 0 and cur < maxPts and pips[cur + 1] and pips[cur + 1]:IsShown() then
            local nextPip = pips[cur + 1]
            if not nextPip._rechargeBar then
                local sb = CreateFrame("StatusBar", nil, nextPip)
                sb:SetAllPoints(nextPip)
                sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                sb:SetFrameLevel(nextPip:GetFrameLevel())
                sb:SetMinMaxValues(0, 1)
                if nextPip._texKey then
                    local path = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, nextPip._texKey, nil)
                    if path then sb:SetStatusBarTexture(path) end
                end
                nextPip._rechargeBar = sb
            end
            nextPip._rechargeBar:SetValue(frac)
            nextPip._rechargeBar:SetStatusBarColor(r * 0.75, g * 0.75, b * 0.75, a)
            nextPip._rechargeBar:Show()
        end

        -- Count text
        if sp.showText and secondaryFrame._countText then
            if frac > 0 and powerType ~= PT.ESSENCE then
                secondaryFrame._countText:SetText(format("%.1f", preciseCur))
            else
                secondaryFrame._countText:SetText(tostring(cur))
            end
        end
    end
end


-------------------------------------------------------------------------------
--  Visibility & combat fade
-------------------------------------------------------------------------------
local function ShouldShowSecondary()
    local sp = ERB.db.profile.secondary
    -- Check visibility options first
    if EllesmereUI and EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(sp) then return false end
    local vis = sp.visibility
    if vis == "always" then return true end
    if vis == "never" then return false end
    if vis == "combat" or vis == "in_combat" then return isInCombat end
    if vis == "out_of_combat" then return not isInCombat end
    if vis == "target" then return UnitExists("target") and UnitCanAttack("player", "target") end
    if vis == "in_raid" then return IsInRaid and IsInRaid() or false end
    if vis == "in_party" then
        local inRaid = IsInRaid and IsInRaid() or false
        return inRaid or (IsInGroup and IsInGroup() or false)
    end
    if vis == "solo" then
        return not (IsInRaid and IsInRaid()) and not (IsInGroup and IsInGroup())
    end
    return true
end

local function ShouldShowBar(barProfile)
    -- Check visibility options first
    if EllesmereUI and EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(barProfile) then return false end
    local vis = barProfile.visibility or "always"
    if vis == "always" then return true end
    if vis == "never" then return false end
    if vis == "combat" or vis == "in_combat" then return isInCombat end
    if vis == "out_of_combat" then return not isInCombat end
    if vis == "target" then return UnitExists("target") and UnitCanAttack("player", "target") end
    if vis == "in_raid" then return IsInRaid and IsInRaid() or false end
    if vis == "in_party" then
        local inRaid = IsInRaid and IsInRaid() or false
        return inRaid or (IsInGroup and IsInGroup() or false)
    end
    if vis == "solo" then
        return not (IsInRaid and IsInRaid()) and not (IsInGroup and IsInGroup())
    end
    return true
end

local function UpdateVisibility()
    if not mainFrame then return end

    -- Main frame always shown
    mainFrame:Show()
    mainFrame:SetAlpha(1)

    local inVehicle = ERB._inVehicle

    -- Health bar visibility
    if healthBar then
        local hp = ERB.db.profile.health
        if hp and hp.enabled and not IsSpecDisabled(hp) and ShouldShowBar(hp) and not inVehicle then
            healthBar:Show()
            EllesmereUI.SetElementVisibility(healthBar, true)
            healthBar:SetAlpha(hp.barAlpha or 1)
        else
            EllesmereUI.SetElementVisibility(healthBar, false)
        end
    end

    -- Power bar visibility
    if primaryBar then
        local pp = ERB.db.profile.primary
        local sp = ERB.db.profile.secondary
        -- Also check cachedPrimary: specs without a primary power (e.g. BM/MM Hunter)
        -- should hide the power bar even if enabled in settings
        local hidePower = sp and sp.hidePowerIfResource and cachedSecondary
        if not hidePower and pp and pp.enabled ~= false and not IsSpecDisabled(pp) and cachedPrimary and ShouldShowBar(pp) and not inVehicle then
            primaryBar:Show()
            EllesmereUI.SetElementVisibility(primaryBar, true)
            primaryBar:SetAlpha(pp.barAlpha or 1)
        else
            EllesmereUI.SetElementVisibility(primaryBar, false)
        end
    end

    -- Secondary resource visibility + ooc alpha
    if secondaryFrame then
        local sp = ERB.db.profile.secondary
        if sp and sp.enabled ~= false and cachedSecondary and ShouldShowSecondary() and not inVehicle then
            secondaryFrame:Show()
            EllesmereUI.SetElementVisibility(secondaryFrame, true)
            local base = sp.barAlpha or 1
            local ooc = isInCombat and 1 or (sp.oocAlpha or 1)
            secondaryFrame:SetAlpha(base * ooc)
        else
            EllesmereUI.SetElementVisibility(secondaryFrame, false)
        end
    end
end

-------------------------------------------------------------------------------
--  OnUpdate: smooth bar animation
-------------------------------------------------------------------------------
local SMOOTH_SPEED = 8
local _runeThrottle = 0
local _hpColorThrottle = 0

local function OnUpdate(self, dt)
    -- Smooth bar animation (health)
    if healthBar and healthBar:IsShown() then
        local tgt = healthBar._smoothTarget
        if issecretvalue and issecretvalue(tgt) then
            healthBar:SetValue(tgt)
        else
            local cur = healthBar._smoothCurrent
            if abs(cur - tgt) > 1 then
                cur = Lerp(cur, tgt, min(1, dt * SMOOTH_SPEED))
                healthBar._smoothCurrent = cur
                healthBar:SetValue(cur)
            end
        end
        -- Poll threshold color at ~20fps so it reacts without waiting for UNIT_HEALTH.
        -- Only runs when the health bar is visible AND threshold coloring is enabled.
        _hpColorThrottle = _hpColorThrottle + dt
        if _hpColorThrottle >= 0.05 then
            _hpColorThrottle = 0
            local hp = ERB.db.profile.health
            local _hpPollEntry = hp and ResolveThresholdSpecEntry(hp) or nil
            local _hpPollEnabled = _hpPollEntry and (_hpPollEntry.thresholdEnabled ~= false) or false
            if not _hpPollEnabled then _hpPollEntry = nil end
            if _hpPollEntry and UnitHealthPercent then
                local ft = healthBar:GetStatusBarTexture()
                if ft then
                    local baseR, baseG, baseB
                    if hp.darkTheme then
                        baseR, baseG, baseB = DARK_FILL_R, DARK_FILL_G, DARK_FILL_B
                    elseif hp.customColored then
                        baseR, baseG, baseB = hp.fillR, hp.fillG, hp.fillB
                    else
                        local cc = CLASS_COLORS[cachedClass]
                        if cc then baseR, baseG, baseB = cc[1], cc[2], cc[3]
                        else baseR, baseG, baseB = 0.15, 0.75, 0.30 end
                    end
                    local tR = _hpPollEntry.thresholdR or hp.thresholdR or 1
                    local tG = _hpPollEntry.thresholdG or hp.thresholdG or 0.2
                    local tB = _hpPollEntry.thresholdB or hp.thresholdB or 0.2
                    local curve = GetBarThresholdCurve(baseR, baseG, baseB, tR, tG, tB, _hpPollEntry.thresholdPct or hp.thresholdPct or 30)
                    if curve then
                        local ok, colorResult = pcall(UnitHealthPercent, "player", false, curve)
                        if ok and colorResult and colorResult.GetRGBA then
                            ft:SetVertexColor(colorResult:GetRGBA())
                        end
                    end
                end
            end
        end
    end

    -- Smooth bar animation (primary resource)
    if primaryBar and primaryBar:IsShown() then
        if cachedPrimary == "EBON_MIGHT" then
            -- Ebon Might countdown (throttled to ~20 fps for smooth drain)
            _ebonMightThrottle = _ebonMightThrottle + dt
            if _ebonMightThrottle >= 0.05 then
                _ebonMightThrottle = 0
                local remaining = (_ebonMightExpiry > 0) and max(0, _ebonMightExpiry - GetTime()) or 0
                primaryBar:SetValue(remaining)
                primaryBar._smoothTarget = remaining
                primaryBar._smoothCurrent = remaining
                -- Text
                local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
                if pp and pp.textFormat and pp.textFormat ~= "none" then
                    local fmt = pp.textFormat
                    local percentSuffix = (pp.showPercent == false) and "" or "%"
                    local pct = format("%d", remaining / EBON_MIGHT_DURATION * 100)
                    local timeText = remaining > 0 and format("%.1f", remaining) or "0"
                    local txt
                    if fmt == "perpp" then txt = pct .. percentSuffix
                    elseif fmt == "both" then txt = timeText .. " | " .. pct .. percentSuffix
                    else txt = timeText end
                    primaryBar._text:SetText(txt)
                end
            end
        else
            local tgt = primaryBar._smoothTarget
            if issecretvalue and issecretvalue(tgt) then
                primaryBar:SetValue(tgt)
            else
                local cur = primaryBar._smoothCurrent
                if abs(cur - tgt) > 1 then
                    cur = Lerp(cur, tgt, min(1, dt * SMOOTH_SPEED))
                    primaryBar._smoothCurrent = cur
                    primaryBar:SetValue(cur)
                end
            end
        end
    end

    -- Guardian Ironfur bar: drive moving hash lines + fill every frame for
    -- smooth right-to-left motion (the 0.1s throttle below would look choppy).
    if cachedSecondary and cachedSecondary.power == "IRONFUR_BAR"
       and secondaryBar and secondaryBar:IsShown() then
        UpdateIronfurBar()
    -- Smooth bar animation (bar-style secondary, e.g. Devourer / Elemental maelstrom)
    elseif secondaryBar and secondaryBar:IsShown() then
        local tgt = secondaryBar._smoothTarget
        if issecretvalue and issecretvalue(tgt) then
            secondaryBar:SetValue(tgt)
        else
            local cur = secondaryBar._smoothCurrent
            if abs(cur - tgt) > 0.5 then
                cur = Lerp(cur, tgt, min(1, dt * SMOOTH_SPEED))
                secondaryBar._smoothCurrent = cur
                secondaryBar:SetValue(cur)
            end
        end
    end

    -- Prot Ignore Pain: drive the single moving duration hash + the
    -- fill-width-derived stack text every frame (both cheap + change-gated)
    if cachedSecondary and cachedSecondary.power == "IGNOREPAIN_BAR"
       and secondaryBar and secondaryBar:IsShown() then
        IP.UpdateHash()
        IP.UpdateText()
    end

    -- DK rune updates (throttled to ~10 fps) -- calls the full sorted
    -- update so rune positions stay consistent with depletion order.
    if cachedSecondary and cachedSecondary.type == "runes" then
        _runeThrottle = _runeThrottle + dt
        if _runeThrottle >= 0.1 then
            _runeThrottle = 0
            UpdateSecondaryResource()
        end
    end

    -- Evoker Essence recharge animation (throttled to ~20 fps for smooth fill)
    if _essenceNextTick and cachedSecondary and cachedSecondary.power == PT.ESSENCE then
        _runeThrottle = _runeThrottle + dt
        if _runeThrottle >= 0.05 then
            _runeThrottle = 0
            UpdateSecondaryResource()
        end
    end

    -- Cast bar update
    UpdateCastBar(dt)

    -- Throttled poll for Vengeance soul fragments (GetSpellCastCount has no
    -- discrete event) and as a safety net for other custom/bar resources.
    if cachedSecondary and (cachedSecondary.type == "custom" or cachedSecondary.type == "bar") then
        _runeThrottle = _runeThrottle + dt  -- reuse the rune throttle counter
        if _runeThrottle >= 0.1 then
            _runeThrottle = 0
            UpdateSecondaryResource()
        end
    end
end


-------------------------------------------------------------------------------
--  Bar Textures (shared with options)
-------------------------------------------------------------------------------
local TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local CAST_BAR_TEXTURES = {
    ["none"]          = nil,
    ["blizzard"]      = "ATLAS",
    ["melli"]         = TEX_BASE .. "melli.tga",
    ["beautiful"]     = TEX_BASE .. "beautiful.tga",
    ["plating"]       = TEX_BASE .. "plating.tga",
    ["atrocity"]      = TEX_BASE .. "atrocity.tga",
    ["divide"]        = TEX_BASE .. "divide.tga",
    ["glass"]         = TEX_BASE .. "glass.tga",
    ["fade-right"]    = TEX_BASE .. "fade-right.tga",
    ["thin-line-top"]    = TEX_BASE .. "thin-line-top.tga",
    ["thin-line-bottom"] = TEX_BASE .. "thin-line-bottom.tga",
    ["fade"]          = TEX_BASE .. "fade.tga",
    ["gradient-lr"]   = TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = TEX_BASE .. "matte.tga",
    ["sheer"]         = TEX_BASE .. "sheer.tga",
}
local CAST_BAR_TEXTURE_ORDER = {
    "none", "blizzard", "melli", "atrocity",
    "fade", "fade-right", "thin-line-top", "thin-line-bottom",
    "beautiful", "plating",
    "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local CAST_BAR_TEXTURE_NAMES = {
    ["none"]        = "None",
    ["blizzard"]    = "Blizzard",
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
-- Expose for options
_G._ERB_CastBarTextures     = CAST_BAR_TEXTURES
_G._ERB_CastBarTextureOrder = CAST_BAR_TEXTURE_ORDER
_G._ERB_CastBarTextureNames = CAST_BAR_TEXTURE_NAMES

-------------------------------------------------------------------------------
--  Health/Power bar texture tables (shared with options dropdown)
-------------------------------------------------------------------------------
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
    "fade", "fade-right", "thin-line-top", "thin-line-bottom",
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
_G._ERB_BarTextures     = BAR_TEXTURES
_G._ERB_BarTextureOrder = BAR_TEXTURE_ORDER
_G._ERB_BarTextureNames = BAR_TEXTURE_NAMES

-------------------------------------------------------------------------------
--  Append SharedMedia statusbar textures to both texture tables via the
--  shared EllesmereUI helper (same entry point Unit Frames uses). Safe to
--  call multiple times; dupes are skipped inside the helper.
-------------------------------------------------------------------------------
local function AppendSharedMediaTextures()
    if not EllesmereUI.AppendSharedMediaTextures then return end
    EllesmereUI.AppendSharedMediaTextures(
        CAST_BAR_TEXTURE_NAMES,
        CAST_BAR_TEXTURE_ORDER,
        nil,
        CAST_BAR_TEXTURES
    )
    EllesmereUI.AppendSharedMediaTextures(
        BAR_TEXTURE_NAMES,
        BAR_TEXTURE_ORDER,
        nil,
        BAR_TEXTURES
    )
end


-------------------------------------------------------------------------------
--  Player Cast Bar
-------------------------------------------------------------------------------
local SPARK_TEX = "Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga"

BuildCastBar = function()
    local cb = ERB.db.profile.castBar

    -- ResourceBars only claims Blizzard's player cast bar while its own
    -- replacement bar is active. The shared helper arbitrates ownership
    -- across EUI modules and releases control cleanly for other addons.
    if EllesmereUI and EllesmereUI.SetPlayerCastBarSuppressed then
        EllesmereUI.SetPlayerCastBarSuppressed("ResourceBars", cb.enabled)
    end

    if not cb.enabled then
        if castBarFrame then EllesmereUI.SetElementVisibility(castBarFrame, false) end
        return
    end

    if not castBarFrame then
        castBarFrame = CreateFrame("Frame", "ERB_CastBarFrame", UIParent)
        castBarFrame:SetFrameStrata(cb.frameStrata or "MEDIUM")
        castBarFrame:SetFrameLevel(15)

        -- Background
        local bg = castBarFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        castBarFrame._bg = bg

        -- Border frame: child that covers the full cast bar (bar + icon)
        local bdrFrame = CreateFrame("Frame", nil, castBarFrame)
        bdrFrame:SetAllPoints(castBarFrame)
        bdrFrame:SetFrameLevel(castBarFrame:GetFrameLevel() + 5)
        castBarFrame._border = bdrFrame
        local PP = EllesmereUI and EllesmereUI.PP
        if PP then PP.CreateBorder(bdrFrame, 0, 0, 0, 1, 1) end

        -- Clip frame to prevent bar fill from bleeding past the border
        local clipFrame = CreateFrame("Frame", nil, castBarFrame)
        clipFrame:SetClipsChildren(true)
        castBarFrame._barClip = clipFrame

        -- Status bar (inside clip frame)
        local bar = CreateFrame("StatusBar", "ERB_CastBar", clipFrame)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        castBarFrame._bar = bar

        -- Spark (in its own child frame inside clip so it gets clipped)
        local sparkFrame = CreateFrame("Frame", nil, clipFrame)
        sparkFrame:SetAllPoints(bar)
        sparkFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
        local spark = sparkFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture(SPARK_TEX)
        spark:SetBlendMode("ADD")
        castBarFrame._spark = spark

        -- Latency overlay (on clipFrame, above bar fill, below spark)
        local latOverlay = clipFrame:CreateTexture(nil, "ARTWORK", nil, 7)
        latOverlay:Hide()
        castBarFrame._latencyOverlay = latOverlay

        -- Spell icon
        local iconFrame = CreateFrame("Frame", nil, castBarFrame)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castBarFrame._iconFrame = iconFrame
        castBarFrame._icon = icon

        -- Text overlay frame (above all bar borders)
        local textFrame = CreateFrame("Frame", nil, castBarFrame)
        textFrame:SetAllPoints(bar)
        textFrame:SetFrameLevel(25)
        castBarFrame._textFrame = textFrame

        -- Spell name text
        local nameText = textFrame:CreateFontString(nil, "OVERLAY")
        SetRBFont(nameText, GetRBFont(), 11)
        nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetNonSpaceWrap(false)
        castBarFrame._nameText = nameText

        -- Timer text
        local timerText = textFrame:CreateFontString(nil, "OVERLAY")
        SetRBFont(timerText, GetRBFont(), 11)
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        timerText:SetJustifyH("RIGHT")
        timerText:SetWordWrap(false)
        timerText:SetNonSpaceWrap(false)
        castBarFrame._timerText = timerText

        -- Casting state
        castBarFrame._casting = false
        castBarFrame._channeling = false
        castBarFrame._empowering = false
        castBarFrame._castID = nil
        castBarFrame._startTime = 0
        castBarFrame._endTime = 0
        castBarFrame._spellName = ""
        castBarFrame._pips = {}
        castBarFrame._numStages = 0
        castBarFrame._ticks = {}
        castBarFrame._numTicks = 0
    end

    -- Apply settings
    local w, h = cb.width, cb.height
    local hasIcon = cb.showIcon ~= false
    -- Total frame width includes icon (h x h) only when icon is shown
    local totalW = hasIcon and (w + h) or w
    if cb.unlockPos and cb.unlockPos.point then
        -- Position managed by unlock mode -- only animate size changes.
        -- Skip reposition during unlock mode so resize does not snap the bar.
        local rp = cb.unlockPos.relPoint or cb.unlockPos.point
        local px, py = cb.unlockPos.x or 0, cb.unlockPos.y or 0
        local anchored = EllesmereUI.IsUnlockAnchored("ERB_CastBar")
        if EllesmereUI._unlockActive then
            castBarFrame:SetSize(totalW, h)
        elseif anchored and castBarFrame:GetLeft() then
            -- Anchor system owns position; just set size directly
            castBarFrame:SetSize(totalW, h)
        else
            local function ApplyCastUnlockTransform()
                local aw = castBarFrame["_barAnim_w"] or totalW
                local ah = castBarFrame["_barAnim_h"] or h
                castBarFrame:SetSize(aw, ah)
                castBarFrame:ClearAllPoints()
                castBarFrame:SetPoint(cb.unlockPos.point, UIParent, rp, px, py)
            end
            SmoothBarAnimate(castBarFrame, "w", totalW, function() ApplyCastUnlockTransform() end)
            SmoothBarAnimate(castBarFrame, "h", h, function() ApplyCastUnlockTransform() end)
        end
    else
        castBarFrame:SetSize(totalW, h)
        if not EllesmereUI._unlockActive then
            castBarFrame:ClearAllPoints()
            castBarFrame:SetPoint("CENTER", UIParent, "CENTER", cb.anchorX, cb.anchorY)
        end
    end

    -- Border: update the dedicated child border frame (PP or textured)
    if castBarFrame._border then
        local bs = cb.borderSize or 0
        local texKey = cb.borderTexture or "solid"
        -- "Show Behind": +5 in front of the bar, level-1 behind it.
        local pl = castBarFrame:GetFrameLevel()
        castBarFrame._border:SetFrameLevel(cb.borderBehind and math.max(0, pl - 1) or (pl + 5))
        EllesmereUI.ApplyBorderStyle(castBarFrame._border, bs,
            cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1,
            texKey, cb.borderTextureOffset, cb.borderTextureOffsetY,
            cb.borderTextureShiftX, cb.borderTextureShiftY, "resourcebars", bs)
    end

    -- Icon: left side, full height, no inset
    local iconFrame = castBarFrame._iconFrame
    if hasIcon then
        iconFrame:SetSize(h, h)
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("TOPLEFT", castBarFrame, "TOPLEFT", 0, 0)
        iconFrame:Show()
    else
        iconFrame:Hide()
    end

    -- Clip frame + bar: right of icon (or full width), full height
    local clipFrame = castBarFrame._barClip
    local bar = castBarFrame._bar
    local bdrInset = (PP and PP.mult) or 1
    clipFrame:ClearAllPoints()
    clipFrame:SetPoint("TOPLEFT", castBarFrame, "TOPLEFT", (hasIcon and h or 0) + bdrInset, -bdrInset)
    clipFrame:SetPoint("BOTTOMRIGHT", castBarFrame, "BOTTOMRIGHT", -bdrInset, bdrInset)
    clipFrame:SetFrameLevel(castBarFrame:GetFrameLevel() + 1)
    bar:ClearAllPoints()
    bar:SetAllPoints(clipFrame)

    -- Bar texture
    local texKey = cb.texture
    local isBlizzard = (texKey == "blizzard")
    if isBlizzard then
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        bar:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        castBarFrame._bg:SetAtlas("UI-CastingBar-Background", true)
        castBarFrame._bg:ClearAllPoints()
        castBarFrame._bg:SetAllPoints(castBarFrame)
    else
        local texPath = EllesmereUI.ResolveTexturePath(CAST_BAR_TEXTURES, texKey, "Interface\\Buttons\\WHITE8x8")
        bar:SetStatusBarTexture(texPath)
        castBarFrame._bg:SetTexture(nil)
        castBarFrame._bg:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
    end

    -- Bar color / gradient
local fillTex = bar:GetStatusBarTexture()

if cb.gradientEnabled then
    local dir = cb.gradientDir or "HORIZONTAL"

    local fR, fG, fB, fA = cb.fillR, cb.fillG, cb.fillB, cb.fillA
    if cb.classColored then
        local cc = CLASS_COLORS[cachedClass]
        if cc then fR, fG, fB = cc[1], cc[2], cc[3] end
    end
    fillTex:SetVertexColor(1, 1, 1, 1)
    fillTex:SetGradient(dir,
        CreateColor(fR, fG, fB, fA),
        CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA)
    )

    -- Hide the old clip-frame gradient if it exists from a prior session
    if castBarFrame._gradClip then castBarFrame._gradClip:Hide() end
    castBarFrame._gradientFullBar = nil

    castBarFrame._nameText:SetParent(castBarFrame._textFrame)
    castBarFrame._timerText:SetParent(castBarFrame._textFrame)
else
    if castBarFrame._gradClip then
        castBarFrame._gradClip:Hide()
    end
    castBarFrame._gradientFullBar = nil

    castBarFrame._nameText:SetParent(castBarFrame._textFrame)
    castBarFrame._timerText:SetParent(castBarFrame._textFrame)

    do
        local fR, fG, fB, fA = cb.fillR, cb.fillG, cb.fillB, cb.fillA
        if cb.classColored then
            local cc = CLASS_COLORS[cachedClass]
            if cc then fR, fG, fB = cc[1], cc[2], cc[3] end
        end
        fillTex:SetVertexColor(fR, fG, fB, fA)
    end
end

    -- Spark
    local spark = castBarFrame._spark
    if cb.showSpark then
        spark:SetSize(8, h)
        spark:ClearAllPoints()
    
        if cb.gradientEnabled and castBarFrame._gradClip then
            spark:SetPoint("CENTER", castBarFrame._gradClip, "RIGHT", 0, 0)
        else
            spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
        end
    
        spark:Show()
    else
        spark:Hide()
    end

    -- Latency overlay: register/unregister event + style overlay based on setting
    if cb.latencyEnabled and _erbEventFrame then
        if not _latencyEventActive then
            _erbEventFrame:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
            _latencyEventActive = true
        end
        local lo = castBarFrame._latencyOverlay
        local lR, lG, lB, lA = cb.latencyR or 0.835, cb.latencyG or 0.290, cb.latencyB or 0.290, cb.latencyA or 1
        local texKey = cb.texture
        if texKey and texKey ~= "none" and texKey ~= "blizzard" then
            local texPath = EllesmereUI.ResolveTexturePath(CAST_BAR_TEXTURES, texKey, nil)
            if texPath then
                lo:SetTexture(texPath)
                lo:SetVertexColor(lR, lG, lB, lA)
            else
                lo:SetColorTexture(lR, lG, lB, lA)
            end
        else
            lo:SetColorTexture(lR, lG, lB, lA)
        end
    else
        if _latencyEventActive and _erbEventFrame then
            _erbEventFrame:UnregisterEvent("CURRENT_SPELL_CAST_CHANGED")
            _latencyEventActive = false
            _latencySendTime = nil
        end
        if castBarFrame._latencyOverlay then castBarFrame._latencyOverlay:Hide() end
        castBarFrame._latencySuffix = nil
    end
    -- Text width cap: use the bar's rendered width so width-matching
    -- and border insets are accounted for. Falls back to cb.width if
    -- the bar hasn't been laid out yet.
    local barW = bar:GetWidth()
    if not barW or barW < 10 then barW = cb.width end

    -- Timer text
    local timerText = castBarFrame._timerText
    if cb.showTimer then
        SetRBFont(timerText, GetRBFont(), cb.timerSize or 11)
        timerText:ClearAllPoints()
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4 + (cb.timerX or 0), cb.timerY or 0)
        timerText:Show()
    else
        timerText:Hide()
    end

    -- Spell name text
    local nameText = castBarFrame._nameText
    if cb.showSpellText then
        SetRBFont(nameText, GetRBFont(), cb.spellTextSize or 11)
        nameText:ClearAllPoints()
        nameText:SetPoint("LEFT", bar, "LEFT", 4 + (cb.spellTextX or 0), cb.spellTextY or 0)
        nameText:SetWidth(barW * (cb.showTimer and 0.88 or 0.95))
        nameText:Show()
    else
        nameText:Hide()
    end

    -- Hide pips when not empowering
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end

    -- Hide channel ticks when not channeling
    HideChannelTicks()

    -- Hide when not casting
    if not castBarFrame._casting and not castBarFrame._channeling and not castBarFrame._empowering then
        EllesmereUI.SetElementVisibility(castBarFrame, false)
    else
        castBarFrame:Show()
        EllesmereUI.SetElementVisibility(castBarFrame, true)
    end
end


-------------------------------------------------------------------------------
--  Channel tick marks
--  Shows vertical tick marks on the cast bar during channeled spells whose
--  spell ID appears in CHANNEL_TICK_DATA.  The penultimate tick (the last
--  safe point to chain/clip) is drawn slightly wider in gold.
--  Layout mirrors the empower pip code above for visual consistency.
-------------------------------------------------------------------------------
ShowChannelTicks = function(spellID)
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.showChannelTicks then return end

    local tickData = CHANNEL_TICK_DATA[spellID]
    local wantTicks = tickData and (cb.showTickMarks or cb.showLastTick)

    -- Nothing to draw: hide stale marks and bail
    if not wantTicks then
        for i = 1, #castBarFrame._ticks do
            castBarFrame._ticks[i]:Hide()
        end
        castBarFrame._numTicks = 0
        if castBarFrame._gcdMark then castBarFrame._gcdMark:Hide() end
        return
    end

    local bar = castBarFrame._bar
    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then return end

    -- Pixel-snap helpers (same approach as empower pips)
    local effectiveScale = bar:GetEffectiveScale()
    local pixelSize = 1 / effectiveScale
    local tickWidth = max(pixelSize, floor(2 * effectiveScale + 0.5) / effectiveScale)
    local highlightWidth = max(pixelSize, floor(3 * effectiveScale + 0.5) / effectiveScale)
    local snappedHeight = floor(barHeight * effectiveScale + 0.5) / effectiveScale

    -- Tick marks
    if wantTicks then
        local numTicks
        if tickData.tickInterval then
            local channelDuration = castBarFrame._endTime - castBarFrame._startTime
            if channelDuration > 0 then
                numTicks = floor(channelDuration / tickData.tickInterval)
            else
                numTicks = 0
            end
        else
            numTicks = tickData.ticks
            if tickData.modSpell and IsPlayerSpell(tickData.modSpell) then
                numTicks = tickData.modTicks
            end
        end

        -- Pre-read colors once outside the loop
        local showTickMarks = cb.showTickMarks
        local showLastTick = cb.showLastTick
        local tmR, tmG, tmB, tmA = cb.tickMarksR or 1.0, cb.tickMarksG or 1.0, cb.tickMarksB or 1.0, cb.tickMarksA or 0.7
        local ltR, ltG, ltB, ltA = cb.lastTickR or 1.0, cb.lastTickG or 0.82, cb.lastTickB or 0.0, cb.lastTickA or 0.95

        for i = 1, numTicks - 1 do
            local isLastTick = (i == numTicks - 1)

            if not showTickMarks and not isLastTick then
                if castBarFrame._ticks[i] then castBarFrame._ticks[i]:Hide() end
            else
                local tick = castBarFrame._ticks[i]
                if not tick then
                    tick = bar:CreateTexture(nil, "OVERLAY", nil, 3)
                    castBarFrame._ticks[i] = tick
                end

                local snappedOffset = floor(barWidth * (numTicks - i) / numTicks * effectiveScale + 0.5) / effectiveScale

                if isLastTick and showLastTick then
                    tick:SetColorTexture(ltR, ltG, ltB, ltA)
                    tick:SetSize(highlightWidth, snappedHeight)
                else
                    tick:SetColorTexture(tmR, tmG, tmB, tmA)
                    tick:SetSize(tickWidth, snappedHeight)
                end

                tick:ClearAllPoints()
                tick:SetPoint("CENTER", bar, "LEFT", snappedOffset, 0)
                tick:Show()
            end
        end

        -- Hide extras from a previous channel that had more ticks
        for i = max(1, numTicks), #castBarFrame._ticks do
            castBarFrame._ticks[i]:Hide()
        end

        castBarFrame._numTicks = numTicks
    else
        for i = 1, #castBarFrame._ticks do
            castBarFrame._ticks[i]:Hide()
        end
        castBarFrame._numTicks = 0
    end

    -- GCD boundary mark removed (UnitSpellHaste returns secret values in combat)
    if castBarFrame._gcdMark then castBarFrame._gcdMark:Hide() end
end

HideChannelTicks = function()
    if not castBarFrame or not castBarFrame._ticks then return end
    for i = 1, #castBarFrame._ticks do
        castBarFrame._ticks[i]:Hide()
    end
    castBarFrame._numTicks = 0
    if castBarFrame._gcdMark then
        castBarFrame._gcdMark:Hide()
    end
end


UpdateCastBar = function(dt)
    if not castBarFrame or not castBarFrame:IsShown() then return end
    local now = GetTime()
    local bar = castBarFrame._bar
    local cb = ERB.db.profile.castBar
    local showTimer = cb.showTimer

    local latSuffix = _latencyEventActive and castBarFrame._latencySuffix
    local totalDurMode = showTimer and cb.showTotalDuration
    -- Cache the " / X.X" suffix once per cast (total duration is constant)
    local totalSuffix = totalDurMode and castBarFrame._totalDurSuffix

    if castBarFrame._casting or castBarFrame._empowering then
        -- Safety: if cast/empower ran 1s past expected end, force stop.
        -- Catches missed EMPOWER_STOP events under network desync.
        if castBarFrame._endTime and now > castBarFrame._endTime + 1 then
            OnCastStop()
            return
        end
        local castDur = castBarFrame._endTime - castBarFrame._startTime
        local progress = (castDur > 0) and ((now - castBarFrame._startTime) / castDur) or 0
        progress = min(max(progress, 0), 1)
        bar:SetValue(progress)
        -- Size the gradient clip frame to match the fill width
        if castBarFrame._gradientFullBar and castBarFrame._gradClip then
            castBarFrame._gradClip:SetWidth(max(0.01, bar:GetWidth() * progress))
        end

        -- Apply empowered stage coloring if enabled
        if castBarFrame._empowering and cb.coloredEmpowerStages then
            local numStages = castBarFrame._numStages or 0
            local stage = GetCurrentEmpowerStage(progress, numStages)
            local r, g, b = GetEmpowerStageColor(stage, numStages)

            -- Apply color to bar or gradient
            if castBarFrame._gradientFullBar and castBarFrame._gradTex then
                empowerColorA:SetRGBA(r, g, b, 1)
                empowerColorB:SetRGBA(r, g, b, 1)
                castBarFrame._gradTex:SetGradient("HORIZONTAL", empowerColorA, empowerColorB)
            else
                bar:GetStatusBarTexture():SetVertexColor(r, g, b, 1)
            end
            castBarFrame._empowerColorApplied = true
        end

        if showTimer then
            local remaining = castBarFrame._endTime - now
            if remaining > 0 then
                if totalDurMode then
                    local elapsed = now - castBarFrame._startTime
                    castBarFrame._timerText:SetText(format("%.1f", elapsed) .. (totalSuffix or ""))
                elseif latSuffix then
                    castBarFrame._timerText:SetText(format("%.1f", remaining) .. latSuffix)
                else
                    castBarFrame._timerText:SetText(format("%.1f", remaining))
                end
            else
                castBarFrame._timerText:SetText("")
            end
        end
    elseif castBarFrame._channeling then
        local chanDur = castBarFrame._endTime - castBarFrame._startTime
        local progress = (chanDur > 0) and ((castBarFrame._endTime - now) / chanDur) or 0
        progress = min(max(progress, 0), 1)
        bar:SetValue(progress)
        -- Size the gradient clip frame to match the fill width
        if castBarFrame._gradientFullBar and castBarFrame._gradClip then
            castBarFrame._gradClip:SetWidth(max(0.01, bar:GetWidth() * progress))
        end
        if showTimer then
            local remaining = castBarFrame._endTime - now
            if remaining > 0 then
                if totalDurMode then
                    local elapsed = now - castBarFrame._startTime
                    castBarFrame._timerText:SetText(format("%.1f", elapsed) .. (totalSuffix or ""))
                elseif latSuffix then
                    castBarFrame._timerText:SetText(format("%.1f", remaining) .. latSuffix)
                else
                    castBarFrame._timerText:SetText(format("%.1f", remaining))
                end
            else
                castBarFrame._timerText:SetText("")
            end
        end
    end

    -- Update spark position
    if castBarFrame._spark:IsShown() then
        castBarFrame._spark:ClearAllPoints()
    
        if castBarFrame._gradientFullBar and castBarFrame._gradClip and castBarFrame._gradClip:IsShown() then
            castBarFrame._spark:SetPoint("CENTER", castBarFrame._gradClip, "RIGHT", 0, 0)
        else
            castBarFrame._spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
        end
    end
end

-------------------------------------------------------------------------------
--  Latency overlay helper
--  Called once per cast/channel start.  Measures actual per-spell latency
--  (time between spell button press and server confirmation) and sizes the
--  overlay as that fraction of the total cast duration.
-------------------------------------------------------------------------------
local function ShowLatencyOverlay(castType)
    if not castBarFrame then return end
    local overlay = castBarFrame._latencyOverlay
    if not overlay then return end

    local cb = ERB.db.profile.castBar
    local sendTime = _latencySendTime
    _latencySendTime = nil  -- consumed regardless of outcome

    -- Bail early: feature off, no timestamp, or bad timing
    if not cb.latencyEnabled or not sendTime then
        overlay:Hide(); castBarFrame._latencySuffix = nil; return
    end

    local latencySec = min(GetTime() - sendTime, 0.4)  -- cap 400ms
    local castDur = castBarFrame._endTime - castBarFrame._startTime
    local barWidth = castBarFrame._bar:GetWidth()

    if latencySec <= 0 or castDur <= 0 or latencySec >= castDur or barWidth <= 0 then
        overlay:Hide(); castBarFrame._latencySuffix = nil; return
    end

    -- Build the suffix string once; reused every frame by UpdateCastBar
    if cb.latencyShowText then
        castBarFrame._latencySuffix = " (" .. floor(latencySec * 1000 + 0.5) .. "ms)"
    else
        castBarFrame._latencySuffix = nil
    end

    local clip = castBarFrame._barClip
    overlay:ClearAllPoints()
    if castType == "channel" then
        overlay:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, 0)
    else
        overlay:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    end
    overlay:SetWidth(barWidth * (latencySec / castDur))
    overlay:Show()
end

local function HideLatencyOverlay()
    if not castBarFrame then return end
    if castBarFrame._latencyOverlay then castBarFrame._latencyOverlay:Hide() end
    castBarFrame._latencySuffix = nil
end

OnCastStart = function()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.enabled then return end

    local name, _, _, startTimeMS, endTimeMS, _, _, notInterruptible, spellID, barID = UnitCastingInfo("player")
    if not name then return end

    castBarFrame._casting = true
    castBarFrame._channeling = false
    castBarFrame._empowering = false
    castBarFrame._castID = barID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
    castBarFrame._nameText:SetText(name)
    castBarFrame._bar:SetValue(0)

    -- Hide empower pips
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do castBarFrame._pips[i]:Hide() end
    end
    castBarFrame._numStages = 0
    HideChannelTicks()

    -- Icon
    do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    if _latencyEventActive then ShowLatencyOverlay("cast") end

    castBarFrame:Show()
    EllesmereUI.SetElementVisibility(castBarFrame, true)
end

OnChannelStart = function()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.enabled then return end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellID, _, _, channelCastID = UnitChannelInfo("player")
    if not name then
        -- UnitChannelInfo can be empty on rapid channel restarts (e.g. SCK spam).
        -- Single retry on the next frame; if still nil the channel was cancelled.
        if not castBarFrame._channelRetry then
            castBarFrame._channelRetry = true
            C_Timer.After(0, function()
                castBarFrame._channelRetry = nil
                OnChannelStart()
            end)
        end
        return
    end

    castBarFrame._casting = false
    castBarFrame._channeling = true
    castBarFrame._empowering = false
    castBarFrame._castID = channelCastID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
    castBarFrame._nameText:SetText(name)
    castBarFrame._bar:SetValue(1)

    -- Hide empower pips
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do castBarFrame._pips[i]:Hide() end
    end
    castBarFrame._numStages = 0

    -- Icon
    do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    -- Channel tick marks
    ShowChannelTicks(spellID)

    if _latencyEventActive then ShowLatencyOverlay("channel") end

    castBarFrame:Show()
    EllesmereUI.SetElementVisibility(castBarFrame, true)
end

OnChannelUpdate = function()
    if not castBarFrame then return end
    if not castBarFrame._channeling then return end

    local name, _, _, startTimeMS, endTimeMS, _, _, spellID = UnitChannelInfo("player")
    if not name then return end

    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000

    -- Recompute tick mark and GCD boundary positions for new duration
    if spellID then ShowChannelTicks(spellID) end
end

-- Called for UNIT_SPELLCAST_STOP only (normal cast completion).
-- Ignores the event if the castID doesn't match the active cast -- this
-- prevents hiding the bar when a new cast has already started.
local function OnCastComplete(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._casting then return end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then return end
    castBarFrame._casting = false
    castBarFrame._castID = nil
    EllesmereUI.SetElementVisibility(castBarFrame, false)
end

-- Called for UNIT_SPELLCAST_FAILED / INTERRUPTED.
-- These fire for the spell that FAILED, which may be a completely different
-- spell than the one currently being cast (e.g. pressing an instant while
-- casting). Only hide if the castID matches our active cast.
local function OnCastFailed(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._casting then return end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then return end
    castBarFrame._casting = false
    castBarFrame._castID = nil
    EllesmereUI.SetElementVisibility(castBarFrame, false)
end

-- Called for UNIT_SPELLCAST_CHANNEL_STOP.
local function OnChannelStop(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._channeling then return end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then return end
    castBarFrame._channeling = false
    castBarFrame._castID = nil
    HideChannelTicks()
    EllesmereUI.SetElementVisibility(castBarFrame, false)
end

-- Called for UNIT_SPELLCAST_EMPOWER_STOP.
local function OnEmpowerStop(eventCastID)
    if not castBarFrame then return end
    if not castBarFrame._empowering then return end
    -- Accept any empower stop while we're empowering. Strict castID
    -- matching can reject valid stops due to event desync under load.
    castBarFrame._empowering = false
    castBarFrame._castID = nil
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end
    castBarFrame._numStages = 0

    -- Reset empower stage coloring if it was applied
    if castBarFrame._empowerColorApplied then
        castBarFrame._empowerColorApplied = false
        local cb = ERB.db.profile.castBar
        local fR, fG, fB, fA = cb.fillR, cb.fillG, cb.fillB, cb.fillA
        if cb.classColored then
            local cc = CLASS_COLORS[cachedClass]
            if cc then fR, fG, fB = cc[1], cc[2], cc[3] end
        end
        if castBarFrame._gradientFullBar and castBarFrame._gradTex then
            empowerColorA:SetRGBA(fR, fG, fB, fA)
            empowerColorB:SetRGBA(cb.gradientR or fR, cb.gradientG or fG, cb.gradientB or fB, cb.gradientA or fA)
            castBarFrame._gradTex:SetGradient(cb.gradientDir or "HORIZONTAL", empowerColorA, empowerColorB)
        else
            local fillTex = castBarFrame._bar:GetStatusBarTexture()
            fillTex:SetVertexColor(fR, fG, fB, fA)
        end
    end
    cachedStageThresholds = nil

    EllesmereUI.SetElementVisibility(castBarFrame, false)
end

OnCastStop = function()
    if not castBarFrame then return end
    castBarFrame._casting = false
    castBarFrame._channeling = false
    castBarFrame._empowering = false
    castBarFrame._castID = nil
    -- Hide pip textures
    if castBarFrame._pips then
        for i = 1, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end
    castBarFrame._numStages = 0
    HideChannelTicks()
    if _latencyEventActive then HideLatencyOverlay() end
    EllesmereUI.SetElementVisibility(castBarFrame, false)
end


OnEmpowerStart = function()
    if not castBarFrame then return end
    local cb = ERB.db.profile.castBar
    if not cb.enabled then return end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellID, empowering, _, empowerCastID = UnitChannelInfo("player")
    if not name or not empowering then return end

    -- Add hold-at-max time to the end
    local holdAtMax = GetUnitEmpowerHoldAtMaxTime("player")
    endTimeMS = endTimeMS + holdAtMax

    castBarFrame._casting = false
    castBarFrame._channeling = false
    castBarFrame._empowering = true
    castBarFrame._castID = empowerCastID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
    if _latencyEventActive then HideLatencyOverlay() end
    castBarFrame._nameText:SetText(name)
    castBarFrame._bar:SetValue(0)
    HideChannelTicks()

    -- Icon
    do
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    -- Stage pips (hash marks) -- pixel-perfect positioning
    local stages = UnitEmpoweredStagePercentages("player")
    -- Cache cumulative thresholds for per-frame stage color lookup
    if stages then
        cachedStageThresholds = {}
        local cum = 0
        for i = 1, #stages do
            cum = cum + stages[i]
            cachedStageThresholds[i] = cum
        end
    else
        cachedStageThresholds = nil
    end
    if stages then
        local bar = castBarFrame._bar
        local barWidth = bar:GetWidth()
        local barHeight = bar:GetHeight()
        local numStages = #stages
        castBarFrame._numStages = numStages

        -- Compute the effective scale so we can snap to physical pixels
        local effectiveScale = bar:GetEffectiveScale()
        local pixelSize = 1 / effectiveScale          -- 1 physical pixel in UI units
        local pipWidth = max(pixelSize, floor(2 * effectiveScale + 0.5) / effectiveScale) -- at least 1px, target ~2px

        -- Position a pip at each stage boundary (skip the last -- it's the bar end)
        local lastOffset = 0
        for i = 1, numStages - 1 do
            local pip = castBarFrame._pips[i]
            if not pip then
                pip = bar:CreateTexture(nil, "OVERLAY", nil, 2)
                pip:SetColorTexture(1, 1, 1, 0.85)
                castBarFrame._pips[i] = pip
            end
            local rawOffset = lastOffset + (barWidth * stages[i])
            lastOffset = rawOffset
            -- Snap offset to nearest physical pixel
            local snappedOffset = floor(rawOffset * effectiveScale + 0.5) / effectiveScale
            local snappedHeight = floor(barHeight * effectiveScale + 0.5) / effectiveScale
            pip:SetSize(pipWidth, snappedHeight)
            pip:ClearAllPoints()
            pip:SetPoint("CENTER", bar, "LEFT", snappedOffset, 0)
            pip:Show()
        end

        -- Hide any extra pips from a previous cast with more stages
        for i = numStages, #castBarFrame._pips do
            castBarFrame._pips[i]:Hide()
        end
    end

    castBarFrame:Show()
    EllesmereUI.SetElementVisibility(castBarFrame, true)
end

OnEmpowerUpdate = function()
    if not castBarFrame then return end
    if not castBarFrame._empowering then return end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellID, empowering = UnitChannelInfo("player")
    if not name or not empowering then return end

    local holdAtMax = GetUnitEmpowerHoldAtMaxTime("player")
    endTimeMS = endTimeMS + holdAtMax

    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
end

-------------------------------------------------------------------------------
--  Totem Bar
--  Reparents Blizzard TotemFrame, repositions buttons in a clean row, and
--  adds overlay border frames (our own frames, never written to Blizzard).
-------------------------------------------------------------------------------
local function GetTotemSettings()
    return ERB.db and ERB.db.profile and ERB.db.profile.totemBar
end

-- Cached layout state to avoid redundant work on every Update hook
local _totemLayoutCache = {}
local _totemActiveSet = {}  -- reusable set for O(1) cleanup lookups

local function LayoutTotemBar()
    if not totemBarFrame or not TotemFrame then return end
    local tb = GetTotemSettings()
    if not tb or not tb.enabledClasses then return end

    local spacing = tb.spacing or 2
    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.Snap then spacing = PP.Snap(spacing) end
    local iconSize = tb.iconSize or 30

    -- Use SetScale on TotemFrame rather than SetSize on individual buttons.
    -- Buttons keep their native template size; scale controls visual size.
    local nativeSize = 37
    local iconScale = iconSize / nativeSize

    -- Reparent and position TotemFrame every call (Blizzard's Update can reset these)
    TotemFrame:SetParent(totemBarFrame)
    TotemFrame:SetFrameStrata("HIGH")
    TotemFrame:ClearAllPoints()
    TotemFrame:SetPoint("LEFT", totemBarFrame, "LEFT", 0, 0)
    TotemFrame:Show()

    -- Only re-apply scale when setting changed
    local cache = _totemLayoutCache
    if cache.iconScale ~= iconScale then
        TotemFrame:SetScale(iconScale)
        cache.iconScale = iconScale
    end

    -- Collect active totem buttons (reuse table)
    local buttons = cache.buttons
    if not buttons then buttons = {}; cache.buttons = buttons end
    local count = 0
    for _, child in ipairs({ TotemFrame:GetChildren() }) do
        if child:IsShown() and child.Icon and child:GetObjectType() == "Button" then
            count = count + 1
            buttons[count] = child
        end
    end
    -- Trim stale entries
    for i = count + 1, #buttons do buttons[i] = nil end

    local scaledSpacing = spacing / iconScale
    local zoom = 0.055
    local timerSize = tb.timerSize or 11
    local scaledTimerSize = math.max(6, math.floor(timerSize / iconScale + 0.5))
    local fontPath = EllesmereUI.GetFont and EllesmereUI.GetFont() or STANDARD_TEXT_FONT
    local outlineMode = EllesmereUI.GetOutline and EllesmereUI.GetOutline() or "OUTLINE"

    wipe(_totemActiveSet)
    for i, btn in ipairs(buttons) do
        _totemActiveSet[btn] = true

        btn:ClearAllPoints()
        if i == 1 then
            btn:SetPoint("LEFT", TotemFrame, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", buttons[i - 1], "RIGHT", scaledSpacing, 0)
        end

        -- Hide Blizzard's circular border
        if btn.Border then btn.Border:Hide() end

        -- Make Icon frame fill the entire button
        if btn.Icon then
            btn.Icon:ClearAllPoints()
            btn.Icon:SetAllPoints(btn)
        end

        -- Square the icon: remove circular mask
        if btn.Icon and btn.Icon.Texture and btn.Icon.TextureMask then
            btn.Icon.Texture:RemoveMaskTexture(btn.Icon.TextureMask)
            btn.Icon.TextureMask:Hide()
        end
        if btn.Icon and btn.Icon.Cooldown and btn.Icon.TextureMask then
            pcall(btn.Icon.Cooldown.RemoveMaskTexture, btn.Icon.Cooldown, btn.Icon.TextureMask)
        end

        -- Apply icon zoom crop
        if btn.Icon and btn.Icon.Texture then
            btn.Icon.Texture:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end

        -- Timer text
        if btn.Duration then
            if tb.showTimer then
                btn.Duration:SetTextColor(1, 1, 1, 1)
            else
                btn.Duration:SetTextColor(0, 0, 0, 0)
            end
            btn.Duration:SetFont(fontPath, scaledTimerSize, outlineMode)
            btn.Duration:SetDrawLayer("OVERLAY", 7)
            btn.Duration:ClearAllPoints()
            btn.Duration:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.Duration:SetJustifyH("CENTER")
            btn.Duration:SetJustifyV("MIDDLE")
        end

        -- Border overlay (our own frame in the button's scale space)
        local overlay = _totemBorderOverlays[btn]
        if not overlay then
            overlay = CreateFrame("Frame", nil, btn)
            _totemBorderOverlays[btn] = overlay
        end
        -- "Show Behind": +3 in front of the icon, level-1 behind it.
        overlay:SetFrameLevel(tb.borderBehind and math.max(0, btn:GetFrameLevel() - 1) or (btn:GetFrameLevel() + 3))
        overlay:ClearAllPoints()
        overlay:SetAllPoints(btn.Icon or btn)
        overlay:Show()
        local bs = tb.borderSize or 0
        local texKey = tb.borderTexture or "solid"
        EllesmereUI.ApplyBorderStyle(overlay, bs,
            tb.borderR or 0, tb.borderG or 0, tb.borderB or 0, tb.borderA or 1,
            texKey, tb.borderTextureOffset, tb.borderTextureOffsetY,
            tb.borderTextureShiftX, tb.borderTextureShiftY, "resourcebars", bs)
    end

    -- Hide overlays for buttons no longer active (O(n) via set lookup)
    for btn, overlay in pairs(_totemBorderOverlays) do
        if not _totemActiveSet[btn] then overlay:Hide() end
    end

    -- Size container
    local maxButtons = 5
    local maxW = iconSize * maxButtons + spacing * (maxButtons - 1)
    totemBarFrame:SetSize(maxW, iconSize)
end

local function BuildTotemBar()
    local tb = GetTotemSettings()
    if not tb then return end

    -- enabledClasses nil = disabled; table with class keys = enabled for those classes
    local ec = tb.enabledClasses
    local _, classFile = UnitClass("player")
    local active = ec and classFile and ec[classFile]

    if not active then
        if totemBarFrame then
            EllesmereUI.SetElementVisibility(totemBarFrame, false)
        end
        -- Restore TotemFrame to original parent
        if TotemFrame and _totemOrigParent and not InCombatLockdown() then
            TotemFrame:SetParent(_totemOrigParent)
            TotemFrame:ClearAllPoints()
            TotemFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 155)
        end
        return
    end

    if not totemBarFrame then
        totemBarFrame = CreateFrame("Frame", "ERB_TotemBarFrame", UIParent)
        local tb = ERB.db and ERB.db.profile and ERB.db.profile.totemBar
        totemBarFrame:SetFrameStrata(tb and tb.frameStrata or "MEDIUM")
        totemBarFrame:SetFrameLevel(15)
        totemBarFrame:SetSize(120, 30)
        -- Re-register unlock elements so unlock mode picks up the new frame
        if _G._ERB_RegisterUnlock then _G._ERB_RegisterUnlock() end
    end

    -- Save original parent for restore on disable
    if TotemFrame and not _totemOrigParent then
        _totemOrigParent = TotemFrame:GetParent()
    end

    -- Position our container
    if tb.unlockPos and tb.unlockPos.point then
        if not EllesmereUI._unlockActive then
            local PP = EllesmereUI and EllesmereUI.PP
            local px, py = tb.unlockPos.x or 0, tb.unlockPos.y or 0
            if PP and PP.SnapForES then
                local es = totemBarFrame:GetEffectiveScale()
                px = PP.SnapForES(px, es)
                py = PP.SnapForES(py, es)
            end
            totemBarFrame:ClearAllPoints()
            totemBarFrame:SetPoint(tb.unlockPos.point, UIParent,
                tb.unlockPos.relPoint or tb.unlockPos.point, px, py)
        end
    else
        if not EllesmereUI._unlockActive then
            totemBarFrame:ClearAllPoints()
            -- Default: left-aligned 5px below the player unit frame
            local playerUF = _G["oUF_EllesmerePlayer"]
            if playerUF and playerUF:IsShown() then
                totemBarFrame:SetPoint("TOPLEFT", playerUF, "BOTTOMLEFT", 0, -5)
            else
                totemBarFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
            end
        end
    end

    EllesmereUI.SetElementVisibility(totemBarFrame, true)

    -- Invalidate layout cache so next LayoutTotemBar re-applies scale
    _totemLayoutCache.iconScale = nil
    _totemLayoutCache.spacing = nil

    -- Hook Blizzard updates (once)
    if not _totemHooked and TotemFrame then
        _totemHooked = true
        local function OnTotemUpdate()
            local s = GetTotemSettings()
            if s and s.enabledClasses then LayoutTotemBar() end
        end
        hooksecurefunc(TotemFrame, "Update", OnTotemUpdate)
        TotemFrame:HookScript("OnShow", OnTotemUpdate)
        if TotemButtonMixin then
            hooksecurefunc(TotemButtonMixin, "OnLoad", function()
                C_Timer.After(0, OnTotemUpdate)
            end)
        end
    end

    LayoutTotemBar()
end

-------------------------------------------------------------------------------
--  Master Apply
-------------------------------------------------------------------------------
function ERB:ApplyAll()
    local _, classFile = UnitClass("player")
    cachedClass = classFile
    cachedPrimary = GetPrimaryPowerType()
    cachedSecondary = GetSecondaryResource()

    BuildMainFrame()
    BuildBars()
    BuildCastBar()
    BuildTotemBar()

    -- Apply frame strata to all existing bar frames (covers live changes)
    local g = ERB.db.profile.general or DEFAULTS.profile.general
    local barStrata = g.frameStrata or "MEDIUM"
    if mainFrame then mainFrame:SetFrameStrata(barStrata) end
    if healthBar then healthBar:SetFrameStrata(barStrata) end
    if primaryBar then primaryBar:SetFrameStrata(barStrata) end
    if secondaryFrame then secondaryFrame:SetFrameStrata(barStrata) end
    local tb = ERB.db.profile.totemBar
    if totemBarFrame then totemBarFrame:SetFrameStrata(tb and tb.frameStrata or "MEDIUM") end
    local cb = ERB.db.profile.castBar
    if castBarFrame then castBarFrame:SetFrameStrata(cb and cb.frameStrata or "MEDIUM") end
    UpdateHealthBar()
    UpdatePrimaryBar()
    UpdateSecondaryResource()
    UpdateVisibility()

    -- Vehicle proxy: hide resource bars during full vehicle UI ([vehicleui] condition)
    -- Secure frame creation + RegisterStateDriver both need to happen outside combat
    if not ERB._vehicleProxy then
        local function InitVehicleProxy()
            if ERB._vehicleProxy then return end
            ERB._vehicleProxy = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
            ERB._vehicleProxy:SetAttribute("_onstate-erbvehicle", [[
                self:CallMethod("OnVehicleStateChanged", newstate)
            ]])
            ERB._vehicleProxy.OnVehicleStateChanged = function(_, state)
                ERB._inVehicle = (state == "hide")
                UpdateVisibility()
            end
            RegisterStateDriver(ERB._vehicleProxy, "erbvehicle", "[vehicleui][petbattle] hide; show")
        end
        if InCombatLockdown() then
            local waiter = CreateFrame("Frame")
            waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
            waiter:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                self:SetScript("OnEvent", nil)
                InitVehicleProxy()
            end)
        else
            InitVehicleProxy()
        end
    end
end

local function ScheduleRosterApply()
    if EllesmereUI and EllesmereUI.InvalidateFrameCache then
        EllesmereUI.InvalidateFrameCache()
    end
    C_Timer.After(0.2, function()
        ERB:ApplyAll()
    end)
end


-------------------------------------------------------------------------------
--  Event handling
-------------------------------------------------------------------------------
local function OnEvent(self, event, ...)
    if event == "UNIT_HEALTH" then
        UpdateHealthBar()
        -- Stagger is based on health, so update secondary resource too
        if cachedSecondary and cachedSecondary.power == "BREWMASTER_STAGGER" then
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        local unit, powerToken = ...
        if unit == "player" then
            UpdatePrimaryBar()
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_MAXHEALTH" then
        UpdateHealthBar()
        -- Stagger / Ignore Pain max derives from player max health
        if cachedSecondary and (cachedSecondary.power == "BREWMASTER_STAGGER"
           or cachedSecondary.power == "IGNOREPAIN_BAR") then
            local newMax = UnitHealthMax("player") or 1
            if not issecretvalue or not issecretvalue(newMax) then
                if cachedSecondary.power == "IGNOREPAIN_BAR" then
                    newMax = newMax * IP.CAP
                end
                if newMax > 0 and newMax ~= cachedSecondary.max then
                    cachedSecondary.max = newMax
                    BuildBars()
                end
            end
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        -- Drives the Prot Ignore Pain bar; no-op for everyone else.
        if cachedSecondary and cachedSecondary.power == "IGNOREPAIN_BAR" then
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_MAXPOWER" then
        -- Re-check secondary resource in case max changed (e.g. talent-based pip count)
        local newSec = GetSecondaryResource()
        local oldMax = cachedSecondary and cachedSecondary.max
        local newMax = newSec and newSec.max
        if oldMax ~= newMax then
            cachedSecondary = newSec
            BuildBars()
        end
        UpdatePrimaryBar()
        UpdateSecondaryResource()
    elseif event == "RUNE_POWER_UPDATE" then
        UpdateSecondaryResource()
    elseif event == "UNIT_POWER_POINT_CHARGE" then
        UpdateSecondaryResource()
    elseif event == "PLAYER_REGEN_DISABLED" then
        isInCombat = true
        UpdateVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        isInCombat = false
        UpdateVisibility()
        -- Clean up Whirlwind GUID cache on combat end
        if EllesmereUI and EllesmereUI.HandleWhirlwindStacks then
            EllesmereUI.HandleWhirlwindStacks(event)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateVisibility()
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        UpdateVisibility()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- Re-check secondary max power: UnitPowerMax can change across zone
        -- transitions (e.g. Prot Paladin holy power reporting 3 vs 5).
        -- UNIT_MAXPOWER doesn't always fire reliably on zone change.
        local newSec = GetSecondaryResource()
        local oldMax = cachedSecondary and cachedSecondary.max
        local newMax = newSec and newSec.max
        if oldMax ~= newMax then
            cachedSecondary = newSec
            BuildBars()
        end
        UpdateVisibility()
    elseif event == "GROUP_ROSTER_UPDATE" then
        UpdateVisibility()
        ScheduleRosterApply()
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        _essenceNextTick = nil
        _essenceLastCount = nil
        _essenceTickDur = 0
        _ebonMightExpiry = 0
        _ebonMightThrottle = 0
        wipe(ironfurTicks)
        ironfurGoEUntil = 0
        ironfurBaseDur = IronfurBaseDuration()
        IP.hashEndTime = 0
        cachedPrimary = GetPrimaryPowerType()
        cachedSecondary = GetSecondaryResource()
        BuildBars()
        BuildCastBar()
        UpdatePrimaryBar()
        UpdateSecondaryResource()
        UpdateVisibility()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        cachedPrimary = GetPrimaryPowerType()
        cachedSecondary = GetSecondaryResource()
        BuildBars()
        UpdatePrimaryBar()
        UpdateSecondaryResource()
        UpdateVisibility()
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            if cachedPrimary == "EBON_MIGHT" then UpdatePrimaryBar() end
            if cachedSecondary and cachedSecondary.type == "custom" then
                UpdateSecondaryResource()
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Route to manual resource trackers (12.0+ secret-value safe)
        local unit, castGUID, spellID = ...
        if unit == "player" then
            HandleIronfurCast(spellID)
            IP.HandleCast(spellID)
            if EllesmereUI then
                if EllesmereUI.HandleTipOfTheSpear then
                    EllesmereUI.HandleTipOfTheSpear(event, unit, castGUID, spellID)
                end
                if EllesmereUI.HandleWhirlwindStacks then
                    EllesmereUI.HandleWhirlwindStacks(event, unit, castGUID, spellID)
                end
            end
            if cachedSecondary and (cachedSecondary.type == "custom"
               or cachedSecondary.power == "IRONFUR_BAR") then
                UpdateSecondaryResource()
            end
        end
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
        -- Reset manual trackers on death/resurrect
        wipe(ironfurTicks)
        ironfurGoEUntil = 0
        IP.hashEndTime = 0
        if EllesmereUI then
            if EllesmereUI.HandleTipOfTheSpear then
                EllesmereUI.HandleTipOfTheSpear(event)
            end
            if EllesmereUI.HandleWhirlwindStacks then
                EllesmereUI.HandleWhirlwindStacks(event)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            ERB:ApplyAll()
            RegisterUnlockElements()
        end)
    elseif event == "CURRENT_SPELL_CAST_CHANGED" then
        _latencySendTime = GetTime()
    elseif event == "UNIT_SPELLCAST_START" then
        local unit = ...
        if unit == "player" then OnCastStart() end
    elseif event == "UNIT_SPELLCAST_STOP" then
        local unit, _, _, castID = ...
        if unit == "player" then OnCastComplete(castID) end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        -- args: unit, castGUID, spellID, castID
        local unit, _, _, castID = ...
        if unit == "player" then OnCastFailed(castID) end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- args: unit, castGUID, spellID, interruptedBy, castID
        local unit, _, _, _, castID = ...
        if unit == "player" then OnCastFailed(castID) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit = ...
        if unit == "player" then OnChannelStart() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        local unit = ...
        if unit == "player" then OnChannelUpdate() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- args: unit, castGUID, spellID, interruptedBy, castID
        local unit, _, _, _, castID = ...
        if unit == "player" then OnChannelStop(castID) end
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        local unit = ...
        if unit == "player" then OnEmpowerStart() end
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- args: unit, castGUID, spellID, empowerComplete, interruptedBy, castID
        local unit, _, _, _, _, castID = ...
        if unit == "player" then OnEmpowerStop(castID) end
    elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        local unit = ...
        if unit == "player" then OnEmpowerUpdate() end
    end
end


-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
function ERB:OnInitialize()
    self.db = EllesmereUI.Lite.NewDB("EllesmereUIResourceBarsDB", DEFAULTS, true)

    _G._ERB_AceDB = self.db
    _G._ERB_Apply = function() ERB:ApplyAll() end
    -- Unlock mode / EUI options panel: temporarily render the power bar at its
    -- true stored height (no expand) so movers and getSize see the real size.
    -- RUNTIME-ONLY suppression via EllesmereUI._erbExpandSuppressed -- it NEVER
    -- writes the saved primary.expandIfNoResource setting.
    --
    -- The old version mutated the saved bool, which the toggle's getValue reads
    -- and the Lite DB persists verbatim: opening the panel made the toggle read
    -- OFF, a missed restore on /reload or logout stranded the setting false on
    -- disk (no recovery without a manual re-toggle), and profile swaps wrote the
    -- flag onto the wrong profile. This mirrors the shift provider below, which
    -- computes its effect from live state and never writes the saved value.
    --
    -- The ApplyAll gate also checks EllesmereUI._unlockActive directly, so the
    -- panel->unlock transition stays suppressed even if this flag races (e.g. the
    -- unlock-open animation fires the panel OnHide and clears the flag while
    -- _unlockActive is still true).
    _G._ERB_SuppressExpand = function()
        EllesmereUI._erbExpandSuppressed = true
        ERB:ApplyAll()
    end
    _G._ERB_RestoreExpand = function()
        EllesmereUI._erbExpandSuppressed = false
        ERB:ApplyAll()
    end
    _G._ERB_GetSecondaryResource = GetSecondaryResource
    _G._ERB_CalcPipGeometry = CalcPipGeometry
    _G._ERB_GetPrimaryPowerType = GetPrimaryPowerType
    _G._ERB_PowerColors = POWER_COLORS

    -- "Shift Elements if No Resource": a direction signal the shared anchor
    -- engine consults to temporarily move elements anchored to the class
    -- resource bar when the spec has no class resource. Visual-only; never
    -- written to saved positions. Direction the shift WOULD apply (ignores
    -- unlock state): +1 = Up, -1 = Down, 0 = none.
    local function ResolveShiftDir()
        local sp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
        if not sp or not sp.enabled then return 0 end
        local mode = sp.shiftElementsIfNoResource
        if mode ~= "Up" and mode ~= "Down" then return 0 end
        if GetSecondaryResource() then return 0 end
        return (mode == "Up") and 1 or -1
    end
    -- Consulted inside ApplyAnchorPosition. Returns 0 while unlock mode is
    -- active so the layout shows normal (and movers capture true positions).
    EllesmereUI._GetAnchorTargetShiftDir = function(targetKey, childKey)
        if targetKey ~= "ERB_ClassResource" then return 0 end
        if EllesmereUI._unlockActive then return 0 end
        return ResolveShiftDir()
    end
    -- Whether a shift WOULD apply outside unlock mode (unlock entry uses this to
    -- decide whether to un-shift before snapshotting positions). None = false.
    _G._ERB_ShiftWantsApply = function() return ResolveShiftDir() ~= 0 end
    -- Re-apply the shift after unlock mode closes (PropagateAnchorChain is a
    -- no-op while unlocked, so this runs on exit). Gated so None = zero work.
    _G._ERB_RestoreShift = function()
        if ResolveShiftDir() ~= 0 and EllesmereUI.PropagateAnchorChain then
            EllesmereUI.PropagateAnchorChain("ERB_ClassResource")
        end
    end

    BuildBarTypeSpecMap()

    AppendSharedMediaTextures()
end

function ERB:OnEnable()
    local eventFrame = CreateFrame("Frame")
    _erbEventFrame = eventFrame
    eventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    -- Visibility option events
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:SetScript("OnUpdate", OnUpdate)

    -- Apply immediately at PLAYER_LOGIN so positions are set before combat
    -- lockdown blocks ApplySavedPositions. The PLAYER_ENTERING_WORLD handler
    -- will re-apply after the full game state is available.
    ERB:ApplyAll()
    RegisterUnlockElements()

    -- Collapse/restore expandIfNoResource when EUI options panel opens/closes
    if EllesmereUI.RegisterOnShow then
        EllesmereUI:RegisterOnShow(function()
            if _G._ERB_SuppressExpand then _G._ERB_SuppressExpand() end
        end)
    end
    if EllesmereUI.RegisterOnHide then
        EllesmereUI:RegisterOnHide(function()
            if _G._ERB_RestoreExpand then _G._ERB_RestoreExpand() end
        end)
    end
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
SLASH_ERB1 = "/erb"
SLASH_ERB2 = "/ellesresource"
SlashCmdList.ERB = function(msg)
    if msg == "lock" or msg == "unlock" then
        -- Unlock mode is now handled by the shared EllesmereUI system
        if EllesmereUI and EllesmereUI.ToggleUnlockMode then
            EllesmereUI:ToggleUnlockMode()
        end
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    if EllesmereUI and EllesmereUI.ShowModule then
        EllesmereUI:ShowModule("EllesmereUIResourceBars")
    end
end
