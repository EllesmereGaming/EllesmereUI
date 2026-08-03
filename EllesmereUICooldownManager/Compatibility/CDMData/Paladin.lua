local addonName, ns = ...

if not C_CooldownViewer or not C_CooldownViewer.RegisterDefinition then return end

-- Category Constants based on EllesmereUI defaults
-- 1 = EssentialCooldownViewer
-- 2 = UtilityCooldownViewer
-- 3 = BuffIconCooldownViewer
-- 4 = BuffBarCooldownViewer
local CDM_CATEGORY_ESSENTIAL = 1
local CDM_CATEGORY_UTILITY   = 2
local CDM_CATEGORY_BUFF_ICON = 3
local CDM_CATEGORY_BUFF_BAR  = 4

-- The dump uses the stable WotLK talent tab/index layout.  Talent auras are
-- not spellbook entries, so IsSpellKnown(auraID) cannot be used to decide if
-- they belong to the current character.
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
-- Paladin class abilities use 102XXX; paladin buffs and procs use 202XXX.
-- These IDs are stable handles and must remain globally unique.
local function Register(def)
    def.class = "PALADIN"
    C_CooldownViewer.RegisterDefinition(def)
end

-- Retribution and Protection cooldowns shared by the paladin class.
Register({
    key = "paladin.avenging_wrath",
    cooldownID = 102001,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 10,
    spellID = 31884,
    iconSpellID = 31884,
    trackingType = "cooldown",
})

Register({
    key = "paladin.divine_shield",
    cooldownID = 102002,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 20,
    spellID = 642,
    iconSpellID = 642,
    trackingType = "cooldown",
})

Register({
    key = "paladin.divine_protection",
    cooldownID = 102003,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 30,
    spellID = 498,
    iconSpellID = 498,
    trackingType = "cooldown",
})

Register({
    key = "paladin.exorcism",
    cooldownID = 102004,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 40,
    spellID = 48801,
    spellIDs = { 48800, 48801 },
    iconSpellID = 48801,
    trackingType = "cooldown",
})

Register({
    key = "paladin.hammer_of_wrath",
    cooldownID = 102005,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 50,
    spellID = 48806,
    spellIDs = { 48805, 48806 },
    iconSpellID = 48806,
    trackingType = "cooldown",
})

Register({
    key = "paladin.consecration",
    cooldownID = 102006,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 60,
    spellID = 48819,
    spellIDs = { 48818, 48819 },
    iconSpellID = 48819,
    trackingType = "cooldown",
})

Register({
    key = "paladin.holy_wrath",
    cooldownID = 102007,
    category = CDM_CATEGORY_UTILITY,
    order = 10,
    spellID = 48817,
    spellIDs = { 48816, 48817 },
    iconSpellID = 48817,
    trackingType = "cooldown",
})

Register({
    key = "paladin.hammer_of_justice",
    cooldownID = 102008,
    category = CDM_CATEGORY_UTILITY,
    order = 20,
    spellID = 10308,
    iconSpellID = 10308,
    trackingType = "cooldown",
})

Register({
    key = "paladin.hand_of_reckoning",
    cooldownID = 102009,
    category = CDM_CATEGORY_UTILITY,
    order = 30,
    spellID = 62124,
    iconSpellID = 62124,
    trackingType = "cooldown",
})

Register({
    key = "paladin.righteous_defense",
    cooldownID = 102010,
    category = CDM_CATEGORY_UTILITY,
    order = 40,
    spellID = 31789,
    iconSpellID = 31789,
    trackingType = "cooldown",
})

Register({
    key = "paladin.lay_on_hands",
    cooldownID = 102011,
    category = CDM_CATEGORY_UTILITY,
    order = 50,
    spellID = 48788,
    iconSpellID = 48788,
    trackingType = "cooldown",
})

Register({
    key = "paladin.hand_of_protection",
    cooldownID = 102012,
    category = CDM_CATEGORY_UTILITY,
    order = 60,
    spellID = 10278,
    iconSpellID = 10278,
    trackingType = "cooldown",
})

Register({
    key = "paladin.hand_of_freedom",
    cooldownID = 102013,
    category = CDM_CATEGORY_UTILITY,
    order = 70,
    spellID = 1044,
    iconSpellID = 1044,
    trackingType = "cooldown",
})

Register({
    key = "paladin.hand_of_sacrifice",
    cooldownID = 102014,
    category = CDM_CATEGORY_UTILITY,
    order = 80,
    spellID = 6940,
    iconSpellID = 6940,
    trackingType = "cooldown",
})

Register({
    key = "paladin.hand_of_salvation",
    cooldownID = 102015,
    category = CDM_CATEGORY_UTILITY,
    order = 90,
    spellID = 1038,
    iconSpellID = 1038,
    trackingType = "cooldown",
})

Register({
    key = "paladin.turn_evil",
    cooldownID = 102016,
    category = CDM_CATEGORY_UTILITY,
    order = 100,
    spellID = 10326,
    iconSpellID = 10326,
    trackingType = "cooldown",
})

