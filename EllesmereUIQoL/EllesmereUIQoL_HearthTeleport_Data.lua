if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_HearthTeleport_Data.lua
--  Static travel IDs for the Hearthstone / Teleport popup. Spell/item/toy IDs
--  live here so the runtime never depends on a third-party travel addon.
-------------------------------------------------------------------------------
local EUI = EllesmereUI
if not EUI then return end

local D = {}

-- Base item + cosmetic hearth toys (random pool candidates; excludes unique stones)
D.BASE_HEARTH_ITEM = 6948

D.COSMETIC_HEARTHS = {
    54452, 64488, 93672, 28585, 142542, 163045, 162973, 165669, 165670,
    165802, 166746, 166747, 168907, 172179, 180290, 182773, 183716, 184353,
    188952, 190196, 190237, 193588, 200630, 206195, 208704, 209035, 210455,
    212337, 228940, 235016, 236687, 245970, 246565, 250411, 257736, 260221,
    263489, 263933, 264367, 265100, 142298,
}

-- Fixed hearths listed individually in the popup (never in the random pool or toy flyout).
D.FIXED_HEARTHS = {
    { kind = "item", id = 140192 }, -- Dalaran Hearthstone
    { kind = "toy",  id = 253629 }, -- Key to the Arcantina
}

D.RACE_LOCKED_HEARTHS = {
    [210455] = { "Draenei", "LightforgedDraenei" },
}

-- Mage teleports (newest first)
D.MAGE_TELEPORTS = {
    1259190, 446540, 395277, 344587, 281403, 281404, 224869, 193759,
    176248, 176242, 132621, 132627, 88342, 88344, 53140, 49359, 49358,
    33690, 35715, 32271, 32272, 3561, 3567, 3562, 3563, 3565, 3566, 120145,
}

D.MAGE_PORTALS = {
    1259194, 446534, 395289, 344597, 281400, 281402, 224871, 176246, 176244,
    132620, 132626, 88345, 88346, 53142, 49360, 49361, 33691, 35717, 32266,
    32267, 10059, 11417, 11416, 11418, 11419, 11420, 120146,
}

-- Racials (raceReq)
D.RACIALS = {
    { spell = 312370, race = "Vulpera" },
    { spell = 312372, race = "Vulpera" },
    { spell = 265225, race = "DarkIronDwarf" },
    { spell = 1238686, race = "Haranir" },
}

-- Class teleports (non-mage)
D.CLASS_TELEPORTS = {
    { spell = 556,    class = "SHAMAN" },
    { spell = 50977,  class = "DEATHKNIGHT" },
    { spell = 126892, class = "MONK" },
    { spell = 193753, class = "DRUID", cancelForm = true },
}

-- Legacy dungeon Hero's Path (spell id, optional mapID, expansion for grouping).
-- Current-season dungeons live only in EllesmereUI.SEASON_PORTALS (LFG Reminder).
D.LEGACY_EXPANSION_ORDER = {
    "Midnight",
    "The War Within",
    "Dragonflight",
    "Shadowlands",
    "Battle for Azeroth",
    "Legion",
    "Warlords of Draenor",
    "Mists of Pandaria",
    "Wrath of the Lich King",
    "Cataclysm",
}

-- Alliance / Horde spell pairs for a single dungeon teleport (both ids map to the pair).
D.FACTION_SPELLS = {
    [445418] = { alliance = 445418, horde = 464256 }, -- Siege of Boralus
    [464256] = { alliance = 445418, horde = 464256 },
    [467553] = { alliance = 467553, horde = 467555 }, -- The MOTHERLODE!!
    [467555] = { alliance = 467553, horde = 467555 },
}

