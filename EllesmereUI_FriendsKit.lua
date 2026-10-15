if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_FriendsKit.lua
--  The friends list pieces two modules share, so neither keeps a copy: the
--  Friends List module on retail, and Blizzard Skins+ on WoW Forever, where
--  the Friends List module never loads and the Window Skins "Friends List"
--  card hosts them (EllesmereUIBlizzardSkin_FriendsForever.lua):
--    - the realm -> region lookup and the region icons (public API);
--    - the 12.1 Social UI friend tiles (EllesmereUI.FriendsKit.StartTiles);
--    - auto-accepting group invites from friends (FriendsKit.SyncAutoAccept);
--    - the Class Icon Theme choices both settings pages offer.
--  At load this file only defines functions and constant tables: nothing
--  runs, registers or builds until a host starts it.
-------------------------------------------------------------------------------
local Kit = {}
EllesmereUI.FriendsKit = Kit

local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\friends\\"

-------------------------------------------------------------------------------
--  Realm -> region lookup for friend region detection
--  Mini regions: namerica, samerica, australia, europe, russia, korea, taiwan, china
--  Full regions: NA (namerica+samerica+australia), EU (europe+russia), KR, TW, CN
-------------------------------------------------------------------------------
local MINI_TO_FULL = {
    namerica  = "NA",
    samerica  = "NA",
    australia  = "NA",
    europe    = "EU",
    russia    = "EU",
    korea     = "KR",
    taiwan    = "TW",
    china     = "CN",
}

local REGION_ID_TO_FULL = {
    [1] = "NA",  -- Americas + Oceania
    [2] = "KR",
    [3] = "EU",  -- Europe + Russia
    [4] = "TW",
    [5] = "CN",
}

-- The realm tables, built on the first lookup (only friends list code reads
-- them, and only while a friends window is painted)
local REALMS_NA, REALMS_EU, REALMS_ASIA
local function LoadRealms()
-- Region 1: Americas & Oceania
REALMS_NA = {
["Azralon"] = "samerica",
["Gallywix"] = "samerica",
["Goldrinn"] = "samerica",
["Nemesis"] = "samerica",
["TolBarad"] = "samerica",
["Drakkari"] = "samerica",
["Quel'Thalas"] = "samerica",
["Ragnaros"] = "samerica",
["Loatheb"] = "samerica",
["Aman'Thul"] = "australia",
["Barthilas"] = "australia",
["Caelestrasz"] = "australia",
["Dath'Remar"] = "australia",
["Dreadmaul"] = "australia",
["Frostmourne"] = "australia",
["Gundrak"] = "australia",
["Jubei'Thos"] = "australia",
["Khaz'goroth"] = "australia",
["Nagrand"] = "australia",
["Saurfang"] = "australia",
["Thaurissan"] = "australia",
["Arugal"] = "australia",
["Yojamba"] = "australia",
["Remulos"] = "australia",
["Felstriker"] = "australia",
["Shadowstrike"] = "australia",
["Penance"] = "australia",
["Aegwynn"] = "namerica",
["AeriePeak"] = "namerica",
["Agamaggan"] = "namerica",
["Aggramar"] = "namerica",
["Akama"] = "namerica",
["Alexstrasza"] = "namerica",
["Alleria"] = "namerica",
["AltarofStorms"] = "namerica",
["AlteracMountains"] = "namerica",
["Andorhal"] = "namerica",
["Anetheron"] = "namerica",
["Antonidas"] = "namerica",
["Anub'arak"] = "namerica",
["Anvilmar"] = "namerica",
["Arathor"] = "namerica",
["Archimonde"] = "namerica",
["Area52"] = "namerica",
["ArgentDawn"] = "namerica",
["Arthas"] = "namerica",
["Arygos"] = "namerica",
["Auchindoun"] = "namerica",
["Azgalor"] = "namerica",
["AzjolNerub"] = "namerica",
["Azshara"] = "namerica",
["Azuremyst"] = "namerica",
["Baelgun"] = "namerica",
["Balnazzar"] = "namerica",
["BlackDragonflight"] = "namerica",
["Blackhand"] = "namerica",
["Blackrock"] = "namerica",
["BlackwaterRaiders"] = "namerica",
["BlackwingLair"] = "namerica",
["Blade'sEdge"] = "namerica",
["Bladefist"] = "namerica",
["BleedingHollow"] = "namerica",
["BloodFurnace"] = "namerica",
["Bloodhoof"] = "namerica",
["Bloodscalp"] = "namerica",
["Bonechewer"] = "namerica",
["BoreanTundra"] = "namerica",
["Boulderfist"] = "namerica",
["Bronzebeard"] = "namerica",
["BurningBlade"] = "namerica",
["BurningLegion"] = "namerica",
["Cairne"] = "namerica",
["CenarionCircle"] = "namerica",
["Cenarius"] = "namerica",
["Cho'gall"] = "namerica",
["Chromaggus"] = "namerica",
["Coilfang"] = "namerica",
["Crushridge"] = "namerica",
["Daggerspine"] = "namerica",
["Dalaran"] = "namerica",
["Dalvengyr"] = "namerica",
["DarkIron"] = "namerica",
["Darkspear"] = "namerica",
["Darrowmere"] = "namerica",
["Dawnbringer"] = "namerica",
["Deathwing"] = "namerica",
["DemonSoul"] = "namerica",
["Dentarg"] = "namerica",
["Destromath"] = "namerica",
["Dethecus"] = "namerica",
["Detheroc"] = "namerica",
["Doomhammer"] = "namerica",
["Draenor"] = "namerica",
["Dragonblight"] = "namerica",
["Dragonmaw"] = "namerica",
["Drenden"] = "namerica",
["Dunemaul"] = "namerica",
["Durotan"] = "namerica",
["Duskwood"] = "namerica",
["EarthenRing"] = "namerica",
["EchoIsles"] = "namerica",
["Eitrigg"] = "namerica",
["Eldre'Thalas"] = "namerica",
["Elune"] = "namerica",
["EmeraldDream"] = "namerica",
["Eonar"] = "namerica",
["Eredar"] = "namerica",
["Executus"] = "namerica",
["Exodar"] = "namerica",
["Farstriders"] = "namerica",
["Feathermoon"] = "namerica",
["Fenris"] = "namerica",
["Firetree"] = "namerica",
["Fizzcrank"] = "namerica",
["Frostmane"] = "namerica",
["Frostwolf"] = "namerica",
["Galakrond"] = "namerica",
["Garithos"] = "namerica",
["Garona"] = "namerica",
["Garrosh"] = "namerica",
["Ghostlands"] = "namerica",
["Gilneas"] = "namerica",
["Gnomeregan"] = "namerica",
["Gorefiend"] = "namerica",
["Gorgonnash"] = "namerica",
["Greymane"] = "namerica",
["GrizzlyHills"] = "namerica",
["Gul'dan"] = "namerica",
["Gurubashi"] = "namerica",
["Hakkar"] = "namerica",
["Haomarush"] = "namerica",
["Hellscream"] = "namerica",
["Hydraxis"] = "namerica",
["Hyjal"] = "namerica",
["Icecrown"] = "namerica",
["Illidan"] = "namerica",
["Jaedenar"] = "namerica",
["Kael'thas"] = "namerica",
["Kalecgos"] = "namerica",
["Kargath"] = "namerica",
["Kel'Thuzad"] = "namerica",
["Khadgar"] = "namerica",
["KhazModan"] = "namerica",
["Kil'jaeden"] = "namerica",
["Kilrogg"] = "namerica",
["KirinTor"] = "namerica",
["Korgath"] = "namerica",
["Korialstrasz"] = "namerica",
["KulTiras"] = "namerica",
["LaughingSkull"] = "namerica",
["Lethon"] = "namerica",
["Lightbringer"] = "namerica",
["Lightning'sBlade"] = "namerica",
["Lightninghoof"] = "namerica",
["Llane"] = "namerica",
["Lothar"] = "namerica",
["Madoran"] = "namerica",
["Maelstrom"] = "namerica",
["Magtheridon"] = "namerica",
["Maiev"] = "namerica",
["Mal'Ganis"] = "namerica",
["Malfurion"] = "namerica",
["Malorne"] = "namerica",
["Malygos"] = "namerica",
["Mannoroth"] = "namerica",
["Medivh"] = "namerica",
["Misha"] = "namerica",
["Mok'Nathal"] = "namerica",
["MoonGuard"] = "namerica",
["Moonrunner"] = "namerica",
["Mug'thol"] = "namerica",
["Muradin"] = "namerica",
["Nathrezim"] = "namerica",
["Nazgrel"] = "namerica",
["Nazjatar"] = "namerica",
["Ner'zhul"] = "namerica",
["Nesingwary"] = "namerica",
["Nordrassil"] = "namerica",
["Norgannon"] = "namerica",
["Onyxia"] = "namerica",
["Perenolde"] = "namerica",
["Proudmoore"] = "namerica",
["Quel'dorei"] = "namerica",
["Ravencrest"] = "namerica",
["Ravenholdt"] = "namerica",
["Rexxar"] = "namerica",
["Rivendare"] = "namerica",
["Runetotem"] = "namerica",
["Sargeras"] = "namerica",
["ScarletCrusade"] = "namerica",
["Scilla"] = "namerica",
["Sen'jin"] = "namerica",
["Sentinels"] = "namerica",
["ShadowCouncil"] = "namerica",
["Shadowmoon"] = "namerica",
["Shadowsong"] = "namerica",
["Shandris"] = "namerica",
["ShatteredHalls"] = "namerica",
["ShatteredHand"] = "namerica",
["Shu'halo"] = "namerica",
["SilverHand"] = "namerica",
["Silvermoon"] = "namerica",
["SistersofElune"] = "namerica",
["Skullcrusher"] = "namerica",
["Skywall"] = "namerica",
["Smolderthorn"] = "namerica",
["Spinebreaker"] = "namerica",
["Spirestone"] = "namerica",
["Staghelm"] = "namerica",
["SteamwheedleCartel"] = "namerica",
["Stonemaul"] = "namerica",
["Stormrage"] = "namerica",
["Stormreaver"] = "namerica",
["Stormscale"] = "namerica",
["Suramar"] = "namerica",
["Tanaris"] = "namerica",
["Terenas"] = "namerica",
["Terokkar"] = "namerica",
["TheForgottenCoast"] = "namerica",
["TheScryers"] = "namerica",
["TheUnderbog"] = "namerica",
["TheVentureCo"] = "namerica",
["ThoriumBrotherhood"] = "namerica",
["Thrall"] = "namerica",
["Thunderhorn"] = "namerica",
["Thunderlord"] = "namerica",
["Tichondrius"] = "namerica",
["Tortheldrin"] = "namerica",
["Trollbane"] = "namerica",
["Turalyon"] = "namerica",
["TwistingNether"] = "namerica",
["Uldaman"] = "namerica",
["Uldum"] = "namerica",
["Undermine"] = "namerica",
["Ursin"] = "namerica",
["Uther"] = "namerica",
["Vashj"] = "namerica",
["Vek'nilash"] = "namerica",
["Velen"] = "namerica",
["Warsong"] = "namerica",
["Whisperwind"] = "namerica",
["Wildhammer"] = "namerica",
["Windrunner"] = "namerica",
["Winterhoof"] = "namerica",
["WyrmrestAccord"] = "namerica",
["Ysera"] = "namerica",
["Ysondre"] = "namerica",
["Zangarmarsh"] = "namerica",
["Zul'jin"] = "namerica",
["Zuluhed"] = "namerica",
["Ashkandi"] = "namerica",
["Atiesh"] = "namerica",
["Benediction"] = "namerica",
["BloodsailBuccaneers"] = "namerica",
["Faerlina"] = "namerica",
["Grobbulus"] = "namerica",
["Mankrik"] = "namerica",
["OldBlanchy"] = "namerica",
["Westfall"] = "namerica",
["Whitemane"] = "namerica",
["ChaosBolt"] = "namerica",
["CrusaderStrike"] = "namerica",
["DefiasPillager"] = "namerica",
["Doomhowl"] = "namerica",
["Dreamscythe"] = "namerica",
["LavaLash"] = "namerica",
["LivingFlame"] = "namerica",
["LoneWolf"] = "namerica",
["Nightslayer"] = "namerica",
["Pagle"] = "namerica",
["SkullRock"] = "namerica",
["WildGrowth"] = "namerica",
["Maladath"] = "australia",
}

