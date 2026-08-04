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

-- Rogue = class 04. Cooldowns = 104XXX, Buffs/Procs = 204XXX.

local function Register(def)
    def.class = "ROGUE"
    C_CooldownViewer.RegisterDefinition(def)
end

-- Major cooldowns
Register({
    key = "rogue.adrenaline_rush",
    cooldownID = 104001,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 10,
    spellID = 13750,
    iconSpellID = 13750,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 17) -- Combat: Adrenaline Rush
        end,
        resolveSpellID = function()
            return 13750
        end,
    },
})

Register({
    key = "rogue.killing_spree",
    cooldownID = 104002,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 20,
    spellID = 51690,
    iconSpellID = 51690,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 24) -- Combat: Killing Spree
        end,
        resolveSpellID = function()
            return 51690
        end,
    },
})

Register({
    key = "rogue.shadow_dance",
    cooldownID = 104003,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 30,
    spellID = 51713,
    iconSpellID = 51713,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 27) -- Subtlety: Shadow Dance
        end,
        resolveSpellID = function()
            return 51713
        end,
    },
})

Register({
    key = "rogue.vendetta",
    cooldownID = 104004,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 40,
    spellID = 14177,
    iconSpellID = 14177,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 26) -- Assassination: Mutilate -> Hunger for Blood tree
        end,
        resolveSpellID = function()
            return 14177
        end,
    },
})

Register({
    key = "rogue.cold_blood",
    cooldownID = 104005,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 50,
    spellID = 14177,
    iconSpellID = 14177,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 15) -- Assassination: Cold Blood
        end,
        resolveSpellID = function()
            return 14177
        end,
    },
})

Register({
    key = "rogue.preparation",
    cooldownID = 104006,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 60,
    spellID = 14185,
    iconSpellID = 14185,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 13) -- Subtlety: Preparation
        end,
        resolveSpellID = function()
            return 14185
        end,
    },
})

Register({
    key = "rogue.hunger_for_blood",
    cooldownID = 104007,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 70,
    spellID = 51662,
    iconSpellID = 51662,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 28) -- Assassination: Hunger for Blood
        end,
        resolveSpellID = function()
            return 51662
        end,
    },
})

-- Defensive / utility
Register({
    key = "rogue.evasion",
    cooldownID = 104008,
    category = CDM_CATEGORY_UTILITY,
    order = 10,
    spellID = 26669,
    iconSpellID = 26669,
    trackingType = "cooldown",
})

Register({
    key = "rogue.cloak_of_shadows",
    cooldownID = 104009,
    category = CDM_CATEGORY_UTILITY,
    order = 20,
    spellID = 31224,
    iconSpellID = 31224,
    trackingType = "cooldown",
})

Register({
    key = "rogue.vanish",
    cooldownID = 104010,
    category = CDM_CATEGORY_UTILITY,
    order = 30,
    spellID = 26889,
    iconSpellID = 26889,
    trackingType = "cooldown",
})

Register({
    key = "rogue.sprint",
    cooldownID = 104011,
    category = CDM_CATEGORY_UTILITY,
    order = 40,
    spellID = 11305,
    iconSpellID = 11305,
    trackingType = "cooldown",
})

Register({
    key = "rogue.tricks_of_the_trade",
    cooldownID = 104012,
    category = CDM_CATEGORY_UTILITY,
    order = 50,
    spellID = 57934,
    iconSpellID = 57934,
    trackingType = "cooldown",
})

Register({
    key = "rogue.kick",
    cooldownID = 104013,
    category = CDM_CATEGORY_UTILITY,
    order = 60,
    spellID = 1769,
    iconSpellID = 1769,
    trackingType = "cooldown",
})

Register({
    key = "rogue.blind",
    cooldownID = 104014,
    category = CDM_CATEGORY_UTILITY,
    order = 70,
    spellID = 2094,
    iconSpellID = 2094,
    trackingType = "cooldown",
})

Register({
    key = "rogue.shadowstep",
    cooldownID = 104015,
    category = CDM_CATEGORY_UTILITY,
    order = 80,
    spellID = 36554,
    iconSpellID = 36554,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 22) -- Subtlety: Shadowstep
        end,
        resolveSpellID = function()
            return 36554
        end,
    },
})

Register({
    key = "rogue.dismantle",
    cooldownID = 104016,
    category = CDM_CATEGORY_UTILITY,
    order = 90,
    spellID = 51722,
    iconSpellID = 51722,
    trackingType = "cooldown",
})

Register({
    key = "rogue.fan_of_knives",
    cooldownID = 104017,
    category = CDM_CATEGORY_UTILITY,
    order = 100,
    spellID = 51723,
    iconSpellID = 51723,
    trackingType = "cooldown",
})

-- Proc auras
Register({
    key = "rogue.blade_flurry",
    cooldownID = 204001,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 10,
    spellID = 13877,
    auraSpellID = 13877,
    iconSpellID = 13877,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 13) -- Combat: Blade Flurry
        end,
        resolveSpellID = function()
            return 13877
        end,
    },
})

Register({
    key = "rogue.slice_and_dice",
    cooldownID = 204002,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 20,
    spellID = 6774,
    auraSpellID = 6774,
    iconSpellID = 6774,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "rogue.envenom",
    cooldownID = 204003,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 30,
    spellID = 57993,
    auraSpellID = 57993,
    iconSpellID = 57993,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

-- Persistent self-buffs
Register({
    key = "rogue.stealth",
    cooldownID = 204101,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 10,
    spellID = 1787,
    auraSpellID = 1787,
    iconSpellID = 1787,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})
