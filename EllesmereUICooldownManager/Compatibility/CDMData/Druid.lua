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

-- Druid = class 11. Cooldowns = 111XXX, Buffs/Procs = 211XXX.

local function Register(def)
    def.class = "DRUID"
    C_CooldownViewer.RegisterDefinition(def)
end

-- Major cooldowns
Register({
    key = "druid.innervate",
    cooldownID = 111001,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 10,
    spellID = 29166,
    iconSpellID = 29166,
    trackingType = "cooldown",
})

Register({
    key = "druid.rebirth",
    cooldownID = 111002,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 20,
    spellID = 48477,
    iconSpellID = 48477,
    trackingType = "cooldown",
})

Register({
    key = "druid.barkskin",
    cooldownID = 111003,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 30,
    spellID = 22812,
    iconSpellID = 22812,
    trackingType = "cooldown",
})

Register({
    key = "druid.starfall",
    cooldownID = 111004,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 40,
    spellID = 53201,
    spellIDs = { 48505, 53199, 53200, 53201 },
    iconSpellID = 53201,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 26) -- Balance: Starfall
        end,
        resolveSpellID = function()
            return 53201
        end,
    },
})

Register({
    key = "druid.force_of_nature",
    cooldownID = 111005,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 50,
    spellID = 33831,
    iconSpellID = 33831,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 22) -- Balance: Force of Nature
        end,
        resolveSpellID = function()
            return 33831
        end,
    },
})

Register({
    key = "druid.typhoon",
    cooldownID = 111006,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 60,
    spellID = 61384,
    spellIDs = { 50516, 53223, 53225, 61384 },
    iconSpellID = 61384,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 24) -- Balance: Typhoon
        end,
        resolveSpellID = function()
            return 61384
        end,
    },
})

Register({
    key = "druid.berserk",
    cooldownID = 111007,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 70,
    spellID = 50334,
    iconSpellID = 50334,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 27) -- Feral: Berserk
        end,
        resolveSpellID = function()
            return 50334
        end,
    },
})

Register({
    key = "druid.survival_instincts",
    cooldownID = 111008,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 80,
    spellID = 61336,
    iconSpellID = 61336,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 4) -- Feral: Survival Instincts
        end,
        resolveSpellID = function()
            return 61336
        end,
    },
})

Register({
    key = "druid.frenzied_regeneration",
    cooldownID = 111009,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 90,
    spellID = 22842,
    iconSpellID = 22842,
    trackingType = "cooldown",
})

Register({
    key = "druid.swiftmend",
    cooldownID = 111010,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 100,
    spellID = 18562,
    iconSpellID = 18562,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 14) -- Resto: Swiftmend
        end,
        resolveSpellID = function()
            return 18562
        end,
    },
})

Register({
    key = "druid.natures_swiftness",
    cooldownID = 111011,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 110,
    spellID = 17116,
    iconSpellID = 17116,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 12) -- Resto: Nature's Swiftness
        end,
        resolveSpellID = function()
            return 17116
        end,
    },
})

Register({
    key = "druid.wild_growth",
    cooldownID = 111012,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 120,
    spellID = 53251,
    spellIDs = { 48438, 53248, 53249, 53251 },
    iconSpellID = 53251,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 26) -- Resto: Wild Growth
        end,
        resolveSpellID = function()
            return 53251
        end,
    },
})

Register({
    key = "druid.tranquility",
    cooldownID = 111013,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 130,
    spellID = 48447,
    iconSpellID = 48447,
    trackingType = "cooldown",
})

-- Utility cooldowns
Register({
    key = "druid.feral_charge_bear",
    cooldownID = 111014,
    category = CDM_CATEGORY_UTILITY,
    order = 10,
    spellID = 16979,
    iconSpellID = 16979,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 6) -- Feral: Feral Charge
        end,
        resolveSpellID = function()
            return 16979
        end,
    },
})

