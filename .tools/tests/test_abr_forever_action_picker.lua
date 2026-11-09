-- Stub harness: the WoW Forever Action Picker of AuraBuff Reminders. Loads the aura helpers and the
-- collectors over a stubbed internals table (as test_abr_forever_combat.lua does), the picker's spell
-- data and menu cut from the icons file, and its spellbook listener and event branch cut from the
-- lifecycle file, then drives:
--   1. the option off: nothing changes, nothing is read or listened to;
--   2. a spell group with two spells: the top rank of the first known spell, a group of one spell
--      opens no picker;
--   3. a saved pick and rank pin: a pin on the top rank, on a rank whose text has not loaded (read
--      again on the next pass) or on a rank no longer known casts the top rank;
--   4. the spell data is read once per spell;
--   5. the menu: a pick, the wheel pinning and unpinning (a rank learned later is cast), a lower
--      rank whose text has not loaded, the top end, combat;
--   6. an open menu closes once it no longer matches (profile swap, removed group, reused or hidden
--      button, option off, combat stand-down), and a second menu replaces the first's check;
--   7. the class buffs: nothing saved before a pick, the pick saved and cast, the menu refusing a
--      spell no longer known, a respec that takes the picked line away;
--   8. the spellbook listener: only while the option is on and the section can show, and the event
--      branch on both clients;
--   9. the option's key in the WoW Forever defaults and the options toggle.
--   lua .tools/tests/test_abr_forever_action_picker.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local AURAS_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Auras.lua")
local REFRESH_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Refresh.lua")
local ICONS_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Icons.lua")
local LIFECYCLE_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Lifecycle.lua")
local DEFAULTS_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Defaults.lua")
local OPTIONS_SRC = ReadSource("EllesmereUIOptions/EUI_AuraBuffReminders_Options.lua")
local MAIN_SRC = ReadSource("EllesmereUIAuraBuffReminders/EllesmereUIAuraBuffReminders.lua")

local function Cut(src, from, to, label)
    local s = src:find(from, 1, true)
    local e = s and src:find(to, s, true)
    assert(s and e, label .. " not found")
    return src:sub(s, e - 1)
end

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
local TEST = { combat = false, up = {}, subtextReads = 0 }

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetTime() return 100 end
function tContains(t, v)
    for _, x in ipairs(t) do if x == v then return true end end
    return false
end

C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        if TEST.up[id] then
            return { spellId = id, duration = 0, expirationTime = 0, sourceUnit = "player",
                isFromPlayerOrPlayerPet = true }
        end
    end,
    GetAuraDataByIndex = function() return nil end,
    GetAuraDataBySpellName = function() return nil end,
}

-- Two priest buffs with ranks, two paladin blessings and Inner Fire; the spellbook lists each
-- spell's ranks lowest first, as the game's does
local NAMES = {
    [6001] = "Power Word: Fortitude", [6002] = "Power Word: Fortitude", [6003] = "Power Word: Fortitude",
    [6004] = "Power Word: Fortitude",
    [7001] = "Divine Spirit", [7002] = "Divine Spirit",
    [19742] = "Blessing of Wisdom", [19850] = "Blessing of Wisdom",
    [19740] = "Blessing of Might", [19834] = "Blessing of Might",
    [588] = "Inner Fire",
}
local SUBTEXT = {
    [6001] = "Rank 1", [6002] = "Rank 2", [6003] = "Rank 3", [6004] = "Rank 4",
    [7001] = "Rank 1", [7002] = "Rank 2",
    [19742] = "Rank 1", [19850] = "Rank 2", [19740] = "Rank 1", [19834] = "Rank 2",
    [588] = "Rank 1",
}
local BOOK = { 588, 6001, 6002, 6003, 7001, 7002 }
local function Learn(id)
    BOOK[#BOOK + 1] = id
    table.sort(BOOK)
end
local function Forget(id)
    for i, sid in ipairs(BOOK) do
        if sid == id then table.remove(BOOK, i) return end
    end
end

Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 },
    WeaponSlot = { MainHand = 1, OffHand = 2 }, ItemEnchantType = { Imbue = 1, Temporary = 2 },
    ItemWeaponSubclass = { Axe1H = 0, Axe2H = 1, Bow = 2, Gun = 3, Mace1H = 4, Mace2H = 5, Polearm = 6,
        Sword1H = 7, Sword2H = 8, Warglaive = 9, Staff = 10, Fist = 13, Dagger = 15, Crossbow = 18, Wand = 19 } }
