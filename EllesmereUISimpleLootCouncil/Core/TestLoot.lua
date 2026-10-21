if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end







SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local TestLoot = {}
addon.TestLoot = TestLoot



local function Link(id, name)
    return ("|cnIQ4:|Hitem:%d::::::::80:::::::|h[%s]|h|r"):format(id, name)
end

local POOL = {

    Link(18816, "Perdition's Blade"),
    Link(18832, "Brutality Blade"),
    Link(17076, "Bonereaver's Edge"),
    Link(17104, "Spinal Reaper"),
    Link(17073, "Earthshaker"),
    Link(17105, "Aurastone Hammer"),
    Link(17069, "Striker's Mark"),
    Link(17072, "Blastershot Launcher"),
    Link(17066, "Drillborer Disk"),
    Link(18814, "Choker of the Fire Lord"),
    Link(18821, "Quick Strike Ring"),
    Link(16795, "Arcanist Crown"),
    Link(16802, "Arcanist Belt"),
    Link(16807, "Felheart Shoulder Pads"),
    Link(16810, "Felheart Pants"),
    Link(16821, "Nightslayer Cover"),
    Link(16826, "Nightslayer Gloves"),
    Link(16830, "Cenarion Bracers"),
    Link(16835, "Cenarion Leggings"),
    Link(16846, "Giantstalker's Helmet"),
    Link(16839, "Earthfury Gauntlets"),
    Link(16844, "Earthfury Epaulets"),
    Link(16866, "Helm of Might"),
    Link(16865, "Breastplate of Might"),
    Link(16856, "Lawbringer Spaulders"),
    Link(16860, "Lawbringer Gauntlets"),


    Link(19363, "Crul'shorukh, Edge of Chaos"),
    Link(19364, "Ashkandi, Greatsword of the Brotherhood"),
    Link(19351, "Maladath, Runed Blade of the Black Flight"),
    Link(19353, "Drake Talon Cleaver"),
    Link(19360, "Lok'amir il Romathis"),
    Link(19356, "Staff of the Shadow Flame"),
    Link(19361, "Ashjre'thul, Crossbow of Smiting"),
    Link(19349, "Elementium Reinforced Bulwark"),
    Link(19436, "Cloak of Draconic Might"),
    Link(19406, "Drake Fang Talisman"),
    Link(16916, "Netherwind Robes"),
    Link(16919, "Boots of Transcendence"),
    Link(16902, "Stormrage Pauldrons"),
    Link(16906, "Bloodfang Boots"),
    Link(16938, "Dragonstalker's Legguards"),
    Link(16943, "Bracers of Ten Storms"),
    Link(16949, "Greaves of Ten Storms"),
    Link(16954, "Judgment Legplates"),


    Link(22802, "Kingsfall"),
    Link(23577, "The Hungering Cold"),
    Link(22798, "Might of Menethil"),
    Link(22816, "Hatchet of Sundered Bone"),
    Link(23039, "The Eye of Nerub"),
    Link(22820, "Wand of Fates"),
    Link(22960, "Cloak of Suturing"),
    Link(23001, "Eye of Diminution"),
    Link(22512, "Robe of Faith"),
    Link(22501, "Frostfire Gloves"),
    Link(22476, "Bonescythe Breastplate"),
    Link(22482, "Bonescythe Waistguard"),
    Link(22464, "Earthshatter Tunic"),
    Link(22470, "Earthshatter Girdle"),
    Link(22428, "Redemption Headpiece"),
    Link(22420, "Dreadnaught Sabatons"),
}




local function Dungeon(id, name, quality, boss)
    return { link = ("|cnIQ%d:|Hitem:%d::::::::60:::::::|h[%s]|h|r"):format(quality, id, name),
        boss = boss }
end

