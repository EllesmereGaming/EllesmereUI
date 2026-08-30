local addon = EllesmereUIDamageMeter
local S = addon and addon.S
if not S then return end

local TEST_DAMAGE = {
    { name = "Deathknight",   value = 980000, class = "DEATHKNIGHT",
      spells = {{49020, 340000}, {49143, 280000}, {49184, 195000}, {196770, 110000}, {6603, 55000}} },
    { name = "Demonhunter",   value = 920000, class = "DEMONHUNTER",
      spells = {{198013, 310000}, {188499, 260000}, {162794, 200000}, {258920, 100000}, {6603, 50000}} },
    { name = "Warrior",       value = 860000, class = "WARRIOR",
      spells = {{12294, 290000}, {163201, 240000}, {7384, 180000}, {262115, 100000}, {6603, 50000}} },
    { name = "Mage",          value = 800000, class = "MAGE",
      spells = {{11366, 280000}, {108853, 220000}, {133, 170000}, {12654, 90000}, {257541, 40000}} },
    { name = "Hunter",        value = 740000, class = "HUNTER",
      spells = {{19434, 260000}, {257044, 200000}, {185358, 150000}, {75, 90000}, {53351, 40000}} },
    { name = "Rogue",         value = 680000, class = "ROGUE",
      spells = {{196819, 240000}, {1752, 190000}, {315341, 140000}, {13877, 75000}, {6603, 35000}} },
    { name = "Warlock",       value = 620000, class = "WARLOCK",
      spells = {{116858, 220000}, {29722, 170000}, {348, 120000}, {5740, 70000}, {17962, 40000}} },
    { name = "Evoker",        value = 560000, class = "EVOKER",
      spells = {{357208, 200000}, {356995, 160000}, {361469, 110000}, {357211, 60000}, {362969, 30000}} },
    { name = "Shaman",        value = 500000, class = "SHAMAN",
      spells = {{188196, 180000}, {51505, 140000}, {188443, 100000}, {188389, 55000}, {8042, 25000}} },
    { name = "Paladin",       value = 440000, class = "PALADIN",
      spells = {{85256, 160000}, {184575, 120000}, {255937, 90000}, {26573, 45000}, {6603, 25000}} },
    { name = "Monk",          value = 380000, class = "MONK",
      spells = {{107428, 140000}, {100784, 105000}, {113656, 80000}, {100780, 35000}, {101546, 20000}} },
    { name = "Druid",         value = 320000, class = "DRUID",
      spells = {{78674, 120000}, {194153, 90000}, {190984, 60000}, {93402, 35000}, {8921, 15000}} },
    { name = "Priest",        value = 260000, class = "PRIEST",
      spells = {{8092, 100000}, {32379, 70000}, {34914, 45000}, {589, 30000}, {15407, 15000}} },
    { name = "Deathknight2",  value = 210000, class = "DEATHKNIGHT",
      spells = {{49020, 80000}, {49143, 60000}, {49184, 40000}, {6603, 30000}} },
    { name = "Mage2",         value = 170000, class = "MAGE",
      spells = {{11366, 65000}, {133, 50000}, {108853, 35000}, {12654, 20000}} },
    { name = "Hunter2",       value = 135000, class = "HUNTER",
      spells = {{19434, 55000}, {257044, 40000}, {185358, 25000}, {75, 15000}} },
    { name = "Warrior2",      value = 105000, class = "WARRIOR",
      spells = {{12294, 45000}, {163201, 30000}, {7384, 20000}, {6603, 10000}} },
    { name = "Rogue2",        value = 80000,  class = "ROGUE",
      spells = {{196819, 35000}, {1752, 25000}, {6603, 20000}} },
    { name = "Shaman2",       value = 58000,  class = "SHAMAN",
      spells = {{188196, 25000}, {51505, 18000}, {188389, 15000}} },
    { name = "Paladin2",      value = 40000,  class = "PALADIN",
      spells = {{85256, 18000}, {184575, 12000}, {6603, 10000}} },
}

local TEST_HEALING = {
    { name = "Priest",    value = 1250000, class = "PRIEST",
      spells = {{2061, 420000}, {34861, 310000}, {596, 240000}, {139, 180000}, {47788, 100000}} },
    { name = "Druid",     value = 1100000, class = "DRUID",
      spells = {{774, 380000}, {48438, 290000}, {8936, 210000}, {33763, 140000}, {145205, 80000}} },
    { name = "Paladin",   value = 980000,  class = "PALADIN",
      spells = {{19750, 340000}, {82326, 260000}, {20473, 190000}, {85222, 120000}, {53563, 70000}} },
    { name = "Shaman",    value = 870000,  class = "SHAMAN",
      spells = {{77472, 300000}, {1064, 230000}, {61295, 170000}, {73920, 110000}, {5394, 60000}} },
    { name = "Monk",      value = 760000,  class = "MONK",
      spells = {{115175, 260000}, {191837, 200000}, {116670, 150000}, {124682, 100000}, {115310, 50000}} },
    { name = "Evoker",    value = 650000,  class = "EVOKER",
      spells = {{355916, 230000}, {364343, 170000}, {361469, 120000}, {382614, 80000}, {355913, 50000}} },
    { name = "Priest2",   value = 540000,  class = "PRIEST",
      spells = {{2061, 200000}, {34861, 150000}, {596, 100000}, {139, 90000}} },
    { name = "Druid2",    value = 430000,  class = "DRUID",
      spells = {{774, 160000}, {48438, 120000}, {8936, 90000}, {33763, 60000}} },
    { name = "Paladin2",  value = 320000,  class = "PALADIN",
      spells = {{19750, 130000}, {82326, 100000}, {20473, 90000}} },
    { name = "Shaman2",   value = 210000,  class = "SHAMAN",
      spells = {{77472, 90000}, {1064, 60000}, {61295, 60000}} },
}