-- Region 3: Europe & Russia
REALMS_EU = {
["Aegwynn"] = "europe",
["Alexstrasza"] = "europe",
["Alleria"] = "europe",
["Ambossar"] = "europe",
["Aman'Thul"] = "europe",
["Antonidas"] = "europe",
["Anub'arak"] = "europe",
["Area52"] = "europe",
["Arthas"] = "europe",
["Arygos"] = "europe",
["Azshara"] = "europe",
["Baelgun"] = "europe",
["Blackhand"] = "europe",
["Blackmoore"] = "europe",
["Blackrock"] = "europe",
["Blutkessel"] = "europe",
["Dalvengyr"] = "europe",
["DasKonsortium"] = "europe",
["DasSyndikat"] = "europe",
["DerMithrilorden"] = "europe",
["DerRatvonDalaran"] = "europe",
["Destromath"] = "europe",
["Dethecus"] = "europe",
["DieAldor"] = "europe",
["DieArguswacht"] = "europe",
["DieewigeWacht"] = "europe",
["DieNachtwache"] = "europe",
["DieSilberneHand"] = "europe",
["DieTodeskrallen"] = "europe",
["DunMorogh"] = "europe",
["Echsenkessel"] = "europe",
["Eredar"] = "europe",
["Everlook"] = "europe",
["FestungderSt\195\188rme"] = "europe",
["Forscherliga"] = "europe",
["Frostmourne"] = "europe",
["Frostwolf"] = "europe",
["Garrosh"] = "europe",
["Gilneas"] = "europe",
["Gorgonnash"] = "europe",
["Gul'dan"] = "europe",
["Kargath"] = "europe",
["Kel'Thuzad"] = "europe",
["Khaz'goroth"] = "europe",
["Kil'jaeden"] = "europe",
["Krag'jin"] = "europe",
["Lothar"] = "europe",
["Madmortem"] = "europe",
["Mal'Ganis"] = "europe",
["Malfurion"] = "europe",
["Malorne"] = "europe",
["Malygos"] = "europe",
["Mannoroth"] = "europe",
["Mug'thol"] = "europe",
["Nathrezim"] = "europe",
["Nazjatar"] = "europe",
["Nera'thor"] = "europe",
["Nethersturm"] = "europe",
["Norgannon"] = "europe",
["Nozdormu"] = "europe",
["Onyxia"] = "europe",
["Perenolde"] = "europe",
["Proudmoore"] = "europe",
["Rajaxx"] = "europe",
["Rexxar"] = "europe",
["Sen'jin"] = "europe",
["Shattrath"] = "europe",
["Shen'dralar"] = "europe",
["SteamwheedleCartel"] = "europe",
["Taerar"] = "europe",
["Teldrassil"] = "europe",
["Terrordar"] = "europe",
["Theradras"] = "europe",
["Thrall"] = "europe",
["Tichondrius"] = "europe",
["Tirion"] = "europe",
["Todeswache"] = "europe",
["Ulduar"] = "europe",
["Un'Goro"] = "europe",
["Vek'lor"] = "europe",
["Venoxis"] = "europe",
["Wrathbringer"] = "europe",
["Ysera"] = "europe",
["ZirkeldesCenarius"] = "europe",
["Zuluhed"] = "europe",
["Arak-arahm"] = "europe",
["Arathi"] = "europe",
["Archimonde"] = "europe",
["Auberdine"] = "europe",
["Chants\195\169ternels"] = "europe",
["Cho'gall"] = "europe",
["Chromaggus"] = "europe",
["Confr\195\169rieduThorium"] = "europe",
["ConseildesOmbres"] = "europe",
["CulteDeLaRiveNoire"] = "europe",
["Dalaran"] = "europe",
["Drek'Thar"] = "europe",
["Eitrigg"] = "europe",
["Eldre'Thalas"] = "europe",
["Elune"] = "europe",
["Garona"] = "europe",
["Hyjal"] = "europe",
["Illidan"] = "europe",
["Kael'thas"] = "europe",
["KhazModan"] = "europe",
["KirinTor"] = "europe",
["Krasus"] = "europe",
["LaCroisade\195\169carlate"] = "europe",
["LesClairvoyants"] = "europe",
["LesSentinelles"] = "europe",
["Mar\195\169cagedeZangar"] = "europe",
["Medivh"] = "europe",
["Naxxramas"] = "europe",
["Ner'zhul"] = "europe",
["Rashgarroth"] = "europe",
["Sargeras"] = "europe",
["Sinstralis"] = "europe",
["Suramar"] = "europe",
["Templenoir"] = "europe",
["Throk'Feroth"] = "europe",
["Uldaman"] = "europe",
["Varimathras"] = "europe",
["Vol'jin"] = "europe",
["Ysondre"] = "europe",
["C'Thun"] = "europe",
["ColinasPardas"] = "europe",
["DunModr"] = "europe",
["Exodar"] = "europe",
["LosErrantes"] = "europe",
["Mandokir"] = "europe",
["Minahonda"] = "europe",
["Sanguino"] = "europe",
["Shen'dralar"] = "europe",
["Tyrande"] = "europe",
["Uldum"] = "europe",
["Zul'jin"] = "europe",
["Nemesis"] = "europe",
["Pozzodell'Eternit\195\160"] = "europe",
["Aggra"] = "europe",
["GrimBatol"] = "europe",
["Ashenvale"] = "russia",
["Azuregos"] = "russia",
["Blackscar"] = "russia",
["BootyBay"] = "russia",
["BoreanTundra"] = "russia",
["Chromie"] = "russia",
["Deathguard"] = "russia",
["Deepholm"] = "russia",
["Eversong"] = "russia",
["Flamegor"] = "russia",
["Fordragon"] = "russia",
["Galakrond"] = "russia",
["Goldrinn"] = "russia",
["Gordunni"] = "russia",
["Grommash"] = "russia",
["HowlingFjord"] = "russia",
["LichKing"] = "russia",
["MoltenCore"] = "russia",
["Razuvious"] = "russia",
["Soulflayer"] = "russia",
["Theradras"] = "russia",
["Thermaplugg"] = "russia",
["Wyrmthalak"] = "russia",
["Agamaggan"] = "europe",
["Aggramar"] = "europe",
["Ahn'Qiraj"] = "europe",
["Al'Akir"] = "europe",
["Alonsus"] = "europe",
["Anachronos"] = "europe",
["Arathor"] = "europe",
["ArgentDawn"] = "europe",
["Aszune"] = "europe",
["Auchindoun"] = "europe",
["AzjolNerub"] = "europe",
["Azuremyst"] = "europe",
["Balnazzar"] = "europe",
["Blade'sEdge"] = "europe",
["Bladefist"] = "europe",
["Bloodfeather"] = "europe",
["Bloodhoof"] = "europe",
["Bloodscalp"] = "europe",
["Boulderfist"] = "europe",
["Bronzebeard"] = "europe",
["BronzeDragonflight"] = "europe",
["BurningBlade"] = "europe",
["BurningLegion"] = "europe",
["BurningSteppes"] = "europe",
["ChamberofAspects"] = "europe",
["Chromaggus"] = "europe",
["Crushridge"] = "europe",
["Daggerspine"] = "europe",
["DarkmoonFaire"] = "europe",
["Darksorrow"] = "europe",
["Darkspear"] = "europe",
["Deathwing"] = "europe",
["DefiasBrotherhood"] = "europe",
["Dentarg"] = "europe",
["Doomhammer"] = "europe",
["Draenor"] = "europe",
["Dragonblight"] = "europe",
["Dragonmaw"] = "europe",
["Drak'thul"] = "europe",
["Dunemaul"] = "europe",
["EarthenRing"] = "europe",
["EmeraldDream"] = "europe",
["Emeriss"] = "europe",
["Eonar"] = "europe",
["Executus"] = "europe",
["Frostmane"] = "europe",
["Frostwhisper"] = "europe",
["Genjuros"] = "europe",
["Ghostlands"] = "europe",
["GrimBatol"] = "europe",
["Hakkar"] = "europe",
["Haomarush"] = "europe",
["Hellfire"] = "europe",
["Hellscream"] = "europe",
["Jaedenar"] = "europe",
["Karazhan"] = "europe",
["Kazzak"] = "europe",
["Khadgar"] = "europe",
["Kilrogg"] = "europe",
["Kor'gall"] = "europe",
["KulTiras"] = "europe",
["LaughingSkull"] = "europe",
["Lightbringer"] = "europe",
["Lightning'sBlade"] = "europe",
["Magtheridon"] = "europe",
["Mazrigos"] = "europe",
["Moonglade"] = "europe",
["Nagrand"] = "europe",
["Neptulon"] = "europe",
["Nordrassil"] = "europe",
["Outland"] = "europe",
["Quel'Thalas"] = "europe",
["Ragnaros"] = "europe",
["Ravencrest"] = "europe",
["Ravenholdt"] = "europe",
["Runetotem"] = "europe",
["Saurfang"] = "europe",
["ScarshieldLegion"] = "europe",
["Shadowsong"] = "europe",
["ShatteredHalls"] = "europe",
["ShatteredHand"] = "europe",
["Silvermoon"] = "europe",
["Skullcrusher"] = "europe",
["Spinebreaker"] = "europe",
["Sporeggar"] = "europe",
["Stormrage"] = "europe",
["Stormreaver"] = "europe",
["Stormscale"] = "europe",
["Sunstrider"] = "europe",
["Sylvanas"] = "europe",
["Talnivarr"] = "europe",
["TarrenMill"] = "europe",
["Terenas"] = "europe",
["Terokkar"] = "europe",
["TheMaelstrom"] = "europe",
["TheSha'tar"] = "europe",
["TheVentureCo"] = "europe",
["Thunderhorn"] = "europe",
["Trollbane"] = "europe",
["Turalyon"] = "europe",
["Twilight'sHammer"] = "europe",
["TwistingNether"] = "europe",
["Vashj"] = "europe",
["Vek'nilash"] = "europe",
["Wildhammer"] = "europe",
["Xavius"] = "europe",
["Zenedar"] = "europe",
["Firemaw"] = "europe",
["Gehennas"] = "europe",
["Golemagg"] = "europe",
["MirageRaceway"] = "europe",
["Mograine"] = "europe",
["Nek'Rosh"] = "europe",
["PyrewoodVillage"] = "europe",
["Soulseeker"] = "europe",
["Spineshatter"] = "europe",
["Stitches"] = "europe",
["Thunderstrike"] = "europe",
["WildGrowth"] = "europe",
["ZandalarTribe"] = "europe",
}

