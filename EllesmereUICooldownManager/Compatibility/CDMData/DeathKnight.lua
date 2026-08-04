local addonName, ns = ...

if not C_CooldownViewer or not C_CooldownViewer.RegisterDefinition then return end

-- Category Constants based on EllesmereUI defaults
-- These correspond to the internal enum values mapped to the specific cooldown viewer bars:
-- 1 = EssentialCooldownViewer
-- 2 = UtilityCooldownViewer
-- 3 = BuffIconCooldownViewer
-- 4 = BuffBarCooldownViewer
local CDM_CATEGORY_ESSENTIAL = 1
local CDM_CATEGORY_UTILITY   = 2
local CDM_CATEGORY_BUFF_ICON = 3
local CDM_CATEGORY_BUFF_BAR  = 4

-- Proc auras generally are not spellbook entries, so IsSpellKnown(auraID)
-- cannot decide whether their talent is learned.  Resolve the localized spell
-- name and compare it with the player's current talent ranks instead.
local function HasLearnedTalentBySpellID(spellID)
    local talentName = GetSpellInfo and GetSpellInfo(spellID)
    if not talentName or not GetNumTalentTabs or not GetNumTalents or not GetTalentInfo then
        return false
    end
    for tab = 1, GetNumTalentTabs() do
        for index = 1, GetNumTalents(tab) do
            local name, _, _, _, rank = GetTalentInfo(tab, index)
            if name == talentName and (rank or 0) > 0 then
                return true
            end
        end
    end
    return false
end

-- cooldownID Schema: [CD type 1 digit][Class ID 2 digits][Unique ID 3 digits]
-- These IDs MUST be globally unique across the entire addon.
-- CD Types:
-- 1 = Class abilities (cooldowns)
-- 2 = Class buffs and procs
-- 3 = Racials
-- 4 = Items/Trinkets
-- Class IDs (standard WoW API):
-- 01=Warrior, 02=Paladin, 03=Hunter, 04=Rogue, 05=Priest, 06=Death Knight,
-- 07=Shaman, 08=Mage, 09=Warlock, 11=Druid.
-- Example: Death Knight (06) cooldown (1) -> 106XXX
C_CooldownViewer.RegisterDefinition({
    key = "deathknight.icebound_fortitude",
    cooldownID = 106001,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 10,

    spellID = 48792,
    iconSpellID = 48792,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.anti_magic_shell",
    cooldownID = 106002,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 20,

    spellID = 48707,
    iconSpellID = 48707,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.unbreakable_armor",
    cooldownID = 106003,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 30,

    spellID = 51271,
    iconSpellID = 51271,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(51271)
        end,
        resolveSpellID = function()
            return 51271
        end,
    },
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.vampiric_blood",
    cooldownID = 106004,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 40,

    spellID = 55233,
    iconSpellID = 55233,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(55233)
        end,
        resolveSpellID = function()
            return 55233
        end,
    },
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.bone_shield",
    cooldownID = 106005,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 50,

    spellID = 49222,
    iconSpellID = 49222,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(49222)
        end,
        resolveSpellID = function()
            return 49222
        end,
    },
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.dancing_rune_weapon",
    cooldownID = 106006,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 60,

    spellID = 49028,
    iconSpellID = 49028,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(49028)
        end,
        resolveSpellID = function()
            return 49028
        end,
    },
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.summon_gargoyle",
    cooldownID = 106007,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 70,

    spellID = 49206,
    iconSpellID = 49206,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(49206)
        end,
        resolveSpellID = function()
            return 49206
        end,
    },
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.hysteria",
    cooldownID = 106008,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 80,

    spellID = 49016,
    iconSpellID = 49016,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(49016)
        end,
        resolveSpellID = function()
            return 49016
        end,
    },
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.ghoul_frenzy",
    cooldownID = 106009,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 90,

    spellID = 63560,
    iconSpellID = 63560,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(63560)
        end,
        resolveSpellID = function()
            return 63560
        end,
    },
})

