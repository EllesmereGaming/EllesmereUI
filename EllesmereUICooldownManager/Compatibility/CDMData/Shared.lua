local addonName, ns = ...

if not C_CooldownViewer or not C_CooldownViewer.RegisterDefinition then return end

-- Shared definitions are intentionally class-neutral. Racials, equipped-item
-- effects, enchants, and similar proc auras belong here so every class can use
-- the same stable cooldownID and settings entry.
local CDM_CATEGORY_UTILITY   = 2
local CDM_CATEGORY_BUFF_ICON = 3

-- cooldownID Schema: [CD type 1 digit][Owner ID 2 digits][Unique ID 3 digits]
-- Shared definitions use owner 00:
-- 300XXX = racials
-- 400XXX = items, enchants, trinkets, rings, and their proc auras

-- Racials
C_CooldownViewer.RegisterDefinition({
    key = "racial.blood_fury",
    cooldownID = 300001,
    category = CDM_CATEGORY_UTILITY,
    order = 10,

    spellID = 20572,
    iconSpellID = 20572,
    trackingType = "cooldown",
})

-- Equipment and enchant procs
C_CooldownViewer.RegisterDefinition({
    key = "enchant.berserking",
    cooldownID = 400001,
    category = CDM_CATEGORY_BUFF_ICON,
    order = 10,

    spellID = 59620,
    auraSpellID = 59620,
    iconSpellID = 59620,

    trackingType = "aura",
    hasAura = true,
    selfAura = true,

    -- Proc auras are not spellbook entries. Keep the shared slot available;
    -- the adapter itself is only shown while aura 59620 is active.
    resolvers = {
        requirements = function()
            return true
        end,
        resolveSpellID = function()
            return 59620
        end,
    },
})
