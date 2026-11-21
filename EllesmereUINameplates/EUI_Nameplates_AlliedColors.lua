if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local addon, ns = ...

if not ns then return end

-------------------------------------------------------------------------------
--  Nameplates\EUI_Nameplates_AlliedColors.lua
--  The colour of an allied (friendly or neutral) unit's name: which entity it
--  is to you (friend, guild, group, standard NPC, pet, ...) and the override for
--  that entity.
--
--  One catalog (ns.NAME_ONLY_TARGETS) drives both sides: this file resolves a
--  unit to a colour, and the options page builds a toggle + swatch per entry
--  from the same list, in the same order. A unit takes the first enabled entry
--  that matches, so read the catalog top to bottom. Every entry is off by
--  default: with them all off, a name is coloured by the base fallback in
--  Allied.GetNameColor and nothing here costs more than the entries' own
--  toggle reads -- a unit API call (a matcher, the flag, the combat test) is
--  made only for an entry that is on.
--
--  An entry's toggle only ever colours: off means "no entry paints this unit",
--  never "paint something else". A player's pet is the one case with a second
--  step: its own row first, then the colour its owner's flag state takes.
--
--  Read by EllesmereUINameplatesFriendly.lua (the name-only text and the NPC
--  overlay) and by the Friendly options page.
-------------------------------------------------------------------------------

local UnitExists, UnitIsPlayer = UnitExists, UnitIsPlayer
local UnitReaction = UnitReaction
local UnitGUID, UnitPlayerControlled = UnitGUID, UnitPlayerControlled
local UnitIsTapDenied = UnitIsTapDenied
local UnitPlayerOrPetInParty = UnitPlayerOrPetInParty
local UnitPlayerOrPetInRaid = UnitPlayerOrPetInRaid
local GetTime = GetTime
local floor = math.floor
-- A GUID the game withholds is never compared or used as a table key.
local issecretvalue = issecretvalue

local Allied = {}
ns.Allied = Allied

-- Profile alias: reads from the centralized store via ns.db
local function FP()
    return ns.db and ns.db.profile
end

-------------------------------------------------------------------------------
--  Player relationships
-------------------------------------------------------------------------------
-- Players seen in your group this session, by GUID: unit tokens recycle, and a
-- player who leaves the group keeps the GUID their nameplate came up with.
local recentGroupPlayers = {}

-- Records the current group, so "Recently Played With" still knows a player
-- once they leave it. Called on login, on a zone change and on a roster change.
local recentCount = 0
function Allied.UpdateRecentGroupMembers()
    if not IsInGroup() then return end
    if recentCount >= 512 then wipe(recentGroupPlayers); recentCount = 0 end
    local isRaid = IsInRaid()
    local prefix = isRaid and "raid" or "party"
    local count = isRaid and GetNumGroupMembers() or (GetNumGroupMembers() - 1)
    for i = 1, count do
        local unit = prefix .. i
        local guid = UnitGUID(unit)
        if guid and not issecretvalue(guid) and guid ~= "" and not UnitIsUnit(unit, "player") then
            if not recentGroupPlayers[guid] then recentCount = recentCount + 1 end
            recentGroupPlayers[guid] = GetTime()
        end
    end
end

local function IsUnitFriend(unit)
    local guid = UnitGUID(unit)
    if not guid or issecretvalue(guid) or guid == "" then return false end
    if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID and C_BattleNet.GetGameAccountInfoByGUID(guid) then
        return true
    end
    return (C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid)) or false
end

local function IsUnitRecent(unit)
    local guid = UnitGUID(unit)
    if not guid or issecretvalue(guid) or not recentGroupPlayers[guid] then return false end
    -- Still grouped: Party & Raid Members covers them, and ranks higher.
    return not (UnitPlayerOrPetInParty(unit) or UnitPlayerOrPetInRaid(unit))
end

local function IsInMyGroup(unit)
    return UnitPlayerOrPetInParty(unit) or UnitPlayerOrPetInRaid(unit) or false
end

local function IsGuildMember(unit)
    return (UnitIsInMyGuild and UnitIsInMyGuild(unit)) or false
end

local function IsPvPFlagged(unit)
    return (UnitIsPVP and UnitIsPVP(unit)) or false
end

local function IsUnflagged(unit)
    return not IsPvPFlagged(unit)