-- Regions 2, 4, 5: Korea, Taiwan, China
REALMS_ASIA = {
["AbyssalMaw"] = "china",
["AeriePeakCN"] = "china",
["Akil'zon"] = "china",
["Algalon"] = "china",
["Chronos"] = "china",
["Goldshire"] = "china",
["LichKing"] = "china",
["Onyxia"] = "china",
["SilverHand"] = "china",
["SilvermoonCN"] = "china",
["TitanReforged"] = "china",
["Azshara"] = "korea",
["BurningLegion"] = "korea",
["Cenarius"] = "korea",
["Deathwing"] = "korea",
["Durotan"] = "korea",
["Frostmourne"] = "korea",
["Hellscream"] = "korea",
["Hyjal"] = "korea",
["Ragnaros"] = "korea",
["Windrunner"] = "korea",
["Zul'jin"] = "korea",
["Arthas"] = "taiwan",
["Arygos"] = "taiwan",
["BleedingHollow"] = "taiwan",
["ChillwindPoint"] = "taiwan",
["CrystalpineStinger"] = "taiwan",
["DemonFallCanyon"] = "taiwan",
["Dragonmaw"] = "taiwan",
["Frostmane"] = "taiwan",
["Global"] = "taiwan",
["Icecrown"] = "taiwan",
["KrolBlade"] = "taiwan",
["Light'sHope"] = "taiwan",
["Menethil"] = "taiwan",
["Nightsong"] = "taiwan",
["OldBlanchy"] = "taiwan",
["OrderoftheCloudSerpent"] = "taiwan",
["Quel'dorei"] = "taiwan",
["Shadowmoon"] = "taiwan",
["Skywall"] = "taiwan",
["Spirestone"] = "taiwan",
["Stormscale"] = "taiwan",
["WorldTree"] = "taiwan",
["Whisperwind"] = "taiwan",
["Wrathbringer"] = "taiwan",
["ZealotBlade"] = "taiwan",
}
end

local REGION_ICON_PATH = MEDIA .. "regions\\"

-- Lookup a realm name -> mini region realmName should have spaces removed
local function GetRealmMiniRegion(realmName)
    if not realmName or realmName == "" then return nil end
    if not REALMS_NA then LoadRealms() end
    local clean = realmName:gsub("%s+", "")
    -- Check player's own region table first (handles overlapping realm names)
    local myRegion = GetCurrentRegion()
    local primary, secondary
    if myRegion == 3 then
        primary, secondary = REALMS_EU, REALMS_NA
    elseif myRegion == 2 or myRegion == 4 or myRegion == 5 then
        primary, secondary = REALMS_ASIA, REALMS_NA
    else
        primary, secondary = REALMS_NA, REALMS_EU
    end
    return primary[clean] or secondary[clean] or REALMS_ASIA[clean]
end

-- Get the mini region for a BNet friend's game account
local function GetFriendMiniRegion(gameAccountInfo)
    if not gameAccountInfo then return nil end
    -- Try realmName first
    local realm = gameAccountInfo.realmName
    if realm and realm ~= "" then
        local result = GetRealmMiniRegion(realm)
        if result then return result end
    end
    -- Fallback: parse richPresence ("Zone - Realm" format)
    -- If realmName was empty, the friend is likely cross-region, so check OTHER tables first
    local rich = gameAccountInfo.richPresence
    if rich and rich ~= "" then
        local realmFromRich = rich:match("%s%-%s(.+)$")
        if realmFromRich and realmFromRich ~= "" then
            if not REALMS_NA then LoadRealms() end
            local clean = realmFromRich:gsub("%s+", "")
            local myRegion = GetCurrentRegion()
            -- Check the opposite region first since empty realmName = cross-region friend
            if myRegion == 1 then
                return REALMS_EU[clean] or REALMS_ASIA[clean] or REALMS_NA[clean]
            elseif myRegion == 3 then
                return REALMS_NA[clean] or REALMS_ASIA[clean] or REALMS_EU[clean]
            else
                return REALMS_NA[clean] or REALMS_EU[clean] or REALMS_ASIA[clean]
            end
        end
    end
    return nil
end

-- Get the full region for a mini region
local function GetFullRegion(miniRegion)
    return miniRegion and MINI_TO_FULL[miniRegion]
end

-- Get the player's own full region
local function GetMyFullRegion()
    return REGION_ID_TO_FULL[GetCurrentRegion()] or "NA"
end

-- Get the icon path for a mini region
local function GetRegionIcon(miniRegion)
    if not miniRegion then return nil end
    return REGION_ICON_PATH .. miniRegion .. ".png"
