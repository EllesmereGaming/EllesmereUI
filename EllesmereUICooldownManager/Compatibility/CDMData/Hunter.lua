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

-- cooldownID Schema: [CD type 1 digit][Class ID 2 digits][Unique ID 3 digits]
-- Hunter = class 03. Cooldowns = 103XXX, Buffs/Procs = 203XXX.

local function Register(def)
    def.class = "HUNTER"
    C_CooldownViewer.RegisterDefinition(def)
end

-- Major cooldowns
Register({
    key = "hunter.bestial_wrath",
    cooldownID = 103001,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 10,
    spellID = 19574,
    iconSpellID = 19574,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 18) -- BM: Bestial Wrath
        end,
        resolveSpellID = function()
            return 19574
        end,
    },
})

Register({
    key = "hunter.rapid_fire",
    cooldownID = 103002,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 20,
    spellID = 3045,
    iconSpellID = 3045,
    trackingType = "cooldown",
})

Register({
    key = "hunter.readiness",
    cooldownID = 103003,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 30,
    spellID = 23989,
    iconSpellID = 23989,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 11) -- MM: Readiness
        end,
        resolveSpellID = function()
            return 23989
        end,
    },
})

Register({
    key = "hunter.kill_shot",
    cooldownID = 103004,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 40,
    spellID = 61006,
    spellIDs = { 61005, 61006 },
    iconSpellID = 61006,
    trackingType = "cooldown",
})

Register({
    key = "hunter.chimera_shot",
    cooldownID = 103005,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 50,
    spellID = 53209,
    iconSpellID = 53209,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 27) -- MM: Chimera Shot
        end,
        resolveSpellID = function()
            return 53209
        end,
    },
})

Register({
    key = "hunter.explosive_shot",
    cooldownID = 103006,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 60,
    spellID = 60053,
    spellIDs = { 60052, 60053 },
    iconSpellID = 60053,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 28) -- Surv: Explosive Shot
        end,
        resolveSpellID = function()
            return 60053
        end,
    },
})

Register({
    key = "hunter.black_arrow",
    cooldownID = 103007,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 70,
    spellID = 63672,
    spellIDs = { 63668, 63672 },
    iconSpellID = 63672,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 24) -- Surv: Black Arrow
        end,
        resolveSpellID = function()
            return 63672
        end,
    },
})

-- Utility cooldowns
Register({
    key = "hunter.disengage",
    cooldownID = 103008,
    category = CDM_CATEGORY_UTILITY,
    order = 10,
    spellID = 781,
    iconSpellID = 781,
    trackingType = "cooldown",
})

Register({
    key = "hunter.deterrence",
    cooldownID = 103009,
    category = CDM_CATEGORY_UTILITY,
    order = 20,
    spellID = 19263,
    iconSpellID = 19263,
    trackingType = "cooldown",
})

Register({
    key = "hunter.feign_death",
    cooldownID = 103010,
    category = CDM_CATEGORY_UTILITY,
    order = 30,
    spellID = 5384,
    iconSpellID = 5384,
    trackingType = "cooldown",
})

Register({
    key = "hunter.misdirection",
    cooldownID = 103011,
    category = CDM_CATEGORY_UTILITY,
    order = 40,
    spellID = 34477,
    iconSpellID = 34477,
    trackingType = "cooldown",
})

Register({
    key = "hunter.silencing_shot",
    cooldownID = 103012,
    category = CDM_CATEGORY_UTILITY,
    order = 50,
    spellID = 34490,
    iconSpellID = 34490,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 14) -- MM: Silencing Shot
        end,
        resolveSpellID = function()
            return 34490
        end,
    },
})

Register({
    key = "hunter.scatter_shot",
    cooldownID = 103013,
    category = CDM_CATEGORY_UTILITY,
    order = 60,
    spellID = 19503,
    iconSpellID = 19503,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 6) -- Surv: Scatter Shot
        end,
        resolveSpellID = function()
            return 19503
        end,
    },
})

Register({
    key = "hunter.wyvern_sting",
    cooldownID = 103014,
    category = CDM_CATEGORY_UTILITY,
    order = 70,
    spellID = 49012,
    spellIDs = { 49011, 49012 },
    iconSpellID = 49012,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 18) -- Surv: Wyvern Sting
        end,
        resolveSpellID = function()
            return 49012
        end,
    },
})

Register({
    key = "hunter.intimidation",
    cooldownID = 103015,
    category = CDM_CATEGORY_UTILITY,
    order = 80,
    spellID = 19577,
    iconSpellID = 19577,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(1, 12) -- BM: Intimidation
        end,
        resolveSpellID = function()
            return 19577
        end,
    },
})

Register({
    key = "hunter.freezing_trap",
    cooldownID = 103016,
    category = CDM_CATEGORY_UTILITY,
    order = 90,
    spellID = 14311,
    iconSpellID = 14311,
    trackingType = "cooldown",
})

Register({
    key = "hunter.explosive_trap",
    cooldownID = 103017,
    category = CDM_CATEGORY_UTILITY,
    order = 100,
    spellID = 49067,
    spellIDs = { 49066, 49067 },
    iconSpellID = 49067,
    trackingType = "cooldown",
})

Register({
    key = "hunter.frost_trap",
    cooldownID = 103018,
    category = CDM_CATEGORY_UTILITY,
    order = 110,
    spellID = 13809,
    iconSpellID = 13809,
    trackingType = "cooldown",
})

Register({
    key = "hunter.snake_trap",
    cooldownID = 103019,
    category = CDM_CATEGORY_UTILITY,
    order = 120,
    spellID = 34600,
    iconSpellID = 34600,
    trackingType = "cooldown",
})

Register({
    key = "hunter.call_of_the_wild",
    cooldownID = 103020,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 80,
    spellID = 53434,
    iconSpellID = 53434,
    trackingType = "cooldown",
})

-- Proc auras
Register({
    key = "hunter.lock_and_load",
    cooldownID = 203001,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 10,
    spellID = 56453,
    auraSpellID = 56453,
    iconSpellID = 56453,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 20) -- Surv: Lock and Load
        end,
        resolveSpellID = function()
            return 56453
        end,
    },
})

Register({
    key = "hunter.improved_steady_shot",
    cooldownID = 203002,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 20,
    spellID = 53220,
    auraSpellID = 53220,
    iconSpellID = 53220,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 12) -- MM: Improved Steady Shot
        end,
        resolveSpellID = function()
            return 53220
        end,
    },
})

Register({
    key = "hunter.kill_command",
    cooldownID = 203003,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 30,
    spellID = 34026,
    auraSpellID = 34026,
    iconSpellID = 34026,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

-- Persistent buffs
Register({
    key = "hunter.aspect_of_the_dragonhawk",
    cooldownID = 203101,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 10,
    spellID = 61847,
    auraSpellID = 61847,
    iconSpellID = 61847,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "hunter.aspect_of_the_viper",
    cooldownID = 203102,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 20,
    spellID = 34074,
    auraSpellID = 34074,
    iconSpellID = 34074,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})