end

-------------------------------------------------------------------------------
--  The catalog: every name colour override, in priority order within its
--  section. sec groups the entries into the options popup's three sections
--  (1 player relationships, 2 friendly and neutral units, 3 opposing faction
--  units). on / col are the profile keys of the entry's toggle and colour, so
--  the hot path indexes the profile rather than building a key per call.
-------------------------------------------------------------------------------
ns.NAME_ONLY_TARGETS = {
    -- Section 1: Player Relationships
    { key = "FRIENDLY_PLAYER_FRIEND", label = "Friends (BNet & Character)", sec = 1,
      tip = "Highlights players on your Battle.net or character Friends list.\n\nWhen disabled, falls back to your base color.",
      on = "nameOnlyCustomEnabled_FRIENDLY_PLAYER_FRIEND",
      col = "nameOnlyCustomColor_FRIENDLY_PLAYER_FRIEND",
      defColor = { r = 1.00, g = 0.84, b = 0.00 }, match = IsUnitFriend },
    { key = "FRIENDLY_PLAYER_RECENT", label = "Recently Played With", sec = 1,
      tip = "Highlights players who were in your party or raid earlier this session, but are no longer in your group.\n\nWhen disabled, falls back to your base color.",
      on = "nameOnlyCustomEnabled_FRIENDLY_PLAYER_RECENT",
      col = "nameOnlyCustomColor_FRIENDLY_PLAYER_RECENT",
      defColor = { r = 0.70, g = 0.53, b = 1.00 }, match = IsUnitRecent },
    { key = "FRIENDLY_PARTY_RAID", label = "Party & Raid Members", sec = 1,
      tip = "Highlights players in your current party or raid group.\n\nWhen disabled, falls back to your base color.",
      on = "nameOnlyCustomEnabled_FRIENDLY_PARTY_RAID",
      col = "nameOnlyCustomColor_FRIENDLY_PARTY_RAID",
      defColor = { r = 0.616, g = 0.651, b = 1.00 }, match = IsInMyGroup },
    { key = "FRIENDLY_GUILD", label = "Guild Members", sec = 1,
      tip = "Highlights players in your guild.\n\nWhen disabled, falls back to your base color.",
      on = "nameOnlyCustomEnabled_FRIENDLY_GUILD",
      col = "nameOnlyCustomColor_FRIENDLY_GUILD",
      defColor = { r = 0.25, g = 0.88, b = 0.55 }, match = IsGuildMember },
    { key = "FRIENDLY_PLAYER_UNFLAGGED", label = "Unflagged Players", sec = 1,
      tip = "Highlights friendly players who are not PvP flagged.\n\nWhen disabled, falls back to your base color.",
      on = "nameOnlyCustomEnabled_FRIENDLY_PLAYER_UNFLAGGED",
      col = "nameOnlyCustomColor_FRIENDLY_PLAYER_UNFLAGGED",
      defColor = { r = 0.467, g = 0.533, b = 1.00 }, match = IsUnflagged },
    { key = "FRIENDLY_PLAYER_PVP", label = "PvP Flagged Players", sec = 1,
      tip = "Highlights friendly players flagged for PvP.\n\nWhen disabled, falls back to your base color.",
      on = "nameOnlyCustomEnabled_FRIENDLY_PLAYER_PVP",
      col = "nameOnlyCustomColor_FRIENDLY_PLAYER_PVP",
      defColor = { r = 0.00, g = 1.00, b = 0.00 }, match = IsPvPFlagged },
    -- A player's pet is a player relationship, not an NPC one: it paints on the
    -- same plates, and with its own row off it takes the colour its owner's flag
    -- state takes.
    { key = "PET_MINION_FRIENDLY", label = "Player Pets & Minions", sec = 1,
      tip = "Highlights player-controlled pets and minions.\n\nWhen disabled, uses the owner's color: the PvP Flagged or Unflagged Players swatch for the owner's flag state, else the default friendly player color.",
      on = "nameOnlyCustomEnabled_PET_MINION_FRIENDLY",
      col = "nameOnlyCustomColor_PET_MINION_FRIENDLY",
      defColor = { r = 0.467, g = 0.533, b = 1.00 } },

    -- Section 2: Friendly & Neutral Units
    { key = "FRIENDLY_NPC_STANDARD", label = "Standard NPCs", sec = 2,
      tip = "Standard friendly NPCs (guards, citizens, vendors).\n\nWhen disabled, uses the NPC Name Color swatch.",
      on = "nameOnlyCustomEnabled_FRIENDLY_NPC_STANDARD",
      col = "nameOnlyCustomColor_FRIENDLY_NPC_STANDARD",
      defColor = { r = 0.00, g = 1.00, b = 0.00 } },
    { key = "FRIENDLY_NPC_ESCORT", label = "Escort NPCs (In Combat)", sec = 2,
      tip = "Friendly NPCs engaged in combat (escort quest objectives).\n\nWhen disabled, uses the NPC Name Color swatch.",
      on = "nameOnlyCustomEnabled_FRIENDLY_NPC_ESCORT",
      col = "nameOnlyCustomColor_FRIENDLY_NPC_ESCORT",
      defColor = { r = 0.00, g = 1.00, b = 0.00 } },
    { key = "NEUTRAL_NPC_PASSIVE", label = "Passive Neutral NPCs", sec = 2,
      tip = "Non-aggressive neutral NPCs (yellow reaction).\n\nWhen disabled, uses neutral reaction yellow.",
      on = "nameOnlyCustomEnabled_NEUTRAL_NPC_PASSIVE",
      col = "nameOnlyCustomColor_NEUTRAL_NPC_PASSIVE",
      defColor = { r = 1.00, g = 1.00, b = 0.00 } },

    -- Section 3: Opposing Faction Units
    { key = "HOSTILE_NPC_STANDARD", label = "Opposing Faction NPCs", sec = 3,
      tip = "Opposing faction and unfriendly NPCs.\n\nWhen disabled, uses reaction orange.",
      on = "nameOnlyCustomEnabled_HOSTILE_NPC_STANDARD",
      col = "nameOnlyCustomColor_HOSTILE_NPC_STANDARD",
      defColor = { r = 0.949, g = 0.549, b = 0.098 } },
}