end

-- Public API
EllesmereUI.GetRealmMiniRegion = GetRealmMiniRegion
EllesmereUI.GetFriendMiniRegion = GetFriendMiniRegion
EllesmereUI.GetFullRegion = GetFullRegion
EllesmereUI.GetMyFullRegion = GetMyFullRegion
EllesmereUI.GetRegionIcon = GetRegionIcon
EllesmereUI.MINI_TO_FULL = MINI_TO_FULL

-------------------------------------------------------------------------------
--  Class colour escape per class file (lazy-built cache)
-------------------------------------------------------------------------------
local classColorCodes = {}
function Kit.ClassColorCode(classFile)
    local code = classColorCodes[classFile]
    if code then return code end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not cc then return nil end
    code = EllesmereUI.HexColor(cc.r, cc.g, cc.b)
    classColorCodes[classFile] = code
    return code
end

-- Class Icon Theme: the choices both settings pages list
Kit.ICON_STYLE_VALUES = {
    blizzard = "Blizzard",
    modern   = "Modern",
    pixel    = "Pixel",
    pixelsComic = "Pixels Comic",
    glyph    = "Glyph",
    arcade   = "Arcade",
    legend   = "Legend",
    midnight = "Midnight",
    runic    = "Runic",
}
Kit.ICON_STYLE_ORDER = {
    "blizzard", "modern", "pixel", "pixelsComic", "glyph",
    "arcade", "legend", "midnight", "runic",
}

-------------------------------------------------------------------------------
--  12.1 Social UI friend tiles
--
--  DECORATION ONLY. This file never creates a row, never writes element data,
--  and never mutates Blizzard's data provider. That restraint is the entire
--  design, and it is not stylistic caution -- it is the conclusion of a taint
--  bisect run against 12.1:
--
--    overlay off entirely .............................. whispers clean
--    our rows, every decoration disabled .............. whispers TAINTED
--    Blizzard's rows, only MoveNode re-parenting ...... whispers TAINTED
--
--  Any mutation of the friends list data taints the execution that Blizzard's
--  secure OnClick depends on; that reaches SetTellTarget, whose whisper target
--  is a secret value in 12.1, and BNet whispers stop opening. Styling was the
--  one thing the bisect cleared. So we style, and we touch nothing else.
--
--  Blizzard therefore owns: the ScrollBox, the provider, row creation, row
--  population, the click handler and the right-click menu. We own: paint.
--
--  A host starts it once per session (Kit.StartTiles) with its settings,
--  its look and its font; the host's settings page repaints through
--  Kit.RedecorateTiles.
-------------------------------------------------------------------------------
-- External weak-keyed state. Never write custom keys onto a Blizzard frame.
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-------------------------------------------------------------------------------
--  Tuning
-------------------------------------------------------------------------------
-- ROW HEIGHT IS BLIZZARD'S. DO NOT TRY TO CHANGE IT.
--
-- Their height is 70 (85 with larger text), from
-- FriendsListSocialCardMixin.GetActiveBaseHeight, captured by REFERENCE into the view's
-- extent registration at its OnLoad -- before this addon exists, so replacing the mixin
-- function afterwards cannot reach it. The only lever is overwriting that stored
-- registration, i.e. writing into view's own TemplateRegistrations table.
--
-- That write was TESTED and it TAINTS BNet whispers: the extent calculator is
-- read during layout, layout builds the rows, and a row built from an execution
-- that read our value carries taint into the secure OnClick and on into
-- SetTellTarget (whose whisper target is a secret value in 12.1). With the
-- write disabled and every other decoration below still active, whispers are
-- clean -- so decoration is fine and this one write was the whole problem.
--
-- CLOSED. Two separate in-game tests, both TAINTED:
--   1. reg.baseHeight = 46 AND reg.baseHeightCalculator = our closure
--   2. reg.baseHeightCalculator = nil, reg.baseHeight = 46  (plain number,
--      nothing of ours executing inside their layout pass)
-- Test 2 is the decisive one: Blizzard's own code merely READS a number out of
-- its own table, and that is still enough. So it is not about our code running
-- in their path -- reading any value an addon wrote taints the execution, and
-- that execution builds the rows whose secure OnClick opens the whisper menu.
--
-- 70 (85 at larger text) is therefore a hard floor. The only remaining lever on
-- density is the GAME's text-size setting: CalculateScaledHeight runs the base
-- through TextSizeManager:GetScaledValueWeighted with scaleWeight 0.6, so a
-- below-default text size genuinely scales the row under 70.
--
-- So nothing here writes the row height. Do not re-attempt; both shapes are
-- already disproven.
--
-- The tile's icon square: the name starts past it.
local TILE_TARGET_H     = 46

-- Kill switch for all tile decoration. Proven taint-free, so this is only a
-- convenience for future bisects -- leave it true.
local TILE_PAINT = true

-- Left inset of the text block, derived rather than fixed: the class icon is a
-- square that spans the row height, so the text starts at rowHeight + a gutter.
-- Resolved per paint from the row's live height.
local TILE_TEXT_GAP  = 4
-- Three lines, each its own size: Battle.net name / character name + level / location.
local TILE_NAME_SIZE = 15
local TILE_CHAR_SIZE = 12
local TILE_INFO_SIZE = 12
local TILE_LINE_GAP  = -5
-- The row height is Blizzard's now (GetActiveBaseHeight = 70, or 85 in the
-- expanded text-size layout), and we cannot change it without touching their
-- view's extent calculator -- which is provider-adjacent, and provider contact
-- is what taints whispers. So the text block is anchored to the row's vertical
-- CENTRE rather than pinned to the top: it then sits correctly at any height
-- Blizzard picks. The block is centred per paint from its measured height (the
-- line count varies), so there is no fixed vertical offset any more.

local MODERN_BLIZZ_TEX = "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png"
local TEX_BASE         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local MB_L, MB_R, MB_T, MB_B = 0.25, 1, 0, 0.75

local TILE_ONLINE_MASK_TEX = TEX_BASE .. "gradient-lr.tga"
local TILE_ONLINE_BG_ALPHA = 0.25
local TILE_HOVER_MASK_TEX  = TEX_BASE .. "fade-right.tga"
local TILE_HOVER_ALPHA     = 0.2
-- Selection reuses the hover treatment and draws on its own layer ABOVE it, so
-- a selected row that is also hovered shows both and reads brighter.
local TILE_SEL_ALPHA       = 0.4

local OFFLINE_ICON         = MEDIA .. "offline.png"
local FACTION_TEX_ALLIANCE = MEDIA .. "alliance.png"
local FACTION_TEX_HORDE    = MEDIA .. "horde.png"
local FACTION_TEX_NEUTRAL  = MEDIA .. "neutral.png"

local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"
local CLASS_ICON_SPRITE_TEX = {}
for _, style in ipairs({ "modern", "dark", "light", "clean" }) do
    CLASS_ICON_SPRITE_TEX[style] = CLASS_ICON_SPRITE_BASE .. style .. ".tga"
end
local CLASS_SPRITE_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS

