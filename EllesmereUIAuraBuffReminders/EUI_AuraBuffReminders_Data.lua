if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Data.lua
--
--  The spell and item tables of the reminders, the Well Fed, flask and
--  eating checks, the bag item counts and the resolved consumable items.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._abrInternals
-- EllesmereUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local AURA_SCAN_LIMIT, EABR, InCombat = I.AURA_SCAN_LIMIT, I.EABR, I.InCombat
local InMythicPlusKey, InPvPInstance, isSecret = I.InMythicPlusKey, I.InPvPInstance, I.isSecret
local SpellName, Tex, _AC, GetWeaponCategory = I.SpellName, I.Tex, I._AC, I.GetWeaponCategory
local IsUnderDuration = I.IsUnderDuration

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  SPELL DATA Raid Buffs (all non-secret in 12.0, work in combat)
-------------------------------------------------------------------------------
-- Resolves a spell's display name from ID in client locale (English fallback), so labels follow client language. Exposed as _G._EABR_SpellName for options.
_G._EABR_SpellName = function(spellID, fallback)
    local n = spellID and SpellName(spellID)
    return n or fallback
end

-- Returns the legacy GetWeaponEnchantInfo tuple shape (hasMH, mhExpireMs, mhCharges, mhEnchantID, hasOH,
-- ohExpireMs, ohCharges, ohEnchantID). Prefers C_PaperDollInfo.GetTemporaryEnchantmentInfo (12.1: GetWeaponEnchantInfo is a deprecation-CVar shim there); remainingTimeMs maps 1:1 to legacy ms values. On EABR.
EABR.WeaponEnchants = function()
    if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        local mh = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_MAINHAND)
        local oh = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_OFFHAND)
        return (mh and true or false), mh and mh.remainingTimeMs,
            mh and mh.chargesRemaining, mh and mh.enchantID,
            (oh and true or false), oh and oh.remainingTimeMs,
            oh and oh.chargesRemaining, oh and oh.enchantID
    end
    return GetWeaponEnchantInfo()
end

