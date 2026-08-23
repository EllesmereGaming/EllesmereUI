if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ADDON_NAME, ns = ...

-- Season 2 source identity. Loot itself is read from Blizzard's Encounter
-- Journal at runtime; this compact table only joins Challenge Mode / encounter
-- IDs to the item displayed by the Voidcore confirmation prompt.
ns.SEASON_DATA_REVISION = 2
ns.SUPPORTED_SEASON_ID = 18
ns.SUPPORTED_DISPLAY_SEASON_ID = 2

ns.DUNGEON_SOURCES = {
    { challengeModeID = 249, instanceID = 1762, journalInstanceID = 1041, chestItemID = 279621 }, -- King's Rest
    { challengeModeID = 250, instanceID = 1877, journalInstanceID = 1030, chestItemID = 279624 }, -- Temple of Sethraliss
    { challengeModeID = 399, instanceID = 2521, journalInstanceID = 1202, chestItemID = 279622 }, -- Ruby Life Pools
    { challengeModeID = 584, instanceID = 2859, journalInstanceID = 1309, chestItemID = 279619 }, -- Blinding Vale
    { challengeModeID = 585, instanceID = 2923, journalInstanceID = 1313, chestItemID = 279625 }, -- Voidscar Arena
    { challengeModeID = 586, instanceID = 2825, journalInstanceID = 1311, chestItemID = 279620 }, -- Nalorakk's Den
    { challengeModeID = 587, instanceID = 2813, journalInstanceID = 1304, chestItemID = 279623 }, -- Murder Row
    { challengeModeID = 588, instanceID = 2993, journalInstanceID = 1322, chestItemID = 279618 }, -- Altar of Fangs
}

ns.RAID_SOURCES = {
    { journalInstanceID = 1317, instanceID = 2987, encounterID = 2849, chestItemID = 274708 },
    { journalInstanceID = 1320, instanceID = 3004, encounterID = 2888, chestItemID = 278285 },
    { journalInstanceID = 1320, instanceID = 3004, encounterID = 2874, chestItemID = 278283 },
    { journalInstanceID = 1320, instanceID = 3004, encounterID = 2894, chestItemID = 278286 },
    { journalInstanceID = 1320, instanceID = 3004, encounterID = 2882, chestItemID = 278287 },
    { journalInstanceID = 1320, instanceID = 3004, encounterID = 2871, chestItemID = 278288 },
    { journalInstanceID = 1320, instanceID = 3004, encounterID = 2887, chestItemID = 278289 },
    { journalInstanceID = 1320, instanceID = 3004, encounterID = 2883, chestItemID = 278290 },
    { journalInstanceID = 1320, instanceID = 3004, encounterID = 2895, chestItemID = 278284 },
}

-- Voidcore M+ rewards use the Great Vault reward level for the completed key.
-- Levels above 10 share the +10 reward in this season.
ns.MPLUS_TARGET_LEVELS = {
    [2] = 305, [3] = 305, [4] = 308, [5] = 308, [6] = 311,
    [7] = 315, [8] = 315, [9] = 315, [10] = 318,
}

ns.RAID_DIFFICULTIES = { 17, 14, 15, 16 }
ns.RAID_TARGET_LEVELS = { [17] = 279, [14] = 292, [15] = 305, [16] = 318 }