-- The class icon sprite sheet of a Class Icon Theme style (the tiles and the
-- Friends module's legacy rows)
function Kit.ClassIconSprite(style)
    return CLASS_ICON_SPRITE_TEX[style] or (CLASS_ICON_SPRITE_BASE .. style .. ".tga")
end

local MINI_DISPLAY = {
    namerica = "North America", samerica = "South America",
    australia = "Australia", europe = "Europe",
    russia = "Russia", korea = "Korea",
    taiwan = "Taiwan", china = "China",
}

-- The status orb's atlas art, looked up at the first orb painted
local _orbFile, _orbL, _orbR, _orbT, _orbB
local _orbLooked = false
local function LookUpOrb()
    _orbLooked = true
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("lootroll-animreveal-a")
    if info and info.file then
        _orbFile = info.file
        local aL, aR = info.leftTexCoord or 0, info.rightTexCoord or 1
        local aT, aB = info.topTexCoord or 0, info.bottomTexCoord or 1
        _orbL, _orbR, _orbT, _orbB = aL, aL + (aR - aL) / 6, aT, aT + (aB - aT) / 2
    end
end

-- Paints the status orb's art (the atlas' first of 6 columns, top of 2 rows)
-- on tex (the tiles and the Friends module's legacy rows)
function Kit.StatusOrbArt(tex)
    if not _orbLooked then LookUpOrb() end
    if _orbFile then
        tex:SetTexture(_orbFile)
        tex:SetTexCoord(_orbL, _orbR, _orbT, _orbB)
    else
        tex:SetAtlas("lootroll-animreveal-a")
        tex:SetTexCoord(0, 1 / 6, 0, 0.5)
    end
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
-- The host this session (Kit.StartTiles): its settings table (the Friends
-- List profile's friends table, or the Blizzard Skins+ card's), its look and
-- its font key.
local host

local function Settings()
    return host and host.Settings()
end

local function Enabled()
    local f = Settings()
    return f ~= nil and f.enabled ~= false
end

local function FontPath()
    return (EllesmereUI.GetFontPath(host.fontKey)) or STANDARD_TEXT_FONT
end

local function GetClassFile(accountInfo)
    local gi = accountInfo and accountInfo.gameAccountInfo
    if not gi then return nil end
    if gi.classID and gi.classID > 0 then
        local _, classFile = GetClassInfo(gi.classID)
        if classFile then return classFile end
    end
    if gi.className then
        return EllesmereUI.ClassTokenFromLocalized(gi.className)
    end
    return nil
end

local function IsSameProjectOnline(gi)
    if not (gi and gi.isOnline) then return false end
    if gi.clientProgram ~= BNET_CLIENT_WOW then return false end
    return gi.wowProjectID == WOW_PROJECT_ID or gi.wowProjectID == nil
end

local function TileState(accountInfo)
    local gi = accountInfo and accountInfo.gameAccountInfo
    if not (gi and gi.isOnline) then return "offline" end
    return IsSameProjectOnline(gi) and "retail" or "other_game"
end

-------------------------------------------------------------------------------
--  One-time structure per pooled card
-------------------------------------------------------------------------------
local function SkinStructure(card)
    local d = GetFFD(card)
    if d.skinned then return d end
    d.skinned = true

    d.tileBg = card:CreateTexture(nil, "BACKGROUND", nil, 2)
    d.tileBg:SetAllPoints()
    d.tileBg:SetColorTexture(0, 0, 0, 0.10)

    d.onlineBg = card:CreateTexture(nil, "BACKGROUND", nil, 3)
    d.onlineBg:SetTexture(MODERN_BLIZZ_TEX)
    d.onlineBg:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.onlineBg:SetAllPoints()
    d.onlineBg:SetAlpha(TILE_ONLINE_BG_ALPHA)
    d.onlineBg:Hide()
    d.onlineMask = card:CreateMaskTexture()
    d.onlineMask:SetTexture(TILE_ONLINE_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.onlineMask:SetAllPoints(d.onlineBg)
    d.onlineBg:AddMaskTexture(d.onlineMask)

    d.factionBg = card:CreateTexture(nil, "BACKGROUND", nil, 4)

    d.hoverBar = card:CreateTexture(nil, "ARTWORK", nil, -7)
    d.hoverBar:SetAllPoints()
    d.hoverBar:SetTexture(MODERN_BLIZZ_TEX)
    d.hoverBar:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.hoverBar:SetAlpha(TILE_HOVER_ALPHA)
    d.hoverBar:Hide()
    d.hoverMask = card:CreateMaskTexture()
    d.hoverMask:SetTexture(TILE_HOVER_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.hoverMask:SetAllPoints(d.hoverBar)
    d.hoverBar:AddMaskTexture(d.hoverMask)

    d.hoverFill = card:CreateTexture(nil, "ARTWORK", nil, -8)
    d.hoverFill:SetAllPoints()
    d.hoverFill:SetColorTexture(1, 1, 1, 0.02)
    d.hoverFill:SetBlendMode("ADD")
    d.hoverFill:Hide()

    card:HookScript("OnEnter", function() d.hoverBar:Show(); d.hoverFill:Show() end)
    card:HookScript("OnLeave", function() d.hoverBar:Hide(); d.hoverFill:Hide() end)

    -- Selection: same look as hover, own sublevels (-5/-6) so it sits above the
    -- hover pair (-7/-8) rather than replacing it. Its own mask texture, since
    -- AddMaskTexture is additive and sharing one would stack on the hover bar.
    d.selBar = card:CreateTexture(nil, "ARTWORK", nil, -5)
    d.selBar:SetAllPoints()
    d.selBar:SetTexture(MODERN_BLIZZ_TEX)
    d.selBar:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.selBar:SetAlpha(TILE_SEL_ALPHA)
    d.selBar:Hide()
    d.selMask = card:CreateMaskTexture()
    d.selMask:SetTexture(TILE_HOVER_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.selMask:SetAllPoints(d.selBar)
    d.selBar:AddMaskTexture(d.selMask)

    d.selFill = card:CreateTexture(nil, "ARTWORK", nil, -6)
    d.selFill:SetAllPoints()
    d.selFill:SetColorTexture(1, 1, 1, 0.02)
    d.selFill:SetBlendMode("ADD")
    d.selFill:Hide()

    d.classIcon = card:CreateTexture(nil, "ARTWORK", nil, 2)

    d.name = card:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(d.name, true)
    d.name:SetFont(FontPath(), TILE_NAME_SIZE, "")
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    -- Horizontal inset is re-resolved per paint in PaintCard (it follows the
    -- row height); this is just the initial placement.
    d.name:SetPoint("TOPLEFT", card, "TOPLEFT", TILE_TARGET_H + TILE_TEXT_GAP, 0)

    -- Character name + level, its own line under the Battle.net name.
    d.charLine = card:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(d.charLine, true)
    d.charLine:SetFont(FontPath(), TILE_CHAR_SIZE, "")
    d.charLine:SetJustifyH("LEFT")
    d.charLine:SetWordWrap(false)
    d.charLine:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, TILE_LINE_GAP)

    d.info = card:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(d.info, true)
    d.info:SetFont(FontPath(), TILE_INFO_SIZE, "")
    d.info:SetJustifyH("LEFT")
    d.info:SetWordWrap(false)
    -- Anchored per paint: it follows charLine when there is one, otherwise the
    -- name directly, so offline friends do not leave a hole.

    d.orb = card:CreateTexture(nil, "OVERLAY", nil, 3)
    d.orb:SetSize(18, 18)
    Kit.StatusOrbArt(d.orb)

    return d
end

-- Blizzard repopulates its card art on every recycle, so this runs per paint.
local CARD_TEXT_KEYS = { "FriendName", "Name", "Level", "Class", "Location" }
local function SuppressBlizzardArt(card)
    if card.Background then card.Background:Hide(); card.Background:SetAlpha(0) end
    local hl = card.GetHighlightTexture and card:GetHighlightTexture()
    if hl then hl:SetAlpha(0); hl:SetVertexColor(0, 0, 0, 0) end
    for i = 1, #CARD_TEXT_KEYS do
        local fs = card[CARD_TEXT_KEYS[i]]
        if fs then fs:Hide(); fs:SetAlpha(0) end
    end
    if card.PresenceHolder then card.PresenceHolder:Hide(); card.PresenceHolder:SetAlpha(0) end
    if card.StateDisplay then card.StateDisplay:Hide(); card.StateDisplay:SetAlpha(0) end
    if card.GameIconHolder then card.GameIconHolder:Hide() end
end

-------------------------------------------------------------------------------
--  Per-paint passes
-------------------------------------------------------------------------------
local ClassColorCode = Kit.ClassColorCode

-- Line 1: the Battle.net account name on its own.
local function BuildName(accountInfo)
    if FriendsListUtil and FriendsListUtil.BuildFriendNameDisplayText then
        return FriendsListUtil.BuildFriendNameDisplayText(accountInfo)
    end
    return accountInfo.accountName or ""
end

-- The colour Blizzard uses for the location line, so the level suffix can match
-- it rather than the character name.
local function LocationColor(accountInfo)
    local gi = accountInfo.gameAccountInfo
    local online = gi ~= nil and gi.isOnline
    if online then return FRIENDS_GRAY_COLOR or NORMAL_FONT_COLOR end
    return DARKGRAY_COLOR or GRAY_FONT_COLOR
end

-- Line 2: character name (class-coloured) plus the level, the level tinted to
-- match the location line below it. Empty when the friend is not on a character
-- in this project, which collapses the row to two lines.
local function BuildCharLine(accountInfo)
    local gi = accountInfo.gameAccountInfo
    local charName = gi and gi.characterName
    if not (IsSameProjectOnline(gi) and charName and charName ~= "") then return "" end

    local shown = charName
    local p = Settings()
    if p and p.classColorNames then
        local code = ClassColorCode(GetClassFile(accountInfo) or "")
        if code then shown = code .. charName .. "|r" end
    end

    local lvl = gi.characterLevel
    if lvl then
        local levelText
        if SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT then
            levelText = format(SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT, lvl)
        else
            levelText = EllesmereUI.Lf("(Level %d)", lvl)
        end
        local c = LocationColor(accountInfo)
        if c and c.WrapTextInColorCode then
            levelText = c:WrapTextInColorCode(levelText)
        end
        shown = shown .. " " .. levelText
    end
    return shown
end

local function BuildInfo(accountInfo)
    local text = ""
    if FriendsListUtil and FriendsListUtil.BuildLocationDisplayText then
        text = FriendsListUtil.BuildLocationDisplayText(accountInfo) or ""
    end
    if text == "" then
        local gi = accountInfo.gameAccountInfo
        local cp = gi and gi.clientProgram
        if gi and gi.isOnline and (cp == "App" or cp == "BSAp") then
            local loc = GetLocale()
            text = (loc == "enUS" or loc == "enGB") and "In App" or "Battle.Net"
        end
    end
    -- Legacy ||EUI:Group|| tags are stripped from any note we display.
    local note = EllesmereUI.StripFriendNoteTag(accountInfo.note)
    if note then
        if text ~= "" then
            text = text .. "  |cff888888|  " .. note .. "|r"
        else
            text = EllesmereUI.COLOR_CODES.DIM .. note .. "|r"
        end
    end
    return text
end

-- The chosen Class Icon Theme's art for one class on `icon`. Shared by the
-- EllesmereUI tile and the stock-style decoration.
local function SetClassIconTex(icon, style, classFile)
    if style == "blizzard" then
        icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then icon:SetTexCoord(unpack(coords)) end
    else
        local coords = CLASS_SPRITE_COORDS[classFile]
        if coords then
            icon:SetTexture(Kit.ClassIconSprite(style))
            icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
    end
end

local function UpdateClassIcon(card, d, accountInfo)
    local p = Settings()
    if not (p and p.showClassIcons ~= false) then d.classIcon:Hide(); return end

    local h = (card:GetHeight() or 0) - 4
    if h <= 0 then d.classIcon:Hide(); return end

    local icon, state = d.classIcon, TileState(accountInfo)
    icon:ClearAllPoints()

    if state == "retail" then
        local inset = math.floor(h * 0.025 + 0.5)
        icon:SetPoint("LEFT", card, "LEFT", 4, 0)
        icon:SetPoint("TOP", card, "TOP", 0, -(2 + inset))
        icon:SetPoint("BOTTOM", card, "BOTTOM", 0, 2 + inset)
        local iconH = h - inset * 2
        if iconH > 0 then icon:SetWidth(iconH) end

        local classFile = GetClassFile(accountInfo)
        if not classFile then icon:Hide(); return end

        SetClassIconTex(icon, p.iconStyle or "modern", classFile)
        icon:SetDesaturated(false)
        icon:SetAlpha(1)
    else
        local smallH = math.floor(h * 0.75)
        icon:SetSize(smallH, smallH)
        icon:SetPoint("LEFT", card, "LEFT", 4 + math.floor((h - smallH) / 2), 0)
        if state == "other_game" then
            local src = card.GameIconHolder and card.GameIconHolder.Icon
            local tex = src and src:GetTexture()
            if tex then icon:SetTexture(tex); icon:SetTexCoord(0, 1, 0, 1) end
            icon:SetAlpha(1)
        else
            icon:SetTexture(OFFLINE_ICON)
            icon:SetTexCoord(0, 1, 0, 1)
            icon:SetAlpha(0.5)
        end
        icon:SetDesaturated(false)
    end
    icon:Show()
end

local function UpdateFaction(card, d, accountInfo)
    local gi = accountInfo.gameAccountInfo
    local isRetail = IsSameProjectOnline(gi)
    local p = Settings()
    local show = not p or p.factionBanners ~= false

    local path = FACTION_TEX_NEUTRAL
    if show and isRetail and gi.factionName == "Alliance" then
        path = FACTION_TEX_ALLIANCE
    elseif show and isRetail and gi.factionName == "Horde" then
        path = FACTION_TEX_HORDE
    end

    local tex = d.factionBg
    tex:SetTexture(path)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
    tex:SetAlpha(0.2)
    tex:Show()
end

local function UpdateOrb(d, accountInfo)
    local gi = accountInfo.gameAccountInfo
    local isOnline = gi and gi.isOnline

    -- AFK/DND can arrive as secret values; never branch on them directly.
    local _isv = issecretvalue
    local rawAFK, rawDND = accountInfo.isAFK, accountInfo.isDND
    local isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
    local isDND = (not _isv or not _isv(rawDND)) and rawDND or false

    local orb = d.orb
    orb:ClearAllPoints()
    orb:SetPoint("TOPLEFT", d.name, "TOPLEFT", (d.name:GetStringWidth() or 0) - 1, 2)

    if isOnline then
        if isDND then orb:SetVertexColor(1, 0.2, 0.2, 1)
        elseif isAFK then orb:SetVertexColor(1, 0.8, 0, 1)
        else orb:SetVertexColor(0.2, 1, 0.2, 1) end
    else
        orb:SetVertexColor(0.4, 0.4, 0.4, 0.6)
    end
    orb:Show()
end

-- Stock styles: a plain region mark (no mouse, so the row keeps every click
-- and hover; Blizzard's own tooltip already names a friend's region) in the
-- free corner above the 12.1 card's party button, or in the legacy row's
-- empty left gutter under its status icon (clear of the name, the favourite
-- star, the info line and the logo).
local STOCK_REGION_SIZE = 14
local function UpdateStockRegion(card, d, accountInfo)
    local p = Settings()
    local gi = accountInfo and accountInfo.gameAccountInfo
    -- Same-region friends never carry a mark: skip the realm lookup for them.
    if (p and p.showRegionIcons == false) or not gi or gi.isInCurrentRegion == true then
        if d.regionMark then d.regionMark:Hide() end
        return
    end
    local myFull = GetMyFullRegion()
    local mini = GetFriendMiniRegion(gi)
    local full = mini and GetFullRegion(mini)
    if not (mini and full and full ~= myFull) then
        if d.regionMark then d.regionMark:Hide() end
        return
    end
    local mark = d.regionMark
    if not mark then
        mark = card:CreateTexture(nil, "OVERLAY", nil, 7)
        mark:SetSize(STOCK_REGION_SIZE, STOCK_REGION_SIZE)
        if card.PartyButton then
            mark:SetPoint("BOTTOM", card.PartyButton, "TOP", 0, 1)
        elseif card.status and card.gameIcon then
            mark:SetSize(12, 12)
            mark:SetPoint("TOP", card.status, "BOTTOM", 0, -1)
        else
            mark:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -3)
        end
        d.regionMark = mark
    end
    if d.regionMini ~= mini then
        d.regionMini = mini
        mark:SetTexture(GetRegionIcon(mini))
        mark:SetTexCoord(0, 1, 0, 1)
    end
    mark:Show()
end

-- The region icon button on a friend's card or legacy row (frame; its state in
-- d, the frame's FFD entry): shown while show is true and the friend plays in
-- another region than ours, left of anchor (the frame's invite button) when
-- there is one. The tooltip names the region.
local function RegionOnEnter(self)
    EllesmereUI.ShowWidgetTooltip(self, self._regionLabel or "")
end
local function RegionOnLeave()
    EllesmereUI.HideWidgetTooltip()
end
function Kit.UpdateRegionButton(frame, d, gameAccountInfo, anchor, show)
    local mini = show and gameAccountInfo and GetFriendMiniRegion(gameAccountInfo)
    local full = mini and GetFullRegion(mini)
    if not (mini and full and full ~= GetMyFullRegion()) then
        if d.regionBtn then d.regionBtn:Hide() end
        return
    end

    if not d.regionBtn then
        local rb = CreateFrame("Button", nil, frame)
        rb:SetFrameLevel(frame:GetFrameLevel() + 5)
        rb._tex = rb:CreateTexture(nil, "OVERLAY", nil, 7)
        rb._tex:SetAllPoints()
        rb._tex:SetAlpha(0.25)
        rb:SetScript("OnEnter", RegionOnEnter)
        rb:SetScript("OnLeave", RegionOnLeave)
        local iconH = math.floor((frame:GetHeight() or 40) * 0.8)
        rb:SetSize(iconH, iconH)
        if anchor then
            rb:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
        else
            rb:SetPoint("RIGHT", frame, "RIGHT", -30, 0)
        end
        d.regionBtn = rb
    end

    local rb = d.regionBtn
    if rb._lastMini ~= mini then
        rb._lastMini = mini
        rb._tex:SetTexture(GetRegionIcon(mini))
        rb._tex:SetTexCoord(0, 1, 0, 1)
        rb._regionLabel = MINI_DISPLAY[mini] or mini
    end
    rb:Show()
end

local function UpdateRegion(card, d, accountInfo)
    local p = Settings()
    Kit.UpdateRegionButton(card, d, accountInfo.gameAccountInfo, card.PartyButton,
        not (p and p.showRegionIcons == false))
end

-------------------------------------------------------------------------------
--  Paint
-------------------------------------------------------------------------------
local function PaintCard(card)
    if not TILE_PAINT then return end
    if not Enabled() then return end

    local ed = card.elementData
    local accountInfo = ed and ed.accountInfo
    if not accountInfo then return end

    local d = SkinStructure(card)
    SuppressBlizzardArt(card)

    local charText = BuildCharLine(accountInfo)
    local hasChar  = charText ~= ""

    d.name:SetText(BuildName(accountInfo))
    d.charLine:SetText(charText)
    d.charLine:SetShown(hasChar)
    d.info:SetText(BuildInfo(accountInfo))

    -- Every string arrives pre-wrapped in Blizzard colour codes, so the
    -- FontStrings stay white or they would tint the markup.
    d.name:SetTextColor(1, 1, 1, 1)
    d.charLine:SetTextColor(1, 1, 1, 1)
    d.info:SetTextColor(1, 1, 1, 1)

    -- The location follows whichever line is above it, so a friend with no
    -- character does not leave a gap.
    d.info:ClearAllPoints()
    d.info:SetPoint("TOPLEFT", hasChar and d.charLine or d.name, "BOTTOMLEFT", 0, TILE_LINE_GAP)

    -- Centre the block vertically. Its height depends on the line count, so it
    -- is measured rather than assumed -- Blizzard's row is 70 and the block is
    -- far shorter, and a fixed offset would sit wrong on two-line rows.
    local rowH = card:GetHeight()
    if rowH and rowH > 0 then
        local gap   = -TILE_LINE_GAP
        local block = TILE_NAME_SIZE + gap + TILE_INFO_SIZE
        if hasChar then block = block + TILE_CHAR_SIZE + gap end
        d.name:ClearAllPoints()
        d.name:SetPoint("TOPLEFT", card, "TOPLEFT",
                        rowH + TILE_TEXT_GAP, -math.max(0, (rowH - block) / 2))
    end

    UpdateClassIcon(card, d, accountInfo)
    d.onlineBg:SetShown(accountInfo.gameAccountInfo ~= nil
                        and accountInfo.gameAccountInfo.isOnline == true)
    UpdateFaction(card, d, accountInfo)
    UpdateOrb(d, accountInfo)
    UpdateRegion(card, d, accountInfo)

    d.hoverBar:Hide()
    d.hoverFill:Hide()

    -- Blizzard calls SetSelected during its own Initialize, i.e. BEFORE this
    -- paint runs and before the structure above exists. The hook stashes the
    -- state in FFD; this applies it once the textures are there.
    local sel = d.selected == true
    d.selBar:SetShown(sel)
    d.selFill:SetShown(sel)
end

-------------------------------------------------------------------------------
--  Stock styles (Blizzard Style / Classic WoW UI): Blizzard's own card, laid
--  out and drawn by Blizzard, with the EllesmereUI additions in its native
--  slots only. No Blizzard region is moved or re-texted; the same write
--  classes as the tile path (our regions on the card, SetAlpha on Blizzard's
--  regions), so the decoration-only rule above still holds.
--    class icon  -> over Blizzard's 20px game-icon slot (same-project friends)
--    class name  -> our string over Blizzard's character name (Class Color Names)
--    region mark -> the free corner above the party button (Show Region Icons)
-------------------------------------------------------------------------------
local function DecorateStockCard(card)
    if not Enabled() then return end
    local ed = card.elementData
    local accountInfo = ed and ed.accountInfo
    if not accountInfo then return end

    local d = GetFFD(card)
    local p = Settings()
    local gi = accountInfo.gameAccountInfo
    local classFile
    if IsSameProjectOnline(gi) then
        classFile = (gi.classFilename ~= "" and gi.classFilename) or GetClassFile(accountInfo)
    end

    -- Class icon: a region of the holder, so it follows Blizzard's own show and
    -- hide of the slot (hidden for offline friends and while the RAF summon
    -- button takes the slot). Blizzard re-sets its Icon's alpha whenever it
    -- shows the holder, so the logo needs no restore when ours stands down.
    local holder = card.GameIconHolder
    if holder then
        local icon = d.stockClassIcon
        -- Only a class the icon theme has art for takes the slot; any other
        -- token (a special game-mode class) keeps Blizzard's own logo.
        local style = (p and p.iconStyle) or "modern"
        local hasArt = classFile and not (p and p.showClassIcons == false)
            and ((style == "blizzard" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile])
                or (style ~= "blizzard" and CLASS_SPRITE_COORDS[classFile]))
        if hasArt then
            if not icon then
                icon = holder:CreateTexture(nil, "OVERLAY")
                icon:SetAllPoints(holder)
                d.stockClassIcon = icon
            end
            if d.stockIconClass ~= classFile or d.stockIconStyle ~= style then
                d.stockIconClass, d.stockIconStyle = classFile, style
                SetClassIconTex(icon, style, classFile)
            end
            icon:Show()
            if holder.Icon then holder.Icon:SetAlpha(0); d.stockLogoOff = true end
        else
            if icon then icon:Hide() end
            -- A pooled card whose last friend wore our icon gets the logo back
            -- (Blizzard restores it only when it re-shows the holder).
            if d.stockLogoOff and holder.Icon then holder.Icon:SetAlpha(1) end
            d.stockLogoOff = nil
        end
    end

    -- Class-coloured character name: our string over Blizzard's (same font
    -- object and rect, so its truncation still holds). Blizzard never resets
    -- the name's alpha itself, so it is restored here whenever ours stands down.
    local name = card.Name
    if name then
        local ov = d.stockName
        local code = classFile and p and p.classColorNames and name:IsShown() and ClassColorCode(classFile)
        if code then
            if not ov then
                ov = card:CreateFontString(nil, "OVERLAY")
                local fo = name:GetFontObject()
                if fo then ov:SetFontObject(fo) else ov:SetFont(name:GetFont()) end
                ov:SetAllPoints(name)
                ov:SetJustifyH("LEFT")
                ov:SetJustifyV("MIDDLE")
                ov:SetWordWrap(false)
                d.stockName = ov
            end
            local charName = (FriendsListUtil and FriendsListUtil.GetFormattedCharacterName
                and FriendsListUtil.GetFormattedCharacterName(accountInfo)) or gi.characterName or ""
            ov:SetText(code .. charName .. "|r")
            ov:Show()
            name:SetAlpha(0)
            d.stockNameHidden = true
        else
            if ov then ov:Hide() end
            if d.stockNameHidden then
                name:SetAlpha(1)
                d.stockNameHidden = nil
            end
        end
    end

    UpdateStockRegion(card, d, accountInfo)
end

-------------------------------------------------------------------------------
--  Stock styles on the legacy friends window (FriendsFrame, the one Blizzard
--  shows while the Social UI is switched off server-side): the same three
--  additions on Blizzard's own rows, again in native slots, again decoration
--  only (our regions on the row, SetAlpha on Blizzard's).
--    class icon  -> over Blizzard's 24px game logo (same-project friends; an
--                   online character friend's logo slot is empty and takes it)
--    class name  -> our string over Blizzard's name, built from the same
--                   pieces Blizzard uses, the character part class-coloured
--    region mark -> under the status icon (Show Region Icons)
--  Runs from a post-hook on Blizzard's row update, after it has filled the
--  row. A row updated while the list is hidden (or skipped by an options pass
--  while hidden) is marked stale and caught up when the list shows.
-------------------------------------------------------------------------------
-- restore: an options-driven pass, where no Blizzard row update ran first to
-- put its logo alpha back.
local function DecorateStockRow(button, restore)
    local bt = button.buttonType
    local isBNet = bt ~= nil and bt == FRIENDS_BUTTON_TYPE_BNET
    local isWoW  = bt ~= nil and bt == FRIENDS_BUTTON_TYPE_WOW
    if not (isBNet or isWoW) or not button.id then return end
    local d = GetFFD(button)
    d.legacy = true
    if not button:IsVisible() then d.stale = true; return end
    d.stale = nil
    if not Enabled() then return end

    -- Every decoration off: stand down whatever is still painted and read no
    -- friend data at all.
    local p = Settings()
    if p and p.showClassIcons == false and not p.classColorNames and p.showRegionIcons == false then
        if d.stockClassIcon then d.stockClassIcon:Hide() end
        if d.stockLogoOff and restore and button.gameIcon then button.gameIcon:SetAlpha(1) end
        d.stockLogoOff = nil
        if d.stockName then d.stockName:Hide() end
        if d.stockNameHidden and button.name then button.name:SetAlpha(1) end
        d.stockNameHidden = nil
        if d.regionMark then d.regionMark:Hide() end
        return
    end

    local accountInfo, gi, info, classFile
    if isBNet then
        accountInfo = C_BattleNet.GetFriendAccountInfo(button.id)
        gi = accountInfo and accountInfo.gameAccountInfo
        if IsSameProjectOnline(gi) then
            classFile = (gi.classFilename ~= "" and gi.classFilename) or GetClassFile(accountInfo)
        end
    else
        info = C_FriendList.GetFriendInfoByIndex(button.id)
        if info and info.connected and info.className then
            classFile = EllesmereUI.ClassTokenFromLocalized(info.className)
        end
    end

    -- Class icon over the logo's rect. A Battle.net friend's slot is Blizzard's
    -- to show or hide (offline, or the summon button in it), so ours follows
    -- the logo's shown state; Blizzard re-sets the logo's alpha on every row
    -- update, so only an options pass has to give it back.
    local logo = button.gameIcon
    if logo then
        local icon = d.stockClassIcon
        local style = (p and p.iconStyle) or "modern"
        local hasArt = (isWoW or logo:IsShown()) and classFile
            and not (p and p.showClassIcons == false)
            and ((style == "blizzard" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile])
                or (style ~= "blizzard" and CLASS_SPRITE_COORDS[classFile]))
        if hasArt then
            if not icon then
                icon = button:CreateTexture(nil, "OVERLAY")
                icon:SetAllPoints(logo)
                d.stockClassIcon = icon
            end
            if d.stockIconClass ~= classFile or d.stockIconStyle ~= style then
                d.stockIconClass, d.stockIconStyle = classFile, style
                SetClassIconTex(icon, style, classFile)
            end
            icon:Show()
            if isBNet then logo:SetAlpha(0); d.stockLogoOff = true end
        else
            if icon then icon:Hide() end
            if d.stockLogoOff and restore then logo:SetAlpha(1) end
            d.stockLogoOff = nil
        end
    end

    -- Class-coloured name: our string over Blizzard's (same font object and
    -- rect, Blizzard's own colour as the base), so the favourite star Blizzard
    -- anchors at the end of its name still lines up. Blizzard never resets
    -- the name's alpha itself, so it is restored whenever ours stands down.
    -- A friend Blizzard greys out as unable to group keeps its grey.
    local name = button.name
    if name then
        local code = classFile and p and p.classColorNames and ClassColorCode(classFile)
        if code and isBNet and CanCooperateWithGameAccount
            and not CanCooperateWithGameAccount(accountInfo) then
            code = nil
        end
        local text
        if code and isBNet then
            local acct = FriendsFrame_GetBNetAccountNameAndStatus
                and FriendsFrame_GetBNetAccountNameAndStatus(accountInfo, true)
            local char = gi.characterName
            if char and char ~= "" and FriendsFrame_GetFormattedCharacterName then
                char = FriendsFrame_GetFormattedCharacterName(char, nil, gi.clientProgram, gi.timerunningSeasonID)
            end
            if acct and char and char ~= "" then
                text = acct .. " " .. code .. "(" .. char .. ")|r"
            end
        elseif code and info and info.name and info.level and FRIENDS_LEVEL_TEMPLATE then
            text = code .. info.name .. "|r, " .. format(FRIENDS_LEVEL_TEMPLATE, info.level, info.className)
        end
        local ov = d.stockName
        if text then
            if not ov then
                ov = button:CreateFontString(nil, "OVERLAY")
                local fo = name:GetFontObject()
                if fo then ov:SetFontObject(fo) else ov:SetFont(name:GetFont()) end
                ov:SetAllPoints(name)
                ov:SetJustifyH(name:GetJustifyH())
                ov:SetJustifyV(name:GetJustifyV())
                ov:SetWordWrap(name:CanWordWrap())
                d.stockName = ov
            end
            -- Colour only: a region's alpha and its colour alpha are one
            -- channel on this client, and Blizzard's name sits at our alpha 0
            -- from the last pass (its 3-arg SetTextColor keeps it), so a full
            -- copy would hand ours alpha 0 from the second update on.
            local r, g, b = name:GetTextColor()
            ov:SetTextColor(r, g, b, 1)
            ov:SetText(text)
            ov:Show()
            name:SetAlpha(0)
            d.stockNameHidden = true
        else
            if ov then ov:Hide() end
            if d.stockNameHidden then
                name:SetAlpha(1)
                d.stockNameHidden = nil
            end
        end
    end

    UpdateStockRegion(button, d, accountInfo)
end

-- The list shows: catch up the rows Blizzard updated, or an options pass
-- skipped, while it was hidden (the latter with that pass's logo restore).
local function CatchUpStaleRows()
    for frame, d in pairs(FFD) do
        if d.stale then
            local restore = d.staleRestore
            d.staleRestore = nil
            DecorateStockRow(frame, restore)
        end
    end
end

-------------------------------------------------------------------------------
--  Hook
--
--  Post-hook on the card mixin, installed by the host's StartTiles at
--  PLAYER_LOGIN -- before the friends list is first shown and therefore before
--  any card frame exists, so every pooled card copies the hooked Initialize
--  when Mixin() runs at creation.
--
--  This is the ONLY contact point with Blizzard's list (under the stock
--  styles, plus the same kind of post-hook on the legacy window's row update
--  and that list's OnShow). We do not touch the ScrollBox, the provider, or
--  any element data.
-------------------------------------------------------------------------------
-- The decorator the Initialize hook runs this session, chosen once from the
-- style latch (pooled cards therefore never mix treatments).
local activeDecorator

-- Starts the tiles for the session, once, from the host's PLAYER_LOGIN.
-- h.Settings: returns the settings table (enabled, showClassIcons, iconStyle,
-- classColorNames, factionBanners, showRegionIcons); h.style: "eui" paints
-- the EllesmereUI tiles, any other look only decorates Blizzard's cards;
-- h.fontKey: the font the tiles take.
function Kit.StartTiles(h)
    if host then return end
    -- WoW Forever's Gamepad interface style navigates Blizzard's windows from
    -- secure code, and the tile hover hooks are script hooks on Blizzard's
    -- cards, so the tiles stand down for the session under it.
    if EllesmereUI.PadGamepadUI() then return end
    host = h
    if h.style ~= "eui" then
        -- Stock styles decorate whichever window Blizzard shows (the switch
        -- is server-side and can flip mid-session). Blizzard keeps its own
        -- selection highlight, so the SetSelected hook below is not needed.
        activeDecorator = DecorateStockCard
        if FriendsListSocialCardMixin then
            hooksecurefunc(FriendsListSocialCardMixin, "Initialize", function(card)
                DecorateStockCard(card)
            end)
        end
        if FriendsFrame_UpdateFriendButton then
            hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button)
                -- Blizzard has just re-set its logo alpha itself.
                local d = FFD[button]
                if d then d.staleRestore = nil end
                DecorateStockRow(button)
            end)
            if FriendsListFrame then
                FriendsListFrame:HookScript("OnShow", CatchUpStaleRows)
            end
        end
        return
    end
    if not FriendsListSocialCardMixin then return end
    activeDecorator = PaintCard
    hooksecurefunc(FriendsListSocialCardMixin, "Initialize", function(card)
        PaintCard(card)
    end)

    -- Selection state comes from Blizzard's own selection behaviour, which
    -- routes through SetSelected on the card. Post-hooking it means we never
    -- read the provider or the selection behaviour ourselves.
    hooksecurefunc(FriendsListSocialCardMixin, "SetSelected", function(card, selected)
        local d = GetFFD(card)
        d.selected = selected and true or false
        if d.selBar then
            d.selBar:SetShown(d.selected)
            d.selFill:SetShown(d.selected)
        end
    end)
