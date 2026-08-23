if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ADDON_NAME, ns = ...

-- Season 2 source identity. Loot itself is read from Blizzard's Encounter
-- Journal at runtime; this compact table only joins Challenge Mode / encounter
-- IDs to the item displayed by the Voidcore confirmation prompt.
ns.SEASON_DATA_REVISION = 4
ns.SUPPORTED_SEASON_ID = 18
ns.SUPPORTED_DISPLAY_SEASON_ID = 2

ns.DUNGEON_SOURCES = {
    { challengeModeID = 249, instanceID = 1762, journalInstanceID = 1041, chestItemID = 279621, fallbackItems = {
        159136, 159137, 159234, 159243, 159288, 159300, 159301, 159304, 159312, 159313,
        159369, 159371, 159409, 159412, 159413, 159418, 159459, 159617, 159618, 159642,
        159643, 159644, 159645, 159667, 160213, 160216, 239045, 239046, 239047,
        239048, 239049, 239050, 239051, 273649,
    } }, -- King's Rest
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

-- Tier tokens do not expose an equip location through the item API. Keep the
-- current season's small token-to-slot mapping here so Encounter Journal rows
-- survive the catalog's slot validation and participate in slot filtering.
-- The Encounter Journal loot-spec filter remains responsible for selecting the
-- appropriate Woven, Cured, Cast, or Forged token for the player's class.
ns.RAID_TOKEN_SLOTS = {
    [270909] = "TIER", -- Slumbering Coil Curio (Ula'tek omni-token)
    [270910] = "INVTYPE_HAND", [270911] = "INVTYPE_HAND",
    [270912] = "INVTYPE_HAND", [270913] = "INVTYPE_HAND",
    [270914] = "INVTYPE_HEAD", [270915] = "INVTYPE_HEAD",
    [270916] = "INVTYPE_HEAD", [270917] = "INVTYPE_HEAD",
    [270918] = "INVTYPE_LEGS", [270919] = "INVTYPE_LEGS",
    [270920] = "INVTYPE_LEGS", [270921] = "INVTYPE_LEGS",
    [270922] = "INVTYPE_SHOULDER", [270923] = "INVTYPE_SHOULDER",
    [270924] = "INVTYPE_SHOULDER", [270925] = "INVTYPE_SHOULDER",
    [270926] = "INVTYPE_CHEST", [270927] = "INVTYPE_CHEST",
    [270928] = "INVTYPE_CHEST", [270929] = "INVTYPE_CHEST",
}

-- Voidcore M+ rewards use the end-of-run Champion/Hero track for the selected
-- key. Levels above 10 share the +10 reward in this season.
ns.MPLUS_TARGET_LEVELS = {
    [2] = 295, [3] = 295, [4] = 298, [5] = 302, [6] = 305,
    [7] = 305, [8] = 308, [9] = 308, [10] = 311,
}

ns.MPLUS_TARGET_BONUS_IDS = {
    [2] = 12834, [3] = 12834, [4] = 12835, [5] = 12836, [6] = 12841,
    [7] = 12841, [8] = 12842, [9] = 12842, [10] = 12843,
}

ns.RAID_DIFFICULTIES = { 17, 14, 15, 16 }
ns.RAID_TARGET_LEVELS = { [17] = 279, [14] = 292, [15] = 305, [16] = 318 }
ns.RAID_TARGET_BONUS_IDS = {
    [17] = { [279] = 12825, [282] = 12826, [285] = 12827, [289] = 12828, [292] = 12829, [295] = 12830 },
    [14] = { [292] = 12833, [295] = 12834, [298] = 12835, [302] = 12836, [305] = 12837, [308] = 12838 },
    [15] = { [305] = 12841, [308] = 12842, [311] = 12843, [315] = 12844, [318] = 12845, [321] = 12846 },
    [16] = { [318] = 12849, [321] = 12850, [324] = 12851, [328] = 12852, [331] = 12853, [334] = 12854 },
}
