if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_BuffPresets.lua
--  THE single curation source for the 10 buff filter presets (Defensives,
--  Raid CDs, Externals, Core/Lesser Healing Buffs, Support, Offensive CDs,
--  Movement, Utility, Consumables). Two consumers, two shapes:
--    * Raid Frames Buff Manager v2 binds filters/spells directly (primary
--      ids are checkbox rows; alts ride include maps behind their primary).
--    * Player Aura Bars derives its filter seed + class hints at load,
--      flattening alts into their own rows (PAB has no primary/alt tiers).
--  Also the WoW Forever buff families (EllesmereUI.FOREVER_BUFF_FAMILIES, at
--  the end): every spell that gives each group buff there.
--  ADD OR EDIT CURATED IDS HERE ONLY -- never in the consumer files.
--------------------------------------------------------------------------------

-- WoW Forever: the vanilla catalogue, in the same shape as the retail one
-- below. Primary = rank 1; alts = every higher rank plus any separate aura
-- id the buff lands under: the include maps match exact aura spell ids, so
-- every learnable rank must be listed. Where the retail catalogue also
-- curates rank 1 under the preset (unchecked there), rank 2 is the primary
-- and rank 1 an alt, so the two clients never share one stored checkbox
-- with different defaults. Active Mitigation, Lesser Healing Buffs and
-- Support are not offered on this client.
-- Both catalogues are built on every client: the running client's one
-- becomes EllesmereUI.BUFF_PRESETS; the other one only feeds the cross-client
-- id sets and preset list at the end of this file.
local function ForeverCatalogue()
    return {
        filters = {
            { key = "defensives",  name = "Defensives" },
            { key = "raidcds",     name = "Raid CDs" },
            { key = "externals",   name = "Externals" },
            { key = "coreheals",   name = "Core Healing Buffs" },
            { key = "offensive",   name = "Offensive CDs" },
            { key = "movement",    name = "Movement" },
            { key = "utility",     name = "Utility" },
            { key = "consumables", name = "Consumables" },
        },
        spells = {
            defensives = {
                [22812] = { class = "DRUID" },  -- Barkskin
                [22842] = { class = "DRUID", alts = { 22845 } },  -- Frenzied Regeneration
                [11958] = { class = "MAGE" },  -- Ice Block
                -- Ice Barrier (rank 2 primary: retail curates rank 1 unchecked)
                [13031] = { class = "MAGE", alts = { 11426, 13032, 13033 } },
                [1463] = { class = "MAGE", alts = { 8494, 8495, 10191, 10192, 10193 } },  -- Mana Shield
                [642] = { class = "PALADIN", alts = { 1020 } },  -- Divine Shield
                [498] = { class = "PALADIN", alts = { 5573 } },  -- Divine Protection
                [586] = { class = "PRIEST", alts = { 9578, 9579, 9592, 10941, 10942 } },  -- Fade
                [27827] = { class = "PRIEST" },  -- Spirit of Redemption
                [5277] = { class = "ROGUE" },  -- Evasion
                -- Vanish (the buff lands as 11327 / 11329)
                [1856] = { class = "ROGUE", alts = { 1857, 11327, 11329 } },
                [871] = { class = "WARRIOR" },  -- Shield Wall
                [12975] = { class = "WARRIOR", alts = { 12976 } },  -- Last Stand
                [20230] = { class = "WARRIOR" },  -- Retaliation
                [19263] = { class = "HUNTER" },  -- Deterrence
                [6229] = { class = "WARLOCK", alts = { 11739, 11740, 28610 } },  -- Shadow Ward
            },
            raidcds = {
                -- Tranquility (rank 2 primary: retail curates rank 1 unchecked)
                [8918] = { class = "DRUID", alts = { 740, 9862, 9863 } },
            },
            externals = {
                [1022] = { class = "PALADIN", alts = { 5599, 10278 } },  -- Blessing of Protection
                [6940] = { class = "PALADIN", alts = { 20729 } },  -- Blessing of Sacrifice
                [10060] = { class = "PRIEST" },  -- Power Infusion
                [6346] = { class = "PRIEST" },  -- Fear Ward
                [29166] = { class = "DRUID" },  -- Innervate
            },
            coreheals = {
                -- Renew (rank 2 primary: retail curates rank 1 unchecked)
                [6074] = { class = "PRIEST", alts = { 139, 6075, 6076, 6077, 6078, 10927,
                    10928, 10929, 25315 } },
                -- Power Word: Shield (rank 2 primary: retail curates rank 1 unchecked)
                [592] = { class = "PRIEST", alts = { 17, 600, 3747, 6065, 6066, 10898, 10899,
                    10900, 10901 } },
                -- Rejuvenation (rank 2 primary: retail curates rank 1 unchecked)
                [1058] = { class = "DRUID", alts = { 774, 1430, 2090, 2091, 3627, 8910, 9839,
                    9840, 9841, 25299 } },
                -- Regrowth (rank 2 primary: retail curates rank 1 unchecked)
                [8938] = { class = "DRUID", alts = { 8936, 8939, 8940, 8941, 9750, 9856, 9857,
                    9858 } },
            },
            offensive = {
                [1719] = { class = "WARRIOR" },  -- Recklessness
                [12328] = { class = "WARRIOR" },  -- Death Wish
                [12292] = { class = "WARRIOR" },  -- Sweeping Strikes
                [18499] = { class = "WARRIOR" },  -- Berserker Rage
                [13750] = { class = "ROGUE" },  -- Adrenaline Rush
                [13877] = { class = "ROGUE" },  -- Blade Flurry
                [14177] = { class = "ROGUE" },  -- Cold Blood
                [12042] = { class = "MAGE" },  -- Arcane Power
                [11129] = { class = "MAGE" },  -- Combustion
                [12043] = { class = "MAGE" },  -- Presence of Mind
                [3045] = { class = "HUNTER" },  -- Rapid Fire
                [19574] = { class = "HUNTER" },  -- Bestial Wrath
                [10060] = { class = "PRIEST" },  -- Power Infusion
                [14751] = { class = "PRIEST" },  -- Inner Focus
                [16188] = { class = "SHAMAN" },  -- Nature's Swiftness
                [17116] = { class = "DRUID" },  -- Nature's Swiftness
                [5217] = { class = "DRUID" },  -- Tiger's Fury
                [20216] = { class = "PALADIN" },  -- Divine Favor
            },
            movement = {
                [1850] = { class = "DRUID", alts = { 9821 } },  -- Dash
                [783] = { class = "DRUID" },  -- Travel Form
                [5215] = { class = "DRUID", alts = { 6783, 9913 } },  -- Prowl
                [2983] = { class = "ROGUE", alts = { 8696, 11305 } },  -- Sprint
                [1784] = { class = "ROGUE", alts = { 1785, 1786, 1787 } },  -- Stealth
                [5118] = { class = "HUNTER" },  -- Aspect of the Cheetah
                [13159] = { class = "HUNTER" },  -- Aspect of the Pack
                [5384] = { class = "HUNTER" },  -- Feign Death
                [130] = { class = "MAGE" },  -- Slow Fall
                [1044] = { class = "PALADIN" },  -- Blessing of Freedom
                [2645] = { class = "SHAMAN" },  -- Ghost Wolf
                [1706] = { class = "PRIEST" },  -- Levitate
            },
            utility = {
                [29166] = { class = "DRUID" },  -- Innervate
                [1044] = { class = "PALADIN" },  -- Blessing of Freedom
                [546] = { class = "SHAMAN" },  -- Water Walking
                [131] = { class = "SHAMAN" },  -- Water Breathing
                [5697] = { class = "WARLOCK" },  -- Unending Breath
                [1008] = { class = "MAGE", alts = { 8455, 10169, 10170 } },  -- Amplify Magic
                [604] = { class = "MAGE", alts = { 8450, 8451, 10173, 10174 } },  -- Dampen Magic
            },
            -- Aura spell ids of the vanilla flasks, elixirs and potions. Flasks,
            -- protection potions, Free Action and Limited Invulnerability are
            -- checked by default; the rest start unchecked.
            consumables = {
                [17626] = { class = "ALL" },  -- Flask of the Titans
                [17628] = { class = "ALL" },  -- Flask of Supreme Power
                [17627] = { class = "ALL" },  -- Flask of Distilled Wisdom
                [17629] = { class = "ALL" },  -- Flask of Chromatic Resistance
                [17538] = { class = "ALL", disabled = true },  -- Elixir of the Mongoose
                [17539] = { class = "ALL", disabled = true },  -- Greater Arcane Elixir
                [11474] = { class = "ALL", disabled = true },  -- Elixir of Shadow Power
                [21920] = { class = "ALL", disabled = true },  -- Elixir of Frost Power
                [17537] = { class = "ALL", disabled = true },  -- Elixir of Brute Force
                [17535] = { class = "ALL", disabled = true },  -- Elixir of the Sages
                [6615] = { class = "ALL" },  -- Free Action Potion
                [3169] = { class = "ALL" },  -- Limited Invulnerability Potion
                [17540] = { class = "ALL", disabled = true },  -- Greater Stoneshield Potion
                [17528] = { class = "ALL", disabled = true },  -- Mighty Rage Potion
                [2379] = { class = "ALL", disabled = true },  -- Swiftness Potion
                [11359] = { class = "ALL", disabled = true },  -- Restorative Potion
                [11364] = { class = "ALL", disabled = true },  -- Magic Resistance Potion
                [17543] = { class = "ALL" },  -- Greater Fire Protection Potion
                [17546] = { class = "ALL" },  -- Greater Nature Protection Potion
                [17548] = { class = "ALL" },  -- Greater Shadow Protection Potion
                [17544] = { class = "ALL" },  -- Greater Frost Protection Potion
                [17549] = { class = "ALL" },  -- Greater Arcane Protection Potion
                [16323] = { class = "ALL", disabled = true },  -- Juju Power
                [16329] = { class = "ALL", disabled = true },  -- Juju Might
                [17038] = { class = "ALL", disabled = true },  -- Winterfall Firewater
            },
        },
    }