-- key -> entry, for the resolution above (one saved key per catalog entry).
local CATALOG_BY_KEY, PLAYER_ENTRIES = {}, {}
for _, item in ipairs(ns.NAME_ONLY_TARGETS) do
    CATALOG_BY_KEY[item.key] = item
    if item.sec == 1 then PLAYER_ENTRIES[#PLAYER_ENTRIES + 1] = item end
end

-- An entry's colour: the saved one, else the defaults table's, else the
-- catalog's own. Returns r, g, b, or nil.
local function EntryColor(fp, item)
    if not item then return nil end
    local c = (fp and fp[item.col]) or (ns.defaults and ns.defaults[item.col]) or item.defColor
    if not c then return nil end
    return c.r, c.g, c.b
end

-- An entry's toggle, off unless the profile says otherwise.
local function On(fp, item)
    return item ~= nil and fp ~= nil and fp[item.on] == true
end

-------------------------------------------------------------------------------
--  Entity type: NPCs and their pets
-------------------------------------------------------------------------------
-- The NPC subtitle (e.g. "Innkeeper", "Flight Master") from tooltip line 2,
-- through the safe C_TooltipInfo API. nil when there is none.
local LEVEL_PATTERN
do
    local tpl = UNIT_LEVEL_TEMPLATE or "Level %d"
    LEVEL_PATTERN = tpl:lower():gsub("%%d", "(.+)")
end

function Allied.GetNPCTitle(unit)
    if not C_TooltipInfo or not C_TooltipInfo.GetUnit then return nil end
    local data = C_TooltipInfo.GetUnit(unit)
    if not data or not data.lines then return nil end
    local cbMode = tonumber(GetCVar("colorblindMode")) or 0
    local line = data.lines[2 + cbMode]
    if not line then return nil end
    local text = line.leftText
    -- The secret guard MUST come before any comparison: line.leftText is a secret
    -- string under nameplate taint, and comparing it throws. A truthiness test
    -- (not text) is secret-safe, so the nil-guard stays first.
    if not text then return nil end
    if issecretvalue and issecretvalue(text) then return nil end
    if text == "" then return nil end
    -- Filter out level strings (e.g. "Level 70 Humanoid")
    if text:lower():match(LEVEL_PATTERN) then return nil end
    return text
end

-- The NPC subtitle, cached by GUID: the tooltip build is the expensive part, and
-- every plate that draws the line (the name-only overlay, the health bar plate)
-- reads the same answer.
local titleByGUID = {}
local titleCount = 0
local function CachedNPCTitle(unit)
    local guid = UnitGUID(unit)
    if not guid then return Allied.GetNPCTitle(unit) end
    -- A withheld identity has no subtitle we could read either.
    if issecretvalue(guid) then return nil end
    local title = titleByGUID[guid]
    if title == nil then
        if titleCount >= 512 then wipe(titleByGUID); titleCount = 0 end
        title = Allied.GetNPCTitle(unit) or false
        titleByGUID[guid] = title
        titleCount = titleCount + 1
    end
    return title or nil
end

-- A unit's subtitle, cached by GUID: the tooltip build is the expensive part, and
-- every plate that draws the line (the name-only overlay, the health bar plate)
-- reads the same answer.
function Allied.GetCachedNPCTitle(unit) return CachedNPCTitle(unit) end

-- Pet or minion: a unit a player controls -- a player's pet, minion or vehicle.
-- An NPC's guardian has no flag of its own in either client's API, and its
-- tooltip subtitle is English words that read titles like "Battle Pet Trainer"
-- as pets, so a non-player unit stays an NPC here and takes its section's colour.
function Allied.IsPet(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return false end
    return UnitPlayerControlled(unit) and true or false
end

-------------------------------------------------------------------------------
--  Resolution
--  One catalogue, one decision per unit: the enabled entry that paints it, or
--  nil. nil is not "no colour" -- it is "no entry paints this unit", so the name
--  keeps the base colour of its side (Allied.GetNameColor, below). An entry's
--  toggle therefore only ever colours.
-------------------------------------------------------------------------------
-- The enabled colour of one catalog key, or nil. A disabled entry paints nothing.
local function ColorOf(fp, key)
    local item = CATALOG_BY_KEY[key]
    if item and On(fp, item) then return EntryColor(fp, item) end
    return nil
end

-- A player's override: the first enabled relationship that matches. A player
-- you can attack never reaches here: that plate is the enemy system's.
local function PlayerColor(unit, fp)
    for i = 1, #PLAYER_ENTRIES do
        local item = PLAYER_ENTRIES[i]
        -- Entries without a matcher (the pets') answer their own branch below.
        -- The matcher (a unit API call) runs only for an entry that is on.
        if item.match and On(fp, item) and item.match(unit) then return EntryColor(fp, item) end
    end
    return nil
end

-- A negative reaction: unfriendly, hostile or hated, attackable or not. This is
-- the unit the Opposing Faction section is for: an unfriendly NPC shows a
-- Blizzard plate like a friendly one, so it resolves here rather than through
-- the enemy nameplates' own colours.
local function IsOpposing(unit)
    local reaction = UnitReaction(unit, "player")
    return reaction ~= nil and reaction <= 3
end

-- A non-player's override, from the section its reaction belongs to: tapped
-- grey, then the opposing section for a negative reaction, then the friendly and
-- neutral one (an escort in combat, a plain NPC, a neutral).
local function NPCColor(unit, fp)
    local reaction = UnitReaction(unit, "player")
    if not reaction then return nil end
    if reaction <= 3 then
        local item = CATALOG_BY_KEY.HOSTILE_NPC_STANDARD
        if not On(fp, item) then return nil end
        -- A tapped unit keeps the base's desaturated grey: every tapped unit is
        -- attackable, so its plate is the enemy nameplates' and never reaches
        -- this palette.
        if UnitIsTapDenied and UnitIsTapDenied(unit) then return nil end
        return EntryColor(fp, item)
    end
    if reaction >= 5 then
        -- The combat test only while the escort entry is on.
        if On(fp, CATALOG_BY_KEY.FRIENDLY_NPC_ESCORT)
           and UnitAffectingCombat and UnitAffectingCombat(unit) then
            local r, g, b = ColorOf(fp, "FRIENDLY_NPC_ESCORT")
            if r then return r, g, b end
        end
        return ColorOf(fp, "FRIENDLY_NPC_STANDARD")
    end
    return ColorOf(fp, "NEUTRAL_NPC_PASSIVE")
end

-- The colour a player shows for its flag state, i.e. exactly what the owner's own
-- name takes: the PvP Flagged or Unflagged Players swatch when that entry is on,
-- else Blizzard's own friendly player colour (7788FF). UnitIsPVP answers for a
-- pet with its owner's flag, so a pet never needs to know who owns it -- which is
-- also why the group and guild entries are not consulted here: they answer for a
-- pet too, and a pet must never wear a guild's colour its owner was never given.
local PLAYER_DEFAULT_R, PLAYER_DEFAULT_G, PLAYER_DEFAULT_B = 0.467, 0.533, 1.00
local function FlaggedColor(unit, fp)
    -- The flag is read only while one of its two entries can paint.
    if On(fp, CATALOG_BY_KEY.FRIENDLY_PLAYER_PVP) or On(fp, CATALOG_BY_KEY.FRIENDLY_PLAYER_UNFLAGGED) then
        local key = IsPvPFlagged(unit) and "FRIENDLY_PLAYER_PVP" or "FRIENDLY_PLAYER_UNFLAGGED"
        local r, g, b = ColorOf(fp, key)
        if r then return r, g, b end
    end
    return PLAYER_DEFAULT_R, PLAYER_DEFAULT_G, PLAYER_DEFAULT_B
end

-- A pet's override, in the order the palette reads: its own row first when that
-- row is on; otherwise the colour of the unit that controls it. A player's pet
-- takes the colour its owner's flag state takes (FlaggedColor); anything else it
-- would have reached is an unfriendly pet outside the enemy nameplates' own, and
-- the NPC section answers for that one.
local function PetColor(unit, fp)
    -- Only a player's pet reaches here (Allied.IsPet), so its row is the player
    -- relationships' one.
    local r, g, b = ColorOf(fp, "PET_MINION_FRIENDLY")
    if r then return r, g, b end
    -- A player's pet only inherits while it is friendly: an attackable pet's plate
    -- is the enemy nameplates' and never reaches this palette, so the flag colours
    -- of the friendly side must not be able to paint one.
    if UnitPlayerControlled(unit) and not IsOpposing(unit) then return FlaggedColor(unit, fp) end
    return NPCColor(unit, fp)
end

-- The override colour for a unit, or nil when no entry paints it.
function Allied.GetOverrideColor(unit, fp)
    if not unit or not UnitExists(unit) then return nil end
    fp = fp or FP()
    if not fp then return nil end
    if UnitIsPlayer(unit) then return PlayerColor(unit, fp) end
    if Allied.IsPet(unit) then return PetColor(unit, fp) end
    return NPCColor(unit, fp)
end

-- Whether any player override can fire: the cheap "does anything here paint"
-- probe for the name-only text path's re-stamp test. The pets' entry has no
-- matcher -- it paints pet plates, never a player's -- so it is not asked.
function Allied.HasPlayerOverride(fp)
    if not fp then return false end
    for i = 1, #PLAYER_ENTRIES do
        local item = PLAYER_ENTRIES[i]
        if item.match and fp[item.on] == true then return true end
    end
    return false
end

-------------------------------------------------------------------------------
--  Options preview
-------------------------------------------------------------------------------
-- Each entry's eye previews it on one of the two samples at the top of the
-- Friendly Plates page: the players' entries (a player's pet included) on the
-- player sample, the NPCs' on the NPC sample. With no eye on, a sample paints the
-- plain unit in the colour the page passes it. An eye works only while its entry
-- is on and can paint (ns.NPO_AlliedPreviewOff on the Friendly page), so a sample
-- never shows a colour the live plates would not.
local PREVIEW_ENTRY = {
    FRIENDLY_PLAYER_FRIEND    = { sample = "player" },
    FRIENDLY_PLAYER_RECENT    = { sample = "player" },
    FRIENDLY_PARTY_RAID       = { sample = "player" },
    FRIENDLY_GUILD            = { sample = "player" },
    FRIENDLY_PLAYER_UNFLAGGED = { sample = "player" },
    FRIENDLY_PLAYER_PVP       = { sample = "player" },
    PET_MINION_FRIENDLY       = { sample = "player", pet = true },
    FRIENDLY_NPC_STANDARD     = { sample = "npc" },
    FRIENDLY_NPC_ESCORT       = { sample = "npc" },
    NEUTRAL_NPC_PASSIVE       = { sample = "npc" },
    HOSTILE_NPC_STANDARD      = { sample = "npc" },
}

-- Which sample an entry previews on ("player" / "npc"), and whether that sample
-- stands for a pet.
function Allied.PreviewTarget(key)
    local p = key and PREVIEW_ENTRY[key]
    if not p then return nil end
    return p.sample, p.pet == true
end

-- The colour an entry previews, or the sample's own base colour when no entry
-- is picked. This reads the same saved colour a live plate does.
function Allied.PreviewNameColor(key, baseForSample)
    local item = key and PREVIEW_ENTRY[key] and CATALOG_BY_KEY[key]
    if not item then return baseForSample.r, baseForSample.g, baseForSample.b end
    local r, g, b = EntryColor(FP(), item)
    if r then return r, g, b end
    return baseForSample.r, baseForSample.g, baseForSample.b
end

-- A hex colour escape for a colour, cached: the name-only text is rebuilt on
-- every plate add. Only ever called with our own (never secret) colours.
local hexR, hexG, hexB, hexStr
function Allied.HexEsc(r, g, b)
    if r ~= hexR or g ~= hexG or b ~= hexB then
        hexR, hexG, hexB = r, g, b
        hexStr = string.format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
    end
    return hexStr
end

-- The colour an NPC's or a pet's name keeps when no entry paints it, and the
-- bottom of every fallback in this file: the reaction colour, which is what
-- Blizzard itself paints such a plate.
local function ReactionBase(unit, fp)
    local reaction = UnitReaction(unit, "player")
    if reaction and reaction <= 3 then
        if UnitIsTapDenied and UnitIsTapDenied(unit) then return 0.55, 0.55, 0.55 end
        return 0.949, 0.549, 0.098
    elseif reaction == 4 then
        return 1.00, 1.00, 0.00
    end
    local c = fp and (fp.friendlyNPCNameColor or (ns.defaults and ns.defaults.friendlyNPCNameColor))
    if c then return c.r, c.g, c.b end
    return 0.00, 1.00, 0.00
end

-- The overlay's name colour: the entry that paints the unit, else the reaction
-- base -- so a pet with no entry and nothing to inherit is Blizzard's own colour.
-- Callers pass NPCs and pets only, the units EllesmereUI's name-only overlay
-- draws: a friendly PLAYER's name is coloured by NameOnlyEsc from
-- GetOverrideColor above (Name Color, else the class colour via the CVar), never
-- from here.
function Allied.GetNameColor(unit)
    local fp = FP()
    if not fp then return 0, 1, 0 end
    local r, g, b = Allied.GetOverrideColor(unit, fp)
    if r then return r, g, b end
    return ReactionBase(unit, fp)
end

-- A pet's owner line colour: the pet's own name colour when Match Pet Name Color
-- is on (a pet takes no class colour, so this is the same colour its name takes),
-- else the Owner Text Color swatch, whose alpha is what sets the line apart from
-- the name above it.
function Allied.GetPetOwnerColor(unit)
    local fp = FP()
    local c = (fp and fp.friendlyPetOwnerColor) or (ns.defaults and ns.defaults.friendlyPetOwnerColor)
    local alpha = (c and c.a) or 1
    if fp and fp.friendlyPetOwnerMatchNameColor == true then
        local r, g, b = Allied.GetNameColor(unit)
        return r, g, b, alpha
    end
    if c then return c.r, c.g, c.b, alpha end
    return 1, 1, 1, alpha
end

-- The subtitle under the overlay's name: the name's own colour when Match NPC
-- Name Color is on, else the Title Color swatch's. Callers pass the colour the
-- name actually takes on their own plate (the overlay's GetNameColor, the health
-- bar plate's bar & name colour), so Match matches the line above it in either
-- friendly style. The configured alpha is what sets the subtitle apart.
function Allied.GetTitleColor(unit, nameR, nameG, nameB)
    local fp = FP()
    local c = (fp and fp.friendlyNPCTitleColor) or (ns.defaults and ns.defaults.friendlyNPCTitleColor)
    local alpha = (c and c.a) or 1
    if fp and fp.friendlyNPCTitleMatchNameColor == true then
        if nameR then return nameR, nameG, nameB, alpha end
        local r, g, b = Allied.GetNameColor(unit)
        return r, g, b, alpha
    end
    if c then return c.r, c.g, c.b, alpha end
    return 0.00, 1.00, 0.00, alpha
end
