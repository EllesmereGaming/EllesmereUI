if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Slots.lua
--
--  The slot model: cycling marker entries, spec positions, dynamic
--  professions, outfits and the interface panels.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local tonumber, type, select = tonumber, type, select
local tinsert = table.insert

-------------------------------------------------------------------------------
--  Slot model
--
--  A slot is { kind = <string>, ... }. Everything the secure button needs is
--  derived from the slot at click time by ResolveAction; everything the UI
--  needs is derived by SlotDisplay. Both are pure lookups over the stored
--  ids, so a slot never caches a stale icon or name across a patch.
-------------------------------------------------------------------------------

-- Both marker kinds store the ICON position: 1..8 in the star-to-skull order
-- every marker UI shows, 0 for the entry that clears instead of placing. The
-- engine numbers its WORLD markers differently, so the world kind maps the
-- stored position onto the engine's number before it names one.
--
-- The engine runs blue, green, purple, red, yellow, orange, silver, white --
-- square, triangle, diamond, cross, star, circle, moon, skull. Blizzard's
-- WORLD_RAID_MARKER_ORDER (Blizzard_CompactRaidFrameManager.lua:5-12) is the
-- same eight numbers listed SKULL to STAR, which is the order its dropdown
-- draws them in; read as though it ran star to skull it lands on the marker
-- mirrored about the middle.
local WORLD_MARKER_ENGINE = { 5, 6, 3, 2, 7, 1, 4, 8 }

local MARKER_NAMES = {
    "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull",
}

-------------------------------------------------------------------------------
--  Cycling marker entries
--
--  One entry that walks the eight markers instead of naming one: each press
--  places the next, star to skull and back to the star. It is the whole set in
--  a single slot, for a palette that has no room for nine.
--
--  The position last placed is kept on the slot, so the run continues across a
--  reload rather than restarting at the star. It is NOT what the press reads,
--  though: an insecure SetAttribute is refused in combat, which is exactly when
--  marking matters, so the secure snippet keeps the authoritative copy and
--  advances it itself. CyclePosBack hands the snippet's answer back here after
--  the press, and the push seeds the snippet from it again. Both ends derive
--  "next" from "last" the same way, so the icon can never advertise a marker
--  other than the one the press places.
-------------------------------------------------------------------------------
local CYCLE_N = 8

-- The macro text each step fires, in the order the entry runs through them.
-- Both cycles step through the eight ICON positions; the world one maps each
-- onto the engine's number exactly as a fixed world marker slot does. nil for
-- every kind that does not cycle, which is what marks a slot as one.
local function CycleSteps(kind)
    local out = {}
    if kind == "cycleraidtarget" then
        for i = 1, CYCLE_N do out[i] = "/tm " .. i end
    elseif kind == "cycleworldmarker" then
        for i = 1, CYCLE_N do out[i] = "/wm " .. WORLD_MARKER_ENGINE[i] end
    else
        return nil
    end
    return out
end

-- The icon position the NEXT press places. Derived from the stored one rather
-- than stored itself, so there is only ever one number to keep in step.
local function CycleNext(slot)
    local last = tonumber(slot and slot.cyclePos) or 0
    if last < 1 or last > CYCLE_N then last = 0 end
    return last % CYCLE_N + 1
end

-- The position the snippet advanced to, back onto the slot it belongs to, so
-- the next push and every icon drawn before it agree with what actually fired.
-- Called from the release; a cell that does not cycle answers nothing and
-- leaves the slot alone.
local function CyclePosBack(btn, idx, slot)
    if not btn or not idx or not slot then return end
    local pos = tonumber(btn:GetAttribute("eqdCycPos" .. idx))
    if pos and CycleSteps(slot.kind) then slot.cyclePos = pos end
end

-- "Summon Random Favorite Mount", used only to DRAW the entry -- its icon and
-- its localized name. Firing does not cast it: the spell is neither in the
-- spellbook nor a journal mount, so CastSpellByName resolves it to nothing
-- and the release fires nothing. The roll is made by
-- C_MountJournal.SummonByID(0), which is ordinary API -- the Mount Journal's
-- own button calls it straight from an insecure click handler
-- (Blizzard_MountCollection.lua:998) -- so the kind fires through
-- FireInsecure the way a battle pet does.
local RANDOM_FAVORITE_MOUNT = 150544

