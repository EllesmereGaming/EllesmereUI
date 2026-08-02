local _, ns = ...
local oUF = ns.oUF

-- Wrath predates Blizzard's Enum namespace. These values mirror the constants
-- used by modern oUF so layouts can share configuration code across clients.
local Enum = _G.Enum or {}
_G.Enum = Enum

Enum.PowerType = Enum.PowerType or {
	Mana = 0,
	Rage = 1,
	Focus = 2,
	Energy = 3,
	ComboPoints = 4,
	Happiness = 4,
	Runes = 5,
	RunicPower = 6,
	SoulShards = 7,
	LunarPower = 8,
	HolyPower = 9,
	Alternate = 10,
	Maelstrom = 11,
	Chi = 12,
	Insanity = 13,
	ArcaneCharges = 16,
	Fury = 17,
	Pain = 18,
	Essence = 19,
}

oUF.Enum = {
	DispelType = {
		None = 0,
		Magic = 1,
		Curse = 2,
		Disease = 3,
		Poison = 4,
		Enrage = 9,
		Bleed = 11,
	},
	SelectionType = {
		Hostile = 0,
		Unfriendly = 1,
		Neutral = 2,
		Friendly = 3,
		PlayerSimple = 4,
		PlayerExtended = 5,
		Party = 6,
		PartyPvP = 7,
		Friend = 8,
		Dead = 9,
		PartyPvPInBattleground = 13,
		RecentAlly = 16,
	},
}
