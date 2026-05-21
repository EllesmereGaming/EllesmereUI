-------------------------------------------------------------------------------
--  EUI_MacroFactory.lua
--  Builds the Macro Factory UI for the Quality of Life options page.
--  Called by BuildQoLPage via EllesmereUI.BuildMacroFactory(parent, y, PP)
-------------------------------------------------------------------------------

-- One-time migration: update EUI_Health macro body to use spell name instead of ID.
-- Runs once per account (v2 flag).
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if EllesmereUIDB._healthMacroMigratedV2 then return end
        local idx = GetMacroIndexByName("EUI_Health")
        if idx == 0 then EllesmereUIDB._healthMacroMigratedV2 = true; return end
        if InCombatLockdown() then return end
        local body = "#showtooltip item:241304\n/cast [nocombat] Recuperate\n/use [combat] item:241304\n/use [combat] item:241305"
        EditMacro(idx, nil, nil, body)
        EllesmereUIDB._healthMacroMigratedV2 = true
    end)
end

function EllesmereUI.BuildMacroFactory(parent, startY, PP)
    local ICON_SIZE = 40
    local ICON_GAP = 40
    local ICONS_PER_ROW = 4
    local SPEC_ICONS_PER_ROW = 3
    local SPEC_ICON_GAP = 70
    local FIRST_ICON_Y = -34
    local ROW_STRIDE = 66
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local EG = EllesmereUI.ELLESMERE_GREEN
    local y = startY

    ---------------------------------------------------------------------------
    --  Macro definitions
    ---------------------------------------------------------------------------
    local GENERAL_DEFS = {
        {
            name = "EUI_Potion",
            icon = "Interface\\Icons\\inv_potion_54",
            label = "Potion",
            checkboxes = {
                { key = "opt1", label = "Fleeting Light's Potential", items = {245898, 245897} },
                { key = "opt2", label = "Light's Potential",          items = {241308, 241309} },
                { key = "opt3", label = "Fleeting Recklessness",      items = {245902, 245903} },
                { key = "opt4", label = "Recklessness",               items = {241288, 241289} },
            },
        },
        {
            name = "EUI_Health",
            icon = "Interface\\Icons\\inv_potion_131",
            label = "Health / Recuperate (Combat Based)",
            fixedBody = "/cast [nocombat] Recuperate\n/use [combat] item:241304\n/use [combat] item:241305",
            fixedTooltip = "item:241304",
        },
        {
            name = "EUI_Food",
            icon = "Interface\\Icons\\inv_misc_food_73cinnamonroll",
            label = "Food",
            checkboxes = {
                { key = "opt1", label = "Conjured Mana Bun",          items = {113509} },
                { key = "opt2", label = "Fairbreeze Feast",           items = {260262} },
                { key = "opt3", label = "Silvermoon Soiree Spread",   items = {260263} },
                { key = "opt4", label = "Quel'Danas Rations",         items = {260264} },
                { key = "opt5", label = "Mana Lily Tea",              items = {242297} },
                { key = "opt6", label = "Springrunner Sparkling",     items = {260260} },
                { key = "opt7", label = "Tranquility Bloom Tea",      items = {1226196} },
                { key = "opt8", label = "Sanguithorn Tea",            items = {242299} },
                { key = "opt9", label = "Azeroot Tea",                items = {242301} },
                { key = "opt10", label = "Argentleaf Tea",            items = {242298} },
                { key = "opt11", label = "Everspring Water",          items = {260259} },
            },
        },
        {
            name = "EUI_Trinket1",
            icon = "Interface\\Icons\\inv_jewelry_trinketpvp_01",
            label = "Trinket 1",
            fixedBody = "/use 13",
            fixedTooltip = "13",
        },
        {
            name = "EUI_Trinket2",
            icon = "Interface\\Icons\\inv_jewelry_trinketpvp_02",
            label = "Trinket 2",
            fixedBody = "/use 14",
            fixedTooltip = "14",
        },
        {
            name = "EUI_Focus",
            icon = "Interface\\Icons\\ability_hunter_focusedaim",
            macroIcon = 236203,
            label = "Set Focus",
            fixedBody = "/focus [@mouseover,exists,nodead] []",
        },
    }

    ---------------------------------------------------------------------------
    --  Spec macro definitions (keyed by specID)
    --  Format: same as GENERAL_DEFS but fixedBody only (no checkboxes).
    --  Each entry: { name, icon, label, fixedBody, fixedTooltip (optional) }
    ---------------------------------------------------------------------------
    local function mergeMacros(...)
        local t = {}
        for i = 1, select("#", ...) do
            local src = select(i, ...)
            if src then for _, v in ipairs(src) do t[#t+1] = v end end
        end
        return t
    end

    -- Death Knight (250=Blood, 251=Frost, 252=Unholy)
    local DK_GEN = {
        { name="EUI_MindFreeze", icon="Interface\\Icons\\spell_deathknight_mindfreeze", label="Mind Freeze\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Mind Freeze", fixedTooltip="Mind Freeze" },
        { name="EUI_Asphyxiate", icon="Interface\\Icons\\ability_deathknight_asphixiate", label="Asphyxiate\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Asphyxiate", fixedTooltip="Asphyxiate" },
    }
    local DK_BLOOD = {
        { name="EUI_DnDCursor", icon="Interface\\Icons\\spell_shadow_deathanddecay", label="Death and Decay\n(Cursor)", fixedBody="/cast [@cursor] Death and Decay", fixedTooltip="Death and Decay" },
        { name="EUI_GorefiendCursor", icon="Interface\\Icons\\ability_deathknight_aoedeathgrip", label="Gorefiend's Grasp\n(Cursor)", fixedBody="/cast [@cursor] Gorefiend's Grasp", fixedTooltip="Gorefiend's Grasp" },
        { name="EUI_AbomLimb", icon="Interface\\Icons\\ability_deathknight_intovoidtentacles", label="Abomination Limb\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Abomination Limb", fixedTooltip="Abomination Limb" },
    }
    local DK_FROST = {
        { name="EUI_PFObliterate", icon="Interface\\Icons\\spell_deathknight_pillaroffrost", label="PF Obliterate", fixedBody="/cast Pillar of Frost\n/cast Obliterate\n/cast Raise Dead" },
        { name="EUI_PFReapersMark", icon="Interface\\Icons\\spell_deathknight_pillaroffrost", label="PF Reaper's Mark", fixedBody="/cast Pillar of Frost\n/cast Reaper's Mark\n/cast Raise Dead" },
    }
    local DK_UNHOLY = {
        { name="EUI_DarkTransform", icon="Interface\\Icons\\achievement_boss_festergutrotface", label="Dark Transform\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Dark Transformation", fixedTooltip="Dark Transformation" },
        { name="EUI_PetSwap", icon="Interface\\Icons\\ability_devour", label="Pet Target\nSwap", fixedBody="/cast Leap\n/petattack\n/startattack" },
        { name="EUI_PetMove", icon="Interface\\Icons\\achievement_boss_festergutrotface", label="Pet Move", fixedBody="/petmoveto", fixedTooltip="dark transformation" },
        { name="EUI_PetResummon", icon="Interface\\Icons\\spell_shadow_animatedead", label="Pet Resummon", fixedBody="/script PetDismiss()\n/cast [nopet] Raise Dead" },
    }

    -- Demon Hunter (577=Havoc, 581=Vengeance)
    local DH_GEN = {
        { name="EUI_Disrupt", icon="Interface\\Icons\\ability_demonhunter_consumemagic", label="Disrupt\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Disrupt", fixedTooltip="Disrupt" },
        { name="EUI_ConsumeMagic", icon="Interface\\Icons\\spell_shadow_manaburn", label="Consume Magic\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Consume Magic", fixedTooltip="Consume Magic" },
        { name="EUI_MetaCursor", icon="Interface\\Icons\\ability_demonhunter_metamorphasisdps", label="Metamorphosis\n(Cursor)", fixedBody="/cast [@cursor] Metamorphosis", fixedTooltip="Metamorphosis" },
        { name="EUI_SigilFlame", icon="Interface\\Icons\\ability_demonhunter_sigilofinquisition", label="Sigil of Flame\n(Cursor)", fixedBody="/cast [@cursor] Sigil of Flame", fixedTooltip="Sigil of Flame" },
        { name="EUI_SigilMisery", icon="Interface\\Icons\\ability_demonhunter_sigilofmisery", label="Sigil of Misery\n(Cursor)", fixedBody="/cast [@cursor] Sigil of Misery", fixedTooltip="Sigil of Misery" },
    }
    local DH_DEVOURER = {
        { name="EUI_VoidMeta", icon="Interface\\Icons\\ability_demonhunter_metamorphasisdps", label="Void Metamorphosis\n+ Trinket 1", fixedBody="/cast Void Metamorphosis\n/use 13", fixedTooltip="Void Metamorphosis" },
        { name="EUI_ShiftCursor", icon="Interface\\Icons\\inv_12_dh_void_ability_shift", label="Shift\n(Cursor)", fixedBody="/cast [@cursor] Shift", fixedTooltip="Shift" },
    }
    local DH_HAVOC = {
        { name="EUI_TheHunt", icon="Interface\\Icons\\ability_ardenweald_demonhunter", label="The Hunt\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] The Hunt", fixedTooltip="The Hunt" },
        { name="EUI_VRGlide", icon="Interface\\Icons\\ability_demonhunter_vengefulretreat2", label="Vengeful Retreat\n& Glide", fixedBody="/cast Vengeful Retreat\n/cast !Glide", fixedTooltip="Vengeful Retreat" },
    }
    local DH_VENG = {
        { name="EUI_InfernalStrike", icon="Interface\\Icons\\ability_demonhunter_infernalstrike1", label="Infernal Strike\n(Cursor)", fixedBody="/cast [@cursor] Infernal Strike", fixedTooltip="Infernal Strike" },
        { name="EUI_SigilChains", icon="Interface\\Icons\\ability_demonhunter_sigilofchains", label="Sigil of Chains\n(Cursor)", fixedBody="/cast [@cursor] Sigil of Chains", fixedTooltip="Sigil of Chains" },
        { name="EUI_SigilSilence", icon="Interface\\Icons\\ability_demonhunter_sigilofsilence", label="Sigil of Silence\n(Cursor)", fixedBody="/cast [@cursor] Sigil of Silence" },
    }

    -- Druid (102=Balance, 103=Feral, 104=Guardian, 105=Restoration)
    local DRUID_GEN = {
        { name="EUI_UrsolVortex", icon="Interface\\Icons\\spell_nature_stoneclawtotem", label="Ursol's Vortex\n(Cursor)", fixedBody="/cast [@cursor] Ursol's Vortex" },
        { name="EUI_Innervate", icon="Interface\\Icons\\spell_nature_lightning", label="Innervate\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Innervate", fixedTooltip="Innervate" },
        { name="EUI_RemoveCorrupt", icon="Interface\\Icons\\spell_holy_removecurse", label="Remove Corruption\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Remove Corruption", fixedTooltip="Remove Corruption" },
    }
    local DRUID_BAL = {
        { name="EUI_SolarBeam", icon="Interface\\Icons\\ability_vehicle_sonicshockwave", label="Solar Beam\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Solar Beam", fixedTooltip="Solar Beam" },
        { name="EUI_ForceOfNature", icon="Interface\\Icons\\ability_druid_forceofnature", label="Force of Nature\n(Cursor)", fixedBody="/cast [@cursor] Force of Nature", fixedTooltip="Force of Nature" },
        { name="EUI_CelestialAlign", icon="Interface\\Icons\\spell_nature_natureguardian", label="Celestial Alignment\n(Cursor)", fixedBody="/cast [@cursor] Celestial Alignment", fixedTooltip="Celestial Alignment" },
    }
    local DRUID_FERAL = {
        { name="EUI_SkullBash", icon="Interface\\Icons\\inv_bone_skull_04", label="Skull Bash\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Skull Bash", fixedTooltip="Skull Bash" },
    }
    local DRUID_GUARD = {
        { name="EUI_SkullBash", icon="Interface\\Icons\\inv_bone_skull_04", label="Skull Bash\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Skull Bash", fixedTooltip="Skull Bash" },
    }
    local DRUID_RESTO = {
        { name="EUI_Ironbark", icon="Interface\\Icons\\spell_druid_ironbark", label="Ironbark\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Ironbark", fixedTooltip="Ironbark" },
        { name="EUI_InnervateSelf", icon="Interface\\Icons\\spell_nature_lightning", label="Innervate\n(Player)", fixedBody="/cast [@player] Innervate" },
        { name="EUI_NSConvoke", icon="Interface\\Icons\\ability_ardenweald_druid", label="Nature's Swiftness\nConvoke", fixedBody="/cast [nochanneling] Nature's Swiftness\n/cast Convoke the Spirits\n/cqs", fixedTooltip="Convoke the Spirits" },
    }

    -- Evoker (1467=Devastation, 1468=Preservation, 1473=Augmentation)
    local EVOKER_GEN = {
        { name="EUI_CautFlame", icon="Interface\\Icons\\ability_evoker_fontofmagic_red", label="Cauterizing Flame\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Cauterizing Flame", fixedTooltip="Cauterizing Flame" },
        { name="EUI_RescueCursor", icon="Interface\\Icons\\ability_evoker_flywithme", label="Rescue\n(Cursor)", fixedBody="/tar [@focus]\n/cast [@cursor] Rescue\n/targetlasttarget", fixedTooltip="Rescue" },
        { name="EUI_RescueToYou", icon="Interface\\Icons\\ability_evoker_flywithme", label="Rescue\n(To You)", fixedBody="/tar [@focus]\n/cast [@player] Rescue\n/targetlasttarget", fixedTooltip="Rescue" },
        { name="EUI_SleepWalk", icon="Interface\\Icons\\ability_xavius_dreamsimulacrum", label="Sleep Walk\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Sleep Walk", fixedTooltip="Sleep Walk" },
    }
    local EVOKER_AUG = {
        { name="EUI_Quell", icon="Interface\\Icons\\ability_evoker_quell", label="Quell\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Quell", fixedTooltip="Quell" },
        { name="EUI_BlistScales", icon="Interface\\Icons\\ability_evoker_blisteringscales", label="Blistering Scales\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Blistering Scales", fixedTooltip="Blistering Scales" },
    }
    local EVOKER_DEV = {
        { name="EUI_Quell", icon="Interface\\Icons\\ability_evoker_quell", label="Quell\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Quell", fixedTooltip="Quell" },
        { name="EUI_DragonrageBurst", icon="Interface\\Icons\\ability_evoker_dragonrage2", label="Dragonrage\nBurst", fixedBody="/cast Dragonrage\n/use 13", fixedTooltip="Dragonrage" },
    }
    local EVOKER_PRES = {
        { name="EUI_DreamBreath", icon="Interface\\Icons\\ability_evoker_dreambreath", label="Dream Breath\n(Cursor)", fixedBody="/cast [@cursor] Dream Breath", fixedTooltip="Dream Breath" },
        { name="EUI_Spiritbloom", icon="Interface\\Icons\\ability_evoker_spiritbloom2", label="Spiritbloom\n(Cursor)", fixedBody="/cast [@cursor] Spiritbloom", fixedTooltip="Spiritbloom" },
    }

    -- Hunter (253=BeastMastery, 254=Marksmanship, 255=Survival)
    local HUNTER_GEN = {
        { name="EUI_CounterMuzzle", icon="Interface\\Icons\\ability_kick", label="Counter Shot\nMuzzle (Focus)", fixedBody="/cast [@focus,harm,nodead][] Counter Shot\n/cast [@focus,harm,nodead][] Muzzle" },
        { name="EUI_CancelTurtle", icon="Interface\\Icons\\ability_hunter_pet_turtle", label="Cancel/Cast\nTurtle", fixedBody="/cancelaura Aspect of the Turtle\n/cast Aspect of the Turtle", fixedTooltip="Aspect of the Turtle" },
        { name="EUI_Misdirection", icon="Interface\\Icons\\ability_hunter_misdirection", label="Misdirection\n(Focus)", fixedBody="/cast [@focus,help,nodead][@pet,exists] Misdirection", fixedTooltip="Misdirection" },
        { name="EUI_FreezeTrap", icon="Interface\\Icons\\spell_frost_chainsofice", label="Freezing Trap\n(Cursor)", fixedBody="/cast [@cursor] Freezing Trap", fixedTooltip="Freezing Trap" },
        { name="EUI_FlareCursor", icon="Interface\\Icons\\spell_frost_stun", label="Flare\n(Cursor)", fixedBody="/cast [@cursor] Flare", fixedTooltip="Flare" },
        { name="EUI_TarTrap", icon="Interface\\Icons\\spell_nature_stranglevines", label="Tar Trap\n(Cursor)", fixedBody="/cast [@cursor] Tar Trap", fixedTooltip="Tar Trap" },
        { name="EUI_BindingShot", icon="Interface\\Icons\\spell_shaman_bindelemental", label="Binding Shot\n(Cursor)", fixedBody="/cast [@cursor] Binding Shot", fixedTooltip="Binding Shot" },
    }
    local HUNTER_BM = {
        { name="EUI_RoarSacrifice", icon="Interface\\Icons\\ability_hunter_ferociouswild", label="Roar of\nSacrifice", fixedBody="/target[@focus, help, nodead]\n/cast Roar of Sacrifice\n/targetlasttarget\n/cast [@pet] Misdirection", fixedTooltip="Roar of Sacrifice" },
        { name="EUI_SpiritMend", icon="Interface\\Icons\\ability_hunter_spiritmend", label="Spirit Mend", fixedBody="/cast [@target,help,nodead][@mouseover,help,nodead][@player] Spirit Mend", fixedTooltip="Spirit Mend" },
    }
    local HUNTER_MM = {
    }
    local HUNTER_SURV = {
        { name="EUI_Harpoon", icon="Interface\\Icons\\ability_hunter_harpoon", label="Harpoon\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Harpoon", fixedTooltip="Harpoon" },
    }

    -- Mage (62=Arcane, 63=Fire, 64=Frost)
    local MAGE_GEN = {
        { name="EUI_Counterspell", icon="Interface\\Icons\\spell_frost_iceshock", label="Counterspell\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Counterspell", fixedTooltip="Counterspell" },
        { name="EUI_Spellsteal", icon="Interface\\Icons\\spell_arcane_arcane02", label="Spellsteal\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Spellsteal", fixedTooltip="Spellsteal" },
        { name="EUI_RemoveCurse", icon="Interface\\Icons\\spell_holy_removecurse", label="Remove Curse\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Remove Curse", fixedTooltip="Remove Curse" },
    }
    local MAGE_ARCANE = {
        { name="EUI_PoMBlast", icon="Interface\\Icons\\spell_nature_enchantarmor", label="Presence of Mind\nArcane Blast", fixedBody="/cast Presence of Mind\n/cast Arcane Blast\n/cqs" },
    }
    local MAGE_FIRE = {
        { name="EUI_Flamestrike", icon="Interface\\Icons\\spell_fire_selfdestruct", label="Flamestrike\n(Cursor)", fixedBody="/cast [@cursor] Flamestrike" },
        { name="EUI_MeteorCursor", icon="Interface\\Icons\\spell_mage_meteor", label="Meteor\n(Cursor)", fixedBody="/cast [@cursor] Meteor" },
    }
    local MAGE_FROST_SPEC = {
        { name="EUI_BlizzardCursor", icon="Interface\\Icons\\spell_frost_icestorm", label="Blizzard\n(Cursor)", fixedBody="/cast [@cursor] Blizzard" },
    }

    -- Monk (268=Brewmaster, 270=Mistweaver, 269=Windwalker)
    local MONK_GEN = {
        { name="EUI_Detox", icon="Interface\\Icons\\ability_rogue_imrovedrecuperate", label="Detox\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Detox", fixedTooltip="Detox" },
        { name="EUI_TigersLust", icon="Interface\\Icons\\ability_monk_tigerslust", label="Tiger's Lust\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Tiger's Lust", fixedTooltip="Tiger's Lust" },
        { name="EUI_RingOfPeace", icon="Interface\\Icons\\spell_monk_ringofpeace", label="Ring of Peace\n(Cursor)", fixedBody="/cast [@cursor] Ring of Peace" },
    }
    local MONK_BREW = {
        { name="EUI_SpearHand", icon="Interface\\Icons\\ability_monk_spearhand", label="Spear Hand Strike\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Spear Hand Strike", fixedTooltip="Spear Hand Strike" },
        { name="EUI_BlackOxStatue", icon="Interface\\Icons\\monk_ability_summonoxstatue", label="Black Ox Statue\n(Cursor)", fixedBody="/cast [@cursor] Summon Black Ox Statue" },
    }
    local MONK_WW = {
        { name="EUI_SpearHand", icon="Interface\\Icons\\ability_monk_spearhand", label="Spear Hand Strike\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Spear Hand Strike", fixedTooltip="Spear Hand Strike" },
    }
    local MONK_MW = {
        { name="EUI_LifeCocoon", icon="Interface\\Icons\\ability_monk_chicocoon", label="Life Cocoon\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Life Cocoon", fixedTooltip="Life Cocoon" },
        { name="EUI_JadeSerpent", icon="Interface\\Icons\\ability_monk_summonserpentstatue", label="Jade Serpent\nStatue (Cursor)", fixedBody="/cast [@cursor] Summon Jade Serpent Statue", fixedTooltip="Summon Jade Serpent Statue" },
    }

    -- Paladin (65=Holy, 66=Protection, 70=Retribution)
    local PALA_GEN = {
        { name="EUI_BoFreedom", icon="Interface\\Icons\\spell_holy_sealofvalor", label="Blessing of\nFreedom (Focus)", fixedBody="/cast [@focus,help,nodead][] Blessing of Freedom", fixedTooltip="Blessing of Freedom" },
        { name="EUI_BoProtection", icon="Interface\\Icons\\spell_holy_sealofprotection", label="Blessing of\nProtection (Focus)", fixedBody="/cast [@focus,help,nodead][] Blessing of Protection", fixedTooltip="Blessing of Protection" },
        { name="EUI_DivineShield", icon="Interface\\Icons\\spell_holy_divineshield", label="Divine Shield\nCancel/Cast", fixedBody="/stopcasting\n/cancelaura Divine Shield\n/cast Divine Shield", fixedTooltip="Divine Shield" },
        { name="EUI_ToTLayOnHands", icon="Interface\\Icons\\spell_holy_layonhands", label="Lay on Hands\n(Target of Target)", fixedBody="/cast [@targettarget] Lay on Hands" },
        { name="EUI_Cleanse", icon="Interface\\Icons\\spell_holy_purify", label="Cleanse\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Cleanse", fixedTooltip="Cleanse" },
        { name="EUI_LayOnHands", icon="Interface\\Icons\\spell_holy_layonhands", label="Lay on Hands\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Lay on Hands", fixedTooltip="Lay on Hands" },
    }
    local PALA_HOLY = {
    }
    local PALA_PROT = {
        { name="EUI_Rebuke", icon="Interface\\Icons\\spell_holy_rebuke", label="Rebuke\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Rebuke", fixedTooltip="Rebuke" },
    }
    local PALA_RET = {
        { name="EUI_Rebuke", icon="Interface\\Icons\\spell_holy_rebuke", label="Rebuke\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Rebuke", fixedTooltip="Rebuke" },
    }

    -- Priest (256=Discipline, 257=Holy, 258=Shadow)
    local PRIEST_GEN = {
        { name="EUI_DispelMagic", icon="Interface\\Icons\\spell_holy_dispelmagic", label="Dispel Magic\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Dispel Magic", fixedTooltip="Dispel Magic" },
        { name="EUI_PowerInfusion", icon="Interface\\Icons\\spell_holy_powerinfusion", label="Power Infusion\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Power Infusion", fixedTooltip="Power Infusion" },
        { name="EUI_LeapOfFaith", icon="Interface\\Icons\\priest_spell_leapoffaith_a", label="Leap of Faith\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Leap of Faith", fixedTooltip="Leap of Faith" },
        { name="EUI_MassDispel", icon="Interface\\Icons\\spell_arcane_massdispel", label="Mass Dispel\n(Cursor)", fixedBody="/cast [@cursor] Mass Dispel", fixedTooltip="Mass Dispel" },
        { name="EUI_FeatherSelf", icon="Interface\\Icons\\ability_priest_angelicfeather", label="Angelic Feather\n(Self)", fixedBody="/cast [@player] Angelic Feather\n/stopspelltarget", fixedTooltip="Angelic Feather" },
        { name="EUI_FeatherCursor", icon="Interface\\Icons\\ability_priest_angelicfeather", label="Angelic Feather\n(Cursor)", fixedBody="/cast [@cursor] Angelic Feather\n/stopspelltarget", fixedTooltip="Angelic Feather" },
        { name="EUI_Purify", icon="Interface\\Icons\\spell_holy_purify", label="Purify\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Purify", fixedTooltip="Purify" },
    }
    local PRIEST_DISC = {
        { name="EUI_PainSuppress", icon="Interface\\Icons\\spell_holy_painsupression", label="Pain Suppression\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Pain Suppression", fixedTooltip="Pain Suppression" },
        { name="EUI_PWBarrier", icon="Interface\\Icons\\spell_holy_powerwordbarrier", label="PW: Barrier\n(Cursor)", fixedBody="/cast [@cursor] Power Word: Barrier", fixedTooltip="Power Word: Barrier" },
    }
    local PRIEST_HOLY = {
        { name="EUI_GuardSpirit", icon="Interface\\Icons\\spell_holy_guardianspirit", label="Guardian Spirit\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Guardian Spirit", fixedTooltip="Guardian Spirit" },
        { name="EUI_HWSanctify", icon="Interface\\Icons\\spell_holy_divineprovidence", label="Holy Word:\nSanctify (Cursor)", fixedBody="/cast [@cursor] Holy Word: Sanctify", fixedTooltip="Holy Word: Sanctify" },
    }
    local PRIEST_SHADOW = {
        { name="EUI_Silence", icon="Interface\\Icons\\ability_priest_silence", label="Silence\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Silence", fixedTooltip="Silence" },
        { name="EUI_PurifyDisease", icon="Interface\\Icons\\spell_holy_nullifydisease", label="Purify Disease\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Purify Disease", fixedTooltip="Purify Disease" },
    }

    -- Rogue (259=Assassination, 260=Outlaw, 261=Subtlety)
    local ROGUE_GEN = {
        { name="EUI_Kick", icon="Interface\\Icons\\ability_kick", label="Kick\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Kick", fixedTooltip="Kick" },
        { name="EUI_TricksOfTrade", icon="Interface\\Icons\\ability_rogue_tricksofthetrade", label="Tricks of Trade\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Tricks of the Trade", fixedTooltip="Tricks of the Trade" },
        { name="EUI_DistractCursor", icon="Interface\\Icons\\ability_rogue_distract", label="Distract\n(Cursor)", fixedBody="/cast [@cursor] Distract", fixedTooltip="Distract" },
    }
    local ROGUE_ASS = {
    }
    local ROGUE_OUTLAW = {
        { name="EUI_GrapplingHook", icon="Interface\\Icons\\ability_rogue_grapplinghook", label="Grappling Hook\n(Cursor)", fixedBody="/cast [@cursor] Grappling Hook", fixedTooltip="Grappling Hook" },
    }
    local ROGUE_SUB = {
        { name="EUI_CoupDeGrace", icon="Interface\\Icons\\ability_rogue_coupdetat", label="Coup de Grace\n+ Black Powder", fixedBody="/cast Coup de Grace\n/cast Black Powder" },
        { name="EUI_EasyStealth", icon="Interface\\Icons\\ability_stealth", label="Easy Stealth", fixedBody="/cancelaura [nocombat] Shadow Dance\n/cast !Stealth", fixedTooltip="Stealth" },
    }

    -- Shaman (262=Elemental, 263=Enhancement, 264=Restoration)
    local SHAMAN_GEN = {
        { name="EUI_WindShear", icon="Interface\\Icons\\spell_nature_cyclonestrikes", label="Wind Shear\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Wind Shear", fixedTooltip="Wind Shear" },
        { name="EUI_Purge", icon="Interface\\Icons\\spell_nature_purge", label="Purge\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Purge", fixedTooltip="Purge" },
        { name="EUI_CleanseSpirit", icon="Interface\\Icons\\ability_shaman_cleansespirit", label="Cleanse Spirit\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Cleanse Spirit", fixedTooltip="Cleanse Spirit" },
        { name="EUI_WindrushTotem", icon="Interface\\Icons\\ability_shaman_windwalktotem", label="Windrush Totem\n(Cursor)", fixedBody="/cast [@cursor] Wind Rush Totem", fixedTooltip="Wind Rush Totem" },
        { name="EUI_CapacitorTotem", icon="Interface\\Icons\\spell_nature_brilliance", label="Capacitor Totem\n(Cursor)", fixedBody="/cast [@cursor] Capacitor Totem", fixedTooltip="Capacitor Totem" },
    }
    local SHAMAN_ELE = {
        { name="EUI_EarthquakeCursor", icon="Interface\\Icons\\spell_shaman_earthquake", label="Earthquake\n(Cursor)", fixedBody="/cast [@cursor] Earthquake", fixedTooltip="Earthquake" },
    }
    local SHAMAN_ENH = {
        { name="EUI_AutoTotemMove", icon="Interface\\Icons\\ability_shaman_totemrelocation", label="Auto Totem Move\nfor Totemic", fixedBody="/cast Stormstrike\n/cast [@player] Totemic Projection" },
    }
    local SHAMAN_RESTO = {
        { name="EUI_HealingRain", icon="Interface\\Icons\\spell_nature_giftofthewaterspirit", label="Healing Rain\n(Cursor)", fixedBody="/cast [@cursor] Healing Rain", fixedTooltip="Healing Rain" },
        { name="EUI_SpiritLink", icon="Interface\\Icons\\spell_shaman_spiritlink", label="Spirit Link Totem\n(Cursor)", fixedBody="/cast [@cursor] Spirit Link Totem", fixedTooltip="Spirit Link Totem" },
    }

    -- Warlock (265=Affliction, 266=Demonology, 267=Destruction)
    local LOCK_GEN = {
        { name="EUI_Shadowfury", icon="Interface\\Icons\\spell_shadow_shadowfury", label="Shadowfury\n(Cursor)", fixedBody="/cast [@cursor] Shadowfury" },
        { name="EUI_DemonicGateway", icon="Interface\\Icons\\spell_warlock_demonicportal_green", label="Demonic Gateway\n(Cursor)", fixedBody="/cast [@cursor] Demonic Gateway" },
        { name="EUI_SoulburnHS", icon="Interface\\Icons\\spell_warlock_soulburn", label="Soulburn\nHealthstone", fixedBody="/cast [known:Soulburn] Soulburn\n/use [known:Pact of Gluttony] Demonic Healthstone; Healthstone", fixedTooltip="[known:Pact of Gluttony] Demonic Healthstone; Healthstone" },
    }
    local LOCK_DEMO = {
        { name="EUI_AxeToss", icon="Interface\\Icons\\ability_warrior_titansgrip", label="Axe Toss\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Axe Toss", fixedTooltip="Axe Toss" },
    }
    local LOCK_DESTRO = {
        { name="EUI_Havoc", icon="Interface\\Icons\\ability_warlock_baneofhavoc", label="Havoc\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Havoc", fixedTooltip="Havoc" },
        { name="EUI_SummonInfernal", icon="Interface\\Icons\\spell_shadow_summoninfernal", label="Summon Infernal\n(Cursor)", fixedBody="/cast [@cursor] Summon Infernal" },
        { name="EUI_RainOfFire", icon="Interface\\Icons\\spell_shadow_rainoffire", label="Rain of Fire\n(Cursor)", fixedBody="/cast [@cursor] Rain of Fire" },
        { name="EUI_Cataclysm", icon="Interface\\Icons\\achievement_zone_cataclysm", label="Cataclysm\n(Cursor)", fixedBody="/cast [@cursor] Cataclysm" },
    }

    -- Warrior (71=Arms, 72=Fury, 73=Protection)
    local WARRIOR_GEN = {
        { name="EUI_Pummel", icon="Interface\\Icons\\inv_gauntlets_04", label="Pummel\n(Focus)", fixedBody="/cast [@focus,harm,nodead][] Pummel", fixedTooltip="Pummel" },
        { name="EUI_Intervene", icon="Interface\\Icons\\ability_warrior_safeguard", label="Intervene\n(Focus)", fixedBody="/cast [@focus,help,nodead][] Intervene", fixedTooltip="Intervene" },
        { name="EUI_HeroicLeap", icon="Interface\\Icons\\ability_heroicleap", label="Heroic Leap\n(Cursor)", fixedBody="/cast [@cursor] Heroic Leap", fixedTooltip="Heroic Leap" },
    }
    local WARRIOR_ARMS = {
    }
    local WARRIOR_FURY = {
    }
    local WARRIOR_PROT = {
    }

    local SPEC_DEFS = {
        -- Death Knight
        [250] = mergeMacros(DK_BLOOD, DK_GEN),
        [251] = mergeMacros(DK_FROST, DK_GEN),
        [252] = mergeMacros(DK_UNHOLY, DK_GEN),
        -- Demon Hunter
        [577] = mergeMacros(DH_HAVOC, DH_DEVOURER, DH_GEN),
        [581] = mergeMacros(DH_VENG, DH_DEVOURER, DH_GEN),
        -- Druid
        [102] = mergeMacros(DRUID_BAL, DRUID_GEN),
        [103] = mergeMacros(DRUID_FERAL, DRUID_GEN),
        [104] = mergeMacros(DRUID_GUARD, DRUID_GEN),
        [105] = mergeMacros(DRUID_RESTO, DRUID_GEN),
        -- Evoker
        [1467] = mergeMacros(EVOKER_DEV, EVOKER_GEN),
        [1468] = mergeMacros(EVOKER_PRES, EVOKER_GEN),
        [1473] = mergeMacros(EVOKER_AUG, EVOKER_GEN),
        -- Hunter
        [253] = mergeMacros(HUNTER_BM, HUNTER_GEN),
        [254] = mergeMacros(HUNTER_MM, HUNTER_GEN),
        [255] = mergeMacros(HUNTER_SURV, HUNTER_GEN),
        -- Mage
        [62]  = mergeMacros(MAGE_ARCANE, MAGE_GEN),
        [63]  = mergeMacros(MAGE_FIRE, MAGE_GEN),
        [64]  = mergeMacros(MAGE_FROST_SPEC, MAGE_GEN),
        -- Monk
        [268] = mergeMacros(MONK_BREW, MONK_GEN),
        [269] = mergeMacros(MONK_WW, MONK_GEN),
        [270] = mergeMacros(MONK_MW, MONK_GEN),
        -- Paladin
        [65]  = mergeMacros(PALA_HOLY, PALA_GEN),
        [66]  = mergeMacros(PALA_PROT, PALA_GEN),
        [70]  = mergeMacros(PALA_RET, PALA_GEN),
        -- Priest
        [256] = mergeMacros(PRIEST_DISC, PRIEST_GEN),
        [257] = mergeMacros(PRIEST_HOLY, PRIEST_GEN),
        [258] = mergeMacros(PRIEST_SHADOW, PRIEST_GEN),
        -- Rogue
        [259] = mergeMacros(ROGUE_ASS, ROGUE_GEN),
        [260] = mergeMacros(ROGUE_OUTLAW, ROGUE_GEN),
        [261] = mergeMacros(ROGUE_SUB, ROGUE_GEN),
        -- Shaman
        [262] = mergeMacros(SHAMAN_ELE, SHAMAN_GEN),
        [263] = mergeMacros(SHAMAN_ENH, SHAMAN_GEN),
        [264] = mergeMacros(SHAMAN_RESTO, SHAMAN_GEN),
        -- Warlock
        [265] = mergeMacros(LOCK_GEN),
        [266] = mergeMacros(LOCK_DEMO, LOCK_GEN),
        [267] = mergeMacros(LOCK_DESTRO, LOCK_GEN),
        -- Warrior
        [71]  = mergeMacros(WARRIOR_ARMS, WARRIOR_GEN),
        [72]  = mergeMacros(WARRIOR_FURY, WARRIOR_GEN),
        [73]  = mergeMacros(WARRIOR_PROT, WARRIOR_GEN),
    }

    -- Detect current spec and class
    local specIndex = GetSpecialization()
    local activeSpecID, activeSpecName
    if specIndex then
        activeSpecID, activeSpecName = GetSpecializationInfo(specIndex)
    end
    local activeClassName = UnitClass("player") or "Unknown"
    local isEnglishClient = (GetLocale() == "enUS" or GetLocale() == "enGB")
    local activeSpecDefs = isEnglishClient and activeSpecID and SPEC_DEFS[activeSpecID] or {}

    ---------------------------------------------------------------------------
    --  DB helper (shared across all buttons and event handlers)
    ---------------------------------------------------------------------------
    local function GetMacroDB(macroName)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.macroFactory then EllesmereUIDB.macroFactory = {} end
        if not EllesmereUIDB.macroFactory[macroName] then EllesmereUIDB.macroFactory[macroName] = {} end
        return EllesmereUIDB.macroFactory[macroName]
    end

    ---------------------------------------------------------------------------
    --  Macro body generation
    ---------------------------------------------------------------------------
    local function GetFirstAvailableItemID(def, db)
        if not def.checkboxes then return nil end
        local cbs = def.checkboxes
        local order = db.order
        if not order or #order < #cbs then
            order = {}
            for i = 1, #cbs do order[i] = i end
        end
        for _, idx in ipairs(order) do
            local cb = cbs[idx]
            if cb and db[cb.key] ~= false then
                for _, itemID in ipairs(cb.items) do
                    if (GetItemCount(itemID, false) or 0) > 0 then
                        return itemID
                    end
                end
            end
        end
        return nil
    end

    local function BuildMacroBody(def, db)
        if def.checkboxes then
            local cbs = def.checkboxes
            local order = db.order
            if not order or #order < #cbs then
                order = {}
                for i = 1, #cbs do order[i] = i end
            end

            -- Collect all enabled items
            local availItems = {}
            local firstItemID
            for _, idx in ipairs(order) do
                local cb = cbs[idx]
                if cb and db[cb.key] ~= false then
                    for _, itemID in ipairs(cb.items) do
                        if not firstItemID then firstItemID = itemID end
                        availItems[#availItems + 1] = itemID
                    end
                end
            end

            if #availItems == 0 and not firstItemID then return "" end

            local body = ""
            if db.showTooltip ~= false then
                local tipID = GetFirstAvailableItemID(def, db) or firstItemID
                if tipID then body = "#showtooltip item:" .. tipID .. "\n" end
            end
            local lines = {}
            for _, itemID in ipairs(availItems) do
                lines[#lines + 1] = "/use item:" .. itemID
            end
            if #lines == 0 then return "" end
            return body .. table.concat(lines, "\n")
        elseif def.fixedBody then
            local body = ""
            if db.showTooltip ~= false and def.fixedTooltip then
                body = "#showtooltip " .. def.fixedTooltip .. "\n"
            elseif db.showTooltip ~= false then
                body = "#showtooltip\n"
            end
            return body .. def.fixedBody
        end
        return ""
    end

    local pendingMacroUpdates = {}

    local function UpdateMacro(def, db)
        local idx = GetMacroIndexByName(def.name)
        if idx ~= 0 then
            if InCombatLockdown() then
                pendingMacroUpdates[def.name] = true
            else
                EditMacro(idx, nil, nil, BuildMacroBody(def, db))
            end
        end
    end

    local function ProcessPendingMacroUpdates()
        for macroName in pairs(pendingMacroUpdates) do
            local mdef = nil
            for _, def in ipairs(GENERAL_DEFS) do
                if def.name == macroName then
                    mdef = def
                    break
                end
            end
            if mdef then
                local idx = GetMacroIndexByName(mdef.name)
                if idx ~= 0 then
                    local db = GetMacroDB(mdef.name)
                    EditMacro(idx, nil, nil, BuildMacroBody(mdef, db))
                end
            end
            pendingMacroUpdates[macroName] = nil
        end
    end

    ---------------------------------------------------------------------------
    --  Layout
    ---------------------------------------------------------------------------
    local MAX_SPEC_VISIBLE_ROWS = 3
    local generalRows = math.ceil(#GENERAL_DEFS / ICONS_PER_ROW)
    local specRows = #activeSpecDefs > 0 and math.ceil(#activeSpecDefs / SPEC_ICONS_PER_ROW) or 0
    local visibleSpecRows = math.min(specRows, MAX_SPEC_VISIBLE_ROWS)
    local maxRows = math.max(generalRows, visibleSpecRows)
    local SECTION_H = 102 + ROW_STRIDE * (maxRows - 1)

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(parent:GetWidth(), SECTION_H)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    local halfW = parent:GetWidth() / 2
    local allMacroButtons = {}
    local lastAvailableItems = {}

    -- Center divider (1px absolute pixel)
    local divider = container:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOP", container, "TOP", 0, 0)
    divider:SetPoint("BOTTOM", container, "BOTTOM", 0, 0)
    divider:SetColorTexture(1, 1, 1, 0.15)
    if divider.SetSnapToPixelGrid then
        divider:SetSnapToPixelGrid(false)
        divider:SetTexelSnappingBias(0)
    end

    ---------------------------------------------------------------------------
    --  BuildMacroGroup: creates a titled grid of macro icons
    ---------------------------------------------------------------------------
    local function BuildMacroGroup(defs, anchorSide, titleText, perRow, gap, maxVisibleRows)
        perRow = perRow or ICONS_PER_ROW
        gap = gap or ICON_GAP
        local isLeft = (anchorSide == "LEFT")
        local centerX = isLeft and (halfW / 2) or (halfW + halfW / 2)

        local titleFS = container:CreateFontString(nil, "OVERLAY")
        titleFS:SetFont(fontPath, 16, "")
        titleFS:SetTextColor(1, 1, 1, 1)
        titleFS:SetPoint("TOP", container, "TOPLEFT", centerX, 0)
        titleFS:SetText(titleText)

        local numIcons = #defs
        local totalRows = math.ceil(numIcons / perRow)

        -- Scrollable viewport when content exceeds maxVisibleRows
        local iconParent = container
        local iconAnchor = container
        local scrollCenterX = centerX
        if maxVisibleRows and totalRows > maxVisibleRows then
            local SCROLL_STEP_LOCAL = 45
            local SMOOTH_SPEED_LOCAL = 12

            local visH = math.abs(FIRST_ICON_Y) + maxVisibleRows * ROW_STRIDE
            local contentH = math.abs(FIRST_ICON_Y) + totalRows * ROW_STRIDE

            local sf = CreateFrame("ScrollFrame", nil, container)
            sf:SetPoint("TOPLEFT", container, isLeft and "TOPLEFT" or "TOP", 0, FIRST_ICON_Y + ICON_SIZE / 2 + 4)
            sf:SetSize(halfW, visH)
            sf:SetFrameLevel(container:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            sf:SetClipsChildren(true)

            local sc = CreateFrame("Frame", nil, sf)
            sc:SetSize(halfW, contentH)
            sf:SetScrollChild(sc)

            -- Scrollbar track
            local scrollTrack = CreateFrame("Frame", nil, sf)
            scrollTrack:SetWidth(4)
            scrollTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -70, -32)
            scrollTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -70, 8)
            scrollTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
            scrollTrack:Hide()
            local trackBg = scrollTrack:CreateTexture(nil, "BACKGROUND")
            trackBg:SetAllPoints(); trackBg:SetColorTexture(1, 1, 1, 0.02)

            local scrollThumb = CreateFrame("Button", nil, scrollTrack)
            scrollThumb:SetWidth(4); scrollThumb:SetHeight(60)
            scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
            scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
            scrollThumb:EnableMouse(true)
            scrollThumb:RegisterForDrag("LeftButton")
            scrollThumb:SetScript("OnDragStart", function() end)
            scrollThumb:SetScript("OnDragStop", function() end)
            local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
            thumbTex:SetAllPoints(); thumbTex:SetColorTexture(1, 1, 1, 0.27)

            local scrollTarget = 0
            local isSmoothing = false
            local smoothFrame = CreateFrame("Frame"); smoothFrame:Hide()

            local function UpdateThumb()
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
                if maxScroll <= 0 then scrollTrack:Hide(); return end
                scrollTrack:Show()
                local trackH = scrollTrack:GetHeight()
                local ratio = visH / (visH + maxScroll)
                local thumbH = math.max(30, trackH * ratio)
                scrollThumb:SetHeight(thumbH)
                local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
                scrollThumb:ClearAllPoints()
                scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
            end

            smoothFrame:SetScript("OnUpdate", function(_, elapsed)
                local cur = sf:GetVerticalScroll()
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
                scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
                local diff = scrollTarget - cur
                if math.abs(diff) < 0.3 then
                    sf:SetVerticalScroll(scrollTarget)
                    UpdateThumb()
                    isSmoothing = false
                    smoothFrame:Hide()
                    return
                end
                local newScroll = cur + diff * math.min(1, SMOOTH_SPEED_LOCAL * elapsed)
                newScroll = math.max(0, math.min(maxScroll, newScroll))
                sf:SetVerticalScroll(newScroll)
                UpdateThumb()
            end)

            local function SmoothScrollTo(target)
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
                scrollTarget = math.max(0, math.min(maxScroll, target))
                if not isSmoothing then isSmoothing = true; smoothFrame:Show() end
            end

            sf:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = EllesmereUI.SafeScrollRange(self)
                if maxScroll <= 0 then return end
                local base = isSmoothing and scrollTarget or self:GetVerticalScroll()
                SmoothScrollTo(base - delta * SCROLL_STEP_LOCAL)
            end)
            sf:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

            -- Thumb drag
            local isDragging = false
            local dragStartY, dragStartScroll
            local function StopDrag()
                if not isDragging then return end
                isDragging = false
                scrollThumb:SetScript("OnUpdate", nil)
            end
            scrollThumb:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                isSmoothing = false; smoothFrame:Hide()
                isDragging = true
                local _, cy = GetCursorPosition()
                dragStartY = cy / self:GetEffectiveScale()
                dragStartScroll = sf:GetVerticalScroll()
                self:SetScript("OnUpdate", function(self2)
                    if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
                    isSmoothing = false; smoothFrame:Hide()
                    local _, cy2 = GetCursorPosition()
                    cy2 = cy2 / self2:GetEffectiveScale()
                    local deltaY = dragStartY - cy2
                    local trackH = scrollTrack:GetHeight()
                    local maxTravel = trackH - self2:GetHeight()
                    if maxTravel <= 0 then return end
                    local maxScroll = EllesmereUI.SafeScrollRange(sf)
                    local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + (deltaY / maxTravel) * maxScroll))
                    scrollTarget = newScroll
                    sf:SetVerticalScroll(newScroll)
                    UpdateThumb()
                end)
            end)
            scrollThumb:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then StopDrag() end
            end)

            iconParent = sc
            iconAnchor = sc
            scrollCenterX = halfW / 2
        end

        for gi, def in ipairs(defs) do
            local rowIdx = math.floor((gi - 1) / perRow)
            local colIdx = (gi - 1) % perRow
            local iconsInRow = math.min(perRow, numIcons - rowIdx * perRow)
            local rowW = iconsInRow * ICON_SIZE + (iconsInRow - 1) * gap
            local iconX = scrollCenterX - rowW / 2 + ICON_SIZE / 2 + colIdx * (ICON_SIZE + gap)
            local iconY = FIRST_ICON_Y - rowIdx * ROW_STRIDE

            local btn = CreateFrame("Button", nil, iconParent)
            PP.Size(btn, ICON_SIZE, ICON_SIZE)
            btn:SetPoint("TOP", iconAnchor, "TOPLEFT", iconX, iconY)
            btn:SetFrameLevel(iconParent:GetFrameLevel() + 5)

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(); tex:SetTexture(def.macroIcon or def.icon); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._tex = tex

            local bdr = CreateFrame("Frame", nil, btn)
            bdr:SetAllPoints(); bdr:SetFrameLevel(btn:GetFrameLevel() + 1)
            PP.CreateBorder(bdr, 0, 0, 0, 1, 1)

            local hoverBdr = CreateFrame("Frame", nil, btn)
            hoverBdr:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
            hoverBdr:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
            hoverBdr:SetFrameLevel(btn:GetFrameLevel() + 2)
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            PP.CreateBorder(hoverBdr, ar, ag, ab, 1, 2)
            hoverBdr:Hide()
            btn._hoverBdr = hoverBdr

            local labelFS = iconParent:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(fontPath, 13, ""); labelFS:SetTextColor(1, 1, 1, 0.9)
            labelFS:SetPoint("TOP", btn, "BOTTOM", 0, -4)
            local flatLabel = def.label:gsub("\n", " ")
            if #flatLabel > 12 then flatLabel = flatLabel:sub(1, 12) .. ".." end
            labelFS:SetText(flatLabel)
            btn._label = labelFS

            -- Flash system (OnUpdate, no AnimationGroup)
            local flashFS = iconParent:CreateFontString(nil, "OVERLAY")
            flashFS:SetFont(fontPath, 9, ""); flashFS:SetTextColor(1, 1, 1, 0)
            flashFS:SetPoint("TOP", btn, "BOTTOM", 0, -4); flashFS:Hide()
            local flashTex = btn:CreateTexture(nil, "OVERLAY")
            flashTex:SetAllPoints(); flashTex:SetColorTexture(1, 1, 1, 0)
            local flashDriver = CreateFrame("Frame", nil, iconParent); flashDriver:Hide()
            local flashElapsed = 0
            flashDriver:SetScript("OnUpdate", function(self, dt)
                flashElapsed = flashElapsed + dt
                if flashElapsed < 0.08 then flashTex:SetColorTexture(1, 1, 1, 0.7 * (flashElapsed / 0.08))
                elseif flashElapsed < 0.38 then flashTex:SetColorTexture(1, 1, 1, 0.7 * (1 - (flashElapsed - 0.08) / 0.3))
                else flashTex:SetColorTexture(1, 1, 1, 0) end
                if flashElapsed < 0.15 then flashFS:SetTextColor(1, 1, 1, flashElapsed / 0.15)
                elseif flashElapsed < 0.95 then flashFS:SetTextColor(1, 1, 1, 1)
                elseif flashElapsed < 1.55 then flashFS:SetTextColor(1, 1, 1, 1 - (flashElapsed - 0.95) / 0.6)
                else flashFS:Hide(); flashTex:SetColorTexture(1, 1, 1, 0); btn._label:Show(); self:Hide() end
            end)
            local function PlayFlash()
                flashElapsed = 0; flashFS:SetText("Macro Created"); flashFS:SetTextColor(1, 1, 1, 0)
                flashFS:Show(); btn._label:Hide(); flashDriver:Show()
            end
            btn._playFlash = PlayFlash

            -- State
            local function MacroExists() return GetMacroIndexByName(def.name) ~= 0 end
            local function RefreshState()
                local exists = MacroExists()
                tex:SetDesaturated(exists)
                btn._isGray = exists
            end

            local function GetDB() return GetMacroDB(def.name) end

            -- Dynamic icon: show the first selected item or equipped trinket
            local function RefreshIcon()
                local db = GetDB()
                local icon
                if def.checkboxes then
                    local cbs = def.checkboxes
                    local order = db.order
                    if not order or #order < #cbs then
                        order = {}
                        for i = 1, #cbs do order[i] = i end
                    end
                    for _, idx in ipairs(order) do
                        local cb = cbs[idx]
                        if cb and db[cb.key] ~= false and cb.items and cb.items[1] then
                            icon = C_Item.GetItemIconByID(cb.items[1])
                            if icon then break end
                        end
                    end
                elseif def.fixedTooltip then
                    local slot = tonumber(def.fixedTooltip)
                    if slot then
                        icon = GetInventoryItemTexture("player", slot)
                    end
                end
                tex:SetTexture(icon or def.macroIcon or def.icon)
            end
            btn._refreshIcon = RefreshIcon
            RefreshIcon()

            -------------------------------------------------------------------
            --  Right-click dropdown menu (lazy-built)
            -------------------------------------------------------------------
            local menuFrame
            local function BuildMenu()
                if menuFrame then return end
                local MH, DH, HH, MW = 28, 14, 20, 240
                local cbItems = def.checkboxes
                local hasCheckboxes = cbItems and #cbItems > 0

                local menuH = 4 + MH + MH + 4
                if hasCheckboxes then
                    menuH = menuH + DH + HH + (#cbItems * MH)
                end

                menuFrame = CreateFrame("Frame", nil, UIParent)
                menuFrame:SetFrameStrata("FULLSCREEN_DIALOG"); menuFrame:SetFrameLevel(200)
                menuFrame:SetClampedToScreen(true); menuFrame:EnableMouse(true)
                menuFrame:SetSize(MW, menuH)
                menuFrame:Hide()
                local mBg = menuFrame:CreateTexture(nil, "BACKGROUND"); mBg:SetAllPoints()
                mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA or 0.92)
                EllesmereUI.MakeBorder(menuFrame, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
                local mY = -4

                -- Create/Delete action row
                local aR = CreateFrame("Button", nil, menuFrame)
                aR:SetHeight(MH); aR:SetFrameLevel(menuFrame:GetFrameLevel() + 2)
                aR:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                aR:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                local aL = aR:CreateFontString(nil, "OVERLAY")
                aL:SetFont(fontPath, 13, ""); aL:SetTextColor(0.75, 0.75, 0.75, 1)
                aL:SetPoint("LEFT", aR, "LEFT", 12, 0)
                local aHL = aR:CreateTexture(nil, "ARTWORK"); aHL:SetAllPoints(); aHL:SetColorTexture(1, 1, 1, 0)
                local function RefAct()
                    if MacroExists() then aL:SetText("|cffff4444Delete Macro|r") else aL:SetText("Create Macro") end
                end
                RefAct(); menuFrame._refreshAction = RefAct
                aR:SetScript("OnEnter", function() aL:SetTextColor(1, 1, 1, 1); aHL:SetColorTexture(1, 1, 1, 0.04) end)
                aR:SetScript("OnLeave", function() RefAct(); aHL:SetColorTexture(1, 1, 1, 0) end)
                aR:SetScript("OnClick", function()
                    if InCombatLockdown() then return end
                    if MacroExists() then
                        DeleteMacro(def.name)
                    else
                        local db = GetDB()
                        CreateMacro(def.name, def.macroIcon or "INV_MISC_QUESTIONMARK", BuildMacroBody(def, db), nil)
                        lastAvailableItems[def.name] = GetFirstAvailableItemID(def, db)
                        PlayFlash()
                        C_Timer.After(0.15, function()
                            if not InCombatLockdown() then ShowMacroFrame() end
                        end)
                    end
                    C_Timer.After(0.1, function() RefreshState(); RefAct() end)
                end)
                mY = mY - MH

                -- Show Tooltip checkbox
                local tR = CreateFrame("Button", nil, menuFrame)
                tR:SetHeight(MH); tR:SetFrameLevel(menuFrame:GetFrameLevel() + 2)
                tR:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                tR:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                local tB = CreateFrame("Frame", nil, tR); tB:SetSize(16, 16); tB:SetPoint("RIGHT", tR, "RIGHT", -10, 0)
                local tBg = tB:CreateTexture(nil, "BACKGROUND"); tBg:SetAllPoints(); tBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                local tBrd = EllesmereUI.MakeBorder(tB, 0.4, 0.4, 0.4, 0.6, PP)
                local tCk = tB:CreateTexture(nil, "ARTWORK"); PP.SetInside(tCk, tB, 2, 2)
                tCk:SetColorTexture(EG.r, EG.g, EG.b, 1); tCk:SetSnapToPixelGrid(false)
                local tL = tR:CreateFontString(nil, "OVERLAY"); tL:SetFont(fontPath, 13, "")
                tL:SetTextColor(0.75, 0.75, 0.75, 1); tL:SetPoint("LEFT", tR, "LEFT", 12, 0); tL:SetText("Show Tooltip")
                local tHL = tR:CreateTexture(nil, "ARTWORK"); tHL:SetAllPoints(); tHL:SetColorTexture(1, 1, 1, 0)
                local function RefTT()
                    local db = GetDB()
                    if db.showTooltip ~= false then tCk:Show(); tBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                    else tCk:Hide(); tBrd:SetColor(0.4, 0.4, 0.4, 0.6) end
                end
                RefTT()
                tR:SetScript("OnEnter", function() tL:SetTextColor(1, 1, 1, 1); tHL:SetColorTexture(1, 1, 1, 0.04) end)
                tR:SetScript("OnLeave", function() tL:SetTextColor(0.75, 0.75, 0.75, 1); tHL:SetColorTexture(1, 1, 1, 0) end)
                tR:SetScript("OnClick", function()
                    local db = GetDB()
                    if db.showTooltip ~= false then db.showTooltip = false
                    else db.showTooltip = true end
                    RefTT()
                    UpdateMacro(def, db)
                end)
                mY = mY - MH

                -- Item checkboxes (only for item-based macros)
                if hasCheckboxes then
                    -- Divider
                    local dv = CreateFrame("Frame", nil, menuFrame); dv:SetHeight(DH)
                    dv:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                    dv:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                    local dl = dv:CreateTexture(nil, "ARTWORK"); dl:SetHeight(1)
                    dl:SetPoint("LEFT", dv, "LEFT", 10, 0); dl:SetPoint("RIGHT", dv, "RIGHT", -10, 0)
                    dl:SetColorTexture(1, 1, 1, 0.08)
                    mY = mY - DH

                    -- Hint text
                    local ht = CreateFrame("Frame", nil, menuFrame); ht:SetHeight(HH)
                    ht:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                    ht:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                    local hfs = ht:CreateFontString(nil, "OVERLAY"); hfs:SetFont(fontPath, 10, "")
                    hfs:SetTextColor(1, 1, 1, 0.25); hfs:SetPoint("CENTER"); hfs:SetText("Drag to Reorder")
                    mY = mY - HH

                    -- Checkbox rows with drag reorder
                    local cbBaseY = mY
                    local rowFrames = {}
                    local isDragging = false
                    local insLine = menuFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    insLine:SetHeight(2); insLine:SetColorTexture(EG.r, EG.g, EG.b, 0.9); insLine:Hide()

                    for ci, cb in ipairs(cbItems) do
                        local row = CreateFrame("Button", nil, menuFrame)
                        row:SetHeight(MH); row._baseY = mY; row._cbIndex = ci; row._cb = cb
                        row:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                        row:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                        row:SetFrameLevel(menuFrame:GetFrameLevel() + 2)

                        local rl = row:CreateFontString(nil, "OVERLAY"); rl:SetFont(fontPath, 13, "")
                        rl:SetTextColor(0.75, 0.75, 0.75, 1); rl:SetPoint("LEFT", row, "LEFT", 12, 0); rl:SetText(cb.label)
                        local rb = CreateFrame("Frame", nil, row); rb:SetSize(16, 16); rb:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                        local rBg = rb:CreateTexture(nil, "BACKGROUND"); rBg:SetAllPoints(); rBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                        local rBrd = EllesmereUI.MakeBorder(rb, 0.4, 0.4, 0.4, 0.6, PP)
                        local rCk = rb:CreateTexture(nil, "ARTWORK"); PP.SetInside(rCk, rb, 2, 2)
                        rCk:SetColorTexture(EG.r, EG.g, EG.b, 1); rCk:SetSnapToPixelGrid(false)
                        local rHL = row:CreateTexture(nil, "ARTWORK"); rHL:SetAllPoints(); rHL:SetColorTexture(1, 1, 1, 0)

                        local function UC()
                            local db = GetDB()
                            local key = row._cb.key
                            if db[key] ~= false then rCk:Show(); rBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                            else rCk:Hide(); rBrd:SetColor(0.4, 0.4, 0.4, 0.6) end
                        end
                        UC(); row._updateCheck = UC; row._lbl = rl

                        row:SetScript("OnEnter", function()
                            if isDragging then return end
                            rl:SetTextColor(1, 1, 1, 1); rHL:SetColorTexture(1, 1, 1, 0.04)
                        end)
                        row:SetScript("OnLeave", function()
                            if isDragging then return end
                            rl:SetTextColor(0.75, 0.75, 0.75, 1); rHL:SetColorTexture(1, 1, 1, 0)
                        end)
                        row:SetScript("OnClick", function()
                            if isDragging then return end
                            local db = GetDB()
                            local key = row._cb.key
                            if db[key] ~= false then db[key] = false
                            else db[key] = true end
                            UC()
                            UpdateMacro(def, db)
                            RefreshIcon()
                        end)

                        -- Drag (3px threshold via OnMouseDown/Up/Update)
                        local dsY, dgO
                        row:SetScript("OnMouseDown", function(_, b)
                            if b ~= "LeftButton" then return end
                            local _, cy = GetCursorPosition(); dsY = cy
                        end)
                        row:SetScript("OnMouseUp", function(self, b)
                            if b ~= "LeftButton" then return end
                            dsY = nil
                            if not isDragging then return end
                            isDragging = false; insLine:Hide()
                            self:SetFrameLevel(menuFrame:GetFrameLevel() + 2); self:SetAlpha(1)
                            local _, cy = GetCursorPosition()
                            local sc = menuFrame:GetEffectiveScale(); cy = cy / sc
                            local from = self._cbIndex; local to = from
                            for ri, rf in ipairs(rowFrames) do
                                if rf._baseY then
                                    local rm = (menuFrame:GetTop() or 0) + rf._baseY - MH / 2
                                    if cy > rm then to = ri; break end
                                    to = ri
                                end
                            end
                            to = math.max(1, math.min(to, #cbItems))
                            if from ~= to then
                                local db = GetDB()
                                if not db.order then db.order = {}; for oi = 1, #cbItems do db.order[oi] = oi end end
                                local mv = table.remove(db.order, from); table.insert(db.order, to, mv)
                            end
                            local db = GetDB()
                            if not db.order then db.order = {}; for oi = 1, #cbItems do db.order[oi] = oi end end
                            for ri = 1, #rowFrames do
                                local rf = rowFrames[ri]; local oi = db.order[ri]; local it = cbItems[oi]
                                rf._cbIndex = ri; rf._cb = it; rf._lbl:SetText(it.label)
                                local ry = cbBaseY - (ri - 1) * MH; rf._baseY = ry; rf:ClearAllPoints()
                                rf:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, ry)
                                rf:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, ry)
                                rf._updateCheck()
                            end
                            UpdateMacro(def, db)
                            RefreshIcon()
                        end)
                        row:SetScript("OnUpdate", function(self)
                            if not dsY then return end
                            local _, cy = GetCursorPosition()
                            if not isDragging then
                                if math.abs(cy - dsY) < 3 then return end
                                isDragging = true
                                local sc = menuFrame:GetEffectiveScale()
                                dgO = (cy / sc) - (self:GetTop() or 0)
                                self:SetFrameLevel(menuFrame:GetFrameLevel() + 10); self:SetAlpha(0.8)
                                for _, rf in ipairs(rowFrames) do
                                    if rf._lbl then rf._lbl:SetTextColor(0.75, 0.75, 0.75, 1) end
                                end
                            end
                            local sc = menuFrame:GetEffectiveScale()
                            local cY = cy / sc; local mT = menuFrame:GetTop() or 0
                            local lY = cY - (dgO or 0) - mT
                            lY = math.max(cbBaseY - (#cbItems - 1) * MH, math.min(lY, cbBaseY))
                            self:ClearAllPoints()
                            self:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, lY)
                            self:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, lY)
                            local iI = #cbItems
                            for ri, rf in ipairs(rowFrames) do
                                if rf ~= self and rf._baseY then
                                    local rm = mT + rf._baseY - MH / 2
                                    if cY > rm then iI = ri; break end
                                    iI = ri + 1
                                end
                            end
                            iI = math.max(1, math.min(iI, #cbItems + 1))
                            local lnY = (iI <= 1) and (cbBaseY + 1) or (cbBaseY - (iI - 1) * MH + 1)
                            insLine:ClearAllPoints()
                            insLine:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, lnY)
                            insLine:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, lnY)
                            insLine:Show()
                        end)

                        rowFrames[ci] = row; mY = mY - MH
                    end
                end  -- hasCheckboxes

                -- Close on click outside
                menuFrame:SetScript("OnUpdate", function(self)
                    if not self:IsMouseOver() and not btn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                        self:Hide()
                    end
                end)
            end -- BuildMenu

            btn._showMenu = function()
                BuildMenu()
                for _, mb in ipairs(allMacroButtons) do
                    if mb._cogPopup and mb._cogPopup:IsShown() then mb._cogPopup:Hide() end
                end
                if menuFrame:IsShown() then menuFrame:Hide(); return end
                local bs = btn:GetEffectiveScale(); local us = UIParent:GetEffectiveScale()
                menuFrame:SetScale(bs / us); menuFrame:ClearAllPoints()
                menuFrame:SetPoint("TOP", btn, "BOTTOM", 0, -18)
                if menuFrame._refreshAction then menuFrame._refreshAction() end
                menuFrame:Show(); btn._cogPopup = menuFrame
            end

            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnEnter", function(self)
                self._hoverBdr:Show()
                local fullName = def.label:gsub("\n", " ")
                if def.tooltip then
                    local status = self._isGray and "|cff888888Created|r" or "|cff888888Click to create|r"
                    EllesmereUI.ShowWidgetTooltip(self, fullName .. "\n" .. def.tooltip .. "\n" .. status)
                elseif self._isGray then
                    EllesmereUI.ShowWidgetTooltip(self, fullName .. "\n|cff888888Created. Right-click to configure.|r")
                else
                    EllesmereUI.ShowWidgetTooltip(self, fullName .. "\n|cff888888Click to create. Right-click to configure.|r")
                end
            end)
            btn:SetScript("OnLeave", function(self) self._hoverBdr:Hide(); EllesmereUI.HideWidgetTooltip() end)
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then self._showMenu(); return end
                if self._isGray then return end
                if InCombatLockdown() then return end
                local db = GetDB()
                CreateMacro(def.name, def.macroIcon or "INV_MISC_QUESTIONMARK", BuildMacroBody(def, db), nil)
                lastAvailableItems[def.name] = GetFirstAvailableItemID(def, db)
                self._playFlash()
                C_Timer.After(0.1, RefreshState)
                C_Timer.After(0.15, function()
                    if not InCombatLockdown() then ShowMacroFrame() end
                end)
            end)

            RefreshState()
            btn._def = def
            allMacroButtons[#allMacroButtons + 1] = btn
        end -- for gi
    end -- BuildMacroGroup

    -- Build general macros on left side
    BuildMacroGroup(GENERAL_DEFS, "LEFT", "General Macro Factory")

    -- Build spec macros on right side
    if #activeSpecDefs > 0 then
        BuildMacroGroup(activeSpecDefs, "RIGHT", (activeSpecName or "Spec") .. " " .. activeClassName .. " Macro Factory", SPEC_ICONS_PER_ROW, SPEC_ICON_GAP, MAX_SPEC_VISIBLE_ROWS)
    else
        local emptyFS = container:CreateFontString(nil, "OVERLAY")
        emptyFS:SetFont(fontPath, 16, "")
        emptyFS:SetTextColor(1, 1, 1, 0.25)
        emptyFS:SetPoint("CENTER", container, "TOPLEFT", halfW + halfW / 2, -SECTION_H / 2)
        if not isEnglishClient then
            emptyFS:SetText("Spec Macros are currently not supported\nfor non-English clients. Support coming soon!")
        else
            emptyFS:SetText("No spec macros for " .. (activeSpecName or "this spec"))
        end
        emptyFS:SetJustifyH("CENTER")
    end

    -- Update macros when inventory changes
    local function UpdateInventoryDependentMacros()
        for _, btn in ipairs(allMacroButtons) do
            local mdef = btn._def
            if mdef and mdef.checkboxes and btn._tex then
                local idx = GetMacroIndexByName(mdef.name)
                if idx ~= 0 then
                    local db = GetMacroDB(mdef.name)
                    local newAvailableItemID = GetFirstAvailableItemID(mdef, db)
                    local oldAvailableItemID = lastAvailableItems[mdef.name]
                    if newAvailableItemID ~= oldAvailableItemID then
                        lastAvailableItems[mdef.name] = newAvailableItemID
                        UpdateMacro(mdef, db)
                    end
                end
            end
        end
    end

    -- Poll for macro state changes (2s interval)
    local pollFrame = CreateFrame("Frame", nil, container)
    local elapsed = 0
    pollFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 2 then return end
        elapsed = 0
        for _, btn in ipairs(allMacroButtons) do
            local mdef = btn._def
            if mdef and btn._tex then
                local ex = GetMacroIndexByName(mdef.name) ~= 0
                if btn._isGray and not ex then btn._tex:SetDesaturated(false); btn._isGray = false
                elseif not btn._isGray and ex then btn._tex:SetDesaturated(true); btn._isGray = true end
                if btn._refreshIcon then btn._refreshIcon() end
                if btn._cogPopup and btn._cogPopup:IsShown() and btn._cogPopup._refreshAction then
                    btn._cogPopup._refreshAction()
                end
            end
        end
    end)

    -- Update macros when bag changes (throttled), spec changes, login, or combat ends
    local eventFrame = CreateFrame("Frame", nil, container)
    local bagUpdatePending = false
    eventFrame:RegisterEvent("BAG_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            ProcessPendingMacroUpdates()
            UpdateInventoryDependentMacros()
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            EllesmereUI:RefreshPage()
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(1, UpdateInventoryDependentMacros)
        elseif not bagUpdatePending then
            bagUpdatePending = true
            C_Timer.After(0.5, function()
                bagUpdatePending = false
                UpdateInventoryDependentMacros()
            end)
        end
    end)

    return SECTION_H
end
