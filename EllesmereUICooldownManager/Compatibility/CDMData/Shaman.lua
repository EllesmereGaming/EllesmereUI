local addonName, ns = ...

if not C_CooldownViewer or not C_CooldownViewer.RegisterDefinition then return end

local CDM_CATEGORY_ESSENTIAL = 1
local CDM_CATEGORY_UTILITY   = 2
local CDM_CATEGORY_BUFF_ICON = 3
local CDM_CATEGORY_BUFF_BAR  = 4

local function HasLearnedTalent(tabIndex, talentIndex)
    if not GetTalentInfo or not GetNumTalentTabs or not GetNumTalents then
        return false
    end
    if tabIndex > GetNumTalentTabs() or talentIndex > GetNumTalents(tabIndex) then
        return false
    end
    local _, _, _, _, rank = GetTalentInfo(tabIndex, talentIndex)
    return (rank or 0) > 0
end

-- Shaman = class 07. Cooldowns = 107XXX, Buffs/Procs = 207XXX.

local function Register(def)
    def.class = "SHAMAN"
    C_CooldownViewer.RegisterDefinition(def)
end

-- Major cooldowns
Register({
    key = "shaman.bloodlust",
    cooldownID = 107001,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 10,
    spellID = 2825,
    iconSpellID = 2825,
    trackingType = "cooldown",
})

Register({
    key = "shaman.heroism",
    cooldownID = 107002,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 11,
    spellID = 32182,
    iconSpellID = 32182,
    trackingType = "cooldown",
})

Register({
    key = "shaman.elemental_mastery",
    cooldownID = 107003,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 20,
    spellID = 16166,
    iconSpellID = 16166,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 16) -- Elemental: Elemental Mastery
        end,
        resolveSpellID = function()
            return 16166
        end,
    },
})

Register({
    key = "shaman.thunderstorm",
    cooldownID = 107004,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 30,
    spellID = 59159,
    spellIDs = { 51490, 59156, 59158, 59159 },
    iconSpellID = 59159,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 25) -- Elemental: Thunderstorm
        end,
        resolveSpellID = function()
            return 59159
        end,
    },
})

Register({
    key = "shaman.shamanistic_rage",
    cooldownID = 107005,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 40,
    spellID = 30823,
    iconSpellID = 30823,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 22) -- Enhancement: Shamanistic Rage
        end,
        resolveSpellID = function()
            return 30823
        end,
    },
})

Register({
    key = "shaman.feral_spirit",
    cooldownID = 107006,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 50,
    spellID = 51533,
    iconSpellID = 51533,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 26) -- Enhancement: Feral Spirit
        end,
        resolveSpellID = function()
            return 51533
        end,
    },
})

Register({
    key = "shaman.nature_swiftness",
    cooldownID = 107007,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 60,
    spellID = 16188,
    iconSpellID = 16188,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 12) -- Resto: Nature's Swiftness
        end,
        resolveSpellID = function()
            return 16188
        end,
    },
})

Register({
    key = "shaman.tidal_force",
    cooldownID = 107008,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 70,
    spellID = 55198,
    iconSpellID = 55198,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 18) -- Resto: Tidal Force
        end,
        resolveSpellID = function()
            return 55198
        end,
    },
})

Register({
    key = "shaman.riptide",
    cooldownID = 107009,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 80,
    spellID = 61301,
    spellIDs = { 61295, 61299, 61300, 61301 },
    iconSpellID = 61301,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 26) -- Resto: Riptide
        end,
        resolveSpellID = function()
            return 61301
        end,
    },
})

Register({
    key = "shaman.mana_tide_totem",
    cooldownID = 107010,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 90,
    spellID = 16190,
    iconSpellID = 16190,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 17) -- Resto: Mana Tide Totem
        end,
        resolveSpellID = function()
            return 16190
        end,
    },
})

-- Utility cooldowns
Register({
    key = "shaman.wind_shear",
    cooldownID = 107011,
    category = CDM_CATEGORY_UTILITY,
    order = 10,
    spellID = 57994,
    iconSpellID = 57994,
    trackingType = "cooldown",
})

Register({
    key = "shaman.grounding_totem",
    cooldownID = 107012,
    category = CDM_CATEGORY_UTILITY,
    order = 20,
    spellID = 8177,
    iconSpellID = 8177,
    trackingType = "cooldown",
})

Register({
    key = "shaman.hex",
    cooldownID = 107013,
    category = CDM_CATEGORY_UTILITY,
    order = 30,
    spellID = 51514,
    iconSpellID = 51514,
    trackingType = "cooldown",
})

Register({
    key = "shaman.fire_elemental_totem",
    cooldownID = 107014,
    category = CDM_CATEGORY_UTILITY,
    order = 40,
    spellID = 2894,
    iconSpellID = 2894,
    trackingType = "cooldown",
})

Register({
    key = "shaman.earth_elemental_totem",
    cooldownID = 107015,
    category = CDM_CATEGORY_UTILITY,
    order = 50,
    spellID = 2062,
    iconSpellID = 2062,
    trackingType = "cooldown",
})

Register({
    key = "shaman.stormstrike",
    cooldownID = 107016,
    category = CDM_CATEGORY_UTILITY,
    order = 60,
    spellID = 17364,
    iconSpellID = 17364,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 13) -- Enhancement: Stormstrike
        end,
        resolveSpellID = function()
            return 17364
        end,
    },
})

Register({
    key = "shaman.lava_lash",
    cooldownID = 107017,
    category = CDM_CATEGORY_UTILITY,
    order = 70,
    spellID = 60103,
    iconSpellID = 60103,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 19) -- Enhancement: Lava Lash
        end,
        resolveSpellID = function()
            return 60103
        end,
    },
})

Register({
    key = "shaman.earth_shock",
    cooldownID = 107018,
    category = CDM_CATEGORY_UTILITY,
    order = 80,
    spellID = 49231,
    spellIDs = { 49230, 49231 },
    iconSpellID = 49231,
    trackingType = "cooldown",
})

-- Proc auras
Register({
    key = "shaman.clearcasting",
    cooldownID = 207001,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 10,
    spellID = 16246,
    auraSpellID = 16246,
    iconSpellID = 16246,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 13) -- Elemental: Elemental Focus
        end,
        resolveSpellID = function()
            return 16246
        end,
    },
})

Register({
    key = "shaman.maelstrom_weapon",
    cooldownID = 207002,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 20,
    spellID = 53817,
    auraSpellID = 53817,
    iconSpellID = 53817,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 25) -- Enhancement: Maelstrom Weapon
        end,
        resolveSpellID = function()
            return 53817
        end,
    },
})

Register({
    key = "shaman.tidal_waves",
    cooldownID = 207003,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 30,
    spellID = 53390,
    auraSpellID = 53390,
    iconSpellID = 53390,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 25) -- Resto: Tidal Waves
        end,
        resolveSpellID = function()
            return 53390
        end,
    },
})

-- Persistent buffs
Register({
    key = "shaman.water_shield",
    cooldownID = 207101,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 10,
    spellID = 57960,
    auraSpellID = 57960,
    iconSpellID = 57960,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "shaman.lightning_shield",
    cooldownID = 207102,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 20,
    spellID = 49281,
    auraSpellID = 49281,
    iconSpellID = 49281,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "shaman.earth_shield",
    cooldownID = 207103,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 30,
    spellID = 49284,
    auraSpellID = 49284,
    iconSpellID = 49284,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 14) -- Resto: Earth Shield
        end,
        resolveSpellID = function()
            return 49284
        end,
    },
})