Register({
    key = "paladin.judgement_of_justice",
    cooldownID = 102017,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 120,
    spellID = 53407,
    iconSpellID = 53407,
    trackingType = "cooldown",
})

Register({
    key = "paladin.judgement_of_light",
    cooldownID = 102018,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 130,
    spellID = 20271,
    iconSpellID = 20271,
    trackingType = "cooldown",
})

Register({
    key = "paladin.judgement_of_wisdom",
    cooldownID = 102019,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 140,
    spellID = 53408,
    iconSpellID = 53408,
    trackingType = "cooldown",
})

-- Retribution talent abilities recorded in the dump.
Register({
    key = "paladin.crusader_strike",
    cooldownID = 102101,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 70,
    spellID = 35395,
    iconSpellID = 35395,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 23) -- Retribution: Crusader Strike
        end,
        resolveSpellID = function()
            return 35395
        end,
    },
})

Register({
    key = "paladin.divine_storm",
    cooldownID = 102102,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 80,
    spellID = 53385,
    iconSpellID = 53385,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 26) -- Retribution: Divine Storm
        end,
        resolveSpellID = function()
            return 53385
        end,
    },
})

Register({
    key = "paladin.repentance",
    cooldownID = 102103,
    category = CDM_CATEGORY_UTILITY,
    order = 110,
    spellID = 20066,
    iconSpellID = 20066,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 18) -- Retribution: Repentance
        end,
        resolveSpellID = function()
            return 20066
        end,
    },
})

-- Protection talent abilities recorded in the dump.
Register({
    key = "paladin.avengers_shield",
    cooldownID = 102201,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 90,
    spellID = 48827,
    iconSpellID = 48827,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 22) -- Protection: Avenger's Shield
        end,
        resolveSpellID = function()
            return 48827
        end,
    },
})

Register({
    key = "paladin.hammer_of_the_righteous",
    cooldownID = 102202,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 100,
    spellID = 53595,
    iconSpellID = 53595,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 26) -- Protection: Hammer of the Righteous
        end,
        resolveSpellID = function()
            return 53595
        end,
    },
})

Register({
    key = "paladin.shield_of_righteousness",
    cooldownID = 102203,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 110,
    spellID = 61411,
    spellIDs = { 53600, 61411 },
    iconSpellID = 61411,
    trackingType = "cooldown",
})

Register({
    key = "paladin.divine_sacrifice",
    cooldownID = 102204,
    category = CDM_CATEGORY_UTILITY,
    order = 120,
    spellID = 64205,
    iconSpellID = 64205,
    trackingType = "cooldown",
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 6) -- Protection: Divine Sacrifice
        end,
        resolveSpellID = function()
            return 64205
        end,
    },
})

-- Proc and short-duration auras recorded by the dump.
Register({
    key = "paladin.the_art_of_war",
    cooldownID = 202001,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 10,
    spellID = 59578,
    auraSpellID = 59578,
    iconSpellID = 59578,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(3, 17) -- Retribution: The Art of War
        end,
        resolveSpellID = function()
            return 59578
        end,
    },
})

Register({
    key = "paladin.holy_shield",
    cooldownID = 202002,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 20,
    spellID = 48952,
    auraSpellID = 48952,
    iconSpellID = 48952,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 17) -- Protection: Holy Shield
        end,
        resolveSpellID = function()
            return 48952
        end,
    },
})

Register({
    key = "paladin.ardent_defender",
    cooldownID = 202003,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 30,
    spellID = 66233,
    auraSpellID = 66233,
    iconSpellID = 66233,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 18) -- Protection: Ardent Defender
        end,
        resolveSpellID = function()
            return 66233
        end,
    },
})

Register({
    key = "paladin.vengeance",
    cooldownID = 202004,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 40,
    spellID = 20053,
    auraSpellID = 20053,
    iconSpellID = 20053,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 15) -- Protection: Vengeance
        end,
        resolveSpellID = function()
            return 20053
        end,
    },
})

-- Buffs that are useful to keep visible while playing Protection.
Register({
    key = "paladin.divine_plea",
    cooldownID = 202101,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 10,
    spellID = 54428,
    auraSpellID = 54428,
    iconSpellID = 54428,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "paladin.blessing_of_sanctuary",
    cooldownID = 202102,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 20,
    spellID = 25899,
    auraSpellID = 25899,
    iconSpellID = 25899,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
    resolvers = {
        requirements = function()
            return HasLearnedTalent(2, 12) -- Protection: Blessing of Sanctuary
        end,
        resolveSpellID = function()
            return 25899
        end,
    },
})

Register({
    key = "paladin.retribution_aura",
    cooldownID = 202103,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 30,
    spellID = 54043,
    auraSpellID = 54043,
    iconSpellID = 54043,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "paladin.crusader_aura",
    cooldownID = 202104,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 40,
    spellID = 32223,
    auraSpellID = 32223,
    iconSpellID = 32223,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})

Register({
    key = "paladin.righteous_fury",
    cooldownID = 202105,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 50,
    spellID = 25780,
    auraSpellID = 25780,
    iconSpellID = 25780,
    trackingType = "aura",
    hasAura = true,
    selfAura = true,
})
