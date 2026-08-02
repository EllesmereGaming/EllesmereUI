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