local RAID_BUFFS = {
    { key="motw",   class="DRUID",   name="Mark of the Wild",       castSpell=1126,   buffIDs={1126,432661},    check="raid" },
    { key="bshout", class="WARRIOR", name="Battle Shout",           castSpell=6673,   buffIDs={6673},    check="raid", benefit="attackPower" },
    { key="fort",   class="PRIEST",  name="Power Word: Fortitude",  castSpell=21562,  buffIDs={21562},   check="raid" },
    { key="ai",     class="MAGE",    name="Arcane Intellect",       castSpell=1459,   buffIDs={1459,432778},    check="raid", benefit="intellect" },
    { key="bronze", class="EVOKER",  name="Blessing of the Bronze", castSpell=364342,
      buffIDs={381732,381741,381746,381748,381749,381750,381751,381752,381753,381754,381756,381757,381758},
      check="raid" },
    { key="sky",    class="SHAMAN",  name="Skyfury",                castSpell=462854, buffIDs={462854},  check="raid" },
    -- Hunter's Mark: disabled (under maintenance); entry intentionally omitted.
}
-- WoW Forever: that client's four raid buffs replace the list (there it is
-- read only by its own Raid Buffs: EABR.CollectForeverRaidBuffs and the
-- options grid). Same keys as retail, so a profile's switches move between
-- the clients. castSpell = rank 1 (label and options icon); fam = the shared
-- buff family (every rank, the group version, other casters' versions);
-- selfCast = cast with no target.
if EABR.FOREVER then
    RAID_BUFFS = {
        { key="motw",   class="DRUID",   name="Mark of the Wild",      castSpell=1126, dismissKey="raidbuff:motw",
          fam=EllesmereUI.FOREVER_BUFF_FAMILIES.mark },
        { key="bshout", class="WARRIOR", name="Battle Shout",          castSpell=6673, dismissKey="raidbuff:bshout",
          fam=EllesmereUI.FOREVER_BUFF_FAMILIES.bshout, benefit="attackPower", selfCast=true },
        { key="fort",   class="PRIEST",  name="Power Word: Fortitude", castSpell=1243, dismissKey="raidbuff:fort",
          fam=EllesmereUI.FOREVER_BUFF_FAMILIES.fort },
        { key="ai",     class="MAGE",    name="Arcane Intellect",      castSpell=1459, dismissKey="raidbuff:ai",
          fam=EllesmereUI.FOREVER_BUFF_FAMILIES.ai, benefit="intellect" },
    }
end

-------------------------------------------------------------------------------
--  SPELL DATA Auras (some non-secret, some still OOC-only)
-------------------------------------------------------------------------------
local AURAS = {
    { key="moonkin_form", class="DRUID", name="Moonkin Form", castSpell=24858,
      check="player", specs={102}, combatOnly=true, isStance=true },
    -- Symbiotic Relationship: player gets a buff when active (group only)
    { key="symbiotic",  class="DRUID",   name="Symbiotic Relationship", castSpell=474750, buffIDs={474754},
      check="player", combatOk=false, requireGroup=true },
    -- Warrior stances: shapeshift forms via stance bar (not auras), OOC only. Arms->Battle, Fury->Berserker, Prot->Defensive; reminder hides once active, suppressed if unknown.
    { key="battle_stance",  class="WARRIOR", name="Battle Stance",   castSpell=386164, buffIDs={386164},
      check="player", specs={71}, combatOk=false, isStance=true },
    { key="berserk_stance", class="WARRIOR", name="Berserker Stance", castSpell=386196, buffIDs={386196},
      check="player", specs={72}, combatOk=false, isStance=true },
    { key="def_stance",  class="WARRIOR", name="Defensive Stance",  castSpell=386208, buffIDs={386208},
      check="player", specs={73}, combatOk=false, isStance=true },
    -- Shadowform OOC only (Void Form 194249 also satisfies); formSpellIDs lists every form that counts as active,
    -- for the combat/PvP fallback where the aura API is restricted.
    { key="shadowform", class="PRIEST",  name="Shadowform",        castSpell=232698, buffIDs={232698, 194249},
      check="player", specs={258}, combatOk=false, formSpellIDs={232698, 194249, 185916} },
    -- Paladin Aura: only Devotion satisfies in dungeons/raids, any aura elsewhere; noPvP because Devotion Aura is ContextuallySecret in PvP even OOC.
    -- nameFallback: with a second Paladin's aura also active, the source is
    -- ambiguous and GetPlayerAuraBySpellID(465) can come back nil (fully
    -- withheld, not just secret) even though the buff is up -- a name scan
    -- catches it before the reminder false-fires.
    { key="devo_aura",  class="PALADIN", name="Devotion Aura",     castSpell=465,
      buffIDs={465, 32223, 317920}, instanceBuffIDs={465}, nameFallback="Devotion Aura",
      check="player", combatOk=false, noPvP=true },
    -- Beacon of Light: standalone IsSpellOverlayed system (not checked by CollectAuras)
    { key="bol",        class="PALADIN", name="Beacon of Light",   castSpell=53563,  buffIDs={53563},
      standalone=true, notIfKnown=200025 },
    -- Beacon of Faith: standalone IsSpellOverlayed system (not checked by CollectAuras)
    { key="bof",        class="PALADIN", name="Beacon of Faith",   castSpell=156910, buffIDs={156910},
      standalone=true },
    -- Source of Magic (369459, non-secret): applies to a healer target, not the caster -- check if player's cast exists on any group member.
    { key="som",        class="EVOKER",  name="Source of Magic",   castSpell=369459, buffIDs={369459},
      check="ownOnRaid", combatOk=true, requireInstanceGroup=true },
    -- Blistering Scales: requireTalent omitted (Regenerative Chitin is a passive modifier).
    { key="blistering_scales", class="EVOKER", name="Blistering Scales", castSpell=360827,
      buffIDs={360827}, check="ownOnRaid", combatOk=true,
      requireInstanceGroup=true },
    -- Bestow Weyrnstone: OOC only. Tracks target aura, not the one on self.
    { key="bestow_weyrnstone", class="EVOKER", name="Bestow Weyrnstone", castSpell=408233,
      buffIDs={410318}, check="ownOnRaid", combatOk=false,
      specs={1473}, requireInstanceGroup=true },
    -- Timelessness: OOC only.
    { key="timelessness", class="EVOKER", name="Timelessness", castSpell=412710,
      buffIDs={412710}, check="ownOnRaid", combatOk=false,
      specs={1473}, requireInstanceGroup=true },
    -- Soulstone: satisfied only by this Warlock's own cast, whether it is on
    -- the player or any connected party/raid member. OOC-only; restricted
    -- source data is never used to infer ownership.
    { key="soulstone", class="WARLOCK", name="Soulstone", castSpell=20707,
      buffIDs={20707}, check="ownGroupOrSelf", combatOk=false },
}

-------------------------------------------------------------------------------
--  Healthstone / Soulstone / Partnered Trinket tracking
-------------------------------------------------------------------------------
local HEALTHSTONE_ITEM_IDS = { 5512, 224464 }  -- Healthstone, Demonic Healthstone

local PARTNERED_TRINKET = {
    key = "coaches_whistle", name = "Emerald Coach's Whistle",
    buffID = 389581, buffIDs = {389581, 383798}, icon = 134157, duration = 3600,
}

-- Pet tracking: classes that summon permanent pets
local PET_CLASSES = { HUNTER = true, WARLOCK = true, DEATHKNIGHT = true, MAGE = true }

-- If the player knows ANY of these, they use their own imbue system (not generic oils/stones), so the weapon-enchant reminder is suppressed.
local _IMBUE_EXCLUDE_SPELLS = {
    382021,  -- Earthliving Weapon (Shaman)
    318038,  -- Flametongue Weapon (Shaman)
    33757,   -- Windfury Weapon (Shaman)
    433583,  -- Rite of Adjuration (Paladin Lightsmith)
    433568,  -- Rite of Sanctification (Paladin Lightsmith)
}

-------------------------------------------------------------------------------
--  SPELL DATA Consumables (OOC only, not during keystones)
-------------------------------------------------------------------------------
-- Rogue Poisons: table drives options UI, detection uses the unified scan below; lethal/non-lethal categories match WoW's internal classification.
local ROGUE_POISONS = {
    -- Lethal poisons (mutually exclusive per slot): Deadly first (core Assa), then talented, then other base.
    { key="deadly",     name="Deadly Poison",     castSpell=2823,   cat="lethal" },
    { key="amplifying", name="Amplifying Poison", castSpell=381664, cat="lethal" },
    { key="instant",    name="Instant Poison",    castSpell=315584, cat="lethal" },
    { key="wound",      name="Wound Poison",      castSpell=8679,   cat="lethal" },
    -- Non-lethal poisons (mutually exclusive per slot).
    { key="numbing",    name="Numbing Poison",    castSpell=5761,   cat="nonlethal" },
    { key="atrophic",   name="Atrophic Poison",   castSpell=381637, cat="nonlethal" },
    { key="crippling",  name="Crippling Poison",  castSpell=3408,   cat="nonlethal" },
}
-- Dragon-Tempered Blades (381801): allows 2 of each poison category
local DTB_SPELL_ID = 381801

-- Paladin Rites (non-secret in 12.0)
local PALADIN_RITES = {
    { key="rite_adj",  name="Rite of Adjuration",     castSpell=433583, buffIDs={433583}, wepEnchID={7144} },
    { key="rite_sanc", name="Rite of Sanctification",  castSpell=433568, buffIDs={433568}, wepEnchID={7143} },
}



-- Shaman Imbues (non-secret in 12.0)
local SHAMAN_IMBUES = {
    { key="flametongue", name="Flametongue Weapon", castSpell=318038, buffIDs={319778}, wepEnchID={5400} },
    { key="windfury",    name="Windfury Weapon",    castSpell=33757,  buffIDs={319773},  wepEnchID={5401} },
    { key="earthliving", name="Earthliving Weapon", castSpell=382021, buffIDs={382021, 382022}, wepEnchID={6498} },
    { key="tidecaller",  name="Tidecaller's Guard", castSpell=457481, buffIDs={457496, 457481}, wepEnchID={7528}, requireShield=true },
    { key="tstrike",     name="Thunderstrike Ward", castSpell=462757, buffIDs={462757, 462742}, wepEnchID={7587}, requireShield=true },
}

-- Shaman Shields, gated on Elemental Orbit (383010). With Orbit: Earth Shield self-buff (383648) + Lightning/Water Shield both required; without, any of the three shields. Cast spell by spec: Resto (264) -> Water Shield (52127), else Lightning Shield (192106).
local function ShamanShieldCastSpell()
    local specIdx = GetSpecialization and GetSpecialization() or 0
    local specID = specIdx and specIdx > 0 and GetSpecializationInfo(specIdx) or 0 -- guardrails-allow: deprecated-global by Ellesmere: moved verbatim by the split; never reached on Forever
    return (specID == 264) and 52127 or 192106
end

-- es_ally (opt-in, default off) is the display-only reminder for our Earth
-- Shield (974) on a group member; it reads the targeted own-aura tracker, and
-- the generic shield loop skips it.
local SHAMAN_SHIELDS = {
    { key="es_orbit", name="Earth Shield (Self)",
      castSpell=974, buffIDs={383648}, requireTalent=383010,
      check="player" },
    { key="es_ally", name="Earth Shield (Ally)",
      castSpell=974, buffIDs={974}, requireTalent=383010 },
    { key="ls_ws_orbit", name="Lightning/Water Shield",
      castSpellFn=ShamanShieldCastSpell, buffIDs={192106, 52127}, requireTalent=383010,
      check="player" },
    { key="shield_basic", name="Shield (No Orbit)",
      castSpellFn=ShamanShieldCastSpell, buffIDs={974, 192106, 52127}, excludeTalent=383010,
      check="player" },
}

-- Warlock permanent pets ("wrong demon" check). families includes cosmetic
-- Grimoire-of-* reskins (e.g. Wrathguard = Felguard) so those don't misfire.
local WARLOCK_PETS = {
    { key="felguard",   name="Felguard",   castSpell=30146,  families={[29]=true,  [104]=true} },
    { key="imp",        name="Imp",        castSpell=688,    families={[23]=true,  [100]=true} },
    { key="voidwalker", name="Voidwalker", castSpell=697,    families={[16]=true,  [101]=true} },
    { key="sayaad",     name="Sayaad",     castSpell=366222, families={[17]=true,  [102]=true, [302]=true} },
    { key="felhunter",  name="Felhunter",  castSpell=691,    families={[15]=true,  [103]=true} },
}

-- Points an entry at whichever pet the shared cycle index currently selects
-- from `pets` (Missing Pet and Wrong Demon share one index, so cycling on
-- either reminder advances the same pointer). On EABR, not a top-level
-- local.
EABR.SetWarlockPetSpell = function(e, pets, fallbackTexture, labelOverride)
    local n = #pets
    local idx = EABR._petCycleIndex or 1
    if idx > n then idx = 1 end
    local pet = pets[idx]
    e.mode = "spell"
    e.spellID = pet.castSpell
    e.texture = Tex(pet.castSpell) or fallbackTexture
    e.label = labelOverride or EllesmereUI.L(pet.name)
    e.petCycleTotal = n > 1 and n or nil
end

-- Weapon Enchant Items (temporary weapon enchants applied from items). weaponType: BLADED, BLUNT, RANGED, NEUTRAL (NEUTRAL fits any weapon).
local WEAPON_ENCHANT_ITEMS = {
    -- Midnight
    {itemID=237367, name="Refulgent Weightstone",     weaponType="BLUNT",   icon=7548939},
    {itemID=237369, name="Refulgent Weightstone",     weaponType="BLUNT",   icon=7548939},
    {itemID=237370, name="Refulgent Whetstone",       weaponType="BLADED",  icon=7548942},
    {itemID=237371, name="Refulgent Whetstone",       weaponType="BLADED",  icon=7548942},
    {itemID=257749, name="Laced Zoomshots",           weaponType="RANGED",  icon=249176},
    {itemID=257750, name="Laced Zoomshots",           weaponType="RANGED",  icon=249176},
    {itemID=257751, name="Weighted Boomshots",        weaponType="RANGED",  icon=249175},
    {itemID=257752, name="Weighted Boomshots",        weaponType="RANGED",  icon=249175},
    {itemID=243733, name="Thalassian Phoenix Oil",    weaponType="NEUTRAL", icon=7548987},
    {itemID=243734, name="Thalassian Phoenix Oil",    weaponType="NEUTRAL", icon=7548987},
    {itemID=243735, name="Oil of Dawn",               weaponType="NEUTRAL", icon=7548985},
    {itemID=243736, name="Oil of Dawn",               weaponType="NEUTRAL", icon=7548985},
    {itemID=243737, name="Smuggler's Enchanted Edge", weaponType="NEUTRAL", icon=7548986},
    {itemID=243738, name="Smuggler's Enchanted Edge", weaponType="NEUTRAL", icon=7548986},
    -- TWW
    {itemID=222504, name="Ironclaw Whetstone",     weaponType="BLADED",  icon=3622195},
    {itemID=222503, name="Ironclaw Whetstone",     weaponType="BLADED",  icon=3622195},
    {itemID=222502, name="Ironclaw Whetstone",     weaponType="BLADED",  icon=3622195},
    {itemID=222510, name="Ironclaw Weightstone",   weaponType="BLUNT",   icon=3622199},
    {itemID=222509, name="Ironclaw Weightstone",   weaponType="BLUNT",   icon=3622199},
    {itemID=222508, name="Ironclaw Weightstone",   weaponType="BLUNT",   icon=3622199},
    {itemID=224107, name="Algari Mana Oil",        weaponType="NEUTRAL", icon=609892},
    {itemID=224106, name="Algari Mana Oil",        weaponType="NEUTRAL", icon=609892},
    {itemID=224105, name="Algari Mana Oil",        weaponType="NEUTRAL", icon=609892},
    {itemID=224113, name="Oil of Deep Toxins",     weaponType="NEUTRAL", icon=609897},
    {itemID=224112, name="Oil of Deep Toxins",     weaponType="NEUTRAL", icon=609897},
    {itemID=224111, name="Oil of Deep Toxins",     weaponType="NEUTRAL", icon=609897},
    {itemID=224110, name="Oil of Beledar's Grace", weaponType="NEUTRAL", icon=609896},
    {itemID=224109, name="Oil of Beledar's Grace", weaponType="NEUTRAL", icon=609896},
    {itemID=224108, name="Oil of Beledar's Grace", weaponType="NEUTRAL", icon=609896},
    {itemID=220156, name="Bubbling Wax",           weaponType="NEUTRAL", icon=133778},
}

-- Flask Items (Midnight) each flask has multiple item IDs across quality ranks + fleeting variants
local FLASK_ITEMS = {
    { key="blood_knights",         buffID=1235110, name="Flask of the Blood Knights",
      items={241324, 241325, 245931, 245930} },
    { key="magisters",             buffID=1235108, name="Flask of the Magisters",
      items={241322, 241323, 245933, 245932} },
    { key="shattered_sun",         buffID=1235111, name="Flask of the Shattered Sun",
      items={241326, 241327, 245929, 245928} },
    { key="thalassian_resistance", buffID=1235057, name="Flask of Thalassian Resistance",
      items={241320, 241321, 245926, 245927} },
    { key="thalassian_horror", buffID=1239355, name="Vicious Thalassian Flask of Honor",
      items={241334} },
}
local FLASK_BUFF_ID_SET = {}
local FLASK_NAME_SET = {}
for _, f in ipairs(FLASK_ITEMS) do
    FLASK_BUFF_ID_SET[f.buffID] = true
    -- Build name set from localized spell names (works in all languages)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(f.buffID)
    local locName = info and info.name
    if locName then FLASK_NAME_SET[locName] = true end
    FLASK_NAME_SET[f.name] = true  -- English fallback
end
-- TWW flask buff IDs (detection only, so we don't false-positive when a player still has a TWW flask active)
for _, id in ipairs({432473, 432021, 431974, 431973, 431972, 431971}) do
    FLASK_BUFF_ID_SET[id] = true
end
-- PvP-morphed Midnight flask buff IDs (Blizzard replaces the PvE buff ID with a separate PvP variant in arenas/battlegrounds)
for _, id in ipairs({1235113, 1235114, 1235115, 1235116}) do
    FLASK_BUFF_ID_SET[id] = true
end

-- Food Items (Midnight)
local FOOD_ITEMS = {
    { key="royal_roast",           itemID=242275, name="Royal Roast" },
    { key="impossibly_royal_roast", itemID=255847, name="Impossibly Royal Roast" },
    { key="flora_frenzy",          itemID=255848, name="Flora Frenzy" },
    { key="champions_bento",       itemID=242274, name="Champion's Bento" },
    { key="warped_wise_wings",     itemID=242285, name="Warped Wise Wings" },
    { key="void_kissed_fish_rolls", itemID=242284, name="Void-Kissed Fish Rolls" },
    { key="sun_seared_lumifin",    itemID=242283, name="Sun-Seared Lumifin" },
    { key="null_and_void_plate",   itemID=242282, name="Null and Void Plate" },
    { key="glitter_skewers",       itemID=242281, name="Glitter Skewers" },
    { key="fel_kissed_filet",      itemID=242286, name="Fel-Kissed Filet" },
    { key="buttered_root_crab",    itemID=242280, name="Buttered Root Crab" },
    { key="arcano_cutlets",        itemID=242287, name="Arcano Cutlets" },
    { key="tasty_smoked_tetra",    itemID=242278, name="Tasty Smoked Tetra" },
    { key="crimson_calamari",      itemID=242277, name="Crimson Calamari" },
    { key="braised_blood_hunter",  itemID=242276, name="Braised Blood Hunter" },
    { key="harandar_celebration",  itemID=255846, name="Harandar Celebration" },
    { key="silvermoon_parade",     itemID=255845, name="Silvermoon Parade" },
    { key="queldorei_medley",      itemID=242272, name="Quel'dorei Medley" },
    { key="blooming_feast",        itemID=242273, name="Blooming Feast" },
    { key="sunwell_delight",       itemID=242293, name="Sunwell Delight" },
    { key="hearthflame_supper",    itemID=242295, name="Hearthflame Supper" },
    { key="fried_bloomtail",       itemID=242291, name="Fried Bloomtail" },
    { key="felberry_figs",         itemID=242294, name="Felberry Figs" },
    { key="eversong_pudding",      itemID=242292, name="Eversong Pudding" },
    { key="bloodthistle_wrapped_cutlets", itemID=242296, name="Bloodthistle-wrapped Cutlets" },
    { key="wise_tails",            itemID=242290, name="Wise Tails" },
    { key="twilight_anglers_medley", itemID=242288, name="Twilight Angler's Medley" },
    { key="spellfire_filet",       itemID=242289, name="Spellfire Filet" },
    { key="spiced_biscuits",       itemID=242304, name="Spiced Biscuits" },
    { key="silvermoon_standard",   itemID=242305, name="Silvermoon Standard" },
    { key="quick_sandwich",        itemID=242307, name="Quick Sandwich" },
    { key="portable_snack",        itemID=242308, name="Portable Snack" },
    { key="mana_infused_stew",     itemID=242303, name="Mana-Infused Stew" },
    { key="foragers_medley",       itemID=242306, name="Forager's Medley" },
    { key="farstrider_rations",    itemID=242309, name="Farstrider Rations" },
    { key="bloom_skewers",         itemID=242302, name="Bloom Skewers" },
    { key="feast_of_knowledge",    itemID=275266, name="Feast of Knowledge" },
    -- Hearty Food Items
    { key="hearty_royal_roast",            itemID=242747, name="Hearty Royal Roast" },
    { key="hearty_impossibly_royal_roast",  itemID=268679, name="Hearty Impossibly Royal Roast" },
    { key="hearty_flora_frenzy",            itemID=268680, name="Hearty Flora Frenzy" },
    { key="hearty_champions_bento",         itemID=242746, name="Hearty Champion's Bento" },
    { key="hearty_warped_wise_wings",       itemID=242757, name="Hearty Warped Wise Wings" },
    { key="hearty_void_kissed_fish_rolls",  itemID=242756, name="Hearty Void-Kissed Fish Rolls" },
    { key="hearty_sun_seared_lumifin",      itemID=242755, name="Hearty Sun-Seared Lumifin" },
    { key="hearty_null_and_void_plate",     itemID=242754, name="Hearty Null and Void Plate" },
    { key="hearty_glitter_skewers",         itemID=242753, name="Hearty Glitter Skewers" },
    { key="hearty_fel_kissed_filet",        itemID=242758, name="Hearty Fel-Kissed Filet" },
    { key="hearty_buttered_root_crab",      itemID=242752, name="Hearty Buttered Root Crab" },
    { key="hearty_arcano_cutlets",          itemID=242759, name="Hearty Arcano Cutlets" },
    { key="hearty_tasty_smoked_tetra",      itemID=242750, name="Hearty Tasty Smoked Tetra" },
    { key="hearty_crimson_calamari",        itemID=242749, name="Hearty Crimson Calamari" },
    { key="hearty_braised_blood_hunter",    itemID=242748, name="Hearty Braised Blood Hunter" },
    { key="hearty_harandar_celebration",    itemID=266996, name="Hearty Harandar Celebration" },
    { key="hearty_silvermoon_parade",       itemID=266985, name="Hearty Silvermoon Parade" },
    { key="hearty_queldorei_medley",        itemID=242744, name="Hearty Quel'dorei Medley" },
    { key="hearty_blooming_feast",          itemID=242745, name="Hearty Blooming Feast" },
    { key="hearty_sunwell_delight",         itemID=242765, name="Hearty Sunwell Delight" },
    { key="hearty_hearthflame_supper",      itemID=242767, name="Hearty Hearthflame Supper" },
    { key="hearty_fried_bloomtail",         itemID=242763, name="Hearty Fried Bloomtail" },
    { key="hearty_felberry_figs",           itemID=242766, name="Hearty Felberry Figs" },
    { key="hearty_eversong_pudding",        itemID=242764, name="Hearty Eversong Pudding" },
    { key="hearty_bloodthistle_wrapped_cutlets", itemID=242768, name="Hearty Bloodthistle-Wrapped Cutlets" },
    { key="hearty_wise_tails",              itemID=242762, name="Hearty Wise Tails" },
    { key="hearty_twilight_anglers_medley", itemID=242760, name="Hearty Twilight Angler's Medley" },
    { key="hearty_spellfire_filet",         itemID=242761, name="Hearty Spellfire Filet" },
    { key="hearty_spiced_biscuits",         itemID=242771, name="Hearty Spiced Biscuits" },
    { key="hearty_silvermoon_standard",     itemID=242772, name="Hearty Silvermoon Standard" },
    { key="hearty_quick_sandwich",          itemID=242774, name="Hearty Quick Sandwich" },
    { key="hearty_portable_snack",          itemID=242775, name="Hearty Portable Snack" },
    { key="hearty_mana_infused_stew",       itemID=242770, name="Hearty Mana-Infused Stew" },
    { key="hearty_foragers_medley",         itemID=242773, name="Hearty Forager's Medley" },
    { key="hearty_farstrider_rations",      itemID=242776, name="Hearty Farstrider Rations" },
    { key="hearty_bloom_skewers",           itemID=242769, name="Hearty Bloom Skewers" },
    { key="hearty_feast_of_knowledge",      itemID=275269, name="Hearty Feast of Knowledge" },
}

-- Weapon Enchant dropdown choices (name best itemID lookup at runtime)
local WEAPON_ENCHANT_CHOICES = {
    { key="thalassian_phoenix_oil",  name="Thalassian Phoenix Oil" },
    { key="smugglers_enchanted_edge", name="Smuggler's Enchanted Edge" },
    { key="oil_of_dawn",             name="Oil of Dawn" },
    { key="refulgent_weightstone",   name="Refulgent Weightstone" },
    { key="refulgent_whetstone",     name="Refulgent Whetstone" },
    { key="laced_zoomshots",         name="Laced Zoomshots" },
    { key="weighted_boomshots",      name="Weighted Boomshots" },
}

-- Augment Runes (item IDs inlined at usage site in CollectConsumables)
local RUNE_BUFF_IDS = {1295329, 1264426, 453250, 1234969, 1242347, 393438, 347901} -- 1295329 = Tidesworn (12.1)

-- Inky Black Potion
local INKY_BLACK_ITEM = 124640
local INKY_BLACK_BUFF = 185394  -- "Inky Blackness" buff (icon 136122); detected by aura scan, see PlayerHasInkyBlackness

-------------------------------------------------------------------------------
--  Helpers: Well Fed / Flask buff detection (by name, not spell ID secret)
-------------------------------------------------------------------------------
-- Consumable aura presence is unverifiable in combat / active M+ (suppress,
-- never false-remind) and anywhere the 12.1 aura restriction is engaged --
-- AurasRestricted() is the authoritative probe (asymmetric per-frame cache;
-- index scans HARD-ERROR under restriction, even out of combat in raids).
-- Weapon enchants and raid buffs use other APIs and are not gated here.
function EABR.ConsumablePresenceUnverifiable()
    if InCombat() or InMythicPlusKey() then return true end
    return EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted() or false
end

-------------------------------------------------------------------------------
--  Eating-state tracker: the eating channel shares one aura icon (133950)
--  across all food. Tracked by auraInstanceID from the player UNIT_AURA
--  payload; the full scan runs only at enable/zone edges. Under restriction
--  the payload and index scans are secret/blocked -- the tracker simply
--  reports "not eating" there (the food reminder is suppressed anyway).
-------------------------------------------------------------------------------
function EABR.IsPlayerEating()
    return EABR._eatingIID ~= nil
end

function EABR.ScanEatingState()
    EABR._eatingIID = nil
    if EABR.FOREVER then return end  -- no food reminder on WoW Forever, so no eating channel to track
    if EllesmereUI.AuraKit and EllesmereUI.AuraKit.AurasRestricted() then return end
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then break end
        local ic = aura.icon
        if ic and not isSecret(ic) and ic == 133950 then
            local iid = aura.auraInstanceID
            if iid ~= nil and not isSecret(iid) then EABR._eatingIID = iid end
            return
        end
    end
end

function EABR.UpdateEatingState(updateInfo)
    -- 12.1: the whole payload and each list can be secret in restricted
    -- content; indexing a secret errors, so every layer is gated.
    if updateInfo == nil or isSecret(updateInfo) then return end
    local added = updateInfo.addedAuras
    if added ~= nil and not isSecret(added) then
        for _, aura in ipairs(added) do
            if aura ~= nil and not isSecret(aura) then
                local ic = aura.icon
                if ic and not isSecret(ic) and ic == 133950 then
                    local iid = aura.auraInstanceID
                    if iid ~= nil and not isSecret(iid) then
                        EABR._eatingIID = iid
                        break
                    end
                end
            end
        end
    end
    local removed = updateInfo.removedAuraInstanceIDs
    if removed ~= nil and not isSecret(removed) and EABR._eatingIID then
        for _, id in ipairs(removed) do
            if id ~= nil and not isSecret(id) and id == EABR._eatingIID then
                EABR._eatingIID = nil
                break
            end
        end
    end
end

function EABR.GetEatingExpirationTime()
    if not EABR._eatingIID then return nil end
    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", EABR._eatingIID)
    if not ok or not auraData then return nil end
    local exp = auraData.expirationTime
    if exp == nil or isSecret(exp) or exp == 0 then return nil end
    return exp
end

local function PlayerHasBuffByName(buffName)
    -- Cannot verify -> treat as present so the reminder never false-fires.
    if EABR.ConsumablePresenceUnverifiable() then return true end
    if _AC.valid then
        _AC.ensureNames()
        return _AC.byName[buffName] or false
    end
    local sawReadableName = false
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return true end -- can't verify absence
        if not aura then break end
        local aName = aura.name
        if aName and not isSecret(aName) then
            sawReadableName = true
            if aName == buffName then return true end
        end
    end
    if not sawReadableName then return true end -- names secret / empty: suppress
    return false
end

local function PlayerHasWellFed()
    if InPvPInstance() then return true end  -- food not trackable in PvP, suppress
    if EABR.ConsumablePresenceUnverifiable() then return true end
    -- Well Fed has no whitelisted spell ID (icon scan). If icons aren't
    -- readable, suppress rather than false-fire "missing".
    if _AC.valid then
        -- Read from the refresh's one aura pass (shared with the flask check).
        _AC.ensureNames()
        if not _AC.sawIcon then return true end
        local aura = _AC.wellFed
        if not aura then return false end
        local dur, exp = aura.duration, aura.expirationTime
        if dur ~= nil and exp ~= nil and not isSecret(dur) and not isSecret(exp)
           and IsUnderDuration(dur, exp, "consumable") then
            return false
        end
        return true
    end
    local sawReadableIcon = false
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return true end -- can't verify absence
        if not aura then break end
        local ic = aura.icon
        if ic and not isSecret(ic) then
            sawReadableIcon = true
            if ic == 136000 then
                local dur, exp = aura.duration, aura.expirationTime
                if dur ~= nil and exp ~= nil and not isSecret(dur) and not isSecret(exp)
                   and IsUnderDuration(dur, exp, "consumable") then
                    return false
                end
                return true
            end
        end
    end
    if not sawReadableIcon then return true end -- icons secret: suppress
    return false
end

local function PlayerHasFlaskBuff()
    if InPvPInstance() then return true end
    if EABR.ConsumablePresenceUnverifiable() then return true end
    -- Direct ID lookup for known flask buff IDs (zero allocation)
    for id in pairs(FLASK_BUFF_ID_SET) do
        local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and result ~= nil then
            local dur, exp = result.duration, result.expirationTime
            if dur ~= nil and exp ~= nil and not isSecret(dur) and not isSecret(exp)
               and IsUnderDuration(dur, exp, "consumable") then
                return false
            end
            return true
        end
    end
    -- Name-based fallback for flasks not in our ID set (lazy scan)
    if _AC.valid then
        _AC.ensureNames()
        for aName in pairs(_AC.byName) do
            if FLASK_NAME_SET[aName] then return true end
        end
    end
    return false
end

local function PlayerHasInkyBlackness()
    if InPvPInstance() then return true end
    if EABR.ConsumablePresenceUnverifiable() then return true end
    local sawReadable = false
    for i = 1, AURA_SCAN_LIMIT do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return true end -- can't verify absence
        if not aura then break end
        local sid = aura.spellId
        local ic = aura.icon
        if (sid and not isSecret(sid)) or (ic and not isSecret(ic)) then
            sawReadable = true
        end
        if (sid and not isSecret(sid) and sid == INKY_BLACK_BUFF)
        or (ic and not isSecret(ic) and ic == 136122) then
            local dur, exp = aura.duration, aura.expirationTime
            if dur ~= nil and exp ~= nil and not isSecret(dur) and not isSecret(exp)
               and IsUnderDuration(dur, exp, "consumable") then
                return false
            end
            return true
        end
    end
    if not sawReadable then return true end -- fields secret: suppress
    return false
end

-------------------------------------------------------------------------------
--  Item count snapshot: GetItemCount is a per-item bag scan (~135-item consumable resolve was ~7ms cold).
--  Walks bags 0-4 ONCE into {itemID->count} (rebuilt only on bag change, consumables never in the reagent bag) so CachedGetItemCount is a hash lookup; DetectUsedItem shares it -- one bag walk per change, not two.
-------------------------------------------------------------------------------
local _bagCounts = {}
local _itemCountDirty = true

-- Resolved consumable cache: WHICH item to show per bag/equip-derived category, rebuilt only when bags/weapon/
-- preferred-item settings change (EABR.ResolveConsumables). Hung on EABR, not a local. Caches only
-- SELECTION state (itemID/cat/hasBags/availability); icon is derived at each emit site to stay byte-identical to per-refresh GetItemIcon calls. Defaults nil/false; dirty starts true so the first OOC CollectConsumables fully populates it.
EABR._resolved = {
    dirty = true,                   -- rebuild pending
    sig = {},                       -- last preferred-setting signature
    rune = {},                      -- {itemID, hasBags}
    flask = {},                     -- {itemID, hasBags}
    food = {},                      -- {itemID}
    inky = {},                      -- {hasPotion}
    healthstone = {},               -- {hasStone}
    we = { [16] = {}, [17] = {} },  -- per-slot {cat, itemID, hasBags}
}

local function InvalidateItemCountCache()
    _itemCountDirty = true
    EABR._resolved.dirty = true
end

local function RebuildBagCounts()
    wipe(_bagCounts)
    _itemCountDirty = false
    for bag = 0, 4 do
        local numSlots = C_Container and C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container and C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                _bagCounts[info.itemID] = (_bagCounts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
end

local function CachedGetItemCount(itemID)
    if _itemCountDirty then RebuildBagCounts() end
    return _bagCounts[itemID] or 0
end

-------------------------------------------------------------------------------
--  Helpers: Find best item in bags for a preferred choice
-------------------------------------------------------------------------------
local function FindFlaskItem(preferredKey, lastUsedItemID)
    if preferredKey == "last_used" then
        if lastUsedItemID and CachedGetItemCount(lastUsedItemID) > 0 then
            return lastUsedItemID
        end
        -- Fallback: first flask found in bags
        for _, f in ipairs(FLASK_ITEMS) do
            for _, id in ipairs(f.items) do
                if CachedGetItemCount(id) > 0 then return id end
            end
        end
        return nil
    end
    for _, f in ipairs(FLASK_ITEMS) do
        if f.key == preferredKey then
            for _, id in ipairs(f.items) do
                if CachedGetItemCount(id) > 0 then return id end
            end
        end
    end
    return nil
end

local function FindFoodItem(preferredKey, lastUsedItemID)
    if preferredKey ~= "last_used" then
        for _, f in ipairs(FOOD_ITEMS) do
            if f.key == preferredKey and CachedGetItemCount(f.itemID) > 0 then return f.itemID end
        end
        -- Preferred food out of stock: try the base variant of the same food
        -- (e.g. "hearty_royal_roast" -> "royal_roast") before giving up on it.
        local baseKey = preferredKey:gsub("^hearty_", "")
        if baseKey ~= preferredKey then
            for _, f in ipairs(FOOD_ITEMS) do
                if f.key == baseKey and CachedGetItemCount(f.itemID) > 0 then return f.itemID end
            end
        end
    elseif lastUsedItemID and CachedGetItemCount(lastUsedItemID) > 0 then
        return lastUsedItemID
    end
    -- Fall back to the highest-quality food still in bags so the reminder
    -- stays clickable when the preferred/last food is gone but something
    -- edible remains. Runs only inside the resolve-on-change cache rebuild.
    local bestID, bestQ = nil, -1
    for _, f in ipairs(FOOD_ITEMS) do
        if CachedGetItemCount(f.itemID) > 0 then
            local q = 0
            if C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo then
                local ok, tier = pcall(C_TradeSkillUI.GetItemCraftedQualityByItemInfo, f.itemID)
                if ok and tier then q = tier end
            end
            if q > bestQ then bestID = f.itemID; bestQ = q end
        end
    end
    return bestID
end

local function FindWeaponEnchantItem(preferredKey, lastUsedItemID, targetCat)
    if preferredKey == "last_used" then
        if lastUsedItemID and CachedGetItemCount(lastUsedItemID) > 0 then
            return lastUsedItemID
        end
        -- Fallback: first matching weapon enchant in bags
        for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
            local wt = we.weaponType
            if ((wt == "NEUTRAL") or (wt == targetCat)) and CachedGetItemCount(we.itemID) > 0 then
                return we.itemID
            end
        end
        return nil
    end
    -- Find by name match (picks highest tier in bags)
    for _, choice in ipairs(WEAPON_ENCHANT_CHOICES) do
        if choice.key == preferredKey then
            for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
                if we.name == choice.name and CachedGetItemCount(we.itemID) > 0 then
                    return we.itemID
                end
            end
            break
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Resolves bag/equip-derived consumable display items -- the costly part of the consumable check (Find*Item walks
--  + GetWeaponCategory). Depends only on bags, equipped weapon, and preferred-item settings (+ lastUsed*); rebuilt
--  lazily on change, CollectConsumables reads resolved records each refresh and derives the icon at emit. NOTE: any FUTURE resolution input must also set _resolved.dirty (or join the signature below), or a stale item could show.
-------------------------------------------------------------------------------
function EABR.ResolveConsumables()
    if not db then return end
    local co = db.profile and db.profile.consumables
    if not co then return end

    local R = EABR._resolved
    local pf  = co.preferredFlask or "last_used"
    local pfd = co.preferredFood or "last_used"
    local pwe = co.preferredWeaponEnchant or "last_used"
    -- Lazy gate: rebuild only when dirty (bag/equip event) or a preferred-item setting changed -- options setters only RequestRefresh with no bag event, so a signature compare catches it here.
    local sig = R.sig
    if not R.dirty and sig.pf == pf and sig.pfd == pfd and sig.pwe == pwe then
        return
    end
    R.dirty = false
    sig.pf, sig.pfd, sig.pwe = pf, pfd, pwe

    local luf  = db.profile and db.profile.lastUsedFlask or nil
    local lufd = db.profile and db.profile.lastUsedFood or nil
    local luwe = db.profile and db.profile.lastUsedWeaponEnchant or nil

    -- Augment Rune: void, then ethereal, then Tidesworn (12.1); fall back to the
    -- void rune so an out-of-stock restock reminder can still render.
    local runeItem = nil
    if CachedGetItemCount(259085) > 0 then runeItem = 259085
    elseif CachedGetItemCount(243191) > 0 then runeItem = 243191
    elseif CachedGetItemCount(274797) > 0 then runeItem = 274797 end
    R.rune.hasBags = (runeItem ~= nil)
    R.rune.itemID = runeItem or 259085

    -- Flask: resolve a display item even when out of stock (shown desaturated).
    local flaskItemID = FindFlaskItem(pf, luf)
    R.flask.hasBags = (flaskItemID ~= nil)
    if not flaskItemID then
        if pf == "last_used" then
            flaskItemID = luf
        else
            for _, f in ipairs(FLASK_ITEMS) do
                if f.key == pf then flaskItemID = f.items[1]; break end
            end
        end
        if not flaskItemID and FLASK_ITEMS[1] then
            flaskItemID = FLASK_ITEMS[1].items[1]
        end
    end
    R.flask.itemID = flaskItemID

    -- Food: resolve a display item even when out of stock (shown desaturated).
    local foodItemID = FindFoodItem(pfd, lufd)
    R.food.hasBags = (foodItemID ~= nil)
    if not foodItemID then
        if pfd == "last_used" then
            foodItemID = lufd
        else
            for _, f in ipairs(FOOD_ITEMS) do
                if f.key == pfd then foodItemID = f.itemID; break end
            end
        end
        if not foodItemID and FOOD_ITEMS[1] then
            foodItemID = FOOD_ITEMS[1].itemID
        end
    end
    R.food.itemID = foodItemID
    -- Amber-count flag when the shown food is a backup because the
    -- preferred/last pick ran out (but some other food is still owned).
    R.food.isSubstitute = false
    if foodItemID and R.food.hasBags then
        local foodKey
        for _, f in ipairs(FOOD_ITEMS) do
            if f.itemID == foodItemID then foodKey = f.key; break end
        end
        if pfd ~= "last_used" then
            R.food.isSubstitute = (foodKey ~= pfd)
        elseif lufd and foodItemID ~= lufd then
            R.food.isSubstitute = true
        end
    end

    -- Weapon enchant per slot: cat (equipped weapon type) gates the reminder in CollectConsumables and selects the item; resolves even out of stock (desaturated), same fallback order as inline code.
    for _, slot in ipairs({16, 17}) do
        local r = R.we[slot]
        local cat = GetWeaponCategory(slot)
        r.cat = cat
        local bestItemID = FindWeaponEnchantItem(pwe, luwe, cat)
        r.hasBags = (bestItemID ~= nil)
        if not bestItemID then
            if pwe == "last_used" then
                bestItemID = luwe
            else
                for _, choice in ipairs(WEAPON_ENCHANT_CHOICES) do
                    if choice.key == pwe then
                        for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
                            if we.name == choice.name then bestItemID = we.itemID; break end
                        end
                        break
                    end
                end
            end
            if not bestItemID then
                for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
                    if we.weaponType == "NEUTRAL" or we.weaponType == cat then
                        bestItemID = we.itemID; break
                    end
                end
            end
        end
        r.itemID = bestItemID
    end

    -- Inky Black Potion: constant item; only availability is bag-derived.
    R.inky.hasPotion = CachedGetItemCount(INKY_BLACK_ITEM) > 0

    -- Healthstone: constant texture; only availability is bag-derived.
    local hasStone = false
    for _, itemID in ipairs(HEALTHSTONE_ITEM_IDS) do
        if CachedGetItemCount(itemID) > 0 then hasStone = true; break end
    end
    R.healthstone.hasStone = hasStone
end

I._bagCounts, I._IMBUE_EXCLUDE_SPELLS, I.AURAS = _bagCounts, _IMBUE_EXCLUDE_SPELLS, AURAS
I.CachedGetItemCount, I.DTB_SPELL_ID = CachedGetItemCount, DTB_SPELL_ID
I.FLASK_ITEMS, I.FOOD_ITEMS, I.INKY_BLACK_ITEM = FLASK_ITEMS, FOOD_ITEMS, INKY_BLACK_ITEM
I.InvalidateItemCountCache, I.PALADIN_RITES = InvalidateItemCountCache, PALADIN_RITES
I.PARTNERED_TRINKET, I.PET_CLASSES = PARTNERED_TRINKET, PET_CLASSES
I.PlayerHasBuffByName, I.PlayerHasFlaskBuff = PlayerHasBuffByName, PlayerHasFlaskBuff
I.PlayerHasInkyBlackness, I.PlayerHasWellFed = PlayerHasInkyBlackness, PlayerHasWellFed
I.RAID_BUFFS, I.RebuildBagCounts, I.ROGUE_POISONS = RAID_BUFFS, RebuildBagCounts, ROGUE_POISONS
I.RUNE_BUFF_IDS, I.SHAMAN_IMBUES = RUNE_BUFF_IDS, SHAMAN_IMBUES
I.FLASK_BUFF_ID_SET = FLASK_BUFF_ID_SET
I.SHAMAN_SHIELDS, I.WARLOCK_PETS = SHAMAN_SHIELDS, WARLOCK_PETS
I.WEAPON_ENCHANT_CHOICES, I.WEAPON_ENCHANT_ITEMS = WEAPON_ENCHANT_CHOICES, WEAPON_ENCHANT_ITEMS
I.broken = false