end

-- Options-driven repaint that never goes through Blizzard's view: re-run this
-- session's decorator on every card or legacy row we have decorated that is on
-- screen now, from the data Blizzard already gave it. (view:Refresh
-- regenerates the data provider from our execution -- the whisper-taint class
-- above.)
function Kit.RedecorateTiles()
    local fn = activeDecorator
    if not fn then return end
    for frame, d in pairs(FFD) do
        if d.legacy then
            -- A row kept shown under a hidden list (another Friends sub-tab)
            -- is caught up when the list shows; a released row is
            -- re-initialised by Blizzard when the pool reuses it.
            if frame:IsVisible() then
                DecorateStockRow(frame, true)
            elseif frame:IsShown() then
                d.stale, d.staleRestore = true, true
            end
        elseif frame.IsVisible and frame:IsVisible() and frame.elementData then
            fn(frame)
        end
    end
end

-------------------------------------------------------------------------------
--  Auto-accept group invites from friends (and guildmates, when the host's
--  settings say so). Independent of the friends window and its look: an
--  invite is answered whichever window Blizzard shows. PARTY_INVITE_REQUEST
--  is registered only while the toggle is on; GROUP_ROSTER_UPDATE only
--  between an accept and its popup cleanup.
-------------------------------------------------------------------------------
local autoAcceptFrame, autoAcceptSettings
local autoAcceptHidePopup = false