D.LEGACY_DUNGEONS = {
    -- Prior season pools (legacy once off SEASON_PORTALS)
    { spell = 1216786, mapID = 525,  expansion = "The War Within" },
    { spell = 1237215, mapID = 542,  expansion = "The War Within" },
    { spell = 445417, mapID = 503,  expansion = "The War Within" },
    { spell = 445414, mapID = 505,  expansion = "The War Within" },
    { spell = 445444, mapID = 499,  expansion = "The War Within" },
    { spell = 467553, mapID = 247,  expansion = "The War Within" },
    { spell = 367416, mapID = 391,  expansion = "Shadowlands" },
    { spell = 354465, mapID = 378,  expansion = "Shadowlands" },
    { spell = 393273, mapID = 402,  expansion = "Dragonflight" },
    { spell = 1254572, mapID = 558, expansion = "Midnight" },
    { spell = 1254559, mapID = 560, expansion = "Midnight" },
    { spell = 1254563, mapID = 559, expansion = "Midnight" },
    { spell = 1254555, mapID = 556, expansion = "Wrath of the Lich King" },
    { spell = 1254551, mapID = 239,  expansion = "Legion" },
    { spell = 159898,  mapID = 161,  expansion = "Warlords of Draenor" },
    { spell = 1254400, mapID = 557,  expansion = "Midnight" },
    -- The War Within
    { spell = 445416, expansion = "The War Within" },
    { spell = 445269, expansion = "The War Within" },
    { spell = 445440, expansion = "The War Within" },
    { spell = 445441, expansion = "The War Within" },
    { spell = 445443, expansion = "The War Within" },
    -- Dragonflight
    { spell = 393267, mapID = 405, expansion = "Dragonflight" },
    { spell = 393283, mapID = 406, expansion = "Dragonflight" },
    { spell = 393276, mapID = 404, expansion = "Dragonflight" },
    { spell = 393222, mapID = 403, expansion = "Dragonflight" },
    { spell = 424197, mapID = 463, expansion = "Dragonflight" },
    { spell = 393279, expansion = "Dragonflight" },
    { spell = 393262, expansion = "Dragonflight" },
    -- Shadowlands
    { spell = 354462, expansion = "Shadowlands" },
    { spell = 354463, expansion = "Shadowlands" },
    { spell = 354464, expansion = "Shadowlands" },
    { spell = 354466, expansion = "Shadowlands" },
    { spell = 354467, expansion = "Shadowlands" },
    { spell = 354468, expansion = "Shadowlands" },
    { spell = 354469, expansion = "Shadowlands" },
    -- Battle for Azeroth
    { spell = 410071, mapID = 245, expansion = "Battle for Azeroth" },
    { spell = 410074, mapID = 251, expansion = "Battle for Azeroth" },
    { spell = 424167, mapID = 248, expansion = "Battle for Azeroth" },
    { spell = 424187, mapID = 244, expansion = "Battle for Azeroth" },
    { spell = 373274, expansion = "Battle for Azeroth" },
    { spell = 445418, expansion = "Battle for Azeroth" },
    { spell = 272268, expansion = "Battle for Azeroth" },
    -- Legion
    { spell = 410078, mapID = 206, expansion = "Legion" },
    { spell = 424153, mapID = 199, expansion = "Legion" },
    { spell = 424163, mapID = 198, expansion = "Legion" },
    { spell = 393764, expansion = "Legion" },
    { spell = 393766, expansion = "Legion" },
    { spell = 373262, expansion = "Legion" },
    -- Warlords of Draenor
    { spell = 159901, mapID = 168, expansion = "Warlords of Draenor" },
    { spell = 159900, mapID = 166, expansion = "Warlords of Draenor" },
    { spell = 159896, mapID = 169, expansion = "Warlords of Draenor" },
    { spell = 159897, expansion = "Warlords of Draenor" },
    { spell = 159895, expansion = "Warlords of Draenor" },
    { spell = 159899, expansion = "Warlords of Draenor" },
    { spell = 159902, expansion = "Warlords of Draenor" },
    -- Mists of Pandaria
    { spell = 131204, mapID = 2, expansion = "Mists of Pandaria" },
    { spell = 131205, mapID = 3, expansion = "Mists of Pandaria" },
    { spell = 131206, mapID = 4, expansion = "Mists of Pandaria" },
    { spell = 131225, mapID = 5, expansion = "Mists of Pandaria" },
    { spell = 131222, mapID = 6, expansion = "Mists of Pandaria" },
    { spell = 131228, expansion = "Mists of Pandaria" },
    { spell = 131232, expansion = "Mists of Pandaria" },
    { spell = 131231, expansion = "Mists of Pandaria" },
    { spell = 131229, expansion = "Mists of Pandaria" },
    -- Cataclysm
    { spell = 410080, mapID = 438, expansion = "Cataclysm" },
    { spell = 424142, mapID = 456, expansion = "Cataclysm" },
    { spell = 445424, expansion = "Cataclysm" },
}

D.RAIDS = {
    1239155, 1226482,
    432254, 432257, 432258,
    373190, 373191, 373192,
}

EUI.HEARTH_TELEPORT_DATA = D
