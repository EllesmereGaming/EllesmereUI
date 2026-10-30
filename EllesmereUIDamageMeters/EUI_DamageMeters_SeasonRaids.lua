if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI and EllesmereUI.IS_FOREVER then return end
-- SEASON UPDATE: this season's raids and boss lairs, by the map ID the game
-- reports inside them (GetInstanceInfo's eighth return), each with the NPC IDs
-- of its bosses. Adds are left out on purpose: their rows keep the combat note.
-- Kept by hand; the dungeons beside it are generated (EUI_DamageMeters_SeasonMobs.lua).
local _, ns = ...
ns.DM_SEASON_RAIDS = {
    [3004] = { -- The Venomous Abyss
        257911, 259854,         -- The Coiled Altar: Zul'jan, Hex Lord Malacrass
        261835, 261843, 261848, -- The Lost Explorers: First Mate Nama, Scrollsage Iku, Trader Gebbo
        259927, 263050,         -- Nek'zali the Soulcoiler, Echo of Jawae
        258557, 258556,         -- Entombed Sentinels: Breath of Ula'tek, Blood of Ula'tek
        257347,                 -- Sszorak
        257361, 257368,         -- The Twin Fangs: Vexhul, Ithraz
        257758,                 -- Ula'tek
        259181,                 -- Vashnik the Malignant
    },
    [3095] = { 267861, 259664, 262995 }, -- The Unbinding of Kith'ix: Kith'ix
    [2987] = { 252959 },                 -- The Tidebound Grotto: Nymrissa Wavecaller
}
