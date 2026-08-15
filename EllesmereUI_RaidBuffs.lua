-------------------------------------------------------------------------------
--  EllesmereUI_RaidBuffs.lua -- Shared raid buff definitions
--
--  Which class provides which group-wide buff, and the aura ids that prove it
--  landed. Facts about the game, not about any one feature, which is why they
--  live in the parent: every child addon has the parent, so a module reading
--  this depends on nothing the user might have switched off.
--
--  Aura Buff Reminders owned this table first, because it needed it first --
--  it is the module that nags people to recast a missing buff. The Raid Tools
--  consumable check needs the same answers, and a second copy would mean two
--  lists to update and one of them silently wrong. Same reasoning as
--  EllesmereUI_Glows.lua: modules attach here instead of duplicating.
--
--  FIELDS
--    key        stable identifier, used as a settings key -- never rename one
--    class      the class token that can cast it. A buff nobody present can
--               provide is not missing, and consumers use this to say so.
--    name       English fallback only; the localized name comes from the game
--               through castSpell.
--    castSpell  the spell a player casts. Also the source of the icon.
--    buffIDs    every aura id that counts as "has it" -- a buff can land under
--               more than one id depending on who cast it or how.
--    check      "raid" for group-wide buffs. Anything else is a per-player
--               reminder and does not belong in a raid-wide check.
--    benefit    which stat it grants, where that distinction matters.
--
--  Ids age slowly here: these are class spells, so an expansion adds one
--  rather than invalidating the rest.
-------------------------------------------------------------------------------

EllesmereUI.RaidBuffs = {
    { key="motw",   class="DRUID",   name="Mark of the Wild",       castSpell=1126,   buffIDs={1126,432661},    check="raid" },
    { key="bshout", class="WARRIOR", name="Battle Shout",           castSpell=6673,   buffIDs={6673},    check="raid", benefit="attackPower" },
    { key="fort",   class="PRIEST",  name="Power Word: Fortitude",  castSpell=21562,  buffIDs={21562},   check="raid" },
    { key="ai",     class="MAGE",    name="Arcane Intellect",       castSpell=1459,   buffIDs={1459,432778},    check="raid", benefit="intellect" },
    { key="bronze", class="EVOKER",  name="Blessing of the Bronze", castSpell=364342,
      buffIDs={381732,381741,381746,381748,381749,381750,381751,381752,381753,381754,381756,381757,381758},
      check="raid" },
    { key="sky",    class="SHAMAN",  name="Skyfury",                castSpell=462854, buffIDs={462854},  check="raid" },
    -- Hunter's Mark: disabled (under maintenance)
    -- { key="hmark",  class="HUNTER",  name="Hunter's Mark",          castSpell=257284, buffIDs={257284},  check="huntersMark" },
}