local function MarkerIcon(id)
    return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. id
end

-- The CURRENT index of the specialization a slot names, for both kinds that
-- name one. Either way, nil leaves the slot doing nothing.
--
-- A spec slot banks the specID, the same number on every character that has
-- that spec: the index is only a position in one character's list, so a
-- palette carried to an alt would otherwise point at somebody else's spec. A
-- dynamicspec slot banks the position instead, and means it -- the second on a
-- druid and the second on a warrior are both simply "the second one".
local function SpecIndexFor(slot)
    if not slot or not C_SpecializationInfo then return nil end
    local classID = select(3, UnitClass("player"))
    if not classID then return nil end
    local count = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0

    if slot.kind == "dynamicspec" then
        local i = tonumber(slot.index)
        if i and i >= 1 and i <= count then return i end
        return nil
    end

    local want = tonumber(slot.specID)
    if not want then return nil end
    for i = 1, count do
        if C_SpecializationInfo.GetSpecializationInfo(i) == want then return i end
    end
    return nil
end

-- What a dynamicspec entry is CALLED when it is being picked, and on the
-- character that cannot resolve it. Kept here rather than in the options page
-- so the picker row and the placeholder cannot drift apart.
--
-- On ns with no local alias, and called back through ns below: written when
-- the module was one file whose main chunk was at Lua's ceiling of 200 locals
-- (see UsableSlots), where a local here spent the last one.
ns.SpecPositionName = function(index)
    return EllesmereUI.Lf("Specialization %1$d", index or 0)
end

-------------------------------------------------------------------------------
--  Dynamic Profession: a dynamicprofession slot names a POSITION (1/2 = the
--  two primary professions in GetProfessions order, 3/4/5 = Cooking, Fishing,
--  Archaeology), resolved live to that profession's opener spell, or with
--  slot.extra its second non-passive spell. slot.specialization resolves the
--  first known specialization ability for Mining, Herbalism, or Skinning.
--  Unlearned positions and professions with no second ability resolve to nil
--  and go dark under Hide Unusable Entries. Resolvers live on ns (from the
--  200-local ceiling of the module as one file). SlotUsable, ResolveAction
--  and SlotDisplay share a memo per position and ability kind.
--  PushAllPalettes wipes it beside usableMemo; SPELLS_CHANGED covers the
--  learn/unlearn edge.
-------------------------------------------------------------------------------
do
    local cache = {}

    local function Resolve(slot)
        if not slot or slot.kind ~= "dynamicprofession" then return nil, nil end
        local i = tonumber(slot.index)
        if not i then return nil, nil end
        local key = i * 4 + (slot.extra and 1 or 0)
            + (slot.specialization and 2 or 0)
        local hit = cache[key]
        if hit then return hit.book, hit.spell end

        local prof1, prof2, arch, fish, cook = GetProfessions()
        local book
        if i == 1 then book = prof1
        elseif i == 2 then book = prof2
        elseif i == 3 then book = cook
        elseif i == 4 then book = fish
        elseif i == 5 then book = arch
        end

        -- Gathering specialization abilities live in general spellbook
        -- flyouts, outside the profession's own spellbook block.
        local spell
        if book then
            local _, _, _, _, numSpells, spellOffset, skillLine = GetProfessionInfo(book)
            if slot.specialization then
                -- Blizzard exposes each learned flyout and each profession's
                -- skill line, but no relationship between the two.
                local flyoutID
                if skillLine == 182 then flyoutID = 239       -- Herbalism
                elseif skillLine == 186 then flyoutID = 240   -- Mining
                elseif skillLine == 393 then flyoutID = 238   -- Skinning
                end
                if flyoutID then
                    local numSlots = select(3, GetFlyoutInfo(flyoutID))
                    for n = 1, (numSlots or 0) do
                        local spellID, _, isKnown = GetFlyoutSlotInfo(flyoutID, n)
                        if isKnown then spell = spellID; break end
                    end
                end
            else
                -- Nth non-passive spell in the profession block: 1 = opener,
                -- 2 = the profession's native extra action, when it has one.
                local which = slot.extra and 2 or 1
                local seen = 0
                for n = 1, (numSpells or 0) do
                    local info = C_SpellBook.GetSpellBookItemInfo(
                        n + (spellOffset or 0), Enum.SpellBookSpellBank.Player)
                    if info and info.spellID and not info.isPassive then
                        seen = seen + 1
                        if seen == which then spell = info.spellID; break end
                    end
                end
            end
        end

        cache[key] = { book = book, spell = spell }
        return book, spell
    end

    ns.ProfessionBookIndexFor = function(slot) return (Resolve(slot)) end
    ns.ProfessionSpellFor = function(slot) return (select(2, Resolve(slot))) end
    ns.WipeProfessionCache = function() wipe(cache) end