end

local RETAIL_PRESETS = {

-- Order = display order. Indicators assign filters by numeric id, but preset
-- identity rides the `preset` field so curated-data updates can find them.
filters = {
    { key = "defensives",  name = "Defensives" },
    { key = "activemitigation", name = "Active Mitigation" },
    { key = "raidcds",     name = "Raid CDs" },
    { key = "externals",   name = "Externals" },
    { key = "coreheals",   name = "Core Healing Buffs" },
    { key = "lesserheals", name = "Lesser Healing Buffs" },
    { key = "support",     name = "Support" },
    { key = "offensive",   name = "Offensive CDs" },
    { key = "movement",    name = "Movement" },
    { key = "utility",     name = "Utility" },
    { key = "consumables", name = "Consumables" },
},

-- Curated spell lists per preset: [primaryID] = { class = "CLASSFILE"|"ALL",
-- disabled = true|nil, alts = { id, ... } }. Enabled by default unless
-- `disabled`. In BM2 the PRIMARY id is the checkbox row and alternates
-- (talent/rank variants) follow the primary's state; in PAB every id becomes
-- its own row with the primary's state and class hint.
spells = {
    defensives = {
        [48707] = { class = "DEATHKNIGHT", alts = { 444741 } },
        [48792] = { class = "DEATHKNIGHT" },
        [49039] = { class = "DEATHKNIGHT", disabled = true },
        [55233] = { class = "DEATHKNIGHT" },
        [101568] = { class = "DEATHKNIGHT" },
        [442715] = { class = "DEMONHUNTER", disabled = true },
        [212800] = { class = "DEMONHUNTER" },
        [1266616] = { class = "DEMONHUNTER", alts = { 394933 }, disabled = true },
        [427912] = { class = "DEMONHUNTER", alts = { 258920 }, disabled = true },
        [187827] = { class = "DEMONHUNTER" },
        [207771] = { class = "DEMONHUNTER" },
        [209426] = { class = "DEMONHUNTER", disabled = true },
        [22812] = { class = "DRUID" },
        [22842] = { class = "DRUID" },
        [192081] = { class = "DRUID", disabled = true },
        [61336] = { class = "DRUID" },
        [393903] = { class = "DRUID", disabled = true },
        [1261872] = { class = "DRUID" },
        [404381] = { class = "EVOKER" },
        [363916] = { class = "EVOKER" },
        [374349] = { class = "EVOKER" },
        [186265] = { class = "HUNTER" },
        [472708] = { class = "HUNTER", disabled = true },
        [264735] = { class = "HUNTER" },
        [342246] = { class = "MAGE" },
        [235313] = { class = "MAGE", disabled = true },
        [11426] = { class = "MAGE", disabled = true },
        [45438] = { class = "MAGE" },
        [414658] = { class = "MAGE" },
        [235450] = { class = "MAGE", disabled = true },
        [449336] = { class = "MAGE" },
        [1309793] = { class = "MAGE" },
        [122783] = { class = "MONK" },
        [115203] = { class = "MONK", alts = { 120954 } },
        [125174] = { class = "MONK" },
        [132578] = { class = "MONK" },
        [322507] = { class = "MONK" },
        [432180] = { class = "MONK", disabled = true },
        [1241059] = { class = "MONK" },
        [498] = { class = "PALADIN", alts = { 403876 } },
        [642] = { class = "PALADIN" },
        [184662] = { class = "PALADIN", disabled = true },
        [31850] = { class = "PALADIN" },
        [86659] = { class = "PALADIN" },
        [212641] = { class = "PALADIN" },
        [114216] = { class = "PRIEST", alts = { 114214 }, disabled = true },
        [19236] = { class = "PRIEST" },
        [47585] = { class = "PRIEST" },
        [586] = { class = "PRIEST" },
        [45242] = { class = "PRIEST", alts = { 426401 }, disabled = true },
        [193065] = { class = "PRIEST" },
        [27827] = { class = "PRIEST" },
        [31224] = { class = "ROGUE" },
        [5277] = { class = "ROGUE" },
        [1966] = { class = "ROGUE" },
        [185311] = { class = "ROGUE" },
        [108271] = { class = "SHAMAN" },
        [260881] = { class = "SHAMAN" },
        [108416] = { class = "WARLOCK" },
        [104773] = { class = "WARLOCK" },
        [132413] = { class = "WARLOCK" },
        [387636] = { class = "WARLOCK" },
        [389614] = { class = "WARLOCK", disabled = true },
        [118038] = { class = "WARRIOR" },
        [184364] = { class = "WARRIOR" },
        [190456] = { class = "WARRIOR", alts = { 1277297 } },
        [147833] = { class = "WARRIOR" },
        [385391] = { class = "WARRIOR" },
        [871] = { class = "WARRIOR" },
        [202147] = { class = "WARRIOR", disabled = true },
    },
    activemitigation = {
        [77535] = { class = "DEATHKNIGHT" },
        [203819] = { class = "DEMONHUNTER" },
        [192081] = { class = "DRUID" },
        [132403] = { class = "PALADIN" },
        [132404] = { class = "WARRIOR" },
    },
    raidcds = {
        [145629] = { class = "DEATHKNIGHT", alts = { 51052 } },
        [209426] = { class = "DEMONHUNTER", alts = { 196718 } },
        [740] = { class = "DRUID", alts = { 157982, 1264623 }, disabled = true },
        [359816] = { class = "EVOKER", alts = { 362361 }, disabled = true },
        [363534] = { class = "EVOKER", disabled = true },
        [374227] = { class = "EVOKER" },
        [31821] = { class = "PALADIN", alts = { 317929 } },
        [64843] = { class = "PRIEST", alts = { 64844 }, disabled = true },
        [81782] = { class = "PRIEST", alts = { 62618 } },
        [325174] = { class = "SHAMAN", alts = { 98008 } },
        [97463] = { class = "WARRIOR", alts = { 97462 } },
    },
    externals = {
        [102342] = { class = "DRUID" },
        [357170] = { class = "EVOKER" },
        [53480] = { class = "HUNTER" },
        [116849] = { class = "MONK" },
        [1022] = { class = "PALADIN", alts = { 1309794 } },
        [6940] = { class = "PALADIN" },
        [204018] = { class = "PALADIN" },
        [387804] = { class = "PALADIN" },
        [47788] = { class = "PRIEST" },
        [33206] = { class = "PRIEST" },
    },
    coreheals = {
        [1278914] = { class = "DRUID", disabled = true },
        [33763] = { class = "DRUID", alts = { 419207, 1227806 } },
        [8936] = { class = "DRUID", alts = { 419287 }, disabled = true },
        [774] = { class = "DRUID", alts = { 419204 }, disabled = true },
        [155777] = { class = "DRUID", disabled = true },
        [439530] = { class = "DRUID", disabled = true },
        [474754] = { class = "DRUID", alts = { 474750 } },
        [48438] = { class = "DRUID", alts = { 419344 }, disabled = true },
        [409678] = { class = "EVOKER", disabled = true },
        [355941] = { class = "EVOKER", alts = { 355936, 382614 }, disabled = true },
        [376788] = { class = "EVOKER", disabled = true },
        [363502] = { class = "EVOKER", disabled = true },
        [364343] = { class = "EVOKER" },
        [445740] = { class = "EVOKER", disabled = true },
        [373267] = { class = "EVOKER" },
        [366155] = { class = "EVOKER", disabled = true },
        [367364] = { class = "EVOKER", disabled = true },
        [373862] = { class = "EVOKER", disabled = true },
        [1291636] = { class = "EVOKER", disabled = true },
        [409895] = { class = "EVOKER", disabled = true },
        [450769] = { class = "MONK", alts = { 450521, 450711, 450526, 450531 }, disabled = true },
        [1292922] = { class = "MONK", disabled = true },
        [124682] = { class = "MONK", disabled = true },
        [467281] = { class = "MONK", alts = { 427296 }, disabled = true },
        [388513] = { class = "MONK", disabled = true },
        [450805] = { class = "MONK", disabled = true },
        [119611] = { class = "MONK" },
        [115175] = { class = "MONK", alts = { 1260617, 198533 }, disabled = true },
        [156910] = { class = "PALADIN" },
        [53563] = { class = "PALADIN" },
        [200025] = { class = "PALADIN" },
        [1244893] = { class = "PALADIN" },
        [431381] = { class = "PALADIN", disabled = true },
        [156322] = { class = "PALADIN", alts = { 461432 }, disabled = true },
        [432502] = { class = "PALADIN", disabled = true },
        [469703] = { class = "PALADIN", disabled = true },
        [194384] = { class = "PRIEST" },
        [77489] = { class = "PRIEST", disabled = true },
        [17] = { class = "PRIEST", alts = { 1246768, 1254306, 1300008 }, disabled = true },
        [41635] = { class = "PRIEST", disabled = true },
        [139] = { class = "PRIEST", disabled = true },
        [453846] = { class = "PRIEST", alts = { 453850 }, disabled = true },
        [1253593] = { class = "PRIEST", alts = { 1300009 }, disabled = true },
        [207400] = { class = "SHAMAN", disabled = true },
        [383648] = { class = "SHAMAN", alts = { 974 } },
        [444490] = { class = "SHAMAN", disabled = true },
        [61295] = { class = "SHAMAN", disabled = true },
    },
    lesserheals = {
        [1278914] = { class = "DRUID" },
        [33763] = { class = "DRUID", alts = { 419207, 1227806 }, disabled = true },
        [8936] = { class = "DRUID", alts = { 419287 } },
        [774] = { class = "DRUID", alts = { 419204 } },
        [155777] = { class = "DRUID" },
        [439530] = { class = "DRUID", disabled = true },
        [474754] = { class = "DRUID", alts = { 474750 }, disabled = true },
        [48438] = { class = "DRUID", alts = { 419344 } },
        [409678] = { class = "EVOKER", disabled = true },
        [355941] = { class = "EVOKER", alts = { 355936, 382614 } },
        [376788] = { class = "EVOKER" },
        [363502] = { class = "EVOKER", disabled = true },
        [364343] = { class = "EVOKER", disabled = true },
        [445740] = { class = "EVOKER", disabled = true },
        [373267] = { class = "EVOKER" },
        [366155] = { class = "EVOKER" },
        [367364] = { class = "EVOKER" },
        [373862] = { class = "EVOKER", disabled = true },
        [1291636] = { class = "EVOKER", disabled = true },
        [409895] = { class = "EVOKER" },
        [450769] = { class = "MONK", alts = { 450521, 450711, 450526, 450531 } },
        [1292922] = { class = "MONK" },
        [124682] = { class = "MONK" },
        [467281] = { class = "MONK", alts = { 427296 }, disabled = true },
        [388513] = { class = "MONK", disabled = true },
        [450805] = { class = "MONK", disabled = true },
        [119611] = { class = "MONK", disabled = true },
        [115175] = { class = "MONK", alts = { 1260617, 198533 } },
        [156910] = { class = "PALADIN", disabled = true },
        [53563] = { class = "PALADIN", disabled = true },
        [200025] = { class = "PALADIN", disabled = true },
        [1244893] = { class = "PALADIN", disabled = true },
        [431381] = { class = "PALADIN" },
        [156322] = { class = "PALADIN", alts = { 461432 } },
        [432502] = { class = "PALADIN" },
        [469703] = { class = "PALADIN" },
        [194384] = { class = "PRIEST", disabled = true },
        [77489] = { class = "PRIEST" },
        [17] = { class = "PRIEST", alts = { 1246768, 1254306, 1300008 } },
        [41635] = { class = "PRIEST" },
        [139] = { class = "PRIEST" },
        [453846] = { class = "PRIEST", alts = { 453850 }, disabled = true },
        [1253593] = { class = "PRIEST", alts = { 1300009 } },
        [207400] = { class = "SHAMAN", disabled = true },
        [383648] = { class = "SHAMAN", alts = { 974 }, disabled = true },
        [444490] = { class = "SHAMAN" },
        [61295] = { class = "SHAMAN" },
    },
    support = {
        [360827] = { class = "EVOKER" },
        [395152] = { class = "EVOKER", alts = { 395296 } },
        [410263] = { class = "EVOKER", disabled = true },
        [410089] = { class = "EVOKER" },
        [413984] = { class = "EVOKER", disabled = true },
        [369459] = { class = "EVOKER", disabled = true },
        [406732] = { class = "EVOKER", disabled = true },
        [361021] = { class = "EVOKER", disabled = true },
        [361022] = { class = "EVOKER", disabled = true },
    },
    offensive = {
        [1249658] = { class = "DEATHKNIGHT", alts = { 152279 } },
        [42650] = { class = "DEATHKNIGHT" },
        [51271] = { class = "DEATHKNIGHT" },
        [191427] = { class = "DEMONHUNTER", alts = { 187827, 321067, 321068, 162264 } },
        [471306] = { class = "DEMONHUNTER", alts = { 1217605, 473671, 1217607 } },
        [194223] = { class = "DRUID", alts = { 102560 } },
        [106951] = { class = "DRUID", alts = { 102543 } },
        [50334] = { class = "DRUID", alts = { 102558 }, disabled = true },
        [403631] = { class = "EVOKER", disabled = true },
        [375087] = { class = "EVOKER" },
        [186254] = { class = "HUNTER", alts = { 1235388, 1285912, 19574 } },
        [288613] = { class = "HUNTER" },
        [1250646] = { class = "HUNTER", alts = { 1251703 } },
        [190319] = { class = "MAGE" },
        [365350] = { class = "MAGE", alts = { 365362 } },
        [1247908] = { class = "MAGE" },
        [1249625] = { class = "MONK" },
        [1248992] = { class = "MONK", disabled = true },
        [31884] = { class = "PALADIN", alts = { 231895, 454351, 216331 } },
        [10060] = { class = "PRIEST" },
        [194249] = { class = "PRIEST" },
        [13750] = { class = "ROGUE" },
        [121471] = { class = "ROGUE" },
        [185422] = { class = "ROGUE", disabled = true },
        [1249810] = { class = "ROGUE" },
        [114050] = { class = "SHAMAN", alts = { 114051, 114052, 1219480 } },
        [466772] = { class = "SHAMAN" },
        [442726] = { class = "WARLOCK" },
        [1276767] = { class = "WARLOCK", disabled = true },
        [1276166] = { class = "WARLOCK" },
        [266087] = { class = "WARLOCK" },
        [417282] = { class = "WARLOCK" },
        [107574] = { class = "WARRIOR" },
        [1719] = { class = "WARRIOR" },
    },
    movement = {
        [48265] = { class = "DEATHKNIGHT" },
        [212552] = { class = "DEATHKNIGHT" },
        [444347] = { class = "DEATHKNIGHT" },
        [1850] = { class = "DRUID", alts = { 61684 } },
        [106898] = { class = "DRUID", alts = { 77761, 77764 } },
        [252216] = { class = "DRUID" },
        [5215] = { class = "DRUID" },
        [340546] = { class = "DRUID" },
        [400126] = { class = "DRUID" },
        [186257] = { class = "HUNTER", alts = { 186258 } },
        [118922] = { class = "HUNTER" },
        [5384] = { class = "HUNTER" },
        [199483] = { class = "HUNTER" },
        [1267208] = { class = "HUNTER" },
        [444754] = { class = "MAGE" },
        [130] = { class = "MAGE" },
        [55342] = { class = "MAGE" },
        [108843] = { class = "MAGE" },
        [110960] = { class = "MAGE" },
        [382294] = { class = "MAGE" },
        [119085] = { class = "MONK" },
        [443569] = { class = "MONK" },
        [101545] = { class = "MONK", disabled = true },
        [116841] = { class = "MONK" },
        [394112] = { class = "MONK" },
        [432180] = { class = "MONK" },
        [449609] = { class = "MONK" },
        [276111] = { class = "PALADIN", alts = { 221886, 221883, 276112, 254474,
            254472, 254471, 221885, 254473, 363608, 294133, 221887, 1272854,
            453804, 1253874, 1253723, 1253881 } },
        [1044] = { class = "PALADIN" },
        [121557] = { class = "PRIEST" },
        [65081] = { class = "PRIEST" },
        [111759] = { class = "PRIEST" },
        [2983] = { class = "ROGUE" },
        [1784] = { class = "ROGUE" },
        [31230] = { class = "ROGUE" },
        [36554] = { class = "ROGUE" },
        [114018] = { class = "ROGUE" },
        [192082] = { class = "SHAMAN" },
        [79206] = { class = "SHAMAN" },
        [58875] = { class = "SHAMAN", alts = { 90328 } },
        [2645] = { class = "SHAMAN" },
        [111400] = { class = "WARLOCK" },
        [333889] = { class = "WARLOCK" },
        [387626] = { class = "WARLOCK" },
        [387633] = { class = "WARLOCK" },
        [202164] = { class = "WARRIOR" },
        [1244157] = { class = "WARRIOR" },
        [358267] = { class = "EVOKER" },
        [358733] = { class = "EVOKER" },
        [370889] = { class = "EVOKER" },
        -- Time Spiral: the buff lands under a different spell id per RECIPIENT
        -- class (each class gets its own empowered-movement aura).
        [375234] = { class = "EVOKER", alts = { 375226, 375229, 375230, 375238,
            375240, 375252, 375253, 375254, 375255, 375256, 375257, 375258 } },
        [406732] = { class = "EVOKER" },
    },
    utility = {
        [3714] = { class = "DEATHKNIGHT" },
        [29166] = { class = "DRUID" },
        [406732] = { class = "EVOKER", alts = { 406789 } },
        [390386] = { class = "EVOKER", disabled = true },
        [408233] = { class = "EVOKER", disabled = true },
        [1224810] = { class = "HUNTER", alts = { 54216, 62305 } },
        [466904] = { class = "HUNTER", disabled = true },
        [264667] = { class = "HUNTER", alts = { 357650 }, disabled = true },
        [80353] = { class = "MAGE", disabled = true },
        [116841] = { class = "MONK" },
        [1044] = { class = "PALADIN", alts = { 299256 } },
        [115834] = { class = "ROGUE", alts = { 114018 } },
        [2825] = { class = "SHAMAN", disabled = true },
        [32182] = { class = "SHAMAN", disabled = true },
    },
    consumables = {
        [1236998] = { class = "ALL" },
        [1236616] = { class = "ALL" },
        [1239479] = { class = "ALL" },
        [1236994] = { class = "ALL" },
    },
},

}

