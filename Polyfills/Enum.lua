-- Enum Namespace and catch-all safety
-- Enum Namespace
Enum = Enum or {}

-- Explicitly populate Enum subfields used in the codebase
Enum.ItemClass = {
    Weapon = 2,
    Armor = 4,
    Gem = 3,
    Container = 1,
    Consumable = 0,
    Glyph = 16,
    TradeGoods = 7,
    Projectile = 6,
    Quiver = 11,
    Recipe = 9,
    Reagent = 5,
    Key = 13,
    Miscellaneous = 15,
    Quest = 12,
    Profession = 19,
    Housing = 20,
}

Enum.ItemBind = {
    None = 0,
    OnAcquire = 1,
    OnEquip = 2,
}

Enum.SpellBookSpellBank = {
    Player = "spell",
    Pet = "pet",
}

Enum.SpellBookItemType = {
    Spell = "SPELL",
    FutureSpell = "FUTURESPELL",
    PetAction = "PETACTION",
    Flyout = "FLYOUT",
}

Enum.BankType = {
    Character = 1,
    Account = 2,
}

Enum.BagSlotFlags = {
    ClassEquipment = 1,
    ClassConsumables = 2,
    ClassProfessionGoods = 3,
    ClassReagents = 4,
    ClassJunk = 5,
}

Enum.QuestClassification = {
    Normal = 0,
    Elite = 1,
    Rare = 2,
    RareElite = 3,
    WorldQuest = 4,
}

Enum.TooltipDataType = {
    Spell = 1,
    UnitAura = 2,
    Item = 3,
    Macro = 4,
    PetAction = 5,
}

Enum.PowerType = {
    Mana = 0,
    Rage = 1,
    Focus = 2,
    Energy = 3,
    RunicPower = 6,
}
