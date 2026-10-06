if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Actions.lua
--
--  Dynamic rez, the usability filter, ResolveAction, FireInsecure and what
--  a slot shows: icon, spell id, cooldown, count, usability.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local tonumber, type, select = tonumber, type, select
local GetCursorInfo = GetCursorInfo
local InCombatLockdown = InCombatLockdown

local ChildIndex, P, QUESTION_MARK = I.ChildIndex, I.P, I.QUESTION_MARK
local ReadPalette, CycleNext, CycleSteps = I.ReadPalette, I.CycleNext, I.CycleSteps
local MARKER_NAMES, MarkerIcon = I.MARKER_NAMES, I.MarkerIcon
local RANDOM_FAVORITE_MOUNT, SpecIndexFor = I.RANDOM_FAVORITE_MOUNT, I.SpecIndexFor
local WORLD_MARKER_ENGINE, SetUsableSlots = I.WORLD_MARKER_ENGINE, I.SetUsableSlots

-- Assigned below with the usability filter; EllesmereUIQuickdraw.lua holds
-- the forward declaration ChildSlots reads through.
local UsableSlots

-------------------------------------------------------------------------------
--  Dynamic Rez
--
--  One entry that is whichever resurrection spell this character has, so a
--  palette shared between a druid, a priest and a death knight carries the rez
--  once rather than three times over with two of them dead on every character.
--
--  single and group are the out-of-combat casts; battle is the in-combat one.
--  The same kit the raid frames' Dynamic Rez click-cast binding uses
--  (EUI_RaidFrames_ClickCast.lua:90), kept as a copy of the table rather than
--  read across from it: that is a separate addon the user can switch off, and
--  an entry on a palette must not stop working when they do. The two lists have
--  to be changed together when a class gains or loses a rez.
--
--  One table rather than a local per entry point, and everything else scoped to
--  the do-block below. That is not tidiness: as one file the module's main
--  chunk sat within a handful of Lua's ceiling of 200 locals, and neither a
--  field nor a block-local costs one of them.
-------------------------------------------------------------------------------
local Rez = {}
do
local UnitExists, UnitIsFriend, UnitIsDeadOrGhost =
    UnitExists, UnitIsFriend, UnitIsDeadOrGhost

local REZ_BY_CLASS = {
    PRIEST      = { single = 2006,   group = 212036 },
    PALADIN     = { single = 7328,   group = 212056, battle = 391054 },
    SHAMAN      = { single = 2008,   group = 212048 },
    DRUID       = { single = 50769,  group = 212040, battle = 20484 },
    MONK        = { single = 115178, group = 212051 },
    EVOKER      = { single = 361227, group = 361178 },
    DEATHKNIGHT = { battle = 61999 },
    WARLOCK     = { battle = 20707 },
}

-- battle, single, group for this character, any of them nil. Filtered by what
-- is actually in the spellbook, because the macro below picks a branch by
-- CONDITION rather than by knowledge: a /cast line naming a spell the character
-- has not got is a branch that matches and then casts nothing, which would eat
-- the fallback the next branch was there to be.
--
-- Not cached, and deliberately so. What is known moves with talents --
-- Intercession is a holy paladin's -- and it is also simply WRONG for a moment
-- at login, while the spellbook is still cold. A cache would latch that empty
-- answer and hold it until something invalidated it, which is a worse failure
-- than the reads it saves: three spellbook lookups, on a path that runs once
-- per palette open rather than per frame. See AdvanceLiveIcons for the one that
-- does run per frame.
--
-- The macro this feeds is written at push time, and SPELLS_CHANGED already
-- requests a push for the usability filter -- so a talent swap, a spec change,
-- levelling into a rez and the spellbook warming up after login all rebuild it
-- with no registration of its own.
local function RezKit()
    local _, class = UnitClass("player")
    local kit = class and REZ_BY_CLASS[class]
    if not kit then return nil end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local function Known(id)
        if not id then return nil end
        if C_SpellBook.IsSpellInSpellBook and bank
           and not C_SpellBook.IsSpellInSpellBook(id, bank, true) then
            return nil
        end
        return id
    end
    return Known(kit.battle), Known(kit.single), Known(kit.group)
end

-- A corpse worth casting the single-target rez at. UnitIsDeadOrGhost rather
-- than UnitIsDead, to agree with the macro's [dead]: that conditional is true
-- for a player who has released as well, and a released player is exactly who
-- needs resurrecting.
--
-- Identity APIs can answer SECRET booleans in restricted content, and this
-- runs EVERY FRAME from IconState while a menu holding a live-icon entry is
-- open -- truthiness on a secret throws, and a throw here storms the whole
-- OnUpdate. Every read is issecretvalue-guarded FIRST and a secret fails to
-- false: an unknowable corpse keeps the current branch, and the next
-- readable frame corrects the picture.
function Rez.HasDeadTarget()
    local exists = UnitExists("target")
    if issecretvalue(exists) or not exists then return false end
    local friend = UnitIsFriend("player", "target")
    if issecretvalue(friend) or not friend then return false end
    local dead = UnitIsDeadOrGhost("target")
    if issecretvalue(dead) or not dead then return false end
    return true
end

-- Which spell the entry would cast RIGHT NOW, for the icon and the live state
-- beneath it. Display only -- the macro decides again at fire time and the game
-- evaluates its conditionals then -- so this exists to keep the picture honest,
-- and its branch order has to match Rez.MacroText's exactly or the palette shows
-- one spell and casts another.
function Rez.SpellNow()
    local battle, single, group = RezKit()
    -- A class whose only rez is the battle one casts it in every state, which
    -- is what the bare macro line below does for the same case.
    if not (single or group) then return battle end
    if battle and InCombatLockdown() then return battle end
    if single and Rez.HasDeadTarget() then return single end
    return group or single
end

