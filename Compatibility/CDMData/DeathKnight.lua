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

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.icebound_fortitude",
    cooldownID = 100001,
    category = CDM_CATEGORY_ESSENTIAL,
    order = 10,

    spellID = 48792,
    iconSpellID = 48792,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

C_CooldownViewer.RegisterDefinition({
    key = "deathknight.killing_machine",
    cooldownID = 200001,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 20,

    spellID = 51124,
    auraSpellID = 51124,
    iconSpellID = 51124,

    trackingType = "aura",
    hasAura = true,
    selfAura = true,

    class = "DEATHKNIGHT",
})