function GetInventoryItemID() return nil end
function UnitIsUnit(a, b) return a == b end
C_Item = {
    GetItemInfoInstant = function() return nil end,
    GetWeaponEnchantInfo = function() return {} end,
    GetItemIconByID = function(id) return 500000 + id end,
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #BOOK } end,
    GetSpellBookItemType = function(slot) return 1, nil, BOOK[slot] end,
    IsSpellKnown = function(id) return tContains(BOOK, id) end,
}
C_Spell = {
    GetSpellName = function(id) return NAMES[id] end,
    GetSpellSubtext = function(id)
        TEST.subtextReads = TEST.subtextReads + 1
        return SUBTEXT[id]
    end,
    GetSpellInfo = function(q)
        if type(q) == "string" then
            local top
            for _, sid in ipairs(BOOK) do if NAMES[sid] == q then top = sid end end
            return top and { spellID = top, name = q } or nil
        end
        return NAMES[q] and { spellID = q, name = NAMES[q] } or nil
    end,
}

-- Blizzard's menu, as far as the picker uses it: the generator fills a root description, a new
-- menu closes the open one first (its release callbacks run before the call returns), and Close
-- runs the release callbacks
local MENU = {}
local function CreateFromMixinsStub(...)
    local t = {}
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do t[k] = v end
    end
    return t