local RUNNING, OTHER
if EllesmereUI.IS_FOREVER == true then
    RUNNING, OTHER = ForeverCatalogue(), RETAIL_PRESETS
else
    RUNNING, OTHER = RETAIL_PRESETS, ForeverCatalogue()
end
EllesmereUI.BUFF_PRESETS = RUNNING

-- Profiles travel between retail and WoW Forever (exported on one client,
-- imported on the other, and back). Both consumers keep what only the other
-- client curates stored untouched but inert and hidden here: its spell ids
-- and checkbox states inside shared preset filters, and its presets this
-- client does not offer. Id sets hold primaries and alts alike:
--   BUFF_PRESET_IDS[key][id]       this client's catalogue curates id under key
--   BUFF_PRESET_OTHER_IDS[key][id] the other client's catalogue does
--   BUFF_PRESET_OTHER_FILTERS      the other client's preset list (key, name)
local function IdSets(presets)
    local sets = {}
    for key, list in pairs(presets.spells) do
        local set = {}
        for id, info in pairs(list) do
            set[id] = true
            local alts = info.alts
            if alts then
                for i = 1, #alts do set[alts[i]] = true end
            end
        end
        sets[key] = set
    end
    return sets
end
EllesmereUI.BUFF_PRESET_IDS = IdSets(RUNNING)
EllesmereUI.BUFF_PRESET_OTHER_IDS = IdSets(OTHER)
EllesmereUI.BUFF_PRESET_OTHER_FILTERS = OTHER.filters