-- Utility cooldowns
C_CooldownViewer.RegisterDefinition({
    key = "deathknight.mind_freeze",
    cooldownID = 106010,
    category = CDM_CATEGORY_UTILITY,
    order = 10,

    spellID = 47528,
    iconSpellID = 47528,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.strangulate",
    cooldownID = 106011,
    category = CDM_CATEGORY_UTILITY,
    order = 20,

    spellID = 47476,
    iconSpellID = 47476,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.death_grip",
    cooldownID = 106012,
    category = CDM_CATEGORY_UTILITY,
    order = 30,

    spellID = 49576,
    iconSpellID = 49576,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.chains_of_ice",
    cooldownID = 106013,
    category = CDM_CATEGORY_UTILITY,
    order = 40,

    spellID = 45524,
    iconSpellID = 45524,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.empower_rune_weapon",
    cooldownID = 106014,
    category = CDM_CATEGORY_UTILITY,
    order = 50,

    spellID = 47568,
    iconSpellID = 47568,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.army_of_the_dead",
    cooldownID = 106015,
    category = CDM_CATEGORY_UTILITY,
    order = 60,

    spellID = 42650,
    iconSpellID = 42650,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.raise_dead",
    cooldownID = 106016,
    category = CDM_CATEGORY_UTILITY,
    order = 70,

    spellID = 46584,
    iconSpellID = 46584,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.anti_magic_zone",
    cooldownID = 106017,
    category = CDM_CATEGORY_UTILITY,
    order = 80,

    spellID = 51052,
    iconSpellID = 51052,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(51052)
        end,
        resolveSpellID = function()
            return 51052
        end,
    },
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.lichborne",
    cooldownID = 106018,
    category = CDM_CATEGORY_UTILITY,
    order = 90,

    spellID = 49039,
    iconSpellID = 49039,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(49039)
        end,
        resolveSpellID = function()
            return 49039
        end,
    },
})

-- Proc auras
C_CooldownViewer.RegisterDefinition({
    key = "deathknight.killing_machine",
    cooldownID = 206001,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 20,

    spellID = 51124,
    auraSpellID = 51124,
    iconSpellID = 51124,

    trackingType = "aura",
    hasAura = true,
    selfAura = true,

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(51124)
        end,
        resolveSpellID = function()
            return 51124
        end,
    },
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.rime",
    cooldownID = 206002,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 30,

    spellID = 59052,
    auraSpellID = 59052,
    iconSpellID = 59052,

    trackingType = "aura",
    hasAura = true,
    selfAura = true,

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(59057)
        end,
        resolveSpellID = function()
            return 59052
        end,
    },
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.desolation",
    cooldownID = 206003,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 40,

    spellID = 66803,
    auraSpellID = 66803,
    iconSpellID = 66803,

    trackingType = "aura",
    hasAura = true,
    selfAura = true,

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(66803)
        end,
        resolveSpellID = function()
            return 66803
        end,
    },
})

-- Persistent buffs
C_CooldownViewer.RegisterDefinition({
    key = "deathknight.horn_of_winter",
    cooldownID = 206101,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 10,

    spellID = 57623,
    auraSpellID = 57623,
    iconSpellID = 57623,

    trackingType = "aura",
    hasAura = true,
    selfAura = true,

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.bone_shield_buff",
    cooldownID = 206102,
    category = CDM_CATEGORY_BUFF_BAR,
    order = 20,

    spellID = 49222,
    auraSpellID = 49222,
    iconSpellID = 49222,

    trackingType = "aura",
    hasAura = true,
    selfAura = true,

    class = "DEATHKNIGHT",
    resolvers = {
        requirements = function()
            return HasLearnedTalentBySpellID(49222)
        end,
        resolveSpellID = function()
            return 49222
        end,
    },
})
