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

-- Mage = class 08. Cooldowns = 108XXX, Buffs/Procs = 208XXX.

local function Register(def)
    def.class = "MAGE"
    C_CooldownViewer.RegisterDefinition(def)
end

-- Major cooldowns
Register({
    key = "mage.icy_veins",
    cooldownID = 108001,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 10,
    spellID = 12472,
    iconSpellID = 12472,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 11) -- Frost: Icy Veins
        end,
        resolveSpellID = function()
            return 12472
        end,
    },
})

Register({
    key = "mage.arcane_power",
    cooldownID = 108002,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 20,
    spellID = 12042,
    iconSpellID = 12042,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 19) -- Arcane: Arcane Power
        end,
        resolveSpellID = function()
            return 12042
        end,
    },
})

Register({
    key = "mage.presence_of_mind",
    cooldownID = 108003,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 30,
    spellID = 12043,
    iconSpellID = 12043,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 13) -- Arcane: Presence of Mind
        end,
        resolveSpellID = function()
            return 12043
        end,
    },
})

Register({
    key = "mage.combustion",
    cooldownID = 108004,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 40,
    spellID = 11129,
    iconSpellID = 11129,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 18) -- Fire: Combustion
        end,
        resolveSpellID = function()
            return 11129
        end,
    },
})

Register({
    key = "mage.cold_snap",
    cooldownID = 108005,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 50,
    spellID = 11958,
    iconSpellID = 11958,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 13) -- Frost: Cold Snap
        end,
        resolveSpellID = function()
            return 11958
        end,
    },
})

Register({
    key = "mage.summon_water_elemental",
    cooldownID = 108006,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 60,
    spellID = 31687,
    iconSpellID = 31687,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 21) -- Frost: Summon Water Elemental
        end,
        resolveSpellID = function()
            return 31687
        end,
    },
})

Register({
    key = "mage.deep_freeze",
    cooldownID = 108007,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 70,
    spellID = 44572,
    iconSpellID = 44572,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 25) -- Frost: Deep Freeze
        end,
        resolveSpellID = function()
            return 44572
        end,
    },
})

Register({
    key = "mage.mirror_image",
    cooldownID = 108008,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 80,
    spellID = 55342,
    iconSpellID = 55342,
    trackingType = "cooldown",
})

Register({
    key = "mage.evocation",
    cooldownID = 108009,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 90,
    spellID = 12051,
    iconSpellID = 12051,
    trackingType = "cooldown",
})

-- Utility cooldowns
Register({
    key = "mage.counterspell",
    cooldownID = 108010,
    category = CDM_CATEGORY_UTILITY,
    order = 10,
    spellID = 2139,
    iconSpellID = 2139,
    trackingType = "cooldown",
})

Register({
    key = "mage.ice_block",
    cooldownID = 108011,
    category = CDM_CATEGORY_UTILITY,
    order = 20,
    spellID = 45438,
    iconSpellID = 45438,
    trackingType = "cooldown",
})

Register({
    key = "mage.blink",
    cooldownID = 108012,
    category = CDM_CATEGORY_UTILITY,
    order = 30,
    spellID = 1953,
    iconSpellID = 1953,
    trackingType = "cooldown",
})

Register({
    key = "mage.frost_nova",
    cooldownID = 108013,
    category = CDM_CATEGORY_UTILITY,
    order = 40,
    spellID = 27088,
    iconSpellID = 27088,
    trackingType = "cooldown",
})

Register({
    key = "mage.fire_blast",
    cooldownID = 108014,
    category = CDM_CATEGORY_UTILITY,
    order = 50,
    spellID = 42873,
    spellIDs = { 42872, 42873 },
    iconSpellID = 42873,
    trackingType = "cooldown",
})

Register({
    key = "mage.cone_of_cold",
    cooldownID = 108015,
    category = CDM_CATEGORY_UTILITY,
    order = 60,
    spellID = 42931,
    spellIDs = { 42930, 42931 },
    iconSpellID = 42931,
    trackingType = "cooldown",
})

Register({
    key = "mage.dragons_breath",
    cooldownID = 108016,
    category = CDM_CATEGORY_UTILITY,
    order = 70,
    spellID = 42950,
    spellIDs = { 42949, 42950 },
    iconSpellID = 42950,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 22) -- Fire: Dragon's Breath
        end,
        resolveSpellID = function()
            return 42950
        end,
    },
})

Register({
    key = "mage.blast_wave",
    cooldownID = 108017,
    category = CDM_CATEGORY_UTILITY,
    order = 80,
    spellID = 42945,
    spellIDs = { 42944, 42945 },
    iconSpellID = 42945,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 13) -- Fire: Blast Wave
        end,
        resolveSpellID = function()
            return 42945
        end,
    },
})

Register({
    key = "mage.invisibility",
    cooldownID = 108018,
    category = CDM_CATEGORY_UTILITY,
    order = 90,
    spellID = 66,
    iconSpellID = 66,
    trackingType = "cooldown",
})

-- Proc auras
Register({
    key = "mage.missile_barrage",
    cooldownID = 208001,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 10,
    spellID = 44401,
    auraSpellID = 44401,
    iconSpellID = 44401,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 22) -- Arcane: Missile Barrage
        end,
        resolveSpellID = function()
            return 44401
        end,
    },
})

Register({
    key = "mage.hot_streak",
    cooldownID = 208002,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 20,
    spellID = 48108,
    auraSpellID = 48108,
    iconSpellID = 48108,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 21) -- Fire: Hot Streak
        end,
        resolveSpellID = function()
            return 48108
        end,
    },
})

Register({
    key = "mage.fingers_of_frost",
    cooldownID = 208003,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 30,
    spellID = 44544,
    auraSpellID = 44544,
    iconSpellID = 44544,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 18) -- Frost: Fingers of Frost
        end,
        resolveSpellID = function()
            return 44544
        end,
    },
})

Register({
    key = "mage.brain_freeze",
    cooldownID = 208004,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 40,
    spellID = 57761,
    auraSpellID = 57761,
    iconSpellID = 57761,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 19) -- Frost: Brain Freeze
        end,
        resolveSpellID = function()
            return 57761
        end,
    },
})

-- Persistent buffs
Register({
    key = "mage.arcane_intellect",
    cooldownID = 208101,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 10,
    spellID = 42995,
    auraSpellID = 42995,
    iconSpellID = 42995,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "mage.molten_armor",
    cooldownID = 208102,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 20,
    spellID = 43046,
    auraSpellID = 43046,
    iconSpellID = 43046,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "mage.mage_armor",
    cooldownID = 208103,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 30,
    spellID = 43024,
    auraSpellID = 43024,
    iconSpellID = 43024,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "mage.ice_armor",
    cooldownID = 208104,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 40,
    spellID = 43008,
    auraSpellID = 43008,
    iconSpellID = 43008,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})
