local addonName, ns = ...
local EUICompat = _G.EUICompat

if not EUICompat.IsWotLK then return end

EUICompat.CDM.ActiveProvider:RegisterDefinition({
    key = "deathknight.icebound_fortitude",
    cooldownID = 100001,
    category = EUICompat.CDM_CATEGORY_ESSENTIAL,
    order = 10,

    spellID = 48792,
    iconSpellID = 48792,
    trackingType = "cooldown",

    class = "DEATHKNIGHT",
})

EUICompat.CDM.ActiveProvider:RegisterDefinition({
    key = "deathknight.killing_machine",
    cooldownID = 200001,
    category = EUICompat.CDM_CATEGORY_BUFF_ICON,
    order = 20,

    spellID = 51124,
    auraSpellID = 51124,
    iconSpellID = 51124,

    trackingType = "aura",
    hasAura = true,
    selfAura = true,

    class = "DEATHKNIGHT",
})