local TEST_INTERRUPTS = {
    { name = "Rogue",       value = 8, class = "ROGUE",   spells = {{1766, 8}} },
    { name = "Shaman",      value = 7, class = "SHAMAN",  spells = {{57994, 7}} },
    { name = "Deathknight", value = 6, class = "DEATHKNIGHT", spells = {{47528, 6}} },
    { name = "Mage",        value = 5, class = "MAGE",    spells = {{2139, 5}} },
    { name = "Demonhunter", value = 5, class = "DEMONHUNTER", spells = {{183752, 5}} },
    { name = "Warrior",     value = 4, class = "WARRIOR", spells = {{6552, 4}} },
    { name = "Hunter",      value = 3, class = "HUNTER",  spells = {{147362, 3}} },
    { name = "Monk",        value = 3, class = "MONK",    spells = {{116705, 3}} },
    { name = "Paladin",     value = 2, class = "PALADIN", spells = {{96231, 2}} },
    { name = "Warlock",     value = 2, class = "WARLOCK", spells = {{119910, 2}} },
    { name = "Evoker",      value = 1, class = "EVOKER",  spells = {{351338, 1}} },
    { name = "Druid",       value = 1, class = "DRUID",   spells = {{106839, 1}} },
    { name = "Priest",      value = 0, class = "PRIEST",  spells = {} },
}

local TEST_DISPELS = {
    { name = "Priest",    value = 12, class = "PRIEST",  spells = {{527, 8}, {32375, 4}} },
    { name = "Paladin",   value = 9, class = "PALADIN", spells = {{4987, 9}} },
    { name = "Shaman",    value = 7, class = "SHAMAN",  spells = {{51886, 7}} },
    { name = "Druid",     value = 6, class = "DRUID",   spells = {{2782, 6}} },
    { name = "Monk",      value = 5, class = "MONK",    spells = {{115450, 5}} },
    { name = "Evoker",    value = 4, class = "EVOKER",  spells = {{365585, 4}} },
    { name = "Mage",      value = 3, class = "MAGE",    spells = {{475, 3}} },
    { name = "Warlock",   value = 2, class = "WARLOCK", spells = {{89808, 2}} },
    { name = "Hunter",    value = 1, class = "HUNTER",  spells = {{19801, 1}} },
}

local TEST_DEATHS = {
    { name = "Rogue",       value = 4, class = "ROGUE", spells = {} },
    { name = "Mage",        value = 3, class = "MAGE", spells = {} },
    { name = "Hunter",      value = 3, class = "HUNTER", spells = {} },
    { name = "Warlock",     value = 2, class = "WARLOCK", spells = {} },
    { name = "Priest",      value = 2, class = "PRIEST", spells = {} },
    { name = "Demonhunter", value = 1, class = "DEMONHUNTER", spells = {} },
    { name = "Warrior",     value = 1, class = "WARRIOR", spells = {} },
    { name = "Evoker",      value = 1, class = "EVOKER", spells = {} },
    { name = "Deathknight", value = 0, class = "DEATHKNIGHT", spells = {} },
    { name = "Paladin",     value = 0, class = "PALADIN", spells = {} },
    { name = "Shaman",      value = 0, class = "SHAMAN", spells = {} },
    { name = "Monk",        value = 0, class = "MONK", spells = {} },
    { name = "Druid",       value = 0, class = "DRUID", spells = {} },
}

function S.GetTestData(win)
    local modeEntry = S.MODE_ORDER[win.modeIndex]
    if modeEntry == Enum.DamageMeterType.HealingDone
    or modeEntry == Enum.DamageMeterType.Hps
    or modeEntry == S.COMBINED_HEALING
    or modeEntry == Enum.DamageMeterType.Absorbs then
        return TEST_HEALING
    elseif modeEntry == Enum.DamageMeterType.Interrupts then
        return TEST_INTERRUPTS
    elseif modeEntry == Enum.DamageMeterType.Dispels then
        return TEST_DISPELS
    elseif Enum.DamageMeterType.Deaths and modeEntry == Enum.DamageMeterType.Deaths then
        return TEST_DEATHS
    end
    return TEST_DAMAGE
end