-- The macro a Dynamic Rez entry fires, or nil for a character with no rez at
-- all. One /cast with a fallback chain rather than a line each: the chain
-- attempts exactly ONE cast -- the first branch whose condition holds -- where
-- separate lines would each try in turn and the second would land on "another
-- action is in progress".
function Rez.MacroText()
    local battle, single, group = RezKit()
    local Name = C_Spell.GetSpellName
    if not Name then return nil end

    local parts = {}
    local function Add(cond, id)
        -- By NAME: /cast resolves against the localized one, and a hardcoded
        -- English name would fail silently on every other client.
        local name = id and Name(id)
        if name then parts[#parts + 1] = cond .. name end
    end

    -- [combat] only when there is something after it to be the out-of-combat
    -- answer. A death knight or a warlock, whose only rez IS the battle one,
    -- would otherwise cast nothing out of combat -- where that spell works
    -- perfectly well.
    Add((single or group) and "[combat] " or "", battle)
    -- Not a safety check: a corpse is a rez's only valid target, so there is no
    -- exists/nodead here the way there is on an ordinary cast. This condition is
    -- how the single-target spell is chosen over the group one.
    Add("[@target,help,dead] ", single)
    -- Bare, and last: the group rez takes no target, so it is the honest answer
    -- to "none of the above".
    --
    -- Falling back to the single one when there is no group rez -- a character
    -- still levelling into it -- is what keeps this line in step with
    -- Rez.SpellNow, which ends on the same `group or single`. Without the
    -- fallback the macro has no unconditional branch at all, and the entry
    -- draws the single rez, tints it usable and casts nothing. Attempting it
    -- and being told there is no target is the same answer the spell gives from
    -- an action bar, and it matches the picture.
    Add("", group or single)

    if #parts == 0 then return nil end
    return "/cast " .. table.concat(parts, "; ")
end

-- Does this character's class have a resurrection spell at all? The picker asks
-- so it can leave the entry out for a class that has none -- an entry that
-- could never do anything is worse than no entry. By CLASS rather than by what
-- is currently in the spellbook: a paladin who has not taken Intercession still
-- has Redemption, and a druid at level 10 will have Rebirth soon enough.
function ns.HasRezKit()
    local _, class = UnitClass("player")
    return (class and REZ_BY_CLASS[class]) ~= nil
end
end

-- The filtered answers, one per palette table. Wiped ONLY at the top of
-- PushAllPalettes: the memo is what keeps the drawn menu and the pushed
-- secure attributes reading the SAME list even when the spellbook shifts
-- between the push and the open (a pet swap mid-fight, say) -- usability is
-- allowed to go stale until the next push rather than ever disagreeing with
-- what a cell index fires. Every input that can change an answer lands here
-- through that same wipe: SPELLS_CHANGED and UPDATE_MACROS request a push,
-- every slot edit and the toggle itself request one through Refresh, class
-- and spec-list are fixed for the session, and a profile switch hands out
-- different palette tables (weak keys let the old ones go).
local usableMemo = setmetatable({}, { __mode = "k" })

-- KnownForm, SpellKnownHere and SlotUsable are private to UsableSlots, and
-- are scoped so they cost no main-chunk local: as one file the module's main
-- chunk was at Lua's ceiling of 200 locals, and merging two features into it
-- went over. usableMemo stays outside the block -- PushAllPalettes wipes it.
do
-- Is this one spell id in either of this character's books, player or pet?
local function KnownForm(sid)
    return (sid and sid > 0)
        and (IsPlayerSpell(sid)
             or (C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
                 and C_SpellBook.IsSpellKnownOrInSpellBook(sid)))
        or false
end

-- Whether this character's books hold the spell in ANY of its forms: the
-- stored id, its talent override, and its base form. Generous on purpose --
-- hiding a castable entry is a worse failure than drawing a dead one, so
-- every form is checked before answering no, and a malformed id answers yes
-- and leaves the slot to render as the placeholder it always was.
local function SpellKnownHere(id)
    if type(id) ~= "number" or id <= 0 then return true end
    if KnownForm(id) then return true end
    local ovr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
        and C_SpellBook.FindSpellOverrideByID(id)
    if ovr ~= id and KnownForm(ovr) then return true end
    local base = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(id)
    return base ~= id and KnownForm(base)
end

-- Can this character do anything with the slot? Only the kinds that resolve
-- against one character's own kit are tested -- another class's
-- specialization, a profession position this character does not reach, a
-- spell no book here holds, a macro this character does not have, a
-- resurrection this class has none of. Everything else (items, toys,
-- mounts, pets, markers, nested menus) is account-wide or self-resolving
-- and stays.
local function SlotUsable(slot)
    local k = slot and slot.kind
    if k == "spec" or k == "dynamicspec" then
        return SpecIndexFor(slot) ~= nil
    elseif k == "dynamicprofession" then
        return ns.ProfessionSpellFor(slot) ~= nil
    elseif k == "spell" then
        return SpellKnownHere(tonumber(slot.id))
    elseif k == "macro" then
        return GetMacroInfo(slot.name or slot.id) ~= nil
    elseif k == "outfit" then
        return ns.OutfitInfo(slot) ~= nil
    elseif k == "panel" then
        -- The one kind whose availability is the CLIENT's rather than the
        -- character's: Housing arrived in 12.0 and the Shop is not in every
        -- region's build. Hidden by the same setting all the same -- an entry
        -- that can never open anything is one to keep off the ring.
        return ns.PanelAvailable(ns.PanelDef(slot))
    elseif k == "dynamicrez" then
        -- By CLASS rather than by what is in the book right now, which is what
        -- ns.HasRezKit answers: a paladin who has not taken Intercession still
        -- has Redemption, and a druid too low for Rebirth will have it. Hiding
        -- the entry on those would take it away from the character it is FOR.
        -- A mage carrying the shared menu is the case this catches, and it is
        -- the one the entry's own note names.
        return ns.HasRezKit()
    end
    return true
end

-- The entries of the palette this character can use ("Hide Unusable
-- Entries"). A view, never a mutation: returns the stored array itself while
-- nothing is filtered or the setting is off, and a fresh dense array
-- otherwise -- the stored slots keep every entry for the characters that CAN
-- use them.
function UsableSlots(palette, p)
    local slots = palette and palette.slots
    if not slots then return slots end
    if p and p.hideUnusable == false then return slots end
    local memo = usableMemo[palette]
    if memo then return memo end
    local out
    for i = 1, #slots do
        if not SlotUsable(slots[i]) then
            if not out then
                out = {}
                for j = 1, i - 1 do out[j] = slots[j] end
            end
        elseif out then
            out[#out + 1] = slots[i]
        end
    end
    usableMemo[palette] = out or slots
    return out or slots
end
end
SetUsableSlots(UsableSlots)

-- kind -> attribute triple for the secure button, plus an optional 4th value:
-- a sibling attribute key that must be cleared because the same action type
-- would otherwise read it in preference. Returns nil for the kinds with no
-- secure action type at all (battlepet, the two spec kinds, the mounts), which
-- FireInsecure handles instead.
--
-- p is the palette's appearance view, for the one kind whose action depends on
-- a setting rather than only on the slot (worldmarker). It is the view of the
-- palette being PUSHED, which for a nest's cells is the owner's -- the same
-- palette whose appearance draws them.
local function ResolveAction(slot, p)
    if not slot or not slot.kind then return nil end
    local k = slot.kind

    -- A palette opens entries; it never fires one. Returning nothing is what
    -- makes a release on the parent itself a cancel, which is the only sensible
    -- reading of "you stopped on the door rather than going through it".
    if k == "palette" then return nil end

    if k == "spell" then
        if type(slot.id) ~= "number" then return nil end
        return "spell", "spell", slot.id

    elseif k == "dynamicprofession" then
        -- Resolved to the CURRENT position's spell every time the
        -- attributes are written, then fired the same way any other spell
        -- slot is -- see ns.ProfessionSpellFor above for what makes the
        -- position current.
        local spellID = ns.ProfessionSpellFor(slot)
        if not spellID then return nil end
        return "spell", "spell", spellID

    elseif k == "item" then
        if type(slot.id) ~= "number" then return nil end
        return "item", "item", "item:" .. slot.id

    elseif k == "toy" then
        if type(slot.id) ~= "number" then return nil end
        return "toy", "toy", slot.id

    elseif k == "outfit" then
        local info = ns.OutfitInfo(slot)
        if not info then return nil end
        return "outfit", "outfit-index", info.playerFacingOutfitIndex

    elseif k == "macro" then
        -- Stored by name so reordering the macro list doesn't repoint the
        -- slot. RunMacro accepts a name, so the name is what we hand over.
        -- The 4th return clears the sibling key: type="macro" reads "macro"
        -- first and only falls through to "macrotext" when it is unset
        -- (SecureTemplates.lua:441). The direction that matters is therefore
        -- the other branch -- a macrotext slot must clear a stale "macro", or
        -- the earlier slot's macro name wins. This branch clears macrotext for
        -- symmetry, so neither key can outlive the slot that set it.
        local nameOrIndex = slot.name or slot.id
        if not nameOrIndex then return nil end
        return "macro", "macro", nameOrIndex, "macrotext"

    elseif k == "macrotext" then
        if type(slot.macrotext) ~= "string" or slot.macrotext == "" then return nil end
        return "macro", "macrotext", slot.macrotext, "macro"

    elseif k == "mount" then
        -- C_MountJournal.SummonByID is protected, so the mount is summoned
        -- through its own summon spell instead.
        --
        -- By NAME, not by id: SECURE_ACTIONS.spell routes a numeric value to
        -- CastSpellByID and a string to CastSpellByName
        -- (SecureTemplates.lua:387-395). Mount summon spells do not live in the
        -- spellbook, and CastSpellByID does nothing for them; CastSpellByName is
        -- the path a plain "/cast <mount>" macro takes, which does work.
        local mountName, spellID = nil, slot.spellID
        if slot.id then
            mountName, spellID = C_MountJournal.GetMountInfoByID(slot.id)
            spellID = slot.spellID or spellID
        end
        -- The spell's own name over the journal's display name: it is what
        -- CastSpellByName resolves against.
        local info = type(spellID) == "number" and C_Spell.GetSpellInfo(spellID)
        local castName = (info and info.name) or mountName
        if type(castName) ~= "string" or castName == "" then return nil end
        return "spell", "spell", castName

    elseif k == "raidtarget" then
        -- Fired as the /tm slash command rather than through
        -- SECURE_ACTIONS.raidtarget: that action reads TWO attributes, marker
        -- and action, and the firing end of the snippet pushes exactly one key
        -- per cell. The command reaches SetRaidTarget itself
        -- (SlashCommands.lua:1381-1406), and /tm 0 is its documented clear.
        --
        -- What makes that legal is the secure button running the macro, NOT
        -- anything about SetRaidTarget: it is protected, and refuses any call
        -- an addon makes from its own Lua. See the clearmarkers branch below,
        -- which was written on the opposite assumption and did not work.
        local id = tonumber(slot.id)
        if not id or id < 0 or id > 8 then return nil end
        return "macro", "macrotext", "/tm " .. id, "macro"

    elseif k == "clearmarkers" then
        -- SECURE_ACTIONS.raidtarget's own clear-all branch, which calls
        -- RemoveRaidTargets (SecureTemplates.lua:590-592). SetRaidTarget is
        -- documented AllowedWhenUntainted and is refused outright from an
        -- addon's own Lua -- the sweep this replaces raised
        -- ADDON_ACTION_FORBIDDEN on its first call -- so going through the
        -- secure button, which runs the action untainted, is the only route.
        --
        -- The ACTION rides in the ordinary key/value slot: raidtarget reads
        -- "marker" and "action", and the firing end of the snippet pushes one
        -- key per cell. clear-all is the one branch that never looks at
        -- "marker", so the single key can be spent on "action" instead.
        --
        -- It also clears more than the loop could: RemoveRaidTargets reaches
        -- marks on units the client cannot currently name, which no clear-all
        -- macro can. In a group it needs lead or assist, and quietly does
        -- nothing without them -- the same rule as marking itself.
        return "raidtarget", "action", "clear-all"

    elseif k == "worldmarker" then
        -- Same one-attribute reasoning as /tm above: /wm places a world
        -- marker, /cwm clears. Both take the ENGINE's marker number, so the
        -- stored icon position goes through the map.
        local id = tonumber(slot.id)
        if not id or id < 0 or id > 8 then return nil end
        if id == 0 then
            -- The /cwm handler compares its argument against the client's own
            -- ALL string (SlashCommands.lua:824-830), so that string is what
            -- gets baked -- a hardcoded "all" would fail on a localized client.
            return "macro", "macrotext", "/cwm " .. (ALL or "all"), "macro"
        end
        if p == nil or p.worldMarkerToggle ~= false then
            -- Toggle World Markers. Not a macro: /wm is PlaceRaidMarker with
            -- no test at all (SlashCommands.lua:820), and no macro conditional
            -- reports a world marker as down. SECURE_ACTIONS.worldmarker does
            -- the test itself (SecureTemplates.lua:602-618), and still costs
            -- the ONE attribute a cell may spend -- it reads "marker" and
            -- "action", and "action" falls back to "toggle" when unset, which
            -- the snippet's clear guarantees it is.
            --
            -- Placement is unchanged: neither Blizzard nor /wm passes a unit
            -- token, so the marker still lands under the cursor.
            return "worldmarker", "marker", WORLD_MARKER_ENGINE[id]
        end
        -- Repeating ONE marker fast stalls here, where cycling eight does not:
        -- the game holds each marker on its own cooldown -- about four spammed
        -- presses -- and answers "You can't do that right now". Nothing to do
        -- with this module: a plain /wm macro alone does it.
        --
        -- Clearing before placing, the way retail's own marker button does
        -- (Mainline/Blizzard_CompactRaidFrameManager.lua:1065-1066), does not
        -- buy anything from a macro: the /cwm spends the cooldown and the /wm
        -- behind it lands inside the window, which reads as a toggle. Blizzard
        -- gets away with it by calling both C functions straight from an
        -- OnClick, which is not a route an addon has.
        return "macro", "macrotext", "/wm " .. WORLD_MARKER_ENGINE[id], "macro"

    elseif k == "dynamicrez" then
        -- Fired as macro text, which is what makes it dynamic in the way that
        -- matters: the attributes are written out of combat, and a rez has to
        -- pick its branch DURING the fight. The game evaluates [combat] when
        -- the macro runs, so a menu pushed before the pull still casts the
        -- battle rez in it. A resolved spellID could not do that.
        local text = Rez.MacroText()
        if not text then return nil end
        return "macro", "macrotext", text, "macro"

    elseif k == "panel" then
        -- "/click <micro button>", so the panel opens on Blizzard's own click
        -- rather than on ours: the macro runs untainted from the secure
        -- button, and a panel opened by an addon's Lua carries that addon's
        -- taint into everything it draws. The panels with no micro button
        -- answer nothing here and go to FireInsecure instead.
        local text = ns.PanelMacro(ns.PanelDef(slot))
        if not text then return nil end
        return "macro", "macrotext", text, "macro"

    elseif k == "cycleraidtarget" or k == "cycleworldmarker" then
        -- The step the position on the slot says is up. The snippet overwrites
        -- this with its own answer on every press -- see the eqdCycN branch --
        -- so what is pushed here is only what the entry would fire if the
        -- cycle attributes went missing: the right marker, just not advancing.
        --
        -- Deliberately NOT affected by Toggle World Markers, though the step
        -- machinery would carry a marker number as readily as a macro. A cycle
        -- is a run THROUGH the eight, and a step that picks its marker back up
        -- because that one happened to be down already breaks the run: the
        -- press that should have placed the circle places nothing, and the
        -- position still advances. Placing every time is the only behavior
        -- that keeps a cycle predictable.
        local steps = CycleSteps(k)
        return "macro", "macrotext", steps[CycleNext(slot)], "macro"
    end

    return nil
end
ns.ResolveAction = ResolveAction

-- The kinds with no secure action type at all. None of these calls is
-- protected -- summoning a battle pet or a mount and changing specialization
-- are all ordinary API -- so all are safe straight from PostClick.
--
-- WHICH cell reaches here is the snippet's answer rather than the live view's
-- selection; see OnPostClick.
local function FireInsecure(slot)
    if not slot then return end
    if slot.kind == "battlepet" and slot.guid and C_PetJournal then
        C_PetJournal.SummonPetByGUID(slot.guid)

    elseif slot.kind == "randommount" and C_MountJournal then
        -- The Mount Journal button's own call
        -- (Blizzard_MountCollection.lua:998); 0 means "a random favorite".
        -- Refused by the game itself in combat, where no mount can be
        -- summoned anyway.
        C_MountJournal.SummonByID(0)

    elseif slot.kind == "lastmount" and C_MountJournal then
        -- The same call with the mount the player last rode, tracked rather
        -- than stored on the slot -- the whole point of the entry is that it
        -- changes on its own. Nothing tracked yet (a fresh profile, or a
        -- session where the player has not mounted) falls back to the random
        -- favorite rather than doing nothing: an entry that answers a press
        -- with silence reads as broken.
        local pf = P()
        local id = pf and pf.lastMountID
        C_MountJournal.SummonByID(type(id) == "number" and id or 0)

    elseif slot.kind == "panel" then
        -- Only the panels ResolveAction had no micro button for. Out of combat
        -- only, which is the game's rule rather than ours: an insecure
        -- ShowUIPanel is refused in a fight, and it refuses it quietly.
        ns.PanelFire(ns.PanelDef(slot))

    elseif slot.kind == "spec" or slot.kind == "dynamicspec" then
        local index = SpecIndexFor(slot)
        -- Refused in combat by the game itself, with its own error message.
        -- Nothing to defer to PLAYER_REGEN_ENABLED: a spec change the user
        -- asked for mid-fight and got minutes later is not what they meant.
        if index then C_SpecializationInfo.SetSpecialization(index) end
    end
end

-- The fileID behind the question mark path above. GetMacroInfo answers a fileID
-- rather than a path, so the two cannot be compared without this.
local QUESTION_MARK_ID = GetFileIDFromPath and GetFileIDFromPath(QUESTION_MARK)

-- The icon for what a macro would fire RIGHT NOW, or nil to fall back to the
-- icon the macro was saved with.
--
-- A macro's conditionals are evaluated when it runs, so a [mod] macro fires a
-- different spell depending on what is held at the release -- and the palette
-- has to draw the branch it is going to take, or it shows one picture and casts
-- the other. GetMacroSpell and GetMacroItem answer the current branch.
--
-- ONLY for a macro sitting on the dynamic "?" icon, which is what the caller's
-- question-mark test is for. A macro the player gave a real icon keeps it, the
-- way Blizzard's own action buttons keep it: that icon is a choice, and
-- resolving over the top of it would take the choice away. It also makes this
-- safe whichever of the two things GetMacroInfo does -- return the saved icon,
-- or resolve the dynamic one itself -- because in the resolving case a "?" macro
-- never reaches here with a question mark to begin with.
--
-- By macro NAME resolved to an index, which is the pairing the rest of the suite
-- settled on (EllesmereUICooldownManager.lua:6986-6992): the id a macro action
-- carries is not reliably a macro index, and these two want the index.
local function MacroIcon(nameOrIndex)
    if not nameOrIndex then return nil end
    local index = nameOrIndex
    if type(index) ~= "number" then index = GetMacroIndexByName(index) end
    if not index or index <= 0 then return nil end

    local spellID = GetMacroSpell(index)
    if spellID then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.iconID then return info.iconID end
    end

    -- An item branch answers no spell. The link, not the name: it carries the
    -- itemID, and a name would have to be looked up again to get one.
    --
    -- The existence guard is a statement rather than `GetMacroItem and
    -- GetMacroItem(index)` -- an `and` expression is truncated to ONE value, so
    -- that form would drop the link and leave every item macro on its saved
    -- icon. Same trap SlotDisplay's own note names, one function below.
    if GetMacroItem then
        local _, link = GetMacroItem(index)
        if link then
            local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
            if icon then return icon end
        end
    end

    -- Neither -- a macro that only marks, targets or emotes. The saved icon is
    -- the honest answer for those, and it is the one the caller falls back to.
    return nil
end

-- icon, name for display. Never returns nil for icon so a slot whose target
-- has been removed from the game still renders as an occupied slot.
--
-- Note the deliberate absence of `C_Foo and C_Foo.Bar(x)` guards here: an
-- `and` expression is truncated to ONE value, which would silently drop every
-- return past the first and leave every icon nil.
local function SlotDisplay(slot)
    if not slot or not slot.kind then return nil, nil end
    local k = slot.kind

    if k == "spell" then
        local info = C_Spell.GetSpellInfo(slot.id)
        if info then return info.iconID or QUESTION_MARK, info.name end

    elseif k == "item" then
        if type(slot.id) ~= "number" then return QUESTION_MARK, slot.name end
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(slot.id)
        local name = C_Item.GetItemInfo(slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "toy" then
        if type(slot.id) ~= "number" then return QUESTION_MARK, slot.name end
        local _, name, icon = C_ToyBox.GetToyInfo(slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "outfit" then
        local info = ns.OutfitInfo(slot)
        return ns.OutfitIcon(info) or ns.OutfitIcon(slot) or QUESTION_MARK,
               (info and info.name) or slot.name or "Outfit"

    elseif k == "macro" then
        local nameOrIndex = slot.name or slot.id
        local name, icon = GetMacroInfo(nameOrIndex)
        -- A question mark here means the macro carries no icon of its own, so
        -- what it is about to fire is the only thing left to draw. Anything else
        -- is an icon the player picked, and it stands. See MacroIcon.
        if icon == nil or icon == QUESTION_MARK or icon == QUESTION_MARK_ID then
            icon = MacroIcon(nameOrIndex) or icon
        end
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "macrotext" then
        -- slot.icon may be a { atlas = ... } table (the Pings preset stores
        -- one verbatim); SetIconTexture/ApplyIconCrop render both forms.
        return slot.icon or QUESTION_MARK, slot.name or "Macro"

    elseif k == "dynamicrez" then
        -- The spell it would cast, not a fixed emblem: the entry is worth
        -- having because it changes, and one picture over three different casts
        -- would hide the only thing it has to say.
        local id = Rez.SpellNow()
        local info = id and C_Spell.GetSpellInfo(id)
        if info then return info.iconID or QUESTION_MARK, info.name end
        -- A character with no resurrection spell at all -- the mage carrying
        -- the shared palette. Drawn as an occupied slot under its own name, the
        -- same as a spec this character does not have.
        return QUESTION_MARK, "Dynamic Rez"

    elseif k == "mount" then
        if type(slot.id) ~= "number" then return QUESTION_MARK, slot.name end
        local name, _, icon = C_MountJournal.GetMountInfoByID(slot.id)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "lastmount" then
        -- Whatever is tracked right now, so the entry shows the mount it would
        -- actually summon. Before anything is tracked it shows what it would
        -- fall back to, which is the random favorite (see FireInsecure), under
        -- a name that says what the entry IS rather than what it is standing
        -- in for.
        local pf = P()
        local id = pf and pf.lastMountID
        if type(id) == "number" then
            local name, _, icon = C_MountJournal.GetMountInfoByID(id)
            if name then return icon or QUESTION_MARK, name end
        end
        local info = C_Spell.GetSpellInfo(RANDOM_FAVORITE_MOUNT)
        return (info and info.iconID) or QUESTION_MARK, "Last Used Mount"

    elseif k == "randommount" then
        local info = C_Spell.GetSpellInfo(RANDOM_FAVORITE_MOUNT)
        -- The client's own caption for the Mount Journal button, so the entry
        -- reads the same on a localized client as the thing it summons.
        return (info and info.iconID) or QUESTION_MARK,
               MOUNT_JOURNAL_SUMMON_RANDOM_FAVORITE_MOUNT
                   or (info and info.name) or "Random Favorite Mount"

    elseif k == "spec" or k == "dynamicspec" then
        local index = SpecIndexFor(slot)
        if index then
            -- Both kinds draw the specialization they would switch to, which
            -- is the whole point of the dynamic one: the icon and the name are
            -- this character's, so a palette carried to another class arrives
            -- showing that class's specs rather than the owner's.
            local _, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(index)
            return icon or QUESTION_MARK, name or slot.name
        end
        if k == "dynamicspec" then
            -- A position this class has not got: four on anything but a
            -- druid, three on a demon hunter. The entry names a seat rather
            -- than an occupant, so with no occupant to draw it says the seat.
            return QUESTION_MARK, ns.SpecPositionName(tonumber(slot.index))
        end
        -- A spec this character's class does not have. Its identity is still
        -- global -- the specID answers by itself -- so the editor and an
        -- unfiltered menu draw the real specialization, not a placeholder.
        local want = tonumber(slot.specID)
        if want and GetSpecializationInfoByID then
            local _, name, _, icon = GetSpecializationInfoByID(want)
            if icon or name then
                return icon or QUESTION_MARK, name or slot.name
            end
        end
        return QUESTION_MARK, slot.name

    elseif k == "dynamicprofession" then
        if slot.extra or slot.specialization then
            -- The ABILITY's own name and icon rather than the profession's:
            -- unlike the opener, these entries are distinct spells.
            local spellID = ns.ProfessionSpellFor(slot)
            if spellID then
                local info = C_Spell.GetSpellInfo(spellID)
                if info then return info.iconID or QUESTION_MARK, info.name or slot.name end
            end
        else
            local bookIndex = ns.ProfessionBookIndexFor(slot)
            if bookIndex then
                -- The profession's own name and icon, not the opener
                -- spell's -- the same skill icon its spellbook entry shows.
                local name, icon = GetProfessionInfo(bookIndex)
                return icon or QUESTION_MARK, name or slot.name
            end
        end
        -- An unavailable position, native extra, or specialization ability.
        -- Name the seat rather than an occupant, like an empty dynamicspec.
        return QUESTION_MARK, ns.ProfessionPositionName(
            tonumber(slot.index), slot.extra, slot.specialization)

    elseif k == "battlepet" then
        if type(slot.guid) ~= "string" then return QUESTION_MARK, slot.name end
        local _, _, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(slot.guid)
        return icon or QUESTION_MARK, name or slot.name

    elseif k == "raidtarget" then
        local id = tonumber(slot.id) or 0
        if id < 1 or id > 8 then
            return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Clear Target Marker"
        end
        return MarkerIcon(id), "Target Marker: " .. MARKER_NAMES[id]

    elseif k == "clearmarkers" then
        return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Clear All Target Markers"

    elseif k == "worldmarker" then
        local id = tonumber(slot.id) or 0
        if id < 1 or id > 8 then
            return "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Clear World Markers"
        end
        return MarkerIcon(id), "World Marker: " .. MARKER_NAMES[id]

    elseif k == "cycleraidtarget" or k == "cycleworldmarker" then
        -- Drawn as the marker the next press places, not as a fixed emblem: in
        -- a radial the icon is what the entry is picked by, and one that never
        -- changed while the action did would be worse than no entry at all.
        local id = CycleNext(slot)
        local what = (k == "cycleraidtarget") and "Target" or "World"
        return MarkerIcon(id), "Cycle " .. what .. " Marker: " .. MARKER_NAMES[id]

    elseif k == "panel" then
        -- The art is ours rather than the micro button's own: those atlases
        -- are the 32x40 shape of a micro button and would be stretched square
        -- by the icon a menu entry draws at.
        local def = ns.PanelDef(slot)
        if def then return def.icon, ns.PanelName(def) end
        -- A key from a newer version of the module, or one that has been
        -- retired. Drawn as an occupied slot, like every other unresolved kind.
        return QUESTION_MARK, slot.name or "Interface Panel"

    elseif k == "palette" then
        -- ReadPalette, not EnsurePalette: a nested parent is repainted from the
        -- steering path, which must not rewrite the profile's slot array.
        local palette = ReadPalette(ChildIndex(slot))
        -- Two choices before the fallback, narrowest first: this entry's own
        -- override, then the palette's first entry -- so a "Mounts" palette
        -- looks like a mount without anyone having to pick an icon for it.
        -- Only one level down: a first entry that is itself a palette would
        -- send this round its own loop.
        local icon = slot.icon
        local first = palette and palette.slots[1]
        if not icon and first and first.kind ~= "palette" then
            icon = SlotDisplay(first)
        end
        return icon or QUESTION_MARK,
               slot.name or (palette and palette.name) or "Action Menu"
    end

    return QUESTION_MARK, slot.name
end
ns.SlotDisplay = SlotDisplay

-- Cooldown source per kind. Returns start, duration, enable -- handed to
-- CooldownFrame_Set verbatim, never compared or arithmetic'd, so secret
-- cooldown values stay untouched.
-- Returns EITHER a duration object (spells, mounts) OR start, duration, enable
-- (items, toys). Two shapes because only spells have a secret-safe getter.
--
-- Spell cooldowns must not go through C_Spell.GetSpellCooldown: it is flagged
-- SecretWhenCooldownsRestricted (SpellDocumentation.lua:252), so once cooldowns
-- are restricted its startTime and duration come back as SECRET numbers. Our
-- execution is an addon's and therefore tainted, and CooldownFrame_Set opens with
-- `start > 0 and duration > 0` (Cooldown.lua:3) -- comparing a secret from
-- tainted execution throws. C_Spell.GetSpellCooldownDuration returns an opaque
-- duration object instead: it is AllowedWhenTainted, and it goes straight into
-- the widget C-side, so nothing here ever reads a secret.
--
-- Items keep the plain numeric path -- C_Item.GetItemCooldown carries no secret
-- flag and there is no duration-object equivalent for items.
--
-- The spellID an entry's live state is read from, for the kinds that HAVE one.
-- Dynamic entries answer the spell they resolve to right now, so their
-- cooldown describes the same spell as their icon and secure action.
local function SlotSpellID(slot)
    if not slot then return nil end
    if slot.kind == "spell" then
        return type(slot.id) == "number" and slot.id or nil
    elseif slot.kind == "dynamicrez" then
        return Rez.SpellNow()
    elseif slot.kind == "dynamicprofession" then
        return ns.ProfessionSpellFor(slot)
    end
    return nil
end

-- Display data the client only has once it has been ASKED for: GetSpellInfo
-- answers nothing for a spell whose data has not been loaded this session
-- (SpellDocumentation.lua:800-803), and the toy and item getters answer nothing
-- until their item has. A palette paints once per open, so an entry drawn ahead
-- of its data kept the question mark for the whole of that open, and the second
-- open was right only because the first one's failed lookup had fetched it.
-- Both ns-hosted for the reason ns.SetIconTexture is: as one file the module's
-- main chunk was at Lua 5.1's 200-local cap.
function ns.SlotDataReady(slot)
    if not slot then return true end
    local k = slot.kind

    if k == "spell" or k == "dynamicrez" or k == "dynamicprofession" then
        local id = SlotSpellID(slot)
        return not id or C_Spell.IsSpellDataCached(id)
    end

    -- A toy's id IS its itemID, so the two kinds share the one cache. An item's
    -- icon comes off the client's own table and is right either way; its NAME
    -- is what the load is for, and the hub caption reads that.
    if k == "item" or k == "toy" then
        return type(slot.id) ~= "number" or C_Item.IsItemDataCachedByID(slot.id)
    end

    -- Every other kind reads a client-side table -- the mount journal, the pet
    -- journal, the spec and profession lists -- and answers on the first ask.
    return true
end

-- Ask for it, and say whether the answer is still outstanding. Separate from the
-- test above because AdvancePendingIcons retests every frame and must not send
-- the request again with each one.
function ns.WarmSlot(slot)
    if ns.SlotDataReady(slot) then return false end
    if slot.kind == "item" or slot.kind == "toy" then
        C_Item.RequestLoadItemDataByID(slot.id)
    else
        C_Spell.RequestLoadSpellData(SlotSpellID(slot))
    end
    return true
end

local function SlotCooldown(slot)
    if not slot then return nil end
    local k = slot.kind
    if k == "spell" or k == "mount" or k == "dynamicrez"
       or k == "dynamicprofession" or k == "outfit" then
        local id
        if k == "mount" then
            -- No falling back to slot.id here: that is a mountID, and looking
            -- a mountID up as a spellID reports some unrelated spell's cooldown.
            id = slot.spellID or select(2, C_MountJournal.GetMountInfoByID(slot.id))
        elseif k == "outfit" then
            id = Constants.TransmogOutfitDataConsts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID
        else
            id = SlotSpellID(slot)
        end
        if id and C_Spell.GetSpellCooldownDuration then
            -- Parenthesised, so only the duration comes back: 12.1 returns a
            -- second value that would land in this function's `start` slot and
            -- hand a boolean to CooldownFrame_Set.
            return (C_Spell.GetSpellCooldownDuration(id))
        end
    elseif k == "item" or k == "toy" then
        if slot.id and C_Item.GetItemCooldown then
            return nil, C_Item.GetItemCooldown(slot.id)
        end
    end
    return nil
end

-- WHETHER an entry writes a number in its corner, and WHAT that number is --
-- deliberately two returns rather than one nilable value. Two things earn a
-- number: a stack of items, and a spell's charges.
--
-- The charge count must never be looked at, not even for truth or for nil.
-- C_Spell.GetSpellCharges is flagged SecretWhenCooldownsRestricted
-- (SpellDocumentation.lua:234), so currentCharges comes back a SECRET number
-- once restrictions are in effect, and touching one from tainted execution
-- throws -- the same wall the spell cooldown hit. So the caller is told
-- separately that there IS a count, and the count itself only ever reaches
-- SetText, which swallows a secret; Blizzard's own action button hands the
-- identical kind of value to the identical call (ActionButton.lua:810).
--
-- What is safe to test is the TABLE the call returns, which is not itself
-- secret: it comes back as nothing for a spell that has no charges at all.
--
-- Neither item call carries a secret flag, so those may be compared -- and
-- have to be, because a count only means something on a stackable item. A
-- Hearthstone writing "1" in its corner is noise.
local function SlotCount(slot)
    if not slot then return false end
    local k = slot.kind

    -- A battle rez is the charge-carrying spell this matters most for: how many
    -- are left is the whole question a raid asks of it.
    if k == "spell" or k == "dynamicrez" then
        local id = SlotSpellID(slot)
        if not id or not C_Spell.GetSpellCharges then return false end
        local charges = C_Spell.GetSpellCharges(id)
        if not charges then return false end
        return true, charges.currentCharges

    elseif k == "item" then
        if type(slot.id) ~= "number" then return false end
        -- Position 8 is the stack size. It is nil until the item's data has
        -- been cached, which costs at most the count on one open -- the
        -- palette repaints from scratch every time it is drawn.
        local stack = select(8, C_Item.GetItemInfo(slot.id))
        if not stack or stack <= 1 then return false end
        return true, C_Item.GetItemCount(slot.id)
    end

    return false
end

-- How an entry that CANNOT be fired right now is tinted, in the three states
-- an action button has always distinguished. The idle and selected tints are
-- multiplied through these, so an unusable entry still reads as selected while
-- saying why it would do nothing.
local USABILITY_TINT = {
    OUTOFRANGE = { 0.90, 0.20, 0.20, false },
    NOPOWER    = { 0.45, 0.45, 1.00, false },
    UNUSABLE   = { 0.45, 0.45, 0.45, true },
}

-- Which of those states an entry is in, or nil for an entry that is fine and
-- for a kind with nothing to say.
--
-- Every call here is secret-SAFE, and that was checked rather than assumed:
-- C_Spell.IsSpellUsable, C_Spell.IsSpellInRange, C_Item.IsUsableItem,
-- C_Item.ItemHasRange and C_Item.IsItemInRange all carry no
-- SecretWhenCooldownsRestricted flag in the generated documentation, unlike
-- the cooldown and charge getters two functions up. So these results may be
-- branched on. Secrecy is not protection, though: C_Item.IsItemInRange is
-- additionally a PROTECTED call in combat and in protected instances against
-- a unit the player cannot attack, so it sits behind the Range module's gate
-- below. Do not add a kind here without checking its getter both ways -- a
-- mount's usability, for one, has to come from the Mount Journal rather than
-- from its summon spell, which is not in the spellbook and answers unusable
-- for every mount.
--
-- Out of range OUTRANKS the other two, matching every action bar: a spell you
-- cannot reach is the thing to say first, and it is the state a step forward
-- fixes.
--
-- Macros, markers and palettes answer nil. A macro's usability is whatever its
-- body resolves to, which is not knowable from here, and tinting one gray on a
-- guess is worse than saying nothing.
--
-- Toys also answer nil. A toy is not a bag item, so C_Item.IsUsableItem says
-- unusable for every toy a player owns, and graying the whole Hearthstones
-- palette is exactly what that produced. The toy box itself draws no
-- usability tint -- Blizzard_ToyBox.lua desaturates only UNCOLLECTED toys --
-- and the cooldown swipe already tells the one thing a toy has to tell.
local function SlotUsability(slot)
    if not slot then return nil end
    local k = slot.kind

    if k == "spell" or k == "dynamicrez" then
        local id = SlotSpellID(slot)
        if not id then return nil end
        if C_Spell.IsSpellInRange(id) == false then return "OUTOFRANGE" end
        local usable, noPower = C_Spell.IsSpellUsable(id)
        if usable then return nil end
        return noPower and "NOPOWER" or "UNUSABLE"

    elseif k == "item" then
        if type(slot.id) ~= "number" then return nil end
        -- Range against the target is a PROTECTED query in combat and in
        -- protected instances when the target cannot be attacked; the Range
        -- module owns that rule. Skipped = no range tint, usability still applies.
        local allowed = EllesmereUI.ItemRangeChecksAllowed
        if C_Item.ItemHasRange(slot.id) and allowed and allowed("target")
           and C_Item.IsItemInRange(slot.id, "target") == false then
            return "OUTOFRANGE"
        end
        local usable, noPower = C_Item.IsUsableItem(slot.id)
        if usable then return nil end
        return noPower and "NOPOWER" or "UNUSABLE"

    elseif k == "outfit" then
        return InCombatLockdown() and "UNUSABLE" or nil
    end

    return nil
end

-- Build a slot table from whatever is on the cursor. Returns nil when the
-- cursor holds something the palette can't fire.
local function SlotFromCursor()
    local cursorType, a, b, c = GetCursorInfo()
    if not cursorType then return nil end

    if cursorType == "spell" then
        -- Position 2 is the spellbook SLOT, not the spell -- Blizzard's own
        -- comment says so at SharedUIPanelTemplates.lua:1823, where it reads
        -- select(4, GetCursorInfo()) for the id. No fallback to position 2:
        -- that would store a slot number as a spellID and silently create a
        -- slot that casts the wrong thing.
        if type(c) ~= "number" then return nil end
        return { kind = "spell", id = c }

    elseif cursorType == "item" then
        local itemID = tonumber(a)
        if not itemID then return nil end
        -- The Toy Box frame hands back cursorType "item", not "toy", so
        -- reclassify here to match what the search picker already stores.
        if PlayerHasToy(itemID) then
            return { kind = "toy", id = itemID }
        end
        return { kind = "item", id = itemID }

    elseif cursorType == "macro" then
        local name = GetMacroInfo(a)
        if not name then return nil end
        return { kind = "macro", id = a, name = name }

    elseif cursorType == "mount" then
        -- Position 2 is the mountID: Blizzard reads it exactly this way at
        -- SharedUIPanelTemplates.lua:1827. Guessing at other positions is
        -- unsafe here because display indices and mountIDs are both small
        -- integers, so a wrong guess resolves to a real but unrelated mount.
        local mountID = tonumber(a)
        if not mountID then return nil end
        local name, spellID = C_MountJournal.GetMountInfoByID(mountID)
        if not name then return nil end
        return { kind = "mount", id = mountID, spellID = spellID, name = name }

    elseif cursorType == "toy" then
        local itemID = tonumber(a)
        if not itemID then return nil end
        return { kind = "toy", id = itemID }

    elseif cursorType == "battlepet" then
        if not a then return nil end
        return { kind = "battlepet", guid = a }

    elseif cursorType == "outfit" then
        local info = ns.OutfitInfo(a)
        if not info then return nil end
        return { kind = "outfit", id = info.outfitID,
                 name = info.name, icon = ns.OutfitIcon(info) }
    end

    return nil
end
ns.SlotFromCursor = SlotFromCursor

I.FireInsecure, I.ResolveAction, I.Rez = FireInsecure, ResolveAction, Rez
I.SlotCooldown, I.SlotCount, I.SlotDisplay = SlotCooldown, SlotCount, SlotDisplay
I.SlotUsability, I.USABILITY_TINT, I.usableMemo = SlotUsability, USABILITY_TINT, usableMemo
I.UsableSlots = UsableSlots
I.broken = false