-- WoW Forever buff families: one per group buff, every spell that gives it.
-- Read by the Raid Frames Missing Buffs indicator and by Aura Buff Reminders
-- (its Raid Buffs and the rank families of custom spells). names = spells
-- whose (localized) names cover every rank and the group version; single /
-- group = the trainable ranks of the buff and of its group version, lowest
-- first; ids = every spell that applies it (ranks, group version, NPC and
-- item casts, i.e. every spell of those names on the client). Built on WoW
-- Forever only.
if EllesmereUI.IS_FOREVER == true then
    EllesmereUI.FOREVER_BUFF_FAMILIES = {
        fort = { names = { 1243, 21562 },
            single = { 1243, 1244, 1245, 2791, 10937, 10938 }, group = { 21562, 21564 },
            ids = { 1243, 1244, 1245, 2791, 10937, 10938, 10939, 10940, 13864, 23947, 23948,
                    21562, 21564, 450086 } },
        mark = { names = { 1126, 21849 },
            single = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, group = { 21849, 21850 },
            ids = { 1126, 5232, 5234, 5286, 5287, 6756, 8907, 8908, 9884, 9885, 16878, 24752,
                    364163, 1291335, 1310503, 21849, 21850 } },
        spirit = { names = { 14752, 27681 },
            single = { 14752, 14818, 14819, 27841 }, group = { 27681 },
            ids = { 14752, 14818, 14819, 16875, 27841, 27681 } },
        thorns = { names = { 467 },
            single = { 467, 782, 1075, 8914, 9756, 9910 }, group = {},
            ids = { 467, 782, 1075, 8914, 9756, 9910, 15438, 16877, 21335, 21337, 22128, 22351, 22696,
                    25640, 25777, 438294, 438326, 1213813, 1213816, 1213834, 1236308, 1291338, 1312955 } },
        -- Paladin blessings, each with its Greater version (1213408 Kings and
        -- 26650 Light are the client's two non-trainable copies).
        might = { names = { 19740, 25782 },
            single = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, group = { 25782, 25916 },
            ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 } },
        wisdom = { names = { 19742, 25894 },
            single = { 19742, 19850, 19852, 19853, 19854, 25290 }, group = { 25894, 25918 },
            ids = { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 } },
        kings = { names = { 20217, 25898 },
            single = { 20217 }, group = { 25898 },
            ids = { 20217, 1213408, 25898 } },
        salvation = { names = { 1038, 25895 },
            single = { 1038 }, group = { 25895 },
            ids = { 1038, 25895 } },
        light = { names = { 19977, 25890 },
            single = { 19977, 19978, 19979 }, group = { 25890 },
            ids = { 19977, 19978, 19979, 26650, 25890 } },
        ai = { names = { 1459, 23028 },
            single = { 1459, 1460, 1461, 10156, 10157 }, group = { 23028 },
            ids = { 1459, 1460, 1461, 10156, 10157, 13326, 16876, 364161, 23028 } },
        bshout = { names = { 6673 },
            single = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, group = {},
            ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 9128, 24438, 25101, 26043, 26099,
                    27578 } },
    }
end
