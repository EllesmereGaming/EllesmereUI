if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_MapTravelData.lua  (WoW Forever only)
--  Places for the world map travel pins (EllesmereUIForeverEssentials_MapTravel.lua),
--  in percent of each zone map. Instance entrances are the instances' corpse
--  points (Map table) placed with UiMapAssignment; docks and zeppelin towers
--  follow the TaxiNodes and AreaPOI positions; Forever's new docks and
--  dungeons, absent from the client data, are read on the map. Names are read in game
--  (map, area and instance names), so they follow the client's language.
--  Wrapped in a function so the tables are only built on first enable.
-------------------------------------------------------------------------------
local _, module = ...

function module.MapTravelData()
return {
    -- uiMapID = { { x, y, kind, destination uiMapID, destination areaID }, ... }
    transports = {
        [1411] = { {51.2,13.4,"zeppelin",1420,1497}, {50.4,14.3,"zeppelin",1434,117} },         -- Durotar
        [1413] = { {63.7,38.6,"boat",1434,35} },                                                -- The Barrens (Ratchet)
        [1412] = { {34.3,25.8,"zeppelin",2521,16628} },                                         -- Mulgore (Skywatcher Plateau)
        [1416] = { {12.5,51.8,"skycutter",2521,16628} },                                        -- Alterac Mountains (Dalaran)
        [1420] = { {61.3,58.6,"zeppelin",1411,1637}, {60.4,59.1,"zeppelin",1434,117} },         -- Tirisfal Glades
        [1424] = { {50.5,65.0,"boat",1439,442} },                                               -- Hillsbrad Foothills (Southshore)
        [1434] = { {25.8,73.1,"boat",1413,392}, {31.6,29.0,"zeppelin",1411,1637},
                   {31.0,30.2,"zeppelin",1420,1497} },                                          -- Stranglethorn Vale
        [1437] = { {4.6,57.1,"boat",1424,271}, {5.0,63.5,"boat",1445,513} },                    -- Wetlands (Menethil Harbor)
        [1438] = { {55.2,95.0,"boat",1439,442} },                                               -- Teldrassil (Rut'theran Village)
        [1439] = { {32.4,43.8,"boat",1437,150}, {33.2,40.2,"boat",1438,702},
                   {32.4,43.8,"boat",1453,17203} },                                             -- Darkshore (Auberdine)
        [1444] = { {43.3,42.8,"boat",1444,1116}, {31.0,39.7,"boat",1444,1108} },                -- Feralas (Feathermoon ferry)
        [1445] = { {71.6,56.4,"boat",1437,150} },                                               -- Dustwallow Marsh (Theramore)
        [1446] = { {69.0,23.0,"boat",2548,16727} },                                             -- Tanaris (Steamwheedle Port)
        [1453] = { {69.4,30.5,"tram",1455,1537}, {22.0,57.0,"boat",1439,442},
                   {50.0,87.0,"portal",1416,279} },                                             -- Stormwind City
        [1455] = { {76.6,51.2,"tram",1453,1519} },                                              -- Ironforge
        [2521] = { {65.0,81.0,"skycutter",1416,279}, {58.0,81.0,"zeppelin",1412,17045} },       -- Zephras Isle (Valanaar)
        [2548] = { {79.0,52.3,"boat",1446,977} },                                               -- The Riverglades (Powderfuse Port)
    },
    -- uiMapID = { { x, y, uiMapID the road leads to }, ... }
    exits = {
        [1411] = { {34.7,42.6,1413}, {45.6,12.1,1454} },
        [1412] = { {70.5,56.5,1413}, {37.0,32.0,1456} },
        [1413] = { {63.4,19.3,1411}, {38.5,59.5,1412}, {48.3,5.7,1440}, {35.5,27.6,1442}, {50.0,78.6,1445}, {44.6,90.5,1441} },
        [1416] = { {57.0,75.0,1424}, {80.0,33.0,1422} },
        [1417] = { {44.0,92.5,1437}, {20.3,30.0,1424} },
        [1418] = { {6.0,60.0,1427}, {46.2,9.5,1432} },
        [1419] = { {52.9,2.8,1435} },
        [1420] = { {54.5,72.5,1421}, {83.5,69.8,1422}, {61.9,65.0,1458} },
        [1421] = { {67.0,81.5,1424}, {67.5,4.6,1420} },
        [1422] = { {27.0,56.5,1420}, {43.0,85.0,1416}, {69.5,50.2,1423} },
        [1423] = { {8.0,63.0,1422} },
        [1424] = { {83.3,58.8,1417}, {12.5,46.5,1421}, {55.8,19.5,1416}, {88.0,33.0,1425} },
        [1425] = { {8.5,46.5,1424} },
        [1426] = { {85.5,51.2,1432}, {53.5,34.5,1455} },
        [1427] = { {35.0,85.0,1428}, {79.0,46.0,1418} },
        [1428] = { {75.0,84.3,1433}, {28.6,17.1,1427} },
        [1429] = { {20.6,80.6,1436}, {41.5,93.5,1431}, {95.5,72.3,1433}, {32.0,49.5,1453} },
        [1430] = { {32.0,35.0,1431}, {60.2,43.1,1435} },
        [1431] = { {27.3,21.5,1429}, {7.5,62.0,1436}, {86.5,9.0,1433}, {90.5,41.0,1430}, {44.5,88.5,1434} },
        [1432] = { {46.2,76.0,1418}, {21.0,68.5,1426}, {20.5,10.5,1437} },
        [1433] = { {4.5,71.7,1429}, {2.0,90.0,1431}, {53.5,78.6,1435}, {36.0,7.0,1428} },
        [1434] = { {38.2,3.0,1431} },
        [1435] = { {5.0,63.0,1430}, {27.0,6.0,1433}, {34.5,66.0,1419} },
        [1436] = { {61.5,18.0,1429}, {68.0,70.5,1431} },
        [1437] = { {52.5,87.5,1432}, {51.0,10.5,1417} },
        [1438] = { {29.5,56.0,1457} },
        [1439] = { {43.5,92.5,1440} },
        [1440] = { {68.9,89.6,1413}, {26.5,4.0,1439}, {42.0,71.0,1442}, {56.0,26.0,1448}, {94.5,47.5,1447} },
        [1441] = { {31.5,21.5,1413}, {11.5,36.5,1444}, {76.5,97.0,1446} },
        [1442] = { {80.0,90.0,1413}, {78.0,42.0,1440}, {29.5,77.5,1443} },
        [1443] = { {54.0,7.0,1442}, {45.0,95.0,1444} },
        [1444] = { {46.5,2.0,1443}, {89.0,46.0,1441} },
        [1445] = { {28.0,47.5,1413} },
        [1446] = { {51.0,21.0,1441}, {31.7,28.5,1449} },
        [1447] = { {11.5,78.5,1440} },
        [1448] = { {55.5,96.0,1440}, {64.5,8.0,1452}, {63.0,6.5,1450} },
        [1449] = { {79.5,49.5,1446}, {29.0,22.5,1451} },
        [1450] = { {29.7,98.0,1448} },
        [1451] = { {82.0,18.0,1449} },
        [1452] = { {28.0,34.0,1448} },
    },
    -- uiMapID = { { x, y, instance mapID, isRaid, entrance }, ... }: the instances in the
    -- client's own dungeon list (LFGDungeons) that have an entrance point,
    -- dungeons only: no raid is open at WoW Forever's launch (isRaid stays for
    -- when they are). Secondary entrances and wing names are placed by hand
    -- (the game gives one point per instance), as are Forever's new dungeons
    -- (no entrance point in the client; Dalaran's sewer way in, inside the
    -- city, is left out).
    instances = {
        [1413] = { {47.7,35.0,43}, {42.3,89.9,47}, {50.9,92.9,129} },  -- The Barrens
        [1418] = { {35.2,10.3,70,nil,"Main Entrance"}, {65.4,43.6,70,nil,"Back Entrance"} },  -- Badlands
        [1420] = { {85.1,31.4,189,nil,"Graveyard, Library, Armory, Cathedral"}, {63.1,67.5,2999} },  -- Tirisfal Glades
        [1416] = { {8.8,59.6,2959,nil,"Sewer Tunnel"} },             -- Alterac Mountains
        [1421] = { {44.7,67.8,33} },                                  -- Silverpine Forest
        [1422] = { {69.1,73.0,289} },                                 -- Western Plaguelands
        [1423] = { {26.1,10.4,329,nil,"Main Gate"}, {43.6,19.0,329,nil,"Service Entrance"} },  -- Eastern Plaguelands
        [1426] = { {17.7,39.2,90} },                                  -- Dun Morogh
        [1427] = { {40.8,95.6,229}, {27.1,72.5,230} },                -- Searing Gorge
        [1428] = { {33.0,25.2,229}, {22.6,7.5,230} },                 -- Burning Steppes
        [1435] = { {77.3,35.9,109} },                                 -- Swamp of Sorrows
        [1436] = { {42.5,71.7,36} },                                  -- Westfall
        [1437] = { {48.0,56.0,2998} },                                -- Wetlands
        [1440] = { {16.5,11.0,48} },                                  -- Ashenvale
        [1443] = { {29.1,62.9,349} },                                 -- Desolace
        [1444] = { {62.5,24.9,429,nil,"North"}, {65.0,29.8,429,nil,"East"}, {60.3,30.3,429,nil,"West"} },  -- Feralas
        [1446] = { {38.7,19.9,209} },                                 -- Tanaris
        [1453] = { {50.4,66.2,34} },                                  -- Stormwind City
        [1455] = { {28.0,48.0,3065} },                              -- Ironforge
        [1454] = { {53.0,48.9,389} },                                 -- Orgrimmar
    },
}
end