Register({
    key = "druid.feral_charge_cat",
    cooldownID = 111015,
    category = CDM_CATEGORY_UTILITY,
    order = 20,
    spellID = 49376,
    iconSpellID = 49376,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 6) -- Feral: Feral Charge
        end,
        resolveSpellID = function()
            return 49376
        end,
    },
})

Register({
    key = "druid.dash",
    cooldownID = 111016,
    category = CDM_CATEGORY_UTILITY,
    order = 30,
    spellID = 33357,
    iconSpellID = 33357,
    trackingType = "cooldown",
})

Register({
    key = "druid.bash",
    cooldownID = 111017,
    category = CDM_CATEGORY_UTILITY,
    order = 40,
    spellID = 8983,
    iconSpellID = 8983,
    trackingType = "cooldown",
})

Register({
    key = "druid.growl",
    cooldownID = 111018,
    category = CDM_CATEGORY_UTILITY,
    order = 50,
    spellID = 6795,
    iconSpellID = 6795,
    trackingType = "cooldown",
})

Register({
    key = "druid.challenging_roar",
    cooldownID = 111019,
    category = CDM_CATEGORY_UTILITY,
    order = 60,
    spellID = 5209,
    iconSpellID = 5209,
    trackingType = "cooldown",
})

Register({
    key = "druid.enrage",
    cooldownID = 111020,
    category = CDM_CATEGORY_UTILITY,
    order = 70,
    spellID = 5229,
    iconSpellID = 5229,
    trackingType = "cooldown",
})

Register({
    key = "druid.tigers_fury",
    cooldownID = 111021,
    category = CDM_CATEGORY_UTILITY,
    order = 80,
    spellID = 50213,
    iconSpellID = 50213,
    trackingType = "cooldown",
})

Register({
    key = "druid.maim",
    cooldownID = 111022,
    category = CDM_CATEGORY_UTILITY,
    order = 90,
    spellID = 49802,
    iconSpellID = 49802,
    trackingType = "cooldown",
})

-- Proc auras
Register({
    key = "druid.eclipse_solar",
    cooldownID = 211001,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 10,
    spellID = 48517,
    auraSpellID = 48517,
    iconSpellID = 48517,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 23) -- Balance: Eclipse
        end,
        resolveSpellID = function()
            return 48517
        end,
    },
})

Register({
    key = "druid.eclipse_lunar",
    cooldownID = 211002,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 20,
    spellID = 48518,
    auraSpellID = 48518,
    iconSpellID = 48518,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 23) -- Balance: Eclipse
        end,
        resolveSpellID = function()
            return 48518
        end,
    },
})

Register({
    key = "druid.omen_of_clarity",
    cooldownID = 211003,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 30,
    spellID = 16870,
    auraSpellID = 16870,
    iconSpellID = 16870,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 3) -- Resto: Omen of Clarity
        end,
        resolveSpellID = function()
            return 16870
        end,
    },
})

Register({
    key = "druid.savage_roar",
    cooldownID = 211004,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 40,
    spellID = 52610,
    auraSpellID = 52610,
    iconSpellID = 52610,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

-- Persistent buffs
Register({
    key = "druid.mark_of_the_wild",
    cooldownID = 211101,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 10,
    spellID = 48469,
    auraSpellID = 48469,
    iconSpellID = 48469,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "druid.thorns",
    cooldownID = 211102,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 20,
    spellID = 53307,
    auraSpellID = 53307,
    iconSpellID = 53307,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "druid.moonkin_form",
    cooldownID = 211103,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 30,
    spellID = 24858,
    auraSpellID = 24858,
    iconSpellID = 24858,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 17) -- Balance: Moonkin Form
        end,
        resolveSpellID = function()
            return 24858
        end,
    },
})

Register({
    key = "druid.tree_of_life",
    cooldownID = 211104,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 40,
    spellID = 33891,
    auraSpellID = 33891,
    iconSpellID = 33891,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 21) -- Resto: Tree of Life
        end,
        resolveSpellID = function()
            return 33891
        end,
    },
})