end
CreateFromMixins = CreateFromMixinsStub
MenuVariants = { GetDefaultContextMenuMixin = function() return {} end }
MenuConstants = { HorizontalGridDirection = 1 }
InputUtil = { IsGamepadUIEnabled = function() return false end, AnchorRegionToCursor = function() end }
UIParent = { GetWidth = function() return 1920 end }
GameTooltip = { IsOwned = function() return false end, SetSpellByID = function() end }
NumberFontNormalSmall = {}
MenuUtil = {
    CreateContextMenu = function(owner, generator)
        local rec = { owner = owner, style = owner.menuMixin, buttons = {}, released = {}, closed = 0 }
        local root = {}
        function root:AddMenuReleasedCallback(fn) rec.released[#rec.released + 1] = fn end
        function root:SetGridMode() end
        function root:SetMaximumWidth() end
        function root:CreateButton(_, handler, data)
            local b = { handler = handler, data = data, inits = {}, resetters = {} }
            function b:AddInitializer(fn) self.inits[#self.inits + 1] = fn end
            function b:AddResetter(fn) self.resetters[#self.resetters + 1] = fn end
            function b:SetTooltip(fn) self.tooltip = fn end
            rec.buttons[#rec.buttons + 1] = b
            return b
        end
        generator(owner, root)
        local open = MENU.open
        if open then open.menu:Close() end
        local menu = {}
        function menu:Close()
            if rec.isClosed then return end
            rec.isClosed = true
            rec.closed = rec.closed + 1
            if MENU.open == rec then MENU.open = nil end
            for _, fn in ipairs(rec.released) do fn(menu) end
        end
        function menu:GetPoint() return "TOPLEFT" end
        function menu:ClearAllPoints() end
        rec.menu = menu
        MENU.open, MENU.last = rec, rec
        return menu
    end,
}

EllesmereUIDB = {}
EllesmereUI = {
    FOREVER_BUFF_FAMILIES = { ai = { names = {}, single = {}, group = {}, ids = {},
        beneficiaries = { MAGE = true, PRIEST = true } } },
    AuraKit = { AurasRestricted = function() return false end },
    L = function(s) return s end,
    CharKey = function(sep) return "Tester" .. sep .. "Realm" end,
}

-------------------------------------------------------------------------------
--  The internals the files read (the main file and the earlier parts build it
--  in the game)
-------------------------------------------------------------------------------
local EABR = { FOREVER = true }
function EABR.SectionShows(where)
    if TEST.combat then return false end
    return not (where and where.open_world == false)
end
function EABR.FvSyncTrackingEvent() end
function EABR.FvSyncWeaponEvents() end
function EABR.FvSyncBagEvent() end
function EABR.FvSyncSleepBagWatch() end
function EABR.ApplyIconBagCount(btn, _, _, _, rank) btn.rank = rank end
function EABR.HideIconTooltip() end
EABR.FV_WEAPON_BUFFS = {}

local I = {
    EABR = EABR,
    AURA_SCAN_LIMIT = 40, ICON_SIZE = 32,
    NON_SECRET_SPELL_IDS = {}, PET_CLASSES = {}, RAID_BUFFS = {}, WARLOCK_PETS = {},
    _dismissedUntilLoad = {}, combatActiveIcons = {}, cursorActiveIcons = {},
    dbSetters = {}, panelOpenSetters = {}, iconAnchorSetters = {}, combatAnchorSetters = {},
    cursorAnchorSetters = {},
    InCombat = function() return TEST.combat end,
    InMythicPlusKey = function() return false end,
    isSecret = function() return false end,
    SpellName = function(id) return NAMES[id] end,
    Known = function(id) return C_SpellBook.IsSpellKnown(id) end,
    ShortLabel = function(s) return s end,
    Tex = function(id) return id end,
    AcquireEntry = function() return {} end,
    GetPlayerClass = function() return "PRIEST" end,
    CachedGetItemCount = function() return 0 end,
}
setmetatable(I, { __index = function(_, k)
    if k == "broken" then return nil end
    return function() end
end })

local ns = { _abrInternals = I }
assert(loadstring(AURAS_SRC, "=EUI_AuraBuffReminders_Auras.lua"))("EllesmereUIAuraBuffReminders", ns)
assert(rawget(I, "broken") == false, "the aura helpers did not load")
assert(loadstring(REFRESH_SRC, "=EUI_AuraBuffReminders_Refresh.lua"))("EllesmereUIAuraBuffReminders", ns)
assert(rawget(I, "broken") == false, "the collectors did not load")
do
    local s = MAIN_SRC:find("    function EABR.FvClassBuffs()", 1, true)
    local e = s and select(2, MAIN_SRC:find("        return t\n    end\n", s, true))
    assert(s and e, "EABR.FvClassBuffs not found in the main file")
    assert(loadstring("local EABR = ...\n" .. MAIN_SRC:sub(s, e), "=FvClassBuffs"))(EABR)
end

local db = { profile = { display = {}, forever = {
    camp = false, gather = false, gatherClassTrack = true, treasure = false, wellFed = false, mageArmor = false,
    whereToShow = {}, classBuffActions = {}, classBuffPicks = {},
    customIDs = {},
    customGroups = { { name = "Prayers", ids = { 6001, 7001 } }, { name = "Solo", ids = { 7001 } } },
} } }
for _, set in ipairs(I.dbSetters) do set(db) end
local fo = db.profile.forever
local prayers = fo.customGroups[1]

-- The picker's spell data and menu, cut from the icons file. A reload starts a fresh spell data memo
-- (and a fresh menu style); the menu reaches the data through EABR either way.
local ICONS_CUT = Cut(ICONS_SRC, "local pickerSpellData = {}",
    "\n----------------------------------------------------------------------------", "the picker's spell data and menu")
local function SetIconMacroStub(btn, macro, texture, spellID)
    btn.macro, btn.texture, btn._tooltipSpell = macro, texture, spellID
end
local ShowForeverGroupMenu
local function LoadIcons()
    ShowForeverGroupMenu = assert(loadstring("local EABR, db, InCombat, SpellName, Tex, SetIconMacro = ...\n"
        .. "local floor, max = math.floor, math.max\nlocal ShowForeverGroupMenu\nlocal iconPickerStyle\n"
        .. ICONS_CUT .. "\nreturn ShowForeverGroupMenu\n", "=Icons picker"))(
        EABR, db, I.InCombat, I.SpellName, I.Tex, SetIconMacroStub)
end
LoadIcons()

-- The spellbook listener and the event branch, cut from the lifecycle file
local mainFrame = { events = {}, regs = 0 }
function mainFrame:RegisterEvent(e) self.events[e] = true; self.regs = self.regs + 1 end
function mainFrame:UnregisterEvent(e) self.events[e] = nil end
assert(loadstring("local EABR, mainFrame = ...\n" .. Cut(LIFECYCLE_SRC,
    "    function EABR.FvSyncPickerSpellEvents(want)", "\n    function EABR.FvSyncWeaponEvents(want)",
    "EABR.FvSyncPickerSpellEvents"), "=FvSyncPickerSpellEvents"))(EABR, mainFrame)
local OnEvent = assert(loadstring("local EABR = ...\nreturn function(e, arg1)\n" .. Cut(LIFECYCLE_SRC,
    '    if e == "LEARNED_SPELL_IN_SKILL_LINE" or',
    "    -- All other events: just refresh", "the spellbook event branch") .. "\nend\n", "=OnEvent"))(EABR)

local function Collect()
    local missing = {}
    EABR.CollectForever(missing, false, false)
    return missing
end
local function Entry(list, key)
    for _, e in ipairs(list) do
        if e.dismissKey == key then return e end
    end
end
local function Button(e)
    local b = { _foreverGroup = e.foreverGroup, _tooltipSpell = e.spellID, visible = true }
    function b:IsVisible() return self.visible end
    return b
end
local function CellFrame(cell)
    local f = { scripts = {} }
    local function Region(extra)
        return setmetatable(extra or {}, { __index = function() return function() end end })
    end
    function f:AttachTexture() return Region() end
    function f:AttachFontString()
        return Region({ SetText = function(_, s) f.badge = s end })
    end
    function f:EnableMouseWheel(on) self.wheel = on end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    local desc = { GetData = function() return cell.data end }
    for _, fn in ipairs(cell.inits) do fn(f, desc) end
    return f
end
local function Wheel(f, delta) f.scripts.OnMouseWheel(f, delta) end
local function Pick(rec, spellID)
    for _, b in ipairs(rec.buttons) do
        if b.data == spellID then return b.handler(b.data) end
    end
    error("no cell for " .. spellID)
end

-------------------------------------------------------------------------------
--  1. the option off: a spell group casts its first known spell by name, as
--     before; no rank text is read and nothing listens to the spellbook
-------------------------------------------------------------------------------
local missing = Collect()
local e = Entry(missing, "forever:g1")
assert(e and e.mode == "macro" and e.macro == "/cast [@player] Power Word: Fortitude" and not e.foreverGroup,
    "the option off changed a spell group's click: " .. tostring(e and e.macro))
e = Entry(missing, "forever:class_innerfire")
assert(e and e.mode == "spell" and e.spellID == 588, "the option off changed a class buff's click")
assert(TEST.subtextReads == 0, "the option off read rank text")
assert(mainFrame.regs == 0 and not mainFrame.events.SPELLS_CHANGED, "the option off listened to the spellbook")

-------------------------------------------------------------------------------
--  2. the option on: the first known spell's top rank, by rank; a group of one
--     spell casts its top rank with no picker
-------------------------------------------------------------------------------
fo.pickerEnabled = true
missing = Collect()
e = Entry(missing, "forever:g1")
assert(e.mode == "macro" and e.macro == "/cast [@player,nocombat] Power Word: Fortitude(Rank 3)"
    and e.spellID == 6003 and e.spellRank == "3" and e.foreverGroup == prayers,
    "a group of two spells: " .. tostring(e.macro))
local solo = Entry(missing, "forever:g2")
assert(solo.macro == "/cast [@player,nocombat] Divine Spirit(Rank 2)" and solo.foreverGroup == nil,
    "a group of one spell opened a picker or lost its rank")
assert(mainFrame.events.SPELLS_CHANGED, "the option on did not listen to the spellbook")

-------------------------------------------------------------------------------
--  3. a saved pick and pin
-------------------------------------------------------------------------------
prayers.castSpellID = 7001
e = Entry(Collect(), "forever:g1")
assert(e.spellID == 7002 and e.texture == 7002 and e.macro == "/cast [@player,nocombat] Divine Spirit(Rank 2)",
    "the picked spell is not cast: " .. tostring(e.macro))
prayers.castSpellID = nil
prayers.castRanks = { [6001] = 6002 }
e = Entry(Collect(), "forever:g1")
assert(e.spellID == 6002 and e.macro == "/cast [@player,nocombat] Power Word: Fortitude(Rank 2)",
    "a pinned rank is not cast: " .. tostring(e.macro))
-- a pin on the top rank casts the top rank
prayers.castRanks[6001] = 6003
assert(Entry(Collect(), "forever:g1").spellID == 6003, "a pin on the top rank")
-- a pin whose rank text has not loaded casts the top rank, and is read again on the next pass
SUBTEXT[6002] = nil
LoadIcons()
prayers.castRanks[6001] = 6002
e = Entry(Collect(), "forever:g1")
assert(e.spellID == 6003 and e.macro:find("(Rank 3)", 1, true),
    "a pin with no rank text cast a rankless macro: " .. tostring(e.macro))
SUBTEXT[6002] = "Rank 2"
assert(Entry(Collect(), "forever:g1").spellID == 6002, "a pin's rank text was not read again once loaded")
-- a pin on a rank no longer known casts the top rank
Forget(6002)
EABR._fvFamDirty = true
assert(Entry(Collect(), "forever:g1").spellID == 6003, "a pin on a forgotten rank")
Learn(6002)
EABR._fvFamDirty = true
prayers.castRanks = nil

-------------------------------------------------------------------------------
--  4. the spell data: read once per spell, then served from memory
-------------------------------------------------------------------------------
Collect()
TEST.subtextReads = 0
Collect()
assert(TEST.subtextReads == 0, "a pass with nothing changed read rank text " .. TEST.subtextReads .. " times")
-- spell data read before its rank text loaded is not kept: once the text is in, any request reads it
SUBTEXT[7002] = nil
LoadIcons()
local macro, rank = EABR.ForeverPickerSpellData(7002, true)
assert(rank == nil and macro == "/cast [@player,nocombat] Divine Spirit", "spell data with no rank text")
SUBTEXT[7002] = "Rank 2"
macro, rank = EABR.ForeverPickerSpellData(7002, false)
assert(rank == "2" and macro == "/cast [@player,nocombat] Divine Spirit(Rank 2)",
    "spell data read with no rank text was kept: " .. tostring(macro))

-------------------------------------------------------------------------------
--  5. the menu on the spell group
-------------------------------------------------------------------------------
e = Entry(Collect(), "forever:g1")
local btn = Button(e)
ShowForeverGroupMenu(btn)
local rec = MENU.last
assert(rec and #rec.buttons == 2 and rec.buttons[1].data == 6001 and rec.buttons[2].data == 7001,
    "the menu's cells")
assert(rec.style and btn.menuMixin == nil, "the menu style was not used or not taken off the button")
assert(EABR.ValidateOpenPicker, "the open menu has no check")
local fort = CellFrame(rec.buttons[1])
local spirit = CellFrame(rec.buttons[2])
assert(fort.badge == "3" and fort.wheel and spirit.badge == "2", "the cells' rank badges")
-- a pick casts that spell's top rank and is saved on the group
Pick(rec, 7001)
assert(prayers.castSpellID == 7001 and btn._tooltipSpell == 7002 and btn.rank == "2"
    and btn.macro == "/cast [@player,nocombat] Divine Spirit(Rank 2)", "a pick in the menu")
-- the wheel on a spell that is not the picked one pins its rank and leaves the click alone
Wheel(fort, -1)
assert(prayers.castRanks and prayers.castRanks[6001] == 6002 and fort.badge == "2", "the wheel did not pin")
assert(btn._tooltipSpell == 7002, "the wheel on another spell changed the click")
-- back to the top rank: no pin is left, and no empty table
Wheel(fort, 1)
assert(prayers.castRanks == nil and fort.badge == "3", "the top rank left a pin or an empty table")
-- past the top: nothing
Wheel(fort, 1)
assert(prayers.castRanks == nil, "the wheel past the top rank")
-- on the picked spell the wheel changes the click too; back at the top, a rank learned later is cast
Pick(rec, 6001)
Wheel(fort, -1)
assert(btn._tooltipSpell == 6002 and btn.macro:find("(Rank 2)", 1, true), "the wheel on the picked spell")
Wheel(fort, 1)
assert(btn._tooltipSpell == 6003 and prayers.castRanks == nil, "the wheel back to the top on the picked spell")
Learn(6004)
EABR._fvFamDirty = true
e = Entry(Collect(), "forever:g1")
assert(e.spellID == 6004 and e.macro:find("(Rank 4)", 1, true),
    "a rank learned after scrolling back to the top is not cast: " .. tostring(e.spellID))
-- a lower rank whose text has not loaded is not pinned
btn = Button(e)
ShowForeverGroupMenu(btn)
rec = MENU.last
fort = CellFrame(rec.buttons[1])
SUBTEXT[6003] = nil
LoadIcons()
Wheel(fort, -1)
assert(prayers.castRanks == nil, "a rank with no rank text was pinned")
SUBTEXT[6003] = "Rank 3"
-- combat: no pick, no pin
TEST.combat = true
Pick(rec, 7001)
Wheel(fort, -1)
assert(prayers.castSpellID == 6001 and prayers.castRanks == nil, "the menu changed something in combat")
TEST.combat = false

-------------------------------------------------------------------------------
--  6. an open menu closes once it no longer matches
-------------------------------------------------------------------------------
local function Reopen()
    e = Entry(Collect(), "forever:g1")
    btn = Button(e)
    ShowForeverGroupMenu(btn)
    rec = MENU.last
    assert(EABR.ValidateOpenPicker and not rec.isClosed, "the menu did not open")
end
local function Closes(label)
    EABR.ValidateOpenPicker()
    assert(rec.closed == 1, label .. ": the menu stayed open")
    assert(EABR.ValidateOpenPicker == nil, label .. ": the check outlived the menu")
end
-- still current: it stays open
Reopen()
EABR.ValidateOpenPicker()
assert(rec.closed == 0, "a current menu was closed")
-- a profile swap
local profile = db.profile
db.profile = { display = {}, forever = profile.forever }
Closes("a profile swap")
db.profile = profile
-- the group removed
Reopen()
table.remove(fo.customGroups, 1)
Closes("a removed group")
table.insert(fo.customGroups, 1, prayers)
-- the button now shows another reminder, or is hidden
Reopen()
btn._foreverGroup = {}
Closes("a reused button")
Reopen()
btn.visible = false
Closes("a hidden button")
-- the option turned off: no pick, then closed
Reopen()
fo.pickerEnabled = false
Pick(rec, 7001)
assert(prayers.castSpellID == 6001, "a pick with the option off")
Closes("the option off")
fo.pickerEnabled = true
-- a second menu closes the first, whose release leaves the new menu's check in place
Reopen()
local first = rec
Reopen()
assert(first.closed == 1 and rec.closed == 0 and EABR.ValidateOpenPicker, "a second menu")
EABR.ValidateOpenPicker()
assert(rec.closed == 0, "the second menu was closed while current")
-- the stand-down at combat start closes it and stops listening
TEST.combat = true
EABR.FvStandDown()
assert(rec.closed == 1 and EABR.ValidateOpenPicker == nil, "the stand-down left the menu open")
assert(not mainFrame.events.SPELLS_CHANGED, "the stand-down kept listening to the spellbook")
TEST.combat = false

-------------------------------------------------------------------------------
--  7. the class buffs (a paladin's blessings)
-------------------------------------------------------------------------------
local function Blessing()
    local entries = {}
    EABR.CollectClassBuffs(entries, fo, false, {}, "PALADIN")
    return Entry(entries, "forever:class_blessing")
end
for _, id in ipairs({ 19742, 19850, 19740, 19834 }) do Learn(id) end
fo.pickerEnabled = false
e = Blessing()
assert(e.mode == "spell" and e.spellID == 19834 and not e.foreverGroup, "the option off changed the blessing")
fo.pickerEnabled = true
e = Blessing()
assert(e.mode == "macro" and e.macro == "/cast [@player,nocombat] Blessing of Might(Rank 2)" and e.foreverGroup,
    "the blessing with the option on: " .. tostring(e.macro))
assert(fo.classBuffActions.blessing == nil, "the blessing saved settings before a pick")
btn = Button(e)
ShowForeverGroupMenu(btn)
rec = MENU.last
assert(#rec.buttons == 2 and rec.buttons[1].data == 19742 and rec.buttons[2].data == 19740, "the blessing's cells")
assert(fo.classBuffActions.blessing == nil, "opening the menu saved settings")
Pick(rec, 19742)
assert(fo.classBuffActions.blessing and fo.classBuffActions.blessing.castSpellID == 19742
    and btn.macro == "/cast [@player,nocombat] Blessing of Wisdom(Rank 2)", "the blessing pick")
e = Blessing()
assert(e.spellID == 19850, "the picked blessing is not cast: " .. tostring(e.spellID))
-- the menu refuses a spell the character no longer knows: a pick on it, and a menu opened on the
-- old choices offers only what is still known (here one spell, so no menu)
btn = Button(e)
ShowForeverGroupMenu(btn)
rec = MENU.last
Forget(19834)
Forget(19740)
Pick(rec, 19740)
assert(fo.classBuffActions.blessing.castSpellID == 19742, "the menu picked a blessing no longer known")
ShowForeverGroupMenu(btn)
assert(MENU.last == rec, "a menu opened offering a blessing no longer known")
Learn(19740)
Learn(19834)
-- a respec takes the picked line away: the next pass casts the line still known, with no picker
Forget(19742)
Forget(19850)
e = Blessing()
assert(e.spellID == 19834 and e.foreverGroup == nil,
    "after a respec the blessing cast a spell no longer known: " .. tostring(e.spellID))
-- learned again: the spellbook event drops the class choices, and the pick is back
Learn(19742)
Learn(19850)
OnEvent("SPELLS_CHANGED")
e = Blessing()
assert(e.spellID == 19850 and e.foreverGroup, "the picked blessing did not come back once learned again")
for _, id in ipairs({ 19742, 19850, 19740, 19834 }) do Forget(id) end
fo.classBuffActions.blessing = nil

-------------------------------------------------------------------------------
--  8. the spellbook listener and the event branch
-------------------------------------------------------------------------------
Collect()
local regs = mainFrame.regs
assert(mainFrame.events.SPELLS_CHANGED and EABR._fvPickerSpellEvents, "out of combat the listener is off")
Collect()
assert(mainFrame.regs == regs, "a second pass registered the listener again")
TEST.combat = true
Collect()
assert(not mainFrame.events.SPELLS_CHANGED, "the listener stayed on while the section cannot show")
TEST.combat = false
Collect()
assert(mainFrame.events.SPELLS_CHANGED, "the listener did not come back after combat")
fo.pickerEnabled = false
Collect()
assert(not mainFrame.events.SPELLS_CHANGED, "the listener stayed on with the option off")
fo.pickerEnabled = true
-- turned on, it marks the families and class choices, since nothing was heard while it was off
EABR._fvFamDirty, EABR._fvClassPickerGroups = false, {}
EABR.FvSyncPickerSpellEvents(true)
assert(EABR._fvFamDirty and EABR._fvClassPickerGroups == nil, "turning the listener on marked nothing")
-- the event: on WoW Forever a spellbook change rebuilds the families and class choices but leaves the
-- trackers; a learned spell does both; on retail the spellbook change is not this branch's
EABR._fvFamDirty, EABR._fvClassPickerGroups, EABR._fvTrackDirty = false, {}, false
OnEvent("SPELLS_CHANGED")
assert(EABR._fvFamDirty and EABR._fvClassPickerGroups == nil and EABR._fvTrackDirty == false,
    "SPELLS_CHANGED on WoW Forever")
EABR._fvFamDirty, EABR._fvClassPickerGroups = false, {}
OnEvent("LEARNED_SPELL_IN_SKILL_LINE")
assert(EABR._fvFamDirty and EABR._fvClassPickerGroups == nil and EABR._fvTrackDirty == true,
    "LEARNED_SPELL_IN_SKILL_LINE")
EABR.FOREVER = false
EABR._fvFamDirty, EABR._fvClassPickerGroups = false, {}
OnEvent("SPELLS_CHANGED")
assert(EABR._fvFamDirty == false and EABR._fvClassPickerGroups, "SPELLS_CHANGED reached the branch on retail")
EABR.FOREVER = true

-------------------------------------------------------------------------------
--  9. the option's key: WoW Forever's defaults only, read and written there
-------------------------------------------------------------------------------
local display = DEFAULTS_SRC:match("\n        display = (%b{})")
local forever = DEFAULTS_SRC:match("defaults%.profile%.forever = (%b{})")
assert(display and not display:find("pickerEnabled", 1, true), "the option's key is in the shared display defaults")
assert(forever and forever:find("pickerEnabled = false,", 1, true), "the option's key is not in the WoW Forever defaults")
local toggle = OPTIONS_SRC:match('{ type="toggle", text="Action Picker",.-RefreshAll%(%)')
assert(toggle and toggle:find("FDB()", 1, true) and not toggle:find("DDB()", 1, true),
    "the options toggle does not use the WoW Forever settings")

print("aurabuff reminders forever action picker harness: ok")