local function AutoAcceptOnEvent(self, event, _, _, _, _, _, _, inviterGUID)
    if event == "PARTY_INVITE_REQUEST" then
        local fp = autoAcceptSettings and autoAcceptSettings()
        if not fp or fp.enabled == false or not fp.autoAcceptFriendInvites then return end
        if not inviterGUID or inviterGUID == "" or IsInGroup() then return end
        local isFriend = false
        if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
            isFriend = C_BattleNet.GetGameAccountInfoByGUID(inviterGUID) ~= nil
        end
        if not isFriend and C_FriendList and C_FriendList.IsFriend then
            isFriend = C_FriendList.IsFriend(inviterGUID)
        end
        if not isFriend and fp.autoAcceptGuildInvites then
            isFriend = IsGuildMember(inviterGUID)
        end
        if isFriend then
            AcceptGroup()
            -- WoW Forever's Gamepad interface style runs Blizzard's popups from
            -- secure code: its invite popup is left to it there.
            if not EllesmereUI.PadGamepadUI() then
                autoAcceptHidePopup = true
                self:RegisterEvent("GROUP_ROSTER_UPDATE")
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" and autoAcceptHidePopup then
        autoAcceptHidePopup = false
        self:UnregisterEvent("GROUP_ROSTER_UPDATE")
        StaticPopup_Hide("PARTY_INVITE")
        if LFGInvitePopup then
            StaticPopupSpecial_Hide(LFGInvitePopup)
        end
    end
end

-- settings: the host's function returning its settings table (enabled,
-- autoAcceptFriendInvites, autoAcceptGuildInvites). Call it at the host's
-- load and after every change to those keys. The frame is made the first
-- time the toggle is on.
function Kit.SyncAutoAccept(settings)
    autoAcceptSettings = settings
    local fp = settings and settings()
    local on = fp and fp.enabled ~= false and fp.autoAcceptFriendInvites
    if on and not autoAcceptFrame then
        autoAcceptFrame = CreateFrame("Frame")
        autoAcceptFrame:SetScript("OnEvent", AutoAcceptOnEvent)
    end
    if not autoAcceptFrame then return end
    if on then
        autoAcceptFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    else
        autoAcceptFrame:UnregisterEvent("PARTY_INVITE_REQUEST")
    end
end