local DUNGEON_POOL = {

    Dungeon(5194, "Taskmaster Axe", 3, "Sneed"),
    Dungeon(1156, "Lavishly Jeweled Ring", 3, "Gilnid"),
    Dungeon(7230, "Smite's Mighty Hammer", 3, "Mr. Smite"),
    Dungeon(5201, "Emberstone Staff", 3, "Captain Greenskin"),
    Dungeon(5193, "Cape of the Brotherhood", 3, "Edwin VanCleef"),
    Dungeon(5202, "Corsair's Overshirt", 3, "Edwin VanCleef"),
    Dungeon(10399, "Blackened Defias Armor", 3, "Edwin VanCleef"),
    Dungeon(5191, "Cruel Barb", 3, "Edwin VanCleef"),
    Dungeon(5198, "Cookie's Stirring Rod", 3, "Cookie"),


    Dungeon(6460, "Cobrahn's Grasp", 3, "Lord Cobrahn"),
    Dungeon(10410, "Leggings of the Fang", 3, "Lord Cobrahn"),
    Dungeon(13245, "Kresh's Back", 3, "Kresh"),
    Dungeon(6472, "Stinging Viper", 3, "Lord Pythas"),
    Dungeon(6449, "Glowing Lizardscale Cloak", 3, "Skum"),
    Dungeon(6469, "Venomstrike", 3, "Lord Serpentis"),
    Dungeon(6630, "Seedcloud Buckler", 3, "Verdan the Everliving"),
    Dungeon(6631, "Living Root", 3, "Verdan the Everliving"),
    Dungeon(6461, "Slime-encrusted Pads", 3, "Mutanus the Devourer"),
    Dungeon(6627, "Mutant Scale Breastplate", 3, "Mutanus the Devourer"),
    Dungeon(6463, "Deep Fathom Ring", 3, "Mutanus the Devourer"),


    Dungeon(1292, "Butcher's Cleaver", 3, "Razorclaw the Butcher"),
    Dungeon(6321, "Silverlaine's Family Seal", 3, "Baron Silverlaine"),
    Dungeon(6320, "Commander's Crest", 3, "Commander Springvale"),
    Dungeon(6318, "Odo's Ley Staff", 3, "Odo the Blindwatcher"),
    Dungeon(3748, "Feline Mantle", 3, "Wolf Master Nandos"),
    Dungeon(6324, "Robes of Arugal", 3, "Archmage Arugal"),
    Dungeon(6392, "Belt of Arugal", 3, "Archmage Arugal"),
    Dungeon(6220, "Meteor Shard", 3, "Archmage Arugal"),


    Dungeon(6907, "Tortoise Armor", 3, "Ghamoo-ra"),
    Dungeon(888, "Naga Battle Gloves", 3, "Lady Sarevess"),
    Dungeon(6906, "Algae Fists", 3, "Gelihast"),
    Dungeon(1155, "Rod of the Sleepwalker", 3, "Twilight Lord Kelris"),
    Dungeon(6901, "Glowing Thresher Cape", 3, "Old Serra'kis"),
    Dungeon(6904, "Bite of Serra'kis", 3, "Old Serra'kis"),
    Dungeon(6911, "Moss Cinch", 3, "Aku'mai"),
    Dungeon(6910, "Leech Pants", 3, "Aku'mai"),
    Dungeon(6909, "Strike of the Hydra", 3, "Aku'mai"),


    Dungeon(2816, "Death Speaker Scepter", 3, "Death Speaker Jargba"),
    Dungeon(6687, "Corpsemaker", 3, "Overlord Ramtusk"),
    Dungeon(6691, "Swinetusk Shank", 3, "Agathelos the Raging"),
    Dungeon(6693, "Agamaggan's Clutch", 3, "Charlga Razorflank"),
    Dungeon(6694, "Heart of Agamaggan", 3, "Charlga Razorflank"),
    Dungeon(6692, "Pronged Reaver", 3, "Charlga Razorflank"),


    Dungeon(7682, "Torturing Poker", 3, "Interrogator Vishas"),
    Dungeon(7685, "Orb of the Forgotten Seer", 3, "Bloodmage Thalnos"),
    Dungeon(7710, "Loksey's Training Stick", 3, "Houndmaster Loksey"),
    Dungeon(7714, "Hypnotic Blade", 3, "Arcanist Doan"),
    Dungeon(7713, "Illusionary Rod", 3, "Arcanist Doan"),
    Dungeon(7719, "Raging Berserker's Helm", 3, "Herod"),
    Dungeon(7718, "Herod's Shoulder", 3, "Herod"),
    Dungeon(10330, "Scarlet Leggings", 3, "Herod"),
    Dungeon(7717, "Ravager", 3, "Herod"),
    Dungeon(7724, "Gauntlets of Divinity", 3, "Scarlet Commander Mograine"),
    Dungeon(7726, "Aegis of the Scarlet Commander", 3, "Scarlet Commander Mograine"),
    Dungeon(7723, "Mograine's Might", 3, "Scarlet Commander Mograine"),
    Dungeon(7720, "Whitemane's Chapeau", 3, "High Inquisitor Whitemane"),
    Dungeon(7722, "Triune Amulet", 3, "High Inquisitor Whitemane"),
    Dungeon(7721, "Hand of Righteousness", 3, "High Inquisitor Whitemane"),
}


TestLoot.MAX = 12


function TestLoot:Count()
    return addon.IsForever and #DUNGEON_POOL or #POOL
end


function TestLoot:Pick(count)
    count = math.max(1, math.min(count or 1, #POOL))

    local shuffled = {}
    for i = 1, #POOL do shuffled[i] = POOL[i] end

    local picked = {}
    for i = 1, count do
        local j = math.random(i, #shuffled)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
        picked[i] = shuffled[i]
    end
    return picked
end

function TestLoot:DungeonCount()
    return #DUNGEON_POOL
end


function TestLoot:PickDungeon(count)
    count = math.max(1, math.min(count or 1, #DUNGEON_POOL))

    local shuffled = {}
    for i = 1, #DUNGEON_POOL do shuffled[i] = DUNGEON_POOL[i] end

    local links, sources = {}, {}
    for i = 1, count do
        local j = math.random(i, #shuffled)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
        links[i], sources[i] = shuffled[i].link, { boss = shuffled[i].boss }
    end
    return links, sources
end