end

-- Picker / unresolved-placeholder name for a dynamicprofession position (the
-- ns.SpecPositionName counterpart): positions 1-2 by number, 3-5 by the
-- client's own skill name.
ns.ProfessionPositionName = function(index, extra, specialization)
    index = tonumber(index)
    local base
    if index == 3 then base = COOKING or "Cooking"
    elseif index == 4 then base = FISHING or "Fishing"
    elseif index == 5 then base = ARCHAEOLOGY or "Archaeology"
    else base = EllesmereUI.Lf("Profession %1$d", index or 0)
    end
    if specialization then
        return EllesmereUI.Lf("%1$s Specialization Ability", base)
    elseif extra then
        return EllesmereUI.Lf("%1$s Extra Ability", base)
    end
    return base
end

-- Store the stable outfitID; the secure action uses the reorderable index.
function ns.OutfitInfo(slot)
    local id = type(slot) == "table" and slot.id or slot
    local info = type(id) == "number" and C_TransmogOutfitInfo.GetOutfitInfo(id)
    return info and not info.isDisabled and info or nil
end

function ns.OutfitIcon(info)
    local icon = info and info.icon
    return icon ~= 0 and icon or nil
end

function ns.OutfitSlots()
    local out = {}
    for _, info in ipairs(C_TransmogOutfitInfo.GetOutfitsInfo() or {}) do
        if not info.isDisabled then
            out[#out + 1] = {
                kind = "outfit", id = info.outfitID, name = info.name,
                icon = ns.OutfitIcon(info) or { atlas = "poi-transmogrifier" },
            }
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  Interface panels: one entry per Blizzard panel, so the whole micro menu
--  fits on a ring and costs one keybind. A panel with a micro button fires as
--  "/click <button>", the click Blizzard's own menu makes: the macro runs
--  untainted from the secure button, where an addon opening the frame from its
--  own Lua taints what it draws (see MM_MICRO_BUTTON_NAMES in
--  EllesmereUIDataBars/Blocks/MicroMenu.lua). The five
--  with no button to click fire from FireInsecure, out of combat only.
-------------------------------------------------------------------------------
do
    -- Scoped, with the accessors on ns: written when the module was one file
    -- at Lua's ceiling of 200 main-chunk locals (see UsableSlots). The ".png"
    -- on each name is not optional -- the client only finds a PNG by its full
    -- filename.
    local ART = "Interface\\AddOns\\EllesmereUI\\media\\micromenu\\"

    -- button: the micro button to click; a LIST is tried in order, since the
    --   spellbook button was renamed when talents and the spellbook merged.
    -- fire: the toggle for a panel with no button, called from FireInsecure.
    -- label: the client's own caption, by GLOBAL NAME rather than by value so
    --   no English one is baked in; first that answers wins, `default` last.
    -- minor: left out of the preset menu. The Shop and Customer Support are
    --   the two a ring is worth the least; the preset stays at the sixteen a
    --   ring reads best at (on WoW Forever too, where Talents has its own
    --   entry and the Great Vault is unavailable) even though MAX_SLOTS now
    --   seats the full set. Both are still in the picker.
    local PANELS = {
        { key = "character",   icon = ART .. "menu-character.png",
          button = "CharacterMicroButton",
          label = "CHARACTER_BUTTON",           default = "Character" },
        { key = "spellbook",   icon = ART .. "menu-spellbook.png",
          button = { "PlayerSpellsMicroButton", "SpellbookMicroButton" },
          label = { "PLAYERSPELLS_BUTTON", "TALENTS_BUTTON" },
          default = "Spellbook and Talents" },
        { key = "professions", icon = ART .. "menu-professions.png",
          button = "ProfessionMicroButton",
          label = "PROFESSIONS_BUTTON",         default = "Professions" },
        { key = "achievements", icon = ART .. "menu-achievements.png",
          button = "AchievementMicroButton",
          label = { "ACHIEVEMENT_BUTTON", "ACHIEVEMENTS" },
          default = "Achievements" },
        { key = "quests",      icon = ART .. "menu-quests.png",
          button = "QuestLogMicroButton",
          label = { "QUESTLOG_BUTTON", "QUEST_LOG" }, default = "Quest Log" },
        { key = "guild",       icon = ART .. "menu-guild.png",
          button = "GuildMicroButton",
          label = { "GUILD_AND_COMMUNITIES", "GUILD" }, default = "Guild" },
        { key = "groupfinder", icon = ART .. "menu-group.png",
          button = "LFDMicroButton",
          label = "DUNGEONS_BUTTON",            default = "Group Finder" },
        -- No micro button of its own since the Group Finder swallowed the tab:
        -- TogglePVPUI is the call the game's own binding makes, and it lives in
        -- a [Bootstrap] file, so it answers from login however late the panel
        -- itself loads.
        { key = "pvp",         icon = ART .. "menu-pvp.png",
          fire = function() if TogglePVPUI then TogglePVPUI() end end,
          exists = function() return TogglePVPUI ~= nil end,
          label = { "PLAYER_V_PLAYER", "PVP" },  default = "Player vs Player" },
        { key = "adventure",   icon = ART .. "menu-adventure.png",
          button = "EJMicroButton",
          label = { "ADVENTURE_JOURNAL", "ENCOUNTER_JOURNAL" },
          default = "Adventure Guide" },
        { key = "collections", icon = ART .. "menu-collections.png",
          button = "CollectionsMicroButton",
          label = "COLLECTIONS",                default = "Collections" },
        { key = "housing",     icon = ART .. "menu-housing.png",
          button = "HousingMicroButton",
          label = "HOUSING_MICRO_BUTTON",       default = "Housing" },
        -- The Quick Join toast, which is what the game binds TOGGLESOCIAL to
        -- now that the social micro button is gone. Same button the micro menu
        -- data bar block clicks for its Friends entry.
        { key = "social",      icon = ART .. "menu-friends.png",
          button = "QuickJoinToastButton",
          label = { "SOCIAL_LABEL", "SOCIAL_BUTTON", "FRIENDS" },
          default = "Social" },
        { key = "map",         icon = ART .. "menu-map.png",
          fire = function() if ToggleWorldMap then ToggleWorldMap() end end,
          exists = function() return ToggleWorldMap ~= nil end,
          label = { "WORLD_MAP", "WORLDMAP_BUTTON" }, default = "Map" },
        { key = "bags",        icon = ART .. "menu-bags.png",
          fire = function() if ToggleAllBags then ToggleAllBags() end end,
          exists = function() return ToggleAllBags ~= nil end,
          label = { "BAGSLOTTEXT", "INVENTORY_TOOLTIP" }, default = "Bags" },
        -- The Great Vault, which the game gives no keybind of its own at all.
        -- Blizzard's entry point only ever SHOWS it, so the toggle half is
        -- ours: a second press on an open vault closes it, which is how every
        -- other entry here answers a second press.
        { key = "greatvault",  icon = ART .. "menu-vault.png",
          fire = function()
              local f = WeeklyRewardsFrame
              if f and f:IsShown() then
                  HideUIPanel(f)
              elseif WeeklyRewards_ShowUI then
                  WeeklyRewards_ShowUI()
              end
          end,
          exists = function() return WeeklyRewards_ShowUI ~= nil end,
          label = "GREAT_VAULT_REWARDS",        default = "Great Vault" },
        -- The one panel with a micro button that cannot be clicked: its OnClick
        -- opens nothing unless the cursor is ON the button
        -- (MainMenuBarMicroButtons.lua:1844), which a macro's click never is.
        { key = "gamemenu",    icon = ART .. "menu-options.png",
          fire = function()
              if GameMenuFrame and GameMenuFrame:IsShown() then
                  HideUIPanel(GameMenuFrame)
              elseif GameMenuFrame_Show then
                  GameMenuFrame_Show()
              end
          end,
          exists = function() return GameMenuFrame_Show ~= nil end,
          label = "MAINMENU_BUTTON",            default = "Game Menu" },
        { key = "shop",        icon = ART .. "menu-shop.png", minor = true,
          button = "StoreMicroButton",
          label = "BLIZZARD_STORE",             default = "Shop" },
        { key = "help",        icon = ART .. "menu-cs.png", minor = true,
          button = "HelpMicroButton",
          label = "HELP_BUTTON",                default = "Customer Support" },
    }

    -- WoW Forever has no Great Vault content: its weekly rewards entry point
    -- still loads there but only opens an empty window, so the vault entry
    -- loses its toggle. PanelAvailable then answers no, which keeps it out of
    -- the picker and the preset and makes it fire nothing, while a saved
    -- vault slot still draws its own icon and name and goes dark under Hide
    -- Unusable Entries like any other panel the client cannot open.
    -- Forever also splits the spellbook and the talents into two micro
    -- buttons. Its combined button still exists but opens on whichever tab
    -- was last shown, so there the spellbook entry clicks the spellbook's own
    -- button and a Talents entry follows it.
    if EllesmereUI.IS_FOREVER then
        for _, def in ipairs(PANELS) do
            if def.key == "greatvault" then def.fire = nil end
        end
        for i, def in ipairs(PANELS) do
            if def.key == "spellbook" then
                def.button, def.label, def.default = "SpellbookMicroButton", "SPELLBOOK", "Spellbook"
                tinsert(PANELS, i + 1, { key = "talents",
                    icon = ART .. "menu-achievements.png",
                    button = "TalentMicroButton",
                    label = "TALENTS",                  default = "Talents" })
                break
            end
        end
    end

    local byKey = {}
    for _, def in ipairs(PANELS) do byKey[def.key] = def end

    -- The button this panel is clicked by, or nil for the ones with none and
    -- for a client that has not got the button. IsForbidden as well as
    -- existence: /click refuses a frame an addon may not reach
    -- (SlashCommands.lua:738), so an entry pointing at one would fire nothing.
    local function PanelButton(def)
        local names = def and def.button
        if not names then return nil end
        if type(names) == "string" then names = { names } end
        for _, name in ipairs(names) do
            local f = _G[name]
            if f and f.Click and f.IsForbidden and not f:IsForbidden() then
                return name
            end
        end
        return nil
    end

    ns.PanelDef = function(slot)
        return slot and byKey[slot.key]
    end

    ns.PanelName = function(def)
        if not def then return nil end
        local names = def.label
        if type(names) == "string" then names = { names } end
        for _, g in ipairs(names) do
            local s = _G[g]
            if type(s) == "string" and s ~= "" then return s end
        end
        return EllesmereUI.L(def.default)
    end

    -- The macro a panel entry fires, or nil for the ones FireInsecure takes.
    ns.PanelMacro = function(def)
        local name = PanelButton(def)
        return name and ("/click " .. name) or nil
    end

    ns.PanelFire = function(def)
        if def and def.fire and (not def.exists or def.exists()) then def.fire() end
    end

    -- Whether this client has the panel at all: Housing arrived in 12.0, the
    -- Shop is not built into every region's client, and a panel whose addon
    -- never loaded has no toggle to call. An entry that answers no goes dark
    -- under Hide Unusable Entries rather than sitting there firing nothing.
    ns.PanelAvailable = function(def)
        if not def then return false end
        if def.button then return PanelButton(def) ~= nil end
        return (def.fire ~= nil) and (not def.exists or def.exists())
    end

    -- Candidate slots for the picker and the preset, in the order the micro
    -- menu itself runs. keepOrder holds them in it: the panels are a row the
    -- player already reads left to right, and alphabetising them would be the
    -- one place in the interface they are not in that order.
    ns.PanelSlots = function(includeMinor)
        local out = {}
        for _, def in ipairs(PANELS) do
            if (includeMinor or not def.minor) and ns.PanelAvailable(def) then
                out[#out + 1] = { kind = "panel", key = def.key }
            end
        end
        return out
    end
end

I.CycleNext, I.CyclePosBack, I.CycleSteps = CycleNext, CyclePosBack, CycleSteps
I.MARKER_NAMES, I.MarkerIcon = MARKER_NAMES, MarkerIcon
I.RANDOM_FAVORITE_MOUNT, I.SpecIndexFor = RANDOM_FAVORITE_MOUNT, SpecIndexFor
I.WORLD_MARKER_ENGINE = WORLD_MARKER_ENGINE
I.broken = false
